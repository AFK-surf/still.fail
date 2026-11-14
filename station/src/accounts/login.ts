// Signing a subscription profile in from the pages. The runtime's own login command runs here,
// on the station's machine, so the credentials land in the profile's home; the page only relays what the person has to
// do in their browser:
// - Claude: `claude auth login` prints an authorize link; after approving, the browser shows a code, which the person
//   pastes back and the station types in.
// - Codex: `codex login --device-auth` prints a link and a one-time code; the person enters the code on that page and
//   the command finishes by itself.
// - Grok Build: `grok login --device-auth` the same, its link at accounts.x.ai with the code in it; its home is the
//   profile's grok/ (agents/grok.ts).
// - Devin: `devin auth login --force-manual-token-flow` prints a link at app.devin.ai; after signing in, the page shows a
//   code the person pastes back, as Claude's. It reads the code only from a terminal: it runs in one (platform.terminal).
//   Its sign-in lands in the profile's devin/data/ (XDG_DATA_HOME, agents/devin.ts).
// - Antigravity CLI: no login command; `agy` itself, in a terminal of its own as Devin's, with the profile's agy/ as its
//   HOME (where it then keeps the sign-in in a file: the keychain is the user's home's), asks how to sign in (the station answers its first choice, Google OAuth), prints a link at accounts.google.com and reads
//   back the code the page shows, which the person pastes, as Claude's. It goes on into its interface once signed in:
//   the sign-in is done when its file is written (agents/agy.ts agyToken), and the command and those between stopped.
// - OpenCode Go (`startConsole`): no command; the station asks the OpenCode Console for a code itself (console.ts) and
//   keeps asking until it is approved, then leaves the tokens in the profile's home. The page shows it as Codex's.
// - Kimi Code (`startKimi`): the same with Kimi's device grant (kimi.ts).
// - Cursor (`startCursor`): no command either; the station makes the login's page itself (accounts/cursor.ts), with no
//   code to enter: the person confirms it there, the station mints the profile's key and keeps it in its home.
// A stand-in `open` on PATH keeps the commands from opening a browser on the server; it writes down the page a command
// would have opened, which the station's own browser opens when a person asks (logins/pages.ts: Claude's comes back
// to the command's loopback port, with no code to paste). Who follows hears each change of a job (`changes`): pushed,
// not asked again.
import type { Clock } from "effect";
import { type ChildProcess, spawn } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileCredentials } from "../agents/no-keychain.ts";
import { CONSOLE, type ConsoleLogin, type Device, type DeviceAnswer, deviceToken, startDevice, type Token, whoIs, writeConsole } from "./console.ts";
import { KIMI_AUTH, kimiDeviceToken, newDeviceId, readKimi, startKimiDevice, writeKimi } from "./kimi.ts";
import { CURSOR, type CursorUrls, cursorHandshake, mintCursorKey, pollCursor, writeCursor } from "./cursor.ts";
import { cleanEnv } from "../agents/runtime.ts";
import { devinData } from "../agents/devin.ts";
import { agyHome, agyToken, noteAgyEmail } from "../agents/agy.ts";
import type { Runtime } from "../agents/profiles.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { withShellCommand } from "../ops/shell-path.ts";
import { Fibers, wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";
import { started } from "../platform/processes.ts";
import { loopbackOf, urlsIn, webPage } from "../ops/command-output.ts";
import type { LoginPages } from "../logins/pages.ts";

export type LoginState = "starting" | "needs_code" | "needs_approval" | "verifying" | "done" | "failed" | "cancelled";

export type LoginJob = {
  profile: string;
  runtime: Runtime;
  /// Signing in to OpenCode (an OpenCode Go profile) or Kimi (a Kimi Code profile) rather than the runtime's
  /// subscription (absent: the runtime's).
  provider?: "opencode" | "kimi";
  state: LoginState;
  url: string | null;
  userCode: string | null;
  error: string | null;
  startedAt: number;
  expiresAt: number;
  /// Its page can be opened in the station's browser now (`openPage`).
  browser?: boolean;
  /// The screen of the tab its page is open in, in the station's browser, while it is.
  screen?: string;
};

/// A sign-in's tab in the station's browser (logins/pages.ts) is known by this.
const pageKey = (profile: string) => `profile:${profile}`;

const TIMEOUT_MS = 15 * 60_000;
/// Variables that would make the login command talk to something other than the subscription.
const SCRUBBED = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CONFIG_DIR", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CODEX_HOME", "OPENAI_API_KEY", "GROK_HOME", "GROK_AUTH", "GROK_AUTH_PATH", "XAI_API_KEY", "WINDSURF_API_KEY", "XDG_DATA_HOME", "GEMINI_API_KEY", "GOOGLE_API_KEY", "AGY_ADC_AUTH", "AGY_ACCOUNT"];
/// The terminal Devin's login runs in: wide, so that its link is printed on one line.
const DEVIN_COLS = 1000;
const DEVIN_ROWS = 40;

/// The login commands, by runtime.
export type LoginCommands = { claude: string; codex: string; grok?: string; devin?: string; agy?: string };
/// How often the Antigravity CLI's sign-in file is looked for once its code went in, and for how long.
const AGY_POLL_MS = 500;
const AGY_WAIT_MS = 90_000;

/// Where a profile keeps the cookies and passkeys of its sign-in tab in the station's browser, inside its own home.
export const LOGIN_BROWSER_FILE = ".stillfail-login-state.json";

/// What a sign-in is for: a profile's id, the runtime it signs in to, its home, and (for Claude) the account email to
/// pre-populate on the authorize page when known.
export type LoginProfile = { id: string; runtime: Runtime; home: string; email?: string | null };

/// A sign-in under way: its command (none for OpenCode's, which `stop` ends), and the file its stand-in browser writes
/// the pages it opens to.
type Running = { run: number; job: LoginJob; child: ChildProcess | null; raw: string; output: string; cancelTimer: () => void; exited: boolean; lang: Lang; stop?: () => void; opened?: string; home?: string; chose?: boolean };

export class LoginManager {
  private jobs = new Map<string, Running>();
  private finished = new Map<string, LoginJob>();
  private listeners = new Set<(profile: string) => void>();
  private runs = 0;
  private noBrowserDir: string;
  private commands: LoginCommands;
  private background: Fibers;
  /// The environment the commands start from; variables that point a login elsewhere are removed at start.
  private env: () => Record<string, string>;

  /// The OpenCode Console signed in to (console.ts CONSOLE; a test's stand-in).
  private console: string;
  /// Kimi's sign-in server (kimi.ts KIMI_AUTH; a test's stand-in).
  private kimi: string;
  /// Cursor signed in to (cursor.ts CURSOR; a test's stand-in), and the name its key is given (the station's).
  private cursor: CursorUrls;
  private keyName: () => string;
  /// Where a sign-in's page opens in the station's browser (none until the browser's part attaches it).
  private pages: LoginPages | null = null;
  /// Where each profile's isolated sign-in browser context keeps its cookies and passkeys across re-logins.
  private stateFile: (profile: string) => string | null;

  constructor(data: string, commands: LoginCommands = { claude: "claude", codex: "codex" }, env: () => Record<string, string> = () => cleanEnv([]), clock?: Clock.Clock, console = CONSOLE, cursor: CursorUrls = CURSOR, keyName: () => string = () => "still.fail", kimi = KIMI_AUTH) {
    this.console = console;
    this.kimi = kimi;
    this.cursor = cursor;
    this.keyName = keyName;
    this.background = new Fibers("login", clock);
    this.noBrowserDir = join(data, "run", "no-browser");
    this.commands = commands;
    this.env = env;
    this.stateFile = (profile) => {
      const home = this.jobs.get(profile)?.home;
      return home ? join(home, LOGIN_BROWSER_FILE) : null;
    };
  }

  /// Overrides how a profile's sign-in browser state file is located (accounts/index.ts: follows a new profile's home
  /// once `newLogin` renames it).
  setStateFile(resolve: (profile: string) => string | null) {
    this.stateFile = resolve;
  }

  /// Hears the profile id of each login job that changes; gives the function that stops it.
  changes(listener: (profile: string) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /// The station's browser, for the pages of sign-ins (logins/module.ts): a tab coming or going is told as a change.
  attach(pages: LoginPages) {
    this.pages = pages;
    pages.changes((key) => {
      const profile = key.startsWith("profile:") ? key.slice("profile:".length) : null;
      if (profile !== null && this.jobs.has(profile)) this.emit(profile);
    });
  }

  get(profile: string): LoginJob | null {
    const running = this.jobs.get(profile);
    if (running) {
      const job: LoginJob = { ...running.job };
      if (this.pages !== null) {
        const screen = this.pages.screenOf(pageKey(profile));
        if (screen !== null) job.screen = screen;
        if ((screen !== null || this.stationPage(running) !== null) && this.pages.can()) job.browser = true;
      }
      return job;
    }
    const done = this.finished.get(profile);
    return done ? { ...done } : null;
  }

  /// The page a sign-in under way opens in the station's browser: the one its command opened where that comes back to
  /// it here (Claude's loopback one), else the one it gives to open; null when it has none (yet).
  private stationPage(running: Running): string | null {
    const { job } = running;
    if (job.state !== "needs_code" && job.state !== "needs_approval") return null;
    if (running.opened) {
      let opened: string[] = [];
      try {
        opened = urlsIn(readFileSync(running.opened, "utf8"));
      } catch {}
      const back = opened.findLast((u) => loopbackOf(u) !== null);
      if (back !== undefined) return back;
    }
    return webPage(job.url) ? job.url : null;
  }

  /// Opens the page of `profile`'s sign-in in the station's browser (the tab open already, if there is one): its
  /// screen.
  async openPage(profile: string, lang: Lang = stationLang()): Promise<string> {
    const running = this.jobs.get(profile);
    if (!running) throw new Error(tr(lang, "station.loginPage.nothing"));
    if (this.pages === null || !this.pages.can()) throw new Error(tr(lang, "station.loginPage.noBrowser"));
    const url = this.stationPage(running);
    if (url === null && this.pages.screenOf(pageKey(profile)) === null) throw new Error(tr(lang, "station.loginPage.nothing"));
    let screen: string;
    try {
      screen = await this.pages.open(pageKey(profile), url ?? "about:blank", { stateFile: () => this.stateFile(profile) });
    } catch (error) {
      throw new Error(tr(lang, "station.loginPage.failed", { error: (error as Error).message }));
    }
    // Ended (or started again) meanwhile: its tab goes too.
    if (this.jobs.get(profile) !== running) {
      this.pages.close(pageKey(profile));
      throw new Error(tr(lang, "station.loginPage.nothing"));
    }
    return screen;
  }

  /// Starts a sign-in for a subscription profile, replacing any running one.
  async start(profile: LoginProfile, lang: Lang = stationLang()): Promise<LoginJob> {
    this.cancel(profile.id);
    this.finished.delete(profile.id);
    mkdirSync(profile.home, { recursive: true });
    const [noBrowser, open] = this.noBrowser();
    const sourceEnv = this.env();
    const clean = Object.fromEntries(Object.entries(sourceEnv).filter(([k]) => !SCRUBBED.includes(k)));
    let env = platform.prependPath(clean, noBrowser) as Record<string, string>;
    env.BROWSER = open;
    // The pages it opens, written down for the station's browser (one file a sign-in).
    const opened = join(noBrowser, `${profile.id}.opened`);
    rmSync(opened, { force: true });
    env.STILLFAIL_LOGIN_OPENED = opened;
    let command: string;
    let args: string[];
    let pathCommand: string | undefined;
    if (profile.runtime === "claude") {
      env.CLAUDE_CONFIG_DIR = profile.home;
      fileCredentials(env);
      const email = typeof profile.email === "string" && profile.email.trim() !== "" ? profile.email.trim() : null;
      [command, args] = [this.commands.claude, ["auth", "login", "--claudeai", ...(email ? ["--email", email] : [])]];
    } else if (profile.runtime === "grok") {
      env.GROK_HOME = join(profile.home, "grok");
      env.GROK_DISABLE_AUTOUPDATER = "1";
      mkdirSync(env.GROK_HOME, { recursive: true });
      [command, args] = [this.commands.grok ?? "grok", ["login", "--device-auth"]];
    } else if (profile.runtime === "devin") {
      env.XDG_DATA_HOME = devinData(profile.home);
      mkdirSync(env.XDG_DATA_HOME, { recursive: true });
      pathCommand = this.commands.devin ?? "devin";
      const wrapped = platform.terminal(pathCommand, ["auth", "login", "--force-manual-token-flow"], DEVIN_COLS, DEVIN_ROWS);
      if (wrapped === null) return this.refused(profile.id, profile.runtime, tr(lang, "station.login.devinNoTerminal"));
      [command, args] = wrapped;
    } else if (profile.runtime === "agy") {
      env.HOME = agyHome(profile.home);
      // Not a remote session's: there it first asks the terminal what it can do, and waits for an answer none gives.
      delete env.SSH_CONNECTION;
      env.AGY_CLI_DISABLE_AUTO_UPDATE = "1";
      mkdirSync(env.HOME, { recursive: true });
      pathCommand = this.commands.agy ?? "agy";
      const wrapped = platform.terminal(pathCommand, [], DEVIN_COLS, DEVIN_ROWS);
      if (wrapped === null) return this.refused(profile.id, profile.runtime, tr(lang, "station.login.agyNoTerminal"));
      [command, args] = wrapped;
    } else {
      env.CODEX_HOME = profile.home;
      [command, args] = [this.commands.codex, ["login", "--device-auth"]];
    }
    const now = this.background.now();
    const job: LoginJob = { profile: profile.id, runtime: profile.runtime, state: "starting", url: null, userCode: null, error: null, startedAt: now, expiresAt: now + TIMEOUT_MS };
    const run = ++this.runs;
    const id = profile.id;
    // The shell lookup can take time. Record the sign-in first so cancelling or replacing it stops this start too.
    const running: Running = {
      run, job, child: null, raw: "", output: "", exited: true, opened, lang, home: profile.home,
      cancelTimer: this.background.after(TIMEOUT_MS, () => this.failRun(id, run, tr(lang, "station.login.timedOut"))),
    };
    this.jobs.set(id, running);
    this.emit(id);
    const foundEnv = await withShellCommand(pathCommand ?? command, env, sourceEnv);
    if (this.jobs.get(id) !== running) return { ...job, state: "cancelled" };
    // The browser stand-ins must stay ahead of any Node bin added for the login command.
    if (foundEnv !== env) env = platform.prependPath(foundEnv, noBrowser) as Record<string, string>;
    const r = platform.runnable(command, args, env);
    const child = spawn(r.file, r.args, { cwd: profile.home, env, stdio: ["pipe", "pipe", "pipe"], windowsVerbatimArguments: r.windowsVerbatimArguments, windowsHide: true });
    running.child = child;
    running.exited = false;
    const spawned = await started(child);
    if (this.jobs.get(id) !== running) return { ...job, state: "cancelled" };
    if (spawned) {
      // Recorded like any other failure, so the page shows why.
      running.exited = true;
      const error = tr(lang, "station.login.cannotRun", { error: spawned.message });
      this.finish(id, "failed", error);
      return { ...job, state: "failed", error };
    }
    // A later failure to write (the command gone) is its end's to say.
    child.stdin?.on("error", () => {});
    for (const stream of [child.stdout, child.stderr]) stream?.on("data", (chunk: Buffer) => this.output(id, run, chunk.toString("utf8")));
    // Everything it said is in before its end is judged: `close` comes after its output ends.
    child.once("close", (code, signal) => {
      const current = this.jobs.get(id);
      if (!current || current.run !== run) return;
      current.exited = true;
      if (code === 0) return this.finish(id, "done", null);
      const said = lastLines(current.output);
      const shown = code !== null ? String(code) : signal ? "signal" : "signal";
      this.finish(id, "failed", said !== "" ? said : tr(lang, "station.login.exited", { code: shown }));
    });
    log.info("login", "login started", { profile: id, runtime: profile.runtime });
    this.emit(id);
    return { ...job };
  }

  /// Starts signing an OpenCode Go profile in to the person's OpenCode Console account, replacing any running sign-in:
  /// a code from the Console, then asked about at the interval it gives until it is approved, refused or runs out.
  startConsole(profile: { id: string; home: string }, lang: Lang = stationLang()): Promise<LoginJob> {
    return this.deviceSignIn(profile, "opencode", lang, {
      start: () => startDevice(this.console),
      ask: (code) => deviceToken(this.console, code),
      keep: async (token) => {
        const who = await whoIs(this.console, token.access, token.org);
        return () => writeConsole(profile.home, { access: token.access, refresh: token.refresh, expiresAt: wall.now() + token.expiresInMs, org: token.org, ...who } satisfies ConsoleLogin);
      },
    });
  }

  /// Starts signing a Kimi Code profile in to the person's Kimi account the same way (kimi.ts), for a device of its own:
  /// the one it signed in on before where it has one (Kimi renews a token only for the device it was given to).
  startKimi(profile: { id: string; home: string }, lang: Lang = stationLang()): Promise<LoginJob> {
    const deviceId = readKimi(profile.home)?.deviceId ?? newDeviceId();
    return this.deviceSignIn(profile, "kimi", lang, {
      start: () => startKimiDevice(this.kimi, deviceId),
      ask: (code) => kimiDeviceToken(this.kimi, code, deviceId),
      keep: async (token) => () => writeKimi(profile.home, { access: token.access, refresh: token.refresh, expiresAt: wall.now() + token.expiresInMs, lifeMs: token.expiresInMs, deviceId }),
    });
  }

  /// A device authorization grant (RFC 8628) the station follows itself: a code, then asked about at the interval given
  /// until it is approved, refused or runs out; then what `keep` makes of the tokens written to the profile's home.
  private async deviceSignIn(
    profile: { id: string; home: string },
    provider: "opencode" | "kimi",
    lang: Lang,
    steps: { start: () => Promise<Device>; ask: (deviceCode: string) => Promise<DeviceAnswer>; keep: (token: Token) => Promise<() => void> },
  ): Promise<LoginJob> {
    const [failed, expired, denied, unreachable] =
      provider === "kimi"
        ? ["station.login.kimiFailed", "station.login.kimiExpired", "station.login.kimiDenied", "could not ask Kimi about a sign-in"]
        : ["station.login.consoleFailed", "station.login.consoleExpired", "station.login.consoleDenied", "could not ask the OpenCode Console about a sign-in"];
    this.cancel(profile.id);
    this.finished.delete(profile.id);
    mkdirSync(profile.home, { recursive: true });
    const id = profile.id;
    const now = this.background.now();
    const job: LoginJob = { profile: id, runtime: "claude", provider, state: "starting", url: null, userCode: null, error: null, startedAt: now, expiresAt: now + TIMEOUT_MS };
    const run = ++this.runs;
    const running: Running = { run, job, child: null, raw: "", output: "", exited: true, lang, home: profile.home, cancelTimer: () => {} };
    this.jobs.set(id, running);
    this.emit(id);
    const current = () => this.jobs.get(id)?.run === run;
    let device: Device;
    try {
      device = await steps.start();
    } catch (e) {
      if (current()) this.finish(id, "failed", tr(lang, failed, { error: (e as Error).message }));
      return this.get(id)!;
    }
    if (!current()) return this.get(id)!;
    Object.assign(job, { state: "needs_approval", url: device.url, userCode: device.userCode, expiresAt: now + Math.min(device.expiresInMs, TIMEOUT_MS) });
    running.cancelTimer = this.background.after(job.expiresAt - now, () => this.failRun(id, run, tr(lang, expired)));
    let interval = device.intervalMs;
    const ask = async () => {
      if (!current()) return;
      let answer: DeviceAnswer;
      try {
        answer = await steps.ask(device.deviceCode);
      } catch (e) {
        // The network, for once: asked again at the next interval.
        log.warn("login", unreachable, { profile: id, error: (e as Error).message });
        answer = { pending: true as const, slowDown: false };
      }
      if (!current()) return;
      if ("pending" in answer) {
        if (answer.slowDown) interval += 5_000;
        running.stop = this.background.after(interval, ask);
        return;
      }
      if ("error" in answer) {
        if (answer.error === "access_denied") return this.finish(id, "failed", tr(lang, denied));
        return this.finish(id, "failed", answer.error === "expired_token" ? tr(lang, expired) : tr(lang, failed, { error: answer.error }));
      }
      job.state = "verifying";
      this.emit(id);
      const write = await steps.keep(answer.token);
      if (!current()) return;
      try {
        write();
      } catch (e) {
        return this.finish(id, "failed", tr(lang, "station.login.homeFailed", { error: (e as Error).message }));
      }
      this.finish(id, "done", null);
    };
    running.stop = this.background.after(interval, ask);
    log.info("login", "device sign-in started", { profile: id, provider });
    this.emit(id);
    return { ...job };
  }

  /// Starts signing a Cursor profile in to the person's Cursor account, replacing any running sign-in: a page to confirm
  /// the login on (no code), asked about until it is confirmed or runs out; then the key minted for the station.
  async startCursor(profile: { id: string; home: string }, lang: Lang = stationLang()): Promise<LoginJob> {
    this.cancel(profile.id);
    this.finished.delete(profile.id);
    mkdirSync(profile.home, { recursive: true });
    const id = profile.id;
    const now = this.background.now();
    const handshake = cursorHandshake(this.cursor);
    const job: LoginJob = { profile: id, runtime: "cursor", state: "needs_approval", url: handshake.url, userCode: null, error: null, startedAt: now, expiresAt: now + TIMEOUT_MS };
    const run = ++this.runs;
    const running: Running = { run, job, child: null, raw: "", output: "", exited: true, lang, home: profile.home, cancelTimer: () => {} };
    this.jobs.set(id, running);
    running.cancelTimer = this.background.after(TIMEOUT_MS, () => this.failRun(id, run, tr(lang, "station.login.timedOut")));
    const current = () => this.jobs.get(id)?.run === run;
    // Asked often at first (the person is on the page), less as it goes on.
    let interval = 1_000;
    const ask = async () => {
      if (!current()) return;
      let answer;
      try {
        answer = await pollCursor(this.cursor, handshake);
      } catch (e) {
        // The network, for once: asked again at the next interval.
        log.warn("login", "could not ask Cursor about a sign-in", { profile: id, error: (e as Error).message });
        answer = { pending: true as const };
      }
      if (!current()) return;
      if ("pending" in answer) {
        interval = Math.min(Math.round(interval * 1.2), 5_000);
        running.stop = this.background.after(interval, ask);
        return;
      }
      job.state = "verifying";
      this.emit(id);
      let minted;
      try {
        minted = await mintCursorKey(this.cursor, answer.accessToken, this.keyName());
      } catch (e) {
        if (current()) this.finish(id, "failed", tr(lang, "station.login.cursorKeyFailed", { error: (e as Error).message }));
        return;
      }
      if (!current()) return;
      try {
        writeCursor(profile.home, { apiKey: minted.apiKey, email: minted.email, keyName: this.keyName(), createdAt: wall.now() });
      } catch (e) {
        return this.finish(id, "failed", tr(lang, "station.login.homeFailed", { error: (e as Error).message }));
      }
      this.finish(id, "done", null);
    };
    running.stop = this.background.after(interval, ask);
    log.info("login", "Cursor sign-in started", { profile: id });
    this.emit(id);
    return { ...job };
  }

  /// A sign-in that cannot be started here, recorded like any other failure, so the page shows why.
  private refused(id: string, runtime: Runtime, error: string): LoginJob {
    const now = this.background.now();
    const failed: LoginJob = { profile: id, runtime, state: "failed", url: null, userCode: null, error, startedAt: now, expiresAt: now };
    this.finished.set(id, failed);
    this.emit(id);
    return { ...failed };
  }

  /// Claude and Devin: the code the browser showed after approving.
  async submitCode(profile: string, code: string, lang: Lang = stationLang()): Promise<LoginJob> {
    const running = this.jobs.get(profile);
    if (!running || running.job.state !== "needs_code") throw new Error(tr(lang, "station.login.notWaitingForCode"));
    const clean = code.trim();
    if (clean === "") throw new Error(tr(lang, "station.login.emptyCode"));
    running.job.state = "verifying";
    const job = { ...running.job };
    await new Promise<void>((resolve, reject) => {
      const stdin = running.child?.stdin;
      if (!stdin || stdin.destroyed) return resolve();
      // Devin and the Antigravity CLI read it in a terminal of their own, where Enter is a carriage return.
      const terminal = running.job.runtime === "devin" || running.job.runtime === "agy";
      stdin.write(`${clean}${terminal ? "\r" : "\n"}`, (error) => (error ? reject(error) : resolve()));
    });
    if (running.job.runtime === "agy") this.awaitAgy(profile, running);
    this.emit(profile);
    return job;
  }

  /// The Antigravity CLI goes on into its interface once signed in: done when it has written its sign-in since the code
  /// went in; failed when it has not in a while (a code it did not take: it says nothing a program can read of it).
  private awaitAgy(profile: string, running: Running) {
    // (the file's time is the machine's: compared with the wall's; how long it is waited for, the station's clock)
    const since = wall.now() - 1000;
    const until = this.background.now() + AGY_WAIT_MS;
    const look = () => {
      if (this.jobs.get(profile) !== running) return;
      if (running.home !== undefined && writtenSince(agyToken(running.home), since)) {
        const home = running.home;
        void readFile(agyToken(home), "utf8").then((text) => noteAgyEmail(home, text), () => null).finally(() => {
          if (this.jobs.get(profile) === running) this.finish(profile, "done", null);
        });
        return;
      }
      if (this.background.now() > until) return this.finish(profile, "failed", tr(running.lang, "station.login.agyCodeRefused"));
      running.stop = this.background.after(AGY_POLL_MS, look);
    };
    look();
  }

  cancel(profile: string) {
    if (this.jobs.has(profile)) this.finish(profile, "cancelled", null);
  }

  stopAll() {
    for (const id of [...this.jobs.keys()]) this.cancel(id);
  }

  /// Stops every sign-in and what waits on them.
  async close() {
    this.stopAll();
    await this.background.close();
  }

  private output(profile: string, run: number, chunk: string) {
    const running = this.jobs.get(profile);
    if (!running || running.run !== run) return;
    // Read whole: an escape can be cut between two pieces.
    running.raw += chunk;
    const raw = [...running.raw];
    if (raw.length > 16000) running.raw = raw.slice(raw.length - 16000).join("");
    running.output = stripAnsi(running.raw);
    // The Antigravity CLI asks how to sign in first: Google OAuth, its first choice.
    if (running.job.runtime === "agy" && running.job.state === "starting" && !running.chose && running.output.includes("Select login method")) {
      running.chose = true;
      running.child?.stdin?.write("\r");
    }
    if (parse(running.job, running.output)) this.emit(profile);
  }

  private failRun(profile: string, run: number, error: string) {
    if (this.jobs.get(profile)?.run === run) this.finish(profile, "failed", error);
  }

  private finish(profile: string, state: LoginState, error: string | null) {
    const running = this.jobs.get(profile);
    if (!running) return;
    this.jobs.delete(profile);
    running.cancelTimer();
    running.stop?.();
    if (!running.exited && running.child) {
      const child = running.child;
      // The Antigravity CLI does not end by itself once signed in, in a terminal of its own: the processes between
      // (macOS: a shell, `cat`, script) end with it, all of them found first, as they would be left behind.
      if (running.job.runtime === "agy" && child.pid !== undefined) {
        const pid = child.pid;
        void platform.descendants(pid).then((pids) => {
          for (const p of [pid, ...pids]) {
            try {
              process.kill(p, "SIGTERM");
            } catch {}
          }
        });
      } else {
        try {
          child.kill("SIGTERM");
        } catch {}
      }
    }
    if (running.opened) rmSync(running.opened, { force: true });
    this.pages?.close(pageKey(profile));
    this.finished.set(profile, { ...running.job, state, error });
    log.info("login", "login ended", { profile, state, error });
    this.emit(profile);
  }

  private emit(profile: string) {
    for (const listener of this.listeners) {
      try {
        listener(profile);
      } catch (e) {
        log.warn("login", "a login listener failed", { error: (e as Error).message });
      }
    }
  }

  /// A directory whose `open` and `xdg-open` open nothing, put first on the login command's PATH; and what `open` is to
  /// be called by (BROWSER). Each writes the pages it is given to the file STILLFAIL_LOGIN_OPENED names (on Windows it
  /// does nothing).
  private noBrowser(): [dir: string, open: string] {
    mkdirSync(this.noBrowserDir, { recursive: true });
    const script = `#!/bin/sh\n# A browser for a sign-in run by still.fail (station/src/accounts/login.ts): the page goes to the station.\n[ -n "$STILLFAIL_LOGIN_OPENED" ] || exit 0\nfor a in "$@"; do printf '%s\\n' "$a" >> "$STILLFAIL_LOGIN_OPENED"; done\nexit 0\n`;
    const [open] = ["open", "xdg-open"].map((name) => platform.makeCommand(join(this.noBrowserDir, name), script, true));
    return [this.noBrowserDir, open!];
  }
}

/// Reads where to sign in from what the command said so far. Whether the job changed.
export function parse(job: LoginJob, output: string): boolean {
  if (job.state !== "starting") return false;
  const urls = output
    .split(/\s+/)
    .filter((w) => w.includes("https://"))
    .map((w) => w.slice(w.indexOf("https://")));
  if (job.runtime === "claude") {
    const url = urls.find((u) => u.includes("/oauth/authorize?") && !u.endsWith("?"));
    if (url !== undefined && output.toLowerCase().includes("paste code")) {
      job.url = url;
      job.state = "needs_code";
      return true;
    }
  } else if (job.runtime === "agy") {
    const url = urls.find((u) => u.startsWith("https://accounts.google.com/o/oauth2/") && u.includes("antigravity.google%2Foauth-callback"));
    if (url !== undefined && output.toLowerCase().includes("authorization code")) {
      job.url = url;
      job.state = "needs_code";
      return true;
    }
  } else if (job.runtime === "devin") {
    const url = urls.find((u) => u.startsWith("https://app.devin.ai/auth/cli/") && u.includes("code_challenge="));
    if (url !== undefined && output.toLowerCase().includes("paste it")) {
      job.url = url;
      job.state = "needs_code";
      return true;
    }
  } else {
    const site = job.runtime === "grok" ? "https://accounts.x.ai/" : "https://auth.openai.com/";
    const url = urls.find((u) => u.startsWith(site) && u.includes("device"));
    const code = deviceCode(output);
    if (url !== undefined && code !== null) {
      job.url = url;
      job.userCode = code;
      job.state = "needs_approval";
      return true;
    }
  }
  return false;
}

/// A one-time code like ABCD-12345: four capitals or digits, a dash, four to six more.
export function deviceCode(output: string): string | null {
  const code = (s: string, min: number, max: number) => s.length >= min && s.length <= max && /^[A-Z0-9]+$/.test(s);
  for (const word of output.split(/[^A-Za-z0-9_-]/)) {
    const parts = word.split("-");
    for (let i = 0; i + 1 < parts.length; i++) {
      if (code(parts[i]!, 4, 4) && code(parts[i + 1]!, 4, 6)) return `${parts[i]}-${parts[i + 1]}`;
    }
  }
  return null;
}

/// Drops terminal escapes (colours, cursor moves): ESC [ parameters letter; and ESC ] … ended by BEL or ESC \ (a
/// link's target, as Devin writes its sign-in page: the page's address is in the text too).
export function stripAnsi(text: string): string {
  let out = "";
  const chars = [...text];
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i]!;
    if (c === "\u001b" && chars[i + 1] === "]") {
      i += 1;
      while (i + 1 < chars.length && chars[i + 1] !== "\u0007" && !(chars[i + 1] === "\u001b" && chars[i + 2] === "\\")) i += 1;
      i += chars[i + 1] === "\u0007" ? 1 : 2;
      continue;
    }
    if (c === "\u001b" && chars[i + 1] === "[") {
      i += 1;
      while (i + 1 < chars.length) {
        const p = chars[i + 1]!;
        i += 1;
        if (/[A-Za-z]/.test(p)) break;
        if (!/[0-9;?]/.test(p)) break;
      }
      continue;
    }
    out += c;
  }
  return out;
}

/// Whether `path` was written at or after `since` (ms).
function writtenSince(path: string, since: number): boolean {
  try {
    return statSync(path).mtimeMs >= since;
  } catch {
    return false;
  }
}

function lastLines(output: string): string {
  const lines = output
    .trim()
    .split(/\r?\n/)
    .filter((l) => l.trim() !== "");
  return [...lines.slice(Math.max(0, lines.length - 4)).join("\n")].slice(0, 600).join("");
}
