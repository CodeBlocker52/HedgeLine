// Resolves the full loop for one origin tx: origin → Lasna reactive tx → getCallbacks → Base destination tx,
// with block timestamps (whole-second + estimated sub-second), gasUsed per hop, and explorer links. Read-only.
// Usage: npm run watch -- <base|unichain> <originTxHash>
import type { Hash } from "viem";
import { baseSepolia, lasna, unichainSepolia } from "./lib/chains.ts";
import { EXPLORER, clients, resolveLoop } from "./lib/loop.ts";
import deployments from "./deployments.json" with { type: "json" };

const [chainArg, tx] = process.argv.slice(2);
const originChainId = chainArg === "unichain" ? unichainSepolia.id : chainArg === "base" ? baseSepolia.id : 0;
if (!originChainId || !tx?.startsWith("0x")) throw new Error("usage: npm run watch -- <base|unichain> <originTxHash>");

const reactive = deployments.lasna.contracts.PingReactive as `0x${string}`;
const receiver = deployments.baseSepolia.contracts.PingReceiver as `0x${string}`;

// Search Lasna / Base from a little before the origin block's time (Lasna ~1 s blocks, Base ~0.2 s).
const originBlock = (await clients[originChainId].getTransactionReceipt({ hash: tx as Hash })).blockNumber;
const originTs = (await clients[originChainId].getBlock({ blockNumber: originBlock })).timestamp;
const [lasnaHead, baseHead] = await Promise.all([clients[lasna.id].getBlock(), clients[baseSepolia.id].getBlock()]);
const age = BigInt(Math.max(0, Number(lasnaHead.timestamp - originTs))) + 30n;
const res = await resolveLoop({
  originChainId,
  originTxHash: tx as Hash,
  sentAtMs: Number(originTs) * 1000,
  originSeenMs: Number(originTs) * 1000,
  reactive,
  receiver,
  lasnaFromBlock: lasnaHead.number - age,
  baseFromBlock: baseHead.number - age * 5n,
  timeoutMs: 60_000,
  noCallbackWaitMs: 5_000,
});

console.log(JSON.stringify(res, null, 2));
const link = (id: number, h?: string) => (h ? EXPLORER[id] + h : "-");
console.log(`\norigin ${link(originChainId, res.origin.txHash)}`);
console.log(`lasna  ${link(lasna.id, res.lasna?.txHash)} (${res.lasna?.event ?? "not found"})`);
console.log(`dest   ${link(baseSepolia.id, res.dest?.txHash)}`);
if (res.error) process.exitCode = 1;
