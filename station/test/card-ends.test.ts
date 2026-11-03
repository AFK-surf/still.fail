// A card that stops waiting changes where its thread's platform shows it (connects/card-ends.ts): the connect's
// surface is told its post, its card and why; a station chat's, or a surface without cards, is not.
import assert from "node:assert/strict";
import { test } from "node:test";
import { type CardEnd, showEnded } from "../src/connects/card-ends.ts";
import type { ChatSurface, ThreadRef } from "../src/sessions/chat.ts";
import { newMessage } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

function rig(surface: string) {
  const store = Store.open(":memory:", null);
  store.insertSession({ key: "a", connect: "ds", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThread(surface, "C1", "1.1", null, null);
  store.joinThread(thread.id, "a", "ds");
  const told: [ThreadRef, string, string, CardEnd][] = [];
  const chat = { cards: true, cardEnded: async (at: ThreadRef, ts: string, text: string, _card: unknown, end: CardEnd) => void told.push([at, ts, text, end]) } as unknown as ChatSurface;
  const asked: string[] = [];
  const stop = store.subscribe((change) => showEnded(store, (connect) => (asked.push(connect), chat), change));
  return { store, thread, told, asked, stop };
}

test("a card a person's message closed is changed where its connect shows it", () => {
  const r = rig("slack:T1");
  try {
    r.store.insertMessage({ ...newMessage(r.thread.id, "1.2", "agent", "a", "合并吗？"), card: { type: "options", options: [{ label: "合并" }] } });
    assert.deepEqual(r.told, []);
    r.store.insertMessage(newMessage(r.thread.id, "1.3", "person", "U1", "等等"));
    assert.deepEqual(r.told, [[{ channel: "C1", threadTs: "1.1" }, "1.2", "合并吗？", { why: "message", by: "U1", byTs: "1.3" }]]);
    assert.ok(r.asked.every((c) => c === "ds"));
  } finally {
    r.stop();
    r.store.close();
  }
});

test("a station chat's cards are the app's alone: no surface is asked", () => {
  const r = rig("ember");
  try {
    r.store.insertMessage({ ...newMessage(r.thread.id, "1.2", "agent", "a", "合并吗？"), card: { type: "options", options: [{ label: "合并" }] } });
    r.store.insertMessage(newMessage(r.thread.id, "1.3", "person", "U1", "等等"));
    assert.deepEqual([r.told, r.asked], [[], []]);
  } finally {
    r.stop();
    r.store.close();
  }
});
