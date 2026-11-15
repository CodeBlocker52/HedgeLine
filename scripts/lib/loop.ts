// Full-loop resolver for the M1 ping loop: origin tx → Lasna reactive tx → destination tx on Base Sepolia.
//
// Lasna tx:   PingReactive emits Relayed/Skipped(originTxHash indexed, originChainId indexed, …) in react().
// Dest tx:    PingReceiver emits Pinged(reactive, n, …, originTxHash indexed, …) on Base Sepolia.
// Cross-check: system contract getCallbacks(lasnaTxHash) must name the same destination tx.
//
// Three kinds of time are recorded and must be labelled as such in reports:
//   whole-second      chain block.timestamp differences (exact to ±1 s)
//   estimated sub-second   block-position estimate from lib/blocktime.ts (Base 200 ms blocks)
//   wall-clock        Date.now() when this watcher first saw each receipt/log (resolution = poll interval)
import {
  createPublicClient,
  http,
  parseAbi,
  parseAbiItem,
  type Address,
  type Hash,
  type PublicClient,
} from "viem";
import { SYSTEM_CONTRACT, baseSepolia, lasna, rpcUrl, unichainSepolia } from "./chains.ts";
import { estimateBlockTime, type BlockTimeEstimate } from "./blocktime.ts";

export const clients = {
  [baseSepolia.id]: createPublicClient({
    chain: baseSepolia,
    transport: http(rpcUrl("BASE_SEPOLIA_RPC", "https://sepolia.base.org")),
  }) as PublicClient,
  [unichainSepolia.id]: createPublicClient({
    chain: unichainSepolia,
    transport: http(rpcUrl("UNICHAIN_SEPOLIA_RPC", "https://sepolia.unichain.org")),
  }) as PublicClient,
  [lasna.id]: createPublicClient({ chain: lasna, transport: http(rpcUrl("LASNA_RPC", "https://lasna-rpc.rnk.dev/")) }) as PublicClient,
};

export const EXPLORER: Record<number, string> = {
  [baseSepolia.id]: "https://sepolia.basescan.org/tx/",
  [unichainSepolia.id]: "https://sepolia.uniscan.xyz/tx/",
  [lasna.id]: "https://lasna.reactscan.net/tx/",
};

const relayed = parseAbiItem("event Relayed(uint256 indexed originTxHash, uint256 indexed originChainId, uint256 n)");
const skipped = parseAbiItem(
  "event Skipped(uint256 indexed originTxHash, uint256 indexed originChainId, uint256 n, uint8 reason)",
);
const pinged = parseAbiItem(
  "event Pinged(address indexed reactive, uint256 indexed n, uint256 originChainId, uint256 originBlock, uint256 indexed originTxHash, uint256 originTimestamp, uint256 timestamp)",
);
const getCallbacksAbi = parseAbi([
  "function getCallbacks(uint256 txHash) view returns ((uint256 blockNumber, address requester, uint256 index, uint256 chainId, uint256 txHash, bytes err)[])",
]);

/** keccak256("CallbackRequest(uint256,address,address,uint8,bytes)"), emitted by the system contract per requested callback. */
export const CALLBACK_REQUEST_TOPIC0 = "0xef94dbc611c4b95bf4b8ba34b413972180c2faf26fbb480befacedd83e07b133";

export interface Hop {
  chainId: number;
  txHash: Hash;
  blockNumber: string;
  timestampS: number;
  estimatedMs: number;
  positionInSecond: number;
  gasUsed: string;
  wallClockSeenMs: number;
}

export interface CallbackRecord {
  blockNumber: string;
  requester: Address;
  index: string;
  chainId: string;
  txHash: Hash;
  err: string;
}

export interface LoopResult {
  originChainId: number;
  originTxHash: Hash;
  sentAtMs: number;
  /** chain head timestamp minus local clock (s), sampled before sending. Lasna's clock is not aligned with Base's. */
  clockSkewS?: Record<string, number>;
  origin: Hop;
  lasna?: Hop & { event: "Relayed" | "Skipped"; n: string; skipReason?: number; callbackRequestLogs: number };
  dest?: Hop & { pingedOriginTimestamp: string; pingedTimestamp: string; n: string };
  /** For Skipped: Base was watched for this long after the Lasna tx and no Pinged appeared. */
  noDestWatchedMs?: number;
  /** Highest Base block covered by the (chunked) scan for a forbidden Pinged. */
  noDestScannedToBlock?: string;
  callbacks?: CallbackRecord[];
  callbacksCheckedAtMs?: number;
  latency?: {
    wholeSecond: { originToLasnaS: number; lasnaToDestS?: number; totalS?: number };
    estimatedSubSecond: { originToLasnaMs: number; lasnaToDestMs?: number; totalMs?: number };
    wallClock: { originSeenToLasnaSeenMs: number; lasnaSeenToDestSeenMs?: number; originSeenToDestSeenMs?: number; sentToDestSeenMs?: number };
  };
  error?: string;
}

/** Error text safe to persist: viem's short message only, with any URL removed (RPC URLs may carry API keys). */
export function safeError(e: unknown): string {
  const err = e as { shortMessage?: string; message?: string };
  return String(err.shortMessage ?? err.message ?? e).replace(/https?:\/\/\S+/g, "<url>");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const toHash = (x: bigint): Hash => `0x${x.toString(16).padStart(64, "0")}`;

/** Public RPCs sit behind load balancers: a block/receipt seen by one node can be missing on the next. Retry. */
async function hop(client: PublicClient, txHash: Hash, seenMs: number): Promise<Hop> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await hopOnce(client, txHash, seenMs);
    } catch (e) {
      if (attempt >= 15) throw e;
      await sleep(500);
    }
  }
}

async function hopOnce(client: PublicClient, txHash: Hash, seenMs: number): Promise<Hop> {
  const r = await client.getTransactionReceipt({ hash: txHash });
  const est: BlockTimeEstimate = await estimateBlockTime(client, r.blockNumber);
  return {
    chainId: client.chain!.id,
    txHash,
    blockNumber: r.blockNumber.toString(),
    timestampS: Number(est.timestampS),
    estimatedMs: est.estimatedMs,
    positionInSecond: est.positionInSecond,
    gasUsed: r.gasUsed.toString(),
    wallClockSeenMs: seenMs,
  };
}

/** Chain head timestamp minus local wall clock, in seconds (one sample per chain). */
export async function clockSkew(): Promise<Record<string, number>> {
  const now = Date.now() / 1000;
  const [b, u, l] = await Promise.all([
    clients[baseSepolia.id].getBlock(),
    clients[unichainSepolia.id].getBlock(),
    clients[lasna.id].getBlock(),
  ]);
  const f = (ts: bigint) => Math.round((Number(ts) - now) * 10) / 10;
  return { base: f(b.timestamp), unichain: f(u.timestamp), lasna: f(l.timestamp) };
}

export async function getCallbacks(lasnaTxHash: Hash): Promise<CallbackRecord[]> {
  const cbs = await clients[lasna.id].readContract({
    address: SYSTEM_CONTRACT,
    abi: getCallbacksAbi,
    functionName: "getCallbacks",
    args: [BigInt(lasnaTxHash)],
  });
  return cbs.map((c) => ({
    blockNumber: c.blockNumber.toString(),
    requester: c.requester,
    index: c.index.toString(),
    chainId: c.chainId.toString(),
    txHash: toHash(c.txHash),
    err: c.err,
  }));
}

export interface ResolveOpts {
  originChainId: number;
  originTxHash: Hash;
  sentAtMs: number;
  /** Wall-clock when the origin receipt was first returned (defaults to now). */
  originSeenMs?: number;
  clockSkewS?: Record<string, number>;
  reactive: Address;
  receiver: Address;
  /** Lasna block to start searching from (take it just before sending). */
  lasnaFromBlock: bigint;
  /** Base block to start searching from for Pinged. */
  baseFromBlock: bigint;
  pollMs?: number;
  timeoutMs?: number;
  /** For Skipped: how long to keep watching Base for a (forbidden) Pinged. */
  noCallbackWaitMs?: number;
  /** How long to poll getCallbacks before giving up (re-check later with `npm run m1 -- recheck`). */
  getCallbacksWaitMs?: number;
}

/** Follows one origin tx through Lasna to Base. Lasna and Base are polled concurrently. Never throws. */
export async function resolveLoop(o: ResolveOpts): Promise<LoopResult> {
  const pollMs = o.pollMs ?? 400;
  const deadline = Date.now() + (o.timeoutMs ?? 120_000);
  const lasnaC = clients[lasna.id];
  const baseC = clients[baseSepolia.id];
  const originC = clients[o.originChainId as keyof typeof clients];
  const originHashNum = BigInt(o.originTxHash);
  const res: LoopResult = {
    originChainId: o.originChainId,
    originTxHash: o.originTxHash,
    sentAtMs: o.sentAtMs,
    clockSkewS: o.clockSkewS,
    origin: await hop(originC, o.originTxHash, o.originSeenMs ?? Date.now()),
  };
  let stopDest = false;

  const watchLasna = async () => {
    while (!res.lasna) {
      if (Date.now() > deadline) throw new Error("timeout waiting for Lasna Relayed/Skipped");
      const [r, s] = await Promise.all([
        lasnaC.getLogs({ address: o.reactive, event: relayed, args: { originTxHash: originHashNum }, fromBlock: o.lasnaFromBlock }),
        lasnaC.getLogs({ address: o.reactive, event: skipped, args: { originTxHash: originHashNum }, fromBlock: o.lasnaFromBlock }),
      ]);
      const seen = Date.now();
      const log = r[0] ?? s[0];
      if (log) {
        const h = await hop(lasnaC, log.transactionHash!, seen);
        const receipt = await lasnaC.getTransactionReceipt({ hash: log.transactionHash! });
        const callbackRequestLogs = receipt.logs.filter(
          (l) => l.address.toLowerCase() === SYSTEM_CONTRACT.toLowerCase() && l.topics[0] === CALLBACK_REQUEST_TOPIC0,
        ).length;
        res.lasna = r[0]
          ? { ...h, event: "Relayed", n: r[0].args.n!.toString(), callbackRequestLogs }
          : { ...h, event: "Skipped", n: s[0].args.n!.toString(), skipReason: Number(s[0].args.reason), callbackRequestLogs };
        return;
      }
      await sleep(pollMs);
    }
  };

  // Base public RPC caps eth_getLogs at 200 blocks: scan with a cursor, re-reading the head chunk until it fills.
  let cursor = o.baseFromBlock;
  const watchDest = async () => {
    while (!res.dest && !stopDest) {
      if (Date.now() > deadline) throw new Error("timeout waiting for Pinged on Base Sepolia");
      const head = await baseC.getBlockNumber();
      const to = head < cursor + 199n ? head : cursor + 199n;
      const logs =
        to >= cursor
          ? await baseC.getLogs({ address: o.receiver, event: pinged, args: { originTxHash: originHashNum }, fromBlock: cursor, toBlock: to })
          : [];
      const seen = Date.now();
      if (logs[0]) {
        const h = await hop(baseC, logs[0].transactionHash!, seen);
        res.dest = {
          ...h,
          n: logs[0].args.n!.toString(),
          pingedOriginTimestamp: logs[0].args.originTimestamp!.toString(),
          pingedTimestamp: logs[0].args.timestamp!.toString(),
        };
        return;
      }
      if (to === cursor + 199n) cursor = to + 1n; // full chunk scanned: move on; otherwise re-scan the head chunk
      else await sleep(pollMs);
    }
  };

  try {
    const destP = watchDest();
    await watchLasna();
    if (res.lasna!.event === "Skipped") {
      // Keep watching Base for a while: a Pinged here would mean the skip path leaked a callback.
      const t0 = Date.now();
      await Promise.race([destP, sleep(o.noCallbackWaitMs ?? 30_000)]);
      stopDest = true;
      await destP;
      res.noDestWatchedMs = Date.now() - t0;
      res.noDestScannedToBlock = cursor.toString();
      if (res.dest) res.error = "Skipped on Lasna but a Pinged appeared on Base";
    } else {
      await destP;
    }

    const cbDeadline = Date.now() + (o.getCallbacksWaitMs ?? 60_000);
    for (;;) {
      res.callbacks = await getCallbacks(res.lasna!.txHash);
      res.callbacksCheckedAtMs = Date.now();
      if (res.callbacks.length > 0 || Date.now() > cbDeadline) break;
      await sleep(2000);
    }
    if (res.lasna!.event === "Skipped" && res.lasna!.callbackRequestLogs > 0) res.error = "Skipped tx emitted CallbackRequest";
    if (res.lasna!.event === "Skipped" && res.callbacks.length > 0) res.error = "Skipped tx has getCallbacks records";
    if (res.dest && res.callbacks[0] && res.callbacks[0].txHash.toLowerCase() !== res.dest.txHash.toLowerCase()) {
      res.error = `getCallbacks dest tx ${res.callbacks[0].txHash} != Pinged tx ${res.dest.txHash}`;
    }
  } catch (e) {
    stopDest = true;
    res.error = safeError(e);
  }

  if (res.lasna) {
    res.latency = {
      wholeSecond: { originToLasnaS: res.lasna.timestampS - res.origin.timestampS },
      estimatedSubSecond: { originToLasnaMs: res.lasna.estimatedMs - res.origin.estimatedMs },
      wallClock: { originSeenToLasnaSeenMs: res.lasna.wallClockSeenMs - res.origin.wallClockSeenMs },
    };
    if (res.dest) {
      res.latency.wholeSecond.lasnaToDestS = res.dest.timestampS - res.lasna.timestampS;
      res.latency.wholeSecond.totalS = res.dest.timestampS - res.origin.timestampS;
      res.latency.estimatedSubSecond.lasnaToDestMs = res.dest.estimatedMs - res.lasna.estimatedMs;
      res.latency.estimatedSubSecond.totalMs = res.dest.estimatedMs - res.origin.estimatedMs;
      res.latency.wallClock.lasnaSeenToDestSeenMs = res.dest.wallClockSeenMs - res.lasna.wallClockSeenMs;
      res.latency.wallClock.originSeenToDestSeenMs = res.dest.wallClockSeenMs - res.origin.wallClockSeenMs;
      res.latency.wallClock.sentToDestSeenMs = res.dest.wallClockSeenMs - res.sentAtMs;
    }
  }
  return res;
}

/** Post-hoc: all Pinged logs for `originTxHash` on Base in [from, to], scanned in 200-block chunks. */
export async function scanPinged(receiver: Address, originTxHash: Hash, from: bigint, to: bigint): Promise<Hash[]> {
  const out: Hash[] = [];
  for (let a = from; a <= to; a += 200n) {
    const b = a + 199n < to ? a + 199n : to;
    const logs = await clients[baseSepolia.id].getLogs({
      address: receiver,
      event: pinged,
      args: { originTxHash: BigInt(originTxHash) },
      fromBlock: a,
      toBlock: b,
    });
    out.push(...logs.map((l) => l.transactionHash!));
  }
  return out;
}
