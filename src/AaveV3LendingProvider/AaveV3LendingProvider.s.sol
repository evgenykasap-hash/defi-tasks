// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AaveV3LendingProvider} from "./AaveV3LendingProvider.sol";
import {AaveV3LendingProviderConfig} from "./AaveV3LendingProviderConfig.sol";

contract DeployAaveV3LendingProvider is Script {
    function run() public {
        vm.startBroadcast();

        (address poolAddressesProvider, address[] memory supportedTokens) = AaveV3LendingProviderConfig.getConfig();

        AaveV3LendingProvider aaveV3LendingProvider = new AaveV3LendingProvider(poolAddressesProvider, supportedTokens);

        console.log("AaveV3LendingProvider deployed at:", address(aaveV3LendingProvider));

        vm.stopBroadcast();
    }
}
