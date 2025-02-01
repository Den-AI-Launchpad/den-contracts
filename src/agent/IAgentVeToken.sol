// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAgentVeToken {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _creator,
        address _stakedToken,
        uint256 _unlockAt,
        address _agentNft,
        bool _canStake
    ) external;

    function stake(uint256 amount, address receiver) external;

    function withdraw(uint256 amount) external;
}
