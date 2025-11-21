// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract UniswapV3ExchangeProvider {
    error InvalidTokenPair();
    error AmountMustBeGreaterThanZero();
    error InvalidMultihopPath();

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    struct SinglehopPair {
        address tokenA;
        address tokenB;
    }

    struct MultihopPair {
        address tokenIn;
        address tokenOut;
        address[] intermediaryTokens;
    }

    ISwapRouter public swapRouter;
    uint24 public immutable POOL_FEE;
    uint256 private immutable _SLIPPAGE_TOLERANCE;
    uint256 private constant BASIS_POINTS = 10000;

    mapping(address => mapping(address => bool)) private validPairs;
    mapping(address => mapping(address => address[])) private multihopPairs;

    constructor(
        ISwapRouter _swapRouter,
        uint24 _poolFee,
        SinglehopPair[] memory _singlehopPairs,
        MultihopPair[] memory _multihopPairs,
        uint256 _slippageTolerance
    ) {
        swapRouter = _swapRouter;
        POOL_FEE = _poolFee;
        _SLIPPAGE_TOLERANCE = _slippageTolerance;

        // Initialize singlehop pairs
        for (uint256 i = 0; i < _singlehopPairs.length; i++) {
            address tokenA = _singlehopPairs[i].tokenA;
            address tokenB = _singlehopPairs[i].tokenB;

            validPairs[tokenA][tokenB] = true;
            validPairs[tokenB][tokenA] = true;
        }

        // Initialize multihop routes
        for (uint256 i = 0; i < _multihopPairs.length; i++) {
            address tokenIn = _multihopPairs[i].tokenIn;
            address tokenOut = _multihopPairs[i].tokenOut;
            address[] memory intermediaries = _multihopPairs[i].intermediaryTokens;

            if (intermediaries.length == 0) {
                revert InvalidMultihopPath();
            }

            validPairs[tokenIn][tokenOut] = true;
            validPairs[tokenOut][tokenIn] = true;

            multihopPairs[tokenIn][tokenOut] = intermediaries;

            address[] memory reverseIntermediaries = new address[](intermediaries.length);
            for (uint256 j = 0; j < intermediaries.length; j++) {
                reverseIntermediaries[j] = intermediaries[intermediaries.length - 1 - j];
            }
            multihopPairs[tokenOut][tokenIn] = reverseIntermediaries;
        }
    }

    function swapInput(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        public
        returns (uint256 amountOut)
    {
        if (!_isValidPair(tokenIn, tokenOut)) {
            revert InvalidTokenPair();
        }

        if (amountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);

        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        if (_needsMultihop(tokenIn, tokenOut)) {
            // Build path: tokenIn -> intermediary1 -> intermediary2 -> ... -> tokenOut
            bytes memory path = _buildPathForExactInput(tokenIn, tokenOut);

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut
            });

            amountOut = swapRouter.exactInput(params);
        } else {
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

            amountOut = swapRouter.exactInputSingle(params);
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    function swapOutput(address tokenIn, address tokenOut, uint256 amountOut, uint256 maxAmountIn)
        public
        returns (uint256 amountIn)
    {
        if (!_isValidPair(tokenIn, tokenOut)) {
            revert InvalidTokenPair();
        }

        if (amountOut == 0 || maxAmountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint256 maxAmountInWithSlippage = _applySlippageToMaxInput(maxAmountIn);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), maxAmountInWithSlippage);

        TransferHelper.safeApprove(tokenIn, address(swapRouter), maxAmountInWithSlippage);

        if (_needsMultihop(tokenIn, tokenOut)) {
            // Build reversed path for exactOutput: tokenOut -> intermediary1 -> ... -> tokenIn
            bytes memory path = _buildPathForExactOutput(tokenIn, tokenOut);

            ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: maxAmountInWithSlippage
            });

            amountIn = swapRouter.exactOutput(params);
        } else {
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: maxAmountInWithSlippage,
                sqrtPriceLimitX96: 0
            });

            amountIn = swapRouter.exactOutputSingle(params);
        }

        if (amountIn < maxAmountInWithSlippage) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, maxAmountInWithSlippage - amountIn);
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    function _applySlippageToMaxInput(uint256 amountIn) internal view returns (uint256) {
        return (amountIn * (BASIS_POINTS + _SLIPPAGE_TOLERANCE)) / BASIS_POINTS;
    }

    function _isValidPair(address tokenA, address tokenB) internal view returns (bool) {
        return validPairs[tokenA][tokenB];
    }

    function _needsMultihop(address tokenIn, address tokenOut) internal view returns (bool) {
        return multihopPairs[tokenIn][tokenOut].length > 0;
    }

    function _buildPathForExactInput(address tokenIn, address tokenOut) internal view returns (bytes memory) {
        address[] memory intermediaries = multihopPairs[tokenIn][tokenOut];

        bytes memory path = abi.encodePacked(tokenIn);

        for (uint256 i = 0; i < intermediaries.length; i++) {
            path = abi.encodePacked(path, POOL_FEE, intermediaries[i]);
        }

        path = abi.encodePacked(path, POOL_FEE, tokenOut);

        return path;
    }

    function _buildPathForExactOutput(address tokenIn, address tokenOut) internal view returns (bytes memory) {
        address[] memory intermediaries = multihopPairs[tokenIn][tokenOut];

        bytes memory path = abi.encodePacked(tokenOut);

        for (uint256 i = intermediaries.length; i > 0; i--) {
            path = abi.encodePacked(path, POOL_FEE, intermediaries[i - 1]);
        }

        path = abi.encodePacked(path, POOL_FEE, tokenIn);

        return path;
    }
}
