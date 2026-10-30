// What the station's log says of a member's connection (src/mesh/serve.ts): as it is admitted and as it ends, both with
// the trace of the device's dial, so the device's `mesh.connect` and the station's lines of the same connection are
// found together (2026-10-30: a phone's handshake with a station went through and nothing came after, and nothing the
// station said could be told apart from its other devices').
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { hearLines, type Line } from "../src/ops/log.ts";
import { ALPN, Reader, serve } from "../src/mesh/serve.ts";
import type { Admin } from "../src/api/admin.ts";
import type { Stream } from "../src/mesh/native.ts";
import { GrantKey } from "./fake-control-plane.ts";
import { memoryMesh } from "./memory-mesh.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const TRACE = "4bf92f3577b34da6a3ce929d0e0e4736";

test("a member's connection is said as it comes and as it ends, with the trace of the device's dial", async (t) => {
  const lines: Line[] = [];
  hearLines((l) => void (l.at === "mesh" && lines.push(l)));
  t.after(() => hearLines(null));
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [at, device] = await Promise.all([bind(), bind()]);
  const data = mkdtempSync(join(tmpdir(), "mesh-lines-"));
  const grant = new GrantKey("k1");
  writeState(data, { origin: "o", station: at.id(), workspace: WS, workspace_name: "Team", name: "s0", relay_url: "", relay_urls: [], grant_keys: { keys: [grant.jwk] }, peers: [], revocations: [] });
  const cloud = new Cloud(data);
  t.after(async () => {
    cloud.close();
    await Promise.all([at.close(), device.close()]);
  });
  void (async () => {
    for (;;) {
      const conn = await at.accept();
      if (!conn) return;
      void serve({ cloud, admin: undefined as unknown as Admin, up: () => true }, conn).catch(() => {});
    }
  })();
  const line = (stream: Stream, value: unknown) => stream.write(Buffer.from(JSON.stringify(value) + "\n"));
  const conn = await device.connect({ id: at.id(), ips: [`127.0.0.1:${at.sockets()[0]!.split(":").at(-1)}`] }, ALPN);
  const now = Math.floor(Date.now() / 1000);
  const credential = grant.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub: "usr_a", email: "a@x", name: "a", ws: WS, role: "owner", device: device.id(), sid: "s", iat: now, exp: now + 3600 });
  const first = await conn.openBi();
  await line(first, { credential, protocol: 2, traceparent: `00-${TRACE}-00f067aa0ba902b7-01` });
  assert.equal((await new Reader(first).line()).ok, true);
  const came = lines.find((l) => l.message === "client connected")!;
  assert.deepEqual([came.fields.device, came.fields.trace, came.fields.via], [device.id().slice(0, 12), TRACE, "direct"]);

  conn.close(0, "gone to the background");
  for (let i = 0; i < 100 && !lines.some((l) => l.message === "a device's connection ended"); i++) await new Promise((r) => setImmediate(r));
  const ended = lines.find((l) => l.message === "a device's connection ended")!;
  assert.deepEqual([ended.fields.device, ended.fields.trace, ended.fields.why], [device.id().slice(0, 12), TRACE, "gone to the background"]);
  assert.equal(typeof ended.fields.lasted, "number");
});
