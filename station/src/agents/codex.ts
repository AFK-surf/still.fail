// Codex driver: one shared `codex app-server` per profile, under a runner whose id comes
// from the profile, one thread per session.
//
// Pinned by spikes:
// - a thread adds <1MB to its app-server, so sessions share one process;
// - per-session settings (the MCP endpoint and token) travel in the thread/start|resume `config`, not the process
//   environment;
// - threads need sandbox "danger-full-access" with approvalPolicy "never", or MCP tool calls are refused.
import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, statSync } from "node:fs";
import { open } from "node:fs/promises";
import { join } from "node:path";
import { agentEnv } from "../ops/agent-env.ts";
import { log } from "../ops/log.ts";
import { rememberCodexRollout } from "../read/transcript.ts";
import { LiveFromCodex, chars, type CodexLiveState } from "./live.ts";
import { linkCodexAuth, type Env } from "./machine-logins.ts";
import { keyOfRunner, lentFile, sandboxed, syncNow } from "./sandbox.ts";
import { AgentProcess, ackedOffset, bytesWithin, debug, findRunner, outFile, runnerId } from "./process.ts";
import { accessKind, codexOverrides, expandRoute, isMachine, profileEnv, profileFast, profileModel, profileVia } from "./profiles.ts";
import { TOOL_SERVERS, cleanEnv, failureOf, unreachable, type AgentDriver, type AgentSession, type FailureReason, type OpenOptions, type Profile, type RuntimeEvent, type TurnOutcome } from "./runtime.ts";
import { liveRunners, listening, type RunnerInfo } from "./runner.ts";
import { REPO_RULES_COMMAND } from "./repo-rules.ts";
import { wall } from "../ops/fibers.ts";
import { Said, stationLang, tr } from "../ops/i18n.ts";
import { findCommand, run } from "../updates/runtimes.ts";
import { withShellCommand } from "../ops/shell-path.ts";
import { versionIn } from "../updates/versions.ts";
import { findMissingCodexHost } from "../updates/codex-repair.ts";

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

/// Why a Codex turn failed, from its error's `codexErrorInfo` (a code, or a code with the HTTP status it came with) and
/// message: the code first, then the status, then what the message says (`failureOf`).
export function classifyCodexError(info: unknown, message = ""): FailureReason {
  const code = typeof info === "string" ? info : info && typeof info === "object" && !Array.isArray(info) ? Object.keys(info)[0] : undefined;
  if (code === "unauthorized") return "auth";
  if (code === "usageLimitExceeded" || code === "rateLimitExceeded") return "rate_limit";
  if (code === "serverOverloaded") return "overloaded";
  if (code === "contextWindowExceeded") return "context";
  const held = code !== undefined && info && typeof info === "object" ? (info as Record<string, unknown>)[code] : undefined;
  const status = held && typeof held === "object" ? (held as { httpStatusCode?: unknown }).httpStatusCode : undefined;
  if (typeof status === "number" && [401, 403, 429, 529].includes(status)) return failureOf(`${status} ${message}`);
  // Some versions report the HTTP refusal in the message without an unauthorized codexErrorInfo.
  if (/\b(?:401|unauthorized|token_revoked)\b|invalidated oauth token/i.test(message)) return "auth";
  // The request not made, or its answer cut off, with no status that says more: the way to the provider.
  if (["httpConnectionFailed", "responseStreamConnectionFailed", "responseStreamDisconnected"].includes(code ?? "") && (typeof status !== "number" || status >= 500)) return "network";
  return failureOf(message);
}

/// Keeps capabilities alongside model ids; an old runtime may omit them.
export class ModelCatalog {
  models: string[] = [];
  efforts = new Map<string, string[]>();
  /// Each model's own reasoning level, where it says one (model/list's defaultReasoningEffort).
  defaults = new Map<string, string>();

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
      if (typeof m.defaultReasoningEffort === "string" && m.defaultReasoningEffort !== "") this.defaults.set(id, m.defaultReasoningEffort);
    }
  }
}

/// A thread's share of its app-server's notifications.
type Notice = { kind: "method"; method: string; params: Json } | { kind: "hostExited"; reason: string };
type Sink = (notice: Notice) => void;

/// What a crashed station had seen of a thread (read again from the app-server's output).
type Recovered = { busy: boolean; turnId: string | null; live: LiveFromCodex };
/// What the station before ran on a host handed over, in its `turnFrom` while its sessions are taken up.
const BEFORE = "\0before";

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

/// The version an app-server a runner keeps runs: its answer to `initialize`, the first line it wrote. Read off the
/// station's thread; the host says none until it is.
async function versionInOutput(file: string): Promise<string | null> {
  let fd;
  try {
    fd = await open(file, "r");
  } catch {
    return null;
  }
  try {
    const buf = Buffer.alloc(4096);
    const { bytesRead: n } = await fd.read(buf, 0, buf.length, 0);
    const first = buf.subarray(0, n).toString("utf8").split("\n")[0] ?? "";
    return userAgentVersion(JSON.parse(first)?.result?.userAgent);
  } catch {
    return null;
  } finally {
    await fd.close().catch(() => undefined);
  }
}

/// `host`'s version as its output says it, once read (`versionInOutput`).
const readVersion = (host: Host, file: string) => void versionInOutput(file).then((version) => { if (host.version === null) host.version = version; });

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
  /// A sign-in replaced the credentials this process loaded. Existing turns may finish on it.
  loginStale = false;
  /// Its installation was replaced here, even if the replacement has the same version.
  runtimeStale = false;
  /// Being replaced with turns running on it (`drain`): no new one goes to it, and it ends after its last.
  draining = false;
  private idleWaiters = new Set<() => void>();

  whenIdle(): Promise<void> {
    if (this.turns.size === 0 || !this.alive()) return Promise.resolve();
    return new Promise((resolve) => this.idleWaiters.add(resolve));
  }

  signalIdle() {
    if (this.turns.size > 0 && this.alive()) return;
    for (const resolve of this.idleWaiters) resolve();
    this.idleWaiters.clear();
  }
  /// The Codex it runs (null: not known). Updated on the disk, the files it starts its helpers from are gone, and every
  /// tool call of its threads fails: it is replaced once no turn runs on it.
  version: string | null = null;
  private ready: boolean;
  private readying: Promise<void> | null = null;
  /// Notices for threads not taken up yet, while sessions are being taken up (null otherwise).
  private orphans: Map<string, Notice[]> | null = null;
  /// After a crash: where each thread stood when the station that crashed stopped acknowledging.
  recovered = new Map<string, Recovered>();
  /// Where in its output each turn running began, and where what a station reads after a crash begins: the earliest of
  /// them, else just past the line that ended the last one. Told to its runner with the ack of the line it changed on
  /// (`keepFrom`), which keeps it with that ack: never ahead of what was acknowledged, whatever of the acks is lost.
  private turnFrom = new Map<string, number>();
  private keptFrom = -1;
  /// Where the station before kept, handed over (Host.adopt `from`).
  handedFrom = 0;
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
    return { label, line: (line: string, from: number, to: number) => this.onLine(line, from, to), exit: (said: string, stderr: string) => this.onExit(said, stderr) };
  }

  /// When the login it was started with runs out, if it was lent by another station.
  lentUntil: number | null = null;

  /// `cwd`: where it runs, its profile's home; a session's own app-server in the session's workspace (in its sandbox,
  /// made there with it).
  /// `id`: its runner's (`runnerId`, or another while one of the same key is being replaced: `runnerFor`).
  static async start(profile: Profile, key: string, command: string, data: string, env: Env, caBundle: string, lent?: CodexDriverOptions["lent"], cwd = profile.home, id = runnerId("codex", key)): Promise<Host> {
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
    host.proc = await AgentProcess.start(data, id, command, hostArgs(profile), childEnv, cwd, { ...host.processOptions(label), local: key === profile.id });
    return host;
  }

  /// Takes up an app-server a runner keeps. Replies to what the previous station asked are dropped: its ids are below
  /// `nextId`.
  /// `from`: where the station before kept that a crash reads from (handed over): kept there until its sessions are
  /// taken up, those with a turn running then held there (`running`).
  static adopt(profile: string, info: RunnerInfo, signature: string, nextId: number, ready: boolean, recovered?: Map<string, Recovered>, key = profile, from?: number): Host {
    log.info("agents::codex", "taking up a codex app-server", { profile, key, pgid: info.pgid, crashed: recovered !== undefined });
    const host = new Host(profile, signature, nextId, ready, key);
    if (recovered) host.recovered = recovered;
    if (from !== undefined) {
      host.handedFrom = from;
      host.turnFrom.set(BEFORE, from);
    }
    host.orphans = new Map();
    wall.after(ORPHANS_MS, () => {
      if (host.turnFrom.delete(BEFORE)) host.reckon(from!);
      const dropped = [...(host.orphans?.values() ?? [])].reduce((n, l) => n + l.length, 0);
      if (dropped > 0) log.warn("agents::codex", "notifications for threads nobody took up, dropped", { profile, threads: host.orphans?.size, dropped });
      host.orphans = null;
    });
    host.proc = AgentProcess.adopt(info, host.processOptions(`codex app-server ${profile}`));
    if (from !== undefined) host.reckon(from);
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

  /// A turn running on it that began at or after `from` in its output (one the station before ran, or one read again).
  running(thread: string, from: number) {
    if (!this.turnFrom.has(thread)) this.turnFrom.set(thread, from);
  }

  private noteTurn(thread: string, started: boolean, from: number, to: number) {
    if (started) this.running(thread, from);
    else this.turnFrom.delete(thread);
    this.reckon(to);
  }

  reckon(to: number) {
    const at = this.turnFrom.size > 0 ? Math.min(...this.turnFrom.values()) : to;
    if (at === this.keptFrom) return;
    this.keptFrom = at;
    this.proc.keepFrom(at);
  }

  private onLine(line: string, from = 0, to = 0) {
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
      if (method === "turn/started" || method === "turn/completed") this.noteTurn(thread, method === "turn/started", from, to);
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
    this.signalIdle();
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
    return { runner: this.proc.info.id, signature: this.signature, nextId: this.nextId, ready: this.ready, ...(this.keptFrom >= 0 ? { keep: this.keptFrom } : {}), ...(this.draining ? { draining: true } : {}), ...(this.key !== this.profile ? { key: this.key } : {}), ...(this.loginStale ? { loginStale: true } : {}), ...(this.runtimeStale ? { runtimeStale: true } : {}) };
  }
}

/// `key`: the driver's key for it when not its profile's (`hostKey`); none from a station before it.
/// `keep`: where what is read again after a crash begins (Host `turnFrom`); none from a station before it.
/// `draining`: being replaced, its turns ending on it (`drain`).
export type CodexHostSnapshot = { runner: string; signature: string; nextId: number; ready: boolean; key?: string; loginStale?: boolean; runtimeStale?: boolean; keep?: number; draining?: boolean };

/// A thread as a next station takes it up, with what its app-server needs (HandedHost).
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
  /// Where this thread writes its rollout (optional for snapshots from an older station).
  transcriptPath?: string | null;
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
  /// A missing code-mode host (tests can supply a probe); told so the station refreshes its software status.
  missingHost?: typeof findMissingCodexHost;
  incompleteInstallation?: () => void;
  /// Bytes of output an app-server may have before it is replaced (OUTPUT_LIMIT).
  outputLimit?: number;
  /// Settled once what the station before this one left is taken up (sessions/agents.ts `start`). Until then an
  /// app-server a runner keeps is that station's, to be taken up with its snapshot by the session that ran on it. Asked
  /// for before (a profile's quota or the model catalog, as the station starts), one was taken up as after a crash, all
  /// it ever wrote read again on the main thread (131 MB on a station, 2026-11-02: held 4.8 s as devices came back after an
  /// update), and taken from the station still handing over, which let go of the turns running on it.
  takenUp?: Promise<unknown>;
  /// Another stretch of an app-server's output read again: the launcher hears the station gets on with it.
  taking?: () => void;
  /// Bytes of an app-server's output read again between two of them (TAKE_UP_BYTES).
  takeUpBytes?: number;
};

/// An app-server's runner keeps all it wrote (every diff and command output of every thread on it, hundreds of MB in a
/// week) as long as it runs, and a station taking it up after a crash reads all of it again: past this, it is replaced
/// once no turn runs on it, as one Codex was updated under is, and its runner's file goes with it.
const OUTPUT_LIMIT = 64 * 1024 * 1024;

/// Lines of an app-server's output read again at a time before the main thread is let go (`takeUp`): three hosts of
/// 172 to 291 MB held it up to 32 s at a time on a loaded station, and six starts in a row took up at most one session
/// in the launcher's 90 s (2026-11-06).
const TAKE_UP_LINES = 4096;
/// Or bytes of it, whichever comes first: its lines can be MBs each, and 4096 of them were tens of GB between two tells
/// to the launcher. An output of 77 GB, a line of it 160 MB: the launcher's 90 s ran out under every station getting on
/// with it, and the next began from the same place, killed some 20 times in 35 minutes (2026-11-13).
const TAKE_UP_BYTES = 16 * 1024 * 1024;

/// What an app-server writes most of and that says nothing of where a thread stands (LiveFromCodex keeps no state of
/// either): not decoded or parsed again when its output is read after a crash, told by how its line begins.
const UNTOLD = ['{"method":"turn/diff/updated"', '{"method":"item/commandExecution/outputDelta"'].map((m) => Buffer.from(m));
const untold = (line: Buffer) => UNTOLD.some((m) => line.length >= m.length && line.compare(m, 0, m.length, 0, m.length) === 0);

/// A borrowed login this close to its end is replaced in its home's auth.json, under the app-server running on it: Codex
/// reads that file again when it is refused (UnauthorizedRecovery's first step) and
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
  /// App-servers being replaced while turns run on them (`drain`): out of `hosts`, each ending after its last turn.
  private draining = new Set<Host>();
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

  async updateMatchesStation(profile: Profile): Promise<boolean> {
    if (this.command !== "codex") return false;
    const env = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(profile, "codex"), profile.id) };
    const [agentEnv, stationEnv] = await Promise.all([withShellCommand(this.command, env), withShellCommand(this.command, this.env)]);
    const agent = findCommand(this.command, agentEnv);
    const station = findCommand(this.command, stationEnv);
    return agent !== null && station !== null && agent.onPath === station.onPath && agent.real === station.real;
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
    return host.runtimeStale || (host.version !== null && installed !== null && host.version !== installed);
  }

  /// An app-server whose output has grown past the limit (OUTPUT_LIMIT).
  /// A runner from before it kept what the station keeps (`keeps`) is replaced the same way: it gives back the disk under
  /// a turn still running (read again after a crash, that turn is lost), or none at all.
  private outgrown(host: Host): number | null {
    try {
      const size = statSync(outFile(this.data, host.proc.info.id)).size;
      return size > (this.options.outputLimit ?? OUTPUT_LIMIT) || host.proc.info.keeps !== true ? size : null;
    } catch {
      return null;
    }
  }

  /// Replaces a profile's app-server Codex was updated under, or whose output has grown too long, once no turn runs on
  /// it: its sessions are opened again on a new one with their next turn.
  private async retireStale(key: string, installed: string | null) {
    const host = this.hosts.get(key);
    if (!host || !host.alive() || host.turns.size > 0) return;
    if (host.loginStale) {
      log.info("agents::codex", "login changed; restarting its codex app-server", { profile: host.profile, key });
    } else if (this.stale(host)) {
      log.info("agents::codex", "codex was updated under its app-server; restarting it", { profile: host.profile, key, running: host.version, installed });
    } else {
      const output = this.outgrown(host);
      if (output === null) return;
      log.info("agents::codex", "its app-server's output has grown long, or its runner is from before; restarting it", { profile: host.profile, key, bytes: output, keeps: host.proc.info.keeps === true });
    }
    // No turn begins on it from here (`prompt` looks again after its last await): one waiting there opens again elsewhere.
    host.draining = true;
    this.hosts.delete(key);
    await host.proc.kill(5000);
  }

  /// Codex installed or updated (from the station's pages): app-servers of the old one are replaced once idle.
  async runtimeChanged(replaced = false, drainBusy = false) {
    // Mark the old hosts before probing the new version, so a concurrent turn cannot join one during the probe.
    if (replaced) await this.serial(async () => { for (const host of this.hosts.values()) host.runtimeStale = true; });
    const installed = await this.installedVersion(true);
    const draining: Host[] = [];
    await this.serial(async () => {
      // Do not let new turns join a known older host while its existing turns are still finishing.
      if (installed !== null) for (const host of this.hosts.values()) if (host.version !== null && host.version !== installed) host.runtimeStale = true;
      for (const [id, host] of [...this.hosts]) {
        if (drainBusy && host.runtimeStale && host.turns.size > 0) {
          // As with an outgrown host, its running turns finish there; new ones can start on the updated executable.
          host.draining = true;
          this.hosts.delete(id);
          this.draining.add(host);
          draining.push(host);
        } else await this.retireStale(id, installed);
      }
    });
    for (const host of draining) void this.drain(host).catch((error) => log.warn("agents::codex", "a codex app-server being replaced not let go of", { profile: host.profile, error: String(error) }));
  }

  /// A new sign-in must be loaded by every app-server of this profile, without interrupting its turns.
  async loginChanged(profileId: string) {
    await this.serial(async () => {
      for (const [key, host] of this.hosts) {
        if (host.profile !== profileId) continue;
        host.loginStale = true;
        await this.retireStale(key, this.installed?.version ?? null);
      }
    });
  }

  /// A turn ended on a host: if Codex was updated under it or its output has grown too long, it is replaced now that it
  /// may be idle.
  hostIdle(host: Host) {
    host.signalIdle();
    if (host.draining) return void this.drain(host).catch((error) => log.warn("agents::codex", "a codex app-server being replaced not let go of", { profile: host.profile, error: String(error) }));
    if (this.hosts.get(host.key) !== host) return;
    // Outgrown with turns running all the while (a profile's app-server, which many chats share: on ccvm one went 19
    // hours without a moment idle, its output 4.9 GB, 2026-11-04): replaced now, the turns on it ending there.
    if (host.turns.size > 0) {
      if (this.outgrown(host) === null) return;
      void this.serial(async () => {
        if (this.hosts.get(host.key) !== host || host.turns.size === 0) return;
        log.info("agents::codex", "its app-server's output has grown long, or its runner is from before; new turns go to a new one, its own end there", { profile: host.profile, key: host.key, turns: host.turns.size, keeps: host.proc.info.keeps === true });
        host.draining = true;
        this.hosts.delete(host.key);
        this.draining.add(host);
      }).then(() => (host.draining ? this.drain(host) : undefined)).catch((error) => log.warn("agents::codex", "a codex app-server not replaced", { profile: host.profile, error: String(error) }));
      return;
    }
    void (async () => {
      const installed = await this.installedVersion();
      if (!host.loginStale && !this.stale(host) && this.outgrown(host) === null) return;
      await this.serial(() => this.retireStale(host.key, installed));
    })().catch((error) => log.warn("agents::codex", "a codex app-server not replaced", { profile: host.profile, error: String(error) }));
  }

  /// An app-server being replaced lets go of its threads with no turn running (closed: opened again on the new one with
  /// their next turn), and ends once none is left.
  private async drain(host: Host) {
    // Each closed at once (its session refuses a turn from then on: `prompt`), then unsubscribed: no turn starts on it
    // in between. Resumed elsewhere, it is let go of there first (`releasedElsewhere`), whatever became of this.
    const releases: Promise<unknown>[] = [];
    for (const [thread, sink] of [...host.threads]) {
      if (host.turns.has(thread)) continue;
      host.threads.delete(thread);
      sink({ kind: "hostExited", reason: "its app-server is being replaced" });
      releases.push(host.request("thread/unsubscribe", { threadId: thread }).catch(() => {}));
    }
    await Promise.all(releases);
    if (host.threads.size > 0 || host.turns.size > 0) return;
    // Held as this driver's until it and its runner are gone: one let go of first, while it ended, was taken up again
    // as left by a station before (`leftRunners`) by a host asked for meanwhile, and then killed under it.
    await this.serial(async () => {
      if (host.alive()) await host.proc.kill(5000);
      this.draining.delete(host);
    });
  }

  /// A thread about to be resumed on another app-server of its key: each one being replaced (this driver's, handed
  /// over so, or left by a station that crashed) lets go of it first, answering its unsubscribe; one that has exited
  /// holds nothing. Two holding it at once would both write its rollout (Codex locks it to one).
  private async releasedElsewhere(profile: Profile, key: string, threadId: string, on: Host) {
    // One left by the station before that no session handed over is on (`sweepLeft`, later) is one of them already: the
    // sessions are all taken up by now (`host` waits for that).
    await this.serial(async () => {
      for (const info of await this.leftRunners(key)) if (info.id !== on.proc.info.id) this.keepDraining(this.holdLeft(profile, info, key));
    });
    for (const host of [...this.draining]) {
      if (host === on || host.key !== key || !host.alive()) continue;
      try {
        await host.request("thread/unsubscribe", { threadId });
      } catch (error) {
        if (!host.alive()) continue;
        throw new Error(`the codex app-server being replaced did not let go of its thread: ${(error as Error).message}`);
      }
    }
  }

  /// One taken up as being replaced (handed over so, or left by a station that crashed beside a newer one): what of it
  /// no session took up a while after is let go of, and it ends once nothing runs on it.
  private keepDraining(host: Host) {
    host.draining = true;
    this.draining.add(host);
    wall.after(ORPHANS_MS, () => {
      for (const thread of [...host.turns]) if (!host.threads.has(thread)) host.turns.delete(thread);
      void this.drain(host).catch((error) => log.warn("agents::codex", "a codex app-server being replaced not let go of", { profile: host.profile, error: String(error) }));
    });
  }

  /// The runners of a host key an earlier station left, the oldest first: its own (`runnerId`) and those of app-servers
  /// started while one was being replaced (`<id>.<n>`); none this driver holds.
  private async leftRunners(key: string): Promise<RunnerInfo[]> {
    const base = runnerId("codex", key);
    const runners = await liveRunners(this.data, { strict: true });
    const held = new Set([...this.hosts.values(), ...this.draining].map((h) => h.proc.info.id));
    return runners
      .filter((r) => (r.id === base || r.id.startsWith(`${base}.`)) && !held.has(r.id) && listening(r))
      .sort((a, b) => a.startedAt - b.startedAt);
  }

  /// What an earlier station left of a host key taken up: the newest as its app-server, any older as being replaced.
  private async takeUpLeft(profile: Profile, key: string): Promise<Host | null> {
    const left = await this.leftRunners(key);
    const newest = left.pop();
    if (newest === undefined) return null;
    for (const older of left) this.keepDraining(await this.takeUp(profile, older, key));
    return this.takeUp(profile, newest, key);
  }

  /// Handed over: an app-server being replaced that no session handed over is on (its last threads being let go of as
  /// the station before stopped) is taken up as such once the sessions are, and ends.
  private sweepLeft(profile: Profile, key: string) {
    wall.after(ORPHANS_MS, () => {
      void this.serial(async () => {
        for (const info of await this.leftRunners(key)) this.keepDraining(this.holdLeft(profile, info, key));
      }).catch((error) => log.warn("agents::codex", "a codex app-server left being replaced not taken up", { key, error: String(error) }));
    });
  }

  /// One left being replaced with no session handed over on it (none of its turns runs on: those are handed over): held,
  /// its output not read again. Read, a runner from before `keep` is read from its start, on the station's thread; on
  /// ccvm one was 5 GB (2026-11-04).
  private holdLeft(profile: Profile, info: RunnerInfo, key: string): Host {
    const host = Host.adopt(profile.id, info, JSON.stringify(info.args) === JSON.stringify(hostArgs(profile)) ? hostSignature(profile) : "unknown", wall.now(), true, undefined, key);
    readVersion(host, outFile(this.data, info.id));
    return host;
  }

  /// The runner id a new app-server of a key starts under: its own, unless one being replaced still has it.
  private async runnerFor(key: string): Promise<string> {
    const base = runnerId("codex", key);
    return (await findRunner(this.data, base)) ? `${base}.${wall.now().toString(36)}` : base;
  }

  /// Ends an app-server of one session's whose last thread was let go.
  retire(host: Host): Promise<void> {
    return this.serial(async () => {
      if (this.hosts.get(host.key) === host) this.hosts.delete(host.key);
      host.draining = true;
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
    await this.options.takenUp;
    const installed = await this.installedVersion();
    const key = this.hostKey(profile.id, session);
    for (;;) {
      const result = await this.serial(async () => {
        await this.retireStale(key, installed);
        const current = this.hosts.get(key);
        // A new caller waits for old turns, rather than joining the process with the previous login.
        if (current && current.alive() && (current.loginStale || current.runtimeStale)) return { waiting: current };
        if (current && current.alive()) await this.renewLent(current, profile);
        if (current && current.alive() && current.signature !== hostSignature(profile)) {
          // The profile (or the station's variables for its agents) changed. Replace the process once no turn runs on it,
          // as when Codex was updated under it: its other threads are closed, to be opened again on the new one with their
          // next turn. Waiting for no thread at all would wait for ever: a session opened meanwhile joins the old one.
          if (current.turns.size === 0) {
            log.info("agents::codex", "profile changed; restarting its codex app-server", { profile: profile.id });
            current.draining = true;
            this.hosts.delete(key);
            await current.proc.kill(5000);
          } else {
            log.info("agents::codex", "profile changed; its codex app-server restarts once no turn runs on it", { profile: profile.id });
          }
        }
        const alive = this.hosts.get(key);
        if (alive && alive.alive()) return { host: alive };
        // Its app-server exited: its runner, on its way out, is not one to take up.
        if (alive) await alive.proc.released();
        // One an earlier station left running (its threads may be taken up yet) is taken up rather than replaced.
        const taken = await this.takeUpLeft(profile, key);
        const left = taken !== null;
        const host = taken ?? (await Host.start(profile, key, this.command, this.data, this.env, this.caBundle, this.options.lent, key === profile.id ? profile.home : cwd, await this.runnerFor(key)));
        // Taken up on a borrowed login: when that one runs out, as its auth.json says.
        if (left && this.options.lent?.borrowed(profile)) host.lentUntil = lentExpiry(profile.home);
        this.hosts.set(key, host);
        return { host };
      });
      if (result.waiting) {
        await result.waiting.whenIdle();
        continue;
      }
      await result.host!.ensureReady();
      return result.host!;
    }
  }

  /// An app-server a runner keeps, with no snapshot: what the previous station had handled of it is read again to know
  /// where each thread stands, from where the earliest turn running then began (its runner keeps it: `ackedOffset`).
  private async takeUp(profile: Profile, info: RunnerInfo, key = profile.id): Promise<Host> {
    const out = outFile(this.data, info.id);
    const { at, keep } = await ackedOffset(info, out);
    const recovered = new Map<string, Recovered>();
    const began = new Map<string, number>();
    const step = this.options.takeUpBytes ?? TAKE_UP_BYTES;
    // Since the last tell: lines read, and where it was.
    let read = 0;
    let told = keep ?? 0;
    for await (const { bytes, at: lineAt } of bytesWithin(out, keep ?? 0, at)) {
      if (++read === TAKE_UP_LINES || lineAt - told >= step) {
        read = 0;
        told = lineAt;
        this.options.taking?.();
        await new Promise((resolve) => setImmediate(resolve));
      }
      if (untold(bytes)) continue;
      let msg: Json;
      try {
        msg = JSON.parse(bytes.toString("utf8"));
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
        if (!began.has(thread)) began.set(thread, lineAt);
        if (typeof msg.params.turn?.id === "string") r.turnId = msg.params.turn.id;
      } else if (msg.method === "turn/completed") {
        began.delete(thread);
        r.busy = false;
        r.turnId = null;
      }
    }
    // Its signature is the profile's if it runs with what the profile says now (the arguments carry the overrides).
    const same = JSON.stringify(info.args) === JSON.stringify(hostArgs(profile));
    // Ids above any the previous station can have sent.
    const host = Host.adopt(profile.id, info, same ? hostSignature(profile) : "unknown", wall.now(), true, recovered, key);
    readVersion(host, out);
    for (const [thread, r] of recovered) {
      if (!r.busy) continue;
      host.turns.add(thread);
      host.running(thread, began.get(thread) ?? 0);
    }
    host.reckon(at);
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
    // A text-only request uses no tools; in a sandbox the command belongs to that environment, not this filesystem.
    if (!options.textOnly && !sandboxed(this.data)) {
      const env = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "codex"), options.profile.id), CODEX_HOME: options.profile.home };
      const missing = await (this.options.missingHost ?? findMissingCodexHost)(this.command, env);
      if (missing) {
        this.options.incompleteInstallation?.();
        throw new Said(tr(stationLang(), "station.updates.codexMissingHostChat"));
      }
    }
    const host = await this.host(options.profile, options.key, options.cwd);
    const model = options.model ?? profileModel(options.profile);
    const skillsOff = hostSkillsOff(this.hostSkills);
    const config: Json = options.textOnly ? {
      "features.shell_tool": false,
      "features.unified_exec": false,
      "features.multi_agent": false,
      "features.apps": false,
      "features.plugins": false,
      "features.browser_use": false,
      "features.computer_use": false,
      "features.image_generation": false,
      "features.view_image": false,
      "features.goals": false,
      "web_search": "disabled",
      "mcp_servers": {},
    } : {
      "mcp_servers.stillfail.url": options.mcpUrl,
      "mcp_servers.stillfail.http_headers": { Authorization: `Bearer ${options.mcpToken}` },
      // A repository's rules told as its tools first touch it, and again after a compaction (./repo-rules.ts: Codex
      // reads AGENTS.md only from where it starts up). Hooks run only once trusted, which a thread's config may say
      // it needs not (an app-server takes no --dangerously-bypass-hook-trust); hooks it knows no more are ignored.
      hooks: {
        PostToolUse: [{ matcher: "*", hooks: [{ type: "command", command: REPO_RULES_COMMAND }] }],
        PostCompact: [{ hooks: [{ type: "command", command: REPO_RULES_COMMAND }] }],
      },
      bypass_hook_trust: true,
    };
    if (options.textOnly) {
      // An empty table is merged with the profile's configured servers. Read their names without config/read, whose
      // reply can contain credentials and would be kept in the runner's output. The thread's inventory is checked too,
      // since its working directory may add servers absent from this host-level inventory.
      try {
        const servers = await mcpInventory(host);
        config.mcp_servers = Object.fromEntries(servers.map((s) => [s.name, { enabled: false }]));
      } catch {
        throw new Error("cannot open a text-only Codex session");
      }
    }
    if (options.effort !== undefined) config.model_reasoning_effort = options.effort;
    // The most context it runs with: it compacts on its own at it.
    if (options.context !== undefined) config.model_auto_compact_token_limit = options.context;
    if (skillsOff.length > 0) config["skills.config"] = skillsOff;
    const common: Json = { cwd: options.cwd, approvalPolicy: "never", sandbox: "danger-full-access", developerInstructions: options.instructions, config };
    if (options.textOnly) {
      common.sandbox = "read-only";
      common.ephemeral = true;
      common.environments = [];
    }
    if (model !== undefined) common.model = model;
    // None for a thread continued from a terminal: it keeps its own, so its cache holds.
    if (options.instructions === "") delete common.developerInstructions;
    let opened: Json;
    if (options.resume !== undefined) {
      await this.releasedElsewhere(options.profile, host.key, options.resume, host);
      common.threadId = options.resume;
      // Without the thread's history: the reply would carry every turn of it, which the station never reads (only the
      // thread's id and path), on one line of the app-server's output, read again whole after a crash. Its size grew
      // with the thread: 16.7 MB for a rollout of 54 MB, 3,975 bytes without (Codex 0.167.0); a station's 160 MB
      // reply was one line of an output of 77 GB that no station could take up again (2026-11-13).
      const resume = { ...common, excludeTurns: true };
      opened = await host.request("thread/resume", resume);
      // A thread still loaded is rejoined as it is, with the MCP connection it had: one that failed (the station's
      // door was closed then) stays failed, and its turns have no station tools. Unloaded, it is loaded again with them.
      if (await stationToolsFailed(host, options.resume)) {
        log.warn("agents::codex", "a thread's station tools had failed; loading it again", { thread: options.resume });
        await host.request("thread/unsubscribe", { threadId: options.resume });
        opened = await host.request("thread/resume", resume);
      }
    } else {
      opened = await host.request("thread/start", common);
    }
    let threadId = opened?.thread?.id;
    if (typeof threadId !== "string") throw new Error("codex gave no thread id");
    if (options.textOnly) {
      // A directory can add servers that were absent from the host's inventory. Open another thread with those
      // disabled too; neither thread gets any conversation text until its effective inventory is entirely disabled.
      try {
        const servers = await mcpInventory(host, threadId);
        if (servers.some((s) => s.runtimeStatus !== "disabled")) {
          if (options.resume !== undefined) throw new Error("cannot disable a resumed thread's MCP servers");
          await host.request("thread/unsubscribe", { threadId });
          config.mcp_servers = { ...config.mcp_servers, ...Object.fromEntries(servers.map((s) => [s.name, { enabled: false }])) };
          opened = await host.request("thread/start", common);
          threadId = opened?.thread?.id;
          if (typeof threadId !== "string") throw new Error("codex gave no thread id");
          if ((await mcpInventory(host, threadId)).some((s) => s.runtimeStatus !== "disabled")) throw new Error("MCP servers are enabled");
        }
      } catch {
        if (typeof threadId === "string") await host.request("thread/unsubscribe", { threadId }).catch(() => {});
        throw new Error("cannot open a text-only Codex session");
      }
    }
    const session = new CodexSession(this, threadId, host, options.profile, { busy: false, turnId: null, closed: false }, new LiveFromCodex(), events);
    session.rememberTranscript(opened?.thread?.path);
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
    let host = await this.serial(async () => {
      // Being replaced as it was handed over: taken up so again, its own turns ending on it.
      if (handed?.host.draining) {
        const already = [...this.draining].find((h) => h.proc.info.id === handed.host.runner);
        if (already) return already;
        const info = await findRunner(this.data, handed.host.runner);
        if (!info) throw new Error(`codex app-server ${key} was not taken up: no runner keeps it`);
        const host = Host.adopt(profileId, info, handed.host.signature, handed.host.nextId, handed.host.ready, undefined, key, handed.host.keep ?? 0);
        readVersion(host, outFile(this.data, info.id));
        this.keepDraining(host);
        return host;
      }
      const current = this.hosts.get(key);
      if (current && current.alive()) {
        if (handed?.host.loginStale) current.loginStale = true;
        if (handed?.host.runtimeStale) current.runtimeStale = true;
        return current;
      }
      if (current) await current.proc.released();
      let host: Host | null;
      if (handed) {
        const info = await findRunner(this.data, handed.host.runner);
        if (!info) throw new Error(`codex app-server ${key} was not taken up: no runner keeps it`);
        host = Host.adopt(profileId, info, handed.host.signature, handed.host.nextId, handed.host.ready, undefined, key, handed.host.keep ?? 0);
        this.sweepLeft(options.profile, key);
        if (handed.host.loginStale) host.loginStale = true;
        if (handed.host.runtimeStale) host.runtimeStale = true;
        readVersion(host, outFile(this.data, info.id));
      } else host = await this.takeUpLeft(options.profile, key);
      if (!host) throw new Error(`codex app-server ${key} was not taken up: no runner keeps it`);
      this.hosts.set(key, host);
      return host;
    });
    let session: CodexSession;
    if (handed) {
      session = new CodexSession(this, handed.threadId, host, options.profile, { busy: handed.busy, turnId: handed.turnId, closed: false }, new LiveFromCodex(handed.live), events);
      session.tuned = handed.tuned ?? null;
      session.running = session.tuned;
      session.toolsUrl = handed.mcpUrl ?? null;
      session.rememberTranscript(handed.transcriptPath);
    } else {
      const threadId = options.resume;
      if (threadId === undefined) throw new Error("a codex thread is taken up by its id (resume)");
      // Its turn running on one being replaced (left by a station that crashed beside a newer one): it goes on there.
      host = [...this.draining].find((h) => h.key === key && h.recovered.get(threadId)?.busy) ?? host;
      const r = host.recovered.get(threadId);
      host.recovered.delete(threadId);
      session = new CodexSession(this, threadId, host, options.profile, { busy: r?.busy ?? false, turnId: r?.turnId ?? null, closed: false }, r?.live ?? new LiveFromCodex(), events);
      // A turn is running that this station did not start.
      if (r?.busy) events({ type: "turnStarted" });
    }
    host.addThread(session.id(), session.sink());
    session.recoverTranscript();
    if (session.busy()) {
      host.turns.add(session.id());
      // Its turn began at or after where the station before kept: a crash reads from there.
      if (handed) host.running(session.id(), host.handedFrom);
    }
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
    if (host.runtimeStale) return true;
    if (host.version === null) return false;
    await this.installedVersion();
    return this.stale(host);
  }

  async shutdown() {
    const hosts = [...this.hosts.values(), ...this.draining];
    this.hosts.clear();
    this.draining.clear();
    await Promise.all(hosts.map((h) => h.proc.kill(5000)));
  }

  detach() {
    for (const host of [...this.hosts.values(), ...this.draining]) host.detach();
    this.hosts.clear();
    this.draining.clear();
  }
}

/// Names and runtime states only: unlike config/read this does not return configured MCP credentials.
async function mcpInventory(host: Host, threadId?: string): Promise<{ name: string; runtimeStatus: unknown }[]> {
  const servers: { name: string; runtimeStatus: unknown }[] = [];
  let cursor: string | null = null;
  do {
    const inventory = await host.request("mcpServerStatus/list", { ...(threadId === undefined ? {} : { threadId }), cursor, detail: "toolsAndAuthOnly" });
    if (!Array.isArray(inventory?.data) || inventory.data.some((s: Json) => typeof s?.name !== "string")) throw new Error("invalid MCP inventory");
    servers.push(...inventory.data.map((s: Json) => ({ name: s.name, runtimeStatus: s.runtimeStatus })));
    cursor = typeof inventory.nextCursor === "string" ? inventory.nextCursor : null;
  } while (cursor !== null);
  return servers;
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

/// Whether a thread's notification says it compacted its context, on its own as it filled or by thread/compact/start:
/// a contextCompaction item done.
export const codexCompacted = (method: string, params: Json) => method === "item/completed" && params?.item?.type === "contextCompaction";

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
  private transcriptPath: string | null = null;

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
      if (codexCompacted(method, params)) this.events({ type: "compacted" });
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
            reason: classifyCodexError(error?.codexErrorInfo ?? null, typeof error?.message === "string" ? error.message : ""),
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

  runtimeVersion() {
    return this.host.version;
  }

  runtimeUpdateMatchesStation() {
    return this.driver.updateMatchesStation(this.profile);
  }

  rememberTranscript(path: unknown) {
    this.transcriptPath = rememberCodexRollout(this.profile.home, this.threadId, path);
  }

  /// A snapshot from an older station (or recovery after a crash) has no path. Ask the running app-server without
  /// holding up the handover; if it cannot say, the ordinary transcript lookup still works.
  recoverTranscript() {
    if (this.transcriptPath !== null) return;
    void this.host.request("thread/read", { threadId: this.threadId, includeTurns: false })
      .then((answer) => { if (!this.state.closed) this.rememberTranscript(answer?.thread?.path); })
      .catch(() => {});
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
    const outdated = this.host.loginStale || this.host.runtimeStale || (this.host.turns.size === 0 && (await this.driver.outdated(this.host, p)));
    await this.driver.renewLent(this.host, this.profile);
    if (this.state.closed) throw new Error("codex session is closed");
    if (this.state.busy) throw new Error("a turn is already running");
    if (outdated) throw new Error("codex was updated, or its profile changed, under its app-server");
    // Its thread could not connect to the station's tools (the door was closed or slow as it was opened, or as it was
    // taken up): its turn would have no chat_post or chat_state, and nothing it called would say so. Opened again,
    // resuming, the thread is loaded with them.
    if (await stationToolsFailed(this.host, this.threadId)) throw new Error("codex thread's connection to the station's tools failed");
    // Looked at again with nothing awaited before the turn is counted: its app-server being replaced lets go of a
    // thread with no turn in the same step (`drain`), so a turn begins on it before that, or is opened again elsewhere.
    if (this.state.closed) throw new Error("codex session is closed");
    if (this.host.draining) throw new Error("its codex app-server is being replaced");
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
    if (this.host.draining) throw new Error("its codex app-server is being replaced");
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
      ...(this.transcriptPath !== null ? { transcriptPath: this.transcriptPath } : {}),
    };
  }

  detach() {
    this.state.closed = true;
    this.host.freeze();
    this.host.threads.delete(this.threadId);
    if (this.host.threads.size === 0) this.host.detach();
  }
}
