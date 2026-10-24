// GET /events (the Rust station's admin/events.rs): what changed, as it changes, pushed. Changes that come in a burst go out
// as one event per session, and one round of sidebar rows; a thread's entries go out as they are written; `host` adds
// host samples, `job` a job's output as it grows, `live` sessions as they run. Keepalives and host samples only while
// someone follows. The same event names and data as the Rust station's; what is told to everyone also carries an
// `id:`, its number in the log of it (event-log.ts: `<run>.<n>`), which clients from before ignore.
//
// The sessions at work are the station's to follow: a stream asked `running=1` is told what every one its viewer sees
// does as it does it (sessions/live.ts `running`), from where each stood as the stream opened, and a session starting
// asks nothing of any client (FOLLOWS). Nothing of before is told: a device reads what it lacks of a transcript as it
// reads anything it lacks, knowing from a session's summary how far its transcript goes (`transcriptLength`).
//
// A client's stream is replaced by another whenever what it follows changes (a client from before, naming the sessions
// it follows: one starts or stops running; any client: what a page shows of the host, a job's log, a login): what
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
import { type FSWatcher, existsSync, statSync, watch } from "node:fs";
import type { Viewer } from "../mesh/credential.ts";
import type { Lang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Readers } from "../read/pool.ts";
import { type StoreChange, sees } from "../store/rows.ts";
import type { Answer } from "./request.ts";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { EventLog, KEPT_MS } from "./event-log.ts";

const PING_MS = 25_000;
const HOST_MS = 10_000;
/// What the agents spent is told at most this often (the first change at once, the last at the end of the while): it
/// changes with every model call, some 15 s apart while agents work, and each telling has a page showing usage, and every
/// client from before it is read only so, read all of it again (some 200 KB).
const USAGE_EVERY_MS = 60_000;
/// A stream's answer when it was told first what came after `since` (the client then reads nothing again).
export const RESUMED = "stillfail-resumed";
/// A stream's answer when it was asked `running=1` and is told what every session at work its viewer sees does, as it
/// does it, without asking for any (`live` events, from where each stood as it was opened; nothing of before): the
/// client then follows no session by name, and reads what it lacks of a transcript as it reads anything it lacks.
export const FOLLOWS = "stillfail-follows";

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
  /// The sessions at work the station follows itself (sessions/live.ts `running`), and each as it is now (where its
  /// transcript ends, the steps in flight): what a stream that follows them is told as it opens.
  held?(): string[];
  heldNow?(key: string): unknown[];
  /// Whether a session is still there (a summary is told only of one that is).
  sessionExists(key: string): boolean;
  /// The overview as `viewer` sees it, in `lang` (GET /overview); none until the agents' side is up.
  overview?(viewer: Viewer, lang: Lang): Promise<unknown>;
  /// A session's process state (the overview counts running and warm ones).
  processState?(key: string): string;
  /// Someone follows again, after nobody did (allowances are read again then).
  followed?(): void;
  /// Whether `viewer` sees a session, a thread or a job: those of their workspace's chats (docs/multi-workspace.md).
  /// None: every one.
  seen?(viewer: Viewer, of: { session: string } | { thread: number } | { job: string }): boolean;
  /// A login's terminal (docs/remote-login.md): `send` given its screen now and as it changes, until the returned
  /// function is called.
  loginScreen?(id: string, send: (screen: { rows: string[]; cursor: { x: number; y: number }; echo: boolean; live: boolean }) => void): () => void;
};

/// A viewer's streams in one language: what their sidebar and overview are told by. A person in two of the station's
/// workspaces is two viewers (docs/multi-workspace.md).
const viewerKey = (viewer: Viewer, lang: Lang) => `${viewer.email}\0${viewer.workspace}\0${lang}`;
/// Whether a stream is that viewer's in that language.
const theirs = (c: { viewer: Viewer; lang: Lang }, viewer: Viewer, lang: Lang) => c.viewer.email === viewer.email && c.viewer.workspace === viewer.workspace && c.lang === lang;

type Client = {
  id: number;
  viewer: Viewer;
  lang: Lang;
  host: boolean;
  /// Told what every session at work its viewer sees does (`running=1`, FOLLOWS).
  running: boolean;
  send(event: string, data: unknown): void;
  raw(text: string): void;
  /// What it follows besides (live sessions, job logs): ended with it.
  stops: (() => void)[];
  /// Ends its stream from this side: its client opens another.
  end(): void;
};

export class Events {
  private clients: Client[] = [];
  private next = 1;
  /// What is told to everyone, kept for a stream that takes over from another or comes back (event-log.ts).
  private readonly log = new EventLog<(c: Client) => boolean>();
  /// With nobody following, the end of the while one may come back (KEPT_MS): what is told is still made until then.
  private lingering: (() => void) | null = null;
  /// Who followed last: whose names a thread's entries are read with while nobody does.
  private last: { viewer: Viewer; lang: Lang } | null = null;
  /// What each viewer's streams were last told of their sidebar (row id → JSON) and their overview (JSON), by viewer and
  /// language (`viewerKey`): what changes is told against it.
  private rowsTold = new Map<string, Map<string, string>>();
  private overviewTold = new Map<string, string>();
  private deps: EventsDeps;
  /// What changed since the last round: sessions (their events), whose sidebars to read whole (`rowsAll`, `rows`), and the
  /// sessions and threads whose items alone to read again, for everyone (`items`) or one viewer (`viewerItems`).
  private dirty = Events.clean();
  private static clean() {
    return {
      sessions: new Set<string>(), rowsAll: false, rows: new Set<string>(), overview: false,
      items: { sessions: new Set<string>(), threads: new Set<number>() }, viewerItems: new Map<string, Set<number>>(),
    };
  }
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
  follow(more: Partial<Pick<EventsDeps, "live" | "held" | "heldNow" | "overview" | "processState" | "followed" | "loginScreen">>) {
    Object.assign(this.deps, more);
  }

  /// The station's screens changed (docs/remote-screens.md): `screens` as GET /screens answers it, in each stream's
  /// language (`listed`), the latest alone kept for one coming back.
  screens(listed: (lang: Lang) => unknown) {
    for (const lang of new Set(this.clients.map((c) => c.lang))) this.emit("screens", listed(lang), (c) => c.lang === lang, `screens\0${lang}`);
  }

  /// A record changed that only some viewers see (a vault's, routes/vault.ts): `data` told to the streams of viewers
  /// `to` takes, the latest under `of` kept for one coming back.
  tell(event: string, data: unknown, of: string, to: (viewer: Viewer) => boolean) {
    this.emit(event, data, (c) => to(c.viewer), of);
  }

  /// A login changed (docs/remote-login.md): told to everyone as `machine-logins`, a read-only member given `limited`
  /// (how it stands only).
  machineLogins(data: { login: unknown }, limited: { login: unknown }, readOnly: (viewer: Viewer) => boolean, of: string) {
    this.emit("machine-logins", data, (c) => !readOnly(c.viewer), `machine-logins\0${of}`);
    this.emit("machine-logins", limited, (c) => readOnly(c.viewer), `machine-logins-limited\0${of}`);
  }

  /// Something the overview shows changed (config, accounts, connects, cloud, updates).
  overviewChanged() {
    this.dirty.overview = true;
    this.wake();
  }

  inUse(): boolean {
    return this.clients.length > 0;
  }

  /// What a session at work did (sessions/live.ts `heldTold`, its entries in brief): told to every stream that follows the
  /// sessions at work and whose viewer sees it. Not of the log: one that comes back is told each as it is now, and reads
  /// what it lacks.
  heldTold(key: string, message: unknown) {
    for (const c of this.clients) if (c.running && this.sees(c, { session: key })) c.send("live", { ...(message as object), key });
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

  /// The sidebar items a change of these sessions and threads can touch may have changed (read/views.ts `scopeOf`), for
  /// everyone or one viewer: only those are read again.
  private itemsChanged(of: { sessions?: string[]; threads?: number[] }, viewer: string | null = null) {
    if (viewer === null) {
      for (const key of of.sessions ?? []) this.dirty.items.sessions.add(key);
      for (const id of of.threads ?? []) this.dirty.items.threads.add(id);
    } else {
      const threads = this.dirty.viewerItems.get(viewer) ?? new Set<number>();
      for (const id of of.threads ?? []) threads.add(id);
      this.dirty.viewerItems.set(viewer, threads);
    }
    this.wake();
  }

  /// Opens a stream for `viewer`: their sidebar's changes are told against what their streams were told of it last.
  /// `since`: the last id the client heard (`<run>.<n>`), from the stream it takes over from or the one it lost; what was
  /// told after it is told first, and their sidebar and overview as they are now (RESUMED says so), or `missed`.
  /// `brief`: the sessions followed have their transcript entries in brief (read/transcript.ts `brief`).
  /// `logins`: those logins' terminals, each a `login-screen` event (all its rows first, then the rows that changed).
  async open(viewer: Viewer, lang: Lang, host: boolean, live: [string, number, number | null][], logs: [string, number][], since: string | null = null, brief = false, logins: string[] = [], running = false): Promise<Answer> {
    // Following the sessions at work itself, it follows none by name: a client that asks both is one that does not know
    // yet whether this station does (an older one follows those it names).
    const follows = running && this.deps.held !== undefined;
    if (follows) live = [];
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
      running: follows,
      // Its own (a session's steps, a log, a host sample, `missed`): not of the log, and without an id (event-log.ts).
      send: (event, data) => push(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
      raw: push,
      stops: [],
      end: () => remove(),
    };
    push("retry: 3000\n\n");
    // Coming back where all that was told since is kept (their sidebar told on this run too).
    const k = viewerKey(viewer, lang);
    const resumes = since !== null && this.rowsTold.has(k) && this.log.has(since);
    if (since !== null && !resumes) {
      // Why, for the log: a station whose streams are never resumed has every client read it again each time.
      log.info("events", "a stream is not resumed", { since, ...this.log.state(), rows: this.rowsTold.has(k) });
      client.send("missed", {});
    }
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
    // The sessions at work its viewer sees, as each is now: from here on what each does comes as it does it (heldTold).
    if (follows) {
      for (const key of this.deps.held!()) {
        if (!this.sees(client, { session: key })) continue;
        for (const message of this.deps.heldNow?.(key) ?? []) client.send("live", { ...(message as object), key });
      }
    }
    // Those sessions as they run, on this same stream: each message a `live` event with its key.
    for (const [key, from, last] of live) {
      const stop = this.deps.live?.(key, from, last, (message) => client.send("live", { ...(message as object), key }), brief);
      if (stop) client.stops.push(stop);
    }
    // Those jobs' last lines: a `job-log` event now, and again each time the log changes, until the stream goes.
    for (const [id, lines] of logs) client.stops.push(this.followLog(client, id, lines));
    // Those logins' terminals: never of the log (a stream that takes over asks again, and is told all of it).
    for (const id of logins) {
      let told: string[] | null = null;
      const stop = this.deps.loginScreen?.(id, (screen) => {
        const rows: Record<string, string> = {};
        screen.rows.forEach((row, i) => {
          if (told === null || told[i] !== row) rows[i] = row;
        });
        client.send("login-screen", { id, rows, cursor: screen.cursor, echo: screen.echo, live: screen.live, ...(told === null ? { full: true } : {}) });
        told = screen.rows;
      });
      if (stop) client.stops.push(stop);
    }
    if (host) void this.deps.host().then((info) => client.send("host", info), () => {});
    // Read afresh: where the log is as it joins, an id alone (no event), so the next stream goes on from here even when
    // nothing is told meanwhile. On a quiet station a stream without it had no id to go on from, and each that a weak
    // link cut read the whole station again (a dozen reads). Clients from before skip a block without data.
    if (!resumes && this.rowsTold.has(k)) client.raw(`id: ${this.log.at()}\n\n`);
    this.clients.push(client);
    this.last = { viewer, lang };
    this.lingering?.();
    this.lingering = null;
    // In the same turn as it joins: what was told since is told again, and what is told from now comes as to the rest.
    if (resumes) for (const told of this.log.after(since!)) if (told.to(client)) client.raw(told.text);
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
        this.log.clear();
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
      headers: { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive", "x-accel-buffering": "no", ...(resumes ? { [RESUMED]: "1" } : {}), ...(follows ? { [FOLLOWS]: "running" } : {}) },
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
  private emit(event: string, data: unknown, to: (c: Client) => boolean = () => true, of?: string) {
    if (!this.listening()) return;
    const { text } = this.log.append(event, data, to, this.time.now(), of);
    for (const c of this.clients) if (to(c)) c.raw(text);
  }

  /// Whether a stream's viewer sees that session, thread or job (`seen`).
  private sees(c: Client, of: { session: string } | { thread: number } | { job: string }): boolean {
    return this.deps.seen?.(c.viewer, of) ?? true;
  }

  private storeChanged(change: StoreChange) {
    switch (change.type) {
      case "session":
        this.dirty.sessions.add(change.key);
        this.itemsChanged({ sessions: [change.key] });
        break;
      case "sessionRemoved":
        this.dirty.sessions.delete(change.key);
        this.states.delete(change.key);
        this.overviewChanged();
        this.emit("session-removed", { key: change.key }, (c) => sees(c.viewer, change.ws ?? null), `session\0${change.key}`);
        this.itemsChanged({ sessions: [change.key] });
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
            .then((text) => this.emit("thread", { id: change.id, entries: JSON.parse(text).entries }, (c) => this.sees(c, { thread: change.id })), (e) => log.warn("events", "thread event not sent", { error: (e as Error).message }));
          // And to each viewer, the thread as GET /threads/:id has it for them (their read position, their unread count):
          // a client puts it in place rather than read it again after every message (a phone did some two a minute).
          for (const { viewer, lang } of this.viewers(who).filter((v) => this.deps.seen?.(v.viewer, { thread: change.id }) ?? true)) {
            void this.deps.readers.read("thread", { viewer, id: change.id, lang }, lang).then(
              (text) => this.emit("thread-view", JSON.parse(text), (c) => theirs(c, viewer, lang), `thread-view\0${change.id}\0${viewerKey(viewer, lang)}`),
              () => {},
            );
          }
        }
        this.itemsChanged({ threads: [change.id] });
        break;
      }
      case "threadRemoved":
        this.emit("thread-removed", { id: change.id }, (c) => sees(c.viewer, change.ws ?? null));
        this.rowsChanged(null);
        break;
      case "read":
        this.emit("read", { viewer: change.viewer, thread: change.thread, n: change.n }, (c) => c.viewer.email === change.viewer && this.sees(c, { thread: change.thread }));
        this.itemsChanged({ threads: [change.thread] }, change.viewer);
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
        void this.deps.readers.read("job", { id: change.id }, "zh").then((text) => this.emit("job", JSON.parse(text), (c) => this.sees(c, { job: change.id }), `job\0${change.id}`), () => {});
        break;
      case "jobRemoved":
        this.emit("job-removed", { id: change.id, session: change.session }, (c) => this.sees(c, { session: change.session }), `job\0${change.id}`);
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
      this.emit("usage", {}, undefined, "usage");
    };
    const wait = this.usageTold + USAGE_EVERY_MS - this.time.now();
    if (wait <= 0) tell();
    else this.usageLater = this.time.after(wait, tell);
  }

  /// Each viewer and language streams are followed in (who followed last, while none is), once.
  private viewers(who: { viewer: Viewer; lang: Lang }): { viewer: Viewer; lang: Lang }[] {
    const seen = new Set<string>();
    return (this.clients.length > 0 ? this.clients : [who]).filter((c) => !seen.has(viewerKey(c.viewer, c.lang)) && seen.add(viewerKey(c.viewer, c.lang)));
  }

  /// Changes gathered into one round: after what happens now, once.
  private wake() {
    if (this.flushing) return;
    this.flushing = new Promise<void>((resolve) => setImmediate(resolve)).then(() => this.flush()).finally(() => {
      this.flushing = null;
      const d = this.dirty;
      if (d.sessions.size > 0 || d.rowsAll || d.rows.size > 0 || d.overview || d.items.sessions.size > 0 || d.items.threads.size > 0 || d.viewerItems.size > 0) this.wake();
    });
  }

  /// One round: an event per changed session, and the sidebar rows that changed, each viewer's in each language their
  /// streams were asked in.
  private async flush() {
    const dirty = this.dirty;
    this.dirty = Events.clean();
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
        this.emit("session", JSON.parse(await this.deps.readers.read("summary", { key }, "zh")), (c) => this.sees(c, { session: key }), `session\0${key}`);
      } catch (error) {
        log.warn("events", "session event not sent", { session: key, error: (error as Error).message });
      }
    }
    // The overview to each viewer, in each language their streams were asked in.
    if (overview && this.deps.overview) {
      const seen = new Set<string>();
      const viewers = this.clients.filter((c) => !seen.has(viewerKey(c.viewer, c.lang)) && seen.add(viewerKey(c.viewer, c.lang)));
      await Promise.all(
        viewers.map(async ({ viewer, lang }) => {
          try {
            const value = await this.deps.overview!(viewer, lang);
            // Told only as it changed for them: a stream that comes back has every viewer's made again.
            const k = viewerKey(viewer, lang);
            const text = JSON.stringify(value);
            if (this.overviewTold.get(k) === text) return;
            this.overviewTold.set(k, text);
            this.emit("overview", value, (c) => theirs(c, viewer, lang), `overview\0${k}`);
          } catch (error) {
            log.warn("events", "overview not told", { error: (error as Error).message });
          }
        }),
      );
    }
    // Each viewer's sidebar: read whole where it may all have changed, or nothing of it is told against yet (it could
    // not be read); else only the items the changes can touch.
    const seen = new Set<string>();
    const everyone = this.clients.filter((c) => !seen.has(viewerKey(c.viewer, c.lang)) && seen.add(viewerKey(c.viewer, c.lang)));
    const itemsOf = (viewer: Viewer) => new Set([...dirty.items.threads, ...(dirty.viewerItems.get(viewer.email) ?? [])]);
    const touched = (viewer: Viewer) => dirty.items.sessions.size > 0 || itemsOf(viewer).size > 0;
    const whole = (v: { viewer: Viewer; lang: Lang }) => dirty.rowsAll || dirty.rows.has(v.viewer.email) || (touched(v.viewer) && !this.rowsTold.has(viewerKey(v.viewer, v.lang)));
    await Promise.all(
      everyone
        .filter((v) => !whole(v))
        .map(async ({ viewer, lang }) => {
          const threads = itemsOf(viewer);
          if (!touched(viewer)) return;
          let read: { rows: any[]; scope: string[] };
          try {
            read = JSON.parse(await this.deps.readers.read("chatRows", { viewer, sessions: [...dirty.items.sessions], threads: [...threads] }, lang));
          } catch (error) {
            log.warn("events", "sidebar rows not read", { error: (error as Error).message });
            return;
          }
          this.tellSomeRows(viewer, lang, read.rows, read.scope);
        }),
    );
    const viewers = everyone.filter(whole);
    if (viewers.length === 0) return;
    await Promise.all(
      viewers.map(async ({ viewer, lang }) => {
        let rows: any[];
        try {
          rows = JSON.parse(await this.deps.readers.read("chats", { viewer, archived: false }, lang));
        } catch (error) {
          log.warn("events", "sidebar rows not read", { error: (error as Error).message });
          return;
        }
        // Their streams opened while it could not be read (nothing it changes by is told against), and what their
        // clients read of the station then failed as it did: now that it reads, those streams are ended. Each comes
        // back to one that is not resumed, and reads the station again.
        if (!this.rowsTold.has(viewerKey(viewer, lang))) {
          const streams = this.clients.filter((c) => theirs(c, viewer, lang));
          log.info("events", "the sidebar reads again: its streams are ended, to read the station again", { streams: streams.length });
          for (const c of streams) c.end();
          return;
        }
        this.tellRows(viewer, lang, rows);
      }),
    );
  }

  /// Some of a viewer's sidebar items as they are now (`rows`, of those `scope` names: one named and not among them is gone
  /// from it), told against what their streams were told of them last; the rest as it was. Nothing while nothing of it was
  /// told (the next stream reads it whole).
  private tellSomeRows(viewer: Viewer, lang: Lang, rows: any[], scope: string[]) {
    const k = viewerKey(viewer, lang);
    const told = this.rowsTold.get(k);
    if (!told) return;
    const to = (c: Client) => theirs(c, viewer, lang);
    const now = new Set<string>();
    for (const row of rows) {
      const id = String(row.id ?? "");
      now.add(id);
      const json = JSON.stringify(row);
      if (told.get(id) === json) continue;
      told.set(id, json);
      this.emit("chat", row, to, `chat\0${k}\0${id}`);
    }
    for (const id of scope) {
      if (now.has(id) || !told.has(id)) continue;
      told.delete(id);
      this.emit("chat-removed", { id }, to, `chat\0${k}\0${id}`);
    }
  }

  /// A viewer's sidebar as it is now (`rows`, in `lang`): the rows that changed since their streams were told it last
  /// are told to them (`chat`, `chat-removed`), and it is what is told against from now.
  private tellRows(viewer: Viewer, lang: Lang, rows: any[]) {
    const k = viewerKey(viewer, lang);
    const now = new Map(rows.map((r) => [String(r.id ?? ""), JSON.stringify(r)]));
    const before = this.rowsTold.get(k);
    this.rowsTold.set(k, now);
    if (!before) return;
    const to = (c: Client) => theirs(c, viewer, lang);
    for (const row of rows) {
      const id = String(row.id ?? "");
      if (before.get(id) !== now.get(id)) this.emit("chat", row, to, `chat\0${k}\0${id}`);
    }
    for (const gone of before.keys()) if (!now.has(gone)) this.emit("chat-removed", { id: gone }, to, `chat\0${k}\0${gone}`);
  }
}
