import assert from "node:assert/strict";
import { test } from "node:test";
import { dockItems } from "../apps/desktop/src/dock.mts";

const row = (over: Record<string, unknown>) => ({
  id: "s1", session: "s1", thread: 7, title: "官网首屏改版", station: "w1/st1", stationName: "studio", unread: true, tone: "done",
  lastActiveAt: 1000, last: { seq: 12, text: "改好了，\n截图在这", preview: "改好了", createdAt: 1000, by: { name: "Claude" } }, ...over,
});
const chats = (...items: unknown[]) => ({ days: [{ items }] });

test("an unread chat: its newest message, who said it, and where to open and read it", () => {
  const [one, ...rest] = dockItems("w1", chats(row({})), undefined);
  assert.equal(rest.length, 0);
  assert.deepEqual(one!.item, { id: "w1/st1|s1", key: "w1/st1|s1#12done", title: "官网首屏改版", station: "studio", tone: "done", who: "Claude", text: "改好了， 截图在这", at: 1000 });
  assert.deepEqual(one!.place, { url: "/o/w1/st1/s1", station: "w1/st1", thread: 7, seq: 12 });
});

test("failed shows read or not; at work, or read and fine, does not", () => {
  const items = dockItems("w1", chats(row({ id: "a", session: "a", tone: "alert", unread: false }), row({ id: "b", session: "b", tone: "busy", unread: false }), row({ id: "c", session: "c", tone: undefined, unread: false })), undefined);
  assert.deepEqual(items.map((i) => [i.item.id, i.item.tone]), [["w1/st1|a", "alert"]]);
});

test("a card waiting on the person: its question and options to answer there, in place of the chat's row", () => {
  const decisions = { items: [
    { station: "w1/st1", stationName: "studio", session: "s1", thread: 7, seq: 30, title: "奏页空状态", question: "按哪种算？", text: "奏 · 按哪种算？",
      options: [{ label: "按最近 7 天" }, { label: "按今天累计", recommended: true }], card: { type: "options" }, message: { createdAt: 2000, by: { name: "Claude" }, text: "两种算法差挺多。" } },
    { station: "w1/st1", session: "s9", thread: 9, seq: 3, title: "aside", deferred: true, options: [] },
  ] };
  const items = dockItems("w1", chats(row({ tone: "wait" })), decisions);
  assert.equal(items.length, 1);
  assert.deepEqual(items[0]!.item, {
    id: "w1/st1|s1", key: "w1/st1|s1#card30", title: "奏页空状态", station: "studio", tone: "wait", who: "Claude", text: "两种算法差挺多。",
    ask: "按哪种算？", options: [{ label: "按最近 7 天" }, { label: "按今天累计", recommended: true }], at: 2000,
  });
  assert.deepEqual(items[0]!.place, { url: "/o/w1/st1/s1", station: "w1/st1", thread: 7, card: 30 });
});

test("a session with characters a path cannot hold is encoded", () => {
  const [one] = dockItems("w1", chats(row({ id: "a/b c", session: "a/b c" })), undefined);
  assert.equal(one!.place.url, "/o/w1/st1/a%2Fb%20c");
});
