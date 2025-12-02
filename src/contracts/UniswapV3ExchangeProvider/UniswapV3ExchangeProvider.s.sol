// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV3ExchangeProvider} from "./UniswapV3ExchangeProvider.sol";
import {UniswapV3ExchangeProviderConfig} from "./UniswapV3ExchangeProviderConfig.sol";

contract DeployUniswapV3ExchangeProvider is Script {
    function run() public {
        vm.startBroadcast();

        UniswapV3ExchangeProvider uniswapV3ExchangeProvider = new UniswapV3ExchangeProvider(
            UniswapV3ExchangeProviderConfig.SWAP_ROUTER, UniswapV3ExchangeProviderConfig.UNISWAP_V3_FACTORY
        );

        console.log("UniswapV3ExchangeProvider deployed at:", address(uniswapV3ExchangeProvider));
        console.log("SwapRouter:", UniswapV3ExchangeProviderConfig.SWAP_ROUTER);

        vm.stopBroadcast();
    }
}
