import assert from "node:assert/strict";
import { worded } from "../../client/core-ts/src/chat-row.ts";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { firstText, lastSaid, makeStore } from "../src/read/store.ts";
import { chats } from "../src/read/views.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { MANUAL, Store, newMessage } from "../src/store/store.ts";

const viewer = { sub: "ann@x", email: "ann@x", name: "Ann", role: "member", workspace: "A", device: "dev", home: true } as const;

function session(store: Store, key: string, ws: string | null = null) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
    createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws });
}
function job(store: Store, key: string) {
  store.insertJob({ id: `j-${key}`, sessionKey: key, name: "job", command: "true", cwd: "/", port: null, token: key,
    state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
}
function oldEdits(store: Store, thread: number) {
  const db = store.db;
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,?,?,?,?,?,?)");
  for (let n = 2; n <= 81; n++) put.run(thread, n, "edit", n + 1000, "agent", "worker", `edit-${n}`, n);
  installLegacyEdits(db);
  addClientColumn(db);
}
const jobChats = (rows: any[]) => rows.map((j) => [j.id, j.chat?.id, j.chat?.title, j.chat?.archived]);
/// (the rows in a client's words: chat-row.ts `worded`)
const titleRows = (rows: any[]) => rows.map((r) => worded(r, WORDS)).map((r) => [r.id, r.title, r.agents.map((a: any) => a.key)]);
const WORDS = { untitled: "新对话", directMessage: "私信", quotedOnly: "引用了一条消息" };

for (const title of ["Given title", null]) test(`a job's own chat with title ${title} does not need its message edits`, () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a"); job(store, "a");
    const chat = store.openThread("ember", "CHAT", "1.1", title, "ann@x");
    store.joinThread(chat.id, "a", "ember");
    store.insertMessage({ ...newMessage(chat.id, "1", "person", "ann@x", "first"), at: 1 });
    const reader = makeStore(store.db, ".");
    const expected = jobChats(openJobs(reader, viewer));
    assert.equal(expected[0][1], "a");
    if (title !== null) assert.equal(expected[0][2], title);
    oldEdits(store, chat.id);
    assert.throws(() => lastSaid(reader, chat.id), { status: 503, message: "legacy edit lookup pending" });
    assert.throws(() => firstText(reader, chat.id), { status: 503, message: "legacy edit lookup pending" });
    assert.deepEqual(openJobs(reader, viewer, false).map((j) => j.id), ["j-a"]);
    assert.deepEqual(jobChats(openJobs(reader, viewer)), expected);
  } finally { store.close(); }
});

for (const own of [false, true]) test(`a named ${own ? "own chat" : "external origin"} does not need an origin's edits`, () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a"); job(store, "a");
    if (own) {
      const chat = store.openThread("ember", "CHAT", "own", "Own title", "ann@x");
      store.joinThread(chat.id, "a", "ember");
    }
    const source = store.openThread("slack:one", "C1", "origin", own ? null : "Origin title", "ann@x");
    store.joinThread(source.id, "a", "one");
    store.insertMessage({ ...newMessage(source.id, "1", "person", "ann@x", "first"), at: 1 });
    const reader = makeStore(store.db, ".");
    const expected = jobChats(openJobs(reader, viewer));
    assert.equal(expected[0][2], own ? "Own title" : "Origin title");
    oldEdits(store, source.id);
    assert.throws(() => firstText(reader, source.id), { status: 503, message: "legacy edit lookup pending" });
    assert.deepEqual(jobChats(openJobs(reader, viewer)), expected);
  } finally { store.close(); }
});

test("an unnamed external origin still needs its first text for the job's chat", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a"); job(store, "a");
    const source = store.openThread("slack:one", "C1", "1.1", null, "ann@x");
    store.joinThread(source.id, "a", "one");
    store.insertMessage({ ...newMessage(source.id, "1", "person", "ann@x", "The first message"), at: 1 });
    const reader = makeStore(store.db, ".");
    const expected = jobChats(openJobs(reader, viewer));
    assert.equal(expected[0][2], "The first message");
    oldEdits(store, source.id);
    assert.throws(() => openJobs(reader, viewer), { status: 503, message: "legacy edit lookup pending" });
    while (!legacyEditStep(store.db).ready) { /* prepare */ }
    while (legacyEditDrain(store.db) > 0) { /* reconcile */ }
    assert.deepEqual(jobChats(openJobs(reader, viewer)), expected);
  } finally { store.close(); }
});

test("the selected origin and its name share the reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-chat-title-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  try {
    session(store, "a"); job(store, "a");
    const own = store.openThreadOf("ember", "CHAT", "own", null, "ann@x", "a");
    store.joinThread(own.id, "a", "ember");
    const source = store.openThread("slack:one", "C1", "origin", null, "ann@x");
    store.joinThread(source.id, "a", "one");
    store.insertMessage({ ...newMessage(source.id, "1", "person", "ann@x", "Before"), at: 1 });
    let changed = false;
    const observed = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT e.at FROM thread_state")) return statement;
        return new Proxy(statement, { get(stmt, member) {
          if (member === "get") return (...args: any[]) => {
            const row = stmt.get(...args);
            if (!changed && args[0] === source.id) {
              writer.prepare("UPDATE entries SET text='After' WHERE thread=? AND n=1").run(source.id);
              changed = true;
            }
            return row;
          };
          const value = Reflect.get(stmt, member, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, dir);
    reader.db.exec("BEGIN");
    try {
      assert.equal(jobChats(openJobs(reader, viewer))[0][2], "Before");
      assert.equal(changed, true);
    } finally { reader.db.exec("COMMIT"); }
    assert.equal(jobChats(openJobs(reader, viewer))[0][2], "After");
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("job title rows preserve the full sidebar's names, agents and order", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", null], ["b", null], ["old", null], ["away", "B"]] as const) session(store, key, ws);
    for (const key of ["a", "b", "old", "away"]) job(store, key);
    const ownA = store.openThread("ember", "CHAT", "own-a", null, "ann@x");
    store.joinThread(ownA.id, "a", "ember");
    store.joinThread(ownA.id, "b", "ember");
    const ownB = store.openThread("ember", "CHAT", "own-b", "B name", "ann@x");
    store.joinThread(ownB.id, "b", "ember");
    const old = store.openThreadOf("ember", "CHAT", "own-old", "Old name", "ann@x", "old");
    store.joinThread(old.id, "old", "ember");
    store.setArchived("old", true, MANUAL);
    const away = store.openThread("ember", "CHAT", "own-away", "Away", "ann@x");
    store.joinThread(away.id, "away", "ember");
    const older = store.openThread("slack:one", "C1", "old-origin", "Earlier origin", "ann@x");
    const newer = store.openThread("slack:one", "C1", "new-origin", null, "ann@x");
    store.joinThread(older.id, "a", "one");
    store.joinThread(newer.id, "a", "one");
    for (const [thread, at, text] of [[ownA.id, 12, "a"], [ownB.id, 12, "b"], [old.id, 7, "old"],
      [away.id, 20, "away"], [older.id, 3, "earlier"], [newer.id, 15, "Newer origin text"]] as const)
      store.insertMessage({ ...newMessage(thread, String(at), "person", "ann@x", text), at });
    const reader = makeStore(store.db, ".");
    for (const archived of [false, true]) {
      const full = titleRows(chats(reader, viewer, archived, null, false));
      const names = titleRows(chats(reader, viewer, archived, null, true));
      assert.deepEqual(names, full);
      const byId = new Map(full.map(([id, title]) => [id, title]));
      if (archived) assert.equal(byId.get("old"), "Old name");
      else {
        assert.equal(byId.get("a"), "Newer origin text");
        assert.equal(byId.get("b"), "B name");
        assert.equal(byId.has("away"), false);
      }
    }
    assert.deepEqual(jobChats(openJobs(reader, viewer)).sort(), [
      ["j-a", "a", "Newer origin text", false], ["j-b", "b", "B name", false], ["j-old", "old", "Old name", true],
    ]);
  } finally { store.close(); }
});
