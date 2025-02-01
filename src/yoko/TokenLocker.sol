// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract TokenLocker {
    using SafeERC20 for IERC20;

    struct LockInfo {
        address token;
        address user;
        uint256 amount;
        uint256 unlockAt;
        bool withdrawn;
    }

    uint256 public nextId;

    mapping(uint256 => LockInfo) public idToLockInfo;

    event NewLock(address indexed token, address user, uint256 indexed amount, uint256 indexed unlockAt);
    event TokenUnlocked(address indexed token, uint256 indexed amount);

    error ZeroAddressUnallowed();
    error InvalidAmount();
    error InvalidUnlockTime();
    error Unauthorized();
    error UnlockTimeNotReached();
    error LockDoesNotExist();
    error AlreadyWithdrawn();

    constructor() {
        nextId = 1;
    }

    function lockToken(address token_, uint256 amount_, uint256 unlockAt_) external {
        if (token_ == address(0)) revert ZeroAddressUnallowed();
        if (amount_ == 0) revert InvalidAmount();
        if (unlockAt_ < block.timestamp) revert InvalidUnlockTime();

        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);

        idToLockInfo[nextId] = LockInfo(token_, msg.sender, amount_, unlockAt_, false);

        nextId++;

        emit NewLock(token_, msg.sender, amount_, unlockAt_);
    }

    function unlockToken(uint256 id) external {
        LockInfo storage lockInfo = idToLockInfo[id];
        if (lockInfo.token == address(0)) revert LockDoesNotExist();
        if (msg.sender != lockInfo.user) revert Unauthorized();
        if (block.timestamp < lockInfo.unlockAt) revert UnlockTimeNotReached();
        if (lockInfo.withdrawn) revert AlreadyWithdrawn();

        lockInfo.withdrawn = true;

        IERC20(lockInfo.token).safeTransfer(msg.sender, lockInfo.amount);

        emit TokenUnlocked(lockInfo.token, lockInfo.amount);
    }

    function getLockInfo(uint256 id) public view returns (LockInfo memory) {
        LockInfo memory lockInfo = idToLockInfo[id];
        if (lockInfo.token == address(0)) revert LockDoesNotExist();
        return lockInfo;
    }
}
