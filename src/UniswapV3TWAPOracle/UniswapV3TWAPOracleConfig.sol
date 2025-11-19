// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title UniswapV3TWAPOracleConfig
/// @notice Provides a curated list of Uniswap V3 pool addresses used by the TWAP oracle
library UniswapV3TWAPOracleConfig {
    // Mainnet pool addresses (3000 = 0.3% fee tier)
    address internal constant ETH_USDC =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;
    address internal constant ETH_USDT =
        0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address internal constant ETH_DAI =
        0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;

    /// @notice Returns the default pool allowlist for deployment/scripts
    function getDefaultPools() internal pure returns (address[] memory pools) {
        pools = new address[](3);
        pools[0] = ETH_USDC;
        pools[1] = ETH_USDT;
        pools[2] = ETH_DAI;
    }
}
