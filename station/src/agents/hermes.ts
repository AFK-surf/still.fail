// Hermes Agent driver: one `hermes acp` per session, spoken to in ACP (acp.ts) with one ACP session in it. See
// docs/hermes.md for the protocol contract and supported profile setup. Beside what ACP says: the station's instructions
// go with each prompt; a message for the running turn waits for the next (Hermes would make it a turn of its own); a
// call's title is `<tool>: <its input>`; the station keeps the transcript (acp.ts KeptTranscript).
import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { peerHttpBase } from "../tools/http.ts";
import { AcpDriver, AcpSession, KeptTranscript, acpOutcome, type AcpStart } from "./acp.ts";
import { fileCredentials } from "./no-keychain.ts";
import type { Events } from "./own-process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { cleanEnv, failureOf, uuid, type FailureReason, type OpenOptions, type Profile } from "./runtime.ts";

type Json = any;

// Hermes can load any provider, including plugins and arbitrary key_env names. Inherit the machine's execution
// and network settings, not an ever-growing blacklist of provider credentials. Model settings come from the
// profile's home or explicit variables; those variables can also opt tools into any other environment they need.
const INHERITED = new Set([
  "PATH", "PATHEXT", "HOME", "USERPROFILE", "USER", "LOGNAME", "SHELL", "SYSTEMROOT", "WINDIR", "COMSPEC",
  "TEMP", "TMP", "TMPDIR", "APPDATA", "LOCALAPPDATA", "PROGRAMDATA", "LANG", "LANGUAGE", "TZ", "TERM",
  "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE",
  "CURL_CA_BUNDLE", "NODE_EXTRA_CA_CERTS", "SSH_AUTH_SOCK",
]);
export const hermesHome = (home: string) => join(home, "hermes");
export const SESSIONS = "sessions";

/// The session ids Hermes gives: a path segment of the transcript's.
const SESSION_ID = /^[a-zA-Z0-9_-]+$/;

/// Hermes' ACP title is `<tool_name>: <argument preview>` (acp_adapter/tools.py). The live and transcript readers
/// need the tool's name, notably to recognise chat_post; its arguments remain in rawInput, not in the name.
function hermesUpdate(update: Json): Json {
  if (update?.sessionUpdate !== "tool_call" || typeof update.title !== "string") return update;
  return { ...update, title: update.title.split(": ", 1)[0] };
}

/// What failed a turn, from what Hermes said of it.
export const classifyFailure = (text: string): FailureReason => failureOf(text);

/// How a prompt's answer ends the turn.
export const outcomeOf = (answer: Json) => acpOutcome(answer, classifyFailure);

export type HermesDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

export function hermesEnv(options: OpenOptions): Record<string, string> {
  const inherited = Object.fromEntries(Object.entries(cleanEnv([])).filter(([key]) => INHERITED.has(key.toUpperCase()) || /^LC_[A-Z_]+$/i.test(key)));
  const env = { ...inherited, ...expandRoute(profileEnv(options.profile, "hermes"), options.route) };
  env.HERMES_HOME = hermesHome(options.profile.home);
  // Hermes treats a borrowed Claude/Codex login as a configured provider. Keep those readers inside this profile,
  // unless the profile explicitly names a credential directory, and never borrow macOS's shared Claude login.
  env.CLAUDE_CONFIG_DIR ??= join(env.HERMES_HOME, "claude");
  env.CODEX_HOME ??= join(env.HERMES_HOME, "codex");
  fileCredentials(env);
  env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
  return env;
}

/// Hermes 0.21.7's ACP inventory excludes unconfigured providers and caps each provider at 200. Bound the combined
/// list too: a configured router can still offer hundreds. Existing manual selections remain in profile.models.
export const HERMES_MODEL_LIMIT = 50;
export function hermesCatalog(catalog: Json, profile: Profile): string[] {
  const valid = (v: unknown): v is string => typeof v === "string" && v.trim() !== "";
  const found = new Set<string>((Array.isArray(catalog?.availableModels) ? catalog.availableModels : []).map((m: Json) => m?.modelId).filter(valid));
  const current = catalog?.currentModelId;
  if (valid(current)) found.add(current);
  const picked = new Set<string>();
  const take = (model: unknown) => {
    if (valid(model) && found.has(model) && picked.size < HERMES_MODEL_LIMIT) picked.add(model);
  };
  take(current);
  take(profile.model);
  for (const model of Array.isArray(profile.models) ? profile.models : []) take(model);
  for (const model of found) { take(model); if (picked.size === HERMES_MODEL_LIMIT) break; }
  return [...picked];
}

export class HermesDriver extends AcpDriver<HermesSession> {
  private readonly command: string;

  constructor(options: HermesDriverOptions) {
    super(options.data);
    this.command = options.command ?? "hermes";
  }

  runtime(): "hermes" {
    return "hermes";
  }

  /// The models a profile's Hermes offers: a session opened only to ask.
  async models(profile: Profile): Promise<string[]> {
    mkdirSync(profile.home, { recursive: true });
    const session = await this.begin({ key: `models-${profile.id}-${uuid()}`, profile, cwd: profile.home, instructions: "", mcpToken: "", mcpUrl: "", route: "model-discovery" }, () => {}, true);
    try {
      return session.availableModels;
    } finally {
      await session.dispose();
    }
  }

  protected session(options: OpenOptions, events: Events) {
    return new HermesSession(this, events, options);
  }

  protected starting(options: OpenOptions): AcpStart {
    if (options.resume !== undefined && !SESSION_ID.test(options.resume)) throw new Error("invalid Hermes session id");
    const sessions = join(hermesHome(options.profile.home), SESSIONS);
    mkdirSync(sessions, { recursive: true });
    // Not one the station kept.
    if (options.resume !== undefined && !existsSync(join(sessions, `${options.resume}.jsonl`))) throw new Error(`no Hermes session ${options.resume}`);
    return { command: this.command, args: ["acp"], env: hermesEnv(options) };
  }

  /// Older ACP adapters omit completion updates for tools invoked through Hermes' discovery bridge. That loses their
  /// results and disconnection signals; require the adapter that reports both ends of a call.
  protected async initialized(_session: HermesSession, answer: Json) {
    const version = /^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(answer.result?.agentInfo?.version ?? "");
    if (!version || (+version[1]! === 0 && (+version[2]! < 21 || (+version[2]! === 21 && +version[3]! < 7)))) {
      throw new Error("Hermes Agent 需要 0.21.7 或更新版本；请先更新 Hermes，再重试。");
    }
  }

  protected async ready(session: HermesSession, options: OpenOptions, probe: boolean) {
    const model = probe ? undefined : (options.model ?? profileModel(options.profile));
    if (model !== undefined) await session.request(`model:${uuid()}`, "session/set_model", { sessionId: session.id(), modelId: model });
  }
}

export class HermesSession extends AcpSession {
  private readonly instructions: string;
  private readonly profile: Profile;
  /// What session/new said it offers (hermesCatalog).
  availableModels: string[] = [];

  constructor(driver: HermesDriver, events: Events, options: OpenOptions) {
    super(driver, events, new KeptTranscript("hermes", join(hermesHome(options.profile.home), SESSIONS)));
    this.instructions = options.instructions;
    this.profile = options.profile;
    this.model = options.model ?? profileModel(options.profile) ?? null;
  }

  protected classify(text: string) {
    return classifyFailure(text);
  }

  named(id: string) {
    if (!SESSION_ID.test(id)) throw new Error("invalid Hermes session id");
    super.named(id);
  }

  protected normalized(update: Json) {
    return hermesUpdate(update);
  }

  opened(result: Json) {
    super.opened(result);
    this.availableModels = hermesCatalog(result?.models, this.profile);
  }

  /// The station's instructions go with each prompt, as context before the message: ACP has no system prompt of a
  /// client's (docs/hermes.md).
  protected promptText(text: string) {
    return this.instructions ? `<stillfail-context>\n${this.instructions}\n</stillfail-context>\n\n${text}` : text;
  }
}
