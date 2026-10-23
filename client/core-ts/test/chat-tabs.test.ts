// A chat's side-panel tabs (src/chat-tabs.ts): which of those kept the chat shows and which is in front, and how
// opening, closing, bringing to the front and closing them all change what is kept (`chat.tabs.*`).
import assert from "node:assert/strict";
import { test } from "node:test";
import { changed, tabsOf, type Change } from "../src/chat-tabs.ts";
import { parseCall } from "../src/core/calls.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const agent = (key: string, jobs: string[] = []): J => ({ session: { key }, jobs: jobs.map((id) => ({ id })) });
const AGENTS = [agent("a1", ["web"]), agent("a2")];
const FILE = `file:${JSON.stringify(["a1", "/out/chart.html", "chart.html"])}`;
const open = (tab: string): Change => ({ action: "open", tab, auto: true });
const close = (tab: string): Change => ({ action: "close", tab, auto: true });

test("a_chat_shows_the_tabs_kept_it_has_and_the_one_in_front", () => {
  const kept = { tabs: ["a1", "gone", "service:web", "service:old", "jobs", FILE, "file:[1]", "letters", "files"], active: "jobs" };
  assert.deepEqual(tabsOf(kept, AGENTS, false, "a1"), { open: ["a1", "service:web", "jobs", FILE, "letters", "files"], shown: "jobs" });
  // The one kept in front gone: the first.
  assert.deepEqual(tabsOf({ tabs: ["a2", "a1"], active: "gone" }, AGENTS, false, null), { open: ["a2", "a1"], shown: "a2" });
  // Its agents not known yet: all kept, the panel holding its place.
  assert.deepEqual(tabsOf({ tabs: ["x", "y"] }, [], false, null), { open: ["x", "y"], shown: "x" });
  // None kept: none, but where its agent has no chat yet its history, opened by itself.
  assert.deepEqual(tabsOf(undefined, AGENTS, false, "a1"), { open: [] });
  assert.deepEqual(tabsOf(undefined, AGENTS, true, "a1"), { open: ["a1"], shown: "a1", auto: true });
  assert.deepEqual(tabsOf({ tabs: [] }, AGENTS, true, "a1"), { open: [] }, "kept empty: closed on purpose");
});

test("an_agents_history_opens_after_the_histories_open_and_anything_else_last", () => {
  const kept = { tabs: ["a1", "jobs", "letters"], active: "jobs" };
  assert.deepEqual(changed(kept, AGENTS, false, null, open("a2")), { tabs: ["a1", "a2", "jobs", "letters"], active: "a2" });
  assert.deepEqual(changed({ tabs: ["jobs"] }, AGENTS, false, null, open("a2")), { tabs: ["a2", "jobs"], active: "a2" });
  assert.deepEqual(changed(kept, AGENTS, false, null, open("files")), { tabs: ["a1", "jobs", "letters", "files"], active: "files" });
  // One open already: brought to the front where it is.
  assert.deepEqual(changed(kept, AGENTS, false, null, open("letters")), { tabs: ["a1", "jobs", "letters"], active: "letters" });
  // Agents not known (a new chat's): last.
  assert.deepEqual(changed({ tabs: ["files"] }, [], false, null, open("a2")), { tabs: ["files", "a2"], active: "a2" });
  assert.deepEqual(changed(undefined, [], false, null, open("files")), { tabs: ["files"], active: "files" });
  // What it shows is what it goes from: a tab it does not have is not kept on.
  assert.deepEqual(changed({ tabs: ["gone", "a1"] }, AGENTS, false, null, open("jobs")), { tabs: ["a1", "jobs"], active: "jobs" });
});

test("closing_one_brings_the_last_left_to_the_front_if_it_was_in_front_and_clearing_keeps_none", () => {
  const kept = { tabs: ["a1", "a2", "jobs"], active: "a2" };
  assert.deepEqual(changed(kept, AGENTS, false, null, close("a2")), { tabs: ["a1", "jobs"], active: "jobs" });
  assert.deepEqual(changed(kept, AGENTS, false, null, close("a1")), { tabs: ["a2", "jobs"], active: "a2" });
  // None kept in front: the first was; the last left comes.
  assert.deepEqual(changed({ tabs: ["a1", "a2", "jobs"] }, AGENTS, false, null, close("a1")), { tabs: ["a2", "jobs"], active: "jobs" });
  assert.deepEqual(changed({ tabs: ["jobs"], active: "jobs" }, AGENTS, false, null, close("jobs")), { tabs: [] });
  assert.equal(changed(kept, AGENTS, false, null, close("letters")), null, "one not open: nothing");
  assert.deepEqual(changed(kept, AGENTS, false, null, { action: "front", tab: "jobs", auto: true }), { tabs: ["a1", "a2", "jobs"], active: "jobs" });
  assert.deepEqual(changed(kept, AGENTS, false, null, { action: "clear", tab: null, auto: true }), { tabs: [], active: "a2" });
});

test("the_history_a_chat_opens_by_itself_is_gone_from_where_a_client_shows_none", () => {
  // Shown (a wide page): what is opened joins it.
  assert.deepEqual(changed(undefined, AGENTS, true, "a1", open("jobs")), { tabs: ["a1", "jobs"], active: "jobs" });
  assert.deepEqual(changed(undefined, AGENTS, true, "a1", close("a1")), { tabs: [] });
  // Not shown (the panel would lie over the chat): from none.
  assert.deepEqual(changed(undefined, AGENTS, true, "a1", { action: "open", tab: "jobs", auto: false }), { tabs: ["jobs"], active: "jobs" });
  assert.equal(changed(undefined, AGENTS, true, "a1", { action: "close", tab: "a1", auto: false }), null);
});

test("the_calls_read_the_chat_and_the_tab", () => {
  assert.deepEqual(parseCall("chat.tabs.open", { chat: "ws/st:k1", tab: "jobs" }), { kind: "chatTabs", chat: "ws/st:k1", action: "open", tab: "jobs", auto: true });
  assert.deepEqual(parseCall("chat.tabs.close", { chat: "ws/st:k1", tab: "jobs", auto: false }), { kind: "chatTabs", chat: "ws/st:k1", action: "close", tab: "jobs", auto: false });
  assert.deepEqual(parseCall("chat.tabs.clear", { chat: "new:ws" }), { kind: "chatTabs", chat: "new:ws", action: "clear", tab: null, auto: true });
  assert.throws(() => parseCall("chat.tabs.front", { chat: "ws/st:k1" }));
  assert.throws(() => parseCall("chat.tabs.open", { chat: "", tab: "jobs" }));
});

test("a_chats_view_says_its_tabs_as_the_calls_change_them", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", session: "k1" });
  subscribe(core, ui, 2, { topic: "prefs" });
  await host.settle();
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).agents.map((a: J) => a.session.key), ["k1"]);
  assert.deepEqual(v(values, 1).tabs, { open: [] });
  call(core, ui, 3, "chat.tabs.open", { chat: "ws/st:k1", tab: "jobs" });
  await host.settle();
  call(core, ui, 4, "chat.tabs.open", { chat: "ws/st:k1", tab: "k1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).tabs, { open: ["k1", "jobs"], shown: "k1" });
  assert.deepEqual([v(values, 2).chatTabs["ws/st:k1"].tabs, v(values, 2).chatTabs["ws/st:k1"].active], [["k1", "jobs"], "k1"]);
  call(core, ui, 5, "chat.tabs.close", { chat: "ws/st:k1", tab: "k1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).tabs, { open: ["jobs"], shown: "jobs" });
  // A workspace's new chat's (no chat to go by): kept all the same.
  call(core, ui, 6, "chat.tabs.open", { chat: "new:ws", tab: "files" });
  await host.settle();
  call(core, ui, 7, "chat.tabs.close", { chat: "new:ws", tab: "files" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 2).chatTabs["new:ws"].tabs, []);
  core.close();
});
