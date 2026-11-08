// The workspace's statistics a Comma connect sends (comma/stats.ts): kept as rows numbered as they change, read of this
// station and the others of its workspace (comma/peer.ts), and sent a page at a time as Comma holds them, against a
// stand-in for Comma's connector socket on a local port. Nothing reaches the real Comma.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { WebSocketServer } from "ws";
import { workspaceRead } from "../src/comma/peer.ts";
import { CommaStats, PAGE_BYTES, PAGE_ROWS, type StationRows, heldFrom, nextPage, probePage } from "../src/comma/stats.ts";
import { CommaSurface } from "../src/comma/surface.ts";
import { CommaTasks } from "../src/comma/tasks.ts";
import { Rig } from "./hub-fakes.ts";

type Json = any;

const dirs: string[] = [];
after(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});
const tempdir = () => {
  const d = mkdtempSync(join(tmpdir(), "comma-stats-"));
  dirs.push(d);
  return d;
};

const DAY = 24 * 60 * 60_000;
const FROM = Date.UTC(2026, 10, 1);
const usageRow = (day: string, session: string, person: string, calls = 1) => ({
  day, session, thread: 7, person, account: "cc", runtime: "claude", model: "claude-opus-5-5", calls, input: 10, cacheRead: 0, cacheWrite: 0, output: 5, cost: 0.01,
});
const chat = (thread: number, state: string) => ({
  thread, surface: "stillfail", title: "Fix the build", state, creator: { ref: "ann@x", name: null, email: "ann@x", via: "cloud" }, createdAt: FROM, lastActiveAt: FROM + 1, archived: false, agents: [{ runtime: "claude", model: null }],
});
const here = (rows: Json[], people: Json = {}, chats: Json[] = []): StationRows => ({ usage: { rows, people }, chats });
const nothing = async () => ({ stations: [], unread: [] });
const quiet = () => () => {};

const rows = (stats: CommaStats) => stats.since(0, 1000).map((r) => ({ kind: r.kind, removed: r.removed, row: r.removed ? null : JSON.parse(r.json) }));

test("the index keeps each station's rows as they changed: a person by their email, a chat by its thread, a row gone tombstoned, an unread station's kept", () => {
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    const people = { "slack:fs:ou_ada": { name: "Ada", email: "ada@x", via: "feishu" }, "slack:fs:ou_bo": { name: "Bo", email: null, via: "feishu" } };
    const first = [
      here([usageRow("2026-11-01", "a", "slack:fs:ou_ada"), usageRow("2026-11-02", "a", "slack:fs:ou_bo")], people, [chat(7, "need_human")]),
      { station: "st-there", ...here([usageRow("2026-11-02", "b", "ann@x")]) },
    ];
    assert.equal(stats.apply(first, [], FROM), 4);
    const kept = rows(stats);
    assert.deepEqual(kept.filter((r) => r.kind === "usage").map((r) => [r.row.person, r.row.personRef, r.row.station ?? null]), [
      ["ada@x", "slack:fs:ou_ada", null], ["Bo", "slack:fs:ou_bo", null], ["ann@x", "ann@x", "st-there"],
    ]);
    assert.deepEqual(kept.filter((r) => r.kind === "task").map((r) => [r.row.thread, r.row.state, r.row.creator]), [[7, "need_human", "ann@x"]]);
    const rev = stats.rev();
    assert.equal(stats.apply(first, [], FROM), 0, "given again unchanged: nothing moves");
    assert.equal(stats.rev(), rev);

    // Bo's day is another's after all, and the other station could not be read this time.
    assert.equal(stats.apply([here([usageRow("2026-11-01", "a", "slack:fs:ou_ada")], people, [chat(7, "all_done")])], ["st-there"], FROM), 2);
    const now = rows(stats);
    assert.equal(now.filter((r) => r.removed).length, 1, "Bo's row is gone");
    assert.ok(now.some((r) => r.row?.station === "st-there"), "the unread station's row stays");
    assert.ok(now.some((r) => r.kind === "task" && r.row.state === "all_done"));
    // A day before the build's span is never tombstoned by it.
    assert.equal(stats.apply([here([], people, [])], [], FROM + 2 * DAY), 0);
  } finally { stats.close(); }
});

test("pages bring Comma from what it holds to the index's rev, at most a page's rows each; tombstones go once every connection holds them", () => {
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    const many = Array.from({ length: PAGE_ROWS + 5 }, (_, i) => usageRow("2026-11-02", `s${i}`, "ann@x"));
    stats.apply([here(many)], [], FROM);
    const probe = probePage(stats);
    assert.deepEqual([probe.rows.length, probe.since, probe.through], [0, stats.rev(), stats.rev()]);
    // A Comma holding nothing of this epoch: all again, from the start, a page within Comma's bounds at a time.
    const first = nextPage(stats, { epoch: null, through: 0 })!;
    assert.deepEqual([first.reset, first.since], [true, 0]);
    let page: ReturnType<typeof nextPage> = first;
    let held = { epoch: first.epoch as string | null, through: 0 };
    let sent = 0;
    while (page !== null) {
      assert.ok(page.rows.length <= PAGE_ROWS && Buffer.byteLength(JSON.stringify(page.rows)) <= PAGE_BYTES);
      assert.equal(page.since, held.through);
      sent += page.rows.length;
      held = { epoch: page.epoch, through: page.through };
      page = nextPage(stats, held);
    }
    assert.deepEqual([sent, held.through], [many.length, stats.rev()]);
    stats.apply([here(many.slice(1))], [], FROM);
    assert.equal(stats.since(0, 1000).filter((r) => r.removed).length, 1);
    stats.held("two", 0);
    stats.held("one", stats.rev());
    assert.equal(stats.since(0, 1000).filter((r) => r.removed).length, 1, "another connection does not hold it yet");
    stats.held("two", stats.rev());
    assert.equal(stats.since(0, 1000).filter((r) => r.removed).length, 0);
    assert.deepEqual(heldFrom({ epoch: "e", through: 3 }), { epoch: "e", through: 3 });
    assert.equal(heldFrom("no"), null);
  } finally { stats.close(); }
});

test("a build reads this station's usage and chats of the home workspace and each other station's; one that does not answer is unread", async () => {
  const asked: [string, string, Json][] = [];
  const answer = (station: string, op: string, args: Json) => {
    asked.push([station, op, args]);
    if (station === "st-down") throw new Error("not reachable");
    if (op === "outflowUsage") return JSON.stringify({ rows: [usageRow("2026-11-02", `${station}-s`, "ann@x")], people: {} });
    // Chats a page at a time: the first page says there are more.
    return JSON.stringify(args.before === undefined ? { chats: [chat(1, "working")], more: true, next: "5.1" } : { chats: [chat(2, "waiting")], more: false, next: null });
  };
  const read = workspaceRead({
    home: () => "ws-home",
    here: async (op, args) => answer("", op, args),
    others: async () => ["st-there", "st-down"],
    there: async (station, op, args) => answer(station, op, args),
  });
  const got = await read(FROM, FROM + DAY);
  assert.deepEqual(got.unread, ["st-down"]);
  assert.deepEqual(got.stations.map((s) => [s.station ?? "", s.usage.rows.length, s.chats.map((c: Json) => c.thread)]), [["", 1, [1, 2]], ["st-there", 1, [1, 2]]]);
  assert.deepEqual(asked[0], ["", "outflowUsage", { from: FROM, to: FROM + DAY, tz: 0, ws: { workspace: "ws-home", home: true } }]);
  assert.deepEqual(asked.filter(([s, op]) => s === "st-there" && op === "outflowChats").map(([, , a]) => a.before ?? null), [null, "5.1"]);
});

test("connected, the station sends Comma what it lacks of the statistics, and again as they change; a Comma from before ends it", async () => {
  const pages: Json[] = [];
  let refuse = false;
  let held: Json = { epoch: null, through: 0 };
  const wss = new WebSocketServer({ noServer: true });
  const server = createServer((_req, res) => res.writeHead(404).end());
  let metadata: Json = null;
  server.on("upgrade", (req, socket, head) =>
    wss.handleUpgrade(req, socket, head, (ws) => {
      ws.on("message", (data) => {
        const f = JSON.parse(String(data));
        if (f.type === "metadata") metadata = f;
        if (f.type !== "request") return;
        if (f.method !== "stats.index") return void ws.send(JSON.stringify({ id: f.id, type: "response", result: {} }));
        pages.push(f.params);
        if (refuse) return void ws.send(JSON.stringify({ id: f.id, type: "error", error: "unknown method" }));
        if (f.params.reset || f.params.epoch === held.epoch) held = { epoch: f.params.epoch, through: f.params.through };
        ws.send(JSON.stringify({ id: f.id, type: "response", result: held }));
      });
      ws.send(JSON.stringify({ type: "connected", connector_run_id: "run_1", device_id: "dev_1" }));
    }),
  );
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const rig = new Rig();
  const dir = tempdir();
  let builds = 0;
  const stats = CommaStats.at(dir, async () => (builds++, { stations: [here([usageRow("2026-11-02", "a", "ann@x")])], unread: [] }), quiet);
  const surface = new CommaSurface({ connect: "cm", server: base, token: "salix_conn_test123", name: "mac", tasks: new CommaTasks(join(dir, "tasks.json")), store: rig.store, models: () => [], stats });
  const until = async (f: () => boolean) => {
    for (let i = 0; i < 500 && !f(); i++) await new Promise((r) => setTimeout(r, 10));
    assert.ok(f());
  };
  try {
    await surface.start(() => {});
    await until(() => metadata !== null && held.through > 0);
    assert.equal(metadata.capabilities.stats_index, 1);
    assert.equal(builds, 1, "connected: built once");
    const sent = pages.flatMap((p) => p.rows);
    assert.deepEqual(sent.map((r: Json) => [r.source, r.kind, r.row.person]), [["stillfail", "usage", "ann@x"]]);

    // Changed: the next page carries only what changed.
    stats.apply([here([usageRow("2026-11-02", "a", "ann@x", 2)])], [], FROM);
    const before = pages.length;
    await until(() => held.through === stats.rev());
    assert.deepEqual(pages.slice(before).flatMap((p) => p.rows).map((r: Json) => r.row.calls), [2]);

    // A Comma that does not take the pages: no more are sent.
    refuse = true;
    stats.apply([here([usageRow("2026-11-02", "a", "ann@x", 3)])], [], FROM);
    await until(() => pages.at(-1)?.through === stats.rev());
    const last = pages.length;
    stats.apply([here([usageRow("2026-11-02", "a", "ann@x", 4)])], [], FROM);
    await new Promise((r) => setTimeout(r, 1500));
    assert.equal(pages.length, last);
  } finally {
    await surface.stop();
    stats.close();
    wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.hub.shutdown();
  }
});
