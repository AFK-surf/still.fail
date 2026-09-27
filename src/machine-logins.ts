// Who this machine's own Claude Code and Codex are signed in as (in their usual homes, ~/.claude and ~/.codex), for
// the pages that ask for a first profile to say so, and the way a profile uses that login itself (`machine`
// profiles). Never copied: both vendors rotate single-use refresh tokens, so a copy would sign one side out later.
// - Codex: the profile's home links auth.json to the machine's; Codex saves it in place (through the link) and reads
//   it again before refreshing, so both share one login.
// - Claude Code: a link does not hold (it replaces the file when it refreshes), so the profile's processes are handed
//   the machine's current access token (CLAUDE_CODE_OAUTH_TOKEN) and never refresh; when it is about to run out, the
//   machine's own claude is asked for a moment, which refreshes it in its own file.
// Only logins kept in files: one in the macOS keychain cannot be used so (the pages offer a sign-in instead).
import { execFile } from "node:child_process";
import { EventEmitter } from "node:events";
import { existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, rmSync, symlinkSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import type { RuntimeKind } from "./config.ts";
import { log } from "./log.ts";

const run = promisify(execFile);

export interface MachineLogin {
  runtime: RuntimeKind;
  /** Its command is on the station's PATH. */
  installed: boolean;
  /** Signed in with an account (a subscription or a key). */
  loggedIn: boolean;
  /** The account's email, when its files say. */
  email: string | null;
  /** The subscription's plan (max, pro, plus…), when known. */
  plan: string | null;
  /** A profile can use it as it is (kept in a file, not only in the keychain). */
  usable: boolean;
  /** In a line, as the pages show it. */
  text: string;
}

/** How long a reading serves before the next overview reads again (in the background). */
const FRESH_MS = 2 * 60_000;

const LABEL: Record<RuntimeKind, string> = { claude: "Claude Code", codex: "Codex" };

/**
 * The machine's logins, read now and then: `get` answers at once with the last reading and reads again when it is old;
 * `changes` says "change" when a reading differs from the last.
 */
export class MachineLogins {
  readonly changes = new EventEmitter();
  #value: MachineLogin[] = [];
  #at = 0;
  #reading: Promise<void> | null = null;
  readonly #env: NodeJS.ProcessEnv;

  constructor(env: NodeJS.ProcessEnv = process.env) {
    this.#env = env;
  }

  get(): MachineLogin[] {
    if (Date.now() - this.#at > FRESH_MS) void this.refresh();
    return this.#value;
  }

  refresh(): Promise<void> {
    this.#reading ??= Promise.all([claudeLogin(this.#env), codexLogin(this.#env)])
      .then((logins) => {
        const changed = JSON.stringify(logins) !== JSON.stringify(this.#value);
        this.#value = logins;
        this.#at = Date.now();
        if (changed) this.changes.emit("change");
      })
      .catch((error: unknown) => log.warn("could not read the machine's logins", { error: String(error) }))
      .finally(() => { this.#reading = null; });
    return this.#reading;
  }
}

/** The environment the machine's own CLI would run in: none of what points it at another home or account. */
function machineEnv(env: NodeJS.ProcessEnv, drop: readonly string[]): NodeJS.ProcessEnv {
  const out = { ...env };
  for (const name of drop) delete out[name];
  return out;
}

function missing(error: unknown): boolean {
  return (error as NodeJS.ErrnoException)?.code === "ENOENT";
}

const CLAUDE_DROP = ["CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"];

/** Where the machine's Claude Code keeps its login when it keeps it in a file. */
export function claudeCredentialsFile(env: NodeJS.ProcessEnv = process.env): string {
  return join(env.HOME || homedir(), ".claude", ".credentials.json");
}

/** Where the machine's Codex keeps its login when it keeps it in a file. */
export function codexAuthFile(env: NodeJS.ProcessEnv = process.env): string {
  return join(env.CODEX_HOME || join(env.HOME || homedir(), ".codex"), "auth.json");
}

async function claudeLogin(env: NodeJS.ProcessEnv): Promise<MachineLogin> {
  const base = { runtime: "claude" as const, email: null, plan: null, usable: false };
  try {
    const { stdout } = await run("claude", ["auth", "status"], { env: machineEnv(env, CLAUDE_DROP), timeout: 20_000 });
    const status = JSON.parse(stdout) as { loggedIn?: boolean; email?: string; subscriptionType?: string };
    if (!status.loggedIn) return { ...base, installed: true, loggedIn: false, text: `${LABEL.claude} 没有登录` };
    const email = status.email ?? null, plan = status.subscriptionType ?? null;
    const usable = readClaudeCredentials(env) !== null;
    return { ...base, installed: true, loggedIn: true, email, plan, usable, text: said(LABEL.claude, email, plan) + (usable ? "" : "，登录存在钥匙串里") };
  } catch (error) {
    // `auth status` exits non-zero when signed out, still printing its JSON.
    const stdout = (error as { stdout?: string }).stdout;
    if (stdout?.includes("loggedIn")) return { ...base, installed: true, loggedIn: false, text: `${LABEL.claude} 没有登录` };
    return missing(error) ? { ...base, installed: false, loggedIn: false, text: `没有装 ${LABEL.claude}` }
      : { ...base, installed: true, loggedIn: false, text: `读不到 ${LABEL.claude} 的登录` };
  }
}

async function codexLogin(env: NodeJS.ProcessEnv): Promise<MachineLogin> {
  const base = { runtime: "codex" as const, email: null, plan: null, usable: false };
  const home = env.CODEX_HOME || join(env.HOME || homedir(), ".codex");
  let text: string;
  try {
    const out = await run("codex", ["login", "status"], { env: machineEnv({ ...env, CODEX_HOME: home }, ["OPENAI_API_KEY", "CODEX_API_KEY"]), timeout: 20_000 });
    text = `${out.stdout}${out.stderr}`;
  } catch (error) {
    if (missing(error)) return { ...base, installed: false, loggedIn: false, text: `没有装 ${LABEL.codex}` };
    // `login status` exits non-zero when signed out.
    text = `${(error as { stdout?: string }).stdout ?? ""}${(error as { stderr?: string }).stderr ?? ""}`;
  }
  if (!/logged in/i.test(text) || /not logged in/i.test(text)) return { ...base, installed: true, loggedIn: false, text: `${LABEL.codex} 没有登录` };
  const { email, plan } = codexAccount(home);
  const usable = existsSync(join(home, "auth.json"));
  return { ...base, installed: true, loggedIn: true, email, plan, usable, text: said(LABEL.codex, email, plan) + (usable ? "" : "，登录存在钥匙串里") };
}

/** The machine's Claude Code login as its file keeps it: its access token and when that runs out. */
function readClaudeCredentials(env: NodeJS.ProcessEnv): { token: string; expiresAt: number } | null {
  try {
    const o = (JSON.parse(readFileSync(claudeCredentialsFile(env), "utf8")) as { claudeAiOauth?: { accessToken?: string; expiresAt?: number } }).claudeAiOauth;
    return o?.accessToken ? { token: o.accessToken, expiresAt: Number(o.expiresAt) || 0 } : null;
  } catch {
    return null;
  }
}

/**
 * How close to running out a token is taken as run out: Claude Code refreshes its own this close to the end, so a
 * moment of it refreshes then, and a process handed one this close is started again for its next turn.
 */
export const CLAUDE_TOKEN_MARGIN_MS = 5 * 60_000;

let refreshing: Promise<void> | null = null;

/**
 * The machine's Claude Code access token for a profile's process, refreshed first (by the machine's own claude, in
 * its own file) when it is about to run out. Throws, in words for the chat, when there is none to use.
 */
export async function machineClaudeToken(env: NodeJS.ProcessEnv = process.env): Promise<{ token: string; expiresAt: number }> {
  let credentials = readClaudeCredentials(env);
  if (!credentials) throw new Error("这台机器上的 Claude Code 没有登录（或者登录存在钥匙串里），要在 station 上重新登录");
  if (credentials.expiresAt - Date.now() > CLAUDE_TOKEN_MARGIN_MS) return credentials;
  refreshing ??= refreshClaude(env).finally(() => { refreshing = null; });
  await refreshing;
  credentials = readClaudeCredentials(env);
  if (!credentials || credentials.expiresAt <= Date.now()) throw new Error("这台机器上 Claude Code 的登录过期了，没能刷新：在 station 上运行一次 claude 看看");
  return credentials;
}

/**
 * The machine's own claude, asked for a word with the smallest model: it refreshes its login on the way (in its own
 * file, as it always does). Kept out of its history.
 */
async function refreshClaude(env: NodeJS.ProcessEnv): Promise<void> {
  log.info("refreshing the machine's Claude Code login");
  try {
    const child = execFile("claude", ["-p", "--model", "haiku", "--no-session-persistence", "Reply with one word: ok"], {
      env: machineEnv(env, CLAUDE_DROP), cwd: tmpdir(), timeout: 120_000,
    });
    child.stdin?.end();
    await new Promise<void>((resolve, reject) => {
      child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`claude exited (${code})`))));
      child.on("error", reject);
    });
  } catch (error) {
    log.warn("could not refresh the machine's Claude Code login", { error: String(error) });
  }
}

/**
 * A machine profile's Codex home, sharing the machine's login: its auth.json a link to the machine's. Made again when
 * something replaced it (a sign-in in the home, say).
 */
export function linkCodexAuth(home: string, env: NodeJS.ProcessEnv = process.env): void {
  const target = codexAuthFile(env);
  const link = join(home, "auth.json");
  mkdirSync(home, { recursive: true });
  try {
    if (lstatSync(link).isSymbolicLink() && readlinkSync(link) === target) return;
    rmSync(link, { force: true });
  } catch {
    // none yet
  }
  symlinkSync(target, link);
}

/** The account in Codex's auth.json: its id token's email and ChatGPT plan (none for an API key, or in the keyring). */
function codexAccount(home: string): { email: string | null; plan: string | null } {
  try {
    const auth = JSON.parse(readFileSync(join(home, "auth.json"), "utf8")) as { tokens?: { id_token?: string } };
    const payload = auth.tokens?.id_token?.split(".")[1];
    if (!payload) return { email: null, plan: null };
    const claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as Record<string, any>;
    return {
      email: claims.email ?? claims["https://api.openai.com/profile"]?.email ?? null,
      plan: claims["https://api.openai.com/auth"]?.chatgpt_plan_type ?? null,
    };
  } catch {
    return { email: null, plan: null };
  }
}

function said(label: string, email: string | null, plan: string | null): string {
  return `${label} 已登录${email ? ` ${email}` : ""}${plan ? `（${plan[0]!.toUpperCase()}${plan.slice(1)}）` : ""}`;
}
