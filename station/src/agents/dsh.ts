// DeepSeek Harness driver: one `dsh --profile acp` per session, under a runner whose id comes from the session key,
// spoken to in ACP (Agent Client Protocol, JSON-RPC over stdio) with one ACP session in it.
//
// Behaviour pinned against dsh 0.2 (docs/dsh.md):
// - `session/new` names the session (no id of ours can be given); `session/resume` takes up a persisted one, and fails
//   for an id it does not have;
// - `session/prompt` is answered when the turn is over: `stopReason` (`cancelled` after `session/cancel`), or an error
//   whose message says why it failed (`turn failed: 401: …`); one prompt at a time, so input for a running turn waits;
// - what the model says comes whole in `session/update`s (agent_message_chunk, agent_thought_chunk), tool calls as
//   tool_call then tool_call_update;
// - the model, its provider and the station's instructions are dsh's configuration: a patch file over its acp profile,
//   written per session; the station's tools are an HTTP MCP server given to `session/new`/`session/resume`.
import { mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { LiveFromDsh, chars, type DshLiveState } from "./live.ts";
import { AgentProcess, ackedOffset, debug, findRunner, linesBefore, outFile, runnerId } from "./process.ts";
import { DSH_KEY, dshRoute, expandRoute, profileEnv, profileModel, type DshRoute } from "./profiles.ts";
import { TOOL_SERVERS, cleanEnv, unreachable, uuid, type AgentDriver, type AgentSession, type FailureReason, type OpenOptions, type RuntimeEvent, type TurnOutcome } from "./runtime.ts";

type Json = any;
type Env = Record<string, string | undefined>;

/// Inherited variables that would let a session use another account or home than its profile's.
const SCRUBBED = ["DEEPSEEK_API_KEY", "DEEPSEEK_BASE_URL", DSH_KEY, "DSH_HOME", "DSH_AGENTS_HOME", "DSH_PERMISSION_MODE"];
/// The route the station's patch declares for a profile's provider (dsh's own DeepSeek route keeps its name).
const ROUTE = "stillfail";
const DEEPSEEK_ROUTE = "deepseek-official";
/// Where in its home a profile's dsh keeps its sessions (not dsh's own sessions/: a profile home's is Codex's too,
/// agent-home.ts `transcriptDir`).
export const SESSIONS = "dsh-sessions";
/// dsh's own model when a DeepSeek profile names none.
const DEEPSEEK_MODEL = "deepseek-v4-flash";

/// The ids of the requests the station makes: a prompt's carry its own, so whatever answers one (after a crash too)
/// ends the turn.
const INIT = "init";
const OPEN = "open";
const PROMPT = "prompt:";

/// Reasoning effort in the station's terms (pool.ts: low, medium, high, max) as each route takes it.
const piEffort = (effort: string | undefined) => (effort && ["minimal", "low", "medium", "high", "xhigh", "max"].includes(effort) ? effort : undefined);
const deepseekEffort = (effort: string | undefined) => (effort === "low" ? "low" : effort === "medium" || effort === "high" ? "high" : effort === "max" ? "max" : undefined);

/// dsh's prompt variables are `{{name}}`, strictly: any other `{{` in the instructions would stop it, so it is broken.
const literal = (text: string) => text.replaceAll("{{", "{​{");

/// The patch over dsh's acp profile for a session (YAML; JSON is YAML): the profile's provider as a route of its own,
/// its model, the station's instructions after dsh's own, transcripts kept uncompressed (read/transcript.ts reads
/// them). Null for a profile that brings its own configuration (custom variables) but for the instructions.
export function dshPatch(route: DshRoute | null, model: string | undefined, effort: string | undefined, instructions: string, home: string, sessionRoute: string): Json[] {
  const patch: Json[] = [];
  if (route?.kind === "pi") {
    if (model === undefined) throw new Error("the profile names no model for DeepSeek Harness");
    const provider: Json = { displayName: route.name, api: route.api, baseURL: route.baseURL, apiKeyEnv: DSH_KEY, models: [{ id: model }] };
    if (route.headers) provider.headers = expandRoute(route.headers, sessionRoute);
    const reasoning = piEffort(effort);
    if (reasoning) provider.reasoning = reasoning;
    patch.push({ id: "llm-pi-ai", config: { providers: { [ROUTE]: provider } } });
    patch.push({ id: "agent-default-model", config: { provider: ROUTE, model } }, { id: "acp", config: { provider: ROUTE, model } });
  } else if (route?.kind === "deepseek") {
    const chosen = model ?? DEEPSEEK_MODEL;
    const config: Json = { apiKeyEnv: "DEEPSEEK_API_KEY" };
    if (model !== undefined) config.models = [{ id: model }];
    const reasoning = deepseekEffort(effort);
    if (reasoning) config.reasoningEffort = reasoning;
    patch.push({ id: "llm-deepseek", config });
    patch.push({ id: "agent-default-model", config: { provider: DEEPSEEK_ROUTE, model: chosen } }, { id: "acp", config: { provider: DEEPSEEK_ROUTE, model: chosen } });
  } else if (model !== undefined) {
    // Its own configuration, with a model named: DeepSeek's (dsh's own default route).
    patch.push({ id: "agent-default-model", config: { provider: DEEPSEEK_ROUTE, model } }, { id: "acp", config: { provider: DEEPSEEK_ROUTE, model } });
  }
  const persona = "You are a coding agent powered by the {{model}} model.";
  const suffix = instructions === "" ? "Your working directory is {{cwd}}." : `Your working directory is {{cwd}}.\n\n${literal(instructions)}`;
  patch.push({ id: "system-prompt", config: { personaPrefix: persona, personaSuffix: suffix } });
  patch.push({ id: "session-persistence-jsonl", config: { root: join(home, SESSIONS), compression: "none" } });
  return patch;
}

/// dsh keeps a session at <root>/<cwd>/<id>/session.v<N>.jsonl (the highest N is the current format): the directory,
/// if it is there.
export function sessionDir(home: string, sessionId: string): string | null {
  const root = join(home, SESSIONS);
  let dirs: string[];
  try {
    dirs = readdirSync(root);
  } catch {
    return null;
  }
  // Its id escaped to one path segment as dsh does: a UUID stays as it is.
  for (const d of dirs) {
    const dir = join(root, d, sessionId);
    try {
      if (statSync(dir).isDirectory()) return dir;
    } catch {}
  }
  return null;
}

/// What failed a turn, from what dsh said of it.
export function classifyFailure(text: string): FailureReason {
  const lower = text.toLowerCase();
  const words = lower.split(/[^\p{L}\p{N}_]+/u);
  const word = (w: string) => words.includes(w);
  if (word("401") || word("403") || ["invalid credential", "missing_credential", "invalid_credential", "api key", "unauthorized", "authenticat"].some((s) => lower.includes(s))) return "auth";
  if (word("429") || ["rate limit", "rate_limit", "quota", "overloaded", "insufficient balance"].some((s) => lower.includes(s))) return "rate_limit";
  return "model";
}

/// How a prompt's answer ends the turn.
export function outcomeOf(message: Json): TurnOutcome {
  if (message?.error !== undefined) {
    const text = typeof message.error?.message === "string" ? message.error.message.replace(/^Internal error: /, "") : JSON.stringify(message.error);
    return { kind: "failed", reason: classifyFailure(text), message: chars(text, 1000) };
  }
  const stop = message?.result?.stopReason;
  if (stop === "cancelled") return { kind: "aborted" };
  if (stop === "refusal") return { kind: "failed", reason: "model", message: "the model refused" };
  return { kind: "completed" };
}

/// The turn as its handled lines leave it.
export type Turn = { busy: boolean; aborting: boolean; closed: boolean };

/// A session as a next station takes it up.
export type DshSnapshot = { runtime: "dsh"; id: string; runner: string; turn: { busy: boolean; aborting: boolean }; tools: string | null; live: DshLiveState };

export type DshDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
  env?: Env;
};

const parse = (line: string): Json | undefined => {
  try {
    return JSON.parse(line);
  } catch {
    debug("agents::dsh", "dsh non-json line", { line: line.slice(0, 500) });
    return undefined;
  }
};

const rpc = (id: string, method: string, params: Json) => JSON.stringify({ jsonrpc: "2.0", id, method, params });

/// The station's tools as ACP gives an MCP server.
const mcpServers = (url: string, token: string) => [{ type: "http", name: "stillfail", url, headers: [{ name: "Authorization", value: `Bearer ${token}` }] }];

export class DshDriver implements AgentDriver {
  private readonly data: string;
  private readonly command: string;
  private live = new Set<DshSession>();

  constructor(options: DshDriverOptions) {
    this.data = options.data;
    this.command = options.command ?? "dsh";
  }

  runtime(): "dsh" {
    return "dsh";
  }

  async open(options: OpenOptions, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const home = options.profile.home;
    mkdirSync(home, { recursive: true });
    if (options.resume !== undefined && sessionDir(home, options.resume) === null) {
      // dsh would refuse it; failing here lets the caller start fresh.
      throw new Error(`no dsh session ${options.resume}`);
    }
    const model = options.model ?? profileModel(options.profile);
    const patch = dshPatch(dshRoute(options.profile), model, options.effort, options.instructions, home, options.route);
    // Per session: its instructions and model are in it. Named by the session's key, so a session started again
    // writes over its own.
    const dir = join(home, "stillfail");
    mkdirSync(dir, { recursive: true });
    const patchFile = join(dir, `${createHash("sha256").update(options.key).digest("hex").slice(0, 16)}.patch.yml`);
    writeFileSync(patchFile, `${JSON.stringify(patch, null, 2)}\n`, { mode: 0o600 });
    const args = ["--profile", "acp", "--patch", patchFile];

    const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "dsh"), options.route) };
    env.DSH_HOME = home;
    // Its shared skills and AGENTS.md are the profile home's (agent-home.ts), not the person's ~/.agents.
    env.DSH_AGENTS_HOME = join(home, "agents");
    // No sandbox and no approvals, as the other runtimes run here; nothing of a session goes to DeepSeek's telemetry.
    env.DSH_PERMISSION_MODE = "danger-full-access";
    env.DSH_TELEMETRY_MODE ??= "DISABLED";
    env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);

    const session = new DshSession(this, "", { busy: false, aborting: false, closed: false }, new LiveFromDsh(), events);
    session.toolsUrl = options.mcpUrl;
    const label = `dsh ${options.key}`;
    session.attach(await AgentProcess.start(this.data, runnerId("dsh", options.key), this.command, args, env, options.cwd, session.processOptions(label)));
    this.live.add(session);
    try {
      await session.request(INIT, "initialize", { protocolVersion: 1, clientCapabilities: {} });
      const servers = mcpServers(options.mcpUrl, options.mcpToken);
      if (options.resume !== undefined) {
        await session.request(OPEN, "session/resume", { sessionId: options.resume, cwd: options.cwd, mcpServers: servers });
        session.named(options.resume);
      } else {
        const opened = await session.request(OPEN, "session/new", { cwd: options.cwd, mcpServers: servers });
        const id = opened?.result?.sessionId;
        if (typeof id !== "string" || id === "") throw new Error("dsh named no session");
        session.named(id);
      }
    } catch (error) {
      await session.dispose();
      throw error;
    }
    return session;
  }

  async adopt(options: OpenOptions, snapshot: unknown | null, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const handed = snapshot as DshSnapshot | null;
    const id = handed?.runner ?? runnerId("dsh", options.key);
    const info = findRunner(this.data, id);
    if (!info) throw new Error(`no runner keeps dsh for ${options.key}`);
    let session: DshSession;
    if (handed) {
      log.info("agents::dsh", "taking up a dsh process handed over", { session: handed.id, pgid: info.pgid, busy: handed.turn.busy });
      session = new DshSession(this, handed.id, { ...handed.turn, closed: false }, new LiveFromDsh(handed.live), events);
      session.toolsUrl = handed.tools;
    } else {
      // The previous station crashed: what it had handled is read again, silently, to know the session and where the
      // turn stands; the rest comes as it would have.
      const at = await ackedOffset(info, outFile(this.data, id));
      const turn: Turn = { busy: false, aborting: false, closed: false };
      const live = new LiveFromDsh();
      let sessionId = options.resume ?? "";
      for (const line of linesBefore(outFile(this.data, id), at)) {
        const message = parse(line);
        if (message === undefined) continue;
        if (message.id === OPEN && typeof message.result?.sessionId === "string") sessionId = message.result.sessionId;
        if (message.method === "session/update") {
          turn.busy = true;
          live.feed(message.params?.update);
        } else if (typeof message.id === "string" && message.id.startsWith(PROMPT)) {
          turn.busy = false;
          live.ended();
        }
      }
      log.info("agents::dsh", "taking up a dsh process after a crash", { session: sessionId, pgid: info.pgid, busy: turn.busy, from: at });
      session = new DshSession(this, sessionId, turn, live, events);
      session.toolsUrl = options.mcpUrl;
      // A turn is running that this station did not start.
      if (turn.busy) events({ type: "turnStarted" });
    }
    session.attach(AgentProcess.adopt(info, session.processOptions(`dsh ${options.key}`)));
    this.live.add(session);
    return session;
  }

  forget(session: DshSession) {
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

export class DshSession implements AgentSession {
  private proc!: AgentProcess;
  private driver: DshDriver;
  private sessionId: string;
  private turn: Turn;
  private live: LiveFromDsh;
  private events: (event: RuntimeEvent) => void;
  /// Requests of ours waiting for their answer (not prompts: their answer ends the turn).
  private waiting = new Map<string, { resolve: (message: Json) => void; reject: (error: Error) => void }>();
  /// Its calls to the station's tools not answered yet.
  private calls = new Set<string>();
  toolsUrl: string | null = null;

  constructor(driver: DshDriver, sessionId: string, turn: Turn, live: LiveFromDsh, events: (event: RuntimeEvent) => void) {
    this.driver = driver;
    this.sessionId = sessionId;
    this.turn = turn;
    this.live = live;
    this.events = events;
  }

  named(id: string) {
    this.sessionId = id;
  }

  attach(proc: AgentProcess) {
    this.proc = proc;
  }

  /// A request whose answer is waited for: an error answer rejects.
  request(id: string, method: string, params: Json): Promise<Json> {
    return new Promise((resolve, reject) => {
      this.waiting.set(id, {
        resolve: (message) => (message?.error !== undefined ? reject(new Error(`dsh ${method}: ${message.error?.message ?? JSON.stringify(message.error)}`)) : resolve(message)),
        reject,
      });
      this.proc.write(rpc(id, method, params));
    });
  }

  processOptions(label: string) {
    return {
      label,
      line: (line: string) => {
        const message = parse(line);
        if (message === undefined) return;
        this.onMessage(message);
      },
      exit: (said: string, stderr: string) => {
        this.turn.closed = true;
        const why = stderr === "" ? "" : `: ${stderr}`;
        for (const w of this.waiting.values()) w.reject(new Error(`dsh exited (${said})${why}`));
        this.waiting.clear();
        const busy = this.turn.busy;
        this.turn.busy = false;
        if (busy) {
          for (const event of this.live.ended()) this.events({ type: "live", event });
          this.events({ type: "turnEnded", outcome: { kind: "failed", reason: "exited", message: `dsh exited (${said}) during the turn${why}` } });
        }
        this.events({ type: "closed", why: `dsh exited (${said})${why}` });
        this.driver.forget(this);
      },
    };
  }

  private onMessage(message: Json) {
    const id = message.id;
    if (message.method === "session/update") {
      const update = message.params?.update;
      for (const event of this.live.feed(update)) this.events({ type: "live", event });
      const lost = this.toolsLost(update);
      if (lost !== null) this.events({ type: "toolsLost", why: lost });
      return;
    }
    if (message.method === "session/request_permission" && id !== undefined) {
      // Nothing is asked here (no approvals); should it ask, what it would do is allowed, as the other runtimes are.
      const options: Json[] = Array.isArray(message.params?.options) ? message.params.options : [];
      const chosen = options.find((o) => o?.kind === "allow_always") ?? options.find((o) => o?.kind === "allow_once") ?? options[0];
      const result = chosen ? { outcome: { outcome: "selected", optionId: chosen.optionId } } : { outcome: { outcome: "cancelled" } };
      this.proc.write(JSON.stringify({ jsonrpc: "2.0", id, result }));
      return;
    }
    if (message.method !== undefined) {
      // A request of its own the station has no answer for.
      if (id !== undefined) this.proc.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code: -32601, message: `${message.method} is not supported` } }));
      return;
    }
    if (typeof id === "string" && id.startsWith(PROMPT)) {
      const outcome = this.turn.aborting && message.error !== undefined ? ({ kind: "aborted" } as TurnOutcome) : outcomeOf(message);
      // An answer to a prompt this station did not see start (taken up after a crash just as it was given).
      if (!this.turn.busy) this.events({ type: "turnStarted" });
      this.turn.busy = false;
      this.turn.aborting = false;
      for (const event of this.live.ended()) this.events({ type: "live", event });
      this.events({ type: "turnEnded", outcome });
      return;
    }
    const waiting = typeof id === "string" ? this.waiting.get(id) : undefined;
    if (waiting) {
      this.waiting.delete(id);
      waiting.resolve(message);
    }
  }

  /// What an update says of the station's tools being out of reach (null: nothing): a call to one of them failed as
  /// unreachable.
  private toolsLost(update: Json): string | null {
    const kind = update?.sessionUpdate;
    const callId = typeof update?.toolCallId === "string" ? update.toolCallId : undefined;
    if (callId === undefined) return null;
    if (kind === "tool_call" && TOOL_SERVERS.some((s) => String(update.title ?? "").includes(s))) this.calls.add(callId);
    if ((kind === "tool_call" || kind === "tool_call_update") && update.status === "failed" && this.calls.delete(callId)) {
      const text = (Array.isArray(update.content) ? update.content : []).map((c: Json) => c?.content?.text ?? c?.text ?? "").join("\n");
      if (unreachable(text)) return chars(text, 300);
    }
    if (update.status === "completed") this.calls.delete(callId);
    return null;
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

  async prompt(text: string) {
    if (this.turn.closed) throw new Error("dsh session is closed");
    if (this.turn.busy) throw new Error("a turn is already running");
    this.turn.busy = true;
    for (const event of this.live.prompted()) this.events({ type: "live", event });
    this.proc.write(rpc(`${PROMPT}${uuid()}`, "session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text }] }));
  }

  /// ACP takes one prompt at a time: what comes while a turn runs waits for the next.
  async steer(_text: string) {
    return false;
  }

  async backgroundTools() {}

  async abort() {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return;
    this.turn.aborting = true;
    this.proc.write(JSON.stringify({ jsonrpc: "2.0", method: "session/cancel", params: { sessionId: this.sessionId } }));
  }

  async dispose() {
    this.driver.forget(this);
    this.turn.closed = true;
    for (const w of this.waiting.values()) w.reject(new Error("dsh session is closed"));
    this.waiting.clear();
    await this.proc.kill(5000);
  }

  snapshot(): DshSnapshot {
    this.proc.freeze();
    this.turn.closed = true;
    return { runtime: "dsh", id: this.sessionId, runner: this.proc.info.id, turn: { busy: this.turn.busy, aborting: this.turn.aborting }, tools: this.toolsUrl, live: this.live.state() };
  }

  detach() {
    this.turn.closed = true;
    this.driver.forget(this);
    this.proc.detach();
  }
}

