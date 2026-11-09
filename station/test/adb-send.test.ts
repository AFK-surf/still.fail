import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fetchOnPhone, staged } from "../src/adb/send.ts";
import type { Connection, Stream } from "../src/mesh/native.ts";

test("a file sent to a phone is put in the session's uploads under a name of its content, once", async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-send-"));
  try {
    writeFileSync(join(dir, "app.apk"), "apk bytes");
    const first = await staged(dir, "app.apk");
    assert.match(first.name, /^[0-9a-f]{16}-app\.apk$/);
    assert.equal(first.size, 9);
    assert.equal(readFileSync(join(dir, "uploads", first.name), "utf8"), "apk bytes");
    const copied = statSync(join(dir, "uploads", first.name)).mtimeMs;
    assert.deepEqual(await staged(dir, join(dir, "app.apk")), first);
    assert.equal(statSync(join(dir, "uploads", first.name)).mtimeMs, copied);
    writeFileSync(join(dir, "app.apk"), "other bytes");
    assert.notEqual((await staged(dir, "app.apk")).name, first.name);
    await assert.rejects(staged(dir, "none.apk"), /no such file/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

/// A connection whose one stream the phone answers with `lines`, keeping what the station wrote.
function phone(lines: unknown[]): { conn: Connection; wrote: Buffer[] } {
  const wrote: Buffer[] = [];
  const out = lines.map((l) => Buffer.from(`${JSON.stringify(l)}\n`));
  const stream: Stream = {
    read: async () => out.shift() ?? null,
    write: async (b) => void wrote.push(b),
    finish: async () => {},
    stopped: async () => null,
    reset: async () => {},
  };
  return { conn: { openBi: async () => stream } as unknown as Connection, wrote };
}

test("the phone is asked to fetch the upload, and what it says comes back", async () => {
  const done = phone([{ at: 4 }, { at: 9 }, { path: "/sdcard/x/app.apk" }]);
  const heard: number[] = [];
  assert.deepEqual(await fetchOnPhone(done.conn, "k1", "ab-app.apk", 9, (at) => heard.push(at)), { path: "/sdcard/x/app.apk" });
  assert.deepEqual(JSON.parse(Buffer.concat(done.wrote).toString()), { fetch: { key: "k1", name: "ab-app.apk", size: 9 } });
  assert.deepEqual(heard, [4, 9]);
  assert.deepEqual(await fetchOnPhone(phone([{ at: 4 }, { error: "the link went", at: 4 }]).conn, "k1", "n", 9), { error: "the link went", at: 4, old: false });
  assert.deepEqual(await fetchOnPhone(phone([{ at: 4 }]).conn, "k1", "n", 9), { error: "the phone ended the fetch", at: 4, old: false });
  // An app from before fetches turns the stream down as a tunnel it does not know.
  assert.deepEqual(await fetchOnPhone(phone([{ error: "无法识别的通道" }]).conn, "k1", "n", 9), { error: "无法识别的通道", at: 0, old: true });
});
