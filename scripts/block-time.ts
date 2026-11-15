// Prints the "estimated sub-second" time of recent blocks (or one block) — a check for lib/blocktime.ts.
// Usage: npm run block-time -- [base|unichain|lasna] [blockNumber] [count]
import { createPublicClient, http, type PublicClient } from "viem";
import { baseSepolia, lasna, rpcUrl, unichainSepolia } from "./lib/chains.ts";
import { estimateBlockTime, SUBSECOND_LABEL } from "./lib/blocktime.ts";

const chains = {
  base: { chain: baseSepolia, env: "BASE_SEPOLIA_RPC", rpc: "https://sepolia.base.org" },
  unichain: { chain: unichainSepolia, env: "UNICHAIN_SEPOLIA_RPC", rpc: "https://sepolia.unichain.org" },
  lasna: { chain: lasna, env: "LASNA_RPC", rpc: "https://lasna-rpc.rnk.dev/" },
} as const;

const [name = "base", blockArg, countArg = "8"] = process.argv.slice(2);
const cfg = chains[name as keyof typeof chains];
if (!cfg) throw new Error(`unknown chain "${name}" (base | unichain | lasna)`);

const client = createPublicClient({ chain: cfg.chain, transport: http(rpcUrl(cfg.env, cfg.rpc)) }) as PublicClient;
const last = blockArg ? BigInt(blockArg) : await client.getBlockNumber();
const count = blockArg ? 1 : Number(countArg);

const rows = [];
for (let n = last - BigInt(count - 1); n <= last; n++) {
  const e = await estimateBlockTime(client, n);
  rows.push({
    block: e.blockNumber.toString(),
    timestamp_s: e.timestampS.toString(),
    position: e.positionInSecond,
    [SUBSECOND_LABEL + " (ms)"]: e.estimatedMs,
  });
}
console.log(`${cfg.chain.name} — ${SUBSECOND_LABEL} block times (estimate, not a measurement)`);
console.table(rows);
