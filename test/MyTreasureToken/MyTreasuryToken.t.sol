// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MyTreasuryToken} from "../../src/contracts/MyTreasureToken/MyTreasuryToken.sol";
import {MockMToken} from "./MockMToken.t.sol";

contract MyTreasuryTokenTest is Test {
    MyTreasuryToken token;
    MockMToken mockMToken;
    address proxyAdmin = makeAddr("proxyAdmin");
    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address user = makeAddr("user");
    address pauser = makeAddr("pauser");
    address swapFacility = makeAddr("swapFacility");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_MAINNET_FORK_URL"));
        vm.startPrank(admin);

        mockMToken = new MockMToken();

        console.log("mockMToken address:", address(mockMToken));

        MyTreasuryToken implementation = new MyTreasuryToken(
            address(mockMToken), // M Token address
            swapFacility // SwapFacility address
        );

        bytes memory initData = abi.encodeWithSelector(
            MyTreasuryToken.initialize.selector,
            "My Treasury USD",
            "tUSD",
            treasury, // Yield recipient
            admin, // Admin
            admin, // Freeze manager
            admin, // Yield recipient manager
            pauser
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initData);

        token = MyTreasuryToken(address(proxy));

        token.enableEarning();
    }

    function testFreezing() public {
        // Test freezing functionality
        vm.startPrank(admin);
        token.freeze(user);
        assertTrue(token.isFrozen(user));
        vm.stopPrank();
    }

    function testYieldRecipientChange() public {
        // Test changing yield recipient
        vm.startPrank(admin);
        address newTreasury = makeAddr("newTreasury");

        token.setYieldRecipient(newTreasury);
        assertEq(token.yieldRecipient(), newTreasury);
        vm.stopPrank();
    }
}
