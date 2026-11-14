// The Rust core's refs.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Data } from "../src/data.ts";
import { holdLanguage } from "../src/i18n.ts";
import { draftAt, expand, KEPT, keep, link, mark, opened, OPENED_KEPT, openedIn, search, title } from "../src/refs.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";

holdLanguage();
const data = () => {
  const host = new FakeHost();
  const d = new Data(host, new Runner(host.time.clock), { owner: () => "s1" });
  Effect.runSync(d.open(["s1"]));
  return d;
};

test("a_reference_shows_the_start_of_the_title_on_one_line", () => {
  assert.equal(title("修一下 [登录]\n  的问题"), "修一下 登录 的问题");
  assert.equal(title("一二三四五六七八九十一二三四五六七八九十一二三 四五"), "一二三四五六七八九十一二三四五六七八九十一二三…");
  assert.equal(title(" \n "), "对话");
  assert.equal(link("https://app.still.fail/", "ws/st", "a b/c"), "https://app.still.fail/w/ws/s/st/chats/a%20b%2Fc");
  assert.deepEqual(draftAt("new:ws"), ["ws", "new"]);
  assert.deepEqual(draftAt("ws/st:thread:7"), ["ws/st", "thread:7"]);
  assert.equal(draftAt("nothing"), null);
});

test("marks_go_out_as_links_while_their_link_is_kept", () => {
  const d = data();
  assert.equal(mark(d, "https://x", "ws/st", "k1", "排查登录"), "@[排查登录]");
  assert.equal(mark(d, "https://x", "ws/st", "k2", "看看"), "@[看看]");
  mark(d, "https://x", "ws/st", "k3", "看看");
  assert.equal(expand(d, "ws/st", "见 @[排查登录] 和 @[看看]，@[没有] @[ 不完整 @"), "见 [排查登录](https://x/w/ws/s/st/chats/k1) 和 [看看](https://x/w/ws/s/st/chats/k3)，@[没有] @[ 不完整 @");
  keep(d, Array.from({ length: KEPT }, (_, i) => [`t${i}`, `https://x/w/ws/s/st/chats/l${i}`] as [string, string]));
  assert.equal(expand(d, "ws/other", "@[排查登录] @[t0]"), "@[排查登录] [t0](https://x/w/ws/s/st/chats/l0)");
});

test("a_mark_is_a_link_only_in_a_chat_of_its_workspace", () => {
  const d = data();
  d.put("chat_ref", "links", [["旧的", "https://x/w/w1/s/st/chats/k0"], ["本机", "/admin/chats/k9"]]);
  mark(d, "https://x", "w1/st", "k1", "排查登录");
  mark(d, "https://x", "w2/st", "k2", "看看");
  const text = "@[排查登录] @[看看] @[旧的] @[本机]";
  assert.equal(expand(d, "w1/st", text), "[排查登录](https://x/w/w1/s/st/chats/k1) @[看看] [旧的](https://x/w/w1/s/st/chats/k0) @[本机]");
  assert.equal(expand(d, "w2/a", text), "@[排查登录] [看看](https://x/w/w2/s/st/chats/k2) @[旧的] @[本机]");
  keep(d, [["本机", "/admin/chats/k9"]]);
  assert.equal(expand(d, "w1/st", "@[本机]"), "@[本机]");
});

test("a_search_finds_titles_first_then_what_else_a_chat_says", () => {
  const item = (id: string, ti: string, station: string, preview: string) => ({ id, session: `s${id}`, title: ti, station, stationName: "Studio", agents: [], last: { preview } });
  const pending = { ...item("p", "登录 新的", "a", ""), pending: true };
  const chats = { days: [{ items: [item("1", "别的", "a", "修登录"), item("2", "登录页", "a", ""), pending] }, { items: [item("3", "登录", "b", ""), item("4", "登录 旧的", "a", "")] }] };
  const ids = (v: { items: { id: string }[] }) => v.items.map((i) => i.id);
  assert.deepEqual(ids(search(chats, " 登录 ", null, null, null)), ["2", "3", "4", "1"]);
  // Written on `a`: every station's, `b`'s saying so.
  assert.deepEqual(search(chats, "", "a", "s2", 3).items.map((i: { id: string; otherStation?: boolean }) => [i.id, i.otherStation ?? false]), [["1", false], ["3", true], ["4", false]]);
  assert.deepEqual(ids(search(chats, "STUDIO", null, null, null)), ["1", "2", "3", "4"]);
});

test("a_search_lists_the_chats_opened_latest_first_then_the_rest_by_when_they_were_last_active", () => {
  const item = (id: string, ti: string, at: number | undefined, more: Record<string, unknown> = {}) => ({ id, session: `s${id}`, title: ti, station: "w/a", stationName: "Studio", agents: [], last: { preview: "" }, lastActiveAt: at, ...more });
  // The pinned first in the list, as the sidebar has them.
  const chats = {
    days: [
      { items: [item("p", "置顶 登录", 1, { pinned: true })] },
      { items: [item("1", "登录页", 5), item("2", "别的", 7, { last: { preview: "修登录" } }), item("3", "登录 旧的", 3), item("4", "无关", 9, { last: { preview: "登录不上" } }), item("5", "登录 无时", undefined), item("6", "登录 也无时", undefined)] },
    ],
  };
  const ids = (v: { items: { id: string }[] }) => v.items.map((i) => i.id);
  // Nothing opened: by when last active, the latest first, pinned or not; none known as 0, in the order they were.
  assert.deepEqual(ids(search(chats, "", null, null, null)), ["4", "2", "1", "3", "p", "5", "6"]);
  // Opened (by its id or its key), the latest first, then the rest so; one of another station is none of these.
  const open: [string, string][] = [["w/a", "s3"], ["w/a", "p"], ["w/b", "1"], ["w/a", "6"]];
  assert.deepEqual(ids(search(chats, "", null, null, null, open)), ["3", "p", "6", "4", "2", "1", "5"]);
  assert.deepEqual(ids(search(chats, "", null, null, 2, open)), ["3", "p"]);
  // Typed: those whose title has it, then those found in what else they say, each in that order.
  assert.deepEqual(ids(search(chats, "登录", null, null, null, open)), ["3", "p", "6", "1", "5", "4", "2"]);
  assert.deepEqual(ids(search(chats, "登录", null, null, null, [["w/a", "s2"]])), ["1", "3", "p", "5", "6", "2", "4"]);
  // What was given is as it was.
  assert.deepEqual(chats.days[1]!.items.map((i) => i.id), ["1", "2", "3", "4", "5", "6"]);
});

test("the_chats_opened_are_kept_each_once_the_latest_50_of_each_workspace", () => {
  const d = data();
  opened(d, "w1/a", "k1");
  opened(d, "w1/b", "k2");
  opened(d, "w2/a", "k3");
  opened(d, "w1/a", "k1");
  assert.deepEqual(openedIn(d, "w1"), [["w1/a", "k1"], ["w1/b", "k2"]]);
  assert.deepEqual(openedIn(d, "w2"), [["w2/a", "k3"]]);
  // Told again while it is the latest: nothing written.
  const put = d.put.bind(d);
  let writes = 0;
  d.put = (...args: Parameters<typeof put>) => {
    writes++;
    put(...args);
  };
  opened(d, "w1/a", "k1");
  assert.equal(writes, 0);
  d.put = put;
  for (let i = 0; i < OPENED_KEPT + 5; i++) opened(d, "w1/a", `n${i}`);
  const kept = openedIn(d, "w1");
  assert.equal(kept.length, OPENED_KEPT);
  assert.deepEqual(kept[0], ["w1/a", `n${OPENED_KEPT + 4}`]);
  assert.deepEqual(kept[OPENED_KEPT - 1], ["w1/a", "n5"]);
  assert.equal(new Set(kept.map(([s, k]) => `${s} ${k}`)).size, OPENED_KEPT);
});

test("other_workspaces_chats_are_offered_only_for_what_is_typed_and_never_crowd_this_ones", async () => {
  const { withOutside, OUTSIDE_SHOWN } = await import("../src/refs.ts");
  const item = (title: string, more: Record<string, unknown> = {}) => ({ id: title, title, ...more });
  const local = [item("登录页"), item("别的", { matched: "by its last message" }), item("修登录")];
  const outside = [item("登录流程 A", { outside: "甲" }), item("登录流程 B", { outside: "甲", xshare: { to: ["ws"], write: false } }), item("无关", { outside: "甲" }), item("登录 C", { outside: "乙" }), item("登录 D", { outside: "乙" })];
  // Nothing typed: this workspace's only.
  assert.deepEqual(withOutside(local, outside, " ", "ws", 8).map((i) => i.id), ["登录页", "别的", "修登录"]);
  // Typed: this workspace's whose title has it, then at most a few of others' whose title has it (one shared with this
  // workspace first), then the rest of this workspace's.
  const found = withOutside(local, outside, "登录", "ws", 8).map((i) => i.id);
  assert.deepEqual(found, ["登录页", "修登录", "登录流程 B", "登录流程 A", "登录 C", "别的"]);
  assert.equal(found.filter((id) => outside.some((o) => o.id === id)).length, OUTSIDE_SHOWN);
  assert.deepEqual(withOutside(local, outside, "登录", "ws", 3).map((i) => i.id), ["登录页", "修登录", "登录流程 B"]);
});
