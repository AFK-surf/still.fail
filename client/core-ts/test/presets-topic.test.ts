// A workspace's presets on a station (the `presets` topic): read as a page shows them and again once
// one is made; the one picked for a new chat there is kept on this device and goes with the chat as it is made.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply as applyOps } from "../src/delta.ts";
import { answers, apply, call, readsOf, subscribe, v } from "./helpers.ts";
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
    "POST /sessions": { key: "chat:c-new", thread: { id: 9, threadTs: "9.0" } },
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
    { id: "app", name: "App", station: S, stationName: "studio" },
    { id: "lib", name: "Lib", station: S, stationName: "studio" },
  ]);
  assert.deepEqual(v(values, 2).presetMarks, [{ name: "lib", repo: "github.com/acme/lib" }], "the one picked's marks, its control's look");
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

test("a_repository_cloned_onto_the_station_shows_as_it_goes_and_an_older_station_sends_no_clones", async () => {
  // (a station from before sends no `clones`: none)
  const said: Record<string, unknown> = { ...base(), "GET /presets": { presets: [], candidates: [candidate] } };
  const s = await started(said as never);
  const ui = s.core.connect();
  const values = new Map<number, unknown>();
  subscribe(s.core, ui, 1, { topic: "presets", station: S });
  await s.host.settle();
  apply(s.host, values);
  assert.deepEqual(v(values, 1).clones, []);

  // Started: the station answers at once, the page reads the list again and shows it cloning.
  const cloning = { id: "c1", url: "https://github.com/acme/lib.git", repo: "github.com/acme/lib", name: "lib", state: "cloning", by: "a@x.com", startedAt: 5 };
  said["POST /presets/clone"] = cloning;
  said["GET /presets"] = { presets: [], candidates: [candidate], clones: [cloning] };
  call(s.core, ui, 2, "preset.clone", { station: S, url: "acme/lib" });
  await s.host.settle();
  const emitted = s.host.takeEmitted();
  const answer = answers(emitted, 2) as { ok?: { id: string; state: string } } | undefined;
  assert.equal(answer?.ok?.state, "cloning", JSON.stringify(answer));
  assert.equal(answer?.ok?.id, "c1");
  const asked = s.host.requests.find((r) => r.method === "POST" && r.url.endsWith("/admin/api/presets/clone"));
  assert.deepEqual(JSON.parse(new TextDecoder().decode(asked!.body!)), { url: "acme/lib" });
  for (const [, message] of emitted) {
    const m = message as Record<string, unknown>;
    if (m.id !== 1) continue;
    if ("value" in m) values.set(1, m.value);
    else if ("delta" in m) values.set(1, applyOps(values.get(1), m.delta as never));
  }
  assert.deepEqual(v(values, 1).clones.map((c: { name: string; state: string; error: string }) => [c.name, c.state, c.error]), [["lib", "cloning", ""]]);

  // Failed, then dropped.
  said["GET /presets"] = { presets: [], candidates: [candidate], clones: [{ ...cloning, state: "failed", error: "fatal: repository not found" }] };
  s.push("presets", {});
  await s.host.settle();
  apply(s.host, values);
  assert.equal(v(values, 1).clones[0].error, "fatal: repository not found");
  said["DELETE /presets/clones/c1"] = { ok: true };
  said["GET /presets"] = { presets: [], candidates: [candidate], clones: [] };
  call(s.core, ui, 3, "preset.cloneDrop", { station: S, id: "c1" });
  await s.host.settle();
  apply(s.host, values);
  assert.ok(s.host.requests.some((r) => r.method === "DELETE" && r.url.endsWith("/admin/api/presets/clones/c1")));
  assert.deepEqual(v(values, 1).clones, []);
  s.core.close();
});

test("a_preset_applies_its_optional_station_and_model_when_picked_or_leaves_them_unrestricted", async () => {
  const p2 = {
    ...profile,
    id: "p2",
    name: "p2@x.com",
    models: ["claude-opus-5-5", "claude-sonnet-5-5"],
  };
  const presetBound = {
    id: "review",
    name: "Code Review",
    dirs: [],
    instructions: "Review carefully.",
    autoStation: true,
    model: { model: "claude-sonnet-5-5", runtime: "claude", effort: "high" },
    createdBy: "a@x.com",
    createdAt: 1,
    updatedAt: 1,
  };
  const presetFree = {
    id: "free",
    name: "Free Prompt",
    dirs: [],
    instructions: "Just instructions.",
    createdBy: "a@x.com",
    createdAt: 1,
    updatedAt: 1,
  };
  const said: Record<string, unknown> = {
    ...base(),
    "GET /overview": { ...overview, profiles: [p2] },
    "GET /presets": { presets: [presetBound, presetFree], candidates: [candidate] },
  };
  const { host, core } = await started(said as never);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "presets", station: S });
  subscribe(core, ui, 2, { topic: "newChat", scope: "ws" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 2).pick.value.model, "claude-opus-5-5");

  // Picking a preset with a model applies that model and effort.
  call(core, ui, 3, "newChat.pick", { scope: "ws", preset: "review", presetStation: S });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 2).preset, "review");
  assert.equal(v(values, 2).pick.value.model, "claude-sonnet-5-5");
  assert.equal(v(values, 2).pick.value.effort, "high");

  // Picking an unrestricted preset keeps the current station and model untouched.
  call(core, ui, 4, "newChat.pick", { scope: "ws", preset: "free", presetStation: S });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 2).preset, "free");
  assert.equal(v(values, 2).pick.value.model, "claude-sonnet-5-5");
  assert.equal(v(values, 2).pick.value.effort, "high");

  // `connect-new:preset` starts unrestricted (`value.model === null`) while still populating panel options/efforts,
  // saves via `pick.save`, and resets to unrestricted via `pick.set({ clear: true })`.
  subscribe(core, ui, 5, { topic: "pick", station: S, of: "connect-new:preset" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 5).value.model, undefined);
  assert.equal(v(values, 5).option, "claude-sonnet-5-5");
  assert.equal(v(values, 5).changed, true);

  call(core, ui, 6, "pick.save", { station: S, of: "connect-new:preset", model: "claude-opus-5-5", effort: "medium" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 5).value.model, "claude-opus-5-5");
  assert.equal(v(values, 5).value.effort, "medium");

  call(core, ui, 7, "pick.set", { station: S, of: "connect-new:preset", clear: true });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 5).value.model, undefined);
  core.close();
});
