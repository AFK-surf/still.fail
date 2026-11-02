// DeepSeek Harness driver: one `dsh --profile acp` per session, under a runner whose id comes from the session key, with
// the station's own driver plugin in it (./dsh-bridge.mjs) in place of dsh's ACP server: dsh's ACP and SDK servers take
// no input for a running turn, and its SDK cannot stop one. The plugin speaks a line of JSON per message (its header).
//
// Behaviour pinned against dsh 0.2 (docs/dsh.md):
// - `open` makes the session (dsh names it) or resumes a persisted one; the station's tools are dsh's mcp-client in the
//   patch, the session's token read from the environment;
// - `prompt` queues a message for the next turn (one starts at once when none runs); `steer` puts one in the running
//   turn, read after the step it is in (a tool call ends first); `cancel` stops the turn, which ends aborted;
// - the turn's bounds and tool calls come as the session's events (turn/start, turn/end with its reason, tool/call,
//   tool/result), the model's output as it streams;
// - the model, its provider and the station's instructions are dsh's configuration: a patch over its acp profile,
//   written per session.
import { mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { seesImages } from "../accounts/models.ts";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { LiveFromDsh, chars, type DshLiveState } from "./live.ts";
import { type Events, OwnProcessDriver, OwnProcessSession, type TurnState, parseLine } from "./own-process.ts";
import { DSH_KEY, dshRoute, expandRoute, profileEnv, profileModel, type DshRoute } from "./profiles.ts";
import type { RunnerInfo } from "./runner.ts";
import { cleanEnv, failureOf, stationTool, unreachable, uuid, type FailureReason, type OpenOptions, type TurnOutcome } from "./runtime.ts";

type Json = any;
type Env = Record<string, string | undefined>;

/// Inherited variables that would let a session use another account or home than its profile's.
const SCRUBBED = ["DEEPSEEK_API_KEY", "DEEPSEEK_BASE_URL", DSH_KEY, "DSH_HOME", "DSH_AGENTS_HOME", "DSH_PERMISSION_MODE"];
/// The route the station's patch declares for a profile's provider (dsh's own DeepSeek route keeps its name).
const ROUTE = "stillfail";
const DEEPSEEK_ROUTE = "deepseek-official";
/// Where in its home a profile's dsh keeps its sessions (not dsh's own sessions/: a profile home's is Codex's too,
/// read/transcript.ts `transcriptDir`).
export const SESSIONS = "dsh-sessions";
/// dsh's own model when a DeepSeek profile names none.
const DEEPSEEK_MODEL = "deepseek-v4-flash";
/// The station's driver plugin: beside this module (src/agents/ from source; the bundle's directory, where the build
/// copies it).
export const BRIDGE = fileURLToPath(new URL("./dsh-bridge.mjs", import.meta.url));

/// The id of the request that opens the session; the others carry their own.
const OPEN = "open";
/// Where the patch's header for the station's tools reads the session's token.
const MCP_TOKEN_VAR = "STILLFAIL_MCP_TOKEN";
/// The patch value that reads the token there when dsh loads it (a YAML tag JSON cannot say: written in by `patchText`).
const TOKEN_HEADER = "__stillfail_mcp_authorization__";

/// Reasoning effort in the station's terms (pool.ts: low, medium, high, max) as each route takes it.
const piEffort = (effort: string | undefined) => (effort && ["minimal", "low", "medium", "high", "xhigh", "max"].includes(effort) ? effort : undefined);
const deepseekEffort = (effort: string | undefined) => (effort === "low" ? "low" : effort === "medium" || effort === "high" ? "high" : effort === "max" ? "max" : undefined);

/// dsh's prompt variables are `{{name}}`, strictly: any `{{` in the instructions would stop it, so it is broken.
const literal = (text: string) => text.replaceAll("{{", "{​{");

/// What a session is started with: the patch over dsh's acp profile (YAML; JSON is YAML) and the route its agent asks
/// for (none: dsh's default).
export type DshSetup = { patch: Json[]; provider?: string; model?: string };

/// The patch for a session: dsh's ACP server off and the station's driver in; the profile's provider as a route of
/// its own and its model; the station's instructions after dsh's own; transcripts kept uncompressed (read/transcript.ts
/// reads them). A profile that brings its own configuration (custom variables) keeps dsh's routes.
export function dshSetup(route: DshRoute | null, model: string | undefined, effort: string | undefined, instructions: string, home: string, sessionRoute: string, mcpUrl: string, bridge = BRIDGE): DshSetup {
  const tools = { transport: "streamable-http", serverName: "stillfail", url: mcpUrl, headers: { Authorization: TOKEN_HEADER }, failOnStartupError: true };
  const patch: Json[] = [
    { id: "acp", disabled: true },
    { insert: [{ id: "stillfail-bridge", name: bridge }, { id: "stillfail-tools", name: "@deepseek-ai/dsh-mcp-client", config: tools }] },
  ];
  let chosen: { provider: string; model: string } | undefined;
  if (route?.kind === "pi") {
    if (model === undefined) throw new Error("the profile names no model for DeepSeek Harness");
    const entry: Json = { id: model, ...(seesImages(model) ? { input: ["text", "image"] } : {}) };
    const provider: Json = { displayName: route.name, api: route.api, baseURL: route.baseURL, apiKeyEnv: DSH_KEY, models: [entry] };
    if (route.headers) provider.headers = expandRoute(route.headers, sessionRoute);
    const reasoning = piEffort(effort);
    if (reasoning) {
      provider.reasoning = reasoning;
      // pi-ai takes a model it has no catalog entry for (deepseek-flash on OpenCode Go) as one without reasoning and
      // refuses any effort for it: the model is said to take the profile's.
      entry.reasoningEfforts = { off: null, [reasoning]: reasoning };
    }
    patch.push({ id: "llm-pi-ai", config: { providers: { [ROUTE]: provider } } });
    chosen = { provider: ROUTE, model };
  } else if (route?.kind === "deepseek") {
    const config: Json = { apiKeyEnv: "DEEPSEEK_API_KEY" };
    if (model !== undefined) config.models = [{ id: model }];
    const reasoning = deepseekEffort(effort);
    if (reasoning) config.reasoningEffort = reasoning;
    patch.push({ id: "llm-deepseek", config });
    chosen = { provider: DEEPSEEK_ROUTE, model: model ?? DEEPSEEK_MODEL };
  } else if (model !== undefined) {
    // Its own configuration, with a model named: DeepSeek's (dsh's own default route).
    chosen = { provider: DEEPSEEK_ROUTE, model };
  }
  if (chosen) patch.push({ id: "agent-default-model", config: chosen });
  // No prompt variables: the ones of dsh's ACP server ({{model}}) have no value without it.
  patch.push({ id: "system-prompt", config: { personaPrefix: "", personaSuffix: literal(instructions) } });
  patch.push({ id: "session-persistence-jsonl", config: { root: join(home, SESSIONS), compression: "none" } });
  return { patch, ...chosen };
}

/// The patch as its file says it: YAML (JSON is YAML) with the tools' header read from the environment by dsh.
export function patchText(patch: Json[]): string {
  return `${JSON.stringify(patch, null, 2).replace(`"${TOKEN_HEADER}"`, `!!js "'Bearer ' + process.env.${MCP_TOKEN_VAR}"`)}\n`;
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
    try {
      if (statSync(join(root, d, sessionId)).isDirectory()) return join(root, d, sessionId);
    } catch {}
  }
  return null;
}

/// What failed a turn, from dsh's error (its code first: AUTH, RATE_LIMIT, QUOTA, UNKNOWN_MODEL, …).
export const classifyFailure = (code: string, text: string): FailureReason =>
  failureOf(`${code} ${text}`, { authCodes: ["auth", "missing_credential", "invalid_credential"], limit: ["insufficient balance"] });

/// How a turn/end's reason ends the turn.
export function outcomeOf(reason: Json): TurnOutcome {
  const kind = reason?.kind;
  if (kind === "aborted") return { kind: "aborted" };
  if (kind === "error") {
    const error = reason.error ?? {};
    const message = typeof error.message === "string" ? error.message : JSON.stringify(error);
    return { kind: "failed", reason: classifyFailure(String(error.code ?? ""), message), message: chars(message, 1000) };
  }
  return { kind: "completed" };
}

/// The turn as its handled lines leave it. `prompted`: a turn of ours is asked for and has not started yet.
export type Turn = TurnState & { prompted: boolean };

/// A session as a next station takes it up.
export type DshSnapshot = { runtime: "dsh"; id: string; runner: string; turn: { busy: boolean; prompted: boolean; aborting: boolean }; tools: string | null; live: DshLiveState };

export type DshDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
  env?: Env;
  /// The driver plugin dsh loads (tests give their own).
  bridge?: string;
};

export class DshDriver extends OwnProcessDriver<DshSession> {
  private readonly command: string;
  private readonly bridge: string;

  constructor(options: DshDriverOptions) {
    super(options.data);
    this.command = options.command ?? "dsh";
    this.bridge = options.bridge ?? BRIDGE;
  }

  runtime(): "dsh" {
    return "dsh";
  }

  async open(options: OpenOptions, events: Events): Promise<DshSession> {
    const home = options.profile.home;
    mkdirSync(home, { recursive: true });
    if (options.resume !== undefined && sessionDir(home, options.resume) === null) {
      // dsh would refuse it; failing here lets the caller start fresh.
      throw new Error(`no dsh session ${options.resume}`);
    }
    const model = options.model ?? profileModel(options.profile);
    const setup = dshSetup(dshRoute(options.profile), model, options.effort, options.instructions, home, options.route, options.mcpUrl, this.bridge);
    // Per session: its instructions and model are in it. Named by the session's key, so a session started again writes
    // over its own. No secret is in it: keys and the tools' token are in the environment.
    const dir = join(home, "stillfail");
    mkdirSync(dir, { recursive: true });
    const patchFile = join(dir, `${createHash("sha256").update(options.key).digest("hex").slice(0, 16)}.patch.yml`);
    writeFileSync(patchFile, patchText(setup.patch), { mode: 0o600 });
    const args = ["--profile", "acp", "--patch", patchFile];

    const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "dsh"), options.route) };
    env.DSH_HOME = home;
    // Not the person's ~/.agents: the session's workspace's skills are where it runs (agent-home.ts `sessionSkills`).
    env.DSH_AGENTS_HOME = join(home, "agents");
    // No sandbox and no approvals, as the other runtimes run here; nothing of a session goes to DeepSeek's telemetry.
    env.DSH_PERMISSION_MODE = "danger-full-access";
    env.DSH_TELEMETRY_MODE ??= "DISABLED";
    env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
    env[MCP_TOKEN_VAR] = options.mcpToken;

    const session = new DshSession(this, "", { busy: false, prompted: false, aborting: false, closed: false }, new LiveFromDsh(), events);
    session.toolsUrl = options.mcpUrl;
    await this.start(session, options, this.command, args, env);
    try {
      const opened = await session.request(OPEN, "open", {
        cwd: options.cwd,
        ...(options.resume !== undefined ? { resume: options.resume } : {}),
        ...(setup.provider !== undefined ? { provider: setup.provider, model: setup.model } : {}),
      }, "dsh did not open the session (its driver plugin did not load?)");
      if (typeof opened?.session !== "string" || opened.session === "") throw new Error("dsh named no session");
      session.named(opened.session);
    } catch (error) {
      await session.dispose();
      throw error;
    }
    return session;
  }

  protected handedOver(_options: OpenOptions, handed: DshSnapshot, _info: RunnerInfo, events: Events) {
    const session = new DshSession(this, handed.id, { ...handed.turn, closed: false }, new LiveFromDsh(handed.live), events);
    session.toolsUrl = handed.tools;
    return session;
  }

  /// What the station before had handled says the session and where its turn stands.
  protected crashed(options: OpenOptions, lines: Iterable<string>, _info: RunnerInfo, events: Events) {
    const turn: Turn = { busy: false, prompted: false, aborting: false, closed: false };
    const live = new LiveFromDsh();
    let sessionId = options.resume ?? "";
    for (const line of lines) {
      const message = parseLine("dsh", line);
      if (message === undefined) continue;
      if (message.id === OPEN && typeof message.session === "string") sessionId = message.session;
      if (message.ev === "event" && message.type === "turn/start") turn.busy = true;
      if (message.ev === "event" && message.type === "turn/end") turn.busy = false;
      live.feed(message);
    }
    const session = new DshSession(this, sessionId, turn, live, events);
    session.toolsUrl = options.mcpUrl;
    return session;
  }
}

export class DshSession extends OwnProcessSession<Turn> {
  private live: LiveFromDsh;
  /// Its calls to the station's tools not answered yet.
  private calls = new Set<string>();

  constructor(driver: DshDriver, sessionId: string, turn: Turn, live: LiveFromDsh, events: Events) {
    super(driver, sessionId, turn, events);
    this.live = live;
  }

  /// A request whose answer is waited for: an error answer rejects.
  request(id: string, op: string, params: Json, late?: string): Promise<Json> {
    const answer = this.waiting.wait(id, (m) => (typeof m?.error === "string" ? new Error(`dsh ${op}: ${m.error}`) : null), late);
    this.proc.write(JSON.stringify({ id, op, ...params }));
    return answer;
  }

  /// A request sent without waiting for its answer (one refused is logged).
  private send(op: string, params: Json = {}) {
    this.proc.write(JSON.stringify({ id: `${op}:${uuid()}`, op, ...params }));
  }

  busy() {
    return this.turn.busy || this.turn.prompted;
  }

  protected idle() {
    this.turn.busy = false;
    this.turn.prompted = false;
  }

  protected cutShort() {
    this.emitLive(this.live.ended());
  }

  private emitLive(events: ReturnType<LiveFromDsh["feed"]>) {
    for (const event of events) this.events({ type: "live", event });
  }

  protected heard(line: string) {
    const message = parseLine("dsh", line);
    if (message === undefined) return;
    if (message.ev === undefined) {
      if (this.waiting.answer(message.id, message)) return;
      if (typeof message.error !== "string") return;
      log.warn("agents::dsh", "dsh refused a request", { session: this.sessionId, request: String(message.id), error: message.error });
      // A prompt refused starts no turn: it ends here.
      if (String(message.id).startsWith("prompt:") && this.turn.prompted) {
        this.turn.prompted = false;
        this.events({ type: "turnEnded", outcome: { kind: "failed", reason: "other", message: chars(message.error, 1000) } });
      }
      return;
    }
    if (message.ev === "event" && message.type === "turn/start") {
      const ours = this.turn.prompted;
      this.turn.prompted = false;
      this.turn.busy = true;
      // A turn of its own: a steer that came as the turn ended started one.
      if (!ours) this.events({ type: "turnStarted" });
    }
    this.emitLive(this.live.feed(message));
    const lost = this.toolsLost(message);
    if (lost !== null) this.events({ type: "toolsLost", why: lost });
    if (message.ev === "event" && message.type === "turn/end") {
      this.turn.busy = false;
      this.turn.aborting = false;
      this.events({ type: "turnEnded", outcome: outcomeOf(message.data?.reason) });
    }
  }

  /// What an event says of the station's tools being out of reach (null: nothing): a call to one of them failed as
  /// unreachable.
  private toolsLost(message: Json): string | null {
    if (message.ev !== "event") return null;
    const data = message.data ?? {};
    if (message.type === "tool/call" && typeof data.callId === "string" && stationTool(String(data.name ?? ""))) this.calls.add(data.callId);
    if (message.type !== "tool/result") return null;
    const result = data.message ?? {};
    if (!this.calls.delete(String(result.toolCallId ?? "")) || result.isError !== true) return null;
    const text = (Array.isArray(result.content) ? result.content : []).map((c: Json) => (typeof c?.text === "string" ? c.text : "")).join("\n");
    return unreachable(text) ? chars(text, 300) : null;
  }

  async prompt(text: string) {
    this.startable();
    this.turn.prompted = true;
    this.emitLive(this.live.prompted());
    this.send("prompt", { text });
  }

  /// Into the running turn: read after the step it is in.
  async steer(text: string) {
    if (this.turn.closed || !this.busy()) return false;
    this.send("steer", { text });
    return true;
  }

  async abort() {
    if (this.turn.closed || !this.busy() || this.turn.aborting) return;
    this.turn.aborting = true;
    this.send("cancel");
  }

  snapshot(): DshSnapshot {
    this.handOver();
    return {
      runtime: "dsh",
      id: this.sessionId,
      runner: this.proc.info.id,
      turn: { busy: this.turn.busy, prompted: this.turn.prompted, aborting: this.turn.aborting },
      tools: this.toolsUrl,
      live: this.live.state(),
    };
  }
}
