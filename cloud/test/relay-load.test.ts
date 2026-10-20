import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";
import { LIMITS } from "../src/limits.ts";
import { relayLoad, type Load } from "../src/relay-metrics.ts";
import { relayLoadView, type Sample } from "../src/relay-load-view.ts";

const METRICS = [
  "# HELP relayserver_bytes_sent_total x",
  "relayserver_bytes_sent_total 1000",
  "relayserver_bytes_recv_total 2000",
  "relayserver_send_packets_sent_total 90",
  "relayserver_send_packets_recv_total 95",
  "relayserver_send_packets_dropped_total 10",
  "relayserver_accepts_total 7",
  "relayserver_disconnects_total 2",
].join("\n");

const load = (l: Partial<Load>): Load => ({ sent: 0, recv: 0, frames: 0, packets: 0, dropped: 0, accepts: 0, disconnects: 0, ...l });

test("a relay's load is read from iroh-relay's metrics and the lines relay-load.sh adds", () => {
  assert.deepEqual(relayLoad(METRICS), { sent: 1000, recv: 2000, frames: 185, packets: 90, dropped: 10, accepts: 7, disconnects: 2 });
  assert.deepEqual(relayLoad(`${METRICS}\nnode_rx 500\nnode_tx 600\nnode_load1 0.25\n`), { sent: 1000, recv: 2000, frames: 185, packets: 90, dropped: 10, accepts: 7, disconnects: 2, rx: 500, tx: 600, load1: 0.25 });
  assert.deepEqual(relayLoad(""), load({}));
});

test("rates come from what the counters grew by, a restart counting from zero and a gap counting nothing", () => {
  const day = 1_800_000_000 - (1_800_000_000 % 86_400);
  const now = day + 3600;
  const samples: Sample[] = [
    // Yesterday, then today: what grew across midnight is today's.
    { at: day - 60, load: load({ sent: 0, recv: 0, frames: 0 }) },
    { at: day + 60, load: load({ sent: 6_000, recv: 6_000, frames: 10 }) },
    // A gap of an hour: no rate, but its traffic is today's.
    { at: now - 240, load: load({ sent: 66_000, recv: 6_000, frames: 20, packets: 100, dropped: 0, accepts: 5, disconnects: 1 }) },
    { at: now - 180, load: load({ sent: 72_000, recv: 12_000, frames: 30, packets: 190, dropped: 10, accepts: 6, disconnects: 1 }) },
    // Restarted: from zero again.
    { at: now - 120, load: load({ sent: 6_000, recv: 6_000, frames: 5, packets: 90, dropped: 5, accepts: 1, disconnects: 0 }) },
    { at: now - 60, load: load({ sent: 12_000, recv: 12_000, frames: 10, packets: 180, dropped: 20, accepts: 3, disconnects: 1, rx: 100, tx: 100 }) },
  ];
  const view = relayLoadView("https://r.example", samples, now);
  assert.equal(view.at, now - 60);
  assert.equal(view.open, 2);
  // 6000 + 6000 + 6000 bytes sent over 180 s.
  assert.deepEqual(view.now, { sent: 100, recv: 100, dropped: 30 / 300, rx: null, tx: null });
  assert.deepEqual(view.today, { bytes: 12_000 + 60_000 + 12_000 + 12_000 + 12_000, frames: 10 + 10 + 10 + 5 + 5 });
  // The last three steps fall in the five minutes before the hour.
  const last = view.day.sent.length - 1;
  assert.equal(view.day.step, 300);
  assert.equal(view.day.sent.length, 288);
  assert.equal(view.day.start + last * 300, now);
  assert.equal(view.day.sent[last], null);
  assert.equal(view.day.sent[last - 1], Math.round(18_000 / 180));
  // The most it held in those five minutes.
  assert.equal(view.day.open[last - 1], 5);
  assert.equal(view.day.dropped[last - 1], 30 / 300);
  // The step across the gap made no rate.
  assert.equal(view.day.sent.filter((v) => v !== null).length, 2);
  assert.equal(view.week.sent.length, 168);
});

test("a relay sampled long ago has no rate now", () => {
  const now = 1_800_000_000;
  const view = relayLoadView("https://r.example", [{ at: now - 3600, load: load({ accepts: 3 }) }, { at: now - 3540, load: load({ accepts: 4, sent: 600 }) }], now);
  assert.equal(view.now, null);
  assert.equal(view.open, null);
  assert.equal(relayLoadView("https://r.example", [], now).at, null);
});

test("relays send their load with their token; the console shows each relay's", async () => {
  const h = await harness();
  try {
    const push = (token: string, relay: string, body = METRICS) => h.fetch("/v1/relays/load", { method: "POST", headers: { authorization: `Bearer ${token}`, "x-stillfail-relay": relay }, body });
    assert.equal((await push("wrong".repeat(10), h.origin)).status, 401);
    assert.equal((await push(h.adminToken, h.origin)).status, 401);
    assert.equal((await push(h.relayLoadToken, "https://elsewhere.example")).status, 400);
    assert.equal((await push(h.relayLoadToken, h.origin, "x".repeat(300 * 1024))).status, 413);
    assert.equal((await push(h.relayLoadToken, `${h.origin}/`)).status, 200);
    const admin = h.as(await h.login("alice"), "admin");
    const answer = await (await admin("GET", "/v1/admin/relays")).json() as { relays: { url: string; name: string; at: number; open: number; limits?: unknown }[] };
    assert.equal(answer.relays.length, 1);
    const [relay] = answer.relays;
    assert.equal(relay!.url, h.origin);
    assert.equal(relay!.name, new URL(h.origin).host);
    assert.equal(relay!.at, h.now());
    assert.equal(relay!.open, 5);
    assert.deepEqual(relay!.limits, { bytes: LIMITS.bytesPerDay, frames: LIMITS.framesPerDay });
    assert.equal((await h.as(await h.login("bob"), "admin")("GET", "/v1/admin/relays")).status, 404);
  } finally {
    await h.close();
  }
});

test("the cron reads still.fail's own relay's counters", async () => {
  const h = await harness();
  try {
    const api = (await h.mf.getWorker("api")) as unknown as { scheduled(options: { cron: string }): Promise<{ outcome: string }> };
    assert.equal((await api.scheduled({ cron: "* * * * *" })).outcome, "ok");
    const admin = h.as(await h.login("alice"), "admin");
    const answer = await (await admin("GET", "/v1/admin/relays")).json() as { relays: { at: number | null; open: number | null }[] };
    assert.equal(answer.relays[0]!.at, h.now());
    assert.equal(answer.relays[0]!.open, 0);
  } finally {
    await h.close();
  }
});
