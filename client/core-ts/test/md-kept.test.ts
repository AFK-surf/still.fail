// What agents said, read once on the device (markdown.ts, md-ahead.ts): a chat opened keeps its replies' trees in its
// account's database (read from there as the app starts anew, not again); the latest replies of a chat are read ahead
// as they come, however long ago they were said, before it is opened (a chat opens by looking up what it shows:
// chat-open-lookup.test.ts); a person's words and a reply with a Slack person in it are not.
import assert from "node:assert/strict";
import { test } from "node:test";
import { mdKey, parse } from "../src/markdown.ts";
import type { FakeHost } from "../src/testing.ts";
import { subscribe } from "./helpers.ts";
import { base, entry, started, threadView } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The test's clock as it starts (testing.ts TestTime).
const START = Date.UTC(2026, 9, 6, 9, 0, 0);

const reply = (n: number, text: string, at: number, authorKind = "agent") => ({ thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind, author: authorKind === "agent" ? "k1" : "a@x.com", text, at });

/// The trees kept, by key: what they were read for.
function kept(host: FakeHost): Map<string, string> {
  for (const sql of host.sqls.values()) {
    if (sql.all("SELECT 1 FROM sqlite_master WHERE name = 'md_kept'").length === 0) continue;
    return new Map(sql.all("SELECT key, of FROM md_kept").map((r) => [String(r[0]), String(r[1])]));
  }
  return new Map();
}

test("a_chat_opened_keeps_its_agents_markdown_read_on_the_device", async () => {
  const text = `改好了：**列表** 和 \`按钮\` ${Math.random()}`;
  const answers = { ...base(), "GET /threads/7/entries?limit=50": { last: 3, entries: [entry(1, "m1"), entry(2, "m2"), reply(3, text, 3)] } };
  const { host, core } = await started(answers);
  // Said long ago, read as it came (and kept): there as the chat opens.
  assert.equal(kept(host).get(mdKey(text)), "t:7");
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  await host.settle();
  const value = host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === 1 && "value" in m)?.value;
  assert.deepEqual(value?.messages?.find((m: J) => m.seq === 3)?.md, parse(text));
  assert.equal(kept(host).get(mdKey(text)), "t:7");
  core.close();
});

test("a_chats_latest_replies_are_read_ahead_as_they_come_however_long_ago_said", async () => {
  const recent = `刚才的 **回复** ${Math.random()}`;
  const mention = `<@U1> 看一下 **这个** ${Math.random()}`;
  const person = `人说的 **话** ${Math.random()}`;
  const old = `很久以前的 **回复** ${Math.random()}`;
  const answers = {
    ...base(),
    "GET /threads": [threadView(7, 4)],
    "GET /threads/7/entries?limit=50": { last: 4, entries: [reply(1, old, START - 10 * 86_400_000), reply(2, person, START - 1000, "person"), reply(3, mention, START - 1000), reply(4, recent, START - 1000)] },
  };
  const { host, core } = await started(answers);
  await host.time.pass(100);
  const read = kept(host);
  assert.deepEqual([recent, mention, person, old].map((t) => read.get(mdKey(t)) ?? null), ["t:7", null, null, "t:7"]);
  core.close();
});
