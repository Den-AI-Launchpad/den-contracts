// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAgentFactory {
    function submitProposal(string memory name, string memory symbol, string memory tokenURI)
        external
        returns (uint256);

    function cancelProposal(uint256 id) external;

    function deployedAgentCount() external view returns (uint256);

    function initFromCurve(string memory name, string memory symbol, address creator, uint256 proposalRequirement_)
        external
        returns (uint256);

    function executeCurveProposal(uint256 id, uint256 totalSupply, uint256 lpSupply, address vault)
        external
        returns (address);
}
