// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {MyTreasuryToken} from "../../contracts/MyTreasureToken/MyTreasuryToken.sol";

contract DeployMyTreasuryToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploying a Transparent Proxy, which requires a proxy admin.
        address proxy = Upgrades.deployTransparentProxy(
            "MyTreasuryToken.sol", // Contract file name
            deployer, // The admin for the proxy contract itself
            abi.encodeCall( // The initializer call data
                MyTreasuryToken.initialize,
                (
                    "My Treasury USD", // name
                    "tUSD", // symbol
                    0x1111111111111111111111111111111111111111, // yieldRecipient
                    0x2222222222222222222222222222222222222222, // admin (DEFAULT_ADMIN_ROLE for the logic)
                    0x3333333333333333333333333333333333333333, // freezeManager
                    0x4444444444444444444444444444444444444444, // yieldRecipientManager
                    0x5555555555555555555555555555555555555555 // pauser
                )
            )
        );

        vm.stopBroadcast();

        console.log("MyTreasuryToken deployed at:", proxy);
    }
}
