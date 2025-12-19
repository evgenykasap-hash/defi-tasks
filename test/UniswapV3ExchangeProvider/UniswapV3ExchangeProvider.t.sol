// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {UniswapV3ExchangeProvider} from "../../src/contracts/UniswapV3ExchangeProvider/UniswapV3ExchangeProvider.sol";
import {
    IUniswapV3ExchangeProvider
} from "../../src/contracts/UniswapV3ExchangeProvider/interfaces/IUniswapV3ExchangeProvider.sol";
import {
    UniswapV3ExchangeProviderConfig
} from "../../src/scripts/UniswapV3ExchangeProvider/UniswapV3ExchangeProviderConfig.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Extended} from "../../src/contracts/common/interfaces/IERC20Extended.sol";
import {UniswapV3TWAPOracle} from "../../src/contracts/UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol";
import {IUniswapV3TWAPOracle} from "../../src/contracts/UniswapV3TWAPOracle/interfaces/IUniswapV3TWAPOracle.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract UniswapV3ExchangeProviderTest is Test {
    UniswapV3ExchangeProvider public uniswapV3ExchangeProvider;
    address user;

    IERC20Extended internal wethToken;
    IERC20Metadata internal usdtToken;
    IERC20Metadata internal linkToken;
    IERC20Metadata internal wbtcToken;

    IUniswapV3TWAPOracle public uniswapV3TwapOracle;

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

        uniswapV3TwapOracle = new UniswapV3TWAPOracle(UniswapV3ExchangeProviderConfig.UNISWAP_V3_FACTORY);

        uniswapV3ExchangeProvider = new UniswapV3ExchangeProvider(
            UniswapV3ExchangeProviderConfig.SWAP_ROUTER, UniswapV3ExchangeProviderConfig.UNISWAP_V3_FACTORY
        );

        IUniswapV3ExchangeProvider.SwapParams[] memory ethUsdtSwaps = new IUniswapV3ExchangeProvider.SwapParams[](1);
        ethUsdtSwaps[0] = IUniswapV3ExchangeProvider.SwapParams({
            tokenA: UniswapV3ExchangeProviderConfig.WETH,
            tokenB: UniswapV3ExchangeProviderConfig.USDT,
            poolFee: UniswapV3ExchangeProviderConfig.WETH_USDT_FEE
        });

        uniswapV3ExchangeProvider.addPair(ethUsdtSwaps, UniswapV3ExchangeProviderConfig.WETH_USDT_SLIPPAGE_TOLERANCE);

        IUniswapV3ExchangeProvider.SwapParams[] memory linkWethSwaps = new IUniswapV3ExchangeProvider.SwapParams[](1);
        linkWethSwaps[0] = IUniswapV3ExchangeProvider.SwapParams({
            tokenA: UniswapV3ExchangeProviderConfig.LINK,
            tokenB: UniswapV3ExchangeProviderConfig.WETH,
            poolFee: UniswapV3ExchangeProviderConfig.LINK_WETH_FEE
        });

        uniswapV3ExchangeProvider.addPair(linkWethSwaps, UniswapV3ExchangeProviderConfig.LINK_WETH_SLIPPAGE_TOLERANCE);

        IUniswapV3ExchangeProvider.SwapParams[] memory wbtcLinkSwaps = new IUniswapV3ExchangeProvider.SwapParams[](2);
        wbtcLinkSwaps[0] = IUniswapV3ExchangeProvider.SwapParams({
            tokenA: UniswapV3ExchangeProviderConfig.WBTC,
            tokenB: UniswapV3ExchangeProviderConfig.WETH,
            poolFee: UniswapV3ExchangeProviderConfig.WBTC_WETH_FEE
        });

        wbtcLinkSwaps[1] = IUniswapV3ExchangeProvider.SwapParams({
            tokenA: UniswapV3ExchangeProviderConfig.WETH,
            tokenB: UniswapV3ExchangeProviderConfig.LINK,
            poolFee: UniswapV3ExchangeProviderConfig.LINK_WETH_FEE
        });

        uniswapV3ExchangeProvider.addPair(wbtcLinkSwaps, UniswapV3ExchangeProviderConfig.WBTC_LINK_SLIPPAGE_TOLERANCE);

        uniswapV3TwapOracle.setPool(
            uniswapV3TwapOracle.getPoolAddress(
                UniswapV3ExchangeProviderConfig.WETH,
                UniswapV3ExchangeProviderConfig.USDT,
                UniswapV3ExchangeProviderConfig.WETH_USDT_FEE
            ),
            true
        );
        uniswapV3TwapOracle.setPool(
            uniswapV3TwapOracle.getPoolAddress(
                UniswapV3ExchangeProviderConfig.LINK,
                UniswapV3ExchangeProviderConfig.WETH,
                UniswapV3ExchangeProviderConfig.LINK_WETH_FEE
            ),
            true
        );
        uniswapV3TwapOracle.setPool(
            uniswapV3TwapOracle.getPoolAddress(
                UniswapV3ExchangeProviderConfig.WBTC,
                UniswapV3ExchangeProviderConfig.WETH,
                UniswapV3ExchangeProviderConfig.WBTC_WETH_FEE
            ),
            true
        );
        uniswapV3TwapOracle.setPool(
            uniswapV3TwapOracle.getPoolAddress(
                UniswapV3ExchangeProviderConfig.WBTC,
                UniswapV3ExchangeProviderConfig.USDT,
                UniswapV3ExchangeProviderConfig.WBTC_USDT_FEE
            ),
            true
        );

        vm.stopPrank();
    }

    // swap input tests
    function test_swapInput_wethToUsdtSwap() public {
        vm.startPrank(user);

        uint256 amountIn = 1 ether;
        TransferHelper.safeApprove(address(wethToken), address(uniswapV3ExchangeProvider), amountIn);
        uint256 usdtBalanceBeforeSwap = usdtToken.balanceOf(user);
        console.log("usdtBalanceBeforeSwap:", usdtBalanceBeforeSwap);
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(address(wethToken), address(usdtToken), amountIn);

        uint256 usdtBalanceAfterSwap = usdtToken.balanceOf(user);
        console.log("usdtBalanceAfterSwap:", usdtBalanceAfterSwap);

        assertEq(usdtBalanceAfterSwap - usdtBalanceBeforeSwap, amountOut);

        console.log("amountOut:", amountOut);

        vm.stopPrank();
    }

    function test_swapInput_linkToWethSwap() public {
        vm.startPrank(user);

        uint256 amountIn = 100 ether;

        uint256 wethBalanceBeforeSwap = wethToken.balanceOf(user);
        console.log("wethBalanceBeforeSwap:", wethBalanceBeforeSwap);

        TransferHelper.safeApprove(address(linkToken), address(uniswapV3ExchangeProvider), amountIn);
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(address(linkToken), address(wethToken), amountIn);

        uint256 wethBalanceAfterSwap = wethToken.balanceOf(user);

        console.log("amountOut:", amountOut);

        assertEq(wethBalanceAfterSwap - wethBalanceBeforeSwap, amountOut);

        vm.stopPrank();
    }

    // multi-hop swap
    function test_swapInput_wbtcToLinkSwap() public {
        vm.startPrank(user);

        uint256 linkBalanceBeforeSwap = linkToken.balanceOf(user);
        console.log("linkBalanceBeforeSwap:", linkBalanceBeforeSwap);

        uint256 amountIn = 100000000;
        TransferHelper.safeApprove(address(wbtcToken), address(uniswapV3ExchangeProvider), amountIn);
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(address(wbtcToken), address(linkToken), amountIn);

        uint256 linkBalanceAfterSwap = linkToken.balanceOf(user);
        console.log("linkBalanceAfterSwap:", linkBalanceAfterSwap);

        console.log("link amount out:", amountOut);

        assertEq(linkBalanceAfterSwap - linkBalanceBeforeSwap, amountOut);
    }

    function test_swapInput_linkToWbtcSwap() public {
        vm.startPrank(user);

        uint256 wbtcBalanceBeforeSwap = wbtcToken.balanceOf(user);
        console.log("wbtcBalanceBeforeSwap:", wbtcBalanceBeforeSwap);

        uint256 amountIn = 6900 ether;
        TransferHelper.safeApprove(address(linkToken), address(uniswapV3ExchangeProvider), amountIn);
        uint256 amountOut = uniswapV3ExchangeProvider.swapInput(address(linkToken), address(wbtcToken), amountIn);

        uint256 wbtcBalanceAfterSwap = wbtcToken.balanceOf(user);

        console.log("wbtcBalanceAfterSwap:", wbtcBalanceAfterSwap);
        console.log("wbtc amount out:", amountOut);

        assertEq(wbtcBalanceAfterSwap - wbtcBalanceBeforeSwap, amountOut);
    }

    // swap output tests
    function test_swapOutput_wethToUsdtSwap() public {
        vm.startPrank(user);

        uint256 wethBalanceBeforeSwap = wethToken.balanceOf(user);
        console.log("wethBalanceBeforeSwap:", wethBalanceBeforeSwap);

        uint256 maxAmountIn = 1 ether;
        uint256 amountOut = uniswapV3TwapOracle.getAveragePrice(
            address(wethToken), address(usdtToken), UniswapV3ExchangeProviderConfig.WETH_USDT_FEE, maxAmountIn
        );

        amountOut = amountOut - ((amountOut * 5) / 100);

        TransferHelper.safeApprove(address(wethToken), address(uniswapV3ExchangeProvider), maxAmountIn);
        uint256 amountIn =
            uniswapV3ExchangeProvider.swapOutput(address(wethToken), address(usdtToken), amountOut, maxAmountIn);

        uint256 wethBalanceAfterSwap = wethToken.balanceOf(user);
        console.log("wethBalanceAfterSwap:", wethBalanceAfterSwap);

        assertEq(wethBalanceAfterSwap + amountIn, wethBalanceBeforeSwap);

        vm.stopPrank();
    }

    function test_swapOutput_wbtcToLinkSwap() public {
        vm.startPrank(user);

        uint256 maxAmountIn = 100000000;
        uint256 linkAmountOut;

        IUniswapV3ExchangeProvider.Pair memory pair = uniswapV3ExchangeProvider.getPair(
            UniswapV3ExchangeProviderConfig.WBTC, UniswapV3ExchangeProviderConfig.LINK
        );
        for (uint256 i = 0; i < pair.swaps.length; i++) {
            IUniswapV3ExchangeProvider.SwapParams memory swap = pair.swaps[i];
            linkAmountOut = uniswapV3TwapOracle.getAveragePrice(swap.tokenA, swap.tokenB, swap.poolFee, maxAmountIn);
        }

        uint256 wbtcBalanceBeforeSwap = wbtcToken.balanceOf(user);
        console.log("wbtcBalanceBeforeSwap:", wbtcBalanceBeforeSwap);

        TransferHelper.safeApprove(address(wbtcToken), address(uniswapV3ExchangeProvider), maxAmountIn);
        uint256 amountIn =
            uniswapV3ExchangeProvider.swapOutput(address(wbtcToken), address(linkToken), linkAmountOut, maxAmountIn);

        uint256 wbtcBalanceAfterSwap = wbtcToken.balanceOf(user);
        console.log("wbtcBalanceAfterSwap:", wbtcBalanceAfterSwap);

        assertEq(wbtcBalanceAfterSwap + amountIn, wbtcBalanceBeforeSwap);
        vm.stopPrank();
    }

    function test_zeroAmountInSwapInput() public {
        vm.startPrank(user);

        vm.expectRevert(IUniswapV3ExchangeProvider.AmountMustBeGreaterThanZero.selector);
        uniswapV3ExchangeProvider.swapInput(address(wethToken), address(usdtToken), 0);

        vm.stopPrank();
    }

    function test_zeroAmountOutSwapOutput() public {
        vm.startPrank(user);

        vm.expectRevert(IUniswapV3ExchangeProvider.AmountMustBeGreaterThanZero.selector);

        uniswapV3ExchangeProvider.swapOutput(address(wethToken), address(usdtToken), 0, 0);

        vm.stopPrank();
    }

    function test_invalidTokenPairSwapInput() public {
        vm.startPrank(user);

        address invalidToken1 = makeAddr("invalidToken1");
        address invalidToken2 = makeAddr("invalidToken2");

        vm.expectRevert(
            abi.encodeWithSelector(IUniswapV3ExchangeProvider.InvalidTokenPair.selector, invalidToken1, invalidToken2)
        );
        uniswapV3ExchangeProvider.swapInput(invalidToken1, invalidToken2, 1 ether);
    }

    function test_invalidTokenPairSwapOutput() public {
        vm.startPrank(user);

        address invalidToken1 = makeAddr("invalidToken1");
        address invalidToken2 = makeAddr("invalidToken2");

        vm.expectRevert(
            abi.encodeWithSelector(IUniswapV3ExchangeProvider.InvalidTokenPair.selector, invalidToken1, invalidToken2)
        );
        uniswapV3ExchangeProvider.swapOutput(invalidToken1, invalidToken2, 1 ether, 1 ether);

        vm.stopPrank();
    }

    function test_addPair_notOwner() public {
        address notOwner = makeAddr("notOwner");

        vm.startPrank(notOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));

        IUniswapV3ExchangeProvider.SwapParams[] memory swaps = new IUniswapV3ExchangeProvider.SwapParams[](1);
        swaps[0] = IUniswapV3ExchangeProvider.SwapParams({
            tokenA: UniswapV3ExchangeProviderConfig.WETH,
            tokenB: UniswapV3ExchangeProviderConfig.USDT,
            poolFee: UniswapV3ExchangeProviderConfig.WETH_USDT_FEE
        });

        uniswapV3ExchangeProvider.addPair(swaps, 0);

        vm.stopPrank();
    }

    function test_setPair_notOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        uniswapV3ExchangeProvider.setPair(address(wethToken), address(usdtToken), true);

        vm.stopPrank();
    }

    function test_setPair_activeTrue() public {
        vm.startPrank(user);

        uniswapV3ExchangeProvider.setPair(address(wethToken), address(usdtToken), true);
        bool active = uniswapV3ExchangeProvider.getPair(address(wethToken), address(usdtToken)).active;

        assertTrue(active);
        vm.stopPrank();
    }

    function test_setPair_activeFalse() public {
        vm.startPrank(user);

        bool active = uniswapV3ExchangeProvider.getPair(address(wethToken), address(usdtToken)).active;

        assertEq(active, true);

        uniswapV3ExchangeProvider.setPair(address(wethToken), address(usdtToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3ExchangeProvider.InvalidTokenPair.selector, address(wethToken), address(usdtToken)
            )
        );
        uniswapV3ExchangeProvider.getPair(address(wethToken), address(usdtToken)).active;

        vm.stopPrank();
    }

    function test_setPair_invalidTokenPair() public {
        vm.startPrank(user);

        address invalidToken1 = makeAddr("invalidToken1");
        address invalidToken2 = makeAddr("invalidToken2");

        vm.expectRevert(
            abi.encodeWithSelector(IUniswapV3ExchangeProvider.InvalidTokenPair.selector, invalidToken1, invalidToken2)
        );
        uniswapV3ExchangeProvider.setPair(invalidToken1, invalidToken2, true);

        vm.stopPrank();
    }
}
