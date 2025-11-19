// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {UniswapV3TWAPOracle} from "./UniswapV3TWAPOracle.sol";
import {UniswapV3TWAPOracleConfig} from "./UniswapV3TWAPOracleConfig.sol";

contract DeployUniswapV3TWAPOracle is Script {
    function run() public {
        vm.startBroadcast();

        address[] memory pools = UniswapV3TWAPOracleConfig.getDefaultPools();
        UniswapV3TWAPOracle oracle = new UniswapV3TWAPOracle(pools);

        console.log("UniswapV3TWAPOracle deployed at:", address(oracle));
        for (uint256 i = 0; i < pools.length; i++) {
            console.log("  - Pool", i, pools[i]);
        }

        vm.stopBroadcast();
    }
}
