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

test("the relays' UDP way is no choice any more: a client from before that sets it is answered, nothing saved", async () => {
  const dir = mkdtempSync(join(tmpdir(), "network-settings-"));
  try {
    const config = new ConfigFile(dir);
    config.check = (raw) => checkNetwork(raw.network);
    // A config.json from when it was a choice still opens.
    config.update((raw) => { raw.network = { congestion: "bbr", relayUdp: true }; });
    const route = routes({ config })[0]!;
    const request = (role: string, body: unknown): Request => ({
      method: "PUT", path: "/network/settings", query: [], headers: {}, lang: "zh",
      body: Buffer.from(JSON.stringify(body)),
      viewer: { sub: "a", email: "a@x", name: "A", role, workspace: "w", device: "d" },
    });
    assert.equal((await route.handle(request("member", { relayUdp: true }), [])).status, 403);
    for (const bad of [{ relayUdp: "yes" }, {}]) assert.equal((await route.handle(request("owner", bad), [])).status, 400);
    const answer = await route.handle(request("admin", { relayUdp: true }), []);
    assert.equal(answer.status, 200);
    assert.deepEqual(JSON.parse(String(answer.body)), { congestion: "bbr" });
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("a manager restarts the station through its launcher, which a station without one cannot", async () => {
  const dir = mkdtempSync(join(tmpdir(), "network-settings-"));
  try {
    const config = new ConfigFile(dir);
    let asked = 0;
    let launcher = false;
    const route = routes({ config, restart: () => (launcher ? async () => { asked++; } : null) }).find((r) => String(r.pattern).includes("restart"))!;
    const request = (role: string): Request => ({
      method: "POST", path: "/station/restart", query: [], headers: {}, lang: "zh", body: Buffer.alloc(0),
      viewer: { sub: "a", email: "a@x", name: "A", role, workspace: "w", device: "d" },
    });
    assert.equal((await route.handle(request("member"), [])).status, 403);
    assert.equal((await route.handle(request("owner"), [])).status, 409);
    launcher = true;
    assert.equal((await route.handle(request("member"), [])).status, 403);
    assert.equal(asked, 0);
    assert.equal((await route.handle(request("admin"), [])).status, 202);
    assert.equal(asked, 1);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("the running mesh takes the network settings as they are saved, each once it changes", async () => {
  const { applyNetwork } = await import("../src/mesh/mesh.ts");
  const dir = mkdtempSync(join(tmpdir(), "network-settings-"));
  try {
    const config = new ConfigFile(dir);
    const said: string[] = [];
    const off = applyNetwork({ setCongestion: (c) => void said.push(`congestion ${c}`) }, config);
    config.update((raw) => { raw.unrelated = 1; });
    assert.deepEqual(said, []);
    config.update((raw) => { raw.network = { congestion: "bbr" }; });
    config.update((raw) => { raw.network = { congestion: "bbr", other: true }; });
    config.update((raw) => { raw.network = { congestion: "cubic" }; });
    assert.deepEqual(said, ["congestion bbr", "congestion cubic"]);
    off();
    config.update((raw) => { raw.network = { congestion: "bbr" }; });
    assert.equal(said.length, 2);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
