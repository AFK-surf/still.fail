// Codex driver (the Rust station's runtime/codex.rs): one shared `codex app-server` per profile, under a runner whose id comes
// from the profile, one thread per session.
//
// Pinned by spikes (spike/README.md):
// - a thread adds <1MB to its app-server, so sessions share one process;
// - per-session settings (the MCP endpoint and token) travel in the thread/start|resume `config`, not the process
//   environment;
// - threads need sandbox "danger-full-access" with approvalPolicy "never", or MCP tool calls are refused.
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, realpathSync, statSync } from "node:fs";
import { join } from "node:path";
import { agentEnv } from "../ops/agent-env.ts";
import { log } from "../ops/log.ts";
import { LiveFromCodex, chars, type CodexLiveState } from "./live.ts";
import { linkCodexAuth, type Env } from "./machine-logins.ts";
import { keyOfRunner, lentFile, sandboxed, syncNow } from "./sandbox.ts";
import { AgentProcess, ackedOffset, debug, findRunner, linesBefore, outFile, runnerId } from "./process.ts";
import { accessKind, codexOverrides, expandRoute, isMachine, profileEnv, profileFast, profileModel, profileVia } from "./profiles.ts";
import { TOOL_SERVERS, cleanEnv, unreachable, type AgentDriver, type AgentSession, type FailureReason, type OpenOptions, type Profile, type RuntimeEvent, type TurnOutcome } from "./runtime.ts";
import type { RunnerInfo } from "./runner.ts";
import { wall } from "../ops/fibers.ts";
import { run } from "../updates/runtimes.ts";
import { versionIn } from "../updates/versions.ts";

type Json = any;

const SCRUBBED = ["OPENAI_API_KEY", "CODEX_HOME"];

/// Codex otherwise reads the system's root certificates for each new connection. On macOS, from a process outside the
/// desktop session, that can take seconds or hang past its 15 s request timeout, and fail with UnknownIssuer.
/// SSL_CERT_FILE makes it use a CA file instead, for its model websocket as well as its HTTP clients. One the user set
/// wins.
const CA_BUNDLE = "/etc/ssl/cert.pem";

export function withCaBundle(env: Record<string, string>, bundle: string) {
  if (["SSL_CERT_FILE", "SSL_CERT_DIR", "CODEX_CA_CERTIFICATE"].some((k) => k in env) || !existsSync(bundle)) return;
  env.SSL_CERT_FILE = bundle;
}

/// Paths in the order Rust sorts PathBufs: component by component.
function comparePaths(a: string, b: string): number {
  const x = a.split("/");
  const y = b.split("/");
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    if (x[i] !== y[i]) return x[i]! < y[i]! ? -1 : 1;
  }
  return x.length - y.length;
}

/// Codex also loads the skills in the user's own ~/.agents/skills. The station's agents share skills through the agent
/// home instead, and the personal ones pull them off course, so each is turned off by path: codex's skills.config takes
/// files, not directories.
export function hostSkillsOff(root: string): { path: string; enabled: false }[] {
  const found: string[] = [];
  const visited = new Set<string>();
  const walk = (dir: string, depth: number) => {
    if (depth > 6) return;
    let real: string;
    try {
      real = realpathSync(dir);
    } catch {
      return;
    }
    if (visited.has(real)) return;
    visited.add(real);
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return;
    }
    for (const name of entries) {
      const path = join(dir, name);
      // Follows links: skill folders are often linked in.
      let isDir: boolean;
      try {
        isDir = statSync(path).isDirectory();
      } catch {
        continue;
      }
      if (isDir) walk(path, depth + 1);
      else if (name === "SKILL.md") found.push(path);
    }
  };
  walk(root, 0);
  return found.sort(comparePaths).map((path) => ({ path, enabled: false as const }));
}

export function classifyCodexError(info: unknown): FailureReason {
  const code = typeof info === "string" ? info : info && typeof info === "object" && !Array.isArray(info) ? Object.keys(info)[0] : undefined;
  if (code === "unauthorized") return "auth";
  if (code === "usageLimitExceeded" || code === "rateLimitExceeded") return "rate_limit";
  if (code === "serverOverloaded") return "overloaded";
  return "model";
}

/// Keeps capabilities alongside model ids; an old runtime may omit them.
export class ModelCatalog {
  models: string[] = [];
  efforts = new Map<string, string[]>();

  extend(answer: Json) {
    const rows = answer?.data;
    if (!Array.isArray(rows)) throw new Error("model/list omitted data");
    for (const m of rows.filter((m: Json) => m?.hidden !== true)) {
      const id = typeof m?.id === "string" ? m.id : typeof m?.model === "string" && m?.id === undefined ? m.model : undefined;
      if (!id) continue;
      this.models.push(id);
      if (Array.isArray(m.supportedReasoningEfforts)) {
        const efforts: string[] = [];
        for (const level of m.supportedReasoningEfforts) {
          const effort = level?.reasoningEffort;
          if (typeof effort === "string" && effort !== "" && !efforts.includes(effort)) efforts.push(effort);
        }
        this.efforts.set(id, efforts);
      }
    }
  }
}

/// A thread's share of its app-server's notifications.
type Notice = { kind: "method"; method: string; params: Json } | { kind: "hostExited"; reason: string };
type Sink = (notice: Notice) => void;

/// What a crashed station had seen of a thread (read again from the app-server's output).
type Recovered = { busy: boolean; turnId: string | null; live: LiveFromCodex };

/// While sessions are being taken up, what the app-server says of a thread not taken up yet waits this long for it.
const ORPHANS_MS = 60_000;
const ORPHANS_MAX = 10_000;

function hostSignature(profile: Profile): string {
  const sorted = (entries: [string, string][]) => Object.fromEntries([...entries].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  return JSON.stringify([
    profile.home,
    sorted(Object.entries(profileEnv(profile, "codex"))),
    // The station's variables for its agents: changed, the app-server starts again with them once no turn runs on it.
    sorted(Object.entries(agentEnv())),
    sorted(codexOverrides(accessKind(profile), profileModel(profile), profileVia(profile))),
  ]);
}

function hostArgs(profile: Profile): string[] {
  const args = ["app-server"];
  for (const [k, v] of codexOverrides(accessKind(profile), profileModel(profile), profileVia(profile))) args.push("-c", `${k}=${v}`);
  args.push("--listen", "stdio://");
  return args;
}

/// The version in what an app-server answered `initialize` with ("stillfail/0.162.1 (Mac OS …) …").
export function userAgentVersion(userAgent: unknown): string | null {
  if (typeof userAgent !== "string") return null;
  return versionIn(userAgent.split(/\s/)[0]?.split("/")[1] ?? "");
}

/// The version an app-server a runner keeps runs: its answer to `initialize`, the first line it wrote.
function versionInOutput(file: string): string | null {
  let fd: number;
  try {
    fd = openSync(file, "r");
  } catch {
    return null;
  }
  try {
    const buf = Buffer.alloc(4096);
    const n = readSync(fd, buf, 0, buf.length, 0);
    const first = buf.subarray(0, n).toString("utf8").split("\n")[0] ?? "";
    return userAgentVersion(JSON.parse(first)?.result?.userAgent);
  } catch {
    return null;
  } finally {
    closeSync(fd);
  }
}

/// How often what `codex` on the PATH is now is read again, while app-servers are looked at.
const INSTALLED_MS = 60_000;

type Pending = { method: string; resolve: (v: Json) => void; reject: (e: Error) => void };

/// One app-server process and its JSON-RPC connection.
class Host {
  proc!: AgentProcess;
  readonly pending = new Map<number, Pending>();
  readonly threads = new Map<string, Sink>();
  /// Its threads in a turn (one asked to start counts).
  readonly turns = new Set<string>();
  /// The Codex it runs (null: not known). Updated on the disk, the files it starts its helpers from are gone, and every
  /// tool call of its threads fails: it is replaced once no turn runs on it.
  version: string | null = null;
  private ready: boolean;
  private readying: Promise<void> | null = null;
  /// Notices for threads not taken up yet, while sessions are being taken up (null otherwise).
  private orphans: Map<string, Notice[]> | null = null;
  /// After a crash: where each thread stood when the station that crashed stopped acknowledging.
  recovered = new Map<string, Recovered>();
  readonly profile: string;
  /// Which app-server of the driver's it is (`hostKey`): its profile's, or one session's when the station runs things in
  /// sandboxes.
  readonly key: string;
  /// What the process was started with; a profile edit that changes it needs a new process.
  readonly signature: string;
  private nextId: number;

  constructor(profile: string, signature: string, nextId: number, ready: boolean, key = profile) {
    this.profile = profile;
    this.key = key;
    this.signature = signature;
    this.nextId = nextId;
    this.ready = ready;
  }

  processOptions(label: string) {
    return { label, line: (line: string) => this.onLine(line), exit: (said: string, stderr: string) => this.onExit(said, stderr) };
  }

  /// When the login it was started with runs out, if it was lent by another station.
  lentUntil: number | null = null;

  /// `cwd`: where it runs, its profile's home; a session's own app-server in the session's workspace (in its sandbox,
  /// made there with it).
  static async start(profile: Profile, key: string, command: string, data: string, env: Env, caBundle: string, lent?: CodexDriverOptions["lent"], cwd = profile.home): Promise<Host> {
    mkdirSync(profile.home, { recursive: true });
    if (isMachine(profile)) linkCodexAuth(profile.home, env);
    const until = lent?.borrowed(profile) ? await lent.write(profile) : null;
    const childEnv: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(profile, "codex"), profile.id) };
    childEnv.CODEX_HOME = profile.home;
    withCaBundle(childEnv, caBundle);
    const host = new Host(profile.id, hostSignature(profile), 1, false, key);
    host.lentUntil = until;
    const label = `codex app-server ${key}`;
    // A profile's own app-server (its account's limits and models, no session's work) runs here; a session's in its
    // sandbox when the station runs things there.
    host.proc = await AgentProcess.start(data, runnerId("codex", key), command, hostArgs(profile), childEnv, cwd, { ...host.processOptions(label), local: key === profile.id });
    return host;
  }

  /// Takes up an app-server a runner keeps. Replies to what the previous station asked are dropped: its ids are below
  /// `nextId`.
  static adopt(profile: string, info: RunnerInfo, signature: string, nextId: number, ready: boolean, recovered?: Map<string, Recovered>, key = profile): Host {
    log.info("agents::codex", "taking up a codex app-server", { profile, key, pgid: info.pgid, crashed: recovered !== undefined });
    const host = new Host(profile, signature, nextId, ready, key);
    if (recovered) host.recovered = recovered;
    host.orphans = new Map();
    wall.after(ORPHANS_MS, () => {
      const dropped = [...(host.orphans?.values() ?? [])].reduce((n, l) => n + l.length, 0);
      if (dropped > 0) log.warn("agents::codex", "notifications for threads nobody took up, dropped", { profile, threads: host.orphans?.size, dropped });
      host.orphans = null;
    });
    host.proc = AgentProcess.adopt(info, host.processOptions(`codex app-server ${profile}`));
    return host;
  }

  alive() {
    return !this.proc.hasExited() && !this.proc.handed();
  }

  /// A thread's sink, and what came for it before it was taken up.
  addThread(threadId: string, sink: Sink) {
    this.threads.set(threadId, sink);
    const waiting = this.orphans?.get(threadId);
    if (waiting) {
      this.orphans!.delete(threadId);
      for (const notice of waiting) sink(notice);
    }
  }

  private onLine(line: string) {
    let msg: Json;
    try {
      msg = JSON.parse(line);
    } catch {
      debug("agents::codex", "codex non-json line", { line: line.slice(0, 500) });
      return;
    }
    const method = typeof msg?.method === "string" ? (msg.method as string) : undefined;
    if (Number.isInteger(msg?.id) && method === undefined) {
      const reply = this.pending.get(msg.id);
      if (!reply) {
        log.info("agents::codex", "a reply to a request of an earlier station, dropped", { profile: this.profile, id: msg.id });
        return;
      }
      this.pending.delete(msg.id);
      if (msg.error !== undefined && msg.error !== null) reply.reject(new Error(`codex ${JSON.stringify(msg.error)}`));
      else reply.resolve(msg.result === undefined ? null : msg.result);
    } else if (msg?.id !== undefined && msg?.id !== null && method !== undefined) {
      // Server->client requests (approvals) should not arrive with approvalPolicy "never"; refuse rather than hang.
      log.warn("agents::codex", "codex asked the client something; refusing", { method });
      this.proc.write(JSON.stringify({ id: msg.id, error: { code: -32601, message: "the station does not answer client requests" } }));
    } else if (method !== undefined) {
      const params = msg.params === undefined ? null : msg.params;
      const thread = typeof params?.threadId === "string" ? (params.threadId as string) : undefined;
      if (thread === undefined) return;
      const notice: Notice = { kind: "method", method, params };
      const sink = this.threads.get(thread);
      if (sink) sink(notice);
      else if (this.orphans) {
        const waiting = this.orphans.get(thread) ?? [];
        if (waiting.length < ORPHANS_MAX) waiting.push(notice);
        this.orphans.set(thread, waiting);
      }
    }
  }

  private onExit(said: string, stderr: string) {
    const reason = `codex app-server exited (${said})${stderr === "" ? "" : `: ${stderr}`}`;
    for (const pending of this.pending.values()) pending.reject(new Error(reason));
    this.pending.clear();
    const threads = [...this.threads.values()];
    this.threads.clear();
    this.turns.clear();
    for (const thread of threads) thread({ kind: "hostExited", reason });
  }

  async ensureReady() {
    while (this.readying) await this.readying;
    if (this.ready) return;
    this.readying = (async () => {
      const answer = await this.request("initialize", { clientInfo: { name: "stillfail", version: "0" }, capabilities: { experimentalApi: true } });
      this.version = userAgentVersion(answer?.userAgent);
      this.proc.write(JSON.stringify({ method: "initialized", params: {} }));
      this.ready = true;
    })();
    try {
      await this.readying;
    } finally {
      this.readying = null;
    }
  }

  request(method: string, params: Json): Promise<Json> {
    if (this.proc.handed()) return Promise.reject(new Error("codex app-server was handed over"));
    if (!this.alive()) return Promise.reject(new Error("codex app-server is not running"));
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { method, resolve, reject });
      this.proc.write(JSON.stringify({ id, method, params }));
    });
  }

  /// Stops hearing it (handover): what it says from now on is the next station's; replies owed go there (and are
  /// dropped there).
  freeze() {
    if (this.proc.handed()) return;
    this.proc.freeze();
    for (const pending of this.pending.values()) pending.reject(new Error("codex app-server was handed over"));
    this.pending.clear();
  }

  detach() {
    this.freeze();
    this.threads.clear();
    this.proc.detach();
  }

  snapshot(): CodexHostSnapshot {
    return { runner: this.proc.info.id, signature: this.signature, nextId: this.nextId, ready: this.ready, ...(this.key !== this.profile ? { key: this.key } : {}) };
  }
}

/// `key`: the driver's key for it when not its profile's (`hostKey`); none from a station before it.
export type CodexHostSnapshot = { runner: string; signature: string; nextId: number; ready: boolean; key?: string };

/// A thread as a next station takes it up (codex.rs HandedThread), with what its app-server needs (HandedHost).
export type CodexSnapshot = {
  runtime: "codex";
  threadId: string;
  profile: string;
  busy: boolean;
  turnId: string | null;
  live: CodexLiveState;
  host: CodexHostSnapshot;
  /// The model and effort it was retuned to, given with its turns (optional: a station from before it does not say).
  tuned?: { model: string; effort: string } | null;
  /// The address of the station's tools its thread was given (optional: a station from before it does not say).
  mcpUrl?: string | null;
};

export type CodexDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path (server.rs gives "codex").
  command?: string;
  /// The station's own environment (the machine's Codex home is found in it); process.env by default.
  env?: Env;
  /// Where the user's own skills are (~/.agents/skills), turned off for the station's agents.
  hostSkills?: string;
  /// The CA file Codex is pointed at (/etc/ssl/cert.pem).
  caBundle?: string;
  /// A session's own Fast choice (store.rs codex_session_fast): undefined when it has none.
  fast?: (threadId: string) => boolean | undefined;
  /// A profile as the config says now (settings), for what a turn reads of it; the opened one otherwise.
  currentProfile?: (id: string) => Profile | undefined;
  /// Another station's subscription, borrowed (share/index.ts): its home's auth.json written with tokens lent by the
  /// station signed in on it (none Codex could renew with); when they run out.
  lent?: { borrowed(profile: Profile): boolean; write(profile: Profile): Promise<number> };
  /// The version of Codex `codex` on the PATH is now (null: not known); `codex --version` by default.
  installedVersion?: () => Promise<string | null>;
  /// Bytes of output an app-server may have before it is replaced (OUTPUT_LIMIT).
  outputLimit?: number;
};

/// An app-server's runner keeps all it wrote (every diff and command output of every thread on it, hundreds of MB in a
/// week) as long as it runs, and a station taking it up after a crash reads all of it again: past this, it is replaced
/// once no turn runs on it, as one Codex was updated under is, and its runner's file goes with it.
const OUTPUT_LIMIT = 64 * 1024 * 1024;

/// What an app-server writes most of and that says nothing of where a thread stands (LiveFromCodex keeps no state of
/// either): not parsed again when its output is read after a crash.
const UNTOLD = ['{"method":"turn/diff/updated"', '{"method":"item/commandExecution/outputDelta"'];

/// A borrowed login this close to its end is replaced in its home's auth.json, under the app-server running on it: Codex
/// reads that file again when it is refused (UnauthorizedRecovery's first step, codex-rs login/src/auth/manager.rs) and
/// goes on with the new one, its threads and their turns as they were.
const LENT_RENEW_MS = 6 * 3600_000;

/// When the access token in a home's auth.json runs out (0 when it does not say).
function lentExpiry(home: string): number {
  try {
    const token = JSON.parse(readFileSync(join(home, "auth.json"), "utf8"))?.tokens?.access_token;
    const claims = JSON.parse(Buffer.from(String(token).split(".")[1] ?? "", "base64url").toString("utf8"));
    return typeof claims?.exp === "number" ? claims.exp * 1000 : 0;
  } catch {
    return 0;
  }
}

export class CodexDriver implements AgentDriver {
  private readonly data: string;
  private readonly command: string;
  private readonly env: Env;
  private readonly hostSkills: string;
  private readonly caBundle: string;
  readonly options: CodexDriverOptions;
  private hosts = new Map<string, Host>();
  private hostQueue: Promise<unknown> = Promise.resolve();
  /// What `codex` on the PATH was when last read, and when.
  private installed: { version: string | null; at: number } | null = null;
  private installedReading: Promise<string | null> | null = null;

  constructor(options: CodexDriverOptions) {
    this.options = options;
    this.data = options.data;
    this.command = options.command ?? "codex";
    this.env = options.env ?? process.env;
    this.hostSkills = options.hostSkills ?? join(this.env.HOME ?? "", ".agents", "skills");
    this.caBundle = options.caBundle ?? CA_BUNDLE;
  }

  runtime(): "codex" {
    return "codex";
  }

  /// Has the app-server running on a profile renew its login now (its login is not renewed from outside meanwhile: it
  /// holds the refresh token); false: none runs on it.
  async renewLogin(profileId: string): Promise<boolean> {
    const host = [...this.hosts.values()].find((h) => h.profile === profileId && h.alive());
    if (!host) return false;
    await host.request("account/read", { refreshToken: true });
    return true;
  }

  /// Which app-server a session's threads go to: its profile's, shared by the profile's sessions; while the station runs
  /// things in sandboxes (agents/sandbox.ts), the session's own, so that each session has a sandbox of its own.
  private hostKey(profileId: string, session?: string): string {
    return session !== undefined && sandboxed(this.data) ? session : profileId;
  }

  /// The version of Codex installed now, read again when the last reading is old or `fresh` asks.
  private async installedVersion(fresh = false): Promise<string | null> {
    if (!fresh && this.installed !== null && wall.now() - this.installed.at < INSTALLED_MS) return this.installed.version;
    if (this.installedReading) return this.installedReading;
    const read = this.options.installedVersion ?? (async () => {
      const [ok, said] = await run(this.command, ["--version"], cleanEnv(SCRUBBED), 20_000).catch(() => [false, ""] as const);
      return ok ? versionIn(said) : null;
    });
    this.installedReading = read()
      .catch(() => null)
      .then((version) => {
        this.installed = { version, at: wall.now() };
        return version;
      })
      .finally(() => {
        this.installedReading = null;
      });
    return this.installedReading;
  }

  /// An app-server running a Codex other than the one installed now: updated under it.
  private stale(host: Host): boolean {
    const installed = this.installed?.version ?? null;
    return host.version !== null && installed !== null && host.version !== installed;
  }

  /// An app-server whose output has grown past the limit (OUTPUT_LIMIT).
  private outgrown(host: Host): number | null {
    try {
      const size = statSync(outFile(this.data, host.proc.info.id)).size;
      return size > (this.options.outputLimit ?? OUTPUT_LIMIT) ? size : null;
    } catch {
      return null;
    }
  }

  /// Replaces a profile's app-server Codex was updated under, or whose output has grown too long, once no turn runs on
  /// it: its sessions are opened again on a new one with their next turn.
  private async retireStale(key: string, installed: string | null) {
    const host = this.hosts.get(key);
    if (!host || !host.alive() || host.turns.size > 0) return;
    if (this.stale(host)) {
      log.info("agents::codex", "codex was updated under its app-server; restarting it", { profile: host.profile, key, running: host.version, installed });
    } else {
      const output = this.outgrown(host);
      if (output === null) return;
      log.info("agents::codex", "its app-server's output has grown long; restarting it", { profile: host.profile, key, bytes: output });
    }
    this.hosts.delete(key);
    await host.proc.kill(5000);
  }

  /// Codex installed or updated (from the station's pages): app-servers of the old one are replaced once idle.
  async runtimeChanged() {
    const installed = await this.installedVersion(true);
    await this.serial(async () => {
      for (const id of [...this.hosts.keys()]) await this.retireStale(id, installed);
    });
  }

  /// A turn ended on a host: if Codex was updated under it or its output has grown too long, it is replaced now that it
  /// may be idle.
  hostIdle(host: Host) {
    if (host.turns.size > 0 || this.hosts.get(host.key) !== host) return;
    void (async () => {
      const installed = await this.installedVersion();
      if (!this.stale(host) && this.outgrown(host) === null) return;
      await this.serial(() => this.retireStale(host.key, installed));
    })().catch((error) => log.warn("agents::codex", "a codex app-server not replaced", { profile: host.profile, error: String(error) }));
  }

  /// Ends an app-server of one session's whose last thread was let go.
  retire(host: Host): Promise<void> {
    return this.serial(async () => {
      if (this.hosts.get(host.key) === host) this.hosts.delete(host.key);
      await host.proc.kill(5000);
    });
  }

  /// One at a time, as Rust's hosts mutex: starting, replacing and taking up hosts.
  private serial<T>(work: () => Promise<T>): Promise<T> {
    const next = this.hostQueue.then(work, work);
    this.hostQueue = next.catch(() => {});
    return next;
  }

  private async host(profile: Profile, session?: string, cwd?: string): Promise<Host> {
    const installed = await this.installedVersion();
    const key = this.hostKey(profile.id, session);
    const host = await this.serial(async () => {
      await this.retireStale(key, installed);
      const current = this.hosts.get(key);
      if (current && current.alive()) await this.renewLent(current, profile);
      if (current && current.alive() && current.signature !== hostSignature(profile)) {
        // The profile (or the station's variables for its agents) changed. Replace the process once no turn runs on it,
        // as when Codex was updated under it: its other threads are closed, to be opened again on the new one with their
        // next turn. Waiting for no thread at all would wait for ever: a session opened meanwhile joins the old one.
        if (current.turns.size === 0) {
          log.info("agents::codex", "profile changed; restarting its codex app-server", { profile: profile.id });
          this.hosts.delete(key);
          await current.proc.kill(5000);
        } else {
          log.info("agents::codex", "profile changed; its codex app-server restarts once no turn runs on it", { profile: profile.id });
        }
      }
      const alive = this.hosts.get(key);
      if (alive && alive.alive()) return alive;
      // Its app-server exited: its runner, on its way out, is not one to take up.
      if (alive) await alive.proc.released();
      // One an earlier station left running (its threads may be taken up yet) is taken up rather than replaced.
      const left = findRunner(this.data, runnerId("codex", key));
      const host = left ? await this.takeUp(profile, left, key) : await Host.start(profile, key, this.command, this.data, this.env, this.caBundle, this.options.lent, key === profile.id ? profile.home : cwd);
      // Taken up on a borrowed login: when that one runs out, as its auth.json says.
      if (left && this.options.lent?.borrowed(profile)) host.lentUntil = lentExpiry(profile.home);
      this.hosts.set(key, host);
      return host;
    });
    await host.ensureReady();
    return host;
  }

  /// An app-server a runner keeps, with no snapshot: what the previous station had handled of it is read again to know
  /// where each thread stands.
  private async takeUp(profile: Profile, info: RunnerInfo, key = profile.id): Promise<Host> {
    const out = outFile(this.data, info.id);
    const at = await ackedOffset(info, out);
    const recovered = new Map<string, Recovered>();
    for (const line of linesBefore(out, at)) {
      if (UNTOLD.some((m) => line.startsWith(m))) continue;
      let msg: Json;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      const thread = msg?.params?.threadId;
      if (typeof msg?.method !== "string" || typeof thread !== "string") continue;
      const r = recovered.get(thread) ?? { busy: false, turnId: null, live: new LiveFromCodex() };
      recovered.set(thread, r);
      r.live.feed(msg.method, msg.params);
      if (msg.method === "turn/started") {
        r.busy = true;
        if (typeof msg.params.turn?.id === "string") r.turnId = msg.params.turn.id;
      } else if (msg.method === "turn/completed") {
        r.busy = false;
        r.turnId = null;
      }
    }
    // Its signature is the profile's if it runs with what the profile says now (the arguments carry the overrides).
    const same = JSON.stringify(info.args) === JSON.stringify(hostArgs(profile));
    // Ids above any the previous station can have sent.
    const host = Host.adopt(profile.id, info, same ? hostSignature(profile) : "unknown", wall.now(), true, recovered, key);
    host.version = versionInOutput(out);
    for (const [thread, r] of recovered) if (r.busy) host.turns.add(thread);
    return host;
  }

  /// The account's rate-limit windows, as the profile's app-server reports them (ChatGPT subscriptions).
  async rateLimits(profile: Profile): Promise<Json> {
    return (await this.host(profile)).request("account/rateLimits/read", {});
  }

  async resetQuota(profile: Profile, key: string): Promise<Json> {
    return (await this.host(profile)).request("account/rateLimitResetCredit/consume", { idempotencyKey: key });
  }

  /// The models the account can run in Codex, as its app-server lists them (the ones it does not hide).
  async models(profile: Profile): Promise<ModelCatalog> {
    const host = await this.host(profile);
    const catalog = new ModelCatalog();
    let cursor: string | null = null;
    const seen = new Set<string>();
    for (;;) {
      const answer = await host.request("model/list", { cursor });
      catalog.extend(answer);
      cursor = typeof answer?.nextCursor === "string" && answer.nextCursor !== "" ? answer.nextCursor : null;
      if (cursor === null) break;
      if (seen.has(cursor)) throw new Error("model/list repeated its cursor");
      seen.add(cursor);
    }
    catalog.models = [...new Set(catalog.models.sort())];
    return catalog;
  }

  async open(options: OpenOptions, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const host = await this.host(options.profile, options.key, options.cwd);
    const model = options.model ?? profileModel(options.profile);
    const skillsOff = hostSkillsOff(this.hostSkills);
    const config: Json = {
      "mcp_servers.stillfail.url": options.mcpUrl,
      "mcp_servers.stillfail.http_headers": { Authorization: `Bearer ${options.mcpToken}` },
    };
    if (options.effort !== undefined) config.model_reasoning_effort = options.effort;
    if (skillsOff.length > 0) config["skills.config"] = skillsOff;
    const common: Json = { cwd: options.cwd, approvalPolicy: "never", sandbox: "danger-full-access", developerInstructions: options.instructions, config };
    if (model !== undefined) common.model = model;
    // None for a thread continued from a terminal: it keeps its own, so its cache holds.
    if (options.instructions === "") delete common.developerInstructions;
    let opened: Json;
    if (options.resume !== undefined) {
      common.threadId = options.resume;
      opened = await host.request("thread/resume", common);
      // A thread still loaded is rejoined as it is, with the MCP connection it had: one that failed (the station's
      // door was closed then) stays failed, and its turns have no station tools. Unloaded, it is loaded again with them.
      if (await stationToolsFailed(host, options.resume)) {
        log.warn("agents::codex", "a thread's station tools had failed; loading it again", { thread: options.resume });
        await host.request("thread/unsubscribe", { threadId: options.resume });
        opened = await host.request("thread/resume", common);
      }
    } else {
      opened = await host.request("thread/start", common);
    }
    const threadId = opened?.thread?.id;
    if (typeof threadId !== "string") throw new Error("codex gave no thread id");
    const session = new CodexSession(this, threadId, host, options.profile, { busy: false, turnId: null, closed: false }, new LiveFromCodex(), events);
    session.running = { model, effort: options.effort };
    session.toolsUrl = options.mcpUrl;
    host.addThread(threadId, session.sink());
    return session;
  }

  async adopt(options: OpenOptions, snapshot: unknown | null, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const handed = snapshot as CodexSnapshot | null;
    const profileId = handed?.profile ?? options.profile.id;
    // The app-server it ran on: its runner as the previous station said, else the one it would run on now.
    const key = handed?.host.key ?? this.hostKey(profileId, options.key);
    const host = await this.serial(async () => {
      const current = this.hosts.get(key);
      if (current && current.alive()) return current;
      if (current) await current.proc.released();
      const id = handed?.host.runner ?? runnerId("codex", key);
      const info = findRunner(this.data, id);
      if (!info) throw new Error(`codex app-server ${key} was not taken up: no runner keeps it`);
      const host = handed
        ? Host.adopt(profileId, info, handed.host.signature, handed.host.nextId, handed.host.ready, undefined, key)
        : await this.takeUp(options.profile, info, key);
      if (handed) host.version = versionInOutput(outFile(this.data, info.id));
      this.hosts.set(key, host);
      return host;
    });
    let session: CodexSession;
    if (handed) {
      session = new CodexSession(this, handed.threadId, host, options.profile, { busy: handed.busy, turnId: handed.turnId, closed: false }, new LiveFromCodex(handed.live), events);
      session.tuned = handed.tuned ?? null;
      session.running = session.tuned;
      session.toolsUrl = handed.mcpUrl ?? null;
    } else {
      const threadId = options.resume;
      if (threadId === undefined) throw new Error("a codex thread is taken up by its id (resume)");
      const r = host.recovered.get(threadId);
      host.recovered.delete(threadId);
      session = new CodexSession(this, threadId, host, options.profile, { busy: r?.busy ?? false, turnId: r?.turnId ?? null, closed: false }, r?.live ?? new LiveFromCodex(), events);
      // A turn is running that this station did not start.
      if (r?.busy) events({ type: "turnStarted" });
    }
    host.addThread(session.id(), session.sink());
    if (session.busy()) host.turns.add(session.id());
    // Left running by a station from before Codex was updated: replaced once the sessions on it are taken up and idle.
    wall.after(ORPHANS_MS, () => this.hostIdle(host));
    return session;
  }

  /// Whether a host runs a Codex other than the one installed.
  /// A borrowed login about to run out: a new one lent in its place (LENT_RENEW_MS), the app-server left running. As a
  /// session opens and before each turn.
  async renewLent(host: Host, profile: Profile) {
    const lent = this.options.lent;
    if (host.lentUntil === null || host.lentUntil - wall.now() >= LENT_RENEW_MS || !lent?.borrowed(profile)) return;
    try {
      host.lentUntil = await lent.write(profile);
      // In a sandbox, its app-server reads the login there: the new one goes there too.
      if (sandboxed(this.data)) {
        await syncNow(this.data, keyOfRunner(host.proc.info.id), [{ path: lentFile(this.data, profile.home), to: join(profile.home, "auth.json"), mode: "whole", back: false }]);
      }
      log.info("agents::codex", "its borrowed login runs out; a new one is lent under its app-server", { profile: profile.id });
    } catch (error) {
      // It goes on with the one it has: asked again at its next turn.
      log.warn("agents::codex", "its borrowed login runs out and no new one was lent", { profile: profile.id, error: (error as Error).message });
    }
  }

  /// Whether a host is not to start another turn: Codex was updated under it, or it runs with what the profile (or the
  /// station's variables for its agents) said before.
  async outdated(host: Host, profile: Profile | undefined): Promise<boolean> {
    if (profile !== undefined && host.signature !== hostSignature(profile)) return true;
    if (host.version === null) return false;
    await this.installedVersion();
    return this.stale(host);
  }

  async shutdown() {
    const hosts = [...this.hosts.values()];
    this.hosts.clear();
    await Promise.all(hosts.map((h) => h.proc.kill(5000)));
  }

  detach() {
    for (const host of this.hosts.values()) host.detach();
    this.hosts.clear();
  }
}

/// Whether thread `threadId`'s connection to the station's MCP endpoint failed, as its app-server says (once its startup
/// ended). An app-server that cannot say: not known to have failed.
async function stationToolsFailed(host: Host, threadId: string): Promise<boolean> {
  try {
    const answer = await host.request("mcpServerStatus/list", { threadId, serverName: "stillfail", detail: "toolsAndAuthOnly" });
    return Array.isArray(answer?.data) && answer.data.some((s: Json) => s?.name === "stillfail" && s?.runtimeStatus === "failed");
  } catch {
    return false;
  }
}

type ThreadState = { busy: boolean; turnId: string | null; closed: boolean };

const input = (text: string) => [{ type: "text", text }];

/// What a thread's notification says of the station's tools being out of reach (null: nothing): a call to one of them
/// that failed as unreachable.
export function codexToolsLost(method: string, params: Json): string | null {
  const item = params?.item;
  if (method !== "item/completed" || item?.type !== "mcpToolCall" || !TOOL_SERVERS.includes(item.server) || item.status !== "failed") return null;
  const error = typeof item.error?.message === "string" ? item.error.message : "";
  return unreachable(error) ? chars(error, 300) : null;
}

export class CodexSession implements AgentSession {
  private driver: CodexDriver;
  private threadId: string;
  private host: Host;
  private profile: Profile;
  private state: ThreadState;
  private live: LiveFromCodex;
  private events: (event: RuntimeEvent) => void;
  /// Another model and effort its turns start with from now on (turn/start keeps them for the thread's later turns).
  tuned: { model: string; effort: string } | null = null;
  /// What its turns run with: as opened, or retuned to; null when not known (taken up from another station).
  running: { model: string | undefined; effort: string | undefined } | null = null;
  /// The address of the station's tools its thread was given; null when not known (taken up after a crash).
  toolsUrl: string | null = null;

  constructor(driver: CodexDriver, threadId: string, host: Host, profile: Profile, state: ThreadState, live: LiveFromCodex, events: (event: RuntimeEvent) => void) {
    this.driver = driver;
    this.threadId = threadId;
    this.host = host;
    this.profile = profile;
    this.state = state;
    this.live = live;
    this.events = events;
  }

  private endTurn(outcome: TurnOutcome) {
    this.state.busy = false;
    this.state.turnId = null;
    this.host.turns.delete(this.threadId);
    this.events({ type: "turnEnded", outcome });
    this.driver.hostIdle(this.host);
  }

  /// A thread's share of its app-server's notifications: its turns and live steps, as events.
  sink(): Sink {
    return (notice) => {
      if (notice.kind === "hostExited") {
        this.state.closed = true;
        if (this.state.busy) this.endTurn({ kind: "failed", reason: "exited", message: notice.reason });
        this.events({ type: "closed", why: notice.reason });
        return;
      }
      const { method, params } = notice;
      for (const event of this.live.feed(method, params)) this.events({ type: "live", event });
      const lost = codexToolsLost(method, params);
      if (lost !== null) this.events({ type: "toolsLost", why: lost });
      if (method === "turn/started") {
        const id = params?.turn?.id;
        if (typeof id === "string") this.state.turnId = id;
        const was = this.state.busy;
        this.state.busy = true;
        this.host.turns.add(this.threadId);
        if (!was) this.events({ type: "turnStarted" });
      } else if (method === "turn/completed") {
        const turn = params?.turn ?? null;
        const status = turn?.status;
        let outcome: TurnOutcome;
        if (status === "interrupted") outcome = { kind: "aborted" };
        else if (status === "failed") {
          const error = turn?.error ?? null;
          outcome = {
            kind: "failed",
            reason: classifyCodexError(error?.codexErrorInfo ?? null),
            message: chars(typeof error?.message === "string" ? error.message : "turn failed", 1000),
          };
        } else outcome = { kind: "completed" };
        this.endTurn(outcome);
      } else if (method === "error" && params?.willRetry !== true) {
        log.warn("agents::codex", "codex turn error", { thread: this.threadId, error: JSON.stringify(params?.error ?? null) });
      }
    };
  }

  id() {
    return this.threadId;
  }

  mcpUrl() {
    return this.toolsUrl;
  }

  busy() {
    return this.state.busy;
  }

  async prompt(text: string) {
    const fast = this.driver.options.fast?.(this.threadId);
    const p = this.driver.options.currentProfile ? this.driver.options.currentProfile(this.host.profile) : this.profile;
    // Codex was updated under its app-server, whose tools would all fail, or it runs with what its profile said before:
    // opened again on a new one, unless another turn runs on it yet.
    const outdated = this.host.turns.size === 0 && (await this.driver.outdated(this.host, p));
    await this.driver.renewLent(this.host, this.profile);
    if (this.state.closed) throw new Error("codex session is closed");
    if (this.state.busy) throw new Error("a turn is already running");
    if (outdated) throw new Error("codex was updated, or its profile changed, under its app-server");
    this.state.busy = true;
    this.host.turns.add(this.threadId);
    const params: Json = { threadId: this.threadId, input: input(text) };
    if (this.tuned) Object.assign(params, this.tuned);
    if (p && accessKind(p) === "subscription") {
      // An explicit null clears a previously selected tier; omitting it would keep Fast on.
      params.serviceTier = (fast ?? profileFast(p)) ? "fast" : null;
    }
    try {
      const started = await this.host.request("turn/start", params);
      const id = started?.turn?.id;
      if (typeof id === "string") this.state.turnId = id;
    } catch (error) {
      this.state.busy = false;
      this.host.turns.delete(this.threadId);
      throw error;
    }
  }

  /// thread/compact/start: the app-server runs it as a turn of its own (turn/started, a contextCompaction item,
  /// turn/completed; 0.160).
  async compact() {
    await this.driver.renewLent(this.host, this.profile);
    if (this.state.closed) throw new Error("codex session is closed");
    if (this.state.busy) throw new Error("a turn is already running");
    this.state.busy = true;
    this.host.turns.add(this.threadId);
    try {
      await this.host.request("thread/compact/start", { threadId: this.threadId });
    } catch (error) {
      this.state.busy = false;
      this.host.turns.delete(this.threadId);
      throw error;
    }
  }

  async steer(text: string) {
    if (this.state.closed || !this.state.busy || this.state.turnId === null) return false;
    try {
      await this.host.request("turn/steer", { threadId: this.threadId, input: input(text), expectedTurnId: this.state.turnId });
      return true;
    } catch (error) {
      debug("agents::codex", "codex steer refused", { thread: this.threadId, error: String(error) });
      return false;
    }
  }

  /// Given with the next turn/start. Back to a default (no model or effort named) only takes a new start: an override left
  /// out keeps the thread's.
  retune(options: OpenOptions) {
    const model = options.model ?? profileModel(options.profile);
    const effort = options.effort;
    if (this.state.closed || this.state.busy) return false;
    if (this.running !== null && this.running.model === model && this.running.effort === effort) return true;
    if (model === undefined || effort === undefined) return false;
    this.tuned = { model, effort };
    this.running = this.tuned;
    return true;
  }

  /// Codex cannot move what a turn waits on to the background.
  async backgroundTools() {}

  async abort() {
    if (this.state.closed || !this.state.busy) return;
    if (this.state.turnId === null) throw new Error("codex has not reported its running turn id");
    try {
      await this.host.request("turn/interrupt", { threadId: this.threadId, turnId: this.state.turnId });
    } catch (error) {
      log.warn("agents::codex", "codex interrupt failed", { thread: this.threadId, error: String(error) });
      throw error;
    }
  }

  async dispose() {
    if (this.state.closed) return;
    this.state.closed = true;
    this.host.threads.delete(this.threadId);
    this.host.turns.delete(this.threadId);
    // Handed over, the thread is the next station's.
    if (this.host.proc.handed()) return;
    // A session's own app-server (in its sandbox) goes with its last thread: left, it would keep the sandbox.
    if (this.host.key !== this.host.profile && this.host.threads.size === 0) return this.driver.retire(this.host);
    // Best effort: the thread just stays loaded.
    await this.host.request("thread/unsubscribe", { threadId: this.threadId }).catch(() => {});
  }

  /// Stops hearing its app-server (all of its threads: lines are the app-server's): the thread stands as it last said.
  snapshot(): CodexSnapshot {
    this.host.freeze();
    this.state.closed = true;
    return {
      runtime: "codex",
      threadId: this.threadId,
      profile: this.host.profile,
      busy: this.state.busy,
      turnId: this.state.turnId,
      live: this.live.state(),
      host: this.host.snapshot(),
      tuned: this.tuned,
      mcpUrl: this.toolsUrl,
    };
  }

  detach() {
    this.state.closed = true;
    this.host.freeze();
    this.host.threads.delete(this.threadId);
    if (this.host.threads.size === 0) this.host.detach();
  }
}
