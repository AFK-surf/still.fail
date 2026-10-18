// A person's plugins on the station (docs/client-plugins.md, src/plugins/): what a plugin may say, whose it is (the
// chat's starter, never the agent's pick), what their apps read and delete, and that only they are told.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Request } from "../src/api/request.ts";
import { routes } from "../src/api/routes/plugins.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { MOST, PluginStore, pluginOf } from "../src/plugins/store.ts";
import { pluginTools } from "../src/tools/plugins.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const ALICE = "alice@example.com";

function setup() {
  const plugins = new PluginStore(new DatabaseSync(":memory:"));
  const told: { ws: string; owner: string; p: unknown }[] = [];
  // Sessions here, by whom each chat is for.
  const starters: Record<string, string> = { s1: "Alice@Example.com", s2: ALICE, s3: "bob@example.com", s4: "local" };
  const tools = pluginTools({
    plugins,
    starter: (key) => (starters[key]?.includes("@") ? { owner: starters[key]!.toLowerCase(), ws: WS } : null),
    exists: (key) => key in starters,
    told: (ws, owner, p) => told.push({ ws, owner, p }),
    now: () => 1_700_000_000_000,
  });
  const run = (name: string, session: string, args: Record<string, unknown>) => tools.find((t) => t.name === name)!.run(session, args);
  const gone: string[] = [];
  const all = routes({ plugins, gone: (_ws, owner, id) => gone.push(`${owner}/${id}`) });
  const call = async (method: string, path: string, email = ALICE, workspace = WS) => {
    const viewer: Viewer = { sub: email, email, name: "", role: "member", workspace, device: "d" };
    const r: Request = { method, path, query: [], headers: {}, body: Buffer.alloc(0), viewer, lang: "en" };
    for (const route of all) {
      if (route.method === method && route.pattern.test(path)) {
        const a = await route.handle(r, []);
        return { status: a.status, body: JSON.parse((a.body as Buffer).toString()) };
      }
    }
    throw new Error(`no route ${method} ${path}`);
  };
  return { plugins, told, run, call, gone };
}

const DOUYIN = { id: "douyin", name: "抖音下载", entries: [{ kind: "share", match: "v\\.douyin\\.com|douyin\\.com/video/" }] };

test("a plugin says an id, a name, share entries with a regular expression, and how it sends", () => {
  const p = pluginOf(DOUYIN, "s1", 5);
  assert.deepEqual(p, { id: "douyin", name: "抖音下载", entries: [{ kind: "share", match: "v\\.douyin\\.com|douyin\\.com/video/" }], action: { kind: "chat", session: "s1", send: "auto" }, at: 5 });
  assert.deepEqual((pluginOf({ ...DOUYIN, entries: [{ kind: "share" }], action: { send: "composer" } }, "s1", 5) as any).action.send, "composer");
  assert.deepEqual((pluginOf({ ...DOUYIN, entries: [{ kind: "share", match: "" }] }, "s1", 5) as any).entries, [{ kind: "share" }]);
  for (const bad of [
    { ...DOUYIN, id: "Douyin" },
    { ...DOUYIN, id: "9x" },
    { ...DOUYIN, name: "" },
    { ...DOUYIN, name: "x".repeat(41) },
    { ...DOUYIN, entries: [] },
    { ...DOUYIN, entries: [{ kind: "button" }] },
    { ...DOUYIN, entries: [{ kind: "share", match: "(" }] },
    { ...DOUYIN, entries: [{ kind: "share", match: "a".repeat(501) }] },
    { ...DOUYIN, action: { kind: "module" } },
    { ...DOUYIN, action: { send: "later" } },
    null,
  ]) assert.equal(typeof pluginOf(bad, "s1", 5), "string", JSON.stringify(bad));
});

test("the agent saves, changes, lists and deletes the plugins of whoever started its chat", async () => {
  const { run, told, plugins } = setup();
  assert.match(await run("plugin_save", "s1", DOUYIN), /^Saved plugin douyin for alice@example\.com/);
  assert.deepEqual(plugins.list(WS, ALICE).map((p) => p.action), [{ kind: "chat", session: "s1", send: "auto" }]);
  assert.deepEqual(told.map((t) => t.owner), [ALICE]);
  // Another chat of the same person's says the same person's plugins; saving again changes it.
  assert.match(await run("plugin_save", "s2", { ...DOUYIN, name: "抖音" }), /^Changed plugin douyin/);
  assert.equal(plugins.list(WS, ALICE).length, 1);
  assert.match(await run("plugin_list", "s2", {}), /"name": "抖音"/);
  // Bob's chat sees none of Alice's.
  assert.match(await run("plugin_list", "s3", {}), /^No plugins here/);
  await assert.rejects(run("plugin_delete", "s3", { id: "douyin" }), /no plugin douyin/);
  assert.equal(await run("plugin_delete", "s1", { id: "douyin" }), "Deleted plugin douyin.");
  assert.deepEqual(told.at(-1)!.p, { id: "douyin", gone: true });
  assert.deepEqual(plugins.list(WS, ALICE), []);
});

test("a plugin's chat is this one or another the same person started here; a chat nobody started keeps none", async () => {
  const { run, plugins } = setup();
  await run("plugin_save", "s1", { ...DOUYIN, action: { session: "s2" } });
  assert.equal(plugins.get(WS, ALICE, "douyin")!.action.session, "s2");
  await assert.rejects(run("plugin_save", "s1", { ...DOUYIN, action: { session: "s3" } }), /no chat of this person's/);
  await assert.rejects(run("plugin_save", "s1", { ...DOUYIN, action: { session: "nope" } }), /no chat of this person's/);
  await assert.rejects(run("plugin_save", "s4", DOUYIN), /started by nobody/);
  await assert.rejects(run("plugin_save", "s1", { ...DOUYIN, entries: [{ kind: "share", match: "[" }] }), /no regular expression/);
});

test("a person keeps at most so many", async () => {
  const { run } = setup();
  for (let i = 0; i < MOST; i++) await run("plugin_save", "s1", { ...DOUYIN, id: `p${i}` });
  await assert.rejects(run("plugin_save", "s1", { ...DOUYIN, id: "more" }), /delete one first/);
  await run("plugin_save", "s1", { ...DOUYIN, id: "p0", name: "changed" });
});

test("their apps read their own plugins in the workspace they ask from, and delete them", async () => {
  const { run, call, gone } = setup();
  await run("plugin_save", "s1", DOUYIN);
  assert.deepEqual((await call("GET", "/plugins")).body.plugins.map((p: any) => p.id), ["douyin"]);
  assert.deepEqual((await call("GET", "/plugins", "bob@example.com")).body.plugins, []);
  assert.deepEqual((await call("GET", "/plugins", ALICE, "01HOTHERWORKSPACEZZZZZZZZZ")).body.plugins, []);
  assert.equal((await call("DELETE", "/plugins/douyin", "bob@example.com")).status, 404);
  assert.equal((await call("DELETE", "/plugins/douyin")).status, 200);
  assert.deepEqual(gone, [`${ALICE}/douyin`]);
  assert.equal((await call("DELETE", "/plugins/douyin")).status, 404);
});
