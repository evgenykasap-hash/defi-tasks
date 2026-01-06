// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {AaveV3SimpleBorrow} from "../../src/contracts/AaveV3SimpleBorrow/AaveV3SimpleBorrow.sol";
import {AaveV3LendingProviderConfig} from "../../src/scripts/AaveV3LendingProvider/AaveV3LendingProviderConfig.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AaveV3SimpleBorrowTest is Test {
    address internal user = makeAddr("user");
    AaveV3SimpleBorrow internal simpleBorrow;
    IERC20Metadata internal wethToken;
    IERC20Metadata internal usdcToken;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));

        (address poolProvider, address weth, address usdc,) = AaveV3LendingProviderConfig.getConfig();

        simpleBorrow = new AaveV3SimpleBorrow(poolProvider);
        wethToken = IERC20Metadata(weth);
        usdcToken = IERC20Metadata(usdc);

        deal(address(wethToken), user, 2 ether);
    }

    function test_SupplyAndBorrow() public {
        uint256 supplyAmount = 1 ether;
        uint256 borrowAmount = 10_000_000; // 10 USDC

        vm.startPrank(user);

        wethToken.approve(address(simpleBorrow), supplyAmount);
        simpleBorrow.supply(address(wethToken), supplyAmount, 0);

        uint256 usdcBefore = usdcToken.balanceOf(user);
        simpleBorrow.borrow(address(usdcToken), borrowAmount, 0);
        uint256 usdcAfter = usdcToken.balanceOf(user);

        console.log("usdcBefore", usdcBefore);
        console.log("usdcAfter", usdcAfter);

        vm.stopPrank();

        assertEq(usdcAfter - usdcBefore, borrowAmount);
    }
}
