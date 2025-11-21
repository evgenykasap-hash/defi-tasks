// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV3TWAPOracle} from "../UniswapV3TWAPOracle.sol";
import {UniswapV3TWAPOracleConfig} from "../UniswapV3TWAPOracleConfig.sol";

contract UniswapV3TWAPOracleTest is Test {
    UniswapV3TWAPOracle private oracle;
    address[] private pools;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));
        pools = UniswapV3TWAPOracleConfig.getDefaultPools();
        oracle = new UniswapV3TWAPOracle(pools);
    }

    function testGetAveragePriceForConfiguredPools() public view {
        uint32 interval = 10 minutes;

        console.log("pools.length:", pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 priceX96 = oracle.getAveragePrice(pools[i], interval);
            console.log("priceX96:", priceX96);
            assertGt(priceX96, 0, "TWAP price should be greater than zero");
        }
    }

    function testGetAveragePriceForUnsupportedPool() public {
        vm.expectRevert(abi.encodeWithSelector(UniswapV3TWAPOracle.UnsupportedPool.selector, address(0xCAFE)));
        oracle.getAveragePrice(address(0xCAFE), 10 minutes);
    }

    function testGetAveragePriceForZeroInterval() public {
        vm.expectRevert(abi.encodeWithSelector(UniswapV3TWAPOracle.AmountMustBeGreaterThanZero.selector));
        oracle.getAveragePrice(pools[0], 0);
    }
}
