// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {AaveV3LendingProvider} from "../../contracts/AaveV3LendingProvider/AaveV3LendingProvider.sol";
import {AaveV3LendingProviderConfig} from "./AaveV3LendingProviderConfig.sol";

contract DeployAaveV3LendingProvider is Script {
    function run() public {
        vm.startBroadcast();

        (address poolAddressesProvider, address weth, address usdc, address dai) =
            AaveV3LendingProviderConfig.getConfig();

        AaveV3LendingProvider aaveV3LendingProvider = new AaveV3LendingProvider(poolAddressesProvider);

        aaveV3LendingProvider.addSupportedToken(weth);
        aaveV3LendingProvider.addSupportedToken(usdc);
        aaveV3LendingProvider.addSupportedToken(dai);

        console.log("AaveV3LendingProvider deployed at:", address(aaveV3LendingProvider));

        vm.stopBroadcast();
    }
}
