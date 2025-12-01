// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {
    IPoolAddressesProvider
} from "@aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol";
import {
    DataTypes
} from "@aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";

interface IAaveV3LendingProvider {
    error NotOwner(address sender);
    error UnsupportedToken(address token);
    error AmountMustBeGreaterThanZero();
    error InsufficientBalance();
    error InsufficientAvailableBorrows();

    struct SuppliedBalance {
        mapping(address => uint256) balances;
        uint256 totalAmount;
    }

    struct BorrowedBalance {
        mapping(address => uint256) balances;
        uint256 totalAmount;
    }

    function getUserAccountData(
        address _user
    )
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
    function supply(
        address _asset,
        uint256 _amount,
        uint16 _referralCode
    ) external;
    function withdraw(
        address _asset,
        uint256 _amount
    ) external returns (uint256 withdrawAmount);
    function borrow(
        address _asset,
        uint256 _amount,
        uint16 _referralCode
    ) external;
    function repay(
        address _asset,
        uint256 _amount
    ) external returns (uint256 repayAmount);
    function getSuppliedBalance(address _asset) external view returns (uint256);
    function addSupportedToken(address _token) external;
    function removeSupportedToken(address _token) external;
}

contract AaveV3LendingProvider is IAaveV3LendingProvider {
    using SafeERC20 for IERC20;

    uint256 private constant INTEREST_MODE = 2;

    address payable owner;

    IPoolAddressesProvider private immutable POOL_ADDRESSES_PROVIDER;
    IPool private immutable POOL;

    mapping(address => IERC20) private supportedTokens;
    mapping(address => SuppliedBalance) private suppliedBalances;
    mapping(address => BorrowedBalance) private borrowedBalances;

    constructor(address _addressProvider) {
        owner = payable(msg.sender);
        POOL_ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressProvider);
        POOL = IPool(POOL_ADDRESSES_PROVIDER.getPool());
    }

    function getUserAccountData(
        address _user
    )
        public
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (
            totalCollateralBase,
            totalDebtBase,
            availableBorrowsBase,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        ) = POOL.getUserAccountData(_user);
    }

    function supply(
        address _asset,
        uint256 _amount,
        uint16 _referralCode
    ) external _onlySupportedToken(_asset) _checkAmount(_amount) {
        IERC20 token = supportedTokens[_asset];
        token.safeTransferFrom(msg.sender, address(this), _amount);

        token.approve(address(POOL), _amount);
        POOL.supply(_asset, _amount, msg.sender, _referralCode);

        suppliedBalances[msg.sender].balances[_asset] += _amount;
        suppliedBalances[msg.sender].totalAmount += _amount;
    }

    function withdraw(
        address _asset,
        uint256 _amount
    ) external _onlySupportedToken(_asset) returns (uint256) {
        if (
            suppliedBalances[msg.sender].balances[_asset] == 0 ||
            suppliedBalances[msg.sender].totalAmount == 0
        ) {
            revert InsufficientBalance();
        }

        uint256 amountToWithdraw = _amount;

        if (amountToWithdraw > suppliedBalances[msg.sender].balances[_asset]) {
            amountToWithdraw = uint256(type(uint).max);
            suppliedBalances[msg.sender].balances[_asset] = 0;
            suppliedBalances[msg.sender].totalAmount = 0;
        } else {
            suppliedBalances[msg.sender].balances[_asset] -= amountToWithdraw;
            suppliedBalances[msg.sender].totalAmount -= amountToWithdraw;
        }

        uint256 withdrawAmount = POOL.withdraw(
            _asset,
            amountToWithdraw,
            msg.sender
        );

        return withdrawAmount;
    }

    function borrow(
        address _asset,
        uint256 _amount,
        uint16 _referralCode
    ) external _onlySupportedToken(_asset) _checkAmount(_amount) {
        POOL.borrow(
            _asset,
            _amount,
            INTEREST_MODE,
            _referralCode,
            address(this)
        );
    }

    function repay(
        address _asset,
        uint256 _amount
    )
        external
        _onlySupportedToken(_asset)
        _checkAmount(_amount)
        returns (uint256 repayAmount)
    {
        repayAmount = POOL.repay(_asset, _amount, INTEREST_MODE, msg.sender);
    }

    function getSuppliedBalance(
        address _asset
    ) external view returns (uint256 balance) {
        balance = suppliedBalances[msg.sender].balances[_asset];
    }

    function addSupportedToken(address _token) external _onlyOwner {
        supportedTokens[_token] = IERC20(_token);
    }

    function removeSupportedToken(address _token) external _onlyOwner {
        delete supportedTokens[_token];
    }

    function _enforceSupportedToken(address token) internal view {
        if (address(supportedTokens[token]) != token) {
            revert UnsupportedToken(token);
        }
    }

    function _enforceAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }
    }

    function _enforceOwner() internal view {
        if (msg.sender != address(owner)) {
            revert NotOwner(msg.sender);
        }
    }

    modifier _onlySupportedToken(address token) {
        _enforceSupportedToken(token);
        _;
    }

    modifier _checkAmount(uint256 amount) {
        _enforceAmount(amount);
        _;
    }

    modifier _onlyOwner() {
        _enforceOwner();
        _;
    }
}
