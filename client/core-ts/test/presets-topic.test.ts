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

test("a_picker_subscribing_over_the_client_protocol_gets_the_repositories", async () => {
  const said: Record<string, unknown> = {
    ...base(),
    "GET /overview": { ...overview, profiles: [profile] },
    "GET /presets": { presets: [], candidates: [candidate] },
  };
  const { host, core, push } = await started(said as never);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  // The app first opens a new chat, whose view reads each station's presets, then opens the folder picker.
  core.receiveJson(ui, JSON.stringify({ id: 1, subscribe: { topic: "newChat", scope: "ws" }, keyed: true }));
  await host.settle();
  apply(host, values);
  assert.ok(host.requests.flatMap(readsOf).some((u) => u.endsWith("/admin/api/presets")));
  core.receiveJson(ui, JSON.stringify({ id: 2, subscribe: { topic: "presets", station: S }, keyed: true }));
  await host.settle();
  const emitted = host.takeEmitted().map(([, message]) => message as { id?: number; value?: { candidates: { name: string }[] }; error?: unknown });
  const answer = emitted.find((message) => message.id === 2);
  assert.ok(answer?.value, `the picker must receive the cached folders, got ${JSON.stringify(answer)}`);
  assert.deepEqual(answer.value.candidates.map((c) => c.name), ["app"]);
  values.set(2, answer.value);
  // A scan completed after the picker opened: the same subscription receives the new repository.
  said["GET /presets"] = { presets: [], candidates: [candidate, { ...candidate, path: "/repos/lib", name: "lib", repo: "github.com/acme/lib" }] };
  push("presets", {});
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 2).candidates.map((c: { name: string }) => c.name), ["app", "lib"]);
  core.close();
});

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
  assert.deepEqual(v(values, 2).presets, [
    { id: "app", name: "App", dirs: 1, station: S, stationName: "studio", marks: [{ name: "app", repo: "github.com/acme/app" }] },
    { id: "lib", name: "Lib", dirs: 1, station: S, stationName: "studio", marks: [{ name: "lib", repo: "github.com/acme/lib" }] },
  ]);
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

test("presets_shown_are_read_again_as_the_station_tells_they_changed", async () => {
  // (the machine's repositories found after 添加目录 was opened: they come into it as it stands)
  const said: Record<string, unknown> = { ...base(), "GET /presets": { presets: [], candidates: [] } };
  const s = await started(said as never);
  const ui = s.core.connect();
  const values = new Map<number, unknown>();
  subscribe(s.core, ui, 1, { topic: "presets", station: S });
  await s.host.settle();
  apply(s.host, values);
  assert.deepEqual(v(values, 1).candidates, []);
  said["GET /presets"] = { presets: [], candidates: [candidate] };
  s.push("presets", {});
  await s.host.settle();
  apply(s.host, values);
  assert.deepEqual(v(values, 1).candidates.map((c: { name: string }) => c.name), ["app"]);
  s.core.close();
});
