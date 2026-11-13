// A runtime process under a runner (./runner.ts), as the drivers use it: what runtime/process.rs GroupProcess was
// (a group of its own; lines of stdout to a handler, stderr to the log; write a line; SIGTERM the group, SIGKILL what
// is left after a grace), with the runner's ways of being let go and taken up again in place of the fd hand-off.
//
// Taking up: lines this station has handled are acknowledged once handled, so a next station is sent exactly the rest.
// `freeze` stops handling lines (none more is acknowledged): what a snapshot says then matches where the next station
// begins. After a crash there is no snapshot; `ackedOffset` and `linesBefore` let a driver read what the dead station
// had handled (silently) to know where things stand before the rest comes.
import { statSync } from "node:fs";
import { open } from "node:fs/promises";
import { createConnection } from "node:net";
import { join } from "node:path";
import { keyPart } from "./sandbox.ts";
import { log } from "../ops/log.ts";
import { Lines, RunnerConnection, leave, listening, listeningSoon, runnerOf, runnersDir, startRunner, type Exit, type RunnerInfo } from "./runner.ts";
import { wall } from "../ops/fibers.ts";
import type { RuntimeKind } from "./runtime.ts";

/// A wait on another process (a grace raced against its exit): the machine's time.
const sleep = wall.sleep;

/// Lines Rust logged at debug: only with STILLFAIL_AGENTS_DEBUG set.
export const debug = (at: string, message: string, fields?: Record<string, unknown>) => {
  if (process.env.STILLFAIL_AGENTS_DEBUG) log.info(at, message, fields);
};

/// A runner id from something of the station's (a session key, a profile id): safe as a file name and short enough for
/// the socket's path (104 bytes on macOS); a hash keeps two keys that clean up the same apart.
export function runnerId(kind: RuntimeKind, key: string): string {
  return `${kind}-${keyPart(key)}`;
}

/// How Rust's process.rs `describe` says an exit: its code, or the signal's name.
export function describeExit(exit: Exit): string {
  if (exit.code !== null) return String(exit.code);
  const named = ["TERM", "KILL", "INT", "HUP"];
  if (exit.signal && named.includes(exit.signal)) return `SIG${exit.signal}`;
  return exit.signal ? `signal ${exit.signal}` : "unknown";
}

export function groupAlive(pgid: number): boolean {
  try {
    process.kill(-pgid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}

const pidAlive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

/// A runner of this id that keeps its process still (its socket there: one on its way out has let it go).
export const findRunner = async (data: string, id: string): Promise<RunnerInfo | undefined> => {
  const runner = await runnerOf(data, id);
  return runner !== undefined && runner.id === id && (await listeningSoon(runner)) ? runner : undefined;
};
export const outFile = (data: string, id: string) => join(runnersDir(data), `${id}.out`);

/// The connection's socket, which runner.ts keeps to itself: its errors would otherwise go unhandled, and its closing
/// (the runner gone, or another station attached) is how this one learns of it.
function socketOf(conn: RunnerConnection): import("node:net").Socket {
  return conn["socket"];
}

export type ProcessOptions = {
  /// For the log: what it is ("claude <session>", "codex app-server <profile>").
  label: string;
  /// Each line of its stdout, in order, with where in its output it begins and ends; acknowledged once this returns.
  line: (text: string, from: number, to: number) => void;
  /// It exited (all of its output handled), as `describeExit` says, unless it was let go first; with the last lines it
  /// wrote to stderr (STDERR_TAIL of them, "" when none): what a runtime that fails as it starts says of why.
  exit: (said: string, stderr: string) => void;
  /// Run here even when the station runs things in sandboxes (agents/sandbox.ts): a process no session's work runs in.
  local?: boolean;
};

/// How many of a runtime's last stderr lines its exit carries, and how long each may be.
const STDERR_TAIL = 3;
const STDERR_LINE = 300;

export class AgentProcess {
  readonly info: RunnerInfo;
  private conn: RunnerConnection;
  private frozen = false;
  private gone = false;
  private killing = false;
  private said: string | null = null;
  /// Its last lines of stderr, for its exit.
  private stderr: string[] = [];
  /// Its exit, described; resolved once its last line has been handled.
  readonly exited: Promise<string>;

  private constructor(info: RunnerInfo, options: ProcessOptions) {
    this.info = info;
    let resolveExit!: (said: string) => void;
    this.exited = new Promise((resolve) => (resolveExit = resolve));
    this.conn = new RunnerConnection(info, (stream, text, from, to) => {
      // Frozen: the line stays unacknowledged, for whoever takes the process up next.
      if (this.frozen) return new Promise<void>(() => {});
      const line = text.endsWith("\r") ? text.slice(0, -1) : text;
      if (stream === "err") {
        debug("agents::process", "runtime stderr", { label: options.label, line: line.slice(0, 2000) });
        if (line.trim() !== "") this.stderr = [...this.stderr, line.trim().slice(0, STDERR_LINE)].slice(-STDERR_TAIL);
      } else options.line(line, from, to);
    });
    const socket = socketOf(this.conn);
    socket.on("error", (error) => {
      if (!this.gone) log.warn("agents::process", "runner connection failed", { label: options.label, error: String(error) });
    });
    socket.on("close", () => {
      if (this.gone || this.said !== null) return;
      // Another station attached (the runner keeps one connection), or the runner itself is gone (killed): then the
      // agent went with its stdin, and nothing will say how it ended.
      if (pidAlive(info.runner)) {
        log.warn("agents::process", "another station took the runner over; letting go", { label: options.label });
        this.frozen = true;
        this.gone = true;
      } else {
        this.said = "runner gone";
        resolveExit(this.said);
        if (!this.frozen) options.exit(this.said, this.stderr.join("\n"));
      }
    });
    this.conn.exited.then((exit) => {
      if (this.said !== null) return;
      this.said = describeExit(exit);
      resolveExit(this.said);
      if (this.frozen) return;
      options.exit(this.said, this.stderr.join("\n"));
      // Read to the end: the runner may go (kill does it once what is left of the group is gone).
      if (!this.killing) this.conn.done();
    });
  }

  /// Starts `program` under a runner `id`. A runner of that id still there (a process an earlier station left and
  /// nobody took up) is ended first, as process.rs reap_stale_groups did.
  static async start(data: string, id: string, program: string, args: string[], env: Record<string, string>, cwd: string, options: ProcessOptions) {
    await endRunner(data, id, options.label);
    const info = await startRunner(data, id, program, args, env, cwd, options.local === true);
    return new AgentProcess(info, options);
  }

  /// Takes up the process a runner keeps: from its first line not acknowledged.
  static adopt(info: RunnerInfo, options: ProcessOptions) {
    if (!listening(info)) throw new Error(`runner ${info.id} has no socket`);
    return new AgentProcess(info, options);
  }

  get pgid() {
    return this.info.pgid;
  }

  hasExited() {
    return this.said !== null;
  }

  /// Let go (or frozen for that): no longer this station's to write to, kill or hear.
  handed() {
    return this.frozen;
  }

  /// Writes a line to its stdin (the newline added); nothing once it is let go.
  write(line: string) {
    if (this.frozen) return;
    this.conn.write(line.endsWith("\n") ? line : `${line}\n`);
  }

  /// The runner gives the disk back under its stdout only up to `at` (told with the next ack): what is read again after
  /// a crash begins there.
  keepFrom(at: number) {
    this.conn.keep = at;
  }

  /// Stops handling its lines: the next station is sent them.
  freeze() {
    this.frozen = true;
  }

  /// Lets go of it without ending it. What was handled is acknowledged first (acks go out as handlers return).
  detach() {
    this.frozen = true;
    if (this.gone) return;
    this.gone = true;
    leave(new Promise((resolve) => setImmediate(() => resolve(this.conn.detach()))));
  }

  /// Once it has exited by itself and been read to the end, its runner (told `done`) cleans up and goes, a moment after:
  /// waited for, so a process started or taken up under its id next is never that runner on its way out (taken up, it
  /// would be gone under the one taking it: its socket removed, its agent long exited). One let go stays for the next
  /// station; one still running is not this to wait for.
  async released() {
    if (this.frozen || this.said === null) return;
    for (let i = 0; i < 200 && pidAlive(this.info.runner); i++) await sleep(10);
  }

  /// SIGTERM the whole group, SIGKILL whatever is left after `graceMs`; then the runner may go.
  async kill(graceMs: number) {
    if (this.frozen) return;
    if (this.killing) {
      await this.exited;
      return;
    }
    this.killing = true;
    this.conn.signal("TERM", true);
    // The leader's exit is the signal the group is done; what outlives it, or a leader that ignores SIGTERM, is killed.
    await Promise.race([this.exited, sleep(graceMs)]);
    if (groupAlive(this.pgid)) {
      this.conn.signal("KILL", true);
      // Gone once the system has taken them away, a moment after.
      for (let i = 0; i < 100 && groupAlive(this.pgid); i++) await sleep(10);
    }
    await Promise.race([this.exited, sleep(1000)]);
    this.conn.done();
    // The runner itself goes once it has told: waited for, so a process started under its id next is not taken for it.
    for (let i = 0; i < 200 && pidAlive(this.info.runner); i++) await sleep(10);
  }
}

/// Ends a runner of this id left by an earlier station, and waits for it to go.
export async function endRunner(data: string, id: string, label: string) {
  const info = await findRunner(data, id);
  if (!info) return;
  log.warn("agents::process", "ending a runtime process left by a previous run", { label, runner: info.runner, pgid: info.pgid });
  if (listening(info)) {
    const conn = new RunnerConnection(info, () => {});
    socketOf(conn).on("error", () => {});
    conn.signal("TERM", true);
    await Promise.race([conn.exited, sleep(2000)]);
    if (groupAlive(info.pgid)) conn.signal("KILL", true);
    await Promise.race([conn.exited, sleep(1000)]);
    conn.done();
  }
  for (let i = 0; i < 300 && pidAlive(info.runner); i++) await sleep(10);
}

/// Where the runner will start sending stdout from: the end of what the previous station acknowledged; and where of
/// stdout that station kept what is read again after a crash (`keep`, told with that same ack; null: a runner from
/// before, or none told). Asked by attaching once without acknowledging anything (the runner sends from its
/// acknowledged place on each attach, saying first where that is: one from before says nothing).
export function ackedOffset(info: RunnerInfo, out: string): Promise<{ at: number; keep: number | null }> {
  return new Promise((resolve) => {
    const socket = createConnection(info.socket);
    let carry = "";
    let done = false;
    const finish = (at: number, keep: number | null = null) => {
      if (done) return;
      done = true;
      quiet();
      socket.destroy();
      resolve({ at, keep });
    };
    const size = () => {
      try {
        return statSync(out).size;
      } catch {
        return 0;
      }
    };
    socket.on("error", () => finish(size()));
    socket.on("connect", () => socket.write(JSON.stringify({ op: "attach" }) + "\n"));
    socket.on("data", (chunk) => {
      carry += chunk.toString("utf8");
      for (let i = carry.indexOf("\n"); i >= 0; i = carry.indexOf("\n")) {
        const message = JSON.parse(carry.slice(0, i));
        carry = carry.slice(i + 1);
        if (message.op === "attached" && Number.isSafeInteger(message.out)) return finish(message.out, Number.isSafeInteger(message.keep) ? Math.min(message.keep, message.out) : null);
        if (message.op === "out" && message.stream === "out") return finish(message.at);
        // The exit comes after all output: nothing of stdout was left to send.
        if (message.op === "exit") return finish(size());
      }
    });
    // Nothing of stdout comes: all of it was acknowledged. What it had then is the place; output written just after
    // that look would come in the moment after, and says its own place.
    let quiet = wall.after(400, () => {
      const end = size();
      quiet = wall.after(150, () => finish(end));
    });
  });
}

/// How much of a runner's output `linesBefore` holds at once.
const READ_CHUNK = 1 << 20;

/// The whole lines of `file` before byte `end` (a line boundary: acknowledgements are at line ends), one at a time: an
/// app-server's output holds days of its threads (hundreds of MB), more than one string can, so it is never held whole.
export async function* linesBefore(file: string, end: number, chunk = READ_CHUNK): AsyncGenerator<string> {
  for await (const line of linesWithin(file, 0, end, chunk)) yield line.text;
}

/// The whole lines of `file` from byte `start` to byte `end` (both line boundaries), each with where it begins. Read off
/// the station's thread: what a station taking up its runners reads, up to hundreds of MB, held it 33 s on one
/// (2026-11-06).
export async function* linesWithin(file: string, start: number, end: number, chunk = READ_CHUNK): AsyncGenerator<{ text: string; at: number }> {
  for await (const line of bytesWithin(file, start, end, chunk)) yield { text: line.bytes.toString("utf8"), at: line.at };
}

/// `linesWithin`'s lines as their bytes, not decoded: what reads only some of them tells the rest by how they begin
/// (codex.ts `takeUp`), and most of an app-server's output is lines it passes over, MBs each.
export async function* bytesWithin(file: string, start: number, end: number, chunk = READ_CHUNK): AsyncGenerator<{ bytes: Buffer; at: number }> {
  if (end <= start) return;
  const fd = await open(file, "r");
  try {
    // A line longer than a chunk is held a part at a time and joined once, at its end.
    const lines = new Lines();
    let at = start;
    // Where the line held (or the next) begins in the file.
    let base = start;
    while (at < end) {
      const buf = Buffer.allocUnsafe(Math.min(chunk, end - at));
      const { bytesRead: n } = await fd.read(buf, 0, buf.length, at);
      if (n <= 0) break;
      // Where the runner gave the disk back (what was acknowledged long before: native/runner `punch`) it reads as
      // zeros: skipped, with the line it cut (never carried on, a part at a time, as one line hundreds of MB long).
      let skip = 0;
      if (buf[0] === 0) {
        while (skip < n && buf[skip] === 0) skip++;
        lines.drop();
        base = at + skip;
      }
      at += n;
      for (const line of lines.take(buf.subarray(skip, n))) {
        const lineAt = base;
        base += line.length + 1;
        yield { bytes: line.at(-1) === 0x0d ? line.subarray(0, -1) : line, at: lineAt };
      }
    }
  } finally {
    await fd.close();
  }
}
