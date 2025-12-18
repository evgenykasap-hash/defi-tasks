// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IUniswapV3TWAPOracle {
    error AmountMustBeGreaterThanZero();
    error UnsupportedPool(address poolAddress);
    error AmountTooLarge(uint256 amountIn);

    function getAveragePrice(address tokenA, address tokenB, uint24 poolFee, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);

    function checkIfPoolIsSupported(address poolAddress) external view returns (bool);

    function getPool(address poolAddress) external view returns (IUniswapV3Pool pool);

    function getPoolAddress(address tokenA, address tokenB, uint24 poolFee) external view returns (address);

    function setPool(address poolAddress, bool active) external;
}
