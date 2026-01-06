// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IMTokenLike} from "@evm-m-extensions/src/interfaces/IMTokenLike.sol";

contract MockMToken is IMTokenLike {
    mapping(address => uint256) internal balances;
    mapping(address => mapping(address => uint256)) internal allowances;
    mapping(address => bool) internal earning;

    uint128 internal index = 1e18;

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256,
        /* deadline */
        uint8,
        /* v */
        bytes32,
        /* r */
        bytes32 /* s */
    )
        external
        override
    {
        allowances[owner][spender] = value;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256,
        /* deadline */
        bytes memory /* signature */
    )
        external
        override
    {
        allowances[owner][spender] = value;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if (sender != msg.sender) {
            uint256 allowed = allowances[sender][msg.sender];
            if (allowed < amount) revert();
            allowances[sender][msg.sender] = allowed - amount;
        }

        _transfer(sender, recipient, amount);
        return true;
    }

    function startEarning() external override {
        earning[msg.sender] = true;
    }

    function stopEarning(address account) external override {
        earning[account] = false;
    }

    function isEarning(address account) external view override returns (bool) {
        return earning[account];
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    function principalBalanceOf(address account) external view override returns (uint240) {
        return uint240(balances[account]);
    }

    function currentIndex() external view override returns (uint128) {
        return index;
    }

    function earnerRate() external pure override returns (uint32) {
        return 0;
    }

    function DOMAIN_SEPARATOR() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function PERMIT_TYPEHASH() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function updateIndex() external view override returns (uint128) {
        return index;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert();
        uint256 senderBalance = balances[sender];
        if (senderBalance < amount) revert();

        unchecked {
            balances[sender] = senderBalance - amount;
            balances[recipient] += amount;
        }
    }
}
