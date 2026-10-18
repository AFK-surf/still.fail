// The requests between stations on the platform's bus (src/mesh/bus.ts): each answered by the part that said it
// answers it (a method's name, or a prefix), the rest by what answers the others; another workspace's stations by what
// hears them; a request asked before the transport waits for it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { PeerBus } from "../src/mesh/bus.ts";

const bus = () => new PeerBus({ waitMs: 50, sleep: (ms) => new Promise((r) => setTimeout(r, ms)) });

test("a request goes to the part that answers its method, else its prefix, else the rest", async () => {
  const b = bus();
  b.on("search.query", async (peer, request, ws) => ({ searched: request.query, peer, ws }));
  b.on("share.", async () => "shares");
  b.otherwise(async (_p, request) => ({ task: request.method }));
  // search.query was answered as a task before the bus (2026-10-19): other stations' searches of this one failed.
  assert.deepEqual(await b.handle("w", "p", { method: "search.query", query: "q" }), { searched: "q", peer: "p", ws: "w" });
  assert.equal(await b.handle("w", "p", { method: "share.list" }), "shares");
  assert.deepEqual(await b.handle("w", "p", { method: "task.start" }), { task: "task.start" });
  assert.equal(b.hearsOutside(), false);
  await assert.rejects(b.handleOutside("p", { method: "xshare.read" }), /starting/);
});

test("asked before the transport is there, a request waits for it; not there in time, it says so", async () => {
  const b = bus();
  const asked = b.ask("st", { method: "describe", workspace: "w" });
  let started = false;
  b.whenAttached(() => (started = true));
  b.attach(async (station, workspace, request) => ({ station, workspace, method: request.method }));
  assert.deepEqual(await asked, { station: "st", workspace: "w", method: "describe" });
  assert.equal(started, true);
  await assert.rejects(bus().ask("st", { method: "describe" }), /not ready/);
});
