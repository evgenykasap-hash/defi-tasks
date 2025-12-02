// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {UniswapV3TWAPOracle} from "../UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3ExchangeProvider} from "./IUniswapV3ExchangeProvider.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract UniswapV3ExchangeProvider is IUniswapV3ExchangeProvider, Ownable {
    ISwapRouter public swapRouter;
    uint256 private constant BASIS_POINTS = 10000;

    UniswapV3TWAPOracle public uniswapV3TwapOracle;
    /*
     * @dev Mapping of pair key to pair data.
     * @notice The pair key is a keccak256 hash of the token0 and token1 addresses.
     * @notice The pair data is a struct that contains the pair's swaps, token0, token1, pool fee, encoded path input, encoded path output, and slippage tolerance.
     */
    mapping(bytes32 => Pair) private validPairs;

    constructor(address _swapRouter, address _factory) Ownable(msg.sender) {
        swapRouter = ISwapRouter(_swapRouter);
        uniswapV3TwapOracle = new UniswapV3TWAPOracle(_factory);
    }

    function swapInput(address tokenIn, address tokenOut, uint256 amountIn) public returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        Pair memory pair = _getPair(tokenIn, tokenOut);

        bool isFirstToken = tokenIn == pair.swaps[0].tokenA;

        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);

        uint256 minAmountOut;
        uint256 poolAmountIn = amountIn;

        for (uint256 i = 0; i < pair.swaps.length; i++) {
            uint256 index = isFirstToken ? i : pair.swaps.length - i - 1;
            SwapParams memory swap = pair.swaps[index];

            address multihopTokenIn = isFirstToken ? swap.tokenA : swap.tokenB;
            address multihopTokenOut = isFirstToken ? swap.tokenB : swap.tokenA;

            uint256 poolAmountOut =
                uniswapV3TwapOracle.getAveragePrice(multihopTokenIn, multihopTokenOut, swap.poolFee, poolAmountIn);

            poolAmountIn = poolAmountOut;
            minAmountOut = poolAmountOut;
        }

        minAmountOut = _applySlippage(minAmountOut, pair.slippageTolerance);

        bytes memory path = isFirstToken ? pair.encodedPathInput : pair.encodedPathOutput;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        amountOut = swapRouter.exactInput(params);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    function swapOutput(address tokenIn, address tokenOut, uint256 amountOut, uint256 maxAmountIn)
        public
        returns (uint256 amountIn)
    {
        if (amountOut == 0 || maxAmountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        Pair memory pair = _getPair(tokenIn, tokenOut);

        bool isFirstToken = tokenIn == pair.swaps[0].tokenA;

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), maxAmountIn);

        TransferHelper.safeApprove(tokenIn, address(swapRouter), maxAmountIn);

        bytes memory path = isFirstToken ? pair.encodedPathOutput : pair.encodedPathInput;
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: maxAmountIn
        });

        amountIn = swapRouter.exactOutput(params);

        if (amountIn < maxAmountIn) {
            uint256 refundAmount = maxAmountIn - amountIn;
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, refundAmount);
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    function addPair(SwapParams[] calldata swaps, uint256 slippageTolerance) external onlyOwner {
        address token0 = swaps[0].tokenA;
        address token1 = swaps[swaps.length - 1].tokenB;

        bytes32 key = _generatePairKey(token0, token1);

        if (validPairs[key].encodedPathInput.length > 0) {
            revert PairAlreadyExists();
        }

        Pair storage pair = validPairs[key];

        bytes memory encodedPathInput = abi.encodePacked(token0);
        bytes memory encodedPathOutput = abi.encodePacked(token1);

        uint256 swapsCount = swaps.length;

        for (uint256 i = 0; i < swapsCount; i++) {
            SwapParams memory swap = swaps[i];
            SwapParams memory swapReverse = swaps[swapsCount - i - 1];

            address poolAddress = uniswapV3TwapOracle.getPoolAddress(swap.tokenA, swap.tokenB, swap.poolFee);

            if (!uniswapV3TwapOracle.checkIfPoolIsSupported(poolAddress)) {
                uniswapV3TwapOracle.setPool(poolAddress, true);
            }

            encodedPathInput = abi.encodePacked(encodedPathInput, swap.poolFee, swap.tokenB);
            encodedPathOutput = abi.encodePacked(encodedPathOutput, swapReverse.poolFee, swapReverse.tokenA);

            // can't copy the swaps array from memory to storage, so I need to push each swap individually
            pair.swaps.push(SwapParams({tokenA: swap.tokenA, tokenB: swap.tokenB, poolFee: swap.poolFee}));
        }

        pair.encodedPathInput = encodedPathInput;
        pair.encodedPathOutput = encodedPathOutput;
        pair.slippageTolerance = slippageTolerance;
        pair.active = true;
    }

    function setPair(address tokenIn, address tokenOut, bool active) external onlyOwner {
        bytes32 key = _generatePairKey(tokenIn, tokenOut);

        Pair memory pair = validPairs[key];

        if (pair.swaps.length == 0) {
            revert InvalidTokenPair(tokenIn, tokenOut);
        }

        validPairs[key].active = active;
    }

    function getPair(address tokenIn, address tokenOut) external view returns (Pair memory) {
        return _getPair(tokenIn, tokenOut);
    }

    function _applySlippage(uint256 amount, uint256 slippageTolerance) internal pure returns (uint256) {
        return (amount * (BASIS_POINTS - slippageTolerance)) / BASIS_POINTS;
    }

    function _getPair(address tokenIn, address tokenOut) internal view returns (Pair memory) {
        Pair memory pair = validPairs[_generatePairKey(tokenIn, tokenOut)];

        if (!pair.active) {
            pair = validPairs[_generatePairKey(tokenOut, tokenIn)];
            if (!pair.active) {
                revert InvalidTokenPair(tokenIn, tokenOut);
            }
        }

        return pair;
    }

    function _generatePairKey(address tokenIn, address tokenOut) internal pure returns (bytes32) {
        // forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }
}
