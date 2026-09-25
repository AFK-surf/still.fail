// How a runtime account reaches its models. A profile picks one access kind;
// ember derives the environment (and, for Codex, the provider section of
// config.toml) from it, so nobody has to know which variables each runtime
// reads. "env" keeps the raw form for anything else.
import { execFile } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";
import type { Profile, RuntimeKind } from "./config.ts";

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

const MANAGED = "# Managed by ember for this profile's access; edits are replaced. Delete this line to take over the file.";

/** Codex reads its provider from config.toml; write it for access kinds that need one. */
export function codexConfig(kind: AccessKind, model: string | undefined): string | null {
  if (kind !== "opencode-go") return null;
  return [
    MANAGED,
    `model = "${model ?? "deepseek-flash"}"`,
    `model_provider = "opencode-go"`,
    ``,
    `[model_providers.opencode-go]`,
    `name = "OpenCode Go"`,
    `base_url = "${OPENCODE}/v1"`,
    `env_key = "OPENCODE_GO_KEY"`,
    `wire_api = "responses"`,
    `env_http_headers = { "x-opencode-session" = "OPENCODE_SESSION" }`,
    ``,
  ].join("\n");
}

/**
 * Writes the managed config.toml of a codex profile. A file someone wrote by
 * hand (no managed marker) is left alone; returns whether it was written.
 */
export function prepareCodexHome(home: string, kind: AccessKind, model: string | undefined): boolean {
  const content = codexConfig(kind, model);
  if (!content) return false;
  const path = join(home, "config.toml");
  if (existsSync(path)) {
    const current = readFileSync(path, "utf8");
    if (current === content) return false;
    if (!current.startsWith(MANAGED)) return false;
  }
  mkdirSync(home, { recursive: true });
  writeFileSync(path, content);
  return true;
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

/** Writes what each profile's access kind needs into its home (codex provider config). */
export function prepareProfileHomes(profiles: readonly Profile[]): void {
  for (const p of profiles) if (p.runtime === "codex") prepareCodexHome(p.home, p.access.kind, p.model);
}

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
