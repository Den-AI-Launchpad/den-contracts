// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./IAgentVeToken.sol";
import "./IAgentNFT.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract AgentVeToken is IAgentVeToken, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    address public creator;
    address public stakedToken;
    address public agentNft;
    uint256 public unlockAt; // The timestamp when the agent creator can withdraw the tokens
    bool public canStake; // To control private/public agent mode
    uint256 public initialLock;

    error Unauthorized();
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientAllowance();

    event Stake(address account, uint256 amount);
    event Withdraw(address account, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    bool internal locked;

    modifier noReentrant() {
        require(!locked, "cannot reenter");
        locked = true;
        _;
        locked = false;
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _creator,
        address _stakedToken,
        uint256 _unlockAt,
        address _agentNft,
        bool _canStake
    ) external initializer {
        __ERC20_init(_name, _symbol);

        creator = _creator;
        unlockAt = _unlockAt;
        stakedToken = _stakedToken;
        agentNft = _agentNft;
        canStake = _canStake;
    }

    // Stakers have to stake their tokens
    function stake(uint256 amount, address receiver) public {
        if (!canStake || totalSupply() != 0) revert Unauthorized();

        address sender = _msgSender();
        if (amount == 0) revert InvalidAmount();
        if (IERC20(stakedToken).balanceOf(sender) < amount) revert InsufficientBalance();
        if (IERC20(stakedToken).allowance(sender, address(this)) < amount) revert InsufficientAllowance();

        if (totalSupply() == 0) {
            initialLock = amount;
        }

        IERC20(stakedToken).safeTransferFrom(sender, address(this), amount);

        _mint(receiver, amount);

        emit Stake(receiver, amount);
    }

    function setCanStake(bool _canStake) public {
        if (_msgSender() != creator) revert Unauthorized();
        canStake = _canStake;
    }

    function setUnlockTime(uint256 _unlockAt) public {
        bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");
        require(IAccessControl(agentNft).hasRole(ADMIN_ROLE, _msgSender()), "Not admin");
        unlockAt = _unlockAt;
    }

    function withdraw(uint256 amount) public noReentrant {
        address sender = _msgSender();
        require(balanceOf(sender) >= amount, "Insufficient balance");
        if (balanceOf(sender) < amount) revert InsufficientBalance();

        if ((sender == creator) && ((balanceOf(sender) - amount) < initialLock)) {
            if (block.timestamp < unlockAt) revert Unauthorized();
        }

        _burn(sender, amount);

        IERC20(stakedToken).safeTransfer(sender, amount);

        emit Withdraw(sender, amount);
    }

    // This is non-transferable token
    function transfer(address, /*to*/ uint256 /*value*/ ) public override returns (bool) {
        revert("Transfer not supported");
    }

    function transferFrom(address, /*from*/ address, /*to*/ uint256 /*value*/ ) public override returns (bool) {
        revert("Transfer not supported");
    }

    function approve(address, /*spender*/ uint256 /*value*/ ) public override returns (bool) {
        revert("Approve not supported");
    }
}
