// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUniswapV3ExchangeProvider {
    error InvalidTokenPair(address tokenIn, address tokenOut);
    error PairAlreadyExists();
    error AmountMustBeGreaterThanZero();

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    struct SwapParams {
        address tokenA;
        address tokenB;
        uint24 poolFee;
    }

    struct Pair {
        /* Swaps sequence for single/multi-hop swaps.
         * Input token (tokenA), output token (tokenB) and their pool address.
         * For example, we can have a pool DAI/USDC,
         * but we want to change USDC to DAI, so we need to keep the sequence as USDC -> DAI and
         * give it to the TWAP provider for a proper price calculation.
         */
        SwapParams[] swaps;
        bytes encodedPathInput;
        bytes encodedPathOutput;
        uint256 slippageTolerance;
        bool active;
    }

    function swapInput(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);

    function swapOutput(address tokenIn, address tokenOut, uint256 amountOut, uint256 maxAmountIn)
        external
        returns (uint256 amountIn);

    function addPair(SwapParams[] calldata swaps, uint256 slippageTolerance) external;
}
