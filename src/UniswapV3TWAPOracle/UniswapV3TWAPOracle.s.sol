// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV3TWAPOracle} from "./UniswapV3TWAPOracle.sol";
import {UniswapV3TWAPOracleConfig} from "./UniswapV3TWAPOracleConfig.sol";

contract DeployUniswapV3TWAPOracle is Script {
    function run() public {
        vm.startBroadcast();
        new UniswapV3TWAPOracle();
        vm.stopBroadcast();
    }
}
