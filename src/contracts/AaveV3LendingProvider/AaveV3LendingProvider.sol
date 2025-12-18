// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPool} from "@aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {IPriceOracle} from "@aave-v3-origin/src/contracts/interfaces/IPriceOracle.sol";
import {UserConfiguration} from "@aave-v3-origin/src/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {
    ReserveConfiguration
} from "@aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {GenericLogic} from "@aave-v3-origin/src/contracts/protocol/libraries/logic/GenericLogic.sol";
import {WadRayMath} from "@aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "@aave-v3-origin/src/contracts/protocol/libraries/math/PercentageMath.sol";
import {IAaveV3LendingProvider} from "./interfaces/IAaveV3LendingProvider.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title AaveV3LendingProvider
/// @notice Thin wrapper around the Aave V3 `IPool` that tracks per-user positions internally.
/// @dev The provider supplies/borrows on Aave from this contract address, while users interact with this wrapper.
contract AaveV3LendingProvider is IAaveV3LendingProvider, Ownable {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    uint256 private constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);
    uint8 private constant E_MODE_DISABLED = 0;

    IPoolAddressesProvider public addressesProvider;
    IPool public pool;
    IPriceOracle public priceOracle;

    mapping(address => UserData) private usersData;
    mapping(address => bool) public supportedTokens;

    /// @dev Restricts actions to assets that are enabled via `addSupportedToken`.
    modifier onlySupportedToken(address token) {
        _onlySupportedToken(token);
        _;
    }

    constructor(address _poolAddressesProvider) Ownable(msg.sender) {
        addressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(addressesProvider.getPool());
        priceOracle = IPriceOracle(addressesProvider.getPriceOracle());
    }

    /// @notice Supplies `_amount` of `_asset` into Aave V3.
    /// @dev Transfers tokens from the caller, supplies from this contract to Aave, and tracks the position in scaled
    /// units using Aave's normalized income index.
    /// @param _asset The underlying ERC20 asset to supply.
    /// @param _amount The amount of `_asset` to supply.
    /// @param _referralCode Aave referral code (usually `0`).
    function supply(address _asset, uint256 _amount, uint16 _referralCode)
        external
        override
        onlySupportedToken(_asset)
    {
        if (_amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        TransferHelper.safeTransferFrom(_asset, msg.sender, address(this), _amount);

        TransferHelper.safeApprove(_asset, address(pool), 0);
        TransferHelper.safeApprove(_asset, address(pool), _amount);

        pool.supply(_asset, _amount, address(this), _referralCode);

        uint256 liquidityIndex = pool.getReserveNormalizedIncome(_asset);
        uint256 scaledAmount = _amount.rayDiv(liquidityIndex);
        SupportedToken storage tokenData = _initializeUserToken(msg.sender, _asset);
        tokenData.suppliedScaled += scaledAmount;
    }

    /// @notice Withdraws `_amount` of `_asset` from Aave V3 back to the caller.
    /// @dev Enforces a conservative max-withdrawable check based on the caller's current collateral and debt, then
    /// withdraws from Aave to this contract and forwards the funds to the caller.
    /// @param _asset The underlying ERC20 asset to withdraw.
    /// @param _amount The amount requested to withdraw.
    /// @return withdrawAmount The actual amount withdrawn by Aave.
    function withdraw(address _asset, uint256 _amount)
        external
        onlySupportedToken(_asset)
        returns (uint256 withdrawAmount)
    {
        if (_amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint256 userBalance = getUserSuppliedBalance(msg.sender, _asset);

        if (userBalance == 0) {
            revert InsufficientCollateral();
        }

        (uint256 totalCollateralInBase, uint256 totalDebtInBase, uint256 ltv,,) = _getUserData(msg.sender);

        uint256 maxWithdrawableBase = _calculateWithdrawableBase(totalCollateralInBase, totalDebtInBase, ltv);

        uint256 amountToBase = _amountToBase(_asset, _amount);

        if (amountToBase > maxWithdrawableBase) {
            revert InsufficientWithdrawableAmount(amountToBase);
        }

        TransferHelper.safeApprove(_asset, address(pool), 0);
        TransferHelper.safeApprove(_asset, address(pool), _amount);

        withdrawAmount = pool.withdraw(_asset, _amount, address(this));

        uint256 liquidityIndex = pool.getReserveNormalizedIncome(_asset);
        uint256 scaledReduction = withdrawAmount.rayDiv(liquidityIndex);

        SupportedToken storage tokenData = usersData[msg.sender].supportedTokens[_asset];
        uint256 currentScaled = tokenData.suppliedScaled;
        tokenData.suppliedScaled = scaledReduction >= currentScaled ? 0 : currentScaled - scaledReduction;

        TransferHelper.safeTransfer(_asset, msg.sender, withdrawAmount);
    }

    /// @notice Borrows `_amount` of `_asset` from Aave V3 and sends it to the caller.
    /// @dev Uses the caller's supplied collateral tracked in this contract to validate that the requested borrow is
    /// within the available borrow capacity. Borrowing happens from this contract address.
    /// @param _asset The underlying ERC20 asset to borrow.
    /// @param _amount The amount of `_asset` to borrow.
    /// @param _referralCode Aave referral code (usually `0`).
    function borrow(address _asset, uint256 _amount, uint16 _referralCode)
        external
        override
        onlySupportedToken(_asset)
    {
        if (_amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        (uint256 totalCollateralInBase, uint256 totalDebtInBase, uint256 ltv,, uint256 healthFactor) =
            _getUserData(msg.sender);

        if (totalCollateralInBase == 0) {
            revert InsufficientCollateral();
        }

        if (healthFactor < 1e18) {
            revert InsufficientHealthFactor(healthFactor);
        }

        uint256 amountToBase = _amountToBase(_asset, _amount);

        uint256 maxAvailableBorrowAmount =
            GenericLogic.calculateAvailableBorrows(totalCollateralInBase, totalDebtInBase, ltv);

        if (amountToBase > maxAvailableBorrowAmount) {
            revert InsufficientAvailableBorrows(_amount);
        }

        pool.borrow(_asset, _amount, INTEREST_RATE_MODE, _referralCode, address(this));

        TransferHelper.safeTransfer(_asset, msg.sender, _amount);

        uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(_asset);
        uint256 scaledBorrow = _amount.rayDiv(borrowIndex);
        SupportedToken storage tokenData = _initializeUserToken(msg.sender, _asset);
        tokenData.borrowedScaled += scaledBorrow;
    }

    /// @notice Repays `_amount` of `_asset` debt on Aave V3 for the caller.
    /// @dev Transfers funds from the caller, repays up to the outstanding debt, refunds any excess, and updates the
    /// stored scaled debt based on the amount actually repaid by Aave.
    /// @param _asset The underlying ERC20 asset to repay.
    /// @param _amount The amount the caller wants to repay.
    /// @return repayAmount The amount actually repaid by Aave.
    function repay(address _asset, uint256 _amount) external onlySupportedToken(_asset) returns (uint256 repayAmount) {
        if (_amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint256 userDebt = getUserBorrowedBalance(msg.sender, _asset);
        if (userDebt == 0) {
            revert InsufficientBalance();
        }

        uint256 amountToRepay = _amount > userDebt ? userDebt : _amount;

        TransferHelper.safeTransferFrom(_asset, msg.sender, address(this), amountToRepay);

        TransferHelper.safeApprove(_asset, address(pool), 0);
        TransferHelper.safeApprove(_asset, address(pool), amountToRepay);

        uint256 repaidAmount = pool.repay(_asset, amountToRepay, INTEREST_RATE_MODE, address(this));

        if (amountToRepay > repaidAmount) {
            TransferHelper.safeTransfer(_asset, msg.sender, amountToRepay - repaidAmount);
        }

        uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(_asset);
        uint256 scaledReduction = repaidAmount.rayDiv(borrowIndex);

        SupportedToken storage tokenData = usersData[msg.sender].supportedTokens[_asset];
        uint256 currentScaled = tokenData.borrowedScaled;
        tokenData.borrowedScaled = scaledReduction >= currentScaled ? 0 : currentScaled - scaledReduction;
        repayAmount = repaidAmount;
        return repayAmount;
    }

    /// @notice Computes the caller's totals on Aave in the market base currency.
    /// @dev Uses Aave's `IPriceOracle` and reserve configuration to calculate:
    /// - total collateral (only assets enabled as collateral and with non-zero liquidation threshold)
    /// - total debt
    /// - average LTV and liquidation threshold across collateral
    /// - health factor derived from liquidation threshold vs debt
    /// @param _user The user whose internal balances are used to compute totals.
    /// @return totalCollateralInBase Total collateral value in base currency.
    /// @return totalDebtInBase Total debt value in base currency.
    /// @return ltv The weighted-average LTV across collateral.
    /// @return liquidationThreshold The weighted-average liquidation threshold across collateral.
    /// @return healthFactor Aave-style health factor (wad), `type(uint256).max` when debt is zero.
    function _getUserData(address _user) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        IAaveV3LendingProvider.Totals memory totals;
        UserData storage userData = usersData[_user];
        DataTypes.UserConfigurationMap memory userConfig = pool.getUserConfiguration(address(this));
        uint8 eModeCategoryId = uint8(pool.getUserEMode(address(this)));
        DataTypes.CollateralConfig memory eModeCollateralConfig;
        uint128 eModeCollateralBitmap;

        if (eModeCategoryId != E_MODE_DISABLED) {
            eModeCollateralConfig = pool.getEModeCategoryCollateralConfig(eModeCategoryId);
            eModeCollateralBitmap = pool.getEModeCategoryCollateralBitmap(eModeCategoryId);
        }

        for (uint256 i = 0; i < userData.tokensList.length; ++i) {
            address asset = userData.tokensList[i];

            SupportedToken storage tokenData = userData.supportedTokens[asset];

            DataTypes.ReserveDataLegacy memory reserveData = pool.getReserveData(asset);
            DataTypes.ReserveConfigurationMap memory configuration = reserveData.configuration;

            if (tokenData.suppliedScaled > 0) {
                uint256 suppliedAmount = tokenData.suppliedScaled.rayMul(pool.getReserveNormalizedIncome(asset));

                uint256 reserveLiquidationThreshold = ReserveConfiguration.getLiquidationThreshold(configuration);
                uint256 reserveLtv = ReserveConfiguration.getLtv(configuration);

                if (eModeCategoryId != E_MODE_DISABLED && _isReserveInBitmap(reserveData.id, eModeCollateralBitmap)) {
                    reserveLiquidationThreshold = uint256(eModeCollateralConfig.liquidationThreshold);
                    reserveLtv = uint256(eModeCollateralConfig.ltv);
                }

                if (reserveLiquidationThreshold > 0 && userConfig.isUsingAsCollateral(reserveData.id)) {
                    uint256 suppliedBase = _amountToBase(asset, suppliedAmount);

                    totals.collateral += suppliedBase;
                    totals.ltvAcc += suppliedBase.percentMul(reserveLtv);
                    totals.liqAcc += suppliedBase.percentMul(reserveLiquidationThreshold);
                }
            }

            if (tokenData.borrowedScaled > 0) {
                uint256 borrowedAmount = tokenData.borrowedScaled.rayMul(pool.getReserveNormalizedVariableDebt(asset));
                totals.debt += _amountToBase(asset, borrowedAmount);
            }
        }

        uint256 averageLtv =
            totals.collateral == 0 ? 0 : (totals.ltvAcc * PercentageMath.PERCENTAGE_FACTOR) / totals.collateral;
        uint256 averageLiquidationThreshold =
            totals.collateral == 0 ? 0 : (totals.liqAcc * PercentageMath.PERCENTAGE_FACTOR) / totals.collateral;

        uint256 healthFactor = totals.debt == 0 ? type(uint256).max : totals.liqAcc.wadDiv(totals.debt);

        return (totals.collateral, totals.debt, averageLtv, averageLiquidationThreshold, healthFactor);
    }

    /// @notice Checks whether a reserve is set in a 128-bit bitmap.
    /// @param reserveId The Aave reserve id.
    /// @param bitmap A bitmask where bit `reserveId` indicates membership.
    /// @return True if the reserve is included in the bitmap.
    function _isReserveInBitmap(uint16 reserveId, uint128 bitmap) internal pure returns (bool) {
        if (reserveId >= 128) {
            return false;
        }

        return (bitmap & (uint128(1) << reserveId)) != 0;
    }

    /// @notice Returns the caller's supplied balance for `_asset` in Aave's base currency.
    /// @dev Convenience wrapper around `getUserSuppliedBalance(msg.sender, _asset)` plus oracle conversion.
    /// @param _asset The underlying asset.
    /// @return Supplied value in base currency (0 if no supply).
    function getSuppliedBalanceCollateralFromAsset(address _asset) public view returns (uint256) {
        uint256 suppliedAmount = getUserSuppliedBalance(msg.sender, _asset);
        if (suppliedAmount == 0) {
            return 0;
        }
        return _amountToBase(_asset, suppliedAmount);
    }

    /// @notice Returns the caller's variable debt for `_asset` in Aave's base currency.
    /// @dev Convenience wrapper around `getUserBorrowedBalance(msg.sender, _asset)` plus oracle conversion.
    /// @param _asset The underlying asset.
    /// @return Borrowed value in base currency (0 if no debt).
    function getVariableDebtBalanceFromAsset(address _asset) public view returns (uint256) {
        uint256 borrowedAmount = getUserBorrowedBalance(msg.sender, _asset);
        if (borrowedAmount == 0) {
            return 0;
        }

        return _amountToBase(_asset, borrowedAmount);
    }

    /// @notice Returns a user's supplied balance for `_asset`, including accrued interest.
    /// @dev Converts the internally stored scaled balance using Aave's normalized income index.
    /// @param _user The user address.
    /// @param _asset The underlying asset.
    /// @return Supplied amount in underlying units.
    function getUserSuppliedBalance(address _user, address _asset) public view returns (uint256) {
        uint256 scaledBalance = usersData[_user].supportedTokens[_asset].suppliedScaled;
        if (scaledBalance == 0) {
            return 0;
        }

        uint256 liquidityIndex = pool.getReserveNormalizedIncome(_asset);
        return scaledBalance.rayMul(liquidityIndex);
    }

    /// @notice Returns a user's borrowed balance for `_asset`, including accrued interest.
    /// @dev Converts the internally stored scaled debt using Aave's normalized variable debt index.
    /// @param _user The user address.
    /// @param _asset The underlying asset.
    /// @return Borrowed amount in underlying units.
    function getUserBorrowedBalance(address _user, address _asset) public view returns (uint256) {
        uint256 scaledBalance = usersData[_user].supportedTokens[_asset].borrowedScaled;
        if (scaledBalance == 0) {
            return 0;
        }

        uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(_asset);
        return scaledBalance.rayMul(borrowIndex);
    }

    /// @notice Sets Aave eMode category for this provider's Aave account.
    /// @dev Only callable by the owner. eMode affects collateral parameters for eligible assets.
    /// @param _categoryId Aave eMode category id.
    function setEMode(uint8 _categoryId) external onlyOwner {
        pool.setUserEMode(_categoryId);
    }

    /// @notice Returns the eMode category currently set for this provider's Aave account.
    /// @return The configured eMode category id.
    function getEModeCategory() external view returns (uint256) {
        return pool.getUserEMode(address(this));
    }

    /// @notice Updates the Aave `IPoolAddressesProvider` and refreshes cached pool/oracle addresses.
    /// @dev Only callable by the owner.
    /// @param _poolAddressesProvider New addresses provider.
    function setPoolAddressesProvider(address _poolAddressesProvider) external onlyOwner {
        addressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(addressesProvider.getPool());
        priceOracle = IPriceOracle(addressesProvider.getPriceOracle());
    }

    /// @notice Calculates the maximum withdrawable collateral value (in base currency).
    /// @dev Ensures that after withdrawing, the remaining collateral still covers the current debt based on LTV.
    /// @param totalCollateralInBase Total collateral value in base currency.
    /// @param totalDebtInBase Total debt value in base currency.
    /// @param ltv Weighted-average LTV across collateral.
    /// @return Maximum base-currency value withdrawable.
    function _calculateWithdrawableBase(uint256 totalCollateralInBase, uint256 totalDebtInBase, uint256 ltv)
        internal
        pure
        returns (uint256)
    {
        if (totalCollateralInBase == 0 || ltv == 0) {
            return 0;
        }

        if (totalDebtInBase == 0) {
            return totalCollateralInBase;
        }

        uint256 debtLtv = totalDebtInBase.percentDiv(ltv);
        if (debtLtv >= totalCollateralInBase) {
            return 0;
        }
        return totalCollateralInBase - debtLtv;
    }

    /// @notice Converts an amount of `_asset` into Aave base currency using the configured price oracle.
    /// @param _asset The underlying asset.
    /// @param _amount Amount in underlying units.
    /// @return Value in base currency units used by the Aave oracle.
    function _amountToBase(address _asset, uint256 _amount) internal view returns (uint256) {
        uint256 assetPrice = priceOracle.getAssetPrice(_asset);
        uint256 unit = 10 ** IERC20Metadata(_asset).decimals();

        return (_amount * assetPrice) / unit;
    }

    /// @notice Reverts if `token` is not enabled in `supportedTokens`.
    /// @param token The underlying asset to check.
    function _onlySupportedToken(address token) internal view {
        if (!supportedTokens[token]) {
            revert UnsupportedToken(token);
        }
    }

    /// @notice Initializes per-user bookkeeping for `_asset` if it hasn't been used by `_user` yet.
    /// @dev Adds the asset to `tokensList` on first use, allowing later iteration for health checks.
    /// @param _user The user for which the asset is being initialized.
    /// @param _asset The underlying asset.
    /// @return tokenData Storage pointer to the user's token data.
    function _initializeUserToken(address _user, address _asset) internal returns (SupportedToken storage) {
        bool isInitialized = usersData[_user].supportedTokens[_asset].initialized;
        if (!isInitialized) {
            usersData[_user].supportedTokens[_asset].initialized = true;
            usersData[_user].tokensList.push(_asset);
        }
        return usersData[_user].supportedTokens[_asset];
    }

    /// @notice Enables `_token` for use in `supply/withdraw/borrow/repay`.
    /// @dev Only callable by the owner. No-op if already enabled.
    /// @param _token Underlying ERC20 token address.
    function addSupportedToken(address _token) external override onlyOwner {
        if (supportedTokens[_token]) {
            return;
        }

        supportedTokens[_token] = true;
    }

    /// @notice Disables `_token` for use in `supply/withdraw/borrow/repay`.
    /// @dev Only callable by the owner. No-op if already disabled.
    /// @param _token Underlying ERC20 token address.
    function removeSupportedToken(address _token) external override onlyOwner {
        if (!supportedTokens[_token]) {
            return;
        }

        supportedTokens[_token] = false;
    }
}
