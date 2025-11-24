// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
    function deposit() external payable;
    function withdraw(uint256) external;
}
