// CodeBuddy Code driver (Tencent's coding CLI, the engine of WorkBuddy): one `codebuddy --acp` per session, spoken to in
// ACP (acp.ts) with one ACP session in it. See docs/codebuddy.md. Beside what ACP says:
// - its files (settings, sessions, logs) are in the profile's, CODEBUDDY_CONFIG_DIR: none of the machine's ~/.codebuddy;
// - the station's instructions are appended to its system prompt (`--append-system-prompt`), its effort a flag;
// - it runs without approvals (`--permission-mode bypassPermissions`), with no telemetry and no updating itself;
// - a message for the running turn goes into it (its `session/steer`); its model is session/set_model;
// - what session/load would say again of the session's past is not asked for (`codebuddy.ai/suppressReplay`);
// - the station keeps the transcript (acp.ts KeptTranscript), with each turn's usage where the prompt's answer says it.
import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { AcpDriver, AcpSession, KeptTranscript, STEER, type AcpStart } from "./acp.ts";
import type { Events } from "./own-process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { cleanEnv, failureOf, uuid, type FailureReason, type OpenOptions, type Profile } from "./runtime.ts";

type Json = any;

/// Inherited variables that would let a session use another account, endpoint or home than its profile's.
const SCRUBBED = ["CODEBUDDY_API_KEY", "CODEBUDDY_AUTH_TOKEN", "CODEBUDDY_INTERNET_ENVIRONMENT", "CODEBUDDY_BASE_URL", "CODEBUDDY_CONFIG_DIR", "CODEBUDDY_HOME", "CODEBUDDY_MODEL", "CODEBUDDY_CUSTOM_HEADERS"];
/// The CLI's place in a profile's home: its config directory, and the transcripts the station keeps beside it.
export const codebuddyHome = (home: string) => join(home, "codebuddy");
export const configDir = (home: string) => join(codebuddyHome(home), ".codebuddy");
export const SESSIONS = "sessions";

/// The session ids it gives (UUIDs): a path segment of the transcript's.
const SESSION_ID = /^[a-zA-Z0-9_-]+$/;

/// Its efforts (`--effort`).
const EFFORTS = ["minimal", "low", "medium", "high", "xhigh", "max"];

/// What failed a turn, from what it said of it.
export const classifyFailure = (text: string): FailureReason =>
  failureOf(text, { auth: ["authentication required", "login required", "invalid api key", "token expired"], limit: ["insufficient credit", "credits exhausted", "quota", "额度"] });

/// The process's arguments: ACP, no approvals, the station's instructions after its system prompt, its effort.
export function codebuddyArgs(options: OpenOptions, probe = false): string[] {
  const args = ["--acp", "--permission-mode", "bypassPermissions"];
  if (!probe && options.instructions !== "") args.push("--append-system-prompt", options.instructions);
  if (!probe && options.effort !== undefined && EFFORTS.includes(options.effort)) args.push("--effort", options.effort);
  return args;
}

/// Its environment: the profile's variables (CODEBUDDY_API_KEY, and CODEBUDDY_INTERNET_ENVIRONMENT=internal for its China
/// site), its files in the profile's home; none of the machine's CodeBuddy keys.
export function codebuddyEnv(options: OpenOptions): Record<string, string> {
  const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "codebuddy"), options.route) };
  env.CODEBUDDY_CONFIG_DIR = configDir(options.profile.home);
  env.DISABLE_AUTOUPDATER = "1";
  env.DISABLE_TELEMETRY = "1";
  env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
  return env;
}

/// The models session/new or session/load lists (ACP's `models`), the current first.
export function codebuddyModels(result: Json): string[] {
  const valid = (v: unknown): v is string => typeof v === "string" && v.trim() !== "";
  const out = new Set<string>();
  if (valid(result?.models?.currentModelId)) out.add(result.models.currentModelId);
  for (const m of Array.isArray(result?.models?.availableModels) ? result.models.availableModels : []) if (valid(m?.modelId)) out.add(m.modelId);
  return [...out];
}

/// A turn's counts as the prompt's answer says them (ACP's `usage`), as the transcript keeps them: input apart from the
/// cache's, thoughts with the output. None when it says none.
export function turnUsage(answer: Json): { inputTokens: number; cacheReadTokens: number; cacheWriteTokens: number; outputTokens: number } | null {
  const u = answer?.result?.usage;
  if (u === null || typeof u !== "object") return null;
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  const read = n(u.cachedReadTokens);
  const written = n(u.cachedWriteTokens);
  return { inputTokens: Math.max(0, n(u.inputTokens) - read - written), cacheReadTokens: read, cacheWriteTokens: written, outputTokens: n(u.outputTokens) + n(u.thoughtTokens) };
}

export type CodebuddyDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

export class CodebuddyDriver extends AcpDriver<CodebuddySession> {
  private readonly command: string;

  constructor(options: CodebuddyDriverOptions) {
    super(options.data);
    this.command = options.command ?? "codebuddy";
  }

  runtime(): "codebuddy" {
    return "codebuddy";
  }

  /// The models a profile's CLI offers: a session opened only to ask (it also says whether it is signed in).
  async models(profile: Profile): Promise<string[]> {
    const session = await this.begin({ key: `models-${profile.id}-${uuid()}`, profile, cwd: codebuddyHome(profile.home), instructions: "", mcpToken: "", mcpUrl: "", route: "model-discovery" }, () => {}, true);
    try {
      return session.availableModels;
    } finally {
      await session.dispose();
    }
  }

  protected session(options: OpenOptions, events: Events) {
    return new CodebuddySession(this, events, options);
  }

  protected starting(options: OpenOptions, probe: boolean): AcpStart {
    if (options.resume !== undefined && !SESSION_ID.test(options.resume)) throw new Error("invalid CodeBuddy session id");
    const sessions = join(codebuddyHome(options.profile.home), SESSIONS);
    mkdirSync(sessions, { recursive: true });
    mkdirSync(configDir(options.profile.home), { recursive: true });
    // Not one the station kept.
    if (options.resume !== undefined && !existsSync(join(sessions, `${options.resume}.jsonl`))) throw new Error(`no CodeBuddy session ${options.resume}`);
    return { command: this.command, args: codebuddyArgs(options, probe), env: codebuddyEnv(options), opening: { _meta: { "codebuddy.ai/suppressReplay": true } } };
  }

  protected async ready(session: CodebuddySession, options: OpenOptions, probe: boolean) {
    const model = probe ? undefined : (options.model ?? profileModel(options.profile));
    if (model !== undefined && model !== session.model) await session.request(`model:${uuid()}`, "session/set_model", { sessionId: session.id(), modelId: model });
    if (model !== undefined) session.model = model;
  }
}

export class CodebuddySession extends AcpSession {
  /// What session/new or session/load said it offers.
  availableModels: string[] = [];
  /// The context its last call had and the model's window, as usage_update says them.
  private context = { used: 0, size: 0 };
  /// The effort its process was started with (a flag of it).
  private readonly effort: string | undefined;

  constructor(driver: CodebuddyDriver, events: Events, options: OpenOptions) {
    super(driver, events, new KeptTranscript("codebuddy", join(codebuddyHome(options.profile.home), SESSIONS)));
    this.effort = options.effort;
  }

  protected classify(text: string) {
    return classifyFailure(text);
  }

  named(id: string) {
    if (!SESSION_ID.test(id)) throw new Error("invalid CodeBuddy session id");
    super.named(id);
  }

  opened(result: Json) {
    super.opened(result);
    this.availableModels = codebuddyModels(result);
    const current = result?.models?.currentModelId;
    if (typeof current === "string" && current !== "") this.model = current;
  }

  protected updated(update: Json) {
    if (update?.sessionUpdate !== "usage_update") return;
    const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? v : 0);
    if (n(update.used) > 0) this.context.used = n(update.used);
    if (n(update.size) > 0) this.context.size = n(update.size);
  }

  /// The turn's usage, into the transcript before its end.
  protected ending(id: string, answer: Json) {
    const usage = turnUsage(answer);
    if (usage !== null) this.transcript?.keep(this.sessionId, { type: "usage", run: id.slice(id.indexOf(":") + 1), model: this.model, usage, calls: 1, context: this.context.used, window: this.context.size });
  }

  /// Into the running turn, read at its next step (`session/steer`, answered `steered` once it is taken). Not when
  /// nothing runs: the station starts that turn itself.
  async steer(text: string) {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return false;
    try {
      const answer = await this.request(`${STEER}${uuid()}`, "session/steer", { sessionId: this.sessionId, contentBlocks: [{ type: "text", text }] }, 30_000);
      if (answer?.result?.steered !== true) return false;
      this.transcript?.user(this.sessionId, text, true);
      return true;
    } catch (e) {
      log.warn("agents::codebuddy", "a message could not go into the running turn", { session: this.sessionId, error: (e as Error).message });
      return false;
    }
  }

  /// Between turns, another model is set in the running process, read from its next turn on; another effort starts it
  /// again.
  retune(options: OpenOptions) {
    if (this.turn.closed || this.turn.busy || this.sessionId === "") return false;
    if (options.effort !== this.effort) return false;
    const model = options.model ?? profileModel(options.profile);
    if (model === undefined) return false;
    if (this.availableModels.length > 0 && !this.availableModels.includes(model)) return false;
    if (model !== this.model) this.send("session/set_model", { sessionId: this.sessionId, modelId: model });
    this.model = model;
    return true;
  }
}
