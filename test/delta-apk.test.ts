import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { crc32, deflateRawSync, inflateRawSync } from "node:zlib";
import { entriesInBlob, makeApk, parseHeader, readOld, wholeFiles, zipEntries } from "../scripts/delta.ts";

// An Android update's delta is made into the released APK by the app's own applier (dev.mbui.Delta, Java, its deflater
// JZlib), the release's APK repacked first by the same code (tools/apk). Here: the Java applier makes the new APK byte
// for byte from what scripts/delta.ts made, refuses what is not its delta, and repack keeps every entry's contents.
// With DELTA_APK_OLD and DELTA_APK_NEW (two released APKs), the same on them, with what it took said.
const root = fileURLToPath(new URL("..", import.meta.url));
const deltaJava = join(root, "libs/mbui/android/app/src/main/java/dev/mbui/Delta.java");
const jzlib = join(root, "libs/mbui/android/jzlib/src/com/jcraft/jzlib");
const has = (cmd: string) => spawnSync(cmd, ["-version"], { encoding: "utf8" }).status === 0;
const skip = has("javac") && has("java") ? false : "no javac or java here: the Java applier is not tested";

let compiled: string | undefined;
/** Delta.java and JZlib compiled once, for this JVM (as tools/apk compiles them). */
function classes(): string {
  if (compiled) return compiled;
  const dir = mkdtempSync(join(tmpdir(), "delta-apk-classes-"));
  process.on("exit", () => rmSync(dir, { recursive: true, force: true }));
  const srcs = [deltaJava, ...readdirSync(jzlib).filter((f) => f.endsWith(".java")).map((f) => join(jzlib, f))];
  const r = spawnSync("javac", ["-nowarn", "-encoding", "UTF-8", "-d", dir, ...srcs], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  return (compiled = dir);
}

const java = (args: string[], heap = "-Xmx256m") =>
  spawnSync("java", [heap, "-cp", classes(), "dev.mbui.Delta", ...args], { encoding: "utf8", maxBuffer: 1 << 26 });

function prng(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
/** Bytes like a program's: words from a small vocabulary, so that a change leaves most of it alike. */
const texty = (rand: () => number, n: number) => {
  const words = Array.from({ length: 96 }, () => Buffer.from(Array.from({ length: 2 + Math.floor(rand() * 10) }, () => Math.floor(rand() * 256))));
  const out: Buffer[] = [];
  for (let size = 0; size < n;) { const w = words[Math.floor(rand() * words.length)]!; out.push(w); size += w.length; }
  return Buffer.concat(out).subarray(0, n);
};

type Entry = { name: string; data: Buffer; deflate: boolean; descriptor?: boolean; extra?: Buffer; comment?: string };
/** A zip as zip(1) makes one (node's deflater, not JZlib): local headers, data descriptors where asked, the directory. */
function zip(entries: Entry[], comment = ""): Buffer {
  const parts: Buffer[] = [], central: Buffer[] = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name), extra = e.extra ?? Buffer.alloc(0), note = Buffer.from(e.comment ?? "");
    const body = e.deflate ? deflateRawSync(e.data, { level: 9 }) : e.data, crc = crc32(e.data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(e.descriptor ? 8 : 0, 6);
    local.writeUInt16LE(e.deflate ? 8 : 0, 8);
    local.writeUInt32LE(0x5a2c4e21, 10);
    if (!e.descriptor) {
      local.writeUInt32LE(crc, 14);
      local.writeUInt32LE(body.length, 18);
      local.writeUInt32LE(e.data.length, 22);
    }
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(extra.length, 28);
    const dd = Buffer.alloc(e.descriptor ? 16 : 0);
    if (e.descriptor) { dd.writeUInt32LE(0x08074b50, 0); dd.writeUInt32LE(crc, 4); dd.writeUInt32LE(body.length, 8); dd.writeUInt32LE(e.data.length, 12); }
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0);
    c.writeUInt16LE(0x031e, 4);
    c.writeUInt16LE(20, 6);
    c.writeUInt16LE(e.descriptor ? 8 : 0, 8);
    c.writeUInt16LE(e.deflate ? 8 : 0, 10);
    c.writeUInt32LE(0x5a2c4e21, 12);
    c.writeUInt32LE(crc, 16);
    c.writeUInt32LE(body.length, 20);
    c.writeUInt32LE(e.data.length, 24);
    c.writeUInt16LE(name.length, 28);
    c.writeUInt16LE(extra.length, 30);
    c.writeUInt16LE(note.length, 32);
    c.writeUInt32LE((0o100644 << 16) >>> 0, 38);
    c.writeUInt32LE(offset, 42);
    parts.push(local, name, extra, body, dd);
    central.push(c, name, extra, note);
    offset += 30 + name.length + extra.length + body.length + dd.length;
  }
  const cd = Buffer.concat(central), note = Buffer.from(comment), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  end.writeUInt16LE(note.length, 20);
  return Buffer.concat([...parts, cd, end, note]);
}

/** A zip's entries as its central directory says, with their inflated contents. */
function contents(z: Buffer) {
  let e = z.length - 22;
  while (z.readUInt32LE(e) !== 0x06054b50) e--;
  const out: { name: string; method: number; crc: number; data: Buffer; extra: string; comment: string; attrs: number; time: number }[] = [];
  for (let p = z.readUInt32LE(e + 16), i = 0; i < z.readUInt16LE(e + 10); i++) {
    const n = z.readUInt16LE(p + 28), x = z.readUInt16LE(p + 30), k = z.readUInt16LE(p + 32), local = z.readUInt32LE(p + 42);
    const method = z.readUInt16LE(p + 10), packed = z.readUInt32LE(p + 20);
    const at = local + 30 + z.readUInt16LE(local + 26) + z.readUInt16LE(local + 28), body = z.subarray(at, at + packed);
    out.push({
      name: z.toString("utf8", p + 46, p + 46 + n), method, crc: z.readUInt32LE(p + 16),
      data: method === 8 ? inflateRawSync(body) : Buffer.from(body),
      extra: z.toString("hex", p + 46 + n, p + 46 + n + x), comment: z.toString("utf8", p + 46 + n + x, p + 46 + n + x + k),
      attrs: z.readUInt32LE(p + 38), time: z.readUInt32LE(p + 12),
    });
    p += 46 + n + x + k;
  }
  return out;
}

function pair() {
  const rand = prng(8147);
  const big = texty(rand, 2_300_000), bigNew = Buffer.from(big);
  // (a few edits through it, and a stretch put in: what a new build of a library looks like to bsdiff)
  for (let i = 0; i < 40; i++) bigNew[Math.floor(rand() * bigNew.length)] = Math.floor(rand() * 256);
  const grown = Buffer.concat([bigNew.subarray(0, 1_000_000), texty(rand, 30_000), bigNew.subarray(1_000_000)]);
  const kept = texty(rand, 200_000), manifest = texty(rand, 3000);
  const old: Entry[] = [
    { name: "AndroidManifest.xml", data: manifest, deflate: true, extra: Buffer.from("cafe0200beef", "hex") },
    { name: "classes.dex", data: texty(rand, 50_000), deflate: false },
    { name: "assets/kept.bin", data: kept, deflate: true, comment: "kept as it is" },
    { name: "lib/arm64-v8a/libapp.so", data: big, deflate: true, descriptor: true },
    { name: "assets/gone.txt", data: texty(rand, 9000), deflate: true },
    { name: "META-INF/empty", data: Buffer.alloc(0), deflate: true },
  ];
  const neu: Entry[] = [
    { name: "AndroidManifest.xml", data: manifest, deflate: true, extra: Buffer.from("cafe0200beef", "hex") },
    { name: "classes.dex", data: texty(rand, 52_000), deflate: false },
    { name: "assets/kept.bin", data: kept, deflate: true, comment: "kept as it is" },
    { name: "lib/arm64-v8a/libapp.so", data: grown, deflate: true, descriptor: true },
    { name: "assets/new.txt", data: texty(rand, 12_000), deflate: true },
    { name: "META-INF/empty", data: Buffer.alloc(0), deflate: true },
  ];
  return { old: zip(old, "the old build"), neu: zip(neu, "the new build") };
}

test("an APK's delta is made into the repacked new APK byte for byte by the Java applier, and refused when it is not its delta", { skip }, (t) => {
  const dir = mkdtempSync(join(tmpdir(), "delta-apk-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const { old, neu } = pair();
  const f = (name: string) => join(dir, name);
  writeFileSync(f("old.apk"), old);
  writeFileSync(f("new.apk"), neu);
  for (const n of ["old", "new"]) {
    const r = java(["repack", f(`${n}.apk`), f(`${n}.re.apk`)]);
    assert.equal(r.status, 0, r.stderr);
  }
  // repack: every entry as it was (contents, names, order, extra fields, comments, times, attributes), and done again
  // it changes nothing
  for (const n of ["old", "new"]) {
    const a = readFileSync(f(`${n}.apk`)), b = readFileSync(f(`${n}.re.apk`));
    assert.deepEqual(contents(b), contents(a));
    assert.equal(b.subarray(b.length - 13).toString(), n === "old" ? "the old build" : "the new build");
    const r = java(["repack", f(`${n}.re.apk`), f(`${n}.rere.apk`)]);
    assert.equal(r.status, 0, r.stderr);
    assert.ok(readFileSync(f(`${n}.rere.apk`)).equals(b), "repack is idempotent");
  }
  const unzip = spawnSync("unzip", ["-tq", f("new.re.apk")], { encoding: "utf8" });
  if (unzip.error === undefined) assert.equal(unzip.status, 0, unzip.stdout + unzip.stderr);

  const made = spawnSync(process.execPath, [join(root, "scripts/delta.ts"), "make", "--old-apk", f("old.re.apk"), "--new", f("new.re.apk"),
    "--out", f("d.delta"), "--deflate-check", "none"], { encoding: "utf8" });
  assert.equal(made.status, 0, made.stderr);
  const info = JSON.parse(spawnSync(process.execPath, [join(root, "scripts/delta.ts"), "info", f("d.delta")], { encoding: "utf8" }).stdout);
  assert.equal(info.inflate.length, 1, "the changed library is inflated in place");
  assert.equal(info.deflate.length, 1);
  assert.ok(info.made_size > 2 * 1024 * 1024, "several chunks");
  const applied = java(["apply", f("old.re.apk"), f("d.delta"), f("out.apk")]);
  assert.equal(applied.status, 0, applied.stderr);
  assert.ok(readFileSync(f("out.apk")).equals(readFileSync(f("new.re.apk"))), "the new APK, byte for byte");
  t.diagnostic(`delta ${readFileSync(f("d.delta")).length} bytes for a ${neu.length}-byte APK`);

  const delta = readFileSync(f("d.delta"));
  const refused = (name: string, d: Buffer | null, oldApk: string, why: RegExp) => {
    const path = f(`${name}.delta`);
    if (d) writeFileSync(path, d);
    const r = java(["apply", oldApk, d ? path : f("d.delta"), f(`${name}.apk`)]);
    assert.notEqual(r.status, 0, `${name}: refused`);
    assert.match(r.stderr, why, name);
    assert.equal(existsSync(f(`${name}.apk`)), false, `${name}: nothing made`);
  };
  const badMagic = Buffer.from(delta);
  badMagic[3] = badMagic[3]! ^ 1;
  refused("magic", badMagic, f("old.re.apk"), /bad magic/);
  const badSha = Buffer.from(delta);
  // (the old blob's sha256: after the magic, n_files, n_inflate, its one range and old_size, 8 + 4 + 4 + 16 + 8)
  badSha[40] = badSha[40]! ^ 1;
  refused("sha", badSha, f("old.re.apk"), /sha256/);
  refused("cut", delta.subarray(0, delta.length - 20), f("old.re.apk"), /end chunk|cut short|ends early/);
  refused("after", Buffer.concat([delta, Buffer.from([0])]), f("old.re.apk"), /after its end chunk/);
  // (the old APK as zip(1) left it, not repacked: not what the delta was made from)
  refused("wrong-old", null, f("old.apk"), /not the APK it was made for|not the one the delta was made from|past the old APK/);
  refused("other-old", null, f("new.re.apk"), /not the APK it was made for|not the one the delta was made from|past the old APK/);
  assert.deepEqual(readdirSync(dir).filter((n) => n.startsWith("delta-old")), [], "the old blob's temporary file is gone");
});

test("repack refuses a zip64 zip and what is not a zip, leaving nothing", { skip }, (t) => {
  const dir = mkdtempSync(join(tmpdir(), "delta-apk-zip-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, "not.zip"), "not a zip at all, only words, and more of them than an end record needs");
  const z = zip([{ name: "a", data: Buffer.from("aaaa"), deflate: true }]);
  z.writeUInt16LE(0xffff, z.length - 22 + 10);
  z.writeUInt16LE(0xffff, z.length - 22 + 8);
  writeFileSync(join(dir, "z64.zip"), z);
  for (const [name, why] of [["not.zip", /not a zip/], ["z64.zip", /zip64/]] as const) {
    const r = java(["repack", join(dir, name), join(dir, "out.zip")]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, why);
    assert.equal(existsSync(join(dir, "out.zip")), false);
  }
});

test("an APK with most of its entries kept: those found whole in the old blob, its delta made back by the Java applier", { skip }, (t) => {
  const dir = mkdtempSync(join(tmpdir(), "delta-apk-kept-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const f = (name: string) => join(dir, name);
  const rand = prng(31);
  const entries: Entry[] = [100, 3000, 20_000, 80_000, 150_000, 40_000, 9000, 120_000].map((n, i) => ({ name: `assets/${i}.bin`, data: texty(rand, n), deflate: i % 3 !== 1 }));
  const changed = (e: Entry) => { const data = Buffer.from(e.data); data.write("build 8147", data.length >> 1); return { ...e, data }; };
  // (5 deflated and changed: inflated in place; 7 stored and changed; 2 gone; one new)
  const neu = entries.map((e, i) => (i === 5 || i === 7 ? changed(e) : e)).filter((_, i) => i !== 2);
  neu.push({ name: "assets/new.bin", data: texty(rand, 30_000), deflate: true });
  writeFileSync(f("old.apk"), zip(entries));
  writeFileSync(f("new.apk"), zip(neu));
  for (const n of ["old", "new"]) {
    const r = java(["repack", f(`${n}.apk`), f(`${n}.re.apk`)]);
    assert.equal(r.status, 0, r.stderr);
  }
  assert.equal(makeApk(f("old.re.apk"), f("new.re.apk"), f("d.delta"), "none"), 1);
  const applied = java(["apply", f("old.re.apk"), f("d.delta"), f("out.apk")]);
  assert.equal(applied.status, 0, applied.stderr);
  assert.ok(readFileSync(f("out.apk")).equals(readFileSync(f("new.re.apk"))), "the new APK, byte for byte");
  // each entry's data where it is in the old blob: the inflated one inflated, the others as they are in the APK
  const oldZip = readFileSync(f("old.re.apk")), d = readFileSync(f("d.delta")), h = parseHeader(d), blob = readOld(h, { apk: f("old.re.apk") });
  const ranges = entriesInBlob(oldZip, h.inflate), list = zipEntries(oldZip);
  assert.equal(ranges.length, list.length);
  list.forEach((e, i) => {
    const body = oldZip.subarray(e.at, e.at + e.packed), r = ranges[i]!;
    const want = h.inflate.some((x) => x.at === e.at) ? inflateRawSync(body) : body;
    assert.ok(blob.subarray(r.at, r.at + r.len).equals(want), e.name);
  });
  const found = wholeFiles(blob, ranges, readFileSync(f("new.re.apk"))).reduce((n, r) => n + r.len, 0);
  assert.ok(found > blob.length / 8, `${found} of ${blob.length} bytes found whole`);
  t.diagnostic(`delta ${d.length} bytes, ${found} of the old blob's ${blob.length} found whole`);
});

// Two released APKs (DELTA_APK_OLD, DELTA_APK_NEW): repacked, their delta made, applied by Java in 256 MB of heap.
const realOld = process.env.DELTA_APK_OLD, realNew = process.env.DELTA_APK_NEW;
test("two released APKs, repacked: the delta between them made back into the new one by Java in 256 MB",
  { skip: skip || (!realOld || !realNew ? "DELTA_APK_OLD and DELTA_APK_NEW not given" : false), timeout: 900_000 }, (t) => {
    const dir = mkdtempSync(join(tmpdir(), "delta-apk-real-"));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const f = (name: string) => join(dir, name);
    for (const [src, n] of [[realOld!, "old"], [realNew!, "new"]] as const) {
      const r = java(["repack", src, f(`${n}.apk`)]);
      assert.equal(r.status, 0, r.stderr);
    }
    let at = Date.now();
    const made = spawnSync(process.execPath, ["--max-old-space-size=6144", join(root, "scripts/delta.ts"), "make", "--old-apk", f("old.apk"),
      "--new", f("new.apk"), "--out", f("d.delta"), "--deflate-check", "none"], { encoding: "utf8" });
    assert.equal(made.status, 0, made.stderr);
    const making = Date.now() - at;
    at = Date.now();
    const applied = java(["apply", f("old.apk"), f("d.delta"), f("out.apk")], "-Xmx256m");
    const applying = Date.now() - at;
    assert.equal(applied.status, 0, applied.stderr);
    assert.ok(readFileSync(f("out.apk")).equals(readFileSync(f("new.apk"))), "the new APK, byte for byte");
    // (bounded by its buffers, not by the APK: it makes the same in a heap of 16 MB)
    const small = java(["apply", f("old.apk"), f("d.delta"), f("out16.apk")], "-Xmx16m");
    assert.equal(small.status, 0, small.stderr);
    assert.ok(readFileSync(f("out16.apk")).equals(readFileSync(f("new.apk"))));
    t.diagnostic(`delta ${readFileSync(f("d.delta")).length} bytes for a ${readFileSync(f("new.apk")).length}-byte APK; made in ${making} ms, ` +
      `applied in ${applying} ms (-Xmx256m; the same in -Xmx16m); ${made.stderr.trim()}`);
  });
