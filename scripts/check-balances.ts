// Prints the deployer's balances on all three chains plus its reserves/debt on the Lasna system contract.
// Read-only: sends no transactions. Never prints PRIVATE_KEY.
// Usage: npm run check-balances   (loads ../.env via node --env-file)
import { createPublicClient, formatEther, http, isAddress, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { SYSTEM_CONTRACT, baseSepolia, lasna, payableAbi, rpcUrl, unichainSepolia } from "./lib/chains.ts";

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

async function settle<T>(p: Promise<T>): Promise<string> {
  try {
    const v = await p;
    return typeof v === "bigint" ? formatEther(v) : String(v);
  } catch (e) {
    return `error: ${(e as Error).message.split("\n")[0]}`;
  }
}

const [uniEth, baseEth, lreact, debt, reserves] = await Promise.all([
  settle(uni.getBalance({ address: who })),
  settle(base.getBalance({ address: who })),
  settle(rnk.getBalance({ address: who })),
  settle(rnk.readContract({ address: SYSTEM_CONTRACT, abi: payableAbi, functionName: "debt", args: [who] })),
  settle(rnk.readContract({ address: SYSTEM_CONTRACT, abi: payableAbi, functionName: "reserves", args: [who] })),
]);

console.log(`Deployer: ${who}`);
console.table([
  { chain: "Unichain Sepolia (1301)", item: "balance", amount: uniEth, unit: "ETH" },
  { chain: "Base Sepolia (84532)", item: "balance", amount: baseEth, unit: "ETH" },
  { chain: "Reactive Lasna (5318007)", item: "balance", amount: lreact, unit: "lREACT" },
  { chain: "Reactive Lasna (5318007)", item: "system debt", amount: debt, unit: "lREACT" },
  { chain: "Reactive Lasna (5318007)", item: "system reserves", amount: reserves, unit: "lREACT" },
]);
