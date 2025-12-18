// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library AaveV3LendingProviderConfig {
    address internal constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI

    function getConfig() public pure returns (address, address, address, address) {
        return (POOL_ADDRESSES_PROVIDER, WETH, USDC, DAI);
    }
}
