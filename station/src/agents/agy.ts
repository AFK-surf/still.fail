// Antigravity CLI driver: one `agy acp` per session, spoken to in ACP (acp.ts) with one ACP session in it. See
//. Beside what ACP says:
// - its files (sign-in, settings, conversations) are in the profile's, `--gemini-dir`: none of the machine's ~/.gemini;
// - the station's instructions are appended to its system prompt (`_meta.antigravity.systemPrompt.append` of
//   session/new and session/load, which initialize says it takes);
// - it runs without approvals (`--dangerously-skip-permissions`), with no telemetry and no updating itself;
// - a message for the running turn steers it (`promptTakeover`); its model is session/set_model;
// - the station keeps the transcript (acp.ts KeptTranscript), with each turn's usage: the prompt's answer says it.
import { existsSync, mkdirSync } from "node:fs";
import { lstat, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { platform } from "../platform/index.ts";
import { peerHttpBase } from "../tools/http.ts";
import { AcpDriver, AcpSession, KeptTranscript, type AcpStart } from "./acp.ts";
import type { Events } from "./own-process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { TOOL_SERVERS, cleanEnv, failureOf, uuid, type FailureReason, type OpenOptions, type Profile } from "./runtime.ts";

type Json = any;

/// Inherited variables that would let a session use another account or project than its profile's.
const SCRUBBED = ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENAI_USE_VERTEXAI", "GOOGLE_APPLICATION_CREDENTIALS", "GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_LOCATION", "AGY_ADC_AUTH", "AGY_ACCOUNT"];
/// The CLI's home in a profile's: what `agy` signs in to with this as its HOME, its .gemini/ the ACP server's
/// `--gemini-dir`.
export const agyHome = (home: string) => join(home, "agy");
export const geminiDir = (home: string) => join(agyHome(home), ".gemini");
/// Where its sign-in to a Google account lands in that home (its TUI's, `agy` with the profile's agy/ as its HOME:
/// accounts/login.ts), which the ACP server reads from `--gemini-dir`: a file, `id_token_email` whose account it is.
export const agyToken = (home: string) => join(geminiDir(home), "antigravity-cli", "antigravity-oauth-token");
/// Where the station notes the Google account's email when `agyToken` is written or checked, so the account's name and
/// sign-in marker survive macOS `agy` migrating `agyToken` into the login keychain and unlinking the file.
export const agyAccountFile = (home: string) => join(agyHome(home), "account.json");
/// Where `agy acp` keeps its conversation databases under `--gemini-dir` once a signed-in session opens.
export const agyConversations = (home: string) => join(geminiDir(home), "antigravity-cli", "conversations");
export function agyEmailIn(text: string): string | null {
  try {
    const email = JSON.parse(text)?.id_token_email;
    return typeof email === "string" && email !== "" ? email : null;
  } catch {
    return null;
  }
}

export async function noteAgyEmail(home: string, text: string): Promise<string | null> {
  let parsed: Json;
  try {
    parsed = JSON.parse(text);
  } catch {
    await rm(agyAccountFile(home), { force: true }).catch(() => {});
    return null;
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    await rm(agyAccountFile(home), { force: true }).catch(() => {});
    return null;
  }
  const raw = parsed.id_token_email;
  const email = typeof raw === "string" && raw !== "" ? raw : null;
  try {
    await writeFile(agyAccountFile(home), `${JSON.stringify(email !== null ? { email } : {})}\n`);
  } catch {}
  return email;
}

export async function agyNotedEmail(home: string): Promise<string | null> {
  try {
    const email = JSON.parse(await readFile(agyAccountFile(home), "utf8"))?.email;
    return typeof email === "string" && email !== "" ? email : null;
  } catch {
    return null;
  }
}

/// On macOS (`platform.hasKeychain`), `agy acp` running with the user's HOME migrates `agyToken(home)` into the login
/// keychain and unlinks the file. A profile whose sign-in was noted (`agyAccountFile`) or that already opened an ACP
/// conversation (`agyConversations`) signed in before that migration; an unsigned profile (even with `agy/sessions`
/// linked by `linkTranscripts`) has neither.
export async function agyKeychainSignedIn(home: string): Promise<boolean> {
  if (!platform.hasKeychain) return false;
  try {
    await lstat(agyAccountFile(home));
    return true;
  } catch {}
  try {
    return (await readdir(agyConversations(home))).length > 0;
  } catch {
    return false;
  }
}
/// How many bytes of the station's tools a session's model is declared (tools/mcp.ts `fitted`). `agy` 1.5.6 in ACP
/// declares an MCP server's tools only while all of them together stay within about 57-60 KB, dropping the largest
/// beyond that, and offers no call_mcp_tool for those it dropped: measured 2026-11-12 with the station's 42 tools
/// (73 KB; chat_post, station_task and secret_save were dropped, so its sessions could not post) and with subsets of
/// them (57 KB declared whole). Kept well under it, for its own tools' growth.
export const AGY_TOOL_BUDGET = 45_000;

/// Where the station keeps its sessions' transcripts.
export const SESSIONS = "sessions";

/// The conversation ids it gives: a path segment of the transcript's.
const SESSION_ID = /^[a-zA-Z0-9_-]+$/;

/// What failed a turn, from what it said of it.
export const classifyFailure = (text: string): FailureReason =>
  failureOf(text, { auth: ["authentication required", "not logged into antigravity", "authentication expired", "couldn't sign in", "invalid_grant", "unauthenticated"], limit: ["resource_exhausted", "quota"] });

/// The process's arguments: the profile's files, no approvals, no telemetry.
export const agyArgs = (home: string) => ["acp", "--gemini-dir", geminiDir(home), "--dangerously-skip-permissions", "--disable-telemetry"];

/// Environment of an Antigravity CLI process: the station's scrubbed environment, the profile's own variables (which
/// win), its `--gemini-dir` (`ANTIGRAVITY_GEMINI_DIR`, for sandbox sync too), updates off, and the peer HTTP endpoint.
export function agyEnv(options: OpenOptions): Record<string, string> {
  const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "agy"), options.route) };
  env.ANTIGRAVITY_GEMINI_DIR = geminiDir(options.profile.home);
  env.AGY_CLI_DISABLE_AUTO_UPDATE = "1";
  env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
  return env;
}

/// What session/new and session/load are given besides the working directory and the station's tools: its instructions,
/// after its own system prompt.
export const agyOpening = (instructions: string): Json => (instructions === "" ? {} : { _meta: { antigravity: { systemPrompt: { append: instructions } } } });

/// A call's update as the station reads it: an MCP tool's title is `Run mcp_<server>_<tool>` (1.4.12), the station's
/// named as the other runtimes name them (mcp__stillfail__chat_post), so that its live steps, history and lost tools
/// know it.
export function agyUpdate(update: Json): Json {
  if (update?.sessionUpdate !== "tool_call" || typeof update.title !== "string") return update;
  for (const server of TOOL_SERVERS) {
    const prefix = `Run mcp_${server}_`;
    if (update.title.startsWith(prefix)) return { ...update, title: `mcp__${server}__${update.title.slice(prefix.length)}` };
  }
  return update;
}

/// The models session/new or session/load lists (ACP's `models`), the current first.
export function agyModels(result: Json): string[] {
  const valid = (v: unknown): v is string => typeof v === "string" && v.trim() !== "";
  const out = new Set<string>();
  if (valid(result?.models?.currentModelId)) out.add(result.models.currentModelId);
  for (const m of Array.isArray(result?.models?.availableModels) ? result.models.availableModels : []) if (valid(m?.modelId)) out.add(m.modelId);
  return [...out];
}

/// A turn's counts as the prompt's answer says them (ACP's `usage`), as the transcript keeps them: Cursor's names, input
/// apart from the cache's. None when it says none.
export function turnUsage(answer: Json): { inputTokens: number; cacheReadTokens: number; cacheWriteTokens: number; outputTokens: number } | null {
  const u = answer?.result?.usage;
  if (u === null || typeof u !== "object") return null;
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  const read = n(u.cachedReadTokens);
  const written = n(u.cachedWriteTokens);
  return { inputTokens: Math.max(0, n(u.inputTokens) - read - written), cacheReadTokens: read, cacheWriteTokens: written, outputTokens: n(u.outputTokens) + n(u.thoughtTokens) };
}

export type AgyDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

export class AgyDriver extends AcpDriver<AgySession> {
  private readonly command: string;

  constructor(options: AgyDriverOptions) {
    super(options.data);
    this.command = options.command ?? "agy";
  }

  runtime(): "agy" {
    return "agy";
  }

  /// The models a profile's CLI offers: a session opened only to ask.
  async models(profile: Profile): Promise<string[]> {
    const session = await this.begin({ key: `models-${profile.id}-${uuid()}`, profile, cwd: agyHome(profile.home), instructions: "", mcpToken: "", mcpUrl: "", route: "model-discovery" }, () => {}, true);
    try {
      return session.availableModels;
    } finally {
      await session.dispose();
    }
  }

  protected session(options: OpenOptions, events: Events) {
    return new AgySession(this, events, options);
  }

  protected starting(options: OpenOptions): AcpStart {
    if (options.resume !== undefined && !SESSION_ID.test(options.resume)) throw new Error("invalid Antigravity conversation id");
    const sessions = join(agyHome(options.profile.home), SESSIONS);
    mkdirSync(sessions, { recursive: true });
    mkdirSync(geminiDir(options.profile.home), { recursive: true });
    // Not one the station kept.
    if (options.resume !== undefined && !existsSync(join(sessions, `${options.resume}.jsonl`))) throw new Error(`no Antigravity conversation ${options.resume}`);
    return { command: this.command, args: agyArgs(options.profile.home), env: agyEnv(options), opening: agyOpening(options.instructions) };
  }

  protected async ready(session: AgySession, options: OpenOptions, probe: boolean) {
    const model = probe ? undefined : (options.model ?? profileModel(options.profile));
    if (model !== undefined && model !== session.model) await session.request(`model:${uuid()}`, "session/set_model", { sessionId: session.id(), modelId: model });
    if (model !== undefined) session.model = model;
  }
}

export class AgySession extends AcpSession {
  protected readonly steersByPrompt = true;
  /// What session/new or session/load said it offers.
  availableModels: string[] = [];
  /// The context its last call had and the model's window, as usage_update says them.
  private context = { used: 0, size: 0 };

  constructor(driver: AgyDriver, events: Events, options: OpenOptions) {
    super(driver, events, new KeptTranscript("agy", join(agyHome(options.profile.home), SESSIONS)));
  }

  protected classify(text: string) {
    return classifyFailure(text);
  }

  named(id: string) {
    if (!SESSION_ID.test(id)) throw new Error("invalid Antigravity conversation id");
    super.named(id);
  }

  protected normalized(update: Json) {
    return agyUpdate(update);
  }

  opened(result: Json) {
    super.opened(result);
    this.availableModels = agyModels(result);
    const current = result?.models?.currentModelId;
    if (typeof current === "string" && current !== "") this.model = current;
  }

  protected kept() {
    return { availableModels: this.availableModels, context: this.context };
  }

  protected taken(snapshot: Json) {
    this.availableModels = Array.isArray(snapshot.availableModels) ? snapshot.availableModels.filter((m: unknown): m is string => typeof m === "string") : [];
    const c = snapshot.context;
    if (c && typeof c === "object") this.context = { used: typeof c.used === "number" ? c.used : 0, size: typeof c.size === "number" ? c.size : 0 };
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

  protected ignored(id: string, answer: Json) {
    this.ending(id, answer);
  }

  /// Into the running turn: Antigravity CLI immediately resolves the superseded prompt and finishes on the new one.
  async steer(text: string) {
    return this.promptTakeover(text);
  }

  /// Between turns, another model is set in the running process, read from its next turn on.
  retune(options: OpenOptions) {
    if (this.turn.closed || this.turn.busy || this.sessionId === "") return false;
    const model = options.model ?? profileModel(options.profile);
    if (model === undefined) return false;
    if (this.availableModels.length > 0 && !this.availableModels.includes(model)) return false;
    if (model !== this.model) this.send("session/set_model", { sessionId: this.sessionId, modelId: model });
    this.model = model;
    return true;
  }
}
