// A thread's summary brought on by what its station's stream says was said in it (station/thread-after.ts), as the
// station makes it (station/src/read/sessions.ts `thread`): how far it goes, its latest message, what the viewer has not
// read, who wrote in it; and where it cannot be said here.
import assert from "node:assert/strict";
import { test } from "node:test";
import { threadAfter, threadAfterLetters } from "../src/station/thread-after.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const held = (over: J = {}): J => ({
  id: 7, surface: "ember", channel: "EMBER", threadTs: "1.1", title: null, createdBy: "a@x", createdAt: 1, sessions: [],
  last: 3, read: 3, unread: 0, people: [{ id: "a@x", name: "Ada", email: "a@x", via: "cloud" }], firstText: "看一下",
  lastMessage: { agentIdentity: null, seq: 3, thread: 7, ts: "1.3", authorKind: "agent", author: "k", authorName: "bot", text: "好", attachments: [], quotes: [], declared: null, createdAt: 30, editedAt: null },
  ...over,
});
/// An entry as the stream tells it (GET /threads/:id/entries' shape).
const said = (n: number, authorKind: string, author: string, text: string, over: J = {}): J => ({
  thread: 7, n, kind: "message", target: null, ts: `1.${n}`, authorKind, author, text, attachments: [], quotes: [], declared: null, at: n * 10, authorName: author === "k" ? "bot" : author.toUpperCase(), ...over,
});

test("what was said after it brings a thread's summary on: its last entry, its latest message, what its viewer has not read", () => {
  const next = threadAfter(held(), [said(4, "agent", "k", "改好了", { declared: "final", ending: "all_done" }), said(5, "person", "b@x", "收到")], "a@x")!;
  assert.equal(next.last, 5);
  assert.equal(next.unread, 2, "the agent's and b@x's, after where a@x read");
  assert.deepEqual(next.lastMessage, { agentIdentity: null, seq: 5, thread: 7, ts: "1.5", authorKind: "person", author: "b@x", authorName: "B@X", text: "收到", attachments: [], quotes: [], declared: null, createdAt: 50, editedAt: null });
  assert.deepEqual(next.people.map((p: J) => p.id), ["a@x", "b@x"], "who wrote, the first time each did");
  assert.equal(next.firstText, "看一下", "the first thing a person said, as it was");
  // The viewer's own: not unread; an agent's, ended: its ending kept.
  const mine = threadAfter(held(), [said(4, "person", "A@x", "我来"), said(5, "agent", "k", "好", { declared: "final", ending: "all_done" })], "a@x")!;
  assert.equal(mine.unread, 1);
  assert.equal(mine.lastMessage.ending, "all_done");
  // An edit of the latest message is what it says now; of an earlier one, nothing of the summary.
  const edited = threadAfter(held(), [{ ...said(4, "agent", "k", "好了"), kind: "edit", target: 3 }], "a@x")!;
  assert.deepEqual([edited.last, edited.unread, edited.lastMessage.text, edited.lastMessage.editedAt, edited.lastMessage.seq], [4, 0, "好了", 40, 3]);
  // The first thing a person said, where none had.
  assert.equal(threadAfter(held({ firstText: null, people: [] }), [said(4, "person", "a@x", "看".repeat(400))], "a@x")!.firstText, "看".repeat(300));
  // What was told already is no news.
  assert.equal(threadAfter(held(), [said(3, "agent", "k", "好")], "a@x")!.unread, 0);
});

test("where a summary cannot be brought on from what was said, none is made (it is read)", () => {
  assert.equal(threadAfter(undefined, [said(4, "agent", "k", "好")], "a@x"), null, "none held");
  assert.equal(threadAfter(held(), [said(5, "agent", "k", "好")], "a@x"), null, "an entry left out before it");
  assert.equal(threadAfter(held({ surface: "slack:T1" }), [said(4, "person", "U1", "hi")], "a@x"), null, "a Slack thread: its people's other selves only its station knows");
  assert.equal(threadAfter(held(), [said(4, "person", "local", "hi")], "a@x"), null, "the station's own page's person");
});

test("letters coming in its own log of them bring on how many it has and how far that goes", () => {
  assert.deepEqual(threadAfterLetters(held({ letters: 3, lettersLast: 1 }), [{ n: 2 }, { n: 3 }]), { ...held(), letters: 5, lettersLast: 3 });
  assert.deepEqual(threadAfterLetters(held(), [{ n: 1 }]), { ...held(), letters: 1, lettersLast: 1 });
  assert.equal(threadAfterLetters(held({ lettersLast: 1 }), [{ n: 3 }]), null, "one left out before it");
});
