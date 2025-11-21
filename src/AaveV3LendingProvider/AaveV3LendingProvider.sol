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

contract AaveV3LendingProvider {
    using SafeERC20 for IERC20;

    error UnsupportedToken(address token);
    error AmountMustBeGreaterThanZero();
    error NotOwner(address sender);

    address payable owner;

    IPoolAddressesProvider private immutable POOL_ADDRESSES_PROVIDER;
    IPool private immutable POOL;

    struct SupportedToken {
        address addr;
        IERC20 token;
    }

    mapping(address => SupportedToken) private supportedTokens;

    constructor(address _addressProvider, address[] memory _supportedTokens) {
        owner = payable(msg.sender);
        POOL_ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressProvider);
        POOL = IPool(POOL_ADDRESSES_PROVIDER.getPool());

        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            address tokenAddr = _supportedTokens[i];
            supportedTokens[tokenAddr] = SupportedToken({
                addr: tokenAddr,
                token: IERC20(tokenAddr)
            });
        }
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
        address onBehalfOf = address(this);

        POOL.supply(_asset, _amount, onBehalfOf, _referralCode);
    }

    function withdraw(
        address _asset,
        uint256 _amount
    )
        external
        _onlySupportedToken(_asset)
        _checkAmount(_amount)
        _onlyOwner
        returns (uint256 withdrawAmount)
    {
        address to = address(this);

        withdrawAmount = POOL.withdraw(_asset, _amount, to);
    }

    function borrow(
        address _asset,
        uint256 _amount,
        uint16 _referralCode
    ) external {
        uint256 interestMode = 2;
        address onBehalfOf = address(this);

        POOL.borrow(_asset, _amount, interestMode, _referralCode, onBehalfOf);
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
        address onBehalfOf = address(this);
        uint256 interestMode = 2;

        repayAmount = POOL.repay(_asset, _amount, interestMode, onBehalfOf);
    }

    function getPoolAddress() external view returns (address) {
        return address(POOL);
    }

    function getPoolProviderAddress() external view returns (address) {
        return address(POOL_ADDRESSES_PROVIDER);
    }

    function approveToken(
        address token,
        uint256 amount
    ) external _onlySupportedToken(token) _checkAmount(amount) {
        SupportedToken storage supportedToken = supportedTokens[token];
        supportedToken.token.forceApprove(address(POOL), amount);
    }

    function allowanceToken(
        address token
    ) external view _onlySupportedToken(token) returns (uint256) {
        SupportedToken storage supportedToken = supportedTokens[token];
        return supportedToken.token.allowance(address(this), address(POOL));
    }

    modifier _onlyOwner() {
        _enforceOnlyOwner();
        _;
    }

    modifier _onlySupportedToken(address token) {
        _enforceSupportedToken(token);
        _;
    }

    modifier _checkAmount(uint256 amount) {
        _enforceAmount(amount);
        _;
    }

    function _enforceOnlyOwner() internal view {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
    }

    function _enforceSupportedToken(address token) internal view {
        if (supportedTokens[token].addr != token) {
            revert UnsupportedToken(token);
        }
    }

    function _enforceAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }
    }
}
