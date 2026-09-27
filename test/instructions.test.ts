import assert from "node:assert/strict";
import { test } from "node:test";
import { formatInbound } from "../src/instructions.ts";
import { EMBER_SURFACE, type PendingMessage } from "../src/store.ts";

const message = (patch: Partial<PendingMessage>): PendingMessage => ({
  thread: 1, n: 1, ts: "100.0", authorKind: "person", author: "a@x.com", text: "hi", attachments: [], quotes: [],
  declared: null, createdAt: 1, editedAt: null, surface: "slack:T1", channel: "C1", threadTs: "100.0", connect: "c1", ...patch,
});

const hinted = (m: PendingMessage) => /had messages before you were brought in/.test(formatInbound([m], { newThreads: new Set([m.thread]) }));

test("a thread new to the session is said to have earlier messages only when it has them", () => {
  // A chat on ember's page: its id is its own, apart from its first message's; its first message has none before it.
  assert.equal(hinted(message({ surface: EMBER_SURFACE, channel: "EMBER", threadTs: "99.5", ts: "100.2" })), false);
  assert.equal(hinted(message({ surface: EMBER_SURFACE, channel: "EMBER", threadTs: "99.5", ts: "100.2", n: 3 })), true);
  // Slack: a thread's first message has none; a reply does, whether ember saw them or not.
  assert.equal(hinted(message({})), false);
  assert.equal(hinted(message({ ts: "101.0" })), true);
});
