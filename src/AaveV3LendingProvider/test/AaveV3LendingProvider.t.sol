// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20Extended} from "../../libraries/IERC20Extended.sol";
import {AaveV3LendingProvider} from "../AaveV3LendingProvider.sol";
import {AaveV3LendingProviderConfig} from "../AaveV3LendingProviderConfig.sol";

contract AaveV3LendingProviderTest is Test {
    AaveV3LendingProvider internal provider;

    address internal wethAddress;
    address internal usdcAddress;
    address internal daiAddress;

    address payable owner;

    IERC20Extended internal weth;
    IERC20Extended internal usdc;
    IERC20Extended internal dai;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));
        owner = payable(address(this));
        vm.startPrank(owner);
        vm.deal(address(owner), 1_000 ether);

        (address poolProvider, address[] memory tokens) = AaveV3LendingProviderConfig.getConfig();

        provider = new AaveV3LendingProvider(poolProvider, tokens);

        wethAddress = tokens[0];
        usdcAddress = tokens[1];
        daiAddress = tokens[2];

        weth = IERC20Extended(wethAddress);
        usdc = IERC20Extended(usdcAddress);
        dai = IERC20Extended(daiAddress);

        vm.label(address(provider), "AaveProvider");
        vm.label(wethAddress, "WETH");

        vm.stopPrank();
    }

    function testSupplyAndWithdrawWeth() public {
        vm.startPrank(owner);

        _fundProvider(wethAddress, 2 ether);

        uint256 aTokenBalance = provider.getBalance(wethAddress);

        console.log("aTokenBalance", aTokenBalance);

        vm.stopPrank();
    }

    function _fundProvider(address asset, uint256 amount) internal returns (uint256) {
        IERC20Extended(asset).deposit{value: amount}();
        IERC20Extended(asset).approve(address(provider), amount);

        return IERC20Extended(asset).balanceOf(address(provider));
    }
}
