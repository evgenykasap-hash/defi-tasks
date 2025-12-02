// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3TWAPOracle} from "./IUniswapV3TWAPOracle.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract UniswapV3TWAPOracle is IUniswapV3TWAPOracle, Ownable {
    uint32 private constant TWAP_INTERVAL = 5 minutes;
    mapping(address => bool) private supportedPools;
    IUniswapV3Factory private immutable FACTORY;

    constructor(address _factory) Ownable(msg.sender) {
        FACTORY = IUniswapV3Factory(_factory);
    }

    function getAveragePrice(address tokenA, address tokenB, uint24 poolFee, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (amountIn > type(uint128).max) {
            revert AmountTooLarge(amountIn);
        }
        address poolAddress = _getPoolAddress(tokenA, tokenB, poolFee);

        if (!supportedPools[poolAddress]) {
            revert UnsupportedPool(poolAddress);
        }

        if (amountIn == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        (int24 arithmeticMeanTick,) = OracleLibrary.consult(poolAddress, TWAP_INTERVAL);

        // casting to uint128 is safe due to explicit bound check above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountIn128 = uint128(amountIn);
        amountOut = OracleLibrary.getQuoteAtTick(arithmeticMeanTick, amountIn128, tokenA, tokenB);
    }

    function checkIfPoolIsSupported(address poolAddress) external view returns (bool) {
        return supportedPools[poolAddress];
    }

    function setPool(address poolAddress, bool active) external onlyOwner {
        supportedPools[poolAddress] = active;
    }

    function getPoolAddress(address tokenA, address tokenB, uint24 poolFee) external view returns (address) {
        return _getPoolAddress(tokenA, tokenB, poolFee);
    }

    function getPool(address poolAddress) external view _supportedPool(poolAddress) returns (IUniswapV3Pool pool) {
        pool = IUniswapV3Pool(poolAddress);
    }

    function _getPoolAddress(address tokenA, address tokenB, uint24 poolFee) internal view returns (address) {
        return FACTORY.getPool(tokenA, tokenB, poolFee);
    }

    modifier _supportedPool(address poolAddress) {
        __supportedPool(poolAddress);
        _;
    }

    function __supportedPool(address poolAddress) internal view {
        if (!supportedPools[poolAddress]) {
            revert UnsupportedPool(poolAddress);
        }
    }
}
