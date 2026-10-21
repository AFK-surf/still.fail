// Devin driver: one `devin acp` per session (Cognition's Devin CLI, its local agent), under a runner whose id comes from
// the session key, spoken to in ACP (Agent Client Protocol, JSON-RPC over stdio) with one ACP session in it.
//
// Behaviour pinned against the Devin CLI 3000.11 (docs/devin.md):
// - `authenticate` with the profile's key (`_meta.api_key`, read from the credentials its sign-in left in the profile's
//   home), not the CLI's own sign-in on this machine;
// - `session/new` names the session; `session/load` takes up one it keeps (its store: DEVIN_SESSIONS_DIR), saying the
//   session's past again as updates before it is answered: not a turn, not kept again;
// - `session/prompt` is answered when the turn is over: `stopReason` (`cancelled` after `session/cancel`), or an error
//   whose message says why it failed; a prompt given while a turn runs goes into that turn, read at its next step (a
//   command running then goes on), and is answered with it;
// - what the model says streams in `session/update`s (agent_message_chunk, agent_thought_chunk), tool calls as tool_call
//   then tool_call_update (its name `_meta["cognition.ai/inferenceToolName"]`, an MCP tool's mcp__<server>__<tool>);
//   `usage_update` says each model call's counts, the context and the model's window;
// - the session runs in Bypass Permissions (`mode`); a model is a family and a thinking level (`swe-2`, `high`), the
//   process's `--model <family>-<level>`, changed between turns with the `model` and `thought_level` config options; the
//   station's tools an HTTP MCP server given to `session/new`/`session/load` (their tools listed by the model when it
//   needs them), its instructions, memory and skills a folder of the session's own given as another workspace directory
//   (its AGENTS.md and .devin/ read as a project's);
// - Devin keeps its sessions in a database of its own: the driver keeps the transcript itself (<sessions>/<id>.jsonl,
//   as Cursor's), which the history and the usage read.
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { linkSync } from "../ops/links.ts";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { LiveFromAcp, acpCall, chars, type AcpLiveState } from "./live.ts";
import { AgentProcess, ackedOffset, debug, findRunner, linesBefore, outFile, runnerId } from "./process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { TOOL_SERVERS, cleanEnv, unreachable, uuid, type AgentDriver, type AgentSession, type FailureReason, type OpenOptions, type RuntimeEvent, type TurnOutcome } from "./runtime.ts";

type Json = any;

/// Inherited variables that would let a session use another account, backend or store than its profile's.
const SCRUBBED = ["WINDSURF_API_KEY", "WINDSURF_API_SERVER_URL", "DEVIN_API_URL", "DEVIN_WEBAPP_URL", "DEVIN_MODEL", "DEVIN_SESSIONS_DIR", "DEVIN_PERMISSION_MODE", "DEVIN_SANDBOX", "ACP_BACKEND"];
/// What Devin keeps of a profile, in its home: the sign-in (data/, its XDG_DATA_HOME when signing in: accounts/login.ts),
/// the configuration the station gives it, the sessions (shared by every profile that runs Devin: agent-home.ts links
/// them), the folders of the station's instructions.
export const devinHome = (home: string) => join(home, "devin");
export const devinData = (home: string) => join(devinHome(home), "data");
export const SESSIONS = "sessions";
/// Devin's own store of its sessions, in the shared sessions: any profile can take one up.
export const STORE = "store";

/// The ids of the requests the station makes: a prompt's carry their own, so whatever answers one (after a crash too)
/// ends the turn.
const INIT = "init";
const AUTH = "auth";
const OPEN = "open";
const PROMPT = "prompt:";
const STEER = "steer:";

/// The key the profile's sign-in left (`devin auth login` writes credentials.toml in its data directory), null when it
/// has none.
export function devinKey(home: string): string | null {
  try {
    const text = readFileSync(join(devinData(home), "devin", "credentials.toml"), "utf8");
    const m = /^\s*windsurf_api_key\s*=\s*"([^"]+)"/m.exec(text);
    return m ? m[1]! : null;
  } catch {
    return null;
  }
}

/// The configuration Devin is started with (`--config`): not the person's other tools' rules, MCP servers and skills,
/// nor their Devin Cloud's; no updating itself (the station does: updates/runtimes.ts).
export const CONFIG = {
  read_config_from: { cursor: false, windsurf: false, claude: false, opencode: false, zed: false, copilot: false, cloud: false },
  auto_update: false,
  typewriter: false,
};

/// The station's instructions as Devin is given them: with how its tools are reached there (an MCP server's are listed
/// by the model before it calls one), so that no turn spends a step looking for them.
export const devinRules = (instructions: string) =>
  `${instructions}${instructions === "" ? "" : "\n\n"}The station's tools (chat_post, chat_state and the others named in these instructions) are the stillfail MCP server's: call one by its name (mcp__stillfail__chat_post and so on) without listing the server's tools first.`;

/// The station's instructions as the rules of a folder of the session's own, beside its working directory, with the
/// shared memory (AGENTS.md) and skills (.devin/skills) linked in: Devin reads a workspace directory it is given as a
/// project's, without them being written into the person's project.
export function rulesFolder(home: string, key: string, instructions: string): string {
  const dir = join(devinHome(home), "station", createHash("sha256").update(key).digest("hex").slice(0, 16));
  mkdirSync(join(dir, ".devin", "rules"), { recursive: true });
  writeFileSync(join(dir, ".devin", "rules", "stillfail.md"), `---\ndescription: still.fail station\ntrigger: always_on\n---\n${devinRules(instructions)}\n`);
  const linked = (target: string, path: string) => {
    if (!existsSync(target)) return;
    rmSync(path, { recursive: true, force: true });
    try {
      // Where links are refused (Windows without Developer Mode), the skills' a junction and the memory a copy.
      linkSync(target, path, { junction: true, copy: true });
    } catch (e) {
      log.warn("agents::devin", "the shared memory or skills not linked for Devin", { path, error: (e as Error).message });
    }
  };
  // The profile home's AGENTS.md and skills/ are the station's shared memory and skills (agent-home.ts).
  linked(join(home, "AGENTS.md"), join(dir, "AGENTS.md"));
  linked(join(home, "skills"), join(dir, ".devin", "skills"));
  return dir;
}

/// The thinking levels Devin's models are offered at (the last part of a variant's name: swe-2-high).
export const LEVELS = ["none", "minimal", "low", "medium", "high", "xhigh", "max"];

/// A model and level as Devin names the variant: `swe-2` at `high` is swe-2-high (it takes a family alone at its
/// default level).
export const variant = (model: string, effort: string | undefined) => (effort !== undefined && LEVELS.includes(effort) ? `${model}-${effort}` : model);

/// The models `devin models list --format json` lists, as the station offers them: a family at its thinking levels
/// (swe-2: medium, high, max), each variant that is not one at a level a model of its own; not the faster or
/// prioritised ones of a variant (-fast, -priority, -lightning: billed apart).
export function devinCatalog(listed: Json): { models: string[]; efforts: Record<string, string[]> } {
  const models: string[] = [];
  const efforts: Record<string, string[]> = {};
  for (const family of Array.isArray(listed?.families) ? listed.families : []) {
    for (const v of Array.isArray(family?.variants) ? family.variants : []) {
      const uid = typeof v?.model_uid === "string" ? v.model_uid : "";
      if (uid === "" || /-(fast|priority|lightning)$/.test(uid)) continue;
      const level = LEVELS.find((l) => uid.endsWith(`-${l}`));
      const model = level === undefined ? uid : uid.slice(0, -level.length - 1);
      if (!models.includes(model)) models.push(model);
      if (level !== undefined) (efforts[model] ??= []).push(level);
    }
  }
  for (const levels of Object.values(efforts)) levels.sort((a, b) => LEVELS.indexOf(a) - LEVELS.indexOf(b));
  return { models, efforts };
}

/// What failed a turn, from what Devin said of it.
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

/// A model call's counts as Devin says them (a usage_update's), as the transcript keeps them: Cursor's names, input apart
/// from the cache's read (Devin says no cache written).
export function callOf(update: Json): { inputTokens: number; cacheReadTokens: number; cacheWriteTokens: number; outputTokens: number } {
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  const meta = update?._meta ?? {};
  const read = n(meta["cognition.ai/cachedReadTokens"]);
  return { inputTokens: Math.max(0, n(meta["cognition.ai/inputTokens"]) - read), cacheReadTokens: read, cacheWriteTokens: 0, outputTokens: n(meta["cognition.ai/outputTokens"]) };
}

/// The turn as its handled lines leave it.
export type Turn = { busy: boolean; aborting: boolean; closed: boolean };

/// A session as a next station takes it up.
export type DevinSnapshot = { runtime: "devin"; id: string; runner: string; turn: { busy: boolean; aborting: boolean }; tools: string | null; live: AcpLiveState; model: string | null; owner: string | null; steering: string[]; families: string[] };

export type DevinDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

const parse = (line: string): Json | undefined => {
  try {
    return JSON.parse(line);
  } catch {
    debug("agents::devin", "devin non-json line", { line: line.slice(0, 500) });
    return undefined;
  }
};

const rpc = (id: string, method: string, params: Json) => JSON.stringify({ jsonrpc: "2.0", id, method, params });

/// The station's tools as ACP gives an MCP server.
const mcpServers = (url: string, token: string) => [{ type: "http", name: "stillfail", url, headers: [{ name: "Authorization", value: `Bearer ${token}` }] }];

/// The process's arguments: the station's configuration, the ACP server, its model.
export function devinArgs(config: string, model: string | undefined, effort: string | undefined): string[] {
  const args = ["--config", config, "acp"];
  if (model !== undefined) args.push("--model", variant(model, effort));
  return args;
}

/// Its environment: its sessions' store in the shared sessions; no key of anyone else's.
export function devinEnv(options: OpenOptions): Record<string, string> {
  const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "devin"), options.route) };
  env.DEVIN_SESSIONS_DIR = join(devinHome(options.profile.home), SESSIONS, STORE);
  env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
  return env;
}

export class DevinDriver implements AgentDriver {
  private readonly data: string;
  private readonly command: string;
  private live = new Set<DevinSession>();

  constructor(options: DevinDriverOptions) {
    this.data = options.data;
    this.command = options.command ?? "devin";
  }

  runtime(): "devin" {
    return "devin";
  }

  async open(options: OpenOptions, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const home = options.profile.home;
    const sessions = join(devinHome(home), SESSIONS);
    mkdirSync(join(sessions, STORE), { recursive: true });
    if (options.resume !== undefined && !existsSync(join(sessions, `${options.resume}.jsonl`))) {
      // Not one the station kept: failing here lets the caller start fresh.
      throw new Error(`no Devin session ${options.resume}`);
    }
    const config = join(devinHome(home), "config.json");
    writeFileSync(config, `${JSON.stringify(CONFIG, null, 2)}\n`);
    const rules = rulesFolder(home, options.key, options.instructions);
    const model = options.model ?? profileModel(options.profile);
    const session = new DevinSession(this, "", { busy: false, aborting: false, closed: false }, new LiveFromAcp(), events, sessions, model ?? null);
    session.toolsUrl = options.mcpUrl;
    session.attach(await AgentProcess.start(this.data, runnerId("devin", options.key), this.command, devinArgs(config, model, options.effort), devinEnv(options), options.cwd, session.processOptions(`devin ${options.key}`)));
    this.live.add(session);
    try {
      await session.request(INIT, "initialize", { protocolVersion: 1, clientCapabilities: {}, clientInfo: { name: "still.fail", version: "1" } });
      // The profile's sign-in; custom variables bring their own (WINDSURF_API_KEY).
      const key = devinKey(home);
      if (key !== null) await session.request(AUTH, "authenticate", { methodId: "devin-browser", _meta: { api_key: key } });
      const servers = mcpServers(options.mcpUrl, options.mcpToken);
      const opening = { cwd: options.cwd, mcpServers: servers, additionalDirectories: [rules] };
      if (options.resume !== undefined) {
        session.named(options.resume);
        const loaded = await session.request(OPEN, "session/load", { sessionId: options.resume, ...opening });
        session.models(loaded?.result?.configOptions);
      } else {
        const opened = await session.request(OPEN, "session/new", opening);
        const id = opened?.result?.sessionId;
        if (typeof id !== "string" || id === "") throw new Error("Devin named no session");
        session.named(id);
        session.models(opened?.result?.configOptions);
        session.keep({ type: "session", id, cwd: options.cwd });
      }
      session.opened();
      // No approvals, as the other runtimes run here.
      await session.request(`config:${uuid()}`, "session/set_config_option", { sessionId: session.id(), configId: "mode", value: "bypass" });
    } catch (error) {
      await session.dispose();
      throw error;
    }
    return session;
  }

  async adopt(options: OpenOptions, snapshot: unknown | null, events: (event: RuntimeEvent) => void): Promise<AgentSession> {
    const handed = snapshot as DevinSnapshot | null;
    const id = handed?.runner ?? runnerId("devin", options.key);
    const info = findRunner(this.data, id);
    if (!info) throw new Error(`no runner keeps devin for ${options.key}`);
    const sessions = join(devinHome(options.profile.home), SESSIONS);
    let session: DevinSession;
    if (handed) {
      log.info("agents::devin", "taking up a devin process handed over", { session: handed.id, pgid: info.pgid, busy: handed.turn.busy });
      session = new DevinSession(this, handed.id, { ...handed.turn, closed: false }, new LiveFromAcp(handed.live), events, sessions, handed.model);
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
      for (const line of linesBefore(outFile(this.data, id), at)) {
        const message = parse(line);
        if (message === undefined) continue;
        if (message.id === OPEN) {
          open = true;
          if (typeof message.result?.sessionId === "string") sessionId = message.result.sessionId;
        } else if (open && message.method === "session/update" && message.params?.sessionId === sessionId && turnStep(message.params?.update)) {
          turn.busy = true;
          live.feed(message.params?.update);
        } else if (typeof message.id === "string" && (message.id.startsWith(PROMPT) || message.id.startsWith(STEER))) {
          turn.busy = false;
          live.ended();
        }
      }
      log.info("agents::devin", "taking up a devin process after a crash", { session: sessionId, pgid: info.pgid, busy: turn.busy, from: at });
      session = new DevinSession(this, sessionId, turn, live, events, sessions, options.model ?? profileModel(options.profile) ?? null);
      session.toolsUrl = options.mcpUrl;
      session.opened();
      // A turn is running that this station did not start: what answers a prompt next ends it.
      if (turn.busy) events({ type: "turnStarted" });
    }
    session.attach(AgentProcess.adopt(info, session.processOptions(`devin ${options.key}`)));
    this.live.add(session);
    return session;
  }

  forget(session: DevinSession) {
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

/// Whether an update is a step of a turn (what the model says or does), not what Devin says of the session.
const turnStep = (update: Json) => ["agent_message_chunk", "agent_thought_chunk", "tool_call", "tool_call_update"].includes(update?.sessionUpdate);

/// What the transcript keeps of what is being said: the step's kind and its text so far.
type Said = { type: "assistant" | "thinking"; text: string };

export class DevinSession implements AgentSession {
  private proc!: AgentProcess;
  private driver: DevinDriver;
  private sessionId: string;
  private turn: Turn;
  private live: LiveFromAcp;
  private events: (event: RuntimeEvent) => void;
  /// Requests of ours waiting for their answer (not prompts: their answer ends the turn).
  private waiting = new Map<string, { resolve: (message: Json) => void; reject: (error: Error) => void }>();
  /// Its calls to the station's tools not answered yet.
  private calls = new Set<string>();
  /// Where the transcript is kept (the shared sessions).
  private sessions: string;
  /// The model its turns run on (a family, or the variant Devin said), null when not said.
  private model: string | null;
  /// The `model` config option's values (a family's variant each): what another model between turns is set to.
  private families: string[] = [];
  /// Until the session is open: what session/load says again of its past is not a turn.
  private loading = true;
  /// The prompt whose answer ends the turn (ours, or a message put in a turn that had just ended, which became one), and
  /// the messages put in the running turn, not answered yet.
  private owner: string | null = null;
  private steering = new Set<string>();
  /// What is being said, kept whole when something else comes; the calls under way, kept when they are done.
  private said: Said | null = null;
  private open = new Map<string, { name: string; input: Json }>();
  /// The turn's counts so far (each model call's, as usage_update says them once and again), the context its last call
  /// had and the model's window.
  private usage: { calls: number; counts: ReturnType<typeof callOf>; context: number; window: number } | null = null;
  private lastCall = "";
  toolsUrl: string | null = null;

  constructor(driver: DevinDriver, sessionId: string, turn: Turn, live: LiveFromAcp, events: (event: RuntimeEvent) => void, sessions: string, model: string | null) {
    this.driver = driver;
    this.sessionId = sessionId;
    this.turn = turn;
    this.live = live;
    this.events = events;
    this.sessions = sessions;
    this.model = model;
  }

  named(id: string) {
    this.sessionId = id;
  }

  opened() {
    this.loading = false;
  }

  /// What the station that handed it over knew besides the turn.
  handed(snapshot: DevinSnapshot) {
    this.loading = false;
    this.owner = snapshot.owner;
    this.steering = new Set(snapshot.steering);
    this.families = snapshot.families;
  }

  attach(proc: AgentProcess) {
    this.proc = proc;
  }

  /// The model its config options say is current, and the values the `model` option takes.
  models(options: Json) {
    const model = (Array.isArray(options) ? options : []).find((o: Json) => o?.id === "model");
    if (!model) return;
    if (Array.isArray(model.options)) this.families = model.options.map((o: Json) => o?.value).filter((v: unknown): v is string => typeof v === "string");
    if (typeof model.currentValue === "string" && model.currentValue !== "" && this.model === null) this.model = model.currentValue;
  }

  /// A line of the transcript (read/transcript.ts reads it as Cursor's).
  keep(line: Json) {
    if (this.sessionId === "") return;
    try {
      appendFileSync(join(this.sessions, `${this.sessionId}.jsonl`), `${JSON.stringify({ time: wall.now(), ...line })}\n`);
    } catch (e) {
      log.warn("agents::devin", "a transcript line was not kept", { session: this.sessionId, error: (e as Error).message });
    }
  }

  /// A request whose answer is waited for: an error answer rejects.
  request(id: string, method: string, params: Json): Promise<Json> {
    return new Promise((resolve, reject) => {
      this.waiting.set(id, {
        resolve: (message) => (message?.error !== undefined ? reject(new Error(`devin ${method}: ${message.error?.message ?? JSON.stringify(message.error)}${typeof message.error?.data === "string" ? `: ${message.error.data}` : ""}`)) : resolve(message)),
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
        for (const w of this.waiting.values()) w.reject(new Error(`devin exited (${said})${why}`));
        this.waiting.clear();
        const busy = this.turn.busy;
        this.turn.busy = false;
        if (busy) {
          this.keepSaid();
          this.keep({ type: "end", status: "error", error: { message: `devin exited (${said})` } });
          for (const event of this.live.ended()) this.events({ type: "live", event });
          this.events({ type: "turnEnded", outcome: { kind: "failed", reason: "exited", message: `devin exited (${said}) during the turn${why}` } });
        }
        this.events({ type: "closed", why: `devin exited (${said})${why}` });
        this.driver.forget(this);
      },
    };
  }

  private onMessage(message: Json) {
    const id = message.id;
    if (message.method === "session/update") {
      // Another session's (a subagent's) steps are not shown; nor the past session/load says again.
      if (this.loading || message.params?.sessionId !== this.sessionId) return;
      const update = message.params?.update;
      if (!this.turn.busy && turnStep(update)) {
        // A message put in the turn as it ended became a turn of its own: its answer ends it.
        const first = [...this.steering][0];
        if (first === undefined) return;
        this.steering.delete(first);
        this.owner = first;
        this.turn.busy = true;
        this.events({ type: "turnStarted" });
      }
      this.transcribe(update);
      for (const event of this.live.feed(update)) this.events({ type: "live", event });
      const lost = this.toolsLost(update);
      if (lost !== null) this.events({ type: "toolsLost", why: lost });
      return;
    }
    if (message.method === "session/request_permission" && id !== undefined) {
      // Nothing is asked in Bypass Permissions; should it ask (an organisation's policy), what it would do is allowed,
      // as the other runtimes are.
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
    if (typeof id === "string" && (id.startsWith(PROMPT) || id.startsWith(STEER))) {
      // A message put in the turn is answered with the turn (before or after its prompt's answer); one whose turn this
      // station did not see the end of (taken up after a crash) ends the turn running now.
      if (this.steering.delete(id)) return;
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
    if (this.usage !== null) this.keep({ type: "usage", run: id.slice(id.indexOf(":") + 1), model: this.model, usage: this.usage.counts, calls: this.usage.calls, context: this.usage.context, window: this.usage.window });
    this.usage = null;
    this.lastCall = "";
    this.keep({ type: "end", status: outcome.kind === "completed" ? "finished" : outcome.kind === "aborted" ? "cancelled" : "error", ...(outcome.kind === "failed" ? { error: { message: outcome.message } } : {}) });
    for (const event of this.live.ended()) this.events({ type: "live", event });
    this.events({ type: "turnEnded", outcome });
  }

  /// What an update adds to the transcript: what was said, whole once something else comes; a call once it is done;
  /// the turn's counts; the model.
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
        const [name, input] = acpCall(String(update._meta?.["cognition.ai/inferenceToolName"] ?? update.title ?? ""), update.rawInput ?? null);
        this.open.set(callId, { name, input });
      }
      const call = this.open.get(callId);
      if (call && (update.status === "completed" || update.status === "failed")) {
        this.open.delete(callId);
        const result = (Array.isArray(update.content) ? update.content : []).map((c: Json) => c?.content?.text ?? c?.text ?? "").filter((t: string) => t !== "").join("\n");
        this.keep({ type: "tool", id: callId, name: call.name, status: update.status === "failed" ? "error" : "completed", args: call.input, result: chars(result, 20_000) });
      }
      return;
    }
    if (kind === "usage_update") {
      // Each call's counts are said twice (the second time as its agent's): counted once.
      const counts = callOf(update);
      const said = JSON.stringify(counts);
      if (said === this.lastCall) return;
      this.lastCall = said;
      const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
      const u = (this.usage ??= { calls: 0, counts: { inputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0 }, context: 0, window: 0 });
      u.calls += 1;
      u.counts.inputTokens += counts.inputTokens;
      u.counts.cacheReadTokens += counts.cacheReadTokens;
      u.counts.outputTokens += counts.outputTokens;
      if (n(update.used) > 0) u.context = n(update.used);
      if (n(update.size) > 0) u.window = n(update.size);
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
    const kind = update?.sessionUpdate;
    const callId = typeof update?.toolCallId === "string" ? update.toolCallId : undefined;
    if (callId === undefined) return null;
    const named = String(update._meta?.["cognition.ai/inferenceToolName"] ?? "");
    if (kind === "tool_call" && TOOL_SERVERS.some((s) => named.startsWith(`mcp__${s}__`))) this.calls.add(callId);
    if ((kind === "tool_call" || kind === "tool_call_update") && update.status === "failed" && this.calls.delete(callId)) {
      const text = (Array.isArray(update.content) ? update.content : []).map((c: Json) => c?.content?.text ?? c?.text ?? "").join("\n");
      if (unreachable(text) || /failed to connect to mcp server/i.test(text)) return chars(text, 300);
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
    if (this.turn.closed) throw new Error("devin session is closed");
    if (this.turn.busy) throw new Error("a turn is already running");
    this.turn.busy = true;
    this.owner = `${PROMPT}${uuid()}`;
    this.keep({ type: "user", text });
    for (const event of this.live.prompted()) this.events({ type: "live", event });
    this.proc.write(rpc(this.owner, "session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text }] }));
  }

  /// Into the running turn, read at its next step: a prompt given while it runs, answered with the turn. Not when
  /// nothing runs: it would be a turn of its own, which the station starts itself.
  async steer(text: string) {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return false;
    const id = `${STEER}${uuid()}`;
    this.steering.add(id);
    this.keepSaid();
    this.keep({ type: "user", text, steered: true });
    this.proc.write(rpc(id, "session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text }] }));
    return true;
  }

  async backgroundTools() {}

  /// Between turns, another model or thinking level is set in the running process (the `model` and `thought_level`
  /// config options), read from its next turn on. False for a model its options do not have.
  retune(options: OpenOptions) {
    if (this.turn.closed || this.turn.busy || this.sessionId === "") return false;
    const model = options.model ?? profileModel(options.profile);
    if (model === undefined) return false;
    // The option of the model's family: its own name, or a variant of it at a level.
    const family = this.families.find((v) => v === model || LEVELS.some((l) => v === `${model}-${l}`));
    if (family === undefined) return false;
    const set = (configId: string, value: string) => this.proc.write(rpc(`config:${uuid()}`, "session/set_config_option", { sessionId: this.sessionId, configId, value }));
    set("model", family);
    if (options.effort !== undefined && LEVELS.includes(options.effort)) set("thought_level", options.effort);
    this.model = model;
    return true;
  }

  async abort() {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return;
    this.turn.aborting = true;
    this.proc.write(JSON.stringify({ jsonrpc: "2.0", method: "session/cancel", params: { sessionId: this.sessionId } }));
  }

  async dispose() {
    this.driver.forget(this);
    this.turn.closed = true;
    for (const w of this.waiting.values()) w.reject(new Error("devin session is closed"));
    this.waiting.clear();
    await this.proc.kill(5000);
  }

  snapshot(): DevinSnapshot {
    this.proc.freeze();
    this.turn.closed = true;
    return {
      runtime: "devin", id: this.sessionId, runner: this.proc.info.id, turn: { busy: this.turn.busy, aborting: this.turn.aborting }, tools: this.toolsUrl, live: this.live.state(), model: this.model,
      owner: this.owner, steering: [...this.steering], families: this.families,
    };
  }

  detach() {
    this.turn.closed = true;
    this.driver.forget(this);
    this.proc.detach();
  }
}
