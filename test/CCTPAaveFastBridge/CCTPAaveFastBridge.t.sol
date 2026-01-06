// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CCTPAaveFastBridge} from "../../src/contracts/CCTPAaveFastBridge/CCTPAaveFastBridge.sol";
import {CCTPAaveFastBridgeConfig} from "../../src/scripts/CCTPAaveFastBridge/CCTPAaveFastBridgeConfig.sol";
import {AaveV3LendingProviderConfig} from "../../src/scripts/AaveV3LendingProvider/AaveV3LendingProviderConfig.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MockTokenMessenger {
    uint64 public nextNonce = 1;
    uint256 public lastAmount;
    uint32 public lastDestinationDomain;
    bytes32 public lastMintRecipient;
    address public lastBurnToken;
    address public lastCaller;

    function depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
        external
        returns (uint64)
    {
        lastAmount = amount;
        lastDestinationDomain = destinationDomain;
        lastMintRecipient = mintRecipient;
        lastBurnToken = burnToken;
        lastCaller = msg.sender;

        require(IERC20Minimal(burnToken).transferFrom(msg.sender, address(this), amount), "transfer failed");

        uint64 nonce = nextNonce;
        nextNonce += 1;
        return nonce;
    }
}

contract CCTPAaveFastBridgeTest is Test {
    address internal user = makeAddr("user");
    CCTPAaveFastBridge internal bridge;
    MockTokenMessenger internal tokenMessenger;

    IERC20Metadata internal wethToken;
    IERC20Metadata internal usdcToken;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));

        (address poolAddressesProvider,, address usdc) = CCTPAaveFastBridgeConfig.getConfig();

        tokenMessenger = new MockTokenMessenger();
        bridge = new CCTPAaveFastBridge(poolAddressesProvider, address(tokenMessenger), usdc);

        (, address weth,,) = AaveV3LendingProviderConfig.getConfig();

        wethToken = IERC20Metadata(weth);
        usdcToken = IERC20Metadata(usdc);

        deal(address(wethToken), user, 1000 ether);
        deal(address(usdcToken), user, 1000 ether);
    }

    function test_InitiateFastTransfer_UsdcDirectPath() public {
        uint256 amount = 10_000_000; // 10 USDC (6 decimals)
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        usdcToken.approve(address(bridge), amount);
        (uint64 nonce, uint256 bridgedAmount) =
            bridge.initiateFastTransfer(address(usdcToken), amount, 0, 6, mintRecipient);

        vm.stopPrank();

        assertEq(nonce, 1);
        assertEq(bridgedAmount, amount);
        assertEq(tokenMessenger.lastAmount(), amount);
        assertEq(tokenMessenger.lastDestinationDomain(), 6);
        assertEq(tokenMessenger.lastMintRecipient(), mintRecipient);
        assertEq(tokenMessenger.lastBurnToken(), address(usdcToken));
        assertEq(usdcToken.balanceOf(address(bridge)), 0);
        assertEq(bridge.getCurrentBorrow(address(usdcToken)), 0);
    }

    function test_InitiateFastTransfer_BorrowUsdcAndRepay() public {
        uint256 supplyAmount = 1 ether;
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        wethToken.approve(address(bridge), supplyAmount);
        (uint64 nonce, uint256 borrowedUsdcAmount) =
            bridge.initiateFastTransfer(address(wethToken), supplyAmount, 0, 6, mintRecipient);

        assertEq(nonce, 1);
        assertGt(borrowedUsdcAmount, 0);
        assertEq(tokenMessenger.lastAmount(), borrowedUsdcAmount);
        assertEq(tokenMessenger.lastBurnToken(), address(usdcToken));
        assertEq(usdcToken.balanceOf(address(bridge)), 0);

        uint256 currentBorrow = bridge.getCurrentBorrow(address(usdcToken));
        assertApproxEqAbs(currentBorrow, borrowedUsdcAmount, 2);

        deal(address(usdcToken), user, borrowedUsdcAmount + 1_000_000);
        usdcToken.approve(address(bridge), type(uint256).max);
        bridge.repayBorrow(address(usdcToken), type(uint256).max);

        assertEq(bridge.getCurrentBorrow(address(usdcToken)), 0);

        vm.stopPrank();
    }

    function test_RepayBorrow_PartialRepayment() public {
        uint256 supplyAmount = 1 ether;
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        // Initiate fast transfer to create debt
        wethToken.approve(address(bridge), supplyAmount);
        (, uint256 borrowedUsdcAmount) =
            bridge.initiateFastTransfer(address(wethToken), supplyAmount, 0, 6, mintRecipient);

        uint256 initialDebt = bridge.getCurrentBorrow(address(usdcToken));
        assertApproxEqAbs(initialDebt, borrowedUsdcAmount, 2);

        // Repay half of the debt
        uint256 repayAmount = borrowedUsdcAmount / 2;
        deal(address(usdcToken), user, repayAmount);
        usdcToken.approve(address(bridge), repayAmount);
        uint256 actualRepaid = bridge.repayBorrow(address(usdcToken), repayAmount);

        assertEq(actualRepaid, repayAmount);

        uint256 remainingDebt = bridge.getCurrentBorrow(address(usdcToken));
        assertApproxEqAbs(remainingDebt, borrowedUsdcAmount - repayAmount, 2);

        vm.stopPrank();
    }

    function test_RepayBorrow_ExactAmount() public {
        uint256 supplyAmount = 1 ether;
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        wethToken.approve(address(bridge), supplyAmount);
        bridge.initiateFastTransfer(address(wethToken), supplyAmount, 0, 6, mintRecipient);

        uint256 currentDebt = bridge.getCurrentBorrow(address(usdcToken));

        deal(address(usdcToken), user, currentDebt);
        usdcToken.approve(address(bridge), currentDebt);
        bridge.repayBorrow(address(usdcToken), currentDebt);

        assertEq(bridge.getCurrentBorrow(address(usdcToken)), 0);

        vm.stopPrank();
    }

    function test_RepayBorrow_MoreThanOwed() public {
        uint256 supplyAmount = 1 ether;
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        wethToken.approve(address(bridge), supplyAmount);
        bridge.initiateFastTransfer(address(wethToken), supplyAmount, 0, 6, mintRecipient);

        uint256 currentDebt = bridge.getCurrentBorrow(address(usdcToken));
        uint256 excessAmount = currentDebt * 2; // Try to repay 2x the debt

        deal(address(usdcToken), user, excessAmount);
        uint256 userBalanceBefore = usdcToken.balanceOf(user);

        usdcToken.approve(address(bridge), excessAmount);
        uint256 actualRepaid = bridge.repayBorrow(address(usdcToken), excessAmount);

        assertApproxEqAbs(actualRepaid, currentDebt, 1);
        assertEq(bridge.getCurrentBorrow(address(usdcToken)), 0);

        uint256 userBalanceAfter = usdcToken.balanceOf(user);
        assertApproxEqAbs(userBalanceAfter, userBalanceBefore - currentDebt, 1);

        vm.stopPrank();
    }

    function test_RepayBorrow_RevertZeroAmount() public {
        uint256 supplyAmount = 1 ether;
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        wethToken.approve(address(bridge), supplyAmount);
        bridge.initiateFastTransfer(address(wethToken), supplyAmount, 0, 6, mintRecipient);

        vm.expectRevert();
        bridge.repayBorrow(address(usdcToken), 0);

        vm.stopPrank();
    }

    function test_RepayBorrow_RevertNoDebt() public {
        vm.startPrank(user);

        deal(address(usdcToken), user, 1_000_000);
        usdcToken.approve(address(bridge), 1_000_000);

        vm.expectRevert();
        bridge.repayBorrow(address(usdcToken), 1_000_000);

        vm.stopPrank();
    }

    function test_RepayBorrow_MultipleRepayments() public {
        uint256 supplyAmount = 2 ether;
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        wethToken.approve(address(bridge), supplyAmount);
        (, uint256 borrowedUsdcAmount) =
            bridge.initiateFastTransfer(address(wethToken), supplyAmount, 0, 6, mintRecipient);

        uint256 initialDebt = bridge.getCurrentBorrow(address(usdcToken));

        // First repayment - 25%
        uint256 firstRepay = borrowedUsdcAmount / 4;
        deal(address(usdcToken), user, firstRepay);
        usdcToken.approve(address(bridge), firstRepay);
        bridge.repayBorrow(address(usdcToken), firstRepay);

        uint256 debtAfterFirst = bridge.getCurrentBorrow(address(usdcToken));
        assertLt(debtAfterFirst, initialDebt);

        uint256 secondRepay = borrowedUsdcAmount / 4;
        deal(address(usdcToken), user, secondRepay);
        usdcToken.approve(address(bridge), secondRepay);
        bridge.repayBorrow(address(usdcToken), secondRepay);

        uint256 debtAfterSecond = bridge.getCurrentBorrow(address(usdcToken));
        assertLt(debtAfterSecond, debtAfterFirst);

        uint256 remainingDebt = bridge.getCurrentBorrow(address(usdcToken));
        deal(address(usdcToken), user, remainingDebt + 1_000_000);
        usdcToken.approve(address(bridge), type(uint256).max);
        bridge.repayBorrow(address(usdcToken), type(uint256).max);

        assertEq(bridge.getCurrentBorrow(address(usdcToken)), 0);

        vm.stopPrank();
    }

    function test_GetCurrentBorrow_NoDebt() public {
        vm.startPrank(user);

        uint256 currentBorrow = bridge.getCurrentBorrow(address(usdcToken));
        assertEq(currentBorrow, 0);

        vm.stopPrank();
    }

    function test_GetCurrentBorrow_WithDebt() public {
        uint256 supplyAmount = 1 ether;
        bytes32 mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

        vm.startPrank(user);

        wethToken.approve(address(bridge), supplyAmount);
        (, uint256 borrowedUsdcAmount) =
            bridge.initiateFastTransfer(address(wethToken), supplyAmount, 0, 6, mintRecipient);

        uint256 currentBorrow = bridge.getCurrentBorrow(address(usdcToken));
        assertGt(currentBorrow, 0);
        assertApproxEqAbs(currentBorrow, borrowedUsdcAmount, 2);

        vm.stopPrank();
    }
}
