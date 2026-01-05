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

import {ITokenMessenger} from "./interfaces/ITokenMessenger.sol";
import {ICCTPAaveFastBridge} from "./interfaces/ICCTPAaveFastBridge.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title CCTPAaveFastBridge
/// @notice Supplies collateral to Aave V3, borrows max USDC, and initiates a fast CCTP transfer.
contract CCTPAaveFastBridge is ICCTPAaveFastBridge, Ownable {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 private constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);
    uint8 private constant E_MODE_DISABLED = 0;

    IPoolAddressesProvider public addressesProvider;
    IPool public pool;
    IPriceOracle public priceOracle;
    ITokenMessenger public tokenMessenger;
    address public immutable USDC_TOKEN;

    mapping(address => ICCTPAaveFastBridge.UserData) private usersData;

    /// @notice Initializes the bridge with Aave and CCTP addresses.
    /// @param _poolAddressesProvider Aave V3 pool addresses provider.
    /// @param _tokenMessenger Circle CCTP TokenMessenger address.
    /// @param _usdc USDC token address on the source chain.
    constructor(address _poolAddressesProvider, address _tokenMessenger, address _usdc) Ownable(msg.sender) {
        if (_poolAddressesProvider == address(0) || _tokenMessenger == address(0) || _usdc == address(0)) {
            revert InvalidAddress();
        }

        addressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(addressesProvider.getPool());
        priceOracle = IPriceOracle(addressesProvider.getPriceOracle());
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        USDC_TOKEN = _usdc;
    }

    /// @notice Supplies collateral, borrows max USDC, and initiates a fast CCTP transfer.
    /// @param asset The collateral asset supplied to Aave V3.
    /// @param amount The amount of collateral to supply.
    /// @param referralCode Aave referral code (usually `0`).
    /// @param destinationDomain CCTP destination domain.
    /// @param mintRecipient Recipient address on destination chain (bytes32 format).
    /// @return cctpNonce The CCTP burn nonce from TokenMessenger.
    /// @return borrowedUsdcAmount The amount of USDC borrowed and bridged.
    function initiateFastTransfer(
        address asset,
        uint256 amount,
        uint16 referralCode,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external returns (uint64 cctpNonce, uint256 borrowedUsdcAmount) {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        if (asset == USDC_TOKEN) {
            TransferHelper.safeTransferFrom(USDC_TOKEN, msg.sender, address(this), amount);

            TransferHelper.safeApprove(USDC_TOKEN, address(tokenMessenger), 0);
            TransferHelper.safeApprove(USDC_TOKEN, address(tokenMessenger), amount);

            cctpNonce = tokenMessenger.depositForBurn(amount, destinationDomain, mintRecipient, USDC_TOKEN);
            borrowedUsdcAmount = amount;

            (,,,, uint256 userHealthFactor) = _getUserData(msg.sender);

            emit FastTransferInitiated(
                msg.sender,
                asset,
                amount,
                borrowedUsdcAmount,
                destinationDomain,
                mintRecipient,
                userHealthFactor,
                cctpNonce
            );

            return (cctpNonce, borrowedUsdcAmount);
        }

        _supply(msg.sender, asset, amount, referralCode);

        borrowedUsdcAmount = _maxBorrowableUsdc(msg.sender);

        if (borrowedUsdcAmount == 0) {
            revert ZeroUsdcBorrowAvailable();
        }

        _borrowFor(msg.sender, USDC_TOKEN, borrowedUsdcAmount, referralCode);

        TransferHelper.safeApprove(USDC_TOKEN, address(tokenMessenger), 0);
        TransferHelper.safeApprove(USDC_TOKEN, address(tokenMessenger), borrowedUsdcAmount);

        cctpNonce = tokenMessenger.depositForBurn(borrowedUsdcAmount, destinationDomain, mintRecipient, USDC_TOKEN);

        (,,,, uint256 healthFactor) = _getUserData(msg.sender);

        emit FastTransferInitiated(
            msg.sender, asset, amount, borrowedUsdcAmount, destinationDomain, mintRecipient, healthFactor, cctpNonce
        );
    }

    /// @notice Returns the caller's current borrowed balance for `_asset`.
    /// @param asset The borrowed asset to query.
    /// @return The borrowed balance in underlying units.
    function getCurrentBorrow(address asset) external view returns (uint256) {
        return _getUserBorrowedBalance(msg.sender, asset);
    }

    /// @notice Repays the caller's borrowed balance for `_asset`.
    /// @param asset The borrowed asset to repay.
    /// @param amount The amount to repay.
    /// @return repaidAmount The amount actually repaid on Aave.
    function repayBorrow(address asset, uint256 amount) external returns (uint256 repaidAmount) {
        return _repay(msg.sender, asset, amount);
    }

    /// @notice Supplies `_amount` of `_asset` on Aave using this contract as the Aave account.
    /// @param user The user whose internal balances are updated.
    /// @param asset The underlying asset to supply.
    /// @param amount The amount to supply.
    /// @param referralCode Aave referral code (usually `0`).
    function _supply(address user, address asset, uint256 amount, uint16 referralCode) internal {
        TransferHelper.safeTransferFrom(asset, user, address(this), amount);

        TransferHelper.safeApprove(asset, address(pool), 0);
        TransferHelper.safeApprove(asset, address(pool), amount);

        pool.supply(asset, amount, address(this), referralCode);

        uint256 liquidityIndex = pool.getReserveNormalizedIncome(asset);
        uint256 scaledAmount = amount.rayDiv(liquidityIndex);
        ICCTPAaveFastBridge.SupportedToken storage tokenData = _initializeUserToken(user, asset);
        tokenData.suppliedScaled += scaledAmount;
    }

    /// @notice Borrows `_amount` of `_asset` on Aave and records the debt under `user`.
    /// @param user The user whose collateral backs the borrow.
    /// @param asset The asset to borrow.
    /// @param amount The amount to borrow.
    /// @param referralCode Aave referral code (usually `0`).
    function _borrowFor(address user, address asset, uint256 amount, uint16 referralCode) internal {
        (uint256 totalCollateralInBase, uint256 totalDebtInBase, uint256 ltv,, uint256 healthFactor) =
            _getUserData(user);

        if (totalCollateralInBase == 0) {
            revert InsufficientCollateral();
        }

        if (healthFactor < 1e18) {
            revert InsufficientHealthFactor(healthFactor);
        }

        uint256 amountToBase = _amountToBase(asset, amount);

        uint256 maxAvailableBorrowAmount =
            GenericLogic.calculateAvailableBorrows(totalCollateralInBase, totalDebtInBase, ltv);

        if (amountToBase > maxAvailableBorrowAmount) {
            revert InsufficientAvailableBorrows(amount);
        }

        pool.borrow(asset, amount, INTEREST_RATE_MODE, referralCode, address(this));

        uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(asset);
        uint256 scaledBorrow = amount.rayDiv(borrowIndex);
        ICCTPAaveFastBridge.SupportedToken storage tokenData = _initializeUserToken(user, asset);
        tokenData.borrowedScaled += scaledBorrow;
    }

    /// @notice Repays `_amount` of `_asset` debt on Aave for `user`.
    /// @param user The user whose debt is reduced.
    /// @param asset The asset to repay.
    /// @param amount The amount to repay.
    /// @return repayAmount The amount actually repaid on Aave.
    function _repay(address user, address asset, uint256 amount) internal returns (uint256 repayAmount) {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint256 userDebt = _getUserBorrowedBalance(user, asset);
        if (userDebt == 0) {
            revert InsufficientBalance();
        }

        uint256 amountToRepay = amount > userDebt ? userDebt : amount;

        TransferHelper.safeTransferFrom(asset, user, address(this), amountToRepay);

        TransferHelper.safeApprove(asset, address(pool), 0);
        TransferHelper.safeApprove(asset, address(pool), amountToRepay);

        uint256 repaidAmount = pool.repay(asset, amountToRepay, INTEREST_RATE_MODE, address(this));

        if (amountToRepay > repaidAmount) {
            TransferHelper.safeTransfer(asset, user, amountToRepay - repaidAmount);
        }

        uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(asset);
        uint256 scaledReduction = repaidAmount.rayDiv(borrowIndex);

        ICCTPAaveFastBridge.SupportedToken storage tokenData = usersData[user].supportedTokens[asset];
        uint256 currentScaled = tokenData.borrowedScaled;
        tokenData.borrowedScaled = scaledReduction >= currentScaled ? 0 : currentScaled - scaledReduction;
        repayAmount = repaidAmount;
    }

    /// @notice Returns `user` borrowed balance for `_asset`, including accrued interest.
    /// @param user The user address.
    /// @param asset The borrowed asset.
    /// @return Borrowed amount in underlying units.
    function _getUserBorrowedBalance(address user, address asset) internal view returns (uint256) {
        uint256 scaledBalance = usersData[user].supportedTokens[asset].borrowedScaled;
        if (scaledBalance == 0) {
            return 0;
        }

        uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(asset);
        return scaledBalance.rayMul(borrowIndex);
    }

    /// @notice Computes the user's collateral/debt totals and health factor in Aave base currency.
    /// @param user The user whose balances are evaluated.
    /// @return totalCollateralInBase Total collateral value in base currency.
    /// @return totalDebtInBase Total debt value in base currency.
    /// @return ltv Weighted-average LTV across collateral.
    /// @return liquidationThreshold Weighted-average liquidation threshold.
    /// @return healthFactor Aave-style health factor (wad), `type(uint256).max` when debt is zero.
    function _getUserData(address user) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        ICCTPAaveFastBridge.Totals memory totals;
        ICCTPAaveFastBridge.UserData storage userData = usersData[user];
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

            ICCTPAaveFastBridge.SupportedToken storage tokenData = userData.supportedTokens[asset];

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

    /// @notice Checks whether a reserve id is set in a 128-bit bitmap.
    /// @param reserveId The reserve id.
    /// @param bitmap The bitmap to test.
    /// @return True if the bit for `reserveId` is set.
    function _isReserveInBitmap(uint16 reserveId, uint128 bitmap) internal pure returns (bool) {
        if (reserveId >= 128) {
            return false;
        }

        return (bitmap & (uint128(1) << reserveId)) != 0;
    }

    /// @notice Converts `_amount` of `_asset` to Aave base currency using the price oracle.
    /// @param asset The underlying asset.
    /// @param amount The amount in underlying units.
    /// @return Value in base currency units.
    function _amountToBase(address asset, uint256 amount) internal view returns (uint256) {
        uint256 assetPrice = priceOracle.getAssetPrice(asset);
        uint256 unit = 10 ** IERC20Metadata(asset).decimals();

        return (amount * assetPrice) / unit;
    }

    /// @notice Initializes per-user bookkeeping for an asset on first use.
    /// @param user The user address.
    /// @param asset The asset to initialize.
    /// @return tokenData Storage pointer to the user's token data.
    function _initializeUserToken(address user, address asset)
        internal
        returns (ICCTPAaveFastBridge.SupportedToken storage)
    {
        bool isInitialized = usersData[user].supportedTokens[asset].initialized;
        if (!isInitialized) {
            usersData[user].supportedTokens[asset].initialized = true;
            usersData[user].tokensList.push(asset);
        }
        return usersData[user].supportedTokens[asset];
    }

    /// @notice Calculates the maximum USDC the user can borrow based on tracked collateral.
    /// @param user The user whose position is evaluated.
    /// @return The maximum borrowable USDC amount.
    function _maxBorrowableUsdc(address user) internal view returns (uint256) {
        (uint256 totalCollateralInBase, uint256 totalDebtInBase, uint256 ltv,,) = _getUserData(user);
        if (totalCollateralInBase == 0 || ltv == 0) {
            return 0;
        }

        uint256 usdcPrice = priceOracle.getAssetPrice(USDC_TOKEN);
        if (usdcPrice == 0) {
            revert InvalidUsdcPrice();
        }

        uint256 maxDebtBase = (totalCollateralInBase * ltv) / PercentageMath.PERCENTAGE_FACTOR;
        uint256 totalDebtBase = totalDebtInBase;
        if (maxDebtBase <= totalDebtBase) {
            return 0;
        }

        uint256 maxAvailableBorrowBase = maxDebtBase - totalDebtBase;
        uint256 unit = 10 ** IERC20Metadata(USDC_TOKEN).decimals();
        uint256 amount = (maxAvailableBorrowBase * unit) / usdcPrice;

        amount = (amount * 9999) / 10000;

        uint256 debtBaseCeil = _amountToBase(USDC_TOKEN, amount);
        if (debtBaseCeil > maxAvailableBorrowBase) {
            if (amount <= 1) {
                return 0;
            }
            return amount - 1;
        }

        return amount;
    }

    /// @notice Sets the TokenMessenger address.
    /// @param _tokenMessenger The new TokenMessenger address.
    function setTokenMessenger(address _tokenMessenger) external onlyOwner {
        tokenMessenger = ITokenMessenger(_tokenMessenger);
    }

    /// @notice Sets the PoolAddressesProvider address.
    /// @param _poolAddressesProvider The new PoolAddressesProvider address.
    function setPoolAddressesProvider(address _poolAddressesProvider) external onlyOwner {
        addressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(addressesProvider.getPool());
        priceOracle = IPriceOracle(addressesProvider.getPriceOracle());
    }
}
