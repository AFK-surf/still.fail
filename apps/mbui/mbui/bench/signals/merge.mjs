#!/usr/bin/env node
// Puts the native rows (main.exe's JSON lines) beside js-reactivity-benchmark's snapshot and writes the comparison:
// node merge.mjs <snapshot.json> <out prefix> <label=rows.jsonl>...
import { readFileSync, writeFileSync } from "node:fs";

const [snapshotPath, out, ...natives] = process.argv.slice(2);
const snapshot = JSON.parse(readFileSync(snapshotPath, "utf8"));
const rows = [...snapshot.results];
for (const spec of natives) {
  const [label, path] = spec.split("=");
  for (const line of readFileSync(path, "utf8").split("\n")) {
    if (!line.startsWith("{")) continue;
    const row = JSON.parse(line);
    rows.push({ ...row, framework: label });
  }
}

const suites = ["kairo", "mol", "s", "dynamic", "cellx"];
const frameworks = [...new Set(rows.map((r) => r.framework))];
const tests = (suite) => [...new Set(rows.filter((r) => r.suite === suite).map((r) => r.test))];
const time = (fw, suite, test) =>
  rows.find((r) => r.framework === fw && r.suite === suite && r.test === test)?.timeMs;

// js-reactivity-benchmark's relativeSummary: each case's time over the fastest engine's, a geometric mean a suite.
function family(fw, suite, among) {
  const ratios = [];
  for (const test of tests(suite)) {
    const own = time(fw, suite, test);
    const best = Math.min(...among.map((f) => time(f, suite, test)).filter((t) => t > 0));
    if (!(own > 0)) return NaN;
    ratios.push(own / best);
  }
  return Math.exp(ratios.reduce((s, r) => s + Math.log(r), 0) / ratios.length);
}
// a case's time over a reference engine's, a geometric mean a suite (and over all 34 cases)
function versus(fw, ref, suite) {
  const list = (suite ? [suite] : suites).flatMap((s) => tests(s).map((t) => [s, t]));
  const ratios = list.map(([s, t]) => time(fw, s, t) / time(ref, s, t));
  return Math.exp(ratios.reduce((s, r) => s + Math.log(r), 0) / ratios.length);
}

const js = frameworks.filter((f) => !natives.some((n) => n.startsWith(f + "=")));
const fmt = (x) => (Number.isFinite(x) ? `${x.toFixed(2)}×` : "—");
const all = frameworks;
let md = `# mbui signals vs JS signal engines\n\n`;
md += `${snapshot.node} · ${snapshot.system.cpu} · ${snapshot.system.platform} ${snapshot.system.arch} · repeats ${snapshot.repeats} (min) · ${snapshot.startedAt}\n\n`;
// The cases that measure the engine: all but molBench (its time is mostly fib), CellX (one update timed, microseconds:
// a JS engine's warm-up and its clock) and mux (the port makes an array where the benchmark makes an object).
const groups = {
  "kairo (no mux)": (s, t) => s === "kairo" && t !== "mux",
  "s: create": (s, t) => s === "s" && t.startsWith("create"),
  "s: update": (s, t) => s === "s" && t.startsWith("update"),
  dynamic: (s) => s === "dynamic",
};
const inGroup = (s, t) => Object.values(groups).some((g) => g(s, t));
function against(fw, ref, keep) {
  const list = suites.flatMap((s) => tests(s).filter((t) => keep(s, t)).map((t) => [s, t]));
  const ratios = list.map(([s, t]) => time(fw, s, t) / time(ref, s, t));
  return Math.exp(ratios.reduce((a, r) => a + Math.log(r), 0) / ratios.length);
}
const byEngine = [...frameworks].sort((a, b) => against(a, "alien-signals", inGroup) - against(b, "alien-signals", inGroup));
md += `## Against alien-signals (time ÷ alien-signals' on each case, geometric mean; lower is better)\n\n`;
md += `The ${suites.flatMap((s) => tests(s).filter((t) => inGroup(s, t))).length} cases that measure the engine: not molBench (mostly fib), CellX (one update timed) or mux (an array where the benchmark makes an object).\n\n`;
md += `| Engine | ${Object.keys(groups).join(" | ")} | all |\n| --- | ${Object.keys(groups).map(() => "---:").join(" | ")} | ---: |\n`;
for (const fw of byEngine)
  md += `| ${fw} | ${Object.values(groups).map((g) => fmt(against(fw, "alien-signals", g))).join(" | ")} | ${fmt(against(fw, "alien-signals", inGroup))} |\n`;
md += `\n## By family, all engines (time ÷ the fastest on each case, geometric mean; lower is better)\n\n`;
md += `| Engine | ${suites.join(" | ")} | all 34 vs alien |\n| --- | ${suites.map(() => "---:").join(" | ")} | ---: |\n`;
const order = [...all].sort((a, b) => versus(a, "alien-signals") - versus(b, "alien-signals"));
for (const fw of order)
  md += `| ${fw} | ${suites.map((s) => fmt(family(fw, s, all))).join(" | ")} | ${fmt(versus(fw, "alien-signals"))} |\n`;
md += `\n## By family, JS engines only (the published comparison)\n\n`;
md += `| Engine | ${suites.join(" | ")} |\n| --- | ${suites.map(() => "---:").join(" | ")} |\n`;
for (const fw of order.filter((f) => js.includes(f)))
  md += `| ${fw} | ${suites.map((s) => fmt(family(fw, s, js))).join(" | ")} |\n`;

const focus = [...natives.map((n) => n.split("=")[0]), "alien-signals", "Preact Signals", "@vue/reactivity", "SolidJS", "@angular/signals", "Svelte v5", "MobX"].filter((f) => all.includes(f));
md += `\n## Every case (ms, minimum of the samples)\n\n| Suite | Case | ${focus.join(" | ")} |\n| --- | --- | ${focus.map(() => "---:").join(" | ")} |\n`;
for (const s of suites)
  for (const t of tests(s))
    md += `| ${s} | ${t} | ${focus.map((f) => time(f, s, t)?.toFixed(3) ?? "—").join(" | ")} |\n`;

writeFileSync(`${out}.md`, md);
const summary = {
  meta: { node: snapshot.node, cpu: snapshot.system.cpu, repeats: snapshot.repeats, startedAt: snapshot.startedAt, packages: snapshot.packages },
  suites,
  engines: order.map((fw) => ({
    name: fw,
    native: !js.includes(fw),
    family: Object.fromEntries(suites.map((s) => [s, family(fw, s, all)])),
    familyJs: js.includes(fw) ? Object.fromEntries(suites.map((s) => [s, family(fw, s, js)])) : null,
    vsAlien: versus(fw, "alien-signals"),
    vsAlienBySuite: Object.fromEntries(suites.map((s) => [s, versus(fw, "alien-signals", s)])),
  })),
  cases: suites.flatMap((s) => tests(s).map((t) => ({ suite: s, test: t, ms: Object.fromEntries(all.map((f) => [f, time(f, s, t)])) }))),
};
writeFileSync(`${out}.json`, JSON.stringify(summary, null, 2) + "\n");
process.stdout.write(md);
