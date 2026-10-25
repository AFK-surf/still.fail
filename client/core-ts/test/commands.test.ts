// ⌘K's commands (src/commands.ts, `commands.find`): what of what a client can do now the list offers for what was
// typed, named by the core where it knows them, by part.
import assert from "node:assert/strict";
import { test } from "node:test";
import { find as findWith } from "../src/commands.ts";
import { t } from "../src/i18n.ts";
import { answers, call, cloudCore } from "./helpers.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// What a page in a chat can do: the keys' actions it answers (in the keymap's order), then what it offers.
const offered = [
  { id: "chat.switch" }, { id: "chat.new" }, { id: "chat.prev" }, { id: "sidebar.toggle" }, { id: "settings" }, { id: "shortcuts" },
  { id: "composer.focus" }, { id: "chat.stop" }, { id: "chat.find" }, { id: "chat.archive" }, { id: "panel.close" },
  { id: "update.station", station: "studio" }, { id: "chat.relay" },
  { id: "update.app", version: "0.1.2000" }, { id: "update.check" },
  { id: "settings/appearance", group: "settings", label: "外观", words: "设置 settings appearance theme", typed: true },
  { id: "drive/st", group: "settings", label: "文件 · studio", words: "文件 files drive studio", typed: true },
];

const find = (query: string, offered: readonly unknown[]) => findWith(query, offered, t);
const shown = (r: ReturnType<typeof find>) => r.groups.map((g) => [g.group, g.title, g.commands.map((c) => c.id)]);

test("with_nothing_typed_the_list_offers_what_can_be_done_by_part_but_what_only_typing_finds", () => {
  const r = find("", offered);
  assert.deepEqual(shown(r), [
    ["chat", "当前对话", ["chat.stop", "chat.find", "chat.archive", "chat.relay"]],
    ["update", "更新", ["update.station", "update.app"]],
    ["global", "通用", ["chat.new", "sidebar.toggle", "settings", "shortcuts"]],
  ]);
  // Named by the core, what each takes in its name.
  const label = (id: string) => r.groups.flatMap((g) => g.commands).find((c) => c.id === id)?.label;
  assert.equal(label("chat.new"), "新建对话");
  assert.equal(label("update.station"), "更新 station · studio");
  assert.equal(label("update.app"), "更新到 0.1.2000");
  assert.equal(label("chat.relay"), "接力到频道…");
});

test("what_is_typed_finds_a_command_by_its_name_its_id_or_its_other_words", () => {
  // Its name.
  assert.deepEqual(shown(find("  查找 ", offered)), [["chat", "当前对话", ["chat.find"]]]);
  // Its id, without case.
  assert.deepEqual(shown(find("Chat.Arch", offered)), [["chat", "当前对话", ["chat.archive"]]]);
  // Its other words: one only found by typing too (looking for an update), a client's own (a settings page).
  assert.deepEqual(shown(find("update", offered)), [["update", "更新", ["update.station", "update.app", "update.check"]]]);
  assert.deepEqual(shown(find("飞书", offered)), []);
  assert.deepEqual(shown(find("feishu", offered)), [["chat", "当前对话", ["chat.relay"]]]);
  assert.deepEqual(shown(find("设置", offered)), [["global", "通用", ["settings"]], ["settings", "设置", ["settings/appearance"]]]);
  assert.deepEqual(shown(find("files", offered)), [["settings", "设置", ["drive/st"]]]);
});

test("the_moves_only_worth_a_key_are_never_listed_and_what_has_no_name_or_part_is_left_out", () => {
  const r = find("chat", [
    { id: "chat.switch" }, { id: "chat.prev" }, { id: "chat.next" }, { id: "chat.latest" }, { id: "nav.back" },
    // One the core does not name, without words of its own; one in no part the list has; no id; one given twice.
    { id: "chat.mystery" }, { id: "chat.elsewhere", group: "nowhere", label: "chat" }, { label: "chat" }, "chat",
    { id: "chat.find" }, { id: "chat.find" },
  ]);
  assert.deepEqual(shown(r), [["chat", "当前对话", ["chat.find"]]]);
  assert.deepEqual(find("", []), { groups: [] });
});

test("a_client_asks_the_core_for_the_commands_by_name", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  call(core, ui, 1, "commands.find", { query: "新建", offered: [{ id: "chat.new" }, { id: "chat.find" }] });
  await host.settle();
  const answer = answers(host.takeEmitted(), 1) as J;
  assert.deepEqual(answer.ok, { groups: [{ group: "global", title: "通用", commands: [{ id: "chat.new", label: "新建对话" }] }] });
  // Its params as the other calls' are read: a list, or none.
  call(core, ui, 2, "commands.find", { offered: "chat.new" });
  await host.settle();
  assert.ok("error" in (answers(host.takeEmitted(), 2) as J));
  call(core, ui, 3, "commands.find", {});
  await host.settle();
  assert.deepEqual((answers(host.takeEmitted(), 3) as J).ok, { groups: [] });
  core.close();
});
