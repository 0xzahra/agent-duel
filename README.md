# Agent Duel

**Deployed on Base:** `0xAAa9DED4E50Ca82E3C32444EA836940612a9FB96` — [BaseScan](https://basescan.org/address/0xAAa9DED4E50Ca82E3C32444EA836940612a9FB96)

A **free, informational scoreboard** on Base for head-to-head predictions between two participants (AI agents or people).

## What it does (plain English)
1. Someone creates a **question** ("Will X happen by Friday?"). They become its **resolver** and set a commit deadline and a reveal deadline. Outcomes are small numbers (e.g. 0 = No, 1 = Yes).
2. Two participants each **commit** a sealed hash of their prediction: `keccak256(abi.encode(questionId, prediction, salt, theirAddress))`. Nobody can see the prediction, and the hash cannot be copied by another address or reused on another question. (`questionId` is added to the spec'd `(prediction, salt, address)` to stop cross-question replay.)
3. When both have committed (or the commit deadline passes), they **reveal** prediction + salt. A wrong hash is rejected; a second reveal is rejected.
4. The resolver **posts the outcome** (after reveals close, or as soon as both revealed). The contract records: one right + one wrong/unrevealed = **win / loss**; both right or both not right = **draw**. Only one duelist = question void. Counts are kept per address, forever.

There is **no money anywhere**: no payable function, no receive/fallback, no stakes, no token, no prize logic, no owner/admin, no upgrade. It is a reputation scoreboard only.

## How it uses IMD (read-only, never moves anything)
- Base IMD token `0xFF0C532FDB8Cd566Ae169C1CB157ff2Bdc83E105` (ERC-20, 18 decimals, verified on Base RPC 11 Oct 2026; on-chain name still "Fren Pet", symbol "IMD").
- Identity.md NFT on Base `0x0000C0484F4626e368dFb909aBa107f7C97b6B1D` (ERC-721, name "identity.md", `supportsInterface(0x80ac58cd)` = true, verified 11 Oct 2026).
- **Gate:** a question creator may require a minimum IMD balance and/or an Identity.md NFT to commit (`minImd`, `requireSeat`).
- **Badge:** `scoreboard(address)` and the `Committed` event expose Identity.md holder + IMD balance; the web page shows them.
- **Robust:** reads are gas-capped low-level `staticcall`s reading ≤32 bytes; revert / no code / short data => balance 0, never a revert. Failure on a gated question means "gate not passed" (fails closed); ungated questions are unaffected. Addresses are constructor immutables (zero address = IMD features off), because they don't exist on Base Sepolia.
- Note: IMD's own swarm/oracle does not support Base; this contract only reads the Base token/NFT.

## Layout
- `src/AgentDuel.sol` – the contract (~170 lines, Solidity 0.8.24)
- `test/AgentDuel.t.sol` – 17 tests; `test/Fork.t.sol` – read-only check against real Base contracts
- `script/Deploy.s.sol` – deploy script (not run)
- `web/index.html` – static scoreboard (ethers v6 from CDN, public Base RPC, no backend)

## Test
```
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge install foundry-rs/forge-std --no-git
forge test -vv
forge test --match-contract Fork --fork-url https://mainnet.base.org   # optional real-address check
```

## Deploy (needs Zahra's explicit approval first; use a fresh dedicated deployer wallet with a few cents of ETH)
Never paste a private key in chat/files. Use a hardware wallet or a Foundry keystore: `cast wallet import deployer --interactive`.

**Base Sepolia (84532)** – IMD token/NFT don't exist there, so IMD features are off:
```
IMD_TOKEN=0x0000000000000000000000000000000000000000 \
IDENTITY_NFT=0x0000000000000000000000000000000000000000 \
forge script script/Deploy.s.sol --rpc-url https://sepolia.base.org \
  --account deployer --broadcast
```
Then try the full flow with `cast send` (createQuestion, commit, reveal, resolve) from 3 test addresses, open `web/index.html?chain=sepolia&addr=<contract>`.

**Base mainnet (8453)** – real IMD + Identity.md (defaults in the script):
```
forge script script/Deploy.s.sol --rpc-url https://mainnet.base.org \
  --account deployer --broadcast --verify --etherscan-api-key $BASESCAN_KEY
```
(Or verify later: `forge verify-contract <addr> src/AgentDuel.sol:AgentDuel --chain base --constructor-args $(cast abi-encode "c(address,address)" 0xFF0C532FDB8Cd566Ae169C1CB157ff2Bdc83E105 0x0000C0484F4626e368dFb909aBa107f7C97b6B1D)`.)

Afterwards edit `DEPLOYED` and `FROM_BLOCK` (deployment block, important so the page doesn't scan from block 0) in `web/index.html`, host it on any static host, and submit the contract address on the hackathon form.

## Security self-review checklist
- [x] No payable functions, no receive/fallback; tests prove plain and function ETH sends revert. (ETH can still be force-sent via selfdestruct/coinbase; it is unrecoverable and harmless – nothing depends on balance.)
- [x] No owner, admin, proxy, delegatecall, selfdestruct, or external writes.
- [x] External calls only `staticcall` balanceOf, gas-capped, output ≤32 bytes, never revert.
- [x] Commit-reveal binds address + questionId + salt; reveal blocked until commit phase ends so a reveal cannot leak to the opponent before they commit.
- [x] Resolver can't resolve early unless both have revealed (prevents committing after the answer is known).
- [x] Resolver cannot be a duelist; double commit / third committer / double reveal / double resolve rejected.
- [x] Counters are uint32 (overflow reverts under 0.8).
- [ ] Not independently audited – treat as informational; run a Base Sepolia dry run first.
- [ ] Known limits (by design): the resolver is trusted and can post a false or never post an outcome (question just stays open); first two committers are the duelists (a sybil/friend can grab a slot – use gates or an agreed counterpart); outcomes are uint8; sybil accounts can farm wins; the IMD badge is a snapshot-free live read and can change after commit; hash is not secret if the salt is guessable – use a random 32-byte salt and keep it.
- [ ] Hackathon-side risks (from the brief): unpublished deadline/split/jury; prize pays to the deployer wallet (makes it public); entries can't be edited.

## Disclaimer
Informational only. Not financial advice, no wagering, no payouts.
