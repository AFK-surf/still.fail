// Every file a deployed part is built from deploys it: for cloud's api, the station and the beta apps' core, the files
// their bundles take in (esbuild's metafile, npm's packages aside: package.json and the lockfiles say those), each asked
// of scripts/plan.sh on its own. A file the plan does not name for a part that is built from it is a change that part
// never gets (rules/js deployed nothing until 2026-11-05: #3935's and #3983's rules reached no station, cloud or app).
//   node scripts/plan-covers.ts
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
// (station's esbuild, as its build takes it; only what is used of it, typed: the scripts' typecheck has no esbuild)
const esbuild = createRequire(resolve(root, "station/package.json"))("esbuild") as {
  build(options: Record<string, unknown>): Promise<{ metafile?: { inputs: Record<string, unknown> } }>;
};

type Part = { name: string; entries: string[]; keys: string[]; alias?: Record<string, string>; conditions?: string[] };

// The station's bundles, as its build makes them (station/package.json `build`).
const stationEntries = (JSON.parse(readFileSync(resolve(root, "station/package.json"), "utf8")).scripts.build as string)
  .split(" ").filter((w) => /^src\/.*\.ts$/.test(w)).map((w) => `station/${w}`);

const parts: Part[] = [
  // cloud's worker (cloud/wrangler.jsonc `main`)
  { name: "cloud's api", entries: ["cloud/src/index.ts"], keys: ["api"] },
  { name: "the station", entries: stationEntries, keys: ["station"] },
  // the core the beta apps carry (apps/mbui/scripts/core.sh: its entry and aliases)
  {
    name: "the beta apps' core",
    entries: ["apps/mbui/core/hermes.ts"],
    keys: ["android_beta", "mac_beta", "win_beta"],
    alias: { "@core": resolve(root, "client/core-ts/src"), "@ember": root },
    conditions: ["hermes"],
  },
];

async function inputs(p: Part): Promise<string[]> {
  const r = await esbuild.build({
    entryPoints: p.entries.map((e) => resolve(root, e)),
    bundle: true,
    write: false,
    metafile: true,
    outdir: "/nowhere",
    platform: "node",
    format: "esm",
    packages: "external",
    alias: p.alias,
    conditions: p.conditions,
    resolveExtensions: [".ts", ".js", ".mjs", ".json"],
    loader: { ".md": "text", ".txt": "text", ".sql": "text", ".html": "text", ".css": "text", ".svg": "text", ".wasm": "binary", ".node": "file" },
    logLevel: "silent",
  });
  return Object.keys(r.metafile!.inputs)
    .map((f) => relative(root, resolve(root, f.replace(/^[a-z-]+:/, ""))))
    .filter((f) => !f.startsWith("..") && !f.includes("node_modules/"));
}

const files = new Map<string, Part[]>();
for (const p of parts) for (const f of await inputs(p)) files.set(f, [...(files.get(f) ?? []), p]);

// Each file on its own: what plan.sh decides when it is the only one changed.
const script = `PLAN_SOURCE=1; . scripts/plan.sh; range=
while IFS= read -r changed; do decide; echo "$changed api=$api station=$station android_beta=$android_beta mac_beta=$mac_beta win_beta=$win_beta"; done`;
const out = execFileSync("bash", ["-c", script], { cwd: root, input: [...files.keys()].join("\n") + "\n", encoding: "utf8" });

const missed: string[] = [];
for (const line of out.trim().split("\n")) {
  const [file, ...said] = line.split(" ");
  const deploys = new Set(said.filter((s) => s.endsWith("=true")).map((s) => s.slice(0, -5)));
  for (const p of files.get(file!) ?? []) {
    const lacking = p.keys.filter((k) => !deploys.has(k));
    if (lacking.length) missed.push(`${file}: ${p.name} is built from it, but a change to it alone deploys no ${lacking.join(", ")}`);
  }
}
// The agents' rules are built into none of them, and deploy nothing wherever they lie (plan.sh `decide`).
const rules = execFileSync("git", ["ls-files", "AGENTS.md", "CLAUDE.md", "*/AGENTS.md", "*/CLAUDE.md"], { cwd: root, encoding: "utf8" }).trim().split("\n");
const all = `PLAN_SOURCE=1; . scripts/plan.sh; range=
while IFS= read -r changed; do decide; echo "$changed parts=\${static[*]-} api=$api relay=$relay station=$station android_beta=$android_beta mac_beta=$mac_beta win_beta=$win_beta windows_natives=$windows_natives mbui=$mbui"; done`;
for (const line of execFileSync("bash", ["-c", all], { cwd: root, input: rules.join("\n") + "\n", encoding: "utf8" }).trim().split("\n")) {
  const [file, ...said] = line.split(" ");
  const does = said.filter((s) => s.endsWith("=true") || (s.startsWith("parts=") && s !== "parts="));
  if (files.has(file!)) missed.push(`${file}: a part is built from it, so it is no rule file alone: name it otherwise`);
  else if (does.length) missed.push(`${file}: the agents' rules deploy nothing, but a change to it alone does ${does.join(", ")}`);
}
console.log(`plan-covers: ${files.size} files ${parts.map((p) => p.name).join(", ")} are built from`);
if (missed.length) {
  console.error(missed.join("\n") + "\n(say so in scripts/plan.sh)");
  process.exit(1);
}
