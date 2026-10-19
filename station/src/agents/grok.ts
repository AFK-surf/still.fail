// Grok Build driver: one `grok agent stdio` per session, under a runner whose id comes from the session key, spoken to in
// ACP (Agent Client Protocol, JSON-RPC over stdio) with one ACP session in it.
//
// Behaviour pinned against Grok Build 1.0 (docs/grok.md):
// - `session/new` names the session; `session/load` takes up a persisted one (its directory under the home's
//   sessions/, one directory per working directory);
// - `session/prompt` is answered when the turn is over: `stopReason` (`cancelled` after `session/cancel`), or an error
//   whose message says why it failed; its `_meta` carries the turn's usage;
// - what comes in while a turn runs goes into it with `x.ai/interject` (at the next safe point: after the tool call it
//   is in), not as a prompt of its own;
// - what the model says streams in `session/update`s (agent_message_chunk, agent_thought_chunk), tool calls as
//   tool_call then tool_call_update; Grok Build's own notifications (x.ai/…) are not needed here;
// - the model and effort are flags of the process, the station's instructions `_meta.rules`, its tools an HTTP MCP
//   server given to `session/new`/`session/load`; `--always-approve` runs without approvals, as the other runtimes do.
import { appendFileSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { LiveFromAcp, chars, type AcpLiveState } from "./live.ts";
import { AgentProcess, ackedOffset, debug, findRunner, linesBefore, outFile, runnerId } from "./process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { TOOL_SERVERS, cleanEnv, unreachable, uuid, type AgentDriver, type AgentSession, type FailureReason, type OpenOptions, type RuntimeEvent, type TurnOutcome } from "./runtime.ts";

type Json = any;
type Env = Record<string, string | undefined>;

/// Inherited variables that would let a session use another account, home or configuration than its profile's.
const SCRUBBED = ["XAI_API_KEY", "GROK_CODE_XAI_API_KEY", "GROK_HOME", "GROK_AUTH", "GROK_AUTH_PATH", "GROK_AUTH_PROVIDER_COMMAND", "GROK_CONFIG", "GROK_CONFIG_PATH", "GROK_DEFAULT_MODEL", "GROK_AGENT_SECRET", "GROK_SANDBOX"];
/// Grok Build's home in a profile's (GROK_HOME): its sign-in, configuration and sessions apart from the other runtimes'
/// a profile may run (Codex's sessions/ is in the profile's home itself).
export const grokHome = (home: string) => join(home, "grok");
/// Where in its home Grok Build keeps its sessions; in a session's directory, its transcript, and what the station
/// writes beside it of each turn's usage (Grok Build keeps none: the prompt's answer says it).
export const SESSIONS = "sessions";
export const TRANSCRIPT = "chat_history.jsonl";
export const USAGE = "stillfail-usage.jsonl";

/// The ids of the requests the station makes: a prompt's carry its own, so whatever answers one (after a crash too)
/// ends the turn.
const INIT = "init";
const OPEN = "open";
const PROMPT = "prompt:";
const STEER = "steer:";

/// Reasoning effort in the station's terms (pool.ts) as Grok Build takes it (low, medium, high, xhigh; max where the
/// model has it).
export const grokEffort = (effort: string | undefined) => (effort && ["low", "medium", "high", "xhigh", "max"].includes(effort) ? effort : undefined);

/// Grok Build keeps a session at <grok home>/sessions/<working directory, escaped>/<id>/: the directory, if it is there
/// (`home`: the profile's).
export function sessionDir(home: string, sessionId: string): string | null {
  if (sessionId === "") return null;
  const root = join(grokHome(home), SESSIONS);
  let dirs: string[];
  try {
    dirs = readdirSync(root);
  } catch {
    return null;
  }
  for (const d of dirs) {
    try {
      if (statSync(join(root, d, sessionId)).isDirectory()) return join(root, d, sessionId);
    } catch {}
  }
  return null;
}

/// What failed a turn, from what Grok Build said of it.
export function classifyFailure(text: string): FailureReason {
  const lower = text.toLowerCase();
  const words = lower.split(/[^\p{L}\p{N}_]+/u);
  const word = (w: string) => words.includes(w);
  if (word("401") || word("403") || ["unauthorized", "unauthenticated", "not logged in", "sign in", "log in", "authenticat", "api key", "access token", "permission_denied", "subscription"].some((s) => lower.includes(s))) return "auth";
  if (word("429") || ["rate limit", "rate_limit", "quota", "resource_exhausted", "overloaded", "too many requests", "usage limit"].some((s) => lower.includes(s))) return "rate_limit";
  return "model";
}

/// How a prompt's answer ends the turn.
export function outcomeOf(message: Json): TurnOutcome {
  if (message?.error !== undefined) {
    const text = typeof message.error?.message === "string" ? message.error.message.replace(/^Internal error: /, "") : JSON.stringify(message.error);
    const data = typeof message.error?.data === "string" ? `: ${message.error.data}` : "";
    const said = `${text}${data}`;
    return { kind: "failed", reason: classifyFailure(said), message: chars(said, 1000) };
  }
  const stop = message?.result?.stopReason;
  if (stop === "cancelled") return { kind: "aborted" };
  if (stop === "refusal") return { kind: "failed", reason: "model", message: "the model refused" };
  return { kind: "completed" };
}

/// A turn's usage as the station keeps it beside the transcript (counted by usage/counter.ts): its input less what was
/// read from the cache or written to it, as the others count.
export function usageLine(answer: Json, time: number): string | null {
  const meta = answer?.result?._meta;
  const u = meta?.usage;
  if (u === null || typeof u !== "object") return null;
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  const read = n(u.cachedReadTokens);
  const written = n(u.cacheCreationTokens);
  const usage = { input: Math.max(0, n(u.inputTokens) - read - written), cacheRead: read, cacheWrite: written, output: n(u.outputTokens) };
  const id = typeof meta.promptId === "string" ? meta.promptId : typeof meta.requestId === "string" ? meta.requestId : null;
  if (id === null) return null;
  return JSON.stringify({ type: "stillfail/usage", time, id, model: typeof meta.modelId === "string" ? meta.modelId : null, usage });
}

/// The turn as its handled lines leave it.
export type Turn = { busy: boolean; aborting: boolean; closed: boolean };

/// A session as a next station takes it up.
export type GrokSnapshot = { runtime: "grok"; id: string; runner: string; turn: { busy: boolean; aborting: boolean }; tools: string | null; live: AcpLiveState };

export type GrokDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

const parse = (line: string): Json | undefined => {
  try {
    return JSON.parse(line);
  } catch {
    debug("agents::grok", "grok non-json line", { line: line.slice(0, 500) });
    return undefined;
  }
};

const rpc = (id: string, method: string, params: Json) => JSON.stringify({ jsonrpc: "2.0", id, method, params });

/// The station's tools as ACP gives an MCP server.
const mcpServers = (url: string, token: string) => [{ type: "http", name: "stillfail", url, headers: [{ name: "Authorization", value: `Bearer ${token}` }] }];

/// The station's instructions as Grok Build is given them: with how its tools are reached there (an MCP server's tools
/// are behind Grok Build's search_tool and use_tool), so that no turn spends a step looking for them.
export const grokRules = (instructions: string) =>
  `${instructions}${instructions === "" ? "" : "\n\n"}The station's tools (chat_post, chat_state and the others named in these instructions) are the stillfail MCP server's: call one with use_tool and its full name, stillfail__<tool> (for example stillfail__chat_post), without searching for it first.`;

/// The process's arguments: no approvals, its own process (not a shared leader), the model and effort chosen.
export function grokArgs(model: string | undefined, effort: string | undefined): string[] {
  const args = ["agent", "--always-approve", "--no-leader"];
  if (model !== undefined) args.push("--model", model);
  const e = grokEffort(effort);
  if (e !== undefined) args.push("--reasoning-effort", e);
  args.push("stdio");
  return args;
}

/// Its environment: the profile's home as Grok Build's, its key where it has one; no updating itself, no telemetry.
export function grokEnv(options: OpenOptions): Record<string, string> {
  const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "grok"), options.route) };
  env.GROK_HOME = grokHome(options.profile.home);
  env.GROK_DISABLE_AUTOUPDATER = "1";
  env.GROK_TELEMETRY_ENABLED ??= "0";
  env.GROK_TELEMETRY_TRACE_UPLOAD ??= "0";
  // Not the person's Claude Code or Cursor setup (their hooks, MCP servers, rules, skills): the station's agents run
  // with the profile's and the station's, as Claude Code runs with its profile's home here.
  for (const vendor of ["CLAUDE", "CURSOR"]) for (const cell of ["SKILLS", "RULES", "AGENTS", "MCPS", "HOOKS", "SESSIONS"]) env[`GROK_${vendor}_${cell}_ENABLED`] = "false";
  env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
  return env;
}

export class GrokDriver implements AgentDriver {
  private readonly data: string;
  private readonly command: string;
  private live = new Set<GrokSession>();

  constructor(options: GrokDriverOptions) {
    this.data = options.data;
    this.command = options.command ?? "grok";
  }

  runtime(): "grok" {
    return "grok";
  }

  async open(options: OpenOptions, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const home = options.profile.home;
    mkdirSync(grokHome(home), { recursive: true });
    if (options.resume !== undefined && sessionDir(home, options.resume) === null) {
      // Grok Build would refuse it; failing here lets the caller start fresh.
      throw new Error(`no Grok Build session ${options.resume}`);
    }
    const model = options.model ?? profileModel(options.profile);
    const session = new GrokSession(this, "", { busy: false, aborting: false, closed: false }, new LiveFromAcp(), events, home);
    session.toolsUrl = options.mcpUrl;
    const label = `grok ${options.key}`;
    session.attach(await AgentProcess.start(this.data, runnerId("grok", options.key), this.command, grokArgs(model, options.effort), grokEnv(options), options.cwd, session.processOptions(label)));
    this.live.add(session);
    try {
      // The station's instructions after Grok Build's own, for the session opened or loaded.
      const meta = { rules: grokRules(options.instructions) };
      await session.request(INIT, "initialize", { protocolVersion: 1, clientCapabilities: {}, clientInfo: { name: "still.fail", version: "1" }, _meta: meta });
      const servers = mcpServers(options.mcpUrl, options.mcpToken);
      if (options.resume !== undefined) {
        await session.request(OPEN, "session/load", { sessionId: options.resume, cwd: options.cwd, mcpServers: servers, _meta: meta });
        session.named(options.resume);
      } else {
        const opened = await session.request(OPEN, "session/new", { cwd: options.cwd, mcpServers: servers, _meta: meta });
        const id = opened?.result?.sessionId;
        if (typeof id !== "string" || id === "") throw new Error("Grok Build named no session");
        session.named(id);
      }
    } catch (error) {
      await session.dispose();
      throw error;
    }
    return session;
  }

  async adopt(options: OpenOptions, snapshot: unknown | null, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const handed = snapshot as GrokSnapshot | null;
    const id = handed?.runner ?? runnerId("grok", options.key);
    const info = findRunner(this.data, id);
    if (!info) throw new Error(`no runner keeps grok for ${options.key}`);
    let session: GrokSession;
    if (handed) {
      log.info("agents::grok", "taking up a grok process handed over", { session: handed.id, pgid: info.pgid, busy: handed.turn.busy });
      session = new GrokSession(this, handed.id, { ...handed.turn, closed: false }, new LiveFromAcp(handed.live), events, options.profile.home);
      session.toolsUrl = handed.tools;
    } else {
      // The previous station crashed: what it had handled is read again, silently, to know the session and where the
      // turn stands; the rest comes as it would have.
      const at = await ackedOffset(info, outFile(this.data, id));
      const turn: Turn = { busy: false, aborting: false, closed: false };
      const live = new LiveFromAcp();
      let sessionId = options.resume ?? "";
      for (const line of linesBefore(outFile(this.data, id), at)) {
        const message = parse(line);
        if (message === undefined) continue;
        if (message.id === OPEN && typeof message.result?.sessionId === "string") sessionId = message.result.sessionId;
        if (message.method === "session/update" && (sessionId === "" || message.params?.sessionId === sessionId)) {
          turn.busy = true;
          live.feed(message.params?.update);
        } else if (typeof message.id === "string" && message.id.startsWith(PROMPT)) {
          turn.busy = false;
          live.ended();
        }
      }
      log.info("agents::grok", "taking up a grok process after a crash", { session: sessionId, pgid: info.pgid, busy: turn.busy, from: at });
      session = new GrokSession(this, sessionId, turn, live, events, options.profile.home);
      session.toolsUrl = options.mcpUrl;
      // A turn is running that this station did not start.
      if (turn.busy) events({ type: "turnStarted" });
    }
    session.attach(AgentProcess.adopt(info, session.processOptions(`grok ${options.key}`)));
    this.live.add(session);
    return session;
  }

  forget(session: GrokSession) {
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

export class GrokSession implements AgentSession {
  private proc!: AgentProcess;
  private driver: GrokDriver;
  private sessionId: string;
  private turn: Turn;
  private live: LiveFromAcp;
  private events: (event: RuntimeEvent) => void;
  /// Requests of ours waiting for their answer (not prompts: their answer ends the turn).
  private waiting = new Map<string, { resolve: (message: Json) => void; reject: (error: Error) => void }>();
  /// Its calls to the station's tools not answered yet.
  private calls = new Set<string>();
  toolsUrl: string | null = null;
  /// The profile's home (its sessions are in grokHome of it).
  private home: string;

  constructor(driver: GrokDriver, sessionId: string, turn: Turn, live: LiveFromAcp, events: (event: RuntimeEvent) => void, home: string) {
    this.home = home;
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
        resolve: (message) => (message?.error !== undefined ? reject(new Error(`grok ${method}: ${message.error?.message ?? JSON.stringify(message.error)}`)) : resolve(message)),
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
        for (const w of this.waiting.values()) w.reject(new Error(`grok exited (${said})${why}`));
        this.waiting.clear();
        const busy = this.turn.busy;
        this.turn.busy = false;
        if (busy) {
          for (const event of this.live.ended()) this.events({ type: "live", event });
          this.events({ type: "turnEnded", outcome: { kind: "failed", reason: "exited", message: `grok exited (${said}) during the turn${why}` } });
        }
        this.events({ type: "closed", why: `grok exited (${said})${why}` });
        this.driver.forget(this);
      },
    };
  }

  private onMessage(message: Json) {
    const id = message.id;
    if (message.method === "session/update") {
      // A subagent's session says its own steps; the station follows the session it opened.
      if (this.sessionId !== "" && typeof message.params?.sessionId === "string" && message.params.sessionId !== this.sessionId) return;
      const update = message.params?.update;
      for (const event of this.live.feed(update)) this.events({ type: "live", event });
      const lost = this.toolsLost(update);
      if (lost !== null) this.events({ type: "toolsLost", why: lost });
      return;
    }
    if (message.method === "session/request_permission" && id !== undefined) {
      // Nothing is asked here (--always-approve); should it ask, what it would do is allowed, as the other runtimes are.
      const options: Json[] = Array.isArray(message.params?.options) ? message.params.options : [];
      const chosen = options.find((o) => o?.kind === "allow_always") ?? options.find((o) => o?.kind === "allow_once") ?? options.find((o) => String(o?.optionId ?? "").startsWith("allow")) ?? options[0];
      const result = chosen ? { outcome: { outcome: "selected", optionId: chosen.optionId } } : { outcome: { outcome: "cancelled" } };
      this.proc.write(JSON.stringify({ jsonrpc: "2.0", id, result }));
      return;
    }
    if (message.method !== undefined) {
      // A request of its own the station has no answer for (asking the person a question, a plan to approve): what it
      // asks is answered in the chat, not here.
      if (id !== undefined) this.proc.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code: -32601, message: `${message.method} is not supported` } }));
      return;
    }
    if (typeof id === "string" && id.startsWith(PROMPT)) {
      const outcome = this.turn.aborting && message.error !== undefined ? ({ kind: "aborted" } as TurnOutcome) : outcomeOf(message);
      // An answer to a prompt this station did not see start (taken up after a crash just as it was given).
      if (!this.turn.busy) this.events({ type: "turnStarted" });
      this.turn.busy = false;
      this.turn.aborting = false;
      this.keepUsage(message);
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

  /// The turn's usage, beside its transcript (none for a turn that made no call).
  private keepUsage(answer: Json) {
    const line = usageLine(answer, wall.now());
    const dir = sessionDir(this.home, this.sessionId);
    if (line === null || dir === null) return;
    try {
      appendFileSync(join(dir, USAGE), `${line}\n`);
    } catch (e) {
      log.warn("agents::grok", "a turn's usage was not kept", { session: this.sessionId, error: (e as Error).message });
    }
  }

  /// What an update says of the station's tools being out of reach (null: nothing): a call to one of them failed as
  /// unreachable.
  private toolsLost(update: Json): string | null {
    const kind = update?.sessionUpdate;
    const callId = typeof update?.toolCallId === "string" ? update.toolCallId : undefined;
    if (callId === undefined) return null;
    const named = `${String(update.title ?? "")} ${String(update._meta?.["x.ai/tool"]?.name ?? "")} ${String(update.rawInput?.tool_name ?? "")}`;
    if (kind === "tool_call" && TOOL_SERVERS.some((s) => named.includes(s))) this.calls.add(callId);
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
    if (this.turn.closed) throw new Error("grok session is closed");
    if (this.turn.busy) throw new Error("a turn is already running");
    this.turn.busy = true;
    for (const event of this.live.prompted()) this.events({ type: "live", event });
    this.proc.write(rpc(`${PROMPT}${uuid()}`, "session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text }] }));
  }

  /// Into the running turn, read at its next safe point (after the tool call it is in). Not when nothing runs: Grok
  /// Build would make it a turn of its own, which the station starts itself.
  async steer(text: string) {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return false;
    try {
      const answer = await this.request(`${STEER}${uuid()}`, "_x.ai/interject", { sessionId: this.sessionId, text });
      return answer?.result?.status === "queued" || answer?.result !== undefined;
    } catch (e) {
      log.warn("agents::grok", "a message could not go into the running turn", { session: this.sessionId, error: (e as Error).message });
      return false;
    }
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
    for (const w of this.waiting.values()) w.reject(new Error("grok session is closed"));
    this.waiting.clear();
    await this.proc.kill(5000);
  }

  snapshot(): GrokSnapshot {
    this.proc.freeze();
    this.turn.closed = true;
    return { runtime: "grok", id: this.sessionId, runner: this.proc.info.id, turn: { busy: this.turn.busy, aborting: this.turn.aborting }, tools: this.toolsUrl, live: this.live.state() };
  }

  detach() {
    this.turn.closed = true;
    this.driver.forget(this);
    this.proc.detach();
  }
}
