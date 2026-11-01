// Whether a profile works, and what models it offers (the Rust station's profiles.rs: the checks, and which access kinds a
// runtime takes). How an access kind reaches its models (the environment, Codex's overrides) is agents/profiles.ts's.
// The providers' addresses can be pointed elsewhere (`Urls`): tests give fake servers.
import { execFile } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import type { Env } from "../agents/machine-logins.ts";
import { linkCodexAuth, parseClaudeCredentials } from "../agents/machine-logins.ts";
import { fileCredentials, takeBack } from "../agents/no-keychain.ts";
import { type AccessKind, OPENCODE, profileRuntimes, type Runtime, type Via } from "../agents/profiles.ts";
import { type Endpoints, endpoints, find, type Source } from "../agents/providers.ts";
import type { Capability } from "../sessions/decision.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { claudeOAuthToken, claudeToken as tokenOf } from "./oauth.ts";
import { CONSOLE, RenewRefused } from "./console.ts";
import { CURSOR, type CursorUrls, cursorMe, cursorModels, readCursor } from "./cursor.ts";
import { devinCatalog, devinData } from "../agents/devin.ts";
import { platform } from "../platform/index.ts";
import { profileFetch } from "../ops/agent-env.ts";
import { claudePlan, codexClaims } from "./machine.ts";

type Json = any;

/// Whether a profile works, and what models it offers (profiles.rs ProfileCheck, the same JSON).
export type ProfileCheck = {
  decision?: Capability;
  /// The subscription tier as reported by its login; absent when the runtime does not say.
  plan?: string;
  /// runtime → model → reasoning levels, as the runtime reports them.
  modelEfforts?: Record<string, Record<string, string[]>>;
  /// ok: usable; login: needs a subscription sign-in; failed: the key or login was rejected; unknown.
  state: string;
  detail: string;
  /// Models the account can use, when the provider lists them.
  models: string[] | null;
  checkedAt: number;
};

/// `minutes`: how long the window is, where known (the pool weighs what is left by how soon it is lost).
export type QuotaWindow = { label: string; usedPercent: number; resetsAt: number | null; minutes?: number | null };
export type QuotaCredits = { hasCredits: boolean; unlimited: boolean; balance: string | null };

/// How much of a profile's allowance is used, where the provider says (profiles.rs ProfileQuota).
export type ProfileQuota = {
  /// ok: windows filled; unsupported: nothing to show for this kind; unavailable: could not ask; blocked: the provider
  /// refuses the account.
  state: string;
  windows: QuotaWindow[];
  credits?: QuotaCredits;
  resetCount?: number;
  /// The subscription tier, when the provider reports it with the allowance.
  plan?: string;
  detail: string | null;
  checkedAt: number;
  /// Asked with a login that turned out to be over (oauth.ts RenewRefused): its profile is checked again. Not kept.
  signedOut?: boolean;
};

/// Where the providers are: the real ones unless a test says otherwise.
export type Urls = {
  /// OpenCode Go (…/zen/go).
  opencode: string;
  /// Anthropic's API (models, OAuth usage).
  anthropic: string;
  /// ChatGPT's backend (Codex's usage).
  chatgpt: string;
  /// Claude's OAuth token endpoint (renewing a login).
  claudeToken: string;
  /// The OpenCode Console (an OpenCode Go profile signed in to it: console.ts).
  console: string;
  /// Cursor (a Cursor profile signed in to it: cursor.ts); its real one when not given.
  cursor?: CursorUrls;
  /// Kimi's sign-in server (a Kimi Code profile signed in to it: kimi.ts), and Kimi Code's API (its allowance); the real
  /// ones when not given.
  kimi?: string;
  kimiApi?: string;
};

export const URLS: Urls = {
  opencode: OPENCODE,
  anthropic: "https://api.anthropic.com",
  chatgpt: "https://chatgpt.com",
  claudeToken: "https://platform.claude.com/v1/oauth/token",
  console: CONSOLE,
};

/// The access kinds each runtime can use.
export function accessKinds(runtime: Runtime): AccessKind[] {
  if (runtime === "hermes") return ["env"];
  if (runtime === "claude") return ["subscription", "opencode-go", "anthropic-api", "api-provider", "env"];
  // DeepSeek Harness has no subscription to sign in to here: an account of its own is set up by variables.
  if (runtime === "dsh") return ["opencode-go", "anthropic-api", "api-provider", "env"];
  // Grok Build: SuperGrok signed in to, an xAI key, or its own variables.
  if (runtime === "grok") return ["subscription", "api-provider", "env"];
  // Cursor: a Cursor account signed in to (it takes no provider's key), or its own variables (CURSOR_API_KEY).
  if (runtime === "cursor") return ["subscription", "env"];
  // Devin: a Devin account signed in to, or its own variables (WINDSURF_API_KEY).
  if (runtime === "devin") return ["subscription", "env"];
  return ["subscription", "opencode-go", "api-provider", "env"];
}

/// Access kinds that authenticate with a key the profile stores.
export const keyed = (kind: AccessKind) => kind === "opencode-go" || kind === "anthropic-api" || kind === "api-provider";

/// Whether a profile on this access must have a key: every keyed one but a provider that works without.
export const needsKey = (kind: AccessKind, provider: string | undefined): boolean =>
  keyed(kind) && !(kind === "api-provider" && provider !== undefined && find(provider)?.keyOptional === true);

/// The runtimes an access kind runs without its provider (profiles.rs runtimes_of): a provider's follow from where it
/// speaks (`runtimesFor`).
export function runtimesOf(kind: AccessKind, runtime: Runtime | undefined): Runtime[] {
  if (kind === "opencode-go") return ["claude", "codex", "dsh"];
  if (kind === "anthropic-api") return ["claude", "dsh"];
  if (kind === "api-provider") return [];
  if (kind === "subscription" && runtime === "dsh") return [];
  return runtime ? [runtime] : [];
}

/// The runtimes of an access as config.json has it (with its provider and address).
export const runtimesFor = (access: Json, runtime: unknown): Runtime[] => profileRuntimes({ id: "", home: "", runtime: runtime as Runtime, access });

/// The command to sign a subscription profile in, run on the station's machine.
/// None for DeepSeek Harness, which has no subscription here. One on the machine's own login (`machine`) is signed in
/// where the machine's is, its usual home (machine-logins.ts): its own home holds no login, so signing that in changes
/// nothing it uses.
export const loginCommand = (runtime: Runtime, home: string, machine = false) =>
  machine ? (runtime === "claude" ? "claude auth login" : runtime === "codex" ? "codex login" : "")
  : runtime === "claude" ? `CLAUDE_CONFIG_DIR=${home} claude auth login`
  : runtime === "codex" ? `CODEX_HOME=${home} codex login`
  : runtime === "grok" ? `GROK_HOME=${join(home, "grok")} grok login --device-auth`
  : runtime === "devin" ? `XDG_DATA_HOME=${devinData(home)} devin auth login --force-manual-token-flow`
  : "";

/// What a check is given: the account and where it lives.
export type CheckOptions = {
  runtime: Runtime;
  kind: AccessKind;
  key: string;
  /// Of an API-provider profile: which provider and where.
  via: Via;
  home: string;
  /// The station's environment (where a machine login is read, and the CLIs found).
  env: Env;
  /// On the machine's own login.
  machine: boolean;
  /// An OpenCode Go profile whose key is the token of a sign-in to the OpenCode Console, or a Kimi Code one signed in
  /// to Kimi (its key the current token, none once signed out).
  login?: boolean;
  /// The machine login's current token, renewed when about to run out (oauth.ts).
  machineToken?: (env: Env) => Promise<{ token: string }>;
  urls?: Urls;
  lang?: Lang;
};

/// `checkedAt`: stamped by whoever keeps it, on its clock (Accounts).
const check = (state: string, detail: string, models: string[] | null): ProfileCheck => ({ state, detail, models, checkedAt: 0 });

async function get(url: string, headers: Record<string, string>): Promise<Response> {
  return profileFetch(url, { headers, signal: AbortSignal.timeout(15_000) });
}

/// The ids of a `/v1/models` answer.
async function modelIds(response: Response): Promise<string[]> {
  const body: Json = await response.json();
  return Array.isArray(body?.data) ? body.data.map((m: Json) => m?.id).filter((id: unknown): id is string => typeof id === "string") : [];
}

/// Rust's sort of strings (by bytes, which for these ids is by UTF-16 units too).
const sorted = (list: string[]) => list.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

/// Runs a runtime's own status command, in `env` only; what it said and how it ended.
function statusOf(command: string, args: string[], env: Env): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const r = platform.runnable(command, args, env as NodeJS.ProcessEnv);
    execFile(r.file, r.args, { env: env as NodeJS.ProcessEnv, timeout: 20_000, killSignal: "SIGKILL", windowsVerbatimArguments: r.windowsVerbatimArguments }, (error, stdout, stderr) => {
      if (error && (error as NodeJS.ErrnoException).code === "ENOENT") return reject(new Error(`${command}: ${error.message}`));
      if (error && error.killed) return reject(new Error(`${command} ${args.join(" ")} timed out`));
      const code = error ? (typeof (error as any).code === "number" ? (error as any).code : null) : 0;
      resolve({ code, stdout: String(stdout), stderr: String(stderr) });
    });
  });
}

/// Asks the provider or runtime whether this profile works, and what models it offers (checkProfile). Never throws:
/// what went wrong is a failed check.
export async function checkProfile(o: CheckOptions): Promise<ProfileCheck> {
  const lang = o.lang ?? stationLang();
  try {
    return await checkInner(o, lang);
  } catch (e) {
    // A login that can no longer be renewed (oauth.ts) is over: signed in again.
    if (e instanceof RenewRefused) return check("login", e.message, null);
    return check("failed", tr(lang, "station.profile.checkError", { error: (e as Error).message }), null);
  }
}

async function checkInner(o: CheckOptions, lang: Lang): Promise<ProfileCheck> {
  const urls = o.urls ?? URLS;
  const t = (key: string, args?: Record<string, unknown>) => tr(lang, key, args);
  if (o.kind === "opencode-go") {
    // The model list answers any key; the usage is the key's own, so it is what tells a key that works.
    const usage = await get(`${urls.opencode}/v1/usage`, { authorization: `Bearer ${o.key}` });
    // A sign-in refused is one to sign in again (the account's own key would not be).
    if (o.login === true && (usage.status === 401 || usage.status === 403)) return check("login", t("station.profile.consoleSignedOut"), null);
    if (!usage.ok) return check("failed", t("station.profile.keyRefused", { provider: "OpenCode Go", status: usage.status }), null);
    const response = await get(`${urls.opencode}/v1/models`, { authorization: `Bearer ${o.key}` });
    if (!response.ok) return check("failed", t("station.profile.modelsUnreadable", { provider: "OpenCode Go", status: response.status }), null);
    const models = sorted(await modelIds(response));
    return check("ok", t("station.profile.works", { n: models.length }), models);
  }
  if (o.kind === "anthropic-api") {
    const response = await get(`${urls.anthropic}/v1/models?limit=100`, { "x-api-key": o.key, "anthropic-version": "2023-06-01" });
    if (!response.ok) return check("failed", t("station.profile.keyRefused", { provider: "Anthropic", status: response.status }), null);
    const models = await modelIds(response);
    return check("ok", t("station.profile.works", { n: models.length }), models);
  }
  if (o.kind === "api-provider") {
    const source = o.via.provider === undefined ? undefined : find(o.via.provider);
    if (!source) return check("failed", t("station.profile.unknownProvider"), null);
    const at = endpoints(source, o.via.endpoint, o.via.protocol);
    if (!at) return check("failed", t("station.profile.addressNeeded"), null);
    // Signed in to Kimi: a sign-in no longer renewed, or a token refused, is one to sign in again.
    if (o.login === true && o.key === "") return check("login", t("station.profile.kimiSignedOut"), null);
    const done = await checkApi(source, at, o.key, lang);
    return o.login === true && done.state === "failed" ? check("login", t("station.profile.kimiSignedOut"), null) : done;
  }
  if (o.kind === "subscription" && o.runtime === "claude") {
    const env: Env = { ...o.env, CLAUDE_CONFIG_DIR: o.home };
    let machineToken: string | undefined;
    if (o.machine) {
      if (!o.machineToken) throw new Error("the machine's Claude Code login could not be read");
      machineToken = (await o.machineToken(o.env)).token;
      env.CLAUDE_CODE_OAUTH_TOKEN = machineToken;
    } else {
      await takeBack(o.home);
      fileCredentials(env as Record<string, string>);
    }
    const output = await statusOf("claude", ["auth", "status"], env);
    // Signed out, it says so and exits 1: its answer is still the JSON on stdout.
    if (output.code !== 0 && !(output.code === 1 && output.stdout.trimStart().startsWith("{"))) throw new Error(`Command failed: claude auth status\n${output.stderr}`);
    const status: Json = JSON.parse(output.stdout);
    if (status?.loggedIn !== true) return check("login", t("station.profile.signedOut"), null);
    // What the subscription runs, as Anthropic lists it for the account's own token.
    const token = machineToken ?? (await profileToken(o, urls, lang));
    const models = token === undefined ? null : await claudeModels(urls, token);
    // For a profile in its own home Claude keeps the more specific tier beside its token. Read only that metadata
    // into the check; the token itself stays in the home. A machine login's keychain is handled by MachineLogins.
    let credentials: ReturnType<typeof parseClaudeCredentials> = undefined;
    if (!o.machine) {
      try { credentials = parseClaudeCredentials(readFileSync(join(o.home, ".credentials.json"), "utf8")); } catch {}
    }
    const plan = claudePlan(status.subscriptionType ?? credentials?.subscriptionType, status.rateLimitTier ?? credentials?.rateLimitTier);
    const detail = [t("station.profile.signedIn"), typeof status.email === "string" ? status.email : "", plan ?? ""].filter((s) => s !== "");
    const result = check("ok", detail.join(t("station.list.comma")), models);
    if (plan !== null) result.plan = plan;
    return result;
  }
  if (o.kind === "subscription" && o.runtime === "codex") {
    if (o.machine) linkCodexAuth(o.home, o.env);
    const output = await statusOf("codex", ["login", "status"], { ...o.env, CODEX_HOME: o.home });
    const text = `${output.stdout}${output.stderr}`.trim();
    if (text.toLowerCase().includes("not logged in")) return check("login", t("station.profile.signedOut"), null);
    if (output.code !== 0) throw new Error(`Command failed: codex login status\n${text}`);
    const result = check("ok", text.split("\n")[0] || t("station.profile.signedIn"), null);
    const plan = codexClaims(o.home)?.["https://api.openai.com/auth"]?.chatgpt_plan_type;
    if (typeof plan === "string" && plan.trim() !== "") result.plan = plan.trim();
    return result;
  }
  if (o.kind === "subscription" && o.runtime === "grok") {
    // `grok models` says whether it is signed in, and the account's models (* the default, - the rest).
    const output = await statusOf("grok", ["models"], { ...o.env, GROK_HOME: join(o.home, "grok"), GROK_DISABLE_AUTOUPDATER: "1" });
    const text = `${output.stdout}${output.stderr}`;
    if (/not authenticated|not logged in|sign in/i.test(text)) return check("login", t("station.profile.signedOut"), null);
    if (output.code !== 0) throw new Error(`Command failed: grok models\n${text.trim()}`);
    const models = grokModels(text);
    const email = grokEmail(o.home);
    return check("ok", [t("station.profile.signedIn"), email ?? ""].filter((s) => s !== "").join(t("station.list.comma")), models.length > 0 ? models : null);
  }
  if (o.kind === "subscription" && o.runtime === "cursor") {
    // The key the sign-in minted (cursor.ts), asked of Cursor's API: whose it is, and the models it may run.
    const login = readCursor(o.home);
    if (login === null) return check("login", t("station.profile.signedOut"), null);
    const cursor = urls.cursor ?? CURSOR;
    const me = await cursorMe(cursor, login.apiKey);
    if (me === null) return check("login", t("station.profile.cursorKeyRevoked"), null);
    const models = await cursorModels(cursor, login.apiKey);
    return check("ok", [t("station.profile.signedIn"), me.email ?? login.email ?? ""].filter((s) => s !== "").join(t("station.list.comma")), models);
  }
  if (o.kind === "subscription" && o.runtime === "devin") {
    // `devin auth status` in the profile's data directory says whether it is signed in, and as whom; `devin models list`
    // the account's models, a family at its thinking levels each (agents/devin.ts devinCatalog).
    const env = { ...o.env, XDG_DATA_HOME: devinData(o.home) };
    const status = await statusOf("devin", ["auth", "status"], env);
    const text = `${status.stdout}${status.stderr}`;
    if (/not logged in/i.test(text)) return check("login", t("station.profile.signedOut"), null);
    if (status.code !== 0) throw new Error(`Command failed: devin auth status\n${text.trim()}`);
    const listed = await statusOf("devin", ["models", "list", "--format", "json"], env);
    let catalog: ReturnType<typeof devinCatalog> | null = null;
    try {
      catalog = devinCatalog(JSON.parse(listed.stdout));
    } catch {}
    const email = devinEmailIn(text);
    // Noted for what names the account without asking Devin (devinEmail).
    if (email !== null) {
      try {
        writeFileSync(join(o.home, "devin", "account.json"), `${JSON.stringify({ email })}\n`);
      } catch {}
    }
    const done = check("ok", [t("station.profile.signedIn"), email ?? ""].filter((s) => s !== "").join(t("station.list.comma")), catalog !== null && catalog.models.length > 0 ? catalog.models : null);
    if (catalog !== null) done.modelEfforts = { devin: catalog.efforts };
    return done;
  }
  return check("unknown", t("station.profile.envUnchecked"), null);
}

/// The account `devin auth status` says it is signed in as (its `Email:` line).
export function devinEmailIn(text: string): string | null {
  const m = /^\s*Email:\s*(\S+@\S+)\s*$/m.exec(text);
  return m ? m[1]! : null;
}

/// Whose Devin account a profile signed in to: the email the station noted when it was last checked (account.json in
/// its Devin home), none before.
export function devinEmail(home: string): string | null {
  try {
    return devinNotedIn(readFileSync(devinAccountFile(home), "utf8"));
  } catch {
    return null;
  }
}

/// Where `devinEmail` reads it, and what it says there.
export const devinAccountFile = (home: string) => join(home, "devin", "account.json");
export function devinNotedIn(text: string): string | null {
  const email = JSON.parse(text)?.email;
  return typeof email === "string" && email !== "" ? email : null;
}

/// Whose Cursor account a profile signed in to, as its sign-in kept it (accounts/cursor.ts).
export const cursorEmail = (home: string): string | null => readCursor(home)?.email ?? null;

/// The models `grok models` lists: a line each, `* id (default)` or `- id`.
export function grokModels(text: string): string[] {
  return text.split("\n").flatMap((line) => {
    const m = /^\s*[*-]\s+(\S+)/.exec(line);
    return m ? [m[1]!] : [];
  });
}

/// Whose account Grok Build is signed in with, as its auth.json says (agents/grok.ts: its home is the profile's grok/).
export function grokEmail(home: string): string | null {
  try {
    return grokEmailIn(readFileSync(grokAuthFile(home), "utf8"));
  } catch {
    return null;
  }
}

/// Where `grokEmail` reads it, and what it says there.
export const grokAuthFile = (home: string) => join(home, "grok", "auth.json");
export function grokEmailIn(text: string): string | null {
  const auth: Json = JSON.parse(text);
  for (const entry of Object.values(auth ?? {})) {
    const email = (entry as Json)?.email;
    if (typeof email === "string" && email !== "") return email;
  }
  return null;
}

/// The models a Claude subscription's OAuth token may use; null when Anthropic does not say.
/// A Claude profile's token as it signs in now, renewed first when due (oauth.ts): `auth status` says only that a login
/// is kept, and one that can no longer be renewed throws (RenewRefused: to sign in again). One not renewed now for
/// another reason (the provider, the network) is the one kept.
async function profileToken(o: CheckOptions, urls: Urls, lang: Lang): Promise<string | undefined> {
  try {
    return (await claudeOAuthToken(o.env, o.home, null, urls.claudeToken, lang))[0];
  } catch (e) {
    if (e instanceof RenewRefused) throw e;
    return tokenOf(o.home);
  }
}

async function claudeModels(urls: Urls, token: string): Promise<string[] | null> {
  try {
    const response = await get(`${urls.anthropic}/v1/models?limit=100`, { authorization: `Bearer ${token}`, "anthropic-version": "2023-06-01", "anthropic-beta": "oauth-2025-04-20" });
    return response.ok ? await modelIds(response) : null;
  } catch {
    return null;
  }
}

/// The header OpenCode's gateways ask of every request: any id will do.
export const opencodeSession = (): [string, string] => ["x-opencode-session", randomUUID()];

/// A provider's key, asked by its model list: a refusal (401/403) is a key that does not work; a provider with no list
/// is not held against it, its key is only unchecked.
async function checkApi(source: Source, at: Endpoints, key: string, lang: Lang): Promise<ProfileCheck> {
  const t = (k: string, args?: Record<string, unknown>) => tr(lang, k, args);
  // A decision-only provider has no model list and nothing to name: its key is tried by the decision probe.
  if (at.decision !== undefined && at.chat === undefined && at.responses === undefined && at.anthropic === undefined) {
    return check("ok", t("station.profile.decisionOnly", { provider: source.name }), null);
  }
  const base = at.chat ?? at.responses ?? (at.anthropic !== undefined ? `${at.anthropic}/v1` : undefined);
  if (base === undefined) return check("failed", t("station.profile.addressNeeded"), null);
  const anthropicOnly = at.chat === undefined && at.responses === undefined;
  const headers: Record<string, string> = {};
  if (key !== "") headers.authorization = `Bearer ${key}`;
  if (anthropicOnly) Object.assign(headers, { "x-api-key": key, "anthropic-version": "2023-06-01" });
  if (source.sessionHeader) {
    const [name, value] = opencodeSession();
    headers[name] = value;
  }
  const response = await get(`${base}/models`, headers);
  if (response.status === 401 || response.status === 403) return check("failed", t("station.profile.keyRefused", { provider: source.name, status: response.status }), null);
  if (!response.ok) return check("unknown", t("station.profile.noModelList", { provider: source.name }), null);
  const models = sorted(await modelIds(response));
  return check("ok", t("station.profile.works", { n: models.length }), models);
}
