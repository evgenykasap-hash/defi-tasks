// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniswapV3ExchangeProvider} from "./UniswapV3ExchangeProvider.sol";

/// @title UniswapV3ExchangeProviderConfig
/// @notice Shared configuration for deployment and testing
/// @dev Pure library - works in scripts, tests, and anywhere else!
library UniswapV3ExchangeProviderConfig {
    // ============ Mainnet Constants ============

    address internal constant SWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24 internal constant POOL_FEE = 3000; // 0.3%
    uint256 internal constant SLIPPAGE_TOLERANCE = 50; // 0.5%

    // ============ Token Addresses ============

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    // ============ Pair Configuration ============

    /// @notice Get default singlehop pair configuration
    /// @dev Used by both deployment scripts and tests
    function getDefaultSinglehopPairs()
        internal
        pure
        returns (UniswapV3ExchangeProvider.SinglehopPair[] memory)
    {
        UniswapV3ExchangeProvider.SinglehopPair[]
            memory pairs = new UniswapV3ExchangeProvider.SinglehopPair[](3);

        pairs[0] = createSinglehopPair(WETH, USDC);
        pairs[1] = createSinglehopPair(LINK, USDC);
        pairs[2] = createSinglehopPair(WBTC, USDT);

        return pairs;
    }

    /// @notice Get default multihop pair configuration
    /// @dev Used by both deployment scripts and tests
    function getDefaultMultihopPairs()
        internal
        pure
        returns (UniswapV3ExchangeProvider.MultihopPair[] memory)
    {
        UniswapV3ExchangeProvider.MultihopPair[]
            memory pairs = new UniswapV3ExchangeProvider.MultihopPair[](2);

        // WETH -> LINK route through USDC
        address[] memory wethLinkPath = new address[](1);
        wethLinkPath[0] = USDC;

        pairs[0] = createMultihopPair(WETH, LINK, wethLinkPath);

        // WETH -> WBTC route through USDC -> USDT
        address[] memory wethWbtcPath = new address[](2);
        wethWbtcPath[0] = USDC;
        wethWbtcPath[1] = USDT;

        pairs[1] = createMultihopPair(WETH, WBTC, wethWbtcPath);

        return pairs;
    }

    // ============ Custom Configurations ============

    /// @notice Create a custom singlehop pair
    function createSinglehopPair(
        address tokenA,
        address tokenB
    ) internal pure returns (UniswapV3ExchangeProvider.SinglehopPair memory) {
        return
            UniswapV3ExchangeProvider.SinglehopPair({
                tokenA: tokenA,
                tokenB: tokenB
            });
    }

    /// @notice Create a custom multihop pair
    function createMultihopPair(
        address tokenIn,
        address tokenOut,
        address[] memory intermediaries
    ) internal pure returns (UniswapV3ExchangeProvider.MultihopPair memory) {
        return
            UniswapV3ExchangeProvider.MultihopPair({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                intermediaryTokens: intermediaries
            });
    }
}
