// The station's browser (docs/remote-screens.md): one real Chrome, kept for the agents, its tabs screens a person can
// see and drive. Started when an agent asks for it (the `browser` tool), started again if it dies while in use, closed
// after a long idle. It outlives a station process, as jobs do: the next one (a handover, a restart) finds it by its
// DevToolsActivePort and takes it up, its tabs and logins as they were.
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Screens } from "../screens/source.ts";
import type { Cdp } from "./cdp.ts";
import { type ChromeHost, type Running, readState, writeState } from "./chrome.ts";
import { Owners } from "./owners.ts";
import { Authenticators } from "./passkeys.ts";
import { BEHIND } from "./gate.ts";
import { type TabInfo, Tabs } from "./tabs.ts";

/// Unused this long (no agent asking for it, no tab coming, going or navigated, no one watching), it is closed.
export const IDLE_MS = 60 * 60_000;
/// One that ran this long before it died is started again at once; one that keeps dying waits longer each time.
const STEADY_MS = 60_000;
const FIRST_PAUSE_MS = 1000;
const MAX_PAUSE_MS = 60_000;
/// How often its last use is written down (for the station process after this one), at most.
const NOTE_MS = 60_000;
/// How long whether there is a Chrome on the machine is taken to stay as it was found.
const INSTALLED_MS = 60_000;

export type BrowserStatus = {
  running: boolean;
  /// http://127.0.0.1:<port>: what chrome-devtools-mcp's --browserUrl and Playwright's connectOverCDP take.
  http?: string;
  /// The browser's WebSocket (chrome-devtools-mcp --wsEndpoint).
  ws?: string;
  binary?: string;
  headless?: boolean;
  pid?: number | null;
  tabs?: number;
  viewing?: number;
  /// When it was last used (ms).
  lastUse?: number;
};

export type BrowserOptions = {
  /// <data>/browser.
  dir: string;
  chrome: ChromeHost;
  screens?: Screens & { changed?(): void };
  clock?: Clock.Clock;
  idleMs?: number;
  /// Chrome's time for the tabs (tabs.ts `later`): the machine's unless given.
  later?: (ms: number, f: () => void) => () => void;
  /// The session whose chat's context a browser context is (browsers.ts): a tab in it is that session's.
  contextOwner?: (browserContextId: string | undefined) => string | undefined;
  usedTab?: (session: string, targetId: string) => void;
};

type Up = { running: Running; cdp: Cdp; tabs: Tabs; keys: Authenticators; since: number };

export class StationBrowser {
  readonly #o: BrowserOptions;
  readonly #fibers: Fibers;
  readonly #idleMs: number;
  #up: Up | null = null;
  /// A start under way: whoever asks meanwhile waits for it.
  #starting: Promise<Up> | null = null;
  #lastUse = 0;
  #noted = 0;
  #pause = 0;
  #idle: () => void = () => {};
  #restart: () => void = () => {};
  /// Closing on purpose (stopped, idle, or this station process ending): its end is not a death.
  #leaving = false;
  #closed = false;
  /// Which session opened each tab (owners.ts).
  readonly #owners: Owners;
  /// Whether a Chrome was found on the machine, and when it was looked for.
  #installed: { at: number; is: boolean } | null = null;

  constructor(o: BrowserOptions) {
    this.#o = o;
    this.#owners = new Owners(o.dir);
    this.#fibers = new Fibers("browser", o.clock);
    this.#idleMs = o.idleMs ?? IDLE_MS;
    this.#lastUse = readState(o.dir).lastUse ?? 0;
  }

  /// Takes up the Chrome an earlier station process left running, if there is one (its tabs become screens again).
  async resume(): Promise<void> {
    if (this.#closed || this.#up || this.#starting) return;
    const found = await this.#o.chrome.find().catch(() => null);
    if (found === null || this.#closed || this.#up || this.#starting) return;
    try {
      await this.#take(found);
      log.info("browser", "took up the Chrome left running", { port: found.port, pid: found.pid });
    } catch (e) {
      log.warn("browser", "the Chrome left running could not be taken up", { error: (e as Error).message });
    }
  }

  /// The browser, started if it is not running: what an agent connects to.
  async endpoint(): Promise<BrowserStatus> {
    this.used();
    const up = await this.#ensure();
    return this.#status(up);
  }

  /// Its tabs (none while it is not running).
  tabs(): TabInfo[] {
    if (this.#up) this.used();
    return this.#up?.tabs.list() ?? [];
  }

  /// Whether it can be had here: it runs, or there is a Chrome on the machine to start (looked for again a minute on).
  available(): boolean {
    if (this.#up !== null) return true;
    const now = this.#fibers.now();
    if (this.#installed === null || now - this.#installed.at >= INSTALLED_MS) this.#installed = { at: now, is: this.#o.chrome.installed?.() ?? true };
    return this.#installed.is;
  }

  /// A tab of the station's own (no session's) at `url`, in a window of its own opened behind the others (as a
  /// session's: proxy.ts), the browser started if it is not running: its target id, once it is among the screens.
  async openTab(url: string): Promise<string> {
    this.used();
    const up = await this.#ensure();
    const { targetId } = await up.cdp.send("Target.createTarget", { url, ...BEHIND });
    if (typeof targetId !== "string" || targetId === "") throw new Error("Chrome opened no tab.");
    await up.tabs.arrived(targetId);
    return targetId;
  }

  /// A command on the browser's own DevTools connection (its cookies: browsers.ts), the browser started if it is not
  /// running.
  async send(method: string, params: object = {}): Promise<any> {
    this.used();
    const up = await this.#ensure();
    return up.cdp.send(method, params);
  }

  /// A connection of its own to tab `targetId` (a sign-in's form filled by the station: signin-form.ts), the tab's
  /// session on it; closing it lets go of the tab.
  async attach(targetId: string): Promise<{ cdp: Cdp; session: string }> {
    this.used();
    const up = await this.#ensure();
    if (!up.tabs.has(targetId)) throw new Error("This tab is closed.");
    const cdp = await this.#o.chrome.connect(up.running.ws);
    try {
      const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
      return { cdp, session: sessionId };
    } catch (e) {
      cdp.close();
      throw e;
    }
  }

  /// The chats' tabs' authenticators (passkeys.ts), the browser started if it is not running.
  async passkeys(): Promise<Authenticators> {
    this.used();
    return (await this.#ensure()).keys;
  }

  /// The browser context of target `targetId` (any target: a page, a frame, a worker), when it is known.
  contextOf(targetId: string): string | undefined {
    return this.#up?.tabs.contextOf(targetId);
  }

  /// Whether tab `targetId` is there.
  hasTab(targetId: string): boolean {
    return this.#up?.tabs.has(targetId) ?? false;
  }

  /// Closes tab `targetId`, if it is there.
  async closeTab(targetId: string): Promise<void> {
    const up = this.#up;
    if (up === null || !up.tabs.has(targetId)) return;
    await up.tabs.closeTab(targetId).catch(() => {});
  }

  /// Tab `targetId` was opened by `session` (on its own connection, proxy.ts).
  own(targetId: string, session: string) {
    if (this.#up) this.#up.tabs.owned(targetId, session);
    else this.#owners.set(targetId, session);
  }

  /// Closes the tabs `session` opened (its chat archived or deleted); the browser stays.
  async closeOf(session: string): Promise<void> {
    const up = this.#up;
    if (up === null) return;
    const ids = up.tabs.ofSession(session);
    if (ids.length === 0) return;
    log.info("browser", "closing the tabs of a session that ended", { session, tabs: ids.length });
    await Promise.all(ids.map((id) => up.tabs.closeTab(id).catch(() => {})));
  }

  status(): BrowserStatus {
    return this.#up ? this.#status(this.#up) : { running: false, lastUse: this.#lastUse || undefined };
  }

  /// Something used it now (an agent asked, a tab changed, a view opened or ended).
  used() {
    this.#lastUse = this.#fibers.now();
    if (this.#lastUse - this.#noted >= NOTE_MS) this.#note();
  }

  /// Closes it (its tabs with it); the profile and its logins stay.
  async stop(): Promise<void> {
    const up = this.#up ?? (this.#starting ? await this.#starting.catch(() => null) : null);
    if (up === null) return;
    await this.#end(up, "asked to stop");
  }

  /// This station process ends: lets go of the browser, which goes on running for the next one to take up.
  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#leaving = true;
    this.#idle();
    this.#restart();
    const up = this.#up;
    this.#up = null;
    if (up) {
      up.tabs.close();
      up.keys.close();
      up.cdp.close();
    }
    this.#note();
    await this.#fibers.close();
  }

  #status(up: Up): BrowserStatus {
    return {
      running: true,
      http: `http://127.0.0.1:${up.running.port}`,
      ws: up.running.ws,
      binary: up.running.binary,
      headless: up.running.headless,
      pid: up.running.pid,
      tabs: up.tabs.list().length,
      viewing: up.tabs.viewing(),
      lastUse: this.#lastUse,
    };
  }

  #ensure(): Promise<Up> {
    if (this.#closed) return Promise.reject(new Error("The station is stopping."));
    if (this.#up) return Promise.resolve(this.#up);
    if (this.#starting) return this.#starting;
    this.#restart();
    const starting = (async () => {
      // One left running by an earlier station process, else a new one.
      const found = await this.#o.chrome.find().catch(() => null);
      return this.#take(found ?? (await this.#o.chrome.launch()));
    })();
    this.#starting = starting;
    void starting.then(
      () => (this.#starting = null),
      () => (this.#starting = null),
    );
    return starting;
  }

  /// Watches a running Chrome: its tabs into the screens, its end heard.
  async #take(running: Running): Promise<Up> {
    const { chrome, screens } = this.#o;
    const cdp = await chrome.connect(running.ws);
    // (each chat's tab its authenticator: passkeys.ts; the station's own context has none)
    const owner = this.#o.contextOwner;
    const keys = new Authenticators(cdp, (ctx) => owner?.(ctx) !== undefined);
    const tabs = new Tabs({
      cdp, screens, connect: () => chrome.connect(running.ws), now: () => this.#fibers.now(), activity: () => this.used(), later: this.#o.later,
      owners: this.#owners, ...(owner ? { contextOwner: owner } : {}),
      ownPasskey: (targetId, rpId) => {
        const ctx = tabs.contextOf(targetId);
        return ctx !== undefined && keys.has(ctx, rpId);
      },
      usedTab: (session, targetId) => this.#o.usedTab?.(session, targetId),
    });
    try {
      await keys.start();
      await tabs.start();
    } catch (e) {
      keys.close();
      tabs.close();
      cdp.close();
      throw e;
    }
    if (this.#closed) {
      keys.close();
      tabs.close();
      cdp.close();
      throw new Error("The station is stopping.");
    }
    const up: Up = { running, cdp, tabs, keys, since: this.#fibers.now() };
    this.#up = up;
    this.#leaving = false;
    void cdp.closed.then(() => this.#lost(up));
    this.#armIdle();
    return up;
  }

  /// Its connection ended: closed on purpose, or the browser is gone (it died, or someone quit it).
  #lost(up: Up) {
    if (this.#up !== up) return;
    this.#up = null;
    up.tabs.close();
    up.keys.close();
    this.#idle();
    if (this.#leaving || this.#closed) return;
    const inUse = this.#fibers.now() - this.#lastUse < this.#idleMs;
    log.warn("browser", "Chrome ended by itself", { pid: up.running.pid, inUse });
    // Its group (what it left) ended, and its record taken away, before another is started.
    const killed = this.#o.chrome.kill(up.running).catch(() => {});
    if (!inUse) return;
    // In use: started again, at once if it had run a while, else after a pause that grows.
    const ran = this.#fibers.now() - up.since;
    this.#pause = ran >= STEADY_MS ? 0 : Math.min(MAX_PAUSE_MS, Math.max(FIRST_PAUSE_MS, this.#pause * 2));
    const again = async () => {
      await killed;
      if (this.#up || this.#starting || this.#closed) return;
      return this.#ensure().then(
        () => log.info("browser", "Chrome started again"),
        (e) => log.warn("browser", "Chrome could not be started again", { error: (e as Error).message }),
      );
    };
    if (this.#pause === 0) void again();
    else this.#restart = this.#fibers.after(this.#pause, again);
  }

  /// Closed once it has been idle long enough: looked at when it would be, and again then if it was used since.
  #armIdle() {
    this.#idle();
    const up = this.#up;
    if (up === null) return;
    const left = Math.max(0, this.#lastUse + this.#idleMs - this.#fibers.now());
    this.#idle = this.#fibers.after(left, () => {
      if (this.#up !== up) return;
      if (up.tabs.viewing() > 0) this.used();
      if (this.#fibers.now() - this.#lastUse >= this.#idleMs) return this.#end(up, "idle");
      this.#armIdle();
    });
  }

  async #end(up: Up, why: string) {
    this.#leaving = true;
    this.#idle();
    this.#restart();
    log.info("browser", "closing Chrome", { why, pid: up.running.pid });
    up.tabs.close();
    up.keys.close();
    await up.cdp.send("Browser.close").catch(() => {});
    up.cdp.close();
    if (this.#up === up) this.#up = null;
    await this.#o.chrome.kill(up.running);
    this.#pause = 0;
    this.#note();
  }

  #note() {
    this.#noted = this.#fibers.now();
    const lastUse = this.#lastUse;
    try {
      writeState(this.#o.dir, (s) => ({ ...s, lastUse }));
    } catch {}
  }
}
