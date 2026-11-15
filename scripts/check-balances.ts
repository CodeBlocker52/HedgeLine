// Prints the deployer's balances on all three chains, its reserves/debt on the Lasna system contract,
// the estimated lREACT cost per reactive tx (from live gas price + system params), and budget checks.
// Read-only: sends no transactions. Never prints PRIVATE_KEY.
// Usage: npm run check-balances   (loads ../.env via node --env-file)
import { createPublicClient, formatEther, http, isAddress, parseEther, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  CALLBACK_PROXY,
  SYSTEM_CONTRACT,
  baseSepolia,
  feeParamsAbi,
  lasna,
  payableAbi,
  rpcUrl,
  unichainSepolia,
} from "./lib/chains.ts";

/** plan.md §8.3 rule 11: always keep at least this much Base Sepolia ETH for callback fees. */
const BASE_CALLBACK_RESERVE = parseEther("0.02");
/** Assumed gasUsed values for one react() (planning rows for heavier M3/M4 logic). */
const ASSUMED_REACT_GAS = [50_000n, 100_000n, 200_000n, 400_000n];
/**
 * Measured in M1 (docs/reviews/M1.md): PingReactive balance diff across one reactive tx on Lasna at 100 gwei.
 * The charge is LOWER than the docs formula with the receipt's gasUsed (0.0128474 vs 0.0188289 for 88,289 gas).
 */
const MEASURED_M1 = [
  { route: "Ping relayed (1 callback)", receiptGasUsed: 88_289, chargedWei: 12_847_400_000_000_000n },
  { route: "Swap relayed (1 callback)", receiptGasUsed: 90_436, chargedWei: 12_856_100_000_000_000n },
  { route: "Ping skipped (no callback)", receiptGasUsed: 74_324, chargedWei: 11_316_600_000_000_000n },
];
/** Assumed gasUsed for one hedge callback on Base (assumption until M2 measures it). */
const ASSUMED_CALLBACK_GAS = 300_000n;

function deployer(): Address {
  const explicit = process.env.DEPLOYER_ADDRESS;
  if (explicit && isAddress(explicit)) return explicit;
  const pk = process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Set DEPLOYER_ADDRESS or PRIVATE_KEY in .env");
  return privateKeyToAccount((pk.startsWith("0x") ? pk : `0x${pk}`) as `0x${string}`).address;
}

const who = deployer();
const uni = createPublicClient({ chain: unichainSepolia, transport: http(rpcUrl("UNICHAIN_SEPOLIA_RPC", "https://sepolia.unichain.org")) });
const base = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl("BASE_SEPOLIA_RPC", "https://sepolia.base.org")) });
const rnk = createPublicClient({ chain: lasna, transport: http(rpcUrl("LASNA_RPC", "https://lasna-rpc.rnk.dev/")) });

const fee = (client: typeof rnk | typeof base, address: Address) =>
  Promise.all([
    client.readContract({ address, abi: feeParamsAbi, functionName: "_gasPriceCoeffPer1000" }),
    client.readContract({ address, abi: feeParamsAbi, functionName: "_extraGas" }),
    client.getGasPrice(),
  ]);

const [uniEth, baseEth, lreact, debt, reserves, [lCoeff, lExtra, lGasPrice], [bCoeff, bExtra, bGasPrice]] = await Promise.all([
  uni.getBalance({ address: who }),
  base.getBalance({ address: who }),
  rnk.getBalance({ address: who }),
  rnk.readContract({ address: SYSTEM_CONTRACT, abi: payableAbi, functionName: "debt", args: [who] }),
  rnk.readContract({ address: SYSTEM_CONTRACT, abi: payableAbi, functionName: "reserves", args: [who] }),
  fee(rnk, SYSTEM_CONTRACT),
  fee(base, CALLBACK_PROXY[baseSepolia.id]),
]);

console.log(`Deployer: ${who}\n`);
console.table([
  { chain: "Unichain Sepolia (1301)", item: "balance", amount: formatEther(uniEth), unit: "ETH" },
  { chain: "Base Sepolia (84532)", item: "balance", amount: formatEther(baseEth), unit: "ETH" },
  { chain: "Reactive Lasna (5318007)", item: "balance", amount: formatEther(lreact), unit: "lREACT" },
  { chain: "Reactive Lasna (5318007)", item: "system debt", amount: formatEther(debt), unit: "lREACT" },
  { chain: "Reactive Lasna (5318007)", item: "system reserves", amount: formatEther(reserves), unit: "lREACT" },
]);

// fee = gasPrice × coeff/1000 × (gasUsed + _extraGas)   (docs/research/economy.md › Fee Model)
const reactFee = (gasUsed: bigint) => (lGasPrice * lCoeff * (gasUsed + lExtra)) / 1000n;
const lreactBudget = lreact + reserves;
console.log(
  `\nLasna reactive tx cost (ESTIMATE): gasPrice ${lGasPrice} wei × coeff ${lCoeff}/1000 × (gasUsed + _extraGas ${lExtra})`,
);
console.table(
  ASSUMED_REACT_GAS.map((g) => ({
    "assumed react() gasUsed": g.toString(),
    "lREACT per reactive tx": formatEther(reactFee(g)),
    "txs covered by balance+reserves": (lreactBudget / reactFee(g)).toString(),
  })),
);

console.log("Measured in M1 (PingReactive balance diff per reactive tx):");
console.table(
  MEASURED_M1.map((m) => ({
    route: m.route,
    "receipt gasUsed": m.receiptGasUsed,
    "lREACT charged": formatEther(m.chargedWei),
    "txs covered by balance+reserves": (lreactBudget / m.chargedWei).toString(),
  })),
);

const cbFee = (bGasPrice * bCoeff * (ASSUMED_CALLBACK_GAS + bExtra)) / 1000n;
console.log(
  `Base callback cost (ESTIMATE, assumed ${ASSUMED_CALLBACK_GAS} gasUsed): ${formatEther(cbFee)} ETH ` +
    `(gasPrice ${bGasPrice} wei × coeff ${bCoeff}/1000 × (gasUsed + _extraGas ${bExtra}))`,
);

const spendableBase = baseEth > BASE_CALLBACK_RESERVE ? baseEth - BASE_CALLBACK_RESERVE : 0n;
const ok = baseEth >= BASE_CALLBACK_RESERVE && debt === 0n;
console.log(`\nBudget checks (plan.md §8.3 rule 11):`);
console.log(`  Base Sepolia ≥ 0.02 ETH callback reserve: ${baseEth >= BASE_CALLBACK_RESERVE ? "OK" : "FAIL"} (spendable above reserve: ${formatEther(spendableBase)} ETH)`);
console.log(`  Lasna system debt == 0: ${debt === 0n ? "OK" : "FAIL"}`);
console.log(`  Per-step deploy cap: 0.01 ETH (enforced before each deploy)`);
if (!ok) process.exitCode = 1;
