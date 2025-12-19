// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV3TWAPOracle} from "../../src/contracts/UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol";
import {IUniswapV3TWAPOracle} from "../../src/contracts/UniswapV3TWAPOracle/interfaces/IUniswapV3TWAPOracle.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3TWAPOracleConfig} from "../../src/scripts/UniswapV3TWAPOracle/UniswapV3TWAPOracleConfig.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract UniswapV3TWAPOracleTest is Test {
    IUniswapV3TWAPOracle private oracle;
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
        oracle = new UniswapV3TWAPOracle(UniswapV3TWAPOracleConfig.UNISWAP_V3_FACTORY);

        oracle.setPool(oracle.getPoolAddress(weth, usdt, UniswapV3TWAPOracleConfig.WETH_USDT_FEE), true);
        oracle.setPool(oracle.getPoolAddress(weth, dai, UniswapV3TWAPOracleConfig.WETH_DAI_FEE), true);

        vm.stopPrank();
    }

    function test_getAveragePrice_wethToUsdt() public view {
        uint256 priceX96 = oracle.getAveragePrice(weth, usdt, UniswapV3TWAPOracleConfig.WETH_USDT_FEE, 1 ether);
        console.log("priceX96:", priceX96 / (10 ** 6));
        assertGt(priceX96, 0, "TWAP price should be greater than zero");
    }

    function test_getAveragePrice_usdtToWeth() public view {
        uint256 priceX96 = oracle.getAveragePrice(usdt, weth, UniswapV3TWAPOracleConfig.WETH_USDT_FEE, 1 ether);
        console.log("priceX96:", priceX96 / (10 ** 6));
        assertGt(priceX96, 0, "TWAP price should be greater than zero");
    }

    function test_getAveragePrice_priceForMoreThanOneToken() public view {
        uint256 priceForOneTokenX96 = oracle.getAveragePrice(weth, dai, UniswapV3TWAPOracleConfig.WETH_DAI_FEE, 1 ether);

        uint256 priceForThreeTokensX96 =
            oracle.getAveragePrice(weth, dai, UniswapV3TWAPOracleConfig.WETH_DAI_FEE, 3 ether);

        address poolAddress = oracle.getPoolAddress(weth, dai, UniswapV3TWAPOracleConfig.WETH_DAI_FEE);

        uint8 token1Decimals = IERC20Metadata(IUniswapV3Pool(oracle.getPool(poolAddress)).token1()).decimals();

        uint256 normalizedPriceForOneToken = priceForOneTokenX96 / (10 ** token1Decimals);
        uint256 normalizedPriceForThreeTokens = priceForThreeTokensX96 / (10 ** token1Decimals);

        console.log("normalizedPriceForOneToken:", normalizedPriceForOneToken);
        console.log("normalizedPriceForThreeTokens:", normalizedPriceForThreeTokens);

        assertApproxEqAbs(priceForThreeTokensX96, priceForOneTokenX96 * 3, 35);
    }

    function test_addPool_addingSupportedPool() public {
        vm.startPrank(owner);

        address poolAddress = oracle.getPoolAddress(weth, usdt, UniswapV3TWAPOracleConfig.WETH_USDT_FEE);

        oracle.setPool(poolAddress, false);
        assertFalse(oracle.checkIfPoolIsSupported(poolAddress));

        oracle.setPool(poolAddress, true);
        vm.stopPrank();

        assertTrue(oracle.checkIfPoolIsSupported(poolAddress));
    }

    function test_removePool_removingSupportedPool() public {
        vm.startPrank(owner);
        address poolAddress = oracle.getPoolAddress(weth, usdt, UniswapV3TWAPOracleConfig.WETH_USDT_FEE);
        oracle.setPool(poolAddress, true);

        assertTrue(oracle.checkIfPoolIsSupported(poolAddress));
        oracle.setPool(poolAddress, false);
        assertFalse(oracle.checkIfPoolIsSupported(poolAddress));
        vm.stopPrank();
    }

    function test_getAveragePrice_unsupportedPool() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3TWAPOracle.UnsupportedPool.selector, address(0x0000000000000000000000000000000000000000)
            )
        );
        oracle.getAveragePrice(address(0xCAFE), address(0xCAFE), UniswapV3TWAPOracleConfig.WETH_USDT_FEE, 1);
    }

    function test_getAveragePrice_zeroAmountIn() public {
        vm.expectRevert(abi.encodeWithSelector(IUniswapV3TWAPOracle.AmountMustBeGreaterThanZero.selector));
        oracle.getAveragePrice(weth, usdt, UniswapV3TWAPOracleConfig.WETH_USDT_FEE, 0);
    }
}
