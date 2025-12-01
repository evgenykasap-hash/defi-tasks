// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUniswapV3ExchangeProvider} from "./UniswapV3ExchangeProvider.sol";

/// @title UniswapV3ExchangeProviderConfig
/// @notice Shared configuration for deployment and testing
/// @dev Pure library - works in scripts, tests, and anywhere else!
library UniswapV3ExchangeProviderConfig {
    // ============ Mainnet Constants ============

    address internal constant SWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // ============ Token Addresses ============

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    // ============ Pools ============
    address internal constant WETH_USDT =
        0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address internal constant WBTC_WETH =
        0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
    address internal constant WBTC_USDT =
        0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35;
    address internal constant LINK_WETH =
        0xa6Cc3C2531FdaA6Ae1A3CA84c2855806728693e8;

    // ============ Fees ============
    uint24 internal constant WETH_USDT_FEE = 3000;
    uint24 internal constant WBTC_USDT_FEE = 3000;
    uint24 internal constant LINK_WETH_FEE = 3000;
    uint24 internal constant WBTC_LINK_FEE = 3000;

    uint24 internal constant WBTC_LINK_SLIPPAGE_TOLERANCE = 100;
    uint24 internal constant WETH_USDT_SLIPPAGE_TOLERANCE = 500;
    uint24 internal constant WBTC_USDT_SLIPPAGE_TOLERANCE = 500;
    uint24 internal constant LINK_WETH_SLIPPAGE_TOLERANCE = 50;
}
