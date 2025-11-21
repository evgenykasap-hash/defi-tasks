// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AaveV3LendingProvider} from "../AaveV3LendingProvider.sol";
import {AaveV3LendingProviderConfig} from "../AaveV3LendingProviderConfig.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract AaveV3LendingProviderTest is Test {
    AaveV3LendingProvider internal provider;

    address internal wethAddress;
    address internal usdcAddress;
    address internal daiAddress;

    IWETH internal weth;
    IERC20 internal usdc;
    IERC20 internal dai;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));
        vm.deal(address(this), 1_000 ether);

        (
            address poolProvider,
            address[] memory tokens
        ) = AaveV3LendingProviderConfig.getConfig();

        provider = new AaveV3LendingProvider(poolProvider, tokens);

        wethAddress = tokens[0];
        usdcAddress = tokens[1];
        daiAddress = tokens[2];

        weth = IWETH(wethAddress);
        usdc = IERC20(usdcAddress);
        dai = IERC20(daiAddress);

        vm.label(address(provider), "AaveProvider");
        vm.label(wethAddress, "WETH");
        vm.label(usdcAddress, "USDC");
        vm.label(daiAddress, "DAI");
    }

    function testSupplyAndWithdrawWeth() public {
        uint256 depositAmount = 2 ether;

        _fundProviderWithWeth(depositAmount);
        provider.approveToken(wethAddress, depositAmount);

        (uint256 collateralBefore, , , , , ) = provider.getUserAccountData(
            address(provider)
        );

        provider.supply(wethAddress, depositAmount, 0);

        assertEq(
            weth.balanceOf(address(provider)),
            0,
            "Provider balance should be lent out"
        );

        (uint256 collateralAfter, , , , , ) = provider.getUserAccountData(
            address(provider)
        );

        assertGt(collateralAfter, collateralBefore, "Collateral should grow");

        uint256 withdrawn = provider.withdraw(wethAddress, type(uint256).max);

        assertGt(withdrawn, 0, "Withdraw should return some funds");
        assertApproxEqAbs(
            withdrawn,
            depositAmount,
            1e12,
            "Withdrawn amount should roughly equal supplied amount"
        );
        assertApproxEqAbs(
            weth.balanceOf(address(provider)),
            withdrawn,
            1e12,
            "Provider should hold the withdrawn WETH"
        );
    }

    function testBorrowAndRepayUsdc() public {
        uint256 collateralAmount = 5 ether;
        uint256 borrowAmount = 1000 * 1e6;

        _fundProviderWithWeth(collateralAmount);
        provider.approveToken(wethAddress, collateralAmount);
        provider.supply(wethAddress, collateralAmount, 0);

        uint256 usdcBefore = usdc.balanceOf(address(provider));

        provider.borrow(usdcAddress, borrowAmount, 0);

        uint256 usdcAfter = usdc.balanceOf(address(provider));

        assertEq(
            usdcAfter - usdcBefore,
            borrowAmount,
            "Borrow should credit provider with USDC"
        );

        provider.approveToken(usdcAddress, borrowAmount);
        uint256 repaid = provider.repay(usdcAddress, borrowAmount);

        assertEq(repaid, borrowAmount, "Repay amount should match input");
        assertEq(
            usdc.balanceOf(address(provider)),
            usdcBefore,
            "USDC balance should be restored after repayment"
        );

        (, , , uint256 threshold, , uint256 health) = provider
            .getUserAccountData(address(provider));
        assertGt(threshold, 0, "Collateral configuration should remain active");
        assertGt(health, 1e18, "Position should remain healthy after repay");
    }

    function testApproveAndAllowanceHelpers() public {
        uint256 approveAmount = 1 ether;

        _fundProviderWithWeth(approveAmount);
        provider.approveToken(wethAddress, approveAmount);

        uint256 allowance = provider.allowanceToken(wethAddress);
        assertEq(
            allowance,
            approveAmount,
            "Allowance helper should reflect set value"
        );
    }

    function _fundProviderWithWeth(uint256 amount) internal {
        weth.deposit{value: amount}();

        bool success = weth.transfer(address(provider), amount);
        assertTrue(success, "Funding provider with WETH failed");
    }
}
