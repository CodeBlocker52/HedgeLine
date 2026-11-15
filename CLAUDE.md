# Hedgeline — Claude Code guide

**Read [Plan.md](Plan.md) first.** It is the source of truth for scope, specs, milestones and process.
README.md describes the finished product. Platform facts verified against live docs: [docs/research/FACTS.md](docs/research/FACTS.md).
Omni API reference: [docs/research/omni-api.md](docs/research/omni-api.md). Work one milestone at a time; stop at each gate.

Reactive Network is **Omni** (Oct 2026). Most examples online are legacy. Only trust dev.reactive.network and `lib/reactive-lib-omni`.

## Rules (Plan.md §8.3, verbatim)

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

Also: never print, read aloud or overwrite `.env`. Ask before adding a dependency not listed in Plan.md.

## Layout

- `contracts/src`, `contracts/script`, `contracts/test/{unit,fuzz,invariant,loopsim,fork,utils}` — Foundry (config in root `foundry.toml`)
- `scripts/` — TypeScript + viem, run with Node's native TS (`node --env-file=../.env x.ts`)
- `docs/research/` — captured docs; `docs/reviews/Mx.md` — milestone gate reports

## Compiler

- Our sources: `pragma solidity ^0.8.29;`, compiled with **0.8.30** (pinned via `compilation_restrictions`), `evm_version = cancun`.
- v4-core `PoolManager.sol` is `=0.8.26`: never import it from 0.8.30 code. Deploy it in tests with
  `deployCode("PoolManager.sol:PoolManager", abi.encode(owner))` (artifact built by `contracts/test/utils/V4Artifacts.sol`).

## Commands

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build --sizes
forge test                                                   # offline suites
forge test --match-path 'contracts/test/fork/*' -vvv         # fork tests (needs RPC env vars)
forge test --gas-report
forge script contracts/script/<X>.s.sol --rpc-url base_sepolia          # dry run first, always
FOUNDRY_PROFILE=lasna forge script contracts/script/03_DeployReactive.s.sol --rpc-url lasna
cd scripts && npm ci && npm run check-balances && npm run typecheck
cast call 0x8888888888888888888888888888888888888888 "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])" $RX_HASH --rpc-url $LASNA_RPC
```
