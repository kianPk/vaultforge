// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {VaultForge} from "../src/VaultForge.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockYieldStrategy} from "../src/strategies/MockYieldStrategy.sol";

contract VaultForgeTest is Test {
    MockERC20 asset;
    VaultForge vault;
    MockYieldStrategy strategy;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address feeTo = makeAddr("feeTo");

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC", 6);
        vm.prank(admin);
        vault = new VaultForge(asset, "VaultForge USDC", "vfUSDC", admin, feeTo, 1000); // 10% perf fee
        strategy = new MockYieldStrategy(address(asset), address(vault), 100); // 1% per harvest

        vm.prank(admin);
        vault.setStrategy(address(strategy));

        asset.mint(alice, 1_000_000e6);
        asset.mint(bob, 500_000e6);
    }

    function test_depositMintShares() public {
        vm.startPrank(alice);
        asset.approve(address(vault), 100_000e6);
        uint256 shares = vault.deposit(100_000e6, alice);
        vm.stopPrank();

        assertEq(shares, 100_000e6);
        assertEq(vault.balanceOf(alice), 100_000e6);
        assertEq(vault.totalAssets(), 100_000e6);
    }

    function test_allocateAndHarvestTakesFee() public {
        vm.startPrank(alice);
        asset.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, alice);
        vm.stopPrank();

        vm.prank(admin);
        vault.allocate(80_000e6);

        assertEq(vault.deployedAssets(), 80_000e6);
        assertEq(vault.idleAssets(), 20_000e6);

        // Book 1% yield into strategy accounting via harvest inflation
        uint256 before = vault.totalAssets();
        vm.prank(admin);
        (uint256 profit, uint256 fee) = vault.harvest();

        assertEq(profit, 800e6); // 1% of 80k
        assertEq(fee, 80e6); // 10% of profit
        assertGt(vault.totalAssets(), before);
        assertGt(vault.balanceOf(feeTo), 0);
    }

    function test_withdrawPullsFromStrategy() public {
        vm.startPrank(alice);
        asset.approve(address(vault), 50_000e6);
        vault.deposit(50_000e6, alice);
        vm.stopPrank();

        vm.prank(admin);
        vault.allocate(50_000e6);

        vm.prank(alice);
        vault.withdraw(40_000e6, alice, alice);

        assertEq(asset.balanceOf(alice), 1_000_000e6 - 50_000e6 + 40_000e6);
    }

    function test_pauseBlocksDeposit() public {
        vm.prank(admin);
        vault.pause();

        vm.startPrank(alice);
        asset.approve(address(vault), 1e6);
        vm.expectRevert();
        vault.deposit(1e6, alice);
        vm.stopPrank();
    }

    function testFuzz_depositRedeem(uint256 amount) public {
        amount = bound(amount, 1e6, 200_000e6);
        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        uint256 out = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(out, amount);
    }

    function test_depositCapEnforced() public {
        vm.prank(admin);
        vault.setDepositCap(50_000e6);

        vm.startPrank(alice);
        asset.approve(address(vault), 100_000e6);
        vm.expectRevert(VaultForge.DepositCapExceeded.selector);
        vault.deposit(60_000e6, alice);
        vault.deposit(40_000e6, alice);
        vm.stopPrank();
    }

    function test_rebalanceHonorsDebtRatio() public {
        vm.startPrank(alice);
        asset.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, alice);
        vm.stopPrank();

        vm.prank(admin);
        vault.setDebtRatioBps(8000);
        vm.prank(admin);
        vault.rebalance();

        assertApproxEqAbs(vault.deployedAssets(), 80_000e6, 1);
        assertApproxEqAbs(vault.idleAssets(), 20_000e6, 1);
        assertEq(vault.sharePrice(), 1e18);
    }
}
