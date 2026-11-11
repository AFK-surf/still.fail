import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { crc32, deflateRawSync, gzipSync, inflateRawSync } from "node:zlib";
import { CHUNK, WINDOW, applyFile, encodeHeader, info, makeApk, makeDelta, makeTree, parseHeader, sparseSuffixArray, storedZip, suffixArray, treeFiles, wholeFiles, zipEntries } from "../scripts/delta.ts";

// Deltas are applied by the apps' own appliers (C, Java) from this format: the reference applier here must refuse
// what they refuse, and every delta made must give back the package byte for byte.
const script = fileURLToPath(new URL("../scripts/delta.ts", import.meta.url));

function prng(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const random = (rand: () => number, n: number) => Buffer.from(Array.from({ length: n }, () => Math.floor(rand() * 256)));
/** Bytes like a program's: words from a small vocabulary, so that a change leaves most of it alike. */
const texty = (rand: () => number, n: number) => {
  const words = Array.from({ length: 64 }, () => random(rand, 2 + Math.floor(rand() * 10)));
  const out: Buffer[] = [];
  for (let size = 0; size < n;) { const w = words[Math.floor(rand() * words.length)]!; out.push(w); size += w.length; }
  return Buffer.concat(out).subarray(0, n);
};

type Entry = { name: string; data: Buffer; deflate: boolean };
/** A zip as a minimal writer makes one: local headers, the central directory, the end record. */
function zip(entries: Entry[]): Buffer {
  const locals: Buffer[] = [], central: Buffer[] = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name), body = e.deflate ? deflateRawSync(e.data, { level: 6 }) : e.data;
    const fields = (h: Buffer, at: number) => {
      h.writeUInt16LE(e.deflate ? 8 : 0, at);
      h.writeUInt32LE(crc32(e.data), at + 6);
      h.writeUInt32LE(body.length, at + 10);
      h.writeUInt32LE(e.data.length, at + 14);
      h.writeUInt16LE(name.length, at + 18);
    };
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    fields(local, 8);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0);
    c.writeUInt16LE(20, 4);
    c.writeUInt16LE(20, 6);
    fields(c, 10);
    c.writeUInt32LE(offset, 42);
    locals.push(local, name, body);
    central.push(c, name);
    offset += 30 + name.length + body.length;
  }
  const cd = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cd, end]);
}

function tree(root: string, files: Record<string, Buffer>) {
  for (const [path, data] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), data);
  }
}

const temp = (t: { after: (f: () => void) => void }) => {
  const dir = mkdtempSync(join(tmpdir(), "delta-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const cli = (...args: string[]) => spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });

/** A small tree and a stored zip of a changed one, with its delta made. */
function treeCase(dir: string) {
  const rand = prng(7);
  const shared = texty(rand, 40_000), big = random(rand, 3 * CHUNK);
  const old = {
    "Contents/MacOS/app": Buffer.concat([texty(rand, 5000), shared]),
    "Contents/Resources/core.hbc": shared.subarray(0, 30_000),
    "Contents/Resources/gone.txt": texty(rand, 2000),
    "Contents/Resources/empty": Buffer.alloc(0),
    "Contents/Resources/big.bin": big,
    "Contents/Info.plist": Buffer.from("<plist>8142</plist>"),
  };
  const changedBig = Buffer.from(big);
  for (const at of [10, CHUNK + 5, 2 * CHUNK + 77]) changedBig[at] = changedBig[at]! ^ 0x55;
  const changedApp = Buffer.from(old["Contents/MacOS/app"]);
  changedApp.write("8147", 4000);
  const neu: Entry[] = [
    { name: "Contents/Info.plist", data: Buffer.from("<plist>8147</plist>"), deflate: false },
    { name: "Contents/MacOS/app", data: Buffer.concat([random(rand, 300), changedApp]), deflate: false },
    { name: "Contents/Resources/big.bin", data: changedBig, deflate: false },
    { name: "Contents/Resources/core.hbc", data: Buffer.concat([shared.subarray(1000, 30_000), random(rand, 500)]), deflate: false },
    { name: "Contents/Resources/empty", data: Buffer.alloc(0), deflate: false },
    { name: "Contents/Resources/new.txt", data: texty(rand, 3000), deflate: false },
  ];
  tree(join(dir, "old"), old);
  symlinkSync("MacOS/app", join(dir, "old/Contents/link"));
  writeFileSync(join(dir, "new.zip"), zip(neu));
  makeTree(join(dir, "old"), join(dir, "new.zip"), join(dir, "d.delta"));
  return { old: join(dir, "old"), delta: join(dir, "d.delta"), neu: readFileSync(join(dir, "new.zip")) };
}

/** A delta with the given header and raw record stream, in chunks of at most `cut` bytes. */
function craft(h: Parameters<typeof encodeHeader>[0], raw: Buffer, cut = CHUNK) {
  const parts = [encodeHeader(h)];
  for (let at = 0; at < raw.length; at += cut) {
    const piece = raw.subarray(at, at + cut), packed = deflateRawSync(piece), head = Buffer.alloc(8);
    head.writeUInt32LE(piece.length, 0);
    head.writeUInt32LE(packed.length, 4);
    parts.push(head, packed);
  }
  return Buffer.concat([...parts, Buffer.alloc(8)]);
}
const record = (x: number, y: number, z: number, ...bytes: Buffer[]) => {
  const b = Buffer.alloc(24);
  b.writeBigInt64LE(BigInt(x), 0);
  b.writeBigInt64LE(BigInt(y), 8);
  b.writeBigInt64LE(BigInt(z), 16);
  return Buffer.concat([b, ...bytes]);
};

test("the suffix array sorts suffixes, long runs of one byte too", () => {
  const rand = prng(1);
  for (const blob of [Buffer.alloc(0), Buffer.from("a"), Buffer.from("banana"), Buffer.alloc(5000),
    Buffer.concat([Buffer.alloc(3000), random(rand, 50), Buffer.alloc(3000, 1), texty(rand, 4000), Buffer.alloc(2000)])]) {
    const I = suffixArray(blob);
    assert.equal(I[0], blob.length);
    assert.deepEqual([...I].sort((a, b) => a - b), Array.from({ length: blob.length + 1 }, (_, i) => i));
    for (let i = 1; i < I.length - 1; i++) assert.ok(Buffer.compare(blob.subarray(I[i]!), blob.subarray(I[i + 1]!)) < 0, `${i} of ${blob.length}`);
  }
});

test("a folder's delta gives the package back, across chunks, through the command too", (t) => {
  const dir = temp(t);
  const c = treeCase(dir);
  assert.deepEqual(treeFiles(c.old), ["Contents/Info.plist", "Contents/MacOS/app", "Contents/Resources/big.bin",
    "Contents/Resources/core.hbc", "Contents/Resources/empty", "Contents/Resources/gone.txt"]);
  const i = info(readFileSync(c.delta));
  assert.deepEqual(i.files, treeFiles(c.old));
  assert.equal(i.made_size, c.neu.length);
  assert.ok(i.chunks >= 3, `${i.chunks} chunks`);
  assert.ok(i.size < 100_000, `${i.size} bytes`);
  const run = cli("apply", "--old", c.old, "--delta", c.delta, "--out", join(dir, "made.zip"));
  assert.equal(run.status, 0, run.stderr);
  assert.ok(readFileSync(join(dir, "made.zip")).equals(c.neu));
  const again = cli("make", "--old", c.old, "--new", join(dir, "new.zip"), "--out", join(dir, "again.delta"));
  assert.equal(again.status, 0, again.stderr);
  assert.ok(readFileSync(join(dir, "again.delta")).equals(readFileSync(c.delta)), "the same inputs make the same delta");
  assert.deepEqual(JSON.parse(cli("info", c.delta).stdout), i);
});

test("a delta from or to nothing", (t) => {
  const dir = temp(t);
  mkdirSync(join(dir, "none"));
  writeFileSync(join(dir, "empty"), "");
  writeFileSync(join(dir, "some"), texty(prng(3), 10_000));
  tree(join(dir, "one"), { a: Buffer.from("hello") });
  for (const [from, to] of [["none", "some"], ["one", "empty"], ["none", "empty"]] as const) {
    makeTree(join(dir, from), join(dir, to), join(dir, "d"));
    applyFile({ dir: join(dir, from) }, join(dir, "d"), join(dir, "out"));
    assert.ok(readFileSync(join(dir, "out")).equals(readFileSync(join(dir, to))), `${from} → ${to}`);
  }
});

test("an apk's delta inflates only the entries whose deflated bytes changed, and deflates them again", (t) => {
  const dir = temp(t);
  const rand = prng(11);
  const js = texty(rand, 60_000), lib = random(rand, 20_000), res = texty(rand, 8000);
  const changedJs = Buffer.concat([js.subarray(0, 30_000), Buffer.from("build 8147"), js.subarray(30_000)]);
  const changedLib = Buffer.from(lib);
  changedLib.write("8147", 100);
  writeFileSync(join(dir, "old.apk"), zip([
    { name: "AndroidManifest.xml", data: texty(rand, 3000), deflate: true },
    { name: "assets/index.android.bundle", data: js, deflate: true },
    { name: "lib/arm64-v8a/libapp.so", data: lib, deflate: false },
    { name: "res/raw/same.txt", data: res, deflate: true },
    { name: "res/raw/gone.txt", data: texty(rand, 5000), deflate: true },
    { name: "res/raw/was-deflated.txt", data: res.subarray(0, 4000), deflate: true },
  ]));
  writeFileSync(join(dir, "new.apk"), zip([
    { name: "AndroidManifest.xml", data: texty(prng(11), 3000), deflate: true },
    { name: "assets/index.android.bundle", data: changedJs, deflate: true },
    { name: "lib/arm64-v8a/libapp.so", data: changedLib, deflate: false },
    { name: "res/raw/new.txt", data: texty(rand, 5000), deflate: true },
    { name: "res/raw/same.txt", data: res, deflate: true },
    { name: "res/raw/was-deflated.txt", data: Buffer.concat([res.subarray(0, 4000), Buffer.from("!")]), deflate: false },
  ]));
  assert.equal(makeApk(join(dir, "old.apk"), join(dir, "new.apk"), join(dir, "d.delta")), 2);
  const i = info(readFileSync(join(dir, "d.delta")));
  assert.equal(i.files.length, 0);
  assert.equal(i.inflate.length, 2);
  assert.deepEqual(i.deflate.map((r) => r.raw_len).sort((a, b) => a - b), [3000, changedJs.length]);
  const run = cli("apply", "--old-apk", join(dir, "old.apk"), "--delta", join(dir, "d.delta"), "--out", join(dir, "made.apk"));
  assert.equal(run.status, 0, run.stderr);
  assert.ok(readFileSync(join(dir, "made.apk")).equals(readFileSync(join(dir, "new.apk"))));
  const none = cli("make", "--old-apk", join(dir, "old.apk"), "--new", join(dir, "new.apk"), "--out", join(dir, "n.delta"), "--deflate-check", "none");
  assert.equal(none.status, 0, none.stderr);
  // A deflater other than the one that made the apk does not make it again: the check refuses, nothing is left.
  const fast = texty(prng(6), 50_000);
  writeFileSync(join(dir, "level6.apk"), zip([{ name: "a.txt", data: texty(prng(5), 50_000), deflate: true }]));
  writeFileSync(join(dir, "level1.apk"), zipWithBody("a.txt", fast, deflateRawSync(fast, { level: 1 })));
  assert.throws(() => makeApk(join(dir, "level6.apk"), join(dir, "level1.apk"), join(dir, "bad.delta")), /does not give the package/);
  assert.equal(existsSync(join(dir, "bad.delta")), false);
});

/** A one-entry zip whose deflated body is given (another deflater's). */
function zipWithBody(name: string, data: Buffer, body: Buffer) {
  const z = zip([{ name, data, deflate: false }]);
  const n = Buffer.from(name).length, cd = z.subarray(30 + n + data.length);
  const local = Buffer.from(z.subarray(0, 30 + n));
  local.writeUInt16LE(8, 8);
  local.writeUInt32LE(body.length, 18);
  const central = Buffer.from(cd);
  central.writeUInt16LE(8, 10);
  central.writeUInt32LE(body.length, 20);
  central.writeUInt32LE(30 + n + body.length, central.length - 6);
  return Buffer.concat([local, body, central]);
}

test("an applier refuses a delta that is not right, before making anything", (t) => {
  const dir = temp(t);
  const c = treeCase(dir);
  const good = readFileSync(c.delta), h = parseHeader(good);
  const refused = (d: Buffer, why: RegExp, old = c.old) => {
    writeFileSync(join(dir, "bad.delta"), d);
    rmSync(join(dir, "out"), { force: true });
    const run = cli("apply", "--old", old, "--delta", join(dir, "bad.delta"), "--out", join(dir, "out"));
    assert.equal(run.status, 1, `${why}: ${run.stderr}`);
    assert.match(run.stderr, why);
    assert.equal(existsSync(join(dir, "out")), false, `${why}: nothing is left`);
  };
  const magic = Buffer.from(good);
  magic[7] = 0x32;
  refused(magic, /bad magic/);
  for (const path of ["/etc/passwd", "a/../b", "..", "a//b", "a/", "a\\b", "C:/x"]) {
    refused(Buffer.concat([encodeHeader({ ...h, files: [path] }), good.subarray(h.payload)]), /a path an applier refuses/);
  }
  // The old blob: a size or a sha256 not the header's.
  tree(join(dir, "shorter"), { a: Buffer.from("abc") });
  refused(Buffer.concat([encodeHeader({ ...h, files: ["a"] }), good.subarray(h.payload)]), /bytes, the delta's old blob/, join(dir, "shorter"));
  refused(Buffer.concat([encodeHeader({ ...h, files: ["a"], oldSize: 3 }), good.subarray(h.payload)]), /sha256/, join(dir, "shorter"));
  refused(good.subarray(0, h.payload! - 5), /cut short/);
  // The stream, against an old blob of "abc".
  const abc = { files: ["a"], inflate: [], oldSize: 3, oldSha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", deflate: [], madeSize: 5 };
  const fine = record(3, 2, 0, Buffer.from([1, 1, 1]), Buffer.from("de"));
  const ok = (d: Buffer) => {
    writeFileSync(join(dir, "ok.delta"), d);
    applyFile({ dir: join(dir, "shorter") }, join(dir, "ok.delta"), join(dir, "out"));
    return readFileSync(join(dir, "out")).toString();
  };
  assert.equal(ok(craft(abc, fine)), "bcdde");
  assert.equal(ok(craft(abc, fine, 7)), "bcdde", "a record spanning chunks");
  assert.equal(ok(craft({ ...abc, madeSize: 6 }, record(6, 0, 0, Buffer.from([0, 0, 0, 0, 0, 7])))), "abc\0\0\x07", "old is zero past its end");
  const old = join(dir, "shorter");
  refused(craft(abc, record(-1, 6, 0, Buffer.from("abcdef"))), /negative/, old);
  refused(craft(abc, record(0, -1, 0)), /negative/, old);
  refused(craft(abc, record(3, 3, 0, Buffer.from([0, 0, 0]), Buffer.from("def"))), /past made_size/, old);
  refused(craft(abc, record(3, 1, 0, Buffer.from([0, 0, 0]), Buffer.from("d"))), /ends early/, old);
  refused(craft(abc, fine.subarray(0, 28)), /ends early/, old);
  refused(craft(abc, Buffer.concat([fine, record(0, 0, 0)])), /past made_size/, old);
  refused(craft(abc, fine).subarray(0, -8), /no end chunk/, old);
  refused(Buffer.concat([craft(abc, fine), Buffer.alloc(1)]), /after its end chunk/, old);
  const huge = craft(abc, fine);
  huge.writeUInt32LE(CHUNK + 1, encodeHeader(abc).length);
  refused(huge, /more than/, old);
  const lying = craft(abc, fine);
  lying.writeUInt32LE(fine.length + 1, encodeHeader(abc).length);
  refused(lying, /raw_len/, old);
  // A folder's delta given an apk, and the other way.
  const apkDelta = craft({ ...abc, files: [], inflate: [{ at: 0, len: 1 }] }, fine);
  refused(apkDelta, /an apk's delta, given a folder/, old);
  writeFileSync(join(dir, "bad.delta"), craft(abc, fine));
  assert.throws(() => applyFile({ apk: join(dir, "shorter/a") }, join(dir, "bad.delta"), join(dir, "out")), /a folder's delta, given an apk/);
});

test("a zip64 apk is refused", (t) => {
  const dir = temp(t);
  const z = zip([{ name: "a", data: Buffer.from("x"), deflate: false }]);
  z.writeUInt16LE(0xffff, z.length - 12);
  writeFileSync(join(dir, "a.apk"), z);
  assert.throws(() => makeApk(join(dir, "a.apk"), join(dir, "a.apk"), join(dir, "d")), /zip64/);
});

type Rich = { name: string; data: Buffer; deflate: boolean; descriptor?: boolean; attrs?: number; extra?: Buffer; comment?: string };
/** A zip as \`zip\` and \`ditto\` write one streaming: entries deflated or not, some with a data descriptor (no CRC nor
 * sizes in the local header), Unix modes in the external attributes, extra fields, comments. */
function richZip(entries: Rich[], comment = ""): Buffer {
  const locals: Buffer[] = [], central: Buffer[] = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name), body = e.deflate ? deflateRawSync(e.data, { level: 9 }) : e.data, extra = e.extra ?? Buffer.alloc(0);
    const note = Buffer.from(e.comment ?? ""), dd = e.descriptor === true;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE((dd ? 8 : 0) | (e.deflate ? 2 : 0) | 0x800, 6);
    local.writeUInt16LE(e.deflate ? 8 : 0, 8);
    local.writeUInt32LE(0x5a6b2c11, 10);
    if (!dd) { local.writeUInt32LE(crc32(e.data), 14); local.writeUInt32LE(body.length, 18); local.writeUInt32LE(e.data.length, 22); }
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(extra.length, 28);
    const descriptor = Buffer.alloc(dd ? 16 : 0);
    if (dd) { descriptor.writeUInt32LE(0x08074b50, 0); descriptor.writeUInt32LE(crc32(e.data), 4); descriptor.writeUInt32LE(body.length, 8); descriptor.writeUInt32LE(e.data.length, 12); }
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0);
    c.writeUInt16LE(0x0314, 4);
    c.writeUInt16LE(20, 6);
    c.writeUInt16LE((dd ? 8 : 0) | (e.deflate ? 2 : 0) | 0x800, 8);
    c.writeUInt16LE(e.deflate ? 8 : 0, 10);
    c.writeUInt32LE(0x5a6b2c11, 12);
    c.writeUInt32LE(crc32(e.data), 16);
    c.writeUInt32LE(body.length, 20);
    c.writeUInt32LE(e.data.length, 24);
    c.writeUInt16LE(name.length, 28);
    c.writeUInt16LE(extra.length, 30);
    c.writeUInt16LE(note.length, 32);
    c.writeUInt32LE(((e.attrs ?? 0o100644) << 16) >>> 0, 38);
    c.writeUInt32LE(offset, 42);
    locals.push(local, name, extra, body, descriptor);
    central.push(c, name, extra, note);
    offset += 30 + name.length + extra.length + body.length + descriptor.length;
  }
  const cd = Buffer.concat(central), note = Buffer.from(comment), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  end.writeUInt16LE(note.length, 20);
  return Buffer.concat([...locals, cd, end, note]);
}

/** Each entry of a zip as the central directory says it: name, method, flags, external attributes, its data. */
const entriesOf = (z: Buffer) => {
  const list = zipEntries(z);
  let p = z.readUInt32LE(z.lastIndexOf(Buffer.from([0x50, 0x4b, 5, 6])) + 16);
  return list.map((e) => {
    const flags = z.readUInt16LE(p + 8), attrs = z.readUInt32LE(p + 38), time = z.readUInt32LE(p + 12), local = z.readUInt32LE(p + 42);
    p += 46 + z.readUInt16LE(p + 28) + z.readUInt16LE(p + 30) + z.readUInt16LE(p + 32);
    const packed = z.subarray(e.at, e.at + e.packed);
    return { name: e.name, method: e.method, flags, attrs, time, localFlags: z.readUInt16LE(local + 6), localCrc: z.readUInt32LE(local + 14), data: e.method === 8 ? inflateRawSync(packed) : Buffer.from(packed) };
  });
};

test("a zip's raw form: every entry stored, its contents, modes, links and times kept, without data descriptors", (t) => {
  const rand = prng(21);
  const app = texty(rand, 70_000);
  const entries: Rich[] = [
    { name: "still.fail.app/", data: Buffer.alloc(0), deflate: false, attrs: 0o40755 },
    { name: "still.fail.app/Contents/MacOS/still.fail", data: app, deflate: true, descriptor: true, attrs: 0o100755, extra: Buffer.from([0x55, 0x54, 5, 0, 1, 1, 2, 3, 4]) },
    { name: "still.fail.app/Contents/Frameworks/Current", data: Buffer.from("A"), deflate: false, descriptor: true, attrs: 0o120755 },
    { name: "still.fail.app/Contents/Resources/core.hbc", data: random(rand, 20_000), deflate: true, comment: "the core" },
    { name: "still.fail.app/Contents/Resources/empty", data: Buffer.alloc(0), deflate: true, descriptor: true },
    { name: "still.fail.app/Contents/Info.plist", data: Buffer.from("<plist>8147</plist>"), deflate: false },
  ];
  const z = richZip(entries, "made by a test");
  const stored = storedZip(z);
  const before = entriesOf(z), after = entriesOf(stored);
  assert.deepEqual(after.map((e) => e.name), entries.map((e) => e.name), "the same entries in the same order");
  for (const [i, e] of after.entries()) {
    assert.equal(e.method, 0, e.name);
    assert.ok(e.data.equals(entries[i]!.data), `${e.name}: its contents`);
    assert.equal(e.attrs, before[i]!.attrs, `${e.name}: its mode (a link stays a link)`);
    assert.equal(e.time, before[i]!.time, `${e.name}: its time`);
    assert.equal(e.flags & 8, 0, `${e.name}: no data descriptor`);
    assert.equal(e.localFlags & 8, 0, `${e.name}: none said in its local header`);
    assert.equal(e.localCrc, crc32(entries[i]!.data), `${e.name}: its CRC in its local header`);
    assert.equal(e.flags & 0x800, 0x800, `${e.name}: its UTF-8 name kept`);
  }
  assert.ok(stored.subarray(-14).equals(Buffer.from("made by a test")), "the zip's comment kept");
  assert.ok(stored.includes(Buffer.from("the core")) && stored.includes(Buffer.from([0x55, 0x54, 5, 0, 1, 1, 2, 3, 4])), "comments and extra fields kept");
  assert.ok(storedZip(z).equals(stored), "deterministic");
  assert.ok(storedZip(stored).equals(stored), "a stored zip comes back as it was");
  // One a minimal writer stored: as it was.
  const plain = zip([{ name: "a", data: Buffer.from("x"), deflate: false }, { name: "b/c", data: texty(rand, 3000), deflate: false }]);
  assert.ok(storedZip(plain).equals(plain));
  // The system's unzip, where there is one, reads it as the zip it was.
  const dir = temp(t);
  writeFileSync(join(dir, "stored.zip"), stored);
  const unzip = spawnSync("unzip", ["-p", join(dir, "stored.zip"), "still.fail.app/Contents/MacOS/still.fail"], { maxBuffer: 1 << 24 });
  if (unzip.error === undefined) {
    assert.equal(unzip.status, 0, String(unzip.stderr));
    assert.ok(unzip.stdout.equals(app));
  }
});

test("a zip's raw form refuses zip64, encrypted entries and methods other than deflate", () => {
  const one = (more: Partial<Rich> = {}) => richZip([{ name: "a", data: Buffer.from("hello"), deflate: true, ...more }]);
  const z64 = one();
  z64.writeUInt16LE(0xffff, z64.length - 12);
  assert.throws(() => storedZip(z64), /zip64/);
  const sized = one();
  const cd = sized.readUInt32LE(sized.length - 6);
  sized.writeUInt32LE(0xffffffff, cd + 24);
  assert.throws(() => storedZip(sized), /zip64/);
  const extra = one({ extra: Buffer.from([1, 0, 0, 0]) });
  assert.throws(() => storedZip(extra), /zip64/);
  const locked = one();
  const at = locked.readUInt32LE(locked.length - 6);
  locked.writeUInt16LE(locked.readUInt16LE(at + 8) | 1, at + 8);
  assert.throws(() => storedZip(locked), /encrypted/);
  const bzip = one();
  bzip.writeUInt16LE(12, bzip.readUInt32LE(bzip.length - 6) + 10);
  assert.throws(() => storedZip(bzip), /method 12/);
  const lying = one();
  lying.writeUInt32LE(1, lying.readUInt32LE(lying.length - 6) + 16);
  assert.throws(() => storedZip(lying), /CRC/);
});

test("the raw command writes a .tar.gz's tar and a .zip stored", (t) => {
  const dir = temp(t);
  const tar = texty(prng(4), 50_000);
  writeFileSync(join(dir, "r.tar.gz"), gzipSync(tar));
  const z = richZip([{ name: "a", data: texty(prng(5), 9000), deflate: true, descriptor: true }]);
  writeFileSync(join(dir, "r.zip"), z);
  for (const [from, want] of [["r.tar.gz", tar], ["r.zip", storedZip(z)]] as const) {
    const run = cli("raw", join(dir, from), join(dir, "out"));
    assert.equal(run.status, 0, run.stderr);
    assert.ok(readFileSync(join(dir, "out")).equals(want), from);
  }
  const bad = cli("raw", join(dir, "nothing.txt"), join(dir, "out2"));
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /raw form/);
});

// --- the old files found whole ---

/** Bytes from a small LCG, the same for a seed each time. */
function lcg(seed: number) {
  let s = seed >>> 0;
  return (n: number) => {
    const b = Buffer.alloc(n);
    for (let i = 0; i < n; i++) { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; b[i] = s >>> 24; }
    return b;
  };
}
/** Files one after another, as a tree's old blob is, and their ranges in it. */
const blobOf = (files: Buffer[]) => {
  const ranges: { at: number; len: number }[] = [];
  let at = 0;
  for (const f of files) { ranges.push({ at, len: f.length }); at += f.length; }
  return { blob: Buffer.concat(files), ranges };
};
/** A tar-like package: each file after a 512-byte header of its own. */
const tarLike = (files: [string, Buffer][]) => Buffer.concat(files.flatMap(([name, data]) => {
  const head = Buffer.alloc(512);
  head.write(`${name} ${data.length}`);
  return [head, data];
}));

test("the old files found whole: every unchanged one at least a window long, wherever it is, never overlapping", () => {
  const bytes = lcg(5);
  const [a, b, c, d, e, f] = [3000, 1000, WINDOW - 1, 5000, 2000, 700].map((n) => bytes(n)) as Buffer[];
  const old = blobOf([a!, b!, c!, d!, e!, f!]);
  const changed = Buffer.from(e!);
  changed[1000] = changed[1000]! ^ 1;
  const order: [string, Buffer][] = [["d", d!], ["b", b!], ["a", a!], ["e", changed], ["c", c!], ["b2", b!], ["f", f!]];
  const made = tarLike(order), at: Record<string, number> = {};
  order.reduce((o, [name, data]) => { at[name] = o + 512; return o + 512 + data.length; }, 0);
  const runs = wholeFiles(old.blob, old.ranges, made);
  // (d, b, a, then b again and f; not e, changed, nor c, shorter than the window)
  const whole = (name: string, i: number) => ({ made: at[name]!, old: old.ranges[i]!.at, len: old.ranges[i]!.len });
  assert.deepEqual(runs, [whole("d", 3), whole("b", 1), whole("a", 0), whole("b2", 1), whole("f", 5)]);
  for (let i = 0; i < runs.length; i++) {
    const r = runs[i]!;
    assert.ok(made.subarray(r.made, r.made + r.len).equals(old.blob.subarray(r.old, r.old + r.len)));
    if (i > 0) assert.ok(runs[i - 1]!.made + runs[i - 1]!.len <= r.made, "sorted, not overlapping");
  }
  // the rest of the old blob sorted, each suffix by its offset in the old blob, the empty one first
  const I = sparseSuffixArray(old.blob, runs);
  assert.equal(I[0], old.blob.length);
  const outside = [...Array(old.blob.length).keys()].filter((o) => !runs.some((r) => o >= r.old && o < r.old + r.len));
  assert.deepEqual([...I.subarray(1)].sort((x, y) => x - y), outside);
  // a file that begins with a window of one byte is not looked for, though it is there whole
  const zeros = Buffer.concat([Buffer.alloc(WINDOW), bytes(900)]), flat = blobOf([zeros, a!]);
  const there = tarLike([["z", zeros], ["a", a!]]);
  assert.deepEqual(wholeFiles(flat.blob, flat.ranges, there), [{ made: 512 + zeros.length + 512, old: flat.ranges[1]!.at, len: a!.length }]);
});

test("a delta made with the old files found whole gives the package, as small as without them, the same each time", (t) => {
  const dir = temp(t);
  const bytes = lcg(8147);
  const sizes = [100, 255, 256, 700, 3000, 12_000, 40_000, 90_000, 150_000, 300_000];
  const old: Record<string, Buffer> = {};
  for (let i = 0; i < 30; i++) old[`f${String(i).padStart(2, "0")}`] = bytes(sizes[i % sizes.length]!);
  const neu: Record<string, Buffer> = { ...old };
  delete neu.f03;
  neu.f31 = bytes(20_000);
  for (const [name, at] of [["f07", 100], ["f09", 50_000], ["f18", 2000], ["f29", 299_000]] as const) {
    const edited = Buffer.from(old[name]!);
    edited.write("build 8147", at);
    neu[name] = name === "f09" ? Buffer.concat([edited.subarray(0, 60_000), bytes(300), edited.subarray(60_000)]) : edited;
  }
  tree(join(dir, "old"), old);
  const made = tarLike(Object.entries(neu).sort(([x], [y]) => (x < y ? -1 : 1)));
  writeFileSync(join(dir, "new.tar"), made);
  makeTree(join(dir, "old"), join(dir, "new.tar"), join(dir, "d.delta"));
  makeTree(join(dir, "old"), join(dir, "new.tar"), join(dir, "again.delta"));
  const delta = readFileSync(join(dir, "d.delta"));
  assert.ok(readFileSync(join(dir, "again.delta")).equals(delta), "the same delta each time");
  const files = treeFiles(join(dir, "old")), o = blobOf(files.map((f) => old[f]!));
  const runs = wholeFiles(o.blob, o.ranges, made), found = runs.reduce((n, r) => n + r.len, 0);
  assert.ok(found > o.blob.length / 2, `${found} of ${o.blob.length} bytes found whole`);
  const without = makeDelta(o.blob, made, files, [], []);
  t.diagnostic(`with the files found whole ${delta.length} bytes, without ${without.length}`);
  assert.ok(delta.length <= without.length + 512, `${delta.length} bytes, ${without.length} without`);
});

test("with too little of the old blob found whole, the delta is the one made without the files", () => {
  const bytes = lcg(9);
  const kept = bytes(1000), others = [bytes(50_000), bytes(40_000)];
  const old = blobOf([others[0]!, kept, others[1]!]);
  const edit = (b: Buffer) => { const c = Buffer.from(b); for (let i = 0; i < c.length; i += 300) c[i] = c[i]! ^ 0xff; return c; };
  for (const made of [tarLike([["x", bytes(20_000)], ["y", bytes(5000)]]), tarLike([["a", edit(others[0]!)], ["k", kept], ["b", edit(others[1]!)]])]) {
    assert.ok(wholeFiles(old.blob, old.ranges, made).reduce((n, r) => n + r.len, 0) < old.blob.length / 8);
    assert.ok(makeDelta(old.blob, made, ["a", "k", "b"], [], [], old.ranges).equals(makeDelta(old.blob, made, ["a", "k", "b"], [], [])));
  }
});
