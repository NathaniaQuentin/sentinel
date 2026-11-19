# Sentinel — build notes

Track 1, Reactive Omni Buildathon. Deadline 5 Dec 2026 (safe: 5 Dec 20:00 UTC
= 6 Dec 04:00 WITA). Testnets only, no real money.

## Status (19 Nov 2026, evening — DEPLOYED + LIVE-TESTED)

- [x] Contracts written, `forge build` clean (solc 0.8.29; only lint warnings)
- [x] Fork tests: **9/9 pass** (`forge test -vv`, Lasna + Unichain Sepolia forks)
  - stop-loss fires full exit; TP1 exits 50% then TP2 exits the rest;
    trailing stop fires on a 2% pullback from the high-water mark;
    order-cancel closes the reactive book; vault settlement math + clamp +
    duplicate-callback no-op; vault auth (proxy + reactive sender) enforced;
    MockOracle event shape matches Chainlink (`AnswerUpdated` indexed
    current/roundId)
- [x] Frontend written (single static page, ethers v6) — JS syntax checked
- [x] Deployment script written (`script/deploy.sh`) — ready to run
- [x] Video tooling verified (ffmpeg + playwright-core + cached Chromium;
      Chromium cannot reach external sites from this VM — explorer proof is
      rendered locally from live API data, see `video/VIDEO-PLAN.md`)
- [x] **Live testnet deployment + end-to-end run — DONE 19 Nov 2026 ~22:12 WITA**
  (stop-loss 100% exit + TP1 50% + TP2 rest, all executed by Reactive
  callbacks; 3,650 mUSDC paid out to the deployer; see below)
- [x] Sourcify verification — all 5 contracts VERIFIED
- [x] Demo video — recorded, `video/sentinel-demo.mp4` (2:34, 1280×720, 2.3 MB)
- [ ] DoraHacks registration + submission (browser step, parent)

### Deployment war stories (so the next run doesn't repeat them)

- `script/deploy.sh` step 2 hung: `cast call` prints the Chainlink tuple as
  ONE hex blob, so `awk '{print $2}'` was empty and bare `cast --to-dec`
  waited on stdin forever. Fixed in the script (parse word 2 with python).
- forge 1.9.0's `--constructor-args <ARGS>...` is greedy: it swallows any
  flag placed after it (`--json` got eaten as a 4th arg; `--rpc-url` got
  eaten and forge fell back to localhost:8545). `--constructor-args` must
  be LAST, with `--json`/`--broadcast` before it.
- `forge create` in 1.9.0 broadcasts by default (the `--broadcast` flag is
  redundant). The first MockWETH deploy went out from a "dry-run" command.
- The public Sepolia/Unichain RPCs are flaky: a tx can return a spurious
  "nonce too low" error yet still land on-chain (MockUSDC did). Always
  verify on-chain (explorer API / `cast code`) instead of trusting the
  RPC's error. One `cast send` approve was silently dropped the same way —
  re-check allowance before depending on it.
- Budget: 0.15 Sepolia ETH total. 0.045 ETH bridged to Unichain Sepolia via
  the OP Stack L1StandardBridge `0xea58fcA6849d79EAd1f26608855c2D6407d54Ce2`
  (bridge tx `0x8f92b6aefb1d2fa4832c8b8e98e24863b7cc7aa7780f14d888d2d0477c21b989`),
  0.1 ETH → 10.5 lREACT via the faucet contract (Sepolia gas is ~19 wei,
  so gas was negligible). Vault funded with 0.04 ETH instead of 0.05
  because only 0.045 ETH was bridged; 0.04 ETH still funds thousands of
  callbacks at Unichain gas prices.

## Deployer (throwaway, testnet only)

- Address: `0xD8f8b50aD98Fa20969B6eCC259ad6D1A59BD7539`
- Private key: held in a key file **outside** this repo (mode 600) —
  never commit it, never paste it anywhere
- Balances at last check (19 Nov, after deployment): Sepolia ETH ~0.005,
  Unichain Sepolia ETH ~0.002, Lasna lREACT ~5.5 (10.5 received from the
  faucet; 2 + 3 used to fund the reactive contract)

## Deployed contracts (19 Nov 2026, verified on Sourcify)

| Contract | Chain | Address | Explorer | Sourcify |
|---|---|---|---|---|
| MockWETH | Unichain Sepolia (1301) | `0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1` | https://sepolia.uniscan.xyz/address/0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1 | VERIFIED |
| MockUSDC | Unichain Sepolia (1301) | `0xccf6e4bdd4d75d9981e06a20149918016911f042` | https://sepolia.uniscan.xyz/address/0xccf6e4bdd4d75d9981e06a20149918016911f042 | VERIFIED |
| MockOracle | Unichain Sepolia (1301) | `0xEfA5040162745690335ED0abC7eFE7fcAc6Bbf52` | https://sepolia.uniscan.xyz/address/0xEfA5040162745690335ED0abC7eFE7fcAc6Bbf52 | VERIFIED |
| SentinelReactive | Lasna (5318007) | `0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1` | https://lasna.reactscan.net/address/0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1 | VERIFIED |
| SentinelVault | Unichain Sepolia (1301) | `0x7c821a4af880fAb37751B0f376CFA726FC575c23` | https://sepolia.uniscan.xyz/address/0x7c821a4af880fAb37751B0f376CFA726FC575c23 | VERIFIED |

Note: SentinelReactive and MockWETH share the same address — both were the
deployer's nonce-0 deployment on their respective chains (CREATE addresses
depend only on sender + nonce). Different chains, different contracts.

Key system addresses: Lasna system contract
`0x8888888888888888888888888888888888888888`; Unichain Sepolia callback
proxy `0x775c9B990ADe401060B78D0e98684eEf8d2466C1`; Chainlink ETH/USD
`0xd9c93081210dFc33326B2af4C2c11848095E6a9a`; lREACT faucet (Eth Sepolia)
`0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`.

## Funding balances (after deployment, 19 Nov)

- Reactive lREACT balance: 5 lREACT (2 deploy value + 3 funded; 10.5 received)
- Vault Unichain ETH balance: 0.04 ETH
- Vault mock-USDC reserve: 100,000 mUSDC (minus 3,650 paid out in the live runs below → ~96,350 left)

## Live end-to-end run (19 Nov 2026, all testnet)

Deployer `0xD8f8b50aD98Fa20969B6eCC259ad6D1A59BD7539`. Mock price seeded at
$1,808.00708956 (real Chainlink feed value at deploy time).

### Run 1 — stop-loss, full exit (order 1)

- Order opened (tx): `0x2a612431e17d66db5a935c92e4e69b7ad175b37d9011aa26428632f8b467bd94`
  (Unichain block 68245099) — 1 mWETH, stop $1,700 / TP1 $1,900 / TP2 $2,000.
  Reactive picked the order up within seconds (`openOrderCount() == 1`).
- Mock price moved to $1,650 (tx): `0xfe563b26dd0bfa5b4dcf6bbd0516a6ff12f06688dfa7ee02820b9b737a94be03`
  (Unichain block 68245120, 2026-11-19T14:12:28Z).
- `ExitRequested` on Lasna (tx): `0x98a6d00c51ebb399ee9bab1844d06ba56765e4a3168135ce0a793e7cc737c059`
  (Lasna block 8739252, kind 1 stop-loss, exit 1 mWETH @ $1,650).
- `ExitExecuted` on Unichain Sepolia (tx): `0xf34e07efc3e0b87749ca771e3af048249e57915e96b12844eeb5709fea74328b`
  (Unichain block 68245122 — 2 blocks / ~4 seconds after the price move).
- User mUSDC received: **1,650 mUSDC** (1 mWETH × $1,650). Order closed.

### Run 2 — TP1 50% then TP2 rest (order 2)

- Order opened (tx): `0x2f2ed30046d49653623883a958ef81a259da3e7c1d8cdd17db8b05573a7ee466`
  — 1 mWETH, stop 0 / TP1 $1,900 / TP2 $2,000.
- Mock price moved to $1,950 (tx): `0x904f40ba57a51ad71e5366fe78f528d639fb1abacd3dd5b88f001c99ef4f04bf`
  (2026-11-19T14:16:19Z) → TP1 fired: `ExitExecuted`
  `0x2b06df5c0869137d5dfcf5a07d0e3383532b200b16bb2780b24bd37dbdd915e9`
  (block 68245355) — 0.5 mWETH out, **975 mUSDC** received, 0.5 mWETH left.
- Mock price moved to $2,050 (tx): `0xf20696d2fcec49954f2d05c963f443249e8efc1b278cc7b37c2384339c588e0f`
  (2026-11-19T14:16:46Z) → TP2 fired: `ExitExecuted`
  `0xd110940c91ad6a7e3b536a20e5e7d4cb56dfd2bce8ea936286b56367690014d3`
  (block 68245382) — remaining 0.5 mWETH out, **1,025 mUSDC** received.
- Total paid out across both runs: **3,650 mUSDC**. Both orders closed.
  No duplicate/over-fill: vault remaining hit exactly 0 both times.

## Video

- Path: `video/sentinel-demo.mp4` — **2:34, 1280×720, H.264, 2.3 MB** (limit 5:00)
- Contents: title card (5s) → live browser session (88s: connect wallet →
  mint 10 mWETH → open order 3 → mock price $2,050 → $1,650 → order closes,
  balance 3,650 → 5,300 mUSDC on camera) → 4 proof slides with real explorer
  data (order opened / price moved / ExitRequested on Lasna / ExitExecuted +
  payout) → outro with results + addresses.
- Order 3 (the video run): open `0x9a76716d077dbde0028091cd2600fd85c09389bfa2f65462f7eb0ad015988641`,
  setPrice $1,650 `0x097ecd451a36e7635b5056fb058209457cd8d8729ddeddedbe11443f11cb09be`,
  ExitRequested `0x3fb5bb282064c80ff9d2fc09a88fb479edae18f30acc13cda2b0004d9c8f866f`
  (Lasna block 8739898), ExitExecuted `0x626fa5c6a2d3c30968a67093cb9820eaebb403be3b2efc11fecb39f15bbd5083`
  (Unichain block 68245828). Price move → payout: ~3 seconds.
- How it was recorded: `video/record-session.mjs` (Playwright recordVideo,
  injected EIP-1193 provider backed by the throwaway deployer key read at
  runtime from outside the repo) + `video/render-slides.mjs` (proof slides
  from live Blockscout/`cast logs` data) + ffmpeg concat. The frontend's
  ethers is vendored (`frontend/vendor/ethers.umd.min.js`) so the page has
  no CDN dependency; a localhost JSON-RPC proxy (`video/rpc-proxy.py`) let
  this VM's Chromium reach the public RPCs during recording. No audio track
  (captions carry the narration).
- Plan: `video/VIDEO-PLAN.md`

## How the tests were run

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge test -vv
```

Fork tests (9/9 passing, Lasna + Unichain Sepolia forks) were run during
development; the test suite itself is not part of this public snapshot.
