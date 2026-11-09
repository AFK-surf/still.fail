import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { test } from "node:test";
import { WebSocketServer } from "ws";
import { CommaStats } from "../src/comma/stats.ts";
import { CommaSurface } from "../src/comma/surface.ts";
import { CommaTasks } from "../src/comma/tasks.ts";
import { log } from "../src/ops/log.ts";
import { Rig } from "./hub-fakes.ts";

for (const [method, reason, reported] of [
  ["stats.index", "page_too_large", "page_too_large"],
  ["stats.index", "private_text", "no answer or unrecognized refusal"],
  ["task.index", "too_many_tasks", "too_many_tasks"],
] as const) test(`a ${method} refusal is reported safely (${reported}) without advancing the copy`, async () => {
  const server = createServer((_req, res) => res.writeHead(404).end());
  const wss = new WebSocketServer({ noServer: true });
  const held: Record<string, { epoch: string | null; through: number }> = {
    "stats.index": { epoch: null, through: 0 }, "task.index": { epoch: null, through: 0 },
  };
  let refused: (page: any) => void = () => {};
  const refusal = new Promise<any>((resolve) => { refused = resolve; });
  server.on("upgrade", (req, raw, head) => wss.handleUpgrade(req, raw, head, (ws) => {
    ws.on("message", (data) => {
      const frame = JSON.parse(String(data));
      if (frame.type !== "request") return;
      if (!(frame.method in held)) return void ws.send(JSON.stringify({ id: frame.id, type: "response", result: {} }));
      const page = frame.params;
      if (frame.method === method && page.rows.length > 0 &&
          (method !== "stats.index" || Buffer.byteLength(JSON.stringify(page.rows)) > 65_536)) {
        ws.send(JSON.stringify({ id: frame.id, type: "error", error: reason }));
        refused(page);
        return;
      }
      if (page.reset) held[frame.method] = { epoch: page.epoch, through: page.through };
      ws.send(JSON.stringify({ id: frame.id, type: "response", result: held[frame.method] }));
    });
    ws.send(JSON.stringify({ type: "connected", connector_run_id: "one", device_id: "one" }));
  }));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const rig = new Rig();
  const stats = new CommaStats(":memory:", async () => ({ stations: [], unread: [] }), () => () => {});
  stats.apply([{ usage: { rows: [] }, chats: [
    { thread: 1, title: "Crowded", agents: method === "stats.index"
      ? Array.from({ length: 1700 }, (_, i) => ({ id: `agent-${i}`, model: "example-model" })) : [] },
    { thread: 2, title: "Later", agents: [] },
  ] }], [], 0);
  const surface = new CommaSurface({ connect: "one", server: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
    token: "one_token_123", name: "one", tasks: new CommaTasks(join(rig.dir, "comma-tasks.json")), store: rig.store,
    models: () => [], stats: { stats: stats.stats, tasks: stats.tasks, start: () => {} } });
  const info = log.info;
  let noted: (fields: Record<string, unknown>) => void = () => {};
  const note = new Promise<Record<string, unknown>>((resolve) => { noted = resolve; });
  log.info = (at, message, fields) => {
    if (at === "comma" && message === "an index was not sent") noted(fields ?? {});
    else info(at, message, fields);
  };
  try {
    await surface.start(async () => {});
    const page = await Promise.race([refusal, new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error("Comma was not sent the page")), 10_000).unref();
    })]);
    const fields = await Promise.race([note, new Promise<null>((resolve) => setTimeout(() => resolve(null), 2_000).unref())]);
    assert.deepEqual(fields, { connect: "one", method, error: reported });
    if (method === "stats.index") {
      assert.equal(page.rows.length, 1);
      assert.ok(page.through < stats.stats.rev(), "the later row is still pending");
    }
    assert.deepEqual(held[method], { epoch: null, through: 0 }, "the refused reset did not advance the copy");
  } finally {
    await surface.stop(); stats.close(); wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.close(); log.info = info;
  }
});
