// The tabs of the station's browser, as its DevTools tell of them (Target.setDiscoverTargets on the station's own
// connection): listed to the agents, and each a screen source (`browser:<targetId>`) in the station's Screens while it
// is there, saying the session that opened it (owners.ts) and closed from a person's app (docs/remote-screens.md).
import type { ClipType, ScreenSource, ScreenView, Screens, ViewOptions } from "../screens/source.ts";
import { wall } from "../ops/fibers.ts";
import type { Cdp, CdpEvent } from "./cdp.ts";
import type { Owners } from "./owners.ts";
import { TabView, viewportOf } from "./view.ts";

/// `session`: the session that opened it, when known.
export type TabInfo = { id: string; title: string; url: string; attached: boolean; session?: string };

/// What the tabs need of the browser.
export type TabsParts = {
  /// The station's connection to the browser (its watch on the targets).
  cdp: Cdp;
  /// Where the tabs are added as screens (a registry made by `makeScreens`: its `changed` says a title changed).
  screens?: Screens & { changed?(): void };
  /// A new connection to the browser, for a view of its own.
  connect(): Promise<Cdp>;
  /// Milliseconds.
  now(): number;
  /// Something happened in the browser (a tab came, went, was navigated), or a view opened or ended.
  activity(): void;
  /// `f` once, `ms` from now (Chrome's time: the machine's); the function returned calls it off.
  later?(ms: number, f: () => void): () => void;
  /// Which session opened each tab of the station's own context; none: not known.
  owners?: Owners;
  /// The session whose chat's context a browser context is (browsers.ts).
  contextOwner?: (browserContextId: string | undefined) => string | undefined;
};

/// Chrome tells of a tab's new address, not of its title, which the page sets after (Chrome 155): the titles are read
/// again this long after a tab came or changed.
const TITLES_AFTER_MS = [1000, 5000];
/// How long a tab just created is waited for (`arrived`).
const ARRIVE_MS = 3000;

/// A tab as a screen source.
class Tab implements ScreenSource {
  readonly id: string;
  readonly kind = "browser" as const;
  readonly peek = true;
  info: { targetId: string; title: string; url: string; attached: boolean };
  #size = { width: 0, height: 0 };
  readonly #tabs: Tabs;

  constructor(tabs: Tabs, info: Tab["info"]) {
    this.#tabs = tabs;
    this.info = info;
    this.id = `browser:${info.targetId}`;
  }

  title(): string {
    return this.info.title || this.info.url;
  }

  size() {
    return this.#size;
  }

  /// Text: what the page copies is heard (view.ts COPY_HOOK), what the viewer pastes is inserted where its focus is.
  clipboard(): ClipType[] {
    return ["text"];
  }

  /// Its viewport, as measured or as a view's frames say it: the screens' watchers hear when it changed.
  sized(size: { width: number; height: number }) {
    if (size.width === this.#size.width && size.height === this.#size.height) return;
    this.#size = size;
    this.#tabs.resized(this);
  }

  open(options: ViewOptions): Promise<ScreenView> {
    return this.#tabs.open(this, options);
  }

  openedBy(): string | undefined {
    return this.#tabs.ownerOf(this.info.targetId);
  }

  discard(): Promise<void> {
    return this.#tabs.closeTab(this.info.targetId);
  }
}

export class Tabs {
  readonly #p: TabsParts;
  readonly #tabs = new Map<string, { tab: Tab; remove: () => void }>();
  /// The browser context of every target told of (pages, frames, workers): whose chat's it is (gate.ts).
  readonly #contexts = new Map<string, string>();
  readonly #views = new Set<TabView>();
  #unlisten: () => void = () => {};
  #closed = false;
  /// Past the tabs that were there at start (told as created): what comes now is the browser being used.
  #ready = false;
  #rereads: (() => void)[] = [];
  /// Who waits for a tab to come (`arrived`), by its target id.
  readonly #awaited = new Map<string, (() => void)[]>();

  constructor(p: TabsParts) {
    this.#p = p;
  }

  /// Starts watching: the tabs there now come as created.
  async start() {
    this.#unlisten = this.#p.cdp.on((e) => this.#heard(e));
    await this.#p.cdp.send("Target.setDiscoverTargets", { discover: true });
    this.#ready = true;
    // Those of tabs closed while no station process watched are forgotten.
    this.#p.owners?.keep(new Set(this.#tabs.keys()));
  }

  list(): TabInfo[] {
    return [...this.#tabs.values()].map(({ tab }) => {
      const session = this.ownerOf(tab.info.targetId);
      return { id: tab.info.targetId, title: tab.info.title, url: tab.info.url, attached: tab.info.attached, ...(session ? { session } : {}) };
    });
  }

  /// Whether tab `targetId` is there.
  has(targetId: string): boolean {
    return this.#tabs.has(targetId);
  }

  /// Resolves once tab `targetId` is there (a tab just created: Chrome may answer before it tells of it), or after
  /// `ms` all the same.
  arrived(targetId: string, ms = ARRIVE_MS): Promise<void> {
    if (this.#closed || this.#tabs.has(targetId)) return Promise.resolve();
    return new Promise((resolve) => {
      const stop = (this.#p.later ?? wall.after)(ms, () => done());
      const done = () => {
        stop();
        const left = (this.#awaited.get(targetId) ?? []).filter((w) => w !== done);
        if (left.length > 0) this.#awaited.set(targetId, left);
        else this.#awaited.delete(targetId);
        resolve();
      };
      this.#awaited.set(targetId, [...(this.#awaited.get(targetId) ?? []), done]);
    });
  }

  /// The session whose tab `targetId` is: its context's chat's, else the one that opened it in the station's own.
  ownerOf(targetId: string): string | undefined {
    return this.#p.contextOwner?.(this.#contexts.get(targetId)) ?? this.#p.owners?.of(targetId);
  }

  /// The browser context of target `targetId`, when it was told of.
  contextOf(targetId: string): string | undefined {
    return this.#contexts.get(targetId);
  }

  /// Tab `targetId` was opened by `session` (its connection said so): the screens' watchers hear, once it is there.
  owned(targetId: string, session: string) {
    if (this.#p.owners?.set(targetId, session) !== true) return;
    const known = this.#tabs.get(targetId);
    if (known !== undefined) this.#retitled(known);
  }

  /// The tabs `session` opened that are there now.
  ofSession(session: string): string[] {
    return [...this.#tabs.keys()].filter((id) => this.ownerOf(id) === session);
  }

  /// Closes tab `targetId` (it leaves the screens as Chrome tells it went).
  async closeTab(targetId: string): Promise<void> {
    if (this.#closed || !this.#tabs.has(targetId)) throw new Error("This tab is closed.");
    await this.#p.cdp.send("Target.closeTarget", { targetId });
  }

  /// How many views of the tabs are open.
  viewing(): number {
    return this.#views.size;
  }

  /// Stops watching: every tab leaves the screens, every view ends.
  close() {
    if (this.#closed) return;
    this.#closed = true;
    this.#unlisten();
    for (const stop of this.#rereads.splice(0)) stop();
    for (const view of [...this.#views]) view.close();
    for (const { remove } of this.#tabs.values()) remove();
    this.#tabs.clear();
    for (const waiters of [...this.#awaited.values()]) for (const done of waiters) done();
  }

  async open(tab: Tab, options: ViewOptions): Promise<ScreenView> {
    if (!options.codecs.includes("jpeg")) throw new Error("A tab of the station's browser is seen as JPEG frames, which this viewer does not take.");
    if (this.#closed || !this.#tabs.has(tab.info.targetId)) throw new Error("This tab is closed.");
    const cdp = await this.#p.connect();
    try {
      const { sessionId } = await cdp.send("Target.attachToTarget", { targetId: tab.info.targetId, flatten: true });
      const view: TabView = new TabView({
        cdp, session: sessionId, targetId: tab.info.targetId, now: () => this.#p.now(),
        sized: (size) => tab.sized(size),
        ended: () => {
          this.#views.delete(view);
          this.#p.activity();
        },
      });
      this.#views.add(view);
      this.#p.activity();
      await view.start(options);
      return view;
    } catch (e) {
      cdp.close();
      throw e;
    }
  }

  #heard(e: CdpEvent) {
    if (e.sessionId !== undefined) return;
    const activity = () => {
      this.#titlesLater();
      if (this.#ready) this.#p.activity();
    };
    const info = e.params?.targetInfo;
    if (typeof info?.targetId === "string" && typeof info.browserContextId === "string") this.#contexts.set(info.targetId, info.browserContextId);
    if (e.method === "Target.targetDestroyed" && !this.#tabs.has(e.params?.targetId)) this.#contexts.delete(e.params?.targetId);
    switch (e.method) {
      case "Target.targetCreated":
        if (info?.type !== "page") return;
        if (!this.#tabs.has(info.targetId)) {
          // A tab a page opened (a link to a new window, a popup) is its opener's session's.
          const opener = typeof info.openerId === "string" ? this.ownerOf(info.openerId) : undefined;
          if (opener !== undefined) this.#p.owners?.set(info.targetId, opener);
          const tab = new Tab(this, { targetId: info.targetId, title: info.title ?? "", url: info.url ?? "", attached: Boolean(info.attached) });
          const remove = this.#p.screens?.add(tab) ?? (() => {});
          this.#tabs.set(info.targetId, { tab, remove });
          void this.#measure(tab);
          for (const done of this.#awaited.get(info.targetId) ?? []) done();
        }
        activity();
        return;
      case "Target.targetInfoChanged": {
        const known = info ? this.#tabs.get(info.targetId) : undefined;
        if (known === undefined) return;
        const before = known.tab.title();
        known.tab.info = { targetId: info.targetId, title: info.title ?? "", url: info.url ?? "", attached: Boolean(info.attached) };
        if (known.tab.title() !== before) this.#retitled(known);
        activity();
        return;
      }
      case "Target.targetDestroyed": {
        const known = this.#tabs.get(e.params.targetId);
        if (known === undefined) return;
        this.#tabs.delete(e.params.targetId);
        this.#contexts.delete(e.params.targetId);
        this.#p.owners?.drop(e.params.targetId);
        known.remove();
        activity();
        return;
      }
    }
  }

  /// The titles read again a little later (and again after that), once a tab came or changed.
  #titlesLater() {
    for (const stop of this.#rereads.splice(0)) stop();
    const later = this.#p.later ?? wall.after;
    this.#rereads = TITLES_AFTER_MS.map((ms) => later(ms, () => void this.#titles()));
  }

  async #titles() {
    if (this.#closed) return;
    const { targetInfos } = await this.#p.cdp.send("Target.getTargets").catch(() => ({ targetInfos: [] }));
    for (const info of targetInfos ?? []) {
      const known = this.#tabs.get(info.targetId);
      if (known === undefined || (info.title ?? "") === known.tab.info.title) continue;
      const before = known.tab.title();
      known.tab.info = { ...known.tab.info, title: info.title ?? "", url: info.url ?? known.tab.info.url };
      if (known.tab.title() !== before) this.#retitled(known);
    }
  }

  /// A tab's size changed: the screens' watchers hear of it.
  resized(tab: Tab) {
    const known = this.#tabs.get(tab.info.targetId);
    if (known !== undefined && known.tab === tab) this.#retitled(known);
  }

  /// A tab's title changed: the screens' watchers hear of it.
  #retitled(known: { tab: Tab; remove: () => void }) {
    const screens = this.#p.screens;
    if (screens === undefined) return;
    if (screens.changed) screens.changed();
    // A registry that cannot say so: the same source added again (its list is told).
    else known.remove = screens.add(known.tab);
  }

  /// A tab's size before a view says it: its viewport (what its frames show, not its window with the toolbar),
  /// read on a connection of its own (the browser's own attaches to no tab); its window's when that cannot be read.
  async #measure(tab: Tab) {
    let cdp: Cdp | null = null;
    try {
      cdp = await this.#p.connect();
      const { sessionId } = await cdp.send("Target.attachToTarget", { targetId: tab.info.targetId, flatten: true });
      const viewport = viewportOf(await cdp.send("Page.getLayoutMetrics", {}, sessionId));
      if (viewport !== null) {
        if (tab.size().width === 0) tab.sized(viewport);
        return;
      }
    } catch {
    } finally {
      cdp?.close();
    }
    try {
      const { bounds } = await this.#p.cdp.send("Browser.getWindowForTarget", { targetId: tab.info.targetId });
      if (tab.size().width === 0 && bounds?.width > 0) tab.sized({ width: bounds.width, height: bounds.height });
    } catch {}
  }
}
