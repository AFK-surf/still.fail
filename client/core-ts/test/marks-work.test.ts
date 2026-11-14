// The workspaces' marks (views/marks.ts) cost what changed (work.ts `workspaceMarks`, `marked`): a switch of
// workspace, or the pref it writes, makes no workspace's mark and no row's part again; a row that changed makes its
// own alone and its workspace's mark, and the other workspace's mark stays the same object. Counted, never timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { parseTopic, topicKey, type Topic } from "../src/protocol.ts";
import { work, workSince } from "../src/work.ts";
import { link, prefs, rows, setup, ui } from "./views-rig.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

/// The marks as the app asks them (one topic whichever workspace is shown; asked as an app from before asked them, of
/// the one shown, the same topic).
const marksOf = (workspace: string): Topic => parseTopic({ topic: "workspaceMarks", workspace })!;

function row(id: string, thread: number, at: number): J {
  return { id, session: id, thread, title: `${id} 的标题`, agents: [{ key: id, connect: "c1", profile: "p1", runtime: "claude", model: "opus", effort: null, process: "cold", pending: 0, lastTurn: null }], last: null, unread: false, mine: true, lastActiveAt: at, connect: null, origin: null };
}
/// A chat waiting for the viewer (me@x.com) to choose, unread.
function waiting(id: string, thread: number, seq: number, at: number): J {
  const r = row(id, thread, at);
  const options = [{ label: "合", recommended: true }];
  const message = { seq, thread, ts: `9.${seq}`, authorKind: "agent", author: id, authorName: null, text: `${id} 要合吗？`, attachments: [], quotes: [], declared: null, createdAt: at, editedAt: null, options };
  r.decision = { seq, options, card: { type: "options", options, assignee: "me@x.com" }, message, before: [] };
  r.unread = true;
  return r;
}
/// A chat of the viewer's whose agent went wrong (`ended`: when), read or not.
function failed(id: string, thread: number, at: number, unread: boolean, ended = 1): J {
  const r = row(id, thread, at);
  r.agents[0].lastTurn = { kind: "message", outcome: "failed", detail: "auth: 401", startedAt: ended, endedAt: ended };
  r.unread = unread;
  return r;
}
/// A chat of the viewer's with something unread someone (`authorKind`) said last.
function unread(id: string, thread: number, at: number, authorKind: string): J {
  const r = row(id, thread, at);
  r.unread = true;
  r.last = { seq: thread * 10, authorKind };
  return r;
}

/// Two workspaces of one station each: `ws` (whose viewer is me@x.com) with cards waiting, a failure and unread, `wb`
/// with failures and unread; both asked for by the topic of the one shown.
async function twoWorkspaces() {
  const t = setup();
  const now = t.host.nowMs();
  const [a, b] = [ui(), ui()];
  t.subscribe(1, marksOf("ws"));
  await t.readAll([[a, 1]]);
  t.set({ topic: "workspaces" }, [{ workspaces: [{ id: "ws", name: "Home" }, { id: "wb", name: "Labs", emoji: "🧪" }] }]);
  t.set({ topic: "workspace", workspace: "ws" }, { id: "ws", stations: [{ id: "st", name: "studio", last_seen: null, version: null }] });
  t.set({ topic: "workspace", workspace: "wb" }, { id: "wb", stations: [{ id: "lab", name: "lab", last_seen: null, version: null }] });
  t.set(prefs(), { workspace: "ws" });
  t.set(link("ws/st"), { state: "online" });
  t.set(link("wb/lab"), { state: "online" });
  const home = [waiting("k1", 1, 5, now - 1000), waiting("k2", 2, 6, now - 3000), failed("f1", 3, now - 2000, true), unread("u1", 4, now - 500, "agent"), unread("u2", 5, now - 4000, "person")];
  const labs = [failed("g1", 11, now - 1500, true), failed("g2", 12, now - 2500, false), unread("v1", 13, now - 700, "agent"), unread("v2", 14, now - 800, "person")];
  t.set(rows("ws/st"), home);
  t.set(rows("wb/lab"), labs);
  await t.readAll([[a, 1]]);
  return { t, a, b, home, labs, now };
}

test("a_workspaces_marks_are_put_together_of_each_workspaces_own", async () => {
  const { a } = await twoWorkspaces();
  const m = a.value;
  const items = (ws: string) => m.workspaces[ws].items.map((i: J) => [i.kind, i.session, i.seq ?? null]);
  // Most urgent first, the latest first within; failures read or not, the rest only unread.
  assert.deepEqual(items("ws"), [["alert", "f1", null], ["wait", "k1", 5], ["wait", "k2", 6], ["done", "u1", 40], ["done", "u2", 50]]);
  assert.deepEqual(items("wb"), [["alert", "g1", null], ["alert", "g2", null], ["done", "v1", 130], ["done", "v2", 140]]);
  assert.deepEqual([m.workspaces.ws.alert, m.workspaces.ws.wait, m.workspaces.ws.unread, m.workspaces.ws.badge, m.workspaces.ws.label], [1, 2, 2, 5, "1 个出错 · 2 个待你处理 · 2 个有新消息"]);
  assert.deepEqual([m.workspaces.wb.alert, m.workspaces.wb.wait, m.workspaces.wb.unread, m.workspaces.wb.badge], [2, undefined, 2, 3]);
  assert.deepEqual([m.workspaces.wb.items[0].workspaceName, m.workspaces.wb.items[0].workspaceEmoji, m.workspaces.wb.items[0].stationName], ["Labs", "🧪", "lab"]);
  // The badge is every workspace's; each one's `others` the workspaces' besides it, as shown while it is.
  assert.equal(m.badge, 8);
  assert.deepEqual([m.workspaces.ws.others, m.workspaces.ws.othersLabel], ["alert", "其他 workspace：2 个出错 · 2 个有新消息"]);
  assert.deepEqual([m.workspaces.wb.others, m.workspaces.wb.othersLabel], ["alert", "其他 workspace：1 个出错 · 2 个待你处理 · 2 个有新消息"]);
});

test("a_switch_of_workspace_asks_no_mark_again", async () => {
  // The marks were asked of the workspace shown: a switch asked another topic, its value whole (24.6 KB of the
  // real-size two, shaped again, 2.4 ms in Hermes before 大屏's list could be made), the same but which workspace's
  // others it said. One topic whichever is shown: the app holds it across a switch, and asks nothing.
  const { t, a } = await twoWorkspaces();
  assert.equal(topicKey(marksOf("wb")), topicKey(marksOf("ws")));
  const before = { ...work };
  t.set(prefs(), { workspace: "wb" });
  await t.readAll([[a, 1]]);
  assert.deepEqual([workSince(before).workspaceMarks, workSince(before).marked, workSince(before).shapes], [0, 0, 0]);
  assert.equal(a.value.workspaces.wb.others, "alert");
});

test("writing_the_workspace_shown_makes_no_workspaces_mark_again", async () => {
  const { t, a } = await twoWorkspaces();
  const value = t.store.value(marksOf("ws")) as J;
  const before = { ...work };
  t.set(prefs(), { workspace: "wb" });
  await t.readAll([[a, 1]]);
  assert.deepEqual([workSince(before).workspaceMarks, workSince(before).marked], [0, 0]);
  const after = t.store.value(marksOf("ws")) as J;
  assert.equal(after.ok.workspaces.ws, value.ok.workspaces.ws);
  assert.equal(after.ok.workspaces.wb, value.ok.workspaces.wb);
});

test("a_stations_link_coming_and_going_makes_no_workspaces_mark_again", async () => {
  const { t, a } = await twoWorkspaces();
  const value = t.store.value(marksOf("ws")) as J;
  const before = { ...work };
  // As a workspace switched to has its stations tried anew: offline, connecting from offline, online again.
  for (const state of [{ state: "offline" }, { state: "connecting", last: "offline" }, { state: "connecting" }, { state: "online" }]) {
    t.set(link("ws/st"), state);
    await t.readAll([[a, 1]]);
  }
  assert.deepEqual([workSince(before).workspaceMarks, workSince(before).marked], [0, 0]);
  const after = t.store.value(marksOf("ws")) as J;
  assert.equal(after.ok.workspaces.ws, value.ok.workspaces.ws);
  assert.equal(after.ok.workspaces.wb, value.ok.workspaces.wb);
  // (a station renamed is its mark's: made again)
  t.set({ topic: "workspace", workspace: "ws" }, { id: "ws", stations: [{ id: "st", name: "studio 2", last_seen: null, version: null }] });
  await t.readAll([[a, 1]]);
  assert.equal(workSince(before).workspaceMarks, 1);
  assert.equal((t.store.value(marksOf("ws")) as J).ok.workspaces.ws.items[0].stationName, "studio 2");
});

test("a_row_that_changed_makes_its_own_part_again_and_no_other", async () => {
  const { t, a, home, now } = await twoWorkspaces();
  const value = t.store.value(marksOf("ws")) as J;
  const before = { ...work };
  // k2 looked at: its card no longer counted by the badge, nor in 待处理.
  const seen = { ...home[1], unread: false };
  t.set(rows("ws/st"), [home[0], seen, ...home.slice(2)]);
  await t.readAll([[a, 1]]);
  assert.deepEqual([workSince(before).workspaceMarks, workSince(before).marked], [1, 1]);
  const after = t.store.value(marksOf("ws")) as J;
  assert.equal(after.ok.workspaces.wb, value.ok.workspaces.wb, "the other workspace's mark is the same object");
  assert.deepEqual(a.value.workspaces.ws.items.map((i: J) => i.session), ["f1", "k1", "u1", "u2"]);
  assert.deepEqual([a.value.workspaces.ws.wait, a.value.workspaces.ws.badge, a.value.badge], [2, 4, 7]);
  // A failure let go (a pref of its workspace's) makes no row again, and only its workspace's mark.
  const failure = a.value.workspaces.ws.items[0].failure;
  assert.equal(failure, "ws/st/f1@1");
  const kept = t.store.value(marksOf("ws")) as J;
  const letGo = { ...work };
  t.set(prefs(), { workspace: "ws", failsGone: { ws: [failure] } });
  await t.readAll([[a, 1]]);
  assert.deepEqual([workSince(letGo).workspaceMarks, workSince(letGo).marked], [1, 0]);
  // (the other's mark not made again: what it says of the others, this one, is what is new of it)
  const wb = (t.store.value(marksOf("ws")) as J).ok.workspaces.wb;
  assert.equal(wb.items, kept.ok.workspaces.wb.items);
  assert.deepEqual([wb.others, wb.othersLabel], ["wait", "其他 workspace：2 个待你处理 · 2 个有新消息"]);
  assert.deepEqual([a.value.workspaces.ws.alert, a.value.workspaces.ws.items.map((i: J) => i.session)], [0, ["k1", "u1", "u2"]]);
  // A row of the other workspace: that one alone.
  const other = { ...work };
  t.set(rows("wb/lab"), [failed("g1", 11, now - 1500, true), failed("g2", 12, now - 2500, false, 2), unread("v1", 13, now - 700, "agent"), unread("v2", 14, now - 800, "person")]);
  await t.readAll([[a, 1]]);
  assert.deepEqual([workSince(other).workspaceMarks, workSince(other).marked], [1, 1]);
});

test("what_the_badge_counts_changes_every_workspaces_mark_and_the_badge", async () => {
  const { t, a } = await twoWorkspaces();
  const before = { ...work };
  t.set(prefs(), { workspace: "ws", badgeKinds: { done: false } });
  await t.readAll([[a, 1]]);
  assert.deepEqual([workSince(before).workspaceMarks, workSince(before).marked], [2, 0], "what a row says of itself is not what the badge counts");
  assert.deepEqual(a.value.workspaces.ws.items.map((i: J) => i.session), ["f1", "k1", "k2", "u2"]);
  assert.deepEqual(a.value.workspaces.wb.items.map((i: J) => i.session), ["g1", "g2", "v2"]);
  assert.deepEqual([a.value.workspaces.ws.badge, a.value.workspaces.wb.badge, a.value.badge, a.value.badgeKinds.done], [4, 2, 6, false]);
});

test("a_mark_made_again_reads_of_the_database_only_the_row_that_changed", async () => {
  // Made again, a workspace's mark read the JSON of every row it counts to take each one kept (account.ts #byKey): 5.6
  // ms in Hermes for 123 rows, each time one of them changed (2026-11-11).
  const { t, a, home } = await twoWorkspaces();
  const list = ui();
  t.subscribe(3, { topic: "chats", scope: "ws" });
  await t.readAll([[a, 1], [list, 3]]);
  assert.equal(list.value.days.flatMap((d: J) => d.items).length, home.length);
  const before = { ...work };
  // k2 looked at: one marked row changed, as a station's event says it.
  t.data.putChat("ws/st", { ...home[1], unread: false, title: "看过了" });
  await t.readAll([[a, 1], [list, 3]]);
  const spent = workSince(before);
  assert.equal(spent.workspaceMarks, 1, "the mark made again");
  assert.ok(spent.rowJson <= 1, `rows whose JSON was read: ${spent.rowJson}`);
  assert.ok(list.value.days.flatMap((d: J) => d.items).some((i: J) => i.title === "看过了"));
});
