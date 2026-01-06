// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title CCTPAaveFastBridgeConfig
/// @notice Shared configuration for CCTP bridge deployments.
library CCTPAaveFastBridgeConfig {
    address internal constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address internal constant TOKEN_MESSENGER = 0xBd3fa81B58Ba92a82136038B25aDec7066af3155;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Returns the deployment configuration addresses.
    /// @return poolAddressesProvider Aave V3 pool addresses provider.
    /// @return tokenMessenger Circle CCTP TokenMessenger address.
    /// @return usdc USDC token address.
    function getConfig() public pure returns (address poolAddressesProvider, address tokenMessenger, address usdc) {
        return (POOL_ADDRESSES_PROVIDER, TOKEN_MESSENGER, USDC);
    }
}
