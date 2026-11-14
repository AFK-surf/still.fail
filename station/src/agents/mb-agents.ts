// Claude Code processes read by the MoonBit program (station/mb's reader `--agents`, mb/src/reader/agents.mbt), not
// on the station's thread: the program attaches to each process's runner, reads its stream-json and says what it comes
// to (the runtime's events, where the turn stands, up to where it read), which this hands the session and acknowledges
// once handed, the line then acknowledged to the runner. A process is started and ended here as process.ts does it;
// only reading it, and writing to it, go through the program. One that is not there (Windows, whose runners listen on
// a pipe; a checkout without the program; STILLFAIL_AGENTS_HOST=0) leaves the drivers reading as before.
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { MbProcess, mbReaderBinary } from "../read/mb-reader.ts";
import { platform } from "../platform/index.ts";
import { describeExit, endRunner, groupAlive } from "./process.ts";
import { leave, listening, startRunner, type RunnerInfo } from "./runner.ts";

type Json = any;

/// What the program says of a process's lines: the events, the turn as it left it, up to where.
export type Heard = { events: Json[]; turn: Json; to: number };

export type HostedOptions = {
  label: string;
  heard: (heard: Heard) => void;
  exit: (said: string, stderr: string) => void;
};

const pidAlive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

/// A wait on another process (a grace raced against its exit): the machine's time.
const sleep = wall.sleep;

export class AgentsHost {
  readonly #data: string;
  #proc: MbProcess | null = null;
  #ready: Promise<void> | null = null;
  #next = 0;
  readonly #sessions = new Map<number, HostedProcess>();
  readonly #freezes = new Map<number, (states: Record<string, { turn: Json; live: Json }>) => void>();
  #closed = false;

  private constructor(data: string) {
    this.#data = data;
  }

  /// The program for `data`'s processes, where it can read them.
  static where(data: string): AgentsHost | null {
    if (process.env.STILLFAIL_AGENTS_HOST === "0" || !platform.runnerSocketVisible) return null;
    return mbReaderBinary() === null ? null : new AgentsHost(data);
  }

  #start(): Promise<void> {
    if (this.#ready) return this.#ready;
    const proc = new MbProcess(mbReaderBinary()!, ["--agents", "1", "--data", this.#data]);
    this.#proc = proc;
    this.#ready = new Promise<void>((resolve) => {
      proc.on("message", (said: Json) => {
        if (said?.ready === true) {
          proc.postMessage({ wall: wall.now() });
          resolve();
        } else this.#said(said);
      });
    });
    proc.on("error", (error: Error) => log.warn("agents", "the program reading agents failed", { error: error.message }));
    proc.on("exit", (code: number) => {
      if (this.#closed) return;
      log.warn("agents", "the program reading agents ended; starting it again", { code });
      this.#proc = null;
      this.#ready = null;
      // (each process read again from where it was acknowledged, the turn as its session knows it)
      const again = [...this.#sessions.values()];
      // timer: a retry after a failure, with a backoff (one that keeps ending is started again each second at most)
      wall.after(1_000, () => {
        if (this.#closed) return;
        for (const p of again) if (!p.gone) void this.attach(p);
      });
    });
    return this.#ready;
  }

  #said(said: Json) {
    if (typeof said?.frozen === "number") {
      const done = this.#freezes.get(said.frozen);
      this.#freezes.delete(said.frozen);
      done?.(said.states ?? {});
      return;
    }
    const n = said?.lines ?? said?.exit ?? said?.closed ?? said?.left;
    const p = typeof n === "number" ? this.#sessions.get(n) : undefined;
    if (p === undefined) return;
    if (said.lines !== undefined) {
      p.heard({ events: Array.isArray(said.events) ? said.events : [], turn: said.turn, to: said.to });
      this.post({ ack: n, to: said.to });
    } else if (said.exit !== undefined) p.exited_(said.code ?? null, said.signal ?? null, typeof said.stderr === "string" ? said.stderr : "");
    else if (said.closed !== undefined) p.closed_();
    else p.left_();
  }

  post(message: Json) {
    this.#proc?.postMessage(message);
  }

  /// Reads `p`'s process (again, after the program started again: from where it was acknowledged).
  async attach(p: HostedProcess) {
    await this.#start();
    this.#sessions.set(p.n, p);
    this.post({ attach: p.n, socket: p.info.socket, turn: p.turnNow(), live: p.liveNow() });
  }

  number() {
    return ++this.#next;
  }

  forget(p: HostedProcess) {
    this.#sessions.delete(p.n);
  }

  /// Every process's lines held (the station hands over): each one's turn and live steps as they stand then.
  async freeze(): Promise<void> {
    if (this.#proc === null || this.#sessions.size === 0) return;
    const id = this.number();
    const states = await new Promise<Record<string, { turn: Json; live: Json }>>((resolve) => {
      this.#freezes.set(id, resolve);
      this.post({ freeze: id });
    });
    for (const [n, state] of Object.entries(states)) this.#sessions.get(Number(n))?.froze(state.turn, state.live);
  }

  /// Read on again (a handover that did not happen).
  thaw() {
    for (const p of this.#sessions.values()) {
      p.thawed();
      this.post({ thaw: p.n });
    }
  }

  async close() {
    this.#closed = true;
    await this.#proc?.terminate();
  }
}

/// A process under a runner, read by the program: what process.ts `AgentProcess` is to a driver, its lines told as
/// `heard`.
export class HostedProcess {
  readonly info: RunnerInfo;
  readonly n: number;
  readonly #host: AgentsHost;
  readonly #options: HostedOptions;
  #frozen = false;
  gone = false;
  #killing = false;
  #said: string | null = null;
  /// The turn and live steps as they were last said: what the program takes up again with, and a snapshot says.
  #turn: Json;
  #live: Json;
  #frozenState: { turn: Json; live: Json } | null = null;
  readonly exited: Promise<string>;
  #resolveExit!: (said: string) => void;
  #left: (() => void) | null = null;

  private constructor(host: AgentsHost, info: RunnerInfo, options: HostedOptions, turn: Json, live: Json) {
    this.#host = host;
    this.info = info;
    this.n = host.number();
    this.#options = options;
    this.#turn = turn;
    this.#live = live;
    this.exited = new Promise((resolve) => (this.#resolveExit = resolve));
  }

  /// Starts `program` under a runner `id` (one of that id left by an earlier station ended first), read by `host`.
  static async start(host: AgentsHost, data: string, id: string, program: string, args: string[], env: Record<string, string>, cwd: string, options: HostedOptions, turn: Json) {
    await endRunner(data, id, options.label);
    const info = await startRunner(data, id, program, args, env, cwd);
    const p = new HostedProcess(host, info, options, turn, null);
    await host.attach(p);
    return p;
  }

  /// Takes up the process a runner keeps, its turn and live steps as `turn` and `live` say.
  static async adopt(host: AgentsHost, info: RunnerInfo, options: HostedOptions, turn: Json, live: Json) {
    if (!listening(info)) throw new Error(`runner ${info.id} has no socket`);
    const p = new HostedProcess(host, info, options, turn, live);
    await host.attach(p);
    return p;
  }

  get pgid() {
    return this.info.pgid;
  }

  turnNow() {
    return this.#turn;
  }

  liveNow() {
    return this.#live;
  }

  /// Where it stood as its lines were held (a handover): what its snapshot says.
  frozenState() {
    return this.#frozenState;
  }

  heard(heard: Heard) {
    if (this.gone) return;
    this.#turn = heard.turn;
    this.#options.heard(heard);
  }

  froze(turn: Json, live: Json) {
    this.#turn = turn;
    this.#live = live;
    this.#frozenState = { turn, live };
  }

  thawed() {
    this.#frozenState = null;
  }

  exited_(code: number | null, signal: string | null, stderr: string) {
    if (this.#said !== null) return;
    this.#said = describeExit({ code, signal });
    this.#resolveExit(this.#said);
    if (this.#frozen) return;
    this.#options.exit(this.#said, stderr);
    if (!this.#killing) this.done();
  }

  closed_() {
    if (this.gone || this.#said !== null) return;
    if (pidAlive(this.info.runner)) {
      log.warn("agents::process", "another station took the runner over; letting go", { label: this.#options.label });
      this.#frozen = true;
      this.gone = true;
      this.#host.forget(this);
    } else {
      this.#said = "runner gone";
      this.#resolveExit(this.#said);
      if (!this.#frozen) this.#options.exit(this.#said, "");
      this.#host.forget(this);
    }
  }

  left_() {
    this.#host.forget(this);
    this.#left?.();
  }

  hasExited() {
    return this.#said !== null;
  }

  handed() {
    return this.#frozen;
  }

  write(line: string) {
    if (this.#frozen) return;
    this.#host.post({ write: this.n, line });
  }

  /// What a prompt, an abort or a new token does to the turn before what goes with it is written (claude.ts `begin`,
  /// `compact`, `abort`, `renewToken`): the program keeps the turn.
  tell(what: "begin" | "compact" | "aborting" | "renewed") {
    if (this.#frozen) return;
    if (what === "compact") this.#host.post({ begin: this.n, compact: true });
    else this.#host.post({ [what]: this.n });
  }

  keepFrom(_at: number) {}

  freeze() {
    this.#frozen = true;
  }

  detach() {
    this.#frozen = true;
    if (this.gone) return;
    this.gone = true;
    leave(new Promise<void>((resolve) => {
      this.#left = resolve;
      this.#host.post({ detach: this.n });
    }));
  }

  done() {
    this.#host.post({ done: this.n });
  }

  async released() {
    if (this.#frozen || this.#said === null) return;
    for (let i = 0; i < 200 && pidAlive(this.info.runner); i++) await sleep(10);
  }

  async kill(graceMs: number) {
    if (this.#frozen) return;
    if (this.#killing) {
      await this.exited;
      return;
    }
    this.#killing = true;
    this.#host.post({ signal: this.n, name: "TERM" });
    await Promise.race([this.exited, sleep(graceMs)]);
    if (groupAlive(this.pgid)) {
      this.#host.post({ signal: this.n, name: "KILL" });
      for (let i = 0; i < 100 && groupAlive(this.pgid); i++) await sleep(10);
    }
    await Promise.race([this.exited, sleep(1000)]);
    this.done();
    for (let i = 0; i < 200 && pidAlive(this.info.runner); i++) await sleep(10);
  }
}
