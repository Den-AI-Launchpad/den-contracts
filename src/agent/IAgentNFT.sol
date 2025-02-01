// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAgentNFT {
    struct AgentInfo {
        address agentToken;
        address lp;
        address creator;
    }

    function nextAgentId() external view returns (uint256);

    function mint(address to, address agentToken, address lp_) external returns (uint256);

    function getAgentInfo(uint256 tokenId) external view returns (AgentInfo memory);
}
