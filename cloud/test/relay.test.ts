import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { harness } from "./harness.ts";
import { LIMITS } from "../src/limits.ts";
import { relayCounters } from "../src/relay-metrics.ts";
import { relays } from "../src/relays.ts";

const upgrade = { upgrade: "websocket", "sec-websocket-protocol": "iroh-relay" };

test("native relay works without Google configuration or credentials", { timeout: 10000 }, async () => {
  const h = await harness({ noGoogle: true });
  try {
    assert.equal((await h.fetch("/v1/auth/session")).status, 503);
    assert.equal((await h.fetch("/v1/admin/relay/restart", { method: "POST", headers: { authorization: "Bearer " + h.adminToken } })).status, 200);
    assert.equal((await h.fetch("/relay")).status, 426);
    assert.equal((await h.fetch("/relay", { method: "POST" })).status, 405);
    assert.equal((await h.fetchWorker("relay", "https://wrong.example/relay", { headers: upgrade })).status, 421);
    const response = await h.fetch("/relay", { headers: upgrade });
    assert.equal(response.status, 101);
    const socket = response.webSocket!;
    socket.accept();
    const echoed = new Promise<unknown>((resolve) => socket.addEventListener("message", (e) => resolve(e.data), { once: true }));
    socket.send(new Uint8Array([10, 20, 30]));
    assert.deepEqual(new Uint8Array((await echoed) as ArrayBuffer), new Uint8Array([10, 20, 30]));
    socket.close();
  } finally {
    await h.close();
  }
});

test("pending upgrades consume capacity before the backend replies", { timeout: 10000 }, async () => {
  const h = await harness({ noGoogle: true });
  try {
    const relays: any = await h.mf.getDurableObjectNamespace("RELAY", "relay");
    const relay = relays.get(relays.idFromName("primary"));
    // Every upgrade the limit lets through held at the relay, so none has its answer when the last one asks.
    await relay.hold();
    const asked = Array.from({ length: LIMITS.connections + 1 }, () => h.fetch("/relay", { headers: upgrade }));
    await relay.arrived(LIMITS.connections);
    await relay.release();
    const responses = await Promise.all(asked);
    assert.equal(responses.filter((r) => r.status === 101).length, LIMITS.connections);
    assert.equal(responses.filter((r) => r.status === 429).length, 1);
    for (const response of responses) {
      response.webSocket?.accept();
      response.webSocket?.close();
    }
  } finally {
    await h.close();
  }
});

test("closed connections free capacity, counted by the relay process", { timeout: 10000 }, async () => {
  const h = await harness({ noGoogle: true });
  try {
    const sockets: NonNullable<Awaited<ReturnType<typeof h.fetch>>["webSocket"]>[] = [];
    for (let i = 0; i < LIMITS.connections; i++) {
      const response = await h.fetch("/relay", { headers: upgrade });
      assert.equal(response.status, 101);
      response.webSocket!.accept();
      sockets.push(response.webSocket!);
    }
    assert.equal((await h.fetch("/relay", { headers: upgrade })).status, 429);
    const relays: any = await h.mf.getDurableObjectNamespace("RELAY", "relay");
    sockets[0].close();
    // Counted by the relay process once its side has closed too (not 100 ms later, on a guess).
    await relays.get(relays.idFromName("primary")).disconnected(1);
    const response = await h.fetch("/relay", { headers: upgrade });
    assert.equal(response.status, 101);
    response.webSocket!.accept();
    for (const socket of [...sockets.slice(1), response.webSocket!]) socket.close();
  } finally {
    await h.close();
  }
});

test("the relay parses iroh-relay's counters", () => {
  const text = "# HELP x\nrelayserver_bytes_sent_total 10\nrelayserver_bytes_recv_total 5\nrelayserver_send_packets_recv_total 3\nrelayserver_got_ping_total 1\nrelayserver_accepts_total 7\nrelayserver_disconnects_total 2\n";
  assert.deepEqual(relayCounters(text), { bytes: 15, frames: 4, accepts: 7, disconnects: 2 });
});

test("a Worker restart cannot reset the anonymous relay byte budget", { timeout: 10000 }, async () => {
  const persist = await fs.mkdtemp(path.join(os.tmpdir(), "zork-relay-budget-"));
  let h = await harness({ noGoogle: true, persist });
  try {
    const budgets: any = await h.mf.getDurableObjectNamespace("RELAY_BUDGET", "relay");
    await budgets.get(budgets.idFromName("primary")).exhaustBudget();
    await h.close();
    h = await harness({ noGoogle: true, persist });
    assert.equal((await h.fetch("/relay", { headers: upgrade })).status, 429);
  } finally {
    await h.close();
    await fs.rm(persist, { recursive: true, force: true });
  }
});

test("the relays handed out: still.fail's first, then RELAY_URLS, each once", () => {
  const env = { PUBLIC_ORIGIN: "https://app.still.fail" };
  assert.deepEqual(relays(env), { relay_url: "https://app.still.fail", relay_urls: ["https://app.still.fail"], relay_names: {} });
  assert.deepEqual(relays({ ...env, RELAY_URLS: " https://39.105.157.122 ,,https://app.still.fail" }), { relay_url: "https://app.still.fail", relay_urls: ["https://app.still.fail", "https://39.105.157.122"], relay_names: {} });
  assert.deepEqual(relays({ ...env, RELAY_URL: "https://relay.example" }).relay_urls, ["https://relay.example"]);
  // The entries: for a device, after the relays; never for a station.
  const entered = { ...env, RELAY_URLS: "https://39.105.157.122", RELAY_ENTRIES: "https://39.105.157.122:8443, https://39.105.157.122" };
  assert.deepEqual(relays(entered).relay_urls, ["https://app.still.fail", "https://39.105.157.122"]);
  assert.deepEqual(relays(entered, true).relay_urls, ["https://app.still.fail", "https://39.105.157.122", "https://39.105.157.122:8443"]);
  // Named as RELAY_NAMES says, only those handed out.
  const named = { ...env, RELAY_URLS: "https://39.105.157.122", RELAY_NAMES: { "https://39.105.157.122": "北京", "https://gone.example": "旧的" } };
  assert.deepEqual(relays(named).relay_names, { "https://39.105.157.122": "北京" });
});
