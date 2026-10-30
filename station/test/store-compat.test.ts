// The write side over a COPY of a real station's data (the Rust station's ~/.stillfail, or $STILLFAIL_COMPAT_DATA): it
// opens as it is (version 12, nothing added), reads as read/store.ts reads it, and a write cycle leaves the database as
// the Rust schema has it, the threads the Rust wrote out to archive files brought back as they read. Skipped where there
// is no station.
// The live database is never opened: the copy is made with cp (db, -wal, -shm, archive/threads) and removed after.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import * as read from "../src/read/store.ts";
import { SCHEMA } from "../src/store/schema.ts";
import { MANUAL, Store, newMessage, turnSummaryJson } from "../src/store/store.ts";

const live = process.env.STILLFAIL_COMPAT_DATA ?? join(homedir(), ".stillfail");
const present = existsSync(join(live, "stillfail.db"));
const dir = present ? mkdtempSync(join(tmpdir(), "store-compat-")) : "";
after(() => {
  if (dir) rmSync(dir, { recursive: true, force: true });
});

/// Every table's columns, and every index's and view's SQL: what the schema is.
function shape(path: string): string[] {
  const db = new DatabaseSync(path, { readOnly: true });
  try {
    const out: string[] = [];
    for (const m of db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name").all() as any[]) {
      out.push(`${m.type} ${m.name}: ${m.sql}`);
      if (m.type === "table") {
        for (const c of db.prepare(`SELECT name, type, "notnull", dflt_value, pk FROM pragma_table_info('${m.name}')`).all() as any[]) {
          out.push(`  ${m.name}.${c.name} ${c.type} ${c.notnull} ${c.dflt_value} ${c.pk}`);
        }
      }
    }
    out.push(`user_version ${(db.prepare("PRAGMA user_version").get() as any).user_version}`);
    return out;
  } finally {
    db.close();
  }
}

/// Columns the TS station adds to tables the Rust station made (schema.ts), by table: a station's in several workspaces
/// (docs/multi-workspace.md). A table's latest first: each is taken off the end of its table's SQL in turn.
const ADDED: [string, string][] = [
  ["turns", "wait_watch"], ["sessions", "ws"], ["archive_policy", "ws"], ["entries", "letter"], ["entries", "runtime"], ["jobs", "size"], ["jobs", "screen"], ["jobs", "queued"],
  ["usage", "context_window"], ["usage", "context"], ["usage", "calls"],
];
/// What those columns bring with them: an index of its own (letters; the sessions counted by connect and workspace; the
/// threads' homes), and the `merged` view saying the column (letters).
const ADDED_INDEXES = ["entries_letters", "sessions_by_connect", "threads_home", "threads_own"];
const MERGED_ADDS = [", m.letter"];
/// Tables the TS station makes as it opens (schema.ts `addUsageTotals`, `addUsageCompactions`, `addUsageQuarters`): each with its columns,
/// and the indexes and triggers that keep it (named after it), which it makes anew as what they read changes
/// (`addUsageColumns`).
const MADE = ["usage_totals", "usage_compactions", "usage_quarters", "thread_state", "thread_people", "session_first"];
const made = (l: string) => MADE.some((t) => l.startsWith(`table ${t}:`) || l.startsWith(`  ${t}.`) || l.startsWith(`trigger ${t}_`) || l.startsWith(`index ${t}_`));

const noToken = <T extends { token: string }>(r: T) => {
  const { token: _, ...rest } = r;
  return rest;
};

test("a copy of a real station's data opens, reads the same, and takes a write cycle", { skip: !present && "no station data here" }, (t) => {
  for (const suffix of ["", "-wal", "-shm"]) {
    if (existsSync(join(live, `stillfail.db${suffix}`))) cpSync(join(live, `stillfail.db${suffix}`), join(dir, `stillfail.db${suffix}`));
  }
  if (existsSync(join(live, "archive", "threads"))) cpSync(join(live, "archive", "threads"), join(dir, "archive", "threads"), { recursive: true });
  const path = join(dir, "stillfail.db");
  const before = shape(path);

  const store = Store.open(path);
  let opened: string[] = [];
  try {
    assert.equal(store.archiveDir(), join(dir, "archive"));
    // Opening adds nothing to what the Rust station keeps, beyond the tables and indexes of the Rust SCHEMA a station
    // older than that source had not made yet (CREATE … IF NOT EXISTS, as the Rust's open makes them).
    opened = shape(path);
    // Besides the columns the TS station adds on open itself (schema.ts `add*Columns`), as later ones are: a table's SQL
    // then says them after its last column (at its end, or before its PRIMARY KEY), and each is a column line of its own.
    const plain = (l: string) => {
      const columns = ADDED.reduce((t, [table, column]) => (t.startsWith(`table ${table}:`) ? t.replace(new RegExp(`, ${column} [A-Z][A-Z0-9 ]*(?=\\)$|,\\s*PRIMARY KEY)`), "") : t), l);
      return columns.startsWith("view merged:") ? MERGED_ADDS.reduce((t, add) => t.replace(add, ""), columns) : columns;
    };
    const mine = (l: string) => ADDED.some(([table, column]) => l.startsWith(`  ${table}.${column} `)) || ADDED_INDEXES.some((index) => l.startsWith(`index ${index}:`));
    const was = before.map(plain);
    // Ignore only newly added columns; columns already present must still survive opening.
    const now = opened.filter((l) => !mine(l) || before.includes(l)).map(plain);
    // (The triggers of the TS station's own tables aside: it makes them anew.)
    assert.deepEqual(was.filter((l) => !now.includes(l) && !(made(l) && l.startsWith("trigger "))), [], "nothing changed or gone");
    const added = now.filter((l) => !was.includes(l) && !made(l));
    for (const line of added) {
      const name = /^(?:table|index) (\w+):/.exec(line)?.[1] ?? /^  (\w+)\./.exec(line)?.[1];
      assert.ok(name && new RegExp(`CREATE (TABLE|INDEX) IF NOT EXISTS ${name} `).test(SCHEMA), `only the Rust SCHEMA's own: ${line.split("\n")[0]}`);
      assert.ok(!before.some((l) => l.startsWith(`table ${name}:`)), "no column added to a table the station had");
    }

    // Reads: the same as read/store.ts over the same file.
    const r = read.makeStore(new DatabaseSync(path, { readOnly: true }), dir);
    try {
      const viewer: string = (store.db.prepare("SELECT viewer FROM reads GROUP BY viewer ORDER BY COUNT(*) DESC LIMIT 1").get() as any)?.viewer ?? "local";
      assert.deepEqual(store.listSessions().map(noToken), read.listSessions(r));
      assert.deepEqual(store.listThreads(viewer, null, null), read.listThreads(r, viewer, null, null));
      assert.deepEqual(store.participants(null), read.participants(r, null));
      assert.deepEqual(store.listBindings(), read.listBindings(r));
      assert.deepEqual(store.listJobs(null).map(noToken), read.listJobs(r, null));
      assert.deepEqual(store.answersSince(0), read.answersSince(r, 0));
      const stats = store.sessionStats(null);
      for (const [key, s] of read.sessionStats(r, null)) {
        const mine = stats.get(key)!;
        // What the pages read names its last turn too (a client holding the turns puts it in place).
        const { id, ...last } = (s.lastTurn ?? {}) as Record<string, unknown>;
        assert.deepEqual({ ...mine, lastTurn: mine.lastTurn && turnSummaryJson(mine.lastTurn) }, { ...s, lastTurn: s.lastTurn && last }, key);
        if (s.lastTurn) assert.equal(typeof id, "string", key);
      }
      for (const s of store.listSessions().slice(0, 30)) {
        assert.deepEqual(store.listTurns(s.key).map((t) => ({ ...turnSummaryJson(t.summary), id: t.id })), read.listTurns(r, s.key));
      }
      for (const t of store.db.prepare("SELECT id FROM threads ORDER BY id DESC LIMIT 60").all() as any[]) {
        assert.deepEqual(store.entriesBefore(t.id, null, 50), read.entriesBefore(r, t.id, null, 50));
        assert.deepEqual(store.messagesBefore(t.id, null, 50), read.messagesBefore(r, t.id, null, 50));
        assert.deepEqual(store.lastMessage(t.id), read.lastMessage(r, t.id));
        assert.deepEqual(store.pendingCard(t.id), read.pendingCard(r, t.id));
      }
      // What lists say of each thread and session, kept (schema.ts LIST_STATE), as their messages say it.
      const rows = (sql: string) => store.db.prepare(sql).all().map((x) => JSON.stringify(x));
      assert.deepEqual(
        rows("SELECT thread, last_n, said_n, person_n, letters FROM thread_state ORDER BY thread"),
        rows(`SELECT thread, MAX(n) AS last_n, MAX(CASE WHEN kind = 'message' AND letter IS NULL THEN n END) AS said_n,
          MIN(CASE WHEN kind = 'message' AND author_kind = 'person' THEN n END) AS person_n,
          COUNT(CASE WHEN kind = 'message' AND letter IS NOT NULL THEN 1 END) AS letters FROM entries GROUP BY thread ORDER BY thread`),
      );
      assert.deepEqual(
        rows("SELECT thread, author, first_n FROM thread_people ORDER BY thread, author"),
        rows("SELECT thread, author, MIN(n) AS first_n FROM entries WHERE kind = 'message' AND author_kind = 'person' GROUP BY thread, author ORDER BY thread, author"),
      );
      assert.deepEqual(
        rows("SELECT session, thread, n FROM session_first ORDER BY session"),
        rows("SELECT d.session, d.thread, d.n FROM deliveries d WHERE d.rowid = (SELECT MIN(rowid) FROM deliveries x WHERE x.session = d.session) ORDER BY d.session"),
      );
    } finally {
      r.db.close();
    }

    // A message into a thread with a session in lists: appended as the next entry, delivered once.
    const live = store.db
      .prepare(
        `SELECT ts.thread, ts.session FROM thread_sessions ts JOIN threads t ON t.id = ts.thread JOIN sessions s ON s.key = ts.session
         WHERE t.archived_at IS NULL AND t.hidden_at IS NULL AND s.archived_at IS NULL ORDER BY t.id DESC LIMIT 1`,
      )
      .get() as any ??
      // A station whose chats are all in the archive: any thread with a session.
      (store.db.prepare(`SELECT thread, session FROM thread_sessions ORDER BY thread DESC LIMIT 1`).get() as any);
    if (!live) {
      // A station with no chat yet (a new one): nothing to write a message into.
      t.diagnostic("no thread with a session in this station's data: the write cycle is not run");
      return;
    }
    // Archived by hand, it takes no messages: shown again first, as a person would.
    if (store.manuallyArchived(live.thread)) {
      store.setArchived(live.session, false, MANUAL);
      if (store.getThread(live.thread)!.hiddenAt !== null) store.setThreadHidden(live.thread, false, MANUAL);
    }
    {
      const last = store.lastEntry(live.thread);
      const [n, fresh] = store.insertMessage(newMessage(live.thread, "compat.1", "person", "local", "compat test"));
      assert.deepEqual([n, fresh], [last + 1, true]);
      assert.deepEqual(store.insertMessage(newMessage(live.thread, "compat.1", "person", "local", "again")), [n, false]);
      assert.deepEqual(store.deliver(live.thread, n, [live.session]), [live.session]);
      assert.deepEqual(store.deliver(live.thread, n, [live.session]), []);
      assert.ok(store.pendingMessages(live.session).some((p) => p.message.n === n && p.message.thread === live.thread));
      store.markDelivered(live.session, [[live.thread, n]]);
      store.startTurnFor("compat-turn", live.session, "input", { profile: null, person: "local", thread: live.thread });
      store.endTurn("compat-turn", "completed", null, "all_done", null);
      assert.equal(store.lastTurn(live.session)!.ending, "all_done");
    }

    // An archived session's threads, written out to their files by the Rust station: brought back as it is shown again,
    // and archived again, left in the database.
    const archived = store.db
      .prepare(
        `SELECT s.key FROM sessions s WHERE s.archived_at IS NOT NULL AND EXISTS (SELECT 1 FROM thread_sessions ts JOIN threads t ON t.id = ts.thread
           WHERE ts.session = s.key AND t.archived_at IS NOT NULL) ORDER BY s.archived_at DESC LIMIT 3`,
      )
      .all() as any[];
    if (archived.length === 0) t.diagnostic("no archived session with archived threads: bringing them back was not run");
    for (const { key } of archived) {
      const files = new Set<number>();
      for (const t of store.sessionThreads(key)) if (existsSync(join(dir, "archive", "threads", `${t.thread.id}.jsonl.zst`))) files.add(t.thread.id);
      const entries = new Map([...files].map((id) => [id, store.entriesAfter(id, 0)]));
      const by = store.getSession(key)!.archivedBy ?? MANUAL;
      store.setArchived(key, false, MANUAL);
      for (const id of files) {
        assert.ok(!existsSync(join(dir, "archive", "threads", `${id}.jsonl.zst`)), "brought back into the database");
        assert.deepEqual(store.entriesAfter(id, 0), entries.get(id));
      }
      store.setArchived(key, true, by);
      for (const id of files) {
        assert.ok(!existsSync(join(dir, "archive", "threads", `${id}.jsonl.zst`)), "archived again, left in the database");
        assert.deepEqual(store.entriesAfter(id, 0), entries.get(id));
      }
    }

    // Every other thread the Rust station wrote out: brought back a few at a time, each as it read from its file.
    const filed = (store.db.prepare("SELECT id FROM threads WHERE archived_at IS NOT NULL ORDER BY id").all() as any[]).map((r) => r.id as number);
    const fromFiles = new Map(filed.map((id) => [id, store.entriesAfter(id, 0)]));
    let left = filed.length;
    while (left > 0) left = store.bringInArchived(100).left;
    for (const [id, entries] of fromFiles) {
      assert.ok(!existsSync(join(dir, "archive", "threads", `${id}.jsonl.zst`)));
      assert.deepEqual(store.entriesAfter(id, 0), entries, `thread ${id}`);
    }
    assert.deepEqual(store.lostArchives(), []);

    // A chat hidden by hand and shown again: its entries where they were.
    const chat = store.db
      .prepare("SELECT id FROM threads t WHERE hidden_at IS NULL AND archived_at IS NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread = t.id) ORDER BY id DESC LIMIT 1")
      .get() as any;
    assert.ok(chat, "a thread to hide");
    {
      const entries = store.entriesAfter(chat.id, 0);
      store.setThreadHidden(chat.id, true, MANUAL);
      assert.ok(!existsSync(join(dir, "archive", "threads", `${chat.id}.jsonl.zst`)));
      assert.deepEqual(store.entriesAfter(chat.id, 0), entries);
      store.setThreadHidden(chat.id, false, MANUAL);
      assert.deepEqual(store.entriesAfter(chat.id, 0), entries);
    }
  } finally {
    store.close();
  }

  // The database is as the Rust schema has it: nothing new since it was opened, and whole.
  assert.deepEqual(shape(path), opened);
  const db = new DatabaseSync(path, { readOnly: true });
  assert.equal((db.prepare("PRAGMA integrity_check").get() as any).integrity_check, "ok");
  db.close();
  // The sqlite3 shell, where there is one, reads it too.
  try {
    execFileSync("sqlite3", [path, "SELECT COUNT(*) FROM merged"], { stdio: "pipe" });
  } catch (e: any) {
    if (e.code !== "ENOENT") throw e;
  }
});
