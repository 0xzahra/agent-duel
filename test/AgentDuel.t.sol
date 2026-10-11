// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../src/AgentDuel.sol";

contract MockBal { mapping(address=>uint256) public balanceOf; function set(address a,uint256 v) external {balanceOf[a]=v;} }
contract Reverting { fallback() external { revert(); } }
contract Garbage { fallback() external { assembly { mstore(0,1) return(0,8) } } }

contract AgentDuelTest is Test {
    AgentDuel d; MockBal imd; MockBal nft;
    address resolver = address(0xA11CE0);
    address alice = address(0xA1); address bob = address(0xB0B);
    bytes32 sa = keccak256("sa"); bytes32 sb = keccak256("sb");
    uint256 id;

    function setUp() public {
        imd = new MockBal(); nft = new MockBal();
        d = new AgentDuel(address(imd), address(nft));
        vm.prank(resolver);
        id = d.createQuestion("Will X happen?", uint64(block.timestamp+100), uint64(block.timestamp+200), 0, false);
    }
    function _commit(address p, uint8 pred, bytes32 s) internal { bytes32 h = d.hashPrediction(id,pred,s,p); vm.prank(p); d.commit(id,h); }
    function _reveal(address p, uint8 pred, bytes32 s) internal { vm.prank(p); d.reveal(id,pred,s); }

    function test_commitAndReveal() public {
        _commit(alice,1,sa); _commit(bob,0,sb);
        _reveal(alice,1,sa);
        (,bool rev,uint8 p) = d.entries(id,alice);
        assertTrue(rev); assertEq(p,1);
    }
    function test_wrongHashRejected() public {
        _commit(alice,1,sa); _commit(bob,0,sb);
        vm.prank(alice); vm.expectRevert(AgentDuel.HashMismatch.selector); d.reveal(id,0,sa);
        vm.prank(alice); vm.expectRevert(AgentDuel.HashMismatch.selector); d.reveal(id,1,sb);
        // another address cannot reuse alice's hash
        vm.prank(bob); vm.expectRevert(AgentDuel.HashMismatch.selector); d.reveal(id,1,sa);
    }
    function test_doubleRevealRejected() public {
        _commit(alice,1,sa); _commit(bob,0,sb);
        _reveal(alice,1,sa);
        vm.prank(alice); vm.expectRevert(AgentDuel.AlreadyRevealed.selector); d.reveal(id,1,sa);
    }
    function test_cannotRevealBeforeCommitPhaseEnds() public {
        _commit(alice,1,sa);
        vm.prank(alice); vm.expectRevert(AgentDuel.RevealNotOpen.selector); d.reveal(id,1,sa);
        vm.warp(block.timestamp+100); _reveal(alice,1,sa); // deadline passed: ok
    }
    function test_doubleCommitAndThirdRejected() public {
        _commit(alice,1,sa);
        bytes32 h = d.hashPrediction(id,1,sa,alice);
        vm.prank(alice); vm.expectRevert(AgentDuel.AlreadyCommitted.selector); d.commit(id,h);
        _commit(bob,0,sb);
        vm.prank(address(0xC4)); vm.expectRevert(AgentDuel.CommitClosed.selector); d.commit(id,h);
    }
    function test_resolverCannotPlay() public {
        vm.prank(resolver); vm.expectRevert(AgentDuel.ResolverCannotPlay.selector); d.commit(id,bytes32(uint256(1)));
    }
    function test_resolveWinLoss() public {
        _commit(alice,1,sa); _commit(bob,0,sb); _reveal(alice,1,sa); _reveal(bob,0,sb);
        vm.prank(resolver); d.resolve(id,1); // both revealed -> allowed early
        assertEq(d.wins(alice),1); assertEq(d.losses(bob),1);
        assertEq(d.wins(bob),0); assertEq(d.losses(alice),0);
        vm.prank(resolver); vm.expectRevert(AgentDuel.AlreadyResolved.selector); d.resolve(id,1);
    }
    function test_onlyResolverResolves() public {
        _commit(alice,1,sa); _commit(bob,0,sb); _reveal(alice,1,sa); _reveal(bob,0,sb);
        vm.prank(alice); vm.expectRevert(AgentDuel.NotResolver.selector); d.resolve(id,1);
    }
    function test_resolveTooEarly() public {
        _commit(alice,1,sa); _commit(bob,0,sb); _reveal(alice,1,sa);
        vm.prank(resolver); vm.expectRevert(AgentDuel.TooEarly.selector); d.resolve(id,1);
    }
    function test_unrevealedLoses() public {
        _commit(alice,1,sa); _commit(bob,0,sb); _reveal(bob,0,sb);
        vm.warp(block.timestamp+200);
        vm.prank(resolver); d.resolve(id,0);
        assertEq(d.wins(bob),1); assertEq(d.losses(alice),1);
    }
    function test_drawWhenBothWrongOrBothRight() public {
        _commit(alice,1,sa); _commit(bob,1,sb); _reveal(alice,1,sa); _reveal(bob,1,sb);
        vm.prank(resolver); d.resolve(id,1);
        assertEq(d.draws(alice),1); assertEq(d.draws(bob),1); assertEq(d.wins(alice),0);
    }
    function test_countsAccumulateAcrossQuestions() public {
        _commit(alice,1,sa); _commit(bob,0,sb); _reveal(alice,1,sa); _reveal(bob,0,sb);
        vm.prank(resolver); d.resolve(id,1);
        vm.prank(resolver); uint256 id2 = d.createQuestion("Q2", uint64(block.timestamp+100), uint64(block.timestamp+200), 0, false);
        bytes32 ha = d.hashPrediction(id2,0,sa,alice); bytes32 hb = d.hashPrediction(id2,1,sb,bob);
        vm.prank(alice); d.commit(id2, ha);
        vm.prank(bob); d.commit(id2, hb);
        vm.prank(alice); d.reveal(id2,0,sa); vm.prank(bob); d.reveal(id2,1,sb);
        vm.prank(resolver); d.resolve(id2,1); // bob right
        assertEq(d.wins(alice),1); assertEq(d.losses(alice),1); assertEq(d.wins(bob),1); assertEq(d.losses(bob),1);
    }
    function test_voidIfOnlyOnePlayer() public {
        _commit(alice,1,sa); vm.warp(block.timestamp+200);
        vm.prank(resolver); d.resolve(id,1);
        assertEq(d.wins(alice),0); assertEq(d.losses(alice),0); assertEq(d.draws(alice),0);
    }
    function test_imdGateAndSeatGate() public {
        vm.prank(resolver); uint256 g = d.createQuestion("gated", uint64(block.timestamp+100), uint64(block.timestamp+200), 5 ether, true);
        bytes32 h = d.hashPrediction(g,1,sa,alice);
        vm.prank(alice); vm.expectRevert(AgentDuel.GateFailed.selector); d.commit(g,h);
        imd.set(alice,5 ether);
        vm.prank(alice); vm.expectRevert(AgentDuel.GateFailed.selector); d.commit(g,h); // still no seat
        nft.set(alice,1);
        vm.prank(alice); d.commit(g,h);
        (,,,uint256 bal,bool seat) = d.scoreboard(alice);
        assertEq(bal,5 ether); assertTrue(seat);
    }
    function test_externalCallFailureDoesNotRevertViews() public {
        AgentDuel a = new AgentDuel(address(new Reverting()), address(new Garbage()));
        assertEq(a.imdBalance(alice),0); assertFalse(a.isIdentityHolder(alice));
        AgentDuel z = new AgentDuel(address(0), address(0xdead)); // disabled / no code
        assertEq(z.imdBalance(alice),0); assertFalse(z.isIdentityHolder(alice));
        // ungated question still works with broken IMD contracts
        vm.prank(resolver); uint256 q = a.createQuestion("x", uint64(block.timestamp+100), uint64(block.timestamp+200),0,false);
        bytes32 h = a.hashPrediction(q,1,sa,alice);
        vm.prank(alice); a.commit(q, h);
    }
    function test_noEthAccepted() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice); (bool ok,) = address(d).call{value: 1 wei}(""); assertFalse(ok);
        vm.prank(alice); (ok,) = address(d).call{value: 1 wei}(abi.encodeWithSignature("commit(uint256,bytes32)", id, bytes32(uint256(1)))); assertFalse(ok);
        vm.prank(alice); (ok,) = address(d).call{value: 1 wei}(hex"deadbeef"); assertFalse(ok);
        assertEq(address(d).balance, 0);
    }
    function test_badTimesRejected() public {
        vm.expectRevert(AgentDuel.BadTimes.selector);
        d.createQuestion("x", uint64(block.timestamp), uint64(block.timestamp+5), 0, false);
        vm.expectRevert(AgentDuel.BadTimes.selector);
        d.createQuestion("x", uint64(block.timestamp+5), uint64(block.timestamp+5), 0, false);
    }
}
