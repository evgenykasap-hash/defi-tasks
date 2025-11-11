// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UniswapV3} from "../src/UniswapV3.sol";

contract CounterScript is Script {
    UniswapV3 public uniswapV3;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        uniswapV3 = new UniswapV3();

        vm.stopBroadcast();
    }
}
