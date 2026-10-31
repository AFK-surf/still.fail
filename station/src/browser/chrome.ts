// The station's Chrome as a process (docs/remote-screens.md, "The station's browser"): found on the machine, started as
// a normal browser on a profile of its own with a DevTools port, found again by a station process that did not start
// it (it outlives a handover, as jobs do), and ended. What it is used for is browser.ts's.
//
// It is started as a person's browser would be, so that sites let it sign in: no --enable-automation, no
// --remote-debugging-pipe; headless, so that it opens no window on the machine at all (its tabs are seen and driven
// from people's apps, docs/remote-screens.md; headful only when asked). Two things still tell a site it is
// driven, and are undone: Chrome says navigator.webdriver = true of any browser it lets be debugged (undone by
// --disable-blink-features=AutomationControlled), and a headless one says HeadlessChrome in its user agent (given
// the headful one's). With either, Google refuses to sign in ("This browser or app may not be secure"; checked on
// Chrome 155, 2026-10-17). Without them, headless, in its default context or one made over DevTools (a chat's:
// browsers.ts), Google's sign-in goes on to its next step (Chrome 156, 2026-10-31; a browser embedding Chromium, CEF
// 156 off-screen, was refused there).
import { createServer } from "node:net";
import { mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Clock, Effect } from "effect";
import { liveClock, wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { startLasting } from "../ops/processes.ts";
import { platform } from "../platform/index.ts";
import { endGroup, groupAlive, startTimeOf } from "../ops/group.ts";
import { type Cdp, connectCdp } from "./cdp.ts";

/// A Chrome that runs: its DevTools (`port`, the browser's WebSocket `ws`), the program, how it was started.
export type Running = {
  /// Its process (group), when this station started it; null for one found without a record of it.
  pid: number | null;
  /// When `pid` started (ms), to tell it from a later process given the same pid.
  started: number | null;
  port: number;
  ws: string;
  binary: string;
  headless: boolean;
  userAgent: string;
};

/// What browser.ts asks of the machine: separate so its tests can be given a Chrome of their own making.
export interface ChromeHost {
  /// The station's Chrome when it runs already (started by an earlier station process), else null.
  find(): Promise<Running | null>;
  /// Starts it.
  launch(): Promise<Running>;
  /// Whether there is a Chrome here to start (none: taken to be).
  installed?(): boolean;
  /// Makes sure it has ended (asked to close first by the caller): waits a little for it, then ends its group.
  kill(running: Running): Promise<void>;
  connect(url: string): Promise<Cdp>;
}

/// `DevToolsActivePort` (written by Chrome into its profile): the port on the first line, the browser's path on the
/// second.
export function parseActivePort(text: string): { port: number; path: string } | null {
  const [first, second] = text.split(/\r?\n/);
  const port = Number(first);
  const path = second?.trim() ?? "";
  if (!/^\d+$/.test(first ?? "") || !Number.isInteger(port) || port <= 0 || port > 65535 || !path.startsWith("/devtools/browser/")) return null;
  return { port, path };
}

/// Chrome's command line. `port` 0: any free one (said in DevToolsActivePort).
export function chromeArgs(o: { profile: string; port: number; headless: boolean; userAgent?: string }): string[] {
  return [
    `--user-data-dir=${o.profile}`,
    `--remote-debugging-port=${o.port}`,
    "--no-first-run",
    "--no-default-browser-check",
    // Chrome says navigator.webdriver of a browser it lets be debugged; sites (Google's sign-in) refuse such a one.
    "--disable-blink-features=AutomationControlled",
    // Started again after it died, it opens as it was without asking.
    "--hide-crash-restore-bubble",
    // A tab a person watches is drawn while its window is covered, and the agents' tabs run at speed behind others.
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-background-timer-throttling",
    // Headful (when asked), no window of its own as it starts: one would make it the machine's front app, over what the
    // person there is doing (its tabs come in windows opened behind: gate.ts BEHIND; measured on a Mac, Edge 156,
    // 2026-10-29).
    ...(o.headless ? ["--headless=new", "--window-size=1280,900"] : ["--no-startup-window"]),
    ...(o.userAgent ? [`--user-agent=${o.userAgent}`] : []),
  ];
}

/// The user agent a headless Chrome is given: its own, as the headful one says it.
export const headfulAgent = (agent: string): string => agent.replace(/HeadlessChrome\//g, "Chrome/");

/// How long Chrome is given to come up (its DevToolsActivePort), and to end once asked.
const START_MS = 30_000;
const GIVEN_PORT_MS = 10_000;
const END_MS = 5_000;
const LOOK_MS = 100;

/// What is kept in <data>/browser/state.json: the Chrome started last (while it runs), its port (asked for again, so
/// what agents were told stays right across a restart), when it was last used, and the user agent a headless one is
/// given (per program, as it was when read).
export type State = {
  running?: Running;
  port?: number;
  lastUse?: number;
  headlessAgent?: { binary: string; mtimeMs: number; agent: string };
};

export function readState(dir: string): State {
  try {
    const s = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
    return s && typeof s === "object" ? s : {};
  } catch {
    return {};
  }
}

export function writeState(dir: string, change: (s: State) => State) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "state.json"), JSON.stringify(change(readState(dir)), null, 2) + "\n");
}

/// Whether a port of 127.0.0.1 is free to be listened on.
function free(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = createServer();
    server.once("error", () => resolve(false));
    server.listen(port, "127.0.0.1", () => server.close(() => resolve(true)));
  });
}

/// The browser's DevTools as it says them at `port`: its WebSocket and user agent; null when nothing answers there.
async function version(port: number): Promise<{ ws: string; agent: string } | null> {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/json/version`, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) return null;
    const v = (await res.json()) as any;
    return typeof v?.webSocketDebuggerUrl === "string" ? { ws: v.webSocketDebuggerUrl, agent: String(v["User-Agent"] ?? "") } : null;
  } catch {
    return null;
  }
}

/// Whether a recorded process is still the one recorded.
function stillThere(r: Running): boolean {
  if (r.pid === null) return false;
  const started = startTimeOf(r.pid);
  return started !== null && (r.started === null || Math.abs(started - r.started) < 5000) && groupAlive(r.pid);
}

export type ChromeOptions = {
  /// <data>/browser: the profile in it, and state.json.
  dir: string;
  /// The program (else the machine's best: platform.browsers).
  binary?: string;
  /// Headless (the default: no window on the machine), or headful.
  headless?: boolean;
};

export function chromeHost(o: ChromeOptions): ChromeHost {
  const profile = join(o.dir, "profile");
  const activePort = join(profile, "DevToolsActivePort");
  const readActive = () => {
    try {
      return parseActivePort(readFileSync(activePort, "utf8"));
    } catch {
      return null;
    }
  };

  async function find(): Promise<Running | null> {
    // Where it said it is (DevToolsActivePort: written when it chose its port), else where it was recorded (one given
    // its port writes none).
    const recorded = readState(o.dir).running;
    const active = readActive() ?? (recorded ? { port: recorded.port, path: new URL(recorded.ws).pathname } : null);
    if (active === null) return null;
    const v = await version(active.port);
    // What answers there is this profile's Chrome (its browser's path is the one it said), not another program given
    // the port since.
    if (v === null || new URL(v.ws).pathname !== active.path) return null;
    const known = recorded && recorded.port === active.port && stillThere(recorded) ? recorded : null;
    return {
      pid: known?.pid ?? null,
      started: known?.started ?? null,
      port: active.port,
      ws: v.ws,
      binary: known?.binary ?? recorded?.binary ?? "",
      headless: known?.headless ?? /HeadlessChrome/.test(v.agent),
      userAgent: v.agent,
    };
  }

  /// `retried`: started again for its user agent; `anyPort`: the port it had last time was not had; `windowless`:
  /// headless whatever the machine says.
  async function launch(retried = false, anyPort = false, windowless = false): Promise<Running> {
    const binary = o.binary ?? platform.browsers(process.env)[0];
    if (binary === undefined) throw new Error("There is no Chrome on this machine: install Google Chrome (or Chromium or Edge) and ask again.");
    const headless = windowless || (o.headless ?? true);
    mkdirSync(profile, { recursive: true });
    rmSync(activePort, { force: true });
    const state = readState(o.dir);
    const port = !anyPort && state.port !== undefined && (await free(state.port)) ? state.port : 0;
    let mtimeMs = 0;
    try {
      mtimeMs = statSync(binary).mtimeMs;
    } catch {}
    const known = state.headlessAgent;
    const agent = headless && known && known.binary === binary && known.mtimeMs === mtimeMs ? known.agent : undefined;
    const child = startLasting(binary, chromeArgs({ profile, port, headless, userAgent: agent }), { cwd: o.dir, stdio: "ignore", env: process.env });
    let ended: number | null | undefined;
    child.once("exit", (code) => (ended = code));
    child.once("error", () => (ended = -1));
    const pid = child.pid ?? null;
    const started = pid === null ? null : startTimeOf(pid);
    // Chrome's own time: looked at until it answers at its port (given; or chosen, and said in DevToolsActivePort,
    // which Chrome writes only then), or ends.
    let at = port === 0 ? null : port;
    let v: { ws: string; agent: string } | null = null;
    for (let waited = 0; v === null; waited += LOOK_MS) {
      if (ended !== undefined) throw new Error(`Chrome (${binary}) ended as it started (exit ${ended}); is this profile open in another Chrome? ${profile}`);
      // The port it had is not answered on (taken meanwhile): any other, then.
      if (port !== 0 && waited >= GIVEN_PORT_MS) {
        if (pid !== null) platform.signalGroup(pid, "SIGKILL");
        log.warn("browser", "Chrome did not answer on the port it had; starting it on another", { port });
        await wall.sleep(END_MS);
        return launch(retried, true, windowless);
      }
      if (waited >= START_MS) {
        if (pid !== null) platform.signalGroup(pid, "SIGKILL");
        throw new Error(`Chrome (${binary}) did not open its DevTools port within ${START_MS / 1000} s`);
      }
      await wall.sleep(LOOK_MS);
      at ??= readActive()?.port ?? null;
      if (at !== null) v = await version(at);
    }
    const said = v;
    const running: Running = { pid, started, port: at!, ws: said.ws, binary, headless, userAgent: said.agent };
    // A headless Chrome names itself in its user agent: started again with the headful one's, kept for next time.
    if (headless && agent === undefined && /HeadlessChrome/.test(said.agent) && !retried) {
      writeState(o.dir, (s) => ({ ...s, headlessAgent: { binary, mtimeMs, agent: headfulAgent(said.agent) } }));
      await closeAndKill(running);
      return launch(true, anyPort, windowless);
    }
    writeState(o.dir, (s) => ({ ...s, running, port: running.port }));
    log.info("browser", "Chrome started", { binary, port: running.port, pid, headless });
    return running;
  }

  async function closeAndKill(running: Running) {
    try {
      const cdp = await connectCdp(running.ws);
      await cdp.send("Browser.close").catch(() => {});
      cdp.close();
    } catch {}
    await kill(running);
  }

  async function kill(running: Running) {
    if (running.pid !== null && stillThere(running)) {
      for (let waited = 0; waited < END_MS && groupAlive(running.pid); waited += LOOK_MS) await wall.sleep(LOOK_MS);
      if (groupAlive(running.pid)) await Effect.runPromise(endGroup(running.pid, END_MS).pipe(Effect.provideService(Clock.Clock, liveClock)));
    }
    // Its record and its DevToolsActivePort (Chrome takes that away when it ends well; one killed leaves it), unless
    // they are already another's (one started since).
    writeState(o.dir, (s) => {
      if (s.running === undefined || s.running.pid !== running.pid || s.running.port !== running.port) return s;
      const { running: _, ...rest } = s;
      return rest;
    });
    if (readActive()?.port === running.port && (await version(running.port)) === null) rmSync(activePort, { force: true });
  }

  return {
    find,
    installed: () => (o.binary ?? platform.browsers(process.env)[0]) !== undefined,
    async launch() {
      try {
        return await launch();
      } catch (e) {
        // A machine said to show windows that shows none to this process (a Mac's station with no one logged in):
        // headless, then.
        if (o.headless !== undefined || !platform.hasDisplay(process.env)) throw e;
        log.warn("browser", "Chrome did not start with windows; starting it headless", { error: (e as Error).message });
        return launch(false, false, true);
      }
    },
    kill,
    connect: connectCdp,
  };
}
