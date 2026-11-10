// What a station leaves to the client to say (station/src/read: it gives no words of its own any more), said here in
// this device's language: a chat's name by what names it and a last message that only quotes (chat-row.ts `worded`),
// the local page's admin as an author, a refusal given by the key of its words, a call's result in its script's output.
import assert from "node:assert/strict";
import { test } from "node:test";
import { worded } from "../src/chat-row.ts";
import { authorNameOf } from "../src/entries.ts";
import { presentHistory } from "../src/history.ts";
import { setCurrent, t } from "../src/i18n.ts";
import { httpError } from "../src/station/requests.ts";

const words = { untitled: "New chat", directMessage: "Direct message", quotedOnly: "Quoted a message", admin: "Admin" };

test("a station's row in the client's words: named by what names it, a quote-only last message and the local admin said", () => {
  const row = {
    id: "k", title: "", named: { thread: { surface: "ember", channel: "CHAT", title: null, autoTitle: null }, firstText: null, channelName: null },
    last: { seq: 1, authorKind: "person", author: "local", authorName: null, text: "", quotedOnly: true },
  };
  assert.deepEqual(worded(row, words), { id: "k", title: "New chat", last: { seq: 1, authorKind: "person", author: "local", authorName: "Admin", text: "Quoted a message" } });
  // A Slack direct message with nothing said, a thread named by its first line, a given name.
  const dm = { title: "", named: { thread: { surface: "slack:T", channel: "D1", title: null, autoTitle: null }, firstText: null, channelName: null } };
  assert.equal(worded(dm, words).title, "Direct message");
  const first = { title: "", named: { thread: { surface: "slack:T", channel: "C1", title: null, autoTitle: null }, firstText: "<@U1> deploy  it\nmore", channelName: null } };
  assert.equal(worded(first, words).title, "deploy it");
  assert.equal(worded({ title: "", named: { thread: { surface: "ember", title: " Plan ", autoTitle: null } } }, words).title, "Plan");
  // A row a station from before worded itself: as it is.
  const before = { id: "k", title: "新对话", last: { author: "x", authorKind: "person", authorName: "Ann", text: "hi" } };
  assert.deepEqual(worded(before, words), before);
});

test("the local page's admin is named here; anyone a station names, as it names them", () => {
  setCurrent("en");
  assert.equal(authorNameOf("person", "local", null), t("station.author.admin"));
  assert.equal(authorNameOf("person", "local", "Named"), "Named");
  assert.equal(authorNameOf("agent", "local", null), null);
  assert.equal(authorNameOf("person", "ann@x", null), null);
});

test("a refusal by the key of its words is said in this device's language; any other as the station said it", () => {
  setCurrent("zh");
  assert.equal(httpError(403, { error: "station.files.outside" }).message, t("station.files.outside"));
  assert.notEqual(t("station.files.outside"), "station.files.outside");
  assert.equal(httpError(400, { error: "after must be an integer" }).message, "after must be an integer");
  setCurrent("en");
  assert.equal(httpError(404, { error: "station.files.notFound" }).message, "No such file");
});

test("a call's result in its script's output is said in this device's words", () => {
  setCurrent("en");
  const h = presentHistory({ timeline: [
    { kind: "tool_call", text: "{}", tool: "shell", callId: "e1#0" },
    { kind: "tool_result", text: "", ok: true, callId: "e1#0", inScript: true },
  ] }, { threads: [], members: [], slack: [], stations: new Map() } as never);
  assert.ok(JSON.stringify(h).includes(t("station.transcript.inScriptOutput")));
});
