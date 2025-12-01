// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Extended} from "../../libraries/IERC20Extended.sol";
import {AaveV3LendingProvider} from "../AaveV3LendingProvider.sol";
import {AaveV3LendingProviderConfig} from "../AaveV3LendingProviderConfig.sol";

contract AaveV3LendingProviderTest is Test {
    AaveV3LendingProvider internal provider;

    address user = makeAddr("user");

    IERC20Extended internal wethToken;
    IERC20 internal usdcToken;
    IERC20 internal daiToken;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));
        vm.startPrank(user);
        vm.deal(user, 1_000 ether);

        (
            address poolProvider,
            address weth,
            address usdc,
            address dai
        ) = AaveV3LendingProviderConfig.getConfig();

        provider = new AaveV3LendingProvider(poolProvider);

        provider.addSupportedToken(weth);
        provider.addSupportedToken(usdc);
        provider.addSupportedToken(dai);

        wethToken = IERC20Extended(weth);
        usdcToken = IERC20(usdc);
        daiToken = IERC20(dai);

        vm.stopPrank();
    }

    // function testWethSupply() public {
    //     vm.startPrank(user);

    //     uint256 supplyAmount = 2 ether;

    //     wethToken.deposit{value: supplyAmount}();
    //     wethToken.approve(address(provider), supplyAmount);
    //     provider.supply(address(wethToken), supplyAmount, 0);

    //     uint256 suppliedWethBalance = provider.getSuppliedBalance(
    //         address(wethToken)
    //     );
    //     console.log("suppliedWethBalance", suppliedWethBalance);

    //     assertApproxEqAbs(suppliedWethBalance, supplyAmount, 10);

    //     vm.stopPrank();
    // }

    // function testWethWithdraw() public {
    //     vm.startPrank(user);

    //     uint256 userBalance = 2 ether;
    //     uint256 amountToWithdraw = 1 ether;

    //     (
    //         uint256 totalCollateralBase,
    //         ,
    //         uint256 availableBorrowsBase,
    //         ,
    //         ,

    //     ) = provider.getUserAccountData(address(provider));

    //     console.log("totalCollateralBase", totalCollateralBase);
    //     console.log("availableBorrowsBase", availableBorrowsBase);

    //     wethToken.deposit{value: userBalance}();
    //     wethToken.approve(address(provider), userBalance);
    //     provider.supply(address(wethToken), userBalance, 0);

    //     (
    //         uint256 totalCollateralBaseAfter,
    //         ,
    //         uint256 availableBorrowsBaseAfter,
    //         ,
    //         ,

    //     ) = provider.getUserAccountData(address(provider));

    //     console.log("totalCollateralBaseAfter", totalCollateralBaseAfter);
    //     console.log("availableBorrowsBaseAfter", availableBorrowsBaseAfter);

    //     uint256 withdrawnAmount = provider.withdraw(
    //         address(wethToken),
    //         amountToWithdraw
    //     );

    //     (
    //         uint256 totalCollateralBaseAfterWithdraw,
    //         ,
    //         uint256 availableBorrowsBaseAfterWithdraw,
    //         ,
    //         ,

    //     ) = provider.getUserAccountData(address(provider));

    //     console.log(
    //         "totalCollateralBaseAfterWithdraw",
    //         totalCollateralBaseAfterWithdraw
    //     );
    //     console.log(
    //         "availableBorrowsBaseAfterWithdraw",
    //         availableBorrowsBaseAfterWithdraw
    //     );

    //     console.log("withdrawnAmount: ", withdrawnAmount);

    //     assertApproxEqAbs(withdrawnAmount, amountToWithdraw, 10);

    //     vm.stopPrank();
    // }

    // function testWethWithdrawAll() public {
    //     vm.startPrank(user);

    //     uint256 userBalance = 1 ether;
    //     uint256 amountToWithdraw = 2 ether;

    //     wethToken.deposit{value: userBalance}();
    //     wethToken.approve(address(provider), userBalance);
    //     provider.supply(address(wethToken), userBalance, 0);

    //     uint256 suppliedBalanceBefore = provider.getSuppliedBalance(
    //         address(wethToken)
    //     );

    //     uint256 withdrawnAmount = provider.withdraw(
    //         address(wethToken),
    //         amountToWithdraw
    //     );

    //     uint256 suppliedBalanceAfter = provider.getSuppliedBalance(
    //         address(wethToken)
    //     );

    //     assertEq(suppliedBalanceAfter, 0);
    //     assertApproxEqAbs(withdrawnAmount, suppliedBalanceBefore, 10);

    //     vm.stopPrank();
    // }

    // function testWethBorrow() public {
    //     vm.startPrank(user);

    //     uint256 borrowAmount = 1 ether;
    //     uint256 supplyAmount = 2 ether;

    //     wethToken.deposit{value: supplyAmount}();
    //     wethToken.approve(address(provider), supplyAmount);
    //     provider.supply(address(wethToken), supplyAmount, 0);

    //     provider.borrow(address(wethToken), borrowAmount, 0);

    //     uint256 wethBalance = wethToken.balanceOf(address(provider));

    //     vm.stopPrank();
    // }
}
