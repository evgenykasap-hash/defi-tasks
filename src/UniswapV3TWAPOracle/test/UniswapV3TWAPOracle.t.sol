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
import {
    IERC20Metadata
} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract UniswapV3TWAPOracleTest is Test {
    IUniswapV3TWAPOracle private oracle;
    address[] private pools;
    address private owner;

    address private weth;
    address private usdt;
    address private dai;

    function setUp() public {
        weth = UniswapV3TWAPOracleConfig.WETH;
        usdt = UniswapV3TWAPOracleConfig.USDT;
        dai = UniswapV3TWAPOracleConfig.DAI;
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

    function test_getAveragePrice_ethToUsdt() public view {
        address poolAddress = pools[0]; // ETH/USDT
        uint256 priceX96 = oracle.getAveragePrice(
            poolAddress,
            weth,
            usdt,
            10 ** 18,
            10 minutes
        );
        console.log("priceX96:", priceX96 / (10 ** 6));
        assertGt(priceX96, 0, "TWAP price should be greater than zero");
    }

    function test_getAveragePrice_priceForMoreThanOneToken() public view {
        address poolAddress = pools[1]; // ETH/DAI
        uint256 priceForOneTokenX96 = oracle.getAveragePrice(
            poolAddress,
            weth,
            dai,
            1 ether,
            10 minutes
        );

        uint256 priceForThreeTokensX96 = oracle.getAveragePrice(
            poolAddress,
            weth,
            dai,
            3 ether,
            10 minutes
        );

        uint8 token1Decimals = IERC20Metadata(
            IUniswapV3Pool(poolAddress).token1()
        ).decimals();

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

    function test_addPool_addingSupportedPool() public {
        address poolAddress = pools[0]; // ETH/USDT
        vm.startPrank(owner);

        oracle.removePool(poolAddress);
        assertFalse(oracle.checkIfPoolIsSupported(poolAddress));

        oracle.addPool(pools[0]);
        vm.stopPrank();

        assertTrue(oracle.checkIfPoolIsSupported(poolAddress));
    }

    function test_removePool_removingSupportedPool() public {
        address poolAddress = pools[0]; // ETH/USDT
        vm.startPrank(owner);
        oracle.addPool(poolAddress);

        assertTrue(oracle.checkIfPoolIsSupported(poolAddress));
        oracle.removePool(poolAddress);
        assertFalse(oracle.checkIfPoolIsSupported(poolAddress));
        vm.stopPrank();
    }

    function test_getAveragePrice_unsupportedPool() public {
        address poolAddress = address(0xCAFE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3TWAPOracle.UnsupportedPool.selector,
                address(0xCAFE)
            )
        );
        oracle.getAveragePrice(poolAddress, weth, usdt, 1, 10 minutes);
    }

    function test_getAveragePrice_zeroAmountIn() public {
        address poolAddress = pools[0]; // ETH/USDT
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3TWAPOracle.AmountMustBeGreaterThanZero.selector
            )
        );
        oracle.getAveragePrice(poolAddress, weth, usdt, 0, 10 minutes);
    }

    function test_getAveragePrice_zeroInterval() public {
        address poolAddress = pools[0]; // ETH/USDT
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3TWAPOracle.IntervalMustBeGreaterThanZero.selector
            )
        );
        oracle.getAveragePrice(poolAddress, weth, usdt, 0, 0);
    }
}
