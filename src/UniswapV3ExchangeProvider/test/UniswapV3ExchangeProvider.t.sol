// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {
    ISwapRouter
} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {
    TransferHelper
} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {
    UniswapV3ExchangeProvider,
    IUniswapV3ExchangeProvider
} from "../UniswapV3ExchangeProvider.sol";
import {
    UniswapV3ExchangeProviderConfig
} from "../UniswapV3ExchangeProviderConfig.sol";
import {
    IERC20Metadata
} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Extended} from "../../libraries/IERC20Extended.sol";
import {
    IUniswapV3TWAPOracle,
    UniswapV3TWAPOracle
} from "../../UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol";

contract UniswapV3ExchangeProviderTest is Test {
    UniswapV3ExchangeProvider public uniswapV3ExchangeProvider;
    address user;

    IERC20Extended internal wethToken;
    IERC20Metadata internal usdtToken;
    IERC20Metadata internal linkToken;
    IERC20Metadata internal wbtcToken;

    IUniswapV3TWAPOracle public uniswapV3TWAPOracle;

    uint256 constant INITIAL_BALANCE = 100000000 ether;
    uint256 constant INITIAL_BALANCE_PER_TOKEN = INITIAL_BALANCE / 4;

    function setUp() public {
        wethToken = IERC20Extended(UniswapV3ExchangeProviderConfig.WETH);
        usdtToken = IERC20Metadata(UniswapV3ExchangeProviderConfig.USDT);
        linkToken = IERC20Metadata(UniswapV3ExchangeProviderConfig.LINK);
        wbtcToken = IERC20Metadata(UniswapV3ExchangeProviderConfig.WBTC);

        user = makeAddr("user");
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));

        vm.startPrank(user);
        vm.deal(user, INITIAL_BALANCE);

        deal(address(wethToken), user, INITIAL_BALANCE_PER_TOKEN);
        deal(address(usdtToken), user, INITIAL_BALANCE_PER_TOKEN);
        deal(address(linkToken), user, INITIAL_BALANCE_PER_TOKEN);
        deal(address(wbtcToken), user, INITIAL_BALANCE_PER_TOKEN);

        uniswapV3TWAPOracle = new UniswapV3TWAPOracle();

        uniswapV3ExchangeProvider = new UniswapV3ExchangeProvider(
            ISwapRouter(UniswapV3ExchangeProviderConfig.SWAP_ROUTER)
        );

        IUniswapV3ExchangeProvider.SwapParams[]
            memory ethUsdtSwaps = new IUniswapV3ExchangeProvider.SwapParams[](
                1
            );
        ethUsdtSwaps[0] = IUniswapV3ExchangeProvider.SwapParams({
            poolAddress: UniswapV3ExchangeProviderConfig.WETH_USDT,
            tokenA: UniswapV3ExchangeProviderConfig.WETH,
            tokenB: UniswapV3ExchangeProviderConfig.USDT
        });

        uniswapV3ExchangeProvider.addPair(
            ethUsdtSwaps,
            UniswapV3ExchangeProviderConfig.WETH_USDT_FEE,
            UniswapV3ExchangeProviderConfig.WETH_USDT_SLIPPAGE_TOLERANCE
        );

        IUniswapV3ExchangeProvider.SwapParams[]
            memory linkWethSwaps = new IUniswapV3ExchangeProvider.SwapParams[](
                1
            );
        linkWethSwaps[0] = IUniswapV3ExchangeProvider.SwapParams({
            poolAddress: UniswapV3ExchangeProviderConfig.LINK_WETH,
            tokenA: UniswapV3ExchangeProviderConfig.LINK,
            tokenB: UniswapV3ExchangeProviderConfig.WETH
        });

        uniswapV3ExchangeProvider.addPair(
            linkWethSwaps,
            UniswapV3ExchangeProviderConfig.LINK_WETH_FEE,
            UniswapV3ExchangeProviderConfig.LINK_WETH_SLIPPAGE_TOLERANCE
        );

        IUniswapV3ExchangeProvider.SwapParams[]
            memory wbtcLinkSwaps = new IUniswapV3ExchangeProvider.SwapParams[](
                2
            );
        wbtcLinkSwaps[0] = IUniswapV3ExchangeProvider.SwapParams({
            poolAddress: UniswapV3ExchangeProviderConfig.WBTC_WETH,
            tokenA: UniswapV3ExchangeProviderConfig.WBTC,
            tokenB: UniswapV3ExchangeProviderConfig.WETH
        });

        wbtcLinkSwaps[1] = IUniswapV3ExchangeProvider.SwapParams({
            poolAddress: UniswapV3ExchangeProviderConfig.LINK_WETH,
            tokenA: UniswapV3ExchangeProviderConfig.WETH,
            tokenB: UniswapV3ExchangeProviderConfig.LINK
        });

        uniswapV3ExchangeProvider.addPair(
            wbtcLinkSwaps,
            UniswapV3ExchangeProviderConfig.WBTC_LINK_FEE,
            UniswapV3ExchangeProviderConfig.WBTC_LINK_SLIPPAGE_TOLERANCE
        );

        uniswapV3TWAPOracle.addPool(UniswapV3ExchangeProviderConfig.WETH_USDT);
        uniswapV3TWAPOracle.addPool(UniswapV3ExchangeProviderConfig.LINK_WETH);
        uniswapV3TWAPOracle.addPool(UniswapV3ExchangeProviderConfig.WBTC_WETH);
        uniswapV3TWAPOracle.addPool(UniswapV3ExchangeProviderConfig.WBTC_USDT);

        vm.stopPrank();
    }

    // swap input tests
    function test_swapInput_wethToUsdtSwap() public {
        vm.startPrank(user);
        bytes32 pairKey = keccak256(
            abi.encodePacked(
                UniswapV3ExchangeProviderConfig.WETH,
                UniswapV3ExchangeProviderConfig.USDT
            )
        );

        uint256 amountIn = 1 ether;
        TransferHelper.safeApprove(
            address(wethToken),
            address(uniswapV3ExchangeProvider),
            amountIn
        );
        uint256 usdtBalanceBeforeSwap = usdtToken.balanceOf(user);
        console.log("usdtBalanceBeforeSwap:", usdtBalanceBeforeSwap);
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(
            pairKey,
            address(wethToken),
            address(usdtToken),
            amountIn
        );

        uint256 usdtBalanceAfterSwap = usdtToken.balanceOf(user);
        console.log("usdtBalanceAfterSwap:", usdtBalanceAfterSwap);

        assertEq(usdtBalanceAfterSwap - usdtBalanceBeforeSwap, amountOut);

        console.log("amountOut:", amountOut);

        vm.stopPrank();
    }

    function test_swapInput_linkToWethSwap() public {
        vm.startPrank(user);
        bytes32 pairKey = keccak256(
            abi.encodePacked(
                UniswapV3ExchangeProviderConfig.LINK,
                UniswapV3ExchangeProviderConfig.WETH
            )
        );

        uint256 amountIn = 100 ether;

        uint256 wethBalanceBeforeSwap = wethToken.balanceOf(user);
        console.log("wethBalanceBeforeSwap:", wethBalanceBeforeSwap);

        TransferHelper.safeApprove(
            address(linkToken),
            address(uniswapV3ExchangeProvider),
            amountIn
        );
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(
            pairKey,
            address(linkToken),
            address(wethToken),
            amountIn
        );

        uint256 wethBalanceAfterSwap = wethToken.balanceOf(user);

        console.log("amountOut:", amountOut);

        assertEq(wethBalanceAfterSwap - wethBalanceBeforeSwap, amountOut);

        vm.stopPrank();
    }

    // multi-hop swap
    function test_swapInput_wbtcToLinkSwap() public {
        vm.startPrank(user);
        bytes32 pairKey = keccak256(
            abi.encodePacked(
                UniswapV3ExchangeProviderConfig.WBTC,
                UniswapV3ExchangeProviderConfig.LINK
            )
        );

        uint256 linkBalanceBeforeSwap = linkToken.balanceOf(user);
        console.log("linkBalanceBeforeSwap:", linkBalanceBeforeSwap);

        uint256 amountIn = 100000000;
        TransferHelper.safeApprove(
            address(wbtcToken),
            address(uniswapV3ExchangeProvider),
            amountIn
        );
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(
            pairKey,
            address(wbtcToken),
            address(linkToken),
            amountIn
        );

        uint256 linkBalanceAfterSwap = linkToken.balanceOf(user);
        console.log("linkBalanceAfterSwap:", linkBalanceAfterSwap);

        console.log("link amount out:", amountOut);

        assertEq(linkBalanceAfterSwap - linkBalanceBeforeSwap, amountOut);
    }

    function test_swapInput_linkToWbtcSwap() public {
        vm.startPrank(user);
        bytes32 pairKey = keccak256(
            abi.encodePacked(
                UniswapV3ExchangeProviderConfig.WBTC,
                UniswapV3ExchangeProviderConfig.LINK
            )
        );

        uint256 wbtcBalanceBeforeSwap = wbtcToken.balanceOf(user);
        console.log("wbtcBalanceBeforeSwap:", wbtcBalanceBeforeSwap);

        uint256 amountIn = 6900 ether;
        TransferHelper.safeApprove(
            address(linkToken),
            address(uniswapV3ExchangeProvider),
            amountIn
        );
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(
            pairKey,
            address(linkToken),
            address(wbtcToken),
            amountIn
        );

        uint256 wbtcBalanceAfterSwap = wbtcToken.balanceOf(user);

        console.log("wbtcBalanceAfterSwap:", wbtcBalanceAfterSwap);
        console.log("wbtc amount out:", amountOut);

        assertEq(wbtcBalanceAfterSwap - wbtcBalanceBeforeSwap, amountOut);
    }

    // swap output tests
    function test_swapOutput_wethToUsdtSwap() public {
        vm.startPrank(user);
        bytes32 pairKey = keccak256(
            abi.encodePacked(
                UniswapV3ExchangeProviderConfig.WETH,
                UniswapV3ExchangeProviderConfig.USDT
            )
        );

        uint256 wethBalanceBeforeSwap = wethToken.balanceOf(user);
        console.log("wethBalanceBeforeSwap:", wethBalanceBeforeSwap);

        uint256 maxAmountIn = 1 ether;
        uint256 amountOut = uniswapV3TWAPOracle.getAveragePrice(
            UniswapV3ExchangeProviderConfig.WETH_USDT,
            address(wethToken),
            address(usdtToken),
            maxAmountIn,
            5 minutes
        );

        amountOut = amountOut - ((amountOut * 5) / 100);

        TransferHelper.safeApprove(
            address(wethToken),
            address(uniswapV3ExchangeProvider),
            maxAmountIn
        );
        uint256 amountIn = uniswapV3ExchangeProvider.swapOutput(
            pairKey,
            address(wethToken),
            address(usdtToken),
            amountOut,
            maxAmountIn
        );

        uint256 wethBalanceAfterSwap = wethToken.balanceOf(user);
        console.log("wethBalanceAfterSwap:", wethBalanceAfterSwap);

        assertEq(wethBalanceAfterSwap + amountIn, wethBalanceBeforeSwap);

        vm.stopPrank();
    }

    function test_swapOutput_wbtcToLinkSwap() public {
        vm.startPrank(user);
        bytes32 pairKey = keccak256(
            abi.encodePacked(
                UniswapV3ExchangeProviderConfig.WBTC,
                UniswapV3ExchangeProviderConfig.LINK
            )
        );

        uint256 maxAmountIn = 100000000;
        uint256 linkAmountOut;

        IUniswapV3ExchangeProvider.Pair memory pair = uniswapV3ExchangeProvider
            .getPair(pairKey);
        for (uint256 i = 0; i < pair.swaps.length; i++) {
            linkAmountOut = uniswapV3TWAPOracle.getAveragePrice(
                pair.swaps[i].poolAddress,
                pair.swaps[i].tokenA,
                pair.swaps[i].tokenB,
                maxAmountIn,
                5 minutes
            );
        }

        uint256 wbtcBalanceBeforeSwap = wbtcToken.balanceOf(user);
        console.log("wbtcBalanceBeforeSwap:", wbtcBalanceBeforeSwap);

        TransferHelper.safeApprove(
            address(wbtcToken),
            address(uniswapV3ExchangeProvider),
            maxAmountIn
        );
        uint256 amountIn = uniswapV3ExchangeProvider.swapOutput(
            pairKey,
            address(wbtcToken),
            address(linkToken),
            linkAmountOut,
            maxAmountIn
        );

        uint256 wbtcBalanceAfterSwap = wbtcToken.balanceOf(user);
        console.log("wbtcBalanceAfterSwap:", wbtcBalanceAfterSwap);

        assertEq(wbtcBalanceAfterSwap + amountIn, wbtcBalanceBeforeSwap);
        vm.stopPrank();
    }
}
