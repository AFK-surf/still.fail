// What a station said beyond the database's tables (station/memory.ts): kept with them, so what a page showed shows
// again as the app opens again, before any network; read again once a run; written at most once a KEEP_MS a key.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { type Topic, topicKey } from "../src/protocol.ts";
import { LOGS_KEPT, logKey } from "../src/station/link.ts";
import { KEEP_MS, type Keeper, Memory } from "../src/station/memory.ts";
import { HostWire, type LinkNet } from "../src/station/wire.ts";
import { FakeHost } from "../src/testing.ts";
import { apply, readsOf, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, started, stationReplies } from "./station-fixture.ts";

const S = "ws/st";
const job = { id: "j1", session: "k1", name: "watch", state: "running", port: 4817, startedAt: 1, command: "watch" };
const login = { id: "l0", name: "npm", command: ["npm", "login"], state: "done", waiting: false, by: { email: "a@x.com", name: "A" }, startedAt: 1, expiresAt: 2, endedAt: 3 };
const reading: LinkNet = { path: "relay", relay: "relay.test", rttMs: 40, measured: null, today: null, rxBytes: 1000, txBytes: 500, packets: null };

function answers() {
  return {
    ...base(),
    "GET /jobs": [job],
    "GET /jobs/j1/log?lines=300": { text: "one\ntwo\n", outputAt: 1 },
    "GET /machine-logins": { logins: [login] },
    "GET /screens": { screens: [{ id: "desktop", kind: "desktop", title: "桌面", width: 3024, height: 1964, viewers: [] }] },
    "GET /resources": { processes: [], at: 1 },
    "GET /drive/transfers": { transfers: [{ id: "t1", state: "done", names: ["a"], files: 1, createdAt: 1 }] },
  };
}

const TOPICS: Topic[] = [
  { topic: "machineLogins", station: S },
  { topic: "screens", station: S },
  { topic: "jobLog", station: S, job: "j1", lines: 300 },
  { topic: "stationResources", station: S },
  { topic: "driveTransfers", workspace: "ws" },
  { topic: "net", station: S },
  { topic: "host", station: S },
];

/// Each topic's value after `ms`, from a UI subscribing to all of them.
async function shown(core: Core, host: FakeHost, ms: number): Promise<Map<number, unknown>> {
  const ui = core.connect();
  TOPICS.forEach((topic, i) => subscribe(core, ui, i + 1, topic));
  await host.time.pass(ms, 10);
  const values = new Map<number, unknown>();
  apply(host, values);
  return values;
}

const wired = (net: () => LinkNet | null) => (h: FakeHost) => Object.assign(new HostWire(h), { net: (_: unknown) => net() });

test("what_a_station_said_beyond_the_tables_shows_after_a_restart_before_any_network", async () => {
  let net: LinkNet | null = reading;
  const first = await started(answers(), 0, wired(() => net));
  const values = await shown(first.core, first.host, 3_000);
  first.push("host", { identity: "studio", os: "macOS", cpus: 12 });
  await first.host.time.pass(KEEP_MS + 1_000, 1_000);
  apply(first.host, values);
  assert.equal(v(values, 1).logins.length, 1);
  assert.equal(v(values, 2).screens.length, 1);
  assert.equal(v(values, 3).text, "one\ntwo\n");
  assert.deepEqual(v(values, 5).transfers.map((t: { id: string }) => t.id), ["t1"]);
  assert.equal(v(values, 6).rttMs, 40);
  assert.equal((first.core.inner.stations.link(S)?.memory.get("host") as { identity?: string } | undefined)?.identity, "studio");
  await run(first.core.inner.data.written);
  first.core.close();
  // Opened again, nothing answering yet: each shows as it was.
  const host = first.host;
  net = null;
  host.onFetch(() => new Promise(() => {}));
  host.onFetchStream(() => Effect.never);
  host.takeEmitted();
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => wired(() => net)(host) });
  const again = await shown(core, host, 300);
  assert.equal(v(again, 1).loaded, true);
  assert.deepEqual(v(again, 1).logins.map((l: { id: string }) => l.id), ["l0"]);
  assert.equal(v(again, 2).known, true);
  assert.deepEqual(v(again, 2).screens.map((s: { id: string }) => s.id), ["desktop"]);
  assert.equal(v(again, 3).text, "one\ntwo\n");
  assert.notEqual(v(again, 4), undefined);
  assert.deepEqual(v(again, 5).transfers.map((t: { id: string }) => t.id), ["t1"]);
  assert.equal(v(again, 6).rttMs, 40, "how it was reached last, until it is reached anew");
  assert.equal((core.inner.stations.link(S)?.memory.get("host") as { identity?: string } | undefined)?.identity, "studio");
  core.close();
});

test("a_job_log_kept_is_read_again_once_a_run_and_what_is_live_only_is_not_kept", async () => {
  const said = answers();
  const first = await started(said);
  stationReplies(first.host, (req) => (req.url.includes("/admin/api/search?") ? { results: [] } : undefined));
  const ui = first.core.connect();
  const search: Topic = { topic: "stationSearch", station: S, q: "x" };
  subscribe(first.core, ui, 1, { topic: "jobLog", station: S, job: "j1", lines: 300 });
  subscribe(first.core, ui, 2, search);
  await first.host.time.pass(KEEP_MS + 1_000, 1_000);
  const data = first.core.inner.data;
  assert.deepEqual(data.stationMemory(S, logKey("j1", 300)), { text: "one\ntwo\n", outputAt: 1 });
  assert.notEqual(first.core.inner.stations.link(S)?.memory.get(topicKey(search)), undefined, "what the search found is shown");
  assert.equal(data.stationMemory(S, topicKey(search)), undefined, "and not kept");
  await run(data.written);
  first.core.close();
  // Opened again: shown as kept, read again, and what the station says now in its place.
  const host = first.host;
  said["GET /jobs/j1/log?lines=300"] = { text: "one\ntwo\nthree\n", outputAt: 2 };
  const reads = () => host.requests.flatMap(readsOf).filter((u) => u.endsWith("/jobs/j1/log?lines=300")).length;
  const before = reads();
  host.takeEmitted();
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui2 = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui2, 1, { topic: "jobLog", station: S, job: "j1", lines: 300 });
  await host.time.pass(2_000, 50);
  apply(host, values);
  assert.equal(v(values, 1).text, "one\ntwo\nthree\n");
  assert.equal(reads(), before + 1);
  core.close();
});

/// A keeper over a map, its clock moved by hand.
function keeper() {
  const kept = new Map<string, unknown>();
  const writes: [string, unknown][] = [];
  const timers: [number, () => void][] = [];
  let now = 0;
  const k: Keeper = {
    read: (key) => kept.get(key),
    write: (key, value) => {
      writes.push([key, value]);
      if (value === undefined) kept.delete(key);
      else kept.set(key, value);
    },
    bound: (prefix, most) => {
      const of = [...kept.keys()].filter((key) => key.startsWith(prefix));
      for (const key of of.slice(0, Math.max(0, of.length - most))) kept.delete(key);
    },
    now: () => now,
    later: (ms, run) => void timers.push([now + ms, run]),
  };
  const pass = (ms: number) => {
    now += ms;
    for (const t of timers.splice(0).sort((a, b) => a[0] - b[0])) {
      if (t[0] <= now) t[1]();
      else timers.push(t);
    }
  };
  return { k, kept, writes, pass };
}

test("a_key_is_written_as_it_changes_at_most_once_a_while_its_latest_once_the_while_is_over", () => {
  const { k, kept, writes, pass } = keeper();
  const m = new Memory(k);
  m.set("host", 1);
  m.set("host", 2);
  m.set("host", 3);
  assert.deepEqual(writes, [["host", 1]], "the first at once, the rest wait");
  pass(KEEP_MS);
  assert.deepEqual(writes, [["host", 1], ["host", 3]], "the latest, once the while is over");
  assert.equal(kept.get("host"), 3);
  m.hold("screen", { rows: [] });
  pass(KEEP_MS * 2);
  assert.equal(kept.has("screen"), false, "what is live only is not kept");
  m.delete("host");
  assert.equal(kept.has("host"), false);
});

test("what_was_kept_is_read_as_asked_for_and_is_not_fresh_until_the_station_says_it", () => {
  const { k, kept } = keeper();
  kept.set("machineLogins", { supported: true, logins: [] });
  const m = new Memory(k);
  assert.deepEqual(m.get("machineLogins"), { supported: true, logins: [] });
  assert.equal(m.fresh("machineLogins"), false);
  m.set("machineLogins", { supported: true, logins: [login] });
  assert.equal(m.fresh("machineLogins"), true);
  assert.equal(m.has("nothing"), false);
});

test("job_logs_kept_are_the_latest_opened_at_most", () => {
  const { k, kept } = keeper();
  const m = new Memory(k, [["jobLog\n", LOGS_KEPT]]);
  for (let i = 0; i < LOGS_KEPT + 5; i++) m.set(logKey(`j${i}`, 300), { text: `${i}`, outputAt: i });
  const logs = [...kept.keys()].filter((key) => key.startsWith("jobLog\n"));
  assert.equal(logs.length, LOGS_KEPT);
  assert.ok(logs.includes(logKey(`j${LOGS_KEPT + 4}`, 300)));
  assert.ok(!logs.includes(logKey("j0", 300)));
});
