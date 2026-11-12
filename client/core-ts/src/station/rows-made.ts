// A station's sidebar (station/src/read/views.ts `chats`) made here, by the same rules, from what the device holds: the
// sessions' summaries (`sessions`), the threads' summaries as the viewer has them (`threads`), and what the station keeps
// beside them that no summary says (`marks`, GET /chats?marks=1: the cards and needs waiting, the review's marks, pins,
// shares…). Made by the station, every change read every row it could touch again for every viewer, from the disk while
// its machine was short of memory (3 to 10 s each on a station, 2026-11-03); the station keeps what is said and its
// statistics, a device makes what its pages show of them.
import { get, isObject } from "../util.ts";
import * as titles from "../titles.ts";
import { trim } from "../whitespace.ts";
import { type Own, rowFor } from "../chat-row.ts";
import { current, tr } from "../i18n.ts";
import { glanced, work } from "../work.ts";

type J = Record<string, any>;

/// How much of a chat's latest message its row says (views.ts LAST_CHARS).
const LAST_CHARS = 200;

/// What the station keeps beside the summaries (views.ts `chatMarks`).
export type Marks = {
  card: Record<string, J>;
  need: Record<string, J>;
  answered: Record<string, J[]>;
  suggested: number[];
  verdicts: Record<string, J>;
  reviews: boolean;
  kept: number[];
  hidden?: number[];
  muted?: number[];
  pins: Record<string, number>;
  openers: Record<string, J>;
  opened: Record<string, J[]>;
  shares: Record<string, J>;
  clientKeys: Record<string, string>;
  teams: Record<string, string>;
  selves: string[];
  /// The cards and needs the viewer let go (`<thread>:<seq>`), and where they read each chat to (chat-row.ts).
  dismissed: string[];
  reads: Record<string, number>;
};

/// The words a row says in the viewer's language.
export type Words = titles.TitleWords & { quotedOnly: string };

/// The words of the language the core speaks now, the same object while it is the same (what every row is made in:
/// RowsMemo `whole`, data.ts `inWords`).
let wordsNow: { lang: string; words: Words & { admin: string } } | null = null;
export function rowWords(): Words & { admin: string } {
  const lang = current();
  if (wordsNow?.lang !== lang) {
    wordsNow = { lang, words: { untitled: tr(lang, "core-views.new_chat"), directMessage: tr(lang, "core-views.direct_message"), quotedOnly: tr(lang, "station.chat.quotedOnly"), admin: tr(lang, "station.author.admin") } };
  }
  return wordsNow.words;
}

/// What a station's rows were last made of (`rowsMade`, `rowsShared`), kept on its link (link.ts `rows`): each row by a
/// key of its own, with what it was made of (`of`), so a row all of whose parts are as they were is the same object as
/// before (rule 6), and only those something changed are made again (work.ts `chatRowsMade`). Its parts are compared as
/// they are (===): the summaries and threads held are the database's rows, the same objects while unchanged
/// (account.ts); of the marks, each row takes what it reads, a value, or an entry's object, which the sync's events and
/// reads replace rather than change (sync.ts #held, `marksWith`), so the marks need no revision of their own. What every
/// row reads (whose rows they are, the words) is `whole`: all of them are made again as it changes. Empty, it holds
/// nothing, and the rows are made as they always were.
export type RowsMemo = { whole: string; rows: Map<string, { of: unknown[]; row: J }> };
export const rowsMemo = (): RowsMemo => ({ whole: "", rows: new Map() });

/// Makes each row through `memo`: `row(key, of, make)` gives the row made before under `key` where `of` is all as it
/// was, else `make`'s. `done` puts what was made this time in its place (a row not asked again is let go).
function through(memo: RowsMemo, whole: string) {
  const was = memo.whole === whole ? memo.rows : new Map<string, { of: unknown[]; row: J }>();
  const now = new Map<string, { of: unknown[]; row: J }>();
  const same = (a: unknown[], b: unknown[]) => a.length === b.length && a.every((v, i) => v === b[i]);
  return {
    row(key: string, of: unknown[], make: () => J): J {
      const before = was.get(key);
      let row: J;
      if (before !== undefined && same(before.of, of)) row = before.row;
      else {
        work.chatRowsMade++;
        // (frozen: the same object is the same row, data.ts `inWords`, account.ts `setChats`)
        row = Object.freeze(make());
      }
      now.set(key, { of, row });
      return row;
    },
    done(): void {
      memo.whole = whole;
      memo.rows = now;
    },
  };
}

/// What of the station's answer is marks (none where it is not: a station from before).
export function marksOf(answer: unknown): Marks | null {
  if (!isObject(answer) || !isObject(get(answer, "card"))) return null;
  // (copies: the marks held are changed in place as the station tells their changes, marksPut and those after it)
  const o = (k: string) => (isObject(get(answer, k)) ? { ...(get(answer, k) as J) } : {});
  const a = (k: string) => (Array.isArray(get(answer, k)) ? [...(get(answer, k) as any[])] : []);
  return {
    card: o("card"), need: o("need"), answered: o("answered"), suggested: a("suggested"), verdicts: o("verdicts"), reviews: get(answer, "reviews") === true,
    kept: a("kept"), ...(Array.isArray(get(answer, "hidden")) ? { hidden: a("hidden").filter((n): n is number => typeof n === "number") } : {}),
    ...(Array.isArray(get(answer, "muted")) ? { muted: a("muted").filter((n): n is number => typeof n === "number") } : {}),
    pins: o("pins"), openers: o("openers"), opened: o("opened"), shares: o("shares"), clientKeys: o("clientKeys"), teams: o("teams"),
    selves: a("selves").filter((s): s is string => typeof s === "string"),
    dismissed: a("dismissed").filter((s): s is string => typeof s === "string"),
    reads: o("reads"),
  };
}

/// Puts in the marks held those of some chats (`scope`'s, read again) in place of what was held of them. In place, by
/// the scope's keys: each entry the scope's is replaced (a row made of one compares it as it is, RowsMemo), the others
/// not looked at; of the lists of threads, those of the scope taken out, each list walked (glanced.marksWalked: they
/// are the older path's form of the marks, rowsMade's, and go with it, the marks then kept as OwnHeld alone).
export function marksPut(held: Marks, read: Marks, scope: { sessions: readonly string[]; threads: readonly number[] }): void {
  const threads = new Set(scope.threads);
  const byThread = (h: Record<string, any>, r: Record<string, any>) => {
    for (const id of scope.threads) delete h[String(id)];
    Object.assign(h, r);
  };
  const bySession = (h: Record<string, any>, r: Record<string, any>) => {
    for (const key of scope.sessions) delete h[key];
    Object.assign(h, r);
  };
  const ids = (h: number[], r: number[]) => {
    glanced.marksWalked += h.length;
    return [...h.filter((id) => !threads.has(id)), ...r];
  };
  byThread(held.card, read.card);
  byThread(held.need, read.need);
  byThread(held.answered, read.answered);
  byThread(held.verdicts, read.verdicts);
  byThread(held.reads, read.reads);
  held.suggested = ids(held.suggested, read.suggested);
  held.kept = ids(held.kept, read.kept);
  held.reviews = read.reviews;
  if (read.hidden !== undefined) held.hidden = ids(held.hidden ?? [], read.hidden);
  else delete held.hidden;
  if (read.muted !== undefined) held.muted = ids(held.muted ?? [], read.muted);
  else delete held.muted;
  bySession(held.pins, read.pins);
  bySession(held.openers, read.openers);
  bySession(held.opened, read.opened);
  bySession(held.shares, read.shares);
  bySession(held.clientKeys, read.clientKeys);
  Object.assign(held.teams, read.teams);
  held.selves = read.selves;
  glanced.marksWalked += held.dismissed.length;
  held.dismissed = [...held.dismissed.filter((d) => !threads.has(Number(d.slice(0, d.indexOf(":"))))), ...read.dismissed];
}

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/// Whether a person (a creator reference) is the viewer whose email is `me`, or a Slack user they are (`selves`).
export function mineFor(me: string, selves: readonly string[]): (p: unknown) => boolean {
  const email = me.toLowerCase();
  const slack = new Set(selves);
  return (p: unknown): boolean => {
    if (!isObject(p)) return false;
    const pid = str(get(p, "id")) ?? "";
    const pe = str(get(p, "email"));
    return pid === me || (pe !== null && pe.toLowerCase() === email) || (get(p, "via") === "slack" && slack.has(pid.slice(pid.lastIndexOf(":") + 1)));
  };
}

/// A row's place in the list its station makes for everyone: the latest active first, of the row alone, so that one row
/// is written in its place by its key (account.ts `putChat`), nothing else read; rows active at once go by their ids in
/// every read that orders by place (`ORDER BY ord, id`: chat-reads.ts, account.ts Collection).
export const sharedPlace = (row: J): number => -num(row.lastActiveAt) || 0;

/// The viewer's own of a station's marks (chat-row.ts Own) as maps and sets, so that one row's is found by its keys:
/// made of the marks as they are read whole (or replaced, or whose they are changed), then kept true by the changes that
/// change those marks (`markRead`, `markThread`, `markPin`, `markDismissed`, `scoped`), so that an event walks neither
/// the marks nor the rows. `stale`: something changed that a change by key cannot follow (whose rows they are, a mark a
/// station from before lacks): made again of the marks at the next remake.
export class OwnHeld implements Own {
  readonly marks: Marks;
  readonly me: string;
  readonly mine: (person: unknown) => boolean;
  readonly reads = new Map<number, number>();
  readonly dismissed = new Set<string>();
  readonly kept = new Set<number>();
  readonly hidden?: Set<number>;
  readonly muted?: Set<number>;
  readonly pins = new Map<string, number>();
  stale = false;
  /// Each thread's of `dismissed`, to let them go by the thread.
  readonly #letGo = new Map<number, string[]>();
  constructor(marks: Marks, me: string) {
    this.marks = marks;
    this.me = me;
    this.mine = mineFor(me, marks.selves);
    const reads = Object.entries(marks.reads);
    const pins = Object.entries(marks.pins);
    for (const [k, n] of reads) this.reads.set(Number(k), num(n));
    for (const d of marks.dismissed) this.#dismiss(d);
    for (const id of marks.kept) this.kept.add(id);
    if (marks.hidden !== undefined) this.hidden = new Set(marks.hidden);
    if (marks.muted !== undefined) this.muted = new Set(marks.muted);
    for (const [k, at] of pins) this.pins.set(k, num(at));
    glanced.marksWalked += reads.length + pins.length + marks.dismissed.length + marks.kept.length + (marks.hidden?.length ?? 0) + (marks.muted?.length ?? 0);
  }

  #dismiss(d: string): void {
    if (this.dismissed.has(d)) return;
    this.dismissed.add(d);
    const thread = Number(d.slice(0, d.indexOf(":")));
    this.#letGo.set(thread, [...(this.#letGo.get(thread) ?? []), d]);
  }

  /// Those of some chats read again (`read`, put in the marks by marksPut): false where they cannot be followed by key.
  scoped(read: Marks, scope: { sessions: readonly string[]; threads: readonly number[] }): boolean {
    const same = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every((v, i) => v === b[i]);
    if ((read.hidden === undefined) !== (this.hidden === undefined) || (read.muted === undefined) !== (this.muted === undefined) || !same(read.selves, this.marks.selves)) {
      this.stale = true;
      return false;
    }
    for (const id of scope.threads) {
      this.reads.delete(id);
      this.kept.delete(id);
      this.hidden?.delete(id);
      this.muted?.delete(id);
      for (const d of this.#letGo.get(id) ?? []) this.dismissed.delete(d);
      this.#letGo.delete(id);
    }
    for (const key of scope.sessions) this.pins.delete(key);
    for (const [k, n] of Object.entries(read.reads)) this.reads.set(Number(k), num(n));
    for (const d of read.dismissed) this.#dismiss(d);
    for (const id of read.kept) this.kept.add(id);
    for (const id of read.hidden ?? []) this.hidden?.add(id);
    for (const id of read.muted ?? []) this.muted?.add(id);
    for (const [k, at] of Object.entries(read.pins)) this.pins.set(k, num(at));
    return true;
  }

  /// Whether `marks` are those this was made of, and still kept so.
  of(marks: Marks, me: string): boolean {
    return !this.stale && this.marks === marks && this.me === me;
  }

  /// (the changes below, on what is kept here)
  read(thread: number, n: number): void {
    this.reads.set(thread, n);
  }
  threadMark(kind: "kept" | "hidden" | "muted", thread: number, on: boolean): void {
    const set = this[kind];
    if (set === undefined) this.stale = true;
    else if (on) set.add(thread);
    else set.delete(thread);
  }
  pin(key: string, at: number | null): void {
    if (at === null) this.pins.delete(key);
    else this.pins.set(key, at);
  }
  letGo(d: string): void {
    this.#dismiss(d);
  }
}

/// The OwnHeld of `marks`, where `own` is theirs (else none to keep).
const ownOf = (marks: Marks, own: OwnHeld | null): OwnHeld | null => (own !== null && own.marks === marks && !own.stale ? own : null);

/// Where the viewer read a thread to, as the station told it or as it was read here: the furthest.
export function markRead(marks: Marks, own: OwnHeld | null, thread: number, n: number): void {
  const now = Math.max(marks.reads[String(thread)] ?? 0, n);
  marks.reads[String(thread)] = now;
  ownOf(marks, own)?.read(thread, now);
}

/// A thread's mark of the viewer's (kept from archiving, hidden, muted) set or let go.
export function markThread(marks: Marks, own: OwnHeld | null, kind: "kept" | "hidden" | "muted", thread: number, on: boolean): void {
  const kept = ownOf(marks, own);
  const list = marks[kind] ?? [];
  // (whether it is there: of what is kept by its key, else looked for)
  const known = kept !== null && kept[kind] !== undefined;
  if (!known) glanced.marksWalked += list.length;
  const has = known ? kept[kind]!.has(thread) : list.includes(thread);
  if (has !== on && on) list.push(thread);
  else if (has !== on) {
    // (let go: found in the list, walked to it)
    const at = list.indexOf(thread);
    glanced.marksWalked += at + 1;
    if (at >= 0) list.splice(at, 1);
  }
  marks[kind] = list;
  kept?.threadMark(kind, thread, on);
}

/// What the viewer pinned (`at`) or let go (null), by its agent's key.
export function markPin(marks: Marks, own: OwnHeld | null, key: string, at: number | null): void {
  if (at === null) delete marks.pins[key];
  else marks.pins[key] = at;
  ownOf(marks, own)?.pin(key, at);
}

/// What waits in a thread at entry `n` (its card, its agent's need) that the viewer will not take up.
export function markDismissed(marks: Marks, own: OwnHeld | null, thread: number, n: number): void {
  const d = `${thread}:${n}`;
  const kept = ownOf(marks, own);
  if (kept === null) glanced.marksWalked += marks.dismissed.length;
  if (!(kept !== null ? kept.dismissed.has(d) : marks.dismissed.includes(d))) marks.dismissed.push(d);
  kept?.letGo(d);
  for (const kind of [marks.card, marks.need]) {
    const v = kind[String(thread)];
    if (isObject(v) && get(v, "seq") === n) kind[String(thread)] = { ...v, dismissed: true };
  }
}

/// What every row of the viewer's sidebar of the list its station makes reads (RowsMemo `whole`): whose rows they are
/// and the words.
export const sharedWhole = (me: string, selves: readonly string[], words: Words): string => JSON.stringify(["shared", me, selves, words]);

/// What rowFor reads of the viewer's own for a row of that list: where they read it to, the cards they let go of it,
/// its marks.
function ownParts(row: J, own: Own): unknown[] {
  const thread = typeof row.thread === "number" ? row.thread : null;
  if (thread === null) return [row, own.pins.get(row.id)];
  const letGo = (c: unknown) => (isObject(c) ? own.dismissed.has(`${thread}:${get(c, "seq")}`) : null);
  return [row, own.pins.get(row.id), own.reads.get(thread), letGo(row.card), letGo(row.need), letGo(row.decision), own.kept.has(thread), own.hidden?.has(thread), own.muted?.has(thread)];
}

/// The viewer's row of one row of that list (`shared`), by its key, through `memo` as `rowsShared` makes each: the row
/// made before where its parts are as they were. `memo` must be of the same whole (`sharedWhole`): the caller's to say.
export function rowShared(shared: J, own: Own, words: Words, memo: RowsMemo): J {
  const id = String(shared.id);
  const of = ownParts(shared, own);
  const before = memo.rows.get(id);
  if (before !== undefined && before.of.length === of.length && before.of.every((v, i) => v === of[i])) return before.row;
  work.chatRowsMade++;
  const row = Object.freeze(rowFor(shared, own, words));
  memo.rows.set(id, { of, row });
  return row;
}

/// The viewer's sidebar of the chat list its station made for everyone (`shared`, by row id) and the marks that are
/// theirs (chat-row.ts; `own`, where they are kept already, OwnHeld), in their places (`sharedPlace`, then by id); made
/// through `memo` (RowsMemo) as `rowsMade`'s are.
export function rowsShared(shared: Iterable<J>, marks: Marks, me: string, words: Words, memo: RowsMemo = rowsMemo(), own: Own = new OwnHeld(marks, me)): J[] {
  const rows = through(memo, sharedWhole(me, marks.selves, words));
  const out = [...shared].map((row) => rows.row(String(row.id), ownParts(row, own), () => rowFor(row, own, words)));
  rows.done();
  glanced.chatRowsMapped += out.length;
  const id = (r: J) => String(r.id);
  return out.sort((a, b) => sharedPlace(a) - sharedPlace(b) || (id(a) < id(b) ? -1 : id(a) > id(b) ? 1 : 0));
}

/// The sidebar of the viewer whose email is `me`, as the station makes it (views.ts `chats`, not archived).
/// Made through `memo` (RowsMemo): the rows whose parts are as they were are those made before.
export function rowsMade(sessions: readonly unknown[], threads: readonly unknown[], marks: Marks, me: string, words: Words, memo: RowsMemo = rowsMemo()): J[] {
  const mine = mineFor(me, marks.selves);
  // The sessions in lists, the latest active first.
  const shown = new Map<string, J>();
  for (const s of sessions) if (isObject(s) && typeof get(s, "key") === "string" && (get(s, "archivedAt") ?? null) === null) shown.set(get(s, "key") as string, s as J);
  const order = [...shown.values()].sort((a, b) => num(b.lastActiveAt) - num(a.lastActiveAt)).map((s) => s.key as string);
  const members = (t: J): J[] => (Array.isArray(t.sessions) ? t.sessions.filter(isObject) : []);
  const said = (t: J) => num(get(t.lastMessage, "createdAt"));
  // The threads with a session in lists, most recently said in first (read/store.ts `listThreads`).
  const held = (threads.filter((t) => isObject(t) && members(t as J).some((m) => shown.has(m.session))) as J[])
    .sort((a, b) => said(b) - said(a) || num(b.createdAt) - num(a.createdAt) || num(b.id) - num(a.id));
  const own = (t: J) => titles.isOwnChat(t);
  const listed = (t: J) => (t.hiddenAt ?? null) === null;
  const agent = (key: string): J => {
    const x = shown.get(key)!;
    const v: J = { key, runtime: x.runtime ?? null, model: x.model ?? null, effort: x.effort ?? null, process: x.process ?? "cold", pending: x.pending ?? 0, lastTurn: x.lastTurn ?? null };
    if (x.watch !== undefined) v.watch = x.watch;
    return v;
  };
  const connectOf = (t: J): string | null => members(t).map((m) => str(m.connect)).find((c) => c !== null && !titles.isOwnSurface(c)) ?? null;
  const origin = (t: J): J => {
    const connect = connectOf(t);
    return { teamName: connect === null ? null : (marks.teams[connect] ?? null), channel: t.channel ?? null, channelName: t.channelName ?? null, threadTs: t.threadTs ?? null, surface: t.surface ?? null };
  };
  const titleOf = (t: J, channelName: string | null) => titles.chatTitle(t, str(t.firstText), channelName, words);
  // Per agent: the Slack thread it came from (the latest it is in), whether it has a chat of its own, and whether the
  // viewer wrote in one of its Slack threads.
  const origins = new Map<string, J>();
  const chatted = new Set<string>();
  const spoke = new Set<string>();
  for (const t of held) {
    const viewerIn = !own(t) && (Array.isArray(t.people) ? t.people : []).some(mine);
    for (const m of members(t)) {
      if (own(t)) {
        if (listed(t)) chatted.add(m.session);
      } else {
        if (!origins.has(m.session)) origins.set(m.session, t);
        if (viewerIn) spoke.add(m.session);
      }
    }
  }
  const made = through(memo, JSON.stringify(["made", me, marks.selves, words]));
  const kept = new Set(marks.kept);
  const hidden = marks.hidden === undefined ? undefined : new Set(marks.hidden);
  const muted = marks.muted === undefined ? undefined : new Set(marks.muted);
  const suggested = new Set(marks.suggested);
  const teamOf = (t: J | null): unknown => {
    const connect = t === null ? null : connectOf(t);
    return connect === null ? null : marks.teams[connect];
  };
  // (what a row reads of the marks by its agent's key, and puts last)
  const byKey = (key: string): unknown[] => [marks.pins[key], marks.openers[key], marks.opened[key], marks.shares[key]];
  const keyed = (row: J): J => {
    const key = row.id as string;
    row.pinned = marks.pins[key] ?? null;
    if (marks.openers[key] !== undefined) row.opener = marks.openers[key];
    if (marks.opened[key] !== undefined) row.opened = marks.opened[key];
    if (marks.shares[key] !== undefined) row.xshare = marks.shares[key];
    return row;
  };
  const rows: J[] = [];
  for (const t of held) {
    if (!own(t) || !listed(t)) continue;
    const inChat = members(t).map((m) => m.session as string).filter((k) => shown.has(k));
    if (inChat.length === 0) continue;
    const from = members(t).map((m) => origins.get(m.session)).find((o) => o !== undefined) ?? null;
    const key = inChat[0]!;
    const id = String(t.id);
    const of = [
      t, from, teamOf(from), inChat.some((k) => spoke.has(k)), kept.has(t.id), hidden?.has(t.id), muted?.has(t.id), suggested.has(t.id), marks.reviews, marks.verdicts[id],
      marks.clientKeys[key], marks.card[id], marks.need[id], marks.answered[id], ...byKey(key), inChat.length, ...inChat.map((k) => shown.get(k)),
    ];
    rows.push(made.row(`t:${id}`, of, () => {
      const agents = inChat.map(agent);
      const origin_ = from === null ? null : origin(from);
      const title = from !== null && origin_ !== null && titles.givenTitle(t) === null ? titleOf(from, origin_.channelName) : titleOf(t, null);
      let last: J | null = null;
      const m = t.lastMessage;
      if (isObject(m)) {
        const text0 = typeof m.text === "string" ? trim(m.text) : "";
        const text = text0 === "" && Array.isArray(m.quotes) && m.quotes.length > 0 ? words.quotedOnly : text0;
        last = { seq: m.seq, authorKind: m.authorKind, author: m.author, authorName: m.authorName ?? null, text: typeof m.text === "string" ? [...text].slice(0, LAST_CHARS).join("") : null, createdAt: m.createdAt };
        if (m.authorPicture !== undefined) last.authorPicture = m.authorPicture;
        if (m.agentIdentity != null) last.agentIdentity = m.agentIdentity;
        if (m.authorModel !== undefined) last.authorModel = m.authorModel;
        if (m.authorRuntime !== undefined) last.authorRuntime = m.authorRuntime;
      }
      const creator = t.creator ?? null;
      const people = Array.isArray(t.people) ? t.people : [];
      const starters = inChat.map((k) => shown.get(k)!.creator ?? null);
      const row: J = {
        id: key, session: key, thread: t.id, title, agents, last,
        unread: num(t.unread) > 0,
        mine: mine(creator) || people.some(mine) || starters.some(mine) || inChat.some((k) => spoke.has(k)),
        lastActiveAt: Math.max(num(t.createdAt), said(t)),
        connect: from === null ? null : connectOf(from),
        origin: origin_, creator, people,
      };
      row.archiveReminderDismissed = kept.has(t.id);
      if (hidden !== undefined) row.hidden = hidden.has(t.id);
      if (muted !== undefined) row.muted = muted.has(t.id);
      row.archiveRecommended = suggested.has(t.id);
      if (marks.reviews) {
        row.archiveReviewed = true;
        if (marks.verdicts[id] !== undefined) row.archiveCheck = marks.verdicts[id];
      }
      if (marks.clientKeys[key] !== undefined) row.clientKey = marks.clientKeys[key];
      const card = marks.card[id];
      if (isObject(card)) {
        if (get(card.card, "type") === "options") {
          const { card: c, ...rest } = card as J;
          row.decision = { ...rest, options: get(c, "options") ?? null };
        }
        row.card = card;
      } else if (isObject(marks.need[id])) {
        row.need = marks.need[id];
      }
      if (Array.isArray(marks.answered[id])) row.answered = marks.answered[id];
      return keyed(row);
    }));
  }
  for (const key of order) {
    if (chatted.has(key)) continue;
    const x = shown.get(key)!;
    const from = origins.get(key) ?? null;
    rows.push(made.row(`s:${key}`, [x, from, teamOf(from), spoke.has(key), ...byKey(key)], () => {
      const origin_ = from === null ? null : origin(from);
      const named = typeof x.title === "string" ? trim(x.title) : "";
      const starter = x.creator ?? null;
      return keyed({
        id: key, session: key, thread: null,
        title: named !== "" ? named : from !== null && origin_ !== null ? titleOf(from, origin_.channelName) : words.untitled,
        agents: [agent(key)], last: null, unread: false,
        mine: mine(starter) || spoke.has(key),
        lastActiveAt: num(x.lastActiveAt),
        connect: titles.isOwnSurface(x.connect) ? null : (x.connect ?? null),
        origin: origin_,
        people: starter === null ? [] : [starter],
        creator: starter,
      });
    }));
  }
  made.done();
  glanced.chatRowsMapped += rows.length;
  return rows;
}
