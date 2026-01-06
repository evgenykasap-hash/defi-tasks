// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ICCTPAaveFastBridge {
    /// @notice Emitted after initiating the fast CCTP transfer.
    event FastTransferInitiated(
        address indexed user,
        address indexed collateralAsset,
        uint256 suppliedAmount,
        uint256 borrowedUsdcAmount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        uint256 healthFactor,
        uint64 cctpNonce
    );

    error InvalidAddress();
    error AmountMustBeGreaterThanZero();
    error InsufficientHealthFactor(uint256 healthFactor);
    error InsufficientBalance();
    error InsufficientAvailableBorrows(uint256 amount);
    error InsufficientCollateral();
    error ZeroUsdcBorrowAvailable();
    error InvalidUsdcPrice();

    struct SupportedToken {
        bool initialized;
        uint256 suppliedScaled;
        uint256 borrowedScaled;
    }

    struct Totals {
        uint256 collateral;
        uint256 debt;
        uint256 ltvAcc;
        uint256 liqAcc;
    }

    struct UserData {
        mapping(address => SupportedToken) supportedTokens;
        address[] tokensList;
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
    ) external returns (uint64 cctpNonce, uint256 borrowedUsdcAmount);

    /// @notice Returns the caller's current borrowed balance for `_asset`.
    /// @param asset The borrowed asset to query.
    /// @return The borrowed balance in underlying units.
    function getCurrentBorrow(address asset) external view returns (uint256);

    /// @notice Repays the caller's borrowed balance for `_asset`.
    /// @param asset The borrowed asset to repay.
    /// @param amount The amount to repay.
    /// @return repaidAmount The amount actually repaid on Aave.
    function repayBorrow(address asset, uint256 amount) external returns (uint256 repaidAmount);

    /// @notice Sets the TokenMessenger address.
    /// @param _tokenMessenger The new TokenMessenger address.
    function setTokenMessenger(address _tokenMessenger) external;

    /// @notice Sets the PoolAddressesProvider address.
    /// @param _poolAddressesProvider The new PoolAddressesProvider address.
    function setPoolAddressesProvider(address _poolAddressesProvider) external;
}
