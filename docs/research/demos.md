# reactive-smart-contract-demos — Omni vs legacy audit

Repo: https://github.com/Reactive-Network/reactive-smart-contract-demos (UNLICENSED, no LICENSE file). Clones are **gitignored** and not compiled
(foundry only compiles `contracts/`). Re-fetch with:

```bash
git clone --depth 1 https://github.com/Reactive-Network/reactive-smart-contract-demos docs/research/demos
git clone --depth 1 -b omni https://github.com/Reactive-Network/reactive-smart-contract-demos docs/research/demos-omni
```

## `main` branch — commit `6fd02ce56d110762b9cecbacbf4374aa5951d491` (2026-10-07): **all legacy**

Imports `lib/reactive-lib` (the legacy lib, not `reactive-lib-omni`). Zero hits for `onlySystem` / `requestCallbackV_1_0` anywhere in `src/`.

| Demo | Verdict | Evidence |
|---|---|---|
| `src/demos/basic` | ❌ **Legacy** | `BasicDemoReactiveContract.sol:29-30` `if (!vm) { service.subscribe(...)`; `:41` `react(LogRecord calldata log) external vmOnly`; `:45` `emit Callback(...)` |
| `src/demos/cron` | ❌ **Legacy** | `CronDemo.sol:5` imports `AbstractPausableReactive` (legacy-only); `:18-19` `if (!vm) { service.subscribe`; `:43` `vmOnly`; `:46` `emit Callback(` |
| `src/demos/uniswap-v2-stop-take-profit-order` | ❌ **Legacy** | `UniswapDemoStopTakeProfitReactive.sol:106-144` `if (!vm)` + 5× `service.subscribe`; `:156` `vmOnly`; `:351,364,380` `emit Callback(` |

**Do not copy code from `main`.** Ideas only (e.g. the stop/take-profit state machine), re-expressed in Omni API.

## `omni` branch — commit `d1d854b4d8ded359d73dcd85cda882ec5c9aab49` (2026-06-11): **REFERENCE PATTERNS**

Decided in the M0 review: these five micro-demos (plus the docs and `lib/reactive-lib-omni`) are the **reference patterns** for all Hedgeline
Reactive code. They use `lib/reactive-lib-omni` with `@reactive/src/...` imports, the same style as our `remappings.txt`.
Path: `src/micro-demos/` (this branch has no `basic/`, `cron/` or uniswap folders). Copy *patterns*, not files (UNLICENSED).

### Pattern catalogue

| # | Pattern | Where (omni branch) | Hedgeline use |
|---|---|---|---|
| P1 | **Subscribe in a `payable` constructor**: `SYSTEM.subscribe(chainId, contract, topic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE)` | `PingPong.sol` ctor, `Cron.sol` ctor, `Xfers.sol` `_sub()` | `HedgelineReactive` S1/S2/S3; `PingReactive` (M1) |
| P2 | **Wildcard contract** (`address(0)`) with a specific topic0 = "this event on any contract of a chain" | `Xfers.sol` `_sub()` (all ERC-20 `Transfer` on Sepolia) | Not used: every Hedgeline subscription pins chain + contract (+ poolId / account in topic1) |
| P3 | **Indexed-param filter via topics** | — (Xfers filters only on topic0) | S2 `topic1 = poolId`, S3 `topic1 = hedger` |
| P4 | **`react(LogRecord memory log_) external onlySystem`**, guard on `opCode` before `abi.decode(log_.data, ...)` | `Xfers.sol` `react()`: `if (log_.opCode == 3) { ... abi.decode(log_.data, (Transfer)) }` | All decoding in `HedgelineReactive`; we additionally route on `topic0` first |
| P5 | **Self-subscription** to the contract's own Lasna event (`block.chainid`, `address(this)`) | `PingPong.sol` (`ping()` emits `Ping`, `react()` emits `Pong(txHash)`) | Useful in M1 to measure Lasna-only latency (event → react) in isolation |
| P6 | **`requestCallbackV_1_0` from an external (non-`react`) function**, `address(0)` first payload arg, owner-set recipient | `CallbackSender.sol` `ping()` + `setCounterParty()` | Same deployment order (RC → callback → setter); owner `setHedger()` |
| P7 | **Callback receiver**: `constructor(IPayable proxy_, address reactive_) payable AbstractCallback(proxy_, reactive_)`; `fn(address reactive_, ...) external onlyServiceProvider onlyCallbackSender(reactive_)` | `CallbackRecipient.sol` `pong()` | `PingReceiver` (M1), `HedgelineHedger.applyHedge/protectMargin` |
| P8 | **Runtime subscribe/unsubscribe with identical 6 args**, `_coverDebt()` before resubscribing | `Xfers.sol` `updateLimit()` + `_sub/_unsub`; `Cron.sol` `pause/resume` | Owner-only re-subscribe helpers on `HedgelineReactive`; CRON (optional) must be switchable off |
| P9 | **Self-limiting subscription** (unsubscribe from inside `react()` after N events) | `Xfers.sol` `if (--_limit == 0) _unsub();` | Optional safety valve for latency runs to cap lREACT spend |
| P10 | **CRON** via legacy address `0x…fffFfF` + `CRONn_TOPIC_0`; self-callback `chainId: block.chainid, recipient: address(this)` | `Cron.sol` | Optional only (bills every tick) |
| P11 | **Diagnostic state/events in `react()`** (`_lastTxHash`, `_lastReactBlockNumber`, `emit Pong(log_.txHash)`) | `PingPong.sol`, `Xfers.sol` | `Decision(...)` events on Lasna; carry `log_.txHash`/`blockNumber` into the callback payload for latency proof. **Do not copy the two storage writes per react** — plan.md rule 12 (lean `react()`): emit instead of store unless state is needed |

### Anti-patterns in these demos (do not copy)

- `CallbackSender.react()` reverts `NotSupported()`. Per docs, a reverting `react()` is caught and **still billed**. Our `react()` falls through.
- `Cron.sol` requests self-callbacks to `callback(address)` but defines no such function, so those callbacks would fail (and be billed). Any self-callback needs a guarded receiver.
- `require(msg.sender == _OWNER)` without a reason/custom error (`CallbackSender`, `Xfers`). We use Solady `Ownable`.
- `Xfers.updateLimit()` is `payable` with a bare `require`. Fine for a demo; our setters are `onlyOwner` and non-payable unless funding is intended.
- None of them expose `coverDebt()`; we expose it on both reactive and callback contracts (docs recommendation).

### Hedgeline M1 mapping

- `PingOrigin` (Base / Unichain): emits `Ping(uint256 n, uint256 ts)` — plain origin contract, no Reactive lib.
- `PingReactive` (Lasna): P1 + P4 + P6-from-`react()` + P11 (event only) + `coverDebt()`.
- `PingReceiver` (Base): P7 + `coverDebt()`.
