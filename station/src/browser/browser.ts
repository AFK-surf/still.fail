// The station's browser: one real Chrome, kept for the agents, its tabs screens a person can
// see and drive. Started when an agent asks for it (the `browser` tool), started again if it dies while in use, closed
// after a long idle. It outlives a station process, as jobs do: the next one (a handover, a restart) finds it by its
// DevToolsActivePort and takes it up, its tabs and logins as they were.
import type { Clock } from "effect";
import { open, readFile, rename, unlink } from "node:fs/promises";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { ScreenBrowser, Screens } from "../screens/source.ts";
import type { Cdp, CdpEvent } from "./cdp.ts";
import { type ChromeHost, type Running, readState, writeState } from "./chrome.ts";
import { Owners } from "./owners.ts";
import { Authenticators } from "./passkeys.ts";
import { BEHIND } from "./gate.ts";
import { allCookies, keptOf, stateOf } from "./signins.ts";
import { type TabInfo, Tabs } from "./tabs.ts";
import { USER_TAB_IDLE_MS, UserTabs } from "./user-tabs.ts";

export { USER_TAB_IDLE_MS };

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
  userTabIdleMs?: number;
  /// Chrome's time for the tabs (tabs.ts `later`): the machine's unless given.
  later?: (ms: number, f: () => void) => () => void;
  /// The session whose chat's context a browser context is (browsers.ts): a tab in it is that session's.
  contextOwner?: (browserContextId: string | undefined) => string | undefined;
  usedTab?: (session: string, targetId: string) => void;
};

export type OpenTabOptions = {
  /// Where this tab's isolated browser context keeps its cookies and passkeys across sign-ins (null when gone).
  stateFile?: () => string | null;
};

type LoginTab = {
  ctx: string;
  stateFile: () => string | null;
  ending: Promise<void> | null;
  saving: Promise<void>;
};

type Up = {
  running: Running;
  cdp: Cdp;
  tabs: Tabs;
  keys: Authenticators;
  loginContexts: Set<string>;
  loginTabs: Map<string, LoginTab>;
  unlisten: () => void;
  since: number;
};

let loginStateSeq = 0;

/// Writes `content` to `resolvePath()` (mode 0600) only when its parent directory exists: never recreates a dropped
/// pending login's home, and follows a new login's home if `pendingChanged` just renamed it.
async function writeLoginState(resolvePath: () => string | null, content: string): Promise<void> {
  let tried: string | null = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    const path = resolvePath();
    if (path === null || path === tried) return;
    tried = path;
    const tmp = `${path}.${process.pid}.${++loginStateSeq}.tmp`;
    let handle;
    try {
      handle = await open(tmp, "w", 0o600);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "ENOENT") continue;
      throw e;
    }
    try {
      await handle.writeFile(content, { encoding: "utf8" });
      await handle.datasync();
    } catch (e) {
      await handle.close().catch(() => {});
      await unlink(tmp).catch(() => {});
      throw e;
    }
    await handle.close();
    try {
      await rename(tmp, path);
      return;
    } catch (e) {
      await unlink(tmp).catch(() => {});
      if ((e as NodeJS.ErrnoException).code === "ENOENT") continue;
      throw e;
    }
  }
}

export class StationBrowser implements ScreenBrowser {
  readonly #o: BrowserOptions;
  readonly #fibers: Fibers;
  readonly #idleMs: number;
  readonly #flushing = new Set<Promise<void>>();
  readonly #userTabs: UserTabs;
  #defaultCreateQueue: Promise<void> = Promise.resolve();
  #activeLoginContexts: Set<string> | null = null;
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
    this.#userTabs = new UserTabs({
      dir: o.dir,
      screens: o.screens,
      clock: o.clock,
      idleMs: o.userTabIdleMs,
      isIsolatedContext: (ctx) => Boolean(ctx && (o.contextOwner?.(ctx) !== undefined || this.#activeLoginContexts?.has(ctx))),
      createTarget: (url, claim, claimed) => this.#createDefaultTarget(url, claim, claimed),
    });
    o.screens?.setBrowser?.(this);
  }

  /// Takes up the Chrome an earlier station process left running, if there is one (its tabs become screens again).
  async resume(): Promise<void> {
    await this.#userTabs.ready();
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

  /// Opens a persistent user page (`browser:u_<id>`) in Chrome's default profile, recycled to sleep when idle.
  openUserTab(url: string, id?: string): Promise<string> {
    return this.#userTabs.openNew(url, id);
  }

  async #createDefaultTarget(
    url: string,
    claim?: () => void,
    claimed?: (targetId: string, tabs: Tabs) => void,
  ): Promise<{ targetId: string; tabs: Tabs }> {
    this.used();
    const up = await this.#ensure();
    let release!: () => void;
    const prev = this.#defaultCreateQueue;
    this.#defaultCreateQueue = new Promise<void>((r) => (release = r));
    await prev;
    try {
      claim?.();
      const { targetId } = await up.cdp.send("Target.createTarget", { url, ...BEHIND });
      if (typeof targetId !== "string" || targetId === "") throw new Error("Chrome opened no tab.");
      claimed?.(targetId, up.tabs);
      return { targetId, tabs: up.tabs };
    } finally {
      release();
    }
  }

  /// A tab of the station's own (no session's) at `url`, in a window of its own opened behind the others (as a
  /// session's: proxy.ts), the browser started if it is not running: its target id, once it is among the screens.
  /// With `options.stateFile`, opened in a browser context of its own whose cookies and passkeys are read from and
  /// saved back to that file (and disposed when the tab closes).
  async openTab(url: string, options?: OpenTabOptions): Promise<string> {
    this.used();
    if (!options?.stateFile) {
      const { targetId, tabs } = await this.#createDefaultTarget(url);
      await tabs.arrived(targetId);
      return targetId;
    }
    const up = await this.#ensure();
    const { browserContextId } = await up.cdp.send("Target.createBrowserContext", { disposeOnDetach: false });
    if (typeof browserContextId !== "string" || browserContextId === "") throw new Error("Chrome made no browser context.");
    up.loginContexts.add(browserContextId);
    const initialPath = options.stateFile();
    if (initialPath !== null) {
      const kept = await readFile(initialPath, "utf8").catch(() => null);
      if (kept !== null) {
        const state = stateOf(kept);
        const cookies = allCookies(state.cookies);
        if (cookies.length > 0) {
          await up.cdp.send("Storage.setCookies", { browserContextId, cookies }).catch(async () => {
            for (const cookie of cookies) {
              await up.cdp.send("Storage.setCookies", { browserContextId, cookies: [cookie] }).catch(() => {});
            }
          });
        }
        if (state.passkeys.length > 0) await up.keys.put(browserContextId, state.passkeys);
      }
    }
    let targetId = "";
    try {
      const created = await up.cdp.send("Target.createTarget", { url, browserContextId, ...BEHIND });
      targetId = typeof created?.targetId === "string" ? created.targetId : "";
      if (targetId === "") throw new Error("Chrome opened no tab.");
      up.loginTabs.set(targetId, {
        ctx: browserContextId,
        stateFile: options.stateFile,
        ending: null,
        saving: Promise.resolve(),
      });
      await up.tabs.arrived(targetId);
      return targetId;
    } catch (e) {
      if (targetId !== "") up.loginTabs.delete(targetId);
      up.loginContexts.delete(browserContextId);
      up.keys.forget(browserContextId);
      await up.cdp.send("Target.disposeBrowserContext", { browserContextId }).catch(() => {});
      throw e;
    }
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
    if (up === null) return;
    if (up.loginTabs.has(targetId)) {
      await this.#trackFlush(this.#endLoginTab(up, targetId, true));
      return;
    }
    if (!up.tabs.has(targetId)) return;
    await up.tabs.closeTab(targetId).catch(() => {});
  }

  /// Waits for any in-flight login-context and user-tab saves and disposals to finish.
  async flushed(): Promise<void> {
    while (this.#flushing.size > 0) await Promise.all([...this.#flushing]);
    await this.#userTabs.written();
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
    this.#o.screens?.setBrowser?.(null);
    const up = this.#up;
    this.#up = null;
    this.#activeLoginContexts = null;
    if (up) {
      for (const tab of up.loginTabs.values()) {
        if (tab.ending === null) this.#trackFlush(this.#saveLoginTab(up, tab));
      }
      await this.flushed();
      await this.#userTabs.close();
      up.unlisten();
      up.tabs.close();
      up.keys.close();
      up.cdp.close();
    } else {
      await this.flushed();
      await this.#userTabs.close();
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
      await this.#userTabs.ready();
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
    // (each chat's tab and each isolated login tab its authenticator: passkeys.ts; the station's shared context has none)
    const owner = this.#o.contextOwner;
    const loginContexts = new Set<string>();
    const loginTabs = new Map<string, LoginTab>();
    this.#activeLoginContexts = loginContexts;
    let current: Up | null = null;
    const keys = new Authenticators(
      cdp,
      (ctx) => owner?.(ctx) !== undefined || loginContexts.has(ctx),
      (ctx) => this.#loginContextChanged(current, ctx),
    );
    const tabs: Tabs = new Tabs({
      cdp, screens, connect: () => chrome.connect(running.ws), now: () => this.#fibers.now(), activity: () => this.used(), later: this.#o.later,
      owners: this.#owners, ...(owner ? { contextOwner: owner } : {}),
      ownPasskey: (targetId: string, rpId: string): boolean => {
        const ctx = tabs.contextOf(targetId);
        return ctx !== undefined && keys.has(ctx, rpId);
      },
      usedTab: (session, targetId) => this.#o.usedTab?.(session, targetId),
      userTabs: this.#userTabs,
    });
    this.#userTabs.attaching(tabs);
    const unlisten = cdp.on((e) => this.#heardLogin(current, e));
    try {
      await keys.start();
      await tabs.start();
      this.#userTabs.attached(tabs);
    } catch (e) {
      this.#activeLoginContexts = null;
      this.#userTabs.browserStopped();
      unlisten();
      keys.close();
      tabs.close();
      cdp.close();
      throw e;
    }
    if (this.#closed) {
      this.#activeLoginContexts = null;
      unlisten();
      keys.close();
      tabs.close();
      cdp.close();
      throw new Error("The station is stopping.");
    }
    const up: Up = { running, cdp, tabs, keys, loginContexts, loginTabs, unlisten, since: this.#fibers.now() };
    current = up;
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
    this.#activeLoginContexts = null;
    up.unlisten();
    up.tabs.close();
    this.#userTabs.browserStopped();
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
    for (const tab of up.loginTabs.values()) {
      if (tab.ending === null) this.#trackFlush(this.#saveLoginTab(up, tab));
    }
    await this.flushed();
    up.unlisten();
    up.tabs.close();
    this.#userTabs.browserStopped();
    up.keys.close();
    await up.cdp.send("Browser.close").catch(() => {});
    up.cdp.close();
    if (this.#up === up) {
      this.#up = null;
      this.#activeLoginContexts = null;
    }
    await this.#o.chrome.kill(up.running);
    this.#pause = 0;
    this.#note();
  }

  #trackFlush(p: Promise<void>): Promise<void> {
    const tracked = p.then(() => {}, () => {});
    this.#flushing.add(tracked);
    void tracked.then(() => this.#flushing.delete(tracked));
    return p;
  }

  #heardLogin(up: Up | null, e: CdpEvent) {
    if (up === null || e.sessionId !== undefined) return;
    if (e.method === "Target.targetInfoChanged") {
      const targetId = e.params?.targetInfo?.targetId;
      const tab = typeof targetId === "string" ? up.loginTabs.get(targetId) : undefined;
      if (tab && tab.ending === null) void this.#trackFlush(this.#saveLoginTab(up, tab));
    } else if (e.method === "Target.targetDestroyed") {
      const targetId = e.params?.targetId;
      const tab = typeof targetId === "string" ? up.loginTabs.get(targetId) : undefined;
      if (tab && tab.ending === null) void this.#trackFlush(this.#endLoginTab(up, targetId, false));
    }
  }

  #loginContextChanged(up: Up | null, ctx: string) {
    if (up === null) return;
    for (const tab of up.loginTabs.values()) {
      if (tab.ctx === ctx && tab.ending === null) void this.#trackFlush(this.#saveLoginTab(up, tab));
    }
  }

  #saveLoginTab(up: Up, tab: LoginTab): Promise<void> {
    const next = tab.saving.then(async () => {
      const path = tab.stateFile();
      if (path === null) return;
      const got = await up.cdp.send("Storage.getCookies", { browserContextId: tab.ctx }).catch(() => null);
      if (got === null) return;
      const cookies = allCookies(got.cookies);
      const passkeys = await up.keys.read(tab.ctx).catch(() => []);
      if (cookies.length === 0 && passkeys.length === 0) {
        const target = tab.stateFile();
        if (target !== null) await unlink(target).catch(() => {});
        return;
      }
      await writeLoginState(tab.stateFile, keptOf({ cookies, passkeys }));
    }).catch((e) => {
      log.warn("browser", "could not save a login tab's state", { error: (e as Error).message });
    });
    tab.saving = next;
    return next;
  }

  #endLoginTab(up: Up, targetId: string, closeTarget: boolean): Promise<void> {
    const tab = up.loginTabs.get(targetId);
    if (!tab) return Promise.resolve();
    if (tab.ending) return tab.ending;
    const ending = (async () => {
      await this.#saveLoginTab(up, tab);
      if (closeTarget && up.tabs.has(targetId)) await up.tabs.closeTab(targetId).catch(() => {});
      up.loginTabs.delete(targetId);
      up.loginContexts.delete(tab.ctx);
      up.keys.forget(tab.ctx);
      await up.cdp.send("Target.disposeBrowserContext", { browserContextId: tab.ctx }).catch(() => {});
    })();
    tab.ending = ending;
    return ending;
  }

  #note() {
    this.#noted = this.#fibers.now();
    const lastUse = this.#lastUse;
    try {
      writeState(this.#o.dir, (s) => ({ ...s, lastUse }));
    } catch {}
  }
}
