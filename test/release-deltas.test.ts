import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { crc32, deflateRawSync, gunzipSync, zstdCompressSync } from "node:zlib";
import { applyFile, storedZip } from "../scripts/delta.ts";

// scripts/release-deltas.ts on a release directory of every kind of feed, the releases "published" before it a
// directory too (--releases): the deltas made, each giving the package's raw form from what an installed build has
// (the reference applier; Android's, the Java one), the feeds amended, and what leaves a delta out (no feed before,
// a base not there, a delta too big, one that fails) leaving the feed whole. Run twice, nothing changes; run one pair
// at a time, the same is made.
const root = fileURLToPath(new URL("..", import.meta.url));
const script = join(root, "scripts/release-deltas.ts");
const has = (cmd: string) => spawnSync(cmd, ["-version"], { encoding: "utf8" }).status === 0;
const noJava = has("javac") && has("java") ? false : "no javac or java here: Android's deltas (checked by the Java applier) are not tested";
const sha = (b: Uint8Array) => createHash("sha256").update(b).digest("hex");

/** Bytes like a program's, the same each time; `edit` changes a few of them. */
function bytes(n: number, seed: number, edit = 0): Buffer {
  const out = Buffer.alloc(n);
  let s = seed;
  for (let i = 0; i < n; i++) {
    s = (Math.imul(s, 1103515245) + 12345) >>> 0;
    out[i] = 32 + ((s >>> 16) % 95);
  }
  for (let k = 0; k < edit; k++) out[(k * 7919 + 13) % n] = 33 + k % 90;
  return out;
}

type Entry = { name: string; data?: Buffer; deflate?: boolean; mode?: number };
/** A zip as zip(1) and ditto write one: Unix modes in the external attributes (a symlink's target its data). */
function zip(entries: Entry[]): Buffer {
  const parts: Buffer[] = [], central: Buffer[] = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name), data = e.data ?? Buffer.alloc(0);
    const body = e.deflate ? deflateRawSync(data, { level: 6 }) : data, crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(e.deflate ? 8 : 0, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0);
    c.writeUInt16LE(0x031e, 4);
    c.writeUInt16LE(20, 6);
    c.writeUInt16LE(e.deflate ? 8 : 0, 10);
    c.writeUInt32LE(crc, 16);
    c.writeUInt32LE(body.length, 20);
    c.writeUInt32LE(data.length, 24);
    c.writeUInt16LE(name.length, 28);
    c.writeUInt32LE(((e.mode ?? (e.name.endsWith("/") ? 0o40755 : 0o100644)) << 16) >>> 0, 38);
    c.writeUInt32LE(offset, 42);
    parts.push(local, name, body);
    central.push(c, name);
    offset += 30 + name.length + body.length;
  }
  const cd = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, cd, end]);
}

/** A folder's files tarred and gzipped (the system's tar: a tar as releases have them). */
function tgz(files: Record<string, Buffer | { link: string }>, top: string, out: string) {
  const stage = mkdtempSync(join(tmpdir(), "release-deltas-tar-"));
  for (const [name, data] of Object.entries(files)) {
    const path = join(stage, top, name);
    mkdirSync(dirname(path), { recursive: true });
    if (Buffer.isBuffer(data)) writeFileSync(path, data);
    else execFileSync("ln", ["-s", data.link, path]);
  }
  mkdirSync(dirname(out), { recursive: true });
  execFileSync("tar", ["-czf", out, "-C", stage, top], { env: { ...process.env, COPYFILE_DISABLE: "1" } });
  rmSync(stage, { recursive: true, force: true });
}

/** A raw installer (apps/mbui/windows/setup.c --raw): its program, MBSETUP0, the files stored, its offset, MBSETUP0. */
function rawInstaller(stub: Buffer, files: { name: string; data: Buffer }[]): Buffer {
  const parts: Buffer[] = [stub, Buffer.from("MBSETUP0")];
  const u32 = Buffer.alloc(4);
  u32.writeUInt32LE(files.length);
  parts.push(u32);
  for (const f of files) {
    const nl = Buffer.alloc(2), sizes = Buffer.alloc(16), name = Buffer.from(f.name, "utf16le");
    nl.writeUInt16LE(f.name.length);
    sizes.writeBigUInt64LE(BigInt(f.data.length), 0);
    sizes.writeBigUInt64LE(BigInt(f.data.length), 8);
    parts.push(nl, name, sizes, f.data);
  }
  const at = Buffer.alloc(8);
  at.writeBigUInt64LE(BigInt(stub.length));
  parts.push(at, Buffer.from("MBSETUP0"));
  return Buffer.concat(parts);
}

// Signed as scripts/release-sign.ts signs (station/test/release-fakes.ts's way): a key of the test's own.
const { privateKey } = generateKeyPairSync("ed25519");
const signed = (words: object) => {
  const b = Buffer.from(JSON.stringify(words));
  return { release: b.toString("base64"), signature: sign(null, b, privateKey).toString("base64"), key: "test" };
};

const put = (dir: string, name: string, data: Buffer | string | object) => {
  mkdirSync(dirname(join(dir, name)), { recursive: true });
  writeFileSync(join(dir, name), Buffer.isBuffer(data) || typeof data === "string" ? data : `${JSON.stringify(data)}\n`);
};
const file = (name: string, data: Buffer) => ({ file: name, sha256: sha(data), size: data.length });

// --- the packages of build n (an edit each build) ---

const MAC = (n: number) => `desktop/stillfail-beta-0.1.${n}-arm64-mac.zip`;
const macFiles = (n: number) => ({
  "Test.app/Contents/MacOS/test": bytes(60_000, 1, n - 90),
  "Test.app/Contents/Info.plist": Buffer.from(`<plist><string>${n}</string></plist>`),
  "Test.app/Contents/Frameworks/A.framework/Versions/A/A": bytes(30_000, 2),
});
const macZip = (n: number) => zip([
  { name: "Test.app/", mode: 0o40755 },
  ...Object.entries(macFiles(n)).map(([name, data]) => ({ name, data, deflate: true })),
  { name: "Test.app/Contents/Frameworks/A.framework/Versions/Current", data: Buffer.from("A"), mode: 0o120755 },
]);

const LINUX = (n: number) => `linux/stillfail-mbui-${n}-x64-linux.tar.gz`;
const linuxFiles = (n: number) => ({
  stillfail: bytes(50_000, 3, n - 90), "libengine.so.1": bytes(40_000, 4), "core.hbc": bytes(20_000, 5, n - 90),
  VERSION: Buffer.from(`0.1.${n}\n`), "install.sh": Buffer.from("#!/bin/sh\n"), "icon.png": bytes(5_000, 6),
});
/** What install.sh puts in the app's folder: no install.sh nor icon, the link copied as its file. */
const linuxInstalled = (n: number) => {
  const { "install.sh": _i, "icon.png": _p, ...rest } = linuxFiles(n);
  return { ...rest, "libengine.so": rest["libengine.so.1"] };
};

const WIN = (n: number) => `desktop/stillfail-beta-0.1.${n}-x64-win.exe`;
const winStub = bytes(8_000, 7);
const winEntries = (n: number) => [
  { name: "setup.env", data: Buffer.from(`APP_NAME=still.fail beta\r\nAPP_ID=fail.still.desktop.beta\r\nVERSION=0.1.${n}\r\n`) },
  { name: "youdid.wtf.exe", data: bytes(50_000, 8, n - 90) },
  { name: "core.hbc", data: bytes(30_000, 9, n - 90) },
];
const winRaw = (n: number) => rawInstaller(winStub, winEntries(n));
/** The installer itself: packed (LZMS on Windows; here only bytes of its own, never read). */
const winExe = (n: number) => Buffer.concat([winStub, bytes(30_000, 100 + n)]);
const winFeed = (n: number) => {
  const exe = winExe(n), raw = winRaw(n);
  return { versionCode: n, versionName: `0.1.${n}`, ...file(WIN(n), exe), signed: signed({ kind: "stillfail-desktop-win", version: `0.1.${n}`, build: n, file: WIN(n).split("/")[1], sha256: sha(exe), size: exe.length, raw: { sha256: sha(raw), size: raw.length } }) };
};

const APK = (n: number) => `android/stillfail-beta-${n}.apk`;
const apkZip = (n: number) => zip([
  { name: "AndroidManifest.xml", data: bytes(4_000, 10, n - 90), deflate: true },
  { name: "classes.dex", data: bytes(60_000, 11, n - 90), deflate: true },
  { name: "resources.arsc", data: bytes(20_000, 12) },
  { name: "lib/arm64-v8a/libapp.so", data: bytes(50_000, 13, n - 90), deflate: true },
]);

const stationFiles = (n: number) => ({
  BUILD: Buffer.from(`${n}\n`), "station/main.js": bytes(70_000, 14, n - 90), "bin/install.sh": Buffer.from("#!/bin/sh\n"),
});
const STATION = { linux: "beta/stillfail-station-linux-x64.tar.gz", win: "beta/stillfail-station-win32-x64.zip" };

let javaClasses: string | undefined;
function java(args: string[]) {
  if (!javaClasses) {
    javaClasses = mkdtempSync(join(tmpdir(), "release-deltas-java-"));
    process.on("exit", () => rmSync(javaClasses!, { recursive: true, force: true }));
    const jz = join(root, "libs/mbui/android/jzlib/src/com/jcraft/jzlib");
    const srcs = [join(root, "libs/mbui/android/app/src/main/java/dev/mbui/Delta.java"), ...readdirSync(jz).filter((f) => f.endsWith(".java")).map((f) => join(jz, f))];
    execFileSync("javac", ["-nowarn", "-encoding", "UTF-8", "-d", javaClasses, ...srcs], { stdio: "pipe" });
  }
  const r = spawnSync("java", ["-Xmx256m", "-cp", javaClasses, "dev.mbui.Delta", ...args], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
}

/** The station's archives of build n (tar.gz and zip, stillfail/ in each) and its feed, signed. */
function station(dir: string, n: number, names: { linux: string; win: string } = STATION) {
  tgz(stationFiles(n), "stillfail", join(dir, names.linux));
  put(dir, names.win, zip(Object.entries(stationFiles(n)).map(([name, data]) => ({ name: `stillfail/${name}`, data, deflate: true }))));
  const tar = readFileSync(join(dir, names.linux)), z = readFileSync(join(dir, names.win));
  const build = (b: Buffer, raw: Buffer) => ({ sha256: sha(b), size: b.length, nodeSha256: "b".repeat(64), rawSha256: sha(raw), rawSize: raw.length });
  const words = { kind: "stillfail-station-release", version: `0.1.${n}`, build: n, commit: "0".repeat(40), node: "24.21.0",
    builds: { "linux-x64": build(tar, gunzipSync(tar)), "win32-x64": build(z, storedZip(z)) } };
  return { version: `0.1.${n}`, build: n, commit: "0".repeat(40), ...signed(words), words };
}

/** Every feed, build 101 in `rel`, build 100 (and 99, which 100's deltas are from) published in `pub`. */
function world(t: { after(f: () => void): void }, o: { android?: boolean } = {}) {
  const tmp = mkdtempSync(join(tmpdir(), "release-deltas-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const pub = join(tmp, "pub"), rel = join(tmp, "rel");
  // Mac: 100 published, its feed offering a delta from 99 (so 99 is a base too)
  for (const n of [99, 100]) put(pub, MAC(n), macZip(n));
  put(pub, "mac/beta/latest.json", { versionCode: 100, versionName: "0.1.100", ...file(MAC(100), macZip(100)), deltas: [{ from: 99, file: `${MAC(100)}.from-99.delta`, sha256: "c".repeat(64), size: 10 }] });
  put(rel, MAC(101), macZip(101));
  put(rel, "mac/beta/latest.json", { versionCode: 101, versionName: "0.1.101", ...file(MAC(101), macZip(101)) });
  // Linux (preview's feed), its library a link
  tgz({ ...linuxFiles(100), "libengine.so": { link: "libengine.so.1" } }, "still.fail-mbui", join(pub, LINUX(100)));
  put(pub, "linux/mbui/latest.json", { versionCode: 100, versionName: "0.1.100", ...file(LINUX(100), readFileSync(join(pub, LINUX(100)))) });
  tgz({ ...linuxFiles(101), "libengine.so": { link: "libengine.so.1" } }, "still.fail-mbui", join(rel, LINUX(101)));
  put(rel, "linux/mbui/latest.json", { versionCode: 101, versionName: "0.1.101", ...file(LINUX(101), readFileSync(join(rel, LINUX(101)))) });
  // Windows: the installer and its raw form beside it
  put(pub, `${WIN(100)}.raw.zst`, zstdCompressSync(winRaw(100)));
  put(pub, WIN(100), winExe(100));
  put(pub, "win/beta/latest.json", winFeed(100));
  put(rel, WIN(101), winExe(101));
  put(rel, `${WIN(101)}.raw.zst`, zstdCompressSync(winRaw(101)));
  put(rel, "win/beta/latest.json", winFeed(101));
  // Android, repacked by the app's own code (tools/apk), as releases are
  if (o.android) {
    for (const [dir, n] of [[pub, 100], [rel, 101]] as const) {
      put(tmp, `${n}.apk`, apkZip(n));
      java(["repack", join(tmp, `${n}.apk`), join(tmp, `${n}.re.apk`)]);
      put(dir, APK(n), readFileSync(join(tmp, `${n}.re.apk`)));
      put(dir, "android/beta/latest.json", { versionCode: n, versionName: `0.1.${n}`, ...file(APK(n), readFileSync(join(dir, APK(n)))) });
    }
  }
  // the station: 100's Linux archive still under the name it was put (before this release's is put over it), its
  // Windows one only under its own
  const before = station(pub, 100);
  const own = `station/archive/beta/100-${before.words.builds["win32-x64"].sha256}-win32-x64.zip`;
  put(pub, own, readFileSync(join(pub, STATION.win)));
  rmSync(join(pub, STATION.win));
  const { words: _w, ...prevFeed } = before;
  put(pub, "station-beta.json", prevFeed);
  const now = station(rel, 101);
  const { words, ...feed } = now;
  put(rel, "station-beta.json", feed);
  return { tmp, pub, rel, stationWords: words, prevStationWords: before.words };
}

const run = (rel: string, pub: string, ...more: string[]) => {
  const r = spawnSync(process.execPath, [script, rel, "--releases", pub, ...more], { encoding: "utf8", env: { ...process.env, GITHUB_ACTIONS: "", GITHUB_STEP_SUMMARY: "" } });
  assert.equal(r.status, 0, r.stderr);
  return { out: r.stdout, err: r.stderr };
};
const json = (dir: string, name: string) => JSON.parse(readFileSync(join(dir, name), "utf8"));
/** Every file of a directory, by name, with its bytes. */
const snapshot = (dir: string) => {
  const out: Record<string, string> = {};
  const walk = (rel: string) => {
    for (const e of readdirSync(join(dir, rel), { withFileTypes: true })) {
      const p = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) walk(p);
      else out[p] = sha(readFileSync(join(dir, p)));
    }
  };
  walk("");
  return out;
};
/** A tree of files in a new folder: what an installed build has. */
const tree = (tmp: string, files: Record<string, Buffer>) => {
  const dir = mkdtempSync(join(tmp, "installed-"));
  for (const [name, data] of Object.entries(files)) { mkdirSync(dirname(join(dir, name)), { recursive: true }); writeFileSync(join(dir, name), data); }
  return dir;
};
const applied = (tmp: string, files: Record<string, Buffer>, delta: string) => {
  const out = join(tmp, `made-${Math.random().toString(36).slice(2)}`);
  applyFile({ dir: tree(tmp, files) }, delta, out);
  return readFileSync(out);
};
const strip = (files: Record<string, Buffer>, prefix: string) => Object.fromEntries(Object.entries(files).map(([k, v]) => [k.slice(prefix.length), v]));

test("every feed's deltas: made from what an installed build has, giving the raw package, the feeds amended", { skip: noJava }, (t) => {
  const w = world(t, { android: true });
  const { out } = run(w.rel, w.pub);

  // Mac: from 100 and from 99 (100's feed's own), newest first; `raw` the zip stored
  const mac = json(w.rel, "mac/beta/latest.json");
  assert.deepEqual(mac.deltas.map((d: { from: number }) => d.from), [100, 99]);
  const stored = storedZip(macZip(101));
  assert.deepEqual(mac.raw, { sha256: sha(stored), size: stored.length });
  for (const d of mac.deltas) {
    assert.equal(d.file, `${MAC(101)}.from-${d.from}.delta`);
    const delta = readFileSync(join(w.rel, d.file));
    assert.deepEqual([d.sha256, d.size], [sha(delta), delta.length]);
    assert.ok(d.size < 0.8 * mac.size);
    // (the .app's regular files from the .app, not the symlink)
    assert.ok(applied(w.tmp, strip(macFiles(d.from), "Test.app/"), join(w.rel, d.file)).equals(stored), `mac from ${d.from}`);
  }
  assert.match(out, /mac\/beta 101: from 100 [0-9.]+ MB, from 99 [0-9.]+ MB; package [0-9.]+ MB/);

  // Linux: what install.sh copies, the link as its file, gives the tar
  const linux = json(w.rel, "linux/mbui/latest.json");
  assert.equal(linux.deltas.length, 1);
  const tar = gunzipSync(readFileSync(join(w.rel, LINUX(101))));
  assert.deepEqual(linux.raw, { sha256: sha(tar), size: tar.length });
  assert.ok(applied(w.tmp, linuxInstalled(100), join(w.rel, linux.deltas[0].file)).equals(tar));

  // Windows: the installer's files and its uninstaller (its program alone) give the raw installer its words say
  const win = json(w.rel, "win/beta/latest.json");
  assert.deepEqual(win.deltas.map((d: { file: string }) => d.file), [`${WIN(101)}.from-100.delta`]);
  assert.deepEqual(win.raw, { sha256: sha(winRaw(101)), size: winRaw(101).length });
  assert.deepEqual(win.signed, winFeed(101).signed, "the signed words as they were");
  const installedWin = { ...Object.fromEntries(winEntries(100).map((f) => [f.name, f.data])), "Uninstall still.fail beta.exe": winStub };
  assert.ok(applied(w.tmp, installedWin, join(w.rel, win.deltas[0].file)).equals(winRaw(101)));

  // Android: the Java applier makes the APK itself of the old one; no `raw`
  const apk = json(w.rel, "android/beta/latest.json");
  assert.equal(apk.raw, undefined);
  assert.equal(apk.deltas.length, 1);
  java(["apply", join(w.pub, APK(100)), join(w.rel, apk.deltas[0].file), join(w.tmp, "made.apk")]);
  assert.ok(readFileSync(join(w.tmp, "made.apk")).equals(readFileSync(join(w.rel, APK(101)))));

  // The station: each platform's delta from 100 (found under the name it was put, and under its own), saying its
  // base; the signed words as they were; this release's archives kept under their own names
  const st = json(w.rel, "station-beta.json");
  assert.deepEqual(JSON.parse(Buffer.from(st.release, "base64").toString("utf8")), w.stationWords, "the signed words untouched");
  for (const [platform, raw, own] of [
    ["linux-x64", gunzipSync(readFileSync(join(w.rel, STATION.linux))), STATION.linux],
    ["win32-x64", storedZip(readFileSync(join(w.rel, STATION.win))), STATION.win],
  ] as const) {
    const b = w.stationWords.builds[platform];
    const [d, ...more] = st.deltas[platform];
    assert.equal(more.length, 0);
    assert.equal(d.from, 100);
    assert.equal(d.base, w.prevStationWords.builds[platform].sha256);
    assert.match(d.file, new RegExp(`^station/archive/beta/101-${b.sha256}-${platform}\\.from-100-${d.base.slice(0, 16)}\\.delta$`));
    assert.ok(applied(w.tmp, stationFiles(100), join(w.rel, d.file)).equals(raw), platform);
    const copy = `station/archive/beta/101-${b.sha256}-${platform}${own.endsWith(".zip") ? ".zip" : ".tar.gz"}`;
    assert.ok(readFileSync(join(w.rel, copy)).equals(readFileSync(join(w.rel, own))), `${copy}: this release's archive under its own name`);
  }
  assert.match(out, /station-beta linux-x64 101: from 100 [0-9.]+ MB; package/);
});

test("run again, nothing changes; one pair at a time, the same is made", (t) => {
  const w = world(t);
  const again = join(w.tmp, "again");
  cpSync(w.rel, again, { recursive: true });
  run(w.rel, w.pub);
  const first = snapshot(w.rel);
  assert.ok(Object.keys(first).some((f) => f.endsWith(".delta")));
  run(w.rel, w.pub);
  assert.deepEqual(snapshot(w.rel), first, "a second run changes nothing");
  run(again, w.pub, "--jobs", "1");
  assert.deepEqual(snapshot(again), first, "the same at --jobs 1");
});

test("by default the 10 newest bases: the published build and 9 of the builds its deltas are from", (t) => {
  const tmp = mkdtempSync(join(tmpdir(), "release-deltas-test-"));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const pub = join(tmp, "pub"), rel = join(tmp, "rel");
  for (let n = 89; n <= 100; n++) put(pub, MAC(n), macZip(n));
  const froms = Array.from({ length: 11 }, (_, i) => 99 - i);
  put(pub, "mac/beta/latest.json", { versionCode: 100, versionName: "0.1.100", ...file(MAC(100), macZip(100)), deltas: froms.map((from) => ({ from, file: `${MAC(100)}.from-${from}.delta`, sha256: "c".repeat(64), size: 10 })) });
  put(rel, MAC(101), macZip(101));
  put(rel, "mac/beta/latest.json", { versionCode: 101, versionName: "0.1.101", ...file(MAC(101), macZip(101)) });
  run(rel, pub);
  const mac = json(rel, "mac/beta/latest.json");
  assert.deepEqual(mac.deltas.map((d: { from: number }) => d.from), [100, 99, 98, 97, 96, 95, 94, 93, 92, 91]);
  const stored = storedZip(macZip(101));
  for (const d of mac.deltas) assert.ok(applied(tmp, strip(macFiles(d.from), "Test.app/"), join(rel, d.file)).equals(stored), `mac from ${d.from}`);
});

test("--into: the deltas and the amended feeds there, the release directory as it was", (t) => {
  const w = world(t);
  const into = join(w.tmp, "into");
  const before = snapshot(w.rel);
  run(w.rel, w.pub, "--into", into);
  assert.deepEqual(snapshot(w.rel), before);
  const made = Object.keys(snapshot(into));
  assert.ok(made.includes("mac/beta/latest.json") && made.includes("station-beta.json"));
  assert.ok(made.includes(`${MAC(101)}.from-100.delta`));
  assert.ok(!made.includes(MAC(101)), "not the packages");
});

test("no feed published before: no deltas, the feeds as they were, and said so", (t) => {
  const w = world(t);
  rmSync(w.pub, { recursive: true });
  mkdirSync(w.pub);
  const before = snapshot(w.rel);
  const { out } = run(w.rel, w.pub);
  // (only this station release's archives, under their own names, for the releases after it)
  const after = snapshot(w.rel);
  for (const name of Object.keys(after)) if (!(name in before)) assert.match(name, /^station\/archive\/beta\/101-/);
  for (const [name, h] of Object.entries(before)) assert.equal(after[name], h, name);
  assert.match(out, /mac\/beta 101: no deltas \(no feed published at /);
});

test("a base not there, a delta too big, a delta that fails: each left out, the feed whole without it", (t) => {
  const w = world(t);
  // Mac: 99 pruned (100's feed still says a delta from it)
  rmSync(join(w.pub, MAC(99)));
  // Linux: 101 is nothing like 100
  tgz({ stillfail: bytes(200_000, 77), VERSION: Buffer.from("0.1.101\n") }, "still.fail-mbui", join(w.rel, LINUX(101)));
  put(w.rel, "linux/mbui/latest.json", { versionCode: 101, versionName: "0.1.101", ...file(LINUX(101), readFileSync(join(w.rel, LINUX(101)))) });
  // Windows: 100's raw form is not one (its words say no raw either: nothing to check it by)
  put(w.pub, `${WIN(100)}.raw.zst`, zstdCompressSync(Buffer.from("not an installer")));
  const prev = winFeed(100);
  put(w.pub, "win/beta/latest.json", { ...prev, signed: signed({ kind: "stillfail-desktop-win", version: "0.1.100", build: 100, file: WIN(100).split("/")[1], sha256: prev.sha256, size: prev.size }) });
  const { out, err } = run(w.rel, w.pub);
  const mac = json(w.rel, "mac/beta/latest.json");
  assert.deepEqual(mac.deltas.map((d: { from: number }) => d.from), [100]);
  assert.match(out, /mac\/beta 101: from 100 [0-9.]+ MB, from 99 not there;/);
  const linux = json(w.rel, "linux/mbui/latest.json");
  assert.equal(linux.deltas, undefined);
  assert.equal(linux.raw, undefined);
  assert.match(out, /linux\/mbui 101: from 100 not kept \([0-9.]+ MB, 80% of the package or more\)/);
  const win = json(w.rel, "win/beta/latest.json");
  assert.deepEqual(win, winFeed(101), "the feed as it was: valid without its deltas");
  assert.match(out, /win\/beta 101: from 100 failed;/);
  assert.match(err, /win\/beta from 100: no delta: /);
  for (const f of Object.keys(snapshot(w.rel))) assert.doesNotMatch(f, /x64-(linux\.tar\.gz|win\.exe)\.from-/, "nothing left of what was not kept");
});

test("a station's base pruned, a package not the one its feed names: those left out, the rest made", (t) => {
  const w = world(t);
  rmSync(join(w.pub, "station/archive"), { recursive: true });
  const { out } = run(w.rel, w.pub);
  const st = json(w.rel, "station-beta.json");
  assert.equal(st.deltas["win32-x64"], undefined, "100's Windows archive is nowhere");
  assert.equal(st.deltas["linux-x64"].length, 1);
  assert.match(out, /station-beta win32-x64 101: from 100 not there/);
  // a package not the one its feed names: that feed left as it was, the others made
  const w2 = world(t);
  put(w2.rel, MAC(101), macZip(102));
  const r = run(w2.rel, w2.pub);
  assert.equal(json(w2.rel, "mac/beta/latest.json").deltas, undefined);
  assert.match(r.err, /mac\/beta\/latest\.json: no deltas: .*not the one its feed names/);
  assert.ok(json(w2.rel, "linux/mbui/latest.json").deltas);
  assert.ok(existsSync(join(w2.rel, "station-beta.json")) && statSync(join(w2.rel, "station-beta.json")).size > 0);
});
