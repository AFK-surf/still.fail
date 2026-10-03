// The Rust core's refs.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Data } from "../src/data.ts";
import { holdLanguage } from "../src/i18n.ts";
import { draftAt, expand, KEPT, keep, link, mark, search, title } from "../src/refs.ts";
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
  assert.deepEqual(draftAt("new:ws/st"), ["ws/st", "new"]);
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
  assert.deepEqual(ids(search(chats, "", "a", "s2", 2)), ["1", "4"]);
  assert.deepEqual(ids(search(chats, "STUDIO", null, null, null)), ["1", "2", "3", "4"]);
});
