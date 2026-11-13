// A person's own pages in the station's browser (`browser:u_<id>`): opened in Chrome's persistent default profile so
// sign-ins (cookies, localStorage, IndexedDB) survive across sessions, hidden from agents, and recycled like Arc tabs —
// when nobody views one for `USER_TAB_IDLE_MS` (or when Chrome stops), its underlying Chrome target closes to free
// memory while its entry stays in `Screens` (`sleeping: true`) and reloads its saved URL the next time a person opens it.
import { randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Clock } from "effect";
import { PrivateFile } from "../ops/files.ts";
import { Fibers } from "../ops/fibers.ts";
import { ScreenRefused } from "../screens/hub.ts";
import type { ClipType, ScreenSource, ScreenView, Screens, ViewOptions } from "../screens/source.ts";
import type { TargetSnapshot, Tabs } from "./tabs.ts";
import { normalizeBrowserUrl, persistableBrowserUrl, siteOfBrowserUrl } from "./url.ts";

/// Unviewed this long, a live user tab closes its Chrome target and sleeps until opened again.
export const USER_TAB_IDLE_MS = 10 * 60_000;

type StoredTab = {
  id: string;
  url: string;
  title: string;
  targetId?: string;
};

export type UserTabsOptions = {
  dir: string;
  screens?: Screens & { changed?(): void };
  clock?: Clock.Clock;
  idleMs?: number;
  isIsolatedContext?: (browserContextId: string | undefined) => boolean;
  createTarget: (
    url: string,
    claim: () => void,
    claimed: (targetId: string, tabs: Tabs) => void,
  ) => Promise<{ targetId: string; tabs: Tabs }>;
};

class UserTab implements ScreenSource {
  readonly key: string;
  readonly id: string;
  readonly kind = "browser" as const;
  readonly userTab = true;
  readonly popup: boolean;
  url: string;
  savedTitle: string;
  targetId: string | null = null;
  resumeTargetId: string | undefined;
  views = 0;
  waking: Promise<string> | null = null;
  pendingNavigateUrl: string | null = null;
  hibernating = false;
  discarded = false;
  cancelIdle: () => void = () => {};
  removeScreen: () => void = () => {};
  #size = { width: 0, height: 0 };
  readonly #owner: UserTabs;

  constructor(owner: UserTabs, o: { key: string; url: string; title: string; popup: boolean; resumeTargetId?: string }) {
    this.#owner = owner;
    this.key = o.key;
    this.id = `browser:${o.key}`;
    this.url = o.url;
    this.savedTitle = o.title;
    this.popup = o.popup;
    this.resumeTargetId = o.resumeTargetId;
  }

  get peek(): boolean {
    return this.targetId !== null;
  }

  sleeping(): boolean {
    return this.targetId === null;
  }

  title(): string {
    return this.savedTitle || siteOfBrowserUrl(this.url) || this.url;
  }

  site(): string | undefined {
    return siteOfBrowserUrl(this.url);
  }

  size(): { width: number; height: number } {
    return this.targetId === null ? { width: 0, height: 0 } : this.#size;
  }

  sized(size: { width: number; height: number }) {
    if (size.width === this.#size.width && size.height === this.#size.height) return;
    this.#size = size;
    this.#owner.notifyScreens();
  }

  resetSize() {
    this.#size = { width: 0, height: 0 };
  }

  clipboard(): ClipType[] {
    return ["text"];
  }

  open(options: ViewOptions): Promise<ScreenView> {
    return this.#owner.openView(this, options);
  }

  openUrl(url: string): Promise<void> {
    return this.#owner.navigate(this, url);
  }

  reload(): Promise<void> {
    return this.#owner.reload(this);
  }

  sleep(): Promise<void> {
    return this.#owner.sleep(this);
  }

  discard(): Promise<void> {
    return this.#owner.discard(this);
  }
}

export class UserTabs {
  readonly #o: UserTabsOptions;
  readonly #file: PrivateFile;
  readonly #fibers: Fibers;
  readonly #idleMs: number;
  readonly #byKey = new Map<string, UserTab>();
  readonly #byTarget = new Map<string, UserTab>();
  #claiming: UserTab | null = null;
  readonly #ready: Promise<void>;
  #tabs: Tabs | null = null;
  #popupSeq = 0;
  #closed = false;

  constructor(o: UserTabsOptions) {
    this.#o = o;
    this.#file = new PrivateFile(join(o.dir, "user-tabs.json"));
    this.#fibers = new Fibers("user-tabs", o.clock);
    this.#idleMs = o.idleMs ?? USER_TAB_IDLE_MS;
    this.#ready = this.#load();
  }

  ready(): Promise<void> {
    return this.#ready;
  }

  async written(): Promise<void> {
    await this.#ready;
    await this.#file.written();
  }

  notifyScreens() {
    this.#o.screens?.changed?.();
  }

  /// Opens a new persistent user page at `rawUrl` and returns its stable screen id (`browser:u_<id>`).
  async openNew(rawUrl: string): Promise<string> {
    await this.#ready;
    const url = normalizeBrowserUrl(rawUrl);
    if (url === null) throw new ScreenRefused(400, "station.screen.badUrl");
    const key = this.#freshKey();
    const tab = new UserTab(this, { key, url, title: "", popup: false });
    this.#byKey.set(key, tab);
    tab.removeScreen = this.#o.screens?.add(tab) ?? (() => {});
    try {
      await this.#wake(tab, url);
    } catch (e) {
      tab.discarded = true;
      tab.cancelIdle();
      this.#byKey.delete(key);
      tab.removeScreen();
      this.#save();
      throw e;
    }
    if (tab.views === 0) this.#armIdle(tab);
    this.#save();
    return tab.id;
  }

  async openView(tab: UserTab, options: ViewOptions): Promise<ScreenView> {
    await this.#ready;
    if (tab.discarded || this.#closed) throw new ScreenRefused(404, "station.screen.notFound");
    if (options.peek && tab.targetId === null) throw new Error("This tab is sleeping.");
    const targetId = await this.#ensureLive(tab);
    const tabs = this.#tabs;
    if (tabs === null || tab.discarded || tab.targetId !== targetId) throw new ScreenRefused(404, "station.screen.notFound");
    const counted = options.peek !== true;
    if (counted) {
      tab.views++;
      tab.cancelIdle();
    }
    try {
      return await tabs.openTarget(targetId, options, {
        sized: (size) => tab.sized(size),
        ended: () => {
          if (!counted) return;
          tab.views = Math.max(0, tab.views - 1);
          if (tab.views === 0 && tab.targetId !== null && !tab.discarded && !this.#closed) this.#armIdle(tab);
        },
      });
    } catch (e) {
      if (counted) {
        tab.views = Math.max(0, tab.views - 1);
        if (tab.views === 0 && tab.targetId !== null && !tab.discarded && !this.#closed) this.#armIdle(tab);
      }
      throw e;
    }
  }

  async navigate(tab: UserTab, rawUrl: string): Promise<void> {
    await this.#ready;
    if (tab.discarded || this.#closed) throw new ScreenRefused(404, "station.screen.notFound");
    const url = normalizeBrowserUrl(rawUrl);
    if (url === null) throw new ScreenRefused(400, "station.screen.badUrl");
    const beforeTitle = tab.title();
    const beforeSite = tab.site();
    tab.url = url;
    tab.savedTitle = "";
    this.#save();
    if (tab.title() !== beforeTitle || tab.site() !== beforeSite) this.notifyScreens();
    if (tab.targetId !== null && this.#tabs !== null) {
      tab.pendingNavigateUrl = null;
      await this.#tabs.navigateTarget(tab.targetId, url);
      if (tab.views === 0) this.#armIdle(tab);
      return;
    }
    const joinedExistingWake = tab.waking !== null;
    tab.pendingNavigateUrl = url;
    let targetId: string;
    try {
      targetId = await this.#ensureLive(tab, url);
    } finally {
      if (tab.pendingNavigateUrl === url) tab.pendingNavigateUrl = null;
    }
    if (joinedExistingWake && !tab.discarded && !this.#closed && tab.url === url && this.#tabs !== null && tab.targetId === targetId) {
      await this.#tabs.navigateTarget(targetId, url);
      if (!tab.popup) this.#save();
    }
    if (tab.views === 0) this.#armIdle(tab);
  }

  async reload(tab: UserTab): Promise<void> {
    await this.#ready;
    if (tab.discarded || this.#closed) throw new ScreenRefused(404, "station.screen.notFound");
    if (tab.targetId !== null && this.#tabs !== null) {
      await this.#tabs.reloadTarget(tab.targetId);
      if (tab.views === 0) this.#armIdle(tab);
      return;
    }
    await this.#ensureLive(tab);
    if (tab.views === 0) this.#armIdle(tab);
  }

  async sleep(tab: UserTab): Promise<void> {
    await this.#ready;
    if (tab.discarded || this.#closed) return;
    if (tab.popup) {
      await this.discard(tab);
      return;
    }
    const targetId = tab.targetId;
    if (targetId === null) return;
    tab.hibernating = true;
    tab.pendingNavigateUrl = null;
    tab.cancelIdle();
    tab.targetId = null;
    tab.resumeTargetId = undefined;
    tab.resetSize();
    this.#byTarget.delete(targetId);
    this.#save();
    this.notifyScreens();
    const tabs = this.#tabs;
    if (tabs !== null) {
      tabs.closeViewsOf(targetId);
      await tabs.closeTarget(targetId).catch(() => {});
    }
    tab.hibernating = false;
  }

  async discard(tab: UserTab): Promise<void> {
    await this.#ready;
    if (tab.discarded) return;
    tab.discarded = true;
    tab.pendingNavigateUrl = null;
    tab.cancelIdle();
    const targetId = tab.targetId;
    tab.targetId = null;
    tab.resumeTargetId = undefined;
    if (targetId !== null) {
      this.#byTarget.delete(targetId);
    }
    this.#byKey.delete(tab.key);
    tab.removeScreen();
    if (!tab.popup) this.#save();
    if (targetId !== null && this.#tabs !== null) {
      this.#tabs.closeViewsOf(targetId);
      await this.#tabs.closeTarget(targetId).catch(() => {});
    }
  }

  /// Attaches a newly connected `Tabs` before `tabs.start()` discovers targets.
  attaching(tabs: Tabs) {
    this.#tabs = tabs;
  }

  /// Finishes attaching once `tabs.start()` has discovered every live target in Chrome.
  attached(tabs: Tabs) {
    if (this.#tabs !== tabs) return;
    let changed = false;
    for (const tab of this.#byKey.values()) {
      if (tab.resumeTargetId !== undefined && tab.targetId === null) {
        tab.resumeTargetId = undefined;
        changed = true;
      }
    }
    if (changed) this.#save();
  }

  /// Chrome stopped or died: live user pages become sleeping entries; transient popups are removed.
  browserStopped() {
    this.#tabs = null;
    this.#claiming = null;
    this.#byTarget.clear();
    let changed = false;
    let screensChanged = false;
    for (const tab of [...this.#byKey.values()]) {
      tab.cancelIdle();
      tab.pendingNavigateUrl = null;
      tab.views = 0;
      tab.hibernating = false;
      if (tab.popup) {
        tab.discarded = true;
        tab.targetId = null;
        this.#byKey.delete(tab.key);
        tab.removeScreen();
        continue;
      }
      if (tab.targetId !== null || tab.resumeTargetId !== undefined) {
        tab.targetId = null;
        tab.resumeTargetId = undefined;
        tab.resetSize();
        changed = true;
        screensChanged = true;
      }
    }
    if (changed) this.#save();
    if (screensChanged) this.notifyScreens();
  }

  /// Station process ending (handover): leaves live `targetId`s in `user-tabs.json` for the next station to re-adopt.
  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    for (const tab of this.#byKey.values()) tab.cancelIdle();
    await this.written();
    await this.#fibers.close();
  }

  /// Claims a newly created Chrome page target when it is a user tab (or a popup opened from one).
  targetCreated(info: TargetSnapshot): string | undefined {
    const existing = this.#byTarget.get(info.targetId);
    if (existing !== undefined) {
      this.#applyInfo(existing, info, true);
      if (this.#tabs) void this.#tabs.measureTarget(info.targetId, (s) => existing.sized(s), () => existing.size().width);
      return existing.id;
    }
    if (this.#o.isIsolatedContext?.(info.browserContextId)) return undefined;
    // 1. Re-adopting a live user tab left running by an earlier station process.
    for (const tab of this.#byKey.values()) {
      if (tab.targetId === null && tab.resumeTargetId === info.targetId) {
        this.#bindTarget(tab, info.targetId);
        this.#applyInfo(tab, info, true);
        if (tab.views === 0) this.#armIdle(tab);
        if (this.#tabs) void this.#tabs.measureTarget(info.targetId, (s) => tab.sized(s), () => tab.size().width);
        return tab.id;
      }
    }
    // 2. The target `UserTabs` is creating right now on the default-context creation queue.
    if (!info.openerId && this.#claiming !== null) {
      const tab = this.#claiming;
      this.#claiming = null;
      if (!tab.discarded) {
        this.#bindTarget(tab, info.targetId);
        this.#applyInfo(tab, info, true);
        if (this.#tabs) void this.#tabs.measureTarget(info.targetId, (s) => tab.sized(s), () => tab.size().width);
        return tab.id;
      }
    }
    // 3. A child popup / `target="_blank"` tab opened from a live user tab.
    const opener = info.openerId ? this.#byTarget.get(info.openerId) : undefined;
    if (opener !== undefined) {
      const key = `u_p_${++this.#popupSeq}_${randomBytes(3).toString("hex")}`;
      const url = persistableBrowserUrl(info.url ?? "") ?? opener.url;
      const popup = new UserTab(this, { key, url, title: info.title ?? "", popup: true });
      this.#byKey.set(key, popup);
      this.#bindTarget(popup, info.targetId);
      popup.removeScreen = this.#o.screens?.add(popup) ?? (() => {});
      this.#armIdle(popup);
      if (this.#tabs) void this.#tabs.measureTarget(info.targetId, (s) => popup.sized(s), () => popup.size().width);
      return popup.id;
    }
    return undefined;
  }

  targetInfoChanged(info: TargetSnapshot): boolean {
    const tab = this.#byTarget.get(info.targetId);
    if (tab === undefined) return false;
    this.#applyInfo(tab, info, false);
    return true;
  }

  targetDestroyed(targetId: string): boolean {
    const tab = this.#byTarget.get(targetId);
    if (tab === undefined) return false;
    this.#byTarget.delete(targetId);
    tab.cancelIdle();
    if (tab.discarded) return true;
    if (tab.popup) {
      tab.discarded = true;
      tab.targetId = null;
      this.#byKey.delete(tab.key);
      tab.removeScreen();
      return true;
    }
    tab.targetId = null;
    tab.resumeTargetId = undefined;
    tab.hibernating = false;
    tab.resetSize();
    this.#save();
    this.notifyScreens();
    return true;
  }

  refreshTitles(infos: TargetSnapshot[]) {
    for (const info of infos) {
      const tab = this.#byTarget.get(info.targetId);
      if (tab !== undefined) this.#applyInfo(tab, info, false);
    }
  }

  #ensureLive(tab: UserTab, overrideUrl?: string): Promise<string> {
    if (tab.targetId !== null && overrideUrl === undefined) return Promise.resolve(tab.targetId);
    if (tab.waking !== null) return tab.waking;
    const p = this.#wake(tab, overrideUrl ?? tab.url).finally(() => {
      if (tab.waking === p) tab.waking = null;
    });
    tab.waking = p;
    return p;
  }

  async #wake(tab: UserTab, url: string): Promise<string> {
    let created: { targetId: string; tabs: Tabs };
    try {
      created = await this.#o.createTarget(
        url,
        () => {
          this.#claiming = tab;
        },
        (targetId, tabs) => {
          if (this.#claiming === tab) this.#claiming = null;
          if (tab.targetId === null && !tab.discarded && !this.#closed) {
            this.#bindTarget(tab, targetId);
            void tabs.measureTarget(targetId, (s) => tab.sized(s), () => tab.size().width);
          }
        },
      );
    } catch (e) {
      if (this.#claiming === tab) this.#claiming = null;
      throw e;
    }
    const { targetId, tabs } = created;
    if (tab.discarded || this.#closed) {
      await tabs.closeTarget(targetId).catch(() => {});
      throw new ScreenRefused(404, "station.screen.notFound");
    }
    await tabs.arrived(targetId);
    if (!tab.popup) this.#save();
    this.notifyScreens();
    return targetId;
  }

  #bindTarget(tab: UserTab, targetId: string) {
    if (tab.targetId !== null && tab.targetId !== targetId) this.#byTarget.delete(tab.targetId);
    tab.targetId = targetId;
    tab.resumeTargetId = targetId;
    this.#byTarget.set(targetId, tab);
  }

  #applyInfo(tab: UserTab, info: TargetSnapshot, forceNotify: boolean) {
    const beforeTitle = tab.title();
    const beforeSite = tab.site();
    let persist = false;
    const nextUrl = typeof info.url === "string" ? persistableBrowserUrl(info.url) : null;
    if (tab.pendingNavigateUrl !== null && nextUrl !== tab.pendingNavigateUrl) {
      if (forceNotify) this.notifyScreens();
      return;
    }
    if (nextUrl !== null && nextUrl !== tab.url) {
      const oldSite = siteOfBrowserUrl(tab.url);
      const newSite = siteOfBrowserUrl(nextUrl);
      tab.url = nextUrl;
      if (oldSite !== newSite && !(info.title ?? "").trim()) tab.savedTitle = "";
      persist = true;
    }
    const trimmedTitle = (info.title ?? "").trim();
    if (trimmedTitle !== "" && trimmedTitle !== tab.savedTitle) {
      tab.savedTitle = trimmedTitle;
      persist = true;
    }
    if (persist && !tab.popup) this.#save();
    if (forceNotify || tab.title() !== beforeTitle || tab.site() !== beforeSite) this.notifyScreens();
  }

  #armIdle(tab: UserTab) {
    tab.cancelIdle();
    if (this.#closed || tab.discarded || tab.targetId === null || tab.views > 0) return;
    tab.cancelIdle = this.#fibers.after(this.#idleMs, () => {
      if (this.#closed || tab.discarded || tab.targetId === null || tab.views > 0) return;
      void this.sleep(tab);
    });
  }

  #freshKey(): string {
    for (;;) {
      const key = `u_${randomBytes(6).toString("hex")}`;
      if (!this.#byKey.has(key)) return key;
    }
  }

  async #load(): Promise<void> {
    const raw = await readFile(this.#file.path, "utf8").catch(() => null);
    if (raw === null || this.#closed) return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return;
    }
    const items = Array.isArray((parsed as { tabs?: unknown })?.tabs) ? ((parsed as { tabs: unknown[] }).tabs) : [];
    for (const item of items) {
      if (item === null || typeof item !== "object") continue;
      const rec = item as Partial<StoredTab>;
      if (typeof rec.id !== "string" || !/^u_[a-z0-9_-]{1,40}$/i.test(rec.id) || this.#byKey.has(rec.id)) continue;
      const url = typeof rec.url === "string" ? persistableBrowserUrl(rec.url) : null;
      if (url === null) continue;
      const title = typeof rec.title === "string" ? rec.title.trim().slice(0, 512) : "";
      const resumeTargetId = typeof rec.targetId === "string" && rec.targetId !== "" ? rec.targetId : undefined;
      const tab = new UserTab(this, { key: rec.id, url, title, popup: false, resumeTargetId });
      this.#byKey.set(rec.id, tab);
      tab.removeScreen = this.#o.screens?.add(tab) ?? (() => {});
    }
  }

  #save() {
    if (this.#closed) return;
    const tabs: StoredTab[] = [];
    for (const tab of this.#byKey.values()) {
      if (tab.popup || tab.discarded) continue;
      tabs.push({
        id: tab.key,
        url: tab.url,
        title: tab.savedTitle,
        ...(tab.targetId !== null ? { targetId: tab.targetId } : {}),
      });
    }
    void this.#file.write(JSON.stringify({ tabs }, null, 2) + "\n");
  }
}
