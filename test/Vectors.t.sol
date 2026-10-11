// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../src/AgentDuel.sol";

/// Compares commitments computed by the web page's JS (tools/gen-vectors.js -> test/vectors.json)
/// with the contract's hashPrediction, and also does a real commit+reveal with a JS hash.
contract VectorsTest is Test {
    AgentDuel d;
    function setUp() public { d = new AgentDuel(address(0), address(0)); }

    function test_jsHashMatchesContract() public view {
        string memory j = vm.readFile("test/vectors.json");
        uint256 n = 40;
        for (uint256 i = 0; i < n; i++) {
            string memory p = string.concat("$[", vm.toString(i), "]");
            uint256 id = uint256(abi.decode(vm.parseJson(j, string.concat(p, ".id")), (bytes32)));
            uint8 pred = uint8(abi.decode(vm.parseJson(j, string.concat(p, ".pred")), (uint256)));
            bytes32 salt = abi.decode(vm.parseJson(j, string.concat(p, ".salt")), (bytes32));
            address who = abi.decode(vm.parseJson(j, string.concat(p, ".player")), (address));
            bytes32 h = abi.decode(vm.parseJson(j, string.concat(p, ".hash")), (bytes32));
            assertEq(d.hashPrediction(id, pred, salt, who), h, "JS hash != contract hash");
        }
    }

    function test_jsHashWorksOnChain() public {
        string memory j = vm.readFile("test/vectors.json");
        // vector 1: id=2 in the generator pattern; use a fresh question and recompute check via real flow
        address resolver = address(0xBEEF); address a = address(0xA1); address b = address(0xB2);
        vm.prank(resolver);
        uint256 id = d.createQuestion("q", uint64(block.timestamp + 10), uint64(block.timestamp + 20), 0, false);
        assertEq(id, 1);
        // vectors with id "1" and player 0xA1 exist at i where i%5==0 && i%3==0 => i=0,15,30
        bytes32 salt = abi.decode(vm.parseJson(j, "$[0].salt"), (bytes32));
        uint8 pred = uint8(abi.decode(vm.parseJson(j, "$[0].pred"), (uint256)));
        address who = abi.decode(vm.parseJson(j, "$[0].player"), (address));
        bytes32 h = abi.decode(vm.parseJson(j, "$[0].hash"), (bytes32));
        assertEq(who, a);
        vm.prank(a); d.commit(1, h);
        vm.prank(b); d.commit(1, keccak256("other"));
        vm.prank(a); d.reveal(1, pred, salt); // would revert HashMismatch if JS hash differed
        (, bool rev,) = d.entries(1, a);
        assertTrue(rev);
    }
}
