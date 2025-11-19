// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "../libraries/FullMath.sol";
import {TickMath} from "../libraries/TickMath.sol";

contract UniswapV3TWAPOracle {
    error AmountMustBeGreaterThanZero();
    error PoolArrayCannotBeEmpty();
    error UnsupportedPool(address pool);

    mapping(address => bool) public supportedPools;

    constructor(address[] memory pools) {
        if (pools.length == 0) {
            revert PoolArrayCannotBeEmpty();
        }

        for (uint256 i = 0; i < pools.length; i++) {
            supportedPools[pools[i]] = true;
        }
    }

    function getAveragePrice(
        address poolAddress,
        uint32 twapInterval
    ) external view returns (uint256 amountOut) {
        if (!supportedPools[poolAddress]) {
            revert UnsupportedPool(poolAddress);
        }

        if (twapInterval == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0;

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        int56 interval = int56(uint56(twapInterval));
        int56 meanTick = tickCumulativeDelta / interval;

        if (tickCumulativeDelta < 0 && (tickCumulativeDelta % interval != 0)) {
            meanTick--;
        }

        amountOut = _getQuoteAtTick(
            int24(meanTick),
            1 << 96,
            pool.token0(),
            pool.token1()
        );
    }

    function _getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
