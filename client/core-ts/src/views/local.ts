// What a person did here that their station has not confirmed yet (docs/core-ts.md, rules 3 and 4): messages on
// their way (the outbox), chats asked for and not made (pending), messages to an agent before it has a chat (firsts),
// chats renamed, pinned, kept or archived (changing, archiving). Each is a record in the data center, so it shows at
// once, survives a restart, and goes on where it was; the views lay it over what the stations hold. Nothing here
// waits on the network: the calls that change it answer as their station has it, the views show it meanwhile.
import type { Data } from "../data.ts";
import { join, SEP } from "../data.ts";
import { t } from "../i18n.ts";
import { arr as arrU, equal, get as getU, isObject } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

/// The prefix of the keys the core gives chats not made yet: no station's session key starts so.
export const PENDING_PREFIX = "new:";

/// A chat asked for here (`chat.create`): until its station has made it, it is shown from what is known here.
export type Pending = {
  station: string;
  /// What `POST /sessions` is sent.
  ask: J;
  createdAt: number;
  /// What was sent to it before it was made, oldest first: as the outbox has them.
  queue: J[];
  /// Why it could not be made, the last time it was tried.
  failed: string | null;
  /// Its session and thread, once made.
  made: [string, number] | null;
  /// Its station has listed it: from then on its row is the station's alone.
  listed: boolean;
  /// Asked for, not answered yet (a restart asks again).
  making: boolean;
};

/// An agent's first messages, sent before it has a chat.
export type First = { queue: J[]; making: boolean; failed: string | null };

/// A chat changed from here (`chat.rename`, `chat.pin`, `chat.keep`, `chat.archive`), until its station's rows have it.
export type Change = {
  id: number;
  station: string;
  thread: number | null;
  session: string;
  /// What its station's row says once it is done.
  row: Record<string, unknown>;
  /// Out of the archive (or into it): what its page says meanwhile.
  archived: boolean | null;
  /// Done: its station's rows as they were when it answered (`undefined`: not answered).
  done?: { rows: unknown };
};

/// What changed here, for the views to show it anew.
export type LocalChange =
  | { kind: "outbox"; station: string; thread: number }
  | { kind: "pending"; key: string }
  | { kind: "first"; station: string; key: string }
  | { kind: "changing"; station: string }
  | { kind: "archiving" };

const OUTBOX = "outbox";
const PENDING = "pending";
const FIRST = "first";
const CHANGING = "changing";

export class Local {
  readonly #data: Data;
  readonly #now: () => number;
  #sent = 0;
  #changes = 0;
  readonly #outbox = new Map<string, J[]>();
  readonly #pending = new Map<string, Pending>();
  readonly #firsts = new Map<string, First>();
  readonly #changing: Change[] = [];
  /// Chats on their way into the archive from here: station, thread (none: an agent with no chat), session.
  readonly #archiving: [string, number | null, string][] = [];
  /// Recent outbox-to-message identities (the UI may skip the acknowledgement frame), by `station␁thread␁seq`.
  readonly delivered = new Map<string, string>();
  /// Messages sent from here that their station has taken: station, thread, seq.
  readonly #sentIn: [string, number, number][] = [];
  onChange: (change: LocalChange) => void = () => {};

  constructor(data: Data, now: () => number) {
    this.#data = data;
    this.#now = now;
    // What was kept: each record as it was left, the counters past what it used.
    for (const [key, list] of data.records(OUTBOX)) {
      if (Array.isArray(list) && list.length > 0) this.#outbox.set(key, list);
    }
    for (const [key, chat] of data.records(PENDING)) {
      if (isObject(chat)) this.#pending.set(key.slice(key.indexOf(SEP) + 1), chat as unknown as Pending);
    }
    for (const [key, first] of data.records(FIRST)) if (isObject(first)) this.#firsts.set(key, first as unknown as First);
    for (const [, change] of data.records(CHANGING)) if (isObject(change)) this.#changing.push(change as unknown as Change);
    const ids = [...this.#outbox.values(), ...[...this.#pending.values()].map((p) => p.queue), ...[...this.#firsts.values()].map((f) => f.queue)].flat();
    for (const m of ids) {
      const n = Number(String(get(m, "id") ?? "").slice(4));
      if (Number.isInteger(n)) this.#sent = Math.max(this.#sent, n);
    }
    for (const c of this.#changing) this.#changes = Math.max(this.#changes, c.id);
  }

  #nextId(): string {
    this.#sent++;
    return `out-${this.#sent}`;
  }

  // ── chats asked for here ──

  #savePending(key: string): void {
    const chat = this.#pending.get(key);
    if (chat) this.#data.put(PENDING, join([chat.station, key]), chat, false);
  }

  pendingNew(station: string, ask: J): string {
    const now = this.#now();
    const key = `${PENDING_PREFIX}${Math.round(now)}-${++this.#sent}`;
    this.#pending.set(key, { station, ask, createdAt: now, queue: [], failed: null, made: null, listed: false, making: false });
    this.#savePending(key);
    this.onChange({ kind: "pending", key });
    return key;
  }

  /// A chat asked for here, on this station: undefined when it is none; null while not made; its thread once made.
  pendingThread(station: string, key: string): number | null | undefined {
    const chat = this.#pending.get(key);
    if (!chat || chat.station !== station) return undefined;
    return chat.made ? chat.made[1] : null;
  }

  pending(key: string): Pending | undefined {
    return this.#pending.get(key);
  }

  /// The chats asked for and not answered: what a restart asks for again.
  unmade(): string[] {
    return [...this.#pending].filter(([, c]) => c.made === null && c.making).map(([k]) => k);
  }

  /// What to ask its station for, the chat set to be tried (again): its queue is `sending` once more. The ask carries
  /// its key here (`clientKey`): the station's rows say it of the chat made from it.
  pendingTry(key: string): [string, J] | null {
    const chat = this.#pending.get(key);
    if (!chat || chat.made) return null;
    chat.failed = null;
    chat.making = true;
    for (const m of chat.queue) {
      m.state = "sending";
      m.error = null;
    }
    this.#savePending(key);
    this.onChange({ kind: "pending", key });
    const ask = isObject(chat.ask) ? { ...chat.ask, clientKey: key } : chat.ask;
    return [chat.station, ask];
  }

  pendingQueue(key: string, message: J): string | null {
    const chat = this.#pending.get(key);
    if (!chat || chat.made) return null;
    const id = this.#nextId();
    chat.queue.push({ ...message, id, after: 0, createdAt: Math.round(this.#now()), state: chat.failed !== null ? "failed" : "sending", error: chat.failed });
    this.#savePending(key);
    this.onChange({ kind: "pending", key });
    return id;
  }

  /// Drops a message waiting for its chat to be made; a chat whose every message is dropped after it failed is given
  /// up (true then).
  pendingDiscard(key: string, id: string): boolean {
    const chat = this.#pending.get(key);
    if (!chat || chat.made) return false;
    chat.queue = chat.queue.filter((m) => m.id !== id);
    const gone = chat.queue.length === 0 && chat.failed !== null;
    if (gone) {
      this.#pending.delete(key);
      this.#data.forgetRecord(PENDING, join([chat.station, key]));
    } else this.#savePending(key);
    this.onChange({ kind: "pending", key });
    return gone;
  }

  pendingFailedNow(key: string): boolean {
    const chat = this.#pending.get(key);
    return !!chat && chat.made === null && chat.failed !== null;
  }

  pendingFailed(key: string, error: string): void {
    const chat = this.#pending.get(key);
    if (chat && !chat.made) {
      chat.failed = error;
      chat.making = false;
      for (const m of chat.queue) {
        m.state = "failed";
        m.error = error;
      }
      this.#savePending(key);
    }
    this.onChange({ kind: "pending", key });
  }

  /// Its station made it: what waited goes to the chat's outbox, in order, and is answered (id, message) to send.
  pendingMade(key: string, session: string, thread: number): [string, J][] {
    const chat = this.#pending.get(key);
    if (!chat || chat.made) return [];
    chat.made = [session, thread];
    chat.making = false;
    const queue = chat.queue;
    chat.queue = [];
    this.#savePending(key);
    const sends = queue.map((m) => [String(m.id ?? ""), sentAs(m)] as [string, J]);
    if (queue.length > 0) this.#outboxPut(chat.station, thread, [...this.outbox(chat.station, thread), ...queue]);
    this.onChange({ kind: "pending", key });
    this.onChange({ kind: "outbox", station: chat.station, thread });
    return sends;
  }

  /// The rows of the chats asked for here on a station that its rows do not have yet (see views.rs `pending_rows`).
  pendingRows(station: string, rows: J[]): J[] {
    const out: J[] = [];
    for (const [key, chat] of this.#pending) {
      if (chat.station !== station) continue;
      const first = chat.queue[0] ?? (chat.made ? this.outbox(station, chat.made[1])[0] : undefined);
      const text = String(get(first, "text") ?? "").trim();
      const title = text.split("\n").map((l) => l.trim()).find((l) => l !== "") ?? null;
      const theirs = rows.findIndex((r) => (chat.made ? get(r, "id") === chat.made[0] : get(r, "clientKey") === key));
      if (theirs >= 0) {
        if (chat.made && !chat.listed) {
          chat.listed = true;
          this.#savePending(key);
        }
        const last = get(rows[theirs], "last");
        if (title !== null && (last === undefined || last === null)) rows[theirs] = { ...rows[theirs], title };
        continue;
      }
      if (chat.listed) continue;
      if (first === undefined && chat.made === null) continue;
      const [id, thread] = chat.made ? [chat.made[0], chat.made[1]] : [key, null];
      const row: J = {
        id,
        session: id,
        thread,
        title: title ?? t("core-views.new_chat"),
        agents: [],
        last: null,
        unread: false,
        mine: true,
        lastActiveAt: Math.round(chat.createdAt),
        connect: null,
        origin: null,
        clientKey: key,
      };
      if (chat.made === null) row.pending = true;
      out.push(row);
    }
    return out;
  }

  // ── an agent's first messages ──

  #firstKey(station: string, key: string): string {
    return join([station, key]);
  }

  #saveFirst(k: string): void {
    const first = this.#firsts.get(k);
    if (first) this.#data.put(FIRST, k, first, false);
    else this.#data.forgetRecord(FIRST, k);
  }

  /// A message sent to an agent with no chat yet: its id, and whether its chat is to be asked for now.
  firstQueue(station: string, key: string, message: J): [string, boolean] {
    const k = this.#firstKey(station, key);
    const id = this.#nextId();
    let first = this.#firsts.get(k);
    if (!first) {
      first = { queue: [], making: false, failed: null };
      this.#firsts.set(k, first);
    }
    first.queue.push({ ...message, id, after: 0, createdAt: Math.round(this.#now()), state: "sending" });
    const ask = !first.making;
    this.#saveFirst(k);
    if (ask) this.firstTry(station, key);
    else this.onChange({ kind: "first", station, key });
    return [id, ask];
  }

  firstTry(station: string, key: string): boolean {
    const k = this.#firstKey(station, key);
    const first = this.#firsts.get(k);
    if (!first || first.queue.length === 0) return false;
    first.making = true;
    first.failed = null;
    for (const m of first.queue) {
      m.state = "sending";
      m.error = null;
    }
    this.#saveFirst(k);
    this.onChange({ kind: "first", station, key });
    return true;
  }

  firstWaits(station: string, key: string): boolean {
    return (this.#firsts.get(this.#firstKey(station, key))?.queue.length ?? 0) > 0;
  }

  /// The agents whose chats were asked for and not answered: what a restart asks for again.
  firstsMaking(): [string, string][] {
    return [...this.#firsts].filter(([, f]) => f.making).map(([k]) => {
      const at = k.indexOf(SEP);
      return [k.slice(0, at), k.slice(at + 1)];
    });
  }

  firstFailed(station: string, key: string, error: string): void {
    const k = this.#firstKey(station, key);
    const first = this.#firsts.get(k);
    if (first) {
      first.making = false;
      first.failed = error;
      for (const m of first.queue) {
        m.state = "failed";
        m.error = error;
      }
      this.#saveFirst(k);
    }
    this.onChange({ kind: "first", station, key });
  }

  firstDiscard(station: string, key: string, id: string): void {
    const k = this.#firstKey(station, key);
    const first = this.#firsts.get(k);
    if (first) {
      first.queue = first.queue.filter((m) => m.id !== id);
      if (first.queue.length === 0 && !first.making) this.#firsts.delete(k);
      this.#saveFirst(k);
    }
    this.onChange({ kind: "first", station, key });
  }

  firstMade(station: string, key: string, thread: number): [string, J][] {
    const k = this.#firstKey(station, key);
    const queue = this.#firsts.get(k)?.queue ?? [];
    this.#firsts.delete(k);
    this.#saveFirst(k);
    const sends = queue.map((m) => [String(m.id ?? ""), sentAs(m)] as [string, J]);
    if (queue.length > 0) this.#outboxPut(station, thread, [...this.outbox(station, thread), ...queue]);
    this.onChange({ kind: "first", station, key });
    this.onChange({ kind: "outbox", station, thread });
    return sends;
  }

  firstOutbox(station: string, key: string): J[] {
    return structuredClone(this.#firsts.get(this.#firstKey(station, key))?.queue ?? []);
  }

  // ── the outbox ──

  #outboxPut(station: string, thread: number, list: J[]): void {
    const k = join([station, thread]);
    if (list.length === 0) {
      if (this.#outbox.delete(k)) this.#data.forgetRecord(OUTBOX, k);
      return;
    }
    this.#outbox.set(k, list);
    this.#data.put(OUTBOX, k, list, false);
  }

  /// What waits to go into a chat, oldest first.
  outbox(station: string, thread: number): J[] {
    return this.#outbox.get(join([station, thread])) ?? [];
  }

  /// Every chat with something in its outbox: what a restart sends again.
  outboxes(): [string, number, J[]][] {
    return [...this.#outbox].map(([k, list]) => {
      const at = k.indexOf(SEP);
      return [k.slice(0, at), Number(k.slice(at + 1)), list];
    });
  }

  /// Puts back a chat's outbox as its view found it (what arrived goes).
  outboxSettle(station: string, thread: number, list: J[]): void {
    if (equal(list, this.outbox(station, thread))) return;
    this.#outboxPut(station, thread, list);
  }

  /// A message on its way to a chat: shown in it at once, as `sending`. `after`: the chat's newest entry then.
  outboxAdd(station: string, thread: number, message: J, after: number): string {
    const id = this.#nextId();
    this.#outboxPut(station, thread, [...this.outbox(station, thread), { ...message, id, after, createdAt: Math.round(this.#now()), state: "sending" }]);
    this.onChange({ kind: "outbox", station, thread });
    return id;
  }

  outboxGet(station: string, thread: number, id: string): J | undefined {
    return this.outbox(station, thread).find((m) => m.id === id);
  }

  /// Marks an outgoing message `sending` again, or `failed` with the error's message.
  outboxState(station: string, thread: number, id: string, failed: string | null): void {
    const list = this.outbox(station, thread).map((m) => (m.id === id ? { ...m, state: failed !== null ? "failed" : "sending", error: failed } : m));
    this.#outboxPut(station, thread, list);
    this.onChange({ kind: "outbox", station, thread });
  }

  /// The station has the message as entry `seq`: it stays until the chat's entries reach it. `shown`: whether a page
  /// shows the chat (else it goes now, but for a chat asked for here, whose page is on its way to it).
  outboxSent(station: string, thread: number, id: string, seq: number, shown: boolean): void {
    this.#sentIn.push([station, thread, seq]);
    if (this.#sentIn.length > 256) this.#sentIn.shift();
    const madeHere = [...this.#pending.values()].some((c) => c.station === station && c.made?.[1] === thread);
    if (!madeHere && !shown) return this.outboxRemove(station, thread, id);
    this.#outboxPut(station, thread, this.outbox(station, thread).map((m) => (m.id === id ? { ...m, seq } : m)));
    this.onChange({ kind: "outbox", station, thread });
  }

  outboxRemove(station: string, thread: number, id: string): void {
    this.#outboxPut(station, thread, this.outbox(station, thread).filter((m) => m.id !== id));
    this.onChange({ kind: "outbox", station, thread });
  }

  /// Whether the card at `seq` in a chat is answered from here: something sent is on its way into it (not failed), or
  /// went in after the card.
  answered(station: string, thread: number, seq: number): boolean {
    return this.outbox(station, thread).some((m) => m.state !== "failed") || this.#sentIn.some(([s, t, n]) => s === station && t === thread && n > seq);
  }

  // ── archiving and changing ──

  archiving(station: string, thread: number | null, session: string, on: boolean): void {
    if (on) this.#archiving.push([station, thread, session]);
    else {
      const i = this.#archiving.findIndex(([s, t, k]) => s === station && t === thread && k === session);
      if (i >= 0) this.#archiving.splice(i, 1);
    }
    this.onChange({ kind: "archiving" });
  }

  beingArchived(station: string, row: J): boolean {
    return this.#archiving.some(([s, thread, session]) => s === station && (thread !== null ? get(row, "thread") === thread : get(row, "session") === session));
  }

  changing(station: string, thread: number | null, session: string, row: Record<string, unknown>, archived: boolean | null): number {
    const id = ++this.#changes;
    const change: Change = { id, station, thread, session, row, archived };
    this.#changing.push(change);
    this.#data.put(CHANGING, join([station, id]), change, false);
    this.onChange({ kind: "changing", station });
    return id;
  }

  /// Answered: refused (`ok` false), as it was at once; done, shown so until its station's rows change from `rows`.
  changed(id: number, ok: boolean, rows: unknown): void {
    const i = this.#changing.findIndex((c) => c.id === id);
    if (i < 0) return;
    const change = this.#changing[i];
    if (ok) {
      change.done = { rows: rows ?? null };
      this.#data.put(CHANGING, join([change.station, id]), change, false);
      return;
    }
    this.#changing.splice(i, 1);
    this.#data.forgetRecord(CHANGING, join([change.station, id]));
    this.onChange({ kind: "changing", station: change.station });
  }

  /// Lets go of what is done that its station's rows have had since.
  settle(station: string, rows: unknown): void {
    for (let i = this.#changing.length - 1; i >= 0; i--) {
      const c = this.#changing[i];
      if (c.station !== station || c.done === undefined) continue;
      if (!equal(c.done.rows, rows ?? null)) {
        this.#changing.splice(i, 1);
        this.#data.forgetRecord(CHANGING, join([c.station, c.id]));
      }
    }
  }

  /// Whether any change of a station's is done and waits for its rows to have it.
  settling(station: string): boolean {
    return this.#changing.some((c) => c.station === station && c.done !== undefined);
  }

  static #matches(c: Change, station: string, thread: number | null, session: string | null): boolean {
    return c.station === station && (c.thread !== null ? thread === c.thread : session === c.session);
  }

  /// A station's row as the changes from here have it, oldest first (a copy when any applies).
  asChanging(station: string, row: J): J {
    const thread = typeof get(row, "thread") === "number" ? row.thread : null;
    const session = typeof get(row, "session") === "string" ? row.session : null;
    let out = row;
    for (const c of this.#changing) {
      if (!Local.#matches(c, station, thread, session)) continue;
      if (out === row) out = { ...row };
      Object.assign(out, c.row);
    }
    return out;
  }

  /// Whether a chat's page is being taken out of the archive (false) or put in it (true), from here.
  archivedChanging(station: string, thread: number | null, session: string | null): boolean | null {
    for (let i = this.#changing.length - 1; i >= 0; i--) {
      const c = this.#changing[i];
      if (Local.#matches(c, station, thread, session) && c.archived !== null) return c.archived;
    }
    return null;
  }

  restoring(station: string, row: J): boolean {
    const thread = typeof get(row, "thread") === "number" ? row.thread : null;
    const session = typeof get(row, "session") === "string" ? row.session : null;
    return this.archivedChanging(station, thread, session) === false;
  }

  /// Changes not answered when the core last stopped: their answers will not come; refused, as they were.
  forgetUnanswered(): void {
    for (let i = this.#changing.length - 1; i >= 0; i--) {
      const c = this.#changing[i];
      if (c.done !== undefined) continue;
      this.#changing.splice(i, 1);
      this.#data.forgetRecord(CHANGING, join([c.station, c.id]));
    }
  }

  /// The identity of an entry sent from here, once it arrived.
  remember(station: string, thread: number, seq: number, id: string): void {
    const k = join([station, thread, seq]);
    if (this.delivered.has(k)) return;
    this.delivered.set(k, id);
    if (this.delivered.size > 512) this.delivered.delete(this.delivered.keys().next().value!);
  }

  outgoing(station: string, thread: number, seq: number): string | undefined {
    return this.delivered.get(join([station, thread, seq]));
  }
}

/// What an outbox entry sends to its station: its words, files and quotes, and the app it was sent from if said.
export function sentAs(entry: J): J {
  const message: J = { text: entry.text ?? null, attachments: entry.attachments ?? null, quotes: entry.quotes ?? null };
  if (typeof entry.client === "string") message.client = entry.client;
  return message;
}
