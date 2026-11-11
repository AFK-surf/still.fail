// A station's conversations made up for the copies' tests (replica/): sessions in two workspaces, chats with messages,
// edits, attached files, letters, turns, marks, an archived chat and a deleted one, in a data directory of its own.
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { DatabaseSync } from "node:sqlite";
import { Store } from "../src/store/store.ts";
import { type Row, RESTORE_ORDER, TABLES } from "../src/replica/format.ts";
import { moved } from "../src/replica/restore.ts";

export const HOME = "wshome";
export const OTHER = "wsother";
export const ORIGIN = "a".repeat(64);

/// A data directory with its store, and what is in it.
export type Made = { data: string; db: string; store: Store; sessions: string[]; deleted: string; files: Record<string, string> };

let n = 0;
export function dataDir(name = "st"): string {
  return mkdtempSync(join(process.env.STILLFAIL_TEST_TMP ?? tmpdir(), `${name}-`));
}

/// A file attached in `session`'s workspace, with `text` in it.
export function attach(data: string, session: string, name: string, text: string) {
  const dir = join(data, "sessions", "chat", session, "workspace", "uploads");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, name);
  writeFileSync(path, text);
  return { name, path, size: Buffer.byteLength(text) };
}

/// A session of its own chat, in `ws` (null: the home one), with `messages` said in it.
export function chat(store: Store, data: string, key: string, ws: string | null, messages: number) {
  store.insertSession({ key, connect: "chat", runtime: "claude", profile: "cc", workspace: join(data, "sessions", "chat", key, "workspace"), token: `t-${key}-${n++}`, createdAt: 1, lastActiveAt: 1, ws });
  const thread = store.openThread("ember", "C", `ts-${key}`, `Chat ${key}`, "p@x").id;
  store.joinThread(thread, key, "chat");
  for (let i = 0; i < messages; i++) store.insertMessage({ thread, ts: `${key}.${i}`, authorKind: i % 2 === 0 ? "person" : "agent", author: i % 2 === 0 ? "p@x" : key, text: `${key} says ${i}` });
  return thread;
}

/// The made-up station: its home workspace's chats (one archived, one with files and a letter, one deleted) and one
/// chat of another workspace.
export function station(data = dataDir()): Made {
  const db = join(data, "stillfail.db");
  const store = Store.open(db, join(data, "archive"));
  const files: Record<string, string> = {};
  const a = chat(store, data, "chat:a", null, 30);
  const pic = attach(data, "chat:a", "pic.png", "a picture");
  files[pic.path] = "a picture";
  store.insertMessage({ thread: a, ts: "a.pic", authorKind: "person", author: "p@x", text: "look", attachments: [pic] });
  store.editMessage("ember", "C", "ts-chat:a", "chat:a.0", "edited words");
  store.insertLetter({ thread: a, ts: "a.letter", authorKind: "agent", author: "chat:a", text: "dear b", letter: { way: "out", title: "Chat b", link: null } });
  store.setRead("p@x", a, 10);
  store.setPin("p@x", "chat:a", true);
  store.startTurnFor("turn-a", "chat:a", "message", { profile: "cc", person: "p@x", thread: a });
  store.endTurn("turn-a", "completed", null, "all_done", null);
  const b = chat(store, data, "chat:b", null, 5);
  store.setArchived("chat:b", true, "p@x");
  store.setThreadHidden(b, true, "p@x");
  chat(store, data, "chat:gone", null, 3);
  const gone = attach(data, "chat:gone", "secret.txt", "deleted with its chat");
  void gone;
  chat(store, data, "chat:o", OTHER, 4);
  return { data, db, store, sessions: ["chat:a", "chat:b", "chat:o"], deleted: "chat:gone", files };
}

/// Every row of the tables a copy holds that are of `ws`, by table, keyed as a copy keys them, paths as they would be
/// under `to` (where they were under `from`).
export function rowsOf(db: DatabaseSync, ws: string | null, from = "", to = ""): Record<string, Map<string, Row>> {
  const sessions = new Set((db.prepare("SELECT key FROM sessions WHERE ws IS ?").all(ws) as { key: string }[]).map((r) => r.key));
  const threads = new Set((db.prepare("SELECT DISTINCT thread FROM thread_sessions").all() as { thread: number }[])
    .map((r) => r.thread)
    .filter((t) => (db.prepare("SELECT session FROM thread_sessions WHERE thread = ?").all(t) as { session: string }[]).some((s) => sessions.has(s.session))));
  const out: Record<string, Map<string, Row>> = {};
  for (const table of RESTORE_ORDER) {
    const m = new Map<string, Row>();
    for (const row of db.prepare(`SELECT * FROM ${table}`).all() as Row[]) {
      const ofThread = "thread" in row && table !== "sessions" ? threads.has(row.thread as number) : table === "threads" ? threads.has(row.id as number) : false;
      const session = table === "sessions" ? row.key : table === "pins" ? row.session : table === "opened_chats" ? row.child : table === "turns" || table === "runtime_sessions" ? row.session_key : null;
      const ofSession = typeof session === "string" && sessions.has(session);
      if (!(ofThread || ofSession)) continue;
      const r = { ...row };
      if (table === "sessions") {
        r.running = 0;
        if (typeof r.workspace === "string") r.workspace = moved(r.workspace, from, to);
        if (typeof r.cwd === "string") r.cwd = moved(r.cwd, from, to);
      }
      if ((table === "entries" || table === "letters") && typeof r.attachments === "string" && r.attachments !== "") {
        r.attachments = JSON.stringify((JSON.parse(r.attachments) as Row[]).map((a) => ({ ...a, path: moved(a.path as string, from, to) })));
      }
      m.set(JSON.stringify(TABLES[table]!.map((c) => row[c] ?? null)), r);
    }
    out[table] = m;
  }
  return out;
}
