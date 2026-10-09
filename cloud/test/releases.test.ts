import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";
import { groupReads, parseRanges } from "../src/releases.ts";

// The releases bucket's files at /releases/<file>: whole, or the ranges asked for (one, or many as
// multipart/byteranges, as the desktop app's updater asks for what changed between two zips).

/** The parts of a multipart/byteranges answer: each one's content-range and bytes. */
function parts(body: Uint8Array, boundary: string): { range: string; bytes: Uint8Array }[] {
  const text = Buffer.from(body).toString("latin1");
  const out: { range: string; bytes: Uint8Array }[] = [];
  // As electron-updater's DataSplitter reads it: starting with the boundary, each part's bytes followed by CRLF and the next.
  assert.ok(text.startsWith(`--${boundary}\r\n`), "starts with the boundary");
  assert.ok(text.endsWith(`\r\n--${boundary}--\r\n`), "ends with the closing boundary");
  let at = 0;
  for (;;) {
    at = text.indexOf(`--${boundary}`, at) + boundary.length + 2;
    if (text.startsWith("--", at)) return out;
    const headEnd = text.indexOf("\r\n\r\n", at);
    const range = /content-range: bytes (\d+)-(\d+)\/\d+/i.exec(text.slice(at, headEnd))!;
    const start = headEnd + 4;
    const length = Number(range[2]) - Number(range[1]) + 1;
    out.push({ range: `${range[1]}-${range[2]}`, bytes: body.subarray(start, start + length) });
    at = start + length;
    assert.equal(text.slice(at, at + 2), "\r\n");
  }
}

test("a release is served whole or by ranges, the versioned builds cached for good", async () => {
  const h = await harness();
  try {
    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: Uint8Array | string): Promise<unknown> };
    // 5 MB of bytes that say where they are.
    const zip = new Uint8Array(5 * 1024 * 1024).map((_, i) => (i * 7 + (i >> 11)) & 255);
    const name = "desktop/stillfail-0.1.1200-arm64-mac.zip";
    await bucket.put(name, zip);
    await bucket.put("desktop/stillfail-mac.yml", "version: 0.1.1200\n");

    const whole = await h.fetch(`/releases/${name}`);
    assert.equal(whole.status, 200);
    assert.equal(whole.headers.get("accept-ranges"), "bytes");
    assert.equal(whole.headers.get("cache-control"), "public, max-age=31536000, immutable");
    assert.deepEqual(new Uint8Array(await whole.arrayBuffer()), zip);
    const feed = await h.fetch("/releases/desktop/stillfail-mac.yml");
    assert.equal(feed.headers.get("cache-control"), "no-store");
    assert.equal(await feed.text(), "version: 0.1.1200\n");

    const one = await h.fetch(`/releases/${name}`, { headers: { range: "bytes=100-199" } });
    assert.equal(one.status, 206);
    assert.equal(one.headers.get("content-range"), `bytes 100-199/${zip.length}`);
    assert.deepEqual(new Uint8Array(await one.arrayBuffer()), zip.subarray(100, 200));
    const suffix = await h.fetch(`/releases/${name}`, { headers: { range: "bytes=-10" } });
    assert.deepEqual(new Uint8Array(await suffix.arrayBuffer()), zip.subarray(zip.length - 10));
    const outside = await h.fetch(`/releases/${name}`, { headers: { range: `bytes=${zip.length}-` } });
    assert.equal(outside.status, 416);
    assert.equal(outside.headers.get("content-range"), `bytes */${zip.length}`);
    await outside.arrayBuffer();

    // As the updater asks: many ranges, near each other and far apart, some next to each other.
    const asked: [number, number][] = [];
    for (let i = 0; i < 300; i++) {
      const start = i * 17_000 + (i % 3) * 5;
      asked.push([start, start + 1 + (i % 50) * 31]);
    }
    asked.push([4_000_000, 4_000_099], [4_000_100, 4_000_199], [5 * 1024 * 1024 - 5, 5 * 1024 * 1024 - 1]);
    const many = await h.fetch(`/releases/${name}`, { headers: { range: "bytes=" + asked.map(([a, b]) => `${a}-${b}`).join(", ") } });
    assert.equal(many.status, 206);
    const boundary = /^multipart\/byteranges; boundary=(\S+)$/.exec(many.headers.get("content-type") ?? "")?.[1];
    assert.ok(boundary);
    const body = new Uint8Array(await many.arrayBuffer());
    assert.equal(Number(many.headers.get("content-length")), body.length);
    const got = parts(body, boundary);
    assert.equal(got.length, asked.length);
    got.forEach((part, i) => {
      const [a, b] = asked[i]!;
      assert.equal(part.range, `${a}-${b}`);
      assert.deepEqual(part.bytes, zip.subarray(a, b + 1));
    });

    assert.equal((await h.fetch("/releases/desktop/stillfail-0.1.1199-arm64-mac.zip", { headers: { range: "bytes=0-1" } })).status, 404);
  } finally {
    await h.close();
  }
});

test("ranges are read from the bucket in a few reads", () => {
  assert.deepEqual(parseRanges("bytes=0-9, 20-, -5", 100), [{ start: 0, end: 10 }, { start: 20, end: 100 }, { start: 95, end: 100 }]);
  assert.deepEqual(parseRanges("bytes=200-300", 100), []);
  assert.equal(parseRanges("bytes=9-1", 100), null);
  assert.equal(parseRanges("items=0-1", 100), null);
  const ranges = Array.from({ length: 1000 }, (_, i) => ({ start: i * 1_000_000, end: i * 1_000_000 + 10 }));
  const reads = groupReads(ranges);
  assert.ok(reads.length <= 40, `${reads.length} reads`);
  assert.equal(reads.at(-1)!.last, 999);
  // Out of order: a read never goes back.
  assert.deepEqual(groupReads([{ start: 50, end: 60 }, { start: 0, end: 10 }]).map((r) => r.last), [0, 1]);
});

test("/releases/latest/<app> goes to the app's latest build, as its updater's feed names it", async () => {
  const h = await harness();
  try {
    assert.equal((await h.fetch("/releases/latest/mac", { redirect: "manual" })).status, 404, "none released yet");
    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: Uint8Array | string): Promise<unknown> };
    await bucket.put("desktop/stillfail-mac.yml", "version: 0.1.1200\nfiles:\n  - url: stillfail-0.1.1200-arm64-mac.zip\n    size: 5\npath: stillfail-0.1.1200-arm64-mac.zip\nsha512: x\n");
    await bucket.put("android/latest.json", JSON.stringify({ versionCode: 1200, file: "android/stillfail-1200.apk" }));
    const mac = await h.fetch("/releases/latest/mac", { redirect: "manual" });
    assert.equal(mac.status, 302);
    assert.equal(new URL(mac.headers.get("location")!, "http://x").pathname, "/releases/desktop/stillfail-0.1.1200-arm64-mac.zip");
    const android = await h.fetch("/releases/latest/android", { redirect: "manual" });
    assert.equal(new URL(android.headers.get("location")!, "http://x").pathname, "/releases/android/stillfail-1200.apk");
    assert.equal((await h.fetch("/releases/latest/windows", { redirect: "manual" })).status, 404);
    assert.equal((await h.fetch("/releases/latest/win", { redirect: "manual" })).status, 404, "no Windows app released yet");
    await bucket.put("desktop/stillfail.yml", "version: 0.1.1200\nfiles:\n  - url: stillfail-0.1.1200-x64-win.exe\n    size: 5\npath: stillfail-0.1.1200-x64-win.exe\nsha512: x\n");
    await bucket.put("desktop/stillfail-beta.yml", "version: 0.1.1201\npath: stillfail-beta-0.1.1201-x64-win.exe\n");
    const win = await h.fetch("/releases/latest/win", { redirect: "manual" });
    assert.equal(new URL(win.headers.get("location")!, "http://x").pathname, "/releases/desktop/stillfail-0.1.1200-x64-win.exe");
    const winBeta = await h.fetch("/releases/latest/win-beta", { redirect: "manual" });
    assert.equal(new URL(winBeta.headers.get("location")!, "http://x").pathname, "/releases/desktop/stillfail-beta-0.1.1201-x64-win.exe");
  } finally {
    await h.close();
  }
});
