import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { routes } from "../src/api/routes/usage.ts";
import { usageOps } from "../src/read/ops-usage.ts";

test("a joined workspace's memory is read in the reader rather than on the station thread", async () => {
  const asked: unknown[] = [];
  const agents = { get config(): never { throw new Error("the route read memory itself"); } };
  const tools = {
    agents,
    read: async (_r: unknown, op: string, args: unknown) => {
      asked.push([op, args]);
      return { status: 200, headers: {}, body: Buffer.from("{}") };
    },
  };
  const route = routes(tools as never).find((r) => r.method === "GET" && r.pattern.test("/memory"));
  assert.ok(route);
  const request = { viewer: { workspace: "joined", home: false } };
  const answer = await route.handle(request as never, []);
  assert.equal(answer.status, 200);
  assert.deepEqual(asked, [["memory", { workspace: "joined" }]]);
  const invalid = await route.handle({ viewer: { home: false } } as never, []);
  assert.equal(invalid.status, 400, "an absent workspace cannot fall back to the home memory");
  assert.equal(asked.length, 1);
});

test("the reader selects only the asking workspace's memory", () => {
  const data = mkdtempSync(join(tmpdir(), "memory-reader-"));
  try {
    mkdirSync(join(data, "agent/workspaces/joined"), { recursive: true });
    writeFileSync(join(data, "agent/MEMORY.md"), "home only");
    writeFileSync(join(data, "agent/workspaces/joined/MEMORY.md"), "joined only");
    const read = usageOps.memory!;
    const store = { dataDir: data } as never;
    assert.equal((read(store, {}) as any).global.text, "home only");
    assert.equal((read(store, { workspace: "joined" }) as any).global.text, "joined only");
    assert.throws(() => read(store, { workspace: "../outside" }), /not a workspace id/);
  } finally {
    rmSync(data, { recursive: true, force: true });
  }
});
