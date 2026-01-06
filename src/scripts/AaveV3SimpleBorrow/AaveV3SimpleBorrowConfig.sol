// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title AaveV3SimpleBorrowConfig
/// @notice Shared configuration for deploying the Aave V3 simple borrow contract.
library AaveV3SimpleBorrowConfig {
    address internal constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    /// @notice Returns the deployment configuration.
    /// @return poolAddressesProvider Aave V3 pool addresses provider.
    function getConfig() public pure returns (address poolAddressesProvider) {
        return POOL_ADDRESSES_PROVIDER;
    }
}
