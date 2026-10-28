// How a workspace's members' devices reach its stations (src/views/ways.ts, the `workspaceWays` view): from `/v1/me`
// alone, so the workspace page's 连接方式 has them at once while the workspace itself is still being read.
import assert from "node:assert/strict";
import { test } from "node:test";
import { STORAGE_KEY } from "../src/accounts.ts";
import { Core } from "../src/core.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { account, apply, subscribe, v } from "./helpers.ts";

// deno-lint-ignore no-explicit-any
type J = any;

test("a workspace's ways come from /v1/me: still.fail's relays named, its own, the kinds; those turned off counted, the workspace's own read not waited for", async () => {
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "tok", "r0", host.nowMs() / 1000 + 3600)]);
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me")
      return jsonResponse(200, {
        workspaces: [{ id: "ws", name: "W", role: "owner", relays: ["https://own.test"], ways_off: ["https://bj.test/", "tailnet"] }],
        invitations: [],
        relay_url: "https://cf.test",
        relay_urls: ["https://cf.test", "https://bj.test"],
        relay_names: { "https://bj.test": "北京" },
      });
    // (the workspace itself never answers)
    if (path === "/v1/workspaces/ws") return new Promise(() => {});
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaceWays", workspace: "ws" });
  subscribe(core, ui, 2, { topic: "workspace", workspace: "ws" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const view = v(values, 1) as J;
  assert.deepEqual(view.ways.map((w: J) => [w.id, w.kind, w.name, w.own, w.on]), [
    ["https://cf.test", "relay", "cf.test", false, true],
    ["https://bj.test", "relay", "北京", false, false],
    ["https://own.test", "relay", "own.test", true, true],
    ["lan", "lan", "", false, true],
    ["tailnet", "tailnet", "", false, false],
    ["direct", "direct", "", false, true],
  ]);
  assert.equal(view.off, 2);
  assert.equal(view.offLabel, "已关闭 2 项");
});
