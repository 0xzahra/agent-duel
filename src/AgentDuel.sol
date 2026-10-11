// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Agent Duel
/// @notice A FREE, informational scoreboard. Two participants (agents or people) each seal a
///         prediction on the same question as a hash, reveal it later, and once the question's
///         resolver (its creator) posts the outcome the contract records who was right and keeps
///         per-address win / loss / draw counts.
/// @dev    NO payments, NO stakes, NO token, NO custody. There is no payable function and no
///         receive/fallback, so plain ETH transfers revert. There is no owner, admin or upgrade path.
///         IMD usage (read-only): a question may require a minimum Base IMD balance and/or an
///         Identity.md NFT to commit, and the scoreboard view shows an Identity.md holder badge.
///         All IMD reads are low-level staticcalls that never revert the caller.

contract AgentDuel {
    /// @notice Sealed-hash: keccak256(abi.encode(questionId, prediction, salt, participant)).
    /// @dev The questionId is included (on top of prediction, salt, address) so a hash cannot be replayed
    ///      on another question.
    struct Question {
        address resolver;       // question creator; the only one who can post the outcome
        uint64 commitDeadline;  // commits accepted until this time (or until two have committed)
        uint64 revealDeadline;  // reveals accepted until this time
        uint256 minImd;         // min Base IMD balance (wei) needed to commit; 0 = no gate
        bool requireSeat;       // true = committer must hold an Identity.md NFT
        bool resolved;
        uint8 outcome;
        uint8 count;            // number of commitments (max 2)
    }

    struct Entry {
        bytes32 commitment;
        bool revealed;
        uint8 prediction;
    }

    /// @notice Base IMD ERC-20 (read-only). address(0) disables IMD checks.
    address public immutable imdToken;
    /// @notice Identity.md ERC-721 (read-only). address(0) disables seat checks.
    address public immutable identityNft;

    uint256 public questionCount;
    mapping(uint256 => Question) public questions;
    mapping(uint256 => address[2]) public players;
    mapping(uint256 => mapping(address => Entry)) public entries;

    mapping(address => uint32) public wins;
    mapping(address => uint32) public losses;
    mapping(address => uint32) public draws;

    event QuestionCreated(uint256 indexed id, address indexed resolver, string text, uint64 commitDeadline, uint64 revealDeadline, uint256 minImd, bool requireSeat);
    /// @dev seatHolder / imdBalance are informational badges captured at commit time.
    event Committed(uint256 indexed id, address indexed player, bytes32 commitment, bool seatHolder, uint256 imdBalance);
    event Revealed(uint256 indexed id, address indexed player, uint8 prediction);
    event Resolved(uint256 indexed id, uint8 outcome);
    /// @dev result: 1 = win, 2 = loss, 3 = draw.
    event Result(uint256 indexed id, address indexed player, uint8 result);

    error BadTimes();
    error NotResolver();
    error ResolverCannotPlay();
    error CommitClosed();
    error AlreadyCommitted();
    error GateFailed();
    error RevealNotOpen();
    error RevealClosed();
    error NoCommitment();
    error AlreadyRevealed();
    error HashMismatch();
    error AlreadyResolved();
    error TooEarly();
    error NoQuestion();

    constructor(address imdToken_, address identityNft_) {
        imdToken = imdToken_;
        identityNft = identityNft_;
    }

    // ------------------------------------------------------------------ create
    /// @notice Create a question. The caller becomes its resolver.
    function createQuestion(string calldata text, uint64 commitDeadline, uint64 revealDeadline, uint256 minImd, bool requireSeat)
        external returns (uint256 id)
    {
        if (commitDeadline <= block.timestamp || revealDeadline <= commitDeadline) revert BadTimes();
        id = ++questionCount;
        questions[id] = Question(msg.sender, commitDeadline, revealDeadline, minImd, requireSeat, false, 0, 0);
        emit QuestionCreated(id, msg.sender, text, commitDeadline, revealDeadline, minImd, requireSeat);
    }

    // ------------------------------------------------------------------ commit
    /// @notice Helper to compute the sealed hash off-chain / in tests.
    function hashPrediction(uint256 id, uint8 prediction, bytes32 salt, address player) public pure returns (bytes32) {
        return keccak256(abi.encode(id, prediction, salt, player));
    }

    /// @notice Seal a prediction. First two committers are the duelists.
    function commit(uint256 id, bytes32 commitment) external {
        Question storage q = questions[id];
        if (q.resolver == address(0)) revert NoQuestion();
        if (block.timestamp >= q.commitDeadline || q.count >= 2) revert CommitClosed();
        if (msg.sender == q.resolver) revert ResolverCannotPlay();
        if (entries[id][msg.sender].commitment != bytes32(0) || commitment == bytes32(0)) revert AlreadyCommitted();

        uint256 bal = imdBalance(msg.sender);
        bool seat = isIdentityHolder(msg.sender);
        if (q.minImd > 0 && bal < q.minImd) revert GateFailed();
        if (q.requireSeat && !seat) revert GateFailed();

        entries[id][msg.sender].commitment = commitment;
        players[id][q.count] = msg.sender;
        q.count++;
        emit Committed(id, msg.sender, commitment, seat, bal);
    }

    // ------------------------------------------------------------------ reveal
    /// @notice Reveal once the commit phase is over (two committed, or commit deadline passed).
    function reveal(uint256 id, uint8 prediction, bytes32 salt) external {
        Question storage q = questions[id];
        if (q.count < 2 && block.timestamp < q.commitDeadline) revert RevealNotOpen();
        if (block.timestamp >= q.revealDeadline) revert RevealClosed();
        Entry storage e = entries[id][msg.sender];
        if (e.commitment == bytes32(0)) revert NoCommitment();
        if (e.revealed) revert AlreadyRevealed();
        if (hashPrediction(id, prediction, salt, msg.sender) != e.commitment) revert HashMismatch();
        e.revealed = true;
        e.prediction = prediction;
        emit Revealed(id, msg.sender, prediction);
    }

    // ------------------------------------------------------------------ resolve
    /// @notice Resolver posts the outcome (after reveals closed, or once both duelists revealed)
    ///         and the scoreboard is updated. Needs two duelists; otherwise the question is void.
    /// @dev Rules: only a revealed prediction equal to the outcome counts as right. One right and one
    ///      not (wrong or unrevealed) = win/loss. Both right or both not right = draw for both.
    function resolve(uint256 id, uint8 outcome) external {
        Question storage q = questions[id];
        if (msg.sender != q.resolver) revert NotResolver();
        if (q.resolved) revert AlreadyResolved();
        address a = players[id][0];
        address b = players[id][1];
        bool bothRevealed = q.count == 2 && entries[id][a].revealed && entries[id][b].revealed;
        if (!bothRevealed && block.timestamp < q.revealDeadline) revert TooEarly();

        q.resolved = true;
        q.outcome = outcome;
        emit Resolved(id, outcome);
        if (q.count < 2) return; // void: no duel happened

        bool aRight = entries[id][a].revealed && entries[id][a].prediction == outcome;
        bool bRight = entries[id][b].revealed && entries[id][b].prediction == outcome;
        if (aRight == bRight) {
            draws[a]++; draws[b]++;
            emit Result(id, a, 3); emit Result(id, b, 3);
        } else {
            (address w, address l) = aRight ? (a, b) : (b, a);
            wins[w]++; losses[l]++;
            emit Result(id, w, 1); emit Result(id, l, 2);
        }
    }

    // ------------------------------------------------------------------ IMD (read-only views)
    /// @notice Base IMD balance of `who`; 0 if disabled or the external call fails.
    function imdBalance(address who) public view returns (uint256) {
        return _balanceOf(imdToken, who);
    }

    /// @notice Identity.md holder badge: true if `who` owns at least one; false if disabled or the call fails.
    function isIdentityHolder(address who) public view returns (bool) {
        return _balanceOf(identityNft, who) > 0;
    }

    /// @notice Public scoreboard row for an address, with IMD badges.
    function scoreboard(address who) external view returns (uint32 w, uint32 l, uint32 d, uint256 imd, bool seatHolder) {
        return (wins[who], losses[who], draws[who], imdBalance(who), isIdentityHolder(who));
    }

    /// @dev Safe balanceOf: never reverts; bad/missing contract or short return data => 0. Gas-capped, output capped at 32 bytes.
    function _balanceOf(address token, address who) private view returns (uint256 r) {
        if (token == address(0) || token.code.length == 0) return 0;
        bytes memory callData = abi.encodeWithSelector(0x70a08231, who);
        bool ok; uint256 size;
        assembly {
            // copy at most 32 bytes of return data (no return-bomb)
            ok := staticcall(50000, token, add(callData, 32), mload(callData), 0, 32)
            size := returndatasize()
            if and(ok, iszero(lt(size, 32))) { r := mload(0) }
        }
    }
}
