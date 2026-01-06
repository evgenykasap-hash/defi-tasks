// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAaveV3SimpleBorrow {
    error InvalidAddress();
    error AmountMustBeGreaterThanZero();

    event Supplied(address indexed user, address indexed asset, uint256 amount, uint16 referralCode);
    event Borrowed(address indexed user, address indexed asset, uint256 amount, uint16 referralCode);

    function supply(address asset, uint256 amount, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint16 referralCode) external;
}
