// The station's search (docs/search.md): what of the station's data a query finds, as it is then, and for whom.
import assert from "node:assert/strict";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { zstdCompressSync } from "node:zlib";
import { after, test } from "node:test";
import { Store, newMessage } from "../src/store/store.ts";
import { openStore } from "../src/read/store.ts";
import { type Asker, excerpt, pick, terms } from "../src/search/match.ts";
import { historyHits, profileDocs, profilesOf, stationDocs, threadDocs } from "../src/search/sources.ts";

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
  return { data, store, read: () => openStore(data) };
}

/// What the station's data finds as it is now.
function find(s: ReturnType<typeof station>, query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number } = {}) {
  const read = s.read();
  try {
    return pick(stationDocs(read, s.data, {}, options.kinds ? new Set(options.kinds) : null), terms(query), asker, options);
  } finally {
    read.db.close();
  }
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

const kinds = (groups: { kind: string; hits: { key: string }[] }[]) => Object.fromEntries(groups.map((g) => [g.kind, g.hits.map((h) => h.key)]));

test("a chat's messages are found by any part of their words, in any script, case aside, as they read now", () => {
  const s = station();
  const t = chat(s.store, "k1", null);
  say(s.store, t, "1", "我们用 DuckDB 做分析");
  say(s.store, t, "2", "sqlite 的全文索引", "agent");
  // The chat too: it is called by what was first said in it.
  assert.deepEqual(kinds(find(s, "duckdb", home)), { chat: [`c:${t}`], message: [`m:${t}:1`] });
  assert.deepEqual(kinds(find(s, "uckD", home, { kinds: ["message"] })), { message: [`m:${t}:1`] });
  assert.deepEqual(kinds(find(s, "索引", home)), { message: [`m:${t}:2`] });
  // Every word must be there.
  assert.deepEqual(kinds(find(s, "duckdb 索引", home)), {});
  const [hit] = find(s, "duckdb", home, { kinds: ["message"] })[0]!.hits;
  assert.equal(hit!.chat, "k1");
  assert.equal(hit!.seq, 1);
  assert.equal(hit!.text, "我们用 DuckDB 做分析");
  // A chat's hit says where in its title the words are.
  assert.equal(find(s, "duckdb", home, { kinds: ["chat"] })[0]!.hits[0]!.text, "我们用 DuckDB 做分析");
  // Cased letters beyond ASCII's.
  say(s.store, t, "3", "Über die ЖУРНАЛ");
  assert.deepEqual(kinds(find(s, "über журнал", home)), { message: [`m:${t}:3`] });
  // Edited: found as it reads now.
  s.store.editMessage("ember", "ember", "k1", "1", "我们改用 ClickHouse");
  assert.deepEqual(kinds(find(s, "duckdb", home, { kinds: ["message"] })), {});
  // Archived by hand: found as archived.
  s.store.setArchived("k1", true, "a@x");
  const read = s.read();
  assert.ok(threadDocs(read, t).every((d) => d.ref.archived === true));
  read.db.close();
});

test("a member of another workspace finds nothing of this one's chats", () => {
  const s = station();
  const mine = chat(s.store, "k1", null);
  const theirs = chat(s.store, "k2", "W2");
  say(s.store, mine, "1", "deploy the station");
  say(s.store, theirs, "1", "deploy the cloud");
  assert.deepEqual(kinds(find(s, "deploy", home)).message, [`m:${mine}:1`]);
  assert.deepEqual(kinds(find(s, "deploy", other)).message, [`m:${theirs}:1`]);
});

test("those whose title has the words come first, then the newest", () => {
  const docs = [
    { key: "a", kind: "skill", ws: null, title: "deploy notes", body: "old", at: 1, ref: {} },
    { key: "b", kind: "skill", ws: null, title: "other", body: "how to deploy", at: 3, ref: {} },
    { key: "c", kind: "skill", ws: null, title: "another", body: "deploy again", at: 2, ref: {} },
  ];
  assert.deepEqual(kinds(pick(docs, ["deploy"], home)).skill, ["a", "b", "c"]);
  const [group] = pick(docs, ["deploy"], home, { limit: 2 });
  assert.equal(group!.more, true);
  assert.deepEqual(group!.hits.map((h) => h.key), ["a", "b"]);
  assert.deepEqual(pick(docs, ["deploy"], home, { limit: 2, offset: 2 })[0]!.hits.map((h) => h.key), ["c"]);
});

test("what only a member who may write reaches is not found by a read-only one", () => {
  const docs = [{ key: "f:1", kind: "file", ws: "*", scope: "write", title: "plan.md", body: "", at: 1, ref: {} }];
  assert.deepEqual(kinds(pick(docs, ["plan"], home)).file, ["f:1"]);
  assert.deepEqual(kinds(pick(docs, ["plan"], { ...home, scopes: [] })), {});
});

test("skills, memory, jobs and profiles are found", () => {
  const s = station();
  const agent = join(s.data, "agent");
  mkdirSync(join(agent, "skills/deploy"), { recursive: true });
  writeFileSync(join(agent, "MEMORY.md"), "the studio has 64 GB\n");
  writeFileSync(join(agent, "skills/deploy/SKILL.md"), "---\nname: deploy\ndescription: 项目记忆：how releases go out\n---\nrun release.sh\n");
  const key = "k1";
  chat(s.store, key, null);
  s.store.insertJob({ id: "j1", sessionKey: key, name: "web preview", command: "pnpm dev --port 5173", cwd: "/w/k1", port: 5173, token: "t", state: "running", pgid: null, exitCode: null, startedAt: 5, endedAt: null, restarts: 0, log: "", watch: false });
  assert.deepEqual(kinds(find(s, "releases", home)), { skill: ["k::deploy"] });
  assert.deepEqual(kinds(find(s, "64 GB", home)), { memory: ["k::"] });
  assert.deepEqual(kinds(find(s, "5173", home)), { job: ["j:j1"] });
  const profiles = profileDocs(profilesOf({ profiles: [{ id: "studio-max", home: "p/cc", runtime: "claude", model: "claude-opus-5-5" }] }, s.data));
  assert.deepEqual(kinds(pick(profiles, ["opus"], other)), { profile: ["p:studio-max"] });
});

test("a query's words, and the part of a text that has them", () => {
  assert.deepEqual(terms("  Deploy  deploy STUDIO "), ["deploy", "studio"]);
  const long = `${"a ".repeat(100)}needle ${"b ".repeat(200)}`;
  const part = excerpt(long, ["needle"]);
  assert.ok(part.startsWith("…") && part.endsWith("…") && part.includes("needle"), part);
});

test("the station's search thread finds what the store has as it is asked; the index of before is let go", async () => {
  const { Search } = await import("../src/search/search.ts");
  const s = station();
  writeFileSync(join(s.data, "search.db"), "an index of before");
  const t = chat(s.store, "k1", null);
  say(s.store, t, "1", "before the start");
  const search = new Search({ data: s.data });
  search.start();
  try {
    assert.equal(existsSync(join(s.data, "search.db")), false);
    assert.deepEqual(kinds((await search.query("before", home, { kinds: ["message"] })).groups), { message: [`m:${t}:1`] });
    say(s.store, t, "2", "after the start");
    assert.deepEqual(kinds((await search.query("after", home, { kinds: ["message"] })).groups), { message: [`m:${t}:2`] });
    s.store.deleteSession("k1");
    assert.deepEqual((await search.query("after", home)).groups, []);
  } finally {
    await search.stop();
  }
});

test("an execution history is looked through as it is: newest first, numbered as its page numbers it, a file put away too", async () => {
  const s = station();
  const key = "k1";
  const t = chat(s.store, key, null);
  s.store.setRuntimeSessionId(key, "rs1");
  const p = join(s.data, "p");
  mkdirSync(join(p, "projects", "w"), { recursive: true });
  const file = join(p, "projects", "w", "rs1.jsonl");
  const said = (text: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-18T08:00:00Z", message: { content: [{ type: "text", text }] } })}\n`;
  writeFileSync(file, said("先跑 pnpm run deploy"));
  appendFileSync(file, said('deploy 完了, "quoted" too'));
  appendFileSync(file, said("nothing here"));
  const profiles = [{ id: "cc", home: p, runtime: "claude" }];
  const now = () => 0;
  const read = s.read();
  const look = (q: string, asker: Asker = home, limit = 5) => historyHits(read, profiles, terms(q), asker, { limit, offset: 0, ms: 10_000, now });
  const found = await look("deploy");
  assert.deepEqual(found.hits.map((h) => h.key), [`h:${key}:1`, `h:${key}:0`]);
  assert.deepEqual([found.hits[0]!.chat, found.hits[0]!.thread], [key, t]);
  assert.equal((await look("deploy", home, 1)).more, true);
  // As JSON writes it, and in Chinese.
  assert.deepEqual((await look('"quoted"')).hits.map((h) => h.key), [`h:${key}:1`]);
  assert.deepEqual((await look("完了")).hits.map((h) => h.key), [`h:${key}:1`]);
  assert.deepEqual((await look("deploy nowhere")).hits, []);
  // Another workspace's member sees none of it.
  assert.deepEqual((await look("deploy", other)).hits, []);
  // Numbered as the history page numbers them (GET /sessions/:key/timeline).
  const { readTimeline } = await import("../src/read/transcript.ts");
  assert.equal(readTimeline("claude", file)[1]!.text, 'deploy 完了, "quoted" too');
  // Put away: read decompressed.
  writeFileSync(`${file}.zst`, zstdCompressSync(readFileSync(file)));
  rmSync(file);
  assert.deepEqual((await look("deploy")).hits.map((h) => h.key), [`h:${key}:1`, `h:${key}:0`]);
  // Out of time: what was found, and how many sessions were not looked through.
  const late = await historyHits(read, profiles, ["deploy"], home, { limit: 5, offset: 0, ms: -1, now });
  assert.deepEqual([late.hits, late.left], [[], 1]);
  read.db.close();
});

test("the machine's files are found as the drive lends them: not the station's own, the person's own only when said, a read-only member only in what is pinned", async () => {
  const { FileSearch, spotlightQuery } = await import("../src/search/files.ts");
  const home = mkdtempSync(join(tmpdir(), "search-files-"));
  dirs.push(home);
  const made = (rel: string) => {
    const path = join(home, rel);
    mkdirSync(join(path, ".."), { recursive: true });
    writeFileSync(path, "x");
    return path;
  };
  const plan = made("work/plan.md");
  const old = made("notes/old plan.txt");
  const own = made(".stillfail/plan.json");
  const mail = made("Library/Mail/plan.emlx");
  const asked: [string, string[]][] = [];
  let personal = false;
  const files = new FileSearch({
    home, protect: () => [join(home, ".stillfail")], roots: (ws) => (ws === null ? [join(home, "work")] : []), personal: () => personal,
    spotlight: async (query, within) => {
      asked.push([query, within]);
      return [plan, old, own, mail];
    },
  });
  const writer = { workspace: "W1", home: true, scopes: ["write"] };
  const found = (await files.query(["plan"], writer, 10))!;
  assert.deepEqual(found.hits.map((h) => h.path).sort(), [old, plan].sort());
  assert.equal(found.hits.find((h) => h.path === plan)!.text, "~/work");
  // The home's names and words and the apps for one who may write; only what is pinned for one who reads.
  assert.deepEqual(asked.slice(0, 3).map(([, w]) => w), [[home], [home], ["/Applications", "/System/Applications"]]);
  personal = true;
  assert.ok((await files.query(["plan"], writer, 10))!.hits.some((h) => h.path === mail));
  const reader = (await files.query(["plan"], { ...writer, scopes: [] }, 10))!;
  assert.deepEqual(asked.at(-1)![1], [join(home, "work")]);
  assert.deepEqual(reader.hits.map((h) => [h.path, h.root, h.rel]), [[plan, join(home, "work"), "plan.md"]]);
  // Another workspace that pinned nothing: nothing for its readers.
  assert.equal(await files.query(["plan"], { workspace: "W2", home: false, scopes: [] }, 10), null);
  assert.equal(spotlightQuery(['a"b']), '(kMDItemFSName == "*a\\"b*"cd || kMDItemTextContent == "a\\"b*"cdw)');
  assert.equal(spotlightQuery(["abc"], false), 'kMDItemFSName == "*abc*"cd');
  // A short word: at the start of a name alone, never what files say.
  assert.equal(spotlightQuery(["ab"], false), 'kMDItemFSName == "ab*"cd');
  assert.equal(spotlightQuery(["ab"]), null);
  assert.equal(spotlightQuery(["ab", "plan"]), 'kMDItemFSName == "ab*"cd && (kMDItemFSName == "*plan*"cd || kMDItemTextContent == "plan*"cdw)');
});

test("where there is no Spotlight, the home is walked as a search comes: names and the words of small texts, not the station's own nor what tools keep", async () => {
  const { FileSearch, walk } = await import("../src/search/files.ts");
  const top = mkdtempSync(join(tmpdir(), "search-walk-"));
  dirs.push(top);
  mkdirSync(join(top, "docs"), { recursive: true });
  mkdirSync(join(top, "node_modules/x"), { recursive: true });
  mkdirSync(join(top, "data"), { recursive: true });
  writeFileSync(join(top, "docs/plan.md"), "ship the search");
  writeFileSync(join(top, "docs/notes.txt"), "the plan, again");
  writeFileSync(join(top, "node_modules/x/plan.md"), "no");
  writeFileSync(join(top, "data/plan"), "secret");
  const files = new FileSearch({ home: top, protect: () => [join(top, "data")], roots: () => [], personal: () => false, spotlight: null });
  const found = (await files.query(["plan"], { workspace: "W1", home: true, scopes: ["write"] }, 10))!;
  // By its name, then by what it says.
  assert.deepEqual(found.hits.map((h) => h.path), [join(top, "docs/plan.md"), join(top, "docs/notes.txt")]);
  assert.equal(found.more, false);
  assert.deepEqual((await files.query(["ship", "search"], { workspace: "W1", home: true, scopes: ["write"] }, 10))!.hits.map((h) => h.path), [join(top, "docs/plan.md")]);
  // Out of time: what was reached, and more said to be there.
  const late = await walk([top], ["plan"], { skip: [], most: 10, ms: -1, now: () => 0 });
  assert.deepEqual(late, { paths: [], left: true });
});

test("Documents, Desktop and Downloads are searched through still.fail Helper, only where it holds their grant", async () => {
  const { FileSearch } = await import("../src/search/files.ts");
  const home = mkdtempSync(join(tmpdir(), "search-kept-"));
  dirs.push(home);
  const made = (rel: string) => {
    const path = join(home, rel);
    mkdirSync(join(path, ".."), { recursive: true });
    writeFileSync(path, "x");
    return path;
  };
  const doc = made("Documents/plan.pages");
  const desk = made("Desktop/plan.png");
  const asked: string[] = [];
  const files = new FileSearch({
    home, protect: () => [], roots: () => [join(home, "Documents")], personal: () => false,
    spotlight: async () => [],
    helper: {
      granted: (tops) => tops.filter((t) => t.endsWith("Documents")),
      search: async (top) => {
        asked.push(top);
        return top.endsWith("Documents") ? [doc] : [desk];
      },
    },
  });
  const writer = { workspace: "W1", home: true, scopes: ["write"] };
  assert.deepEqual((await files.query(["plan"], writer, 10))!.hits.map((h) => h.path), [doc]);
  assert.deepEqual(asked, [join(home, "Documents")]);
  // A read-only member whose workspace pinned Documents: through the helper too, under that folder.
  const reader = (await files.query(["plan"], { ...writer, scopes: [] }, 10))!;
  assert.deepEqual(reader.hits.map((h) => [h.path, h.rel]), [[doc, "plan.pages"]]);
});

test("the machine is searched once for the same words a while, one search at a time, a search typed on stopping the one before", async () => {
  const { FileSearch, KEPT_MS } = await import("../src/search/files.ts");
  const home = mkdtempSync(join(tmpdir(), "search-queue-"));
  dirs.push(home);
  const plan = join(home, "plan.md");
  writeFileSync(plan, "x");
  let now = 0;
  const asked: string[] = [];
  const stopped: string[] = [];
  // Spotlight that answers once let (`go`), or once stopped.
  const waits: (() => void)[] = [];
  const files = new FileSearch({
    home, protect: () => [], roots: () => [], personal: () => false, now: () => now,
    spotlight: (query, _within, _most, signal) => {
      asked.push(query);
      return new Promise((resolve) => {
        waits.push(() => resolve([plan]));
        signal?.addEventListener("abort", () => {
          stopped.push(query);
          resolve([]);
        });
      });
    },
  });
  const writer = { workspace: "W1", home: true, scopes: ["write"] };
  const go = async () => {
    await new Promise((r) => setImmediate(r));
    for (const w of waits.splice(0)) w();
  };
  // Typed on: the one before stops, and finds nothing; the latest finds the file.
  const first = files.query(["pla"], writer, 10);
  await new Promise((r) => setImmediate(r));
  const second = files.query(["plan"], writer, 10);
  assert.equal(await first, null);
  assert.ok(stopped.length > 0 && stopped.every((q) => q.includes("pla")));
  await go();
  assert.deepEqual((await second)!.hits.map((h) => h.path), [plan]);
  // Asked again (a client's chats changed): what was found, the machine not searched again.
  const before = asked.length;
  assert.deepEqual((await files.query(["plan"], writer, 10))!.hits.map((h) => h.path), [plan]);
  assert.equal(asked.length, before);
  // Another search of other words waits for the one going, and is not stopped by it.
  const other = files.query(["notes"], writer, 10);
  now += KEPT_MS + 1;
  const again = files.query(["plan"], writer, 10);
  await go();
  await go();
  assert.ok((await other) !== null);
  assert.deepEqual((await again)!.hits.map((h) => h.path), [plan]);
  assert.ok(asked.length > before);
});
