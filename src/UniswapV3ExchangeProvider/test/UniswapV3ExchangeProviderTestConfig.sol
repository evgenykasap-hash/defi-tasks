// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Extended} from "../../libraries/IERC20Extended.sol";
import {UniswapV3ExchangeProviderConfig} from "../UniswapV3ExchangeProviderConfig.sol";
import {UniswapV3ExchangeProvider} from "../UniswapV3ExchangeProvider.sol";

/// @title UniswapV3ExchangeProviderTestConfig
/// @notice Test-specific helpers extending base Config
/// @dev Adds token interfaces and test utilities on top of Config
library UniswapV3ExchangeProviderTestConfig {
    // Re-export Config constants for convenience in tests
    address internal constant SWAP_ROUTER = UniswapV3ExchangeProviderConfig.SWAP_ROUTER;
    uint24 internal constant POOL_FEE = UniswapV3ExchangeProviderConfig.POOL_FEE;
    uint256 internal constant SLIPPAGE_TOLERANCE = UniswapV3ExchangeProviderConfig.SLIPPAGE_TOLERANCE;

    address internal constant WETH = UniswapV3ExchangeProviderConfig.WETH;
    address internal constant USDC = UniswapV3ExchangeProviderConfig.USDC;
    address internal constant USDT = UniswapV3ExchangeProviderConfig.USDT;
    address internal constant WBTC = UniswapV3ExchangeProviderConfig.WBTC;
    address internal constant LINK = UniswapV3ExchangeProviderConfig.LINK;

    // ============ Token Decimals (Test-specific) ============

    uint8 internal constant WETH_DECIMALS = 18;
    uint8 internal constant USDC_DECIMALS = 6;
    uint8 internal constant USDT_DECIMALS = 6;
    uint8 internal constant WBTC_DECIMALS = 8;
    uint8 internal constant LINK_DECIMALS = 18;

    // ============ Token Interface Helpers (Test-specific) ============

    /// @notice Get WETH token interface
    function weth() internal pure returns (IERC20Extended) {
        return IERC20Extended(WETH);
    }

    /// @notice Get USDC token interface
    function usdc() internal pure returns (IERC20Extended) {
        return IERC20Extended(USDC);
    }

    /// @notice Get USDT token interface
    function usdt() internal pure returns (IERC20Extended) {
        return IERC20Extended(USDT);
    }

    /// @notice Get WBTC token interface
    function wbtc() internal pure returns (IERC20Extended) {
        return IERC20Extended(WBTC);
    }

    /// @notice Get LINK token interface
    function link() internal pure returns (IERC20Extended) {
        return IERC20Extended(LINK);
    }

    // ============ Pair Configuration (Delegated to Config) ============

    /// @notice Get singlehop pair configuration
    function getSinglehopPairs() internal pure returns (UniswapV3ExchangeProvider.SinglehopPair[] memory) {
        return UniswapV3ExchangeProviderConfig.getDefaultSinglehopPairs();
    }

    /// @notice Get multihop pair configuration
    function getMultihopPairs() internal pure returns (UniswapV3ExchangeProvider.MultihopPair[] memory) {
        return UniswapV3ExchangeProviderConfig.getDefaultMultihopPairs();
    }

    // ============ Test Utilities ============

    /// @notice Convert human-readable amount to raw token amount
    /// @param amount Human-readable amount (e.g., 1.5)
    /// @param decimals Token decimals
    function toRaw(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return amount * (10 ** decimals);
    }

    /// @notice Convert raw token amount to human-readable amount
    /// @param rawAmount Raw token amount
    /// @param decimals Token decimals
    function fromRaw(uint256 rawAmount, uint8 decimals) internal pure returns (uint256) {
        return rawAmount / (10 ** decimals);
    }
}
