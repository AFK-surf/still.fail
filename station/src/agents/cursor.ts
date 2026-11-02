// Cursor driver: one Node process per session, under a runner whose id comes from the session key, running the station's
// own driver (./cursor-bridge.mjs) on Cursor's TypeScript SDK (@cursor/sdk, its local runtime): the agent loop here, the
// models Cursor's, on the person's Cursor account. Not the Cursor CLI's ACP server: a message for the running turn there
// cancels the turn and kills the command it runs; the SDK's `steer` puts it in the turn, the command going on in the
// background. The bridge speaks a line of JSON per message (its header).
//
// Behaviour pinned against @cursor/sdk 1.0 (docs/cursor.md):
// - `open` creates the SDK's agent (it names it) or resumes one it keeps; the station's tools an HTTP MCP server, its
//   instructions (with its workspace's memory) and skills a folder of project rules beside the session's working directory;
// - `prompt` starts a run (a turn), whose messages stream (status, thinking, assistant text, tool calls, usage) and which
//   ends finished, cancelled or in error; `steer` puts a message in the running turn (said delivered or not); `cancel`
//   stops it;
// - the model is the SDK's selection, `id` or `id[param=value,…]`, set per prompt;
// - the bridge keeps the transcript itself (<sessions>/<agent id>.jsonl), the turn's usage in it.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { linkSync } from "../ops/links.ts";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { LiveFromCursor, chars, type CursorLiveState } from "./live.ts";
import { type Events, OwnProcessDriver, OwnProcessSession, type TurnState, parseLine } from "./own-process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { CommandMissing, type RunnerInfo } from "./runner.ts";
import { TOOL_SERVERS, cleanEnv, failureOf, unreachable, uuid, type FailureReason, type OpenOptions, type TurnOutcome } from "./runtime.ts";

type Json = any;

/// Inherited variables that would let a session use another account than its profile's.
const SCRUBBED = ["CURSOR_API_KEY", "CURSOR_AUTH_TOKEN", "CURSOR_BACKEND_URL", "CURSOR_WEBSITE_URL", "STILLFAIL_CURSOR_SDK", "STILLFAIL_CURSOR_HOME"];
/// The package the driver runs on, installed by npm (updates/runtimes.ts).
export const SDK_PACKAGE = "@cursor/sdk";
/// The station's driver: beside this module (src/agents/ from source; the bundle's directory, where the build copies it).
export const BRIDGE = fileURLToPath(new URL("./cursor-bridge.mjs", import.meta.url));

/// What Cursor keeps of a profile, in its home: the sign-in (auth.json, accounts/cursor.ts), the sessions (shared by every
/// profile that runs Cursor: agent-home.ts links them), the folders of the station's rules.
export const cursorHome = (home: string) => join(home, "cursor");
export const SESSIONS = "sessions";
/// The SDK's own home, in the shared sessions: what it keeps of its agents (their checkpoints, the terminals' output) goes
/// with them to whichever profile takes a session on.
export const SDK_HOME = "home";

/// The id of the request that opens the session; the others carry their own.
const OPEN = "open";
const PROMPT = "prompt:";
const STEER = "steer:";

/// Where the station keeps Cursor's SDK: npm installs it there (`-g --prefix`, updates/updates.ts), apart from the
/// machine's own global packages, so it is found by a look at the disk, not by asking npm.
export const sdkPrefix = (data: string) => join(data, "runtimes", "cursor");

/// The SDK's package under the prefix (lib/node_modules where npm puts a prefix's packages; node_modules on Windows),
/// null when it is not installed.
export function findSdk(data: string): string | null {
  for (const root of [join(sdkPrefix(data), "lib", "node_modules"), join(sdkPrefix(data), "node_modules")]) {
    const dir = join(root, ...SDK_PACKAGE.split("/"));
    if (existsSync(join(dir, "package.json"))) return dir;
  }
  return null;
}

/// The SDK's version, as its package says (null: not installed).
export function sdkVersion(data: string): string | null {
  const dir = findSdk(data);
  if (dir === null) return null;
  try {
    const v = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"))?.version;
    return typeof v === "string" ? v : null;
  } catch {
    return null;
  }
}

/// The key a profile signed in to Cursor has (accounts/cursor.ts keeps it in its home's cursor/auth.json); custom
/// variables bring their own CURSOR_API_KEY.
export function cursorKey(home: string): string | null {
  try {
    const key = JSON.parse(readFileSync(join(cursorHome(home), "auth.json"), "utf8"))?.apiKey;
    return typeof key === "string" && key !== "" ? key : null;
  } catch {
    return null;
  }
}

/// The station's instructions as a project rule that always applies, in a folder of the session's own beside its working
/// directory, with the skills of its workspace (`skills`) linked in as .cursor/skills: the SDK reads a folder it is given
/// as a project's (rules, AGENTS.md, skills) without them being written into the person's project.
export function rulesFolder(home: string, key: string, instructions: string, skills?: string): string {
  const dir = join(cursorHome(home), "station", createHash("sha256").update(key).digest("hex").slice(0, 16));
  mkdirSync(join(dir, ".cursor", "rules"), { recursive: true });
  writeFileSync(join(dir, ".cursor", "rules", "stillfail.mdc"), `---\ndescription: still.fail station\nalwaysApply: true\n---\n${instructions}\n`);
  const linked = (target: string, path: string) => {
    if (!existsSync(target)) return;
    rmSync(path, { recursive: true, force: true });
    try {
      // Where links are refused (Windows without Developer Mode), a junction.
      linkSync(target, path, { junction: true, copy: true });
    } catch (e) {
      log.warn("agents::cursor", "the workspace's skills not linked for Cursor", { path, error: (e as Error).message });
    }
  };
  // The skills of the session's workspace (agent-home.ts); its memory is told with the instructions. (An AGENTS.md
  // linked here before was the profile home's, the home workspace's memory whatever the session's workspace: gone.)
  rmSync(join(dir, "AGENTS.md"), { force: true });
  if (skills !== undefined) linked(skills, join(dir, ".cursor", "skills"));
  return dir;
}

/// What failed a turn, from the SDK's error (its code first).
export const classifyFailure = (code: string, text: string): FailureReason => failureOf(`${code} ${text}`);

/// How a run's end ends the turn.
export function outcomeOf(end: Json): TurnOutcome {
  if (end?.status === "cancelled") return { kind: "aborted" };
  if (end?.status === "finished") return { kind: "completed" };
  const message = typeof end?.error?.message === "string" ? end.error.message : `the run ended ${String(end?.status ?? "without saying how")}`;
  return { kind: "failed", reason: classifyFailure(String(end?.error?.code ?? ""), message), message: chars(message, 1000) };
}

/// A session as a next station takes it up.
export type CursorSnapshot = { runtime: "cursor"; id: string; runner: string; turn: { busy: boolean; aborting: boolean }; tools: string | null; live: CursorLiveState; model: string | null };

export type CursorDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The Node the bridge runs on (the station's own).
  node?: string;
  /// The driver (tests give their own) and the SDK's package (tests give a fake): found with npm when not given.
  bridge?: string;
  sdk?: string;
};

export class CursorDriver extends OwnProcessDriver<CursorSession> {
  private readonly node: string;
  private readonly bridge: string;
  private readonly sdk: string | undefined;

  constructor(options: CursorDriverOptions) {
    super(options.data);
    this.node = options.node ?? process.execPath;
    this.bridge = options.bridge ?? BRIDGE;
    this.sdk = options.sdk;
  }

  runtime(): "cursor" {
    return "cursor";
  }

  /// Its environment: the profile's key, the SDK's home and package, the station's tools' token.
  private env(options: OpenOptions, sdk: string): Record<string, string> {
    const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "cursor"), options.route) };
    const key = cursorKey(options.profile.home);
    if (key !== null && env.CURSOR_API_KEY === undefined) env.CURSOR_API_KEY = key;
    env.STILLFAIL_CURSOR_SDK = sdk;
    env.STILLFAIL_CURSOR_HOME = join(cursorHome(options.profile.home), SESSIONS, SDK_HOME);
    env.STILLFAIL_MCP_TOKEN = options.mcpToken;
    env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
    return env;
  }

  async open(options: OpenOptions, events: Events): Promise<CursorSession> {
    const home = options.profile.home;
    const sessions = join(cursorHome(home), SESSIONS);
    mkdirSync(sessions, { recursive: true });
    const sdk = this.sdk ?? findSdk(this.data);
    // Not installed: the person's message waits for it as for any runtime not on PATH (agents/runner.ts).
    if (sdk === null) throw new CommandMissing("cursor");
    if (options.resume !== undefined && !existsSync(join(sessions, `${options.resume}.jsonl`))) {
      // The SDK would not find it; failing here lets the caller start fresh.
      throw new Error(`no Cursor session ${options.resume}`);
    }
    const model = options.model ?? profileModel(options.profile) ?? null;
    const rules = rulesFolder(home, options.key, options.instructions, options.skills);
    const session = new CursorSession(this, "", { busy: false, aborting: false, closed: false }, new LiveFromCursor(), events, model);
    session.toolsUrl = options.mcpUrl;
    await this.start(session, options, this.node, [this.bridge], this.env(options, sdk));
    try {
      const opened = await session.request(OPEN, "open", {
        cwd: options.cwd,
        ...(options.resume !== undefined ? { resume: options.resume } : {}),
        ...(model !== null ? { model } : {}),
        mcpUrl: options.mcpUrl,
        rules,
        sessions,
      }, "Cursor's SDK did not open the agent in time");
      if (typeof opened?.session !== "string" || opened.session === "") throw new Error("Cursor's SDK named no agent");
      session.named(opened.session);
    } catch (error) {
      await session.dispose();
      throw error;
    }
    return session;
  }

  protected handedOver(_options: OpenOptions, handed: CursorSnapshot, _info: RunnerInfo, events: Events) {
    const session = new CursorSession(this, handed.id, { ...handed.turn, closed: false }, new LiveFromCursor(handed.live), events, handed.model);
    session.toolsUrl = handed.tools;
    return session;
  }

  /// What the station before had handled says the session and where its turn stands.
  protected crashed(options: OpenOptions, lines: Iterable<string>, _info: RunnerInfo, events: Events) {
    const turn: TurnState = { busy: false, aborting: false, closed: false };
    const live = new LiveFromCursor();
    let sessionId = options.resume ?? "";
    for (const line of lines) {
      const message = parseLine("cursor", line);
      if (message === undefined) continue;
      if (message.id === OPEN && typeof message.session === "string") sessionId = message.session;
      if (message.ev === "message") {
        turn.busy = true;
        live.feed(message.message);
      } else if (message.ev === "end") {
        turn.busy = false;
        live.ended();
      }
    }
    const session = new CursorSession(this, sessionId, turn, live, events, options.model ?? profileModel(options.profile) ?? null);
    session.toolsUrl = options.mcpUrl;
    return session;
  }
}

export class CursorSession extends OwnProcessSession {
  private live: LiveFromCursor;
  /// Its calls to the station's tools not answered yet.
  private calls = new Set<string>();
  /// The model its next turn runs on (null: the agent's).
  private model: string | null;

  constructor(driver: CursorDriver, sessionId: string, turn: TurnState, live: LiveFromCursor, events: Events, model: string | null) {
    super(driver, sessionId, turn, events);
    this.live = live;
    this.model = model;
  }

  /// A request whose answer is waited for: an error answer rejects.
  request(id: string, op: string, params: Json, late?: string): Promise<Json> {
    const answer = this.waiting.wait(id, (m) => (typeof m?.error === "string" ? new Error(`cursor ${op}: ${m.error}`) : null), late);
    this.proc.write(JSON.stringify({ id, op, ...params }));
    return answer;
  }

  protected cutShort() {
    this.emitLive(this.live.ended());
  }

  private emitLive(events: ReturnType<LiveFromCursor["feed"]>) {
    for (const event of events) this.events({ type: "live", event });
  }

  protected heard(line: string) {
    const message = parseLine("cursor", line);
    if (message === undefined) return;
    if (message.ev === "message") {
      // A turn running that this station did not see start (taken up after a crash just as it was given).
      if (!this.turn.busy) {
        this.turn.busy = true;
        this.events({ type: "turnStarted" });
      }
      this.emitLive(this.live.feed(message.message));
      const lost = this.toolsLost(message.message);
      if (lost !== null) this.events({ type: "toolsLost", why: lost });
      return;
    }
    if (message.ev === "end") {
      const outcome = this.turn.aborting && message.status !== "finished" ? ({ kind: "aborted" } as TurnOutcome) : outcomeOf(message);
      if (!this.turn.busy) this.events({ type: "turnStarted" });
      this.turn.busy = false;
      this.turn.aborting = false;
      this.calls.clear();
      this.emitLive(this.live.ended());
      this.events({ type: "turnEnded", outcome });
      return;
    }
    if (this.waiting.answer(message.id, message)) return;
    if (typeof message.error !== "string") return;
    log.warn("agents::cursor", "cursor refused a request", { session: this.sessionId, request: String(message.id), error: message.error });
    // A prompt refused (the SDK could not start the run: no key, a model it does not have) starts no turn: it ends here.
    if (String(message.id).startsWith(PROMPT) && this.turn.busy) {
      this.turn.busy = false;
      this.turn.aborting = false;
      this.emitLive(this.live.ended());
      this.events({ type: "turnEnded", outcome: outcomeOf({ status: "error", error: { message: message.error, code: message.code } }) });
    }
  }

  /// What a message says of the station's tools being out of reach (null: nothing): a call to one of them failed as
  /// unreachable.
  private toolsLost(message: Json): string | null {
    if (message?.type !== "tool_call" || typeof message.call_id !== "string") return null;
    const provider = String(message.args?.providerIdentifier ?? "");
    if (message.status === "running" && message.name === "mcp" && TOOL_SERVERS.includes(provider)) this.calls.add(message.call_id);
    if (message.status === "running" || !this.calls.delete(message.call_id) || message.status !== "error") return null;
    const text = typeof message.result === "string" ? message.result : JSON.stringify(message.result ?? "");
    return unreachable(text) ? chars(text, 300) : null;
  }

  async prompt(text: string) {
    this.startable();
    this.turn.busy = true;
    this.emitLive(this.live.prompted());
    this.proc.write(JSON.stringify({ id: `${PROMPT}${uuid()}`, op: "prompt", text, ...(this.model !== null ? { model: this.model } : {}) }));
  }

  /// Into the running turn, by the SDK's steer: the turn takes it at its next step (a command it runs goes on in the
  /// background). Not delivered (the turn ending as it came): the station gives it as the next turn's.
  async steer(text: string) {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return false;
    try {
      const answer = await this.request(`${STEER}${uuid()}`, "steer", { text });
      return answer?.delivered === true;
    } catch (e) {
      log.warn("agents::cursor", "a message could not go into the running turn", { session: this.sessionId, error: (e as Error).message });
      return false;
    }
  }

  /// Between turns, another model is the next prompt's (the SDK takes one per run): no new process.
  retune(options: OpenOptions) {
    if (this.turn.closed || this.turn.busy || this.sessionId === "") return false;
    const model = options.model ?? profileModel(options.profile);
    if (model === undefined) return false;
    this.model = model;
    return true;
  }

  async abort() {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return;
    this.turn.aborting = true;
    this.proc.write(JSON.stringify({ id: `cancel:${uuid()}`, op: "cancel" }));
  }

  snapshot(): CursorSnapshot {
    this.handOver();
    return { runtime: "cursor", id: this.sessionId, runner: this.proc.info.id, turn: { busy: this.turn.busy, aborting: this.turn.aborting }, tools: this.toolsUrl, live: this.live.state(), model: this.model };
  }
}
