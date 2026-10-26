// A connect's surface on a platform that tells the station what happens over a socket the station opens (Slack's Socket
// Mode, Feishu's long connection: no public endpoint needed), as Slack's and Feishu's are: who its bot is; the socket
// kept up, connected again whenever it closes (platforms rotate them) or fails (after a wait that doubles up to a
// minute), pinged, and taken for dead once it said nothing for a while (a connection cut on the way can look open
// forever, and nothing would come through it again: 2026-09-30 on bft); what people are called there, kept for the
// connection's lifetime; the status lines of the threads its agents work for. Its socket's loop is a fiber in the
// surface's scope, and stopping the surface closes the scope (the socket with it). What a platform says on its socket
// and is told through its API is its own (slack/surface.ts, feishu/surface.ts).
import { Clock, Deferred, Effect, Exit, FiberSet, Result, Scope } from "effect";
import WebSocket from "ws";
import { log } from "../ops/log.ts";
import type { Attachment } from "../store/store.ts";
import type { Handler, Person, ThreadRef } from "../sessions/chat.ts";
import type { BotIdentity, Connection, SocketStatus } from "./connections.ts";
import type { NameBook } from "./names.ts";
import type { StatusLine } from "./status.ts";

type Json = any;

const MAX_BACKOFF_MS = 60_000;

export type SurfaceOptions = {
  /// The connect it is (for the log).
  connect?: string;
  /// Keeps names across restarts and lets the admin API ask without waiting (knownPerson, knownChannel).
  book?: NameBook | null;
  /// How often the socket is pinged, and how long it may say nothing before it is taken for dead.
  pingMs: number;
  staleMs: number;
  /// The first wait before connecting again after a failure (doubling up to a minute).
  backoffMs?: number;
  /// The clock its pings, its waits for a socket and between tries run on (a TestClock in tests).
  clock?: Clock.Clock;
  /// Told each time a socket said something (a pong too): what a test waits for before it moves that clock on.
  onHeard?: () => void;
};

/// What one socket does besides being kept up: as it opens, with what it says (when, on the surface's clock; `end`
/// ends the socket: the platform asks for another), and as it is pinged (a platform's own ping, besides the socket's).
export type SocketHooks = {
  opened?(socket: WebSocket): void;
  message(socket: WebSocket, data: WebSocket.RawData, said: { binary: boolean; now: number; end: (error: Error | null) => void }): void;
  ping?(socket: WebSocket): void;
};

export abstract class ConnectedSurface implements Connection {
  readonly cards: boolean = true;
  /// What the log calls the platform ("slack", "feishu").
  protected abstract readonly kind: string;
  protected readonly connect: string | undefined;
  protected readonly book: NameBook | null;
  protected me: BotIdentity | null = null;
  private status: SocketStatus = { connected: false, lastError: null };
  private listeners = new Set<() => void>();
  /// People as the platform says, by their id there.
  protected names = new Map<string, Person>();
  /// Each thread an agent works for: its status line.
  private lines = new Map<string, StatusLine>();
  private readonly pingMs: number;
  private readonly staleMs: number;
  private readonly backoffMs: number;
  private readonly clock: Clock.Clock | undefined;
  private readonly onHeard: () => void;
  protected stopped = false;
  private readonly scope: Scope.Closeable;
  /// Runs an effect as a fiber of the surface's scope (on its clock): it ends when the surface stops.
  protected readonly run: (effect: Effect.Effect<void, never>) => Promise<void>;

  constructor(options: SurfaceOptions) {
    this.connect = options.connect;
    this.book = options.book ?? null;
    this.pingMs = options.pingMs;
    this.staleMs = options.staleMs;
    this.backoffMs = options.backoffMs ?? 1_000;
    this.clock = options.clock;
    this.onHeard = options.onHeard ?? (() => {});
    this.scope = Effect.runSync(Scope.make());
    const runtime = Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope);
    this.run = Effect.runSync(options.clock ? runtime.pipe(Effect.provideService(Clock.Clock, options.clock)) : runtime);
  }

  /// Who its bot is and where, as the platform says now.
  protected abstract identify(): Promise<BotIdentity>;
  /// Where its socket connects to now (asked again for each).
  protected abstract address(): Promise<string>;
  /// One connection to `url`, its events given to `handler`: `socket` with the platform's hooks.
  abstract runSocket(url: string, handler: Handler): Effect.Effect<void, Error>;
  /// What the platform says of a person (null: nothing, or it could not be asked).
  protected abstract lookUp(user: string): Promise<Person | null>;
  /// A thread's status line.
  protected abstract statusLine(thread: ThreadRef): StatusLine;
  abstract post(thread: ThreadRef, message: string, files: Attachment[], card?: Json | null): Promise<string>;

  identity(): BotIdentity | null {
    return this.me;
  }

  socket(): SocketStatus {
    return { ...this.status };
  }

  /// Hears each change of the socket's status, and of the identity; gives the function that stops it.
  onChange(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  protected changed() {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch {}
    }
  }

  protected setStatus(connected: boolean, lastError: string | null) {
    if (this.status.connected === connected && this.status.lastError === lastError) return;
    this.status = { connected, lastError };
    this.changed();
  }

  /// Reads again who the bot is and where (its name changed on the platform, say); listeners hear of it.
  async refreshIdentity() {
    this.me = await this.identify();
    this.changed();
  }

  platform(): string {
    return this.kind;
  }

  botUserId(): string {
    return this.me?.botUserId ?? "";
  }

  botName(): string {
    return this.me?.botName ?? "";
  }

  workspace(): string | null {
    const team = this.me?.teamId ?? "";
    return team === "" ? null : team;
  }

  /// An identity it cannot work as throws (Feishu's app without a bot).
  protected usable(_identity: BotIdentity): void {}

  async start(handler: Handler) {
    const identity = await this.identify();
    this.usable(identity);
    log.info(this.kind, `${this.kind} authenticated`, { connect: this.connect, bot: identity.botName, botUserId: identity.botUserId, team: identity.team });
    this.me = identity;
    void this.run(this.connectLoop(handler)).catch(() => {});
  }

  async stop() {
    if (this.stopped) return;
    this.stopped = true;
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
  }

  /// Connects again whenever the socket closes or fails (after a wait that doubles up to a minute), until it stops.
  private connectLoop(handler: Handler): Effect.Effect<void> {
    const self = this;
    return Effect.gen(function* () {
      let backoff = self.backoffMs;
      for (;;) {
        const ran = yield* Effect.result(
          Effect.gen(function* () {
            const url = yield* Effect.tryPromise({ try: () => self.address(), catch: (e) => e as Error });
            yield* self.runSocket(url, handler);
          }),
        );
        if (Result.isSuccess(ran)) backoff = self.backoffMs;
        else {
          const said = ran.failure.message;
          self.setStatus(false, said);
          log.warn(self.kind, `${self.kind} socket failed`, { connect: self.connect, error: said, retryInMs: backoff });
          yield* Effect.sleep(backoff);
          backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
        }
      }
    });
  }

  /// One socket: ends when it closes (or a hook ends it), and fails on its error, when it did not open within
  /// `staleMs`, or when it then said nothing (not even a pong) for `staleMs`; pinged every `pingMs` meanwhile.
  protected socketTo(url: string, hooks: SocketHooks): Effect.Effect<void, Error> {
    const self = this;
    const kind = this.kind;
    const socket = Effect.gen(function* () {
      const clock = yield* Clock.Clock;
      const opened = yield* Deferred.make<void>();
      let ws: WebSocket | undefined;
      let heard = clock.currentTimeMillisUnsafe();
      // The socket itself: ends when it closes, fails on its error. Interrupted (it went quiet, or the surface stops),
      // it is cut off.
      const open = Effect.callback<void, Error>((resume) => {
        const socket = new WebSocket(url);
        ws = socket;
        let finished = false;
        const cut = () => {
          finished = true;
          socket.removeAllListeners();
          socket.on("error", () => {});
          if (socket.readyState !== WebSocket.CLOSED) socket.terminate();
        };
        const end = (error: Error | null) => {
          if (finished) return;
          cut();
          if (error !== null) resume(Effect.fail(error));
          else {
            self.setStatus(false, self.status.lastError);
            resume(Effect.void);
          }
        };
        // The platform says no in the handshake's answer (an app without the socket, too many sockets).
        socket.on("unexpected-response", (_request, response) => {
          end(new Error(`${kind} refused the connection: HTTP ${response.statusCode} ${response.headers["handshake-msg"] ?? ""}`.trim()));
        });
        socket.on("open", () => {
          heard = clock.currentTimeMillisUnsafe();
          self.setStatus(true, null);
          Deferred.doneUnsafe(opened, Effect.void);
          hooks.opened?.(socket);
        });
        const alive = () => {
          heard = clock.currentTimeMillisUnsafe();
          self.onHeard();
        };
        socket.on("pong", alive);
        socket.on("ping", alive);
        socket.on("message", (data, binary) => {
          alive();
          hooks.message(socket, data, { binary, now: heard, end });
        });
        socket.on("close", () => end(null));
        socket.on("error", (error) => end(error));
        return Effect.sync(() => {
          if (!finished) cut();
        });
      });
      // Its watch: open within `staleMs`, then a ping every `pingMs`; it fails once the socket said nothing for `staleMs`.
      const watch = Deferred.await(opened).pipe(
        Effect.timeoutOrElse({
          duration: self.staleMs,
          orElse: () => Effect.fail(new Error(`${kind} socket did not open within ${self.staleMs / 1000}s`)),
        }),
        Effect.andThen(
          Effect.forever(
            Effect.sleep(self.pingMs).pipe(
              Effect.andThen(
                Effect.suspend(() => {
                  const quiet = clock.currentTimeMillisUnsafe() - heard;
                  if (quiet >= self.staleMs) return Effect.fail(new Error(`${kind} socket said nothing for ${quiet / 1000}s`));
                  try {
                    if (ws !== undefined) hooks.ping?.(ws);
                    ws?.ping();
                  } catch {}
                  return Effect.void;
                }),
              ),
            ),
          ),
        ),
      );
      return yield* Effect.raceFirst(open, watch);
    });
    return this.clock ? socket.pipe(Effect.provideService(Clock.Clock, this.clock)) : socket;
  }

  /// A person as the platform says, kept for the connection's lifetime.
  protected async profile(user: string): Promise<Person | null> {
    const known = this.names.get(user);
    if (known) return known;
    const person = await this.lookUp(user);
    if (person) this.names.set(user, person);
    return person;
  }

  /// Their display name, kept for the connection's lifetime.
  async userName(user: string): Promise<string | null> {
    const name = (await this.profile(user))?.name ?? "";
    return name === "" ? null : name;
  }

  /// Their email, where the platform shares it: what ties them to a still.fail account.
  async userEmail(user: string): Promise<string | null> {
    const email = (await this.profile(user))?.email ?? "";
    return email === "" ? null : email;
  }

  working(thread: ThreadRef, messageTs: string | null, status: string, page?: string | null) {
    if (this.stopped) return;
    const key = `${thread.channel}/${thread.threadTs}`;
    let line = this.lines.get(key);
    if (!line) {
      line = this.statusLine(thread);
      this.lines.set(key, line);
    }
    if (status === "" && this.lines.size > 200) this.lines.delete(key);
    line.say(status, messageTs, page ?? null);
  }
}
