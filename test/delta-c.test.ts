import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { constants, deflateRawSync, inflateRawSync, type ZlibOptions } from "node:zlib";

// The desktop hosts' delta applier (libs/mbui/src/host/update_delta.h: its own inflate and SHA-256, in C) held to
// scripts/delta.ts, which makes the release's deltas, and to node's zlib: what it makes is byte for byte what the
// reference makes, and whatever is wrong with a delta it refuses with a reason, never crashing (run under the address
// and undefined-behaviour sanitizers where the compiler has them).

const root = fileURLToPath(new URL("..", import.meta.url));
const harness = join(root, "libs/mbui/src/host/update_delta_test.c");
const deltaTs = join(root, "scripts/delta.ts");
const work = mkdtempSync(join(tmpdir(), "delta-c-test-"));
process.on("exit", () => rmSync(work, { recursive: true, force: true }));

// the harness compiled: with the sanitizers where they build, else plain; none without a C compiler
function compile(): { exe: string; sanitized: boolean } | null {
  if (spawnSync("cc", ["--version"]).status !== 0) return null;
  const exe = join(work, "update_delta_test");
  const base = ["-std=c99", "-Wall", "-Wextra", "-Werror", "-pedantic", "-g", "-o", exe, harness];
  const san = ["-O1", "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined", "-fno-omit-frame-pointer"];
  if (spawnSync("cc", [...san, ...base]).status === 0) return { exe, sanitized: true };
  const plain = spawnSync("cc", ["-O2", ...base], { encoding: "utf8" });
  assert.equal(plain.status, 0, plain.stderr);
  return { exe, sanitized: false };
}
const built = compile();
const skip = built ? false : "no C compiler (cc) here: update_delta.h not tested";

function run(...args: string[]) {
  const r = spawnSync(built!.exe, args, { encoding: "utf8", env: { ...process.env, ASAN_OPTIONS: "abort_on_error=0:exitcode=99" } });
  // a refusal is 1 with its reason; anything else (a signal, a sanitizer's report) is the applier's fault
  assert.ok(r.status === 0 || r.status === 1, `exit ${r.status} signal ${r.signal}: ${r.stderr}`);
  assert.doesNotMatch(r.stderr, /Sanitizer|runtime error/, r.stderr);
  return { ok: r.status === 0, why: r.stderr.trim(), out: r.stdout };
}

// a seeded PRNG (mulberry32): the same bytes every run
function prng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const randomBytes = (r: () => number, n: number) => {
  const b = Buffer.alloc(n);
  for (let i = 0; i < n; i++) b[i] = (r() * 256) | 0;
  return b;
};
const textLike = (r: () => number, n: number) => {
  const words = ["still", "fail", "delta", "update", "the", "app", "of", "a", "chunk", "inflate", "\n", "{", "}", "0x1f"];
  const parts: string[] = [];
  for (let len = 0; len < n;) {
    const w = words[(r() * words.length) | 0]!;
    parts.push(w, " ");
    len += w.length + 1;
  }
  return Buffer.from(parts.join("").slice(0, n));
};
const sha256 = (b: Uint8Array) => createHash("sha256").update(b).digest("hex");

let serial = 0;
const fresh = (name: string) => join(work, `${serial++}-${name}`);

test("its SHA-256 is node's", { skip }, () => {
  const r = prng(1);
  for (const n of [0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 1000, 65536, 300001]) {
    const b = randomBytes(r, n), f = fresh("sha");
    writeFileSync(f, b);
    assert.equal(run("sha256", f).out.trim(), sha256(b), `${n} bytes`);
  }
});

test("its inflate makes what node's zlib deflated, at every level and strategy", { skip }, () => {
  const r = prng(2);
  const inputs: [string, Buffer][] = [
    ["empty", Buffer.alloc(0)],
    ["one byte", Buffer.from([7])],
    ["random", randomBytes(r, 200_000)],
    ["zeros", Buffer.alloc(300_000)],
    ["text", textLike(r, 300_000)],
    ["mixed", Buffer.concat([textLike(r, 50_000), Buffer.alloc(70_000), randomBytes(r, 30_000), textLike(r, 90_000)])],
  ];
  const options: [string, ZlibOptions][] = [];
  for (let level = 0; level <= 9; level++) options.push([`level ${level}`, { level }]);
  options.push(["fixed", { level: 6, strategy: constants.Z_FIXED }], ["huffman only", { level: 6, strategy: constants.Z_HUFFMAN_ONLY }],
    ["rle", { level: 6, strategy: constants.Z_RLE }], ["small window", { level: 9, windowBits: 9, memLevel: 1 }]);
  let checked = 0;
  for (const [what, raw] of inputs) {
    for (const [how, o] of options) {
      const packed = deflateRawSync(raw, o), inF = fresh("z"), outF = fresh("raw");
      writeFileSync(inF, packed);
      const got = run("inflate", inF, outF, String(raw.length));
      assert.ok(got.ok, `${what}, ${how}: ${got.why}`);
      assert.ok(readFileSync(outF).equals(raw), `${what}, ${how}: not the same bytes`);
      // one byte less room than it makes: refused
      if (raw.length) assert.match(run("inflate", inF, outF, String(raw.length - 1)).why, /more than its raw_len/);
      checked++;
    }
  }
  console.log(`inflate: ${checked} streams made again byte for byte`);
});

test("its inflate refuses what is no deflate stream and never reads past one", { skip }, () => {
  const r = prng(3);
  const raw = Buffer.concat([textLike(r, 40_000), randomBytes(r, 5_000)]);
  const streams = [deflateRawSync(raw, { level: 9 }), deflateRawSync(raw, { level: 0 }), deflateRawSync(raw, { strategy: constants.Z_FIXED })];
  let refused = 0, tried = 0;
  for (const s of streams) {
    for (const cut of [0, 1, 2, 5, 17, s.length >> 1, s.length - 1]) {
      const f = fresh("cut");
      writeFileSync(f, s.subarray(0, cut));
      assert.ok(!run("inflate", f, fresh("o"), String(raw.length)).ok, `cut at ${cut}`);
      refused++, tried++;
    }
    for (let i = 0; i < 60; i++) {
      const b = Buffer.from(s), at = (r() * b.length) | 0;
      b[at]! ^= 1 << ((r() * 8) | 0);
      const f = fresh("flip");
      writeFileSync(f, b);
      if (!run("inflate", f, fresh("o"), String(raw.length)).ok) refused++;
      tried++;
    }
  }
  // the first three bits saying a block of the kind that is none
  const f = fresh("kind3");
  writeFileSync(f, Buffer.from([0x07, 0, 0, 0]));
  assert.match(run("inflate", f, fresh("o"), "100").why, /kind that is none/);
  console.log(`inflate: ${refused} of ${tried} broken streams refused, none crashed`);
});

// a tree (nested folders, one file of 3 MB) and a package made of it changed: files changed, added, removed, moved
function tree(seed: number) {
  const r = prng(seed), dir = fresh(`old-${seed}`), files = new Map<string, Buffer>();
  const put = (rel: string, b: Buffer) => {
    mkdirSync(dirname(join(dir, rel)), { recursive: true });
    writeFileSync(join(dir, rel), b);
    files.set(rel, b);
  };
  put("Contents/MacOS/app", Buffer.concat([randomBytes(r, 1_000_000), Buffer.alloc(500_000), textLike(r, 1_500_000)]));
  put("Contents/Info.plist", textLike(r, 3_000));
  put("Contents/Resources/core.hbc", Buffer.concat([textLike(r, 200_000), randomBytes(r, 100_000)]));
  put("Contents/Resources/gone.txt", textLike(r, 20_000));
  put("Contents/Resources/日本語.txt", textLike(r, 5_000));
  put("VERSION", Buffer.from(`0.1.${seed}\n`));
  put("empty", Buffer.alloc(0));
  const big = files.get("Contents/MacOS/app")!;
  const changed = Buffer.from(big);
  for (let i = 0; i < 2_000; i++) changed[(r() * changed.length) | 0] = (r() * 256) | 0;
  const shifted = Buffer.concat([randomBytes(r, 777), changed.subarray(0, 1_200_000), textLike(r, 9_000), changed.subarray(1_200_000)]);
  const pkg = Buffer.concat([
    Buffer.from("PK raw package head"),
    files.get("Contents/Info.plist")!,
    shifted,
    randomBytes(r, 50_000), // added
    files.get("Contents/Resources/core.hbc")!.subarray(1000),
    files.get("Contents/Resources/日本語.txt")!,
    Buffer.from(`0.1.${seed + 1}\n`),
  ]);
  const pkgF = fresh(`new-${seed}`);
  writeFileSync(pkgF, pkg);
  return { dir, files, pkg, pkgF };
}

function makeDelta(dir: string, pkgF: string) {
  const out = fresh("delta");
  const r = spawnSync(process.execPath, [deltaTs, "make", "--old", dir, "--new", pkgF, "--out", out], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  return out;
}

// the delta's parts, to build others of: its header and its stream's raw bytes
function split(d: Buffer) {
  let p = 12;
  for (let n = d.readUInt32LE(8); n > 0; n--) p += 2 + d.readUInt16LE(p);
  p += 4 + 8 + 32 + 4 + 8;
  const header = d.subarray(0, p), raws: Buffer[] = [];
  for (;;) {
    const raw = d.readUInt32LE(p), packed = d.readUInt32LE(p + 4);
    p += 8;
    if (raw === 0) break;
    raws.push(inflateRawSync(d.subarray(p, p + packed)));
    p += packed;
  }
  return { header, stream: Buffer.concat(raws) };
}

// a delta of `header` and `stream` cut in chunks of `size`, each deflated as `how` says (by turns where several)
function rebuild(header: Buffer, stream: Buffer, size: number, how: ZlibOptions[]) {
  const parts = [header];
  for (let at = 0, i = 0; at < stream.length; at += size, i++) {
    const raw = stream.subarray(at, at + size), packed = deflateRawSync(raw, how[i % how.length]), head = Buffer.alloc(8);
    head.writeUInt32LE(raw.length, 0);
    head.writeUInt32LE(packed.length, 4);
    parts.push(head, packed);
  }
  parts.push(Buffer.alloc(8));
  return Buffer.concat(parts);
}

test("a tree's delta made by scripts/delta.ts makes the package byte for byte", { skip }, () => {
  for (const seed of [11, 12, 13]) {
    const t = tree(seed), delta = makeDelta(t.dir, t.pkgF), out = fresh("made");
    const got = run("apply", t.dir, delta, out, String(t.pkg.length));
    assert.ok(got.ok, got.why);
    assert.equal(sha256(readFileSync(out)), sha256(t.pkg), `seed ${seed}`);
    const { stream } = split(readFileSync(delta));
    console.log(`seed ${seed}: ${t.pkg.length} bytes made from a delta of ${readFileSync(delta).length} (${Math.ceil(stream.length / (1 << 20))} chunks)`);
  }
});

test("chunks stored, fixed or dynamic, of any size, a record across them, make the same", { skip }, () => {
  const t = tree(21), d = readFileSync(makeDelta(t.dir, t.pkgF)), { header, stream } = split(d);
  const ways: [string, number, ZlibOptions[]][] = [
    ["stored, 1 MiB", 1 << 20, [{ level: 0 }]],
    ["fixed, 1 MiB", 1 << 20, [{ strategy: constants.Z_FIXED }]],
    ["huffman only, 1 MiB", 1 << 20, [{ strategy: constants.Z_HUFFMAN_ONLY }]],
    ["levels by turns, 100 000", 100_000, [{ level: 0 }, { level: 1 }, { level: 9 }, { strategy: constants.Z_FIXED }]],
    ["7 bytes each", 7, [{ level: 1 }]],
    ["23 bytes each", 23, [{ level: 0 }, { level: 9 }]],
  ];
  const sm = small(), smd = split(sm.d);
  for (const [what, size, how] of ways) {
    // (the small tree's where the chunks are tiny: the records' heads cut every way, quickly)
    const [dir, pkg, h, st]: [string, Buffer, Buffer, Buffer] = size < 100 ? [sm.dir, sm.pkg, smd.header, smd.stream] : [t.dir, t.pkg, header, stream];
    const f = fresh("rebuilt"), out = fresh("made");
    writeFileSync(f, rebuild(h, st, size, how));
    const got = run("apply", dir, f, out);
    assert.ok(got.ok, `${what}: ${got.why}`);
    assert.ok(readFileSync(out).equals(pkg), what);
  }
});

// a small tree's delta, quick to apply many times over, for what it refuses
function small() {
  const r = prng(31), dir = fresh("small-old");
  mkdirSync(join(dir, "a"), { recursive: true });
  const x = textLike(r, 30_000), y = randomBytes(r, 3_000);
  writeFileSync(join(dir, "a/x"), x);
  writeFileSync(join(dir, "y"), y);
  const pkg = Buffer.concat([y.subarray(100), textLike(r, 500), x.subarray(0, 20_000), Buffer.from("tail")]), pkgF = fresh("small-new");
  writeFileSync(pkgF, pkg);
  return { dir, pkg, d: readFileSync(makeDelta(dir, pkgF)) };
}

test("whatever is wrong with a delta is refused with a reason, nothing made before the old files are checked", { skip }, () => {
  const s = small(), { header, stream } = split(s.d);
  const nFiles = s.d.readUInt32LE(8);
  let p = 12;
  const paths: number[] = [];
  for (let n = nFiles; n > 0; n--) paths.push(p), (p += 2 + s.d.readUInt16LE(p));
  const at = { inflate: p, oldSize: p + 4, sha: p + 12, deflate: p + 44, madeSize: p + 48, chunks: p + 56 };
  const refused = (d: Buffer, want: RegExp, what: string, madeSize?: number) => {
    const f = fresh("bad"), out = fresh("out");
    writeFileSync(f, d);
    const got = run("apply", s.dir, f, out, ...(madeSize === undefined ? [] : [String(madeSize)]));
    assert.ok(!got.ok, `${what}: taken`);
    assert.match(got.why, want, what);
    return out;
  };
  const edit = (f: (b: Buffer) => void) => {
    const b = Buffer.from(s.d);
    f(b);
    return b;
  };
  const withPath = (path: Buffer) => {
    const len = Buffer.alloc(2);
    len.writeUInt16LE(path.length);
    return Buffer.concat([s.d.subarray(0, paths[0]!), len, path, s.d.subarray(paths[0]! + 2 + s.d.readUInt16LE(paths[0]!))]);
  };
  let n = 0;
  const no = (d: Buffer, want: RegExp, what: string, madeSize?: number) => (refused(d, want, what, madeSize), n++);

  // the header
  no(edit((b) => (b[0] = 0x58)), /not a delta/, "magic");
  no(edit((b) => b.writeUInt32LE(0, 8)), /n_files 0/, "no files");
  no(edit((b) => b.writeUInt32LE(nFiles + 1, 8)), /old_size|cut short|unsafe/, "one file more than there are");
  for (const bad of ["../y", "a/../../y", "/etc/passwd", "a//x", "a\\x", "C:x", "a/", ""]) no(withPath(Buffer.from(bad)), /unsafe path/, `path ${JSON.stringify(bad)}`);
  no(withPath(Buffer.from([0x61, 0, 0x78])), /unsafe path/, "a NUL in a path");
  no(withPath(Buffer.from([0x61, 0xc0, 0xaf])), /unsafe path/, "overlong UTF-8");
  no(withPath(Buffer.from([0x61, 0xff])), /unsafe path/, "not UTF-8");
  no(withPath(Buffer.from([0xed, 0xa0, 0x80])), /unsafe path/, "a surrogate in UTF-8");
  no(edit((b) => b.writeUInt16LE(0xffff, paths[0]!)), /cut short|unsafe/, "a path's length past the end");
  no(edit((b) => b.writeUInt32LE(1, at.inflate)), /n_inflate/, "inflate ranges");
  no(edit((b) => b.writeUInt32LE(1, at.deflate)), /n_deflate/, "deflate ranges");
  no(edit((b) => b.writeBigUInt64LE(b.readBigUInt64LE(at.oldSize) + 1n, at.oldSize)), /not old_size/, "old_size one more");
  no(edit((b) => b.writeBigUInt64LE(b.readBigUInt64LE(at.oldSize) - 1n, at.oldSize)), /more than old_size/, "old_size one less");
  no(edit((b) => b.writeBigUInt64LE(1n << 53n, at.oldSize)), /too large/, "old_size past 2^53");
  no(edit((b) => b.writeBigUInt64LE(1n << 53n, at.madeSize)), /too large/, "made_size past 2^53");
  no(edit((b) => (b[at.sha + 5]! ^= 1)), /SHA-256/, "the old blob's SHA-256");
  no(edit((b) => b.writeBigUInt64LE(b.readBigUInt64LE(at.madeSize) + 1n, at.madeSize)), /ends before made_size/, "made_size one more");
  no(edit((b) => b.writeBigUInt64LE(b.readBigUInt64LE(at.madeSize) - 1n, at.madeSize)), /more than made_size|after made_size/, "made_size one less");
  no(s.d, /another size than the feed says/, "made_size not the feed's", s.pkg.length + 1);
  // the chunks
  no(edit((b) => b.writeUInt32LE((1 << 20) + 1, at.chunks)), /more than 1 MiB|cut short/, "raw_len over 1 MiB");
  no(edit((b) => b.writeUInt32LE(b.readUInt32LE(at.chunks) + 1, at.chunks)), /less than its raw_len/, "raw_len one more");
  no(edit((b) => b.writeUInt32LE(b.readUInt32LE(at.chunks) - 1, at.chunks)), /more than its raw_len/, "raw_len one less");
  no(edit((b) => b.writeUInt32LE(b.readUInt32LE(at.chunks + 4) + 1, at.chunks + 4)), /more than its deflate stream|cut short|end chunk/, "packed_len one more");
  no(edit((b) => b.writeUInt32LE(b.readUInt32LE(at.chunks + 4) - 1, at.chunks + 4)), /cut short|does not have/, "packed_len one less");
  no(edit((b) => b.writeUInt32LE(0xffffffff, at.chunks + 4)), /cut short/, "packed_len past the end");
  no(s.d.subarray(0, s.d.length - 8), /without its end chunk/, "no end chunk");
  no(s.d.subarray(0, s.d.length - 3), /without its end chunk/, "the end chunk cut");
  no(Buffer.concat([s.d, Buffer.from([0])]), /after its end chunk/, "a byte after the end");
  no(edit((b) => (b[b.length - 1] = 1)), /after its end chunk/, "the end chunk's packed_len not 0");
  no(rebuild(header, Buffer.concat([stream, Buffer.alloc(24)]), 1 << 20, [{}]), /after made_size/, "a record after made_size");
  no(rebuild(header, Buffer.concat([stream, Buffer.alloc(1)]), 1 << 20, [{}]), /after made_size/, "a byte after made_size");
  no(rebuild(header, Buffer.concat([stream, Buffer.alloc(1)]), stream.length, [{}]), /after made_size/, "a chunk after made_size");
  no(rebuild(header, stream.subarray(0, stream.length - 1), 1 << 20, [{}]), /ends before made_size/, "the stream a byte short");
  no(rebuild(header, stream.subarray(0, 10), 1 << 20, [{}]), /ends before made_size/, "the stream cut in a record's head");
  // the records
  const record = (x: bigint, y: bigint, z: bigint) => {
    const b = Buffer.alloc(24);
    b.writeBigInt64LE(x, 0), b.writeBigInt64LE(y, 8), b.writeBigInt64LE(z, 16);
    return b;
  };
  const made = BigInt(s.pkg.length);
  no(rebuild(header, record(-1n, 0n, 0n), 1 << 20, [{}]), /negative/, "x < 0");
  no(rebuild(header, record(0n, -5n, 0n), 1 << 20, [{}]), /negative/, "y < 0");
  no(rebuild(header, record(made + 1n, 0n, 0n), 1 << 20, [{}]), /more than made_size/, "x past made_size");
  no(rebuild(header, record(made, 1n, 0n), 1 << 20, [{}]), /more than made_size/, "x + y past made_size");
  no(rebuild(header, record(0n, 0n, 1n << 53n), 1 << 20, [{}]), /too large/, "z past 2^53");
  no(rebuild(header, record(0n, 0n, -(1n << 53n) - 1n), 1 << 20, [{}]), /too large/, "z before -2^53");
  no(rebuild(header, record((1n << 63n) - 1n, 0n, 0n), 1 << 20, [{}]), /too large/, "x at i64's top");
  // an old file not there, or not the same: refused before a byte is made
  const gone = fresh("gone");
  mkdirSync(join(gone, "a"), { recursive: true });
  writeFileSync(join(gone, "y"), readFileSync(join(s.dir, "y")));
  const f = fresh("d");
  writeFileSync(f, s.d);
  let got = run("apply", gone, f, fresh("out"));
  assert.match(got.why, /could not be read/);
  writeFileSync(join(gone, "a/x"), Buffer.concat([readFileSync(join(s.dir, "a/x")).subarray(1), Buffer.from("!")]));
  const out = fresh("out");
  got = run("apply", gone, f, out);
  assert.match(got.why, /SHA-256/);
  assert.equal(readFileSync(out).length, 0, "nothing made from other old files");
  n += 2;
  console.log(`refused: ${n} broken deltas, each with its reason`);
});

test("a delta cut anywhere, or with any of its bytes flipped, is refused or made, never more", { skip }, () => {
  const s = small(), r = prng(41);
  let cut = 0, flipped = 0, made = 0;
  for (let len = 0; len < s.d.length; len += len < 200 ? 1 : 97) {
    const f = fresh("cut");
    writeFileSync(f, s.d.subarray(0, len));
    assert.ok(!run("apply", s.dir, f, fresh("out")).ok, `cut at ${len}`);
    cut++;
  }
  for (let i = 0; i < 300; i++) {
    const b = Buffer.from(s.d), at = (r() * b.length) | 0;
    b[at]! ^= 1 << ((r() * 8) | 0);
    const f = fresh("flip"), out = fresh("out");
    writeFileSync(f, b);
    if (run("apply", s.dir, f, out).ok) made++;
    flipped++;
  }
  console.log(`${cut} cut deltas refused; ${flipped} with a bit flipped: ${flipped - made} refused, ${made} made something (its SHA-256 is the host's to check)${built!.sanitized ? ", under ASan and UBSan" : ""}`);
});
