import assert from "node:assert/strict";
import { test } from "node:test";
import { grantChatTitle } from "../src/adb/title.ts";
import type { PhoneRequest } from "../src/adb/grants.ts";
import { titleOf } from "../src/read/views.ts";
import { Store } from "../src/store/store.ts";

test("a phone grant's known chat name does not read the session's other chats", () => {
  const store = Store.open(":memory:");
  try {
    const known = store.openThread("ember", "EMBER", "own", "Own title", null);
    store.joinThread(known.id, "s", "ember");
    const request: PhoneRequest = { id: "p", session: "s", chat: "CHAT/own", owner: "person@example.test", reason: "test", at: 0, status: "pending" };
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

test("grant names keep the same results for both surfaces and missing original chats", () => {
  const store = Store.open(":memory:");
  try {
    const own = store.openThread("ember", "EMBER", "own", null, null);
    const named = store.openThread("slack", "C", "named", "A given title", null);
    const unnamed = store.openThread("slack", "C", "unnamed", null, null);
    for (const thread of [own, named, unnamed]) store.joinThread(thread.id, "s", thread.surface);
    const request: PhoneRequest = { id: "p", session: "s", chat: "", owner: "person@example.test", reason: "test", at: 0, status: "pending" };
    const cases = [
      { thread: own, first: "words", latest: unnamed, look: false },
      { thread: named, first: "words", latest: unnamed, look: false },
      { thread: unnamed, first: null, latest: named, look: false },
      { thread: unnamed, first: "<@U123>", latest: named, look: false },
      { thread: unnamed, first: "first words", latest: named, look: true },
      { thread: unnamed, first: "first words", latest: unnamed, look: true },
    ];
    for (const { thread, first, latest, look } of cases) {
      let calls = 0;
      request.chat = `${thread.channel}/${thread.threadTs}`;
      store.firstText = () => first;
      store.sessionChat = () => { calls++; return { thread: latest, firstText: first }; };
      assert.equal(grantChatTitle(store, request), titleOf(thread, latest.id === thread.id ? first : null, null));
      assert.equal(calls, look ? 1 : 0);
    }
    request.chat = "C/missing";
    store.sessionChat = () => ({ thread: unnamed, firstText: "first words" });
    assert.equal(grantChatTitle(store, request), titleOf(unnamed, "first words", null));
    store.sessionChat = () => null;
    assert.equal(grantChatTitle(store, request), null);
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
