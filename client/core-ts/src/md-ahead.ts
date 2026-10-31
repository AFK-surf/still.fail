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
import { markdown, markdownHere, mdKey } from "./markdown.ts";
import { laterSleep, type Runner } from "./runtime.ts";
import { PAGE } from "./station/channel-kinds.ts";

/// How lately a reply was said to be read ahead, and how many chats a station has read ahead as the core starts.
export const AHEAD_MS = 3 * 86_400_000;
export const AHEAD_CHATS = 20;
/// How long after the core starts those are read ahead: after what the app's first pages ask.
export const AHEAD_AFTER_MS = 3000;

type Ahead = { station: string; of: string; text: string; key: string };

export class MdAhead {
  readonly #data: Data;
  readonly #runner: Runner;
  readonly #now: () => number;
  readonly #queue: Ahead[] = [];
  readonly #queued = new Set<string>();
  #running = false;

  constructor(data: Data, runner: Runner, now: () => number) {
    this.#data = data;
    this.#runner = runner;
    this.#now = now;
  }

  /// The chats each station's agents spoke in latest, read ahead.
  seed(): void {
    const since = this.#now() - AHEAD_MS;
    for (const db of this.#data.dbs()) {
      for (const station of db.stations()) {
        for (const thread of this.#data.recentThreads(station, since, AHEAD_CHATS)) this.thread(station, thread);
      }
    }
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
      if (m.authorKind === "person" || text === "" || text.includes("<@") || markdownHere(text)) continue;
      const key = mdKey(text);
      if (this.#queued.has(`${station}\u0001${key}`) || store.has(key)) continue;
      this.#queued.add(`${station}\u0001${key}`);
      this.#queue.push({ station, of: `t:${thread}`, text, key });
    }
    this.#run();
  }

  #run(): void {
    if (this.#running || this.#queue.length === 0) return;
    this.#running = true;
    this.#runner.fork(
      Effect.gen({ self: this }, function* () {
        while (this.#queue.length > 0) {
          // each in a turn of its own: what a UI asks meanwhile goes first
          yield* laterSleep(0);
          const next = this.#queue.shift()!;
          this.#queued.delete(`${next.station}\u0001${next.key}`);
          const store = this.#data.mdStore(next.station, next.of);
          if (store !== undefined && !markdownHere(next.text) && !store.has(next.key)) markdown(next.text, store);
        }
      }).pipe(Effect.ensuring(Effect.sync(() => (this.#running = false)))),
    );
  }
}
