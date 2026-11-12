import assert from "node:assert/strict";
import { test } from "node:test";
import { baseFile } from "../scripts/release-deltas.ts";
import { aheadOf, doomedOf } from "../scripts/release-prune.ts";

// What scripts/release-prune.ts deletes of the releases bucket, as a decision on its keys and feeds: the bases of the
// next deltas stay (the installers the feeds' deltas are from, the Windows installers' raw forms with them, the station's archives its
// feeds name), a delta while its feed offers it, and whatever is newer than its feed (a release being put).
const NOW = 1_800_000_000;
const sha = (c: string) => c.repeat(64);
const station = (build: number, archives: Record<string, string>, deltas: Record<string, { file: string; base: string }[]> = {}) => JSON.stringify({
  version: `0.1.${build}`, build, release: Buffer.from(JSON.stringify({ build, builds: Object.fromEntries(Object.entries(archives).map(([p, s]) => [p, { sha256: s }])) })).toString("base64"), deltas,
});

test("installers: the feed's, any newer, and its deltas' bases, stable's as beta's; a raw form with its installer; a delta while offered", () => {
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
  // stable: 8 being put, 7 named, 6 its base stay, 5..1 go; their blockmaps all stay
  for (const n of [8, 7, 6]) assert.ok(!doomed.has(mac(n)), mac(n));
  for (const n of [5, 4, 3, 2, 1]) assert.ok(doomed.has(mac(n)), mac(n));
  for (const n of [1, 2, 7]) assert.ok(!doomed.has(`${mac(n)}.blockmap`));
  // deltas: the offered one stays, one to 7 not offered goes, one to 6 (older than the feed) goes; 8's (being put) stays
  assert.ok(!doomed.has(`${mac(7)}.from-6.delta`));
  assert.ok(doomed.has(`${mac(7)}.from-5.delta`));
  assert.ok(doomed.has(`${mac(6)}.from-5.delta`));
  assert.ok(!doomed.has(`${mac(8)}.from-7.delta`) && !doomed.has(mac(8)));
  // a beta's installers: 9 and its base 8 stay with their raw forms, 7..3 go with theirs; .sig as blockmaps (30)
  for (const n of [9, 8]) assert.ok(!doomed.has(win(n)) && !doomed.has(`${win(n)}.raw.zst`), win(n));
  for (const n of [7, 6, 5, 4, 3]) assert.ok(doomed.has(win(n)) && doomed.has(`${win(n)}.raw.zst`), win(n));
  assert.ok(!doomed.has(`${win(3)}.sig`));
  assert.ok(!doomed.has(`${win(9)}.from-8.delta`));
  // Linux's as the others', each machine's by itself (arm64's has no feed here: nothing of it goes)
  for (const n of [1, 2, 3, 4]) assert.ok(doomed.has(`linux/stillfail-mbui-${n}-x64-linux.tar.gz`), String(n));
  assert.ok(!doomed.has("linux/stillfail-mbui-5-x64-linux.tar.gz"));
  assert.ok(!doomed.has("linux/stillfail-mbui-6-x64-linux.tar.gz.from-5.delta"));
  assert.ok(!doomed.has("linux/stillfail-mbui-6-arm64-linux.tar.gz"));
});

test("Android beta as seen on production: the feed's base stays, APKs of runs that never were a feed go", () => {
  const apk = (n: number) => `android/stillfail-beta-${n}.apk`;
  const keys = [8358, 8360, 8365, 8367, 8370, 8372, 8375, 99999].map(apk);
  const feeds = { "android/beta/latest.json": JSON.stringify({ versionCode: 8367, file: apk(8367), deltas: [{ from: 8360, file: `${apk(8367)}.from-8360.delta` }] }) };
  // (8365: put by a run later cancelled; 8370.. 99999: newer than the feed, put before theirs or never to be one)
  assert.deepEqual(doomedOf(keys, feeds, null, NOW), [apk(8358), apk(8365)]);
  assert.deepEqual(aheadOf(keys, feeds), [8370, 8372, 8375, 99999].map(apk));
});

test("ten bases all stay, an eleventh older installer goes; a feed without deltas keeps none older", () => {
  const apk = (n: number) => `android/stillfail-beta-${n}.apk`;
  const keys = Array.from({ length: 12 }, (_, i) => apk(100 + i));
  const from = Array.from({ length: 10 }, (_, i) => 110 - i);
  const feeds = { "android/beta/latest.json": JSON.stringify({ versionCode: 111, file: apk(111), deltas: from.map((n) => ({ from: n, file: `${apk(111)}.from-${n}.delta` })) }) };
  assert.deepEqual(doomedOf(keys, feeds, null, NOW), [apk(100)]);
  const none = { "android/beta/latest.json": JSON.stringify({ versionCode: 111, file: apk(111) }) };
  assert.deepEqual(doomedOf(keys, none, null, NOW), keys.slice(0, 11));
  // (a feed not read as JSON: no bases either)
  assert.deepEqual(doomedOf(keys, { "android/beta/latest.json": `{"versionCode": 111, "file": "${apk(111)}", ` }, null, NOW), keys.slice(0, 11));
});

test("desktop: the base's build is swapped inside 0.1.N; the yml feed naming the same zip changes nothing", () => {
  const zip = (n: number) => `desktop/stillfail-beta-0.1.${n}-arm64-mac.zip`;
  assert.equal(baseFile(zip(9), 9, 8), zip(8));
  const keys = [6, 7, 8, 9].map(zip);
  const json = { "mac/beta/latest.json": JSON.stringify({ versionCode: 9, file: zip(9), deltas: [{ from: 8, file: `${zip(9)}.from-8.delta` }, { from: 7, file: `${zip(9)}.from-7.delta` }] }) };
  assert.deepEqual(doomedOf(keys, json, null, NOW), [zip(6)]);
  const yml = { ...json, "desktop/stillfail-beta-mac.yml": `version: 0.1.9\nfiles:\n  - url: stillfail-beta-0.1.9-arm64-mac.zip\npath: stillfail-beta-0.1.9-arm64-mac.zip\n` };
  assert.deepEqual(doomedOf(keys, yml, null, NOW), [zip(6)]);
});

test("Windows: a base's exe and its raw form stay together, a non-base's go together", () => {
  const exe = (n: number) => `win/stillfail-mbui-${n}-x64-win.exe`;
  const keys = [3, 4, 5].flatMap((n) => [exe(n), `${exe(n)}.raw.zst`]);
  const feeds = { "win/mbui/latest.json": JSON.stringify({ versionCode: 5, file: exe(5), deltas: [{ from: 4, file: `${exe(5)}.from-4.delta` }] }) };
  assert.deepEqual(doomedOf(keys, feeds, null, NOW), [exe(3), `${exe(3)}.raw.zst`]);
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

test("an Android release's symbols: older than 30 days by when the bucket says they were put go, nothing else by it", () => {
  const sym = (n: number) => `symbols/android/stillfail-beta-${n}.syms.xz`;
  const apk = (n: number) => `android/stillfail-beta-${n}.apk`;
  const keys = [sym(1), sym(2), sym(3), sym(4), ...[1, 2, 3, 4, 5, 6, 7].map(apk), `staged/${NOW - 3600}-abc/x.tar.gz`, "stillfail-station-linux-x64.tar.gz"];
  const feeds = { "android/beta/latest.json": JSON.stringify({ versionCode: 7, file: apk(7) }) };
  const day = 86400;
  // (sym(4): no time read of it)
  const putAt = new Map([[sym(1), NOW - 31 * day], [sym(2), NOW - 29 * day], [sym(3), NaN]]);
  const doomed = new Set(doomedOf(keys, feeds, null, NOW, putAt));
  assert.ok(doomed.has(sym(1)), "older than 30 days");
  assert.ok(!doomed.has(sym(2)), "younger");
  assert.ok(!doomed.has(sym(3)) && !doomed.has(sym(4)), "no time");
  // every other key's fate as without the times, however old they say it is
  const old = new Map(keys.map((k) => [k, NOW - 365 * day]));
  const others = (d: string[]) => d.filter((k) => !k.startsWith("symbols/"));
  assert.deepEqual(others(doomedOf(keys, feeds, null, NOW, old)), others(doomedOf(keys, feeds, null, NOW)));
  assert.deepEqual(others([...doomed]), [1, 2, 3, 4, 5, 6].map(apk));
  assert.deepEqual(doomedOf(keys, feeds, null, NOW).filter((k) => k.startsWith("symbols/")), [], "none goes without times");
});
