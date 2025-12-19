// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {MYieldToOne} from "evm-m-extensions/src/projects/yieldToOne/MYieldToOne.sol";

contract MyTreasuryToken is MYieldToOne {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address mToken_, address swapFacility_) MYieldToOne(mToken_, swapFacility_) {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address yieldRecipient_,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser
    ) public override initializer {
        MYieldToOne.initialize(
            name, // "My Treasury USD"
            symbol, // "tUSD"
            yieldRecipient_, // Treasury wallet address
            admin, // Admin multisig address
            freezeManager, // Freeze manager address (can be same as admin)
            yieldRecipientManager, // Yield recipient manager address
            pauser
        );
    }
}
