// M1 experiments. Sends N origin txs spaced ≥ gap seconds apart, resolves each full loop (lib/loop.ts) and writes
// raw results to results/m1/<EXP>-<runId>.json.
//   E1  ping on Base Sepolia            → Lasna → onPing on Base
//   E2  ping on Unichain Sepolia        → Lasna → onPing on Base
//   E3  swap on our Base reference pool → Lasna → onPing on Base (n = post-swap sqrtPriceX96)
//   E4  ping(skip=true) on Base         → Lasna Skipped, NO destination tx (getCallbacks stays empty)
// Usage: npm run m1 -- E1 [n=5] [gapSeconds=12]
// Sends transactions with PRIVATE_KEY from ../.env (never printed).
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { createWalletClient, http, parseAbi, type Hash } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { UNISWAP_V4, baseSepolia, lasna, rpcUrl, unichainSepolia } from "./lib/chains.ts";
import { EXPLORER, clients, clockSkew, getCallbacks, resolveLoop, scanPinged, type LoopResult } from "./lib/loop.ts";
import deployments from "./deployments.json" with { type: "json" };

const [exp = "E1", nArg = "5", gapArg = "12"] = process.argv.slice(2);

// `npm run m1 -- recheck`: re-query getCallbacks for every Lasna tx in results/m1/*.json (read-only).
if (exp === "recheck") {
  for (const f of readdirSync("results/m1").filter((x) => x.endsWith(".json"))) {
    const path = `results/m1/${f}`;
    const doc = JSON.parse(readFileSync(path, "utf8")) as {
      results: (LoopResult & { callbacksRecheck?: unknown; noDestPostHoc?: unknown })[];
    };
    const receiverAddr = deployments.baseSepolia.contracts.PingReceiver as `0x${string}`;
    for (const r of doc.results) {
      if (!r.lasna) continue;
      const cbs = await getCallbacks(r.lasna.txHash);
      r.callbacksRecheck = { checkedAtMs: Date.now(), callbacks: cbs };
      let extra = "";
      if (r.lasna.event === "Skipped") {
        // Scan Base for any Pinged carrying this origin tx, from the origin block (or the Base head at send time)
        // through 3000 Base blocks (~10 min at 200 ms) later.
        const from = r.originChainId === 84532 ? BigInt(r.origin.blockNumber) : (await clients[84532].getBlockNumber()) - 3000n;
        const head = await clients[84532].getBlockNumber();
        const to = from + 3000n < head ? from + 3000n : head;
        const found = await scanPinged(receiverAddr, r.originTxHash, from, to);
        r.noDestPostHoc = { scannedFromBlock: from.toString(), scannedToBlock: to.toString(), pingedTxs: found };
        extra = ` Base blocks ${from}-${to} Pinged: ${found.length}`;
      }
      console.log(f, r.lasna.event, r.lasna.txHash, "getCallbacks:", cbs.length, cbs[0]?.txHash ?? "", cbs[0]?.err ?? "", extra);
    }
    writeFileSync(path, JSON.stringify(doc, null, 2));
  }
  process.exit(0);
}
if (!["E1", "E2", "E3", "E4"].includes(exp)) throw new Error("experiment must be E1|E2|E3|E4");
const N = Number(nArg);
const GAP_MS = Math.max(10, Number(gapArg)) * 1000; // spec: ≥ 10 s apart

const pk = process.env.PRIVATE_KEY;
if (!pk) throw new Error("PRIVATE_KEY missing in ../.env");
const account = privateKeyToAccount((pk.startsWith("0x") ? pk : `0x${pk}`) as `0x${string}`);

const originChain = exp === "E2" ? unichainSepolia : baseSepolia;
const wallet = createWalletClient({
  account,
  chain: originChain,
  transport: http(
    originChain.id === baseSepolia.id
      ? rpcUrl("BASE_SEPOLIA_RPC", "https://sepolia.base.org")
      : rpcUrl("UNICHAIN_SEPOLIA_RPC", "https://sepolia.unichain.org"),
  ),
});
const originClient = clients[originChain.id];

const pingOrigin = (originChain.id === baseSepolia.id
  ? deployments.baseSepolia.contracts.PingOrigin
  : deployments.unichainSepolia.contracts.PingOrigin) as `0x${string}`;
const tWeth = deployments.baseSepolia.contracts.tWETH as `0x${string}`;
const tUsdc = deployments.baseSepolia.contracts.tUSDC as `0x${string}`;
const reactive = deployments.lasna.contracts.PingReactive as `0x${string}`;
const receiver = deployments.baseSepolia.contracts.PingReceiver as `0x${string}`;

const pingAbi = parseAbi(["function ping(uint256 n, bool skip)"]);
const swapAbi = parseAbi([
  "struct PoolKey { address currency0; address currency1; uint24 fee; int24 tickSpacing; address hooks; }",
  "struct SwapParams { bool zeroForOne; int256 amountSpecified; uint160 sqrtPriceLimitX96; }",
  "struct TestSettings { bool takeClaims; bool settleUsingBurn; }",
  "function swap(PoolKey key, SwapParams params, TestSettings testSettings, bytes hookData) payable returns (int256)",
]);
const MIN_SQRT_PRICE_PLUS_1 = 4295128740n;
const MAX_SQRT_PRICE_MINUS_1 = 1461446703485210103287273052203988822378723970341n;
// tWETH is token0 (plan.md §3.2); alternate direction so the price stays near 3000.
const poolKey = { currency0: tWeth, currency1: tUsdc, fee: 3000, tickSpacing: 60, hooks: "0x0000000000000000000000000000000000000000" } as const;

async function send(i: number): Promise<Hash> {
  if (exp === "E3") {
    const zeroForOne = i % 2 === 0;
    return wallet.writeContract({
      address: UNISWAP_V4[baseSepolia.id].poolSwapTest,
      abi: swapAbi,
      functionName: "swap",
      args: [
        poolKey,
        {
          zeroForOne,
          amountSpecified: zeroForOne ? -10_000_000_000_000_000n : -30_000_000n, // 0.01 tWETH in, or 30 tUSDC in
          sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_PLUS_1 : MAX_SQRT_PRICE_MINUS_1,
        },
        { takeClaims: false, settleUsingBurn: false },
        "0x",
      ],
    });
  }
  const n = BigInt(Date.now());
  return wallet.writeContract({ address: pingOrigin, abi: pingAbi, functionName: "ping", args: [n, exp === "E4"] });
}

const runId = new Date().toISOString().replace(/[:.]/g, "-");
console.log(`${exp}: ${N} samples, ${GAP_MS / 1000}s apart, origin chain ${originChain.id}, run ${runId}`);
const pending: Promise<LoopResult>[] = [];
for (let i = 0; i < N; i++) {
  if (i > 0) await new Promise((r) => setTimeout(r, GAP_MS));
  const [lasnaFromBlock, baseFromBlock] = await Promise.all([
    clients[lasna.id].getBlockNumber(),
    clients[baseSepolia.id].getBlockNumber(),
  ]);
  const skew = await clockSkew();
  const sentAtMs = Date.now();
  const hash = await send(i);
  const receipt = await originClient.waitForTransactionReceipt({ hash, pollingInterval: 200 });
  const originSeenMs = Date.now();
  if (receipt.status !== "success") throw new Error(`origin tx reverted: ${hash}`);
  console.log(`  [${i}] origin ${EXPLORER[originChain.id]}${hash} (block ${receipt.blockNumber})`);
  pending.push(
    resolveLoop({
      originChainId: originChain.id,
      originTxHash: hash,
      sentAtMs,
      originSeenMs,
      clockSkewS: skew,
      reactive,
      receiver,
      lasnaFromBlock: lasnaFromBlock - 2n,
      baseFromBlock,
      timeoutMs: 180_000,
      noCallbackWaitMs: 45_000,
    }),
  );
}

const results = await Promise.all(pending);
mkdirSync("results/m1", { recursive: true });
const file = `results/m1/${exp}-${runId}.json`;
writeFileSync(file, JSON.stringify({ exp, runId, gapMs: GAP_MS, results }, null, 2));

console.table(
  results.map((r) => ({
    origin: r.origin.txHash.slice(0, 10),
    lasna: r.lasna ? `${r.lasna.txHash.slice(0, 10)} ${r.lasna.event}` : "-",
    dest: r.dest?.txHash.slice(0, 10) ?? "-",
    "CallbackRequest logs": r.lasna?.callbackRequestLogs ?? "-",
    getCallbacks: r.callbacks?.length ?? "-",
    "total s (whole-second)": r.latency?.wholeSecond.totalS ?? "-",
    "total ms (est. sub-second)": r.latency?.estimatedSubSecond.totalMs ?? "-",
    "sent→dest seen ms (wall-clock)": r.latency?.wallClock.sentToDestSeenMs ?? "-",
    "react gas": r.lasna?.gasUsed ?? "-",
    "callback tx gas": r.dest?.gasUsed ?? "-",
    error: r.error ?? "",
  })),
);
console.log(`raw results: scripts/${file}`);
if (results.some((r) => r.error)) process.exitCode = 1;
