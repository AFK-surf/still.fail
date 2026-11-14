// A test's own feed (an AppRelease, latest.json) given a delta, as still.fail's releases list one (client/core-ts
// src/app-release.ts): `raw` (what the delta makes where that is not the release's file itself: its sha256 and size)
// and `deltas` (one, from the build named). e2e/win.sh's and scripts/e2e-local.sh release-seed's.
//   node e2e/feed-delta.mjs FEED RAW|- FROM FILE DELTA     FILE: the delta's path under /releases/, DELTA: where it is here
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const [feed, raw, from, file, delta] = process.argv.slice(2);
if (!delta || !/^\d+$/.test(from)) {
  console.error("usage: feed-delta.mjs FEED RAW|- FROM FILE DELTA");
  process.exit(2);
}
const said = (path) => {
  const b = readFileSync(path);
  return { sha256: createHash("sha256").update(b).digest("hex"), size: b.length };
};
const release = JSON.parse(readFileSync(feed, "utf8"));
if (raw !== "-") release.raw = said(raw);
release.deltas = [{ from: Number(from), file, ...said(delta) }];
writeFileSync(feed, JSON.stringify(release) + "\n");
console.log(`feed-delta: ${feed}: ${raw !== "-" ? `raw ${release.raw.size} bytes, ` : ""}a delta from ${from} of ${release.deltas[0].size} bytes`);
