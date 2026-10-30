// The wide screen's rail as clients draw it (prefs `railView`, src/rail.ts): which places, in what order, as each
// workspace keeps them; what is left out, by kind; the words; whether it is the default.
import assert from "node:assert/strict";
import { test } from "node:test";
import { RAIL_DEFAULT, RAIL_PLACES, railOf, railView } from "../src/rail.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

test("a_rail_kept_reads_as_the_places_known_once_each_none_kept_the_default", () => {
  assert.deepEqual(railOf(undefined), { items: RAIL_DEFAULT, hidden: ["mine", "watching", "archive"], changed: false });
  assert.deepEqual(railOf(null).items, RAIL_DEFAULT);
  // What this build does not know left out (奏, gone, too), each once, in the order kept.
  const kept = railOf(["files", "nope", "chats", "files", 3, "decisions"]);
  assert.deepEqual(kept.items, ["files", "chats"]);
  assert.deepEqual(kept.hidden, ["mine", "watching", "archive", "attention", "stations", "profiles", "connects", "usage"]);
  assert.equal(kept.changed, true);
  // Kept empty: nothing in it, not the default.
  assert.deepEqual(railOf([]), { items: [], hidden: RAIL_PLACES, changed: true });
  assert.equal(railOf([...RAIL_DEFAULT]).changed, false);
});

test("the_rail_view_says_every_place_its_words_kind_and_list_and_each_workspaces_own", () => {
  const view = railView({ rail: ["usage", "chats"], rails: { w1: ["mine", "watching"], w2: [] } }) as any;
  assert.deepEqual(view.places.map((p: any) => p.id), RAIL_PLACES);
  assert.deepEqual(view.places.find((p: any) => p.id === "chats"), { id: "chats", label: "对话", kind: "lists", list: "all" });
  assert.deepEqual(view.places.find((p: any) => p.id === "attention"), { id: "attention", label: "待处理", kind: "attention" });
  assert.deepEqual(view.places.find((p: any) => p.id === "stations"), { id: "stations", label: "Station", kind: "places" });
  assert.deepEqual(view.groups.map((g: any) => [g.kind, g.label, g.places]), [
    ["places", "页面", ["files", "stations", "profiles", "connects", "usage"]],
    ["lists", "对话列表", ["chats", "mine", "watching", "archive"]],
    ["attention", "提醒", ["attention"]],
  ]);
  assert.deepEqual(view.default, RAIL_DEFAULT);
  assert.deepEqual(view.all.items, ["usage", "chats"]);
  assert.deepEqual(view.by.w1.items, ["mine", "watching"]);
  assert.deepEqual(view.by.w2.items, []);
  assert.equal(view.by.w3, undefined, "one not kept goes by `all`");
  assert.deepEqual(railView({}).all, railOf(undefined));
});

test("the_prefs_topic_says_the_rail_as_each_workspace_keeps_it", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).railView.all.items, RAIL_DEFAULT);
  assert.deepEqual(v(values, 1).railView.by, {});
  call(core, ui, 2, "prefs.set", { rails: { w1: ["files", "chats", "files"] } });
  await host.settle();
  apply(host, values);
  const rail = v(values, 1).railView;
  assert.deepEqual(rail.by.w1, { items: ["files", "chats"], hidden: ["mine", "watching", "archive", "attention", "stations", "profiles", "connects", "usage"], changed: true });
  assert.deepEqual(rail.all.items, RAIL_DEFAULT, "the others as before");
  // Kept as it was written: the view is the core's, not kept.
  assert.deepEqual(v(values, 1).rails.w1, ["files", "chats", "files"]);
  call(core, ui, 3, "prefs.set", { rails: { w1: null }, rail: ["usage"] });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).railView.by, {});
  assert.deepEqual(v(values, 1).railView.all.items, ["usage"]);
  core.close();
});
