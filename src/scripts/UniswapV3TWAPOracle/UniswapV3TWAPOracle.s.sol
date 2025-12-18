// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {UniswapV3TWAPOracle} from "../../contracts/UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol";
import {UniswapV3TWAPOracleConfig} from "./UniswapV3TWAPOracleConfig.sol";

contract DeployUniswapV3TWAPOracle is Script {
    function run() public {
        vm.startBroadcast();
        new UniswapV3TWAPOracle(UniswapV3TWAPOracleConfig.UNISWAP_V3_FACTORY);
        vm.stopBroadcast();
    }
}
