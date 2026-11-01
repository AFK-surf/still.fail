// A workspace's presets on a station (the `presets` topic, docs/presets.md): read as a page shows them and again once
// one is made; the one picked for a new chat there is kept on this device and goes with the chat as it is made.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply, call, readsOf, subscribe, v } from "./helpers.ts";
import { base, overview, started } from "./station-fixture.ts";

const S = "ws/st";
const preset = (id: string, name: string) => ({ id, name, dirs: [{ path: `/repos/${id}`, repo: `github.com/acme/${id}` }], instructions: "", createdBy: "a@x.com", createdAt: 1, updatedAt: 1 });
const candidate = { path: "/repos/app", name: "app", repo: "github.com/acme/app", chats: 3, lastAt: 2 };
const profile = {
  id: "p1", name: "p1@x.com", runtime: "claude", runtimes: ["claude"], access: { kind: "subscription", key: "" }, home: "/h", homeExists: true, model: null, models: ["claude-opus-5-5"],
  env: [], usedBy: [], loginCommand: "", check: { state: "ok", detail: "", checkedAt: 1 }, quota: { state: "ok", windows: [], detail: null, checkedAt: 1 },
};

test("presets_are_read_as_shown_again_once_one_is_made_and_the_one_picked_goes_with_a_new_chat", async () => {
  const said: Record<string, unknown> = {
    ...base(),
    "GET /overview": { ...overview, profiles: [profile] },
    "GET /presets": { presets: [preset("app", "App")], candidates: [candidate] },
    "POST /presets": preset("lib", "Lib"),
    "POST /sessions": { key: "ember:c-new", thread: { id: 9, threadTs: "9.0" } },
  };
  const { host, core } = await started(said as never);
  const reads = () => host.requests.flatMap(readsOf).filter((u) => u.endsWith("/admin/api/presets")).length;
  assert.equal(reads(), 0, "not read until a page shows them");
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "presets", station: S });
  subscribe(core, ui, 2, { topic: "newChat", scope: "ws" });
  await host.settle();
  apply(host, values);
  assert.equal(reads(), 1);
  assert.deepEqual(v(values, 1).presets.map((p: { name: string }) => p.name), ["App"]);
  assert.equal(v(values, 1).candidates[0].chats, 3);
  assert.equal(v(values, 2).preset, "", "none picked yet");

  // One made: read again, the list as it is now.
  said["GET /presets"] = { presets: [preset("app", "App"), preset("lib", "Lib")], candidates: [candidate] };
  call(core, ui, 3, "preset.add", { station: S, name: "Lib", dirs: ["/repos/lib"] });
  await host.settle();
  apply(host, values);
  const made = host.requests.find((r) => r.method === "POST" && r.url.endsWith("/admin/api/presets"));
  assert.deepEqual(JSON.parse(new TextDecoder().decode(made!.body!)), { name: "Lib", dirs: ["/repos/lib"], instructions: "" });
  assert.equal(reads(), 2);
  assert.deepEqual(v(values, 1).presets.map((p: { name: string }) => p.name), ["App", "Lib"]);

  // Picked for the station's new chats: the page says so, and the chat made there is opened with it.
  call(core, ui, 4, "newChat.pick", { scope: "ws", preset: "lib", presetStation: S });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 2).preset, "lib");
  assert.equal(v(values, 2).presetName, "Lib", "named as the station says, the page asking nothing more");
  assert.equal(v(values, 2).presetStation, S);
  assert.deepEqual(v(values, 2).presets, [{ id: "app", name: "App", dirs: 1, station: S, stationName: "studio" }, { id: "lib", name: "Lib", dirs: 1, station: S, stationName: "studio" }]);
  call(core, ui, 5, "newChat.create", { station: S, key: v(values, 2).next });
  await host.settle();
  const asked = host.requests.find((r) => r.method === "POST" && r.url.endsWith("/admin/api/sessions"));
  const body = JSON.parse(new TextDecoder().decode(asked!.body!));
  assert.equal(body.preset, "lib", "this station's: by its id");
  assert.equal(body.presetCopy, undefined);

  // Gone from the station: no longer picked, nor sent with a chat.
  said["GET /presets"] = { presets: [preset("app", "App")], candidates: [candidate] };
  said["DELETE /presets/lib"] = { ok: true };
  call(core, ui, 6, "preset.delete", { station: S, id: "lib" });
  await host.settle();
  call(core, ui, 7, "newChat.pick", { scope: "ws", station: "st" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 2).preset, "");
  core.close();
});
