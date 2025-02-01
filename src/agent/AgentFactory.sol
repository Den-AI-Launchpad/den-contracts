// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

import "openzeppelin-contracts/contracts/proxy/Clones.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import "./IAgentFactory.sol";
import "./IAgentToken.sol";
import "./IAgentVeToken.sol";
import "./IAgentNFT.sol";

contract AgentFactory is IAgentFactory, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 private _nextId;

    address public agentTokenImpl;
    address public veTokenImpl;
    address public agentNFT;
    uint256 public proposalRequirement;
    uint256 public stakingPeriod;

    address public baseToken;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant BONDING_ROLE = keccak256("BONDING_ROLE");

    event AgentDeployed(uint256 id, address token, address lp);
    event ProposalSubmitted(uint256 id);

    enum ProposalStatus {
        Active,
        Executed,
        Withdrawn
    }

    struct Proposal {
        string name;
        string symbol;
        string tokenURI;
        ProposalStatus status;
        uint256 withdrawableAmount;
        address proposer;
        uint256 agentId;
    }

    mapping(uint256 => Proposal) private _proposals;

    event ProposalRequirementUpdated(uint256 newRequirement);
    event StakingPeriodUpdated(uint256 newPeriod);
    event AgentImplementationUpdated(address implementation);

    error ZeroAddressUnallowed();
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientAllowance();
    error Unauthorized();
    error ProposalInactive();
    error TokenAdminNotSet();

    bool internal locked;

    modifier noReentrant() {
        require(!locked, "cannot reenter");
        locked = true;
        _;
        locked = false;
    }

    address[] public deployedAgentTokens;
    address[] public deployedVeTokens;
    address private _uniswapRouter;
    address private _tokenAdmin;

    bytes private _tokenSupplyParams;
    bytes private _tokenTaxParams;

    function initialize(
        address agentTokenImpl_,
        address veTokenImpl_,
        address baseToken_,
        address agentNFT_,
        uint256 proposalRequirement_,
        uint256 nextId_
    ) public initializer {
        __Pausable_init();

        if (agentTokenImpl_ == address(0) || baseToken_ == address(0) || agentNFT_ == address(0)) {
            revert ZeroAddressUnallowed();
        }

        agentTokenImpl = agentTokenImpl_;
        veTokenImpl = veTokenImpl_;
        baseToken = baseToken_;
        agentNFT = agentNFT_;
        proposalRequirement = proposalRequirement_;
        _nextId = nextId_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getProposal(uint256 proposalId) public view returns (Proposal memory) {
        return _proposals[proposalId];
    }

    function submitProposal(string memory name, string memory symbol, string memory tokenURI)
        public
        whenNotPaused
        returns (uint256)
    {
        address sender = _msgSender();
        if (IERC20(baseToken).balanceOf(sender) < proposalRequirement) revert InsufficientBalance();
        if (IERC20(baseToken).allowance(sender, address(this)) < proposalRequirement) revert InsufficientAllowance();

        IERC20(baseToken).safeTransferFrom(sender, address(this), proposalRequirement);

        uint256 id = _nextId++;
        Proposal memory proposal =
            Proposal(name, symbol, tokenURI, ProposalStatus.Active, proposalRequirement, sender, 0);
        _proposals[id] = proposal;
        emit ProposalSubmitted(id);

        return id;
    }

    function cancelProposal(uint256 id) public noReentrant {
        Proposal storage proposal = _proposals[id];

        if (msg.sender != proposal.proposer || hasRole(EXECUTOR_ROLE, msg.sender)) revert Unauthorized();

        if (proposal.status != ProposalStatus.Active) revert ProposalInactive();

        uint256 withdrawableAmount = proposal.withdrawableAmount;

        proposal.withdrawableAmount = 0;
        proposal.status = ProposalStatus.Withdrawn;

        IERC20(baseToken).safeTransfer(proposal.proposer, withdrawableAmount);
    }

    function _executeApplication(uint256 id, bytes memory tokenSupplyParams_, bool canStake) internal {
        if (_proposals[id].status != ProposalStatus.Active) revert ProposalInactive();

        if (_tokenAdmin == address(0)) revert TokenAdminNotSet();

        Proposal storage proposal = _proposals[id];

        uint256 initialAmount = proposal.withdrawableAmount;
        proposal.withdrawableAmount = 0;
        proposal.status = ProposalStatus.Executed;

        address token = _deployNewAgentToken(proposal.name, proposal.symbol, tokenSupplyParams_);

        address lp = IAgentToken(token).liquidityPools()[0];
        IERC20(baseToken).safeTransfer(token, initialAmount);
        IAgentToken(token).setupInitialLiquidity(address(this));

        uint256 _agentId = IAgentNFT(agentNFT).nextAgentId();
        IAgentNFT(agentNFT).mint(proposal.proposer, token, lp);
        proposal.agentId = _agentId;

        address veToken = _deployNewVeToken(
            string.concat("Staked ", proposal.name),
            string.concat("s", proposal.symbol),
            lp,
            proposal.proposer,
            canStake
        );

        IERC20(lp).approve(veToken, type(uint256).max);
        IAgentVeToken(veToken).stake(IERC20(lp).balanceOf(address(this)), proposal.proposer);

        emit AgentDeployed(_agentId, token, lp);
    }

    function executeProposal(uint256 id, bool canStake) public noReentrant {
        Proposal storage proposal = _proposals[id];

        if (msg.sender != proposal.proposer || hasRole(EXECUTOR_ROLE, msg.sender)) revert Unauthorized();

        _executeApplication(id, _tokenSupplyParams, canStake);
    }

    function _deployNewAgentToken(string memory name, string memory symbol, bytes memory tokenSupplyParams_)
        internal
        returns (address instance)
    {
        instance = Clones.clone(agentTokenImpl);
        IAgentToken(instance).initialize(
            [_tokenAdmin, _uniswapRouter, baseToken], abi.encode(name, symbol), tokenSupplyParams_, _tokenTaxParams
        );

        deployedAgentTokens.push(instance);
        return instance;
    }

    function _deployNewVeToken(
        string memory name,
        string memory symbol,
        address stakingAsset,
        address founder,
        bool canStake
    ) internal returns (address instance) {
        instance = Clones.clone(veTokenImpl);
        IAgentVeToken(instance).initialize(
            name, symbol, founder, stakingAsset, block.timestamp + stakingPeriod, address(agentNFT), canStake
        );

        deployedVeTokens.push(instance);
        return instance;
    }

    function deployedAgentCount() public view returns (uint256) {
        return deployedAgentTokens.length;
    }

    function setProposalRequirement(uint256 newRequirement) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRequirement == 0) revert InvalidAmount();
        proposalRequirement = newRequirement;
        emit ProposalRequirementUpdated(newRequirement);
    }

    function setStakingPeriod(uint256 newPeriod) public onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPeriod = newPeriod;
        emit StakingPeriodUpdated(newPeriod);
    }

    function setImplementation(address implementation) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (implementation == address(0)) revert ZeroAddressUnallowed();
        agentTokenImpl = implementation;
        emit AgentImplementationUpdated(implementation);
    }

    function setUniswapRouter(address router) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (router == address(0)) revert ZeroAddressUnallowed();
        _uniswapRouter = router;
    }

    function setTokenAdmin(address newTokenAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTokenAdmin == address(0)) revert ZeroAddressUnallowed();
        _tokenAdmin = newTokenAdmin;
    }

    function setTokenSupplyParams(uint256 maxSupply, uint256 lpSupply, uint256 vaultSupply, address vault)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _tokenSupplyParams = abi.encode(maxSupply, lpSupply, vaultSupply, vault);
    }

    function setTokenTaxParams(
        uint256 projectBuyTaxBasisPoints,
        uint256 projectSellTaxBasisPoints,
        uint256 taxSwapThresholdBasisPoints,
        address projectTaxRecipient
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _tokenTaxParams = abi.encode(
            projectBuyTaxBasisPoints, projectSellTaxBasisPoints, taxSwapThresholdBasisPoints, projectTaxRecipient
        );
    }

    function setBaseToken(address newToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newToken == address(0)) revert ZeroAddressUnallowed();
        baseToken = newToken;
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function initFromCurve(string memory name, string memory symbol, address creator, uint256 proposalRequirement_)
        public
        whenNotPaused
        onlyRole(BONDING_ROLE)
        returns (uint256)
    {
        address sender = _msgSender();
        require(IERC20(baseToken).balanceOf(sender) >= proposalRequirement_, "Insufficient base token");
        require(
            IERC20(baseToken).allowance(sender, address(this)) >= proposalRequirement_,
            "Insufficient base token allowance"
        );

        IERC20(baseToken).safeTransferFrom(sender, address(this), proposalRequirement_);

        uint256 id = _nextId++;
        Proposal memory proposal = Proposal(name, symbol, "", ProposalStatus.Active, proposalRequirement_, creator, id);
        _proposals[id] = proposal;
        emit ProposalSubmitted(id);

        return id;
    }

    function executeCurveProposal(uint256 id, uint256 totalSupply, uint256 lpSupply, address vault)
        public
        onlyRole(BONDING_ROLE)
        noReentrant
        returns (address)
    {
        bytes memory tokenSupplyParams = abi.encode(totalSupply, lpSupply, totalSupply - lpSupply, vault);

        _executeApplication(id, tokenSupplyParams, true);

        Proposal memory proposal = _proposals[id];

        return IAgentNFT(agentNFT).getAgentInfo(proposal.agentId).agentToken;
    }
}
