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

## `omni` branch — commit `d1d854b4d8ded359d73dcd85cda882ec5c9aab49` (2026-06-11): **Omni-style**

Uses `lib/reactive-lib-omni` and `@reactive/src/...` imports — the same import style the docs and our `remappings.txt` use. Contains only
`src/micro-demos/`: `CallbackSender.sol`, `CallbackRecipient.sol`, `PingPong.sol`, `Cron.sol`, `Xfers.sol`. (No basic/cron/uniswap folders on this branch.)

| File | Verdict | Patterns worth copying | Caveats |
|---|---|---|---|
| `CallbackSender.sol` | ✅ Omni | `requestCallbackV_1_0` from an external fn (not `react`), `address(0)` placeholder, owner setter for counterparty | `react()` **reverts** `NotSupported()` — the docs call revert-as-filter a billed mistake. Don't copy. |
| `CallbackRecipient.sol` | ✅ Omni | `constructor(IPayable proxy_, address reactive_) payable AbstractCallback(...)`; `pong(address reactive_, ...) external onlyServiceProvider onlyCallbackSender(reactive_)` | — |
| `Cron.sol` | ✅ Omni | `SYSTEM.subscribe(block.chainid, 0x…fffFfF, CRONn_TOPIC_0, …)`; pause = `unsubscribe` with identical args; self-callback with `chainId: block.chainid, recipient: address(this)` | Has no `callback(address)` receiver, so its self-callbacks would fail; dated before Omni mainnet (Oct 28). |
| `PingPong.sol`, `Xfers.sol` | ✅ Omni | not needed for Hedgeline | — |

Conclusion: the authoritative Omni patterns are the docs (`docs/research/*.md`) and `lib/reactive-lib-omni`. The `omni` branch micro-demos agree with them,
apart from the caveats above.
