// What agents said, read ahead (markdown.ts): the Markdown of a chat's latest page read in the background as it comes,
// one reply at a time, and kept on the device, so the chat opens with it read. Reading it as the chat opened was the
// most of opening one: a page of agents' replies, ~80 000 characters, took ~0.3 s in Hermes on a Mac Studio
// (bench/chat-open.ts), the messages to come breathing on a phone each time a chat was opened the first time since the
// app started. Read is what comes, whenever it was said (a chat opens by looking up what it shows: an old chat's
// replies came to the device read as the sync brought them, test/chat-open-lookup.test.ts), and as the core starts
// what the chats spoken in lately (AHEAD_MS, AHEAD_CHATS a station) said.
import { Effect } from "effect";
import type { Data } from "./data.ts";
import { merge } from "./entries.ts";
import { MD_READING, mdKey, oldMdKey, refreshMarkdown } from "./markdown.ts";
import { laterSleep, type Runner } from "./runtime.ts";
import { PAGE } from "./station/channel-kinds.ts";
import { timed } from "./spent.ts";

/// How lately a reply was said to be read ahead, and how many chats a station has read ahead as the core starts.
export const AHEAD_MS = 3 * 86_400_000;
export const AHEAD_CHATS = 20;
/// How long after the core starts those are read ahead: after what the app's first pages ask.
export const AHEAD_AFTER_MS = 3000;

type Ahead = { station: string; of: string; text: string; key: string };

/// Sources used by the chat and history readers in a kept entry. Only a source whose old key is actually in the cache
/// is read; the same fields also occur in entries that never had a Markdown tree.
function* sourceTexts(value: unknown): Generator<string> {
  if (Array.isArray(value)) {
    for (const part of value) yield* sourceTexts(part);
  } else if (value !== null && typeof value === "object") {
    for (const [key, part] of Object.entries(value)) {
      if (typeof part === "string" && ["text", "result", "more", "words"].includes(key)) yield part;
      else if (part !== null && typeof part === "object") yield* sourceTexts(part);
    }
  }
}

export class MdAhead {
  readonly #data: Data;
  readonly #runner: Runner;
  readonly #now: () => number;
  readonly #changed: (station: string, of: string) => void;
  readonly #queue: Ahead[] = [];
  readonly #queued = new Set<string>();
  readonly #waiting = new Map<string, Set<string>>();
  #running = false;

  constructor(data: Data, runner: Runner, now: () => number, changed: (station: string, of: string) => void = () => {}) {
    this.#data = data;
    this.#runner = runner;
    this.#now = now;
    this.#changed = changed;
  }

  /// The chats each station's agents spoke in latest, read ahead.
  seed(): void {
    const since = this.#now() - AHEAD_MS;
    for (const db of this.#data.dbs()) {
      for (const station of db.stations()) {
        for (const thread of this.#data.recentThreads(station, since, AHEAD_CHATS)) this.thread(station, thread);
      }
    }
    this.#upgrade();
  }

  /// After a reader change, update trees already on the device as background work too, including old and archived
  /// chats. The old cache did not keep its source, so read it from each owner's kept entries in bounded pages.
  #upgrade(): void {
    this.#runner.fork(Effect.gen({ self: this }, function* () {
      dbs: for (const db of this.#data.dbs()) {
        if (db.meta("md_reading_ahead") === String(MD_READING)) continue;
        let after = { station: "", of: "" };
        for (;;) {
          yield* Effect.yieldNow;
          if (!this.#data.dbs().includes(db)) continue dbs;
          const owners = db.oldMdOwners(MD_READING, after);
          if (owners.length === 0) break;
          for (const owner of owners) {
            after = owner;
            let before = Number.MAX_SAFE_INTEGER;
            const store = this.#data.mdStore(owner.station, owner.of);
            if (store === undefined) continue;
            for (;;) {
              yield* Effect.yieldNow;
              if (!this.#data.dbs().includes(db)) continue dbs;
              if (!db.hasOldMd(owner.station, owner.of, MD_READING)) break;
              const page = db.mdSourcePage(owner.station, owner.of, before);
              if (page.length === 0) break;
              before = page[page.length - 1]!.n;
              for (const row of page) {
                for (const text of sourceTexts(row.json)) {
                  if (text === "") continue;
                  yield* Effect.yieldNow;
                  if (!this.#data.dbs().includes(db)) continue dbs;
                  const key = mdKey(text);
                  if (store.has(key)) continue;
                  const old = oldMdKey(store, key, 1);
                  if (old !== null) timed("md.upgrade", () => refreshMarkdown(text, store, old));
                }
              }
            }
          }
        }
        if (!db.readOnly && this.#data.dbs().includes(db)) db.setMeta("md_reading_ahead", String(MD_READING));
      }
    }));
  }

  /// A chat's entries held changed: what its agents said on its latest page and is not read yet, read in turn, however
  /// long ago it was said. (A reply with a Slack person in it is shown with their name in place (views.ts
  /// shownMessage): read as it opens.)
  thread(station: string, thread: number): void {
    const id = String(thread);
    const span = this.#data.logSpan("entry", station, id);
    const store = this.#data.mdStore(station, `t:${thread}`);
    if (span === null || store === undefined) return;
    const page = this.#data.logRange("entry", station, id, Math.max(1, span.max - PAGE + 1), span.max);
    for (const m of merge([...page.values()])) {
      const text = typeof m.text === "string" ? m.text : "";
      if (m.authorKind === "person" || text === "" || text.includes("<@")) continue;
      const key = mdKey(text);
      if (!store.has(key)) this.#enqueue({ station, of: `t:${thread}`, text, key });
    }
    this.#run();
  }

  /// An older tree went out in a view. Read it after the view goes out, then tell each view that used that tree.
  refresh(station: string, of: string, text: string): void {
    const key = mdKey(text);
    const id = `${station}\u0001${key}`;
    const waiting = this.#waiting.get(id) ?? new Set<string>();
    waiting.add(of);
    this.#waiting.set(id, waiting);
    this.#enqueue({ station, of, text, key }, true);
    this.#run();
  }

  #enqueue(next: Ahead, first = false): void {
    const id = `${next.station}\u0001${next.key}`;
    if (this.#queued.has(id)) {
      if (first) {
        const at = this.#queue.findIndex((x) => x.station === next.station && x.key === next.key);
        if (at > 0) this.#queue.unshift(this.#queue.splice(at, 1)[0]!);
      }
      return;
    }
    this.#queued.add(id);
    if (first) this.#queue.unshift(next);
    else this.#queue.push(next);
  }

  #run(): void {
    if (this.#running || this.#queue.length === 0) return;
    this.#running = true;
    this.#runner.fork(
      Effect.gen({ self: this }, function* () {
        while (this.#queue.length > 0) {
          // each in a turn of its own: what a UI asks meanwhile goes first
          yield* Effect.yieldNow;
          yield* laterSleep(0);
          const next = this.#queue.shift()!;
          const id = `${next.station}\u0001${next.key}`;
          this.#queued.delete(id);
          const store = this.#data.mdStore(next.station, next.of);
          if (store !== undefined && !store.has(next.key)) timed("md.ahead", () => refreshMarkdown(next.text, store, oldMdKey(store, next.key, 1) ?? undefined));
          const waiting = this.#waiting.get(id);
          this.#waiting.delete(id);
          if (store !== undefined) for (const of of waiting ?? []) {
            const prefix = `${next.station}\u0001`;
            if (![...this.#waiting].some(([other, owners]) => other.startsWith(prefix) && owners.has(of))) this.#changed(next.station, of);
          }
        }
      }).pipe(Effect.ensuring(Effect.sync(() => (this.#running = false)))),
    );
  }
}
