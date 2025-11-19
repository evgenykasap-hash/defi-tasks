// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {
    ISwapRouter
} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {UniswapV3ExchangeProvider} from "./UniswapV3ExchangeProvider.sol";
import {
    UniswapV3ExchangeProviderConfig
} from "./UniswapV3ExchangeProviderConfig.sol";

contract DeployUniswapV3ExchangeProvider is Script {
    function run() public {
        vm.startBroadcast();

        UniswapV3ExchangeProvider uniswapV3ExchangeProvider = new UniswapV3ExchangeProvider(
                ISwapRouter(UniswapV3ExchangeProviderConfig.SWAP_ROUTER),
                UniswapV3ExchangeProviderConfig.POOL_FEE,
                UniswapV3ExchangeProviderConfig.getDefaultSinglehopPairs(),
                UniswapV3ExchangeProviderConfig.getDefaultMultihopPairs(),
                UniswapV3ExchangeProviderConfig.SLIPPAGE_TOLERANCE
            );

        console.log(
            "UniswapV3ExchangeProvider deployed at:",
            address(uniswapV3ExchangeProvider)
        );
        console.log("SwapRouter:", UniswapV3ExchangeProviderConfig.SWAP_ROUTER);
        console.log("Pool Fee:", UniswapV3ExchangeProviderConfig.POOL_FEE);
        console.log(
            "Singlehop pairs configured:",
            UniswapV3ExchangeProviderConfig.getDefaultSinglehopPairs().length
        );
        console.log(
            "Multihop pairs configured:",
            UniswapV3ExchangeProviderConfig.getDefaultMultihopPairs().length
        );

        vm.stopBroadcast();
    }
}
