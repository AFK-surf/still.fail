// The Router's reads and writes in the workspace's chats through a Comma connect (surface.ts), apart from the part
// that wires them (module.ts), so that they can be tried alone.
import type { Hub } from "../sessions/hub.ts";
import { say } from "../sessions/lifecycle.ts";
import { wall } from "../ops/fibers.ts";
import { MANUAL, MessageWriteBusy } from "../store/store.ts";
import type { WorkspaceReads } from "./peer.ts";
import { BUILD_DAYS, chatOf, type CommaStats } from "./stats.ts";

type Json = any;
type RouterWrite = { id: string; thread: number; n: number; pending: number };

// An older station answers with raw entries. Bound retries through edits; if no message can be reached in that
// budget, an explicit upgrade error is safer than answering that the chat has no more messages.
const LEGACY_READ_PAGES = 8;
const LEGACY_READ_ROWS = 100;

// The JSON contains only this chat's already-validated hearing members, in their original order.
export const ROUTER_TARGETS_INSERT = `INSERT INTO comma_router_once_targets (id, position, session)
  SELECT o.id, CAST(j.key AS INTEGER), j.value FROM comma_router_once o, json_each(?) j WHERE o.key = ?`;

class AlreadySaid extends Error {
  readonly write: RouterWrite;
  constructor(write: RouterWrite) { super("Router key already recorded"); this.write = write; }
}

/// The older process only knows the other database. Reject while it is still alive rather than letting a timed-out
/// request take effect later, after its caller has already been told it failed.
export function routerSaysAfter(hub: Hub, stats: CommaStats, previousExited: Promise<void>) {
  let ready = false;
  void previousExited.then(() => { ready = true; }, () => {});
  return (workspace: string | null, w: { thread: number; text: string; key: string; requester: string; connect: string }): number => {
    if (!ready) throw new Error("the previous station is still handing over; retry the write");
    return routerSays(hub, stats, workspace, w);
  };
}

/// A chat's messages and title for the Router, only after the station holding the chat confirms its workspace.
export async function routerReads(stats: CommaStats, reads: Pick<WorkspaceReads, "of" | "here" | "there">, ref: string, after: number, limit: number): Promise<Json> {
  const chat = chatOf(ref);
  if (chat === null) throw new Error("no such chat");
  const of = reads.of();
  const read = async (position: number, count: number): Promise<Json> => {
    const args = { thread: chat.thread, after: position, limit: count, messagesOnly: true };
    const got = JSON.parse(chat.station === null
      ? await reads.here("outflowMessages", of === null ? args : { ...args, ws: of })
      : await reads.there(chat.station, "outflowMessages", args));
    if (got === null) throw new Error("no such chat of the workspace");
    if (!Array.isArray(got.messages) || !Number.isSafeInteger(got.last) || got.last < 0 ||
        (got.more !== undefined && typeof got.more !== "boolean") ||
        (got.messagesOnly === true && (typeof got.more !== "boolean" || (got.more && got.messages.length === 0))))
      throw new Error("that station's message answer is incomplete");
    return got;
  };
  let cursor = after;
  let got = await read(cursor, limit);
  let pages = 1;
  const messages: Json[] = [];
  for (;;) {
    if (pages > 1 && got.last < cursor) throw new Error("that station's message answer is incomplete");
    let previous = cursor;
    for (const entry of got.messages) {
      if (!Number.isSafeInteger(entry?.n) || entry.n <= previous || entry.n > got.last ||
          (got.messagesOnly === true && entry.kind !== "message"))
        throw new Error("that station's message answer is incomplete");
      previous = entry.n;
      if (entry.kind === "message" && messages.length < limit) messages.push(entry);
    }
    if (got.messagesOnly === true || got.more !== true || messages.length >= limit) break;
    if (previous <= cursor) throw new Error("that station's message cursor does not continue");
    if (pages >= LEGACY_READ_PAGES) {
      if (messages.length === 0) throw new Error("that station needs an update to read past these edits");
      break;
    }
    cursor = previous;
    got = await read(cursor, LEGACY_READ_ROWS);
    pages++;
  }
  return {
    title: stats.taskTitle(ref),
    messages: messages.slice(0, limit).map((m) => ({
      seq: m.n, author_kind: m.authorKind, author: m.person?.name ?? m.person?.email ?? m.author, text: m.text, at: m.at,
    })),
    through: got.last,
  };
}

/// The Router's message in chat `thread` of this station, as `requester` of the Comma connect `connect` (named so in
/// the chat, as a person of that connect is), once per `key`: its `n`. Only a chat of workspace `home` (one of the
/// station's, the connect's) on the station's pages; a Slack or Feishu chat is answered where it is.
export function routerSays(hub: Hub, stats: CommaStats, home: string | null, w: { thread: number; text: string; key: string; requester: string; connect: string }): number {
  try { return routerSaysOnce(hub, stats, home, w); }
  catch (error) {
    if (error instanceof MessageWriteBusy) throw new Error(w.key === "" ? "the station is busy; retry the write" : "the station is busy; retry the Router request with the same key");
    throw error;
  }
}

function routerSaysOnce(hub: Hub, stats: CommaStats, home: string | null, w: { thread: number; text: string; key: string; requester: string; connect: string }): number {
  const db = hub.store.db;
  const find = () => (db.prepare("SELECT CAST(id AS TEXT) AS id, thread, n, pending FROM comma_router_once WHERE key = ?").get(w.key) as RouterWrite | undefined) ?? null;
  const mirror = (written: RouterWrite) => {
    if (find()?.id !== written.id) throw new Error("the Router's recorded write changed; retry");
    // Keep old stations' lookup in step, too. A failed write can be retried without recording the message again.
    if (stats.said(w.key) === null) stats.remember(w.key, written.n);
    return written.n;
  };
  const finish = (written: RouterWrite) => {
    // The state and targets must come from one snapshot: cleanup may otherwise remove part of the target list
    // after a retry read the old pending state. The identity stays distinct even after this key expires and is reused.
    const rows = db.prepare(`SELECT o.pending, t.session FROM comma_router_once o
      LEFT JOIN comma_router_once_targets t ON t.id = o.id WHERE o.id = ? AND o.key = ? ORDER BY t.position`)
      .all(written.id, w.key) as { pending: number; session: string | null }[];
    const state = rows[0]?.pending;
    if (state === undefined) throw new Error("the Router's recorded write changed; retry");
    if (state === 2) throw new Error("the Router's write has expired");
    if (state !== 0) {
      const entry = db.prepare("SELECT text FROM entries WHERE thread = ? AND n = ? AND kind = 'message'").get(written.thread, written.n) as { text: string | null } | undefined;
      if (typeof entry?.text !== "string") throw new Error("the Router's recorded message is unavailable");
      const current = hub.store.threadSessions(written.thread);
      if (current.length === 0 || current.some((member) => {
        const session = hub.store.getSession(member.session);
        return session === null || hub.wsOf(session) !== home;
      })) throw new Error("no such chat of the workspace");
      const members = new Set(current.map((member) => member.session));
      hub.deliver(written.thread, written.n, rows.flatMap((row) => row.session === null ? [] : [row.session]).filter((session) => members.has(session) && hub.store.getSession(session) !== null), entry.text, { retryPending: true, workspace: home });
      if (!hub.store.completeRouterWrite(written.id)) throw new Error("the Router's recorded write changed; retry");
    }
    return mirror(written);
  };
  const recorded = w.key === "" ? null : find();
  if (recorded !== null) return finish(recorded);
  const had = w.key === "" ? null : stats.said(w.key);
  if (had !== null) return had;
  // The Task index tells a chat the Router wrote in by this form of its author (read/outflow.ts routerWrote): durable
  // where comma_router_once is not, and for the writes without a key, which leave none.
  const author = `slack:${w.connect}:${w.requester}`;
  if (w.key === "") {
    const members = hub.store.threadSessions(w.thread);
    if (members.length === 0 || members.some((m) => (hub.wsOf(m.session) ?? null) !== home)) throw new Error("no such chat of the workspace");
    return say(hub, w.thread, author, w.text);
  }
  let encodedTargets = "[]";
  const insertedWrite: { value: RouterWrite | null } = { value: null };
  try {
    const n = say(hub, w.thread, author, w.text, [], [], null, {
      workspace: home,
      before: () => {
        const old = find(); if (old !== null) throw new AlreadySaid(old);
        // Membership and workspace must be checked under the same write lock as the entry. A session can join or
        // move workspaces between the request arriving and this transaction beginning.
        const members = hub.store.threadSessions(w.thread);
        if (members.length === 0) throw new Error("no such chat of the workspace");
        const targets: string[] = [];
        for (const m of members) {
          const session = hub.store.getSession(m.session);
          if (session === null || hub.wsOf(session) !== home) throw new Error("no such chat of the workspace");
          if (m.leftAt === null && session.archivedBy !== MANUAL) targets.push(m.session);
        }
        encodedTargets = JSON.stringify(targets);
      },
      inserted: (n) => {
        const now = wall.now();
        // Expire at most 64 keys and 64 targets at a time. A failed delivery can have many targets: remove it in
        // batches too, without letting a retry deliver only the targets that happen to remain during cleanup.
        const expired = now - BUILD_DAYS * 24 * 60 * 60_000;
        const oldest = "SELECT id FROM comma_router_once INDEXED BY comma_router_once_age WHERE at < ? ORDER BY at LIMIT 64";
        db.prepare(`UPDATE comma_router_once SET pending = 2 WHERE pending = 1 AND id IN (${oldest})`).run(expired);
        db.prepare(`DELETE FROM comma_router_once_targets WHERE (id, position) IN (
          SELECT t.id, t.position FROM (${oldest}) a CROSS JOIN comma_router_once_targets t WHERE t.id = a.id LIMIT 64
        )`).run(expired);
        db.prepare(`DELETE FROM comma_router_once WHERE id IN
          (SELECT a.id FROM (${oldest}) a WHERE NOT EXISTS (SELECT 1 FROM comma_router_once_targets t WHERE t.id = a.id))`).run(expired);
        const row = db.prepare("INSERT INTO comma_router_once (key, thread, n, at, pending) VALUES (?, ?, ?, ?, 1) RETURNING CAST(id AS TEXT) AS id")
          .get(w.key, w.thread, n, now) as { id: string };
        insertedWrite.value = { id: row.id, thread: w.thread, n, pending: 1 };
        // Capture only the original members who were hearing at commit. Someone who rejoins or is unarchived before
        // a retry must not receive a message from before that change.
        db.prepare(ROUTER_TARGETS_INSERT).run(encodedTargets, w.key);
      },
      targets: () => {
        const write = insertedWrite.value;
        if (write === null) throw new Error("the Router's recorded write is unavailable");
        return (db.prepare("SELECT session FROM comma_router_once_targets WHERE id = ? ORDER BY position").all(write.id) as { session: string }[])
          .map((target) => target.session);
      },
    });
    const written = insertedWrite.value;
    if (written === null || written.n !== n || !hub.store.completeRouterWrite(written.id)) throw new Error("the Router's recorded write changed; retry");
    return mirror(written);
  } catch (error) {
    if (error instanceof AlreadySaid) return finish(error.write);
    throw error;
  }
}
