// What a person did here that their station has not confirmed yet (docs/core-ts.md, rules 3 and 4): messages on
// their way (the outbox), chats asked for and not made (pending), messages to an agent before it has a chat (firsts),
// chats renamed, pinned, kept or archived (changing, archiving). Each is held here and kept in its account's database
// (tables outbox, pending, first, changing: written again on their own if the rest could not be), so it shows at once,
// survives a restart, and goes on where it was; the views lay it over what the stations hold. Nothing here waits on
// the network: the calls that change it answer as their station has it, the views show it meanwhile.
import type { Data } from "../data.ts";
import { join, SEP } from "../data.ts";
import type { AccountDb } from "../db/account.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { localId } from "../ids.ts";
import { arr as arrU, equal, get as getU, isObject } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

/// The prefix of the keys the core gives chats not made yet: no station's session key starts so.
export const PENDING_PREFIX = "new:";

/// A key for a chat asked for here: named as the core names what it makes here (localId), not by the clock: a recorded
/// new chat's key comes again in its replay.
export function pendingKeyMade(): string {
  return `${PENDING_PREFIX}${localId("chat")}`;
}

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
  /// Not asked for: its station was down as it was to be (asked once the station is reached again).
  unsent?: boolean;
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
  /// Done: how often its station's rows had changed when it answered (`undefined`: not answered); shown so until they
  /// change again.
  done?: { rev: number };
};

/// What changed here, for the views to show it anew.
export type LocalChange =
  /// `chat`: what changed shows in the chat alone (a message the station took), not in any list.
  | { kind: "outbox"; station: string; thread: number; chat?: true }
  | { kind: "pending"; key: string }
  | { kind: "first"; station: string; key: string }
  | { kind: "changing"; station: string }
  | { kind: "archiving" }
  | { kind: "letGo"; station: string; thread: number }
  /// A vault request decided here (`request`): its card off the 奏 page, how it went on its card in its chat.
  | { kind: "vault"; request: string };

/// How a vault request decided here went, as its station restates its card (station/src/vault/secrets.ts #settle).
export type VaultOutcome = { status: "granted" | "denied"; scope?: "once" | "hour" | "chat"; timeout?: { kind: "idle" | "fixed"; seconds: number } };

/// The name a station keeps an upload under: the last part of its path, wherever it is moved.
const keptName = (path: string) => path.split("/").at(-1)!;
const OUTBOX = "outbox";
const PENDING = "pending";
const FIRST = "first";
const CHANGING = "changing";

export class Local {
  readonly #data: Data;
  readonly #now: () => number;
  #changes = 0;
  readonly #outbox = new Map<string, J[]>();
  readonly #pending = new Map<string, Pending>();
  readonly #pendingDb = new Map<string, AccountDb>();
  /// The station's session back to the key this device created it with, kept across restarts.
  readonly #made = new Map<string, string>();
  readonly #firsts = new Map<string, First>();
  readonly #changing: Change[] = [];
  /// Chats on their way into the archive from here: station, thread (none: an agent with no chat), session.
  readonly #archiving: [string, number | null, string][] = [];
  /// Recent outbox-to-message identities (the UI may skip the acknowledgement frame), by `station␁thread␁seq`.
  readonly delivered = new Map<string, string>();
  /// Files put up from here (from this device's bytes, or while their message waited), by the name the station keeps
  /// each under (unique; it keeps it as it moves the file into the chat's uploads): the upload each was here
  /// (`composer.add`'s id), whose picture this device still has (the latest few).
  readonly #uploadedFrom = new Map<string, string>();
  /// Messages sent from here that their station has taken: station, thread, seq.
  readonly #sentIn: [string, number, number][] = [];
  /// Cards let go from here (`decision.dismiss`): station, thread, seq, and once the station took it how often its rows
  /// had changed then (data.rowsRev).
  readonly #lettingGo: { station: string; thread: number; seq: number; done?: number }[] = [];
  /// Vault requests decided here (their cards' `vault`) and how: the latest few.
  readonly #vaultDecided: { request: string; outcome: VaultOutcome }[] = [];
  onChange: (change: LocalChange) => void = () => {};
  onMade: (station: string, key: string) => void = () => {};

  constructor(data: Data, now: () => number) {
    this.#data = data;
    this.#now = now;
  }

  /// What was kept in the accounts' databases: each as it was left, the counters past what it used.
  load(): void {
    for (const db of this.#data.dbs()) this.opened(db);
  }

  /// What an account's database keeps of what was done here (it was opened: at start, or signed in).
  opened(db: AccountDb): void {
    for (const [station, thread, list] of db.locals(OUTBOX)) {
      if (Array.isArray(list) && list.length > 0) this.#outbox.set(join([station, thread]), list);
    }
    for (const [, key, chat] of db.locals(PENDING)) if (isObject(chat)) {
      const pending = chat as unknown as Pending;
      this.#pending.set(key, pending);
      this.#pendingDb.set(key, db);
      if (pending.made) this.#made.set(join([pending.station, pending.made[0]]), key);
    }
    for (const [station, key, first] of db.locals(FIRST)) if (isObject(first)) this.#firsts.set(join([station, key]), first as unknown as First);
    for (const [, , change] of db.locals(CHANGING)) if (isObject(change) && !this.#changing.some((c) => c.station === change.station && c.id === change.id)) this.#changing.push(change as unknown as Change);
    for (const c of this.#changing) this.#changes = Math.max(this.#changes, c.id);
  }

  #nextId(): string {
    return localId("out");
  }

  // ── chats asked for here ──

  #savePending(key: string): void {
    const chat = this.#pending.get(key);
    if (chat) this.#data.putLocal(PENDING, chat.station, key, chat);
  }

  /// `key`: the one the page named it by as its first words were sent (the `newChat` topic's `next`), else one made now.
  pendingNew(station: string, ask: J, key: string = pendingKeyMade()): string {
    if (!key.startsWith(PENDING_PREFIX) || this.#pending.has(key)) throw CoreError.invalid("newChat.create: a key already used");
    const now = this.#now();
    this.#pending.set(key, { station, ask, createdAt: now, queue: [], failed: null, made: null, listed: false, making: false });
    const db = this.#data.of(station);
    if (db) this.#pendingDb.set(key, db);
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

  /// A made chat's original key, from either name, only in the account that keeps this station now.
  pendingKey(station: string, session: string): string | undefined {
    const key = this.#made.get(join([station, session])) ?? session;
    const pending = this.#pending.get(key);
    const db = this.#data.of(station);
    return db && this.#pendingDb.get(key) === db && pending?.station === station && pending.made ? key : undefined;
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
    chat.unsent = undefined;
    for (const m of chat.queue) {
      m.state = "sending";
      m.error = null;
      delete m.unreached;
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
    chat.queue.push({ ...message, id, after: 0, createdAt: Math.round(this.#now()), state: chat.failed !== null ? "failed" : "sending", error: chat.failed, ...(chat.failed !== null && chat.unsent === true ? { unreached: true } : {}) });
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
      this.#pendingDb.delete(key);
      this.#data.putLocal(PENDING, chat.station, key, undefined);
    } else this.#savePending(key);
    this.onChange({ kind: "pending", key });
    return gone;
  }

  pendingFailedNow(key: string): boolean {
    const chat = this.#pending.get(key);
    return !!chat && chat.made === null && chat.failed !== null;
  }

  /// `unsent`: it was not asked for (its station down), and is once the station is reached again.
  pendingFailed(key: string, error: string, unsent = false): void {
    const chat = this.#pending.get(key);
    if (chat && !chat.made) {
      chat.failed = error;
      chat.making = false;
      chat.unsent = unsent || undefined;
      for (const m of chat.queue) {
        m.state = "failed";
        m.error = error;
        if (unsent) m.unreached = true;
        else delete m.unreached;
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
    this.#made.set(join([chat.station, session]), key);
    chat.making = false;
    const queue = chat.queue;
    chat.queue = [];
    this.#savePending(key);
    this.onMade(chat.station, key);
    const sends = queue.map((m) => [String(m.id ?? ""), sentAs(m)] as [string, J]);
    if (queue.length > 0) this.#outboxPut(chat.station, thread, [...this.outbox(chat.station, thread), ...queue]);
    this.onChange({ kind: "pending", key });
    this.onChange({ kind: "outbox", station: chat.station, thread });
    return sends;
  }

  /// The rows of the chats asked for here on a station that its rows do not have yet (see views.rs `pending_rows`).
  pendingRows(station: string): J[] {
    const out: J[] = [];
    for (const [key, chat] of this.#pending) {
      if (chat.station !== station) continue;
      const theirs: J = chat.made ? this.#data.chat(station, chat.made[0]) : this.#data.chatOfClientKey(station, key);
      if (theirs !== undefined) {
        if (chat.made && !chat.listed) {
          chat.listed = true;
          this.#savePending(key);
        }
        continue;
      }
      if (chat.listed) continue;
      if (this.#firstOf(chat) === undefined && chat.made === null) continue;
      const [id, thread] = chat.made ? [chat.made[0], chat.made[1]] : [key, null];
      const row: J = {
        id,
        session: id,
        thread,
        // named by no one yet: what its station will call it till then (views.ts chatTitle)
        title: t("core-views.new_chat"),
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

  #firstOf(chat: Pending): J {
    return chat.queue[0] ?? (chat.made ? this.outbox(chat.station, chat.made[1])[0] : undefined);
  }

  // ── an agent's first messages ──

  #firstKey(station: string, key: string): string {
    return join([station, key]);
  }

  #saveFirst(k: string): void {
    const first = this.#firsts.get(k);
    const at = k.indexOf(SEP);
    this.#data.putLocal(FIRST, k.slice(0, at), k.slice(at + 1), first);
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
      if (this.#outbox.delete(k)) this.#data.putLocal(OUTBOX, station, String(thread), undefined);
      return;
    }
    this.#outbox.set(k, list);
    this.#data.putLocal(OUTBOX, station, String(thread), list);
  }

  /// What waits to go into a chat, oldest first.
  outbox(station: string, thread: number): J[] {
    return this.#outbox.get(join([station, thread])) ?? [];
  }

  /// A station's messages that failed as it was not reached, oldest first in each chat; and its chats asked for here and
  /// not asked of it, its having been down: what goes once it is reached again.
  unreached(station: string): { messages: [number, string][]; chats: string[] } {
    const messages: [number, string][] = [];
    for (const [s, thread, list] of this.outboxes()) {
      if (s !== station) continue;
      for (const m of list) if (m.state === "failed" && m.unreached === true && m.final !== true) messages.push([thread, String(m.id)]);
    }
    const chats = [...this.#pending].filter(([, c]) => c.station === station && c.made === null && !c.making && c.unsent === true).map(([k]) => k);
    return { messages, chats };
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

  /// A queued message cannot be acknowledged by equal text until its own POST has started.
  outboxDelivering(station: string, thread: number, id: string): void {
    this.#outboxPut(station, thread, this.outbox(station, thread).map((m) => m.id === id ? { ...m, queued: false } : m));
  }

  /// Persist resolved attachments before delivery, so a retry/restart never needs their source Blobs again.
  outboxUploaded(station: string, thread: number, id: string, files: J[]): void {
    const uploads = this.outboxGet(station, thread, id)?.uploads;
    files.forEach((f, i) => this.uploadedHere(station, get(f, "path"), get(arr(uploads)[i], "id")));
    this.#outboxPut(station, thread, this.outbox(station, thread).map((m) => m.id === id ? { ...m, attachments: [...(m.attachments ?? []), ...files], uploads: [] } : m));
    this.onChange({ kind: "outbox", station, thread });
  }

  /// A file went up to `station` from here as upload `from` (`composer.add`'s id) and is kept there at `path`: its
  /// messages say so (`uploadOf`), the latest 64.
  uploadedHere(station: string, path: unknown, from: unknown): void {
    if (typeof from !== "string" || typeof path !== "string") return;
    const key = `${station}\n${keptName(path)}`;
    this.#uploadedFrom.delete(key);
    this.#uploadedFrom.set(key, from);
    while (this.#uploadedFrom.size > 64) this.#uploadedFrom.delete(this.#uploadedFrom.keys().next().value!);
  }

  /// The upload (`composer.add`'s id) a file of `station` kept at `path` was here (`uploadedHere`).
  uploadOf(station: string, path: unknown): string | undefined {
    return typeof path === "string" ? this.#uploadedFrom.get(`${station}\n${keptName(path)}`) : undefined;
  }

  outboxGet(station: string, thread: number, id: string): J | undefined {
    return this.outbox(station, thread).find((m) => m.id === id);
  }

  /// The first message sent here into a chat that did not go (failed: waiting to be sent again or dropped), for its
  /// row to say so: by its thread, or, a chat asked for here and not made yet, by its key.
  unsent(station: string, thread: number | null, key: string | null): J | undefined {
    const pending = key !== null ? this.#pending.get(key) : undefined;
    const queue = thread !== null ? this.outbox(station, thread) : pending?.station === station ? pending.queue : [];
    return queue.find((m) => m.state === "failed");
  }

  /// Marks an outgoing message `sending` again, or `failed` with the error's message (`final`: refused as it is, not to
  /// be sent again).
  /// `unreached`: it failed as its station was not reached (sent again once it is: its idempotency key makes it go once).
  outboxState(station: string, thread: number, id: string, failed: string | null, final = false, unreached = false): void {
    const list = this.outbox(station, thread).map((m) => (m.id === id ? { ...m, state: failed !== null ? "failed" : "sending", error: failed, final: failed !== null && final ? true : undefined, unreached: failed !== null && unreached ? true : undefined } : m));
    this.#outboxPut(station, thread, list);
    this.onChange({ kind: "outbox", station, thread });
  }

  /// The station has the message as entry `seq`: it is `sent`, and stays until the chat's entries reach it. `shown`:
  /// whether a page shows the chat (else it goes now, but for a chat asked for here, whose page is on its way to it).
  outboxSent(station: string, thread: number, id: string, seq: number, shown: boolean): void {
    this.#sentIn.push([station, thread, seq]);
    if (this.#sentIn.length > 256) this.#sentIn.shift();
    const madeHere = [...this.#pending.values()].some((c) => c.station === station && c.made?.[1] === thread);
    if (!madeHere && !shown) return this.outboxRemove(station, thread, id);
    this.#outboxPut(station, thread, this.outbox(station, thread).map((m) => (m.id === id ? { ...m, seq, state: "sent" } : m)));
    this.onChange({ kind: "outbox", station, thread, chat: true });
  }

  outboxRemove(station: string, thread: number, id: string): void {
    this.#outboxPut(station, thread, this.outbox(station, thread).filter((m) => m.id !== id));
    this.onChange({ kind: "outbox", station, thread });
  }

  /// What an upload has come to after the message it goes with was sent: an image's size (a big one takes a while to
  /// read), so its row holds the image's own shape before it is up, not a fixed box that changes once it is; how much of
  /// it the station has, so its card says how far it has gone. That message's upload takes it wherever it waits.
  uploadChanged(upload: string, patch: { width?: number; height?: number; sent?: number }): void {
    const changes = (u: J) => get(u, "id") === upload && Object.entries(patch).some(([k, v]) => get(u, k) !== v);
    const changed = (list: J[]): J[] | null => {
      if (!list.some((m) => arr(get(m, "uploads")).some(changes))) return null;
      return list.map((m) => arr(get(m, "uploads")).some((u) => get(u, "id") === upload)
        ? { ...m, uploads: arr(get(m, "uploads")).map((u) => get(u, "id") === upload ? { ...u, ...patch } : u) }
        : m);
    };
    for (const [k, list] of this.#outbox) {
      const next = changed(list);
      if (!next) continue;
      const at = k.indexOf(SEP);
      const [station, thread] = [k.slice(0, at), Number(k.slice(at + 1))];
      this.#outboxPut(station, thread, next);
      this.onChange({ kind: "outbox", station, thread });
    }
    for (const [key, chat] of this.#pending) {
      const next = changed(chat.queue);
      if (!next) continue;
      chat.queue = next;
      this.#savePending(key);
      this.onChange({ kind: "pending", key });
    }
    for (const [k, first] of this.#firsts) {
      const next = changed(first.queue);
      if (!next) continue;
      first.queue = next;
      this.#saveFirst(k);
      const at = k.indexOf(SEP);
      this.onChange({ kind: "first", station: k.slice(0, at), key: k.slice(at + 1) });
    }
  }

  /// Whether the card at `seq` in a chat is answered from here: something sent is on its way into it (not failed), or
  /// went in after the card.
  answered(station: string, thread: number, seq: number): boolean {
    return this.outbox(station, thread).some((m) => m.state !== "failed") || this.#sentIn.some(([s, t, n]) => s === station && t === thread && n > seq);
  }

  /// A card let go from here (`decision.dismiss`): off the 奏 page at once. Refused (`ok` false), it is back; taken,
  /// it stays off until its station's rows change from how they were then (`rev`), which then say it is dismissed.
  letGo(station: string, thread: number, seq: number): void {
    this.#lettingGo.push({ station, thread, seq });
    this.onChange({ kind: "letGo", station, thread });
  }

  letGoEnded(station: string, thread: number, seq: number, ok: boolean, rev: number): void {
    const i = this.#lettingGo.findIndex((l) => l.station === station && l.thread === thread && l.seq === seq && l.done === undefined);
    if (i < 0) return;
    if (ok) this.#lettingGo[i] = { ...this.#lettingGo[i], done: rev };
    else {
      this.#lettingGo.splice(i, 1);
      this.onChange({ kind: "letGo", station, thread });
    }
  }

  /// Whether the card at `seq` in a chat is let go from here.
  lettingGo(station: string, thread: number, seq: number): boolean {
    return this.#lettingGo.some((l) => l.station === station && l.thread === thread && l.seq === seq);
  }

  /// A vault request approved or turned down here (`outcome`): its card is off the 奏 page, and its card in its chat says
  /// how it went, at once (its station says so as it tells it).
  vaultDecided(request: string, outcome: VaultOutcome): void {
    if (this.decidedVault(request)) return;
    this.#vaultDecided.push({ request, outcome });
    if (this.#vaultDecided.length > 64) this.#vaultDecided.shift();
    this.onChange({ kind: "vault", request });
  }

  decidedVault(request: string): boolean {
    return this.vaultOutcome(request) !== undefined;
  }

  /// How a vault request decided here went (none: not decided here).
  vaultOutcome(request: string): VaultOutcome | undefined {
    return this.#vaultDecided.find((d) => d.request === request)?.outcome;
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
    this.#data.putLocal(CHANGING, station, String(id), change);
    this.onChange({ kind: "changing", station });
    return id;
  }

  /// Answered: refused (`ok` false), as it was at once; done, shown so until its station's rows change from how they
  /// were then (`rev`: how often they had changed, data.rowsRev).
  changed(id: number, ok: boolean, rev: number): void {
    const i = this.#changing.findIndex((c) => c.id === id);
    if (i < 0) return;
    const change = this.#changing[i];
    if (ok) {
      change.done = { rev };
      this.#data.putLocal(CHANGING, change.station, String(id), change);
      return;
    }
    this.#changing.splice(i, 1);
    this.#data.putLocal(CHANGING, change.station, String(id), undefined);
    this.onChange({ kind: "changing", station: change.station });
  }

  /// Lets go of what is done that its station's rows have had since (they changed after it answered).
  settle(station: string, rev: number): void {
    for (let i = this.#lettingGo.length - 1; i >= 0; i--) {
      const l = this.#lettingGo[i];
      if (l.station === station && l.done !== undefined && l.done !== rev) this.#lettingGo.splice(i, 1);
    }
    for (let i = this.#changing.length - 1; i >= 0; i--) {
      const c = this.#changing[i];
      if (c.station !== station || c.done === undefined) continue;
      if (c.done.rev !== rev) {
        this.#changing.splice(i, 1);
        this.#data.putLocal(CHANGING, c.station, String(c.id), undefined);
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
      this.#data.putLocal(CHANGING, c.station, String(c.id), undefined);
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
  if (Array.isArray(entry.cc) && entry.cc.length > 0) message.cc = entry.cc;
  return message;
}
