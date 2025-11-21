// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {UniswapV3ExchangeProvider} from "../UniswapV3ExchangeProvider.sol";
import {UniswapV3ExchangeProviderTestConfig} from "./UniswapV3ExchangeProviderTestConfig.sol";

contract UniswapV3ExchangeProviderTest is Test {
    UniswapV3ExchangeProvider public uniswapV3ExchangeProvider;
    address user;

    function setUp() public {
        user = makeAddr("user");
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));

        // Use library functions - no deployment needed!
        uniswapV3ExchangeProvider = new UniswapV3ExchangeProvider(
            ISwapRouter(UniswapV3ExchangeProviderTestConfig.SWAP_ROUTER),
            UniswapV3ExchangeProviderTestConfig.POOL_FEE,
            UniswapV3ExchangeProviderTestConfig.getSinglehopPairs(),
            UniswapV3ExchangeProviderTestConfig.getMultihopPairs(),
            UniswapV3ExchangeProviderTestConfig.SLIPPAGE_TOLERANCE
        );
    }

    function testSwapExactInputSingle() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        // Use library helpers - much cleaner!
        UniswapV3ExchangeProviderTestConfig.weth().deposit{value: 10 ether}();
        UniswapV3ExchangeProviderTestConfig.weth().approve(address(uniswapV3ExchangeProvider), 10 ether);

        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(
            UniswapV3ExchangeProviderTestConfig.WETH, UniswapV3ExchangeProviderTestConfig.USDC, 2 ether, 0
        );

        uint256 userBalance = UniswapV3ExchangeProviderTestConfig.usdc().balanceOf(user);

        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive USDC");
        assertGt(userBalance, 0, "User should have USDC");

        console.log("Swapped 2 WETH for", amountOut, "USDC");
    }

    function testSwapExactOutputSingle() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        UniswapV3ExchangeProviderTestConfig.weth().deposit{value: 10 ether}();

        uint256 desiredUsdcOut = 3000 * 1e6;
        uint256 maxWethIn = 2 ether;

        uint256 initialWeth = UniswapV3ExchangeProviderTestConfig.weth().balanceOf(user);

        UniswapV3ExchangeProviderTestConfig.weth().approve(address(uniswapV3ExchangeProvider), maxWethIn * 2);

        uint256 actualWethSpent = uniswapV3ExchangeProvider.swapOutput(
            UniswapV3ExchangeProviderTestConfig.WETH,
            UniswapV3ExchangeProviderTestConfig.USDC,
            desiredUsdcOut,
            maxWethIn
        );

        vm.stopPrank();

        assertEq(
            UniswapV3ExchangeProviderTestConfig.usdc().balanceOf(user),
            desiredUsdcOut,
            "Should receive exact USDC amount"
        );
        assertLe(actualWethSpent, maxWethIn, "Should not spend more than max");

        uint256 finalWeth = UniswapV3ExchangeProviderTestConfig.weth().balanceOf(user);
        assertEq(initialWeth - finalWeth, actualWethSpent, "WETH spent should match");

        console.log("Spent WETH:", actualWethSpent);
        console.log("Received USDC:", desiredUsdcOut);
    }

    function testSwapExactInputMultihop() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        UniswapV3ExchangeProviderTestConfig.weth().deposit{value: 10 ether}();
        UniswapV3ExchangeProviderTestConfig.weth().approve(address(uniswapV3ExchangeProvider), 10 ether);

        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(
            UniswapV3ExchangeProviderTestConfig.WETH, UniswapV3ExchangeProviderTestConfig.LINK, 2 ether, 0
        );

        uint256 userBalance = UniswapV3ExchangeProviderTestConfig.link().balanceOf(user);

        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive LINK");
        assertGt(userBalance, 0, "User should have LINK");

        console.log("Swapped 2 WETH for", amountOut, "LINK");
    }

    function testSwapExactOutputMultihop() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        UniswapV3ExchangeProviderTestConfig.weth().deposit{value: 10 ether}();
        UniswapV3ExchangeProviderTestConfig.weth().approve(address(uniswapV3ExchangeProvider), 10 ether);

        uint256 desiredLinkOut = 1 ether;
        uint256 maxWethIn = 2 ether;

        uint256 initialWeth = UniswapV3ExchangeProviderTestConfig.weth().balanceOf(user);

        UniswapV3ExchangeProviderTestConfig.weth().approve(address(uniswapV3ExchangeProvider), maxWethIn * 2);

        uint256 actualWethSpent = uniswapV3ExchangeProvider.swapOutput(
            UniswapV3ExchangeProviderTestConfig.WETH,
            UniswapV3ExchangeProviderTestConfig.LINK,
            desiredLinkOut,
            maxWethIn
        );

        uint256 finalWeth = UniswapV3ExchangeProviderTestConfig.weth().balanceOf(user);
        vm.stopPrank();

        assertEq(
            UniswapV3ExchangeProviderTestConfig.link().balanceOf(user),
            desiredLinkOut,
            "Should receive exact LINK amount"
        );
        assertLe(actualWethSpent, maxWethIn, "Should not spend more than max");

        assertEq(initialWeth - finalWeth, actualWethSpent, "WETH spent should match");

        console.log("Spent WETH:", actualWethSpent);
        console.log("Received LINK:", desiredLinkOut);
    }

    function testSwapExactInputWithThreeHops() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        UniswapV3ExchangeProviderTestConfig.weth().deposit{value: 10 ether}();
        UniswapV3ExchangeProviderTestConfig.weth().approve(address(uniswapV3ExchangeProvider), 10 ether);

        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(
            UniswapV3ExchangeProviderTestConfig.WETH, UniswapV3ExchangeProviderTestConfig.WBTC, 2 ether, 0
        );

        uint256 userBalance = UniswapV3ExchangeProviderTestConfig.wbtc().balanceOf(user);
        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive WBTC");
        assertGt(userBalance, 0, "User should have WBTC");

        console.log("Swapped 2 WETH for", amountOut, "WBTC");
    }

    function testSwapExactOutputWithThreeHops() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        UniswapV3ExchangeProviderTestConfig.weth().deposit{value: 10 ether}();

        uint256 desiredBtcOut = 100000;
        uint256 maxWethIn = 0.05 ether;

        uint256 initialWeth = UniswapV3ExchangeProviderTestConfig.weth().balanceOf(user);

        UniswapV3ExchangeProviderTestConfig.weth().approve(address(uniswapV3ExchangeProvider), maxWethIn * 2);

        uint256 actualWethSpent = uniswapV3ExchangeProvider.swapOutput(
            UniswapV3ExchangeProviderTestConfig.WETH, UniswapV3ExchangeProviderTestConfig.WBTC, desiredBtcOut, maxWethIn
        );

        vm.stopPrank();

        assertEq(
            UniswapV3ExchangeProviderTestConfig.wbtc().balanceOf(user),
            desiredBtcOut,
            "Should receive exact WBTC amount"
        );
        assertLe(actualWethSpent, maxWethIn, "Should not spend more than max");

        uint256 finalWeth = UniswapV3ExchangeProviderTestConfig.weth().balanceOf(user);
        assertEq(initialWeth - finalWeth, actualWethSpent, "WETH spent should match");

        console.log("Spent WETH:", actualWethSpent);
        console.log("Received WBTC:", desiredBtcOut);
    }
}
