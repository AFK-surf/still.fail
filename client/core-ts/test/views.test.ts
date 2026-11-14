// The Rust core's views.rs tests, ported: a store whose topics the test sets, the views routed as core.ts does.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Choose } from "../src/choose.ts";
import { applyKeyed } from "../src/collections.ts";
import { CoreError } from "../src/error.ts";
import { apply as applyOps } from "../src/delta.ts";
import * as format from "../src/format.ts";
import { holdLanguage, t as words } from "../src/i18n.ts";
import { merge } from "../src/entries.ts";
import { topicKey, type Topic } from "../src/protocol.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { attention, choices, models, quotaFor, runnableOn } from "../src/views/models.ts";
import { OVERVIEW_FIT, answeredAt, betaOffered, blockedUnder, down, noticeOf, shownMessage, stationOn } from "../src/views/views.ts";
import { localDay } from "../src/views/usage.ts";
import { decorate, installView, profile as presentProfile } from "../src/present.ts";
import { conformTy } from "../src/conform.ts";
import { markdown } from "../src/markdown.ts";
import { work, workSince } from "../src/work.ts";
import { hostOf, link, overview, prefs, rows, sessions, setup, sorted, threads, ui, workspace, type Ui } from "./views-rig.ts";
import { dbName } from "../src/data.ts";
import { VERSION, overviewPartOf } from "../src/db/schema.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const DAY_MS = 86_400_000;

const sortedKeys = (topics: Topic[]) => topics.map(topicKey).sort();
const sameTopics = (a: Topic[], b: Topic[], message?: string) => assert.deepEqual(sortedKeys(a), sortedKeys(b), message);

function stations(nowS: number): J {
  return {
    id: "ws",
    stations: [
      { id: "a", name: "alpha", last_seen: Math.trunc(nowS) - 10, version: "0.4.0" },
      { id: "b", name: "beta", last_seen: Math.trunc(nowS) - 1000, version: null },
      { id: "c", name: "gamma", last_seen: null, version: null },
    ],
  };
}
const oneStation = (): J => ({ id: "ws", stations: [{ id: "st", name: "studio", last_seen: null, version: null }] });
const session = (key: string): J => ({ key, connect: "c1", profile: "p1", runtime: "claude", model: "opus", effort: null, process: "cold", pending: 0, lastTurn: null });
const member = (thread: number, key: string, connect: string): J => ({ thread, session: key, connect, joinedAt: 1 });
const fullSession = (key: string, patch: J = {}): J => ({
  key, connect: "c1", scope: "thread", title: null, createdBy: null, boundTo: [], creator: null, participants: [], runtime: "claude", profile: "p1",
  profilePinned: false, model: null, effort: null, runtimeSessionId: null, workspace: "/w", running: false, createdAt: 1, lastActiveAt: 1, archivedAt: null,
  process: "cold", turns: 0, pending: 0, firstText: null, lastTurn: null, ...patch,
});
const turn = (id: string): J => ({ id, kind: "chat", outcome: null, declared: null, detail: null, startedAt: 1, endedAt: null });
const profile = (id: string, patch: J = {}): J => ({
  id, name: id, runtime: "claude", runtimes: ["claude"], access: { kind: "subscription", key: "" }, home: "/h", homeExists: true, model: null, models: [],
  env: [], usedBy: [], loginCommand: "", check: null, login: null, quota: null, ...patch,
});
const overviewOf = (connects: J[], profiles: J[]): J => ({
  viewer: { via: "local" }, connects, profiles, processes: [], counts: { sessions: 0, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [],
});
const hostInfo = (hostname: string): J => ({
  hostname, os: "macOS 26", arch: "arm64", cpus: 8, cpuModel: "M4", load: 0.2, uptimeSec: 100,
  memory: { totalBytes: 1024, usedBytes: 512, swapUsedBytes: null }, disk: { path: "/", totalBytes: 1024, freeBytes: 512 }, stationRssBytes: 10, checkedAt: 1,
});

for (const name of ["usage", "profiles"]) {
  test(`${name}_is_not_rebuilt_for_a_stations_host_or_route_reading`, async () => {
    const t = setup();
    const u = ui();
    const topic: Topic = name === "usage" ? { topic: name, scope: "ws", days: 7 } : { topic: name, scope: "ws" };
    // The stations page also watches these readings, so they continue to arrive while this view is live.
    t.store.watch(hostOf("ws/st"), () => {});
    t.store.watch({ topic: "way", station: "ws/st" }, () => {});
    t.set(workspace(), oneStation());
    t.set(link("ws/st"), { state: "online" });
    t.set(overview("ws/st"), overviewOf([], [profile("p1")]));
    t.set(hostOf("ws/st"), hostInfo("studio"));
    t.set({ topic: "stationUsage", station: "ws/st" }, { rows: [], since: 0, reading: false });
    t.subscribe(1, topic);
    await t.read(u, 1);
    assert.ok(u.value, `${name} is shown`);
    const before = t.router.computed;
    t.set(hostOf("ws/st"), { ...hostInfo("studio"), load: 0.8, checkedAt: 2 });
    await t.read(u, 1);
    assert.equal(t.router.computed, before, `${name} did not change when the host's load changed`);
    t.set({ topic: "way", station: "ws/st" }, { via: "relay", rttMs: 123 });
    await t.read(u, 1);
    assert.equal(t.router.computed, before, `${name} did not change when the route changed`);
  });

  test(`${name}_is_not_rebuilt_for_unrelated_station_overview_or_link_changes`, async () => {
    const t = setup();
    const u = ui();
    const topic: Topic = name === "usage" ? { topic: name, scope: "ws", days: 7 } : { topic: name, scope: "ws" };
    const over = overviewOf([], [profile("p1")]);
    t.store.watch(link("ws/st"), () => {});
    t.set(workspace(), oneStation());
    t.set(link("ws/st"), { state: "online" });
    t.set(overview("ws/st"), over);
    t.set({ topic: "stationUsage", station: "ws/st" }, { rows: [], since: 0, reading: false });
    t.subscribe(1, topic);
    await t.read(u, 1);
    const before = t.router.computed;
    t.set(overview("ws/st"), { ...over, counts: { sessions: 3, running: 2, warm: 1 } });
    await t.read(u, 1);
    assert.equal(t.router.computed, before, `${name} did not change when an agent started`);
    t.set(link("ws/st"), { state: "online", catching: 2 });
    await t.read(u, 1);
    assert.equal(t.router.computed, before, `${name} did not change while the link stayed online`);
  });
}

/// A list's rows as they are shown: each as its station's state makes it, said once for the station (`stations`).
/// A topic's value as the core holds it (`store.value`): whole, what its shape leaves out of what goes out too.
const whole = (t: ReturnType<typeof setup>, topic: Topic): J => {
  const v = t.store.value(topic);
  return v !== undefined && "ok" in v ? v.ok : undefined;
};
/// Each row of a list as its whole row (`chatRow`) gives it, as a press, a hold, a swipe or a pointer reads it, by its
/// id: asked by its id where rows of the fixture share a session (`row`: every numbered one's is "s").
async function wholeOf(t: ReturnType<typeof setup>, list: J, from = 900): Promise<Record<string, J>> {
  const items: J[] = list.days.flatMap((d: J) => d.items);
  const asked: [Ui, number][] = items.map((i, n) => {
    t.subscribe(from + n, { topic: "chatRow", station: i.station, session: items.filter((j) => j.session === i.session).length > 1 ? i.id : i.session });
    return [ui(), from + n];
  });
  await t.readAll(asked);
  return Object.fromEntries(items.map((i, n) => [i.id, asked[n][0].value]));
}
const shownRows = (v: J): J[] => v.days.flatMap((d: J) => d.items).map((i: J) => stationOn(i, v.stations.find((s: J) => s.station === i.station)));

test("usage_keeps_its_spending_and_account_allowance_current", async () => {
  const t = setup();
  const u = ui();
  const quota = (usedPercent: number) => ({ state: "ok", windows: [{ label: "5h", usedPercent }], checkedAt: 1 });
  t.set(workspace(), oneStation());
  t.set(link("ws/st"), { state: "online" });
  t.set(overview("ws/st"), overviewOf([], [profile("p1", { quota: quota(20) })]));
  t.set({ topic: "stationUsage", station: "ws/st" }, { rows: [], since: 0, reading: false });
  t.subscribe(1, { topic: "usage", scope: "ws", days: 7 });
  await t.read(u, 1);
  // (each account's allowance is the core's: the profiles' page says it, the usage page is not sent it)
  const usage = { topic: "usage", scope: "ws", days: 7 };
  assert.equal(u.value.accounts, undefined);
  assert.equal(whole(t, usage).accounts[0].quota.windows[0].usedPercent, 20);
  const now = t.host.nowMs();
  const day = localDay(now, t.host.utcOffsetMin(now));
  t.set({ topic: "stationUsage", station: "ws/st" }, { rows: [{ day, session: "s1", thread: 7, person: "Me@x.com", profile: "p1", model: "claude-opus-5-5", calls: 1, cost: 2 }], since: 0, reading: false });
  await t.read(u, 1);
  assert.equal(u.value.tiles[0].value, "$2.00");
  t.set(overview("ws/st"), overviewOf([], [profile("p1", { quota: quota(70) })]));
  await t.read(u, 1);
  assert.equal(whole(t, usage).accounts[0].quota.windows[0].usedPercent, 70);
  t.set(link("ws/st"), { state: "offline" });
  await t.read(u, 1);
  assert.ok(u.value.notes.some((s: string) => s.includes("studio")));
});

test("usage keeps its available history visible while recent details are prepared", async () => {
  const t = setup();
  const u = ui();
  const topic = { topic: "stationUsage", station: "ws/st" } as const;
  t.set(workspace(), oneStation());
  t.set(link("ws/st"), { state: "online" });
  t.set(overview("ws/st"), overviewOf([], []));
  t.set(topic, { rows: [], since: 0, reading: false, detailsPreparing: true,
    history: { days: [], places: {}, archived: 0, remoteRuns: 0, cards: 0, picked: 0 } });
  t.subscribe(1, { topic: "usage", scope: "ws", days: 7 });
  t.views.start({ topic: "fleet", scope: "ws" });
  await t.read(u, 1);
  assert.ok(u.value.summary, "the already available history can be seen");
  assert.equal(u.value.detailsPreparing, true, "the recent totals are not presented as zero");
  assert.equal(u.value.wait.reading, true);
  assert.equal(t.views.compute({ topic: "fleet", scope: "ws" }), undefined, "a shareable poster does not present missing usage as complete");

  t.set(topic, { rows: [], since: 0, reading: false,
    history: { days: [], places: {}, archived: 0, remoteRuns: 0, cards: 0, picked: 0 } });
  await t.read(u, 1);
  assert.notEqual(u.value.detailsPreparing, true);
  assert.equal(u.value.wait.reading, false);
  assert.ok(t.views.compute({ topic: "fleet", scope: "ws" }), "the poster is available once the recent details are ready");
});

test("profiles_keep_their_names_and_online_state_current", async () => {
  const t = setup();
  const u = ui();
  t.set(workspace(), oneStation());
  t.set(overview("ws/st"), overviewOf([], [profile("p1", { name: "Old" })]));
  t.subscribe(1, { topic: "profiles", scope: "ws" });
  await t.read(u, 1);
  assert.equal(u.value.items[0].title, "Old");
  t.set(overview("ws/st"), overviewOf([], [profile("p1", { name: "New" })]));
  await t.read(u, 1);
  assert.equal(u.value.items[0].title, "New");
  // (where each of its stations is up, its own page's: the row says only where it is, `where`)
  const one = ui();
  t.subscribe(2, { topic: "profile", scope: "ws", station: "ws/st", id: "p1" });
  await t.read(one, 2);
  assert.equal(u.value.items[0].members, undefined, "the list's row holds no members");
  assert.equal(one.value.members[0].online, true);
  t.set(link("ws/st"), { state: "offline" });
  await t.readAll([[u, 1], [one, 2]]);
  assert.equal(one.value.members[0].online, false);
  assert.equal(one.value.key, u.value.items[0].key);
});

test("an_accounts_row_is_what_the_list_draws_and_its_pages_ask_it_whole", async () => {
  // The list's rows (ProfileRow): whether it is signed in on several stations, how many use it, made by the core; the
  // rest of an account (its members, its check's detail, its allowance's resets) is its own topic's, asked by its key
  // or by one station's profile of it.
  const t = setup();
  const [list, byKey, byStation, none] = [ui(), ui(), ui(), ui()];
  const ada = { email: "ada@x.com", check: { state: "ok", detail: "可用", checkedAt: 1 } };
  t.set(workspace(), { id: "ws", stations: [{ id: "a", name: "alpha", last_seen: null, version: null }, { id: "b", name: "beta", last_seen: null, version: null }] });
  t.set(overview("ws/a"), overviewOf([], [profile("pa", { ...ada, usedBy: ["k1", "k2"] }), profile("solo")]));
  t.set(overview("ws/b"), overviewOf([], [profile("pb", ada)]));
  t.subscribe(1, { topic: "profiles", scope: "ws" });
  t.subscribe(2, { topic: "profile", scope: "ws", key: "sub:claude:ada@x.com" });
  t.subscribe(3, { topic: "profile", scope: "ws", station: "ws/b", id: "pb" });
  t.subscribe(4, { topic: "profile", scope: "ws", station: "ws/b", id: "gone" });
  await t.readAll([[list, 1], [byKey, 2], [byStation, 3], [none, 4]]);
  const row = list.value.items.find((x: J) => x.key === "sub:claude:ada@x.com");
  const solo = list.value.items.find((x: J) => x.key === "ws/a/solo");
  assert.deepEqual([row.several, row.usedCount, solo.several, solo.usedCount], [true, 2, false, 0]);
  assert.deepEqual([row.members, row.profile.check, row.profile.email], [undefined, undefined, undefined], "a row holds only what it draws");
  assert.deepEqual(byKey.value, byStation.value, "the same account by its key or by a station's profile of it");
  assert.deepEqual([byKey.value.key, byKey.value.members.length, byKey.value.profile.check.detail], ["sub:claude:ada@x.com", 2, "可用"]);
  assert.equal(none.value, null, "a profile no station has: none");
});

test("the_accounts_rows_go_out_as_made_beside_their_whole_value_as_they_went_out_shaped_whole", async () => {
  // What `profiles` sends is its rows, shaped beside the whole value the core's readers read (views.ts `profiles`):
  // taken so as it goes out, neither copied, decorated again nor walked by its shape there (output.ts), and the same as
  // what the whole value went out as when it was.
  const t = setup();
  const u = ui();
  const now = t.host.nowMs();
  const quota = { state: "ok", windows: [{ label: "5h", usedPercent: 20, resetsAt: now + 3 * 3_600_000 }, { label: "week", usedPercent: 91, resetsAt: now + 50 * 3_600_000 }], resetCount: 1, resetExpiries: [now + 86_400_000], checkedAt: now - 60_000 };
  t.set(workspace(), { id: "ws", stations: [{ id: "a", name: "alpha", last_seen: null, version: null }, { id: "b", name: "beta", last_seen: null, version: null }] });
  t.set(overview("ws/a"), overviewOf([], [profile("pa", { email: "ada@x.com", usedBy: ["k1"], quota, check: { state: "ok", detail: "可用", checkedAt: now - 120_000 } }), profile("solo", { access: { kind: "anthropic-api", key: "sk-ant…abcd" } })]));
  t.set(overview("ws/b"), overviewOf([], [profile("pb", { email: "ada@x.com", quota })]));
  const before = { ...work };
  t.subscribe(1, { topic: "profiles", scope: "ws" });
  await t.read(u, 1);
  assert.equal(workSince(before).wholeShaped, 0, "taken as made beside its whole value");
  const topic: Topic = { topic: "profiles", scope: "ws" };
  const whole = t.store.value(topic);
  assert.ok(whole !== undefined && "ok" in whole);
  const c = { now: t.host.nowMs(), offsetMin: t.host.utcOffsetMin(t.host.nowMs()) };
  const shapedWhole = conformTy("ProfilesView", decorate(topic, structuredClone(whole.ok), c));
  assert.ok("ok" in shapedWhole);
  assert.equal(JSON.stringify(u.value), JSON.stringify(shapedWhole.ok), "what it went out as shaped whole at output");
  assert.equal(u.value.items.length, 2);
});

test("profiles_follow_the_data_they_read_without_manual_invalidation", async () => {
  const t = setup();
  const u = ui();
  // Keep each source alive, but do not use the old watch callbacks to invalidate the view.
  const watch = t.store.watch.bind(t.store);
  t.store.watch = (topic) => watch(topic, () => {});
  t.set(workspace(), oneStation());
  t.set(overview("ws/st"), overviewOf([], [profile("p1", { name: "Old" })]));
  t.subscribe(1, { topic: "profiles", scope: "ws" });
  await t.read(u, 1);
  assert.equal(u.value.items[0].title, "Old");
  t.set(overview("ws/st"), overviewOf([], [profile("p1", { name: "New" })]));
  await t.read(u, 1);
  assert.equal(u.value.items[0].title, "New");
});

test("profiles_ignore_unrelated_overview_changes_after_a_station_appears", async () => {
  const t = setup();
  const u = ui();
  const over = overviewOf([], [profile("p1", { name: "Ada" })]);
  t.set(workspace(), { id: "ws", stations: [] });
  t.subscribe(1, { topic: "profiles", scope: "ws" });
  await t.read(u, 1);
  t.set(overview("ws/st"), over);
  t.set(workspace(), oneStation());
  await t.read(u, 1);
  assert.equal(u.value.items[0].title, "Ada");
  const before = t.router.computed;
  t.set(overview("ws/st"), { ...over, counts: { sessions: 3, running: 2, warm: 1 } });
  await t.read(u, 1);
  assert.equal(t.router.computed, before, "a new station's unrelated fields do not rebuild the page");
});
const slackThread = (id: number): J => ({
  id, surface: "slack:T1", channel: "C1", channelName: "ops", threadTs: "1.0", title: null, createdBy: null, creator: null, createdAt: 1, sessions: [], last: 0,
  lastMessage: null, read: 0, unread: 0, people: [], firstText: null,
});
const connect = (id: string, name: string): J => ({
  id, name, team: null, enabled: true, kind: "slack", mode: "multi-session", requireMention: true, bind: { runtime: "claude", model: null, effort: null, profile: null },
  slack: { appToken: "", botToken: "" }, connection: { state: "no_tokens" }, createdBy: null, sessions: 0, session: null,
});
const thread = (id: number, keys: string[], at: number): J => ({
  id, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${id}.0`, title: null, createdAt: Math.trunc(at) - 10, creator: null,
  sessions: keys.map((k) => member(id, k, "ember")), last: id * 10,
  lastMessage: { seq: id * 10, thread: id, ts: `${id * 10}.0`, authorKind: "agent", author: keys[0] ?? "", authorName: null, text: "好的", attachments: [], quotes: [], declared: null, createdAt: Math.trunc(at), editedAt: null },
  read: 0, unread: 0, people: [], firstText: null,
});
function row(id: string, at: number): J {
  const th = /^[0-9]+$/.test(id) ? Number(id) : null;
  return { id, session: th !== null ? "s" : id, thread: th, title: `${id} 的标题`, agents: [session(id)], last: null, unread: false, mine: false, lastActiveAt: Math.trunc(at), connect: null, origin: null };
}
const said = (seq: number, kind: string, author: string, text: string, at: number): J => ({
  seq, thread: 7, ts: `9.${String(seq).padStart(6, "0")}`, authorKind: kind, author, authorName: null, text, attachments: [], quotes: [], declared: null, createdAt: Math.trunc(at), editedAt: null,
});
function deciding(id: string, th: number, seq: number, at: number, dismissed: boolean): J {
  const r = row(id, at);
  r.thread = th;
  r.session = id;
  const options = [{ label: "合", recommended: true }, { label: "先不改", detail: "留到下周" }];
  const message = { ...said(seq, "agent", id, `**${id}** 要合吗？\n细节`, at), options };
  r.decision = {
    seq, options, card: { type: "options", options, assignee: "me@x.com" }, message,
    before: [said(seq - 2, "person", "me@x.com", "改一下", at - 20), said(seq - 1, "agent", id, "好", at - 10)],
  };
  if (dismissed) r.decision.dismissed = true;
  return r;
}
const ids = (v: J): string[] => v.days.flatMap((d: J) => d.items.map((i: J) => i.id));

/// A value without what the clients show of it: what a view puts together, alone.
const SHOWN = new Set(["trouble", "settled", "archivable", "swipeArchive", "swipeAsk", "stateText", "stateLead", "stateRest", "face", "line", "available", "offered", "connection", "glyph", "note", "time", "statusText", "tone", "badgeText", "titleText", "agentText", "maker", "runtimeText", "processText", "efforts", "modeText", "modeShort", "runText", "presence", "checkText", "checkTone", "preview", "makers", "mark", "order", "left", "level", "refills", "shown", "processesText", "by", "waiting", "since", "originText", "originKind", "summary", "modelsText", "stateBusy", "problems", "changes", "modeWords", "modeLabel", "modeSentence", "placeText"]);
function plain(v: J): J {
  if (Array.isArray(v)) return v.map(plain);
  if (v !== null && typeof v === "object") return Object.fromEntries(Object.entries(v).filter(([k, x]) => !SHOWN.has(k) && x !== null && x !== undefined).map(([k, x]) => [k, plain(x)]));
  return v;
}

test("a notice that a runtime is not installed offers installing it as the station's updates have it", () => {
  const dsh = (over: J): J => ({ id: "dsh", name: "DeepSeek Harness", installed: false, updatable: true, state: "idle", ...over });
  // A manager can install it; a member is told who can; a station that cannot (no npm) says why.
  assert.deepEqual(installView("dsh", [dsh({})], true), { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", action: "安装" });
  assert.deepEqual(installView("dsh", [dsh({})], false), { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", note: "需由 workspace 的 owner 或管理员安装" });
  assert.deepEqual(installView("dsh", [dsh({ updatable: false, note: "未找到 npm" })], true), { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", note: "未找到 npm" });
  // Installing, how far; failed, why, with trying again; then installed: each said in place of the notice's words.
  assert.deepEqual(installView("dsh", [dsh({ state: "updating", percent: 42 })], true), { runtime: "dsh", state: "installing", title: "正在安装 DeepSeek Harness", percent: 42 });
  assert.deepEqual(installView("dsh", [dsh({ state: "updating", percent: 42, progress: "正在下载 0.2.0：21/50 MB" })], true), { runtime: "dsh", state: "installing", title: "正在安装 DeepSeek Harness", note: "正在下载 0.2.0：21/50 MB", percent: 42 });
  assert.deepEqual(installView("dsh", [dsh({ state: "updating", progress: "正在安装" })], true), { runtime: "dsh", state: "installing", title: "正在安装 DeepSeek Harness" });
  assert.deepEqual(installView("dsh", [dsh({ state: "failed", message: "EACCES" })], true), { runtime: "dsh", state: "failed", title: "无法安装 DeepSeek Harness", detail: "EACCES", action: "重试" });
  assert.deepEqual(installView("dsh", [dsh({ installed: true, version: "0.2.0" })], true), { runtime: "dsh", state: "installed", title: "已安装 DeepSeek Harness" });
  // A station older than its updates: nothing offered.
  assert.equal(installView("dsh", [], true), null);
});

test("a notice that a runtime is not installed is said under the viewer's message that waits for it", () => {
  const install = { runtime: "dsh", state: "missing", title: "此 station 尚未安装 DeepSeek Harness", action: "安装" };
  const said = (over: J): J => ({ seq: 1, mine: false, waiting: false, ...over });
  // Folded into the last of the viewer's waiting before it (each notice of the runs that failed), gone from the chat.
  const folded = blockedUnder([said({ seq: 1, mine: true }), said({ seq: 2, mine: true, waiting: true }), said({ seq: 3, system: true, install }), said({ seq: 4, system: true, install })]);
  assert.deepEqual(folded.map((m) => [m.seq, m.blocked?.state ?? null]), [[1, null], [2, "missing"]]);
  // None of the viewer's waits (someone else's in Slack): it stays a notice; installed and nothing waits, it is gone.
  assert.deepEqual(blockedUnder([said({ seq: 1, waiting: true }), said({ seq: 2, system: true, install })]).map((m) => m.seq), [1, 2]);
  assert.deepEqual(blockedUnder([said({ seq: 1, mine: true }), said({ seq: 2, system: true, install: { ...install, state: "installed" } })]).map((m) => m.seq), [1]);
});

test("a notice that a chat's run changed says what changed, what it runs on now where that has not the room, and both runs whole opened", () => {
  const run = { runtime: "claude", model: "claude-opus-5-5", effort: "high", fast: null, profile: "cc", account: "a@x.com", pinned: false, context: null };
  const shown = (was: J, now: J) => shownMessage({ authorKind: "ember", author: "ember", text: "已切换：…", change: { was, now } }, [], null, [], [], [], undefined).notice;
  // Another model and effort: those alone, before and after; the station's words given way to the viewer's.
  let notice = shown(run, { ...run, model: "claude-sonnet-5-5", effort: "medium" });
  assert.equal(notice.words, "Opus 5.5 · 高 → Sonnet 5.5 · 中");
  assert.equal(notice.short, "换成 Sonnet 5.5 · 中");
  assert.deepEqual(notice.lines, ["之前：Claude Code · Opus 5.5 · 高 · 自动 · a@x.com", "现在：Claude Code · Sonnet 5.5 · 中 · 自动 · a@x.com"]);
  assert.equal(notice.failed, false);
  // Its two sides apart, each with the mark it is drawn with: who made the model, else the runtime's maker.
  assert.deepEqual(notice.sides, { was: "Opus 5.5 · 高", now: "Sonnet 5.5 · 中", to: "换成", wasMaker: "anthropic", wasRuntime: "claude", nowMaker: "anthropic", nowRuntime: "claude" });
  // Another runtime: its speed said only where both have one; the account kept to and the most context said whole.
  notice = shown(run, { ...run, runtime: "codex", model: "gpt-6", effort: "high", fast: true, profile: "cx", account: "b@x.com", pinned: true, context: 200000 });
  assert.equal(notice.words, "Claude Code · Opus 5.5 → Codex · GPT-6");
  assert.deepEqual(notice.sides, { was: "Claude Code · Opus 5.5", now: "Codex · GPT-6", to: "换成", wasMaker: "anthropic", wasRuntime: "claude", nowMaker: "openai", nowRuntime: "codex" });
  // The runtime's default model: no maker said, the app draws the runtime's.
  assert.equal(shown(run, { ...run, runtime: "agy", model: null }).sides.nowMaker, "");
  assert.equal(notice.lines[1], "现在：Codex · GPT-6 · 高 · Fast · b@x.com · 上下文 200K");
  // An effort or a speed alone is named.
  assert.equal(shown(run, { ...run, effort: "low" }).words, "思考深度：高 → 低");
  assert.equal(shown(run, { ...run, effort: "low" }).sides, undefined);
  assert.equal(shown({ ...run, fast: false }, { ...run, fast: true }).short, "速度：Fast");
  // Another account alone (the station moved it, an allowance run out) is named; with another runtime it is the rest's.
  notice = shown(run, { ...run, profile: "cc2", account: "b@x.com" });
  assert.equal(notice.words, "账号：a@x.com → b@x.com");
  assert.equal(notice.short, "账号：b@x.com");
  assert.equal(notice.lines[1], "现在：Claude Code · Opus 5.5 · 高 · 自动 · b@x.com");
  // Not a change (an old station's notice, a message of an agent): as it was.
  assert.equal(shownMessage({ authorKind: "ember", author: "ember", text: "已压缩上下文" }, [], null, [], [], [], undefined).notice.short, undefined);
});

test("canonical_and_legacy_station_notices_have_the_same_presentation", () => {
  const shown: J[] = [];
  for (const kind of ["ember", "stillfail"]) {
    let message: J = { authorKind: kind, author: kind, text: "notice" };
    message = shownMessage(message, [], null, [], [], [], undefined);
    assert.equal(message.system, true);
    assert.equal(message.mine, false);
    shown.push(message.by);
  }
  assert.deepEqual(shown[0], shown[1]);
});

test("another_chats_agent_goes_by_that_chats_name_without_the_header_line", () => {
  const agents = [{ session: { key: "k", agentText: "Opus", runtime: "claude" } }];
  for (const [text, title] of [
    ["来自 [发版 0.1.1780](https://x/o/w/s/a)：\n\n回归过了吗？", "发版 0.1.1780"],
    ["From <https://x/o/w/s/a|Release>:\n\n回归过了吗？", "Release"],
    // The first message of a chat it opened (chat_create).
    ["由 [发版 0.1.1780](https://x/o/w/s/a) 开的 chat：\n\n回归过了吗？", "发版 0.1.1780"],
    ["Opened by [Release](https://x/o/w/s/a):\n\n回归过了吗？", "Release"],
  ]) {
    let message: J = { authorKind: "agent", author: "far/a", text, agentIdentity: { model: "claude-opus-5-5" } };
    message = shownMessage(message, agents, null, [], [], [], undefined);
    assert.deepEqual([message.text, message.by.name, message.by.from], ["回归过了吗？", title, "https://x/o/w/s/a"]);
  }
  let own: J = { authorKind: "agent", author: "k", text: "来自 [a](https://x/o/w/s/a)：\n\nhi" };
  own = shownMessage(own, agents, null, [], [], [], undefined);
  assert.deepEqual([own.text, own.by.name], ["来自 [a](https://x/o/w/s/a)：\n\nhi", "Opus"]);
});

test("a_slack_persons_message_shows_their_slack_picture_else_their_accounts", () => {
  const members = [{ email: "ada@x.com", name: "Ada", picture: "https://p/ada" }];
  const slack = shownMessage({ authorKind: "person", author: "U1", authorName: "Ada L", authorPicture: "https://avatars.slack-edge.com/ada_72.png", text: "hi" }, [], null, [], members, [], undefined);
  assert.deepEqual(slack.by, { name: "Ada L", picture: "https://avatars.slack-edge.com/ada_72.png" });
  const page = shownMessage({ authorKind: "person", author: "ada@x.com", text: "hi" }, [], null, [], members, [], undefined);
  assert.deepEqual(page.by, { name: "Ada", picture: "https://p/ada" });
  const unknown = shownMessage({ authorKind: "person", author: "U2", authorName: "Bo", text: "hi" }, [], null, [], members, [], undefined);
  assert.deepEqual(unknown.by, { name: "Bo", picture: null });
});

test("historical_messages_do_not_follow_the_current_model", () => {
  let message: J = { authorKind: "agent", author: "k", agentIdentity: { model: "gpt-6-sol", effort: "high" } };
  const agents = [{ session: { key: "k", agentText: "GPT-6 Astra", model: "gpt-6-astra", runtime: "claude", maker: { id: "openai", name: "OpenAI" } } }];
  message = shownMessage(message, agents, null, [], [], [], undefined);
  assert.equal(message.by.name, format.agentLabel("gpt-6-sol", "high"));
  assert.equal(message.by.runtime, "claude");
  delete message.agentIdentity;
  message = shownMessage(message, agents, null, [], [], [], undefined);
  assert.equal(message.by.name, "GPT-6 Astra");
  assert.equal(message.by.maker.id, "openai");
});

test("historical messages keep the runtime they were sent on", () => {
  const agents = [{ session: { key: "k", runtime: "codex", agentText: "GPT-6", maker: { id: "openai", name: "OpenAI" } } }];
  const old = shownMessage({ authorKind: "agent", author: "k", agentIdentity: { model: "claude-opus-5-5", runtime: "claude" } }, agents, null, [], [], [], undefined);
  assert.deepEqual([old.by.name, old.by.maker?.id, old.by.runtime], [format.agentLabel("claude-opus-5-5", null), "anthropic", "claude"]);
  const defaultModel = shownMessage({ authorKind: "agent", author: "k", agentIdentity: { model: null, effort: null, runtime: "claude" } }, agents, null, [], [], [], undefined);
  assert.deepEqual([defaultModel.by.name, defaultModel.by.maker, defaultModel.by.runtime], [format.agentLabel(null, null), null, "claude"]);
  const legacy = shownMessage({ authorKind: "agent", author: "k", authorRuntime: "claude" }, agents, null, [], [], [], undefined);
  assert.equal(legacy.by.runtime, "claude");
});

test("an_agents_mark_is_drawn_from_what_its_message_says_before_its_session_is_read", () => {
  const message: J = { authorKind: "agent", author: "k", authorName: "Worker", authorModel: "gpt-5.5", authorRuntime: "codex", text: "hi" };
  const before = shownMessage(message, [], null, [], [], [], undefined);
  assert.deepEqual([before.by.name, before.by.maker?.id, before.by.runtime], ["Worker", "openai", "codex"]);
  // Its author runtime remains the one given with the message after its session is read.
  const agents = [{ session: { key: "k", agentText: "Opus", model: "claude-opus-5-5", runtime: "claude", maker: { id: "anthropic", name: "Anthropic" } } }];
  const after = shownMessage(message, agents, null, [], [], [], undefined);
  assert.deepEqual([after.by.name, after.by.maker.id, after.by.runtime], ["Worker", "openai", "codex"]);
  // From a station that does not say: no mark yet.
  const old = shownMessage({ authorKind: "agent", author: "k", text: "hi" }, [], null, [], [], [], undefined);
  assert.deepEqual([old.by.maker, old.by.runtime], [null, null]);
});

test("a_station_is_down_as_its_link_finds_it_or_as_it_was_last_until_then", () => {
  assert.ok(down({ state: "offline" }));
  assert.ok(!down({ state: "online" }));
  assert.ok(!down({ state: "reconnecting" }));
  assert.ok(!down({ state: "error" }));
  assert.ok(down({ state: "connecting", last: "offline" }));
  assert.ok(!down({ state: "connecting", last: "online" }));
  assert.ok(!down({ state: "connecting" }));
});

test("the_beta_switch_is_offered_to_an_account_in_the_beta_or_a_station_on_it", () => {
  const w = (channel: string | null) => ({ updates: [{ id: "claude" }, { id: "station", channel }] });
  assert.ok(!betaOffered(undefined, () => true));
  assert.ok(!betaOffered({}, () => true));
  assert.ok(!betaOffered(w(null), () => true));
  assert.ok(!betaOffered(w("stable"), () => false));
  assert.ok(betaOffered(w("stable"), () => true));
  assert.ok(betaOffered(w("beta"), () => false));
});

test("a_rows_decision_is_its_line_and_mark_and_counts_for_the_workspace", async () => {
  const t = setup();
  const [chats, marks] = [ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.subscribe(2, { topic: "workspaceMarks" });
  await t.readAll([[chats, 1], [marks, 2]]);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.readAll([[chats, 1], [marks, 2]]);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const blocked = deciding("k1", 7, 5, now - 1000, false);
  blocked.agents[0].lastTurn = { kind: "message", declared: "block", ending: "need_decision", outcome: "completed", startedAt: 1, endedAt: 1 };
  blocked.mine = true;
  blocked.unread = true;
  const others = deciding("other", 11, 7, now - 4000, false);
  others.decision.card.assignee = "other@x.com";
  t.set(rows("ws/st"), [blocked, deciding("k2", 8, 3, now - 2000, true), deciding("k3", 9, 4, now - 3000, false), others]);
  await t.readAll([[chats, 1], [marks, 2]]);
  const v = chats.value;
  const all = v.days.flatMap((d: J) => d.items);
  const of = (id: string) => all.find((r: J) => r.id === id);
  // (its card: its row's line in the list, its whole row's own)
  const whole = await wholeOf(t, v);
  assert.deepEqual([of("k1").tone, of("k1").stateText, of("k1").decision, whole.k1.decision.text], ["wait", "待处理 · k1 要合吗？", undefined, "待处理 · k1 要合吗？"]);
  assert.deepEqual([of("k2").tone, whole.k2.decision.dismissed, whole.k2.decision.text], [undefined, true, undefined]);
  const m = marks.value;
  assert.deepEqual([m.workspaces.ws.wait, m.workspaces.ws.alert, m.workspaces.ws.label], [2, 0, "2 个待你处理"]);
  // Of the lists the rail leads to: 我参与的 has the one of theirs waiting, 监控中 nothing.
  assert.deepEqual([m.workspaces.ws.tone, m.workspaces.ws.mineTone, m.workspaces.ws.watchingTone], ["wait", "wait", undefined]);
  // 待处理 and the badge are the same: the cards waiting for them not looked at since they came (k3 read: its row still
  // says it).
  assert.deepEqual([m.badge, m.workspaces.ws.badge], [1, 1]);
  assert.deepEqual(m.workspaces.ws.items.map((i: J) => [i.kind, i.session, i.seq, i.stationName]), [["wait", "k1", 5, "studio"]]);
  assert.equal(m.workspaces.ws.items[0].text, "待处理 · k1 要合吗？", "its row's line");
  assert.equal(m.workspaces.ws.items[0].what, "k1 要合吗？", "the same without its lead");
});

test("a_comma_tasks_chat_is_marked_by_comma_as_a_slack_one_is_by_slack", async () => {
  const t = setup();
  const chats = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  await t.readAll([[chats, 1]]);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const task = row("k1", now - 1000);
  task.connect = "cm";
  task.origin = { surface: "comma:cm", channel: "TASK", channelName: null, threadTs: "1.000001", teamName: null };
  t.set(rows("ws/st"), [task, row("k2", now - 2000)]);
  await t.readAll([[chats, 1]]);
  const all = chats.value.days.flatMap((d: J) => d.items);
  const of = (id: string) => all.find((r: J) => r.id === id);
  assert.deepEqual([of("k1").originKind, of("k1").originText], ["comma", "Comma"]);
  assert.deepEqual([of("k2").originKind, of("k2").originText], [undefined, undefined]);
});

test("a_hidden_chat_that_needs_the_viewer_remains_in_attention", async () => {
  const t = setup();
  const [list, marks] = [ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.subscribe(2, { topic: "workspaceMarks" });
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const r = deciding("hidden", 7, 5, t.host.nowMs(), false);
  r.hidden = true;
  r.mine = true;
  r.unread = true;
  t.set(rows("ws/st"), [r]);
  await t.readAll([[list, 1], [marks, 2]]);
  assert.deepEqual(ids(list.value), []);
  assert.deepEqual(marks.value.workspaces.ws.items.map((item: J) => [item.kind, item.session]), [["wait", "hidden"]]);
});

test("待处理_lists_the_unread_the_badge_counts_last_of_all_with_how_far_to_read_them", async () => {
  const t = setup();
  const marks = ui();
  t.subscribe(1, { topic: "workspaceMarks" });
  await t.readAll([[marks, 1]]);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const unread = (id: string, at: number, authorKind: string) => {
    const r = row(id, at);
    r.mine = true;
    r.unread = true;
    r.thread = 20;
    r.last = { seq: 30, authorKind };
    return r;
  };
  const other = unread("other", now - 500, "person");
  other.mine = false;
  const waits = deciding("k1", 7, 5, now - 3000, false);
  waits.unread = true;
  t.set(rows("ws/st"), [unread("agent", now - 2000, "agent"), unread("person", now - 1000, "person"), other, waits]);
  await t.readAll([[marks, 1]]);
  const listed = () => marks.value.workspaces.ws.items.map((i: J) => [i.kind, i.session, i.seq]);
  assert.deepEqual(listed(), [["wait", "k1", 5], ["done", "person", 30], ["done", "agent", 30]]);
  assert.equal(marks.value.badge, listed().length, "every number on the badge can be found in it");
  // a kind the badge does not count is not listed
  t.set(prefs(), { badgeKinds: { on: true, wait: true, failed: true, done: false, message: true, services: true } });
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.badge], [[["wait", "k1", 5], ["done", "person", 30]], 2]);
});

test("待处理_is_what_went_wrong_till_let_go_or_waits_not_looked_at_since_of_what_the_badge_counts", async () => {
  const t = setup();
  const marks = ui();
  t.subscribe(1, { topic: "workspaceMarks" });
  await t.readAll([[marks, 1]]);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const failed = (id: string, at: number, unread: boolean): J => {
    const r = row(id, at);
    r.agents[0].lastTurn = { kind: "message", outcome: "failed", detail: "auth: 401", startedAt: 1, endedAt: 1 };
    r.mine = true;
    r.unread = unread;
    return r;
  };
  const waits = deciding("k1", 7, 5, now - 3000, false);
  waits.unread = true;
  t.set(rows("ws/st"), [failed("new", now - 1000, true), failed("old", now - 2000, false), waits]);
  await t.readAll([[marks, 1]]);
  const listed = () => marks.value.workspaces.ws.items.map((i: J) => [i.kind, i.session]);
  // gone wrong, read or not, till it runs again or is let go: as the workspace's mark says (pengxiao, 2026-10-28);
  // the badge only what was not read
  assert.deepEqual(listed(), [["alert", "new"], ["alert", "old"], ["wait", "k1"]]);
  assert.deepEqual([marks.value.workspaces.ws.alert, marks.value.workspaces.ws.label, marks.value.badge], [2, "2 个出错 · 1 个待你处理", 2]);
  const old = marks.value.workspaces.ws.items[1].failure;
  assert.equal(old, "ws/st/old@1", "a failure names its chat and when it ended");
  // let go (忽略): off 待处理 and the workspace's mark
  t.set(prefs(), { failsGone: { ws: [old] } });
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.workspaces.ws.alert, marks.value.workspaces.ws.label], [[["alert", "new"], ["wait", "k1"]], 1, "1 个出错 · 1 个待你处理"]);
  // the same chat failing again is another failure: back
  const again = failed("old", now - 500, false);
  again.agents[0].lastTurn = { ...again.agents[0].lastTurn, startedAt: 2, endedAt: 2 };
  t.set(rows("ws/st"), [failed("new", now - 1000, true), again, waits]);
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.workspaces.ws.alert], [[["alert", "old"], ["alert", "new"], ["wait", "k1"]], 2]);
  // run again (it ended well): no longer wrong
  const fine = row("old", now - 400);
  fine.mine = true;
  t.set(rows("ws/st"), [failed("new", now - 1000, true), fine, waits]);
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.workspaces.ws.alert], [[["alert", "new"], ["wait", "k1"]], 1]);
  // the badge counting only the cards: 待处理 has only them
  t.set(prefs(), { badgeKinds: { failed: false } });
  await t.readAll([[marks, 1]]);
  assert.deepEqual([listed(), marks.value.badge], [[["wait", "k1"]], 1]);
});

test("workspace_marks_follow_rows_read_directly_from_data_without_manual_invalidation", async () => {
  const t = setup();
  const u = ui();
  const watch = t.store.watch.bind(t.store);
  t.store.watch = (topic) => watch(topic, () => {});
  t.store.watch({ topic: "workspaces" }, () => {});
  t.store.watch(link("ws/st"), () => {});
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  t.set(rows("ws/st"), []);
  await t.host.time.pass(100);
  t.subscribe(1, { topic: "workspaceMarks" });
  await t.read(u, 1);
  assert.deepEqual(u.value.workspaces.ws.items, []);

  const failed = row("failed", t.host.nowMs());
  failed.mine = true;
  failed.unread = true;
  failed.agents[0].lastTurn = { kind: "message", outcome: "failed", detail: "auth: 401", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/st"), [failed]);
  await t.read(u, 1);
  assert.deepEqual(u.value.workspaces.ws.items.map((item: J) => item.session), ["failed"]);
});

// A message that did not go was said only in its chat, below what the agent last said: the list showed the agent's
// state (做完了) and no mark, so it went unseen there (2026-10-22).
test("a_chat_with_a_message_that_did_not_go_is_marked_on_its_row_until_it_goes", async () => {
  const t = setup();
  const chats = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const r = row("7", t.host.nowMs() - 1000);
  t.set(rows("ws/st"), [r]);
  await t.read(chats, 1);
  const of = () => chats.value.days.flatMap((d: J) => d.items).find((i: J) => i.id === "7");
  assert.deepEqual([of().tone, of().stateText], [undefined, undefined]);
  const id = t.views.outboxAdd("ws/st", 7, { text: "开始吧\n第二行", attachments: [], quotes: [] });
  await t.read(chats, 1);
  assert.deepEqual([of().tone, of().stateText], [undefined, undefined], "on its way, nothing to say");
  t.views.local.outboxState("ws/st", 7, id, "Office-VM-1 离线");
  await t.read(chats, 1);
  assert.deepEqual([of().tone, of().stateText, of().unsent], ["alert", "未发送：开始吧 第二行", true]);
  t.views.local.outboxState("ws/st", 7, id, null);
  await t.read(chats, 1);
  assert.deepEqual([of().tone, of().stateText], [undefined, undefined], "sent again");
});

function typing(id: string, th: number, seq: number, at: number): J {
  const r = row(id, at);
  r.thread = th;
  r.session = id;
  const card = { type: "text", placeholder: "sk_test_…", assignee: "me@x.com" };
  r.card = { seq, card, message: { ...said(seq, "agent", id, "Stripe 的测试 key 是多少？", at), card }, before: [] };
  return r;
}

test("a_text_card_is_on_its_row_whatever_its_agent_does", async () => {
  const t = setup();
  const chats = ui();
  t.subscribe(2, { topic: "chats", scope: "ws" });
  await t.readAll([[chats, 2]]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  await t.readAll([[chats, 2]]);
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  const working = typing("k1", 7, 5, now - 1000);
  working.agents[0].process = "running";
  const needs = row("k2", now - 2000);
  needs.thread = 8;
  needs.agents[0].lastTurn = { kind: "message", declared: "block", ending: "need_help", need: "要 key", about: { thread: 8, seq: 9, ts: "9.000009" }, outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/st"), [working, needs]);
  await t.readAll([[chats, 2]]);
  const v = chats.value;
  const all = v.days.flatMap((d: J) => d.items);
  const of = (id: string) => all.find((r: J) => r.id === id);
  const k1 = of("k1");
  // A line that asks for a decision only says so: the chat leads to its post, not the row.
  assert.deepEqual([k1.stateText, k1.stateAbout, k1.tone], ["待处理 · Stripe 的测试 key 是多少？", undefined, "wait"]);
  assert.deepEqual([(await wholeOf(t, v)).k1.decision.card.type, k1.decision, k1.card], ["text", undefined, undefined]);
  const k2 = of("k2");
  assert.deepEqual([k2.stateText, k2.stateAbout, k2.tone], ["需要你处理：要 key", undefined, "wait"]);
});

test("what_is_worth_a_look_about_a_session_is_its_account_its_quota_running_out_and_the_disk_filling_up", () => {
  const ov = (check: string, week: number, free: number) => ({
    profiles: [{ id: "a", name: "A", check: { state: check, detail: "d" }, quota: { state: "ok", windows: [{ label: "5 小时", usedPercent: 10, resetsAt: 1 }, { label: "每周", usedPercent: week, resetsAt: 2 }] } }],
    disk: { freeBytes: free, totalBytes: 1000e9 },
  });
  const s = { profile: "a" };
  assert.deepEqual(attention(ov("ok", 50, 500e9), s, 0), []);
  assert.deepEqual(attention(ov("login", 92, 5e9), s, 0), [
    { kind: "account", text: "「A」需要重新登录" },
    { kind: "quota", text: "每周剩余 8%", more: "即将刷新", quota: { left: 8, mark: "W", level: "red", until: 2 } },
    { kind: "disk", text: "磁盘剩 5 GB" },
  ]);
});

test("a_models_own_window_is_said_of_that_model_alone", () => {
  // Fable's week used up under an account whose own windows have room (#4365): the account's other models run on.
  const fable = { label: "每周 · Fable", usedPercent: 100, resetsAt: 9000, scope: "Fable" };
  const week = { label: "每周", usedPercent: 30, resetsAt: 9000 };
  const ov = { profiles: [{ id: "a", name: "A", runtimes: ["claude"], model: "claude-opus-5-5", models: ["claude-fable-5-1", "claude-opus-5-5"], check: { state: "ok" }, quota: { state: "ok", windows: [week], scoped: [fable] } }] };
  const on = (model: string | null) => runnableOn(ov, { runtime: "claude", profile: "a", model }, 0)[0];
  assert.deepEqual([on("claude-fable-5-1").quota.windows, on("claude-fable-5-1").spent.until, on("claude-fable-5-1").quotaLine], [[week, fable], 9000, { text: "每周 · Fable剩余 0%", level: "red" }]);
  assert.deepEqual([on("claude-opus-5-5").quota, on("claude-opus-5-5").spent, on("claude-opus-5-5").quotaLine], [{ state: "ok", windows: [week] }, null, { text: "每周 70%" }]);
  assert.deepEqual(on(null).quota.windows, [week], "its account's own model, Opus");
  const spent = Object.fromEntries(models(ov, 0).map((m: J) => [m.model, m.spent?.until ?? null]));
  assert.deepEqual(spent, { "claude-fable-5-1": 9000, "claude-opus-5-5": null });
  assert.deepEqual(attention(ov, { profile: "a", model: "claude-opus-5-5" }, 0), []);
  assert.deepEqual(attention(ov, { profile: "a", model: "claude-fable-5-1" }, 0), [{ kind: "quota", text: "每周 · Fable剩余 0%", more: "即将刷新", quota: { left: 0, mark: "Fable", level: "red", until: 9000 } }]);
  const agyWin = [
    { label: "5 小时 · Gemini", usedPercent: 10, resetsAt: 9000, scope: "gemini" },
    { label: "每周 · Gemini", usedPercent: 20, resetsAt: 9000, scope: "gemini" },
    { label: "5 小时 · Claude / GPT", usedPercent: 100, resetsAt: 9000, scope: "3p" },
    { label: "每周 · Claude / GPT", usedPercent: 40, resetsAt: 9000, scope: "3p" },
  ];
  const agyOv = { profiles: [{ id: "g", name: "G", runtimes: ["agy"], model: "gemini-4-carbon-medium", models: ["gemini-4-carbon-medium", "google/gemini-3.1-pro", "claude-opus-5-5-medium", "anthropic/claude-opus-4-6"], check: { state: "ok" }, quota: { state: "ok", windows: agyWin } }] };
  const agyOn = (model: string | null) => runnableOn(agyOv, { runtime: "agy", profile: "g", model }, 0)[0];
  assert.equal(agyOn("gemini-4-carbon-medium").spent, null);
  assert.equal(agyOn("google/gemini-3.1-pro").spent, null);
  assert.equal(agyOn("claude-opus-5-5-medium").spent.until, 9000);
  assert.equal(agyOn("anthropic/claude-opus-4-6").spent.until, 9000);
  assert.equal(agyOn(null).quota.windows.length, 2, "falls back to the profile's own default model");
  assert.equal(quotaFor(agyOv.profiles[0]!.quota, null).windows.length, 4, "the account's own page keeps all four windows");
});

test("an_agent_can_be_moved_to_the_profiles_of_its_runtime", () => {
  const ov = {
    profiles: [
      { id: "a", name: "A", runtimes: ["claude", "codex"], models: ["m"] },
      { id: "b", name: "B", runtimes: ["codex"], models: ["m"], quota: { state: "ok", windows: [{ usedPercent: 100, resetsAt: 9000 }] } },
      { id: "c", name: "C", runtimes: ["claude"], models: ["m"] },
      { id: "d", name: "D", runtimes: ["codex"], models: ["other"] },
    ],
  };
  const s = { runtime: "codex", profile: "a", model: "m" };
  assert.deepEqual(runnableOn(ov, s, 0), [
    { id: "a", name: "A", current: true, spent: null, kind: null, runtime: null, quota: null, quotaLine: null, efforts: ["minimal", "low", "medium", "high", "xhigh"] },
    {
      id: "b", name: "B", current: false, spent: { until: 9000, text: "额度已用完 · 1 分钟内恢复", back: "1 分钟内恢复" }, kind: null, runtime: null,
      quota: { state: "ok", windows: [{ usedPercent: 100, resetsAt: 9000 }] }, quotaLine: { text: "剩余 0%", level: "red" }, efforts: ["minimal", "low", "medium", "high", "xhigh"],
    },
  ]);
  assert.ok(choices(ov, s, 0).some((c: J) => c.model === "m" && c.accounts.codex.length === 2));
});

test("chats_told_a_window_have_their_first_rows_and_say_how_many_more", async () => {
  // A list of 1400 chats went whole to the app as it opened, a screen of them shown (2026-11-08).
  const t = setup();
  const u = ui();
  t.window({ topic: "chats", scope: "ws" }, 2);
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(link("ws/st"), { state: "online" });
  t.set(rows("ws/st"), [row("1", now - 1000), row("2", now - 2000), row("3", now - 3 * 86_400_000)]);
  await t.read(u, 1);
  assert.deepEqual(ids(u.value), ["1", "2"]);
  assert.equal(u.value.more, 1);
  // a new one on top: the last of the first two goes, one more past them
  t.set(rows("ws/st"), [row("4", now), row("1", now - 1000), row("2", now - 2000), row("3", now - 3 * 86_400_000)]);
  await t.read(u, 1);
  assert.deepEqual(ids(u.value), ["4", "1"]);
  assert.equal(u.value.more, 2);
  // all of them in it, its window raised: no `more`
  t.window({ topic: "chats", scope: "ws" }, 10);
  await t.read(u, 1);
  assert.deepEqual(ids(u.value), ["4", "1", "2", "3"]);
  assert.equal(u.value.more ?? null, null);
});

/// Whether a value holds an object as only a row not made yet is (views.ts `unmade`): none goes out.
function holdsStandIn(v: J): boolean {
  if (Array.isArray(v)) return v.some(holdsStandIn);
  if (v === null || typeof v !== "object") return false;
  if (Object.keys(v).sort().join() === "lastActiveAt,state,station") return true;
  return Object.values(v).some(holdsStandIn);
}
/// The list's items, each one a made row.
const madeItems = (v: J): J[] => {
  const items = v.days.flatMap((d: J) => d.items);
  for (const i of items) assert.ok(typeof i.id === "string" && typeof i.title === "string", `a made row: ${JSON.stringify(i)}`);
  return items;
};
/// What a list's window of `rows` rows is of the whole list (views.ts firstRows as it was).
function firstOf(whole: J, rows: number): J {
  let left = rows;
  let more = 0;
  const days: J[] = [];
  for (const d of whole.days) {
    if (left <= 0) more += d.items.length;
    else if (d.items.length <= left) days.push(d);
    else {
      days.push({ ...d, items: d.items.slice(0, left) });
      more += d.items.length - left;
    }
    left -= Math.min(left, d.items.length);
  }
  return more === 0 ? whole : { ...whole, days, more };
}

test("a_chat_lists_rows_are_made_as_its_page_shows_them", async () => {
  // A list of 420 chats on 5 stations made all its rows, 55 ms in one block on Hermes, to send a page of 50 (2026-11-11).
  const t = setup({ all: true });
  const now = t.host.nowMs();
  const names = ["a", "b", "c", "d", "e"];
  t.set(workspace(), { id: "ws", stations: names.map((id) => ({ id, name: id, last_seen: null, version: null })) });
  // 84 a station, an hour apart across the stations, over 17 days; a few pinned, some at work.
  const records = (st: number, changed: J = {}) =>
    Array.from({ length: 84 }, (_, i) => {
      const id = `${names[st]}${i}`;
      const r = { ...row(id, now - (i * 5 + st) * 3_600_000), agents: [{ ...session(id), ...(i % 7 === 0 ? { process: "running" } : {}) }] };
      return { ...r, ...(i === 3 ? { pinned: 1000 + st } : {}), ...changed[id] };
    });
  for (const [st, id] of names.entries()) {
    t.set(link(`ws/${id}`), { state: "online" });
    t.set(rows(`ws/${id}`), records(st));
  }
  // As on opening: the rows on the device, none of them loaded yet (views.ts #head reads the first of them alone).
  for (const id of names) t.data.release(rows(`ws/${id}`));
  assert.ok(names.every((id) => !t.data.loaded(rows(`ws/${id}`))));
  const page = ui();
  const list: Topic = { topic: "chats", scope: "ws" };
  let from = work.rows;
  t.window(list, 50);
  t.subscribe(1, list);
  await t.read(page, 1);
  await t.read(page, 1);
  // (a window over its stations' rows, none of them loaded: db/chat-reads.ts `window`)
  assert.ok(names.every((id) => !t.data.loaded(rows(`ws/${id}`))), "none of its stations' rows loaded");
  assert.equal(madeItems(page.value).length, 50);
  assert.equal(page.value.more, 370);
  assert.ok(work.rows - from <= 50, `the first page made ${work.rows - from} rows`);
  // scrolled: its window 50 more
  from = work.rows;
  t.window(list, 100);
  await t.read(page, 1);
  assert.equal(madeItems(page.value).length, 100);
  assert.ok(work.rows - from <= 50, `scrolling made ${work.rows - from} rows`);
  // One far down the list changes: no row made, as it is written or read (no list read it). Then one in the page: its
  // row alone made, as its record is written (and kept beside it: db/kept.ts KEPT.listRow), none as the list reads it.
  from = work.rows;
  let written = work.listRowWritten;
  t.set(rows("ws/e"), records(4, { e80: { title: "改了" } }));
  await t.read(page, 1);
  assert.deepEqual([work.rows - from, work.listRowWritten - written], [0, 0], "a chat outside the page");
  from = work.rows;
  written = work.listRowWritten;
  t.set(rows("ws/e"), records(4, { e80: { title: "改了" }, e1: { title: "也改了" } }));
  await t.read(page, 1);
  assert.deepEqual([work.rows - from, work.listRowWritten - written], [0, 1], "a chat in the page");
  assert.ok(madeItems(page.value).some((i: J) => i.title === "也改了"));
  // The page is the whole list's first rows, its days and `more`; the whole list, a search, the `@` menu and the rail's
  // card have made rows.
  const topics: Topic[] = [
    list,
    { topic: "search", scope: "ws", query: "" },
    { topic: "chatSearch", scope: "ws", query: "标题", limit: 500 },
    { topic: "railCard", scope: "ws", place: "chats" },
  ];
  for (let i = 1; i < topics.length; i++) t.subscribe(1 + i, topics[i]);
  const shown = topics.slice(1).map(() => ui());
  await t.readAll(shown.map((u, i) => [u, 2 + i] as [Ui, number]));
  const whole = t.views.chatsWhole("ws") as J;
  assert.equal(madeItems(whole.ok).length, 420);
  assert.deepEqual(t.store.value(list), { ok: firstOf(whole.ok, 100) });
  assert.ok(shown[1].value.items.length > 100, "the `@` menu lists past the page");
  for (const i of shown[1].value.items) assert.ok(typeof i.title === "string");
  for (const topic of topics) {
    const v = t.store.value(topic);
    assert.ok(v !== undefined && "ok" in v, `${topicKey(topic)} has a value`);
    assert.ok(!holdsStandIn(v.ok), `${topicKey(topic)} holds no row not made`);
  }
  assert.ok(!holdsStandIn(whole.ok), "the whole list holds no row not made");
  assert.ok(![page, ...shown].some((u) => holdsStandIn(u.value)), "none went out");
});

test("a_list_answered_in_a_burst_loads_none_of_its_stations_rows_before_or_after_the_others", async () => {
  // A switch of workspace subscribes its first screen's topics in one go, the list among the first: its stations' rows
  // loaded behind it (views.ts #head, a station a turn) went ahead of each answer after the list's, 2.3-3.5 ms each in
  // Hermes (2026-11-11); since 2026-11-12 nothing loads them.
  const t = setup({ all: true });
  const now = t.host.nowMs();
  const names = ["a", "b", "c", "d", "e"];
  t.set(workspace(), { id: "ws", stations: names.map((id) => ({ id, name: id, last_seen: null, version: null })) });
  const records = (st: number) => Array.from({ length: 84 }, (_, i) => ({ ...row(`${names[st]}${i}`, now - (i * 5 + st) * 3_600_000), agents: [session(`${names[st]}${i}`)] }));
  for (const [st, id] of names.entries()) {
    t.set(link(`ws/${id}`), { state: "online" });
    t.set(overview(`ws/${id}`), overviewOf([], [profile("p1")]));
    t.set(rows(`ws/${id}`), records(st));
  }
  for (const id of names) t.data.release(rows(`ws/${id}`));
  const loaded = () => names.filter((id) => t.data.loaded(rows(`ws/${id}`))).length;
  // What had been loaded as each message went out.
  const went: [number, number][] = [];
  const emit = t.host.emit.bind(t.host);
  t.host.emit = (client, message) => {
    went.push([(message as { id: number }).id, loaded()]);
    emit(client, message);
  };
  const burst: Topic[] = [
    { topic: "chats", scope: "ws", limit: 50 },
    { topic: "workspace", workspace: "ws" },
    { topic: "stations", scope: "ws" },
    { topic: "profiles", scope: "ws" },
    { topic: "workspaceMarks", scope: "ws" },
  ];
  burst.forEach((topic, i) => t.subscribe(1 + i, topic));
  const page = ui();
  await t.read(page, 1);
  await t.read(page, 1);
  const firsts = burst.map((_, i) => went.findIndex(([id]) => id === 1 + i));
  assert.ok(firsts.every((at) => at >= 0), `every topic answered: ${JSON.stringify(went)}`);
  // In the order subscribed, and none of the rows loaded till the last of them went.
  assert.deepEqual([...firsts].sort((a, b) => a - b), firsts);
  assert.deepEqual(firsts.map((at) => went[at]![1]), burst.map(() => 0), `rows loaded as each went out: ${JSON.stringify(went)}`);
  // Nor after: the list is a window over its stations' rows (db/chat-reads.ts `window`), whole as it first went, `more`
  // its rows past the page; nothing behind it to send it again for.
  assert.equal(loaded(), 0, "none of its stations' rows loaded");
  assert.equal(went.filter(([id]) => id === 1).length, 1, "the list sent once");
  assert.equal(madeItems(page.value).length, 50);
  assert.equal(page.value.more, 370);
});

test("writing_another_pref_does_not_make_a_chat_list_again", async () => {
  const t = setup();
  const u = ui();
  t.set(workspace(), oneStation());
  t.set(link("ws/st"), { state: "online" });
  t.set(rows("ws/st"), [row("1", t.host.nowMs() - 1000), row("2", t.host.nowMs() - 2000)]);
  t.set(prefs(), { archiveHint: "done" });
  t.subscribe(1, { topic: "chats", scope: "ws" });
  await t.read(u, 1);
  assert.deepEqual(ids(u.value), ["1", "2"]);
  const before = t.router.computed;
  // the app writes the workspace shown at each switch
  t.set(prefs(), { archiveHint: "done", workspace: "other" });
  await t.read(u, 1);
  assert.equal(t.router.computed, before, "the list was not made again");
  t.set(prefs(), { archiveHint: "off", workspace: "other" });
  await t.read(u, 1);
  assert.equal(t.router.computed, before + 1, "its archive hint makes it again");
});

test("chats_puts_together_the_online_stations", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  await t.read(u, 1);
  sameTopics(t.started(), [workspace(), prefs()]);
  assert.equal(u.value === undefined, true);
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const each = (st: string) => [rows(st), link(st), overview(st)];
  sameTopics(t.started(), [...each("ws/a"), ...each("ws/b"), ...each("ws/c")]);
  let v = u.value;
  // (who is looking, whether it is still read and each station's state are the core's: the list is sent its stations as
  // its rows read them, ChatsView)
  const chats = { topic: "chats", scope: "ws" };
  assert.deepEqual(whole(t, chats).me, { id: "Me@x.com", email: "Me@x.com" });
  assert.equal(whole(t, chats).loading, true);
  assert.deepEqual(whole(t, chats).stations, [
    { station: "ws/a", id: "a", name: "alpha", state: "connecting", message: null, running: 0, doing: "正在连接" },
    { station: "ws/b", id: "b", name: "beta", state: "connecting", message: null, running: 0, doing: "正在连接" },
    { station: "ws/c", id: "c", name: "gamma", state: "connecting", message: null, running: 0, doing: "正在连接" },
  ]);
  assert.deepEqual([v.me, v.loading, v.stations], [undefined, undefined, [{ station: "ws/a" }, { station: "ws/b" }, { station: "ws/c" }]]);
  assert.deepEqual(v.days, []);
  assert.deepEqual(v.note, { reading: true, text: "正在连接 3 台 station", failing: [], empty: false });
  assert.deepEqual([v.glyph.dim, v.glyph.online, v.glyph.summary], [3, 0, "3 台 station"]);
  t.set(link("ws/c"), { state: "offline" });
  const now = t.host.nowMs();
  const slack = row("s1", now - 2000);
  slack.connect = "c1";
  slack.origin = { teamName: "Acme", channel: "C1", channelName: "ops", threadTs: "1.0" };
  t.set(link("ws/a"), { state: "online" });
  t.set(rows("ws/a"), [row("1", now - 1000), slack]);
  t.set(link("ws/b"), { state: "online" });
  t.set(rows("ws/b"), [row("1", now - 1500)]);
  await t.read(u, 1);
  v = u.value;
  assert.equal(whole(t, chats).loading, false);
  assert.deepEqual([whole(t, chats).stations[0].state, whole(t, chats).stations[1].state], ["online", "online"]);
  let items = v.days[0].items;
  assert.deepEqual(ids(v), ["1", "1", "s1"]);
  assert.deepEqual([items[0].station, items[1].station, items[1].stationName], ["ws/a", "ws/b", "beta"]);
  // (what the list's rows say: no more of an agent than its mark shows, nor what no client reads of the chat: its
  // thread's Slack channel is said in `originText`, its agent's session the chat's own page's)
  const { lastActiveAt: _at, mine: _mine, origin: _origin, ...listed } = structuredClone(slack);
  const shown = { ...listed, station: "ws/a", stationName: "alpha", state: null, agents: [{ runtime: "claude" }] };
  assert.deepEqual(plain(items[2]), plain(shown));
  const held = whole(t, chats).days[0].items.find((i: J) => i.id === "s1");
  assert.deepEqual([held.origin, held.agents[0].key], [slack.origin, "s1"]);
  // A station given an emoji: its rows carry it (the rows made before are made again), and the stations list too.
  const withEmoji = stations(t.nowS());
  withEmoji.stations[1].emoji = "🍎";
  t.set(workspace(), withEmoji);
  await t.read(u, 1);
  assert.deepEqual(u.value.days[0].items.map((i: J) => i.stationEmoji ?? null), [null, "🍎", null]);
  // And an icon beside it: carried as it is (the clients draw it, or the emoji where they cannot).
  const withIcon = stations(t.nowS());
  withIcon.stations[1].emoji = "🍎";
  withIcon.stations[1].icon = "glyph:apple";
  t.set(workspace(), withIcon);
  await t.read(u, 1);
  assert.deepEqual(u.value.days[0].items.map((i: J) => i.stationIcon ?? null), [null, "glyph:apple", null]);
  t.set(link("ws/b"), { state: "offline" });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(ids(v), ["1", "1", "s1"]);
  assert.equal(whole(t, chats).stations[1].state, "offline");
  assert.equal(v.glyph.label, "3 台 station，1 台在线，2 台离线");
  assert.equal(v.note.reading, false);
  assert.deepEqual(v.trouble, { text: "2 台 station 异常", state: "offline", retry: false });
  items = v.days[0].items;
  // Said once, for the station: not on each of its rows.
  assert.deepEqual([items[0].offline, items[1].offline], [undefined, undefined]);
  assert.equal(v.stations[1].offline, "beta 离线");
  assert.deepEqual(shownRows(v).map((i: J) => i.offline), [undefined, "beta 离线", undefined]);
  t.set(link("ws/b"), { state: "online" });
  await t.read(u, 1);
  assert.deepEqual(u.value.trouble, { text: "gamma 离线", state: "offline", retry: false, station: "ws/c" });
  // A station's link coming and going changes its state in the list once, not each of its rows (1400 rows patched,
  // 278 KB, for each change of one station, 2026-11-08).
  t.set(link("ws/b"), { state: "reconnecting" });
  await t.host.time.pass(100);
  const said = t.host.takeEmitted().map(([, m]) => m as J).filter((m) => m.id === 1);
  assert.equal(said.length, 1);
  assert.ok(said[0].delta.every((op: J) => op.path[0] !== "days"), JSON.stringify(said[0].delta));
  u.value = applyOps(u.value, said[0].delta);
  assert.equal(u.value.stations[1].reconnecting, "正在重新连接 beta");
  t.set(link("ws/b"), { state: "online" });
  await t.read(u, 1);
  t.fail(rows("ws/a"), new CoreError("http_500", "坏了"));
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(whole(t, chats).stations[0], { station: "ws/a", id: "a", name: "alpha", state: "error", message: "坏了", running: 0, doing: "连不上" });
  assert.deepEqual(ids(v), ["1"]);
  t.set(rows("ws/a"), [row("1", now - 1000)]);
  t.set(link("ws/a"), { state: "reconnecting", message: "连接已断开" });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual([whole(t, chats).stations[0].state, whole(t, chats).stations[0].message], ["connecting", "连接已断开"]);
  assert.equal(ids(v).length, 2);
  assert.deepEqual(v.trouble, { text: "2 台 station 异常", state: "offline", retry: false });
  const reconnecting = (x: J) => shownRows(x).map((i: J) => [i.station, i.reconnecting ?? null]);
  assert.ok(v.days[0].items.every((i: J) => i.reconnecting === undefined));
  assert.ok(reconnecting(v).some(([s, r]: J) => s === "ws/a" && r === "正在重新连接 alpha"), JSON.stringify(v));
  assert.ok(reconnecting(v).every(([s, r]: J) => s === "ws/a" || r === null));
  t.set(link("ws/a"), { state: "error", message: "没有权限" });
  await t.read(u, 1);
  assert.ok(reconnecting(u.value).some(([s, r]: J) => s === "ws/a" && r === "无法连接 alpha，正在重试"));
  t.set(link("ws/a"), { state: "online" });
  await t.read(u, 1);
  assert.ok(reconnecting(u.value).every(([, r]: J) => r === null));
  t.fail(workspace(), new CoreError("not_found", "进不了这个工作区"));
  await t.read(u, 1);
  assert.equal(u.error.code, "not_found");
});

test("follows_the_workspaces_station_list", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  await t.read(u, 1);
  t.started();
  const withoutA = stations(t.nowS());
  withoutA.stations.splice(0, 1);
  t.set(workspace(), withoutA);
  await t.read(u, 1);
  assert.deepEqual(u.value.stations.map((s: J) => s.station), ["ws/b", "ws/c"]);
  assert.deepEqual(t.stopped(), []);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  sameTopics(t.stopped(), [rows("ws/a"), link("ws/a"), overview("ws/a")]);
});

test("groups_by_the_viewers_day_newest_first", async () => {
  const t = setup();
  t.host.setUtcOffsetMin(480);
  const now = t.host.nowMs();
  const offset = 480 * 60_000;
  const midnight = Math.floor((now + offset) / DAY_MS) * DAY_MS - offset;
  const today = midnight + (now - midnight) / 2;
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  t.set(rows("ws/st"), [row("1", midnight - 1000), row("2", midnight - 2 * DAY_MS - 1000), row("3", today), row("4", midnight - DAY_MS + 1000), row("a", midnight - 3 * DAY_MS - 1000)]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual(
    v.days.map((d: J) => [d.daysAgo, d.items.map((i: J) => i.id)]),
    [[0, ["3"]], [1, ["1", "4"]], [3, ["2"]], [4, ["a"]]],
  );
  // (when each day is, who is looking and the stations' state are the core's)
  const held = whole(t, { topic: "chats", scope: "ws" });
  assert.equal(held.days[1].at, midnight - 1000);
  assert.deepEqual(held.me, { id: "Me@x.com", email: "Me@x.com" });
  assert.deepEqual(held.stations, [{ station: "ws/st", id: "st", name: "studio", state: "online", message: null, running: 0, doing: "正在连接" }]);
  assert.deepEqual([v.days[1].at, v.me, v.stations], [undefined, undefined, [{ station: "ws/st" }]]);
});

test("grouping_a_large_chat_list_does_not_repeatedly_ask_the_time_zone_for_the_same_row", async () => {
  const t = setup();
  const u = ui();
  const topic: Topic = { topic: "chats", scope: "ws" };
  const now = t.host.nowMs();
  const cutover = now - 4 * DAY_MS;
  const input = Array.from({ length: 257 }, (_, i) => row(String(i + 1), now - 1_000_000 - ((i * 113) % 257) * 3_600_000));
  t.set(workspace(), oneStation());
  t.set(rows("ws/st"), input);
  // (all of it in its window)
  t.window(topic, input.length);
  t.subscribe(1, topic);
  await t.read(u, 1);
  await t.read(u, 1);
  assert.equal(ids(u.value).length, input.length);

  // The offset can differ at each row's time (for example across a daylight-saving change).
  const times = new Set(input.map((r) => r.lastActiveAt as number));
  const calls = new Map<number, number>();
  const offset = (at: number) => at < cutover ? 60 : 120;
  t.host.utcOffsetMin = (at) => {
    if (times.has(at)) calls.set(at, (calls.get(at) ?? 0) + 1);
    return offset(at);
  };
  const result = t.views.compute(topic);
  assert.ok(result && "ok" in result);
  const items = (result.ok as J).days.flatMap((d: J) => d.items);
  const day = (at: number) => Math.floor((at + offset(at) * 60_000) / DAY_MS);
  const expected = [...items].sort((a: J, b: J) => day(b.lastActiveAt) - day(a.lastActiveAt) || b.lastActiveAt - a.lastActiveAt);
  assert.deepEqual(items.map((r: J) => r.id), expected.map((r: J) => r.id));
  for (const group of (result.ok as J).days) {
    const d = day(group.items[0].lastActiveAt);
    assert.equal(group.daysAgo, day(now) - d);
    assert.ok(group.items.every((r: J) => day(r.lastActiveAt) === d));
  }
  assert.equal(calls.size, input.length, "each row uses the offset at its own time");
  const repeated = [...calls.values()].filter((n) => n > 1).length;
  assert.equal(repeated, 0, "each row's date is converted once while the list is ordered");
});

test("a_chat_the_viewer_kept_out_of_the_archive_has_the_rows_color_and_order", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const done = row("done", now);
  done.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
  const active = row("active", now - 1);
  for (const dismissed of [false, true]) {
    done.archiveReminderDismissed = dismissed;
    t.set(rows("ws/st"), [structuredClone(done), structuredClone(active)]);
    await t.read(u, 1);
    const v = u.value;
    assert.deepEqual(ids(v), ["done", "active"]);
    const shown = v.days[0].items.find((r: J) => r.id === "done");
    assert.equal(shown.settled, dismissed ? undefined : true);
    // (whether it could go with one tap whatever the hint is the core's)
    assert.equal(whole(t, { topic: "chats", scope: "ws" }).days[0].items.find((r: J) => r.id === "done").archivable, dismissed ? undefined : true);
    // Kept by the viewer: its whole row says so (its menu lets it go), not the list's.
    assert.deepEqual([shown.kept, (await wholeOf(t, v, dismissed ? 950 : 900)).done.kept], [undefined, dismissed ? true : undefined]);
    assert.equal(shown.stateText, "已完成");
  }
});

test("a_done_chat_is_offered_to_archive_as_the_archive_hint_says_and_archivable_whatever_it_says", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const done = row("done", now);
  done.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
  const active = row("active", now - 1);
  t.set(rows("ws/st"), [done, active]);
  for (const [hint, offered] of [[undefined, true], ["off", false], ["reviewed", false], ["done", true]] as const) {
    t.set(prefs(), hint === undefined ? {} : { archiveHint: hint });
    await t.read(u, 1);
    const v = u.value;
    assert.deepEqual(ids(v), ["done", "active"], String(hint));
    const shown = v.days[0].items.find((r: J) => r.id === "done");
    assert.equal(shown.settled, offered ? true : undefined, String(hint));
    assert.equal(whole(t, { topic: "chats", scope: "ws" }).days[0].items.find((r: J) => r.id === "done").archivable, true, String(hint));
    assert.equal(shown.archivable, undefined);
  }
});

test("any_made_chat_is_swiped_away_regardless_of_its_state_its_station_there", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  t.set(link("ws/st"), { state: "online" });
  await t.host.time.pass(100);
  const done = (id: string, more: J): J => {
    const r = row(id, now);
    r.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
    return { ...r, ...more };
  };
  const running = row("running", now - 1);
  running.agents[0].process = "running";
  const failed = row("failed", now - 2);
  failed.agents[0].lastTurn = { kind: "message", outcome: "failed", startedAt: 1, endedAt: 2 };
  const watching = row("watching", now - 3);
  watching.agents[0].watch = { names: ["CI"], since: 1, at: 2 };
  const decision = deciding("decision", 7, 3, now - 4, false);
  const pending = { ...row("pending", now - 5), pending: true };
  const empty = { ...row("empty", now - 6), agents: [] };
  t.set(rows("ws/st"), [
    done("unread", { unread: true }),
    done("pinned", { pinned: 5 }),
    done("kept", { archiveReminderDismissed: true }),
    done("reviewed", { archiveReviewed: true, archiveRecommended: false }),
    running,
    failed,
    watching,
    decision,
    pending,
    empty,
  ]);
  await t.read(u, 1);
  const flags = (v: J): J => Object.fromEntries(v.days.flatMap((d: J) => d.items.map((i: J) => [i.id, [i.swipeArchive ?? false, i.archivable ?? false]])));
  // A swipe is the viewer's own choice, not the recommendation to archive with one tap.
  assert.deepEqual(flags(u.value), {
    unread: [true, false], pinned: [true, false], kept: [true, false], reviewed: [true, false],
    running: [true, false], failed: [true, false], watching: [true, false], decision: [true, false], pending: [false, false], empty: [true, false],
  });
  // Only one at work or keeping watch is asked about before its swipe archives it.
  // (its whole row's, `chatRow`: a list's row says none, as a swipe asks it as it begins)
  const asks = Object.fromEntries(Object.entries(await wholeOf(t, u.value)).filter(([, w]) => w?.swipeAsk !== undefined).map(([id, w]) => [id, w.swipeAsk]));
  assert.deepEqual(asks, {
    running: "此对话正在进行中。归档后，agent 完成当前回复即停止，等待中的任务也会停止。",
    watching: "「CI」仍在监控。归档会停止监控。",
  });
  // Its station offline: nothing there to take it.
  t.set(link("ws/st"), { state: "offline" });
  await t.read(u, 1);
  assert.equal(shownRows(u.value).some((i: J) => i.swipeArchive === true), false);
});

test("a_chat_someone_else_started_asks_before_its_swipe_archives_it_for_the_whole_workspace", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  t.set(link("ws/st"), { state: "online" });
  await t.host.time.pass(100);
  const other = { id: "ana@x.com", email: "ana@x.com", name: "Ana", via: "web" };
  const mine = { id: "me@x.com", email: "me@x.com", name: "我", via: "web" };
  const running = { ...row("running", now - 3), creator: other };
  running.agents[0].process = "running";
  const watching = { ...row("watching", now - 5), creator: other };
  watching.agents[0].watch = { names: ["CI"], since: 1, at: 2 };
  const mineRunning = { ...row("mine-running", now - 6), creator: mine };
  mineRunning.agents[0].process = "running";
  t.set(rows("ws/st"), [
    { ...row("theirs", now), creator: other },
    { ...row("theirs-hides", now - 1), creator: other, hidden: false },
    { ...row("mine", now - 2), creator: mine },
    running,
    row("nobody", now - 4),
    watching,
    mineRunning,
  ]);
  await t.read(u, 1);
  // (its whole row's, `chatRow`: a list's row says none, as a swipe asks it as it begins)
  const asks = Object.fromEntries(Object.entries(await wholeOf(t, u.value)).filter(([, w]) => w?.swipeAsk !== undefined).map(([id, w]) => [id, w.swipeAsk]));
  // Archived, a chat is off the lists of everyone in the workspace, not the viewer's alone: one someone else started is
  // asked about first, the viewer's own way to take it off only their list said where it has one (its 隐藏).
  assert.deepEqual(asks, {
    theirs: "这是Ana发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。",
    "theirs-hides": "这是Ana发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。只想从自己的列表移走，可以长按选「隐藏」。",
    // (at work or keeping watch as well: both said, who it reaches first)
    running: "这是Ana发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。此对话正在进行中。归档后，agent 完成当前回复即停止，等待中的任务也会停止。",
    watching: "这是Ana发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。「CI」仍在监控。归档会停止监控。",
    "mine-running": "此对话正在进行中。归档后，agent 完成当前回复即停止，等待中的任务也会停止。",
  });
});

test("pinned_rows_go_above_the_days_the_latest_pinned_first", async () => {
  const t = setup();
  const now = t.host.nowMs();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const pinned = (id: string, at: number, p: J) => ({ ...row(id, at), pinned: p });
  t.set(rows("ws/st"), [pinned("1", now, null), pinned("2", now - 3 * DAY_MS, 5), pinned("3", now - 1000, 9), row("4", now - 2000)]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.days[0].label, v.days[0].daysAgo], ["已固定", -1]);
  // (that it is the pinned is the core's: the page knows it by its key, -1)
  assert.equal(whole(t, { topic: "chats", scope: "ws" }).days[0].pinned, true);
  assert.deepEqual(ids(v), ["3", "2", "1", "4"]);
  const flags = v.days.flatMap((d: J) => d.items.map((i: J) => ("pinned" in i ? i.pinned : "absent")));
  assert.deepEqual(flags, [true, true, false, "absent"]);
  assert.equal(v.days[1].pinned, undefined);
});

test("a_chat_an_agent_opened_leads_back_to_its_opener_wherever_that_is_and_only_so", async () => {
  // Each chat stands on its own (its place, its archiving): the one opened only knows the way back to its opener, by
  // that one's title as its list has it, else as it was called; on its own station or another.
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.host.time.pass(100);
  const now = t.host.nowMs();
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("gone", now - 5000), title: "归档的发起者", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [
    { ...row("opener", now - 3000), title: "RPG 人物与剑术演示" },
    { ...row("here", now), opener: { session: "opener", title: "旧名字" } },
    { ...row("orphan", now - 1000), opener: { session: "gone", title: "当时的名字" } },
  ]);
  t.set(rows("ws/b"), [{ ...row("there", now - 2000), opener: { station: "a", session: "opener", title: "旧名字" } }]);
  await t.read(u, 1);
  const byId = new Map<string, J>(u.value.days.flatMap((d: J) => d.items).map((i: J) => [i.id, i]));
  assert.deepEqual(byId.get("here").opener, { station: "ws/a", session: "opener", title: "RPG 人物与剑术演示", text: "由「RPG 人物与剑术演示」创建" });
  assert.deepEqual(byId.get("there").opener, { station: "ws/a", session: "opener", title: "RPG 人物与剑术演示", text: "由「RPG 人物与剑术演示」创建" });
  assert.deepEqual(byId.get("orphan").opener, { station: "ws/a", session: "gone", title: "归档的发起者", text: "由「归档的发起者」创建", archived: true, note: "已归档" });
  assert.equal(byId.get("opener").opener, undefined);
  // Its own place in the list, newest first, whoever opened it.
  assert.deepEqual(ids(u.value), ["here", "orphan", "there", "opener"]);
});

test("the_rows_are_led_by_the_agents_whatever_was_set", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  t.set(rows("ws/st"), []);
  await t.read(u, 1);
  assert.equal(u.value.leading, "agents");
  t.set(prefs(), { rowPicture: "people" });
  await t.read(u, 1);
  assert.equal(u.value.leading, "agents");
});

test("mine_keeps_the_rows_the_station_says_are_the_viewers", async () => {
  const t = setup();
  const [all, mine] = [ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(all, 1);
  const now = t.host.nowMs();
  const w = (id: string, at: number, m: boolean) => ({ ...row(id, at), mine: m });
  t.set(rows("ws/a"), [w("1", now - 1, true), w("k", now - 2, false)]);
  t.set(rows("ws/b"), [w("1", now - 3, false), w("j", now - 4, true)]);
  await t.read(all, 1);
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  await t.read(mine, 2);
  assert.deepEqual(ids(all.value), ["1", "k", "1", "j"]);
  assert.deepEqual(ids(mine.value), ["1", "j"]);
  assert.equal(mine.value.days[0].items[1].station, "ws/b");
});

test("a_hidden_chat_stays_out_of_normal_lists_but_is_findable_and_can_be_restored", async () => {
  const t = setup();
  const [all, hidden, found] = [ui(), ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.subscribe(2, { topic: "chats", scope: "ws", hidden: true });
  t.subscribe(3, { topic: "chatSearch", scope: "ws", query: "标题" });
  t.set(workspace(), oneStation());
  const now = t.host.nowMs();
  const hiddenRow = { ...row("7", now), hidden: true, mine: true };
  t.set(rows("ws/st"), [hiddenRow, { ...row("8", now - 1), hidden: false }]);
  await t.readAll([[all, 1], [hidden, 2], [found, 3]]);
  assert.deepEqual(ids(all.value), ["8"]);
  assert.deepEqual(ids(hidden.value), ["7"]);
  assert.deepEqual(found.value.items.map((item: J) => [item.id, item.hidden]), [["7", true], ["8", false]]);
  // A new message or completion changes the row, but does not restore it.
  t.set(rows("ws/st"), [{ ...hiddenRow, unread: true, lastActiveAt: now + 1 }, { ...row("8", now - 1), hidden: false }]);
  await t.readAll([[all, 1], [hidden, 2]]);
  assert.deepEqual(ids(all.value), ["8"]);
  assert.deepEqual(ids(hidden.value), ["7"]);
  t.set(rows("ws/st"), [{ ...hiddenRow, hidden: false }, { ...row("8", now - 1), hidden: false }]);
  await t.readAll([[all, 1], [hidden, 2]]);
  assert.deepEqual(ids(all.value), ["7", "8"]);
  assert.deepEqual(ids(hidden.value), []);
});

test("watching_keeps_the_rows_one_of_whose_agents_keeps_watch_marked_so", async () => {
  const t = setup();
  const [all, watching] = [ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(all, 1);
  const now = t.host.nowMs();
  const ci = row("ci", now - 1);
  ci.agents[0].watch = { names: ["盯 CI"], since: Math.trunc(now) - 10, at: Math.trunc(now) - 5 };
  t.set(rows("ws/a"), [ci, row("plain", now - 2)]);
  await t.read(all, 1);
  t.subscribe(2, { topic: "chats", scope: "ws", watching: true });
  await t.read(watching, 2);
  assert.deepEqual(ids(all.value), ["ci", "plain"]);
  // (what it watches in words: its whole row's, what its archiving asks; the list's rows say none)
  const whole = await wholeOf(t, all.value);
  assert.deepEqual([whole.ci.watch.text, whole.plain.watch, all.value.days[0].items[0].watch], ["监控中：盯 CI", undefined, undefined]);
  assert.deepEqual(ids(watching.value), ["ci"]);
});

test("a_chats_unread_is_a_mark_and_its_title_comes_from_what_was_said", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const now = t.host.nowMs();
  const named = { ...row("1", now - 1), title: "排查", unread: true, last: { seq: 7, authorKind: "agent", author: "a", authorName: null, text: "好的", createdAt: Math.trunc(now) - 1 } };
  const saidRow = { ...row("2", now - 2), title: "看看 这个" };
  t.set(rows("ws/st"), [named, saidRow]);
  await t.read(u, 1);
  const rowsOf = () => u.value.days[0].items.map((i: J) => [i.id, i.title, i.unread]);
  assert.deepEqual(rowsOf(), [["1", "排查", true], ["2", "看看 这个", false]]);
  t.data.putChat("ws/st", { ...named, unread: false });
  await t.read(u, 1);
  assert.equal(rowsOf()[0][2], false);
});

test("many_changes_are_one_computation_and_one_emission", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const [computed, messages] = [t.router.computed, u.messages];
  for (const st of ["ws/a", "ws/b"]) {
    t.set(link(st), { state: "online" });
    t.set(rows(st), [row("1", t.host.nowMs())]);
  }
  t.data.putChat("ws/a", { ...row("1", t.host.nowMs()), title: "改了" });
  await t.read(u, 1);
  assert.equal(t.router.computed, computed + 1);
  assert.equal(u.messages, messages + 1);
  assert.equal(u.value.days[0].items.length, 2);
  t.set(link("ws/a"), { state: "online" });
  await t.read(u, 1);
  assert.equal(t.router.computed, computed + 2);
  assert.equal(u.messages, messages + 1);
});

test("a_station_refusing_for_a_security_mode_says_why_in_place_of_offline", async () => {
  // A station added to another workspace, taking none of its members yet, showed only 离线 there (2026-10-23).
  const t = setup();
  const list = ui();
  const chats = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.subscribe(2, { topic: "chats", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.readAll([[list, 1], [chats, 2]]);
  const why = "此 workspace 在此 station 加入后才开启安全模式，它不再接受此 workspace 的成员：请将它从此 workspace 移除后重新添加";
  t.set(link("ws/a"), { state: "online" });
  t.set(link("ws/c"), { state: "online" });
  t.set(link("ws/b"), { state: "offline", cause: "lock", message: why });
  await t.readAll([[list, 1], [chats, 2]]);
  const b = (list.value as J[]).find((s) => s.station === "ws/b");
  assert.deepEqual([b.online, b.summary, b.line, b.blocked], [false, "安全模式未放行", "安全模式未放行", why]);
  const v = chats.value;
  // (its rows are sent what they read of it; why and how it is, the core's)
  assert.deepEqual(v.stations.find((s: J) => s.station === "ws/b"), { station: "ws/b", offline: "安全模式未放行 beta" });
  assert.deepEqual(whole(t, { topic: "chats", scope: "ws" }).stations.find((s: J) => s.station === "ws/b"), { station: "ws/b", id: "b", name: "beta", state: "offline", message: why, cause: "lock", running: 0, doing: "安全模式未放行", offline: "安全模式未放行 beta" });
  assert.deepEqual(v.trouble, { text: "安全模式未放行 beta", state: "offline", retry: false, station: "ws/b" });
  // Down for another reason: as before, nothing of a security mode.
  t.set(link("ws/b"), { state: "offline", cause: "unreached" });
  await t.readAll([[list, 1], [chats, 2]]);
  const again = (list.value as J[]).find((s) => s.station === "ws/b");
  assert.deepEqual([again.summary, again.blocked], ["连不上", undefined]);
  assert.equal(chats.value.trouble.text, "无法连接 beta");
});

test("stations_that_find_this_core_too_old_say_so_once_and_one_among_others_amiss_is_counted", async () => {
  // Every station answered a stable page 426 (2026-11-10): its list said 「4 台 station 异常」, nothing of why.
  for (const app of [true, false]) {
    const t = setup();
    t.host.appKeys = app;
    const chats = ui();
    t.subscribe(1, { topic: "chats", scope: "ws" });
    t.set(workspace(), stations(t.nowS()));
    await t.read(chats, 1);
    const said = app ? "这个 app 版本太旧，station 已不再支持：请更新 app" : "这个页面版本太旧，station 已不再支持：请刷新页面";
    t.set(link("ws/a"), { state: "error", message: "请更新 app", old: "app" });
    t.set(link("ws/b"), { state: "error", message: "请更新 app", old: "app" });
    t.set(link("ws/c"), { state: "online" });
    await t.read(chats, 1);
    // Said once, not as so many stations amiss; each station's own sentence still its message.
    assert.deepEqual(chats.value.trouble, { text: said, state: "error", retry: false });
    assert.deepEqual(whole(t, { topic: "chats", scope: "ws" }).stations.filter((s: J) => s.state === "error").map((s: J) => [s.station, s.message]), [["ws/a", "请更新 app"], ["ws/b", "请更新 app"]]);
    // One alone: the same words, its mark beside them.
    t.set(link("ws/b"), { state: "online" });
    await t.read(chats, 1);
    assert.deepEqual(chats.value.trouble, { text: said, state: "error", retry: false, station: "ws/a" });
    // Among others amiss for another reason: counted as before.
    t.set(link("ws/b"), { state: "offline" });
    await t.read(chats, 1);
    assert.deepEqual(chats.value.trouble, { text: "2 台 station 异常", state: "error", retry: false });
    // One this core finds too old: that it is, by name, as a station saying what this core cannot read.
    t.set(link("ws/a"), { state: "error", message: "此 station 版本过旧", old: "station" });
    t.set(link("ws/b"), { state: "online" });
    await t.read(chats, 1);
    assert.deepEqual(chats.value.trouble, { text: "alpha 版本不兼容，需要更新", state: "incompatible", retry: false, station: "ws/a" });
  }
});

test("a station's mode is the viewer's to change where they added it, or no member did and they own the workspace", async () => {
  // Its owner is who added it, whatever the viewer's role (the user, 2026-11-10; cloud/src/directory.ts setStationMode).
  const t = setup();
  const list = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  const of = (role: string): J => ({
    id: "ws",
    role,
    members: [{ sub: "s1", role }, { sub: "s2", role: "admin" }],
    stations: [
      { id: "a", name: "alpha", enrolled_by: "s1", last_seen: null, version: null },
      { id: "b", name: "beta", enrolled_by: "s2", last_seen: null, version: null },
      { id: "c", name: "gamma", enrolled_by: "gone", last_seen: null, version: null },
    ],
  });
  const mine = () => (list.value as J[]).map((s) => [s.id, s.mine]);
  t.set(workspace(), of("admin"));
  await t.read(list, 1);
  assert.deepEqual(mine(), [["a", true], ["b", false], ["c", false]], "an admin: only what they added");
  t.set(workspace(), of("member"));
  await t.read(list, 1);
  assert.deepEqual(mine(), [["a", true], ["b", false], ["c", false]], "a member: what they added too");
  t.set(workspace(), of("owner"));
  await t.read(list, 1);
  assert.deepEqual(mine(), [["a", true], ["b", false], ["c", true]], "the owner: one no member added as well, never another member's");
});

/// A station's overview with what changes most and no row shows: each profile's quota by the minute, its decisions.
const busyOverview = (used: number, decided: boolean, running = 0): J => ({
  ...overviewOf([], [profile("p", { model: "claude-opus-5-5", models: ["claude-opus-5-5"], quota: { state: "ok", windows: [{ label: "5h", usedPercent: used, resetsAt: 9_000_000_000_000 }], checkedAt: 1 } })]),
  counts: { sessions: 3, running, warm: 0 },
  disk: { freeBytes: 10, totalBytes: 100 },
  drive: { roots: [{ path: "/Users/me", name: "me", state: "ok" }] },
  automaticDecisions: { canEdit: true, settings: { completion: { enabled: decided, model: null } }, models: [], recent: [] },
  archiving: { days: 7, slackDays: 0, reviewed: false, canEdit: true },
});

/// Every station of `stations` up, each with its host (once the views asked for it) and that overview.
async function allUp(t: ReturnType<typeof setup>, ids = ["a", "b", "c"]): Promise<void> {
  t.set(workspace(), ids.length === 3 ? stations(t.nowS()) : { id: "ws", stations: ids.map((id) => ({ id, name: id === "a" ? "alpha" : "beta", last_seen: null, version: null })) });
  for (const id of ids) {
    t.set(link(`ws/${id}`), { state: "online" });
    t.set(overview(`ws/${id}`), busyOverview(20, false));
  }
  await t.host.time.pass(100);
  for (const id of ids) t.set(hostOf(`ws/${id}`), hostInfo(id));
}

test("a_list_of_stations_is_rows_one_station_its_page_and_the_models_are_the_cores_own", async () => {
  // Each model with each account's quota was most of a phone's list (463 KB, 25-86 ms each time it came, 2026-11-10):
  // a list's item is what its row shows, a station's page asks that station.
  const t = setup({ all: true });
  const [list, page, whole] = [ui(), ui(), ui()];
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.subscribe(2, { topic: "station", scope: "ws", station: "ws/a" });
  t.subscribe(3, { topic: "stationsWhole", scope: "ws" });
  await allUp(t);
  await t.readAll([[list, 1], [page, 2], [whole, 3]]);
  const a = (list.value as J[]).find((s) => s.station === "ws/a");
  assert.deepEqual(Object.keys(a).sort(), ["face", "host", "id", "joined", "lastSeen", "line", "mine", "name", "online", "overview", "problems", "reconnecting", "stateBusy", "stateText", "station", "summary", "version"]);
  const allowed = new Set(["station", "id", "name", "emoji", "icon", "summary", "face", "line", "online", "reconnecting", "blocked", "stateText", "stateBusy", "problems", "lastSeen", "version", "way", "joined", "home", "mine", "host", "overview"]);
  for (const row of list.value as J[]) assert.deepEqual(Object.keys(row).filter((k) => !allowed.has(k)), [], row.station);
  assert.deepEqual(Object.keys(a.overview).sort(), ["counts", "disk", "drive", "viewer"]);
  assert.deepEqual(Object.keys(a.host).sort(), ["identity", "meters", "os"]);
  assert.deepEqual([a.overview.counts.sessions, a.overview.drive.roots[0].path, a.host.os], [3, "/Users/me", "macOS 26"]);
  // Its page: all of it but the models.
  const p: J = page.value;
  assert.equal(p.station, "ws/a");
  assert.equal(p.models, undefined);
  assert.equal(p.overview.profiles.length, 1);
  assert.ok(Array.isArray(p.runtimes) && Array.isArray(p.profileGroups) && p.link !== undefined);
  assert.equal(p.summary, a.summary);
  // The core's own whole list: the models too.
  const w = (whole.value as J[]).find((s) => s.station === "ws/a");
  assert.ok((w.models as J[]).length > 0);
  assert.equal(w.overview.profiles.length, 1);
  // A station the workspace has not: null; the workspace not read yet: not known, as the list.
  const none = ui();
  t.subscribe(4, { topic: "station", scope: "ws", station: "ws/zzz" });
  await t.read(none, 4);
  assert.equal(none.value, null);
  const t2 = setup({ all: true });
  const [list2, page2] = [ui(), ui()];
  t2.subscribe(1, { topic: "stations", scope: "ws" });
  t2.subscribe(2, { topic: "station", scope: "ws", station: "ws/a" });
  await t2.readAll([[list2, 1], [page2, 2]]);
  assert.deepEqual([list2.messages, page2.messages], [0, 0]);
});

test("a_list_of_stations_says_nothing_of_what_its_rows_do_not_show", async () => {
  const t = setup();
  // (taking keyed ops, as the app does)
  t.store.subscribe(1, 1, { topic: "stations", scope: "ws" }, true);
  let list: J;
  const said = async () => {
    await t.host.time.pass(100);
    const out = t.host.takeEmitted().map(([, m]) => m as J).filter((m) => m.id === 1);
    for (const m of out) list = "value" in m ? m.value : applyKeyed(list, m.delta);
    return out;
  };
  await allUp(t);
  await said();
  assert.deepEqual(await said(), []);
  assert.equal(list.find((s: J) => s.station === "ws/a").host.os, "macOS 26");
  // (a) a minute passes
  await t.host.time.pass(60_000);
  assert.deepEqual(await said(), [], "a minute");
  // (b) a profile's quota changes on one station
  t.set(overview("ws/b"), busyOverview(70, false));
  assert.deepEqual(await said(), [], "a quota");
  // (c) its automatic decisions change
  t.set(overview("ws/b"), busyOverview(70, true));
  assert.deepEqual(await said(), [], "its decisions");
  // (d) one station's agents at work: that item alone, patched
  t.set(overview("ws/a"), busyOverview(20, false, 2));
  const out = await said();
  assert.equal(out.length, 1);
  assert.equal(out[0].delta.length, 1, JSON.stringify(out[0].delta));
  assert.equal(out[0].delta[0].patch, "ws/a");
  assert.equal(list.find((s: J) => s.station === "ws/a").overview.counts.running, 2);
});

test("a_station_whose_overview_this_core_cannot_read_says_so_in_its_row_as_on_its_page", async () => {
  // What it cannot read is outside the row's four parts: the row says so all the same, as its page does.
  const t = setup({ all: true });
  const [list, page] = [ui(), ui()];
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.subscribe(2, { topic: "station", scope: "ws", station: "ws/a" });
  await allUp(t);
  t.set(overview("ws/a"), { ...busyOverview(20, false), processes: "a station newer than the app" });
  await t.readAll([[list, 1], [page, 2]]);
  const row = (list.value as J[]).find((s) => s.station === "ws/a");
  const p: J = page.value;
  assert.equal(row.summary, words("core-views.station.incompatible_short"));
  // (its line under its name is the rows' alone: its page holds it, and is not sent it)
  assert.deepEqual([row.summary, row.line, row.problems], [p.summary, whole(t, { topic: "station", scope: "ws", station: "ws/a" }).line, p.problems]);
  assert.equal(p.line, undefined);
  assert.deepEqual(row.problems.map((x: J) => x.key), ["incompatible"]);
  assert.equal(row.overview, undefined);
  // Read again: as any other.
  t.set(overview("ws/a"), busyOverview(20, false));
  await t.readAll([[list, 1], [page, 2]]);
  const again = (list.value as J[]).find((s) => s.station === "ws/a");
  assert.deepEqual(again.problems, []);
  assert.deepEqual(Object.keys(again.overview).sort(), ["counts", "disk", "drive", "viewer"]);
});

test("a_stations_overview_is_decorated_once_for_its_record_by_the_list_and_the_profiles_and_not_again_as_the_list_is_asked_anew", async () => {
  // The list decorated every station's whole overview for whether it can be read, the profiles all of them again, and
  // the list all of them again as it was asked a minute after it was let go (12–13 ms of its 14–16 ms in Hermes, 5
  // stations of 150 KB each).
  const t = setup({ all: true });
  const [list, profiles, again] = [ui(), ui(), ui()];
  const from = { ...work };
  t.subscribe(1, { topic: "stations", scope: "ws" });
  await allUp(t);
  await t.read(list, 1);
  assert.equal(workSince(from).overviews, 3, "the list: each station's overview once");
  t.subscribe(2, { topic: "profiles", scope: "ws" });
  await t.read(profiles, 2);
  assert.equal(profiles.value.items.length, 3);
  assert.equal(workSince(from).overviews, 3, "the profiles take what the list made");
  t.store.unsubscribe(1, 1);
  t.store.unsubscribe(1, 2);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  assert.ok(!t.store.liveTopics().some((topic) => topic.topic === "stations" || topic.topic === "profiles"), "both let go");
  const before = { ...work };
  t.subscribe(3, { topic: "stations", scope: "ws" });
  await t.read(again, 3);
  assert.equal(workSince(before).overviews, 0, "asked again, no overview changed: none");
  assert.deepEqual(again.value, list.value);
});

/// An overview this core cannot read (a station newer than the app: a field of another type than it knows).
const newerOverview = (): J => ({ ...busyOverview(20, false), processes: "a station newer than the app" });

/// The stations' rows asked of a core started anew on the database `first` left (its host's), its stations up again
/// (their links and hosts are not kept), and what that took.
async function stationsAnew(first: ReturnType<typeof setup>) {
  const before = { ...work };
  const t = setup({ all: true, host: first.host });
  const list = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  for (const id of ["a", "b", "c"]) t.set(link(`ws/${id}`), { state: "online" });
  await t.host.time.pass(100);
  for (const id of ["a", "b", "c"]) t.set(hostOf(`ws/${id}`), hostInfo(id));
  await t.read(list, 1);
  return { t, list, made: workSince(before) };
}

/// Each station's verdict kept beside its overview (`station_fit`): its shapes' id and whether it could be read.
const verdicts = (t: ReturnType<typeof setup>): string[] =>
  t.host.sqls.get(dbName("s1"))!.all("SELECT address, shapes, readable FROM station_fit ORDER BY address, shapes").map((r: J) => `${r[0]} ${r[1] === OVERVIEW_FIT() ? "this" : r[1]} ${r[2]}`);

/// A list's rows but how each is reached (a rig's links as it set them).
const rowsOf = (list: Ui): J[] => (list.value as J[]).map(({ reconnecting: _r, ...row }) => row);

/// The stations' rows as a core first asks them, with station c's overview one it cannot read.
async function stationsFirst() {
  const t = setup({ all: true });
  const list = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  await allUp(t);
  t.set(overview("ws/c"), newerOverview());
  await t.read(list, 1);
  return { t, list };
}

test("a_core_started_anew_lists_its_stations_reading_and_decorating_no_overview", async () => {
  // The list decorated each station's whole overview for whether this core could read it, and read and parsed each for
  // the four parts its row shows: 10.6 ms and 3.2 ms of its 14.9 ms in Hermes (5 stations of 25-27 KB), on each start.
  // Both are kept beside the overview as it is written (its part, its verdict): read of the database, not the overview.
  const first = await stationsFirst();
  assert.deepEqual(verdicts(first.t), ["ws/a this 1", "ws/b this 1", "ws/c this 0"], "judged as each was written");
  const again = await stationsAnew(first.t);
  assert.equal(again.made.overviews, 0, "no overview decorated");
  assert.equal(again.made.overviewsRead, 0, "no overview read");
  assert.deepEqual(rowsOf(again.list), rowsOf(first.list));
  const c = (again.list.value as J[]).find((s) => s.station === "ws/c");
  assert.deepEqual([c.summary, c.problems.map((x: J) => x.key), c.overview], [words("core-views.station.incompatible_short"), ["incompatible"], undefined]);
  assert.deepEqual(Object.keys((again.list.value as J[]).find((s) => s.station === "ws/a").overview).sort(), ["counts", "disk", "drive", "viewer"]);
});

test("an_overview_written_without_a_verdict_is_judged_as_it_is_first_read_and_the_verdict_kept", async () => {
  const first = await stationsFirst();
  const sql = first.t.host.sqls.get(dbName("s1"))!;
  // An older core writes station a's overview as it always did (one this core cannot read) and b's (one it can): no
  // verdict on either; their parts kept all the same.
  const write = (station: string, o: J) => sql.run("INSERT INTO station (address, kind, json, confirmed) VALUES (?, 'overview', ?, 2) ON CONFLICT (address, kind) DO UPDATE SET json = excluded.json, confirmed = coalesce(excluded.confirmed, confirmed)", [station, JSON.stringify(o)]);
  write("ws/a", newerOverview());
  write("ws/b", busyOverview(20, false, 4));
  assert.deepEqual(verdicts(first.t), ["ws/c this 0"]);
  const again = await stationsAnew(first.t);
  // Judged as now, each once.
  assert.equal(again.made.overviews, 2);
  const row = (s: string) => (again.list.value as J[]).find((x) => x.station === s);
  assert.deepEqual(row("ws/a").problems.map((x: J) => x.key), ["incompatible"]);
  assert.equal(row("ws/a").overview, undefined);
  assert.equal(row("ws/b").overview.counts.running, 4, "its row as written, of its part");
  await again.t.host.time.pass(100);
  assert.deepEqual(verdicts(again.t), ["ws/a this 0", "ws/b this 1", "ws/c this 0"], "kept");
  // and not judged again
  const third = await stationsAnew(again.t);
  assert.deepEqual([third.made.overviews, third.made.overviewsRead], [0, 0]);
  assert.deepEqual(third.list.value, again.list.value);
});

test("a_verdict_kept_under_other_shapes_is_not_this_cores", async () => {
  const first = await stationsFirst();
  const sql = first.t.host.sqls.get(dbName("s1"))!;
  // Another core's verdicts (an app put back to an older one, its shapes otherwise): c readable to it, a not.
  sql.run("INSERT INTO station_fit (address, shapes, readable) VALUES ('ws/a', 'other', 0), ('ws/c', 'other', 1)");
  sql.run("DELETE FROM station_fit WHERE shapes <> 'other'");
  const again = await stationsAnew(first.t);
  assert.equal(again.made.overviews, 3, "each judged as now");
  assert.deepEqual(rowsOf(again.list), rowsOf(first.list));
  await again.t.host.time.pass(100);
  assert.deepEqual(verdicts(again.t), ["ws/a this 1", "ws/a other 0", "ws/b this 1", "ws/c this 0", "ws/c other 1"]);
});

test("a_database_from_before_the_rows_part_and_verdicts_is_brought_to_them_and_lists_the_same_stations", async () => {
  const first = await stationsFirst();
  const sql = first.t.host.sqls.get(dbName("s1"))!;
  // As a core before them left it: no verdicts, the parts of the chat list alone (no row's column), kept by its triggers.
  const before = overviewPartOf;
  sql.exec(`
    DROP TRIGGER station_fit_put; DROP TRIGGER station_fit_set; DROP TRIGGER station_fit_drop; DROP TABLE station_fit;
    DROP TRIGGER station_part_put; DROP TRIGGER station_part_set; DROP TRIGGER station_part_drop; DROP TABLE station_part;
    CREATE TABLE station_part (address TEXT PRIMARY KEY, part TEXT NOT NULL);
    CREATE TRIGGER IF NOT EXISTS station_part_put AFTER INSERT ON station WHEN new.kind = 'overview'
    BEGIN
      DELETE FROM station_part WHERE address = new.address;
      INSERT INTO station_part (address, part) SELECT new.address, ${before("new.json")} WHERE json_valid(new.json);
    END;
    CREATE TRIGGER IF NOT EXISTS station_part_set AFTER UPDATE OF json ON station WHEN new.kind = 'overview' AND old.json IS NOT new.json
    BEGIN
      DELETE FROM station_part WHERE address = new.address;
      INSERT INTO station_part (address, part) SELECT new.address, ${before("new.json")} WHERE json_valid(new.json);
    END;
    CREATE TRIGGER IF NOT EXISTS station_part_drop AFTER DELETE ON station WHEN old.kind = 'overview'
    BEGIN
      DELETE FROM station_part WHERE address = old.address;
    END;
    INSERT INTO station_part (address, part) SELECT st.address, ${before("st.json")} FROM station AS st WHERE st.kind = 'overview';
  `);
  const parts = () => sql.all("SELECT address, json_type(row) FROM station_part ORDER BY address").map((r: J) => `${r[0]} ${r[1]}`);
  const partsBefore = sql.all("SELECT address, part FROM station_part ORDER BY address");
  const again = await stationsAnew(first.t);
  // Brought to them as it opened, at its version (a core before them still writes it): the triggers made again, every
  // part with them, by SQLite.
  assert.equal(sql.all("PRAGMA user_version")[0][0], VERSION);
  assert.deepEqual(parts(), ["ws/a object", "ws/b object", "ws/c object"]);
  // (what the chat list reads, and an older core reads, as it was)
  assert.deepEqual(sql.all("SELECT address, part FROM station_part ORDER BY address"), partsBefore);
  assert.ok(String(sql.all("SELECT sql FROM sqlite_master WHERE name = 'station_part_set'")[0]?.[0]).includes("(address, part, row, chat, formerly, profiles, profiled)"));
  assert.equal(again.made.overviewsRead, 3, "read only to be judged");
  assert.deepEqual(rowsOf(again.list), rowsOf(first.list));
  await again.t.host.time.pass(100);
  assert.deepEqual(verdicts(again.t), ["ws/a this 1", "ws/b this 1", "ws/c this 0"]);
  // A core before them writing an overview: its part made with the row all the same (the triggers are this core's).
  sql.run("UPDATE station SET json = ? WHERE address = 'ws/b' AND kind = 'overview'", [JSON.stringify(busyOverview(20, false, 6))]);
  assert.equal(sql.all("SELECT row -> '$.counts.running' FROM station_part WHERE address = 'ws/b'")[0][0], "6");
});

test("a_verdict_goes_as_its_overview_changes_or_goes_whoever_writes_it", async () => {
  const { t } = await stationsFirst();
  const sql = t.host.sqls.get(dbName("s1"))!;
  const json = (s: string) => String(sql.all("SELECT json FROM station WHERE address = ? AND kind = 'overview'", [s])[0][0]);
  // Written again the same: kept.
  sql.run("UPDATE station SET json = ?, confirmed = 3 WHERE address = 'ws/a' AND kind = 'overview'", [json("ws/a")]);
  assert.deepEqual(verdicts(t), ["ws/a this 1", "ws/b this 1", "ws/c this 0"]);
  // Changed: gone.
  sql.run("UPDATE station SET json = ? WHERE address = 'ws/a' AND kind = 'overview'", [JSON.stringify(busyOverview(30, false))]);
  assert.deepEqual(verdicts(t), ["ws/b this 1", "ws/c this 0"]);
  // Put anew (as an older core's upsert or a replace): gone.
  sql.run("INSERT OR REPLACE INTO station (address, kind, json, confirmed) VALUES ('ws/b', 'overview', ?, 1)", [json("ws/b")]);
  assert.deepEqual(verdicts(t), ["ws/c this 0"]);
  // Its overview gone: gone.
  sql.run("DELETE FROM station WHERE address = 'ws/c' AND kind = 'overview'");
  assert.deepEqual(verdicts(t), []);
  // Written by this core: judged as it is written.
  t.set(overview("ws/a"), newerOverview());
  await t.host.time.pass(100);
  assert.deepEqual(verdicts(t), ["ws/a this 0"]);
});

test("a_stations_words_about_time_follow_the_minute_watched_or_asked_anew", async () => {
  const t = setup({ all: true });
  t.store.setClock();
  const now = t.host.nowMs();
  // (its allowance read 30 s before: 刚刚, then so many minutes ago)
  const read = { ...busyOverview(20, false), profiles: [profile("p", { quota: { state: "ok", windows: [{ label: "5h", usedPercent: 20, resetsAt: now + 86_400_000 }], checkedAt: now - 30_000 } })] };
  t.set(workspace(), { id: "ws", stations: [{ id: "a", name: "alpha", last_seen: null, version: null }] });
  t.set(link("ws/a"), { state: "online" });
  t.set(overview("ws/a"), read);
  const ago = () => format.relativeTime(now - 30_000, t.host.nowMs(), 0);
  const [page, profiles] = [ui(), ui()];
  t.subscribe(1, { topic: "station", scope: "ws", station: "ws/a" });
  t.subscribe(2, { topic: "profile", scope: "ws", station: "ws/a", id: "p" });
  const said = async () => {
    await t.readAll([[page, 1], [profiles, 2]]);
    return [page.value.overview.profiles[0].quota.time.checkedAt.ago, profiles.value.profile.quota.time.checkedAt.ago];
  };
  assert.deepEqual(await said(), [ago(), ago()]);
  assert.equal(ago(), words("core-logic.format.ago.now"));
  // Watched: made again as the minute passes.
  await t.host.time.pass(150_000, 1000);
  assert.equal(ago(), words("core-logic.format.ago.minutes", { n: 3 }));
  assert.deepEqual(await said(), [ago(), ago()], "watched, minutes on");
  // Let go, then asked anew minutes later with its record unchanged: what was kept for it is not taken.
  t.store.unsubscribe(1, 1);
  t.store.unsubscribe(1, 2);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  const [page2, profiles2] = [ui(), ui()];
  t.subscribe(3, { topic: "station", scope: "ws", station: "ws/a" });
  t.subscribe(4, { topic: "profile", scope: "ws", station: "ws/a", id: "p" });
  await t.readAll([[page2, 3], [profiles2, 4]]);
  assert.notEqual(ago(), words("core-logic.format.ago.minutes", { n: 3 }));
  assert.deepEqual([page2.value.overview.profiles[0].quota.time.checkedAt.ago, profiles2.value.profile.quota.time.checkedAt.ago], [ago(), ago()], "asked anew, minutes later");
});

test("a_part_of_a_stations_overview_is_its_pages_and_changes_only_with_it", async () => {
  const t = setup({ all: true });
  const [page, part] = [ui(), ui()];
  t.subscribe(1, { topic: "station", scope: "ws", station: "ws/a" });
  t.subscribe(2, { topic: "stationPart", scope: "ws", station: "ws/a", part: "archiving" });
  await allUp(t);
  await t.readAll([[page, 1], [part, 2]]);
  assert.ok(part.value !== null && part.value.days === 7);
  assert.deepEqual(part.value, page.value.overview.archiving);
  // Another part of its overview changes (a profile's quota): nothing on this one. (Its decisions are its own: its
  // review's words are said in it.)
  t.set(overview("ws/a"), busyOverview(70, false));
  await t.host.time.pass(100);
  assert.deepEqual(t.host.takeEmitted().filter(([, m]) => (m as J).id === 2), []);
  // Not read, or a station it does not have: null.
  const other = ui();
  t.subscribe(3, { topic: "stationPart", scope: "ws", station: "ws/zzz", part: "profiles" });
  await t.read(other, 3);
  assert.equal(other.value, null);
});

test("a_profiles_resets_say_when_they_end_wherever_its_overview_goes_out_and_as_it_is_read_again", async () => {
  // A profile's page showed when its resets end as it opened, and no longer a few seconds on, once its station's
  // overview was read again (the user, 2026-11-11): the page's value then shares with the one before, goes out as a
  // new value and has its times put again, and a row put again had lost what said when it ends. A part of the
  // overview and an account's own topic (`profile`) never said it.
  const t = setup({ all: true });
  const [page, part, list] = [ui(), ui(), ui()];
  const day = 86_400_000;
  const now = t.host.nowMs();
  // (half a day and half an hour past the day: the same words for the minutes this takes)
  const [soon, late] = [now + 30.5 * day + 1_800_000, now + 118.5 * day + 1_800_000];
  const withResets = (checkedAt: number) => overviewOf([], [profile("p", {
    email: "a@x.com",
    quota: {
      state: "ok", detail: null, checkedAt, windows: [{ label: "每周", usedPercent: 100, resetsAt: now + day }], resetCount: 2, resetExpiries: [soon, late],
      resets: [
        { id: "weekly", kind: "weekly", left: 1, usable: true, expiries: [soon] },
        { id: "model", kind: "model", model: "Fable", left: 1, usable: true, expiries: [late] },
      ],
    },
  })]);
  t.set(workspace(), { id: "ws", stations: [{ id: "a", name: "alpha", last_seen: null, version: null }] });
  t.set(link("ws/a"), { state: "online" });
  t.set(overview("ws/a"), withResets(now - 60_000));
  t.subscribe(1, { topic: "station", scope: "ws", station: "ws/a" });
  t.subscribe(2, { topic: "stationPart", scope: "ws", station: "ws/a", part: "profiles" });
  t.subscribe(3, { topic: "profile", scope: "ws", key: "sub:claude:a@x.com" });
  const said = async () => {
    await t.readAll([[page, 1], [part, 2], [list, 3]]);
    return [page.value.overview.profiles[0].quota, part.value[0].quota, list.value.profile.quota].map((q: J) => (q.resets as J[]).map((r) => `${r.title} ${r.leftText} ${r.text}`));
  };
  const rows = ["每周重置 剩 1 次 30 天 12 小时后到期", "Fable 重置 剩 1 次 118 天 12 小时后到期"];
  assert.deepEqual(await said(), [rows, rows, rows], "as it is first read");
  t.set(overview("ws/a"), withResets(now));
  assert.deepEqual(await said(), [rows, rows, rows], "its allowance read again");
  t.set(hostOf("ws/a"), hostInfo("a"));
  await t.host.time.pass(61_000);
  assert.deepEqual(await said(), [rows, rows, rows], "a minute on, its machine read");
});

test("a_stations_software_is_a_part_of_its_overview_as_its_page_says_it", async () => {
  // 关于's 本机 Station: this machine's station's version and whether a newer one is out, not its whole page.
  const t = setup({ all: true });
  const [page, part] = [ui(), ui()];
  t.subscribe(1, { topic: "station", scope: "ws", station: "ws/a" });
  t.subscribe(2, { topic: "stationPart", scope: "ws", station: "ws/a", part: "updates" });
  await allUp(t);
  const station = { id: "station", installed: true, version: "0.1.1", latest: "0.1.2", newer: true, updatable: true, state: "idle", channel: "stable" };
  t.set(overview("ws/a"), { ...busyOverview(20, false), updates: [station] });
  await t.readAll([[page, 1], [part, 2]]);
  assert.deepEqual(part.value, page.value.overview.updates);
  assert.deepEqual(part.value.map((u: J) => [u.id, u.name, u.shownText, u.latest, u.newer]), [["station", "Station", "0.1.1", "0.1.2", true]]);
});

test("a_new_chats_stations_are_their_rows_without_models_or_profiles", async () => {
  // Its stations were the whole list's items (50-95 ms a value on a phone, 2026-11-10).
  // (its page made by choose.ts, as a core plugs it in)
  const t = setup({ all: true, owners: ({ host, store, data }) => [new Choose({ store, data, now: () => host.nowMs(), agent: () => null })] });
  const u = ui();
  t.subscribe(1, { topic: "newChat", scope: "ws" });
  await allUp(t, ["a", "b"]);
  await t.read(u, 1);
  const v: J = u.value;
  assert.ok(v !== undefined, JSON.stringify(u.error));
  assert.deepEqual(v.stations.map((s: J) => s.station), ["ws/a", "ws/b"]);
  for (const s of [...v.stations, v.station]) {
    assert.equal(s.models, undefined, s.station);
    assert.equal(s.overview.profiles, undefined, s.station);
    // (its overview as the page reads it, NewChatOverview: the row's, OverviewRow, made as that once)
    assert.deepEqual(Object.keys(s.overview).sort(), ["counts", "drive"]);
  }
  // what it runs is still the station's own
  assert.equal(v.model?.model, "claude-opus-5-5");
  assert.equal(v.waiting, false);
});

test("profiles_say_the_logins_each_up_station_offers_for_a_profile", async () => {
  // The Profile place lists them with its profiles: it read them of every station's whole overview in the list.
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "profiles", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const login = (runtime: string, loggedIn: boolean) => ({ runtime, installed: true, loggedIn, email: loggedIn ? "me@x.com" : null, plan: loggedIn ? "pro" : null, text: runtime });
  t.set(link("ws/a"), { state: "online" });
  t.set(link("ws/b"), { state: "online" });
  t.set(link("ws/c"), { state: "offline" });
  t.set(overview("ws/a"), { ...overviewOf([], []), machineLogins: [login("codex", true), login("claude", false)] });
  t.set(overview("ws/b"), overviewOf([], []));
  t.set(overview("ws/c"), { ...overviewOf([], []), machineLogins: [login("codex", true)] });
  await t.read(u, 1);
  const v: J = u.value;
  assert.deepEqual(v.machineLogins.map((m: J) => [m.station, m.stationName, m.logins.map((l: J) => [l.runtime, l.offered])]), [["ws/a", "alpha", [["codex", true]]]]);
});

test("connects_say_the_slack_apps_waiting_and_whether_the_first_step_is_a_profile", async () => {
  const t = setup();
  const [all, mine] = [ui(), ui()];
  t.subscribe(1, { topic: "connects", scope: "ws" });
  t.subscribe(2, { topic: "connects", scope: "ws", mine: true });
  t.set(workspace(), stations(t.nowS()));
  for (const st of ["ws/a", "ws/b", "ws/c"]) t.set(link(st), { state: "online" });
  const app = (id: string) => ({ appId: id, name: id, teamId: "T1", team: null, created: 1, links: { settings: "s", install: "i", appToken: "a", oauth: "o" }, install: null, state: null, installed: false });
  t.set(overview("ws/a"), { ...overviewOf([], []), slackApps: [app("A1"), app("A2")] });
  t.set(overview("ws/b"), overviewOf([], []));
  await t.readAll([[all, 1], [mine, 2]]);
  // ws/c not read yet: not known to have none
  assert.equal(all.value.noProfile, false);
  t.set(overview("ws/c"), { ...overviewOf([], []), slackApps: [app("C1")] });
  await t.readAll([[all, 1], [mine, 2]]);
  for (const v of [all.value, mine.value]) {
    assert.deepEqual(v.slackApps.map((w: J) => [w.station, w.stationName, w.app.appId]), [["ws/a", "alpha", "A1"], ["ws/a", "alpha", "A2"], ["ws/c", "gamma", "C1"]]);
    assert.equal(v.noProfile, true);
  }
  t.set(overview("ws/b"), overviewOf([], [profile("p")]));
  await t.readAll([[all, 1], [mine, 2]]);
  assert.deepEqual([all.value.noProfile, mine.value.noProfile], [false, false]);
});

test("a_stopped_view_lets_its_topics_go", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const each = (st: string): Topic[] => [link(st), overview(st), hostOf(st), { topic: "way", station: st }];
  const watched = [workspace(), { topic: "workspaces" }, ...each("ws/a"), ...each("ws/b"), ...each("ws/c")];
  sameTopics(t.started(), watched);
  t.store.unsubscribe(1, 1);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  assert.deepEqual(t.stopped(), []);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  sameTopics(t.stopped(), watched);
  assert.deepEqual(t.store.liveTopics(), []);
});

test("stations_say_how_each_is_reached_and_its_figures_are_a_view_of_their_own", async () => {
  // The list follows each station's way (seldom changing), not its readings: those are `stationNet`, for where they are
  // drawn.
  const t = setup();
  const u = ui();
  const card = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  t.set({ topic: "way", station: "ws/a" }, { path: "relay", relay: "relay.test" });
  await t.read(u, 1);
  const a = () => (u.value as J[]).find((s) => s.station === "ws/a");
  assert.deepEqual(a().way, { path: "中继 relay.test", via: "relay" });
  assert.equal("net" in a(), false);
  assert.equal(t.started().some((x) => x.topic === "net"), false);
  t.subscribe(2, { topic: "stationNet", station: "ws/a" });
  await t.read(card, 2);
  assert.equal(card.value, null);
  assert.deepEqual(t.started(), [{ topic: "net", station: "ws/a" }]);
  const computed = t.router.computed;
  const messages = u.messages;
  t.set({ topic: "net", station: "ws/a" }, { path: "relay", relay: "relay.test", rttMs: 286, rxBytes: 0, txBytes: 0, samples: [] });
  await t.readAll([[u, 1], [card, 2]]);
  const shown: J = card.value;
  assert.deepEqual([shown.path, shown.via, shown.rtt], ["中继 relay.test", "relay", { text: "286 ms", level: "ok" }]);
  assert.equal(t.router.computed, computed + 1, "the card's view alone");
  assert.equal(u.messages, messages);
});

test("a_held_topic_a_view_watches_goes_out_to_a_page_subscribing_later", async () => {
  // The station list watches the workspace; a station's page subscribing to the workspace itself then (its role, for
  // the ⋯ menu) has it at once, not when it next changes.
  const t = setup();
  const list = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), { ...oneStation(), role: "owner" });
  await t.read(list, 1);
  assert.equal(list.value.length, 1);
  const page = ui();
  t.subscribe(2, workspace());
  await t.read(page, 2);
  assert.equal(page.value?.role, "owner");
});

test("stations_whole_shows_each_station_with_its_models", async () => {
  // (the core's own list, what a model's choice reads: as it is made, no shape between)
  const t = setup({ all: true });
  const u = ui();
  t.subscribe(1, { topic: "stationsWhole", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const quota = (windows: J[]) => ({ state: "ok", detail: null, checkedAt: 1, windows });
  const overviewA = overviewOf([], [
    profile("p1", { runtimes: ["codex"], models: ["o3", "gpt-5"], quota: quota([{ label: "5 小时", usedPercent: 40, resetsAt: 100 }, { label: "每周", usedPercent: 100, resetsAt: 5000 }]) }),
    profile("p2", { runtimes: ["claude"], models: [] }),
    profile("p3", { runtimes: ["claude"], models: ["sonnet"] }),
    profile("p4", { runtimes: ["claude"], models: ["opus", "sonnet"] }),
    profile("p5", { runtimes: ["claude", "codex"], models: ["deepseek-flash"] }),
    profile("p6", { runtimes: ["codex"], models: ["openai/gpt-5"], quota: quota([{ label: "每周", usedPercent: 100, resetsAt: 6000 }]) }),
  ]);
  t.set(overview("ws/a"), overviewA);
  t.set(hostOf("ws/a"), hostInfo("studio"));
  t.set(link("ws/a"), { state: "error", message: "没有权限" });
  t.set(link("ws/b"), { state: "offline" });
  await t.read(u, 1);
  const v = u.value;
  const seen = t.nowS();
  assert.ok(Math.abs(seen - v[0].lastSeen - 10) < 5);
  assert.equal(v[0].version, "0.4.0");
  assert.equal(v[0].online, true);
  assert.deepEqual(v[0].link, { state: "error", message: "没有权限", last: null });
  // Reached, if refused: not coming back.
  assert.equal(v[0].reconnecting, false);
  assert.deepEqual(v[0].overview.profiles.map((p: J) => p.id), ["p1", "p2", "p3", "p4", "p5", "p6"]);
  assert.equal(v[0].host.hostname, "studio");
  assert.deepEqual(v[0].runtimes, [{ runtime: "claude", models: ["deepseek-flash", "opus", "sonnet"] }, { runtime: "codex", models: ["deepseek-flash", "gpt-5", "o3", "openai/gpt-5"] }]);
  const models = v[0].models.map((m: J) => ({ model: m.model, runtimes: m.runtimes, spent: m.spent?.until ?? null }));
  assert.deepEqual(models, [
    { model: "opus", runtimes: ["claude"], spent: null },
    { model: "sonnet", runtimes: ["claude"], spent: null },
    { model: "deepseek-flash", runtimes: ["claude", "codex"], spent: null },
    { model: "gpt-5", runtimes: ["codex"], spent: 5000 },
    { model: "o3", runtimes: ["codex"], spent: 5000 },
  ]);
  const gpt = v[0].models[3];
  assert.equal(gpt.family, "GPT");
  assert.deepEqual([gpt.maker.id, gpt.efforts.codex[0], gpt.accounts.codex[0].id], ["openai", "minimal", "p1"]);
  assert.ok(gpt.spent.text.startsWith("额度已用完 · "));
  assert.deepEqual([gpt.name, gpt.ids], ["GPT-5", ["gpt-5", "openai/gpt-5"]]);
  assert.deepEqual(gpt.accounts.codex.map((a: J) => a.id), ["p1", "p6"]);
  assert.deepEqual(plain(v[1]), { station: "ws/b", id: "b", name: "beta", online: false, reconnecting: false, lastSeen: v[1].lastSeen, link: { state: "offline" }, runtimes: [], models: [], profileGroups: [], profileStates: {}, betaOffered: false, mine: false });
  assert.ok(v[1].summary.startsWith("离线 · "));
  assert.equal(v[2].lastSeen, null);
});

test("the_beta_switch_follows_the_accounts_beta_at_once", async () => {
  const t = setup({ all: true });
  const watch = t.store.watch.bind(t.store);
  t.store.watch = (topic) => watch(topic, () => {});
  const u = ui();
  t.subscribe(1, { topic: "station", scope: "ws", station: "ws/a" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  const o = overviewOf([], []);
  o.updates = [{ id: "station", name: "still.fail station", installed: true, version: "0.1.1", newer: false, updatable: true, state: "idle", channel: "stable" }];
  t.set(overview("ws/a"), o);
  await t.read(u, 1);
  assert.equal(u.value.betaOffered, false);
  t.data.put("me", "s1", { user: { beta: true } });
  await t.read(u, 1);
  assert.equal(u.value.betaOffered, true);
});

test("connects_lists_every_online_stations_connects", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "connects", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(u, 1);
  // (a row is made of its station's overview alone: not of its sessions or chats)
  const each = (st: string) => [link(st), overview(st)];
  sameTopics(t.started(), [workspace(), ...each("ws/a"), ...each("ws/b"), ...each("ws/c")]);
  t.set(link("ws/c"), { state: "offline" });
  const me = { id: "Me@x.com", email: "Me@x.com" };
  assert.deepEqual(u.value as J, { me, items: [], wait: { reading: true, text: "正在从 3 台 station 读取", failing: [], empty: false }, slackApps: [], noProfile: false });
  const c1 = { ...connect("c1", "one"), createdBy: { id: "me@x.com", name: "我" } };
  const c2 = connect("c2", "two");
  t.set(overview("ws/a"), overviewOf([c1, c2], []));
  t.fail(overview("ws/b"), new CoreError("offline", "连不上"));
  await t.read(u, 1);
  const v: J = u.value;
  assert.deepEqual(v.items.map((i: J) => [i.station, i.connect.id]), [["ws/a", "c1"], ["ws/a", "c2"]]);
  // what its row shows, and nothing of its page (its sessions, those it could deliver into, the ways it could change)
  assert.deepEqual(Object.keys(v.items[0]).sort(), ["connect", "station", "stationName"]);
  assert.deepEqual([v.wait.reading, v.wait.failing.map((f: J) => [f.station, f.message])], [false, [["ws/b", "连不上"]]]);
  assert.equal(v.items[0].connect.createdBy.shown.display, "你");
  assert.equal(v.items[0].connect.statusText, "未连接 Slack");
  assert.deepEqual([v.items[0].connect.placeText, v.items[0].connect.modeLabel], ["Slack", "每个 thread 一个会话"]);
  const mine = ui();
  t.subscribe(2, { topic: "connects", scope: "ws", mine: true });
  await t.read(mine, 2);
  assert.deepEqual(mine.value.items.map((i: J) => i.connect.id), ["c1"]);
});

test("a_connects_list_is_sent_nothing_as_its_sessions_or_its_stations_quota_change", async () => {
  // Its rows are made of each station's connects alone: a session's turn, a new one or an allowance read again made
  // every list of them anew, and each connect's every session went out with it (1.5 MB at a workspace's real size).
  const t = setup();
  const u = ui();
  t.subscribe(1, { topic: "connects", scope: "ws" });
  t.set(workspace(), oneStation());
  t.set(link("ws/st"), { state: "online" });
  const over = overviewOf([connect("c1", "one")], [profile("p1")]);
  t.set(overview("ws/st"), over);
  t.store.watch(sessions("ws/st"), () => {});
  t.set(sessions("ws/st"), [fullSession("k1")]);
  await t.read(u, 1);
  assert.deepEqual(u.value.items.map((i: J) => i.connect.id), ["c1"]);
  const [computed, messages] = [t.router.computed, u.messages];
  t.set(sessions("ws/st"), [fullSession("k1", { turns: 3, lastActiveAt: 9 }), fullSession("k2")]);
  t.set(overview("ws/st"), { ...over, profiles: [profile("p1", { quota: { state: "ok", detail: null, checkedAt: 2, windows: [] } })], counts: { sessions: 2, running: 1, warm: 0 } });
  await t.read(u, 1);
  assert.equal(t.router.computed, computed, "the list is not made again");
  assert.equal(u.messages, messages);
  t.set(overview("ws/st"), { ...over, connects: [{ ...connect("c1", "one"), name: "uno" }] });
  await t.read(u, 1);
  assert.deepEqual(u.value.items.map((i: J) => i.connect.name), ["uno"]);
});

test("a_connects_page_is_that_connect_and_its_choice_of_a_session_the_sessions_of_its_runtime", async () => {
  const t = setup();
  const [page, choice, none, offline] = [ui(), ui(), ui(), ui()];
  t.subscribe(1, { topic: "connect", scope: "ws", station: "ws/a", id: "c1" });
  t.subscribe(2, { topic: "connectCandidates", scope: "ws", station: "ws/a", id: "c1" });
  t.subscribe(3, { topic: "connect", scope: "ws", station: "ws/a", id: "c9" });
  t.subscribe(4, { topic: "connect", scope: "ws", station: "ws/c", id: "c1" });
  t.set(workspace(), stations(t.nowS()));
  await t.readAll([[page, 1], [choice, 2], [none, 3], [offline, 4]]);
  // (its own station's alone)
  sameTopics(t.started(), [workspace(), link("ws/a"), link("ws/b"), link("ws/c"), overview("ws/a"), sessions("ws/a"), threads("ws/a"), overview("ws/c"), sessions("ws/c"), threads("ws/c")]);
  // not read yet: none
  assert.deepEqual([page.value, choice.value, none.value], [undefined, undefined, undefined]);
  t.set(link("ws/c"), { state: "offline" });
  const c1 = { ...connect("c1", "one"), mode: "single-session", session: "k2" };
  const c2 = connect("c2", "two");
  t.set(overview("ws/a"), { ...overviewOf([c1, c2], []), connectRuntimeChange: true });
  t.set(sessions("ws/a"), [
    fullSession("k1", { lastActiveAt: 5, turns: 2, firstText: "第一个" }),
    fullSession("k2", { connect: "c2", scope: "all", lastActiveAt: 9, title: "合并的", boundTo: ["c1", "c2"], process: "running" }),
    fullSession("k3", { runtime: "codex", lastActiveAt: 7 }),
  ]);
  t.set(threads("ws/a"), [thread(4, ["k1"], t.host.nowMs())]);
  await t.readAll([[page, 1], [choice, 2], [none, 3], [offline, 4]]);
  const v: J = page.value;
  assert.deepEqual([v.station, v.stationName, v.connect.id, v.runtimeChanges, v.running], ["ws/a", "alpha", "c1", true, 1]);
  assert.equal("candidates" in v, false);
  assert.deepEqual(v.sessions.map((s: J) => [s.key, s.chat ?? null]), [["k3", null], ["k1", 4]]);
  assert.deepEqual([v.bound.key, v.bound.titleText], ["k2", "合并的"]);
  assert.deepEqual(v.changes.map((c: J) => c.mode), ["multi-session", "single-session", "single-session"]);
  // its runtime's, the latest first, each in words, the one it delivers into said so; nothing more of each
  const said = choice.value.candidates;
  assert.deepEqual(said.map((c: J) => [c.key, c.titleText, c.current]), [["k2", "合并的", true], ["k1", "第一个", false]]);
  assert.deepEqual(Object.keys(said[0]).sort(), ["current", "description", "key", "titleText"]);
  assert.ok(said[0].description.startsWith("单会话 · two · 0 轮 · "), said[0].description);
  assert.ok(said[0].description.endsWith(" · 也被 two 使用"), said[0].description);
  assert.deepEqual([none.value, offline.value], [null, null]);
});

test("times_in_words_go_out_fresh_each_minute", async () => {
  const t = setup();
  t.host.setUtcOffsetMin(480);
  t.store.setClock();
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  await t.read(u, 1);
  const clock = (ms: number) => ms > 1000 && ms <= 61_000 && ms !== EVICT_AFTER_MS;
  const count = () => t.host.time.sleeps.filter(clock).length;
  const before = count();
  assert.ok(before >= 1, JSON.stringify(t.host.time.sleeps));
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  assert.equal(count(), before);
});

const sessionOf = (st: string, key: string): Topic => ({ topic: "session", station: st, key });
const pageOf = (st: string, id: number): Topic => ({ topic: "thread", station: st, thread: id });
const entry = (n: number, text: string): J => ({ thread: 7, n, kind: "message", ts: `${n}.0`, authorKind: "person", author: "a@x.com", authorName: null, text, at: n });
const page = (first: number, texts: string[], kept: J): J => ({ first, last: first + texts.length - 1, entries: texts.map((x, i) => entry(first + i, x)), thread: kept });
const chatTopic = (station: string, th: number): Topic => ({ topic: "chat", station, thread: th, session: null });
const agentPage = (station: string, key: string): Topic => ({ topic: "chat", station, thread: null, session: key });
const hasTopic = (list: Topic[], topic: Topic) => list.some((x) => topicKey(x) === topicKey(topic));

for (const omitted of [false, true]) test(`a_new_chat_shows_when_made_with_${omitted ? "an_omitted" : "a_null"}_thread`, async () => {
  const t = setup();
  const watch = t.store.watch.bind(t.store);
  t.store.watch = (topic) => watch(topic, () => {});
  const u = ui();
  try {
    const key = t.views.local.pendingNew("ws/a", {}, "new:test");
    t.subscribe(1, omitted ? { topic: "chat", station: "ws/a", session: key } : agentPage("ws/a", key));
    await t.read(u, 1);
    assert.equal(u.value.pending, true);
    t.views.local.pendingMade(key, "k", 7);
    await t.read(u, 1);
    assert.deepEqual([u.value.pending, u.value.key], [false, "k"]);
  } finally { t.store.runner.shutdown(); }
});

test("hidden_letters_keep_the_loaded_entry_cursors_advancing", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], t.host.nowMs())]);
  for (const last of [50, 100, 150]) {
    const entries = Array.from({ length: last }, (_, i) => ({
      ...entry(i + 1, "来自 [other](https://still.fail/o/ws/a/other)：\n\n更新"),
      authorKind: "agent", author: "other",
    }));
    t.set(pageOf("ws/a", 7), { first: 1, last, entries, end: false, thread: null });
    await t.read(u, 1);
    assert.equal(u.value.messages.length, 0, "letters do not add visible messages");
    assert.deepEqual([u.value.firstEntry, u.value.lastEntry], [1, last]);
  }
});

test("an_items_page_is_its_agents_and_becomes_its_chat", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: null, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  let v = u.value;
  assert.ok(v, "the agent alone");
  assert.deepEqual([v.thread ?? null, v.messages, v.title], [null, [], "修构建"]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: 7, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  assert.ok(hasTopic(t.started(), pageOf("ws/a", 7)));
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), page(1, ["开始吧"], null));
  await t.read(u, 1);
  v = u.value;
  assert.equal(v.thread.id, 7);
  assert.equal(v.messages.length, 1);
});

test("a_failure_notice_is_offered_to_report_where_the_station_takes_bug_reports", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const ember = (n: number, text: string): J => ({ ...entry(n, text), authorKind: "ember", author: "ember" });
  t.set(pageOf("ws/a", 7), { first: 1, last: 3, entries: [entry(1, "开始吧"), ember(2, "⚠️ 本轮出错：workspace routing discovery timed out"), ember(3, "已停止当前任务")], thread: null });
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  const reportable = () => u.value.messages.map((m: J) => [m.seq, m.reportable ?? false]);
  // A station that takes none (another provider's, the beta channel, one from before): nothing offered.
  assert.deepEqual(reportable(), [[1, false], [2, false], [3, false]]);
  t.set(overview("ws/a"), { ...overviewOf([], []), feedback: true });
  await t.read(u, 1);
  assert.deepEqual(reportable(), [[1, false], [2, true], [3, false]]);
});

test("a_notice_comes_with_its_words_read_as_markdown_a_chat_it_opened_a_link_to_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  // (as the station says it opened one in a still.fail chat: sessions/opened.ts sayOpened)
  const link = "https://app.still.fail/o/ws/a/k2";
  const opened = `已创建对话：[共享调试：配对后连不上](${link})`;
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "开始吧"), { ...entry(2, opened), authorKind: "ember", author: "ember" }], thread: null });
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  const notice = u.value.messages[1].notice;
  assert.equal(notice.words, opened);
  assert.deepEqual(notice.md, markdown(opened));
  assert.ok(JSON.stringify(notice.md).includes(`"href":"${link}"`));
  // (the words drawn are the notice's: the message's own not read besides)
  assert.equal(u.value.messages[1].md, undefined);
});

test("a_message_says_the_chats_it_links_to_their_titles_and_which_are_archived", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("c-old", now), title: "旧的", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [row("c-live", now)]);
  const live = "https://app.still.fail/o/ws/a/c-live";
  const old = "https://app.still.fail/o/ws/a/c-old";
  // One linked bare, one archived in a reference, one no list has; a message with none says none.
  // One to a message of the chat is the chat's too.
  const atMessage = `${live}?message=2`;
  t.set(pageOf("ws/a", 7), page(1, [`看 ${live} 和 [那个](${old})，还有 https://app.still.fail/o/ws/a/c-none`, "没有链接", `第二条 ${atMessage}`], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  assert.deepEqual(u.value.messages.map((m: J) => m.chats), [[{ href: old, title: "旧的", archived: true, note: "已归档" }, { href: live, title: "c-live 的标题" }], undefined, [{ href: atMessage, title: "c-live 的标题" }]]);
});

test("a_chat_an_agent_opened_has_the_way_back_to_its_opener_over_its_messages", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(rows("ws/a"), [{ ...row("k", now), thread: 7, opener: { session: "p", title: "当时的名字" } }, { ...row("p", now - 1000), title: "发起的对话" }]);
  t.set(pageOf("ws/a", 7), page(1, ["开始"], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  assert.deepEqual(u.value.opener, { station: "ws/a", session: "p", title: "发起的对话", text: "由「发起的对话」创建" });
});

test("a_chat_whose_agent_opened_others_lists_them_each_where_it_stands", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("old", now), title: "归档的", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [
    { ...row("k", now), thread: 7, opened: [{ session: "c-need", title: "当时的名字" }, { session: "old" }, { session: "gone", title: "没了的" }] },
    { ...row("c-need", now), title: "安卓构建", agents: [{ ...session("a1"), lastTurn: { kind: "message", declared: "block", ending: "need_help", need: "选一台测试机", outcome: "completed", startedAt: 1, endedAt: 2 } }] },
  ]);
  t.set(pageOf("ws/a", 7), page(1, ["开始"], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.openedText, "创建了 3 个对话");
  assert.deepEqual(v.opened.map((o: J) => [o.session, o.title, o.stateLead ?? null, o.archived ?? false]), [
    ["c-need", "安卓构建", "need", false],
    ["old", "归档的", null, true],
    ["gone", "没了的", null, false],
  ]);
});

test("a_chat_that_links_others_reads_their_rows_alone_not_their_stations_lists", async () => {
  // A station's archive is thousands of rows: read whole to find a linked chat's title, it was most of what opening a
  // chat with a link in it took (0.65-0.83 s on a phone, 2026-10-31).
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set({ topic: "archivedRows", station: "ws/a" }, [{ ...row("c-old", now), title: "旧的", archived: { at: now, by: "auto" } }]);
  t.set(rows("ws/a"), [row("c-live", now)]);
  t.set(pageOf("ws/a", 7), page(1, ["看 https://app.still.fail/o/ws/a/c-live 和 https://app.still.fail/o/ws/a/c-old"], null));
  t.set(overview("ws/a"), overviewOf([], []));
  await t.read(u, 1);
  // (as the app opens again: nothing of the lists read, the chat made anew)
  t.data.release({ topic: "archivedRows", station: "ws/a" });
  t.data.release(rows("ws/a"));
  t.store.invalidate(chatTopic("ws/a", 7));
  await t.read(u, 1);
  assert.deepEqual(u.value.messages[0].chats.map((c: J) => [c.title, c.archived ?? false]), [["c-live 的标题", false], ["旧的", true]]);
  assert.equal(t.data.loaded({ topic: "archivedRows", station: "ws/a" }), false, "the archive not read");
  assert.equal(t.store.inUse({ topic: "archivedRows", station: "ws/a" }), false, "nor shown: its station not asked for it whole");
  assert.equal(t.data.loaded(rows("ws/a")), false, "nor the list");
});

test("a_card_answered_from_here_stays_answered_once_its_message_leaves_the_outbox", () => {
  const t = setup();
  const views = t.views;
  const id = views.outboxAdd("ws/st", 7, { text: "好" });
  assert.ok(views.local.answered("ws/st", 7, 4));
  views.outboxSent("ws/st", 7, id, 5);
  assert.equal(views.local.outboxGet("ws/st", 7, id), undefined);
  assert.ok(views.local.answered("ws/st", 7, 4));
  assert.ok(!views.local.answered("ws/st", 7, 6));
});

test("a_chat_renamed_or_pinned_here_shows_so_at_once_and_as_its_station_has_it_once_answered", async () => {
  const t = setup();
  const local = t.views.local;
  const list = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const now = t.host.nowMs();
  t.set(rows("ws/st"), [row("7", now - 1000), row("8", now - 2000)]);
  await t.read(list, 1);
  const item = (id: string) => list.value.days.flatMap((d: J) => d.items).find((i: J) => i.id === id);
  const renaming = local.changing("ws/st", 7, "s", { title: "新名字" }, null);
  const pinning = local.changing("ws/st", 8, "s", { pinned: now }, null);
  await t.read(list, 1);
  assert.equal(item("7").title, "新名字");
  assert.equal(item("8").pinned, true);
  local.changed(pinning, false, t.data.rowsRev("ws/st"));
  local.changed(renaming, true, t.data.rowsRev("ws/st"));
  await t.read(list, 1);
  assert.equal(item("7").title, "新名字");
  assert.notEqual(item("8").pinned, true);
  t.set(rows("ws/st"), [{ ...row("7", now - 1000), title: "站上的名字" }, row("8", now - 2000)]);
  await t.read(list, 1);
  assert.equal(item("7").title, "站上的名字");
});

test("an_agents_first_messages_show_at_once_and_go_on_into_its_chat_as_the_same_rows", async () => {
  const t = setup();
  const local = t.views.local;
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: null, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  const [first, ask] = local.firstQueue("ws/a", "k", { text: "修一下", attachments: [], quotes: [] });
  const [second, again] = local.firstQueue("ws/a", "k", { text: "还有", attachments: [], quotes: [] });
  assert.ok(ask && !again);
  await t.read(u, 1);
  assert.deepEqual(u.value.outbox.map((m: J) => [m.id, m.state]), [[first, "sending"], [second, "sending"]]);
  local.firstFailed("ws/a", "k", "连不上");
  await t.read(u, 1);
  assert.equal(u.value.outbox[0].state, "failed");
  assert.ok(local.firstTry("ws/a", "k"));
  const sends = local.firstMade("ws/a", "k", 7);
  assert.deepEqual(sends.map(([id]) => id), [first, second]);
  assert.ok(!local.firstWaits("ws/a", "k"));
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: 7, title: "修构建", agents: [] }]);
  await t.read(u, 1);
  t.set(threads("ws/a"), [thread(7, ["k"], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(1, ["开始吧"], null));
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.thread.id, 7);
  assert.deepEqual(v.outbox.map((m: J) => m.id), [first, second]);
});

test("an_old_notification_resolves_an_archived_chat_without_an_active_row", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  await t.read(u, 1);
  assert.ok(hasTopic(t.started(), threads("ws/a")));
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", archivedAt: 42 })]);
  t.set(rows("ws/a"), []);
  await t.read(u, 1);
  assert.equal(u.value === undefined, true, "must not show an empty agent while resolving the chat");
  const archived = { ...thread(7, ["k"], t.host.nowMs()), hiddenAt: 42 };
  t.set(threads("ws/a"), [archived]);
  await t.read(u, 1);
  assert.ok(hasTopic(t.started(), pageOf("ws/a", 7)));
  t.set(pageOf("ws/a", 7), page(1, ["原来的消息"], archived));
  await t.read(u, 1);
  const view = u.value;
  assert.equal(view.thread.id, 7);
  assert.equal(view.archived, true);
  assert.equal(view.messages.length, 1);
});

test("an_open_chat_tracks_archive_and_restore_without_losing_messages", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const chat = thread(7, ["k"], t.host.nowMs());
  t.set(pageOf("ws/a", 7), page(1, ["kept message"], structuredClone(chat)));
  await t.read(u, 1);
  assert.equal(u.value.archived, false);
  for (const hidden of [42, null]) {
    chat.hiddenAt = hidden;
    t.set(threads("ws/a"), [structuredClone(chat)]);
    await t.read(u, 1);
    assert.equal(u.value.archived, hidden !== null);
    assert.equal(u.value.messages[0].text, "kept message");
  }
  chat.archivedAt = 42;
  t.set(threads("ws/a"), [chat]);
  await t.read(u, 1);
  assert.equal(u.value.archived, false);
});

test("a_chats_decisions_show_their_options_and_where_they_stand", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const asked = { ...entry(2, "先 A 还是 B？"), authorKind: "agent", author: "k", declared: "block", ending: "need_decision", options: [{ label: "A", recommended: true }, { label: "B" }] };
  const picked = { ...entry(3, "B"), quotes: [{ author: "agent", text: "先 A 还是 B？", comment: "", ts: "2.0", role: "agent" }] };
  const again = { ...entry(4, "那 C 呢？"), authorKind: "agent", author: "k", options: [{ label: "C" }] };
  t.set(pageOf("ws/a", 7), { first: 1, last: 4, entries: [entry(1, "做吧"), asked, picked, again], thread: null });
  const chatRow = { ...row("k", now), thread: 7, decision: { seq: 4, options: [{ label: "C" }], message: { seq: 4, text: "那 C 呢？" }, before: [] } };
  t.set(rows("ws/a"), [chatRow]);
  await t.read(u, 1);
  const v = u.value;
  const m = v.messages;
  assert.deepEqual(m[1].options, [{ label: "B" }, { label: "A", recommended: true }]);
  assert.equal(m[1].ending, "need_decision");
  assert.deepEqual([m[1].decision.resolved, m[1].decision.chosen], [true, "B"]);
  assert.deepEqual(m[3].decision, { resolved: false });
  assert.deepEqual([m[1].card.type, m[3].card], ["options", { type: "options", options: [{ label: "C" }], assigneeText: "尚未指定决策人" }]);
  assert.equal(m[0].decision, undefined);
  assert.equal(v.decision.text, "待处理 · 那 C 呢？");
  assert.equal(v.archivable, undefined);
  // The card is in the chat: its line is not said at the end of the messages.
  assert.equal(v.stateText, undefined);
  // What waits undecided: the page leads to it, and its post says it can be let go there; no other post does.
  assert.deepEqual(v.asks, [{ seq: 4, card: true, mine: false, text: "那 C 呢？" }]);
  assert.deepEqual(m.map((x: J) => x.asked ?? false), [false, false, false, true]);
  // The last post, nothing after it: no room kept for the bell at the end.
  assert.equal(v.askClear, undefined);
  // Its agent still in the turn that asked ("k" saying this as it goes on): the card is answerable all the same.
  t.set({ topic: "session", station: "ws/a", key: "k" }, { session: fullSession("k", { connect: "ember" }), turns: [{ ...turn("t1"), endedAt: null }], jobs: [], threads: [] });
  const busy = t.views.compute(chatTopic("ws/a", 7)) as J;
  assert.deepEqual(busy.ok.messages[3].decision, { resolved: false });
});

test("an_agents_need_without_a_card_is_let_go_where_the_chats_end_says_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const asks = { ...entry(2, "你在手机上试一下新的列表"), authorKind: "agent", author: "k", ending: "need_help" };
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "做吧"), asks], thread: null });
  const agent = { ...session("k"), lastTurn: { id: "t", kind: "input", startedAt: 1, endedAt: 2, outcome: "completed", declared: "block", ending: "need_help", need: "在手机上试新列表" } };
  const chatRow = { ...row("k", now), thread: 7, agents: [agent], need: { seq: 2, message: { seq: 2, text: "你在手机上试一下新的列表" }, before: [] } };
  t.set(rows("ws/a"), [chatRow]);
  await t.read(u, 1);
  const v = u.value;
  // The reminder at the end of the messages says what it needs, and 忽略 goes with it, not under the post that asks.
  assert.deepEqual([v.stateLead, v.stateRest, v.stateAsk], ["need", "在手机上试新列表", 2]);
  assert.deepEqual(v.asks, [{ seq: 2, card: false, mine: false, text: "在手机上试新列表" }]);
  assert.deepEqual(v.messages.map((x: J) => x.asked ?? false), [false, false]);
  // It is the end itself, no bell over it there: the end keeps no room for one.
  assert.equal(v.askClear, undefined);
});

test("an_agents_need_let_go_stays_at_the_chats_end_said_as_let_go", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const asks = { ...entry(2, "你在手机上试一下新的列表"), authorKind: "agent", author: "k", ending: "need_help" };
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "做吧"), asks], thread: null });
  const agent = { ...session("k"), lastTurn: { id: "t", kind: "input", startedAt: 1, endedAt: 2, outcome: "completed", declared: "block", ending: "need_help", need: "在手机上试新列表" } };
  const chatRow = { ...row("k", now), thread: 7, agents: [agent], need: { seq: 2, message: { seq: 2, text: "你在手机上试一下新的列表" }, before: [], dismissed: true } };
  t.set(rows("ws/a"), [chatRow]);
  await t.read(u, 1);
  const v = u.value;
  // What it needed stays where the chat ends, said as let go; nothing more to let go, nothing asked.
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest, v.stateAsk], ["已忽略：在手机上试新列表", "dismissed", "在手机上试新列表", undefined]);
  assert.deepEqual(v.asks, []);
});

test("a_chat_agent_shares_its_unchanged_frozen_session_details", () => {
  const t = setup();
  const topic = sessionOf("ws/a", "k");
  t.set(topic, { session: fullSession("k"), threads: [thread(7, ["k"], 1)], turns: [turn("t1")], jobs: [{ id: "j1" }] });
  const held = t.data.shared(topic) as J;
  const first = t.views.agent("ws/a", "k");
  for (const key of ["turns", "threads", "jobs"]) {
    assert.ok(Object.isFrozen(held[key]));
    assert.strictEqual(first[key], held[key], `${key} is shared rather than copied for every chat view`);
  }
  t.set(topic, { session: fullSession("k"), threads: [thread(7, ["k"], 1)], turns: [turn("t2")], jobs: [{ id: "j2" }] });
  const next = t.views.agent("ws/a", "k");
  assert.equal(next.turns[0].id, "t2");
  assert.equal(next.jobs[0].id, "j2");
  assert.equal(first.turns[0].id, "t1", "a later update does not change a shared earlier value");
});

test("compact_chat_jobs_reuses_the_chat_read_by_the_page", async () => {
  const t = setup();
  const topic = chatTopic("ws/a", 7);
  t.subscribe(1, { ...topic, compact: true });
  t.subscribe(2, { topic: "chatJobs", station: "ws/a", thread: 7, session: null, compact: true });
  await t.host.time.pass(100);
  assert.equal(hasTopic(t.store.liveTopics(), topic), false, "the jobs view does not start a second full chat");
  assert.equal(hasTopic(t.store.liveTopics(), { ...topic, compact: true }), true);
});

test("a_compact_chat_keeps_the_page_and_its_jobs_available_separately", async () => {
  const t = setup();
  const full = ui();
  const compact = ui();
  const jobs = ui();
  const summary = ui();
  const topic = chatTopic("ws/a", 7);
  t.subscribe(1, topic);
  t.subscribe(2, { ...topic, compact: true });
  t.subscribe(3, { topic: "chatJobs", station: "ws/a", thread: 7, session: null, compact: true });
  t.subscribe(4, { topic: "chatJobs", station: "ws/a", thread: 7, session: null, compact: true, summary: true });
  await t.readAll([[full, 1], [compact, 2], [jobs, 3], [summary, 4]]);
  const chat = thread(7, ["k"], t.host.nowMs());
  t.set(threads("ws/a"), [chat]);
  t.set(pageOf("ws/a", 7), page(1, ["hello"], chat));
  t.set(rows("ws/a"), [{ ...row("k", t.host.nowMs()), thread: 7 }]);
  const job = { id: "j1", session: "k", name: "job", state: "running", port: null, exitCode: null, startedAt: 1, endedAt: null, command: "", restarts: 0, notices: [] };
  const detail = { session: fullSession("k"), threads: [chat], turns: [turn("t1")], jobs: [job] };
  t.set(sessionOf("ws/a", "k"), detail);
  await t.readAll([[full, 1], [compact, 2], [jobs, 3], [summary, 4]]);
  assert.equal(full.value.agents[0].jobs[0].id, "j1");
  // (its turns and threads are the core's own: neither page is sent them)
  assert.deepEqual([full.value.agents[0].turns, full.value.agents[0].threads], [undefined, undefined]);
  assert.equal(t.views.agent("ws/a", "k").turns[0].id, "t1");
  assert.deepEqual(compact.value.messages, full.value.messages);
  assert.equal(compact.value.agents[0].hasJobs, true);
  assert.deepEqual([compact.value.agents[0].turns, compact.value.agents[0].threads, compact.value.agents[0].jobs], [undefined, undefined, []]);
  assert.equal(jobs.value.jobs[0].id, "j1");
  assert.equal(summary.value.hasJobs, true);
  assert.deepEqual(summary.value.jobs, []);
  t.set(sessionOf("ws/a", "k"), { ...detail, jobs: [] });
  await t.readAll([[full, 1], [compact, 2], [jobs, 3], [summary, 4]]);
  assert.equal(compact.value.agents[0].hasJobs, false);
  assert.deepEqual(jobs.value.jobs, []);
  assert.equal(summary.value.hasJobs, false);
});

test("only the overload notice belonging to a waiting retry offers its cancellation", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const chat = thread(7, ["k", "j"], t.host.nowMs());
  t.set(threads("ws/a"), [chat]);
  const entries = [1, 2].map((n) => ({
    ...entry(n, "⚠️ 模型满载，自动重试，与额度无关"), authorKind: "ember", author: "ember",
  }));
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries, end: false, thread: chat });
  const waiting = {
    kind: "resume", outcome: "failed", declared: "waiting", detail: "overloaded: at capacity",
    about: { thread: 7, seq: 2, ts: "2.0" }, startedAt: 10, endedAt: 11,
  };
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { lastTurn: waiting }), threads: [chat], turns: [] });
  t.set(sessionOf("ws/a", "j"), { session: fullSession("j"), threads: [chat], turns: [] });
  await t.read(u, 1);
  assert.equal(u.value.messages[0].notice.retrySession, undefined);
  assert.equal(u.value.messages[1].notice.retrySession, "k");
  // A new turn, or an unrelated wait, cannot be cancelled through that old notice.
  for (const lastTurn of [
    { ...waiting, outcome: "aborted", declared: null },
    { ...waiting, outcome: "completed", detail: null },
    { ...waiting, about: { ...waiting.about, thread: 8 } },
  ]) {
    t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { lastTurn }), threads: [chat], turns: [] });
    await t.read(u, 1);
    assert.equal(u.value.messages[1].notice.retrySession, undefined);
  }
});

test("only the notice of a failed turn still where its agent stands offers 重试, for a failure a retry can mend", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const chat = thread(7, ["k"], t.host.nowMs());
  t.set(threads("ws/a"), [chat]);
  const entries = [1, 2].map((n) => ({
    ...entry(n, "⚠️ 与模型服务的连接中断，回复即可重试"), authorKind: "ember", author: "ember",
  }));
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries, end: false, thread: chat });
  const failed = {
    kind: "input", outcome: "failed", declared: null, detail: "network: fetch failed",
    about: { thread: 7, seq: 2, ts: "2.0" }, startedAt: 10, endedAt: 11,
  };
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { lastTurn: failed }), threads: [chat], turns: [] });
  await t.read(u, 1);
  assert.equal(u.value.messages[0].notice.againSession, undefined);
  assert.equal(u.value.messages[1].notice.againSession, "k");
  assert.equal(u.value.messages[1].notice.retrySession, undefined);
  // Gone once it runs, a message waits for it, it ended otherwise, or the failure is one a retry would meet again.
  for (const [session, lastTurn] of [
    [{ process: "running" }, failed],
    [{ pending: 1 }, failed],
    [{}, { ...failed, outcome: "completed", detail: null, declared: "final" }],
    [{}, { ...failed, outcome: "aborted", detail: null }],
    [{}, { ...failed, detail: "auth: signed out" }],
    [{}, { ...failed, about: { ...failed.about, thread: 8 } }],
  ] as const) {
    t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { ...session, lastTurn }), threads: [chat], turns: [] });
    await t.read(u, 1);
    assert.equal(u.value.messages[1].notice.againSession, undefined, JSON.stringify([session, lastTurn]));
  }
  // A turn the station stopped asking for a state (回复即可继续) offers it too, while it stands there.
  const givenUp = { kind: "nudge", outcome: "completed", declared: null, detail: null, about: failed.about, startedAt: 10, endedAt: 11 };
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { lastTurn: givenUp }), threads: [chat], turns: [] });
  await t.read(u, 1);
  assert.equal(u.value.messages[1].notice.againSession, "k");
  assert.equal(u.value.messages[0].notice.againSession, undefined);
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { pending: 1, lastTurn: givenUp }), threads: [chat], turns: [] });
  await t.read(u, 1);
  assert.equal(u.value.messages[1].notice.againSession, undefined);
});

test("chat_is_a_thread_its_messages_and_its_agents", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  await t.read(u, 1);
  // The viewer's workspaces too: its sharing names the others (views/xshare.ts); its station's screens, its bar's way to them.
  sameTopics(t.started(), [threads("ws/a"), sessions("ws/a"), pageOf("ws/a", 7), rows("ws/a"), overview("ws/a"), link("ws/a"), workspace(), prefs(), { topic: "workspaces" }, { topic: "screens", station: "ws/a" }]);
  assert.equal(u.value === undefined, true);
  const now = t.host.nowMs();
  const chat = { ...thread(7, ["k", "j"], now), title: "排查", people: [{ id: "local", name: "本机管理页", email: null, via: "local" }] };
  const kept = { ...structuredClone(chat), title: "排查（上次）" };
  t.set(pageOf("ws/a", 7), page(39, ["第 39 条", "第 40 条"], kept));
  await t.read(u, 1);
  let v = u.value;
  assert.deepEqual([v.title, v.messages.length, v.more], ["排查（上次）", 2, true]);
  sameTopics(t.started(), [sessionOf("ws/a", "k"), sessionOf("ws/a", "j")]);
  t.set(threads("ws/a"), [thread(3, ["x"], now), structuredClone(chat)]);
  await t.read(u, 1);
  assert.equal(u.value.title, "排查");
  const texts = Array.from({ length: 30 }, (_, i) => `第 ${i + 11} 条`);
  t.set(pageOf("ws/a", 7), page(11, texts, null));
  await t.read(u, 1);
  assert.deepEqual(u.value.agents, []);
  t.set(sessions("ws/a"), [fullSession("j", { connect: "ember" })]);
  await t.read(u, 1);
  let agents = u.value.agents;
  assert.deepEqual([agents.length, agents[0].session.key, agents[0].status], [1, "j", "idle"]);
  assert.ok(agents[0].connect === undefined && agents[0].profile === undefined);
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { profile: "p2" }), threads: [structuredClone(chat)], turns: [turn("t1")] });
  t.fail(sessionOf("ws/a", "j"), new CoreError("http_404", "没有这个会话"));
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
  assert.equal(v.title, "排查");
  // (its thread as its page reads it: who started it and when, when it was last written in, how many wait; the rest the
  // core's own)
  assert.deepEqual(plain(v.thread), { id: 7, surface: "ember", unread: 0, lastMessage: {} });
  assert.deepEqual(plain(v.people), plain(chat.people));
  assert.equal(v.people[0].shown.name, "本机管理页");
  assert.deepEqual(v.link, { state: "connecting" });
  assert.deepEqual([v.messages.length, v.more], [30, true]);
  assert.equal(v.agents.length, 1);
  assert.equal(v.agents[0].session.key, "k");
  // (its turns and threads the core's own: the page is sent neither)
  assert.deepEqual([v.agents[0].turns, v.agents[0].threads], [undefined, undefined]);
  assert.equal(t.views.agent("ws/a", "k").turns[0].id, "t1");
  assert.deepEqual(plain(t.views.agent("ws/a", "k").threads), plain([chat]));
  assert.deepEqual([v.agents[0].connect, v.agents[0].profile], [undefined, undefined]);
  t.set(overview("ws/a"), overviewOf([connect("c1", "Slack")], [profile("p1"), profile("p2", { name: "主力" })]));
  t.set(link("ws/a"), { state: "online" });
  await t.read(u, 1);
  v = u.value;
  // (its connect and its profile as its page names them; the rest of each the core's own)
  assert.deepEqual(v.agents[0].connect, { name: "Slack" });
  assert.deepEqual([v.agents[0].profile.id, v.agents[0].profile.name], [undefined, "主力"]);
  assert.deepEqual([t.views.agent("ws/a", "k").connect.id, t.views.agent("ws/a", "k").profile.id], ["c1", "p2"]);
  assert.deepEqual(v.link, { state: "online" });
  // A new message goes out as an append.
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(41, "新的")], last: 41 }));
  await t.host.time.pass(100);
  const sent = t.host.takeEmitted();
  assert.equal(sent.length, 1);
  const delta = (sent[0][1] as J).delta;
  assert.ok(delta, JSON.stringify(sent[0]));
  const appended: J[] = merge([entry(41, "新的")]).map((m) => ({ ...m }));
  appended[0].mine = false;
  appended[0].system = false;
  appended[0].words = [{ text: "新的" }];
  assert.deepEqual(plain(delta), plain([{ path: ["lastEntry"], set: 41 }, { path: ["messages"], append: appended }]));
  u.value = applyOps(u.value, delta);
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, { n: 42, kind: "edit", target: 41, text: "新的（改）", attachments: [], quotes: [], at: 42 }], last: 42 }));
  await t.read(u, 1);
  v = u.value;
  assert.equal(v.lastEntry, 42, "an edit advances the entry cursor without adding a message");
  // (the page is sent its words as they are now; when they were edited is the core's own)
  assert.deepEqual(v.messages.slice(-2).reverse().map((m: J) => [m.text, m.editedAt ?? null]), [["新的（改）", null], ["第 40 条", null]]);
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...Array.from({ length: 10 }, (_, i) => entry(i + 1, "旧的")), ...(p as J).entries], first: 1 }));
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual([v.messages[0].seq, v.messages.length, v.more], [1, 41, false]);
  const seven = (t.data.thread("ws/a", 7) as J);
  t.data.putThread("ws/a", { ...seven, sessions: [...seven.sessions, member(7, "n", "ember")] });
  await t.read(u, 1);
  sameTopics(t.started(), [sessionOf("ws/a", "n")]);
  t.set(sessionOf("ws/a", "n"), { session: fullSession("n", { connect: "ember" }), threads: [], turns: [] });
  await t.read(u, 1);
  agents = u.value.agents;
  assert.deepEqual(agents.map((a: J) => a.session.key), ["k", "n"]);
  // Not in the threads read again: still the chat held (one made since the list was asked is not in it either); gone
  // only as its station says.
  t.set(threads("ws/a"), [thread(3, ["k"], now)]);
  await t.read(u, 1);
  assert.equal(u.error?.status, undefined, "not said to be gone");
  assert.deepEqual(u.value.agents.map((a: J) => a.session.key), ["k", "n"]);
  t.fail(pageOf("ws/a", 7), new CoreError("http_404", "对话不存在", 404));
  await t.read(u, 1);
  assert.equal(u.error.status, 404);
});

test("a_slack_chat_is_its_thread_like_any_other", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/st", 3));
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const slack = { ...thread(3, ["k"], t.host.nowMs()), surface: "slack:T1", channel: "C1", channelName: "ops", firstText: "<@U0BOT> 部署挂了", sessions: [member(3, "k", "c1")] };
  t.set(threads("ws/st"), [slack]);
  t.set(pageOf("ws/st", 3), page(1, ["<@U0BOT> 部署挂了", "在看"], null));
  await t.read(u, 1);
  t.set(sessionOf("ws/st", "k"), { session: fullSession("k"), threads: [], turns: [] });
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.title, "部署挂了");
  assert.equal(v.thread.surface, "slack:T1");
  assert.equal(v.messages.length, 2);
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
});

test("an_agent_without_a_chat_is_its_page_with_no_messages", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  await t.read(u, 1);
  sameTopics(t.started(), [sessionOf("ws/a", "k"), { topic: "live", station: "ws/a", key: "k" }, rows("ws/a"), sessions("ws/a"), threads("ws/a"), overview("ws/a"), link("ws/a"), workspace(), prefs(), { topic: "screens", station: "ws/a" }]);
  t.set(sessionOf("ws/a", "k"), { session: fullSession("k"), threads: [slackThread(3)], turns: [turn("t1")] });
  await t.read(u, 1);
  assert.equal(u.value === undefined, true, "its title is the station's: it waits for the items");
  const item = { ...row("k", t.host.nowMs()), title: "部署挂了", origin: { teamName: "AFK", channel: "C1", channelName: "ops", threadTs: "1.2" } };
  t.set(rows("ws/a"), [row("7", t.host.nowMs()), item]);
  t.set(overview("ws/a"), overviewOf([{ ...connect("c1", "Slack"), connection: { state: "connected", workspace: { team: "AFK", teamId: "T1", url: "https://afk.slack.com/", botUserId: "U0BOT", botName: "bot" } } }], []));
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.thread ?? null, v.title, v.messages, v.outbox, v.more], [null, "部署挂了", [], [], false]);
  const a = v.agents[0];
  assert.deepEqual([v.agents.length, a.session.key, a.connect.name, a.status], [1, "k", "Slack", "idle"]);
  // (its turns and threads the core's own: the page is sent neither)
  assert.deepEqual([a.turns, a.threads], [undefined, undefined]);
  assert.deepEqual([t.views.agent("ws/a", "k").turns[0].id, t.views.agent("ws/a", "k").threads[0].id], ["t1", 3]);
  assert.deepEqual(v.me, { id: "Me@x.com", email: "Me@x.com" });
  // where its Slack thread is, and the way there, as a chat's info says them
  assert.deepEqual([v.place, v.slackUrl, v.feishuUrl], ["#ops", "https://afk.slack.com/archives/C1/p12", undefined]);
  assert.equal(v.slackApp, "slack://channel?team=T1&id=C1&message=1.2");
  // (whether it has a chat is the core's own, read by its side panel's tabs: the page is sent those, `tabs.auto`)
  const own = () => t.store.get(agentPage("ws/a", "k")) as J;
  assert.equal(own().noChat, undefined, "its Slack thread is its chat: the page does not open its history by itself");
  assert.equal(v.noChat, undefined);
  for (const archived of [42, null]) {
    t.set(sessionOf("ws/a", "k"), { session: fullSession("k", { archivedAt: archived }), threads: [], turns: [] });
    await t.read(u, 1);
    assert.equal(u.value.archived, archived !== null);
    assert.equal(own().noChat, archived === null ? true : undefined);
    assert.equal(u.value.noChat, undefined);
  }
  t.fail(sessionOf("ws/a", "k"), new CoreError("http_404", "会话已删除", 404));
  await t.read(u, 1);
  assert.equal(u.error.status, 404);
});

test("a_sent_message_shows_until_the_chat_has_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  assert.deepEqual(u.value.outbox, []);
  const views = t.views;
  const id = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  await t.read(u, 1);
  let out = u.value.outbox;
  assert.deepEqual([out[0].id, out[0].text, out[0].state], [id, "你好", "sending"]);
  views.local.outboxState("ws/a", 7, id, "无法连接 station");
  await t.read(u, 1);
  out = u.value.outbox;
  assert.deepEqual([out[0].state, out[0].error], ["failed", "无法连接 station"]);
  views.local.outboxState("ws/a", 7, id, null);
  views.outboxSent("ws/a", 7, id, 6);
  await t.read(u, 1);
  // The station took it: sent, kept until its entry comes.
  assert.deepEqual([u.value.outbox[0].seq, u.value.outbox[0].state], [6, "sent"]);
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(6, "你好")], last: 6 }));
  await t.host.time.pass(100);
  const sent = t.host.takeEmitted();
  assert.equal(sent.length, 1);
  const ops = (sent[0][1] as J).delta as J[];
  assert.ok(ops, JSON.stringify(sent[0]));
  assert.ok(ops.some((op) => JSON.stringify(op.path) === '["messages"]'), JSON.stringify(ops));
  assert.ok(ops.some((op) => JSON.stringify(op.path) === '["outbox"]' && JSON.stringify(op.set) === "[]"), JSON.stringify(ops));
  const other = views.outboxAdd("ws/b", 1, { text: "x" });
  views.outboxSent("ws/b", 1, other, 1);
  assert.equal(views.local.outboxGet("ws/b", 1, other), undefined);
});

// An image sent before it was up showed as a file card that turned into its picture once up (mbui, 2026-10-26): it is
// among the message's files from the first, in its shape, named by its upload; any other file going up stays a card.
test("an_image_sent_while_going_up_is_among_its_messages_files_at_once", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const up = { name: "a.txt", path: "/w/uploads/a.txt", size: 2 };
  const id = t.views.outboxAdd("ws/a", 7, { text: "看看", attachments: [up], quotes: [], uploads: [
    { id: "u1", name: "shot.PNG", size: 300, width: 1200, height: 800, sent: 100 },
    { id: "u2", name: "notes.pdf", size: 50, sent: 10 },
  ] });
  await t.read(u, 1);
  let [o] = u.value.outbox;
  assert.deepEqual(o.attachments, [up, { name: "shot.PNG", path: "upload:u1", size: 300, width: 1200, height: 800, upload: "u1" }]);
  assert.deepEqual(o.uploads.map((f: J) => [f.id, f.sent]), [["u2", 10]]);
  assert.deepEqual([o.waits, o.progress], ["正在上传 31%", 110 / 350]);
  // Up: the station's file in its place, still drawn from here (its upload); nothing left going up.
  t.views.local.outboxUploaded("ws/a", 7, id, [{ name: "shot.PNG", path: "/w/uploads/shot.png", size: 300, width: 1200, height: 800 }, { name: "notes.pdf", path: "/w/uploads/notes.pdf", size: 50 }]);
  await t.read(u, 1);
  [o] = u.value.outbox;
  assert.deepEqual(o.attachments.map((f: J) => [f.path, f.upload]), [["/w/uploads/a.txt", undefined], ["/w/uploads/shot.png", "u1"], ["/w/uploads/notes.pdf", "u2"]]);
  assert.deepEqual([o.uploads, o.waits], [undefined, undefined]);
  // Failed, it says so, not that it is going up.
  const failed = t.views.outboxAdd("ws/a", 7, { text: "再看", attachments: [], quotes: [], uploads: [{ id: "u3", name: "b.jpg", size: 9 }] });
  t.views.local.outboxState("ws/a", 7, failed, "连不上");
  await t.read(u, 1);
  const f = u.value.outbox.find((m: J) => m.id === failed);
  assert.deepEqual([f.attachments.map((a: J) => a.path), f.uploads, f.waits], [["upload:u3"], undefined, undefined]);
});

// A video sent with a new chat's first message showed as a file card: a new chat's files go up
// only as its message goes, so its video was still going up when its row came. Drawn as its message draws it once up:
// in its place and shape, its still the one picked here.
test("a_video_sent_while_going_up_is_among_its_messages_files_at_once", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  t.views.outboxAdd("ws/a", 7, { text: "", attachments: [], quotes: [], uploads: [{ id: "v1", name: "clip.MP4", size: 900, width: 1080, height: 1920, sent: 0 }] });
  await t.read(u, 1);
  const [o] = u.value.outbox;
  assert.deepEqual([o.attachments, o.uploads], [[{ name: "clip.MP4", path: "upload:v1", size: 900, width: 1080, height: 1920, upload: "v1" }], undefined]);
});

// A message going up said only 正在上传, however long it took (mbui, 2026-10-26): under it, how far all its files are
// together, as each says how much of it the station has; until every one has said (a station's file copied across says
// nothing until it is there), only that they go up.
test("a_message_going_up_says_how_far_its_files_are_together", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const id = t.views.outboxAdd("ws/a", 7, { text: "看看", attachments: [], quotes: [], uploads: [
    { id: "u1", name: "shot.png", size: 300, sent: 0 },
    { id: "u2", name: "notes.pdf", size: 100, sent: 50 },
  ] });
  await t.read(u, 1);
  const shown = () => { const o = u.value.outbox.find((m: J) => m.id === id); return [o.waits, o.progress]; };
  assert.deepEqual(shown(), ["正在上传 12%", 50 / 400]);
  t.views.local.uploadChanged("u1", { sent: 300 });
  await t.read(u, 1);
  assert.deepEqual(shown(), ["正在上传 87%", 350 / 400]);
  // Every byte gone, the station not yet saying it has them: waiting for it, not 100% (a picture's answer came 9 s
  // after its bytes and it read as stuck, 2026-11-09).
  t.views.local.uploadChanged("u2", { sent: 100 });
  await t.read(u, 1);
  assert.deepEqual(shown(), ["等待 station 确认收到", 1]);
  const copied = t.views.outboxAdd("ws/a", 7, { text: "再看", attachments: [], quotes: [], uploads: [
    { id: "u3", name: "a.png", size: 10, sent: 5 },
    { id: "u4", name: "b.zip", size: 10 },
  ] });
  await t.read(u, 1);
  const o = u.value.outbox.find((m: J) => m.id === copied);
  assert.deepEqual([o.waits, o.progress], ["正在上传", undefined]);
});

// The UIs keep an outgoing message's id past the core that gave it (a restarted core, the page still up): the Android
// chat's list crashed on two rows keyed o:out-1 when a new core counted from 1 again (2026-10).
test("a_message_sent_after_the_core_restarts_is_named_apart_from_one_sent_before", () => {
  const before = setup().views.outboxAdd("ws/a", 7, { text: "早" });
  const after = setup().views.outboxAdd("ws/a", 7, { text: "早" });
  assert.notEqual(before, after);
});

test("a_chat_asked_for_here_shows_at_once_and_becomes_its_stations_under_the_same_key", async () => {
  const t = setup();
  const local = t.views.local;
  const key = local.pendingNew("ws/st", { runtime: "claude" });
  const [screen, list] = [ui(), ui()];
  t.subscribe(1, agentPage("ws/st", key));
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  t.set(rows("ws/st"), [row("7", t.host.nowMs() - 1000)]);
  const both = () => t.readAll([[screen, 1], [list, 2]]);
  await both();
  let v = screen.value;
  assert.deepEqual([v.pending, v.key, v.outbox, v.title], [true, undefined, [], "新对话"]);
  assert.equal(list.value.days.length, 0);
  const first = local.pendingQueue(key, { text: "修一下登录\n细节…", attachments: [], quotes: [] })!;
  await both();
  v = screen.value;
  // named by no one yet: a new chat, its page and its row, not the words sent (as its station calls it)
  assert.deepEqual([v.title, v.outbox[0].id, v.outbox[0].state], ["新对话", first, "sending"]);
  let items = list.value.days[0].items;
  assert.deepEqual([items[0].id, items[0].pending, items[0].title], [key, true, "新对话"]);
  local.pendingFailed(key, "no claude profile configured");
  await both();
  const out = screen.value.outbox;
  assert.deepEqual([out[0].state, out[0].error], ["failed", "no claude profile configured"]);
  assert.equal(local.pendingTry(key)?.[0], "ws/st");
  await both();
  assert.equal(screen.value.outbox[0].state, "sending");
  const sends = local.pendingMade(key, "chat:c-1", 9);
  assert.deepEqual(sends.map(([id, m]) => [id, m.text]), [[first, "修一下登录\n细节…"]]);
  assert.equal(local.pendingThread("ws/st", key), 9);
  await both();
  v = screen.value;
  assert.deepEqual([v.pending, v.key, v.outbox[0].id], [false, "chat:c-1", first]);
  await both();
  assert.equal(list.value.days[0].items[0].id, "chat:c-1");
  t.set(threads("ws/st"), [thread(9, ["chat:c-1"], t.host.nowMs())]);
  t.set(pageOf("ws/st", 9), page(1, ["修一下登录\n细节…"], null));
  await both();
  v = screen.value;
  assert.deepEqual([v.key, v.thread.id, v.messages.length], ["chat:c-1", 9, 1]);
  const made = { ...row("chat:c-1", t.host.nowMs()), thread: 9, mine: true };
  t.set(rows("ws/st"), [made]);
  await both();
  items = list.value.days[0].items;
  assert.deepEqual([items.length, items[0].pending], [1, undefined]);
  t.set(rows("ws/st"), []);
  await both();
  assert.equal(list.value.days.length, 0);
});

test("the_stations_row_covers_a_chat_made_here_before_its_answer_comes", async () => {
  const t = setup();
  const local = t.views.local;
  const list = ui();
  t.subscribe(2, { topic: "chats", scope: "ws", mine: true });
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  const old = { ...row("chat:c-0", t.host.nowMs() - 5000), mine: true, thread: 3 };
  t.set(rows("ws/st"), [old]);
  await t.read(list, 2);
  const key = local.pendingNew("ws/st", { runtime: "claude" });
  local.pendingQueue(key, { text: "修一下登录", attachments: [], quotes: [] });
  local.pendingTry(key);
  const idsOf = (): [string, string][] => list.value.days.flatMap((d: J) => d.items).map((i: J) => [i.id ?? "", i.title ?? ""]);
  await t.read(list, 2);
  assert.ok(idsOf().some(([i, ti]) => i === key && ti === "新对话"));
  const theirs = { ...row("chat:c-2", t.host.nowMs()), mine: true, thread: 8, title: "新对话" };
  t.set(rows("ws/st"), [old, theirs]);
  await t.read(list, 2);
  const cmp = (a: [string, string], b: [string, string]) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
  assert.deepEqual(idsOf().sort(cmp), [["chat:c-0", "chat:c-0 的标题"], ["chat:c-2", "新对话"], [key, "新对话"]].sort(cmp as never));
  assert.equal(local.pendingTry(key)?.[1].clientKey, key);
  const made: J = { ...row("chat:c-1", t.host.nowMs()), mine: true, thread: 9, title: "新对话", clientKey: key };
  t.set(rows("ws/st"), [old, theirs, made]);
  await t.read(list, 2);
  const expected: [string, string][] = [["chat:c-0", "chat:c-0 的标题"], ["chat:c-1", "新对话"], ["chat:c-2", "新对话"]];
  assert.deepEqual(idsOf().sort(cmp), expected);
  local.pendingMade(key, "chat:c-1", 9);
  await t.read(list, 2);
  assert.deepEqual(idsOf().sort(cmp), expected);
  made.last = { seq: 1, text: "修一下登录", authorKind: "person", author: "Me@x.com", createdAt: Math.trunc(t.host.nowMs()) };
  made.title = "登录按钮";
  t.set(rows("ws/st"), [old, theirs, made]);
  await t.read(list, 2);
  assert.ok(idsOf().some(([i, ti]) => i === "chat:c-1" && ti === "登录按钮"));
  // its station no longer says the key (it keeps it only a while): the row still does, its page open by it
  const later: J = { ...made, title: "登录按钮 2" };
  delete later.clientKey;
  t.set(rows("ws/st"), [old, theirs, later]);
  await t.read(list, 2);
  const mine = list.value.days.flatMap((d: J) => d.items).find((i: J) => i.id === "chat:c-1");
  assert.deepEqual([mine?.title, mine?.clientKey], ["登录按钮 2", key]);
});

test("a_chat_made_here_keeps_its_first_message_until_its_page_has_the_entry", async () => {
  const t = setup();
  const local = t.views.local;
  const key = local.pendingNew("ws/st", { runtime: "claude" });
  const first = local.pendingQueue(key, { text: "修一下登录", attachments: [], quotes: [] })!;
  local.pendingMade(key, "chat:c-1", 9);
  t.views.outboxSent("ws/st", 9, first, 1);
  const screen = ui();
  t.subscribe(1, agentPage("ws/st", key));
  t.set(workspace(), oneStation());
  await t.host.time.pass(100);
  await t.read(screen, 1);
  let v = screen.value;
  assert.deepEqual([v.messages.length, v.outbox[0].id], [0, first]);
  t.set(threads("ws/st"), [thread(9, ["chat:c-1"], t.host.nowMs())]);
  t.set(pageOf("ws/st", 9), page(1, ["修一下登录"], null));
  await t.read(screen, 1);
  v = screen.value;
  assert.deepEqual([v.messages.length, v.outbox.length], [1, 0]);
});

test("outgoing_identity_survives_a_coalesced_acknowledgement", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const views = t.views;
  const id = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  await t.read(u, 1);
  views.outboxSent("ws/a", 7, id, 6);
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(6, "你好")], last: 6 }));
  await t.read(u, 1);
  const current = u.value;
  assert.deepEqual(current.outbox, []);
  assert.equal(current.messages.find((m: J) => m.seq === 6).outgoing, id);
  assert.equal(current.messages.find((m: J) => m.seq === 5).outgoing, undefined);
});

test("a_sent_message_that_arrives_before_its_seq_leaves_the_outbox_with_it", async () => {
  const t = setup();
  const u = ui();
  const topic = chatTopic("ws/a", 7);
  t.subscribe(1, topic);
  t.set(threads("ws/a"), [thread(7, [], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), page(5, ["早"], null));
  await t.read(u, 1);
  const views = t.views;
  const first = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  const second = views.outboxAdd("ws/a", 7, { text: "你好", attachments: [], quotes: [] });
  await t.read(u, 1);
  assert.equal(u.value.outbox.length, 2);
  const mine = (n: number, text: string) => ({ ...entry(n, text), author: "Me@x.com" });
  t.store.update(pageOf("ws/a", 7), (p) => ({ ...(p as J), entries: [...(p as J).entries, entry(6, "你好"), mine(7, "你好")], last: 7 }));
  await t.read(u, 1);
  assert.deepEqual(u.value.outbox.map((m: J) => m.id), [second]);
  const messages = u.value.messages;
  assert.equal(messages.find((m: J) => m.seq === 7).outgoing, first);
  assert.equal(messages.find((m: J) => m.seq === 6).outgoing, undefined);
  assert.equal(views.local.outboxGet("ws/a", 7, first), undefined);
  const now = views.compute(topic) as J;
  assert.equal(now.ok.messages.find((m: J) => m.seq === 7).outgoing, first);
  views.outboxSent("ws/a", 7, first, 7);
  await t.read(u, 1);
  assert.equal(u.value.outbox.length, 1);
});

test("what_a_chats_agent_sent_to_slack_shows_after_the_message_it_followed_without_being_one_of_the_chats", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const said = (n: number, at: number, text: string) => ({ ...entry(n, text), at });
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [said(1, 1000, "发到 ops 说一声"), { ...said(2, 3000, "<@U9> 发了"), authorKind: "agent", author: "k" }], thread: null });
  const call = (tool: string, args: J, at: string, callId: string) => ({ at, kind: "tool_call", tool, text: JSON.stringify(args), callId });
  t.data.putItems("transcript", "ws/a", "k", [
    [0, call("mcp__stillfail__chat_post", { to: "C0OPS/1727.0001", text: "*部署* 好了 <https://x.y|看这里>" }, "1970-01-01T00:00:02Z", "c1")],
    [1, { at: "1970-01-01T00:00:02Z", kind: "tool_result", text: "posted", ok: true, callId: "c1" }],
    // Its own chat's words are its messages already; what goes to a still.fail chat is not Slack's.
    [2, call("mcp__stillfail__chat_post", { to: "CHAT/1.0", text: "这里" }, "1970-01-01T00:00:02.5Z", "c2")],
    [3, call("mcp__stillfail__slack_api", { method: "chat.postMessage", params: { channel: "C0DEV", text: "<@U9> 新话题" } }, "1970-01-01T00:00:04Z", "c3")],
    // What someone said in Slack, given to it.
    [4, { at: "1970-01-01T00:00:05Z", kind: "user", text: '<message via="slack" thread="C0OPS/1727.0001" from="Mia (U9)" ts="2.5">*收到*，<@U9> 看一下</message>' }],
  ]);
  await t.read(u, 1);
  let v = u.value;
  // Each under the message it followed (the chat's own `elsewhere`: what came before its first).
  const sent = (v: J): J[] => [...v.elsewhere, ...v.messages.flatMap((m: J) => m.elsewhere ?? [])];
  assert.deepEqual(v.elsewhere, []);
  assert.deepEqual(v.messages.map((m: J) => (m.elsewhere ?? []).length), [2, 1]);
  const agent = sent(v)[0].by.name;
  // (whether who said it is one of the chat's agents, `by.here`, is the core's own: the page is not sent it)
  const own = () => t.store.get(chatTopic("ws/a", 7)) as J;
  assert.deepEqual(sent(v).map((s: J) => s.by.here), [undefined, undefined, undefined]);
  assert.deepEqual(sent(own()).map((s: J, i: number) => [s.after, s.text, s.place.name, s.failed, s.received ?? false, sent(v)[i].by.name, s.by.here ?? false]), [
    [1, "**部署** 好了 [看这里](https://x.y)", "#C0OPS", false, false, agent, true],
    [1, "**收到**，@Mia 看一下", "#C0OPS", false, true, "Mia", false],
    [2, "@Mia 新话题", "#C0DEV", false, false, agent, true],
  ]);
  assert.equal(v.messages.length, 2);
  // Slack people the station's agents heard from are named in what agents say too.
  assert.equal(v.messages[1].text, "@Mia 发了");
  // The agent's own message: one of the chat's agents said it.
  assert.equal(own().messages[1].by.here, true);
  // Slack's answer gives the new message its thread; one Slack refused failed.
  t.data.putItems("transcript", "ws/a", "k", [
    [5, { at: "1970-01-01T00:00:04Z", kind: "tool_result", text: JSON.stringify({ ok: true, ts: "1727.0002" }), callId: "c3" }],
    [6, call("mcp__stillfail__slack_api", { method: "chat.postMessage", params: { channel: "C0DEV", thread_ts: "1727.0002", text: "<@U7> 补一句" } }, "1970-01-01T00:00:05Z", "c4")],
    [7, { at: "1970-01-01T00:00:05Z", kind: "tool_result", text: JSON.stringify({ ok: false, error: "not_in_channel" }), callId: "c4" }],
  ]);
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(sent(v).map((s: J) => [s.after, s.text, s.failed]), [
    [1, "**部署** 好了 [看这里](https://x.y)", false],
    [1, "**收到**，@Mia 看一下", false],
    [2, "@Mia 新话题", false],
    // Someone none of the station's agents heard from: by their Slack id.
    [2, "@U7 补一句", true],
  ]);
});

test("a_chat_updates_a_slack_mention_when_another_agent_learns_the_name", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], t.host.nowMs())]);
  t.set(pageOf("ws/a", 7), {
    first: 1, last: 1,
    entries: [{ ...entry(1, "<@U9> 发了"), authorKind: "agent", author: "k" }],
    thread: null,
  });
  await t.read(u, 1);
  assert.equal(u.value.messages[0].text, "@U9 发了");

  const heard = (name: string, at: string) => ({
    at, kind: "user", text: `<message via="slack" thread="C0OPS/1.2" from="${name} (U9)" ts="1.2">hi</message>`,
  });
  // The name came from a different agent, whose transcript this chat does not watch.
  t.data.putItems("transcript", "ws/a", "other", [[0, heard("Mia", "1970-01-01T00:00:01Z")]]);
  await t.read(u, 1);
  assert.equal(u.value.messages[0].text, "@Mia 发了");
  t.data.putItems("transcript", "ws/a", "other", [[1, heard("Mia Wu", "1970-01-01T00:00:02Z")]]);
  await t.read(u, 1);
  assert.equal(u.value.messages[0].text, "@Mia Wu 发了");
  const made = t.router.computed;
  t.data.putItems("transcript", "ws/a", "another", [[0, heard("Mia Wu", "1970-01-01T00:00:03Z")]]);
  await t.read(u, 1);
  assert.equal(t.router.computed, made, "hearing the same name again did not rebuild the chat");
});

test("a_chats_page_is_told_by_each_message_whose_its_files_are_and_nothing_under_its_last_done_post", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const file = (path: string) => ({ name: path.split("/").pop(), path, size: 1 });
  const done = { ...entry(3, "好了"), authorKind: "agent", author: "k", declared: "final", ending: "all_done", attachments: [file("elsewhere/b.png")] };
  // Kept frozen, as the core keeps what it has read: what the page is told goes on copies (written on these, it threw
  // and took the core down).
  const frozen = <T,>(v: T): T => { if (v && typeof v === "object") { for (const x of Object.values(v)) frozen(x); Object.freeze(v); } return v; };
  t.set(pageOf("ws/a", 7), frozen({ first: 1, last: 3, entries: [{ ...entry(1, "看看"), attachments: [file("a.png")] }, { ...entry(2, "在看"), authorKind: "agent", author: "k" }, done], thread: null }));
  const settled = { ...row("k", now), thread: 7 };
  settled.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/a"), [settled]);
  await t.read(u, 1);
  const v = u.value;
  // Kept by the chat's agent: the only one, its workspace's or not.
  assert.deepEqual(v.messages.map((m: J) => m.attachments.map((a: J) => a.owner)), [["k"], [], ["k"]]);
  assert.equal(v.archivable, true);
  // Where it stands, as its row says it: at the end of its messages too.
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], ["已完成", "done", ""]);
  // Archived from its bar or the list: nothing offers it under its last all-done post, nor says what the check made of it.
  assert.equal(v.archiveOffered, undefined);
  assert.deepEqual(v.messages.map((m: J) => [m.archive, m.archiveCheck]), [[undefined, undefined], [undefined, undefined], [undefined, undefined]]);
});

test("a_done_chats_page_not_read_yet_says_where_it_stands_from_its_first_value_not_once_its_read_is_told", async () => {
  // Opening a chat only raises what is brought first (the user, 2026-11-09): its page is what it will be once read, at
  // once, not its end line and archive a moment after, as the read the opening told comes back.
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "看看"), { ...entry(2, "好了"), authorKind: "agent", author: "k", declared: "final", ending: "all_done" }], thread: null });
  const unread = { ...row("k", now), thread: 7, unread: true };
  unread.agents[0].lastTurn = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/a"), [unread]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.stateText, v.stateLead, v.archivable], ["已完成", "done", true]);
  // (the list's row is as it was: not read, nothing said for it yet)
  assert.equal(unread.unread, true);
});

test("a_chats_page_says_at_the_end_of_its_messages_what_its_agent_needs_as_its_row_does", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "部署一下"), { ...entry(2, "要 key"), authorKind: "agent", author: "k" }], thread: null });
  const blocked = { ...row("k", now), thread: 7 };
  blocked.agents[0].lastTurn = { kind: "message", declared: "block", ending: "need_help", need: "Stripe 的测试 key", outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(rows("ws/a"), [blocked]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], ["需要你处理：Stripe 的测试 key", "need", "Stripe 的测试 key"]);
});

test("where_a_chat_stood_is_not_said_again_between_the_viewers_words_reaching_it_and_its_agent_taking_them", async () => {
  // That its agent took them comes by another read (its session's, its row's) than the chat's page: between the two
  // the line of the turn before came back, and went again as the agent set to work (the user, 2026-11-10:
  // 「有个结束的提示，发消息后会出现，然后 agent 开始行动就消失」).
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  const done = { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: now - 60_000, endedAt: now - 50_000 };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", lastTurn: done })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const before = [{ ...entry(1, "看看"), author: "Me@x.com", at: now - 70_000 }, { ...entry(2, "好了"), authorKind: "agent", author: "k", declared: "final", ending: "all_done", at: now - 50_000 }];
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: before, thread: null });
  const rowOf = (lastTurn: J, patch: J = {}): J => {
    const r = { ...row("k", now), thread: 7 };
    r.agents = [{ ...r.agents[0], lastTurn, ...patch }];
    return r;
  };
  t.set(rows("ws/a"), [rowOf(done)]);
  await t.read(u, 1);
  assert.equal(u.value.stateText, "已完成");
  // On their way: the turn it tells of no longer stands.
  t.views.outboxAdd("ws/a", 7, { text: "再改一下", attachments: [], quotes: [] });
  await t.read(u, 1);
  assert.deepEqual([u.value.outbox.length, u.value.stateText], [1, undefined]);
  // In the chat, its agent's session and its row as they were: nor then.
  const sent = { ...entry(3, "再改一下"), author: "Me@x.com", at: now };
  t.set(pageOf("ws/a", 7), { first: 1, last: 3, entries: [...before, sent], thread: null });
  await t.read(u, 1);
  assert.deepEqual([u.value.outbox.length, u.value.messages.length, u.value.stateText], [0, 3, undefined]);
  // Its agent at work on them: nothing to say; its turn over: where it stands now.
  const working = { kind: "message", outcome: null, declared: null, startedAt: now + 1_000, endedAt: null };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", process: "running", lastTurn: working })]);
  t.set(rows("ws/a"), [rowOf(working, { process: "running" })]);
  await t.read(u, 1);
  assert.equal(u.value.stateText, undefined);
  const again = { ...done, need: "改好了", startedAt: now + 1_000, endedAt: now + 9_000 };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", lastTurn: again })]);
  t.set(rows("ws/a"), [rowOf(again)]);
  await t.read(u, 1);
  assert.equal(u.value.stateText, "已完成：改好了");
});

test("a_slack_threads_page_says_at_the_end_of_its_messages_where_it_stands_as_its_agents_row_does", async () => {
  // Its agent has no chat here: the list has it by its session alone (its row's thread null), the page by its thread.
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  const done = { kind: "input", declared: "all_done", ending: "all_done", need: "问题已答完", outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ds", lastTurn: done })]);
  t.set(threads("ws/a"), [{ ...slackThread(7), sessions: [member(7, "k", "ds")], last: 3 }]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 3, entries: [entry(1, "讲讲"), { ...entry(2, "讲完了"), authorKind: "agent", author: "k" }, entry(3, "我试试")], thread: null });
  const alone = row("k", now);
  alone.agents[0].lastTurn = done;
  t.set(rows("ws/a"), [alone]);
  await t.read(u, 1);
  const v = u.value;
  assert.equal(alone.thread, null);
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], ["已完成：问题已答完", "done", "问题已答完"]);
});

test("a_chats_page_says_what_its_agent_waits_on_once_in_its_activity_not_again_at_the_end", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  const waits = { kind: "message", declared: "waiting", ending: "waiting", waitFor: "CI 跑完", waitSeconds: 600, outcome: "completed", startedAt: 1, endedAt: 1 };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", process: "warm", lastTurn: waits })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "合一下"), { ...entry(2, "等 CI"), authorKind: "agent", author: "k" }], thread: null });
  const waiting = { ...row("k", now), thread: 7 };
  waiting.agents[0].lastTurn = waits;
  waiting.agents[0].process = "warm";
  t.set(rows("ws/a"), [waiting]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual(v.agents.map((a: J) => [a.status, a.wait?.text]), [["running", "等待：CI 跑完"]]);
  assert.deepEqual([v.stateText, v.stateLead, v.stateRest], [undefined, undefined, undefined]);
});

test("a_stopped_turn_is_not_said_again_under_its_notice", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  const stopped = { kind: "input", outcome: "aborted", startedAt: 1, endedAt: 2 };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", process: "warm", lastTurn: stopped })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "开始"), { ...entry(2, "已停止当前任务"), authorKind: "ember", author: "ember" }], thread: null });
  const r = { ...row("k", now), thread: 7 };
  r.agents[0].lastTurn = stopped;
  r.agents[0].process = "warm";
  t.set(rows("ws/a"), [r]);
  await t.read(u, 1);
  assert.equal(u.value.stateText, undefined);
});

test("a_failure_is_not_repeated_when_its_notice_is_in_the_chat", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  const failed = { kind: "input", outcome: "failed", detail: "model: failed", startedAt: 1, endedAt: 2, about: { thread: 7, seq: 2, ts: "2" } };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", process: "warm", lastTurn: failed })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const notice = { ...entry(2, "⚠️ 模型服务出错，回复即可重试"), authorKind: "ember", author: "ember" };
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [entry(1, "开始"), notice], thread: null });
  const r = { ...row("k", now), thread: 7 };
  r.agents[0].lastTurn = failed;
  r.agents[0].process = "warm";
  t.set(rows("ws/a"), [r]);
  await t.read(u, 1);
  assert.equal(u.value.stateText, undefined);
  r.agents[0].lastTurn = { ...failed, outcome: "completed" };
  t.set(rows("ws/a"), [{ ...r, agents: [...r.agents] }]);
  await t.read(u, 1);
  assert.equal(u.value.stateText, undefined, "an unexpected end with its own notice is not repeated either");
  // If no matching notice was recorded, the state must still say why it stopped.
  r.agents[0].lastTurn = { ...failed, about: null };
  t.set(rows("ws/a"), [{ ...r, agents: [...r.agents] }]);
  await t.read(u, 1);
  assert.equal(u.value.stateText, "出错：模型服务出错");
});

test("the_viewers_messages_sent_one_after_another_go_close_together_their_time_under_the_last", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(threads("ws/a"), [thread(7, [], now)]);
  const minute = 60_000;
  const said = (n: number, at: number, author = "Me@x.com"): J => ({ ...entry(n, `第 ${n} 条`), author, at });
  // A minute apart, then four minutes on (within 5 of the last's time), then one 5 minutes later than the shown one
  // before it, someone else's, and two more of the viewer's.
  const at = [0, 1, 5, 11, 12, 13, 14].map((m) => now - 15 * minute + m * minute);
  t.set(pageOf("ws/a", 7), { first: 1, last: 7, entries: [said(1, at[0]), said(2, at[1]), said(3, at[2]), said(4, at[3]), said(5, at[4], "a@x.com"), said(6, at[5]), said(7, at[6])], thread: null });
  await t.read(u, 1);
  let v = u.value;
  assert.deepEqual(v.messages.map((m: J) => m.mine), [true, true, true, true, false, true, true]);
  // 1 and 2 are within 5 minutes of 3's time; 3 is 6 minutes before 4's, so it shows its own; 5 is someone else's.
  assert.deepEqual(v.messages.map((m: J) => m.followed ?? false), [true, true, false, false, false, true, false]);
  // Each close under the one before it that has its time under it.
  assert.deepEqual(v.messages.map((m: J) => m.joined ?? false), [false, true, true, false, false, false, true]);
  // What they send now would follow the last, theirs, for 5 minutes from its time.
  assert.equal(v.joinsUntil, at[6] + 5 * minute);
  // One on its way follows the last one too; failed, it does not.
  const id = t.views.outboxAdd("ws/a", 7, { text: "还有", attachments: [], quotes: [] });
  await t.read(u, 1);
  v = u.value;
  assert.deepEqual(v.messages.map((m: J) => m.followed ?? false), [true, true, false, false, false, true, true]);
  assert.deepEqual([v.outbox[0].joined, v.outbox[0].followed], [true, undefined]);
  assert.equal(v.joinsUntil, v.outbox[0].createdAt + 5 * minute);
  t.views.local.outboxState("ws/a", 7, id, "无法连接 station");
  await t.read(u, 1);
  assert.deepEqual(u.value.messages.map((m: J) => m.followed ?? false), [true, true, false, false, false, true, false]);
  assert.equal(u.value.outbox[0].joined, undefined);
  // (nor would the next follow one that did not go, or someone else's)
  assert.equal(u.value.joinsUntil, undefined);
  t.views.local.outboxRemove("ws/a", 7, id);
  await t.read(u, 1);
  assert.equal(u.value.joinsUntil, at[6] + 5 * minute);
  t.set(pageOf("ws/a", 7), { first: 1, last: 8, entries: [said(1, at[0]), said(2, at[1]), said(3, at[2]), said(4, at[3]), said(5, at[4], "a@x.com"), said(6, at[5]), said(7, at[6]), said(8, at[6] + minute, "a@x.com")], thread: null });
  await t.read(u, 1);
  assert.equal(u.value.joinsUntil, undefined);
});

test("a_chats_page_is_told_which_files_its_agents_words_place_and_an_open_image_the_ones_beside_it", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const file = (name: string) => ({ name, path: `ws/k/${name}`, size: 1 });
  // The person's own words place nothing, even naming one; the agent's place theirs (not one named in code), in the
  // order named, ahead of the rest below them.
  const said = { ...entry(1, "![](a.png)"), attachments: [file("a.png"), file("notes.txt")] };
  const agent = { ...entry(2, "先看第二张 ![](c.png)，再看 [这张](ember-file://ws/k/b.png)\n\n`![](d.png)`"), authorKind: "agent", author: "k", attachments: [file("b.png"), file("c.png"), file("d.png"), file("e.mp4")] };
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [said, agent], thread: null });
  t.set(rows("ws/a"), [{ ...row("k", now), thread: 7 }]);
  await t.read(u, 1);
  const v = u.value;
  assert.deepEqual(v.messages.map((m: J) => m.placed ?? null), [null, ["c.png", "b.png"]]);
  // The page is not told every image; the one open in the preview, those beside it as the page shows them.
  assert.equal(v.images, undefined);
  const shown = async (name: string, id: number) => {
    const n = ui();
    t.subscribe(id, { topic: "imageNear", station: "ws/a", thread: 7, session: null, path: `ws/k/${name}` });
    await t.read(n, id);
    assert.equal(n.value.count, 4);
    return [n.value.before ? [n.value.before.name, n.value.before.owner] : null, n.value.after ? [n.value.after.name, n.value.after.owner] : null, n.value.index ?? null];
  };
  assert.deepEqual(await shown("a.png", 2), [null, ["c.png", "k"], 0]);
  assert.deepEqual(await shown("c.png", 3), [["a.png", "k"], ["b.png", "k"], 1]);
  assert.deepEqual(await shown("b.png", 4), [["c.png", "k"], ["d.png", "k"], 2]);
  assert.deepEqual(await shown("d.png", 5), [["b.png", "k"], null, 3]);
  // One not among them (gone meanwhile): none beside it.
  assert.deepEqual(await shown("x.png", 6), [null, null, null]);
});

test("imageNear identifies the particular message or quote that opened the same file", async () => {
  const t = setup();
  const chat = ui();
  t.subscribe(1, chatTopic("ws/a", 7));
  const now = t.host.nowMs();
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember" })]);
  t.set(threads("ws/a"), [thread(7, ["k"], now)]);
  const photo = { name: "photo.png", path: "ws/k/photo.png", size: 1 };
  const original = { ...entry(1, ""), attachments: [photo] };
  const quoted = { ...entry(2, "."), attachments: [photo], quotes: [{ author: "Ana", text: "photo.png", comment: "", ts: "1.0", file: "photo.png" }] };
  t.views.local.remember("ws/a", 7, 2, "sent-1");
  t.set(pageOf("ws/a", 7), { first: 1, last: 2, entries: [original, quoted], thread: null });
  t.set(rows("ws/a"), [{ ...row("k", now), thread: 7 }]);
  await t.read(chat, 1);
  for (const [id, at, index, other] of [[2, "m:1.0/f", 0, "o:sent-1/q:0"], [3, "o:sent-1/q:0", 1, "m:1.0/f"]] as const) {
    const shown = ui();
    t.subscribe(id, { topic: "imageNear", station: "ws/a", thread: 7, session: null, path: photo.path, at });
    await t.read(shown, id);
    assert.equal(shown.value.count, 2);
    assert.equal(shown.value.index, index);
    assert.equal(index === 0 ? shown.value.afterAt : shown.value.beforeAt, other);
  }
});

test("an_agent_only_in_slack_shows_what_was_said_there_on_its_page", async () => {
  const t = setup();
  const u = ui();
  t.subscribe(1, agentPage("ws/a", "k"));
  // Who wrote to it in Slack, with their Slack picture (the station's names book).
  const mia = { id: "slack:ember:U9", name: "Mia", email: null, via: "slack", picture: "https://avatars.slack-edge.com/mia_72.jpg" };
  t.set(sessions("ws/a"), [fullSession("k", { connect: "ember", participants: [mia] })]);
  t.set(rows("ws/a"), [{ id: "k", session: "k", thread: null, title: "看看项目", agents: [] }]);
  // Another agent's bot on the station, its picture as Slack shows it.
  const gpt = { ...connect("gpt", "GPT-Ember"), botImage: "https://avatars.slack-edge.com/gpt_72.jpg", connection: { state: "connected", botUserId: "UB2" } };
  t.set(overview("ws/a"), overviewOf([gpt], []));
  const call = (tool: string, args: J, at: string, callId: string) => ({ at, kind: "tool_call", tool, text: JSON.stringify(args), callId });
  t.data.putItems("transcript", "ws/a", "k", [
    [0, { at: "1970-01-01T00:00:01Z", kind: "user", text: '<message via="slack" thread="C0OPS/1.5" from="Mia (U9)" ts="1.5">看看项目\n\nAttached files:\n- /ws/k/uploads/shot.png (shot.png, 13 bytes)</message>' }],
    [1, call("mcp__stillfail__chat_post", { to: "C0OPS/1.5", text: "*看了*" }, "1970-01-01T00:00:03Z", "c1")],
    [2, { at: "1970-01-01T00:00:03Z", kind: "tool_result", text: "posted", ok: true, callId: "c1" }],
    [3, { at: "1970-01-01T00:00:04Z", kind: "user", text: '<message via="slack" thread="C0OPS/1.5" from="GPT-Ember (<@UB2>)" ts="4.0">也看了</message>' }],
    [4, { at: "1970-01-01T00:00:05Z", kind: "user", text: '<message via="slack" thread="C0OPS/1.5" from="Mia (U9)" ts="5.0"><@UB2> 继续</message>' }],
  ]);
  await t.read(u, 1);
  const v = u.value;
  assert.equal(v.thread ?? null, null);
  assert.deepEqual(v.messages, []);
  assert.deepEqual(v.elsewhere.map((s: J) => [s.after, s.text, s.place.name, s.received ?? false, s.by.name]), [
    [0, "看看项目", "#C0OPS", true, "Mia"],
    [0, "**看了**", "#C0OPS", false, v.elsewhere[1].by.name],
    [0, "也看了", "#C0OPS", true, "GPT-Ember"],
    // Another agent's bot mentioned: by its name, as it was heard.
    [0, "@GPT-Ember 继续", "#C0OPS", true, "Mia"],
  ]);
  // The person's picture as their Slack shows it; the agent's mark, no picture; another agent's bot, its picture.
  assert.equal(v.elsewhere[0].by.picture, mia.picture);
  assert.equal(v.elsewhere[1].by.picture, undefined);
  assert.equal(v.elsewhere[2].by.picture, gpt.botImage);
  // The files the person sent with it are its files, kept by the session they were given to; not its words.
  assert.deepEqual(v.elsewhere.map((s: J) => s.attachments ?? []), [[{ name: "shot.png", path: "/ws/k/uploads/shot.png", size: 13, owner: "k" }], [], [], []]);
});

// ── What is shared is never written on (「谁能改什么」) ──

/// mulberry32: the same draws for the same seed.
function draws(seed: number) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let x = a;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  const int = (n: number) => Math.floor(next() * n);
  return { int, chance: (p: number) => next() < p, pick: <T,>(list: T[]): T => list[int(list.length)] };
}

/// A chat and what is around it, of every kind there is, drawn from a seed: the views make their values from all of
/// it, kept frozen as the core keeps it (and every value the store keeps frozen too, in tests), so a write on any of
/// it anywhere throws, and the topic it is made for says so.
function drawnChat(seed: number, now: number) {
  const d = draws(seed);
  const keys = ["k", "j", "q"].slice(0, 1 + d.int(3));
  const file = (i: number) => ({ name: `f${i}.png`, path: d.chance(0.5) ? `/w/f${i}.png` : `elsewhere/f${i}.png`, size: i + 1 });
  const files = () => Array.from({ length: d.int(3) }, (_, i) => file(i));
  const quotes = () => (d.chance(0.3) ? [{ author: "agent", text: "那段", comment: d.chance(0.5) ? "嗯" : "", ts: "1.0", role: "agent" }] : []);
  const options = () => [{ label: "A", recommended: true }, { label: "B", detail: "再说" }];
  const entries: J[] = [];
  const n = 1 + d.int(12);
  for (let i = 1; i <= n; i++) {
    const kind = d.pick(["person", "agent", "agent", "stillfail", "edit"]);
    if (kind === "edit" && entries.length > 0) {
      entries.push({ thread: 7, n: i, kind: "edit", target: d.pick(entries).n, text: `改过的 ${i}`, attachments: files(), quotes: quotes(), at: i });
      continue;
    }
    const e: J = { ...entry(i, `第 ${i} 条 @Mia`), attachments: files(), quotes: quotes() };
    if (kind === "agent") {
      Object.assign(e, { authorKind: "agent", author: d.pick(keys), agentIdentity: d.chance(0.5) ? { model: "claude-opus-5-5", effort: "high" } : null });
      if (d.chance(0.3)) Object.assign(e, { declared: "final", ending: "all_done" });
      else if (d.chance(0.3)) Object.assign(e, { declared: "block", ending: "need_decision", options: options() });
      if (d.chance(0.2)) e.card = { type: d.pick(["options", "text"]), options: options(), assignee: d.pick(["me@x.com", "other@x.com"]) };
      if (d.chance(0.2)) e.text = "[来自 Slack](https://x.slack.com/a) 那边说的";
    } else if (kind === "stillfail") Object.assign(e, { authorKind: "stillfail", author: "stillfail" });
    else if (d.chance(0.5)) e.author = "me@x.com";
    entries.push(e);
  }
  const people = [{ id: "me@x.com", email: "me@x.com", name: "我", via: "web" }, { id: "local", name: "本机管理页", email: null, via: "local" }].slice(0, d.int(3));
  const th = { ...thread(7, keys, now), people, creator: d.chance(0.5) ? { id: "other@x.com", email: "other@x.com", name: "Other", via: "web" } : null };
  const turnOf = () => d.pick([null, { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1, need: "好了" }, { kind: "message", declared: "block", need: "选哪个", startedAt: 1, endedAt: null }]);
  const sessionsOf = keys.map((k) => fullSession(k, { connect: d.pick(["ember", "c1"]), profile: d.pick(["p1", "p2"]), model: d.pick([null, "claude-opus-5-5"]), process: d.pick(["cold", "running"]), lastTurn: turnOf(), lastActiveAt: now - d.int(100_000) }));
  const r: J = { ...row("k", now), thread: 7, title: "排查", agents: keys.map((k) => ({ ...session(k), lastTurn: turnOf(), process: d.pick(["cold", "running"]) })), unread: d.chance(0.5), mine: d.chance(0.5) };
  if (d.chance(0.5)) r.pinned = now - d.int(1000);
  if (d.chance(0.4)) r.decision = { seq: n, options: options(), message: { seq: n, text: "选哪个？", attachments: files() }, before: [], card: { type: "options", options: options() } };
  if (d.chance(0.4)) r.last = { seq: n, thread: 7, ts: `${n}.0`, authorKind: d.pick(["agent", "person"]), author: d.pick([...keys, "me@x.com"]), authorName: null, text: "最后一句", attachments: files(), quotes: [], declared: null, createdAt: now, editedAt: null };
  const quota = { state: "ok", windows: [{ label: "5h", usedPercent: d.int(100), resetsAt: now / 1000 + 3600 }, { label: "7d", usedPercent: d.int(100) }], credits: { hasCredits: d.chance(0.5), unlimited: false }, resetCount: d.int(3), checkedAt: 1 };
  const ov = {
    ...overviewOf([connect("c1", "Slack")], [profile("p1", { quota }), profile("p2", { name: "主力", access: { kind: "env", provider: "openrouter", key: "" }, check: { state: d.pick(["ok", "login", "failed"]), detail: "", models: ["claude-opus-5-5"], checkedAt: 1 } })]),
    machineLogins: [{ runtime: "claude", installed: true, loggedIn: true, plan: "max", email: "me@x.com", text: "me@x.com · max" }],
  };
  const outbox = Array.from({ length: d.int(3) }, (_, i) => ({ text: `还没发出的 ${i}`, attachments: files(), quotes: quotes() }));
  return { page: { first: 1, last: n, entries, thread: null }, thread: th, sessions: sessionsOf, row: r, overview: ov, outbox };
}

test("what_the_core_keeps_and_shares_is_never_written_on_whatever_a_chat_holds", async () => {
  const seeds = process.env.SIM_SEED ? [Number(process.env.SIM_SEED)] : Array.from({ length: 60 }, (_, i) => i + 1);
  for (const seed of seeds) {
    const t = setup();
    const now = t.host.nowMs();
    const drawn = drawnChat(seed, now);
    const topics: Topic[] = [
      chatTopic("ws/st", 7),
      { topic: "chats", scope: "ws" },
      { topic: "stations", scope: "ws" },
      { topic: "connects", scope: "ws" },
      { topic: "connect", scope: "ws", station: "ws/st", id: "c1" },
      { topic: "connectCandidates", scope: "ws", station: "ws/st", id: "c1" },
      overview("ws/st"),
      sessions("ws/st"),
      hostOf("ws/st"),
    ];
    const uis = topics.map((topic, i) => {
      t.subscribe(i + 1, topic);
      return [ui(), i + 1] as [Ui, number];
    });
    t.set(workspace(), oneStation());
    t.set(prefs(), {});
    t.set(link("ws/st"), { state: "online" });
    t.set(overview("ws/st"), drawn.overview);
    t.set(hostOf("ws/st"), hostInfo("studio"));
    t.set(sessions("ws/st"), drawn.sessions);
    t.set(threads("ws/st"), [drawn.thread]);
    t.set(rows("ws/st"), [drawn.row]);
    t.set(pageOf("ws/st", 7), drawn.page);
    for (const o of drawn.outbox) t.views.outboxAdd("ws/st", 7, o);
    await t.readAll(uis);
    const said = `seed ${seed} (SIM_SEED=${seed} runs it again)`;
    uis.forEach(([u], i) => {
      assert.equal(u.error, undefined, `${topicKey(topics[i])}: ${JSON.stringify(u.error)}; ${said}`);
      assert.notEqual(u.value, undefined, `${topicKey(topics[i])} has no value; ${said}`);
    });
    assert.equal(uis[0][0].value.messages.length, drawn.page.entries.filter((e: J) => e.kind === "message").length, said);
  }
});

test("a_station_says_how_it_is_and_what_is_wrong_with_it_in_the_cores_words", async () => {
  // StationCards.tsx's state() and problems() were the web's own (and its 15 s silence a timer of the page's): the
  // core's now, for the web's station page and the desktop app's alike.
  const t = setup();
  const list = ui();
  t.subscribe(1, { topic: "stations", scope: "ws" });
  t.set(workspace(), stations(t.nowS()));
  await t.read(list, 1);
  t.set(link("ws/a"), { state: "online" });
  t.set(link("ws/b"), { state: "offline" });
  t.set(link("ws/c"), { state: "offline" });
  await t.read(list, 1);
  const of = (st: string) => (list.value as J[]).find((s) => s.station === st);
  // up, not read yet: connecting, nothing wrong yet
  assert.deepEqual([of("ws/a").stateText, of("ws/a").stateBusy, of("ws/a").problems], ["正在连接", false, []]);
  // away: when it was last online, red; never online, amber
  assert.ok(of("ws/b").stateText.endsWith("在线"), of("ws/b").stateText);
  assert.deepEqual(of("ws/b").problems.map((p: J) => [p.key, p.level]), [["away", "red"]]);
  assert.deepEqual([of("ws/c").stateText, of("ws/c").problems.map((p: J) => [p.key, p.level])], ["尚未上线", [["away", "amber"]]]);
  // up and no host reading for 15 s: silent
  await t.host.time.pass(15_000);
  await t.read(list, 1);
  assert.deepEqual(of("ws/a").problems.map((p: J) => [p.key, p.level]), [["silent", "amber"]]);
  // its host read and its agents at work: busy, nothing wrong
  t.set(hostOf("ws/a"), hostInfo("studio"));
  t.set(overview("ws/a"), { ...overviewOf([], []), counts: { sessions: 2, running: 2, warm: 0 } });
  await t.read(list, 1);
  assert.deepEqual([of("ws/a").stateText, of("ws/a").stateBusy, of("ws/a").problems], ["2 个 agent 正在运行", true, []]);
});

test("a_profile_says_what_it_is_who_signs_it_in_and_its_last_check_in_the_cores_words", () => {
  // Accounts.tsx worked these out itself (ACCESS labels, signInProvider, the check's detail without 可用): the core's
  // now, for the web's page and the desktop app's.
  const sub = presentProfile(profile("p1", { check: { state: "ok", detail: "可用，Claude Max", models: [] } }));
  assert.deepEqual([sub.kindText, sub.signInProvider, sub.checkLine], ["订阅账号", "Claude", "Claude Max"]);
  const codex = presentProfile(profile("p2", { runtime: "codex", runtimes: ["codex"] }));
  assert.deepEqual([codex.signInProvider, codex.checkLine], ["ChatGPT", "尚未检查"]);
  const machine = presentProfile(profile("p3", { machine: true }));
  assert.equal(machine.kindText, "终端里的登录");
  const go = presentProfile(profile("p4", { access: { kind: "opencode-go", key: "" } }));
  assert.deepEqual([go.kindText, go.signInProvider], ["OpenCode Go", "OpenCode"]);
  // the station's detail in English starts with its Works, as the Chinese with 可用
  const en = presentProfile(profile("p5", { check: { state: "ok", detail: "Works, 3 models", models: [] } }));
  assert.equal(en.checkLine, "3 models");
});

test("subscription tiers are presented from the check or allowance, and never guessed", () => {
  const checked = presentProfile(profile("sub", { name: "a@example.com", check: { state: "ok", detail: "已登录，a@example.com，max", models: [], plan: "max" } }));
  assert.equal(checked.planText, "Max");
  assert.equal(checked.checkLine, "已登录");
  const machineUltra = presentProfile(profile("machine", { runtime: "claude", check: { state: "ok", detail: "已登录，max", models: [], plan: "ultra" } }));
  assert.deepEqual([machineUltra.planText, machineUltra.checkLine], ["Ultra", "已登录"]);
  const quota = presentProfile(profile("sub", { runtime: "grok", check: { state: "ok", detail: "已登录", models: [] }, quota: { state: "ok", windows: [], plan: "SuperGrok Heavy" } }));
  assert.equal(quota.planText, "SuperGrok Heavy");
  const noWindows = presentProfile(profile("sub", { check: { state: "ok", detail: "", models: [] }, quota: { state: "unavailable", windows: [], plan: "pro" } }));
  assert.equal(noWindows.planText, "Pro");
  const shared = presentProfile(profile("sub", { share: { role: "user" }, check: { state: "ok", plan: "ultra", detail: "", models: [] } }));
  assert.equal(shared.planText, "Ultra");
  assert.equal(presentProfile(profile("sub", { check: { state: "ok", plan: "promax", detail: "", models: [] } })).planText, "Pro Max");
  for (const [plan, name] of [["prolite", "Pro 100"], ["pro", "Pro 200"], ["promax", "Pro 500"]]) {
    assert.equal(presentProfile(profile("codex", { runtime: "codex", runtimes: ["codex"], check: { state: "ok", plan, detail: "", models: [] } })).planText, name);
  }
  assert.equal(presentProfile(profile("claude", { check: { state: "ok", plan: "pro", detail: "", models: [] } })).planText, "Pro");
  assert.equal(presentProfile(profile("sub", { check: { state: "ok", plan: "unknown", detail: "", models: [] } })).planText, "");
  assert.equal(presentProfile(profile("sub", { check: { state: "ok", plan: "unknown", detail: "", models: [] }, quota: { state: "ok", windows: [], plan: "pro" } })).planText, "Pro");
  assert.equal(presentProfile(profile("sub", { check: { state: "ok", plan: "plus", checkedAt: 10, detail: "", models: [] }, quota: { state: "ok", windows: [], plan: "pro", checkedAt: 20 } })).planText, "Pro");
  assert.equal(presentProfile(profile("sub", { check: { state: "ok", plan: "pro", checkedAt: 20, detail: "", models: [] }, quota: { state: "ok", windows: [], plan: "plus", checkedAt: 10 } })).planText, "Pro");
  assert.equal(presentProfile(profile("old", { check: { state: "ok", detail: "已登录", models: [] } })).planText, "");
  assert.equal(presentProfile(profile("key", { access: { kind: "api-provider", key: "" }, check: { state: "ok", plan: "pro", detail: "", models: [] } })).planText, "");
  assert.equal(presentProfile(profile("out", { check: { state: "login", detail: "未登录", models: [] }, quota: { state: "ok", windows: [], plan: "pro" } })).planText, "");
});

test("still.fail's notice is shown as a line: a failure's mark taken off, no closing 。, a profile's link after its ：", () => {
  assert.deepEqual(noticeOf("⚠️ 运行失败：额度用完了。", false), { failed: true, words: "运行失败：额度用完了" });
  assert.deepEqual(noticeOf("已切换模型", false), { failed: false, words: "已切换模型" });
  assert.deepEqual(noticeOf("⚠️ 登录 Work 失败：令牌过期。 ", true), { failed: true, words: "登录 Work 失败：令牌过期", linkAt: 11 });
  assert.deepEqual(noticeOf("登录失败", true), { failed: false, words: "登录失败" });
  // What failed said, under what it means: apart, shown when opened.
  assert.deepEqual(noticeOf("⚠️ 模型服务拒绝了请求（403），未说明原因\n\n```\nunexpected status 403 Forbidden: Unknown error\n```", false), { failed: true, words: "模型服务拒绝了请求（403），未说明原因", detail: "unexpected status 403 Forbidden: Unknown error" });
  assert.deepEqual(noticeOf("⚠️ 账号认证失败：在 Profile 中重新登录\n\n```\n401 Missing API key\n```", true), { failed: true, words: "账号认证失败：在 Profile 中重新登录", linkAt: 7, detail: "401 Missing API key" });
  const m = shownMessage({ authorKind: "stillfail", author: "stillfail", text: "⚠️ 出错了。", seq: 3 }, [], {}, [], [], [], null);
  assert.deepEqual(m.notice, { failed: true, words: "出错了" });
});

test("a_slack_threads_row_has_its_link_there_as_its_page_does_for_its_menu", async () => {
  const t = setup();
  const chats = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  await t.read(chats, 1);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const slack = { ...row("k", t.host.nowMs()), connect: "c1", origin: { teamName: "AFK", channel: "C1", channelName: "ops", threadTs: "1.2" } };
  t.set(rows("ws/st"), [row("7", t.host.nowMs()), slack]);
  const connected = { state: "connected", workspace: { team: "AFK", teamId: "T1", url: "https://afk.slack.com/", botUserId: "U0BOT", botName: "bot" } };
  t.set(overview("ws/st"), overviewOf([{ ...connect("c1", "Slack"), connection: { state: "disabled" } }], []));
  await t.read(chats, 1);
  // (its whole row's, `chatRow`, as its menu reads it: the list's rows say none)
  let of = await wholeOf(t, chats.value);
  assert.deepEqual([of.k.slackUrl, of.k.feishuUrl, of["7"].slackUrl], [undefined, undefined, undefined], "not signed in: none");
  t.set(overview("ws/st"), overviewOf([{ ...connect("c1", "Slack"), connection: connected }], []));
  await t.read(chats, 1);
  of = await wholeOf(t, chats.value, 950);
  assert.deepEqual([of.k.slackUrl, of.k.slackApp, of["7"].slackUrl], ["https://afk.slack.com/archives/C1/p12", "slack://channel?team=T1&id=C1&message=1.2", undefined]);
  assert.equal(chats.value.days.flatMap((d: J) => d.items).find((r: J) => r.id === "k").slackUrl, undefined);
});

/// Three stations' chats, each with a Slack thread's row and a Feishu chat's, and overviews of some size: Slack users,
/// a connect signed in to Slack and one to Feishu, agents running, profiles with their allowances.
const STATIONS = ["a", "b", "c"];
const slackSignedIn = (state = "connected"): J => ({ state, workspace: { team: "AFK", teamId: "T1", url: "https://afk.slack.com/", botUserId: "U0BOT", botName: "bot" } });
function busyStation(i: number, patch: J = {}): J {
  const quota = { state: "ok", windows: [{ label: "5h", usedPercent: 10 + i, resetsAt: 9e12 }], checkedAt: 1 };
  return {
    ...overviewOf(
      [{ ...connect("c1", "Slack"), connection: slackSignedIn() }, { ...connect("c2", "飞书"), kind: "feishu", feishu: { domain: "lark" }, connection: { state: "connected" } }],
      Array.from({ length: 20 }, (_, p) => profile(`p${p}`, { quota, models: ["opus", "sonnet"], env: [{ name: "X", value: "y".repeat(200) }] })),
    ),
    slackUsers: ["U1", "U2"],
    counts: { sessions: 9, running: i + 1, warm: 0 },
    ...patch,
  };
}
function busyRows(st: string, now: number): J[] {
  return [
    { ...row(`${st}-slack`, now - 1000), connect: "c1", origin: { teamName: "AFK", channel: "C1", channelName: "ops", threadTs: "1.2" } },
    { ...row(`${st}-feishu`, now - 2000), connect: "c2", origin: { surface: "feishu:c2", channel: "oc_1", channelName: "群" } },
    ...Array.from({ length: 5 }, (_, i) => row(`${st}${i}`, now - 3000 - i)),
  ];
}
/// A rig with the stations' records written, their chat list asked for.
async function busyList(options: { host?: J } = {}, write = true) {
  const t = setup(options);
  const now = t.host.nowMs();
  if (write) t.set(workspace(), { id: "ws", stations: STATIONS.map((id) => ({ id, name: id, last_seen: null, version: null })) });
  for (const [i, st] of STATIONS.entries()) {
    t.set(link(`ws/${st}`), { state: "online" });
    if (write) {
      t.set(overview(`ws/${st}`), busyStation(i));
      t.set(rows(`ws/${st}`), busyRows(st, now));
    }
  }
  // (written as the list is read: its time passes)
  const u = ui();
  t.subscribe(1, { topic: "chats", scope: "ws" });
  await t.read(u, 1);
  return { t, u };
}

test("a_chat_list_reads_what_it_shows_of_each_stations_overview_not_the_whole_of_it", async () => {
  // The list read every station's whole overview, the largest record there is, for its Slack users and its connects:
  // 3.25 ms of its 21.8 ms in Hermes, five stations of 150 KB each read and parsed on a workspace's first open in a run.
  const first = await busyList();
  const of = await wholeOf(first.t, first.u.value);
  assert.deepEqual([of["a-slack"].slackUrl, of["a-feishu"].feishuUrl === undefined, first.u.value.glyph.running], ["https://afk.slack.com/archives/C1/p12", false, 6]);
  // A core started anew on that database: nothing read yet.
  const before = { ...work };
  const again = await busyList({ host: first.t.host }, false);
  assert.equal(workSince(before).overviewsRead, 0, "no station's whole overview read");
  assert.deepEqual(again.u.value, first.u.value);
});

test("a_chat_list_is_made_again_only_as_what_it_reads_of_an_overview_changes", async () => {
  const { t, u } = await busyList();
  const listed = () => u.value.days.flatMap((d: J) => d.items);
  const was = u.value;
  // Its allowances, its profiles, its jobs: nothing the list reads.
  let before = { ...work };
  let computed = t.router.computed;
  t.set(overview("ws/a"), busyStation(0, { profiles: [profile("p0", { quota: { state: "ok", windows: [], checkedAt: 2 } })], processes: [{ pid: 1 }], disk: { free: 1 } }));
  await t.read(u, 1);
  assert.equal(t.router.computed, computed, "the list not made again");
  assert.equal(workSince(before).listed, 0);
  assert.equal(u.value, was);
  // Who the viewer is in Slack: its station's rows made again.
  before = { ...work };
  computed = t.router.computed;
  t.set(overview("ws/a"), busyStation(0, { slackUsers: ["U1"] }));
  await t.read(u, 1);
  assert.equal(t.router.computed, computed + 1);
  assert.ok(workSince(before).listed > 0, "its rows made again");
  // A connect's state: no row made again; their links there go, their whole rows' (`chatRow`, as its menu reads them).
  assert.equal((await wholeOf(t, u.value))["a-slack"].slackUrl, "https://afk.slack.com/archives/C1/p12");
  const rowsWere = listed();
  before = { ...work };
  t.set(overview("ws/a"), busyStation(0, { slackUsers: ["U1"], connects: [{ ...connect("c1", "Slack"), connection: slackSignedIn("disabled") }] }));
  await t.read(u, 1);
  // (the whole rows held meanwhile are made again, each with its menu: none of the list's)
  assert.deepEqual([workSince(before).listed, workSince(before).rows - workSince(before).rowMenus], [0, 0]);
  assert.ok(listed().every((r: J, i: number) => r === rowsWere[i]));
  assert.equal((await wholeOf(t, u.value, 950))["a-slack"].slackUrl, undefined);
  // How many agents it runs: the glyph's count.
  t.set(overview("ws/a"), busyStation(5, { slackUsers: ["U1"], connects: [{ ...connect("c1", "Slack"), connection: slackSignedIn("disabled") }] }));
  await t.read(u, 1);
  assert.equal(u.value.glyph.running, 11);
});

test("a_database_without_the_overviews_parts_opens_at_its_version_and_gives_the_same_chat_list", async () => {
  const first = await busyList();
  // As a core before them left the database: no parts, no triggers keeping them.
  const sql = first.t.host.sqls.get(dbName("s1"))!;
  sql.exec("DROP TRIGGER IF EXISTS station_part_put; DROP TRIGGER IF EXISTS station_part_set; DROP TRIGGER IF EXISTS station_part_drop; DROP TABLE IF EXISTS station_part;");
  const before = { ...work };
  const again = await busyList({ host: first.t.host }, false);
  // The parts are made as the database opens, no version raised: a core before them still writes it (schema.ts).
  assert.equal(sql.all("PRAGMA user_version")[0][0], 1);
  assert.equal(VERSION, 1);
  assert.deepEqual(again.u.value, first.u.value);
  assert.equal(workSince(before).overviewsRead, 0, "the parts made of the overviews by SQLite: none read by the core");
});

test("an_overview_written_by_a_core_that_knows_nothing_of_its_part_is_what_the_chat_list_shows", async () => {
  const first = await busyList();
  const sql = first.t.host.sqls.get(dbName("s1"))!;
  // An older core (a web page still open from before) writes station a's overview as it always did: its connect signed
  // out of Slack, other Slack users, more agents at work.
  const changed = busyStation(0, { slackUsers: ["U9"], counts: { sessions: 9, running: 7, warm: 0 }, connects: [{ ...connect("c1", "Slack"), connection: slackSignedIn("disabled") }] });
  sql.run("INSERT INTO station (address, kind, json, confirmed) VALUES (?, ?, ?, ?) ON CONFLICT (address, kind) DO UPDATE SET json = excluded.json, confirmed = coalesce(excluded.confirmed, confirmed)", ["ws/a", "overview", JSON.stringify(changed), 2]);
  const again = await busyList({ host: first.t.host }, false);
  const item = await wholeOf(again.t, again.u.value);
  assert.equal(item["a-slack"].slackUrl, undefined, "its connect's state as written");
  assert.equal(item["b-slack"].slackUrl, "https://afk.slack.com/archives/C1/p12");
  assert.equal(again.u.value.glyph.running, 7 + 2 + 3);
  // and as the core that knows of it writes it again: the same
  const fresh = await busyList();
  fresh.t.set(overview("ws/a"), changed);
  await fresh.t.read(fresh.u, 1);
  assert.deepEqual(again.u.value.days, fresh.u.value.days);
  assert.deepEqual(again.u.value.glyph, fresh.u.value.glyph);
});

test("an_agent_whose_card_is_answered_from_here_is_at_work_from_the_answer_on_till_its_turn_after_it_begins", () => {
  const agent = (status: string, startedAt: number | null) => ({
    status,
    session: { key: "s-1", lastTurn: startedAt === null ? null : { startedAt } },
  });
  const card = { seq: 5, ts: "t-5", by: { name: "Claude", agent: "s-1" }, card: { type: "options" }, createdAt: 100 };
  const quotes = [{ author: "Claude", text: "换吗？", comment: "", role: "agent", ts: "t-5" }];
  // on its way: at work at once
  assert.equal(answeredAt([agent("final", 50)], [card], [{ id: "o-1", state: "sending", quotes }])[0].status, "queued");
  // not sent: as it was
  assert.equal(answeredAt([agent("final", 50)], [card], [{ id: "o-1", state: "failed", quotes }])[0].status, "final");
  // here, its turn not begun since: still at work
  const answer = { seq: 6, ts: "t-6", mine: true, quotes, createdAt: 200 };
  assert.equal(answeredAt([agent("final", 50)], [card, answer], [])[0].status, "queued");
  // its turn after it begun (and over): as the station says
  assert.equal(answeredAt([agent("final", 250)], [card, answer], [])[0].status, "final");
  // words sent under the card, the chat's last word: they answer it as a pick does
  const said = { seq: 6, ts: "t-6", mine: true, quotes: [], createdAt: 200 };
  assert.equal(answeredAt([agent("final", 50)], [card], [{ id: "o-1", state: "sending", quotes: [] }])[0].status, "queued");
  assert.equal(answeredAt([agent("final", 50)], [card, said], [])[0].status, "queued");
  // words under something said after it, quoting no card: as they are
  const after = { seq: 6, ts: "t-6", by: { name: "Claude", agent: "s-1" }, createdAt: 150 };
  const later = { seq: 7, ts: "t-7", mine: true, quotes: [], createdAt: 200 };
  assert.equal(answeredAt([agent("final", 50)], [card, after, later], [])[0].status, "final");
  // at work already: as it is
  assert.equal(answeredAt([agent("running", 50)], [card], [{ id: "o-1", state: "sending", quotes }])[0].status, "running");
});

test("subscribing_a_held_topic_views_read_sends_its_value_and_makes_none_of_them_again", async () => {
  // The app, switching workspace, subscribes the workspace's record, which the chat list and the marks read already:
  // that made the marks of the workspace just left again, nothing in it changed (8 ms in Hermes, 2026-11-11).
  const t = setup();
  const [chats, marks, record] = [ui(), ui(), ui()];
  t.subscribe(1, { topic: "chats", scope: "ws" });
  t.subscribe(2, { topic: "workspaceMarks", workspace: "ws" });
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws" }] }]);
  t.set(workspace(), oneStation());
  t.set(prefs(), {});
  t.set(link("ws/st"), { state: "online" });
  const now = t.host.nowMs();
  t.set(rows("ws/st"), [deciding("k1", 7, 5, now - 1000, false), row("r2", now - 2000)]);
  await t.readAll([[chats, 1], [marks, 2]]);
  assert.equal(marks.value.workspaces.ws.wait, 1);
  const before = { ...work };
  const computed = t.router.computed;
  t.subscribe(3, workspace());
  await t.readAll([[chats, 1], [marks, 2], [record, 3]]);
  assert.deepEqual(record.value, oneStation(), "its value, whole");
  assert.equal(record.messages, 1);
  const since = workSince(before);
  assert.deepEqual([t.router.computed - computed, since.workspaceMarks, since.listed, since.rows], [0, 0, 0, 0], "no view made again");
  assert.deepEqual([chats.messages, marks.messages], [1, 1], "nor sent anything");
  // What it holds changing still makes them again, and goes to its subscriber.
  t.set(workspace(), { id: "ws", stations: [{ id: "st", name: "工作室", last_seen: null, version: null }] });
  await t.readAll([[chats, 1], [marks, 2], [record, 3]]);
  assert.equal(record.value.stations[0].name, "工作室");
  assert.ok(t.router.computed > computed);
  assert.equal(chats.value.days[0].items[0].stationName, "工作室");
});
