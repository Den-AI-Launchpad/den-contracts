// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import "./BPair.sol";

contract BFactory is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    mapping(address => mapping(address => address)) private _pair;

    address[] public pairs;

    address public router;

    address public taxVault;
    uint256 public buyTax;
    uint256 public sellTax;

    event PairCreated(address indexed tokenA, address indexed tokenB, address pair, uint256);

    error ZeroAddressUnallowed();
    error InvalidAmount();
    error RouterDoesNotExist();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address taxVault_, address router_, uint256 buyTax_, uint256 sellTax_) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        taxVault = taxVault_;
        router = router_;
        buyTax = buyTax_;
        sellTax = sellTax_;
    }

    function _createPair(address tokenA, address tokenB) internal returns (address) {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddressUnallowed();
        if (router == address(0)) revert RouterDoesNotExist();

        BPair pair_ = new BPair(router, tokenA, tokenB);

        _pair[tokenA][tokenB] = address(pair_);
        _pair[tokenB][tokenA] = address(pair_);

        pairs.push(address(pair_));

        uint256 n = pairs.length;

        emit PairCreated(tokenA, tokenB, address(pair_), n);

        return address(pair_);
    }

    function createPair(address tokenA, address tokenB)
        external
        onlyRole(CREATOR_ROLE)
        nonReentrant
        returns (address)
    {
        address pair = _createPair(tokenA, tokenB);

        return pair;
    }

    function getPair(address tokenA, address tokenB) public view returns (address) {
        return _pair[tokenA][tokenB];
    }

    function allPairsLength() public view returns (uint256) {
        return pairs.length;
    }

    function setTaxVault(address newVault) public onlyRole(ADMIN_ROLE) {
        if (newVault == address(0)) revert ZeroAddressUnallowed();
        taxVault = newVault;
    }

    function setSellTax(uint256 newSellTax) public onlyRole(ADMIN_ROLE) {
        if (newSellTax == 0) revert InvalidAmount();
        sellTax = newSellTax;
    }

    function setBuyTax(uint256 newBuyTax) public onlyRole(ADMIN_ROLE) {
        if (newBuyTax == 0) revert InvalidAmount();
        buyTax = newBuyTax;
    }

    function setRouter(address router_) public onlyRole(ADMIN_ROLE) {
        router = router_;
    }
}
