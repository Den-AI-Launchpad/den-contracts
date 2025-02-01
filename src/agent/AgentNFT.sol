// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "./IAgentNFT.sol";

contract AgentNFT is
    Initializable,
    IAgentNFT,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable
{
    uint256 private _nextId;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(uint256 => AgentInfo) public agentInfos;

    error Unauthorized();

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        __ERC721_init("Den Agent", "DEN AGENT");
        __ERC721URIStorage_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _nextId = 1;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function nextAgentId() public view returns (uint256) {
        return _nextId;
    }

    function totalSupply() public view returns (uint256) {
        return _nextId - 1;
    }

    function mint(address to, address agentToken_, address lp_) external onlyRole(MINTER_ROLE) returns (uint256) {
        uint256 idToMint = _nextId;
        _mint(to, idToMint);
        _nextId++;

        agentInfos[idToMint] = AgentInfo({creator: to, agentToken: agentToken_, lp: lp_});

        return idToMint;
    }

    function getAgentInfo(uint256 tokenId) external view returns (AgentInfo memory) {
        return agentInfos[tokenId];
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function setTokenURI(uint256 id, string memory newTokenURI) public {
        if (agentInfos[id].creator != msg.sender) revert Unauthorized();
        _setTokenURI(id, newTokenURI);
    }
}
