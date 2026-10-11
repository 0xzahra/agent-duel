// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Script.sol";
import "../src/AgentDuel.sol";

/// NOT RUN YET. Needs explicit approval + a fresh dedicated deployer key supplied by the owner at deploy time.
/// Base mainnet: real IMD + Identity.md. Base Sepolia (84532): those do not exist there, so pass zero addresses
/// (IMD checks disabled) via env IMD_TOKEN / IDENTITY_NFT.
contract Deploy is Script {
    function run() external {
        address imd = vm.envOr("IMD_TOKEN", address(0xFF0C532FDB8Cd566Ae169C1CB157ff2Bdc83E105));
        address nft = vm.envOr("IDENTITY_NFT", address(0x0000C0484F4626e368dFb909aBa107f7C97b6B1D));
        vm.startBroadcast();
        AgentDuel d = new AgentDuel(imd, nft);
        vm.stopBroadcast();
        console.log("AgentDuel:", address(d));
    }
}
