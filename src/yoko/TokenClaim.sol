// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract TokenClaim is Ownable {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public addressToAllocation;

    mapping(address => bool) public hasClaimed;

    address public token;

    event Claimed(address indexed account, uint256 indexed amount);

    event AllocationSet(address indexed account, uint256 indexed amount);

    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "can't be zero address");
        token = token_;
    }

    function setAllocations(address[] calldata accounts, uint256[] calldata amounts) public onlyOwner {
        require(accounts.length == amounts.length, "array length mismatch");

        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "can't be zero address");
            require(amounts[i] > 0, "can't be zero");

            addressToAllocation[accounts[i]] = amounts[i];

            emit AllocationSet(accounts[i], amounts[i]);
        }
    }

    function claim() external {
        require(!hasClaimed[msg.sender], "already claimed");
        uint256 allocation = addressToAllocation[msg.sender];
        require(allocation > 0, "can't be zero");

        IERC20(token).safeTransfer(msg.sender, allocation);
        hasClaimed[msg.sender] = true;

        emit Claimed(msg.sender, allocation);
    }

    function recoverERC20(address token_, uint256 amount) public onlyOwner {
        IERC20(token_).safeTransfer(msg.sender, amount);
    }
}
