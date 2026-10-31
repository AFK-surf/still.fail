// The keyboard shortcuts (keymap.ts): bindings as the core has them, as key caps show them, the prefs' `keymap` and
// `keys.set`.
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseCall } from "../src/core/calls.ts";
import type { Core } from "../src/core.ts";
import { t } from "../src/i18n.ts";
import { ACTIONS, binding, change, label, view } from "../src/keymap.ts";
import { SHAPES } from "../src/shapes/schema.ts";
import type { FakeHost } from "../src/testing.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const MAC_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
const desktop = (mac: boolean, keys: J = {}) => ({ device: { app: "desktop", mac }, keys });
const of = (km: J, action: string) => km.actions.find((a: J) => a.action === action);

test("a_binding_is_kept_with_its_modifiers_in_one_order_and_what_is_none_is_refused", () => {
  assert.equal(binding("Mod+Shift+H"), "Shift+Mod+H");
  assert.equal(binding("Mod+Alt+N"), "Alt+Mod+N");
  assert.equal(binding("Ctrl+Alt+Shift+Mod+F12"), "Ctrl+Alt+Shift+Mod+F12");
  for (const key of ["Space", "Escape", "Up", "\\", "[", ";", "7", "K"]) assert.equal(binding(key), key);
  for (const key of ["Mod+-", "Mod+=", "Mod+Plus", "Shift+Mod+Plus"]) assert.equal(binding(key), key);
  for (const bad of ["", "Mod", "Mod+", "Mod++", "Mod+k", "Mod+Backspace", "Cmd+K", "Mod+Mod+K", "Shift+K+Mod", 3, null]) assert.equal(binding(bad), null, String(bad));
});

test("a_key_cap_says_a_binding_as_a_mac_or_a_pc_has_it", () => {
  assert.equal(label("Shift+Mod+H", true), "⇧⌘H");
  assert.equal(label("Ctrl+Alt+Shift+Mod+Up", true), "⌃⌥⇧⌘↑");
  assert.equal(label("Shift+Mod+H", false), "Ctrl+Shift+H");
  assert.equal(label("Alt+Mod+N", false), "Ctrl+Alt+N");
  assert.equal(label("Alt+Down", false), "Alt+↓");
  assert.equal(label("Escape", false), "Esc");
  assert.equal(label("Space", true), t("web-main.keymap.space"));
  assert.equal(label("Mod+Plus", true), "⌘+");
});

test("the_keymap_is_the_actions_own_keys_and_on_the_desktop_those_changed_there", () => {
  // A page: the app's own keys; the desktop app's only are not listed; what is kept in `keys` is not gone by.
  let km = view({ device: { app: "web", mac: false }, keys: { "chat.find": ["Mod+J"] } }) as J;
  assert.deepEqual(km.actions.map((a: J) => a.action), Object.keys(ACTIONS));
  assert.equal(km.changeable, false);
  assert.deepEqual(of(km, "chat.new").keys, ["Alt+Mod+N"]);
  assert.deepEqual(of(km, "chat.new").labels, ["Ctrl+Alt+N"]);
  assert.deepEqual(of(km, "chat.find").keys, ["Mod+F"]);
  assert.equal(of(km, "chat.find").changed, false);
  assert.equal(of(km, "nav.back").listed, false);
  assert.equal(of(km, "nav.back").text, t("web-main.shortcuts.unset"));
  assert.equal(of(km, "composer.focus").typing, "no");
  assert.equal(of(km, "chat.latest").typing, "empty");
  assert.equal(of(km, "chat.switch").name, t("web-main.keymap.chat.switch"));
  assert.deepEqual(km.groups.map((g: J) => [g.group, g.name]), [["global", t("web-main.keymap.group.global")], ["chat", t("web-main.keymap.group.chat")], ["files", t("web-main.keymap.group.files")]]);
  assert.deepEqual([km.workspace[0], km.workspace[8]], ["Alt+1", "Alt+9"]);
  // The desktop app on a Mac: its own keys first; those changed, as said (one that is none left out); none: unset.
  km = view(desktop(true, { "chat.find": ["Mod+J", "Mod+Shift+J", "nope"], "chat.stop": [] })) as J;
  assert.equal(km.changeable, true);
  assert.deepEqual(of(km, "chat.new").keys, ["Mod+N", "Alt+Mod+N"]);
  assert.equal(of(km, "chat.new").text, "⌘N / ⌥⌘N");
  assert.deepEqual(of(km, "chat.find").keys, ["Mod+J", "Shift+Mod+J"]);
  assert.equal(of(km, "chat.find").changed, true);
  assert.deepEqual(of(km, "chat.stop").keys, []);
  assert.equal(of(km, "chat.stop").text, t("web-main.shortcuts.unset"));
  assert.equal(of(km, "nav.back").listed, true);
  assert.equal(km.workspace[0], "⌃1");
  assert.deepEqual(of(km, "zoom.out").keys, ["Mod+-"]);
  assert.deepEqual(of(km, "zoom.reset").keys, ["Mod+0"]);
  assert.ok(of(km, "zoom.in").keys.includes("Mod+="));
  // Nothing told yet: a page's.
  assert.deepEqual(of(view({}) as J, "chat.new").keys, ["Alt+Mod+N"]);
});

test("keys_given_to_an_action_are_taken_from_the_one_that_had_them_said_so", () => {
  const { patch, moved, said } = change(desktop(true), "chat.find", ["Mod+K"]);
  assert.deepEqual(patch, { "chat.find": ["Mod+K"], "chat.switch": [] });
  assert.deepEqual(moved, ["chat.switch"]);
  assert.equal(said, t("web-main.shortcuts.moved", { keys: "⌘K", action: t("web-main.keymap.chat.switch") }));
  // One of several keys: the rest stay.
  assert.deepEqual(change(desktop(false), "chat.find", ["Alt+Mod+N"]).patch, { "chat.find": ["Alt+Mod+N"], "chat.new": ["Mod+N"] });
  // None moved; its own again; every action's own again.
  assert.deepEqual(change(desktop(false), "chat.find", ["Mod+J"]), { patch: { "chat.find": ["Mod+J"] }, moved: [], said: null });
  assert.deepEqual(change(desktop(false), "chat.find", null), { patch: { "chat.find": null }, moved: [], said: null });
  assert.deepEqual(change(desktop(false), null, null), { patch: null, moved: [], said: null });
});

test("the_actions_the_clients_are_told_of_are_the_keymaps", () => {
  const words = SHAPES.KeyActionName as J;
  assert.deepEqual(words.values, Object.keys(ACTIONS));
});

test("keys_set_reads_an_action_and_bindings_and_refuses_what_is_none", () => {
  assert.deepEqual(parseCall("keys.set", { action: "chat.find", keys: ["Mod+Shift+F", "Shift+Mod+F"] }), { kind: "keysSet", action: "chat.find", keys: ["Shift+Mod+F"] });
  assert.deepEqual(parseCall("keys.set", { action: "chat.find", keys: null }), { kind: "keysSet", action: "chat.find", keys: null });
  assert.deepEqual(parseCall("keys.set", {}), { kind: "keysSet", action: null, keys: null });
  const code = (f: () => unknown) => { try { f(); return "none"; } catch (e) { return (e as J).code; } };
  assert.equal(code(() => parseCall("keys.set", { action: "chat.nope", keys: ["Mod+K"] })), "invalid_params");
  assert.equal(code(() => parseCall("keys.set", { action: "chat.find", keys: ["Mod+Q+"] })), "invalid_params");
  assert.equal(code(() => parseCall("keys.set", { action: "chat.find", keys: [3] })), "invalid_params");
  assert.equal(code(() => parseCall("keys.set", { keys: ["Mod+K"] })), "invalid_params");
});

/// A call answered: its `ok`, or its error (what else came stays to be read).
async function ask(host: FakeHost, core: Core, ui: number, id: number, name: string, params: unknown): Promise<J> {
  call(core, ui, id, name, params);
  await host.settle();
  const i = host.emitted.findIndex(([, m]) => (m as J).id === id && ("ok" in (m as J) || "error" in (m as J)));
  if (i < 0) throw new Error(`${name} not answered`);
  const [[, m]] = host.emitted.splice(i, 1);
  return m as J;
}

test("the_desktop_app_changes_its_keys_and_the_prefs_say_its_keymap_anew", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await ask(host, core, ui, 2, "client.device", { app: "desktop", build: "0.1.9", userAgent: MAC_UA });
  const values = new Map();
  apply(host, values);
  let km = v(values, 1).keymap;
  assert.equal(km.mac, true);
  assert.equal(km.changeable, true);
  assert.deepEqual(of(km, "chat.switch").labels, ["⌘K"]);
  // ⌘K given to 在对话中查找: taken from 切换对话, said so.
  const moved = await ask(host, core, ui, 3, "keys.set", { action: "chat.find", keys: ["Mod+K"] });
  assert.deepEqual(moved.ok.moved, ["chat.switch"]);
  assert.ok(moved.ok.said.includes("⌘K"), moved.ok.said);
  apply(host, values);
  km = v(values, 1).keymap;
  assert.deepEqual([of(km, "chat.find").keys, of(km, "chat.find").changed], [["Mod+K"], true]);
  assert.deepEqual([of(km, "chat.switch").keys, of(km, "chat.switch").text], [[], t("web-main.shortcuts.unset")]);
  assert.deepEqual(v(values, 1).keys, { "chat.find": ["Mod+K"], "chat.switch": [] });
  // A binding that is none is refused, by `prefs.set` too; what was kept stays.
  assert.equal((await ask(host, core, ui, 4, "keys.set", { action: "chat.find", keys: ["Mod+"] })).error.code, "invalid_params");
  assert.equal((await ask(host, core, ui, 5, "prefs.set", { keys: { "chat.find": ["Hyper+K"] } })).error.code, "invalid_params");
  // `prefs.set` keeps a binding as the keymap has it.
  await ask(host, core, ui, 6, "prefs.set", { keys: { "chat.stop": ["Mod+Shift+S"] } });
  apply(host, values);
  assert.deepEqual(v(values, 1).keys["chat.stop"], ["Shift+Mod+S"]);
  // Every action's own again.
  await ask(host, core, ui, 7, "keys.set", {});
  apply(host, values);
  km = v(values, 1).keymap;
  assert.ok(km.actions.every((a: J) => !a.changed));
  assert.deepEqual(of(km, "chat.switch").keys, ["Mod+K"]);
  // The window's zoom is kept in the device prefs and invalid sizes cannot reach the UI.
  await ask(host, core, ui, 8, "prefs.set", { windowZoom: "125" });
  apply(host, values);
  assert.equal(v(values, 1).windowZoom, "125");
  assert.equal((await ask(host, core, ui, 9, "prefs.set", { windowZoom: "9999" })).error.code, "invalid_params");
  await ask(host, core, ui, 10, "prefs.set", { windowZoom: null });
  apply(host, values);
  assert.equal(v(values, 1).windowZoom, undefined);
  core.close();
});
