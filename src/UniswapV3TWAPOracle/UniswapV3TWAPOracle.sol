// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {
    OracleLibrary
} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IUniswapV3TWAPOracle {
    error IntervalMustBeGreaterThanZero();
    error AmountMustBeGreaterThanZero();
    error UnsupportedPool(address pool);
    error NotOwner();

    struct Pool {
        address tokenA;
        address tokenB;
    }

    function getAveragePrice(
        address poolAddress,
        address tokenA,
        address tokenB,
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
    mapping(address => Pool) public supportedPools;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function getAveragePrice(
        address poolAddress,
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint32 twapInterval
    )
        external
        view
        _supportedPool(poolAddress, tokenA, tokenB)
        returns (uint256 amountOut)
    {
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
            tokenA,
            tokenB
        );
    }

    function checkIfPoolIsSupported(
        address poolAddress
    ) external view returns (bool) {
        return
            supportedPools[poolAddress].tokenA != address(0) &&
            supportedPools[poolAddress].tokenB != address(0);
    }

    function addPool(address poolAddress) external _onlyOwner {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address tokenA = pool.token0();
        address tokenB = pool.token1();

        supportedPools[poolAddress] = Pool({tokenA: tokenA, tokenB: tokenB});
    }

    function removePool(address poolAddress) external _onlyOwner {
        delete supportedPools[poolAddress];
    }

    function getPool(
        address poolAddress
    ) external pure returns (IUniswapV3Pool pool) {
        pool = IUniswapV3Pool(poolAddress);
    }

    modifier _onlyOwner() {
        if (msg.sender != address(owner)) {
            revert NotOwner();
        }
        _;
    }

    modifier _supportedPool(
        address poolAddress,
        address tokenA,
        address tokenB
    ) {
        bool isValid = (supportedPools[poolAddress].tokenA == tokenA &&
            supportedPools[poolAddress].tokenB == tokenB) ||
            (supportedPools[poolAddress].tokenA == tokenB &&
                supportedPools[poolAddress].tokenB == tokenA);

        if (!isValid) {
            revert UnsupportedPool(poolAddress);
        }
        _;
    }
}
