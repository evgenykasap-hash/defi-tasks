// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {
    IUniswapV3TWAPOracle,
    UniswapV3TWAPOracle
} from "../UniswapV3TWAPOracle.sol";
import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3TWAPOracleConfig} from "../UniswapV3TWAPOracleConfig.sol";
import {IERC20Extended} from "../../libraries/IERC20Extended.sol";

contract UniswapV3TWAPOracleTest is Test {
    IUniswapV3TWAPOracle private oracle;
    address[] private pools;
    address private owner;

    function setUp() public {
        owner = makeAddr("owner");
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));

        vm.startPrank(owner);
        pools = UniswapV3TWAPOracleConfig.getDefaultPools();
        oracle = new UniswapV3TWAPOracle();

        for (uint256 i = 0; i < pools.length; i++) {
            oracle.addPool(pools[i]);
        }
        vm.stopPrank();
    }

    function testGetETHtoUSDCAveragePrice() public view {
        uint256 priceX96 = oracle.getAveragePrice(
            pools[0], // ETH/USDC
            10 ** 18,
            10 minutes
        );
        console.log("priceX96:", priceX96 / (10 ** 6));
        assertGt(priceX96, 0, "TWAP price should be greater than zero");
    }

    function testGetAveragePriceForMoreThanOneToken() public view {
        uint256 priceForOneTokenX96 = oracle.getAveragePrice(
            pools[0], // ETH/USDC
            1 ether,
            10 minutes
        );

        uint256 priceForThreeTokensX96 = oracle.getAveragePrice(
            pools[0], // ETH/USDC
            3 ether,
            10 minutes
        );

        uint8 token1Decimals = IERC20Extended(IUniswapV3Pool(pools[0]).token1())
            .decimals();

        uint256 normalizedPriceForOneToken = priceForOneTokenX96 /
            (10 ** token1Decimals);
        uint256 normalizedPriceForThreeTokens = priceForThreeTokensX96 /
            (10 ** token1Decimals);

        console.log("normalizedPriceForOneToken:", normalizedPriceForOneToken);
        console.log(
            "normalizedPriceForThreeTokens:",
            normalizedPriceForThreeTokens
        );

        assertApproxEqAbs(priceForThreeTokensX96, priceForOneTokenX96 * 3, 35);
    }

    function testAddingSupportedPool() public {
        vm.startPrank(owner);

        assertFalse(oracle.checkIfPoolIsSupported(address(0xCAFE)));

        oracle.addPool(address(0xCAFE));
        vm.stopPrank();

        assertTrue(oracle.checkIfPoolIsSupported(address(0xCAFE)));
    }

    function testRemovingSupportedPool() public {
        vm.startPrank(owner);
        oracle.addPool(address(0xCAFE));

        assertTrue(oracle.checkIfPoolIsSupported(address(0xCAFE)));
        oracle.removePool(address(0xCAFE));
        assertFalse(oracle.checkIfPoolIsSupported(address(0xCAFE)));
        vm.stopPrank();
    }

    function testGetAveragePriceForUnsupportedPool() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3TWAPOracle.UnsupportedPool.selector,
                address(0xCAFE)
            )
        );
        oracle.getAveragePrice(address(0xCAFE), 1, 10 minutes);
    }

    function testGetAveragePriceForZeroAmountIn() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3TWAPOracle.AmountMustBeGreaterThanZero.selector
            )
        );
        oracle.getAveragePrice(pools[0], 0, 10 minutes);
    }

    function testGetAveragePriceForZeroInterval() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3TWAPOracle.IntervalMustBeGreaterThanZero.selector
            )
        );
        oracle.getAveragePrice(pools[0], 0, 0);
    }
}
