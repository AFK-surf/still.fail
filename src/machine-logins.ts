// Who this machine's own Claude Code and Codex are signed in as (in their usual homes, ~/.claude and ~/.codex), for
// the pages that ask for a first profile to say so. Only read: ember's profiles never take these credentials over
// (copying them would fork each vendor's single-use refresh tokens and sign the machine's own CLI out later).
import { execFile } from "node:child_process";
import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
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

async function claudeLogin(env: NodeJS.ProcessEnv): Promise<MachineLogin> {
  const base = { runtime: "claude" as const, email: null, plan: null };
  try {
    const { stdout } = await run("claude", ["auth", "status"], {
      env: machineEnv(env, ["CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"]), timeout: 20_000,
    });
    const status = JSON.parse(stdout) as { loggedIn?: boolean; email?: string; subscriptionType?: string };
    if (!status.loggedIn) return { ...base, installed: true, loggedIn: false, text: `${LABEL.claude} 没有登录` };
    const email = status.email ?? null, plan = status.subscriptionType ?? null;
    return { ...base, installed: true, loggedIn: true, email, plan, text: said(LABEL.claude, email, plan) };
  } catch (error) {
    // `auth status` exits non-zero when signed out, still printing its JSON.
    const stdout = (error as { stdout?: string }).stdout;
    if (stdout?.includes("loggedIn")) return { ...base, installed: true, loggedIn: false, text: `${LABEL.claude} 没有登录` };
    return missing(error) ? { ...base, installed: false, loggedIn: false, text: `没有装 ${LABEL.claude}` }
      : { ...base, installed: true, loggedIn: false, text: `读不到 ${LABEL.claude} 的登录` };
  }
}

async function codexLogin(env: NodeJS.ProcessEnv): Promise<MachineLogin> {
  const base = { runtime: "codex" as const, email: null, plan: null };
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
  return { ...base, installed: true, loggedIn: true, email, plan, text: said(LABEL.codex, email, plan) };
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
