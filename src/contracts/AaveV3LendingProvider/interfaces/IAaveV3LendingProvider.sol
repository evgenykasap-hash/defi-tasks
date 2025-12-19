// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAaveV3LendingProvider {
    error UnsupportedTokenForEMode();
    error UnsupportedToken(address token);
    error AmountMustBeGreaterThanZero();
    error InsufficientHealthFactor(uint256 healthFactor);
    error InsufficientBalance();
    error InsufficientAvailableBorrows(uint256 amount);
    error InsufficientWithdrawableAmount(uint256 amount);
    error InsufficientCollateral();

    struct Totals {
        uint256 collateral;
        uint256 debt;
        uint256 ltvAcc;
        uint256 liqAcc;
    }

    struct SupportedToken {
        bool initialized;
        uint256 suppliedScaled;
        uint256 borrowedScaled;
    }

    struct UserData {
        mapping(address => SupportedToken) supportedTokens;
        address[] tokensList;
    }

    function supply(address _asset, uint256 _amount, uint16 _referralCode) external;
    function withdraw(address _asset, uint256 _amount) external returns (uint256 withdrawAmount);
    function borrow(address _asset, uint256 _amount, uint16 _referralCode) external;
    function repay(address _asset, uint256 _amount) external returns (uint256 repayAmount);
    function addSupportedToken(address _token) external;
    function removeSupportedToken(address _token) external;

    function setPoolAddressesProvider(address _poolAddressesProvider) external;
    function setEMode(uint8 _categoryId) external;
    function getEModeCategory() external view returns (uint256);
}
