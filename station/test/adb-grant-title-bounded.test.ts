import assert from "node:assert/strict";
import { test } from "node:test";
import { grantChatTitle } from "../src/adb/title.ts";
import type { PhoneRequest } from "../src/adb/grants.ts";
import { Store } from "../src/store/store.ts";

test("a phone grant's known chat name does not read the session's other chats", () => {
  const store = Store.open(":memory:");
  try {
    const known = store.openThread("ember", "EMBER", "own", "Own title", null);
    store.joinThread(known.id, "s", "ember");
    const request: PhoneRequest = { id: "p", session: "s", chat: "EMBER/own", owner: "person@example.test", reason: "test", at: 0, status: "pending" };
    let calls = 0;
    const real = store.sessionChat.bind(store);
    store.sessionChat = (session) => { calls++; return real(session); };
    for (const count of [40, 400]) {
      for (let n = 0; n < count - (count === 400 ? 40 : 0); n++) {
        const thread = store.openThread("slack", "C", `${count}-${n}`, null, null);
        store.joinThread(thread.id, "s", "slack");
      }
      assert.equal(grantChatTitle(store, request), "Own title");
      assert.equal(calls, 0, "a given name does not depend on which chat was said in last");
    }
  } finally { store.close(); }
});

test("an unnamed surface chat uses its first words only when it is the latest", () => {
  const store = Store.open(":memory:");
  try {
    const own = store.openThread("slack", "C", "own", null, null);
    const other = store.openThread("slack", "C", "other", null, null);
    store.joinThread(own.id, "s", "slack");
    store.joinThread(other.id, "s", "slack");
    const request: PhoneRequest = { id: "p", session: "s", chat: "C/own", owner: "person@example.test", reason: "test", at: 0, status: "pending" };
    let calls = 0, latest = own;
    store.firstText = () => "The first words";
    store.sessionChat = () => { calls++; return { thread: latest, firstText: "The first words" }; };
    assert.equal(grantChatTitle(store, request), "The first words");
    latest = other;
    assert.notEqual(grantChatTitle(store, request), "The first words");
    assert.equal(calls, 2);
    store.firstText = () => null;
    grantChatTitle(store, request);
    assert.equal(calls, 2, "without first words the name no longer depends on the latest chat");
  } finally { store.close(); }
});
