// Copies deploy tx hashes from a forge broadcast file into deployments.json (`txs` per chain). Read-only on chain.
// Usage: npm run record-broadcast -- ../broadcast/multi/M1Deploy.s.sol-latest/run.json
import { readFileSync, writeFileSync } from "node:fs";

type Tx = { transactionType: string; contractName?: string | null; contractAddress?: string | null; function?: string | null; hash: string };
type Seq = { chain: number; transactions: Tx[]; receipts: { transactionHash: string; status: string }[] };
const file = process.argv[2];
if (!file) throw new Error("usage: npm run record-broadcast -- <broadcast run.json>");
const run = JSON.parse(readFileSync(file, "utf8")) as { deployments: Seq[] };
const reg = JSON.parse(readFileSync("deployments.json", "utf8")) as Record<string, { chainId: number; txs: Record<string, string> }>;
const keyOf = Object.fromEntries(Object.entries(reg).map(([k, v]) => [v.chainId, k]));

for (const seq of run.deployments) {
  const chain = reg[keyOf[seq.chain]];
  seq.transactions.forEach((t, i) => {
    const r = seq.receipts[i];
    if (!r || Number(r.status) !== 1) throw new Error(`tx ${t.hash} on ${seq.chain} not successful`);
    const fn = (t.function ?? "").split("(")[0];
    let key = t.transactionType.startsWith("CREATE") ? `deploy${t.contractName}` : fn || "call";
    if (t.transactionType.startsWith("CREATE") && t.contractName === "TestToken") key = `${key}:${t.contractAddress}`;
    else if (fn === "mint" || fn === "approve") key = `${fn}:${t.contractAddress}:${i}`;
    chain.txs[key] = r.transactionHash;
  });
}
writeFileSync("deployments.json", JSON.stringify(reg, null, 2) + "\n");
console.log(JSON.stringify(reg, null, 2));
