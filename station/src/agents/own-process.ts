// A runtime that runs each session in a process of its own (Claude Code, DeepSeek Harness, Cursor, Grok Build, Devin,
// Hermes Agent; not Codex, whose sessions share their profile's app-server): the process under a runner whose id comes from the
// session key (./runner.ts), so that a station starting again takes it up, from the snapshot the one before left at
// handover or, after a crash, from what that one had handled of its output, read again silently. What every such driver
// does is here: the sessions it has, starting a process and taking one up, its requests waiting for their answers, the
// process going away (a turn running fails as exited, then the session closes), letting it go. What a runtime is told
// and says is each driver's.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { AgentProcess, ackedOffset, debug, findRunner, linesBefore, outFile, runnerId } from "./process.ts";
import type { RunnerInfo } from "./runner.ts";
import type { AgentDriver, AgentSession, OpenOptions, RuntimeEvent, RuntimeKind } from "./runtime.ts";

type Json = any;
export type Events = (event: RuntimeEvent) => void;

/// Where a session's turn stands, as its handled lines leave it.
export type TurnState = { busy: boolean; aborting: boolean; closed: boolean };

/// What every such session's snapshot says (each runtime's says more).
export type ProcessSnapshot = { runtime: RuntimeKind; id: string; runner: string; turn: { busy: boolean } };

/// How long a runtime has to answer a request of ours: opening a long session it loads included.
export const ANSWER_MS = 120_000;

/// A line of a runtime's output as the JSON it is (one that is not: nothing, said when debugging).
export function parseLine(kind: RuntimeKind, line: string): Json | undefined {
  try {
    return JSON.parse(line);
  } catch {
    debug(`agents::${kind}`, `${kind} non-json line`, { line: line.slice(0, 500) });
    return undefined;
  }
}

/// A session's requests waiting for their answers, by the id each was sent with.
export class Waiting {
  private waits = new Map<string, { answered: (answer: Json) => void; failed: (error: Error) => void }>();

  /// The answer to the request `id` (to be sent once this is asked): one `refused` makes an error of rejects, and so
  /// does no answer within `ms` (saying `late`, where there is a likely why).
  wait(id: string, refused: (answer: Json) => Error | null, late?: string, ms = ANSWER_MS): Promise<Json> {
    return new Promise((resolve, reject) => {
      const cancel = wall.after(ms, () => this.fail(id, new Error(late ?? `no answer to ${id} in ${ms / 1000} s`)));
      this.waits.set(id, {
        answered: (answer) => {
          cancel();
          const error = refused(answer);
          if (error === null) resolve(answer);
          else reject(error);
        },
        failed: (error) => {
          cancel();
          reject(error);
        },
      });
    });
  }

  /// An answer came: whether it was waited for.
  answer(id: unknown, answer: Json): boolean {
    const wait = typeof id === "string" ? this.waits.get(id) : undefined;
    if (wait === undefined) return false;
    this.waits.delete(id as string);
    wait.answered(answer);
    return true;
  }

  /// Gives up on one.
  fail(id: string, error: Error) {
    const wait = this.waits.get(id);
    this.waits.delete(id);
    wait?.failed(error);
  }

  /// Gives up on all of them (the process went away, the session closed).
  failAll(error: Error) {
    const waits = [...this.waits.values()];
    this.waits.clear();
    for (const wait of waits) wait.failed(error);
  }
}

export abstract class OwnProcessDriver<S extends OwnProcessSession = OwnProcessSession> implements AgentDriver {
  protected readonly data: string;
  private readonly live = new Set<S>();

  constructor(data: string) {
    this.data = data;
  }

  abstract runtime(): RuntimeKind;
  abstract open(options: OpenOptions, events: Events): Promise<AgentSession>;
  /// The session a snapshot says (the station before handed it over), on the process `info` keeps.
  protected abstract handedOver(options: OpenOptions, snapshot: Json, info: RunnerInfo, events: Events): S;
  /// The session the station before had when it crashed: `lines`, what that one had handled of the process's output,
  /// read again (silently) to know it and where its turn stands.
  protected abstract crashed(options: OpenOptions, lines: Iterable<string>, info: RunnerInfo, events: Events): S;

  /// How its process is named in the log.
  protected label(options: OpenOptions, _session: S): string {
    return `${this.runtime()} ${options.key}`;
  }

  /// Starts the process of a session being opened, which is one of this driver's from now on.
  protected async start(session: S, options: OpenOptions, command: string, args: string[], env: Record<string, string>) {
    const id = runnerId(this.runtime(), options.key);
    session.attach(await AgentProcess.start(this.data, id, command, args, env, options.cwd, session.processOptions(this.label(options, session))));
    this.live.add(session);
  }

  async adopt(options: OpenOptions, snapshot: unknown | null, events: Events): Promise<S> {
    const kind = this.runtime();
    const handed = snapshot as ProcessSnapshot | null;
    const id = handed?.runner ?? runnerId(kind, options.key);
    const info = findRunner(this.data, id);
    if (!info) throw new Error(`no runner keeps ${kind} for ${options.key}`);
    let session: S;
    if (handed) {
      log.info(`agents::${kind}`, `taking up a ${kind} process handed over`, { session: handed.id, pgid: info.pgid, busy: handed.turn.busy });
      session = this.handedOver(options, handed, info, events);
    } else {
      const out = outFile(this.data, id);
      const at = await ackedOffset(info, out);
      session = this.crashed(options, linesBefore(out, at), info, events);
      log.info(`agents::${kind}`, `taking up a ${kind} process after a crash`, { session: session.id(), pgid: info.pgid, busy: session.busy(), from: at });
      // A turn is running that this station did not start.
      if (session.busy()) events({ type: "turnStarted" });
    }
    session.attach(AgentProcess.adopt(info, session.processOptions(this.label(options, session))));
    this.live.add(session);
    return session;
  }

  forget(session: S) {
    this.live.delete(session);
  }

  async shutdown() {
    const live = [...this.live];
    this.live.clear();
    await Promise.all(live.map((s) => s.dispose()));
  }

  detach() {
    for (const session of this.live) session.detach();
    this.live.clear();
  }
}

export abstract class OwnProcessSession<T extends TurnState = TurnState> implements AgentSession {
  protected proc!: AgentProcess;
  protected readonly driver: OwnProcessDriver<any>;
  protected sessionId: string;
  protected turn: T;
  protected readonly events: Events;
  /// Requests of ours waiting for their answers.
  protected readonly waiting = new Waiting();
  /// The address of the station's tools it was given (one taken up from another station: as it was given then).
  toolsUrl: string | null = null;

  constructor(driver: OwnProcessDriver<any>, sessionId: string, turn: T, events: Events) {
    this.driver = driver;
    this.sessionId = sessionId;
    this.turn = turn;
    this.events = events;
  }

  /// Each line of its output (a message of the runtime's), in order.
  protected abstract heard(line: string): void;
  abstract prompt(text: string): Promise<void>;
  abstract steer(text: string): Promise<boolean>;
  abstract abort(): Promise<void>;
  abstract snapshot(): unknown;

  /// Its process went away during a turn: what is open of the turn ends with it (its steps, what is being written of it).
  protected cutShort(_said: string): void {}

  /// No turn runs any more.
  protected idle() {
    this.turn.busy = false;
  }

  protected get kind(): RuntimeKind {
    return this.driver.runtime();
  }

  attach(proc: AgentProcess) {
    this.proc = proc;
  }

  named(id: string) {
    this.sessionId = id;
  }

  processOptions(label: string) {
    return {
      label,
      line: (line: string) => this.heard(line),
      exit: (said: string, stderr: string) => this.exited(said, stderr),
    };
  }

  private exited(said: string, stderr: string) {
    // What it wrote to stderr last is the only word of why one that fails as it starts gives.
    const why = stderr === "" ? "" : `: ${stderr}`;
    this.turn.closed = true;
    this.waiting.failAll(new Error(`${this.kind} exited (${said})${why}`));
    const busy = this.busy();
    this.idle();
    if (busy) {
      this.cutShort(said);
      this.events({ type: "turnEnded", outcome: { kind: "failed", reason: "exited", message: `${this.kind} exited (${said}) during the turn${why}` } });
    }
    this.events({ type: "closed", why: `${this.kind} exited (${said})${why}` });
    this.driver.forget(this);
  }

  /// A turn can be started now: else why not.
  protected startable() {
    if (this.turn.closed) throw new Error(`${this.kind} session is closed`);
    if (this.busy()) throw new Error("a turn is already running");
  }

  /// Stops hearing it, for a snapshot: the turn stands as its last handled line left it, and the lines after are the
  /// next station's.
  protected handOver() {
    this.proc.freeze();
    this.turn.closed = true;
  }

  id() {
    return this.sessionId;
  }

  mcpUrl() {
    return this.toolsUrl;
  }

  busy() {
    return this.turn.busy;
  }

  async backgroundTools() {}

  async dispose() {
    this.driver.forget(this);
    this.turn.closed = true;
    this.waiting.failAll(new Error(`${this.kind} session is closed`));
    await this.proc.kill(5000);
  }

  detach() {
    this.turn.closed = true;
    this.driver.forget(this);
    this.proc.detach();
  }
}
