// Devin driver: one `devin acp` per session (Cognition's Devin CLI, its local agent), spoken to in ACP (acp.ts) with one
// ACP session in it.
//
// Behaviour pinned against the Devin CLI 3000.11 (docs/devin.md), beside what ACP says:
// - `authenticate` with the profile's key (`_meta.api_key`, read from the credentials its sign-in left in the profile's
//   home), not the CLI's own sign-in on this machine;
// - `session/load` takes up a session it keeps (its store: DEVIN_SESSIONS_DIR);
// - a prompt given while a turn runs goes into that turn, read at its next step (a command running then goes on), and is
//   answered with it;
// - a call is named in `_meta["cognition.ai/inferenceToolName"]` (an MCP tool's mcp__<server>__<tool>); `usage_update`
//   says each model call's counts, the context and the model's window;
// - the session runs in Bypass Permissions (`mode`); a model is a family and a thinking level (`swe-2`, `high`), the
//   process's `--model <family>-<level>`, changed between turns with the `model` and `thought_level` config options;
//   the station's instructions, memory and skills a folder of the session's own given as another workspace directory
//   (its AGENTS.md and .devin/ read as a project's);
// - Devin keeps its sessions in a database of its own: the driver keeps the transcript itself (acp.ts KeptTranscript),
//   which the history and the usage read.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { linkSync } from "../ops/links.ts";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { AcpDriver, AcpSession, KeptTranscript, acpOutcome, type AcpStart } from "./acp.ts";
import type { Events } from "./own-process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { cleanEnv, failureOf, uuid, type FailureReason, type OpenOptions } from "./runtime.ts";

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

const AUTH = "auth";

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
/// skills of its workspace (`skills`) linked in as .devin/skills: Devin reads a workspace directory it is given as a
/// project's, without them being written into the person's project.
export function rulesFolder(home: string, key: string, instructions: string, skills?: string): string {
  const dir = join(devinHome(home), "station", createHash("sha256").update(key).digest("hex").slice(0, 16));
  mkdirSync(join(dir, ".devin", "rules"), { recursive: true });
  writeFileSync(join(dir, ".devin", "rules", "stillfail.md"), `---\ndescription: still.fail station\ntrigger: always_on\n---\n${devinRules(instructions)}\n`);
  const linked = (target: string, path: string) => {
    if (!existsSync(target)) return;
    rmSync(path, { recursive: true, force: true });
    try {
      // Where links are refused (Windows without Developer Mode), a junction.
      linkSync(target, path, { junction: true, copy: true });
    } catch (e) {
      log.warn("agents::devin", "the workspace's skills not linked for Devin", { path, error: (e as Error).message });
    }
  };
  // The skills of the session's workspace (agent-home.ts); its memory is told with the instructions. (An AGENTS.md
  // linked here before was the profile home's, the home workspace's memory whatever the session's workspace: gone.)
  rmSync(join(dir, "AGENTS.md"), { force: true });
  if (skills !== undefined) linked(skills, join(dir, ".devin", "skills"));
  return dir;
}

/// The thinking levels Devin's models are offered at (the last part of a variant's name: swe-2-high).
export const LEVELS = ["none", "minimal", "low", "medium", "high", "xhigh", "max"];

/// A model and level as Devin names the variant: `swe-2` at `high` is swe-2-high (it takes a family alone at its
/// default level).
export const variant = (model: string, effort: string | undefined) => (effort !== undefined && LEVELS.includes(effort) ? `${model}-${effort}` : model);

/// The models `devin models list --format json` lists, as the station offers them: each family a model at its thinking
/// levels (swe-2: medium, high, max), the name most of its variants are a level of. Not its variants of another kind
/// (glm-5-2-1m, claude-opus-4-6-thinking), the faster or prioritised ones (-fast, -priority, -lightning: billed apart),
/// nor Fusion's pairs of a model and a sidekick (fusion-gpt-6-sol-low-sidekick-gpt-5-6-luna-high: hundreds, each at
/// two levels, not a model at one).
export function devinCatalog(listed: Json): { models: string[]; efforts: Record<string, string[]> } {
  const models: string[] = [];
  const efforts: Record<string, string[]> = {};
  for (const family of Array.isArray(listed?.families) ? listed.families : []) {
    const seen: { model: string; level: string | undefined }[] = [];
    for (const v of Array.isArray(family?.variants) ? family.variants : []) {
      const uid = typeof v?.model_uid === "string" ? v.model_uid : "";
      if (uid === "" || /-(fast|priority|lightning)$/.test(uid) || uid.includes("-sidekick-")) continue;
      const level = LEVELS.find((l) => uid.endsWith(`-${l}`));
      seen.push({ model: level === undefined ? uid : uid.slice(0, -level.length - 1), level });
    }
    const count = (m: string) => seen.filter((s) => s.model === m).length;
    const model = seen.reduce<string | undefined>((best, s) => (best === undefined || count(s.model) > count(best) ? s.model : best), undefined);
    if (model === undefined || models.includes(model)) continue;
    models.push(model);
    const levels = LEVELS.filter((l) => seen.some((s) => s.model === model && s.level === l));
    if (levels.length > 0) efforts[model] = levels;
  }
  return { models, efforts };
}

/// What failed a turn, from what Devin said of it.
export const classifyFailure = (text: string): FailureReason => failureOf(text);

/// How a prompt's answer ends the turn.
export const outcomeOf = (answer: Json) => acpOutcome(answer, classifyFailure);

/// A model call's counts as Devin says them (a usage_update's), as the transcript keeps them: Cursor's names, input apart
/// from the cache's read (Devin says no cache written).
export function callOf(update: Json): { inputTokens: number; cacheReadTokens: number; cacheWriteTokens: number; outputTokens: number } {
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  const meta = update?._meta ?? {};
  const read = n(meta["cognition.ai/cachedReadTokens"]);
  return { inputTokens: Math.max(0, n(meta["cognition.ai/inputTokens"]) - read), cacheReadTokens: read, cacheWriteTokens: 0, outputTokens: n(meta["cognition.ai/outputTokens"]) };
}

export type DevinDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

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

export class DevinDriver extends AcpDriver<DevinSession> {
  private readonly command: string;

  constructor(options: DevinDriverOptions) {
    super(options.data);
    this.command = options.command ?? "devin";
  }

  runtime(): "devin" {
    return "devin";
  }

  protected session(options: OpenOptions, events: Events) {
    return new DevinSession(this, events, options);
  }

  protected starting(options: OpenOptions): AcpStart {
    const home = options.profile.home;
    const sessions = join(devinHome(home), SESSIONS);
    mkdirSync(join(sessions, STORE), { recursive: true });
    // Not one the station kept.
    if (options.resume !== undefined && !existsSync(join(sessions, `${options.resume}.jsonl`))) throw new Error(`no Devin session ${options.resume}`);
    const config = join(devinHome(home), "config.json");
    writeFileSync(config, `${JSON.stringify(CONFIG, null, 2)}\n`);
    const rules = rulesFolder(home, options.key, options.instructions, options.skills);
    const model = options.model ?? profileModel(options.profile);
    return { command: this.command, args: devinArgs(config, model, options.effort), env: devinEnv(options), opening: { additionalDirectories: [rules] } };
  }

  /// The profile's sign-in; custom variables bring their own (WINDSURF_API_KEY).
  protected async initialized(session: DevinSession, _answer: Json, options: OpenOptions) {
    const key = devinKey(options.profile.home);
    if (key !== null) await session.request(AUTH, "authenticate", { methodId: "devin-browser", _meta: { api_key: key } });
  }

  /// No approvals, as the other runtimes run here.
  protected async ready(session: DevinSession) {
    await session.request(`config:${uuid()}`, "session/set_config_option", { sessionId: session.id(), configId: "mode", value: "bypass" });
  }
}

export class DevinSession extends AcpSession {
  protected readonly steersByPrompt = true;
  /// The `model` config option's values (a family's variant each): what another model between turns is set to.
  private families: string[] = [];
  /// The turn's counts so far (each model call's, as usage_update says them once and again), the context its last call
  /// had and the model's window.
  private usage: { calls: number; counts: ReturnType<typeof callOf>; context: number; window: number } | null = null;
  private lastCall = "";

  constructor(driver: DevinDriver, events: Events, options: OpenOptions) {
    super(driver, events, new KeptTranscript("devin", join(devinHome(options.profile.home), SESSIONS)));
    this.model = options.model ?? profileModel(options.profile) ?? null;
  }

  protected classify(text: string) {
    return classifyFailure(text);
  }

  /// The model its config options say is current, and the values the `model` option takes.
  opened(result: Json) {
    super.opened(result);
    const model = (Array.isArray(result?.configOptions) ? result.configOptions : []).find((o: Json) => o?.id === "model");
    if (!model) return;
    if (Array.isArray(model.options)) this.families = model.options.map((o: Json) => o?.value).filter((v: unknown): v is string => typeof v === "string");
    if (typeof model.currentValue === "string" && model.currentValue !== "" && this.model === null) this.model = model.currentValue;
  }

  protected kept() {
    return { families: this.families };
  }

  protected taken(snapshot: Json) {
    this.families = Array.isArray(snapshot.families) ? snapshot.families : [];
  }

  /// Each call's counts are said twice (the second time as its agent's): counted once.
  protected updated(update: Json) {
    if (update?.sessionUpdate !== "usage_update") return;
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

  /// The turn's usage, into the transcript before its end.
  protected ending(id: string) {
    if (this.usage !== null) this.transcript?.keep(this.sessionId, { type: "usage", run: id.slice(id.indexOf(":") + 1), model: this.model, usage: this.usage.counts, calls: this.usage.calls, context: this.usage.context, window: this.usage.window });
    this.usage = null;
    this.lastCall = "";
  }

  /// Into the running turn, read at its next step: a prompt given while it runs, answered with the turn.
  async steer(text: string) {
    return this.promptInto(text);
  }

  /// Between turns, another model or thinking level is set in the running process (the `model` and `thought_level`
  /// config options), read from its next turn on. False for a model its options do not have.
  retune(options: OpenOptions) {
    if (this.turn.closed || this.turn.busy || this.sessionId === "") return false;
    const model = options.model ?? profileModel(options.profile);
    if (model === undefined) return false;
    // The option of the model's family: its own name, or a variant of it at a level.
    const family = this.families.find((v) => v === model || LEVELS.some((l) => v === `${model}-${l}`));
    if (family === undefined) return false;
    this.send("session/set_config_option", { sessionId: this.sessionId, configId: "model", value: family });
    if (options.effort !== undefined && LEVELS.includes(options.effort)) this.send("session/set_config_option", { sessionId: this.sessionId, configId: "thought_level", value: options.effort });
    this.model = model;
    return true;
  }
}
