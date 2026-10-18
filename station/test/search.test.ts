// The station's search index (docs/search.md): what the station's data puts in it, what a query finds there for whom,
// and what is indexed again as the data changes.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { Store, newMessage } from "../src/store/store.ts";
import { openStore } from "../src/read/store.ts";
import { type Asker, SearchIndex, excerpt, terms } from "../src/search/index.ts";
import { jobDocs, memoryDocs, profileDocs, profilesOf, threadDocs } from "../src/search/sources.ts";

const dirs: string[] = [];
const closing: { close(): void }[] = [];
after(() => {
  for (const c of closing) {
    try {
      c.close();
    } catch {}
  }
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function station() {
  const data = mkdtempSync(join(tmpdir(), "search-test-"));
  dirs.push(data);
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  closing.push(store);
  const index = new SearchIndex(join(data, "search.db"));
  closing.push(index);
  return { data, store, index, read: () => openStore(data) };
}

const home: Asker = { workspace: "W1", home: true, scopes: ["write"] };
const other: Asker = { workspace: "W2", home: false, scopes: ["write"] };

function chat(store: Store, key: string, ws: string | null) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1, ws });
  const thread = store.openThreadOf("ember", "ember", key, null, "a@x", key);
  store.joinThread(thread.id, key, "ember");
  return thread.id;
}

const say = (store: Store, thread: number, ts: string, text: string, kind: "person" | "agent" = "person") => store.insertMessage(newMessage(thread, ts, kind, kind === "person" ? "a@x" : "agent", text))[0];

const index = (s: ReturnType<typeof station>, thread: number) => {
  const read = s.read();
  const found = threadDocs(read, thread, s.index.mark(`t:${thread}`))!;
  if (found.whole) s.index.replace(`t:${thread}`, found.version, found.docs);
  else s.index.tx(() => {
    for (const d of found.docs) s.index.put(d);
    s.index.setMark(`t:${thread}`, found.version);
  });
  read.db.close();
  return found;
};

const kinds = (groups: { kind: string; hits: { key: string }[] }[]) => Object.fromEntries(groups.map((g) => [g.kind, g.hits.map((h) => h.key)]));

test("a chat's messages are found by any part of their words, in any script, case aside", () => {
  const s = station();
  const t = chat(s.store, "k1", null);
  say(s.store, t, "1", "我们用 DuckDB 做分析");
  say(s.store, t, "2", "sqlite 的全文索引", "agent");
  index(s, t);
  // The chat too: it is called by what was first said in it.
  assert.deepEqual(kinds(s.index.search("duckdb", home)), { chat: [`c:${t}`], message: [`m:${t}:1`] });
  assert.deepEqual(kinds(s.index.search("uckD", home, { kinds: ["message"] })), { message: [`m:${t}:1`] });
  // Two characters have no trigram: looked for in the text.
  assert.deepEqual(kinds(s.index.search("索引", home)), { message: [`m:${t}:2`] });
  // Every word must be there.
  assert.deepEqual(kinds(s.index.search("duckdb 索引", home)), {});
  const [hit] = s.index.search("duckdb", home, { kinds: ["message"] })[0]!.hits;
  assert.equal(hit!.chat, "k1");
  assert.equal(hit!.seq, 1);
  assert.equal(hit!.text, "我们用 DuckDB 做分析");
});

test("a member of another workspace finds nothing of this one's chats", () => {
  const s = station();
  const mine = chat(s.store, "k1", null);
  const theirs = chat(s.store, "k2", "W2");
  say(s.store, mine, "1", "deploy the station");
  say(s.store, theirs, "1", "deploy the cloud");
  index(s, mine);
  index(s, theirs);
  assert.deepEqual(kinds(s.index.search("deploy", home)).message, [`m:${mine}:1`]);
  assert.deepEqual(kinds(s.index.search("deploy", other)).message, [`m:${theirs}:1`]);
});

test("a thread is indexed again from where it was: what was said since, and what an edit changed", () => {
  const s = station();
  const t = chat(s.store, "k1", null);
  say(s.store, t, "1", "first words");
  assert.equal(index(s, t).whole, true);
  say(s.store, t, "2", "second words");
  s.store.editMessage("ember", "ember", "k1", "1", "first edited");
  const again = index(s, t);
  assert.equal(again.whole, false);
  assert.deepEqual(again.docs.map((d) => d.key).sort(), [`c:${t}`, `m:${t}:1`, `m:${t}:2`]);
  assert.deepEqual(kinds(s.index.search("edited", home)).message, [`m:${t}:1`]);
  assert.deepEqual(kinds(s.index.search("first words", home)), {});
  // Nothing new: nothing written.
  assert.deepEqual(index(s, t).docs.filter((d) => d.kind === "message"), []);
});

test("those whose title has the words come first, then the newest", () => {
  const s = station();
  s.index.replace("x", "1", [
    { key: "a", kind: "skill", source: "x", ws: null, title: "deploy notes", body: "old", at: 1, ref: {} },
    { key: "b", kind: "skill", source: "x", ws: null, title: "other", body: "how to deploy", at: 3, ref: {} },
    { key: "c", kind: "skill", source: "x", ws: null, title: "another", body: "deploy again", at: 2, ref: {} },
  ]);
  assert.deepEqual(kinds(s.index.search("deploy", home)).skill, ["a", "b", "c"]);
  const [group] = s.index.search("deploy", home, { limit: 2 });
  assert.equal(group!.more, true);
  assert.deepEqual(group!.hits.map((h) => h.key), ["a", "b"]);
  assert.deepEqual(s.index.search("deploy", home, { limit: 2, offset: 2 })[0]!.hits.map((h) => h.key), ["c"]);
});

test("what only a member who may write reaches is not found by a read-only one", () => {
  const s = station();
  s.index.replace("f", "1", [{ key: "f:1", kind: "file", source: "f", ws: "*", scope: "write", title: "plan.md", body: "", at: 1, ref: {} }]);
  assert.deepEqual(kinds(s.index.search("plan", home)).file, ["f:1"]);
  assert.deepEqual(kinds(s.index.search("plan", { ...home, scopes: [] })), {});
});

test("skills, memory, jobs and profiles are found", () => {
  const s = station();
  const agent = join(s.data, "agent");
  mkdirSync(join(agent, "skills/deploy"), { recursive: true });
  writeFileSync(join(agent, "MEMORY.md"), "the studio has 64 GB\n");
  writeFileSync(join(agent, "skills/deploy/SKILL.md"), "---\nname: deploy\ndescription: 项目记忆：how releases go out\n---\nrun release.sh\n");
  s.index.replace("k:", "1", memoryDocs(s.data, null).docs);
  const key = "k1";
  chat(s.store, key, null);
  s.store.insertJob({ id: "j1", sessionKey: key, name: "web preview", command: "pnpm dev --port 5173", cwd: "/w/k1", port: 5173, token: "t", state: "running", pgid: null, exitCode: null, startedAt: 5, endedAt: null, restarts: 0, log: "", watch: false });
  const read = s.read();
  s.index.replace(`j:${key}`, "1", jobDocs(read, key).docs);
  read.db.close();
  s.index.replace("p", "1", profileDocs(profilesOf({ profiles: [{ id: "studio-max", home: "p/cc", runtime: "claude", model: "claude-opus-5-5" }] }, s.data)).docs);
  assert.deepEqual(kinds(s.index.search("releases", home)), { skill: ["k::deploy"] });
  assert.deepEqual(kinds(s.index.search("64 GB", home)), { memory: ["k::"] });
  assert.deepEqual(kinds(s.index.search("5173", home)), { job: ["j:j1"] });
  assert.deepEqual(kinds(s.index.search("opus", other)), { profile: ["p:studio-max"] });
});

test("a query's words, and the part of a text that has them", () => {
  assert.deepEqual(terms("  Deploy  deploy STUDIO "), ["deploy", "studio"]);
  const long = `${"a ".repeat(100)}needle ${"b ".repeat(200)}`;
  const part = excerpt(long, ["needle"]);
  assert.ok(part.startsWith("…") && part.endsWith("…") && part.includes("needle"), part);
});

test("the station's index thread keeps up with its store, and answers as it does", async () => {
  const { Search } = await import("../src/search/search.ts");
  const s = station();
  const t = chat(s.store, "k1", null);
  say(s.store, t, "1", "before the start");
  const search = new Search({ data: s.data, store: s.store });
  search.start();
  try {
    assert.equal((await search.flushed()).building, false);
    assert.deepEqual(kinds((await search.query("before", home, { kinds: ["message"] })).groups), { message: [`m:${t}:1`] });
    // Said after: told by the store, indexed in the background.
    say(s.store, t, "2", "after the start");
    await search.flushed();
    assert.deepEqual(kinds((await search.query("after", home, { kinds: ["message"] })).groups), { message: [`m:${t}:2`] });
    // Deleted: found no more.
    s.store.deleteSession("k1");
    await search.flushed();
    assert.deepEqual((await search.query("after", home)).groups, []);
  } finally {
    await search.stop();
  }
});

test("an execution history is found, grown from where it was, and one that stopped the index's thread is passed over until it changes", async () => {
  const { historyDocs, READING, FAILED, Readings } = await import("../src/search/sources.ts");
  const { appendFileSync } = await import("node:fs");
  const s = station();
  const key = "k1";
  chat(s.store, key, null);
  s.store.setRuntimeSessionId(key, "rs1");
  const home = join(s.data, "p");
  mkdirSync(join(home, "projects", "w"), { recursive: true });
  const file = join(home, "projects", "w", "rs1.jsonl");
  const said = (text: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-18T08:00:00Z", message: { content: [{ type: "text", text }] } })}\n`;
  writeFileSync(file, said("先跑 pnpm run deploy"));
  const profiles = [{ id: "cc", home, runtime: "claude" }];
  const read = s.read();
  const first = (await historyDocs(read, key, profiles, null))!;
  assert.deepEqual(first.docs.map((d) => [d.key, d.body]), [[`h:${key}:0`, "先跑 pnpm run deploy"]]);
  appendFileSync(file, said("deploy 完了"));
  const grown = (await historyDocs(read, key, profiles, first.version))!;
  assert.equal(grown.whole, false);
  assert.deepEqual(grown.docs.map((d) => d.key), [`h:${key}:1`]);
  // Its reading stopped the thread: passed over, until the file changes.
  const failed = (await historyDocs(read, key, profiles, READING))!;
  assert.ok(failed.version.startsWith(FAILED));
  assert.deepEqual(failed.docs, []);
  assert.deepEqual((await historyDocs(read, key, profiles, failed.version))!.docs, []);
  appendFileSync(file, said("again"));
  assert.equal((await historyDocs(read, key, profiles, failed.version))!.docs.length, 3);
  // Read on from where it was read to: only what was added is read, at the index it has in the whole.
  const readings = new Readings();
  let whole = 0;
  const all = (await historyDocs(read, key, profiles, null, () => whole++, readings))!;
  appendFileSync(file, said("one more deploy"));
  const more = (await historyDocs(read, key, profiles, all.version, () => whole++, readings))!;
  assert.equal(whole, 1);
  assert.deepEqual(more.docs.map((d) => [d.key, d.body]), [[`h:${key}:3`, "one more deploy"]]);
  // Numbered as the history page numbers them (GET /sessions/:key/timeline).
  const { readTimeline } = await import("../src/read/transcript.ts");
  assert.equal(JSON.parse(more.version).n, readTimeline("claude", file).length);
  read.db.close();
});
