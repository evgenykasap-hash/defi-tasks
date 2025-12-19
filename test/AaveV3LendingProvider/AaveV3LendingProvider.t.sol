// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {AaveV3LendingProvider} from "../../src/contracts/AaveV3LendingProvider/AaveV3LendingProvider.sol";
import {AaveV3LendingProviderConfig} from "../../src/scripts/AaveV3LendingProvider/AaveV3LendingProviderConfig.sol";
import {UniswapV3TWAPOracle} from "../../src/contracts/UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol";
import {UniswapV3TWAPOracleConfig} from "../../src/scripts/UniswapV3TWAPOracle/UniswapV3TWAPOracleConfig.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAaveV3LendingProvider} from "../../src/contracts/AaveV3LendingProvider/interfaces/IAaveV3LendingProvider.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract AaveV3LendingProviderTest is Test {
    uint256 constant AAVE_ORACLE_UNIT = 1e8;
    AaveV3LendingProvider internal provider;
    UniswapV3TWAPOracle internal uniswapV3TwapOracle;

    address user = makeAddr("user");

    IERC20Metadata internal wethToken;
    IERC20Metadata internal usdcToken;
    IERC20Metadata internal daiToken;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));
        vm.startPrank(user);

        (address poolProvider, address weth, address usdc, address dai) = AaveV3LendingProviderConfig.getConfig();

        uniswapV3TwapOracle = new UniswapV3TWAPOracle(UniswapV3TWAPOracleConfig.UNISWAP_V3_FACTORY);

        uniswapV3TwapOracle.setPool(
            uniswapV3TwapOracle.getPoolAddress(weth, usdc, UniswapV3TWAPOracleConfig.WETH_USDT_FEE), true
        );
        provider = new AaveV3LendingProvider(poolProvider);

        provider.addSupportedToken(weth);
        provider.addSupportedToken(usdc);
        provider.addSupportedToken(dai);

        wethToken = IERC20Metadata(weth);
        usdcToken = IERC20Metadata(usdc);
        daiToken = IERC20Metadata(dai);

        deal(address(wethToken), user, 1000000 ether);
        deal(address(usdcToken), user, 1000000 ether);
        deal(address(daiToken), user, 1000000 ether);

        vm.stopPrank();
    }

    function test_SupplyWeth() public {
        vm.startPrank(user);

        uint256 supplyAmount = 1 ether;

        wethToken.approve(address(provider), supplyAmount);
        provider.supply(address(wethToken), supplyAmount, 0);

        uint256 suppliedBalanceInUsdc = provider.getSuppliedBalanceCollateralFromAsset(address(wethToken));

        uint256 wethPriceInUsdc = uniswapV3TwapOracle.getAveragePrice(
            address(wethToken), address(usdcToken), UniswapV3TWAPOracleConfig.WETH_USDT_FEE, supplyAmount
        );

        wethPriceInUsdc = wethPriceInUsdc / (10 ** usdcToken.decimals());
        suppliedBalanceInUsdc = suppliedBalanceInUsdc / AAVE_ORACLE_UNIT;

        console.log("wethPriceInUsdc", wethPriceInUsdc);
        console.log("suppliedBalanceInUsdc", suppliedBalanceInUsdc);

        assertApproxEqAbs(suppliedBalanceInUsdc, wethPriceInUsdc, 30);

        vm.stopPrank();
    }

    function test_SupplyUsdc() public {
        vm.startPrank(user);

        uint256 supplyAmount = 30000000; // 30 USDC

        usdcToken.approve(address(provider), supplyAmount);
        provider.supply(address(usdcToken), supplyAmount, 0);

        uint256 suppliedBalanceInUsdc =
            provider.getSuppliedBalanceCollateralFromAsset(address(usdcToken)) / AAVE_ORACLE_UNIT;

        uint256 suppliedUsdc = supplyAmount / (10 ** usdcToken.decimals());

        console.log("suppliedUsdc", suppliedUsdc);
        console.log("suppliedBalanceInUsdc", suppliedBalanceInUsdc);

        assertApproxEqAbs(suppliedBalanceInUsdc, suppliedUsdc, 30);

        vm.stopPrank();
    }

    function test_BorrowWeth() public {
        vm.startPrank(user);

        uint256 borrowAmount = 1 ether;
        uint256 borrowAmountPrice = uniswapV3TwapOracle.getAveragePrice(
            address(wethToken), address(usdcToken), UniswapV3TWAPOracleConfig.WETH_USDT_FEE, borrowAmount
        );

        uint256 supplyAmount = borrowAmountPrice * 2;

        usdcToken.approve(address(provider), supplyAmount);
        provider.supply(address(usdcToken), supplyAmount, 0);

        provider.borrow(address(wethToken), borrowAmount, 0);

        uint256 borrowedWethAmount = provider.getVariableDebtBalanceFromAsset(address(wethToken));

        borrowAmountPrice = borrowAmountPrice / (10 ** usdcToken.decimals());
        borrowedWethAmount = borrowedWethAmount / AAVE_ORACLE_UNIT;

        assertApproxEqAbs(borrowedWethAmount, borrowAmountPrice, 30);

        console.log("borrowedWethAmount", borrowedWethAmount);
        console.log("borrowAmountPrice", borrowAmountPrice);
    }

    function test_InsufficientCollateral() public {
        vm.startPrank(user);

        uint256 borrowAmount = 1 ether;

        // no total supplied collateral
        wethToken.approve(address(provider), borrowAmount);

        vm.expectRevert(IAaveV3LendingProvider.InsufficientCollateral.selector);
        provider.borrow(address(wethToken), borrowAmount, 0);

        vm.stopPrank();
    }

    function test_InsufficientAvailableBorrows() public {
        vm.startPrank(user);
        uint256 supplyAmount = 1 ether;
        uint256 borrowAmount = supplyAmount * 2;

        wethToken.approve(address(provider), borrowAmount);
        provider.supply(address(wethToken), supplyAmount, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IAaveV3LendingProvider.InsufficientAvailableBorrows.selector, borrowAmount)
        );
        provider.borrow(address(wethToken), borrowAmount, 0);

        vm.stopPrank();
    }

    function test_WithdrawWeth() public {
        vm.startPrank(user);

        uint256 supplyAmount = 2 ether;
        uint256 withdrawAmount = 1 ether;

        wethToken.approve(address(provider), supplyAmount);
        provider.supply(address(wethToken), supplyAmount, 0);

        uint256 userWethBalanceBeforeWithdraw = wethToken.balanceOf(user);
        console.log("userWethBalanceBeforeWithdraw", userWethBalanceBeforeWithdraw);

        uint256 withdrawnAmount = provider.withdraw(address(wethToken), withdrawAmount);
        uint256 userWethBalanceAfterWithdraw = wethToken.balanceOf(user);

        console.log("userWethBalanceAfterWithdraw", userWethBalanceAfterWithdraw);

        assertEq(userWethBalanceAfterWithdraw, userWethBalanceBeforeWithdraw + withdrawnAmount);

        vm.stopPrank();
    }

    function test_RepayWeth() public {
        vm.startPrank(user);

        uint256 supplyAmount = 10000000000;
        uint256 repayAmount = 1 ether;

        usdcToken.approve(address(provider), supplyAmount);
        provider.supply(address(usdcToken), supplyAmount, 0);

        wethToken.approve(address(provider), repayAmount);
        provider.borrow(address(wethToken), repayAmount, 0);

        uint256 userWethBalanceBeforeRepay = wethToken.balanceOf(user);
        console.log("userWethBalanceBeforeRepay", userWethBalanceBeforeRepay);

        uint256 repaidAmount = provider.repay(address(wethToken), repayAmount / 2);

        uint256 userWethBalanceAfterRepay = wethToken.balanceOf(user);
        console.log("userWethBalanceAfterRepay", userWethBalanceAfterRepay);

        assertEq(userWethBalanceAfterRepay + repaidAmount, userWethBalanceBeforeRepay);

        vm.stopPrank();
    }

    function test_setEModeByOwner() public {
        vm.startPrank(user);
        provider.setEMode(0);
        assertEq(provider.getEModeCategory(), 0);
        vm.stopPrank();
    }

    function test_setEModeByNonOwnerReverts() public {
        address stranger = makeAddr("stranger");

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        provider.setEMode(0);
        vm.stopPrank();
    }
}
