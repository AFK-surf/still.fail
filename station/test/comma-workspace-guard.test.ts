import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { WebSocketServer, type WebSocket } from "ws";
import { makeComma } from "../src/comma/index.ts";
import { CommaStats, RevIndex } from "../src/comma/stats.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { Rig } from "./hub-fakes.ts";

type Json = any;
const until = async (f: () => boolean) => {
  for (let i = 0; i < 1000 && !f(); i++) await new Promise((resolve) => setTimeout(resolve, 10));
  assert.ok(f());
};

test("a joined workspace's connect sends that workspace's index, never the home's, and its Router reads there", async () => {
  const server = createServer((_req, res) => res.writeHead(404).end());
  const wss = new WebSocketServer({ noServer: true });
  const sockets = new Map<string, WebSocket>(), metadata = new Set<string>(), replies = new Map<string, Json>();
  const received: Record<string, Json[]> = { home: [], joined: [] };
  const copies: Record<string, Record<string, { epoch: string | null; through: number; rows: Map<string, Json> }>> = {
    home: { "stats.index": { epoch: null, through: 0, rows: new Map() }, "task.index": { epoch: null, through: 0, rows: new Map() } },
    joined: { "stats.index": { epoch: "old", through: 7, rows: new Map([["old", { title: "old home" }]]) },
      "task.index": { epoch: "old", through: 7, rows: new Map([["old", { title: "old home" }]]) } },
  };
  server.on("upgrade", (req, socket, head) => {
    const who = req.headers.authorization === "Bearer home_token_123" ? "home" : "joined";
    wss.handleUpgrade(req, socket, head, (ws) => {
      sockets.set(who, ws);
      ws.on("message", (data) => {
        const f = JSON.parse(String(data));
        if (f.type === "metadata") metadata.add(who);
        if (f.type === "response" || f.type === "error") replies.set(f.id, f);
        if (f.type !== "request") return;
        if (f.method === "stats.index" || f.method === "task.index") {
          received[who]!.push({ method: f.method, page: f.params });
          const held = copies[who]![f.method]!;
          if (f.params.reset || (f.params.epoch === held.epoch && f.params.since <= held.through)) {
            if (f.params.reset) held.rows.clear();
            for (const row of f.params.rows) held.rows.set(row.key ?? row.thread, row);
            held.epoch = f.params.epoch;
            held.through = f.params.through;
          }
          ws.send(JSON.stringify({ id: f.id, type: "response", result: { epoch: held.epoch, through: held.through } }));
        } else ws.send(JSON.stringify({ id: f.id, type: "response", result: {} }));
      });
      ws.send(JSON.stringify({ type: "connected", connector_run_id: who, device_id: who }));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const rig = new Rig(), dir = rig.dir;
  const priorConfig = process.env.STILLFAIL_CONFIG;
  process.env.STILLFAIL_CONFIG = join(dir, "config.json");
  const config = new ConfigFile(dir);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  config.update((raw) => { raw.connects = [
    { id: "home", kind: "comma", enabled: true, comma: { server: base, token: "home_token_123" } },
    { id: "joined", kind: "comma", enabled: true, workspace: "joined-workspace", comma: { server: base, token: "joined_token_123" } },
  ]; });
  const rows = [{ usage: { rows: [], people: {} }, chats: [{ thread: 17, title: "home-only title", surface: "stillfail", createdAt: 1, lastActiveAt: 2, agents: [] }] }];
  const stats = new CommaStats(":memory:", async () => ({ stations: rows, unread: [] }), () => () => {});
  const otherRows = [{ usage: { rows: [], people: {} }, chats: [{ thread: 18, title: "new home title", surface: "stillfail", createdAt: 1, lastActiveAt: 2, agents: [] }] }];
  const otherStats = new CommaStats(":memory:", async () => ({ stations: otherRows, unread: [] }), () => () => {});
  const joinedRows = [{ usage: { rows: [], people: {} }, chats: [{ thread: 19, title: "joined title", surface: "stillfail", createdAt: 1, lastActiveAt: 2, agents: [] }] }];
  const joinedStats = new CommaStats(":memory:", async () => ({ stations: joinedRows, unread: [] }), () => () => {});
  const emptyDb = new DatabaseSync(":memory:");
  emptyDb.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  const empty = { stats: new RevIndex(emptyDb, "stats_index"), tasks: new RevIndex(emptyDb, "task_index"), start: () => {} };
  let home: string | null = "home-workspace", version = 0, previousExited!: () => void;
  const previous = new Promise<void>((resolve) => { previousExited = resolve; });
  let reads = 0, writes = 0, scopesOpened = 0, finishRead!: (value: Json) => void;
  const waitingRead = new Promise<Json>((resolve) => { finishRead = resolve; });
  const chats = { read: async () => (reads++, await waitingRead), say: async () => (writes++, { seq: 1 }) };
  let joinedReads = 0;
  const joinedChats = { read: async () => (joinedReads++, { title: "joined title", messages: [] }), say: async () => ({ seq: 1 }) };
  const homeListeners = new Set<() => void>();
  const connects = makeComma({ data: dir, config, store: rig.store, receive: async () => {}, bound: () => true,
    inWorkspace: (ws) => ws === null || ws === "joined-workspace",
    scope: (ws) => (scopesOpened++, ws === "joined-workspace" ? { indexes: joinedStats, chats: joinedChats }
      : { indexes: ws === "home-workspace" ? stats : otherStats, chats }), empty,
    home: () => home, within: (ws) => ws === home || ws === "joined-workspace", scopeVersion: () => version,
    onScopeChange: (changed) => { homeListeners.add(changed); return () => homeListeners.delete(changed); }, previousExited: previous });
  const request = async (who: string, id: string, method: string, params: Json) => {
    sockets.get(who)!.send(JSON.stringify({ id, type: "request", method, params }));
    await until(() => replies.has(id));
    return replies.get(id)!;
  };
  try {
    await connects.reconcile();
    await until(() => metadata.size === 2);
    assert.deepEqual([received.home!.length, received.joined!.length], [0, 0]);
    assert.equal(scopesOpened, 0, "the scoped database is not opened while the previous station can still use it");
    assert.equal((await request("joined", "read-joined", "task.read", { task: "17" })).type, "error");
    assert.equal((await request("joined", "write-joined", "task.say", { task: "17", text: "hello" })).type, "error");
    assert.deepEqual([reads, writes, joinedReads], [0, 0, 0]);
    previousExited();
    await until(() => copies.joined!["stats.index"]!.epoch !== "old" && copies.joined!["task.index"]!.epoch !== "old");
    await until(() => [...copies.home!["task.index"]!.rows.values()].some((row) => row.title === "home-only title"));
    await until(() => [...copies.joined!["task.index"]!.rows.values()].some((row) => row.title === "joined title"));
    const titles = (who: string) => [...copies[who]!["task.index"]!.rows.values()].map((row) => row.title);
    assert.deepEqual(titles("joined"), ["joined title"], "the old home rows are gone and the home's never come");
    assert.equal((await request("joined", "read-joined-after", "task.read", { task: "19" })).type, "response");
    assert.deepEqual([reads, joinedReads], [0, 1], "the joined connect's Router reads in its own workspace");

    sockets.get("home")!.send(JSON.stringify({ id: "read-home", type: "request", method: "task.read", params: { task: "17" } }));
    await until(() => reads === 1);
    home = "other-home"; version++;
    home = "home-workspace"; version++;
    finishRead({ title: "home-only title", messages: [{ text: "home-only message" }] });
    await until(() => replies.has("read-home"));
    assert.equal(replies.get("read-home").type, "error", "a read cannot return after the home changed, even if it changed back");
    assert.equal((await request("home", "write-after-move", "task.say", { task: "17", text: "hello" })).type, "error");
    assert.equal(writes, 0);

    // An edit that moves a connect between workspaces must recreate it even when its token is unchanged.
    const oldEpoch = copies.home!["task.index"]!.epoch;
    config.update((raw) => { raw.connects.find((c: Json) => c.id === "home").workspace = "joined-workspace"; });
    await until(() => copies.home!["task.index"]!.epoch !== oldEpoch && titles("home").includes("joined title"));
    assert.equal(titles("home").includes("home-only title"), false);

    config.update((raw) => { delete raw.connects.find((c: Json) => c.id === "home").workspace; });
    await until(() => [...copies.home!["task.index"]!.rows.values()].some((r) => r.title === "home-only title"));
    home = "new-home"; version++;
    for (const changed of homeListeners) changed();
    await until(() => [...copies.home!["task.index"]!.rows.values()].some((r) => r.title === "new home title"));
    assert.equal([...copies.home!["task.index"]!.rows.values()].some((r) => r.title === "home-only title"), false);
    assert.deepEqual(titles("joined"), ["joined title"]);
  } finally {
    previousExited(); finishRead({});
    await connects.close(); stats.close(); otherStats.close(); joinedStats.close(); emptyDb.close(); wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.close();
    if (priorConfig === undefined) delete process.env.STILLFAIL_CONFIG; else process.env.STILLFAIL_CONFIG = priorConfig;
  }
});
