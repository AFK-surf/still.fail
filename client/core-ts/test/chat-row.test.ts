// What a row of the chat list is (schema.ts ListedChat): what the row draws, what tells it from another, the few things a
// press needs to know where to go; and a chat's whole row (`chatRow`, ChatItem), what a press, a hold, a swipe or a
// pointer reads besides (its menu, its swipe's question, its time in words), asked as that begins. The list is made
// without the rest and depends on nothing only that reads: no row's menu, swipe question or watch is made of a list
// (work.ts `rowMenus`, `swipeAsks`, `watches`), a station's connect, the viewer's role and workspaces and a member no
// row names make no row again, a minute sends nothing of it; a chat's whole row is what the list's row was before
// (`OLD`, the list's rows as it sent them then), and its list's row that cut to the list's shape. Counted, never timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import { work, workSince } from "../src/work.ts";
import { LIST_ROW_KEYS } from "../src/views/views.ts";
import { link, overview, prefs, rows, setup, ui, type Ui } from "./views-rig.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

const ME = { sub: "s1", email: "me@x.com", name: "我", role: "member" };
const ANA = { sub: "s2", email: "ana@x.com", name: "Ana Lee", picture: "https://x/ana.png", role: "admin" };
const BO = { sub: "s3", email: "bo@x.com", name: "Bo", role: "member" };
/// The workspace: two stations (so a row says its station's mark), three members, the viewer a member of it.
const workspaceOf = (members: J[] = [ME, ANA, BO], role = "member"): J => ({
  id: "ws", role, members,
  stations: [{ id: "a", name: "alpha", emoji: "🍁", last_seen: null, version: null }, { id: "b", name: "beta", last_seen: null, version: null }],
});
const agent = (key: string, patch: J = {}): J => ({ key, connect: "c1", profile: "p1", runtime: "claude", model: "claude-opus-5-5", effort: null, process: "cold", pending: 0, lastTurn: null, ...patch });
const person = (p: J, via = "web"): J => ({ id: p.email, email: p.email, name: p.name, via });
const slackSignedIn = (state = "connected"): J => ({ state, workspace: { team: "AFK", teamId: "T1", url: "https://afk.slack.com/", botUserId: "U0BOT", botName: "bot" } });
const connects = (slack = "connected"): J[] => [
  { id: "c1", name: "Slack", team: null, enabled: true, kind: "slack", mode: "multi-session", requireMention: true, bind: { runtime: "claude", model: null, effort: null, profile: null }, slack: { appToken: "", botToken: "" }, connection: slackSignedIn(slack), createdBy: null, sessions: 0, session: null },
  { id: "c2", name: "飞书", team: null, enabled: true, kind: "feishu", mode: "multi-session", requireMention: true, bind: { runtime: "claude", model: null, effort: null, profile: null }, feishu: { domain: "lark" }, connection: { state: "connected" }, createdBy: null, sessions: 0, session: null },
];
const overviewOf = (slack = "connected", slackUsers = ["U1"]): J => ({
  viewer: { via: "local" }, connects: connects(slack), profiles: [], processes: [], counts: { sessions: 0, running: 1, warm: 0 }, mesh: null, slackUsers, slackTeams: [], slackApps: [], disk: null, logins: [],
});

/// Station a's chats, each something a whole row says otherwise: a Slack thread Ana started (its link there, her name in
/// its swipe's question; kept), a watching one (muted), one whose card waits for the viewer (pinned), one at work
/// (shared with another workspace), a Feishu chat, one done (offered to archive), one an agent opened (from `run`).
function chatsOf(now: number): J[] {
  const at = (i: number) => Math.trunc(now) - (i + 1) * 61_000;
  const said = (seq: number, who: J | string, text: string, i: number): J => ({ seq, authorKind: typeof who === "string" ? "agent" : "person", author: typeof who === "string" ? who : who.email, authorName: null, text, createdAt: at(i) });
  const options = [{ label: "合", recommended: true }, { label: "先不改", detail: "留到下周" }];
  const card = { seq: 9, options, card: { type: "options", options, assignee: ME.email }, message: { seq: 9, thread: 13, ts: "9.000009", authorKind: "agent", author: "card", authorName: null, text: "**card** 要合吗？\n细节", attachments: [], quotes: [], declared: null, createdAt: at(2), editedAt: null, options }, before: [] };
  return [
    { id: "slack", session: "slack", thread: 11, title: "部署", agents: [agent("slack")], last: said(5, ANA, "看一下 <@U1>", 0), unread: true, mine: false, lastActiveAt: at(0), connect: "c1", origin: { teamName: "AFK", channel: "C1", channelName: "ops", threadTs: "1.2" }, creator: person(ANA), people: [person(ANA), person(ME)], archiveReminderDismissed: true, hidden: false, muted: false },
    { id: "watch", session: "watch", thread: 12, title: "盯 CI", agents: [agent("watch", { watch: { names: ["CI"], since: 1, at: 2 } })], last: said(3, "watch", "还在跑", 1), unread: false, mine: true, lastActiveAt: at(1), connect: null, origin: null, creator: person(ME), people: [person(ME)], hidden: false, muted: true },
    { id: "card", session: "card", thread: 13, title: "合并", agents: [agent("card", { lastTurn: { kind: "message", declared: "block", ending: "need_decision", outcome: "completed", startedAt: 1, endedAt: 1 } })], last: said(9, "card", "要合吗？", 2), unread: true, mine: true, lastActiveAt: at(2), connect: null, origin: null, decision: card, pinned: 5, creator: person(ME), people: [person(ME), person(ANA)] },
    { id: "run", session: "run", thread: 14, title: "重构", agents: [agent("run", { process: "running" })], last: said(4, ME, "继续", 3), unread: false, mine: true, lastActiveAt: at(3), connect: null, origin: null, xshare: { to: ["w2"], write: false }, creator: person(ME), people: [person(ME)] },
    { id: "feishu", session: "feishu", thread: 15, title: "飞书群", agents: [agent("feishu")], last: null, unread: false, mine: false, lastActiveAt: at(4), connect: "c2", origin: { surface: "feishu:c2", channel: "oc_1", channelName: "群" } },
    { id: "done", session: "done", thread: 16, title: "做完了", agents: [agent("done", { lastTurn: { kind: "message", declared: "final", ending: "all_done", outcome: "completed", startedAt: 1, endedAt: 1 } })], last: null, unread: false, mine: true, lastActiveAt: at(5), connect: null, origin: null },
    { id: "opened", session: "opened", thread: 17, title: "子任务", agents: [agent("opened")], last: null, unread: false, mine: true, lastActiveAt: at(6), connect: null, origin: null, opener: { session: "run", title: "重构" } },
  ];
}
/// Station b's one chat.
const otherOf = (now: number): J[] => [{ id: "b1", session: "b1", thread: 21, title: "另一台", agents: [agent("b1")], last: null, unread: false, mine: true, lastActiveAt: Math.trunc(now) - 30 * 61_000, connect: null, origin: null }];

/// A rig with the workspace and its stations' chats written, the viewer's workspaces as the account says them (`me`,
/// as xshare.ts places reads them), their chat list asked for.
async function listed(asked: Topic = { topic: "chats", scope: "ws" }) {
  const t = setup({ all: true, env: ({ data }) => ({ places: () => (((data.record("me", "s1") as J)?.workspaces ?? []) as J[]).map((w) => ({ id: w.id, name: w.name, role: w.role ?? null, emoji: null, icon: null })) }) });
  // (the minute's clock the store says times in words by, as a core's)
  t.store.setClock();
  const now = t.host.nowMs();
  t.data.put("me", "s1", { workspaces: [{ id: "ws", name: "WS", role: "member" }, { id: "w2", name: "W2", role: "owner" }] });
  t.set(workspace(), workspaceOf());
  t.set(prefs(), {});
  for (const s of ["a", "b"]) t.set(link(`ws/${s}`), { state: "online" });
  t.set(overview("ws/a"), overviewOf());
  t.set(rows("ws/a"), chatsOf(now));
  t.set(rows("ws/b"), otherOf(now));
  const u = ui();
  t.subscribe(1, asked);
  await t.read(u, 1);
  return { t, u };
}
const workspace = (): Topic => ({ topic: "workspace", workspace: "ws" });
const items = (v: J): J[] => v.days.flatMap((d: J) => d.items);

test("a_chat_list_is_made_with_no_rows_menu_swipe_question_or_watch", async () => {
  const before = { ...work };
  const { u } = await listed();
  const made = workSince(before);
  assert.equal(items(u.value).length, 8);
  // (made as their records were written and kept beside them, db/kept.ts KEPT.listRow, or as the list read them)
  assert.ok(made.rows + made.listRowWritten >= 8, `${made.rows} rows made as read, ${made.listRowWritten} as written`);
  // (main: 8 menus, 8 swipes' questions, 1 watch: every row's, the list's)
  assert.deepEqual([made.rowMenus, made.swipeAsks, made.watches], [0, 0, 0]);
  // Nor what a row's whole row says besides: none of it goes out on the list.
  for (const i of items(u.value)) for (const k of ["swipeAsk", "watch", "decision", "mayShare", "mayPublish", "slackUrl", "slackApp", "feishuUrl", "kept", "muted", "time", "xshare"]) assert.equal(i[k], undefined, `${i.id}.${k}`);
});

test("a_lists_rows_are_made_again_by_what_they_draw_alone", async () => {
  const { t, u } = await listed();
  const was = items(u.value);
  const same = (why: string) => {
    const now = items(u.value);
    assert.equal(now.length, was.length, why);
    now.forEach((r, i) => assert.equal(r, was[i], `${why}: ${r.id} the same row`));
  };
  // What only a row's whole row reads: no row made again (main: every row of the station, or of the list).
  const nothing = async (why: string, change: () => unknown) => {
    const before = { ...work };
    await change();
    await t.read(u, 1);
    assert.equal(workSince(before).rows, 0, `${why}: rows made`);
    same(why);
  };
  // its station's connect signed out of Slack (a Slack thread's link there)
  await nothing("a connect's state", () => t.set(overview("ws/a"), { ...overviewOf("disabled") }));
  // the viewer's role here (who may publish), their workspaces (who may share)
  await nothing("the viewer's role", () => t.set(workspace(), workspaceOf([ME, ANA, BO], "viewer")));
  await nothing("the viewer's workspaces", () => t.data.put("me", "s1", { workspaces: [{ id: "ws", name: "WS", role: "member" }] }));
  // a member no row names, renamed and pictured anew
  await nothing("a member no row names", () => t.set(workspace(), workspaceOf([ME, ANA, { ...BO, name: "Bob", picture: "https://x/bo.png" }], "viewer")));
  // a minute and more on (its time is its whole row's)
  await nothing("minutes on", () => t.host.time.pass(3 * 60_000));
  // What a row draws: Ana renamed makes again the rows that name her alone (their faces, who said their last line).
  let before = { ...work };
  t.set(workspace(), workspaceOf([ME, { ...ANA, name: "Ana Park" }, { ...BO, name: "Bob", picture: "https://x/bo.png" }], "viewer"));
  await t.read(u, 1);
  assert.equal(workSince(before).rows, 2, "the two rows naming Ana");
  const now = items(u.value);
  for (const [i, r] of now.entries()) {
    const names = (r.people ?? []).map((p: J) => p.shown.name);
    if (r.id === "slack" || r.id === "card") assert.ok(names.includes("Ana Park"), `${r.id}: ${names}`);
    else assert.equal(r, was[i], `${r.id} the same row`);
  }
  // Who the viewer is in Slack (`mine` of its faces and its last line): its station's rows.
  before = { ...work };
  t.set(overview("ws/a"), { ...overviewOf("disabled", ["U1", "U2"]) });
  await t.read(u, 1);
  assert.equal(workSince(before).rows, 7, "station a's rows");
  // Its station's name: its rows.
  before = { ...work };
  t.set(workspace(), { ...workspaceOf([ME, { ...ANA, name: "Ana Park" }, { ...BO, name: "Bob", picture: "https://x/bo.png" }], "viewer"), stations: [{ id: "a", name: "alpha 2", emoji: "🍁", last_seen: null, version: null }, { id: "b", name: "beta", last_seen: null, version: null }] });
  await t.read(u, 1);
  assert.equal(workSince(before).rows, 7, "station a renamed");
  assert.equal(items(u.value).find((r) => r.id === "slack").stationName, "alpha 2");
});

test("a_minute_passing_sends_nothing_of_a_chat_list", async () => {
  const { t, u } = await listed();
  const said = u.messages;
  const was = u.value;
  await t.host.time.pass(60_000);
  await t.read(u, 1);
  await t.host.time.pass(5 * 60_000);
  await t.read(u, 1);
  assert.equal(u.messages, said, "nothing sent as the minutes pass (main: the rows' times in words, each minute)");
  assert.equal(u.value, was);
  // A chat's whole row says its time in words: sent again as the minute passes while it is held.
  const whole = ui();
  t.subscribe(2, { topic: "chatRow", station: "ws/a", session: "slack" });
  await t.read(whole, 2);
  const [ago, sent] = [whole.value.time.lastActiveAt.ago, whole.messages];
  // (the minute's clock goes on a second past each minute: one and the next on)
  await t.host.time.pass(2 * 60_000);
  await t.read(whole, 2);
  assert.ok(whole.messages > sent);
  assert.notEqual(whole.value.time.lastActiveAt.ago, ago);
});

/// The list's rows as it sent them before its rows were what a row draws (main b7906dd23: `chats`, this fixture, the
/// test's clock), by id: what a chat's whole row is.
const OLD: Record<string, J> = {
  "card": {"id":"card","session":"card","thread":13,"title":"合并","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"last":{"seq":9,"by":{"mine":false},"preview":"要合吗？"},"unread":true,"station":"ws/a","stationName":"alpha","stationEmoji":"🍁","state":"block","time":{"lastActiveAt":{"ago":"3 分钟前","full":"10/6 08:56:57"}},"people":[{"id":"me@x.com","email":"me@x.com","shown":{"name":"我","mine":true}},{"id":"ana@x.com","email":"ana@x.com","shown":{"name":"Ana Lee","picture":"https://x/ana.png","mine":false}}],"creator":{"id":"me@x.com"},"peopleText":"你 发起 · Ana Lee","pinned":true,"decision":{"seq":9,"options":[{"label":"先不改","detail":"留到下周"},{"label":"合","recommended":true}],"card":{"assignee":"me@x.com","type":"options","options":[{"label":"先不改","detail":"留到下周"},{"label":"合","recommended":true}]},"text":"待处理 · card 要合吗？"},"swipeArchive":true,"stateText":"待处理 · card 要合吗？","stateLead":"decision","stateLeadText":"待处理","stateRest":" · card 要合吗？","tone":"wait","mayPublish":true},
  "slack": {"id":"slack","session":"slack","thread":11,"title":"部署","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"last":{"seq":5,"by":{"mine":false},"preview":"看一下"},"unread":true,"connect":"c1","station":"ws/a","stationName":"alpha","stationEmoji":"🍁","originText":"Slack · AFK · #ops","originKind":"slack","time":{"lastActiveAt":{"ago":"1 分钟前","full":"10/6 08:58:59"}},"people":[{"id":"ana@x.com","email":"ana@x.com","shown":{"name":"Ana Lee","picture":"https://x/ana.png","mine":false}},{"id":"me@x.com","email":"me@x.com","shown":{"name":"我","mine":true}}],"creator":{"id":"ana@x.com"},"peopleText":"Ana Lee 发起 · 你","swipeArchive":true,"swipeAsk":"这是Ana Lee发起的对话。归档后，workspace 里所有人的列表都不再显示它，agent 也不再接收新消息。只想从自己的列表移走，可以长按选「隐藏」。","kept":true,"hidden":false,"muted":false,"tone":"done","mayPublish":true,"slackUrl":"https://afk.slack.com/archives/C1/p12","slackApp":"slack://channel?team=T1&id=C1&message=1.2"},
  "watch": {"id":"watch","session":"watch","thread":12,"title":"盯 CI","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"last":{"seq":3,"by":{"mine":false},"preview":"还在跑"},"unread":false,"station":"ws/a","stationName":"alpha","stationEmoji":"🍁","time":{"lastActiveAt":{"ago":"2 分钟前","full":"10/6 08:57:58"}},"people":[{"id":"me@x.com","email":"me@x.com","shown":{"name":"我","mine":true}}],"creator":{"id":"me@x.com"},"peopleText":"你 发起","watch":{"text":"监控中：CI","ask":"「CI」仍在监控。归档会停止监控。"},"swipeArchive":true,"swipeAsk":"「CI」仍在监控。归档会停止监控。","hidden":false,"muted":true,"mayPublish":true},
  "run": {"id":"run","session":"run","thread":14,"title":"重构","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"last":{"seq":4,"by":{"mine":true},"preview":"继续"},"unread":false,"station":"ws/a","stationName":"alpha","stationEmoji":"🍁","state":"run","time":{"lastActiveAt":{"ago":"4 分钟前","full":"10/6 08:55:56"}},"people":[{"id":"me@x.com","email":"me@x.com","shown":{"name":"我","mine":true}}],"creator":{"id":"me@x.com"},"peopleText":"你 发起","swipeArchive":true,"swipeAsk":"此对话正在进行中。归档后，agent 完成当前回复即停止，等待中的任务也会停止。","tone":"busy","xshare":{"to":["w2"],"write":false},"mayPublish":true},
  "feishu": {"id":"feishu","session":"feishu","thread":15,"title":"飞书群","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"unread":false,"connect":"c2","station":"ws/a","stationName":"alpha","stationEmoji":"🍁","originText":"飞书 · 群","originKind":"feishu","time":{"lastActiveAt":{"ago":"5 分钟前","full":"10/6 08:54:55"}},"swipeArchive":true,"mayPublish":true,"feishuUrl":"https://applink.larksuite.com/client/chat/open?openChatId=oc_1"},
  "done": {"id":"done","session":"done","thread":16,"title":"做完了","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"unread":false,"station":"ws/a","stationName":"alpha","stationEmoji":"🍁","time":{"lastActiveAt":{"ago":"6 分钟前","full":"10/6 08:53:54"}},"settled":true,"swipeArchive":true,"stateText":"已完成","stateLead":"done","stateRest":"","mayPublish":true},
  "opened": {"id":"opened","session":"opened","thread":17,"title":"子任务","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"unread":false,"station":"ws/a","stationName":"alpha","stationEmoji":"🍁","time":{"lastActiveAt":{"ago":"7 分钟前","full":"10/6 08:52:53"}},"swipeArchive":true,"mayPublish":true,"opener":{"station":"ws/a","session":"run","title":"重构","text":"由「重构」创建"}},
  "b1": {"id":"b1","session":"b1","thread":21,"title":"另一台","agents":[{"runtime":"claude","agentText":"Opus 5.5","maker":{"id":"anthropic"}}],"unread":false,"station":"ws/b","stationName":"beta","time":{"lastActiveAt":{"ago":"31 分钟前","full":"10/6 08:29:30"}},"swipeArchive":true,"mayPublish":true},
};

test("a_chats_whole_row_is_what_the_lists_row_was_and_its_lean_row_that_cut_to_the_lists_shape", async () => {
  const { t, u } = await listed();
  const list = items(u.value);
  assert.deepEqual(list.map((i) => i.id).sort(), Object.keys(OLD).sort());
  const asked: [Ui, number][] = list.map((_, n) => [ui(), 10 + n]);
  list.forEach((i, n) => t.subscribe(10 + n, { topic: "chatRow", station: i.station, session: i.session }));
  await t.readAll(asked);
  for (const [n, i] of list.entries()) {
    const whole = asked[n]![0].value;
    assert.deepEqual(whole, OLD[i.id], `${i.id}: its whole row is the list's row as it was`);
    const cut = conform("ListedChat", whole);
    assert.ok("ok" in cut);
    assert.deepEqual(i, cut.ok, `${i.id}: its list's row is its whole row cut to ListedChat`);
  }
  // None such: null.
  const none = ui();
  t.subscribe(40, { topic: "chatRow", station: "ws/a", session: "gone" });
  await t.read(none, 40);
  assert.equal(none.value, null);
});

test("a_search_and_the_at_menu_list_their_chats_whole", async () => {
  // (made for the chats they show, as chatRow makes one: views.ts wholeFor)
  const { t, u } = await listed({ topic: "chatSearch", scope: "ws", query: "", limit: 8 });
  const found = u.value.items as J[];
  assert.ok(found.length >= 7);
  for (const i of found) {
    const { otherStation: _o, ...whole } = i;
    assert.deepEqual(whole, OLD[i.id], `${i.id} as its whole row`);
  }
  const search = ui();
  t.subscribe(2, { topic: "search", scope: "ws", query: "" });
  await t.read(search, 2);
  for (const i of search.value.items as J[]) assert.deepEqual(i, OLD[i.id], `${i.id} as its whole row`);
});


/// Values at the ends of a value (strings, numbers, booleans, nulls).
const leaves = (v: J): number => (v !== null && typeof v === "object" ? Object.values(v).reduce((n: number, x) => n + leaves(x), 0) : 1);

test("a_lists_row_is_made_as_what_it_holds_its_records_values_shared_none_cloned", async () => {
  const before = { ...work };
  const { t } = await listed();
  const made = workSince(before);
  // The rows as the core holds them (what its readers read, `store.value`), not as they go out.
  const held: J[] = items((t.store.value({ topic: "chats", scope: "ws" }) as J).ok);
  assert.equal(held.length, 8);
  // No record cloned into a list's row (main: one each, 8, every value of each copied).
  assert.equal(made.rowsCloned, 0, "records cloned whole");
  // What a list's row holds: its shape's and what the core reads of it (views.ts LIST_ROW_KEYS, each with its reader),
  // none of the rest of its record (main: `named`, `mine`, `archiveReviewed`, its card, the whole agents' summaries …).
  for (const r of held) {
    for (const k of Object.keys(r)) assert.ok(LIST_ROW_KEYS.has(k), `${r.id}.${k} held: say who reads it (views.ts LIST_ROW_READ)`);
    for (const a of r.agents) for (const k of Object.keys(a)) assert.ok(["key", "runtime", "model", "agentText", "maker"].includes(k), `${r.id}.agents[].${k}`);
    if (r.last != null) for (const k of Object.keys(r.last)) assert.ok(["seq", "by", "preview"].includes(k), `${r.id}.last.${k}`);
    for (const p of r.people ?? []) assert.deepEqual(Object.keys(p.shown).sort(), ["mine", "name", "picture"], `${r.id}.people[].shown`);
  }
  // What it takes of its record as it is, the record's own (frozen, shared): none copied.
  const records = new Map(((t.data.shared({ topic: "chatRows", station: "ws/a" }) as J[]) ?? []).map((r: J) => [r.id, r]));
  const slack = held.find((r) => r.id === "slack");
  assert.equal(slack.origin, records.get("slack").origin, "its origin the record's");
  assert.equal(held.find((r) => r.id === "run").xshare, records.get("run").xshare, "its sharing the record's");
  // (main: 526 leaves for these 8 rows, 9.3 KB; made as they hold, 237 and 4.6 KB)
  const n = held.reduce((k, r) => k + leaves(r), 0);
  assert.ok(n <= LEAVES, `${n} leaves held`);
});
/// The leaves the fixture's 8 list rows hold at most (as made, 237).
const LEAVES = 240;
