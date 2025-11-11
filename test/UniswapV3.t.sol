// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {UniswapV3} from "../src/UniswapV3.sol";

contract UniswapV3Test is Test {
    UniswapV3 public uniswapV3;

    function setUp() public {
        uniswapV3 = new UniswapV3();
    }
}
