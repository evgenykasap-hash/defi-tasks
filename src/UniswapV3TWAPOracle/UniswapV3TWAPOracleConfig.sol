// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title UniswapV3TWAPOracleConfig
/// @notice Provides a curated list of Uniswap V3 pool addresses used by the TWAP oracle
library UniswapV3TWAPOracleConfig {
    // Mainnet pool addresses (3000 = 0.3% fee tier)
    address internal constant ETH_USDT =
        0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address internal constant ETH_DAI =
        0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @notice Returns the default pool allowlist for deployment/scripts
    function getDefaultPools() internal pure returns (address[] memory pools) {
        pools = new address[](2);
        pools[0] = ETH_USDT;
        pools[1] = ETH_DAI;
    }
}
