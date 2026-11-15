// Chain + infrastructure constants. Every address here is verified in docs/research/FACTS.md
// (live docs + `cast code` on 2026-11-16). Our own deployed addresses live in deployments.json only.
import { defineChain, type Address } from "viem";
import { baseSepolia, unichainSepolia } from "viem/chains";

export const lasna = defineChain({
  id: 5318007,
  name: "Reactive Lasna",
  nativeCurrency: { name: "lREACT", symbol: "lREACT", decimals: 18 },
  rpcUrls: { default: { http: ["https://lasna-rpc.rnk.dev/"] } },
  blockExplorers: { default: { name: "Reactscan", url: "https://lasna.reactscan.net" } },
  testnet: true,
});

export { baseSepolia, unichainSepolia };

/** Reactive system contract (Lasna + mainnet). Holds reserves/debt for reactive contracts. */
export const SYSTEM_CONTRACT: Address = "0x8888888888888888888888888888888888888888";

/** Callback proxies. Hold reserves/debt for callback contracts, billed in the destination's native ETH. */
export const CALLBACK_PROXY = {
  [baseSepolia.id]: "0x476F44b11F5C942c58f4c8E3d0300E5710743585",
  [unichainSepolia.id]: "0x775c9B990ADe401060B78D0e98684eEf8d2466C1",
} as const satisfies Record<number, Address>;

export const UNISWAP_V4 = {
  [unichainSepolia.id]: {
    poolManager: "0x00b036b58a818b1bc34d502d3fe730db729e62ac",
    positionManager: "0xf969aee60879c54baaed9f3ed26147db216fd664",
    stateView: "0xc199f1072a74d4e905aba1a84d9a45e2546b6222",
    poolSwapTest: "0x9140a78c1a137c7ff1c151ec8231272af78a99a4",
  },
  [baseSepolia.id]: {
    poolManager: "0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408",
    positionManager: "0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80",
    stateView: "0x571291b572ed32ce6751a2cb2486ebee8defb9b4",
    poolSwapTest: "0x8b5bcc363dde2614281ad875bad385e0a785d3b9",
  },
} as const satisfies Record<number, Record<string, Address>>;

/** Read-only ABI fragments shared by the system contract and callback proxies (IPayable + economy docs). */
export const payableAbi = [
  { type: "function", name: "debt", stateMutability: "view", inputs: [{ name: "contract_", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "reserves", stateMutability: "view", inputs: [{ name: "contract_", type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

export function rpcUrl(envName: string, fallback: string): string {
  const v = process.env[envName];
  return v && v.length > 0 ? v : fallback;
}
