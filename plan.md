# Hedgeline — Build Plan for Claude Code

> **Read this whole file before writing any code.** It is the single source of truth for scope, architecture, verified platform facts, milestones and acceptance criteria. When this file and your training data disagree about Reactive Network, **this file and the live docs win** — Reactive Omni (Oct 2026) changed the API and most examples online are for the legacy version.

---

## 0. Mission

Build **Hedgeline** and submit it to the **Reactive Omni Buildathon**, track **Every Second Counts**, before **Dec 5, 2026**. Target submission: **Dec 3** (2 days of buffer).

**One sentence:** a Reactive contract on Lasna keeps a real short on Base Sepolia sized to the exact delta of a Uniswap v4 LP vault on Unichain Sepolia, rehedging on vault changes *and* on external price moves, and guarding the short's margin — with no off-chain bot.

The README in the repo root (`README.md`) describes the finished product. This plan describes how to get there. If they conflict, raise it with the human; don't silently pick one.

### How we win (judging, 4 criteria, equal weight, 1–5 each)

| Criterion | What it means for us | Gate |
|---|---|---|
| **Execution** | Reactive transactions and the callbacks they trigger must exist on-chain. **Entries without them are not scored further.** | Hard gate — first priority |
| **Integration** | The reactive contract must do real work, not relay. Ours holds state, computes delta, nets, gates, guards margin. | Core design |
| **Usefulness** | Real LP problem; quiet-pool rehedge; margin safety | Story + demo |
| **Craft** | Readable code, working demo, docs others can follow | Tests, README, video |

Track-specific signal from the organizers: **"The strongest entries will show their latency numbers measured across the full loop, not just one leg of it."** Latency measurement is a first-class feature, not polish.

### Buildathon rules (non-negotiable)

- Track **Every Second Counts** must run on **Lasna testnet**, with **Unichain Sepolia and/or Base Sepolia**. We use both.
- Submit on DoraHacks: public repo link, deployed contract addresses, **a few tx hashes showing the full loop (origin event → callback)**, demo video **under 3 minutes**.
- Repo must be **public and open-source** by submission time.
- **Everything built during the event** (Nov 5 – Dec 5). Libraries/dependencies are fine; prior projects are not. Do not copy code from other hackathon repos.
- On Base Sepolia, **use `block.timestamp`, never block counts**, for timers, cooldowns, deadlines, funding accrual. Base Sepolia produces 200 ms blocks.

---

## 1. Phase 0 — Research capture (do this first, ~half a day)

Before any implementation, build a local knowledge base so you never guess at the Omni API.

1. Create `docs/research/`.
2. Fetch and save as markdown (one file per page):
   - https://dev.reactive.network/ (Getting Started — includes **Legacy vs Omni** migration notes)
   - https://dev.reactive.network/origins-and-destinations
   - https://dev.reactive.network/reactive-contracts
   - https://dev.reactive.network/callback-contracts
   - https://dev.reactive.network/economy
   - https://dev.reactive.network/reactive-mainnet
   - https://dev.reactive.network/rnk-rpc-methods
   - https://blog.reactive.network/reactive-omni-buildathon-thirty-days-to-find-out-what-one-second-buys/
3. Add as git submodules / forge deps and **read the source**:
   - `forge install Reactive-Network/reactive-lib-omni` → read `src/base/AbstractReactive.sol`, `AbstractCallback.sol`, `AbstractPayer.sol`, `src/interfaces/ISystemContract.sol`, `IReactive.sol`, `IPayable.sol`
   - `Reactive-Network/reactive-smart-contract-demos` (clone into `docs/research/demos`, do **not** vendor into contracts) → read `src/demos/basic`, `cron`, `uniswap-v2-stop-take-profit-order`. Check whether each demo is Omni-style (`onlySystem`, `requestCallbackV_1_0`) or legacy (`vmOnly`, `emit Callback`). **Only copy patterns from Omni-style code.**
   - `Uniswap/v4-core`, `Uniswap/v4-periphery`
4. Fetch the official Uniswap v4 deployments page (https://developers.uniswap.org/docs/protocols/v4/deployments) and record PoolManager / PositionManager / StateView addresses for Unichain Sepolia (1301) and Base Sepolia (84532).
5. Check `reactive-lib-omni`'s license header. If it is UNLICENSED upstream, keep it as a fetched dependency (submodule / bootstrap script), don't commit its source into our tree.
6. Write `docs/research/FACTS.md` summarising anything that **differs** from section 2 below. Stop and tell the human if a core fact changed (addresses, API names, payload rules).

---

## 2. Verified platform facts (scraped Nov 11, 2026 — re-verify in Phase 0)

### 2.1 Networks

| Network | Chain ID | RPC | Explorer | Role |
|---|---|---|---|---|
| Reactive Lasna (testnet) | `5318007` | `https://lasna-rpc.rnk.dev/` | https://lasna.reactscan.net | Reactive contract |
| Unichain Sepolia | `1301` | `https://sepolia.unichain.org` | https://sepolia.uniscan.xyz | LP vault + v4 pool |
| Base Sepolia | `84532` | `https://sepolia.base.org` | https://sepolia.basescan.org | Reference pool, MiniPerp, Hedger |

- Lasna currency: **lREACT**. Reactive mainnet (`1597`) is **not** used for this track.
- Mainnets and testnets cannot be mixed in one origin→destination flow.

### 2.2 Reactive system addresses

| Item | Value |
|---|---|
| System contract (Lasna & mainnet) | `0x8888888888888888888888888888888888888888` |
| Legacy system address (CRON events only) | `0x0000000000000000000000000000000000fffFfF` |
| Callback proxy — **Base Sepolia** | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` |
| Callback proxy — **Unichain Sepolia** | `0x775c9B990ADe401060B78D0e98684eEf8d2466C1` |
| Callback proxy — Ethereum Sepolia | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` |
| Lasna faucet (send Base Sepolia ETH) | `0x2afaFD298b23b62760711756088F75B7409f5967` — `request(address)` payable, **1 ETH → 100 lREACT, max 5 ETH per tx** |
| Lasna faucet (send Sepolia ETH) | `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` |

### 2.3 Uniswap v4 (verify against the official deployments page in Phase 0)

| Chain | PoolManager | PositionManager |
|---|---|---|
| Unichain Sepolia (1301) | `0x00b036b58a818b1bc34d502d3fe730db729e62ac` | `0xf969aee60879c54baaed9f3ed26147db216fd664` |
| Base Sepolia (84532) | `0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408` | `0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80` |

### 2.4 Omni reactive contract API (from docs)

```solidity
pragma solidity ^0.8.29;
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

contract X is AbstractReactive {
    constructor(...) payable {
        SYSTEM.subscribe(chainId, contractAddr, topic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }
    function react(LogRecord memory log_) external onlySystem { ... }
}
```

- **No ReactVM, no `vm` flag, no `vmOnly`, no dual deployment.** One deployment to Lasna; `react()` runs with ordinary persistent state.
- `LogRecord { chainId, contractAddress, topic0..topic3 (uint256), data (bytes, non-indexed params only), blockNumber, opCode (= number of topics), blockHash (uint256), txHash (uint256), logIndex }`.
- **`LogRecord` has no timestamp.** Anything time-related must come from event data we emit ourselves, or be resolved off-chain from `chainId + blockNumber`.
- Subscriptions: `SYSTEM.subscribe(chainId, contract, topic0, topic1, topic2, topic3)` — equality matching only, no OR within one subscription (call `subscribe` multiple times), at least one criterion must be specific. Wildcards: `chainId=0`, `contract=address(0)`, topic = `REACTIVE_IGNORE`. Subscriptions live in the node; you can't read them back on-chain. `unsubscribe` needs all six args to match exactly.
- **Do not revert to filter logs.** A revert is caught, emits `ReactiveContractReverted`, and is still billed. Unmatched logs should fall through.
- Route on `topic0` first and check `opCode` before decoding `data`.
- **Callbacks:**
  ```solidity
  SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
      chainId: 84532,
      recipient: hedger,
      gasLimit: 1_000_000,
      payload: abi.encodeWithSignature("applyHedge(address,...)", address(0), ...)
  }));
  ```
  - `emit Callback(...)` is **deprecated** — don't use it.
  - **The first payload argument must be an `address` placeholder (`address(0)`).** The network overwrites the first 160 bits with the requesting reactive contract's address. Forgetting it is the #1 way callbacks break.
  - `requestCallbackV_1_0` can be called from `react()` or from any external function.
- **Gas:** reactive tx gas cap **900,000**. Callback gas limit minimum **100,000** (lower requests are ignored). The proxy withholds gas for its own accounting (`_extraGas`, `_maxChargeGas`) before calling the recipient, so size limits generously and measure.
- **Billing:** the reactive contract pays for `react()` in lREACT. **Callbacks are billed to the recipient on the destination chain in that chain's native ETH**, even when they fail. Any debt > 0 stops execution entirely (the contract goes `inactive`). Fund with `depositTo(address)` on the system contract (Lasna) or on the callback proxy (Base Sepolia). Expose `coverDebt()` wrappers.
- **CRON** (optional, not core): subscribe to the legacy address `0x…fffFfF` with topic `Cron10 = 0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687` (every 10 blocks ≈ 10 s). Bills every tick — must be switchable off.
- Inspect callbacks for a reactive tx: `cast call 0x8888…8888 "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])" $REACTIVE_TX_HASH --rpc-url $LASNA_RPC` (returns destination tx hash and `err`).
- Verify contracts on Lasna via Sourcify: `forge verify-contract --verifier sourcify --chain-id 5318007 $ADDR $NAME`.

### 2.5 Omni callback contract API (from docs)

```solidity
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

contract Hedger is AbstractCallback {
    constructor(IPayable callbackProxy_, address callbackSender_) payable
        AbstractCallback(callbackProxy_, callbackSender_) {}

    function applyHedge(address reactive_, ...) external
        onlyServiceProvider            // caller is the callback proxy
        onlyCallbackSender(reactive_)  // injected sender is our reactive contract
    { ... }
}
```

- **Always use both modifiers.**
- `callbackSender_` is **immutable**. Getting it wrong means redeploying.
- **Deployment order:** (1) deploy reactive contract, (2) deploy callback contract with proxy + reactive address, (3) set recipient on the reactive contract via an owner-only setter, (4) fund both.
- A contract cannot be both reactive and callback.

### 2.6 Things to verify empirically in M1 (unknown from docs)

- Which **EVM version / solc** Lasna supports (v4-core needs Cancun for transient storage, but the reactive contract only imports pure math — confirm it compiles and deploys). Set per-profile `evm_version` in `foundry.toml` if needed.
- Real end-to-end latency on each hop.
- Whether the PoolManager `Swap` event on Base Sepolia reaches Lasna with `topic1 = poolId` filtering as expected.
- Callback proxy `_extraGas` / `_maxChargeGas` on Base Sepolia (read with `cast call`).

---

## 3. Architecture spec

### 3.1 Components

```
Unichain Sepolia                 Reactive Lasna                    Base Sepolia
────────────────                 ──────────────                    ────────────
HedgelineVault (v4 hook)  ──S1──▶ HedgelineReactive ──applyHedge──▶ HedgelineHedger ──▶ MiniPerp
 tWETH/tUSDC pool                  (the brain)      ──protectMargin▶     ▲                 │
                                        ▲  ▲                             │                 │ marks to
                                        │  └────────S3 (perp events)─────┴─────────────────┘
                                        └───────────S2 (PoolManager.Swap, poolId)── Reference v4 pool
```

### 3.2 Tokens

- Deploy `TestToken` (Solady ERC20, public `mint` capped per call) as **tWETH (18 dec)** and **tUSDC (6 dec)** on **both** Unichain Sepolia and Base Sepolia.
- **Pool orientation must be identical on both chains** (same token0/token1 meaning and decimals) so one `sqrtPriceX96` means the same price everywhere.
- **Decided (M0 review): deploy both tokens with CREATE2** through the deterministic deployer `0x4e59b44847b379578588920ca78fbf26c0b4956c` (present on Base Sepolia and Unichain Sepolia), **same salt + same init code on both chains**. The deploy script must assert that (a) each token's address is identical on both chains and (b) the token0/token1 order is the same on both, and **revert otherwise**. No `invertedPair` flag.
- **Recorded salts (M1).** **tWETH must be token0** (§3.8 assumes it; the pool price is then ≈ 3000 tUSDC per tWETH). The tWETH salt was mined offline with `contracts/script/MineTokenSalt.s.sol` (iterate `<i>` until `address(tWETH) < address(tUSDC)`); `M1Deploy` also reverts if tWETH isn't token0. Constants live in `contracts/script/M1Lib.sol`:

  | Token | Salt preimage | Salt | Constructor args |
  |---|---|---|---|
  | tWETH | `keccak256("hedgeline.TestToken.tWETH.v1.0")` | `0x58ea70424e810c4cac32f8d0d8a0a933b22b9dfbb849423b23430e375e865e21` | `("Hedgeline Test WETH", "tWETH", 18, 1_000e18)` |
  | tUSDC | `keccak256("hedgeline.TestToken.tUSDC.v1")` | `0x21413999aad98318d7d6b9401b7a8dc57160d931275847f7445e96212966cf70` | `("Hedgeline Test USDC", "tUSDC", 6, 10_000_000e6)` |

  Changing `TestToken.sol` or its constructor args changes the init code, so the addresses change and the salt must be re-mined.

### 3.3 `HedgelineVault` (Unichain Sepolia) — v4 hook + LP vault

Responsibilities:
- Owns all liquidity in its pool. Users deposit/withdraw through the vault and receive ERC20 shares.
- Manages **2 fixed ranges** (`rangeId 0` narrow around initial price, `rangeId 1` wide) so the reactive contract has something to net. Allocation split is a constructor param.
- Hook permissions: `beforeAddLiquidity` + `beforeRemoveLiquidity` (revert unless `sender == address(this)`), `afterSwap` (emit price update). Mine the address with `HookMiner`.
- Uses `poolManager.unlock()` + `unlockCallback` to modify liquidity.

Events (exact):
```solidity
event PositionUpdated(
    uint8   indexed rangeId,
    uint128 liquidity,
    int24   tickLower,
    int24   tickUpper,
    uint160 sqrtPriceX96,   // pool price after the change
    uint64  nonce,          // monotonic per vault
    uint256 timestamp       // block.timestamp, for latency
);
event PoolPriceUpdated(uint160 sqrtPriceX96, uint64 nonce, uint256 timestamp); // from afterSwap — dashboard/diagnostics only, NOT subscribed by the reactive contract
```

Keep scope tight: **no** directional fee, **no** fee compounding, **no** rebalancing ranges. Fees accrue in the pool and are collected on withdraw.

### 3.4 Reference pool (Base Sepolia)

- A plain v4 tWETH/tUSDC pool on the official Base Sepolia PoolManager, **no hook**.
- Price source for S2 and the perp's mark price.
- S2 subscription: `chainId=84532, contract=PoolManager, topic0=keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"), topic1=poolId`. **Verify the exact Swap signature from v4-core source in Phase 0.**
- Need a simple swap router for scripts (`PoolSwapTest` from v4-core test utils, or a 40-line custom router using `unlock`).
- **Fallback** if PoolManager events misbehave on Lasna: a tiny `ReferencePool` contract with `setPrice` + `PriceUpdated(uint160 sqrtPriceX96, uint256 timestamp)` event. Decide by end of M1.

### 3.5 `MiniPerp` (Base Sepolia)

Minimal, honest, readable. One market (ETH-USD), collateral tUSDC.

- `deposit(uint256)`, `withdraw(uint256)` (only if margin stays above initial margin).
- `setPosition(int256 targetSizeWad)` — moves the caller's position to an absolute target size (negative = short) at the mark price; realizes PnL on reductions.
- `markPrice()` — reads `sqrtPriceX96` from the reference pool via `StateLibrary.getSlot0(poolManager, poolId)`; converts to price WAD with decimal adjustment.
- Funding: `fundingRatePerSecondWad` set by owner (simulated, documented as such); cumulative index updated by `block.timestamp` deltas on every interaction. Shorts receive when rate > 0.
- `marginRatio(account)` = `(collateral + unrealizedPnL + funding) / (|size| × mark)`.
- `liquidate(account)` if ratio < `maintenanceMarginWad` (e.g. 5%). Anyone can call.
- Events:
  ```solidity
  event PositionChanged(address indexed account, int256 sizeWad, uint256 entryPriceWad, uint256 timestamp);
  event CollateralChanged(address indexed account, uint256 collateral, uint256 timestamp);
  event Liquidated(address indexed account, int256 sizeWad, uint256 markPriceWad, uint256 timestamp);
  ```
- Interface `IHedgeVenue { setPosition; deposit; withdraw; marginRatio; positionOf; markPrice; }` — the hedger depends only on this.

### 3.6 `HedgelineHedger` (Base Sepolia) — callback contract

```solidity
contract HedgelineHedger is AbstractCallback, Ownable {
    // callbacks — both modifiers on both
    function applyHedge(
        address reactive_,
        uint64  nonce,
        int256  targetSizeWad,      // absolute, negative = short
        uint160 sqrtPriceX96,       // price used by the decision
        uint256 originChainId,
        uint256 originBlock,
        uint256 originTxHash
    ) external onlyServiceProvider onlyCallbackSender(reactive_);

    function protectMargin(
        address reactive_,
        uint64  nonce,
        uint8   action,             // 1 = STEP_DOWN, 2 = CUT, 3 = TOP_UP
        int256  newTargetSizeWad,
        uint256 topUpAmount,
        uint256 originChainId,
        uint256 originBlock,
        uint256 originTxHash
    ) external onlyServiceProvider onlyCallbackSender(reactive_);

    function coverDebt() external;               // AbstractPayer._coverDebt wrapper
    function pause(bool) external onlyOwner;     // blocks increases, never blocks reductions
    function hedgeState() external view returns (int256 shortSize, uint256 collateral, uint64 lastNonce);
}
```

Rules:
- One shared monotonic nonce for both callbacks. `nonce <= lastNonce` → emit `StaleCallback` and **return** (don't revert — reverts still cost us gas and spam `CallbackFailure`; but emit so it's visible).
- Clamp: `|target| ≤ maxShortWad` and `|target − current| ≤ maxStepWad`.
- Holds tUSDC collateral and a separate reserve for `TOP_UP`.
- Events:
  ```solidity
  event HedgeApplied(uint64 indexed nonce, int256 targetSizeWad, int256 appliedSizeWad,
                     uint160 sqrtPriceX96, uint256 originChainId, uint256 originBlock,
                     uint256 originTxHash, uint256 timestamp);
  event MarginProtected(uint64 indexed nonce, uint8 action, int256 newSizeWad, uint256 topUp,
                        uint256 originChainId, uint256 originBlock, uint256 originTxHash, uint256 timestamp);
  event StaleCallback(uint64 nonce, uint64 lastNonce);
  ```

### 3.7 `HedgelineReactive` (Lasna) — the brain

State (mirrors):
```solidity
struct Range { uint128 liquidity; int24 tickLower; int24 tickUpper; bool active; }
Range[2]  ranges;
uint160   lastSqrtPrice;          // latest external price (S2)
uint64    lastVaultNonce;         // ignore out-of-order vault events
int256    lastSentTarget;         // what we last asked for
uint64    callbackNonce;
// perp mirror (S3)
int256    perpSize; uint256 perpEntry; uint256 perpCollateral;
// params (owner-settable)
uint256 hWad = 0.65e18; uint256 hMinWad = 0.30e18; uint256 hStepWad = 0.10e18;
uint256 tauWad; uint256 minNotionalWad;
uint256 mWarnWad; uint256 mCritWad;
uint64  callbackGasLimit = 1_000_000;
address hedger; // set after hedger deploy (owner-only setter)
```

Subscriptions (constructor, plus owner-only re-subscribe helpers):
- S1: `(1301, vault, PositionUpdated topic0, IGNORE, IGNORE, IGNORE)` **only**. (Decided in M0 review: no subscription to `PoolPriceUpdated` — every Unichain swap would cost a reactive tx; the external price comes from S2.)
- S2: `(84532, basePoolManager, Swap topic0, uint256(poolId), IGNORE, IGNORE)`
- S3: `(84532, miniPerp, PositionChanged topic0, uint256(uint160(hedger)), IGNORE, IGNORE)` and same for `CollateralChanged`
  (topic1 = indexed account = hedger, so we only see our own position)

`react()` flow:
1. Route on `topic0`; check `opCode`; decode.
2. S1 → update `ranges[rangeId]` if `nonce > lastVaultNonce`; then run **decide(lastSqrtPrice)** (if a price is known; else use the vault's own sqrtPrice).
3. S2 → `lastSqrtPrice = sqrtP`; run **marginCheck(sqrtP)** then **decide(sqrtP)**.
4. S3 → update perp mirror only (no callback).

`decide(sqrtP)`:
- `target = −h × Σ delta(range_i, sqrtP)` (negative = short).
- If `|target − lastSentTarget| > tau` **and** `|target − lastSentTarget| × price > minNotional` → request `applyHedge` with `++callbackNonce`, set `lastSentTarget = target`.
- Else emit `HedgeSkipped(reason, target, lastSentTarget)` — this is proof scenario #3 for judges.

`marginCheck(sqrtP)`:
- Compute ratio from perp mirror + price.
- `< mCrit` → `protectMargin(CUT)` with `h = hMin`.
- `< mWarn` → `protectMargin(STEP_DOWN)`, `h = max(h − hStep, hMin)` — or `TOP_UP` if hedger reserve is configured (owner param `preferTopUp`).
- Debounce: don't fire `protectMargin` again until a `PositionChanged`/`CollateralChanged` arrives or N seconds pass (use the vault/hook timestamps; LogRecord has no timestamp — use `block.timestamp` on Lasna for debounce, it's fine here).

Gas: must stay well under the **900k** reactive gas cap — 2 ranges is trivial; still add a gas test.

Keep `react()` lean (lREACT is the binding budget: Lasna fee = gasPrice × coeff/1000 × (gasUsed + 100k `_extraGas`)): route on `topic0` first, early-return on anything unmatched, check `opCode` before decoding, and skip storage writes that don't change state.

Also emit diagnostic events on Lasna (`Decision(...)`) — they make Reactscan readable in the demo.

Expose `coverDebt()`, owner setters for params, `setHedger(address)`.

### 3.8 Math (`DeltaMath` library)

- `amount0(L, sqrtP, sqrtA, sqrtB)` per section "The math" in README; clamp `sqrtP` into `[sqrtA, sqrtB]`.
- Implement with `FullMath`/`SqrtPriceMath` from v4-core; **cross-check bit-for-bit** against `SqrtPriceMath.getAmount0Delta(sqrtP, sqrtB, L, false)` in tests.
- Units: delta in token0 base units if token0 = tWETH. Convert to WAD size for the perp with decimal adjustment. Write one helper, test it hard, use it everywhere.
- Price WAD from `sqrtPriceX96`: `price = sqrtP² / 2^192` adjusted by `10^(dec0 − dec1)`. Use `FullMath.mulDiv` to avoid overflow. Handle inversion if token order demands.

---

## 4. Repository layout & tooling

```
hedgeline/
├── CLAUDE.md                     # short: points here, coding rules, commands
├── plan.md                       # this file
├── README.md
├── foundry.toml                  # profiles: default, lasna (evm_version), ci
├── remappings.txt                # @reactive/=lib/reactive-lib-omni/ ...
├── contracts/
│   ├── src/{HedgelineVault,HedgelineReactive,HedgelineHedger,MiniPerp,TestToken}.sol
│   ├── src/libraries/{DeltaMath,PriceMath}.sol
│   ├── src/interfaces/IHedgeVenue.sol
│   ├── script/{01_DeployBase,02_DeployUnichain,03_DeployReactive,04_DeployHedger,05_Wire}.s.sol
│   ├── script/HookMiner.sol
│   └── test/{unit,fuzz,invariant,loopsim,fork}/
├── scripts/                      # TypeScript + viem
│   ├── move-price.ts  watch.ts  latency.ts  simulate-lag.ts  scenarios.ts  arb-sync.ts
│   └── deployments.json          # single source of addresses, written by deploy scripts
├── frontend/                     # Next.js read-only dashboard
├── docs/{research/,LATENCY.md,DEMO.md,reviews/}
└── .github/workflows/test.yml
```

- Solidity: `^0.8.29` for Reactive-side contracts (lib requires it); pick one compiler version for the whole repo if v4-core allows, otherwise per-profile.
- Use Solady for ERC20/Ownable/SafeTransferLib.
- `.env.example`: `PRIVATE_KEY`, `UNICHAIN_SEPOLIA_RPC`, `BASE_SEPOLIA_RPC`, `LASNA_RPC`. **Never commit `.env`.** One deployer key for all three chains is fine on testnet.

---

## 5. Testing strategy

| Layer | What | Where |
|---|---|---|
| Unit | DeltaMath, PriceMath, MiniPerp accounting (open/close/realize/funding/liquidate), Hedger nonce + clamp + pause, Vault deposit/withdraw/shares | `test/unit` |
| Fuzz | DeltaMath vs `getAmount0Delta` across tick range; MiniPerp PnL symmetry; price conversion round-trips | `test/fuzz` |
| Invariant | Hedger never applies stale nonce; `|short| ≤ maxShort`; collateral never negative without `Liquidated`; vault shares ↔ liquidity consistent | `test/invariant` |
| **Loop simulation** | `OmniSim`: deploy reactive contract locally, etch a mock system contract at `0x8888…8888` that calls `react()` with hand-built `LogRecord`s and **captures `requestCallbackV_1_0` calls**; a `MockCallbackProxy` that overwrites the first 160 bits of the payload with the reactive address and calls the hedger. Test all 5 proof scenarios end-to-end in one process. | `test/loopsim` |
| Fork | Real PoolManagers on Unichain Sepolia / Base Sepolia: vault deposit emits correct event; Base swap emits Swap with expected topics | `test/fork` |
| Gas | `react()` worst case < 500k (headroom under 900k cap); callbacks < 60% of configured gas limit | `test/unit` |

**Rule:** every bug found on testnet gets a regression test in `loopsim` before the fix lands.

---

## 6. Milestones (today = Nov 11; submit Dec 3)

Each milestone ends with: all tests green, `docs/reviews/Mx.md` written (see §8), and a git tag `mX`.

### M0 — Research + scaffold (Nov 11–12)
- Phase 0 complete; `FACTS.md` written.
- Foundry repo, remappings, CI, `.env.example`, `CLAUDE.md`, subagents (§8).
- Wallet funded: Unichain Sepolia ETH, Base Sepolia ETH, lREACT from faucet (human does this).
- **Accept:** `forge build` green; `docs/research/` populated; balances confirmed via `cast balance`.

### M1 — Hello loop on Omni (Nov 13–16) ⚠️ GO/NO-GO GATE
- Minimal `PingOrigin` on Base Sepolia (emits `Ping(uint256 n, uint256 ts)`), minimal `PingReactive` on Lasna, minimal `PingReceiver` (AbstractCallback) on Base Sepolia.
- Then the same with origin on **Unichain Sepolia**.
- Then subscribe to the Base Sepolia **PoolManager Swap** event filtered by a poolId (create a throwaway pool).
- `scripts/watch.ts` prints: origin tx → Lasna reactive tx → `getCallbacks` → destination tx, with timestamps.
- **Accept:** three full loops visible on Reactscan + explorers; first latency numbers recorded in `docs/LATENCY.md`; EVM-version question answered.
- **Gate (Nov 16–18):** if no full loop by **Nov 18**, stop and escalate to the human (fallback project decision). Do not start M2 without a working loop.

### M2 — MiniPerp + Hedger (Nov 16–19)
- `TestToken`, `MiniPerp`, `IHedgeVenue`, `HedgelineHedger` with full tests.
- Deploy to Base Sepolia; reactive contract sends a hardcoded `applyHedge` on a Ping → **a real short opens**.
- **Accept:** `HedgeApplied` + `PositionChanged` on Base Sepolia from a Reactive callback; stale-nonce test passes in loopsim.

### M3 — Vault hook + delta brain (Nov 19–23)
- `HedgelineVault` (hook mined, 2 ranges, shares), `DeltaMath`, full `HedgelineReactive` decide() with S1 + S2, band + notional gate, `HedgeSkipped`.
- Base reference pool + `move-price.ts`; Unichain `arb-sync.ts` (optional script that trades the Unichain pool toward the Base price, to show realism).
- **Accept:** proof scenarios **1, 2, 3, 4** executed on testnet with hashes recorded in `docs/LATENCY.md`.

### M4 — Margin guard + latency suite (Nov 23–26)
- S3 mirror, `marginCheck`, `protectMargin` (STEP_DOWN, CUT, TOP_UP), debounce.
- `scenarios.ts` runs all 5 scenarios in sequence and writes results JSON.
- `latency.ts` (median/p95/max per trigger, ≥ 20 samples each) and `simulate-lag.ts` (measured vs 7 s replay on the same price path).
  - `latency.ts` adds **block-position offsets** (`scripts/lib/blocktime.ts`): Base Sepolia `block.timestamp` is whole seconds shared by ~5 blocks, so time ≈ `ts + blockTime × (block − first block with that ts)`. Output columns using it are labelled **"estimated sub-second"**; whole-second chain-timestamp latency is reported alongside, and the wall-clock receipt watcher (`watch.ts`) stays as a cross-check.
- **Accept:** scenario **5** on testnet; latency + hedge-error tables filled in README from script output.

### M5 — Dashboard (Nov 26–28)
- Next.js read-only: vault delta per range, net delta, current short, margin ratio gauge, live event feed (origin → reactive → callback), latency histogram. Reads `deployments.json`.
- Deploy to Vercel.
- **Accept:** dashboard works without a wallet; shows a live loop within seconds of `move-price`.
- **Scope freeze: Nov 28.** After this, only bug fixes, docs, video.

### M6 — Polish + submission (Nov 29 – Dec 3)
- README: every `TODO` replaced with real data. Banner + diagrams in `assets/`.
- Verify contracts (Sourcify on Lasna; BaseScan/Blockscout on others).
- `docs/DEMO.md` script → record video (< 3:00): 0:00–0:20 problem · 0:20–1:50 live quiet-pool rehedge + skip + margin guard with explorers open · 1:50–2:30 latency table · 2:30–2:55 architecture.
- Fresh-clone test: follow README "Deploy it yourself" on a clean machine/dir.
- Make repo public, submit on DoraHacks: repo, addresses, ≥ 5 full-loop tx hash sets, video.
- **Accept:** submitted by **Dec 3**.

---

## 7. Risks & fallbacks

| Risk | Signal | Fallback |
|---|---|---|
| No full loop on Omni | M1 not done by Nov 18 | Escalate to human; ask in Reactive dev Telegram (https://t.me/reactivedevs) with tx hashes |
| PoolManager Swap events not delivered / filtering issues | M1 step 3 fails | Use `ReferencePool` with `PriceUpdated` event (§3.4) |
| v4 hook-as-vault takes too long | M3 slipping past Nov 22 | Drop the hook: plain vault contract that owns a position via PositionManager and emits the same `PositionUpdated` event. Reactive side unchanged. |
| Callback reverts / `CallbackFailure` | `getCallbacks` shows `err` | Raise gas limit; check both modifiers + first-arg placeholder; add loopsim regression |
| Contract goes `inactive` (debt) | Reactscan status | `depositTo` top-up; check `debt(address)` on system contract / proxy; keep both funded |
| Lasna EVM version mismatch | deploy reverts / invalid opcode | Compile reactive contract with lower `evm_version` profile; keep it free of transient storage |
| Time | Solana hackathon deadline Dec 6 overlaps | Scope freeze Nov 28 is hard |

---

## 8. Working model: Claude Code + human + Claude (chat) reviewer

### 8.1 Roles

- **Human (Abhijeet):** owns keys, funding, deploy approvals, scope decisions, video. Final say.
- **Claude Code (lead session):** implements milestones, runs tests, deploys, writes docs. Works one milestone at a time from this plan.
- **Claude Code subagents** (`.claude/agents/`, keep each prompt short):
  - `test-engineer` — writes/extends tests (unit, fuzz, invariant, loopsim) for code the lead just wrote; never edits `src/`.
  - `security-reviewer` — read-only; reviews diffs for: callback auth (both modifiers), payload first-arg placeholder, nonce logic, clamps, reentrancy, decimals/units, revert-as-filter in `react()`, timestamp vs block count on Base. Outputs findings with severity.
  - `docs-writer` — keeps README, LATENCY.md, DEMO.md in sync with deployed reality; refuses to write numbers not present in script output.
- **Claude (chat) as architect/reviewer:** at each milestone gate the human shares `docs/reviews/Mx.md` (and key files or a public repo link). Chat-Claude reviews design, math, and judging fit, and returns a list of required changes. Claude Code applies them before starting the next milestone.

### 8.2 Milestone review file (`docs/reviews/Mx.md`) — Claude Code writes this

```
# Mx review
## Done (vs acceptance criteria) — checklist
## Deployed addresses + tx hashes (with explorer links)
## Test summary (forge test output tail, counts)
## Decisions made + why (anything not in plan.md)
## Deviations from plan.md
## Open questions for the human / reviewer
## security-reviewer findings + resolution
```

### 8.3 Rules for Claude Code

1. **Never invent addresses, tx hashes, or numbers.** Every on-chain fact in docs must come from a broadcast file, `cast` output or script JSON.
2. **Never copy legacy Reactive patterns** (`vmOnly`, `emit Callback`, `service.subscribe`, `IReactive.LogRecord calldata log` with `vm` flags).
3. **Every callback function:** `address` first param + `onlyServiceProvider` + `onlyCallbackSender`.
4. **No reverts as filters in `react()`.**
5. **Base Sepolia: timestamps, not block counts.**
6. Small commits, conventional messages, tests in the same commit as the feature.
7. Ask the human before: spending > 0.5 testnet ETH in one go, redeploying a contract whose address is already in docs, changing scope.
8. Before each deploy: dry-run (`forge script` without `--broadcast`) and print the plan.
9. Keep `scripts/deployments.json` as the only address registry; scripts and frontend read it.
10. When stuck > 45 min on a platform issue, stop and write a short issue note with tx hashes for the human to post in the Reactive dev channel.
11. **Budget (from M0 review):** print the estimated gas cost before any deploy; **stop if a single step costs > 0.01 ETH**; always keep **≥ 0.02 Base Sepolia ETH** for callback fees.
12. Keep `react()` lean: route on `topic0` first, early return, no unnecessary storage writes (lREACT is the binding budget).

---

## 9. Definition of done (submission checklist)

- [ ] Public GitHub repo, MIT license, CI green
- [ ] Contracts deployed + verified: Vault (Unichain Sepolia), Reactive (Lasna), Hedger + MiniPerp (Base Sepolia)
- [ ] 5 proof scenarios executed; each has origin tx, Lasna reactive tx, callback tx (scenario 3: no callback, `HedgeSkipped` on Lasna)
- [ ] Latency tables (≥ 20 samples per trigger) + hedge-error comparison, generated by scripts, raw data in `docs/LATENCY.md`
- [ ] Test suite: unit + fuzz + invariant + loopsim + fork; counts in README badge
- [ ] README: zero `TODO`s; runbook commands tested on a fresh clone
- [ ] Dashboard live, read-only, no wallet needed
- [ ] Demo video < 3:00, public YouTube link
- [ ] DoraHacks submission done by **Dec 3**

---

## 10. Reference links

- Buildathon: https://blog.reactive.network/reactive-omni-buildathon-thirty-days-to-find-out-what-one-second-buys/ · DoraHacks: https://dorahacks.io/hackathon/reactive-omni-buildathon
- Reactive docs: https://dev.reactive.network/ (Getting Started, Origins & Destinations, Reactive Contracts, Callback Contracts, Economy, Mainnet/Lasna, RNK RPC Methods)
- `reactive-lib-omni`: https://github.com/Reactive-Network/reactive-lib-omni
- Demos: https://github.com/Reactive-Network/reactive-smart-contract-demos
- Reactscan Lasna: https://lasna.reactscan.net · Reactive dev Telegram: https://t.me/reactivedevs
- Uniswap v4 docs: https://docs.uniswap.org/contracts/v4/overview · deployments: https://developers.uniswap.org/docs/protocols/v4/deployments
- LVR: Milionis, Moallemi, Roughgarden, Zhang (2022). Hedge ratio: Hane (2026), arXiv:2603.19716.