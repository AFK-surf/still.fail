// Saving a controller choice must survive restart, reject invalid values and remain manager-only.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ConfigFile } from "../src/ops/config.ts";
import { checkNetwork, congestionOf } from "../src/mesh/settings.ts";
import { routes } from "../src/api/routes/network.ts";
import type { Request } from "../src/api/request.ts";

test("network choices persist, validate and belong to station managers", async () => {
  const dir = mkdtempSync(join(tmpdir(), "network-settings-"));
  try {
    const config = new ConfigFile(dir);
    config.check = (raw) => checkNetwork(raw.network);
    config.update((raw) => { raw.unrelated = true; });
    assert.equal(congestionOf(config.raw()), "cubic");
    let changed = 0;
    const route = routes({ config, changed: () => changed++ })[0]!;
    const request = (role: string, congestion: unknown): Request => ({
      method: "PUT", path: "/network/settings", query: [], headers: {}, lang: "zh",
      body: Buffer.from(JSON.stringify({ congestion })),
      viewer: { sub: "a", email: "a@x", name: "A", role, workspace: "w", device: "d" },
    });
    assert.equal((await route.handle(request("member", "bbr"), [])).status, 403);
    assert.equal(congestionOf(config.raw()), "cubic");
    for (const bad of ["reno", null, 3]) assert.equal((await route.handle(request("owner", bad), [])).status, 400);
    assert.equal(changed, 0);
    for (const choice of ["bbr", "cubic"]) {
      assert.equal((await route.handle(request("admin", choice), [])).status, 200);
      const restarted = new ConfigFile(dir);
      assert.equal(congestionOf(restarted.raw()), choice);
      assert.equal(restarted.raw().unrelated, true);
    }
    assert.equal(changed, 2);
    assert.throws(() => config.update((raw) => { raw.network.congestion = "bad"; }), /cubic or bbr/);
    assert.equal(congestionOf(new ConfigFile(dir).raw()), "cubic");
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
