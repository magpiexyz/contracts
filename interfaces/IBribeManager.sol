// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBribeManager {
    function userTotalVote(address user) external view returns (uint256);

    function getUserMaxVote(address _user) external view returns (uint256 maxVote);
}