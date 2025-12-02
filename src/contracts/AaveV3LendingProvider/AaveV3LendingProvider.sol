// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
import {IAaveV3LendingProvider} from "./IAaveV3LendingProvider.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AaveV3LendingProvider is IAaveV3LendingProvider, Ownable {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    uint256 private constant INTEREST_RATE_MODE = uint256(DataTypes.InterestRateMode.VARIABLE);

    IPoolAddressesProvider public addressesProvider;
    IPool public pool;
    IPriceOracle public priceOracle;

    mapping(address => UserData) private usersData;
    mapping(address => bool) public supportedTokens;

    modifier onlySupportedToken(address token) {
        _onlySupportedToken(token);
        _;
    }

    constructor(address _poolAddressesProvider) Ownable(msg.sender) {
        addressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(addressesProvider.getPool());
        priceOracle = IPriceOracle(addressesProvider.getPriceOracle());
    }

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

    function _getUserData(address _user) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        IAaveV3LendingProvider.Totals memory totals;
        address[] storage tokens = usersData[_user].tokensList;
        uint256 length = tokens.length;
        DataTypes.UserConfigurationMap memory userConfig = pool.getUserConfiguration(address(this));

        for (uint256 i = 0; i < length; ++i) {
            address asset = tokens[i];

            SupportedToken storage tokenData = usersData[_user].supportedTokens[asset];

            if (!_userHasPosition(_user, asset)) {
                continue;
            }

            DataTypes.ReserveDataLegacy memory reserveData = pool.getReserveData(asset);
            DataTypes.ReserveConfigurationMap memory configuration = reserveData.configuration;

            if (tokenData.suppliedScaled > 0) {
                uint256 liquidityIndex = pool.getReserveNormalizedIncome(asset);
                uint256 suppliedAmount = tokenData.suppliedScaled.rayMul(liquidityIndex);

                uint256 reserveLiquidationThreshold = ReserveConfiguration.getLiquidationThreshold(configuration);

                if (reserveLiquidationThreshold > 0 && userConfig.isUsingAsCollateral(reserveData.id)) {
                    uint256 suppliedBase = _amountToBase(asset, suppliedAmount);
                    uint256 reserveLtv = ReserveConfiguration.getLtv(configuration);

                    totals.collateral += suppliedBase;
                    totals.ltvAcc += suppliedBase.percentMul(reserveLtv);
                    totals.liqAcc += suppliedBase.percentMul(reserveLiquidationThreshold);
                }
            }

            if (tokenData.borrowedScaled > 0) {
                uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(asset);
                uint256 borrowedAmount = tokenData.borrowedScaled.rayMul(borrowIndex);
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

    function getSuppliedBalanceCollateralFromAsset(address _asset) public view returns (uint256) {
        uint256 suppliedAmount = getUserSuppliedBalance(msg.sender, _asset);
        if (suppliedAmount == 0) {
            return 0;
        }
        return _amountToBase(_asset, suppliedAmount);
    }

    function getVariableDebtBalanceFromAsset(address _asset) public view returns (uint256) {
        uint256 borrowedAmount = getUserBorrowedBalance(msg.sender, _asset);
        if (borrowedAmount == 0) {
            return 0;
        }

        return _amountToBase(_asset, borrowedAmount);
    }

    function getUserSuppliedBalance(address _user, address _asset) public view returns (uint256) {
        uint256 scaledBalance = usersData[_user].supportedTokens[_asset].suppliedScaled;
        if (scaledBalance == 0) {
            return 0;
        }

        uint256 liquidityIndex = pool.getReserveNormalizedIncome(_asset);
        return scaledBalance.rayMul(liquidityIndex);
    }

    function getUserBorrowedBalance(address _user, address _asset) public view returns (uint256) {
        uint256 scaledBalance = usersData[_user].supportedTokens[_asset].borrowedScaled;
        if (scaledBalance == 0) {
            return 0;
        }

        uint256 borrowIndex = pool.getReserveNormalizedVariableDebt(_asset);
        return scaledBalance.rayMul(borrowIndex);
    }

    function setEMode(uint8 _categoryId) external onlyOwner {
        pool.setUserEMode(_categoryId);
    }

    function getEModeCategory() external view returns (uint256) {
        return pool.getUserEMode(address(this));
    }

    function setPoolAddressesProvider(address _poolAddressesProvider) external onlyOwner {
        addressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        pool = IPool(addressesProvider.getPool());
        priceOracle = IPriceOracle(addressesProvider.getPriceOracle());
    }

    function _calculateWithdrawableBase(uint256 totalCollateralInBase, uint256 totalDebtInBase, uint256 ltv)
        internal
        pure
        returns (uint256)
    {
        if (totalCollateralInBase == 0) {
            return 0;
        }

        if (totalDebtInBase == 0) {
            return totalCollateralInBase;
        }

        if (ltv == 0) {
            return 0;
        }

        uint256 debtLtv = totalDebtInBase.percentDiv(ltv);
        if (debtLtv >= totalCollateralInBase) {
            return 0;
        }
        return totalCollateralInBase - debtLtv;
    }

    function _amountToBase(address _asset, uint256 _amount) internal view returns (uint256) {
        uint256 assetPrice = priceOracle.getAssetPrice(_asset);
        uint256 unit = 10 ** IERC20Metadata(_asset).decimals();

        return (_amount * assetPrice) / unit;
    }

    function _onlySupportedToken(address token) internal view {
        if (!supportedTokens[token]) {
            revert UnsupportedToken(token);
        }
    }

    function _initializeUserToken(address _user, address _asset) internal returns (SupportedToken storage) {
        bool isInitialized = usersData[_user].supportedTokens[_asset].initialized;
        if (!isInitialized) {
            usersData[_user].supportedTokens[_asset].initialized = true;
            usersData[_user].tokensList.push(_asset);
        }
        return usersData[_user].supportedTokens[_asset];
    }

    function _userHasPosition(address _user, address _asset) internal view returns (bool) {
        SupportedToken storage tokenData = usersData[_user].supportedTokens[_asset];
        return tokenData.suppliedScaled > 0 || tokenData.borrowedScaled > 0;
    }

    function addSupportedToken(address _token) external override onlyOwner {
        if (supportedTokens[_token]) {
            return;
        }

        supportedTokens[_token] = true;
    }

    function removeSupportedToken(address _token) external override onlyOwner {
        if (!supportedTokens[_token]) {
            return;
        }

        supportedTokens[_token] = false;
    }
}
