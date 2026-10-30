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

test("a chart shows each bucket's busiest minute, timed by when the relay read its counters", () => {
  const now = 1_800_000_000 - (1_800_000_000 % 3600);
  const samples: Sample[] = [
    { at: now - 590, load: load({ sent: 0 }) },
    // A burst of a minute, then quiet: the five minutes' average would be a fifth of it.
    { at: now - 530, load: load({ sent: 600_000 }) },
    { at: now - 470, load: load({ sent: 600_000 }) },
    { at: now - 410, load: load({ sent: 600_000 }) },
    { at: now - 350, load: load({ sent: 600_000 }) },
    { at: now - 290, load: load({ sent: 600_000 }) },
    // Read a minute later, but its post took 50 s to arrive: 60 000 bytes in a minute, not in 10 s.
    { at: now - 180, load: load({ sent: 600_000, time: now - 230 }) },
    { at: now - 170, load: load({ sent: 660_000, time: now - 170 }) },
  ];
  const view = relayLoadView("https://r.example", samples, now);
  const day = view.day.sent.length - 1, week = view.week.sent.length - 1;
  assert.equal(view.day.sent[day - 2], 10_000);
  assert.equal(view.day.sent[day - 1], 1_000);
  // The same peak over the week, whose buckets are an hour.
  assert.equal(view.week.sent[week - 1], 10_000);
  assert.equal(relayLoad(`${METRICS}\nnode_time 1800000000\n`).time, 1_800_000_000);
});

test("a relay sampled long ago has no rate now", () => {
  const now = 1_800_000_000;
  const view = relayLoadView("https://r.example", [{ at: now - 3600, load: load({ accepts: 3 }) }, { at: now - 3540, load: load({ accepts: 4, sent: 600 }) }], now);
  assert.equal(view.now, null);
  assert.equal(view.open, null);
  assert.equal(relayLoadView("https://r.example", [], now).at, null);
});

test("relays send their load from their own address; the console shows each relay's", async () => {
  const relay = "https://203.0.113.7";
  const h = await harness({ relayUrls: relay, relayNames: { [relay]: "北京" } });
  try {
    const push = (from: string | null, named: string, body = METRICS) => h.fetch("/v1/relays/load", { method: "POST", headers: { "x-stillfail-relay": named, ...(from ? { "cf-connecting-ip": from } : {}) }, body });
    assert.equal((await push(null, relay)).status, 403);
    assert.equal((await push("198.51.100.1", relay)).status, 403);
    assert.equal((await push("203.0.113.7", "https://elsewhere.example")).status, 400);
    assert.equal((await push("203.0.113.7", relay, "x".repeat(300 * 1024))).status, 413);
    assert.equal((await push("203.0.113.7", `${relay}/`)).status, 200);
    const admin = h.as(await h.login("alice"), "admin");
    const answer = await (await admin("GET", "/v1/admin/relays")).json() as { relays: { url: string; name: string; at: number | null; open: number | null; limits?: unknown }[] };
    assert.deepEqual(answer.relays.map((r) => r.url), [h.origin, relay]);
    const [own, beijing] = answer.relays;
    // still.fail's own, held to its budget, not sampled (no cron ran).
    assert.deepEqual([own!.name, own!.at, own!.limits], [new URL(h.origin).host, null, { bytes: LIMITS.bytesPerDay, frames: LIMITS.framesPerDay }]);
    assert.deepEqual([beijing!.name, beijing!.at, beijing!.open, beijing!.limits], ["北京", h.now(), 5, undefined]);
    assert.equal((await h.as(await h.login("bob"), "admin")("GET", "/v1/admin/relays")).status, 404);
  } finally {
    await h.close();
  }
});

test("what a relay did between two of its samples goes to Axiom as a log line", async () => {
  const relay = "https://203.0.113.7";
  const got: any[] = [];
  const h = await harness({ relayUrls: relay, axiom: async (request) => (got.push({ url: request.url, body: JSON.parse(await request.text()) }), new Response("{}")) });
  try {
    const push = (body: string) => h.fetch("/v1/relays/load", { method: "POST", headers: { "x-stillfail-relay": relay, "cf-connecting-ip": "203.0.113.7" }, body });
    // The first sample has none before it: nothing said.
    assert.equal((await push(`${METRICS}\nnode_time ${h.now() - 60}\n`)).status, 200);
    assert.equal(got.length, 0);
    const later = METRICS.replace("bytes_sent_total 1000", "bytes_sent_total 61000").replace("dropped_total 10", "dropped_total 40").replace("accepts_total 7", "accepts_total 9");
    assert.equal((await push(`${later}\nnode_load1 0.5\nnode_time ${h.now()}\n`)).status, 200);
    assert.equal(got.length, 1);
    assert.equal(got[0].url, "https://api.axiom.co/v1/logs");
    const [resource] = got[0].body.resourceLogs;
    const attrs = (list: any[]) => Object.fromEntries(list.map((a: any) => [a.key, a.value.intValue ?? a.value.doubleValue ?? a.value.stringValue]));
    assert.deepEqual(attrs(resource.resource.attributes), { "service.name": "stillfail-relay", "stillfail.relay": "203.0.113.7" });
    const [line] = resource.scopeLogs[0].logRecords;
    assert.equal(line.body.stringValue, "relay minute");
    assert.deepEqual(attrs(line.attributes), {
      "log.target": "relay", "log.secs": "60", "log.open": "7", "log.accepts": "2", "log.disconnects": "0",
      "log.sent": "60000", "log.recv": "0", "log.packets": "0", "log.dropped": "30", "log.load1": 0.5,
    });
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
