// How a profile's account reaches its models (mesh/app/src/profiles.rs `access_env`, `codex_overrides`), and the
// environment a profile's runtime is started with, as config.rs parse_config makes it (`envs`: what the access kind
// needs there plus the profile's own variables, which win). A profile here is config.json's, its home made absolute.
import type { Profile } from "./runtime.ts";
import { cleanEndpoint, endpoints, find, runtimesOf, type Endpoints, type Source } from "./providers.ts";

export type AccessKind = "subscription" | "opencode-go" | "anthropic-api" | "env" | "api-provider";
export type Runtime = "claude" | "codex";

/// Which provider an API-provider profile is on, and where.
export type Via = { provider?: string; endpoint?: string; protocol?: string };

/// A profile's fields as the drivers read them (config.json's names).
export type ProfileAccess = { kind?: AccessKind; key?: string; provider?: string; endpoint?: string; protocol?: string };

const str = (v: unknown): string | undefined => (typeof v === "string" && v !== "" ? v : undefined);
const access = (p: Profile): ProfileAccess => (p.access && typeof p.access === "object" ? (p.access as ProfileAccess) : {});

export const accessKind = (p: Profile): AccessKind => access(p).kind ?? "env";
/// Its model, when it names one.
export const profileModel = (p: Profile): string | undefined => str(p.model);
/// On the machine's own login (machine_logins.rs).
export const isMachine = (p: Profile): boolean => p.machine === true;
export const profileFast = (p: Profile): boolean => p.fast === true;
export const profileVia = (p: Profile): Via => {
  const a = access(p);
  return { provider: str(a.provider), endpoint: a.endpoint === undefined ? undefined : cleanEndpoint(a.endpoint), protocol: str(a.protocol) };
};

/// The source of an API-provider profile and where it speaks, when it names a known provider (and a usable address).
export function apiSource(via: Via): [Source, Endpoints] | undefined {
  const source = via.provider === undefined ? undefined : find(via.provider);
  const at = source && endpoints(source, via.endpoint, via.protocol);
  return source && at ? [source, at] : undefined;
}

/// The key the runtimes are given where the profile has none (a provider that works without): they ask for one.
const NO_KEY = "none";
export const OPENCODE = "https://opencode.ai/zen/go";
/// The variable a Codex provider config reads an API provider's key from.
const CODEX_KEY = "EMBER_API_KEY";

/// Environment an access kind needs. `{route}` is expanded per session later.
export function accessEnv(runtime: Runtime, kind: AccessKind, key: string, model: string | undefined, via: Via): Record<string, string> {
  if (kind === "opencode-go" && runtime === "claude") {
    const small = model ?? "deepseek-flash";
    return {
      ANTHROPIC_BASE_URL: OPENCODE,
      ANTHROPIC_API_KEY: key,
      ANTHROPIC_CUSTOM_HEADERS: "x-opencode-session: {route}",
      // Claude Code's background calls use a small model; point it at one the provider has.
      ANTHROPIC_DEFAULT_HAIKU_MODEL: small,
      ANTHROPIC_SMALL_FAST_MODEL: small,
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
    };
  }
  // The provider's session key keeps the name of before the rename: its sessions go on under it.
  if (kind === "opencode-go" && runtime === "codex") return { OPENCODE_GO_KEY: key, OPENCODE_SESSION: "ember-{route}" };
  if (kind === "anthropic-api") return { ANTHROPIC_API_KEY: key };
  if (kind === "api-provider") return apiEnv(runtime, key, model, via);
  return {};
}

/// A provider's key for a runtime, from where the provider speaks: Claude Code reads its Anthropic endpoint, Codex its
/// Responses endpoint (the provider's config is `codexOverrides`).
function apiEnv(runtime: Runtime, key: string, model: string | undefined, via: Via): Record<string, string> {
  const found = apiSource(via);
  if (!found) return {};
  const [source, at] = found;
  const keyOrNone = key === "" ? NO_KEY : key;
  if (runtime === "claude") {
    if (at.anthropic === undefined) return {};
    const env: Record<string, string> = { ANTHROPIC_BASE_URL: at.anthropic };
    if (source.auth === "apiKey") env.ANTHROPIC_API_KEY = keyOrNone;
    // The key is a bearer token; a key variable left unset is not asked about.
    else if (source.auth === "bearer") Object.assign(env, { ANTHROPIC_AUTH_TOKEN: keyOrNone, ANTHROPIC_API_KEY: "" });
    else Object.assign(env, { ANTHROPIC_AUTH_TOKEN: keyOrNone, ANTHROPIC_API_KEY: keyOrNone });
    if (source.sessionHeader) env.ANTHROPIC_CUSTOM_HEADERS = "x-opencode-session: {route}";
    // Claude Code's background calls use a small model; where the profile names one, it is that.
    if (model !== undefined) Object.assign(env, { ANTHROPIC_DEFAULT_HAIKU_MODEL: model, ANTHROPIC_SMALL_FAST_MODEL: model });
    env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    return env;
  }
  if (at.responses === undefined) return {};
  const env: Record<string, string> = { [CODEX_KEY]: keyOrNone };
  if (source.sessionHeader) env.OPENCODE_SESSION = "ember-{route}";
  return env;
}

/// Codex features the station's agents have no use for, off for every profile: apps starts the ChatGPT connectors' MCP
/// server (about 1.5 s of a new thread's start); recommended_plugins lists plugins not installed (KBs of prompt).
const CODEX_FEATURES_OFF: [string, string][] = [
  ["features.apps", "false"],
  ["features.recommended_plugins", "false"],
];

/// Codex reads its model provider from config; the station passes it as `-c` overrides when it starts the app-server,
/// so config.toml stays the user's. Values are TOML. In key order (a BTreeMap in Rust).
export function codexOverrides(kind: AccessKind, model: string | undefined, via: Via): [string, string][] {
  const out = new Map<string, string>(CODEX_FEATURES_OFF);
  const sorted = () => [...out.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  if (kind === "api-provider") {
    // Codex keeps its own names for the providers it has built in (openai among them): this one is just `api`.
    const found = apiSource(via);
    if (!found || found[1].responses === undefined) return sorted();
    const [source, at] = found;
    out.set("model_provider", '"api"');
    if (model !== undefined) out.set("model", JSON.stringify(model));
    out.set("model_providers.api.name", JSON.stringify(source.name));
    out.set("model_providers.api.base_url", JSON.stringify(at.responses));
    out.set("model_providers.api.env_key", `"${CODEX_KEY}"`);
    out.set("model_providers.api.wire_api", '"responses"');
    if (source.sessionHeader) out.set("model_providers.api.env_http_headers", '{"x-opencode-session"="OPENCODE_SESSION"}');
    return sorted();
  }
  if (kind !== "opencode-go") return sorted();
  out.set("model_provider", '"opencode-go"');
  if (model !== undefined) out.set("model", JSON.stringify(model));
  out.set("model_providers.opencode-go.name", '"OpenCode Go"');
  out.set("model_providers.opencode-go.base_url", `"${OPENCODE}/v1"`);
  out.set("model_providers.opencode-go.env_key", '"OPENCODE_GO_KEY"');
  out.set("model_providers.opencode-go.wire_api", '"responses"');
  out.set("model_providers.opencode-go.env_http_headers", '{"x-opencode-session"="OPENCODE_SESSION"}');
  return sorted();
}

/// The runtimes an account runs (profiles.rs runtimes_for): an OpenCode Go key both, an Anthropic key Claude Code, a
/// provider's what it speaks; a subscription (and custom variables) the runtime it was made for.
export function profileRuntimes(p: Profile): Runtime[] {
  const kind = accessKind(p);
  if (kind === "api-provider") {
    const found = apiSource(profileVia(p));
    return found ? runtimesOf(found[1]) : [];
  }
  if (kind === "opencode-go") return ["claude", "codex"];
  if (kind === "anthropic-api") return ["claude"];
  return p.runtime === "claude" || p.runtime === "codex" ? [p.runtime] : [];
}

/// The environment for a profile's processes of `runtime` (config.rs `envs`, Profile::env): none for a runtime it does
/// not run. In values, `{route}` is still to be expanded.
export function profileEnv(p: Profile, runtime: Runtime): Record<string, string> {
  if (!profileRuntimes(p).includes(runtime)) return {};
  const key = (access(p).key ?? "").trim();
  const custom = p.env && typeof p.env === "object" ? (p.env as Record<string, string>) : {};
  return { ...accessEnv(runtime, accessKind(p), key, profileModel(p), profileVia(p)), ...custom };
}

export const expandRoute = (env: Record<string, string>, route: string): Record<string, string> =>
  Object.fromEntries(Object.entries(env).map(([k, v]) => [k, v.replaceAll("{route}", route)]));

/// Both names of a variable the station sets for what it starts (former.rs `both`): the new one, and the old one for
/// scripts written against it.
export const bothNames = (name: string): [string, string] => [`STILLFAIL_${name}`, `EMBER_${name}`];
