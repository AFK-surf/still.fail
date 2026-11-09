import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { WebSocketServer } from "ws";
import { workspaceIndex } from "../src/comma/workspace-index.ts";
import { makeComma } from "../src/comma/index.ts";
import { CommaStats, RevIndex, type StationRows } from "../src/comma/stats.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { Rig } from "./hub-fakes.ts";

type Json = any;
const quiet = () => () => {};
const nothing = async () => ({ stations: [], unread: [] });
const row = (title: string): StationRows => ({ usage: { rows: [] }, chats: [
  { thread: 17, title, surface: "stillfail", createdAt: 1, lastActiveAt: 2, agents: [] },
] });
const until = async (f: () => boolean) => {
  for (let i = 0; i < 1000 && !f(); i++) await new Promise((resolve) => setTimeout(resolve, 10));
  assert.ok(f());
};

test("a new home resets the old copy before its own first read completes", async () => {
  const server = createServer((_req, res) => res.writeHead(404).end());
  const wss = new WebSocketServer({ noServer: true });
  const pages: Json[] = [];
  server.on("upgrade", (req, socket, head) => wss.handleUpgrade(req, socket, head, (ws) => {
    const held: Record<string, Json> = { "stats.index": { epoch: "old", through: 1 }, "task.index": { epoch: "old", through: 1 } };
    ws.on("message", (data) => {
      const f = JSON.parse(String(data));
      if (f.type !== "request") return;
      if (f.method === "stats.index" || f.method === "task.index") {
        pages.push({ method: f.method, ...f.params });
        if (f.params.reset || f.params.epoch === held[f.method].epoch) held[f.method] = { epoch: f.params.epoch, through: f.params.through };
      }
      ws.send(JSON.stringify({ id: f.id, type: "response", result: held[f.method] ?? {} }));
    });
    ws.send(JSON.stringify({ type: "connected", connector_run_id: "new-home", device_id: "new-home" }));
  }));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const rig = new Rig(), dir = rig.dir, previousConfig = process.env.STILLFAIL_CONFIG;
  process.env.STILLFAIL_CONFIG = join(dir, "config.json");
  const config = new ConfigFile(dir);
  config.update((raw) => { raw.connects = [{ id: "new-home", kind: "comma", enabled: true,
    comma: { server: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, token: "new_home_token_123" } }]; });
  const legacy = CommaStats.at(dir, nothing, quiet);
  legacy.apply([row("unscoped old title")], [], 0); legacy.close();
  const old = CommaStats.inWorkspace(dir, "old-home", nothing, quiet);
  old.apply([row("old home title")], [], 0); old.close();
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  const empty = { stats: new RevIndex(db, "stats_index"), tasks: new RevIndex(db, "task_index"), start: () => {} };
  let release!: (v: { stations: StationRows[]; unread: string[] }) => void;
  const pending = new Promise<{ stations: StationRows[]; unread: string[] }>((resolve) => { release = resolve; });
  let index: ReturnType<typeof workspaceIndex> | null = null;
  const hasOldTitle = (page: Json) => /unscoped old title|old home title/.test(JSON.stringify(page.rows));
  const connects = makeComma({ data: dir, config, store: rig.store, receive: async () => {}, bound: () => true,
    scope: (ws) => {
      index ??= workspaceIndex(dir, ws, () => true, () => 1, () => pending, quiet);
      return { indexes: index.indexes, chats: { read: async () => ({}), say: async () => ({}) } };
    }, empty, home: () => "new-home", within: () => true, scopeVersion: () => 1, onScopeChange: () => () => {}, previousExited: Promise.resolve() });
  try {
    await connects.reconcile();
    await until(() => pages.some((page) => page.method === "task.index" && page.reset));
    assert.equal(pages.some(hasOldTitle), false);
    assert.deepEqual(pages.find((page) => page.method === "task.index" && page.reset).rows, []);
    release({ stations: [row("new home title")], unread: [] });
    await until(() => pages.some((page) => JSON.stringify(page.rows).includes("new home title")));
    assert.equal(pages.some(hasOldTitle), false);
  } finally {
    release({ stations: [], unread: [] });
    await connects.close();
    if (index !== null) { await (index as ReturnType<typeof workspaceIndex>).stats.settled(); (index as ReturnType<typeof workspaceIndex>).stats.close(); }
    db.close(); wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.close();
    if (previousConfig === undefined) delete process.env.STILLFAIL_CONFIG; else process.env.STILLFAIL_CONFIG = previousConfig;
  }
});
