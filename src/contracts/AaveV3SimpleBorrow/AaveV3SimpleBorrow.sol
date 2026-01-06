// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPool} from "@aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {IAaveV3SimpleBorrow} from "./interfaces/IAaveV3SimpleBorrow.sol";

/// @title AaveV3SimpleBorrow
/// @notice Supplies collateral and borrows assets directly via Aave V3.
contract AaveV3SimpleBorrow is IAaveV3SimpleBorrow {
    uint256 private constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);

    IPoolAddressesProvider public addressesProvider;
    IPool public pool;

    /// @notice Initializes the contract with an Aave V3 pool addresses provider.
    /// @param _poolAddressesProvider The pool addresses provider address.
    constructor(address _poolAddressesProvider) {
        if (_poolAddressesProvider == address(0)) {
            revert InvalidAddress();
        }

        addressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(addressesProvider.getPool());
    }

    /// @notice Supplies collateral on behalf of the caller.
    /// @param asset The underlying asset to supply.
    /// @param amount The amount to supply.
    /// @param referralCode Aave referral code (usually `0`).
    function supply(address asset, uint256 amount, uint16 referralCode) external override {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        TransferHelper.safeTransferFrom(asset, msg.sender, address(this), amount);
        TransferHelper.safeApprove(asset, address(pool), 0);
        TransferHelper.safeApprove(asset, address(pool), amount);

        pool.supply(asset, amount, address(this), referralCode);

        emit Supplied(msg.sender, asset, amount, referralCode);
    }

    /// @notice Borrows an asset against the caller's Aave collateral.
    /// @param asset The asset to borrow.
    /// @param amount The amount to borrow.
    /// @param referralCode Aave referral code (usually `0`).
    function borrow(address asset, uint256 amount, uint16 referralCode) external override {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        pool.borrow(asset, amount, INTEREST_RATE_MODE, referralCode, address(this));

        TransferHelper.safeTransfer(asset, msg.sender, amount);

        emit Borrowed(msg.sender, asset, amount, referralCode);
    }
}
