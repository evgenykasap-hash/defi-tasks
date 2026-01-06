// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

/// @notice Minimal 0.8-compatible interface for Circle's TokenMessenger.
/// @dev Mirrors `TokenMessenger.depositForBurn` in @evm-cctp-contracts.
interface ITokenMessenger {
    function depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
        external
        returns (uint64);
}
