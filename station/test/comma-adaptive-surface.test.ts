import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { test } from "node:test";
import { WebSocketServer } from "ws";
import { CommaStats, PAGE_BYTES } from "../src/comma/stats.ts";
import { CommaSurface } from "../src/comma/surface.ts";
import { CommaTasks } from "../src/comma/tasks.ts";
import { Rig } from "./hub-fakes.ts";

type Json = any;

test("a connection sends adaptive pages again after a rate limit and finishes the receiver's copy", async () => {
  const server = createServer((_req, res) => res.writeHead(404).end());
  const wss = new WebSocketServer({ noServer: true });
  const held: Record<string, { epoch: string | null; through: number }> = {
    "stats.index": { epoch: null, through: 0 }, "task.index": { epoch: null, through: 0 },
  };
  const copy = new Map<string, Json>();
  const pages: Json[] = [];
  let refused = false;
  server.on("upgrade", (req, raw, head) => wss.handleUpgrade(req, raw, head, (ws) => {
    ws.on("message", (data) => {
      const frame = JSON.parse(String(data));
      if (frame.type !== "request") return;
      if (!(frame.method in held)) return void ws.send(JSON.stringify({ id: frame.id, type: "response", result: {} }));
      const page = frame.params;
      if (frame.method === "stats.index" && page.rows.length > 0) {
        pages.push(page);
        if (!refused) {
          refused = true;
          return void ws.send(JSON.stringify({ id: frame.id, type: "error", error: "rate_limited" }));
        }
      }
      const before = held[frame.method];
      if (page.reset || (page.epoch === before.epoch && page.since <= before.through)) {
        if (frame.method === "stats.index") {
          if (page.reset) copy.clear();
          for (const row of page.rows) {
            if (!page.reset && row.rev <= before.through) continue;
            if (row.removed) copy.delete(row.key); else copy.set(row.key, row.row);
          }
        }
        held[frame.method] = { epoch: page.epoch, through: page.reset ? page.through : Math.max(before.through, page.through) };
      }
      ws.send(JSON.stringify({ id: frame.id, type: "response", result: held[frame.method] }));
    });
    ws.send(JSON.stringify({ type: "connected", connector_run_id: "one", device_id: "one" }));
  }));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const rig = new Rig();
  const stats = new CommaStats(":memory:", async () => ({ stations: [], unread: [] }), () => () => {});
  const chats = Array.from({ length: 32 }, (_, i) => ({ thread: i + 1, title: i < 12 ? "x".repeat(16_384) : "small", agents: [] }));
  stats.apply([{ usage: { rows: [] }, chats }], [], 0);
  const indexes = { stats: stats.stats, tasks: stats.tasks, start: () => {} };
  const surface = new CommaSurface({ connect: "one", server: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
    token: "one_token_123", name: "one", tasks: new CommaTasks(join(rig.dir, "comma-tasks.json")), store: rig.store,
    models: () => [], stats: indexes });
  try {
    await surface.start(async () => {});
    for (let i = 0; i < 2000 && held["stats.index"].through < stats.stats.rev(); i++) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(held["stats.index"].through, stats.stats.rev());
    assert.ok(refused && pages.length > 2);
    assert.deepEqual(pages[1], pages[0], "the rate-limited page is retried unchanged");
    assert.ok(pages.every((page) => page.rows.length <= 200 && Buffer.byteLength(JSON.stringify(page.rows)) <= PAGE_BYTES));
    assert.deepEqual([...copy.values()].map((row) => row.thread).sort((a, b) => a - b), chats.map((chat) => chat.thread));
  } finally {
    await surface.stop(); stats.close(); wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.close();
  }
});
