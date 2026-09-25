// How a runtime account reaches its models. A profile picks one access kind;
// ember derives the environment (and, for Codex, provider config overrides)
// from it, so nobody has to know which variables each runtime reads. "env"
// keeps the raw form for anything else.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { RuntimeKind } from "./config.ts";

export type AccessKind = "subscription" | "opencode-go" | "anthropic-api" | "env";

export const ACCESS_KINDS: Record<RuntimeKind, readonly AccessKind[]> = {
  claude: ["subscription", "opencode-go", "anthropic-api", "env"],
  codex: ["subscription", "opencode-go", "env"],
};

/** Access kinds that authenticate with a key the profile stores. */
export const KEYED: ReadonlySet<AccessKind> = new Set(["opencode-go", "anthropic-api"]);

const OPENCODE = "https://opencode.ai/zen/go";

/** Environment an access kind needs. `{route}` is expanded per session later. */
export function accessEnv(runtime: RuntimeKind, kind: AccessKind, key: string, model: string | undefined): Record<string, string> {
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
  if (kind === "opencode-go" && runtime === "codex") return { OPENCODE_GO_KEY: key, OPENCODE_SESSION: "ember-{route}" };
  if (kind === "anthropic-api") return { ANTHROPIC_API_KEY: key };
  return {};
}

/**
 * Codex reads its model provider from config; ember passes it as `-c`
 * overrides when it starts the app-server, so config.toml stays the user's.
 * Values are TOML.
 */
export function codexOverrides(kind: AccessKind, model: string | undefined): Record<string, string> {
  if (kind !== "opencode-go") return {};
  return {
    model_provider: `"opencode-go"`,
    ...(model ? { model: JSON.stringify(model) } : {}),
    "model_providers.opencode-go.name": `"OpenCode Go"`,
    "model_providers.opencode-go.base_url": `"${OPENCODE}/v1"`,
    "model_providers.opencode-go.env_key": `"OPENCODE_GO_KEY"`,
    "model_providers.opencode-go.wire_api": `"responses"`,
    "model_providers.opencode-go.env_http_headers": `{"x-opencode-session"="OPENCODE_SESSION"}`,
  };
}

export interface ProfileCheck {
  /** ok: usable; login: needs a subscription sign-in; failed: the key or login was rejected. */
  state: "ok" | "login" | "failed" | "unknown";
  detail: string;
  /** Models the account can use, when the provider lists them. */
  models: string[] | null;
  checkedAt: number;
}

const run = promisify(execFile);

/** Asks the provider or runtime whether this profile works, and what models it offers. */
export async function checkProfile(options: {
  runtime: RuntimeKind; kind: AccessKind; key: string; home: string; env: NodeJS.ProcessEnv;
}): Promise<ProfileCheck> {
  const checkedAt = Date.now();
  try {
    if (options.kind === "opencode-go") {
      const response = await fetch(`${OPENCODE}/v1/models`, { headers: { authorization: `Bearer ${options.key}` }, signal: AbortSignal.timeout(15_000) });
      if (!response.ok) return { state: "failed", detail: `OpenCode Go 拒绝了这个 key（${response.status}）`, models: null, checkedAt };
      const body = await response.json() as { data?: { id: string }[] };
      const models = (body.data ?? []).map((m) => m.id).sort();
      return { state: "ok", detail: `可用，${models.length} 个模型`, models, checkedAt };
    }
    if (options.kind === "anthropic-api") {
      const response = await fetch("https://api.anthropic.com/v1/models?limit=100", {
        headers: { "x-api-key": options.key, "anthropic-version": "2023-06-01" }, signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) return { state: "failed", detail: `Anthropic 拒绝了这个 key（${response.status}）`, models: null, checkedAt };
      const body = await response.json() as { data?: { id: string }[] };
      const models = (body.data ?? []).map((m) => m.id);
      return { state: "ok", detail: `可用，${models.length} 个模型`, models, checkedAt };
    }
    if (options.kind === "subscription" && options.runtime === "claude") {
      const { stdout } = await run("claude", ["auth", "status"], { env: { ...options.env, CLAUDE_CONFIG_DIR: options.home }, timeout: 20_000 });
      const status = JSON.parse(stdout) as { loggedIn?: boolean; authMethod?: string; email?: string; subscriptionType?: string };
      return status.loggedIn
        ? { state: "ok", detail: ["已登录", status.email, status.subscriptionType].filter(Boolean).join("，"), models: null, checkedAt }
        : { state: "login", detail: "还没登录", models: null, checkedAt };
    }
    if (options.kind === "subscription" && options.runtime === "codex") {
      const { stdout, stderr } = await run("codex", ["login", "status"], { env: { ...options.env, CODEX_HOME: options.home }, timeout: 20_000 });
      const text = `${stdout}${stderr}`.trim();
      return /not logged in/i.test(text)
        ? { state: "login", detail: "还没登录", models: null, checkedAt }
        : { state: "ok", detail: text.split("\n")[0] ?? "已登录", models: null, checkedAt };
    }
    return { state: "unknown", detail: "自定义环境变量，ember 无法自动检查", models: null, checkedAt };
  } catch (error) {
    return { state: "failed", detail: `检查失败：${error instanceof Error ? error.message : String(error)}`, models: null, checkedAt };
  }
}

/** The command to sign a subscription profile in, run on the ember host. */
export function loginCommand(runtime: RuntimeKind, home: string): string {
  return runtime === "claude" ? `CLAUDE_CONFIG_DIR=${home} claude auth login` : `CODEX_HOME=${home} codex login`;
}
