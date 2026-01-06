// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {CCTPAaveFastBridge} from "../../contracts/CCTPAaveFastBridge/CCTPAaveFastBridge.sol";
import {CCTPAaveFastBridgeConfig} from "./CCTPAaveFastBridgeConfig.sol";

/// @title DeployCCTPAaveFastBridge
/// @notice Deploys the CCTP fast bridge contract.
contract DeployCCTPAaveFastBridge is Script {
    /// @notice Deploys the bridge using the configured addresses.
    function run() public {
        vm.startBroadcast();

        (address poolAddressesProvider, address tokenMessenger, address usdc) = CCTPAaveFastBridgeConfig.getConfig();

        CCTPAaveFastBridge bridge = new CCTPAaveFastBridge(poolAddressesProvider, tokenMessenger, usdc);

        console.log("CCTPAaveFastBridge deployed at:", address(bridge));

        vm.stopBroadcast();
    }
}
