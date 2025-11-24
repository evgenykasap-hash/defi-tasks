// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Extended} from "../libraries/IERC20Extended.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol";

contract AaveV3LendingProvider {
    using SafeERC20 for IERC20Extended;

    error UnsupportedToken(address token);
    error AmountMustBeGreaterThanZero();
    error NotOwner(address sender);

    uint256 private constant INTEREST_MODE = 2;

    address payable owner;

    IPoolAddressesProvider private immutable POOL_ADDRESSES_PROVIDER;
    IPool private immutable POOL;

    struct SupportedToken {
        address addr;
        IERC20Extended token;
    }

    mapping(address => SupportedToken) private supportedTokens;

    constructor(address _addressProvider, address[] memory _supportedTokens) {
        owner = payable(msg.sender);
        POOL_ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressProvider);
        POOL = IPool(POOL_ADDRESSES_PROVIDER.getPool());

        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            address tokenAddr = _supportedTokens[i];
            supportedTokens[tokenAddr] = SupportedToken({addr: tokenAddr, token: IERC20Extended(tokenAddr)});
        }
    }

    function getUserAccountData(address _user)
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
        (totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor) =
            POOL.getUserAccountData(_user);
    }

    modifier _onlySupportedToken(address token) {
        _enforceSupportedToken(token);
        _;
    }

    modifier _checkAmount(uint256 amount) {
        _enforceAmount(amount);
        _;
    }

    function supply(address _asset, uint256 _amount, uint16 _referralCode)
        external
        _onlySupportedToken(_asset)
        _checkAmount(_amount)
    {
        SupportedToken storage supportedToken = supportedTokens[_asset];
        supportedToken.token.safeTransferFrom(msg.sender, address(this), _amount);

        supportedToken.token.approve(address(POOL), _amount);
        POOL.supply(_asset, _amount, msg.sender, _referralCode);
    }

    function withdraw(address _asset) external _onlySupportedToken(_asset) returns (uint256 withdrawAmount) {
        SupportedToken storage supportedToken = supportedTokens[_asset];
        uint256 amount = supportedToken.token.balanceOf(address(this));

        withdrawAmount = POOL.withdraw(_asset, amount, msg.sender);
    }

    function borrow(address _asset, uint256 _amount, uint16 _referralCode)
        external
        _onlySupportedToken(_asset)
        _checkAmount(_amount)
    {
        POOL.borrow(_asset, _amount, INTEREST_MODE, _referralCode, msg.sender);
    }

    function repay(address _asset, uint256 _amount)
        external
        _onlySupportedToken(_asset)
        _checkAmount(_amount)
        returns (uint256 repayAmount)
    {
        repayAmount = POOL.repay(_asset, _amount, INTEREST_MODE, msg.sender);
    }

    function withdrawToken(address _tokenAddress) external _onlySupportedToken(_tokenAddress) {
        SupportedToken storage supportedToken = supportedTokens[_tokenAddress];

        supportedToken.token.safeTransfer(address(owner), supportedToken.token.balanceOf(address(this)));
    }

    function getBalance(address _asset) external view returns (uint256) {
        return POOL.getVirtualUnderlyingBalance(_asset);
    }

    function getPoolAddress() external view returns (address) {
        return address(POOL);
    }

    function getPoolProviderAddress() external view returns (address) {
        return address(POOL_ADDRESSES_PROVIDER);
    }

    function _enforceOnlyOwner() internal view {
        if (msg.sender != address(owner)) {
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

    function getOwnerAddress() external view returns (address) {
        return address(owner);
    }
}
