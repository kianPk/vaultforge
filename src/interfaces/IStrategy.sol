// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal yield strategy interface used by VaultForge.
interface IStrategy {
    function asset() external view returns (address);
    function vault() external view returns (address);
    function totalAssets() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256 withdrawn);
    function harvest() external returns (uint256 profit);
}
