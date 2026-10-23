// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VaultForge} from "../src/VaultForge.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockYieldStrategy} from "../src/strategies/MockYieldStrategy.sol";

contract DeployVaultForge is Script {
    function run() external {
        address deployer = msg.sender;
        vm.startBroadcast();
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        VaultForge vault = new VaultForge(usdc, "VaultForge USDC", "vfUSDC", deployer, deployer, 1000);
        MockYieldStrategy strategy = new MockYieldStrategy(address(usdc), address(vault), 100);
        vault.setStrategy(address(strategy));
        vm.stopBroadcast();
        console2.log("USDC", address(usdc));
        console2.log("Vault", address(vault));
        console2.log("Strategy", address(strategy));
    }
}
