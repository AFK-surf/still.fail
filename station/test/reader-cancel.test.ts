import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { ALPN, Reader, serve, writeLine } from "../src/mesh/serve.ts";
import { GrantKey } from "./fake-control-plane.ts";
import { memoryMesh } from "./memory-mesh.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const viewer = { sub: "u", email: "u@x", name: "U", role: "owner", workspace: WS, device: "d" };

test("a cancelled batch is not kept as a successful answer to the same key", async () => {
  const seen: (AbortSignal | undefined)[] = [];
  const readers = { data: "", names: new Map(), read: async (_op: string, _args: unknown, _lang: string, options: { signal?: AbortSignal }) => {
    seen.push(options.signal);
    return "{}";
  } };
  const admin = new Admin(readers as any);
  const aborted = new AbortController();
  aborted.abort();
  const request = { method: "POST", path: "/batch", query: [], headers: { "idempotency-key": "batch" }, body: Buffer.from('{"gets":["/threads/1/entries"]}'), viewer, lang: "en" as const };
  assert.equal((await admin.handle({ ...request, signal: aborted.signal })).status, 503);
  const next = new AbortController();
  assert.equal((await admin.handle({ ...request, signal: next.signal })).status, 200);
  assert.deepEqual(seen, [next.signal], "the retry reads and carries its own cancellation signal");
});

for (const batch of [false, true]) test(`a device abandoning ${batch ? "a batch" : "a read"} cancels its pending reader`, async (t) => {
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [at, device] = await Promise.all([bind(), bind()]);
  const data = mkdtempSync(join(tmpdir(), "mesh-reader-cancel-"));
  const grant = new GrantKey("k1");
  writeState(data, { origin: "o", station: at.id(), workspace: WS, workspace_name: "Team", name: "s0", relay_url: "", relay_urls: [], grant_keys: { keys: [grant.jwk] }, peers: [], revocations: [] });
  const cloud = new Cloud(data);
  let begin!: (signal: AbortSignal | undefined) => void;
  const begun = new Promise<AbortSignal | undefined>((resolve) => { begin = resolve; });
  let release!: () => void;
  const released = new Promise<void>((resolve) => { release = resolve; });
  const readers = { data, names: new Map(), read: async (_op: string, _args: unknown, _lang: string, options: { signal?: AbortSignal }) => {
    begin(options.signal);
    await released;
    return "{}";
  } };
  const admin = new Admin(readers as any);
  t.after(async () => {
    release();
    cloud.close();
    await Promise.all([at.close(), device.close()]);
    rmSync(data, { recursive: true, force: true });
  });
  void (async () => {
    for (;;) {
      const conn = await at.accept();
      if (!conn) return;
      void serve({ cloud, admin, up: () => true }, conn).catch(() => {});
    }
  })();
  const conn = await device.connect({ id: at.id() }, ALPN);
  const now = Math.floor(Date.now() / 1000);
  const credential = grant.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub: "usr_a", email: "a@x", name: "a", ws: WS, role: "owner", device: device.id(), sid: "s", iat: now, exp: now + 3600 });
  const first = await conn.openBi();
  await writeLine(first, { credential, protocol: 2 });
  assert.equal((await new Reader(first).line()).ok, true);
  const stream = await conn.openBi();
  await writeLine(stream, { method: batch ? "POST" : "GET", path: batch ? "/admin/api/batch" : "/admin/api/chats", headers: {} });
  if (batch) await stream.write(Buffer.from('{"gets":["/threads/1/entries"]}'));
  await stream.finish();
  const signal = await begun;
  await stream.reset(0);
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(signal?.aborted, true);
});
