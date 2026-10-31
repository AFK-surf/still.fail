import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { contextView, routes } from "../src/api/routes/context.ts";
import type { Request } from "../src/api/request.ts";
import { ConfigFile } from "../src/ops/config.ts";

test("the cold-cache threshold is editable by managers, validated, and saved independently of the switch", async () => {
  const dir = mkdtempSync(join(tmpdir(), "context-settings-"));
  const oldConfig = process.env.STILLFAIL_CONFIG;
  process.env.STILLFAIL_CONFIG = join(dir, "config.json");
  try {
    const config = new ConfigFile(dir);
    const route = routes({ config })[0]!;
    const request = (role: string, body: unknown): Request => ({
      method: "PUT", path: "/context/settings", query: [], headers: {}, lang: "zh",
      body: Buffer.from(JSON.stringify(body)),
      viewer: { sub: "a", email: "a@x", name: "A", role, workspace: "w", device: "d" },
    });
    assert.deepEqual(contextView(config.raw()), { afreshWhenCold: false, afreshAbove: 1 });
    assert.equal((await route.handle(request("member", { afreshAbove: 2 }), [])).status, 403);
    for (const bad of [-1, "2", null]) assert.equal((await route.handle(request("admin", { afreshAbove: bad }), [])).status, 400);
    assert.equal((await route.handle(request("admin", {}), [])).status, 400);
    assert.equal((await route.handle(request("admin", { afreshWhenCold: true }), [])).status, 200);
    assert.equal((await route.handle(request("admin", { afreshAbove: 2.5 }), [])).status, 200);
    assert.deepEqual(contextView(new ConfigFile(dir).raw()), { afreshWhenCold: true, afreshAbove: 2.5 });
    assert.equal((await route.handle(request("admin", { afreshWhenCold: false }), [])).status, 200);
    assert.deepEqual(contextView(new ConfigFile(dir).raw()), { afreshWhenCold: false, afreshAbove: 2.5 });
    assert.equal((await route.handle(request("admin", { afreshAbove: 0 }), [])).status, 200);
    assert.deepEqual(contextView(new ConfigFile(dir).raw()), { afreshWhenCold: false, afreshAbove: 0 });
    assert.equal((await route.handle(request("admin", { afreshAbove: 1 }), [])).status, 200);
    assert.deepEqual(contextView(new ConfigFile(dir).raw()), { afreshWhenCold: false, afreshAbove: 1 });
  } finally {
    if (oldConfig === undefined) delete process.env.STILLFAIL_CONFIG;
    else process.env.STILLFAIL_CONFIG = oldConfig;
    rmSync(dir, { recursive: true, force: true });
  }
});
