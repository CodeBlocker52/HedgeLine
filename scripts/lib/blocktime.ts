// Block-position timing: "estimated sub-second" block times.
//
// block.timestamp is whole seconds on every chain we use. On Base Sepolia (~200 ms blocks) about five
// consecutive blocks share one timestamp, so a chain-timestamp latency is only good to ±1 s.
// Estimate: t ≈ timestamp + blockTime × (position of the block among blocks with that timestamp),
// capped below the next second. This is an ESTIMATE. Always report it next to the whole-second figure
// and the wall-clock receipt watcher, and label it "estimated sub-second".
import type { PublicClient } from "viem";

export const SUBSECOND_LABEL = "estimated sub-second";

/** Nominal block times (ms). Base Sepolia: 200 ms since Denim; Unichain Sepolia and Lasna: ~1 s. */
export const BLOCK_TIME_MS: Record<number, number> = {
  84532: 200,
  1301: 1000,
  5318007: 1000,
};

export interface BlockTimeEstimate {
  chainId: number;
  blockNumber: bigint;
  /** Whole-second chain timestamp (exact). */
  timestampS: bigint;
  /** 0-based index of this block among consecutive blocks sharing its timestamp. */
  positionInSecond: number;
  /** timestamp × 1000 + offset, offset = min(position × blockTime, 999). */
  estimatedMs: number;
  label: typeof SUBSECOND_LABEL;
}

const tsCache = new Map<string, bigint>();

async function timestampOf(client: PublicClient, chainId: number, n: bigint): Promise<bigint> {
  const key = `${chainId}:${n}`;
  const hit = tsCache.get(key);
  if (hit !== undefined) return hit;
  const b = await client.getBlock({ blockNumber: n });
  tsCache.set(key, b.timestamp);
  return b.timestamp;
}

export async function estimateBlockTime(client: PublicClient, blockNumber: bigint): Promise<BlockTimeEstimate> {
  const chainId = client.chain?.id ?? (await client.getChainId());
  const blockTimeMs = BLOCK_TIME_MS[chainId] ?? 1000;
  const ts = await timestampOf(client, chainId, blockNumber);

  // Walk back while the previous block has the same timestamp. Bounded by blocks-per-second (+1 slack).
  const maxBack = Math.ceil(1000 / blockTimeMs) + 1;
  let position = 0;
  for (let n = blockNumber - 1n; n >= 0n && position < maxBack; n--) {
    if ((await timestampOf(client, chainId, n)) !== ts) break;
    position++;
  }

  const offset = Math.min(position * blockTimeMs, 999);
  return {
    chainId,
    blockNumber,
    timestampS: ts,
    positionInSecond: position,
    estimatedMs: Number(ts) * 1000 + offset,
    label: SUBSECOND_LABEL,
  };
}

/** Estimated sub-second latency between two blocks (possibly on different chains), in ms. */
export function estimatedLatencyMs(from: BlockTimeEstimate, to: BlockTimeEstimate): number {
  return to.estimatedMs - from.estimatedMs;
}

/** Whole-second latency from chain timestamps alone (exact to ±1 s). */
export function wholeSecondLatencyS(from: BlockTimeEstimate, to: BlockTimeEstimate): number {
  return Number(to.timestampS - from.timestampS);
}
