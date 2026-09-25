// Signing a subscription profile in from the admin page. The runtime's own
// login command runs here, on the machine ember runs on, so the credentials
// land in the profile's home; the page only relays what the person has to do
// in their browser:
// - Claude: `claude auth login` prints an authorize link; after approving, the
//   browser shows a code, which the person pastes back and ember types in.
// - Codex: `codex login --device-auth` prints a link and a one-time code; the
//   person enters the code on that page and the command finishes by itself.
// A stand-in `open` on PATH keeps the commands from opening a browser on the
// server.
import { spawn, type ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Profile } from "./config.ts";
import { log } from "./log.ts";

export type LoginState =
  /** Started; waiting for the command to say where to sign in. */
  | "starting"
  /** Claude: the person approves in the browser and pastes the code shown there. */
  | "needs_code"
  /** Codex: the person enters `userCode` at `url`; the command waits for it. */
  | "needs_approval"
  /** The code was sent; the command is finishing. */
  | "verifying"
  | "done"
  | "failed"
  | "cancelled";

export interface LoginJob {
  profile: string;
  runtime: Profile["runtime"];
  state: LoginState;
  url: string | null;
  userCode: string | null;
  error: string | null;
  startedAt: number;
  expiresAt: number;
}

const TIMEOUT_MS = 15 * 60_000;
const ANSI = /\x1b\[[0-9;?]*[A-Za-z]/g;
/** Variables that would make the login command talk to something other than the subscription. */
const SCRUBBED = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CONFIG_DIR", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CODEX_HOME", "OPENAI_API_KEY"];

interface Running {
  job: LoginJob;
  child: ChildProcess;
  output: string;
  timer: ReturnType<typeof setTimeout>;
}

export class LoginManager {
  /** Emits "change" with a profile id whenever its login job changes. */
  readonly changes = new EventEmitter();
  readonly #jobs = new Map<string, Running>();
  readonly #finished = new Map<string, LoginJob>();
  readonly #noBrowserDir: string;
  readonly #commands: { claude: string; codex: string };

  constructor(dataDir: string, commands = { claude: "claude", codex: "codex" }) {
    this.#noBrowserDir = join(dataDir, "run", "no-browser");
    this.#commands = commands;
  }

  get(profile: string): LoginJob | null {
    return this.#jobs.get(profile)?.job ?? this.#finished.get(profile) ?? null;
  }

  /** Starts a sign-in for a subscription profile, replacing any running one. */
  start(profile: Profile): LoginJob {
    this.cancel(profile.id);
    this.#finished.delete(profile.id);
    mkdirSync(profile.home, { recursive: true });
    const env: NodeJS.ProcessEnv = { ...process.env };
    for (const name of SCRUBBED) delete env[name];
    env.PATH = `${this.#noBrowser()}:${env.PATH ?? ""}`;
    env.BROWSER = join(this.#noBrowser(), "open");
    const [command, args] = profile.runtime === "claude"
      ? [this.#commands.claude, ["auth", "login", "--claudeai"]]
      : [this.#commands.codex, ["login", "--device-auth"]];
    if (profile.runtime === "claude") env.CLAUDE_CONFIG_DIR = profile.home;
    else env.CODEX_HOME = profile.home;

    const now = Date.now();
    const job: LoginJob = {
      profile: profile.id, runtime: profile.runtime, state: "starting", url: null, userCode: null, error: null,
      startedAt: now, expiresAt: now + TIMEOUT_MS,
    };
    const child = spawn(command, args, { cwd: profile.home, env, stdio: ["pipe", "pipe", "pipe"] });
    const running: Running = { job, child, output: "", timer: setTimeout(() => this.#fail(profile.id, "15 分钟内没有完成登录，已取消。"), TIMEOUT_MS) };
    this.#jobs.set(profile.id, running);
    const onData = (chunk: Buffer) => {
      running.output = (running.output + chunk.toString("utf8").replace(ANSI, "")).slice(-8000);
      this.#parse(running);
    };
    child.stdout!.on("data", onData);
    child.stderr!.on("data", onData);
    child.on("error", (error) => this.#fail(profile.id, `无法运行登录命令：${error.message}`));
    child.on("exit", (code) => {
      if (this.#jobs.get(profile.id) !== running) return;
      if (code === 0) this.#finish(profile.id, "done", null);
      else this.#fail(profile.id, lastLines(running.output) || `登录命令退出（${code}）`);
    });
    log.info("login started", { profile: profile.id, runtime: profile.runtime });
    this.#emit(profile.id);
    return job;
  }

  /** Claude only: the code the browser showed after approving. */
  submitCode(profile: string, code: string): LoginJob {
    const running = this.#jobs.get(profile);
    if (!running || running.job.state !== "needs_code") throw new Error("这个账号没有在等授权码");
    const clean = code.trim();
    if (!clean) throw new Error("授权码是空的");
    running.child.stdin!.write(`${clean}\n`);
    running.job.state = "verifying";
    this.#emit(profile);
    return running.job;
  }

  cancel(profile: string): void {
    const running = this.#jobs.get(profile);
    if (!running) return;
    this.#finish(profile, "cancelled", null);
  }

  stopAll(): void {
    for (const id of [...this.#jobs.keys()]) this.cancel(id);
  }

  #parse(running: Running): void {
    const { job, output } = running;
    if (job.state !== "starting") return;
    if (job.runtime === "claude") {
      const url = /https:\/\/\S+\/oauth\/authorize\?\S+/.exec(output)?.[0];
      if (url && /Paste code/i.test(output)) {
        job.url = url;
        job.state = "needs_code";
        this.#emit(job.profile);
      }
    } else {
      const url = /https:\/\/auth\.openai\.com\/\S*device\S*/.exec(output)?.[0];
      const code = /\b([A-Z0-9]{4}-[A-Z0-9]{4,6})\b/.exec(output)?.[1];
      if (url && code) {
        job.url = url;
        job.userCode = code;
        job.state = "needs_approval";
        this.#emit(job.profile);
      }
    }
  }

  #fail(profile: string, error: string): void {
    this.#finish(profile, "failed", error);
  }

  #finish(profile: string, state: "done" | "failed" | "cancelled", error: string | null): void {
    const running = this.#jobs.get(profile);
    if (!running) return;
    this.#jobs.delete(profile);
    clearTimeout(running.timer);
    if (running.child.exitCode === null) running.child.kill("SIGTERM");
    running.job.state = state;
    running.job.error = error;
    this.#finished.set(profile, running.job);
    log.info("login ended", { profile, state, error });
    this.#emit(profile);
  }

  #emit(profile: string): void {
    this.changes.emit("change", profile);
  }

  /** A directory whose `open` and `xdg-open` do nothing, put first on the login command's PATH. */
  #noBrowser(): string {
    mkdirSync(this.#noBrowserDir, { recursive: true });
    for (const name of ["open", "xdg-open"]) {
      const path = join(this.#noBrowserDir, name);
      writeFileSync(path, "#!/bin/sh\nexit 0\n");
      chmodSync(path, 0o755);
    }
    return this.#noBrowserDir;
  }
}

function lastLines(output: string): string {
  return output.trim().split("\n").filter((l) => l.trim()).slice(-4).join("\n").slice(0, 600);
}
