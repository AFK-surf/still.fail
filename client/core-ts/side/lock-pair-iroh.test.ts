// The side run's (not CI's): test/lock-pair.test.ts's trusted device met by a new one over the real thing, two endpoints
// of the native addon (station/native/mesh) on localhost, the trusted one taking the new one as the mesh's does
// (views/pair.ts `served`). What it waits on comes over a real socket, which the core's clock does not see, so it gives
// each step of the clock real time as well and is not the same every run: in CI it failed main fe6d90f2's check-linux
// (43217458770, 2026-11-12) once its steps were taken at once. The exchange, the code and what it signs are
// test/lock-pair.test.ts's, on a stream of its own on the test's clock; a failure here is for an agent to reproduce
// there, or to let be when it can't.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { Effect } from "effect";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import { PAIR_ALPN } from "../src/pair.ts";
import { served, streamDuplex, tryOne } from "../src/views/pair.ts";
import { run as runEffect } from "../test/run.ts";
import { genesis, grant, rig } from "../test/lock-rig.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test("over iroh: the trusted device takes the new one on its endpoint, and the code typed signs it in", { skip: loadAddon() === null ? "the mesh addon is not built here" : false }, async () => {
  const addon = loadAddon() as any;
  const seen: any[] = [];
  const iroh = nodeIroh({ bind: async (o: any) => { const e = await addon.bind(o); seen.push(e); return e; } })!;
  const trustedEnd = await runEffect(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false, alpns: [PAIR_ALPN] }));
  const newEnd = await runEffect(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false }));
  const socket = (seen[0].sockets() as string[]).find((x) => !x.startsWith("["))!;
  newEnd.addAddr({ id: trustedEnd.id(), ips: [`127.0.0.1:${socket.slice(socket.lastIndexOf(":") + 1)}`] });
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, trustedEnd.id()) }));
  r.core.inner.meshNow = () => ({ deviceId: () => trustedEnd.id() }) as never;
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  /// The core's clock 10 ms on, and as long again of real time for what comes over the socket.
  const step = async () => {
    await r.host.time.pass(10);
    await sleep(10);
  };
  // The trusted device's endpoint takes it, as the mesh's does (views/pair.ts `served`).
  void runEffect(trustedEnd.accept!()).then((taken) => taken && served(r.core.inner, taken.connection));
  const connection = await runEffect(newEnd.connect({ id: trustedEnd.id() }, PAIR_ALPN, []));
  const d = streamDuplex(await runEffect(connection.openBi()), () => connection.close(0, "done"));
  await runEffect(d.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", newEnd.id(), "s2") }], kind: "web", label: "Chrome", sign_key: null }));
  const answer = runEffect(d.next());
  for (let i = 0; i < 100 && (await prompts()).pairing.length === 0; i++) await step();
  assert.deepEqual(await answer, { t: "code", workspaces: ["ws"] });
  const code = (await prompts()).pairing[0].code;
  const done: any[] = [];
  r.core.inner.runner.fork(Effect.map(Effect.result(tryOne(r.core.inner, { id: trustedEnd.id(), d, workspaces: ["ws"] }, newEnd.id(), code)), (x) => done.push(x)));
  for (let i = 0; i < 500 && done.length === 0; i++) await step();
  assert.equal(done[0]?._tag, "Success", String(done[0]?.failure?.message));
  const entry = r.cloud.chains.get("ws")!.at(-1)!;
  assert.equal((entry.body as { id: string }).id, newEnd.id());
  assert.equal((entry.body as { kind: string }).kind, "web");
  connection.close(0, "done");
  await runEffect(newEnd.close());
  await runEffect(trustedEnd.close());
});
