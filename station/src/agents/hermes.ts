// Hermes Agent over ACP stdio. Session lifecycle and transcript format follow the other ACP drivers.
// See docs/hermes.md for the protocol contract and supported profile setup.
import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { LiveFromAcp, chars, type AcpLiveState } from "./live.ts";
import { AgentProcess, ackedOffset, debug, findRunner, linesBefore, outFile, runnerId } from "./process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { TOOL_SERVERS, cleanEnv, unreachable, uuid, type AgentDriver, type AgentSession, type FailureReason, type OpenOptions, type RuntimeEvent, type TurnOutcome } from "./runtime.ts";

type Json = any;

// Hermes resolves providers from this profile's HERMES_HOME and explicit environment.
const SCRUBBED = ["HERMES_HOME", "HERMES_CONFIG_FILE", "OPENAI_API_KEY", "OPENAI_BASE_URL", "ANTHROPIC_API_KEY", "OPENROUTER_API_KEY", "GEMINI_API_KEY", "GROQ_API_KEY", "DEEPSEEK_API_KEY"];
export const hermesHome = (home: string) => join(home, "hermes");
export const SESSIONS = "sessions";
const INIT = "init";
const OPEN = "open";
const PROMPT = "prompt:";

/// Hermes' ACP title is `<tool_name>: <argument preview>` (acp_adapter/tools.py). The live and transcript readers
/// need the tool's name, notably to recognise chat_post; its arguments remain in rawInput, not in the name.
function hermesUpdate(update: Json): Json {
  if (update?.sessionUpdate !== "tool_call" || typeof update.title !== "string") return update;
  return { ...update, title: update.title.split(": ", 1)[0] };
}

/// What failed a turn, from what Hermes said of it.
export function classifyFailure(text: string): FailureReason {
  const lower = text.toLowerCase();
  const words = lower.split(/[^\p{L}\p{N}_]+/u);
  const word = (w: string) => words.includes(w);
  if (word("401") || word("403") || ["unauthorized", "unauthenticated", "not logged in", "not authenticated", "has not authenticated", "sign in", "log in", "api key", "permission_denied"].some((s) => lower.includes(s))) return "auth";
  if (word("429") || ["rate limit", "rate_limit", "quota", "usage limit", "limit reached", "resource_exhausted", "overloaded", "too many requests"].some((s) => lower.includes(s))) return "rate_limit";
  return "model";
}

/// How a prompt's answer ends the turn.
export function outcomeOf(message: Json): TurnOutcome {
  if (message?.error !== undefined) {
    const text = typeof message.error?.message === "string" ? message.error.message.replace(/^Internal error: /, "") : JSON.stringify(message.error);
    const data = typeof message.error?.data === "string" ? `: ${message.error.data}` : typeof message.error?.data?.message === "string" ? `: ${message.error.data.message}` : "";
    const said = `${text}${data}`;
    return { kind: "failed", reason: classifyFailure(said), message: chars(said, 1000) };
  }
  const stop = message?.result?.stopReason;
  if (stop === "cancelled") return { kind: "aborted" };
  if (stop === "refusal") return { kind: "failed", reason: "model", message: "the model refused" };
  return { kind: "completed" };
}

/// The turn as its handled lines leave it.
export type Turn = { busy: boolean; aborting: boolean; closed: boolean };

/// A session as a next station takes it up.
export type HermesSnapshot = { runtime: "hermes"; id: string; runner: string; turn: { busy: boolean; aborting: boolean }; tools: string | null; live: AcpLiveState; model: string | null; owner: string | null; said: Said | null; calls: [string, { name: string; input: Json }][] };

export type HermesDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

const parse = (line: string): Json | undefined => {
  try {
    return JSON.parse(line);
  } catch {
    debug("agents::hermes", "hermes non-json line", { line: line.slice(0, 500) });
    return undefined;
  }
};

const rpc = (id: string, method: string, params: Json) => JSON.stringify({ jsonrpc: "2.0", id, method, params });

/// The station's tools as ACP gives an MCP server.
const mcpServers = (url: string, token: string) => [{ type: "http", name: "stillfail", url, headers: [{ name: "Authorization", value: `Bearer ${token}` }] }];

export function hermesEnv(options: OpenOptions): Record<string, string> {
  const env = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "hermes"), options.route) };
  env.HERMES_HOME = hermesHome(options.profile.home);
  env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
  return env;
}

export class HermesDriver implements AgentDriver {
  private readonly data: string;
  private readonly command: string;
  private live = new Set<HermesSession>();

  constructor(options: HermesDriverOptions) {
    this.data = options.data;
    this.command = options.command ?? "hermes";
  }

  runtime(): "hermes" {
    return "hermes";
  }

  async open(options: OpenOptions, events: (event: RuntimeEvent) => void): Promise<HermesSession> {
    if (options.resume !== undefined && !/^[a-zA-Z0-9_-]+$/.test(options.resume)) throw new Error("invalid Hermes session id");
    const home = options.profile.home;
    const sessions = join(hermesHome(home), SESSIONS);
    mkdirSync(sessions, { recursive: true });
    if (options.resume !== undefined && !existsSync(join(sessions, `${options.resume}.jsonl`))) {
      // Not one the station kept: failing here lets the caller start fresh.
      throw new Error(`no Hermes session ${options.resume}`);
    }
    const model = options.model ?? profileModel(options.profile);
    const session = new HermesSession(this, "", { busy: false, aborting: false, closed: false }, new LiveFromAcp(), events, sessions, model ?? null);
    session.toolsUrl = options.mcpUrl;
    session.instructions = options.instructions;
    session.attach(await AgentProcess.start(this.data, runnerId("hermes", options.key), this.command, ["acp"], hermesEnv(options), options.cwd, session.processOptions(`hermes ${options.key}`)));
    this.live.add(session);
    try {
      const initialized = await session.request(INIT, "initialize", { protocolVersion: 1, clientCapabilities: {}, clientInfo: { name: "still.fail", version: "1" } });
      // Older ACP adapters omit completion updates for tools invoked through Hermes' discovery bridge.
      // That loses their results and disconnection signals; require the adapter that reports both ends of a call.
      const version = /^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(initialized.result?.agentInfo?.version ?? "");
      if (!version || (+version[1] === 0 && (+version[2] < 21 || (+version[2] === 21 && +version[3] < 7)))) {
        throw new Error("Hermes Agent 需要 0.21.7 或更新版本；请先更新 Hermes，再重试。");
      }
      const servers = mcpServers(options.mcpUrl, options.mcpToken);
      const opening = { cwd: options.cwd, mcpServers: servers };
      if (options.resume !== undefined) {
        session.named(options.resume);
        await session.request(OPEN, "session/load", { sessionId: options.resume, ...opening });
      } else {
        const opened = await session.request(OPEN, "session/new", opening);
        const id = opened?.result?.sessionId;
        if (typeof id !== "string" || id === "") throw new Error("Hermes named no session");
        session.named(id);
        session.keep({ type: "session", id, cwd: options.cwd });
      }
      session.opened();
      if (model !== undefined) await session.request(`model:${uuid()}`, "session/set_model", { sessionId: session.id(), modelId: model });
    } catch (error) {
      await session.dispose();
      throw error;
    }
    return session;
  }

  async adopt(options: OpenOptions, snapshot: unknown | null, events: (event: RuntimeEvent) => void): Promise<HermesSession> {
    const handed = snapshot as HermesSnapshot | null;
    const id = handed?.runner ?? runnerId("hermes", options.key);
    const info = findRunner(this.data, id);
    if (!info) throw new Error(`no runner keeps hermes for ${options.key}`);
    const sessions = join(hermesHome(options.profile.home), SESSIONS);
    let session: HermesSession;
    if (handed) {
      log.info("agents::hermes", "taking up a hermes process handed over", { session: handed.id, pgid: info.pgid, busy: handed.turn.busy });
      session = new HermesSession(this, handed.id, { ...handed.turn, closed: false }, new LiveFromAcp(handed.live), events, sessions, handed.model);
      session.toolsUrl = handed.tools;
      session.handed(handed);
    } else {
      // The previous station crashed: what it had handled is read again, silently, to know the session and where the
      // turn stands; the rest comes as it would have.
      const at = await ackedOffset(info, outFile(this.data, id));
      const turn: Turn = { busy: false, aborting: false, closed: false };
      const live = new LiveFromAcp();
      let sessionId = options.resume ?? "";
      let open = false;
      let partial: Json[] = [];
      for (const line of linesBefore(outFile(this.data, id), at)) {
        const message = parse(line);
        if (message === undefined) continue;
        if (message.id === OPEN) {
          open = true;
          if (typeof message.result?.sessionId === "string") sessionId = message.result.sessionId;
        } else if (open && message.method === "session/update" && message.params?.sessionId === sessionId && turnStep(message.params?.update)) {
          turn.busy = true;
          const update = hermesUpdate(message.params?.update);
          live.feed(update);
          partial.push(update);
        } else if (typeof message.id === "string" && message.id.startsWith(PROMPT)) {
          turn.busy = false;
          live.ended();
          partial = [];
        }
      }
      log.info("agents::hermes", "taking up a hermes process after a crash", { session: sessionId, pgid: info.pgid, busy: turn.busy, from: at });
      session = new HermesSession(this, sessionId, turn, live, events, sessions, options.model ?? profileModel(options.profile) ?? null);
      session.toolsUrl = options.mcpUrl;
      session.opened();
      session.recoverPartial(partial);
      // A turn is running that this station did not start: what answers a prompt next ends it.
      if (turn.busy) events({ type: "turnStarted" });
    }
    session.instructions = options.instructions;
    session.attach(AgentProcess.adopt(info, session.processOptions(`hermes ${options.key}`)));
    this.live.add(session);
    return session;
  }

  forget(session: HermesSession) {
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

/// Whether an update is a step of a turn (what the model says or does), not what Hermes says of the session.
const turnStep = (update: Json) => ["agent_message_chunk", "agent_thought_chunk", "tool_call", "tool_call_update"].includes(update?.sessionUpdate);

/// What the transcript keeps of what is being said: the step's kind and its text so far.
type Said = { type: "assistant" | "thinking"; text: string };

export class HermesSession implements AgentSession {
  private proc!: AgentProcess;
  private driver: HermesDriver;
  private sessionId: string;
  private turn: Turn;
  private live: LiveFromAcp;
  private events: (event: RuntimeEvent) => void;
  /// Requests of ours waiting for their answer (not prompts: their answer ends the turn).
  private waiting = new Map<string, { resolve: (message: Json) => void; reject: (error: Error) => void }>();
  /// Where the transcript is kept (the shared sessions).
  private sessions: string;
  /// The selected Hermes model, null when using its configured default.
  private model: string | null;
  /// Until the session is open: what session/load says again of its past is not a turn.
  private loading = true;
  /// The prompt whose answer ends the turn.
  private owner: string | null = null;
  /// What is being said, kept whole when something else comes; the calls under way, kept when they are done.
  private said: Said | null = null;
  private recovering = false;
  private open = new Map<string, { name: string; input: Json }>();
  toolsUrl: string | null = null;
  instructions = "";

  constructor(driver: HermesDriver, sessionId: string, turn: Turn, live: LiveFromAcp, events: (event: RuntimeEvent) => void, sessions: string, model: string | null) {
    this.driver = driver;
    this.sessionId = sessionId;
    this.turn = turn;
    this.live = live;
    this.events = events;
    this.sessions = sessions;
    this.model = model;
  }

  named(id: string) {
    if (!/^[a-zA-Z0-9_-]+$/.test(id)) throw new Error("invalid Hermes session id");
    this.sessionId = id;
  }

  opened() {
    this.loading = false;
  }

  /// What the station that handed it over knew besides the turn.
  handed(snapshot: HermesSnapshot) {
    this.loading = false;
    this.owner = snapshot.owner;
    this.said = snapshot.said;
    this.open = new Map(snapshot.calls);
  }

  attach(proc: AgentProcess) {
    this.proc = proc;
  }

  /// Rebuild only the unfinished text/tool records from acknowledged output; completed records are already on disk.
  recoverPartial(updates: Json[]) {
    this.recovering = true;
    try { for (const update of updates) this.transcribe(update); }
    finally { this.recovering = false; }
  }

  /// A line of the transcript (read/transcript.ts reads it as Cursor's).
  keep(line: Json) {
    if (this.sessionId === "" || this.recovering) return;
    try {
      appendFileSync(join(this.sessions, `${this.sessionId}.jsonl`), `${JSON.stringify({ time: wall.now(), ...line })}\n`);
    } catch (e) {
      log.warn("agents::hermes", "a transcript line was not kept", { session: this.sessionId, error: (e as Error).message });
    }
  }

  /// A request whose answer is waited for: an error answer rejects.
  request(id: string, method: string, params: Json): Promise<Json> {
    return new Promise((resolve, reject) => {
      const cancel = wall.after(60_000, () => { this.waiting.delete(id); reject(new Error(`hermes ${method} timed out`)); });
      this.waiting.set(id, {
        resolve: (message) => (cancel(), message?.error !== undefined ? reject(new Error(`hermes ${method}: ${message.error?.message ?? JSON.stringify(message.error)}${typeof message.error?.data === "string" ? `: ${message.error.data}` : ""}`)) : resolve(message)),
        reject: (error) => { cancel(); reject(error); },
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
        for (const w of this.waiting.values()) w.reject(new Error(`hermes exited (${said})${why}`));
        this.waiting.clear();
        const busy = this.turn.busy;
        this.turn.busy = false;
        if (busy) {
          this.keepSaid();
          this.keep({ type: "end", status: "error", error: { message: `hermes exited (${said})` } });
          for (const event of this.live.ended()) this.events({ type: "live", event });
          this.events({ type: "turnEnded", outcome: { kind: "failed", reason: "exited", message: `hermes exited (${said}) during the turn${why}` } });
        }
        this.events({ type: "closed", why: `hermes exited (${said})${why}` });
        this.driver.forget(this);
      },
    };
  }

  private onMessage(message: Json) {
    const id = message.id;
    if (message.method === "session/update") {
      // Another session's (a subagent's) steps are not shown; nor the past session/load says again.
      if (this.loading || message.params?.sessionId !== this.sessionId) return;
      const update = hermesUpdate(message.params?.update);
      // Read the open call before transcribe removes a completed one; this same map survives handover and crash.
      const lost = this.toolsLost(update);
      this.transcribe(update);
      for (const event of this.live.feed(update)) this.events({ type: "live", event });
      if (lost !== null) this.events({ type: "toolsLost", why: lost });
      return;
    }
    if (message.method === "session/request_permission" && id !== undefined) {
      // Allow this call once, as the station runs its other agents unattended. Never persist an allowlist entry.
      const options: Json[] = Array.isArray(message.params?.options) ? message.params.options : [];
      const chosen = options.find((o) => o?.kind === "allow_once");
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
      // The answer to the outstanding prompt ends this turn, including after adoption.
      if (this.owner !== null && id !== this.owner) return;
      this.end(id, message);
      return;
    }
    const waiting = typeof id === "string" ? this.waiting.get(id) : undefined;
    if (waiting) {
      this.waiting.delete(id);
      waiting.resolve(message);
    }
  }

  /// The turn ended as the answer to its prompt says.
  private end(id: string, message: Json) {
    const outcome = this.turn.aborting && message.error !== undefined ? ({ kind: "aborted" } as TurnOutcome) : outcomeOf(message);
    // An answer to a prompt this station did not see start (taken up after a crash just as it was given).
    if (!this.turn.busy) this.events({ type: "turnStarted" });
    this.turn.busy = false;
    this.turn.aborting = false;
    this.owner = null;
    this.keepSaid();
    this.open.clear();
    this.keep({ type: "end", status: outcome.kind === "completed" ? "finished" : outcome.kind === "aborted" ? "cancelled" : "error", ...(outcome.kind === "failed" ? { error: { message: outcome.message } } : {}) });
    for (const event of this.live.ended()) this.events({ type: "live", event });
    this.events({ type: "turnEnded", outcome });
  }

  /// What an update adds to the transcript: what was said, whole once something else comes; a call once it is done;
  /// only completed tool calls are written.
  private transcribe(update: Json) {
    const kind = update?.sessionUpdate;
    if (kind === "agent_message_chunk" || kind === "agent_thought_chunk") {
      const type = kind === "agent_message_chunk" ? "assistant" : "thinking";
      const text = typeof update.content?.text === "string" ? update.content.text : "";
      if (this.said !== null && this.said.type !== type) this.keepSaid();
      this.said ??= { type, text: "" };
      this.said.text += text;
      return;
    }
    if (kind === "tool_call" || kind === "tool_call_update") {
      const callId = typeof update.toolCallId === "string" ? update.toolCallId : null;
      if (callId === null) return;
      this.keepSaid();
      if (kind === "tool_call" && !this.open.has(callId)) {
        this.open.set(callId, { name: String(update.title ?? ""), input: update.rawInput ?? null });
      }
      const call = this.open.get(callId);
      if (call && (update.status === "completed" || update.status === "failed")) {
        this.open.delete(callId);
        const result = (Array.isArray(update.content) ? update.content : []).map((c: Json) => c?.content?.text ?? c?.text ?? "").filter((t: string) => t !== "").join("\n");
        this.keep({ type: "tool", id: callId, name: call.name, status: update.status === "failed" ? "error" : "completed", args: call.input, result: chars(result, 20_000) });
      }
      return;
    }
  }

  /// What was being said, into the transcript.
  private keepSaid() {
    if (this.said === null) return;
    if (this.said.text.trim() !== "") this.keep({ type: this.said.type, text: this.said.text });
    this.said = null;
  }

  /// What an update says of the station's tools being out of reach (null: nothing): a call to one of them failed as
  /// unreachable.
  private toolsLost(update: Json): string | null {
    const callId = typeof update?.toolCallId === "string" ? update.toolCallId : undefined;
    if (callId === undefined) return null;
    const named = this.open.get(callId)?.name ?? String(update.title ?? "");
    if (update.status === "failed" && TOOL_SERVERS.some((s) => named.startsWith(`mcp__${s}__`))) {
      const text = (Array.isArray(update.content) ? update.content : []).map((c: Json) => c?.content?.text ?? c?.text ?? "").join("\n");
      if (unreachable(text) || /failed to connect to mcp server/i.test(text)) return chars(text, 300);
    }
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
    if (this.turn.closed) throw new Error("hermes session is closed");
    if (this.turn.busy) throw new Error("a turn is already running");
    this.turn.busy = true;
    this.owner = `${PROMPT}${uuid()}`;
    this.keep({ type: "user", text });
    for (const event of this.live.prompted()) this.events({ type: "live", event });
    this.proc.write(rpc(this.owner, "session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text: this.instructions ? `<stillfail-context>\n${this.instructions}\n</stillfail-context>\n\n${text}` : text }] }));
  }

  // Hermes may queue concurrent prompts as independent turns; let the station queue them instead.
  async steer(_text: string) { return false; }
  async backgroundTools() {}

  async abort() {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return;
    this.turn.aborting = true;
    this.proc.write(JSON.stringify({ jsonrpc: "2.0", method: "session/cancel", params: { sessionId: this.sessionId } }));
  }

  async dispose() {
    this.driver.forget(this);
    this.turn.closed = true;
    for (const w of this.waiting.values()) w.reject(new Error("hermes session is closed"));
    this.waiting.clear();
    await this.proc.kill(5000);
  }

  snapshot(): HermesSnapshot {
    this.proc.freeze();
    this.turn.closed = true;
    return {
      runtime: "hermes", id: this.sessionId, runner: this.proc.info.id, turn: { busy: this.turn.busy, aborting: this.turn.aborting }, tools: this.toolsUrl, live: this.live.state(), model: this.model,
      owner: this.owner, said: this.said, calls: [...this.open],
    };
  }

  detach() {
    this.turn.closed = true;
    this.driver.forget(this);
    this.proc.detach();
  }
}
