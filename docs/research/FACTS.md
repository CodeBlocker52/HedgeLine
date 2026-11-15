# FACTS — plan.md §2 re-verified (2026-11-16)

Legend: ✅ confirmed · ❌ changed (new value given) · ❓ couldn't verify yet (and when we will).
Sources: **D** = live docs captured in `docs/research/*.md` (fetched 2026-11-16) · **L** = `lib/reactive-lib-omni` v0.1.0 source ·
**C** = read-only `cast`/`eth_call` against the public RPCs on 2026-11-16 (no transactions sent) · **U** = official Uniswap v4 deployments page ·
**V4** = `lib/v4-core` source.

## Summary — nothing core changed

**No ❌ on any core fact** (addresses, API names, payload rules all match plan.md §2). Open items:

- ❓ Lasna EVM version under a *real deployment* — `eth_call` shows Cancun opcodes work (PUSH0, TSTORE/TLOAD, MCOPY); `BLOBBASEFEE` crashes the RPC handler. Confirm with the M1 deploy.
- ❓ End-to-end latency per hop — M1.
- ❓ PoolManager `Swap` delivered to Lasna with `topic1 = poolId` filter — M1 step 3.
- ❓ `getCallbacks` return shape on a real reactive tx — M1 (signature is documented, never executed by us).
- ❌ (minor, process only) Plan §1.3: the `basic`, `cron`, `uniswap-v2-stop-take-profit-order` demos on `main` are **all legacy**; Omni demos live on the `omni` branch under `src/micro-demos/` instead. See `demos.md`.
- ➕ New facts not in the plan: callback-proxy gas params, Lasna gas price, Swap `data` layout — see bottom.

## 2.1 Networks

| Fact | Status | Evidence |
|---|---|---|
| Lasna chain ID `5318007` | ✅ | D (reactive-mainnet, origins), C `cast chain-id` → 5318007 |
| Lasna RPC `https://lasna-rpc.rnk.dev/` | ✅ | D; C (responds) |
| Lasna explorer https://lasna.reactscan.net | ✅ | D |
| Unichain Sepolia `1301`, RPC `https://sepolia.unichain.org`, explorer sepolia.uniscan.xyz | ✅ | D (origins table), C `cast chain-id` → 1301 |
| Base Sepolia `84532`, RPC `https://sepolia.base.org`, explorer sepolia.basescan.org | ✅ | D, C `cast chain-id` → 84532 |
| Lasna currency lREACT; mainnet `1597` not used | ✅ | D |
| Mainnets and testnets can't mix in one flow | ✅ | D (origins: "Mainnets and testnets must not be mixed") |
| Unichain Sepolia 1 s blocks, Base Sepolia 200 ms blocks | ✅ | D (buildathon blog) |

## 2.2 Reactive system addresses

| Fact | Status | Evidence |
|---|---|---|
| System contract `0x8888888888888888888888888888888888888888` (Lasna + mainnet) | ✅ | D, L (`AbstractReactive.SYSTEM`), C code present (239 bytes) |
| Legacy system `0x0000000000000000000000000000000000fffFfF` (CRON only) | ✅ | D (reactive-contracts › CRON), C code present |
| Callback proxy Base Sepolia `0x476F44b11F5C942c58f4c8E3d0300E5710743585` | ✅ | D (origins testnet table), C code present |
| Callback proxy Unichain Sepolia `0x775c9B990ADe401060B78D0e98684eEf8d2466C1` | ✅ | D, C code present |
| Callback proxy Ethereum Sepolia `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` | ✅ | D, C code present |
| Lasna faucet (Base Sepolia) `0x2afaFD298b23b62760711756088F75B7409f5967`, `request(address)` payable | ✅ | D; C code present, selector `0x27c78c42` = `request(address)` found in bytecode |
| Rate 1 ETH → 100 lREACT, max 5 ETH per tx | ✅ | D ("Amounts above 5 ETH are lost") |
| Lasna faucet (Sepolia) `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` | ✅ | D, C code present on Ethereum Sepolia |

## 2.3 Uniswap v4

| Chain | Contract | Address | Status |
|---|---|---|---|
| Unichain Sepolia | PoolManager | `0x00b036b58a818b1bc34d502d3fe730db729e62ac` | ✅ U, C |
| Unichain Sepolia | PositionManager | `0xf969aee60879c54baaed9f3ed26147db216fd664` | ✅ U, C |
| Unichain Sepolia | StateView | `0xc199f1072a74d4e905aba1a84d9a45e2546b6222` | ➕ U, C |
| Unichain Sepolia | PoolSwapTest | `0x9140a78c1a137c7ff1c151ec8231272af78a99a4` | ➕ U, C |
| Unichain Sepolia | PoolModifyLiquidityTest | `0x5fa728c0a5cfd51bee4b060773f50554c0c8a7ab` | ➕ U, C |
| Base Sepolia | PoolManager | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` | ✅ U, C |
| Base Sepolia | PositionManager | `0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80` | ✅ U, C |
| Base Sepolia | StateView | `0x571291b572ed32ce6751a2cb2486ebee8defb9b4` | ➕ U, C |
| Base Sepolia | PoolSwapTest | `0x8b5bcc363dde2614281ad875bad385e0a785d3b9` | ➕ U, C |
| Base Sepolia | PoolModifyLiquidityTest | `0x37429cd17cb1454c34e7f50b09725202fd533039` | ➕ U, C |

"C" here = `cast code` returned non-empty bytecode (PoolManager 24009 bytes on both chains; PositionManager 23877 on both). Full excerpt: `uniswap-v4-deployments.md`.

**Swap event** (V4 `src/interfaces/IPoolManager.sol:90`):

```solidity
event Swap(PoolId indexed id, address indexed sender, int128 amount0, int128 amount1,
           uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee);
```

- Canonical signature (PoolId is a UDVT over `bytes32`): `Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)` ✅ matches Plan §3.4.
- `cast keccak` → **topic0 = `0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f`**
- Delivered as LOG3 ⇒ `opCode == 3`; `topic1 = poolId`, `topic2 = sender`; `data` = 6 words `(amount0, amount1, sqrtPriceX96, liquidity, tick, fee)` — `sqrtPriceX96` is word index 2.

## 2.4 Omni reactive contract API

| Fact | Status | Evidence |
|---|---|---|
| `pragma solidity ^0.8.29;` | ✅ | L (all 8 files), D |
| Imports `@reactive/src/{interfaces,base}/...` | ✅ | D, L; compiles in our sanity test |
| No ReactVM / `vm` / `vmOnly` / dual deployment | ✅ | D (Getting Started › Legacy v Omni), L |
| `react(LogRecord memory log_) external onlySystem` | ✅ | D; L declares `calldata` in the interface, `memory` impl compiles (tested) |
| `LogRecord` fields/order as in plan | ✅ | L `IReactive.sol` (see omni-api.md) |
| `LogRecord` has no timestamp | ✅ | L |
| Subscribe semantics (equality only, no OR, wildcards `0`/`address(0)`/`REACTIVE_IGNORE`, ≥1 specific, not readable on-chain, unsubscribe exact match) | ✅ | D (reactive-contracts › Subscriptions) |
| `REACTIVE_IGNORE` value | ➕ | L: `0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad` |
| Don't revert to filter (caught, `ReactiveContractReverted`, billed) | ✅ | D (reactive-contracts, economy) |
| Route on `topic0`, check `opCode` first | ✅ | D |
| `SYSTEM.requestCallbackV_1_0(CallbackConfiguration_V_1_0{chainId, recipient, gasLimit(uint64), payload})` | ✅ | D, L |
| `emit Callback` deprecated | ✅ | D, L (`@dev Deprecated`) |
| First payload arg `address(0)` placeholder, first 160 bits overwritten | ✅ | D |
| `requestCallbackV_1_0` callable from any function | ✅ | D |
| Reactive tx gas cap 900,000 | ✅ | D (economy › Gas Limits) |
| Callback gas limit min 100,000 (lower ignored) | ✅ | D |
| Proxy withholds `_extraGas` + `_maxChargeGas` before forwarding | ✅ | D; values ➕ below |
| Billing: RC pays lREACT; callbacks billed to recipient in destination ETH, even on failure; debt > 0 ⇒ inactive; `depositTo(address)`; `coverDebt()` wrapper | ✅ | D (economy, callback-contracts) |
| CRON: legacy address + `Cron10` topic `0x04463f7c…b687`, every 10 blocks ≈ 10 s, bills each tick | ✅ | D; C `cast keccak "Cron10(uint256)"` matches |
| `getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])` | ✅ signature / ❓ execution | D (economy › Inspecting Callbacks: block number, requester, index, dest chain, dest tx hash, err). Not yet called on a real tx — M1. |
| Sourcify verify `--chain-id 5318007` | ✅ | D |

## 2.5 Omni callback contract API

| Fact | Status | Evidence |
|---|---|---|
| `AbstractCallback(IPayable callbackProxy_, address callbackSender_)` | ✅ | D, L |
| `onlyServiceProvider` + `onlyCallbackSender(reactive_)` — always both | ✅ | D, L; behaviour tested in `Remappings.t.sol` |
| `_CALLBACK_SENDER` immutable, no setter | ✅ | L |
| Deployment order RC → callback → setter → fund | ✅ | D |
| A contract can't be both reactive and callback | ✅ | D, L (single immutable `_SERVICE_PROVIDER`) |

## 2.6 Empirical unknowns

| Question | Status | Evidence / plan |
|---|---|---|
| Lasna EVM version | ❓ partially answered | C raw `eth_call` with init code on Lasna: `PUSH0` ✅, `TSTORE/TLOAD` ✅, `MCOPY` ✅ ⇒ Cancun-level execution; `BLOBBASEFEE` ⇒ RPC error `method handler crashed` (never use `block.blobbasefee`). Same probes all succeed on Base/Unichain Sepolia. Confirm with a real deploy in M1. |
| Real end-to-end latency per hop | ❓ | M1 (`scripts/watch.ts`) |
| Base PoolManager `Swap` reaches Lasna with `topic1 = poolId` | ❓ | M1 step 3 |
| Callback proxy `_extraGas` / `_maxChargeGas` on Base Sepolia | ✅ resolved | C — see below |

## ➕ New facts (not in plan.md)

| Item | Value | Source |
|---|---|---|
| Lasna system `_gasPriceCoeffPer1000` / `_extraGas` / `_maxChargeGas` | 1000 / 100000 / 50000 | C (matches documented defaults) |
| Base Sepolia proxy `_gasPriceCoeffPer1000` / `_extraGas` / `_maxChargeGas` | 1100 / 80000 / 50000 | C |
| Unichain Sepolia proxy `_gasPriceCoeffPer1000` / `_extraGas` / `_maxChargeGas` | 1100 / 80000 / 50000 | C |
| Fee formula (both sides) | `fee = max(tx.gasprice, basefee) · coeff/1000 · (gasUsed + _extraGas)` | D (economy) |
| Lasna gas price / base fee at time of check | 100000000000 wei (100 gwei) / 100 gwei | C `cast gas-price`, `cast base-fee` |
| Base Sepolia gas price / base fee | 6000000 wei / 5000000 wei | C |
| Unichain Sepolia gas price / base fee | 1500000 wei / 500000 wei | C |
| Lasna block gas limit | 1000000000 | C `cast block latest -f gasLimit` |
| Lasna blocks carry a normal `timestamp` (usable for debounce in `react()`) | e.g. 1794768429 | C |
| Proxy rejects callbacks to code-less recipients with `NotAContract` (not charged) | — | D (callback-contracts) |
| `pay()` auto-settles from contract balance when reserves are empty, so a funded balance alone keeps a contract active | — | D (economy) |
| System contract emits `CallbackRequest(uint256 indexed chainId, address indexed sender, address indexed recipient, CallbackVersion version, bytes configuration)` | — | D |
| Docs examples and reactive-lib-omni are `SPDX: UNLICENSED`; no LICENSE file in either repo | — | D, L |

## License decision (Plan §1.5)

`reactive-lib-omni` is UNLICENSED upstream. It is kept **only as a git submodule** (`lib/reactive-lib-omni`, pinned in `.gitmodules` + `foundry.lock`);
its source is not committed to our tree. The demos repo is also UNLICENSED and is cloned into gitignored folders only.
