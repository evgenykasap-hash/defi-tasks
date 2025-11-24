// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {
    OracleLibrary
} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IERC20Extended} from "../libraries/IERC20Extended.sol";

interface IUniswapV3TWAPOracle {
    error IntervalMustBeGreaterThanZero();
    error AmountMustBeGreaterThanZero();
    error PoolArrayCannotBeEmpty();
    error UnsupportedPool(address pool);
    error NotOwner();

    function getAveragePrice(
        address poolAddress,
        uint256 amountIn,
        uint32 twapInterval
    ) external view returns (uint256 amountOut);

    function checkIfPoolIsSupported(
        address poolAddress
    ) external view returns (bool);

    function addPool(address poolAddress) external;
    function removePool(address poolAddress) external;
}

contract UniswapV3TWAPOracle is IUniswapV3TWAPOracle {
    mapping(address => bool) public supportedPools;
    address public owner;

    modifier _onlyOwner() {
        if (msg.sender != address(owner)) {
            revert NotOwner();
        }
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function getAveragePrice(
        address poolAddress,
        uint256 amountIn,
        uint32 twapInterval
    ) external view returns (uint256 amountOut) {
        if (!supportedPools[poolAddress]) {
            revert UnsupportedPool(poolAddress);
        }

        if (twapInterval == 0) {
            revert IntervalMustBeGreaterThanZero();
        }

        if (amountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            poolAddress,
            twapInterval
        );

        amountOut = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(amountIn),
            IUniswapV3Pool(poolAddress).token0(),
            IUniswapV3Pool(poolAddress).token1()
        );
    }

    function checkIfPoolIsSupported(
        address poolAddress
    ) external view returns (bool) {
        return supportedPools[poolAddress];
    }

    function addPool(address poolAddress) external _onlyOwner {
        supportedPools[poolAddress] = true;
    }

    function removePool(address poolAddress) external _onlyOwner {
        supportedPools[poolAddress] = false;
    }
}
