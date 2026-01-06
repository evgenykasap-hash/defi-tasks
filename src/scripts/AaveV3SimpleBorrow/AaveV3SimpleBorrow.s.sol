// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {AaveV3SimpleBorrow} from "../../contracts/AaveV3SimpleBorrow/AaveV3SimpleBorrow.sol";
import {AaveV3SimpleBorrowConfig} from "./AaveV3SimpleBorrowConfig.sol";

/// @title DeployAaveV3SimpleBorrow
/// @notice Deploys the Aave V3 simple borrow contract.
contract DeployAaveV3SimpleBorrow is Script {
    /// @notice Deploys the contract using the configured pool addresses provider.
    function run() public {
        vm.startBroadcast();

        address poolAddressesProvider = AaveV3SimpleBorrowConfig.getConfig();
        AaveV3SimpleBorrow simpleBorrow = new AaveV3SimpleBorrow(poolAddressesProvider);

        console.log("AaveV3SimpleBorrow deployed at:", address(simpleBorrow));

        vm.stopBroadcast();
    }
}
