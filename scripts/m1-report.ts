// Builds the M1 latency/gas report from results/m1/*.json (read-only, no RPC).
// Per experiment it uses every run with ≥ 5 samples and no errors. Writes results/m1/report.md + summary.json.
// Usage: npm run m1-report
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import type { LoopResult } from "./lib/loop.ts";
import { EXPLORER } from "./lib/loop.ts";

type Run = { exp: string; runId: string; results: LoopResult[] };
const all: Run[] = readdirSync("results/m1")
  .filter((f) => /^E\d-.*\.json$/.test(f))
  .map((f) => JSON.parse(readFileSync(`results/m1/${f}`, "utf8")) as Run);
const ok = (r: Run) => r.results.length >= 5 && r.results.every((x) => !x.error);
const runs = all.filter(ok);
const excluded = all.filter((r) => !ok(r));

const median = (xs: number[]) => {
  if (xs.length === 0) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const max = (xs: number[]) => (xs.length ? Math.max(...xs) : NaN);
const def = (xs: (number | undefined)[]) => xs.filter((x): x is number => typeof x === "number");
const short = (h: string) => `${h.slice(0, 10)}…`;
const link = (chainId: number, h?: string) => (h ? `[${short(h)}](${EXPLORER[chainId]}${h})` : "—");

const summary: Record<string, unknown> = {};
let md = "";
for (const exp of ["E1", "E2", "E3", "E4"]) {
  const rs = runs.filter((r) => r.exp === exp).flatMap((r) => r.results.map((x) => ({ ...x, runId: r.runId })));
  if (rs.length === 0) continue;
  md += `### ${exp} (${rs.length} samples; runs ${[...new Set(rs.map((r) => r.runId))].join(", ")})\n\n`;
  if (exp === "E4") {
    md += "| # | origin tx | Lasna tx | event | CallbackRequest logs | Pinged on Base | getCallbacks | react gas |\n|---|---|---|---|---|---|---|---|\n";
    rs.forEach((r, i) => {
      const pingedCell = r.dest ? link(84532, r.dest.txHash) : `none (Base blocks ${r.origin.blockNumber}–${r.noDestScannedToBlock})`;
      md += `| ${i} | ${link(r.originChainId, r.origin.txHash)} | ${link(5318007, r.lasna?.txHash)} | ${r.lasna?.event}${r.lasna?.skipReason ? ` (reason ${r.lasna.skipReason})` : ""} | ${r.lasna?.callbackRequestLogs} | ${pingedCell} | ${r.callbacks?.length} | ${r.lasna?.gasUsed} |\n`;
    });
    const g = def(rs.map((r) => (r.lasna ? Number(r.lasna.gasUsed) : undefined)));
    summary[exp] = { samples: rs.length, skippedBySkipFlag: rs.filter((r) => r.lasna?.event === "Skipped" && r.lasna.skipReason === 1).length, callbackRequestLogs: rs.reduce((a, r) => a + (r.lasna?.callbackRequestLogs ?? 0), 0), pinged: rs.filter((r) => r.dest).length, reactGas: { median: median(g), max: max(g) } };
    md += `\nreact() gasUsed (Lasna receipt): median ${median(g)}, max ${max(g)}\n\n`;
    continue;
  }
  md +=
    "| # | origin tx | Lasna tx | dest tx | whole-second total (s) | est. sub-second total (ms) | wall-clock origin seen→Lasna seen (ms) | wall-clock Lasna seen→dest seen (ms) | wall-clock origin seen→dest seen (ms) | react gas | callback tx gas |\n|---|---|---|---|---|---|---|---|---|---|---|\n";
  rs.forEach((r, i) => {
    const l = r.latency!;
    md += `| ${i} | ${link(r.originChainId, r.origin.txHash)} | ${link(5318007, r.lasna?.txHash)} | ${link(84532, r.dest?.txHash)} | ${l.wholeSecond.totalS} | ${l.estimatedSubSecond.totalMs} | ${l.wallClock.originSeenToLasnaSeenMs} | ${l.wallClock.lasnaSeenToDestSeenMs} | ${l.wallClock.originSeenToDestSeenMs} | ${r.lasna?.gasUsed} | ${r.dest?.gasUsed} |\n`;
  });
  const col = (f: (r: LoopResult) => number | undefined) => def(rs.map(f));
  const stats = {
    samples: rs.length,
    fullLoops: rs.filter((r) => r.dest).length,
    wholeSecondTotalS: col((r) => r.latency?.wholeSecond.totalS),
    estimatedSubSecondTotalMs: col((r) => r.latency?.estimatedSubSecond.totalMs),
    wallClockOriginSeenToLasnaSeenMs: col((r) => r.latency?.wallClock.originSeenToLasnaSeenMs),
    wallClockLasnaSeenToDestSeenMs: col((r) => r.latency?.wallClock.lasnaSeenToDestSeenMs),
    wallClockOriginSeenToDestSeenMs: col((r) => r.latency?.wallClock.originSeenToDestSeenMs),
    wallClockSentToDestSeenMs: col((r) => r.latency?.wallClock.sentToDestSeenMs),
    lasnaChainTsOriginToLasnaS: col((r) => r.latency?.wholeSecond.originToLasnaS),
    lasnaChainTsLasnaToDestS: col((r) => r.latency?.wholeSecond.lasnaToDestS),
    reactGas: col((r) => (r.lasna ? Number(r.lasna.gasUsed) : undefined)),
    callbackTxGas: col((r) => (r.dest ? Number(r.dest.gasUsed) : undefined)),
  };
  const agg = Object.fromEntries(
    Object.entries(stats).map(([k, v]) => [k, Array.isArray(v) ? { median: median(v), max: max(v), values: v } : v]),
  );
  summary[exp] = agg;
  const a = agg as Record<string, { median: number; max: number }>;
  md += `\n| ${exp} | median | max | kind |\n|---|---|---|---|\n`;
  md += `| total, origin block → dest block | ${a.wholeSecondTotalS.median} s | ${a.wholeSecondTotalS.max} s | whole-second (chain timestamps) |\n`;
  md += `| total, origin block → dest block | ${a.estimatedSubSecondTotalMs.median} ms | ${a.estimatedSubSecondTotalMs.max} ms | estimated sub-second (block position) |\n`;
  md += `| origin receipt seen → Lasna log seen | ${a.wallClockOriginSeenToLasnaSeenMs.median} ms | ${a.wallClockOriginSeenToLasnaSeenMs.max} ms | wall-clock (400 ms polling) |\n`;
  md += `| Lasna log seen → dest log seen | ${a.wallClockLasnaSeenToDestSeenMs.median} ms | ${a.wallClockLasnaSeenToDestSeenMs.max} ms | wall-clock (400 ms polling) |\n`;
  md += `| origin receipt seen → dest log seen | ${a.wallClockOriginSeenToDestSeenMs.median} ms | ${a.wallClockOriginSeenToDestSeenMs.max} ms | wall-clock (400 ms polling) |\n`;
  md += `| tx sent → dest log seen | ${a.wallClockSentToDestSeenMs.median} ms | ${a.wallClockSentToDestSeenMs.max} ms | wall-clock (includes origin inclusion) |\n`;
  md += `| Lasna block ts − origin block ts | ${a.lasnaChainTsOriginToLasnaS.median} s | ${a.lasnaChainTsOriginToLasnaS.max} s | whole-second, **Lasna clock not aligned** |\n`;
  md += `| react() gasUsed | ${a.reactGas.median} | ${a.reactGas.max} | Lasna receipt |\n`;
  md += `| callback tx gasUsed | ${a.callbackTxGas.median} | ${a.callbackTxGas.max} | Base receipt (proxy + onPing) |\n\n`;
}

if (excluded.length) {
  md += "### Runs excluded from the tables (fewer than 5 samples or any error)\n\n| run | exp | samples | errors |\n|---|---|---|---|\n";
  for (const r of excluded) {
    const errs = [...new Set(r.results.map((x) => x.error).filter(Boolean))].join("; ").replace(/\|/g, "/").slice(0, 200);
    md += `| ${r.runId} | ${r.exp} | ${r.results.length} | ${errs || "—"} |\n`;
  }
  md += "\n";
}
writeFileSync("results/m1/report.md", md);
writeFileSync("results/m1/summary.json", JSON.stringify(summary, null, 2));
console.log(md);
