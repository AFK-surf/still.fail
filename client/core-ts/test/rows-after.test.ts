// A station's sidebar rows brought on here by what its stream tells (station/rows-after.ts), as the station makes them
// (station/src/read/views.ts `chats`); and where only the station can say what they are now.
import assert from "node:assert/strict";
import { test } from "node:test";
import { rowAfterDismiss, rowAfterKept, rowAfterPin, rowAfterSaid, rowAfterSession } from "../src/station/rows-after.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const agent = (over: J = {}): J => ({ key: "k", runtime: "claude", model: "m", effort: null, process: "cold", pending: 0, lastTurn: null, ...over });
const row = (over: J = {}): J => ({
  id: "k", session: "k", thread: 7, title: "部署", agents: [agent()], unread: false, mine: false, lastActiveAt: 30,
  last: { seq: 3, authorKind: "agent", author: "k", authorName: "bot", text: "好", createdAt: 30 },
  people: [{ id: "a@x", name: "Ada", email: "a@x", via: "cloud" }], archiveRecommended: false, pinned: null, ...over,
});
/// An entry as the stream tells it (GET /threads/:id/entries' shape).
const said = (n: number, authorKind: string, author: string, text: string, over: J = {}): J => ({
  thread: 7, n, kind: "message", target: null, ts: `1.${n}`, authorKind, author, text, attachments: [], quotes: [], declared: null, at: n * 10, authorName: author === "k" ? "bot" : author.toUpperCase(), ...over,
});
const summary = (over: J = {}): J => ({ key: "k", title: null, connect: "ember", createdBy: null, archivedAt: null, runtime: "claude", model: "m", effort: null, process: "cold", pending: 0, lastTurn: null, lastActiveAt: 30, ...over });

test("what was said brings a chat's row on: its latest message, unread, who wrote, how lately", () => {
  const next = rowAfterSaid(row(), [said(4, "agent", "k", "  改好了\n"), said(5, "person", "b@x", "收到")], "a@x") as J;
  assert.deepEqual(next.last, { seq: 5, authorKind: "person", author: "b@x", authorName: "B@X", text: "收到", createdAt: 50 });
  assert.deepEqual([next.unread, next.mine, next.lastActiveAt], [true, false, 50]);
  assert.deepEqual(next.people.map((p: J) => p.id), ["a@x", "b@x"]);
  // The viewer's own: not unread, and the row is theirs.
  const own = rowAfterSaid(row(), [said(4, "person", "A@x", "我来")], "a@x") as J;
  assert.deepEqual([own.unread, own.mine], [false, true]);
  // As much of it as the row says, trimmed.
  assert.equal((rowAfterSaid(row(), [said(4, "agent", "k", "长".repeat(300))], "a@x") as J).last.text, "长".repeat(200));
  // An edit of its latest message is what it says now.
  assert.equal((rowAfterSaid(row(), [{ ...said(4, "agent", "k", "好了"), kind: "edit", target: 3 }], "a@x") as J).last.text, "好了");
  // A letter changes nothing of it; what the row was read with already is no news.
  assert.equal(rowAfterSaid(row(), [said(4, "agent", "j", "信", { letter: true })], "a@x"), null);
  assert.equal(rowAfterSaid(row(), [said(3, "agent", "k", "好")], "a@x"), null);
  // The review's marks hold while the chat stands as it looked at it.
  const marked = rowAfterSaid(row({ archiveRecommended: true, archiveCheck: { option: 1 } }), [said(4, "agent", "k", "又改了")], "a@x") as J;
  assert.deepEqual([marked.archiveRecommended, "archiveCheck" in marked], [false, false]);
});

test("what only the station can say of a row is read: a card, what waits answered, someone known by other names", () => {
  assert.equal(rowAfterSaid(row(), [said(4, "agent", "k", "选一个", { card: { type: "options" } })], "a@x"), "read");
  assert.equal(rowAfterSaid(row({ card: { seq: 3 } }), [said(4, "person", "a@x", "第一个")], "a@x"), "read");
  assert.equal(rowAfterSaid(row({ need: { seq: 3 } }), [said(4, "person", "b@x", "好的")], "a@x"), "read");
  assert.equal(rowAfterSaid(row({ need: { seq: 3 } }), [{ ...said(4, "agent", "k", "改"), kind: "edit", target: 3 }], "a@x"), "read");
  assert.equal(rowAfterSaid(row(), [said(4, "person", "local", "本机")], "a@x"), "read");
  assert.equal(rowAfterSaid(row(), [said(4, "agent", "k", " ", { quotes: [{ author: "x", text: "y", comment: "" }] })], "a@x"), "read");
  // An agent saying more while its need waits: the need stands.
  assert.notEqual(rowAfterSaid(row({ need: { seq: 3 } }), [said(4, "agent", "k", "还在等")], "a@x"), "read");
});

test("a session's summary brings its agent in a row on; what changes which rows there are is read", () => {
  const next = rowAfterSession(row(), summary(), summary({ process: "running", pending: 2, model: "n", watch: { every: 60 } })) as J;
  assert.deepEqual(next.agents, [agent({ process: "running", pending: 2, model: "n", watch: { every: 60 } })]);
  assert.equal(rowAfterSession(row(), summary(), summary()), null, "nothing of it changed");
  // A row with no chat yet is as active as its session.
  assert.equal((rowAfterSession(row({ thread: null }), summary(), summary({ lastActiveAt: 90 })) as J).lastActiveAt, 90);
  assert.equal(rowAfterSession(row(), summary(), summary({ archivedAt: 5 })), "read");
  assert.equal(rowAfterSession(row(), summary(), summary({ title: "新名" })), "read");
  const asks = { ending: "need_help", startedAt: 1, endedAt: 2 };
  assert.equal(rowAfterSession(row(), summary(), summary({ lastTurn: asks })), "read", "its need is the station's to say");
  assert.equal(rowAfterSession(row(), summary({ lastTurn: asks }), summary({ lastTurn: { ending: "all_done" } })), "read");
  assert.notEqual(rowAfterSession(row(), summary(), summary({ lastTurn: { ending: "all_done" } })), "read");
});

test("what the viewer pinned, dismissed or kept, in place", () => {
  assert.equal((rowAfterPin(row(), 9) as J).pinned, 9);
  assert.equal(rowAfterPin(row({ pinned: 9 }), 9), null);
  const waiting = row({ card: { seq: 5, card: {} }, decision: { seq: 5, options: [] } });
  const dismissed = rowAfterDismiss(waiting, 5) as J;
  assert.deepEqual([dismissed.card.dismissed, dismissed.decision.dismissed], [true, true]);
  assert.equal(rowAfterDismiss(waiting, 4), null);
  assert.equal((rowAfterKept(row(), true) as J).archiveReminderDismissed, true);
});
