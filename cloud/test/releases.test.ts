import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";
import { releaseType, sharedRelease } from "../src/install.ts";
import { VERSIONED, groupReads, parseRanges } from "../src/releases.ts";

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

test("a face's files: a page's stylesheet and slices, the Android app's file, cached for good and fetched from any origin", async () => {
  const h = await harness();
  try {
    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: Uint8Array | string): Promise<unknown> };
    await bucket.put("fonts/noto-sans-sc/2.004/font.css", "@font-face{}");
    await bucket.put("fonts/noto-sans-sc/2.004/var-12.woff2", new Uint8Array([1, 2, 3]));
    await bucket.put("fonts/lxgw-wenkai/1.530/400.ttf.gz", new Uint8Array([4, 5]));
    await bucket.put("fonts/lxgw-wenkai/1.530/preview-0a1b2c3d.ttf", new Uint8Array([6]));
    for (const [path, type] of [["fonts/noto-sans-sc/2.004/font.css", "text/css; charset=utf-8"], ["fonts/noto-sans-sc/2.004/var-12.woff2", "font/woff2"], ["fonts/lxgw-wenkai/1.530/400.ttf.gz", "application/gzip"], ["fonts/lxgw-wenkai/1.530/preview-0a1b2c3d.ttf", "font/ttf"]] as const) {
      const got = await h.fetch(`/releases/${path}`);
      assert.equal(got.status, 200, path);
      assert.equal(got.headers.get("content-type"), type);
      assert.equal(got.headers.get("cache-control"), "public, max-age=31536000, immutable");
      assert.equal(got.headers.get("access-control-allow-origin"), "*");
      await got.arrayBuffer();
    }
    for (const path of ["fonts/noto-sans-sc/font.css", "fonts/noto-sans-sc/2.004/../x.css", "fonts/Noto/2.004/font.css", "fonts/noto-sans-sc/2.004/font.js", "fonts/noto-sans-sc/2.004/preview.ttf"]) {
      const got = await h.fetch(`/releases/${path}`);
      assert.equal(got.status, 404, path);
      await got.arrayBuffer();
    }
    // Only a face's files are for any origin.
    assert.equal((await h.fetch("/releases/station.json")).headers.get("access-control-allow-origin"), null);
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
    await bucket.put("mac/latest.json", JSON.stringify({ versionCode: 1200, file: "desktop/stillfail-0.1.1200-arm64-mac.zip" }));
    await bucket.put("android/latest.json", JSON.stringify({ versionCode: 1200, file: "android/stillfail-1200.apk" }));
    const mac = await h.fetch("/releases/latest/mac", { redirect: "manual" });
    assert.equal(mac.status, 302);
    assert.equal(new URL(mac.headers.get("location")!, "http://x").pathname, "/releases/desktop/stillfail-0.1.1200-arm64-mac.zip");
    const android = await h.fetch("/releases/latest/android", { redirect: "manual" });
    assert.equal(new URL(android.headers.get("location")!, "http://x").pathname, "/releases/android/stillfail-1200.apk");
    assert.equal((await h.fetch("/releases/latest/windows", { redirect: "manual" })).status, 404);
    assert.equal((await h.fetch("/releases/latest/win", { redirect: "manual" })).status, 404, "no Windows app released yet");
    await bucket.put("win/latest.json", JSON.stringify({ versionCode: 1200, file: "desktop/stillfail-0.1.1200-x64-win.exe" }));
    await bucket.put("win/beta/latest.json", JSON.stringify({ versionCode: 1201, file: "desktop/stillfail-beta-0.1.1201-x64-win.exe" }));
    const win = await h.fetch("/releases/latest/win", { redirect: "manual" });
    assert.equal(new URL(win.headers.get("location")!, "http://x").pathname, "/releases/desktop/stillfail-0.1.1200-x64-win.exe");
    const winBeta = await h.fetch("/releases/latest/win-beta", { redirect: "manual" });
    assert.equal(new URL(winBeta.headers.get("location")!, "http://x").pathname, "/releases/desktop/stillfail-beta-0.1.1201-x64-win.exe");
  } finally {
    await h.close();
  }
});

test("a cloud of its own reads the station's releases from still.fail's when its bucket has none, never an app's", async () => {
  const asked: string[] = [];
  const h = await harness({
    upstream: (file, request): { status: number; body?: string; headers?: Record<string, string> } => {
      asked.push(`${file} ${request.headers.range ?? ""}`.trim());
      if (file === "station.json") return { status: 200, body: '{"version":"0.1.9"}', headers: { "content-type": "application/json" } };
      if (file === "stillfail-station-linux-x64.tar.gz") return { status: 206, body: "tion", headers: { "content-range": "bytes 3-6/10", "content-type": "application/gzip" } };
      return { status: 404 };
    },
  });
  try {
    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: string): Promise<unknown> };
    await bucket.put("fonts/noto-sans-sc/2.004/font.css", "/* own */");

    const feed = await h.fetch("/releases/station.json");
    assert.equal(feed.status, 200);
    assert.equal(await feed.text(), '{"version":"0.1.9"}');
    const part = await h.fetch("/releases/stillfail-station-linux-x64.tar.gz", { headers: { range: "bytes=3-6" } });
    assert.equal(part.status, 206);
    assert.equal(part.headers.get("content-range"), "bytes 3-6/10");
    assert.equal(await part.text(), "tion");
    // its own bucket's first
    assert.equal(await (await h.fetch("/releases/fonts/noto-sans-sc/2.004/font.css")).text(), "/* own */");
    // none there either: none
    assert.equal((await h.fetch("/releases/station-beta.json")).status, 404);
    // an app's feed is its own alone, even when it has none
    assert.equal((await h.fetch("/releases/android/latest.json")).status, 404);
    assert.deepEqual(asked, ["station.json", "stillfail-station-linux-x64.tar.gz bytes=3-6", "station-beta.json"]);
  } finally {
    await h.close();
  }
});

// A release's deltas (scripts/release-deltas.ts), the Windows installer's raw form and the station's archives kept under
// names of their own: served by those names alone, each with its type, cached for good (named by version or content).
test("the deltas, raw installers and kept station archives are served by their names, for good", () => {
  const sha = "0123456789abcdef".repeat(4);
  const served: [string, string][] = [
    ["desktop/stillfail-beta-0.1.8147-arm64-mac.zip.from-8142.delta", "application/octet-stream"],
    ["desktop/stillfail-0.1.8147-x64-win.exe.from-8146.delta", "application/octet-stream"],
    ["desktop/monoid-beta-0.1.8147-x64-win.exe.raw.zst", "application/zstd"],
    ["android/stillfail-beta-8147.apk.from-8146.delta", "application/octet-stream"],
    ["win/stillfail-mbui-8147-x64-win.exe.from-8146.delta", "application/octet-stream"],
    ["win/stillfail-mbui-8147-x64-win.exe.raw.zst", "application/zstd"],
    ["linux/stillfail-mbui-8147-arm64-linux.tar.gz.from-8146.delta", "application/octet-stream"],
    [`station/archive/beta/8164-${sha}-linux-x64.tar.gz`, "application/gzip"],
    [`station/archive/stable/8100-${sha}-win32-x64.zip`, "application/zip"],
    [`station/archive/beta/8164-${sha}-darwin-arm64.from-8163-${sha.slice(0, 16)}.delta`, "application/octet-stream"],
  ];
  for (const [file, type] of served) {
    assert.equal(releaseType(file), type, file);
    assert.ok(VERSIONED.test(file), `${file}: cached for good`);
  }
  // still.fail's stations' files: another cloud's (monoid's) reads them from still.fail's, its apps' never
  assert.ok(sharedRelease(`station/archive/beta/8164-${sha}-linux-x64.tar.gz`));
  assert.ok(!sharedRelease("desktop/monoid-beta-0.1.8147-x64-win.exe.raw.zst"));
  for (const file of [
    "desktop/stillfail-beta-0.1.8147-arm64-mac.zip.from-x.delta",
    "desktop/stillfail-beta-0.1.8147-arm64-mac.zip.raw.zst",
    "android/stillfail-beta-8147.apk.from-8146.delta.sig",
    "win/stillfail-mbui-8147-x64-win.exe.sig",
    "linux/stillfail-mbui-8147-x64-linux.tar.gz.raw.zst",
    `station/archive/beta/8164-${sha.slice(1)}-linux-x64.tar.gz`,
    `station/archive/nightly/8164-${sha}-linux-x64.tar.gz`,
    `station/archive/beta/8164-${sha}-linux-x64.zip`,
    `station/archive/beta/8164-${sha}-linux-x64.from-8163.delta`,
    `station/archive/beta/../8164-${sha}-linux-x64.tar.gz`,
    `station/8164-${sha}-linux-x64.tar.gz`,
  ]) assert.equal(releaseType(file), null, file);
  // what changes stays uncached
  for (const file of ["station-beta.json", "mac/beta/latest.json", "beta/stillfail-station-linux-x64.tar.gz"]) assert.ok(!VERSIONED.test(file), file);
});
