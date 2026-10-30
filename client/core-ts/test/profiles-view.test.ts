// The workspace's profiles in one list (src/views/profiles.ts): a shared one once, from its host while that one is read;
// one on a station only with that station; a shared subscription whose host is away, unusable and first.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { profile as shownProfile } from "../src/present.ts";
import { runtimes } from "../src/views/models.ts";
import { workspaceProfiles } from "../src/views/profiles.ts";

holdLanguage();

const A = "a".repeat(64);
const B = "b".repeat(64);
const profile = (id: string, extra: Record<string, unknown> = {}) => ({ id, name: id, access: { kind: "subscription" }, checkTone: "green", ...extra });
const station = (id: string, name: string, online: boolean, profiles: unknown[] | null) => ({ id, station: `w/${id}`, name, online, overview: profiles === null ? undefined : { sharing: true, profiles } });

test("a shared profile is listed once, from its host, with where it is signed in and who borrows it", () => {
  const share = { id: "sh-1", host: A, allow: [A, B] };
  const view = workspaceProfiles([
    station(A, "studio", true, [profile("max", { share: { ...share, role: "host" } }), profile("local", { access: { kind: "env" } })]),
    station(B, "mini", true, [profile("sh-1", { share: { ...share, role: "user", reachable: true } })]),
  ]);
  assert.equal(view.items.length, 2);
  const shared = view.items.find((e: any) => e.shared);
  assert.equal(shared.key, "share:sh-1");
  assert.deepEqual(shared.members.map((m: any) => [m.stationName, m.role]), [["studio", "host"], ["mini", "user"]]);
  assert.equal(shared.station, `w/${A}`, "its page is on its host");
  assert.equal(shared.profile.id, "max");
  assert.equal(shared.where, "已在 studio 登录 · 借给 mini");
  assert.equal(shared.usable, true);
  assert.deepEqual(shared.stations.map((s: any) => [s.name, s.allowed]), [["studio", true], ["mini", true]]);
  const local = view.items.find((e: any) => !e.shared);
  assert.equal(local.where, "仅在 studio");
  assert.equal(local.canShare, true);
});

test("a shared subscription whose host is away comes from a copy, unusable, first", () => {
  const share = { id: "sh-1", host: A, allow: null };
  const view = workspaceProfiles([
    station(A, "studio", false, null),
    station(B, "mini", true, [profile("b-own", { access: { kind: "env" } }), profile("sh-1", { name: "Max", share: { ...share, role: "user", reachable: true } })]),
  ]);
  assert.equal(view.items[0].key, "share:sh-1");
  assert.equal(view.items[0].usable, false);
  assert.deepEqual([view.items[0].look, view.items[0].state], [true, { text: "studio 离线", tone: "red" }]);
  assert.equal(view.attention, 1);
  assert.equal(view.items[0].editable, false);
  // Still listed as up by the cloud, but not answering the station borrowing it: away all the same.
  const late = workspaceProfiles([
    station(A, "studio", true, null),
    station(B, "mini", true, [profile("sh-1", { share: { ...share, role: "user", reachable: false } })]),
  ]);
  assert.equal(late.items[0].usable, false);
  assert.equal(late.wait.reading, true, "studio is up and not read yet");
});

test("what needs a look says so in its row, is counted and comes first in its kind: its allowance not read as much as a sign-in wanted", () => {
  const shown = (id: string, extra: Record<string, unknown>) => shownProfile(profile(id, { email: `${id}@x.test`, runtime: "claude", ...extra }));
  const view = workspaceProfiles([
    station(A, "studio", true, [
      shown("a-fine", { check: { state: "ok" }, quota: { state: "ok", windows: [] } }),
      shown("b-new", {}),
      shown("c-quota", { check: { state: "ok" }, quota: { state: "unavailable", detail: "Kimi Code 没有返回额度信息" } }),
      shown("d-login", { check: { state: "login" } }),
    ]),
  ]);
  assert.deepEqual(view.items.map((e: any) => [e.profile.id, e.look, e.state]), [
    ["c-quota", true, { text: "额度查询失败", tone: "amber" }],
    ["d-login", true, { text: "需要登录", tone: "amber" }],
    ["a-fine", false, null],
    // (not checked yet: said, but nothing to look at)
    ["b-new", false, { text: "未检查", tone: "neutral" }],
  ]);
  assert.equal(view.attention, 2);
});

test("the same account signed in on two stations each is one row, each station a member", () => {
  const view = workspaceProfiles([
    station(A, "studio", true, [profile("max", { email: "Z@x.test", runtime: "claude" })]),
    station(B, "mini", true, [profile("max-2", { email: "z@x.test", runtime: "claude", checkTone: "red" })]),
  ]);
  assert.equal(view.items.length, 1);
  const row = view.items[0];
  assert.equal(row.where, "已在 studio、mini 登录");
  assert.equal(row.profile.id, "max", "the row shows the first one that is up and has its login");
  assert.deepEqual(row.members.map((m: any) => [m.stationName, m.role, m.about]), [["studio", "own", "在此 station 单独登录"], ["mini", "own", "在此 station 单独登录"]]);
  // Two different accounts stay two rows.
  const two = workspaceProfiles([
    station(A, "studio", true, [profile("a", { email: "a@x.test", runtime: "claude" })]),
    station(B, "mini", true, [profile("b", { email: "b@x.test", runtime: "claude" })]),
  ]);
  assert.equal(two.items.length, 2);
});

test("an account signed in on every station it is lent to: the row says where it is signed in, and no limit that reads as the whole account's", () => {
  const C = "c".repeat(64);
  const share = { id: "sh-1", host: A, allow: [C] };
  const view = workspaceProfiles([
    station(A, "Studio", true, [profile("codex-3720", { email: "z@x.test", runtime: "codex", share: { ...share, role: "host", users: [C] } })]),
    station(B, "Mini1", true, [profile("codex", { email: "z@x.test", runtime: "codex" })]),
    station(C, "ccvm", true, [profile("own", { email: "z@x.test", runtime: "codex" }), profile("sh-1", { email: "z@x.test", runtime: "codex", share: { ...share, role: "user", reachable: true } })]),
  ]);
  assert.equal(view.items.length, 1);
  assert.equal(view.items[0].where, "已在 Studio、Mini1、ccvm 登录");
  // Borrowed by one not signed in itself: the lender named, as two others are signed in too.
  const lent = workspaceProfiles([
    station(A, "Studio", true, [profile("codex-3720", { email: "z@x.test", runtime: "codex", share: { ...share, role: "host", users: [C] } })]),
    station(B, "Mini1", true, [profile("codex", { email: "z@x.test", runtime: "codex" })]),
    station(C, "ccvm", true, [profile("sh-1", { email: "z@x.test", runtime: "codex", share: { ...share, role: "user", reachable: true } })]),
  ]);
  assert.equal(lent.items[0].where, "已在 Studio、Mini1 登录 · Studio 借给 ccvm");
});

test("a station with two profiles signed in to the same account: its rows named by their profiles too", () => {
  const view = workspaceProfiles([
    station(A, "default", true, [profile("工作", { email: "z@x.test", runtime: "codex" }), profile("备用", { email: "z@x.test", runtime: "codex" })]),
    station(B, "mini", true, [profile("max", { email: "z@x.test", runtime: "codex" })]),
  ]);
  assert.equal(view.items.length, 1);
  assert.deepEqual(view.items[0].members.map((m: any) => m.title), ["default · 工作", "default · 备用", "mini"]);
});

test("an account signed in on two stations, signed out on one: the row shows the one that works and names where the other needs a look", () => {
  const signedOut = shownProfile(profile("machine-claude", { email: "z@x.test", runtime: "claude", machine: true, check: { state: "login" } }));
  const fine = shownProfile(profile("machine-claude", { email: "z@x.test", runtime: "claude", machine: true, check: { state: "ok" } }));
  const view = workspaceProfiles([station(A, "macbook", true, [signedOut]), station(B, "mini", true, [fine])]);
  assert.equal(view.items.length, 1);
  const row = view.items[0];
  assert.equal(row.stationName, "mini", "the copy that works");
  assert.deepEqual([row.look, row.state], [true, { text: "macbook：需要登录", tone: "amber" }]);
  // Both fine: nothing said.
  const both = workspaceProfiles([station(A, "macbook", true, [fine]), station(B, "mini", true, [fine])]);
  assert.deepEqual([both.items[0].look, both.items[0].state, both.items[0].stationName], [false, null, "macbook"]);
});

test("the list is grouped by kind of account: Claude's subscriptions, ChatGPT's, SuperGrok's, Kimi Code's and OpenCode Go's signed in, Cursor's, Devin's, then keys", () => {
  const view = workspaceProfiles([
    station(A, "studio", true, [
      profile("key", { access: { kind: "api-provider" } }),
      profile("go-key", { access: { kind: "opencode-go", key: "sk-1…2345" } }),
      profile("go", { access: { kind: "opencode-go", key: "st_1…2345", login: true } }),
      profile("kimi", { access: { kind: "env", provider: "kimi-code", login: true } }),
      profile("dev", { email: "d@x.test", runtime: "devin" }),
      profile("cur", { email: "c@x.test", runtime: "cursor" }),
      profile("super", { email: "s@x.test", runtime: "grok" }),
      profile("gpt", { email: "g@x.test", runtime: "codex" }),
      profile("b-claude", { email: "b@x.test", runtime: "claude" }),
      profile("a-claude", { email: "a@x.test", runtime: "claude", checkTone: "red" }),
    ]),
  ]);
  assert.deepEqual(view.items.map((e: any) => [e.group, e.groupTitle, e.profile.id]), [
    ["claude", "Claude 订阅", "a-claude"],
    ["claude", "Claude 订阅", "b-claude"],
    ["chatgpt", "ChatGPT 订阅", "gpt"],
    ["grok", "SuperGrok 订阅", "super"],
    ["kimi", "Kimi Code 订阅", "kimi"],
    ["opencode", "OpenCode Go 订阅", "go"],
    ["cursor", "Cursor 订阅", "cur"],
    ["devin", "Devin 订阅", "dev"],
    ["key", "API Key", "go-key"],
    ["key", "API Key", "key"],
  ]);
});

test("two profiles of one station signed in to the same account: the station said once where it is signed in", () => {
  const view = workspaceProfiles([
    station(A, "studio", true, [profile("codex", { email: "z@x.test", runtime: "codex" }), profile("codex-2", { email: "z@x.test", runtime: "codex" })]),
    station(B, "mini", true, [profile("codex-3", { email: "z@x.test", runtime: "codex" })]),
  ]);
  assert.equal(view.items.length, 1);
  assert.equal(view.items[0].members.length, 3, "each profile still a member");
  assert.equal(view.items[0].where, "已在 studio、mini 登录");
});

test("Hermes profiles can name models and expose a selected model to new chats", () => {
  const base = { id: "hm", name: "Hermes", runtime: "hermes", runtimes: ["hermes"], access: {kind:"env"}, models: [], env: [] };
  assert.equal(shownProfile(base).canAddModel, true);
  const listed = shownProfile({...base, check: {state:"ok",models:["openrouter:model-a"],detail:""}});
  assert.ok(listed.available.includes("openrouter:model-a"));
  const selected = {...base,models:["openrouter:model-a"]};
  assert.deepEqual(runtimes({profiles:[selected]}),[{runtime:"hermes",models:["openrouter:model-a"]}]);
});
