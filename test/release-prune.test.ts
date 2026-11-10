import assert from "node:assert/strict";
import { test } from "node:test";
import { doomedOf } from "../scripts/release-prune.ts";

// What scripts/release-prune.ts deletes of the releases bucket, as a decision on its keys and feeds: the bases of the
// next deltas stay (the newest installers, the Windows installers' raw forms with them, the station's archives its
// feeds name), a delta while its feed offers it, and whatever is newer than its feed (a release being put).
const NOW = 1_800_000_000;
const sha = (c: string) => c.repeat(64);
const station = (build: number, archives: Record<string, string>, deltas: Record<string, { file: string; base: string }[]> = {}) => JSON.stringify({
  version: `0.1.${build}`, build, release: Buffer.from(JSON.stringify({ build, builds: Object.fromEntries(Object.entries(archives).map(([p, s]) => [p, { sha256: s }])) })).toString("base64"), deltas,
});

test("installers: the newest five stay, stable's as beta's; a raw form with its installer; a delta while offered", () => {
  const mac = (n: number) => `desktop/stillfail-0.1.${n}-arm64-mac.zip`;
  const win = (n: number) => `desktop/stillfail-beta-0.1.${n}-x64-win.exe`;
  const keys = [
    ...[1, 2, 3, 4, 5, 6, 7].flatMap((n) => [mac(n), `${mac(n)}.blockmap`]),
    `${mac(7)}.from-6.delta`, `${mac(7)}.from-5.delta`, `${mac(6)}.from-5.delta`, `${mac(8)}.from-7.delta`, mac(8),
    ...[3, 4, 5, 6, 7, 8, 9].flatMap((n) => [win(n), `${win(n)}.raw.zst`, `${win(n)}.sig`]),
    `${win(9)}.from-8.delta`,
    "linux/stillfail-mbui-1-x64-linux.tar.gz", "linux/stillfail-mbui-2-x64-linux.tar.gz", "linux/stillfail-mbui-3-x64-linux.tar.gz",
    "linux/stillfail-mbui-4-x64-linux.tar.gz", "linux/stillfail-mbui-5-x64-linux.tar.gz", "linux/stillfail-mbui-6-x64-linux.tar.gz",
    "linux/stillfail-mbui-6-x64-linux.tar.gz.from-5.delta", "linux/stillfail-mbui-6-arm64-linux.tar.gz",
  ];
  const feeds = {
    "mac/latest.json": JSON.stringify({ versionCode: 7, file: mac(7), deltas: [{ from: 6, file: `${mac(7)}.from-6.delta` }] }),
    "desktop/stillfail-mac.yml": `version: 0.1.7\nfiles:\n  - url: stillfail-0.1.7-arm64-mac.zip\npath: stillfail-0.1.7-arm64-mac.zip\n`,
    "win/beta/latest.json": JSON.stringify({ versionCode: 9, file: win(9), signed: { release: "eyJ/a2luZCI6+IndpbiJ9" }, deltas: [{ from: 8, file: `${win(9)}.from-8.delta` }] }),
    "linux/mbui/latest.json": JSON.stringify({ versionCode: 6, file: "linux/stillfail-mbui-6-x64-linux.tar.gz", deltas: [{ from: 5, file: "linux/stillfail-mbui-6-x64-linux.tar.gz.from-5.delta" }] }),
  };
  const doomed = new Set(doomedOf(keys, feeds, null, NOW));
  // stable: the newest five (8 being put, 7 named, 6..4 the bases) stay, 3..1 go; their blockmaps all stay
  for (const n of [8, 7, 6, 5, 4]) assert.ok(!doomed.has(mac(n)), mac(n));
  for (const n of [3, 2, 1]) assert.ok(doomed.has(mac(n)), mac(n));
  for (const n of [1, 2, 7]) assert.ok(!doomed.has(`${mac(n)}.blockmap`));
  // deltas: the offered one stays, one to 7 not offered goes, one to 6 (older than the feed) goes; 8's (being put) stays
  assert.ok(!doomed.has(`${mac(7)}.from-6.delta`));
  assert.ok(doomed.has(`${mac(7)}.from-5.delta`));
  assert.ok(doomed.has(`${mac(6)}.from-5.delta`));
  assert.ok(!doomed.has(`${mac(8)}.from-7.delta`) && !doomed.has(mac(8)));
  // a beta's installers: 9..5 stay with their raw forms, 4 and 3 go with theirs; .sig as blockmaps (30)
  for (const n of [9, 8, 7, 6, 5]) assert.ok(!doomed.has(win(n)) && !doomed.has(`${win(n)}.raw.zst`), win(n));
  for (const n of [4, 3]) assert.ok(doomed.has(win(n)) && doomed.has(`${win(n)}.raw.zst`), win(n));
  assert.ok(!doomed.has(`${win(3)}.sig`));
  assert.ok(!doomed.has(`${win(9)}.from-8.delta`));
  // Linux's as the others', each machine's by itself (arm64's has no feed here: nothing of it goes)
  assert.ok(doomed.has("linux/stillfail-mbui-1-x64-linux.tar.gz"));
  assert.ok(!doomed.has("linux/stillfail-mbui-2-x64-linux.tar.gz"));
  assert.ok(!doomed.has("linux/stillfail-mbui-6-x64-linux.tar.gz.from-5.delta"));
  assert.ok(!doomed.has("linux/stillfail-mbui-6-arm64-linux.tar.gz"));
});

test("the station's own archives: while their channel's feed names them, as its build or a base, or are newer", () => {
  const a = (ch: string, build: number, s: string, p = "linux-x64") => `station/archive/${ch}/${build}-${sha(s)}-${p}.tar.gz`;
  const d = (ch: string, build: number, s: string, from: number, base: string) => `station/archive/${ch}/${build}-${sha(s)}-linux-x64.from-${from}-${sha(base).slice(0, 16)}.delta`;
  const keys = [
    a("beta", 10, "a"), a("beta", 9, "b"), a("beta", 8, "c"), a("beta", 7, "d"), a("beta", 11, "e"),
    d("beta", 10, "a", 9, "b"), d("beta", 10, "a", 8, "c"), d("beta", 9, "b", 8, "c"), d("beta", 11, "e", 10, "a"),
    a("stable", 5, "f"), a("stable", 4, "g"), a("stable", 3, "h"),
    "beta/stillfail-station-linux-x64.tar.gz", "stillfail-station-linux-x64.tar.gz", "station-beta.json",
  ];
  const feeds = {
    "station-beta.json": station(10, { "linux-x64": sha("a") }, { "linux-x64": [{ file: d("beta", 10, "a", 9, "b"), base: sha("b") }] }),
    // (the stable channel's feed: none yet, so nothing of its goes)
  };
  const doomed = new Set(doomedOf(keys, feeds, null, NOW));
  assert.ok(!doomed.has(a("beta", 10, "a")), "its build");
  assert.ok(!doomed.has(a("beta", 9, "b")), "a base of its delta");
  assert.ok(doomed.has(a("beta", 8, "c")) && doomed.has(a("beta", 7, "d")), "named by nothing");
  assert.ok(!doomed.has(a("beta", 11, "e")) && !doomed.has(d("beta", 11, "e", 10, "a")), "being put");
  assert.ok(!doomed.has(d("beta", 10, "a", 9, "b")), "offered");
  assert.ok(doomed.has(d("beta", 10, "a", 8, "c")) && doomed.has(d("beta", 9, "b", 8, "c")), "not offered");
  for (const k of [a("stable", 5, "f"), a("stable", 3, "h"), "beta/stillfail-station-linux-x64.tar.gz", "stillfail-station-linux-x64.tar.gz", "station-beta.json"]) assert.ok(!doomed.has(k), k);
});

test("staged files after two days; the web archives as before", () => {
  const keys = [`staged/${NOW - 3 * 86400}-abc/x.tar.gz`, `staged/${NOW - 3600}-def/x.tar.gz`, ...[1, 2, 3, 4, 5, 6, 7, 8].map((n) => `desktop/web/stillfail-beta-web-0.1.${n}.tar.gz`)];
  const doomed = doomedOf(keys, {}, 8, NOW);
  assert.deepEqual(doomed, [`staged/${NOW - 3 * 86400}-abc/x.tar.gz`, "desktop/web/stillfail-beta-web-0.1.3.tar.gz", "desktop/web/stillfail-beta-web-0.1.2.tar.gz", "desktop/web/stillfail-beta-web-0.1.1.tar.gz"].sort((x, y) => keys.indexOf(x) - keys.indexOf(y)));
});
