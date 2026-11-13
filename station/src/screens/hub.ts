// The station's screens: the registry its parts add their sources to (source.ts
// `makeScreens`), and who is on each now. What members are told of them (GET /admin/api/screens, `screens` on the
// event stream, the agents' `screen` tool) is said here; the views themselves go over the member link (mesh/screens.ts).
import { wall } from "../ops/fibers.ts";
import { type Lang, tr } from "../ops/i18n.ts";
import { type ChromePictures, picturesOf, toldOf } from "./sim-chrome.ts";
import type { SimDebug } from "./sim-debug.ts";
import { type ScreenAccess, type ScreenBrowser, type ScreenSource, type ScreenView, type Screens, type ViewOptions, makeScreens } from "./source.ts";

/// One view open now: whose, whether its input is taken, and how it is told its people changed. `device`: the member's
/// device it came over (the credential's, so to be believed); `client`, `app`: the name and kind of app that device says
/// it is (shown only; none from a client before them). `self`: the device's own main id as it says it, which its link's
/// `device` is not on a link made for a LAN or a relay (only for it to know its own views). `agent`: an agent's own view (computer.ts). `end` and `watchOnly`:
/// how a member elsewhere ends it or stops its input being taken, `by` naming them (for `watchOnly`, who took it, if one did).
export type Watcher = { name: string; control: boolean; tell(state: Record<string, unknown>): void; device?: string; self?: string; client?: string; app?: string; agent?: boolean; end?(by: string): void; watchOnly?(by?: string): void };

/// One view as members are told of it: `id`, the hub's, to end it by; `at`,
/// when it opened (ms).
export type ViewShown = { id: string; name: string; control: boolean; at: number; device?: string; self?: string; client?: string; app?: string; agent?: boolean };

/// Where a person's view is, for an agent to name it to them: the app, the device (its id's start), how long it has been open.
export function viewOn(v: ViewShown): string {
  const minutes = Math.max(0, Math.round((wall.now() - v.at) / 60_000));
  const opened = minutes < 1 ? "just now" : minutes < 120 ? `${minutes} min ago` : `${Math.round(minutes / 60)} h ago`;
  return [v.client ?? "an app that does not say its name", ...(v.device ? [`device ${v.device.slice(0, 12)}`] : []), `opened ${opened}`].join(", ");
}

/// What a person is told of a source's access when something is missing: whether it can be seen and driven, why not,
/// in their language, and what to turn on.
export type AccessShown = { capture: boolean; control: boolean; message: string; app?: string; path?: string; asking?: boolean; help?: "linux-desktop" };

/// A source that cannot be opened now, and why, in words a person reads (`key` of client/i18n's station part).
export class ScreenRefused extends Error {
  readonly status: number;
  readonly key: string;
  readonly args: Record<string, unknown>;
  readonly access?: ScreenAccess;
  constructor(status: number, key: string, args: Record<string, unknown> = {}, access?: ScreenAccess) {
    super(tr("en", key, args));
    this.status = status;
    this.key = key;
    this.args = args;
    this.access = access;
  }
}

/// The message for what is missing; none when nothing is.
export function accessShown(access: ScreenAccess | undefined, lang: Lang): AccessShown | undefined {
  if (access === undefined || (access.capture && access.control && access.unsupported === undefined && access.reason === undefined)) return undefined;
  const named = { app: access.app || "still.fail Helper" };
  const message =
    access.reason ? tr(lang, `station.screen.${access.reason}`)
    : access.unsupported === "platform" ? tr(lang, "station.screen.unsupported")
    : access.unsupported === "helper" ? tr(lang, "station.screen.noHelper")
    : [
        // Neither: it cannot be viewed either, so not "viewed but not controlled".
        !access.capture && !access.control ? tr(lang, "station.screen.bothOff", named)
        : !access.capture ? tr(lang, "station.screen.captureOff", named)
        : tr(lang, "station.screen.controlOff", named),
        // Where it is granted: the window on the machine, up now or once the screen is opened.
        tr(lang, access.asking ? "station.screen.asking" : "station.screen.toAsk", named),
      ].join(" ");
  const help = access.reason && ["linuxNoDisplay", "linuxTools", "linuxToolsFailed", "linuxUnavailable", "linuxPortalUnavailable", "linuxX11FallbackUnavailable"].includes(access.reason);
  return { capture: access.capture, control: access.control, message, ...(access.app ? { app: access.app } : {}), ...(access.path ? { path: access.path } : {}), ...(access.asking ? { asking: true } : {}), ...(help ? { help: "linux-desktop" as const } : {}) };
}

/// A view made to only look stays so if its device opens it again this soon without its person asking to drive (its link
/// went as it was told, a resize's next stream): as long as a client goes on trying (core's REOPEN_MS), and a little.
export const WATCH_HELD_MS = 90_000;

export type HubOptions = {
  /// Where a file a person drops into a view is put on this machine (the drive's
  /// `dropFolder`); none: files are not taken.
  drop?: () => string | null;
};

export class ScreenHub implements Screens {
  readonly #sources = makeScreens();
  readonly #o: HubOptions;
  readonly #views = new Map<string, Map<string, Watcher & { at: number }>>();
  #viewCount = 0;
  /// Until when a device's views of a screen are held to only looking (`watchOnly`), by device and screen.
  readonly #held = new Map<string, number>();
  readonly #listeners = new Set<() => void>();
  readonly #refreshers = new Set<() => Promise<void>>();
  readonly #stopping = new Set<() => void>();
  #browser: ScreenBrowser | null = null;

  constructor(options: HubOptions = {}) {
    this.#o = options;
    this.#sources.watch(() => this.#changed());
  }

  setBrowser(browser: ScreenBrowser | null) {
    if (this.#browser === browser) return;
    this.#browser = browser;
    this.#changed();
  }

  add(source: ScreenSource): () => void {
    return this.#sources.add(source);
  }
  list(): ScreenSource[] {
    return this.#sources.list();
  }
  get(id: string): ScreenSource | undefined {
    return this.#sources.get(id);
  }
  watch(listener: (sources: ScreenSource[]) => void): () => void {
    return this.#sources.watch(listener);
  }
  /// A source's title, size or access changed.
  changed() {
    this.#sources.changed();
  }

  /// How a source's state is looked at again before it is told (the desktop's grants: asked of macOS, not followed).
  refresher(refresh: () => Promise<void>): () => void {
    this.#refreshers.add(refresh);
    return () => this.#refreshers.delete(refresh);
  }
  async refresh(): Promise<void> {
    await Promise.all([...this.#refreshers].map((f) => f().catch(() => {})));
  }

  /// What members are told changed: a source came, went or changed, or someone opened or left a view.
  onChange(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }
  #changed() {
    for (const f of [...this.#listeners]) f();
  }

  /// Who is on a source now: everyone viewing, those of them whose input is taken, and each view.
  people(id: string): { viewers: string[]; controlledBy: string[]; views: ViewShown[] } {
    const on = [...(this.#views.get(id)?.entries() ?? [])];
    return {
      viewers: on.map(([, w]) => w.name),
      controlledBy: on.filter(([, w]) => w.control).map(([, w]) => w.name),
      views: on.map(([view, w]) => ({ id: view, name: w.name, control: w.control, at: w.at, ...(w.device ? { device: w.device } : {}), ...(w.self ? { self: w.self } : {}), ...(w.client ? { client: w.client } : {}), ...(w.app ? { app: w.app } : {}), ...(w.agent ? { agent: true } : {}) })),
    };
  }

  /// A view opened on `id`: everyone on it is told who is, and members are; the returned function leaves.
  join(id: string, watcher: Watcher): () => void {
    const on = this.#views.get(id) ?? new Map<string, Watcher & { at: number }>();
    this.#views.set(id, on);
    const view = `v${++this.#viewCount}`;
    on.set(view, Object.assign(watcher, { at: wall.now() }));
    this.#tellPeople(id);
    let left = false;
    return () => {
      if (left) return;
      left = true;
      on.delete(view);
      if (on.size === 0 && this.#views.get(id) === on) this.#views.delete(id);
      this.#tellPeople(id);
    };
  }

  #tellPeople(id: string) {
    const people = this.people(id);
    for (const w of [...(this.#views.get(id)?.values() ?? [])]) w.tell(people);
    this.#changed();
  }

  /// A person's view found to act on: refused for one not there (it ended meanwhile) and an agent's, which comes back at
  /// the agent's next action and is not a member's to end.
  #viewOf(id: string, view: string): Watcher {
    if (this.get(id) === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    const w = this.#views.get(id)?.get(view);
    if (w === undefined) throw new ScreenRefused(404, "station.screen.viewGone");
    if (w.agent || w.end === undefined) throw new ScreenRefused(405, "station.screen.viewNotEnded");
    return w;
  }

  /// POST /admin/api/screens/<id>/views/<view>/end: a member ends a view from wherever they are; it is not opened again.
  endView(id: string, view: string, by: string): void {
    this.#viewOf(id, view).end!(by);
  }

  /// POST /admin/api/screens/<id>/views/<view>/watch: the view goes on, only looking.
  watchOnly(id: string, view: string): void {
    this.#lookOnly(id, this.#viewOf(id, view));
  }

  /// `w` goes on only looking, its device held from driving again by itself for WATCH_HELD_MS; `by`: who took it.
  #lookOnly(id: string, w: Watcher, by?: string): void {
    if (!w.control) return;
    w.control = false;
    if (w.device) {
      const now = wall.now();
      for (const [key, until] of this.#held) if (until <= now) this.#held.delete(key);
      this.#held.set(`${w.device}\n${id}`, now + WATCH_HELD_MS);
    }
    w.watchOnly?.(by);
    this.#tellPeople(id);
  }

  /// Whether a view `device` opens of `id`, asking to drive, may: not just after it was made to only look, unless its
  /// person asked (`taken`, which lets it go).
  mayDrive(id: string, device: string, taken: boolean): boolean {
    const key = `${device}\n${id}`;
    const until = this.#held.get(key);
    if (until === undefined) return true;
    if (taken || until <= wall.now()) {
      this.#held.delete(key);
      return true;
    }
    return false;
  }

  /// Whether a view `device` opens of `id`, asking to drive, drives it: one person's view drives a screen at a time, any
  /// number look (pengxiao, 2026-11-12). Its person asking (`taken`) takes it: every person's view on another device that
  /// drives it goes on only looking, told it was `by` (an agent's waits as before). Opened again by itself (a link that
  /// went, a resize), it drives only while no such view does, and not soon after it was made to only look (`mayDrive`).
  /// `took`: whose views it took it from.
  drive(id: string, device: string, taken: boolean, by: string): { control: boolean; took: string[] } {
    if (!this.mayDrive(id, device, taken)) return { control: false, took: [] };
    const others = [...(this.#views.get(id)?.values() ?? [])].filter((w) => w.control && !w.agent && w.device !== device);
    if (others.length === 0) return { control: true, took: [] };
    if (!taken) return { control: false, took: [] };
    for (const w of others) this.#lookOnly(id, w, by);
    return { control: true, took: [...new Set(others.map((w) => w.name))] };
  }

  /// An agent `by` asked by a person to take the screen (the `screen` tool's take_control): every person's view that
  /// drives it goes on only looking; how many did.
  takeControl(id: string, by?: string): number {
    if (this.get(id) === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    const driving = [...(this.#views.get(id)?.values() ?? [])].filter((w) => w.control && !w.agent && w.watchOnly !== undefined);
    for (const w of driving) this.#lookOnly(id, w, by);
    return driving.length;
  }

  /// POST /admin/api/screens/<id>/views/end: every person's view ends (an agent's stays); how many did.
  endViews(id: string, by: string): number {
    if (this.get(id) === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    const ending = [...(this.#views.get(id)?.values() ?? [])].filter((w) => !w.agent && w.end !== undefined);
    for (const w of ending) w.end!(by);
    return ending.length;
  }

  /// A view opened by the station itself (the agents' computer-use tool), shown as `who` while it is open: in
  /// `viewers`, and with `control` in `controlledBy` (a name such as "agent: <chat title>"). Closing it leaves.
  async openAs(id: string, options: ViewOptions, who: { name: string; control: boolean }): Promise<ScreenView> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    if (source.userTab) throw new ScreenRefused(403, "station.screen.userOnly");
    const view = await source.open(options);
    const leave = this.join(id, { name: who.name, control: who.control, agent: true, tell: () => {} });
    return {
      next: () => view.next(),
      keyframe: () => view.keyframe(),
      input: (event) => view.input(event),
      close: () => {
        leave();
        view.close();
      },
    };
  }

  /// What ends a view as the station stops.
  whenStopping(stop: () => void): () => void {
    this.#stopping.add(stop);
    return () => this.#stopping.delete(stop);
  }

  /// The station stopping: every view ends, said so (`ended: "stopping"`).
  close() {
    for (const stop of [...this.#stopping]) stop();
  }

  /// POST /admin/api/screens/<id>/close: a screen closed from a person's app (a tab of the browser).
  async closeScreen(id: string): Promise<void> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    if (source.discard === undefined) throw new ScreenRefused(405, "station.screen.notClosed");
    await source.discard();
  }

  /// POST /admin/api/screens/browser: opens a persistent user tab in the station's browser (`{ url } -> screen id`).
  async openBrowser(url: string): Promise<string> {
    if (this.#browser === null || !this.#browser.available()) throw new ScreenRefused(503, "station.screen.noBrowser");
    return this.#browser.openUserTab(url);
  }

  /// POST /admin/api/screens/<id>/open-url: navigates a browser tab or opens a link on a simulator.
  async openUrl(id: string, url: string): Promise<void> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    if (source.openUrl !== undefined) {
      await source.openUrl(url);
      return;
    }
    if (source.debug !== undefined) {
      if (!(await source.debug.openUrl(url))) throw new ScreenRefused(400, "station.screen.badUrl");
      return;
    }
    throw new ScreenRefused(405, "station.screen.noDebug");
  }

  /// POST /admin/api/screens/<id>/reload: reloads a browser tab.
  async reloadScreen(id: string): Promise<void> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    if (source.reload === undefined) throw new ScreenRefused(405, "station.screen.notBrowser");
    await source.reload();
  }

  /// POST /admin/api/screens/<id>/sleep: hibernates a user tab, closing its live Chrome page while keeping its saved entry.
  async sleepScreen(id: string): Promise<void> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    if (source.sleep === undefined) throw new ScreenRefused(405, "station.screen.notBrowser");
    await source.sleep();
  }

  /// A screen's apps' logs and their restart (a simulator's); refused for any other.
  debugOf(id: string): SimDebug {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    if (source.debug === undefined) throw new ScreenRefused(405, "station.screen.noDebug");
    return source.debug;
  }

  /// A simulator's case, one panel's turned as it asks (`GET …/chrome/<panel>/<turn>`); refused for what has none.
  chromeOf(id: string, panel: number, turn: number): Promise<ChromePictures> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    const chrome = source.chrome?.[panel];
    if (chrome === undefined || !Number.isInteger(turn) || turn < 0 || turn > 3) throw new ScreenRefused(404, "station.screen.notFound");
    return picturesOf(chrome, turn);
  }

  /// GET /admin/api/screens, in `lang`: `{screens: [{id, kind, title, width, height, viewers, controlledBy, views, access?,
  /// clipboard?, peek?, drop?, closable?, debug?, poses?, panels?, chrome?, openedBy?}]}`: `clipboard`, the types a view that drives it carries both ways;
  /// `peek`, it can be previewed (ViewOptions.peek); `drop`, where a file
  /// dropped into a view is put (`folder`) and whether the view can show it in the machine's file manager (`reveal`);
  /// `closable`, a person may close it (POST …/close); `debug`, its apps' logs and restart are had, `install` where a file to
  /// install on it goes up to; `openedBy`, the session that opened it (an agent's tab); `since`, since when it has been up
/// (ms: a simulator's boot, an emulator's start).
  listed(lang: Lang): { browser?: boolean; screens: Record<string, unknown>[] } {
    const folder = this.#o.drop?.() ?? null;
    const browser = this.#browser?.available() === true;
    return {
      ...(browser ? { browser: true } : {}),
      screens: this.list().map((s) => {
        const { width, height } = s.size();
        const access = accessShown(s.access?.(), lang);
        const clipboard = s.clipboard?.() ?? [];
        const by = s.openedBy?.();
        const since = s.since?.();
        const site = s.site?.();
        const sleeping = s.sleeping?.() === true;
        return {
          id: s.id, kind: s.kind, title: s.title(), width, height, ...this.people(s.id), ...(access ? { access } : {}),
          ...(clipboard.length > 0 ? { clipboard } : {}),
          ...(s.peek ? { peek: true } : {}),
          ...(s.discard ? { closable: true } : {}),
          ...(s.userTab ? { userTab: true } : {}),
          ...(sleeping ? { sleeping: true } : {}),
          ...(site ? { site } : {}),
          ...(s.openUrl ? { openUrl: true } : {}),
          ...(s.debug ? { debug: true, install: s.debug.installFolder() } : {}),
          ...(s.poses ? { poses: true } : {}),
          ...(s.panels?.length ? { panels: s.panels } : {}),
          ...(s.chrome?.length ? { chrome: s.chrome.map(toldOf) } : {}),
          ...(by ? { openedBy: by } : {}),
          ...(since !== undefined ? { since } : {}),
          ...(folder !== null ? { drop: { folder, reveal: s.reveal === true } } : {}),
        };
      }),
    };
  }
}
