// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {
    ISwapRouter
} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {
    TransferHelper
} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {
    UniswapV3TWAPOracle
} from "../UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol";
import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IUniswapV3ExchangeProvider {
    error InvalidTokenPair();
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
        address poolAddress;
        address tokenA;
        address tokenB;
    }

    struct Pair {
        /* Swaps sequence for single/multi-hop swaps.
         * Input token (tokenA), output token (tokenB) and their pool address.
         * For example, we can have a pool DAI/USDC,
         * but we want to change USDC to DAI, so we need to keep the sequence as USDC -> DAI and
         * give it to the TWAP provider for a proper price calculation.
         */
        SwapParams[] swaps;
        address token0;
        address token1;
        uint24 poolFee;
        bytes encodedPathInput;
        bytes encodedPathOutput;
        uint256 slippageTolerance;
    }

    function swapInput(
        bytes32 pairKey,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut);

    function swapOutput(
        bytes32 pairKey,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn
    ) external returns (uint256 amountIn);

    function addPair(
        SwapParams[] calldata swaps,
        uint24 poolFee,
        uint256 slippageTolerance
    ) external;
}

contract UniswapV3ExchangeProvider is IUniswapV3ExchangeProvider {
    ISwapRouter public swapRouter;
    uint256 private constant BASIS_POINTS = 10000;

    UniswapV3TWAPOracle public uniswapV3TWAPOracle;

    /*
     * @dev Mapping of pair key to pair data.
     * @notice The pair key is a keccak256 hash of the token0 and token1 addresses.
     * @notice The pair data is a struct that contains the pair's swaps, token0, token1, pool fee, encoded path input, encoded path output, and slippage tolerance.
     */
    mapping(bytes32 => Pair) private validPairs;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
        uniswapV3TWAPOracle = new UniswapV3TWAPOracle();
    }

    function swapInput(
        bytes32 pairKey,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        public
        _validPair(pairKey, tokenIn, tokenOut)
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        Pair memory pair = validPairs[pairKey];

        bool isFirstToken = tokenIn == pair.token0;

        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            amountIn
        );

        if (pair.swaps.length > 1) {
            uint256 minAmountOut;
            uint256 poolAmountIn = amountIn;

            for (uint256 i = 0; i < pair.swaps.length; i++) {
                uint256 index = isFirstToken ? i : pair.swaps.length - i - 1;
                address multihopTokenIn = isFirstToken
                    ? pair.swaps[index].tokenA
                    : pair.swaps[index].tokenB;
                address multihopTokenOut = isFirstToken
                    ? pair.swaps[index].tokenB
                    : pair.swaps[index].tokenA;

                uint256 poolAmountOut = uniswapV3TWAPOracle.getAveragePrice(
                    pair.swaps[index].poolAddress,
                    multihopTokenIn,
                    multihopTokenOut,
                    poolAmountIn,
                    5 minutes
                );

                poolAmountIn = poolAmountOut;
                minAmountOut = poolAmountOut;
            }

            minAmountOut = _applySlippage(minAmountOut, pair.slippageTolerance);

            bytes memory path = isFirstToken
                ? pair.encodedPathInput
                : pair.encodedPathOutput;

            ISwapRouter.ExactInputParams memory params = ISwapRouter
                .ExactInputParams({
                    path: path,
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut
                });

            amountOut = swapRouter.exactInput(params);
        } else {
            uint256 minAmountOut = uniswapV3TWAPOracle.getAveragePrice(
                pair.swaps[0].poolAddress,
                tokenIn,
                tokenOut,
                amountIn,
                5 minutes
            );

            minAmountOut = _applySlippage(minAmountOut, pair.slippageTolerance);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: pair.poolFee,
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

    function swapOutput(
        bytes32 pairKey,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn
    ) public _validPair(pairKey, tokenIn, tokenOut) returns (uint256 amountIn) {
        if (amountOut == 0 || maxAmountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        Pair memory pair = validPairs[pairKey];

        bool isFirstToken = tokenIn == pair.token0;

        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            maxAmountIn
        );

        TransferHelper.safeApprove(tokenIn, address(swapRouter), maxAmountIn);

        if (pair.swaps.length > 1) {
            bytes memory path = isFirstToken
                ? pair.encodedPathOutput
                : pair.encodedPathInput;
            ISwapRouter.ExactOutputParams memory params = ISwapRouter
                .ExactOutputParams({
                    path: path,
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: maxAmountIn
                });

            amountIn = swapRouter.exactOutput(params);
        } else {
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
                .ExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: pair.poolFee,
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: maxAmountIn,
                    sqrtPriceLimitX96: 0
                });

            amountIn = swapRouter.exactOutputSingle(params);
        }

        if (amountIn < maxAmountIn) {
            uint256 refundAmount = maxAmountIn - amountIn;
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, refundAmount);
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    function addPair(
        SwapParams[] calldata swaps,
        uint24 poolFee,
        uint256 slippageTolerance
    ) external {
        bytes memory encodedPathInput;
        bytes memory encodedPathOutput;

        address token0;
        address token1;

        if (swaps.length > 1) {
            token0 = swaps[0].tokenA;
            token1 = swaps[swaps.length - 1].tokenB;

            encodedPathInput = abi.encodePacked(token0);
            encodedPathOutput = abi.encodePacked(token1);
            //WBTC/USDT -> USDT/DAI
            for (uint256 i = 0; i < swaps.length; i++) {
                if (
                    !uniswapV3TWAPOracle.checkIfPoolIsSupported(
                        swaps[i].poolAddress
                    )
                ) {
                    uniswapV3TWAPOracle.addPool(swaps[i].poolAddress);
                }

                encodedPathInput = abi.encodePacked(
                    encodedPathInput,
                    poolFee,
                    swaps[i].tokenB
                );
                encodedPathOutput = abi.encodePacked(
                    encodedPathOutput,
                    poolFee,
                    swaps[swaps.length - i - 1].tokenA
                );
            }
        } else {
            if (
                !uniswapV3TWAPOracle.checkIfPoolIsSupported(
                    swaps[0].poolAddress
                )
            ) {
                uniswapV3TWAPOracle.addPool(swaps[0].poolAddress);
            }

            token0 = swaps[0].tokenA;
            token1 = swaps[0].tokenB;
            encodedPathInput = abi.encodePacked(token0, poolFee, token1);
            encodedPathOutput = abi.encodePacked(token1, poolFee, token0);
        }

        bytes32 key = keccak256(abi.encodePacked(token0, token1));

        if (validPairs[key].encodedPathInput.length > 0) {
            revert PairAlreadyExists();
        }

        Pair storage pair = validPairs[key];

        pair.poolFee = poolFee;
        pair.token0 = token0;
        pair.token1 = token1;
        pair.encodedPathInput = encodedPathInput;
        pair.encodedPathOutput = encodedPathOutput;
        pair.slippageTolerance = slippageTolerance;

        // can't copy the swaps array from memory to storage, so I need to push each swap individually
        for (uint256 i = 0; i < swaps.length; i++) {
            pair.swaps.push(
                SwapParams({
                    poolAddress: swaps[i].poolAddress,
                    tokenA: swaps[i].tokenA,
                    tokenB: swaps[i].tokenB
                })
            );
        }
    }

    function getPair(bytes32 pairKey) external view returns (Pair memory) {
        return validPairs[pairKey];
    }

    function _applySlippage(
        uint256 amount,
        uint256 slippageTolerance
    ) internal pure returns (uint256) {
        return (amount * (BASIS_POINTS - slippageTolerance)) / BASIS_POINTS;
    }

    function _isValidPair(
        bytes32 pairKey,
        address tokenIn,
        address tokenOut
    ) internal view {
        bool isValid = (validPairs[pairKey].token0 == tokenIn &&
            validPairs[pairKey].token1 == tokenOut) ||
            (validPairs[pairKey].token0 == tokenOut &&
                validPairs[pairKey].token1 == tokenIn);

        if (!isValid) {
            revert InvalidTokenPair();
        }
    }

    modifier _validPair(bytes32 pairKey, address tokenIn, address tokenOut) {
        _isValidPair(pairKey, tokenIn, tokenOut);
        _;
    }
}
