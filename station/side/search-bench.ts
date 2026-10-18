// The search index over a station's real data (docs/search.md): built from nothing, as a station's first start with
// search does, into a database of its own (`OUT`, never the station's data directory), read-only on the station's
// store; then the words given (`WORDS`, comma-separated) searched, each a few times. Says how long the build took, how
// large the index is, how many documents of each kind, and how long each search took.
//
//   DATA=~/.stillfail OUT=/tmp/x/search.db WORDS=部署,duckdb,ci node station/side/search-bench.ts
import { rmSync, statSync } from "node:fs";
import { openStore } from "../src/read/store.ts";
import { agentHomeOf } from "../src/read/memory.ts";
import { SearchIndex } from "../src/search/index.ts";
import { historyDocs, jobDocs, memoryDocs, memoryWorkspaces, profileDocs, profilesOf, sessionKeys, threadDocs, threadIds } from "../src/search/sources.ts";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const data = process.env.DATA!;
const out = process.env.OUT!;
if (!data || !out) throw new Error("DATA and OUT are required");
for (const f of [out, `${out}-wal`, `${out}-shm`]) rmSync(f, { force: true });
const s = openStore(data);
const index = new SearchIndex(out);
const raw = JSON.parse(readFileSync(join(data, "config.json"), "utf8"));
const profiles = profilesOf(raw, data);
const took = (since: number) => `${((performance.now() - since) / 1000).toFixed(1)} s`;

let at = performance.now();
const ids = threadIds(s);
for (const id of ids) {
  const found = threadDocs(s, id, null);
  if (found) index.replace(`t:${id}`, found.version, found.docs);
}
console.log(`threads: ${ids.length} in ${took(at)}`);
at = performance.now();
const keys = sessionKeys(s);
for (const key of keys) {
  index.replace(`j:${key}`, "1", jobDocs(s, key).docs);
  const found = historyDocs(s, key, profiles, null);
  if (found) index.replace(`h:${key}`, found.version, found.docs);
}
console.log(`sessions: ${keys.length} in ${took(at)}`);
for (const ws of [null, ...memoryWorkspaces(agentHomeOf(data))]) index.replace(`k:${ws ?? ""}`, "1", memoryDocs(data, ws).docs);
index.replace("p", "1", profileDocs(profiles).docs);
index.db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
const mb = (statSync(out).size / 1048576).toFixed(0);
console.log(`index: ${mb} MB, ${JSON.stringify(index.counts())}`);
const home = { workspace: String(JSON.parse(readFileSync(join(data, "mesh", "cloud.json"), "utf8")).workspace ?? ""), home: true, scopes: ["write"] };
for (const words of (process.env.WORDS ?? "").split(",").filter((w) => w !== "")) {
  const times: number[] = [];
  let found = "";
  for (let i = 0; i < 5; i++) {
    const t0 = performance.now();
    const groups = index.search(words, home, {});
    times.push(performance.now() - t0);
    found = groups.map((g) => `${g.kind} ${g.hits.length}${g.more ? "+" : ""}`).join(", ");
  }
  times.sort((a, b) => a - b);
  console.log(`"${words}": ${found || "nothing"}; ${times[2]!.toFixed(0)} ms (median of 5), slowest ${times[4]!.toFixed(0)} ms`);
}
