// An endpoint on a device taking connections (iroh.ts, `accept`): bound to take an ALPN, another endpoint connects to
// it on that one, and it has the connection with the ALPN agreed and who opened it; a stream both ways goes over it,
// and closing the endpoint answers the accept waiting with null. Over Node's addon (hosts/node-iroh.ts) and over the
// bridge (hosts/bridge.ts, its shell here in JavaScript as node-shell.ts), relays off, on this machine; the browser's
// binding, which takes none, has no `accept`.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Bridge, bridgeIroh } from "../src/hosts/bridge.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import type { Iroh, IrohStream } from "../src/iroh.ts";
import { type BoundEndpoint, wrapIroh } from "../src/iroh-bindings.ts";
import { NodeShell } from "./node-shell.ts";
import { run } from "./run.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const utf8 = (s: string) => new TextEncoder().encode(s);
const text = (b: Uint8Array) => new TextDecoder().decode(b);
const skip = loadAddon() === null ? "the mesh addon is not built here" : false;

async function readAll(stream: IrohStream): Promise<string> {
  let all = "";
  for (;;) {
    const chunk = await run(stream.read());
    if (chunk === null) return all;
    all += text(chunk);
  }
}

/// Where an endpoint of the addon listens, on this machine.
function loopback(endpoint: J): string[] {
  const socket = (endpoint.sockets() as string[]).find((s) => !s.startsWith("["));
  assert.ok(socket, "it listens on IPv4");
  return [`127.0.0.1:${socket.slice(socket.lastIndexOf(":") + 1)}`];
}

/// `iroh` binds both ends; `bound(i)`: the addon's endpoint the `i`th bind made.
async function acceptsOver(iroh: Iroh, bound: (i: number) => J) {
  const a = await run(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false }));
  const b = await run(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false, alpns: [utf8("test/1")] }));
  assert.equal(typeof b.accept, "function");
  a.addAddr({ id: b.id(), ips: loopback(bound(1)) });
  const coming = run(b.accept!());
  const out = await run(a.connect({ id: b.id() }, utf8("test/1"), []));
  assert.equal(out.remoteId(), b.id());
  const taken = await coming;
  assert.ok(taken !== null);
  assert.equal(text(taken.alpn), "test/1");
  assert.equal(taken.connection.remoteId(), a.id());

  const ask = await run(out.openBi());
  await run(ask.write(utf8("hello\n")));
  await run(ask.finish());
  const asked = await run(taken.connection.acceptBi());
  assert.ok(asked !== null);
  const line = await readAll(asked);
  assert.equal(line, "hello\n");
  await run(asked.write(utf8(`echo ${line}`)));
  await run(asked.finish());
  assert.equal(await readAll(ask), "echo hello\n");

  out.close(0, "done");
  const waiting = run(b.accept!());
  await run(b.close());
  assert.equal(await waiting, null);
  await run(a.close());
}

test("the Node host's endpoint takes a connection on its ALPN", { skip }, async () => {
  const addon = loadAddon() as J;
  const seen: J[] = [];
  const watched = {
    bind: async (o: J) => {
      const e = await addon.bind(o);
      seen.push(e);
      return e;
    },
  };
  await acceptsOver(nodeIroh(watched)!, (i) => seen[i]);
});

test("the bridge's endpoint takes a connection on its ALPN", { skip }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "accept-"));
  const native = new NodeShell(dir);
  const bridge = new Bridge(native);
  native.bridge = bridge;
  await acceptsOver(bridgeIroh(bridge), (i) => native.bound[i]);
  for (const op of ["iroh.bind", "iroh.accept", "iroh.connect"]) assert.ok(native.calls.includes(op), op);
  native.host.close();
  rmSync(dir, { recursive: true, force: true });
});

test("a binding without accept gives an endpoint without it", async () => {
  const none = async () => ({ id: () => "00" }) as unknown as BoundEndpoint;
  const endpoint = await run(wrapIroh(none, (b) => b).bind({ secretKey: new Uint8Array(32), relayUrls: [], lookup: false, relayOnly: false }));
  assert.equal(endpoint.accept, undefined);
  assert.equal("accept" in endpoint, false);
});
