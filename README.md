# Sentinel — autonomous stop-loss & take-profit executor

**Reactive Omni Buildathon, Track 1: Time-Sensitive DeFi** · Unichain Sepolia + Lasna Testnet

Sentinel lets you set a stop-loss and take-profit once, then walk away. A
Reactive Contract on Lasna watches the Chainlink ETH/USD feed; the moment
your price is hit, it triggers a callback that exits your position — no bot,
no server, no manual trade.

## How it works

1. You deposit mock WETH into `SentinelVault` (Unichain Sepolia) and set a
   stop-loss price, TP1, TP2, and/or a trailing stop (in basis points).
2. `SentinelReactive` (Lasna) subscribes to Chainlink ETH/USD `AnswerUpdated`
   events and to the vault's `OrderOpened` / `OrderCancelled` events, keeping
   its own order book.
3. On every price update it checks open orders:
   - **Stop-loss hit → exit 100%**; **trailing stop hit → exit 100%**
   - **TP1 hit → exit 50%**; **TP2 hit → exit the rest**
4. The exit is requested as a Reactive callback; the vault settles it in mock
   USDC at the trigger price and pays you.

## Contracts

| Contract | Chain | Address |
|---|---|---|
| SentinelReactive | Lasna (5318007) | `0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1` |
| SentinelVault | Unichain Sepolia (1301) | `0x7c821a4af880fAb37751B0f376CFA726FC575c23` |
| MockOracle (Chainlink-shaped) | Unichain Sepolia | `0xEfA5040162745690335ED0abC7eFE7fcAc6Bbf52` |
| MockWETH / MockUSDC | Unichain Sepolia | `0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1` / `0xccf6e4bdd4d75d9981e06a20149918016911f042` |
| Chainlink ETH/USD feed (real) | Unichain Sepolia | `0xd9c93081210dFc33326B2af4C2c11848095E6a9a` |

All five contracts are verified on Sourcify. Deployed addresses, explorer
links and verification status live in [`BUILD-NOTES.md`](BUILD-NOTES.md).

## Demo determinism — read this first

The real Chainlink feed will not move 0.5% on cue during a 5-minute video,
so the demo drives a `MockOracle` that emits the **identical**
`AnswerUpdated(int256,uint256,uint256)` event (indexed `current` and
`roundId`, exactly like Chainlink). `SentinelReactive` subscribes to **both**
the mock oracle and the real feed — the same code path handles both. The
video shows: set an order → move the mock price below the stop → the
reactive contract fires → the callback executes → the user receives mock
USDC, with Lasna and Unichain Sepolia explorer pages as proof.

Settlement is against the vault's mock-USDC reserve at the trigger price.
There is no meaningful DEX liquidity on testnet, so a reserve settlement is
the honest stand-in; a production version would swap on a real DEX.

## Run it (testnet)

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge install   # installs @reactive/lib (see remappings.txt / foundry.lock)
forge build
```

Fork tests (9/9 passing during development — stop-loss, TP1/TP2, trailing
stop, order cancel, vault settlement/clamp/duplicate no-op, vault auth,
MockOracle event shape) are documented in [`BUILD-NOTES.md`](BUILD-NOTES.md);
the test suite itself is not part of this public snapshot.

## Demo video

[`video/sentinel-demo.mp4`](video/sentinel-demo.mp4) — **2:34, 1280×720,
H.264, 2.3 MB** (limit 5:00). Title card → live browser session (connect
wallet → mint 10 mWETH → open an order → mock price $2,050 → $1,650 →
order closes, balance 3,650 → 5,300 mUSDC on camera) → proof slides with
real explorer data (order opened / price moved / `ExitRequested` on Lasna /
`ExitExecuted` + payout) → outro with results and addresses. No audio
(captions carry the narration).

Frontend: serve `frontend/` statically (e.g. `python3 -m http.server`), open
`index.html`, connect a wallet on Unichain Sepolia, mint mock WETH, open an
order, and watch it fill. Contract addresses come from
`frontend/config.js` (written by `script/deploy.sh`).

## Security notes

- `executeExit` is guarded by **both** `onlyServiceProvider` (the callback
  proxy must call it) and `onlyCallbackSender` (the first payload argument
  must be the authorized reactive contract). A contract cannot be both
  reactive and callback.
- Exits are applied optimistically in the reactive contract's book when the
  callback is requested, and the vault clamps every exit to the remaining
  amount — a duplicate or late callback is a harmless no-op and can never
  over-fill.
- Both contracts must stay funded: the reactive contract in lREACT (it pays
  for reactive transactions) and the vault in Unichain Sepolia ETH (it pays
  the callback proxy). Debt above zero silently stops all delivery — the
  frontend shows both balances and the reactive contract's debt, and
  `coverDebt()` is exposed on both contracts.
- Testnet only. Mock tokens have no value. Never send real funds to these
  contracts.

## Repo layout

- `src/` — `SentinelReactive.sol`, `SentinelVault.sol`, `MockOracle.sol`, `MockERC20.sol`
- `frontend/` — one-page static app (`index.html`, `config.js`, vendored ethers)
- `script/` — `deploy.sh` (testnet deployment + Sourcify verification)
- `video/` — demo video [`sentinel-demo.mp4`](video/sentinel-demo.mp4) (2:34) and `VIDEO-PLAN.md`
