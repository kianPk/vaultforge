// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

/// @dev Demo strategy that accrues a fixed bps yield on harvest (test / lab only).
contract MockYieldStrategy is IStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    address public immutable vaultAddr;
    uint256 public stored;
    uint256 public yieldBps; // e.g. 50 = 0.50% per harvest

    error OnlyVault();

    modifier onlyVault() {
        if (msg.sender != vaultAddr) revert OnlyVault();
        _;
    }

    constructor(address asset_, address vault_, uint256 yieldBps_) {
        assetToken = IERC20(asset_);
        vaultAddr = vault_;
        yieldBps = yieldBps_;
    }

    function asset() external view override returns (address) {
        return address(assetToken);
    }

    function vault() external view override returns (address) {
        return vaultAddr;
    }

    function totalAssets() public view override returns (uint256) {
        return stored;
    }

    function deposit(uint256 amount) external override onlyVault {
        if (amount == 0) return;
        assetToken.safeTransferFrom(msg.sender, address(this), amount);
        stored += amount;
    }

    function withdraw(uint256 amount) external override onlyVault returns (uint256 withdrawn) {
        withdrawn = amount > stored ? stored : amount;
        stored -= withdrawn;
        assetToken.safeTransfer(msg.sender, withdrawn);
    }

    function harvest() external override onlyVault returns (uint256 profit) {
        profit = (stored * yieldBps) / 10_000;
        if (profit > 0) {
            // Inflate accounting to represent mark-to-market yield booked by the vault.
            stored += profit;
        }
    }

    /// @notice Lab helper: book external yield tokens into the strategy.
    function pushYield(uint256 amount) external {
        assetToken.safeTransferFrom(msg.sender, address(this), amount);
        stored += amount;
    }
}
