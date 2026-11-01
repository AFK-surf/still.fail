// Claude Code driver (the Rust station's runtime/claude.rs): one `claude -p` stream-json process per session, under a
// runner whose id comes from the session key.
//
// Behaviour pinned by spikes (spike/README.md):
// - a turn is framed by system/init … result; `result.is_error` decides success, not `subtype` (an auth failure ends
//   as subtype "success");
// - 401/403 is retried silently for minutes, visible only as system/api_retry frames, so the first one fails the turn
//   (but see RENEWED);
// - input written while a turn is finishing may start a turn of its own (a system/init with no prompt of ours);
// - interrupt is a control_request; the turn still ends with a result frame.
// - background_tasks (a control_request) moves the Bash commands and subagents a turn waits on to the background: each
//   call returns at once and the turn goes on; a task_notification tells when one ends. Input written after it is
//   read in the turn then, not when they end.
// - each background command and subagent is told as it starts (system/task_started, is_backgrounded; or task_updated
//   with it later) and as it ends (task_notification, or task_updated with a final status); a subagent's own commands
//   say owned_by_subagent. They all end with the process.
import { existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { log } from "../ops/log.ts";
import { claudeProject } from "../read/transcript.ts";
import { LiveFromClaude, chars, type ClaudeLiveState } from "./live.ts";
import { CLAUDE_TOKEN_MARGIN_MS, machineClaudeToken, type Env, type MachineToken } from "./machine-logins.ts";
import { fileCredentials, takeBack } from "./no-keychain.ts";
import { type Events, OwnProcessDriver, OwnProcessSession, parseLine } from "./own-process.ts";
import { bothNames, expandRoute, isMachine, keyFile, profileEnv, profileModel } from "./profiles.ts";
import type { RunnerInfo } from "./runner.ts";
import { OVERLOADED, TOOL_SERVERS, cleanEnv, unreachable, uuid, type BackgroundTask, type FailureReason, type OpenOptions, type Profile, type RuntimeEvent, type TurnOutcome } from "./runtime.ts";
import { wall } from "../ops/fibers.ts";
import { peerHttpBase } from "../tools/http.ts";

type Json = any;

const MCP_TOKEN_VAR = "STILLFAIL_MCP_TOKEN";
/// Inherited variables that would let a session authenticate as something other than its profile.
const SCRUBBED = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CONFIG_DIR", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"];

/// The value given a flag in a process's arguments.
const flagOf = (args: string[], flag: string) => {
  const at = args.indexOf(flag);
  return at >= 0 ? args[at + 1] : undefined;
};

/// The address of the station's tools a process was started with (its --mcp-config); null when it does not say.
export function mcpUrlOf(args: string[]): string | null {
  try {
    const servers = JSON.parse(flagOf(args, "--mcp-config") ?? "")?.mcpServers ?? {};
    const url = TOOL_SERVERS.map((name) => servers[name]?.url).find((u) => typeof u === "string");
    return url ?? null;
  } catch {
    return null;
  }
}

/// What a frame says of the station's tools being out of reach (null: nothing): their server failed to connect as a
/// turn started, or a call to one of them (`calls`: the ids of those made, noted here as they are) failed as
/// unreachable. Seen in the field as `ECONNREFUSED: Unable to connect…`, then `MCP server "stillfail" is not connected`.
export function toolsLostIn(frame: Json, calls: Set<string>): string | null {
  const kind = frame?.type;
  const content: Json[] = Array.isArray(frame?.message?.content) ? frame.message.content : [];
  if (kind === "system" && frame.subtype === "init" && Array.isArray(frame.mcp_servers)) {
    const server = frame.mcp_servers.find((s: Json) => TOOL_SERVERS.includes(s?.name));
    if (server?.status === "failed") return `the ${server.name} MCP server failed to connect`;
  } else if (kind === "assistant") {
    for (const c of content) {
      if (c?.type === "tool_use" && typeof c.id === "string" && TOOL_SERVERS.some((s) => String(c.name ?? "").startsWith(`mcp__${s}__`))) calls.add(c.id);
    }
  } else if (kind === "user") {
    for (const c of content) {
      if (c?.type !== "tool_result" || !calls.delete(c.tool_use_id) || c.is_error !== true) continue;
      const text = typeof c.content === "string" ? c.content : Array.isArray(c.content) ? c.content.map((x: Json) => (typeof x?.text === "string" ? x.text : "")).join("\n") : "";
      if (unreachable(text)) return chars(text, 300);
    }
  }
  return null;
}

export const userMessage = (text: string) => JSON.stringify({ type: "user", message: { role: "user", content: [{ type: "text", text }] } });

/// Claude keeps a session at $CLAUDE_CONFIG_DIR/projects/<encoded cwd>/<id>.jsonl: looked for in the directory of `cwd`
/// (where it runs on), then in every project's (it ran elsewhere before: 923 directories on ccvm, each looked at).
export function transcriptExists(home: string, sessionId: string, cwd: string): boolean {
  const project = claudeProject(cwd);
  if (project !== null && existsSync(join(home, "projects", project, `${sessionId}.jsonl`))) return true;
  let dirs: string[];
  try {
    dirs = readdirSync(join(home, "projects"));
  } catch {
    return false;
  }
  return dirs.some((d) => {
    try {
      return statSync(join(home, "projects", d)).isDirectory() && existsSync(join(home, "projects", d, `${sessionId}.jsonl`));
    } catch {
      return false;
    }
  });
}

/// Anthropic turning the request away before any account is looked at (a region it does not serve, a proxy's address
/// it refuses): a 403 "Request not allowed", "forbidden". Signing in again changes nothing; the network does.
export function refused(text: string): boolean {
  const lower = text.toLowerCase();
  return lower.includes("request not allowed") || /\bforbidden\b/.test(lower);
}

export function classifyResult(text: string): FailureReason {
  const lower = text.toLowerCase();
  const words = lower.split(/[^\p{L}\p{N}]+/u);
  const word = (w: string) => words.includes(w);
  if (refused(text)) return "refused";
  if (word("401") || word("403") || lower.includes("authenticat") || lower.includes("api key")) return "auth";
  if (
    word("429") ||
    ["rate limit", "rate-limit", "rate_limit", "ratelimit", "usage limit"].some((s) => lower.includes(s)) ||
    ["session", "weekly", "daily"].some((window) => lower.includes(`hit your ${window} limit`)) ||
    /\bhit your \d+[- ]hour limit\b/.test(lower) ||
    lower.includes("you've hit your limit")
  ) {
    return "rate_limit";
  }
  if (word("529") || OVERLOADED.some((s) => lower.includes(s))) return "overloaded";
  return "model";
}

/// `renews`: its token is handed over and renewed while it runs (RENEWED): a first 401 is left to that.
/// `renewed`: a new token was given it in this turn, so another 401 is not the old token's.
/// `tasks`: the commands and subagents it runs that have not ended, by id (`background` once moved there).
/// `compacting`: the turn is a `/compact` asked for by hand, and `compactError` why it compacted nothing.
export type Turn = { busy: boolean; aborting: boolean; authFailure: string | null; closed: boolean; renews?: boolean; renewed?: boolean; tasks?: Record<string, Task>; compacting?: boolean; compactError?: string | null };
export type Task = BackgroundTask & { background: boolean };

/// A task's statuses once it has ended.
const ENDED = new Set(["completed", "failed", "killed", "stopped"]);

/// What its tasks as the turn leaves them run in the background.
export const backgroundOf = (turn: Turn): BackgroundTask[] =>
  Object.values(turn.tasks ?? {})
    .filter((t) => t.background)
    .map(({ id, kind, description, startedAt }) => (startedAt === undefined ? { id, kind, description } : { id, kind, description, startedAt }));

/// A token handed to the process (a machine login's, a lent one) is renewed while it runs: started with these, Claude
/// Code asks its host for a new one on a 401 (an `oauth_token_refresh` control request) and retries with it, so the
/// process, its background tasks and subagents go on. It honours them only for a few entrypoints; claude-desktop
/// changes neither its prompt nor its tools (only the entrypoint named in its requests), as checked on 2.1.299.
const RENEWED = { CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH: "1", CLAUDE_CODE_ENTRYPOINT: "claude-desktop" };
/// A CLI that does not ask (one too old) retries a 401 on its own: past this attempt it is stopped as before.
const RENEW_ATTEMPTS = 2;

/// What Claude Code brings of its own that a station's chat agent cannot or must not use, kept out of its context (a
/// fresh session began at 30k tokens, a third of them these; checked on 2.1.289):
/// - its own scheduling: still.fail's jobs are the station's (stillfail-cron); a wakeup or cron of the process's own
///   dies with it;
/// - claude.ai connectors: they come with the Claude account the session runs on, which changes as accounts run out,
///   so none is there to count on; and Claude Docs has the agent open a doc on claude.ai, out of the chat, first;
/// - skills, each listed with its whole description in every session: "off" for those needing what a station's process
///   never has (the desktop app's browser and computer use, connectors, a terminal, permission prompts, a scheduler of
///   its own, settings in a profile's home it leaves when it changes account); "name-only" for those seldom needed.
const DISALLOWED = ["ScheduleWakeup", "CronCreate", "CronDelete", "CronList", "RemoteTrigger"];
const SETTINGS = {
  disableClaudeAiConnectors: true,
  skillOverrides: {
    ...Object.fromEntries(["loop", "schedule", "keybindings-help", "fewer-permission-prompts", "plugin-authoring", "update-config"].map((name) => [name, "off"])),
    ...Object.fromEntries(["dataviz", "claude-api", "code-review", "run"].map((name) => [name, "name-only"])),
    ...Object.fromEntries(["computer-use", "chrome-browser", "built-in-browser", "docs", "google-workspace", "morning", "import-memory"].map((name) => [`anthropic-skills:${name}`, "off"])),
    ...Object.fromEntries(["docx", "pptx", "xlsx", "pdf", "deep-research", "skill-creator"].map((name) => [`anthropic-skills:${name}`, "name-only"])),
  },
};

/// A session as a next station takes it up (claude.rs Handed: the turn as its last handled line left it).
export type ClaudeSnapshot = {
  runtime: "claude";
  id: string;
  runner: string;
  turn: { busy: boolean; aborting: boolean; authFailure: string | null; renews?: boolean; tasks?: Record<string, Task>; compacting?: boolean; compactError?: string | null };
  machineExpires: number | null;
  live: ClaudeLiveState;
};

export type ClaudeDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path (server.rs gives "claude").
  command?: string;
  /// The station's own environment (machine logins are read in it); process.env by default.
  env?: Env;
  /// The machine login's current token, renewed when about to run out or when it is `rejected` (claude_oauth.rs; the
  /// accounts module's).
  machineToken?: (env: Env, rejected?: string) => Promise<MachineToken>;
  /// Another station's subscription, borrowed (share/index.ts): a token lent by the station signed in on it, handed
  /// to the process as the machine's is.
  lent?: { borrowed(profile: Profile): boolean; token(profile: Profile, rejected?: string): Promise<MachineToken> };
};

const interruptRequest = () => JSON.stringify({ type: "control_request", request_id: `interrupt-${uuid()}`, request: { subtype: "interrupt" } });

/// What a frame does to the turn (claude.rs on_frame). `interrupt` is how an auth failure stops the turn; `now` when a
/// task it tells of starts. What it has going in the background, said again (a `tasks` live event) as it changes.
export function onFrame(frame: Json, turn: Turn, emit: (event: RuntimeEvent) => void, interrupt: () => void, now: () => number = wall.now) {
  const before = JSON.stringify(backgroundOf(turn));
  frameDoes(frame, turn, emit, interrupt, now);
  const tasks = backgroundOf(turn);
  if (JSON.stringify(tasks) !== before) emit({ type: "live", event: { kind: "tasks", tasks } });
}

function frameDoes(frame: Json, turn: Turn, emit: (event: RuntimeEvent) => void, interrupt: () => void, now: () => number) {
  const kind = typeof frame?.type === "string" ? frame.type : "";
  const subtype = typeof frame?.subtype === "string" ? frame.subtype : "";
  // A control request it refused (a model it cannot switch to, say): the turns go on as they were.
  if (kind === "control_response" && frame.response?.subtype === "error") log.warn("agents::claude", "claude refused a control request", { request: String(frame.response.request_id ?? ""), error: String(frame.response.error ?? "") });
  if (kind === "system" && subtype === "init") {
    const was = turn.busy;
    turn.busy = true;
    if (!was) emit({ type: "turnStarted" });
  } else if (kind === "system" && subtype === "api_retry") {
    const status = Number.isInteger(frame.error_status) ? (frame.error_status as number) : 0;
    const attempt = Number.isInteger(frame.attempt) ? (frame.attempt as number) : 1;
    // A token renewed while it runs asks for a new one (RENEWED); stopped only when that one fails too.
    const renewing = status === 401 && turn.renews === true && turn.renewed !== true && attempt <= RENEW_ATTEMPTS;
    if ((status === 401 || status === 403) && turn.authFailure === null && !renewing) {
      const error = frame.error === undefined ? "authentication failed" : typeof frame.error === "string" ? frame.error : JSON.stringify(frame.error);
      turn.authFailure = `${status} ${error}`;
      interrupt();
      turn.aborting = true;
    }
  } else if (kind === "system" && subtype === "task_started" && typeof frame.task_id === "string" && frame.owned_by_subagent !== true) {
    const description = typeof frame.description === "string" ? frame.description : "";
    turn.tasks = { ...turn.tasks, [frame.task_id]: { id: frame.task_id, kind: frame.task_type === "local_agent" ? "agent" : "command", description, background: frame.is_backgrounded === true, startedAt: now() } };
  } else if (kind === "system" && (subtype === "task_notification" || subtype === "task_updated") && typeof frame.task_id === "string" && turn.tasks?.[frame.task_id]) {
    const status = subtype === "task_notification" ? frame.status : frame.patch?.status;
    const { [frame.task_id]: task, ...rest } = turn.tasks;
    if (subtype === "task_notification" || ENDED.has(status)) turn.tasks = rest;
    else if (frame.patch?.is_backgrounded === true) turn.tasks = { ...rest, [frame.task_id]: { ...task!, background: true } };
  } else if (kind === "system" && subtype === "status" && turn.compacting === true && frame.compact_result === "failed") {
    // `/compact` that compacted nothing still ends in a result of success: only this says so (2.1.289).
    turn.compactError = typeof frame.compact_error === "string" && frame.compact_error !== "" ? frame.compact_error : "compaction failed";
  } else if (kind === "result") {
    const text = typeof frame.result === "string" ? frame.result : subtype;
    let outcome: TurnOutcome;
    if (turn.authFailure !== null) outcome = { kind: "failed", reason: refused(turn.authFailure) ? "refused" : "auth", message: turn.authFailure };
    else if (turn.aborting) outcome = { kind: "aborted" };
    else if (frame.is_error === true) outcome = { kind: "failed", reason: classifyResult(text), message: chars(text, 1000) };
    else if (turn.compactError) outcome = { kind: "failed", reason: "other", message: chars(turn.compactError, 1000) };
    else outcome = { kind: "completed" };
    turn.busy = false;
    turn.aborting = false;
    turn.authFailure = null;
    turn.renewed = false;
    turn.compacting = false;
    turn.compactError = null;
    // What it waited on in the turn has ended with it; what goes on is in the background.
    if (turn.tasks) turn.tasks = Object.fromEntries(Object.entries(turn.tasks).filter(([, t]) => t.background));
    emit({ type: "turnEnded", outcome });
  }
}

export class ClaudeDriver extends OwnProcessDriver<ClaudeSession> {
  private readonly command: string;
  private readonly env: Env;
  private readonly machineToken: (env: Env, rejected?: string) => Promise<MachineToken>;
  private readonly lent: ClaudeDriverOptions["lent"];

  constructor(options: ClaudeDriverOptions) {
    super(options.data);
    this.command = options.command ?? "claude";
    this.env = options.env ?? process.env;
    this.machineToken = options.machineToken ?? machineClaudeToken;
    this.lent = options.lent;
  }

  runtime(): "claude" {
    return "claude";
  }

  /// Its process is named by its session id in the log.
  protected label(_options: OpenOptions, session: ClaudeSession) {
    return `claude ${session.id()}`;
  }

  async open(options: OpenOptions, events: Events): Promise<ClaudeSession> {
    const home = options.profile.home;
    mkdirSync(home, { recursive: true });
    if (options.resume !== undefined && !transcriptExists(home, options.resume, options.cwd)) {
      // claude would start and exit at once; failing here lets the caller start fresh.
      throw new Error(`no claude transcript for session ${options.resume}`);
    }
    const sessionId = options.resume ?? uuid();
    const mcpConfig = { mcpServers: { stillfail: { type: "http", url: options.mcpUrl, headers: { Authorization: `Bearer \${${MCP_TOKEN_VAR}}` } } } };
    const model = options.model ?? profileModel(options.profile);
    const args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--dangerously-skip-permissions"];
    if (options.resume !== undefined) args.push("--resume", sessionId);
    else args.push("--session-id", sessionId);
    if (model !== undefined) args.push("--model", model);
    if (options.effort !== undefined) args.push("--effort", options.effort);
    // None for a session continued from a terminal: its system prompt and tools stay as they began, so its cache holds.
    const ours = options.instructions !== "";
    if (ours) args.push("--append-system-prompt", options.instructions);
    for (const dir of options.dirs ?? []) args.push("--add-dir", dir);
    args.push("--mcp-config", JSON.stringify(mcpConfig));
    if (ours) args.push("--disallowedTools", DISALLOWED.join(","));
    // A key the station renews in a file (a Kimi sign-in's token, minutes long): Claude Code's key helper reads it,
    // again every minute and after a 401 (Claude Code runs it in a POSIX shell, Git Bash on Windows).
    const file = keyFile(options.profile);
    const settings = { ...(ours ? SETTINGS : {}), ...(file === undefined ? {} : { apiKeyHelper: `cat '${file.replaceAll("'", `'\\''`)}'` }) };
    if (Object.keys(settings).length > 0) args.push("--settings", JSON.stringify(settings));

    const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "claude"), options.route) };
    if (file !== undefined) env.CLAUDE_CODE_API_KEY_HELPER_TTL_MS = "60000";
    env.CLAUDE_CONFIG_DIR = home;
    // A preset's directories (--add-dir): their CLAUDE.md loaded as its own directory's is.
    if ((options.dirs ?? []).length > 0) env.CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = "1";
    env[MCP_TOKEN_VAR] = options.mcpToken;
    // Web services of the workspace's other stations: <this>/<station>/<port>/<path> (mesh/peer-http.ts).
    env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
    // Lets the agent name its own transcript, e.g. for an independent reviewer (codex has CODEX_THREAD_ID).
    for (const name of bothNames("RUNTIME_SESSION_ID")) env[name] = sessionId;
    // A machine profile runs on the machine's own login, handed over as its current token (machine_logins.rs).
    // Another station's subscription the same way, with the token that station lends.
    const renew = this.renewer(options.profile);
    const machine = renew ? await renew() : undefined;
    if (machine) {
      env.CLAUDE_CODE_OAUTH_TOKEN = machine.token;
      Object.assign(env, RENEWED);
    } else {
      // Its own login stays in its home's file when it refreshes it (no_keychain.rs).
      await takeBack(home);
      fileCredentials(env);
    }
    // Its own root certificates, not the system's: read from the macOS keychain by a process outside the desktop
    // session, they took up to 36 s before a new session could start. One the user chose wins.
    env.CLAUDE_CODE_CERT_STORE ??= "bundled";
    // Claude Code nudges a model that has gone a few turns without writing to the user to say what it is doing. Here
    // ordinary output reaches nobody, so the nudge turned into status posts in the chat; the instructions say when to post.
    env.CLAUDE_CODE_SILENT_TURN_REMINDER ??= "0";

    // Renewed while it runs, it is never started again for its token; one read from a file again after a 401 is not
    // stopped at the first.
    const session = new ClaudeSession(this, sessionId, { busy: false, aborting: false, authFailure: null, closed: false, renews: machine !== undefined || file !== undefined }, null, new LiveFromClaude(), events, options.effort, renew, machine?.token ?? null);
    session.toolsUrl = options.mcpUrl;
    await this.start(session, options, this.command, args, env);
    return session;
  }

  /// Where a profile whose token is handed to the process gets a current one (null for a profile with its own login):
  /// the machine login's, or the one lent by the station a borrowed subscription is signed in on.
  private renewer(profile: Profile): Renew | null {
    if (isMachine(profile)) return (rejected) => this.machineToken(this.env, rejected);
    const lent = this.lent;
    if (lent?.borrowed(profile)) return (rejected) => lent.token(profile, rejected);
    return null;
  }

  protected handedOver(options: OpenOptions, handed: ClaudeSnapshot, info: RunnerInfo, events: Events) {
    const session = new ClaudeSession(this, handed.id, { ...handed.turn, closed: false }, handed.machineExpires, new LiveFromClaude(handed.live), events, flagOf(info.args, "--effort"), this.renewer(options.profile), null);
    // The address it was told is in its arguments: the station's may have moved since (hub.ts `toolsAt`).
    session.toolsUrl = mcpUrlOf(info.args);
    return session;
  }

  /// What the station before had handled (stdout up to where it acknowledged) says where the turn stands.
  protected crashed(options: OpenOptions, lines: Iterable<string>, info: RunnerInfo, events: Events) {
    const turn: Turn = { busy: false, aborting: false, authFailure: null, closed: false };
    const live = new LiveFromClaude();
    for (const line of lines) {
      const frame = parseLine("claude", line);
      if (frame === undefined) continue;
      live.feed(frame);
      onFrame(frame, turn, () => {}, () => {});
    }
    const flag = info.args.findIndex((a) => a === "--session-id" || a === "--resume");
    const sessionId = flag >= 0 ? info.args[flag + 1]! : (options.resume ?? "");
    // Its token is not known, nor whether it asks for a new one: as if about to run out, so its next turn starts it
    // again with a current one (a machine login's or a lent one).
    const renew = this.renewer(options.profile);
    const session = new ClaudeSession(this, sessionId, turn, renew ? wall.now() : null, live, events, flagOf(info.args, "--effort"), renew, null);
    session.toolsUrl = mcpUrlOf(info.args);
    return session;
  }
}

/// A current token for a process, renewed first when `rejected` is the one given.
type Renew = (rejected?: string) => Promise<MachineToken>;

export class ClaudeSession extends OwnProcessSession<Turn> {
  /// The machine login's token this process runs on (machine profiles): when it runs out.
  private machineExpires: number | null;
  private live: LiveFromClaude;
  /// The effort it was started with: fixed for the process (`--effort` has no switch while it runs).
  private effort: string | undefined;
  /// Its calls to the station's tools not answered yet (toolsLostIn).
  private calls = new Set<string>();
  /// Where it gets a new token when it asks (RENEWED), and the one it was given last (null when not known here).
  private renew: Renew | null;
  private token: string | null;

  constructor(driver: ClaudeDriver, sessionId: string, turn: Turn, machineExpires: number | null, live: LiveFromClaude, events: Events, effort: string | undefined, renew: Renew | null, token: string | null) {
    super(driver, sessionId, turn, events);
    this.renew = renew;
    this.token = token;
    this.effort = effort;
    this.machineExpires = machineExpires;
    this.live = live;
  }

  protected heard(line: string) {
    const frame = parseLine("claude", line);
    if (frame === undefined) return;
    for (const event of this.live.feed(frame)) this.events({ type: "live", event });
    const lost = toolsLostIn(frame, this.calls);
    if (lost !== null) this.events({ type: "toolsLost", why: lost });
    if (frame?.type === "control_request" && frame.request?.subtype === "oauth_token_refresh") void this.renewToken(String(frame.request_id ?? ""));
    onFrame(frame, this.turn, this.events, () => this.proc.write(interruptRequest()));
  }

  /// It was refused with its token and asks for a new one (RENEWED): given one other than the token refused, or told
  /// why not, when its turn ends failed on authentication as before.
  private async renewToken(requestId: string) {
    let response: Json;
    try {
      if (!this.renew) throw new Error("its token is its own login's");
      const got = await this.renew(this.token ?? undefined);
      if (got.token === this.token) throw new Error("no newer token");
      this.token = got.token;
      this.turn.renewed = true;
      response = { accessToken: got.token };
      log.info("agents::claude", "gave claude a new token", { session: this.sessionId });
    } catch (error) {
      log.warn("agents::claude", "no new token for claude", { session: this.sessionId, error: (error as Error).message });
      response = { accessToken: null, reason: "refresh_failed" };
    }
    if (this.turn.closed) return;
    this.proc.write(JSON.stringify({ type: "control_response", response: { subtype: "success", request_id: requestId, response } }));
  }

  background() {
    return backgroundOf(this.turn);
  }

  async prompt(text: string) {
    this.begin();
    this.proc.write(userMessage(text));
  }

  /// Its `/compact`, as in a terminal: the CLI says `status: compacting`, then how it went, then the turn's result.
  async compact() {
    this.begin();
    this.turn.compacting = true;
    this.turn.compactError = null;
    this.proc.write(userMessage("/compact"));
  }

  private begin() {
    this.startable();
    // Taken up without knowing whether it renews its token (RENEWED): about to run out, it is started again (resuming)
    // with a current one.
    if (this.machineExpires !== null && this.machineExpires - wall.now() < CLAUDE_TOKEN_MARGIN_MS) throw new Error("the machine login's token runs out");
    this.turn.renewed = false;
    this.turn.busy = true;
  }

  async steer(text: string) {
    if (this.turn.closed || !this.turn.busy) return false;
    this.proc.write(userMessage(text));
    return true;
  }

  async backgroundTools() {
    if (this.turn.closed || !this.turn.busy) return;
    // Ctrl+B: every foreground Bash command and subagent. A CLI without it answers an error, and the message waits
    // as before.
    this.proc.write(JSON.stringify({ type: "control_request", request_id: `background-${uuid()}`, request: { subtype: "background_tasks" } }));
  }

  async abort() {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return;
    this.turn.aborting = true;
    this.proc.write(interruptRequest());
  }

  /// Another model is set in the process (set_model, read before the next prompt written after it); another effort needs
  /// a new one.
  retune(options: OpenOptions) {
    const model = options.model ?? profileModel(options.profile);
    if (this.turn.closed || this.turn.busy || model === undefined || options.effort !== this.effort) return false;
    this.proc.write(JSON.stringify({ type: "control_request", request_id: `model-${uuid()}`, request: { subtype: "set_model", model } }));
    return true;
  }

  snapshot(): ClaudeSnapshot {
    this.handOver();
    return {
      runtime: "claude",
      id: this.sessionId,
      runner: this.proc.info.id,
      turn: { busy: this.turn.busy, aborting: this.turn.aborting, authFailure: this.turn.authFailure, renews: this.turn.renews, tasks: this.turn.tasks, compacting: this.turn.compacting, compactError: this.turn.compactError },
      machineExpires: this.machineExpires,
      live: this.live.state(),
    };
  }
}
