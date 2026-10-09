// GET /events (the Rust station's admin/events.rs): what changed, as it changes, pushed. Changes that come in a burst go out
// as one event per session, and one round of sidebar rows; a thread's entries go out as they are written; `host` adds
// host samples, `job` a job's output as it grows, `live` sessions as they run. Keepalives and host samples only while
// someone follows. The same event names and data as the Rust station's; each event now also carries an `id:`: this run of
// the station's, and its number in it (`<run>.<n>`), clients from before ignore it.
//
// A client's stream is replaced by another whenever what it follows changes (a session starts or stops running): what
// was told to everyone between the new one being asked for and its being here went only to the old one, and was lost
// where the client let go of the old one before it had read that. So what is told to everyone is kept a while, and a
// stream asked for `since` the last id its predecessor gave is first told again what came after it (the same ids), or
// `missed` when that is not kept any more (or was another run's): the client then reads the station again.
//
// The same goes for a stream that comes back after its link went down (on a weak link, every minute or so: the link
// moved to a better way, or lost its way): told what it missed, a client reads nothing again, where it used to read all
// the station holds (a slow link's minutes). So while a viewer may come back (KEPT_MS after the last stream went) what is
// told is still made and kept; a viewer's sidebar and overview are told against what their streams were told last (one
// telling for all their streams, kept like the rest), and the one that comes back is told how they stand now. Its answer
// says it was (`stillfail-resumed: 1`). Past KEPT_MS with nobody, nothing more is made, and nothing before can be resumed.
//
// Where the Rust re-read a job's log every second, a log is watched (fs.watch); the sidebar rows of a viewer are read
// once per round for all their streams, off the main thread (the readers).
import { randomBytes } from "node:crypto";
import { type FSWatcher, existsSync, statSync, watch } from "node:fs";
import type { Viewer } from "../mesh/credential.ts";
import type { Lang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Readers } from "../read/pool.ts";
import type { StoreChange } from "../store/rows.ts";
import type { Answer } from "./request.ts";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";

const PING_MS = 25_000;
const HOST_MS = 10_000;
/// What the agents spent is told at most this often (the first change at once, the last at the end of the while): it
/// changes with every model call, some 15 s apart while agents work, and each telling has a page showing usage, and every
/// client from before it is read only so, read all of it again (some 200 KB).
const USAGE_EVERY_MS = 60_000;
/// What was told is kept this long, at most this many and this much, for a stream that takes over or comes back (`since`):
/// an hour, as a phone comes back to a chat after a while in a pocket (ten minutes, half of its streams could not be
/// told what they missed, and read the station again).
const KEPT_MS = 3_600_000;
const KEPT_MOST = 20_000;
const KEPT_BYTES = 8 * 1024 * 1024;
/// A stream's answer when it was told first what came after `since` (the client then reads nothing again).
export const RESUMED = "stillfail-resumed";

/// What the events need of the rest of the station.
export type EventsDeps = {
  readers: Readers;
  /// Its time (a TestClock in tests).
  clock?: Clock.Clock;
  subscribe(listener: (change: StoreChange) => void): () => void;
  /// A host sample (GET /host's answer).
  host(): Promise<unknown>;
  /// A job's log path and how its lines are read (jobs.rs `tail`, `output_at`).
  jobLog(id: string): string | null;
  tail(path: string, lines: number): string;
  outputAt(path: string): number | null;
  /// A session's live steps, from `from`, to `send`, until the returned function is called (live.rs); its transcript
  /// entries in brief (`brief`, read/transcript.ts) for a client that asks so.
  live?(key: string, from: number, last: number | null, send: (message: unknown) => void, brief: boolean): () => void;
  /// Whether a session is still there (a summary is told only of one that is).
  sessionExists(key: string): boolean;
  /// The overview as `viewer` sees it, in `lang` (GET /overview); none until the agents' side is up.
  overview?(viewer: Viewer, lang: Lang): Promise<unknown>;
  /// A session's process state (the overview counts running and warm ones).
  processState?(key: string): string;
  /// Someone follows again, after nobody did (allowances are read again then).
  followed?(): void;
};

/// An event told to everyone (`to` chose whom): its number, and as it went out.
type Told = { n: number; to: (c: Client) => boolean; text: string; at: number };

type Client = {
  id: number;
  viewer: Viewer;
  lang: Lang;
  host: boolean;
  send(event: string, data: unknown): void;
  raw(text: string): void;
  /// What it follows besides (live sessions, job logs): ended with it.
  stops: (() => void)[];
};

export class Events {
  private clients: Client[] = [];
  private next = 1;
  private seq = 0;
  /// This run of the station, in each event's id: a number of another run says nothing here.
  private readonly run = randomBytes(4).toString("hex");
  /// What was told to everyone lately (KEPT_MS, KEPT_MOST, KEPT_BYTES), oldest first, how much it is, and the number of
  /// the last let go (nothing up to it can be resumed from).
  private told: Told[] = [];
  private toldBytes = 0;
  private forgotten = 0;
  /// With nobody following, the end of the while one may come back (KEPT_MS): what is told is still made until then.
  private lingering: (() => void) | null = null;
  /// Who followed last: whose names a thread's entries are read with while nobody does.
  private last: { viewer: Viewer; lang: Lang } | null = null;
  /// What each viewer's streams were last told of their sidebar (row id → JSON) and their overview (JSON), by viewer and
  /// language (`${email}\0${lang}`): what changes is told against it.
  private rowsTold = new Map<string, Map<string, string>>();
  private overviewTold = new Map<string, string>();
  private deps: EventsDeps;
  private dirty = { sessions: new Set<string>(), rowsAll: false, rows: new Set<string>(), overview: false };
  /// The process state last told per session.
  private states = new Map<string, string>();
  private flushing: Promise<void> | null = null;
  private time: Fibers;
  private timers: (() => void)[] = [];
  private lastHost = "";
  /// When usage was last told, and the telling waiting for the end of the while (USAGE_EVERY_MS).
  private usageTold = -Infinity;
  private usageLater: (() => void) | null = null;

  constructor(deps: EventsDeps) {
    this.deps = deps;
    this.time = new Fibers("events", deps.clock);
    deps.subscribe((change) => this.storeChanged(change));
  }

  /// Where `live` sessions are followed from, the overview and process states (the agents' side, once it is made).
  follow(more: Pick<EventsDeps, "live" | "overview" | "processState" | "followed">) {
    Object.assign(this.deps, more);
  }

  /// Something the overview shows changed (config, accounts, connects, cloud, updates).
  overviewChanged() {
    this.dirty.overview = true;
    this.wake();
  }

  inUse(): boolean {
    return this.clients.length > 0;
  }

  /// Whether what is told is made and kept: someone follows, or may come back to what they missed.
  private listening(): boolean {
    return this.clients.length > 0 || this.lingering !== null;
  }

  /// The sidebar rows of `viewer` (everyone's when null) may have changed.
  rowsChanged(viewer: string | null) {
    if (viewer === null) this.dirty.rowsAll = true;
    else this.dirty.rows.add(viewer);
    this.wake();
  }

  /// Opens a stream for `viewer`: their sidebar's changes are told against what their streams were told of it last.
  /// `since`: the last id the client heard (`<run>.<n>`), from the stream it takes over from or the one it lost; what was
  /// told after it is told first, and their sidebar and overview as they are now (RESUMED says so), or `missed`.
  /// `brief`: the sessions followed have their transcript entries in brief (read/transcript.ts `brief`).
  async open(viewer: Viewer, lang: Lang, host: boolean, live: [string, number, number | null][], logs: [string, number][], since: string | null = null, brief = false): Promise<Answer> {
    const queue: string[] = [];
    let wakeReader: (() => void) | null = null;
    let closed = false;
    const push = (text: string) => {
      if (closed) return;
      queue.push(text);
      wakeReader?.();
    };
    const client: Client = {
      id: this.next++,
      viewer,
      lang,
      host,
      send: (event, data) => push(`id: ${this.run}.${++this.seq}\nevent: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
      raw: push,
      stops: [],
    };
    push("retry: 3000\n\n");
    // Coming back where all that was told since is kept (their sidebar told on this run too).
    const k = `${viewer.email}\0${lang}`;
    const resumes = since !== null && this.rowsTold.has(k) && this.kept(since);
    if (since !== null && !resumes) client.send("missed", {});
    if (!resumes) {
      // Afresh: their sidebar as it is now is what its changes are told against from now (read before the stream
      // answers, so the client's own reading of it comes after); where it changed while none of their streams was
      // there, their other streams are told, and it is kept for one coming back. Their overview is told as it next is.
      try {
        this.tellRows(viewer, lang, JSON.parse(await this.deps.readers.read("chats", { viewer, archived: false }, lang)) as any[]);
      } catch (error) {
        log.warn("events", "sidebar rows not read", { error: (error as Error).message });
      }
      this.overviewTold.delete(k);
    }
    // Those sessions as they run, on this same stream: each message a `live` event with its key.
    for (const [key, from, last] of live) {
      const stop = this.deps.live?.(key, from, last, (message) => client.send("live", { ...(message as object), key }), brief);
      if (stop) client.stops.push(stop);
    }
    // Those jobs' last lines: a `job-log` event now, and again each time the log changes, until the stream goes.
    for (const [id, lines] of logs) client.stops.push(this.followLog(client, id, lines));
    if (host) void this.deps.host().then((info) => client.send("host", info), () => {});
    this.clients.push(client);
    this.last = { viewer, lang };
    this.lingering?.();
    this.lingering = null;
    // In the same turn as it joins: what was told since is told again, and what is told from now comes as to the rest.
    if (resumes) this.replay(client, since!);
    // Coming back: their sidebar and overview as they are now, against what their streams were told of them last (what
    // changed while none of theirs was there to be told).
    if (resumes) {
      this.rowsChanged(viewer.email);
      this.overviewChanged();
    }
    if (this.clients.length === 1) {
      this.startTimers();
      this.deps.followed?.();
    }
    const remove = () => {
      if (closed) return;
      closed = true;
      wakeReader?.();
      this.clients = this.clients.filter((c) => c !== client);
      client.stops.forEach((stop) => stop());
      if (this.clients.length > 0) return;
      this.stopTimers();
      // Nobody follows: what is told is still made a while, for one coming back; past it, nothing before can be.
      this.lingering = this.time.after(KEPT_MS, () => {
        this.lingering = null;
        this.told = [];
        this.toldBytes = 0;
        this.forgotten = ++this.seq;
        this.rowsTold.clear();
        this.overviewTold.clear();
      });
    };
    // The stream lasts as long as its reader: when it goes (the mesh stream closed), the client does, at once (an
    // async generator would end only once its pending wait woke up).
    const body: AsyncIterableIterator<Buffer> = {
      [Symbol.asyncIterator]: () => body,
      next: async () => {
        while (!closed && queue.length === 0) await new Promise<void>((resolve) => (wakeReader = resolve));
        wakeReader = null;
        if (queue.length === 0) return { done: true, value: undefined };
        return { done: false, value: Buffer.from(queue.shift()!) };
      },
      return: async () => {
        remove();
        return { done: true, value: undefined };
      },
    };
    return {
      status: 200,
      headers: { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive", "x-accel-buffering": "no", ...(resumes ? { [RESUMED]: "1" } : {}) },
      body,
    };
  }

  /// A job's last `lines` of output (`job-log`: id, lines, text, outputAt): at once, then whenever its log changes.
  private followLog(client: Client, id: string, lines: number): () => void {
    const path = this.deps.jobLog(id);
    if (path === null) return () => {};
    let seen = "";
    const tell = () => {
      let now = "none";
      try {
        const st = statSync(path);
        now = `${st.size}:${st.mtimeMs}`;
      } catch {}
      if (now === seen) return;
      seen = now;
      client.send("job-log", { id, lines, text: existsSync(path) ? this.deps.tail(path, lines) : "", outputAt: this.deps.outputAt(path) });
    };
    tell();
    let watcher: FSWatcher | null = null;
    let pending: (() => void) | null = null;
    const soon = () => {
      // A burst of writes is one event.
      if (pending) return;
      pending = this.time.after(200, () => {
        pending = null;
        tell();
      });
    };
    const follow = () => {
      if (watcher) return;
      try {
        watcher = watch(path, { persistent: false }, soon);
        watcher.on("error", () => {
          watcher?.close();
          watcher = null;
        });
      } catch {
        // No log yet: the check below finds it once the job writes one.
      }
    };
    follow();
    // A log that was not there yet, or was written anew (its watch then ends), is found again here.
    const check = this.time.every(5_000, () => {
      follow();
      tell();
    });
    return () => {
      watcher?.close();
      check();
      pending?.();
    };
  }

  private startTimers() {
    this.timers.push(this.time.every(PING_MS, () => this.clients.forEach((c) => c.raw(": ping\n\n"))));
    this.timers.push(
      this.time.every(HOST_MS, () => {
        if (!this.clients.some((c) => c.host)) return;
        void this.deps.host().then((info: any) => {
          const { checkedAt: _a, uptimeSec: _b, ...shown } = info ?? {};
          const key = JSON.stringify(shown);
          if (key === this.lastHost) return;
          this.lastHost = key;
          for (const c of this.clients) if (c.host) c.send("host", info);
        });
      }),
    );
  }

  private stopTimers() {
    for (const stop of this.timers) stop();
    this.timers = [];
    this.lastHost = "";
  }

  /// Tells everyone `to` chooses: one id for all of them, kept for a stream that takes over from one of them or comes
  /// back. Nothing while nobody follows or may come back.
  private emit(event: string, data: unknown, to: (c: Client) => boolean = () => true) {
    if (!this.listening()) return;
    const n = ++this.seq;
    const text = `id: ${this.run}.${n}\nevent: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
    const now = this.time.now();
    this.told.push({ n, to, text, at: now });
    this.toldBytes += text.length;
    let gone = 0;
    while (gone < this.told.length && (this.told.length - gone > KEPT_MOST || this.toldBytes > KEPT_BYTES || now - this.told[gone]!.at > KEPT_MS)) {
      this.toldBytes -= this.told[gone]!.text.length;
      gone++;
    }
    if (gone > 0) {
      this.forgotten = this.told[gone - 1]!.n;
      this.told = this.told.slice(gone);
    }
    for (const c of this.clients) if (to(c)) c.raw(text);
  }

  /// The number in `since` (`<run>.<n>`), where all that was told after it is kept: this run's, and not let go of.
  private kept(since: string): boolean {
    const m = /^([0-9a-f]+)\.(\d+)$/.exec(since);
    return m !== null && m[1] === this.run && Number(m[2]) >= this.forgotten;
  }

  /// What was told after `since` (kept) that would have been told to `client`, again, as it was.
  private replay(client: Client, since: string) {
    const n = Number(since.slice(since.indexOf(".") + 1));
    for (const t of this.told) if (t.n > n && t.to(client)) client.raw(t.text);
  }

  private storeChanged(change: StoreChange) {
    switch (change.type) {
      case "session":
        this.dirty.sessions.add(change.key);
        this.rowsChanged(null);
        break;
      case "sessionRemoved":
        this.dirty.sessions.delete(change.key);
        this.states.delete(change.key);
        this.overviewChanged();
        this.emit("session-removed", { key: change.key });
        this.rowsChanged(null);
        break;
      case "thread": {
        // Read as one who follows (or did last) would have it.
        const who = this.clients[0] ?? this.last;
        if (this.listening() && who && change.entries.length > 0) {
          const first = change.entries[0].n;
          const last = change.entries.at(-1)!.n;
          // Entries as the pages show them (with their authors' names), read off the main thread.
          void this.deps.readers
            .read("entries", { viewer: who.viewer, thread: change.id, params: [["from", String(first)], ["to", String(last)]] }, who.lang)
            .then((text) => this.emit("thread", { id: change.id, entries: JSON.parse(text).entries }), (e) => log.warn("events", "thread event not sent", { error: (e as Error).message }));
          // And to each viewer, the thread as GET /threads/:id has it for them (their read position, their unread count):
          // a client puts it in place rather than read it again after every message (a phone did some two a minute).
          for (const { viewer, lang } of this.viewers(who)) {
            void this.deps.readers.read("thread", { viewer, id: change.id, lang }, lang).then(
              (text) => this.emit("thread-view", JSON.parse(text), (c) => c.viewer.email === viewer.email && c.lang === lang),
              () => {},
            );
          }
        }
        this.rowsChanged(null);
        break;
      }
      case "threadRemoved":
        this.emit("thread-removed", { id: change.id });
        this.rowsChanged(null);
        break;
      case "read":
        this.emit("read", { viewer: change.viewer, thread: change.thread, n: change.n }, (c) => c.viewer.email === change.viewer);
        this.rowsChanged(change.viewer);
        break;
      case "identities":
        // Who the viewer is on Slack: their overview says it, and their rows count it.
        this.overviewChanged();
        this.rowsChanged(change.viewer);
        break;
      case "pins":
      case "dismissed":
        this.rowsChanged(change.viewer);
        break;
      case "job":
        // A job as GET /jobs/:id answers it, so a client holding it puts it in place without reading anything again.
        void this.deps.readers.read("job", { id: change.id }, "zh").then((text) => this.emit("job", JSON.parse(text)), () => {});
        break;
      case "jobRemoved":
        this.emit("job-removed", { id: change.id, session: change.session });
        break;
      case "usage":
        // Model calls were recorded: a page showing usage reads it again (it is too big to send to everyone).
        this.usageChanged();
        break;
      case "processes":
      case "decisionChecks":
        this.overviewChanged();
        break;
    }
  }

  /// Usage told, at most once a USAGE_EVERY_MS.
  private usageChanged() {
    if (this.usageLater !== null) return;
    const tell = () => {
      this.usageLater = null;
      this.usageTold = this.time.now();
      this.emit("usage", {});
    };
    const wait = this.usageTold + USAGE_EVERY_MS - this.time.now();
    if (wait <= 0) tell();
    else this.usageLater = this.time.after(wait, tell);
  }

  /// Each viewer and language streams are followed in (who followed last, while none is), once.
  private viewers(who: { viewer: Viewer; lang: Lang }): { viewer: Viewer; lang: Lang }[] {
    const seen = new Set<string>();
    return (this.clients.length > 0 ? this.clients : [who]).filter((c) => !seen.has(`${c.viewer.email}\0${c.lang}`) && seen.add(`${c.viewer.email}\0${c.lang}`));
  }

  /// Changes gathered into one round: after what happens now, once.
  private wake() {
    if (this.flushing) return;
    this.flushing = new Promise<void>((resolve) => setImmediate(resolve)).then(() => this.flush()).finally(() => {
      this.flushing = null;
      if (this.dirty.sessions.size > 0 || this.dirty.rowsAll || this.dirty.rows.size > 0 || this.dirty.overview) this.wake();
    });
  }

  /// One round: an event per changed session, and the sidebar rows that changed, each viewer's in each language their
  /// streams were asked in.
  private async flush() {
    const dirty = this.dirty;
    this.dirty = { sessions: new Set(), rowsAll: false, rows: new Set(), overview: false };
    let overview = dirty.overview;
    for (const key of dirty.sessions) {
      if (!this.deps.sessionExists(key)) continue;
      // The overview counts running and warm sessions.
      const state = this.deps.processState?.(key);
      if (state !== undefined && this.states.get(key) !== state) {
        this.states.set(key, state);
        overview = true;
      }
    }
    if (!this.listening()) return;
    for (const key of dirty.sessions) {
      if (!this.deps.sessionExists(key)) continue;
      try {
        this.emit("session", JSON.parse(await this.deps.readers.read("summary", { key }, "zh")));
      } catch (error) {
        log.warn("events", "session event not sent", { session: key, error: (error as Error).message });
      }
    }
    // The overview to each viewer, in each language their streams were asked in.
    if (overview && this.deps.overview) {
      const seen = new Set<string>();
      const viewers = this.clients.filter((c) => !seen.has(`${c.viewer.email}\0${c.lang}`) && seen.add(`${c.viewer.email}\0${c.lang}`));
      await Promise.all(
        viewers.map(async ({ viewer, lang }) => {
          try {
            const value = await this.deps.overview!(viewer, lang);
            // Told only as it changed for them: a stream that comes back has every viewer's made again.
            const k = `${viewer.email}\0${lang}`;
            const text = JSON.stringify(value);
            if (this.overviewTold.get(k) === text) return;
            this.overviewTold.set(k, text);
            this.emit("overview", value, (c) => c.viewer.email === viewer.email && c.lang === lang);
          } catch (error) {
            log.warn("events", "overview not told", { error: (error as Error).message });
          }
        }),
      );
    }
    if (!dirty.rowsAll && dirty.rows.size === 0) return;
    const seen = new Set<string>();
    const viewers = this.clients.filter((c) => (dirty.rowsAll || dirty.rows.has(c.viewer.email)) && !seen.has(`${c.viewer.email}\0${c.lang}`) && seen.add(`${c.viewer.email}\0${c.lang}`));
    await Promise.all(
      viewers.map(async ({ viewer, lang }) => {
        let rows: any[];
        try {
          rows = JSON.parse(await this.deps.readers.read("chats", { viewer, archived: false }, lang));
        } catch (error) {
          log.warn("events", "sidebar rows not read", { error: (error as Error).message });
          return;
        }
        this.tellRows(viewer, lang, rows);
      }),
    );
  }

  /// A viewer's sidebar as it is now (`rows`, in `lang`): the rows that changed since their streams were told it last
  /// are told to them (`chat`, `chat-removed`), and it is what is told against from now.
  private tellRows(viewer: Viewer, lang: Lang, rows: any[]) {
    const k = `${viewer.email}\0${lang}`;
    const now = new Map(rows.map((r) => [String(r.id ?? ""), JSON.stringify(r)]));
    const before = this.rowsTold.get(k);
    this.rowsTold.set(k, now);
    if (!before) return;
    const to = (c: Client) => c.viewer.email === viewer.email && c.lang === lang;
    for (const row of rows) {
      const id = String(row.id ?? "");
      if (before.get(id) !== now.get(id)) this.emit("chat", row, to);
    }
    for (const gone of before.keys()) if (!now.has(gone)) this.emit("chat-removed", { id: gone }, to);
  }
}
