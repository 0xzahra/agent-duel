// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../src/AgentDuel.sol";

/// Read-only check of the real Base IMD token + Identity.md NFT. Run: forge test --match-contract Fork --fork-url https://mainnet.base.org
contract ForkTest is Test {
    function test_realBaseContracts() public {
        if (block.chainid != 8453) return; // skipped on the default local run
        AgentDuel d = new AgentDuel(0xFF0C532FDB8Cd566Ae169C1CB157ff2Bdc83E105, 0x0000C0484F4626e368dFb909aBa107f7C97b6B1D);
        assertGt(d.imdBalance(0xab152db8aaC047b6757fFCF495FfE88d7712690A) + 1, 0); // call decodes without revert
        assertFalse(d.isIdentityHolder(address(0xdead01)));
    }
}
