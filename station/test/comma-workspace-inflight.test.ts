import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { test } from "node:test";
import { WebSocketServer, type WebSocket } from "ws";
import { CommaSurface } from "../src/comma/surface.ts";
import { CommaStats } from "../src/comma/stats.ts";
import { CommaTasks } from "../src/comma/tasks.ts";
import { Rig } from "./hub-fakes.ts";

type Json = any;
const until = async (f: () => boolean) => {
  for (let i = 0; i < 1000 && !f(); i++) await new Promise((resolve) => setTimeout(resolve, 10));
  assert.ok(f());
};

test("a workspace change while Comma answers a probe does not send the old index", async () => {
  const server = createServer((_req, res) => res.writeHead(404).end());
  const wss = new WebSocketServer({ noServer: true });
  const probes: Json[] = [], pages: Json[] = [];
  let socket: WebSocket | null = null;
  server.on("upgrade", (req, raw, head) => wss.handleUpgrade(req, raw, head, (ws) => {
    socket = ws;
    ws.on("message", (data) => {
      const f = JSON.parse(String(data));
      if (f.type !== "request") return;
      if (f.method === "stats.index" || f.method === "task.index") {
        pages.push(f.params);
        if (probes.length < 2) { probes.push(f); return; }
      }
      ws.send(JSON.stringify({ id: f.id, type: "response", result: {} }));
    });
    ws.send(JSON.stringify({ type: "connected", connector_run_id: "one", device_id: "one" }));
  }));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const rig = new Rig();
  const stats = new CommaStats(":memory:", async () => ({ stations: [], unread: [] }), () => () => {});
  stats.apply([{ usage: { rows: [] }, chats: [{ thread: 1, title: "old workspace title", agents: [] }] }], [], 0);
  let allowed = true;
  const indexes = { stats: stats.stats, tasks: stats.tasks, start: () => {} };
  const surface = new CommaSurface({ connect: "one", server: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
    token: "one_token_123", name: "one", tasks: new CommaTasks(join(rig.dir, "comma-tasks.json")), store: rig.store,
    models: () => [], stats: indexes, inScope: () => allowed });
  try {
    await surface.start(async () => {});
    await until(() => probes.length === 2 && socket !== null);
    allowed = false;
    for (const f of probes) (socket as unknown as WebSocket).send(JSON.stringify({ id: f.id, type: "response", result: { epoch: null, through: 0 } }));
    await new Promise((resolve) => setTimeout(resolve, 600));
    assert.equal(pages.length, 2);
    assert.equal(pages.some((page) => JSON.stringify(page.rows).includes("old workspace title")), false);
  } finally {
    await surface.stop(); stats.close(); wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.close();
  }
});
