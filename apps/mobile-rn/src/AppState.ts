// What the pages share of the app (the Android app's AppState.kt, ported as it is): where it is (its stack of pages,
// Screen), what is over it (a sheet, a menu, a toast, an entry read in full), and the ways to the core and the stations
// (AppState). A store the pages read with `useApp(select)` and change through `app`; the app draws it (src/App.tsx).
// How its person likes it on this device is the core's prefs, through web/src/prefs.ts (the web's own logic, one copy).
import { createContext, useSyncExternalStore } from "react";
import type { ReactNode } from "react";
import { CoreError, type CoreClient } from "../../../web/src/core/client.ts";
import { core, prime as primeTopic } from "../../../web/src/core/react.ts";
import type { AppRelease, Appearance, BarPrefs, DoingItem, DoingView, LinkTarget, NotifyView, ReaderPrefs } from "../../../web/src/core/shapes.ts";
import { doingMatches } from "../../../web/src/doing.ts";
import { onPrefs, prefs, setPrefs, type Prefs, type PrefsPatch } from "../../../web/src/prefs.ts";
import { CLOUD_ORIGIN } from "./build";
import { errorText, StationApi } from "./data/Calls";
import { devicePrefs, type DeviceStore } from "./data/Prefs";
import { ChatOf, Topics } from "./data/Topics";
import { t } from "./i18n";
import { barsOf, DEFAULT_BARS } from "./Places";
import type { BarAction } from "./ui/Bar";
import type { IconPaths } from "./ui/IconSet";

export { ChatOf };
export type { BarAction };
/** A ChatOf as words, for a page's id. */
export const chatOfKey = (of: ChatOf) => ("thread" in of ? String(of.thread) : of.session);

/** The pages (AppState.kt Screen), each with its id (`screenId`). */
export type Screen =
  | { kind: "Home" }
  /** An item's page: its chat, or its agent before it has one. `at`: a message (seq) to show once it opens, flashing
   *  (a row's state line: what it is about); `words`: what to find in it. */
  | { kind: "Chat"; station: string; of: ChatOf; at?: number | null; words?: string[] | null }
  /** Rises from the bottom rather than coming in from the side. */
  | { kind: "NewChat" }
  | { kind: "Stations" }
  | { kind: "Station"; address: string }
  /** This phone's adb lent to a station's agents (screens/AdbShare.tsx). */
  | { kind: "AdbShare"; address: string }
  /** An agent’s execution history, opened as a page over its chat. */
  | { kind: "History"; station: string; of: ChatOf; key: string; entry?: number | null }
  /** How an agent runs, changed: its model, how hard it thinks, who runs it. */
  | { kind: "RunSettings"; station: string; of: ChatOf; key: string }
  /** A profile's models, to pick which may be used. */
  | { kind: "Profile"; address: string; profile: string }
  /** Settings, one page from the gear on Home (screens/SettingsHome.tsx); it comes from the left. */
  | { kind: "Settings" }
  /** The account: who is signed in, where, and the other accounts on this device. */
  | { kind: "Me" }
  /** How this device shows still.fail: its theme, whose pictures lead a chat's row. */
  | { kind: "Appearance" }
  /** Files opened in the app and kept on this device, to delete (screens/KeptFiles.tsx). */
  | { kind: "KeptFiles" }
  /** What is kept of a chat (null: files of no chat known), from KeptFiles. */
  | { kind: "KeptChat"; station: string | null; thread: number | null }
  /** What changed in still.fail (screens/Changelog.tsx). */
  | { kind: "Changelog" }
  /** Every station's connects, or (from a station's page) that station's only. */
  | { kind: "Connects"; station?: string | null }
  /** Every station's profiles, or (from a station's page) that station's only. */
  | { kind: "Profiles"; station?: string | null }
  /** An account on several stations: what they have in common, and each station's part. */
  | { kind: "ProfileAccount"; key: string }
  | { kind: "AutomaticDecisions" }
  | { kind: "AutomaticDecisionCompletion" }
  /** A station's archive policy, from its row under the completion rule. */
  | { kind: "AutomaticDecisionPolicy"; station: string }
  | { kind: "Memories" }
  /** What the agents spent (screens/Usage.tsx). */
  | { kind: "Usage" }
  | { kind: "UsagePrices"; days: number }
  /** A web service an agent started, full screen: by its job (people know it by its name, never its port). */
  | { kind: "Preview"; station: string; job: string }
  /** A visualization an agent posted, as a page of its own in the preview (web mobile's 在侧边打开 on a phone). */
  | { kind: "PreviewFile"; station: string; session: string; path: string; name: string }
  /** The workspace itself: its name, its people, leaving it. */
  | { kind: "Workspace" }
  /** The workspace's security mode (its lock), and turning it on. */
  | { kind: "Security" }
  | { kind: "SecurityOpen" }
  /** The workspace's vault: its items, the agents' requests waiting, turning it on (screens/Vault.tsx). */
  | { kind: "Vault" }
  /** A secret of the library: what it is, its content shown, how agents may use it and when they did (screens/Vault.tsx). */
  | { kind: "VaultItem"; vault: string; item: string }
  /** A connect of a station; how it runs; a new one on a station. */
  | { kind: "Connect"; station: string; connect: string }
  | { kind: "ConnectRun"; station: string; connect: string }
  | { kind: "NewConnect"; station: string }
  | { kind: "NewProfile"; station: string }
  /** Chats archived, of every station online: put back in the list, or deleted for good. */
  | { kind: "Archive" }
  /** The decisions waiting for the viewer in the workspace's chats, one at a time (奏 N on the home page). */
  | { kind: "Decisions" }
  /** Every station's lent folders in one list (the bottom bar's 文件, drive/Files.tsx). */
  | { kind: "Files" }
  /** This device's bottom bars, to change (screens/BarSettings.tsx). */
  | { kind: "BarSettings" }
  /** The agents' memory on a station. */
  | { kind: "Memory"; station: string }
  /** A page of a station's memory: a skill (`skill`, with its files), or the global memory's parts from `at` (0 by default). */
  | { kind: "MemoryDoc"; station: string; skill: string | null; at?: number }
  /**
   * A station's drive (drive/DriveScreen.tsx), a page per folder: `root` null is the drive itself (its one root's
   * contents, or its roots), else the folder `path` under `root`.
   */
  | { kind: "Drive"; station: string; root: string | null; path: string }
  /** A text or Markdown file of a drive, read (drive/Reader.tsx). */
  | { kind: "DriveRead"; station: string; root: string; path: string }
  /** A video or a song of a drive, played as it streams (drive/Player.tsx). */
  | { kind: "DrivePlay"; station: string; root: string; path: string }
  /** A connect's Slack app: its name, icon, colour and permissions. */
  | { kind: "SlackApp"; station: string; connect: string };

export type ScreenKind = Screen["kind"];
/** One kind of page (`Screen.Chat` in Kotlin is `ScreenOf<"Chat">`). */
export type ScreenOf<K extends ScreenKind> = Extract<Screen, { kind: K }>;

/** A page's id, as AppState.kt's: two pages are the same page when their ids are. */
export function screenId(s: Screen): string {
  switch (s.kind) {
    case "Home": return "home";
    case "Chat": return `chat/${s.station}/${chatOfKey(s.of)}`;
    case "NewChat": return "new";
    case "Stations": return "stations";
    case "Station": return `station/${s.address}`;
    case "AdbShare": return `adb/${s.address}`;
    case "History": return `history/chat/${s.station}/${chatOfKey(s.of)}/${s.key}/${s.entry ?? null}`;
    case "RunSettings": return `run/${s.station}/${s.key}`;
    case "Profile": return `profile/${s.address}/${s.profile}`;
    case "Settings": return "settings";
    case "Me": return "me";
    case "Appearance": return "appearance";
    case "KeptFiles": return "kept-files";
    case "KeptChat": return `kept-files/${s.station ?? ""}/${s.thread ?? ""}`;
    case "Changelog": return "changelog";
    case "Connects": return "connects" + (s.station ? `/${s.station}` : "");
    case "Profiles": return "profiles" + (s.station ? `/${s.station}` : "");
    case "ProfileAccount": return `profile-account/${s.key}`;
    case "AutomaticDecisions": return "automatic-decisions";
    case "AutomaticDecisionCompletion": return "automatic-decisions/completion";
    case "AutomaticDecisionPolicy": return `automatic-decisions/completion/${s.station}`;
    case "Memories": return "memories";
    case "Usage": return "usage";
    case "UsagePrices": return `usage-prices-${s.days}`;
    case "Preview": return `preview/${s.station}/${s.job}`;
    case "PreviewFile": return `preview-file/${s.station}/${s.session}/${s.path}`;
    case "Workspace": return "workspace";
    case "Security": return "security";
    case "SecurityOpen": return "security/open";
    case "Vault": return "vault";
    case "VaultItem": return `vault/${s.vault}/${s.item}`;
    case "Connect": return `connect/${s.station}/${s.connect}`;
    case "ConnectRun": return `connect-run/${s.station}/${s.connect}`;
    case "NewConnect": return `new-connect/${s.station}`;
    case "NewProfile": return `new-profile/${s.station}`;
    case "Archive": return "archive";
    case "Decisions": return "decisions";
    case "Files": return "files";
    case "BarSettings": return "bar-settings";
    case "Memory": return `memory/${s.station}`;
    case "MemoryDoc": return `memory/${s.station}/${s.skill ? `skill/${s.skill}` : "global"}`;
    case "Drive": return `drive/${s.station}/${s.root ?? ""}/${s.path}`;
    case "DriveRead": return `drive-read/${s.station}/${s.root}/${s.path}`;
    case "DrivePlay": return `drive-play/${s.station}/${s.root}/${s.path}`;
    case "SlackApp": return `slack-app/${s.station}/${s.connect}`;
  }
}

/** A value as words that are the same for equal values, whatever order its fields were written in and with what is
 *  unsaid (null, undefined) left out, as the Kotlin's defaults are. */
function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (v !== null && typeof v === "object") {
    return `{${Object.entries(v as Record<string, unknown>).filter(([, x]) => x !== null && x !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, x]) => `${JSON.stringify(k)}:${canonical(x)}`).join(",")}}`;
  }
  return JSON.stringify(v);
}

/** Two pages are equal as Kotlin's data classes are: every field (the same id is not enough: a chat opened `at` a message is another). */
export function sameScreen(a: Screen | null | undefined, b: Screen | null | undefined): boolean {
  if (a == null || b == null) return a == b;
  return a === b || canonical(a) === canonical(b);
}

/** A box in the window (Compose's Rect): its edges, in dp from the window's top left. */
export interface Rect { left: number; top: number; right: number; bottom: number }

/**
 * A sheet from the bottom (ui/Sheet.kt SheetSpec): `height` the share of the screen it takes, `draggable` by its top,
 * `fit` the height of its content when it is that (dp, null: `height`), what runs when it closes, `solid` (not
 * frosted), and what it shows.
 */
// The specs of what is over the pages (ui/Sheet.kt's classes), each a type and a constructor of the same name: built
// with `new SheetSpec(height, …)` in Kotlin's order, or written as an object with Kotlin's named arguments
// (`{ height: 0.6, draggable: true, content }`), the fields Kotlin defaults left out. What reads them takes the
// defaults for what is not there (`spec.draggable ?? false`).
export interface SheetSpec {
  readonly height: number;
  readonly draggable?: boolean;
  readonly fit?: number | null;
  readonly onClose?: (() => void) | null;
  readonly solid?: boolean;
  readonly content: () => ReactNode;
}
export const SheetSpec = class implements SheetSpec {
  constructor(
    readonly height: number,
    readonly draggable: boolean = false,
    readonly fit: number | null = null,
    readonly onClose: (() => void) | null = null,
    readonly solid: boolean = false,
    readonly content: () => ReactNode = () => null,
  ) {}
};

/** One row of a menu (ui/Sheet.kt MenuItem): its words, its icon (null: none), what it does. */
export interface MenuItem { readonly label: string; readonly icon: IconPaths | null; readonly action: () => void }
export const MenuItem = class implements MenuItem {
  constructor(readonly label: string, readonly icon: IconPaths | null, readonly action: () => void) {}
};

/** A menu by what opened it (ui/Sheet.kt MenuSpec): `anchor` the opener's box in the window, its items, what runs when it is dismissed. */
export interface MenuSpec { readonly anchor: Rect; readonly items: MenuItem[]; readonly onDismiss?: () => void }
export const MenuSpec = class implements MenuSpec {
  constructor(readonly anchor: Rect, readonly items: MenuItem[], readonly onDismiss: () => void = () => undefined) {}
};

/** One entry of an execution history in full, over everything (ui/Sheet.kt ReaderSpec): its label's row, its content. */
export interface ReaderSpec { readonly label: () => ReactNode; readonly content: () => ReactNode }
export const ReaderSpec = class implements ReaderSpec {
  constructor(readonly label: () => ReactNode, readonly content: () => ReactNode) {}
};

/** Where each chat was left: the message at the top of the list and how far below the top it sat; and, if it was left
 *  at its end, the newest message then (`bottom`). */
export interface Place { id: string; offset: number; bottom: string | null }

/** What the app's updates are to the pages (Updates, in the app): a newer build found, getting it, installing it. */
export interface AppUpdates {
  /** A build newer than this one, once a check found it. */
  readonly available: AppRelease | null;
  /** What an update under way is doing ("下载中 40%"), null when none is. */
  readonly progress: string | null;
  /** Whether a check asked for (checkNow) is under way. */
  readonly checking: boolean;
  /** Asks the core for a newer build (at most once an hour unless `now`); the one it finds, if any. */
  check(now?: boolean): Promise<AppRelease | null>;
  /** Checks now, for a person who asked; what to tell them, if anything. */
  checkNow(): Promise<string | null>;
  /** Gets the newer build and has the system install it; what went wrong, if anything. */
  install(): Promise<string | null>;
}

/** No updates until the app says where they come from (`app.updates = new Updates(…)`, src/Updates.ts). */
const NO_UPDATES: AppUpdates = {
  available: null, progress: null, checking: false,
  check: async () => null, checkNow: async () => null, install: async () => null,
};

interface State {
  stack: Screen[];
  /** Whether the last move went deeper, for the direction of the transition. */
  forward: boolean;
  sheet: SheetSpec | null;
  menu: MenuSpec | null;
  toast: string | null;
  /** One entry of an execution history in full, over everything (the sheet stays under it). */
  reader: ReaderSpec | null;
  /** How its person likes it on this device, as the core keeps it (web/src/prefs.ts); null until the app follows them. */
  kept: Prefs | null;
  /** What people set going here and the core has not finished (the `doing` topic, client/core-ts/src/doing.ts). */
  doing: DoingItem[];
  /** 我 → 通知: local notices and pushes, on by default (Notices, Push), as the core keeps it (its `notify`). */
  notify: boolean;
  /** Whether the system was asked to allow notifications; null until the core says. */
  notifyAsked: boolean | null;
  /** The app is started (on screen, maybe under another app's window): the app says so (MainActivity's onStart/onStop). */
  inFront: boolean;
  /** Something over a place's top page (Home's search) has the bottom bar out of the way. */
  barAway: boolean;
  /** Each place's primary action as its top page last said it, for the bar's notch (Places.tsx PlaceAction): by "<workspace>|<place>", null for none. */
  placeActions: Record<string, BarAction | null>;
  /**
   * The chat a new chat became (`made`): it is the same page as the new chat was (screens/ChatHost.tsx), not another
   * pushed in over it; the page is the host's until the next new chat.
   */
  madeChat: ScreenOf<"Chat"> | null;
}

type Listener = () => void;

/** The words of a failure, whatever failed. */
function why(e: unknown): string {
  return e instanceof CoreError ? errorText(e) : e instanceof Error ? e.message : String(e);
}

export class AppState {
  #state: State = {
    stack: [{ kind: "Home" }], forward: true, sheet: null, menu: null, toast: null, reader: null,
    kept: null, doing: [], notify: true, notifyAsked: null, inFront: false, barAway: false, placeActions: {}, madeChat: null,
  };
  readonly #listeners = new Set<Listener>();
  /** The stack as a place from the bar last made it: while it is that very list, the page shown was switched to, not pushed. */
  #placed: Screen[] | null = null;
  #started = false;

  /** Where still.fail cloud is (build.ts). */
  readonly cloudOrigin: string = CLOUD_ORIGIN;
  /** What the app's updates are (the app sets them as it starts). */
  updates: AppUpdates = NO_UPDATES;
  /** The app's own preferences on this device (SharedPreferences "stillfail"). */
  readonly #prefs: DeviceStore = devicePrefs;

  /** The core, for what a part fetches itself (a picture by its URL). */
  get core(): CoreClient { return core(); }

  get state(): State { return this.#state; }
  subscribe = (l: Listener) => {
    this.#listeners.add(l);
    this.start();
    return () => { this.#listeners.delete(l); };
  };
  #set(next: Partial<State>) {
    this.#state = { ...this.#state, ...next };
    for (const l of this.#listeners) l();
  }

  /**
   * Follows the core for the app's life (MainActivity in the Android app starts these): the prefs, what is under way,
   * the notifications' settings; and moves into the core once what the app kept itself before it did. Once: the first
   * page that reads the app starts it if the app has not.
   */
  start() {
    if (this.#started) return;
    this.#started = true;
    this.followPrefs();
    this.followDoing();
    this.followNotify();
    this.#migrate();
  }

  // ── UiHost (ui/Host.kt): what the parts ask of the app ──

  /** Opens a link as the app does (still.fail's own in the app, the rest by the system); `orElse` when it cannot. */
  follow(url: string, orElse: () => void) { this.openLink(url, false, null, orElse); }
  /** Says something at the bottom of the screen for a moment. */
  note(text: string) { this.toast = text; }

  get stack(): Screen[] { return this.#state.stack; }
  get top(): Screen { return this.#state.stack[this.#state.stack.length - 1]!; }
  get forward(): boolean { return this.#state.forward; }

  get sheet(): SheetSpec | null { return this.#state.sheet; }
  set sheet(s: SheetSpec | null) { this.#set({ sheet: s }); }
  /** The long-press menu open over everything (ui/Sheet.tsx MenuHost), or none. */
  get menu(): MenuSpec | null { return this.#state.menu; }
  set menu(m: MenuSpec | null) { this.#set({ menu: m }); }
  get toast(): string | null { return this.#state.toast; }
  set toast(text: string | null) { this.#set({ toast: text }); }
  get reader(): ReaderSpec | null { return this.#state.reader; }
  set reader(r: ReaderSpec | null) { this.#set({ reader: r }); }

  // ── how its person likes it on this device (web/src/prefs.ts) ──

  /**
   * How its person likes it on this device, as the core keeps it (data/Prefs.kt). Changed through `setPrefs`
   * (web/src/prefs.ts): shown at once, then as the core has them.
   */
  get kept(): Prefs { return prefs(); }

  /** Follows the core's prefs for the app's life: the pages that read them are drawn again when they change. Returns how to stop. */
  followPrefs(): () => void {
    const heard = () => {
      const value = prefs();
      if (value === this.#state.kept) return;
      this.#set({ kept: value });
      KeptLang.keep(this.#prefs, value.lang ?? null);
    };
    const off = onPrefs(heard);
    heard();
    return off;
  }

  /** Follows what is under way for the app's life. Returns how to stop. */
  followDoing(): () => void {
    return core().subscribe(Topics.doing, (value) => {
      const view = value as DoingView | null;
      if (!view || !Array.isArray(view.doing)) return;
      this.#set({ doing: view.doing });
    }, () => undefined);
  }

  /** What people set going here and the core has not finished. */
  get doing(): DoingItem[] { return this.#state.doing; }

  /**
   * Whether one of `calls` is under way about what `on` names (its params, as words; null or undefined is any), wherever
   * it was asked: the row or button it is about shows it at once (a spinner, not pressed again), the menu that asked gone.
   */
  isDoing(calls: string | readonly string[], on: Record<string, unknown> = {}): boolean {
    const words = given(on);
    return this.#state.doing.some((item) => item.stage !== "failed" && doingMatches(item, calls, words));
  }

  /** Why one of `calls` about what `on` names failed a moment ago (the core shows it a few seconds); null when none did. */
  failedOf(calls: string | readonly string[], on: Record<string, unknown> = {}): string | null {
    const words = given(on);
    const item = this.#state.doing.findLast((i) => i.stage === "failed" && doingMatches(i, calls, words));
    return item ? (item.error ?? t("android-misc.failed")) : null;
  }

  /**
   * Lets what a person did go on by itself (past the page or menu that asked it), and says how it ended:
   * `没能<what>：<why>` when it failed (and `failed`, if any, is run), `done` (if any) when it went through.
   */
  act(what: string, run: () => Promise<unknown>, done?: string | null, failed?: (() => void) | null) {
    run().then(
      () => { if (done) this.toast = done; },
      (e: unknown) => {
        this.toast = t(e instanceof CoreError && e.code === "unconfirmed" ? "android-misc.act.unconfirmed" : "android-misc.act.failed", { what, error: why(e) });
        failed?.();
      },
    );
  }

  /** The workspace chosen last; the first one when it is gone. */
  get workspace(): string | null { return prefs().workspace ?? null; }
  pickWorkspace(id: string) { if (id !== prefs().workspace) setPrefs({ workspace: id }); }

  #bars: { from: unknown; bars: BarPrefs } | null = null;
  /**
   * The bottom bars (Places.tsx, ui/Bar.tsx) of the workspace in view, whole: its own (`barsBy`), else the ones all had
   * before each had its own, else the default ones before the core says. The same object while they are the same.
   */
  get bars(): BarPrefs {
    const kept = prefs();
    const own = (kept.workspace ? kept.barsBy?.[kept.workspace] : undefined) ?? kept.bars;
    if (this.#bars && this.#bars.from === own) return this.#bars.bars;
    const bars = own ? barsOf(own.sets, own.current) : DEFAULT_BARS;
    this.#bars = { from: own, bars };
    return bars;
  }
  /** The bars changed (`sets`, `current` the one in view): shown at once, kept whole, the workspace in view's (`prefs.set {barsBy}`). */
  setBars(sets: string[][], current: number) {
    const whole = barsOf(sets, current);
    const ws = prefs().workspace;
    if (ws == null) setPrefs({ bars: whole });
    else setPrefs({ barsBy: { [ws]: whole } });
  }

  /** 外观: "system" (the default), "light" or "dark". */
  get theme(): string { return prefs().appearance ?? "system"; }
  useTheme(value: string) { setPrefs({ appearance: value as Appearance }); }

  /** How the drive's reader lays text out on this device (the core's `prefs.reader`, whole; its defaults before it says). */
  get readerPrefs(): ReaderPrefs { return prefs().reader ?? READER_DEFAULTS; }
  /** One setting of the reader changed (`prefs.set {reader: {field: value}}`): shown at once (`shown`, as setPrefs merges
   *  it in), kept in its bounds by the core. */
  setReader(_shown: ReaderPrefs, field: keyof ReaderPrefs, value: string | number | boolean) {
    setPrefs({ reader: { [field]: value } } as unknown as PrefsPatch);
  }

  /** How a station's files are listed on this device, as the web's (prefs `driveViews`): their order (`sort`: name, time,
   *  size or kind, `-down` the other way) and whether hidden ones show (`hidden`: shown). */
  get driveSort(): string { return prefs().driveViews?.sort ?? "name"; }
  get driveHidden(): boolean { return prefs().driveViews?.hidden === "shown"; }
  /** One of them changed (null: back to how it is when never said). */
  setDriveView(key: string, value: string | null) { setPrefs({ driveViews: { [key]: value } }); }

  /** Whether files of a station's put into the chat `key` ("<station>:<chat>") go as files, not named by their path: the
   *  chat's own say (`prefs.dropFiles`), else the settings' (`dropAs`). */
  dropsAsFiles(key: string): boolean {
    const kept = prefs();
    return kept.dropFiles?.[key] ?? (kept.dropAs === "file");
  }
  /** The chat `key` takes such files as files, or not (the same as the settings say: its own say dropped). */
  setDropsAsFiles(key: string, on: boolean) {
    const own = on === (prefs().dropAs === "file") ? null : on;
    setPrefs({ dropFiles: { [key]: own } });
  }

  /** 语言: "zh" or "en" as chosen; null follows the phone. The words change as the core says (its `lang`, src/i18n.ts). */
  get language(): string | null { return prefs().language ?? null; }
  setLanguage(value: string | null) {
    // The Kotlin shows `lang` (value, else the phone's) at once; here `lang` is the core's, a moment later (it is on the
    // device): web/src/prefs.ts keeps what the core works out as the core says it.
    setPrefs({ language: value });
  }

  /**
   * What `workspace`'s chat list shows: "all", "mine" (我参与的) or "watching" (监控中). Each workspace keeps its own;
   * one never chosen in goes by the one filter kept for all before (奏 in the wide screen's sidebar: all here).
   */
  chatFilter(workspace: string): "all" | "mine" | "watching" {
    const p = prefs();
    const mode = p.listFilter?.[workspace] ?? (p.onlyDecisions ? "decisions" : p.onlyWatching ? "watching" : p.onlyMine ? "mine" : "all");
    return mode === "mine" || mode === "watching" ? mode : "all";
  }
  showChats(workspace: string, filter: string) { setPrefs({ listFilter: { [workspace]: filter } } as PrefsPatch); }

  /** A Slack app made for a new connect on `station`, to go on with (screens/Connects.tsx); null lets it go. */
  resume(station: string): string | null { return prefs().resume?.[station] ?? null; }
  setResume(station: string, app: string | null) {
    if (this.resume(station) === app) return;
    setPrefs({ resume: { [station]: app } });
  }

  // ── notifications ──

  get notify(): boolean { return this.#state.notify; }
  get notifyAsked(): boolean | null { return this.#state.notifyAsked; }
  get inFront(): boolean { return this.#state.inFront; }
  set inFront(on: boolean) { if (on !== this.#state.inFront) this.#set({ inFront: on }); }

  /**
   * Turns notifications on or off (the core takes this device's pushes off the accounts when off); answers whether the
   * core wants this device to hold pushes now.
   */
  async useNotify(on: boolean): Promise<boolean> {
    const was = this.#state.notify;
    this.#set({ notify: on });
    try {
      const view = await core().call("notify.set", { on }) as NotifyView;
      this.#set({ notify: view.on });
      return view.push;
    } catch (e) {
      // Refused (or not understood): as it was, and said.
      this.#set({ notify: was });
      this.toast = t(on ? "android-misc.notify.onFailed" : "android-misc.notify.offFailed", { error: why(e) });
      return was;
    }
  }

  /** The system was asked to allow notifications (once). */
  async askedNotify(): Promise<void> {
    this.#set({ notifyAsked: true });
    try { await core().call("notify.set", { asked: true }); } catch { /* the core's own retry */ }
  }

  /** The settings as the app kept them before the core did, into the core once. */
  async moveNotify(): Promise<void> {
    if (!this.#prefs.contains(NOTIFY_FLAG) && !this.#prefs.contains("notifyAsked")) return;
    try {
      await core().call("notify.set", { on: this.#prefs.getBoolean(NOTIFY_FLAG, true), asked: this.#prefs.getBoolean("notifyAsked", false) });
      this.#prefs.remove(NOTIFY_FLAG);
      this.#prefs.remove("notifyAsked");
    } catch {
      // Tried again on the next start; the old values stay where they are.
    }
  }

  /** Follows the core's `notify` (the settings shown in 我). Returns how to stop. */
  followNotify(): () => void {
    return core().subscribe(Topics.notify(), (value) => {
      const view = value as NotifyView | null;
      if (!view || typeof view !== "object") return;
      this.#set({ notify: view.on, notifyAsked: view.asked });
    }, () => undefined);
  }

  /** Looks for a newer build of the app: one found shows 更新 in the home page's top bar (and in 我). */
  async checkUpdates(): Promise<void> { await this.updates.check(); }

  flag(name: string, fallback: boolean): boolean { return this.#prefs.getBoolean(name, fallback); }
  setFlag(name: string, on: boolean) { this.#prefs.putBoolean(name, on); }
  strings(name: string): string[] { return this.#prefs.getString(name, null)?.split("\u0000").filter((s) => s.length > 0) ?? []; }
  setStrings(name: string, values: string[]) { this.#prefs.putString(name, values.join("\u0000")); }

  /**
   * Starts the core reading a chat ahead of its page (its row pressed), kept a moment for it: the page then has it as
   * it comes in, instead of a frame of its loading look first (web core/react.ts prime, which keeps a chat a while longer
   * than PRIME_MS: as the web's).
   */
  prime(station: string, of: ChatOf) {
    primeTopic(Topics.chat(station, of));
  }

  // ── the stack ──

  /**
   * A place from the bottom bar: its page takes the bottom of the stack, in place (no slide, nothing to go back to);
   * the same place again changes nothing.
   */
  place(screen: Screen) {
    const stack = this.#state.stack;
    if (stack.length === 1 && sameScreen(stack[0], screen)) return;
    const to = [screen];
    AppHooks.placed(stack[0] ?? null, screen);
    this.#placed = to;
    this.#set({ sheet: null, menu: null, forward: false, stack: to });
  }
  /** While the stack is the very list a place from the bar made, the page shown was switched to, not pushed. */
  get switched(): boolean { return this.#state.stack === this.#placed; }
  get barAway(): boolean { return this.#state.barAway; }
  set barAway(away: boolean) { if (away !== this.#state.barAway) this.#set({ barAway: away }); }
  get placeActions(): Record<string, BarAction | null> { return this.#state.placeActions; }
  /** A place's action said (by "<workspace>|<place>"), null for none. */
  setPlaceAction(key: string, action: BarAction | null) { this.#set({ placeActions: { ...this.#state.placeActions, [key]: action } }); }

  /** The chat a new chat became, as the page it is drawn in (ChatHost) knows it. */
  get madeChat(): ScreenOf<"Chat"> | null { return this.#state.madeChat; }
  /** Whether `screen` is the new chat's page or the chat it became (a push of either starts the host anew). */
  #ofNewChat(screen: Screen): boolean {
    return screen.kind === "NewChat" || sameScreen(screen, this.#state.madeChat);
  }

  push(screen: Screen) {
    this.#set({ sheet: null, menu: null, forward: true, madeChat: this.#ofNewChat(screen) ? null : this.#state.madeChat, stack: [...this.#state.stack, screen] });
  }
  pop() {
    if (this.#state.stack.length > 1) this.#set({ sheet: null, menu: null, forward: false, stack: this.#state.stack.slice(0, -1) });
  }
  /** The top page gives way to another (a new chat becomes the chat it made). */
  /** From the latest chats on a wide screen (screens/Wide.tsx): in place of the page open, or over the list. */
  open(screen: Screen) {
    const stack = this.#state.stack;
    // A chat a new chat made, opened again from the list, is a page of its own (it slides, not rises).
    const madeChat = this.#ofNewChat(screen) ? null : this.#state.madeChat;
    this.#set({ sheet: null, menu: null, forward: true, madeChat, stack: [...(stack.length > 1 ? stack.slice(0, -1) : stack), screen] });
  }
  replace(screen: Screen) { this.#set({ sheet: null, forward: true, stack: [...this.#state.stack.slice(0, -1), screen] }); }
  /** The chat a new chat became: it stays the page it was (no slide), as the chat. */
  made(screen: ScreenOf<"Chat">) { this.#set({ madeChat: screen }); this.replace(screen); }
  /** The page a screen is drawn in: a new chat and the chat it became are one. */
  pageOf(screen: Screen): string { return this.#ofNewChat(screen) ? "new-chat" : screenId(screen); }
  home() { this.#set({ sheet: null, forward: false, stack: [{ kind: "Home" }] }); }

  /**
   * An item's link from outside: its workspace, and its page over the list (back goes to the list); a service's link
   * (`?service=<job>`) has the service over its chat. `at`: the message it opens at (a notification's).
   */
  openItem(workspace: string, station: string, session: string, service: string | null = null, at: number | null = null) {
    this.pickWorkspace(workspace);
    const address = `${workspace}/${station}`;
    const stack: Screen[] = [{ kind: "Home" }, { kind: "Chat", station: address, of: { session }, at }];
    if (service != null) stack.push({ kind: "Preview", station: address, job: service });
    this.#set({ sheet: null, menu: null, forward: true, stack });
  }

  /** A new chat's page from outside (what is shared, in its composer): over the workspace's list. */
  openNew(workspace: string) {
    this.pickWorkspace(workspace);
    this.#set({ sheet: null, menu: null, forward: true, stack: [{ kind: "Home" }, { kind: "NewChat" }] });
  }

  /** An agent's execution history, over the chat it is in (at `entry`, else its newest): not twice over itself. */
  #pushHistory(address: string, of: ChatOf, key: string, entry: number | null) {
    const page: Screen = { kind: "History", station: address, of, key, entry };
    if (!sameScreen(this.top, page)) this.push(page);
  }

  /** The agents of each chat page (by its id) as last shown: whether a link names one of them. */
  readonly chatAgents = new Map<string, Set<string>>();

  /**
   * still.fail's own links in a chat open here, as pages over the one they are on: the core says what a link opens
   * (`link.parse`: an invitation, a chat's page, an item and its web service); a web service of one of this chat's
   * agents (`?service=<job>`) over the chat, another session as its chat (and its service over that). Any other link
   * goes to `orElse` (the system opens it). `outside`: a link from outside the app (a notification, the browser),
   * whose item opens over the list; `at`: the message a notification is about, its chat opened there.
   */
  openLink(url: string, outside = false, at: number | null = null, orElse: () => void = () => undefined) {
    void (async () => {
      let target: LinkTarget | null = null;
      try {
        target = (await core().call("link.parse", { url })) as LinkTarget | null;
      } catch {
        target = null;
      }
      if (target == null || !this.#open(target, outside, at)) orElse();
    })();
  }

  #open(t: LinkTarget, outside: boolean, at: number | null = null): boolean {
    const ws = t.workspace ?? "";
    const station = t.station ?? "";
    // One of its agents' execution history the link names, over the chat once it is open (`?history=`, `entry`).
    const history = t.history != null ? (address: string, session: string) => this.#pushHistory(address, { session }, t.history!, t.entry ?? null) : null;
    switch (t.opens) {
      // `?history=…` alone, as a chat's notes link to it: in the chat it is in.
      case "history": {
        const top = this.top;
        if (top.kind !== "Chat" || t.history == null) return false;
        this.#pushHistory(top.station, top.of, t.history, t.entry ?? null);
        break;
      }
      // An invitation's link: what it leads to, in a sheet, before it is accepted.
      case "invite":
        if (t.token == null) return false;
        AppHooks.invite(this, t.token);
        break;
      // A reference to another chat (web/src/chatRefs.ts), opened over this one.
      case "chat": {
        const chat = t.chat;
        if (chat == null) return false;
        const top = this.top;
        const address = `${ws}/${station}`;
        if (top.kind === "Chat" && top.station === address && "session" in top.of && top.of.session === chat) { history?.(address, chat); return true; }
        if (ws !== this.workspace) this.openItem(ws, station, chat);
        else this.#set({ sheet: null, menu: null, forward: true, stack: [...this.#state.stack, { kind: "Chat", station: address, of: { session: chat } }] });
        history?.(address, chat);
        break;
      }
      case "item": {
        const session = t.session;
        if (session == null) return false;
        const service = t.service ?? null;
        const address = `${ws}/${station}`;
        const top = this.top;
        const here = top.kind === "Chat" && top.station === address
          && (("session" in top.of && top.of.session === session) || this.chatAgents.get(screenId(top))?.has(session) === true);
        if (outside) this.openItem(ws, station, session, service, at);
        else if (here) { if (service != null) this.push({ kind: "Preview", station: address, job: service }); }
        else if (ws !== this.workspace) this.openItem(ws, station, session, service);
        else {
          const stack: Screen[] = [...this.#state.stack, { kind: "Chat", station: address, of: { session } }];
          if (service != null) stack.push({ kind: "Preview", station: address, job: service });
          this.#set({ sheet: null, menu: null, forward: true, stack });
        }
        // Here: over this chat, whose agent it is.
        if (here && top.kind === "Chat") { if (t.history != null) this.#pushHistory(top.station, top.of, t.history, t.entry ?? null); }
        else history?.(address, session);
        break;
      }
      // A station's 共享调试, as its agent asks for it (adb_devices): the page, sharing only once its person taps.
      case "adbShare": {
        if (station === "") return false;
        const address = `${ws}/${station}`;
        if (sameScreen(this.top, { kind: "AdbShare", address })) return true;
        const elsewhere = ws !== this.workspace;
        if (elsewhere) this.pickWorkspace(ws);
        const under: Screen[] = outside || elsewhere ? [{ kind: "Home" }] : this.#state.stack;
        this.#set({ sheet: null, menu: null, forward: true, stack: [...under, { kind: "AdbShare", address }] });
        break;
      }
      // One of a station's screens, as its agent asks a person to take over (docs/remote-screens.md): the viewer
      // over whatever page is open (back comes back to it).
      case "screen": {
        const screen = t.screen;
        if (screen == null || station === "") return false;
        this.openScreen(`${ws}/${station}`, screen, null);
        break;
      }
      default:
        return false;
    }
    return true;
  }

  /**
   * Opens one of a station's screens in the viewer (remote/ScreenActivity: over the app, set as the app starts);
   * `title`, the row's, until the core says one.
   */
  openScreen: (station: string, screen: string, title: string | null) => void = () => undefined;

  api(station: string): StationApi { return new StationApi(core(), station); }

  /** For what outlives the page that started it (a message sent as the page moves to its new chat). */
  readonly scope = {
    launch(run: () => Promise<unknown>): void {
      void run().catch((e: unknown) => console.warn("still.fail:", e));
    },
  };

  /** Where each chat was left (Place), by its page's id. */
  readonly places = new Map<string, Place>();

  /**
   * The pages, as what a sheet over them frosts (Haze's state in the Android app). Nothing to mark here: expo-blur
   * frosts what is behind it (ui/Glass.tsx); kept so the hosts take it as the Kotlin's do.
   */
  readonly haze: object = {};

  /** `call(name, params)` on the core. */
  call(name: string, params: unknown = {}) { return core().call(name, params); }

  /**
   * What a new chat ran on, kept here before the core kept it (newChat/<station's address>, newChat.lastIn/<scope>,
   * newChat.last): into the core once (newChat.migrate, by the stations' ids as the web keeps them), then gone.
   */
  #migrate() {
    const kept = [...this.#prefs.all.keys()].filter((k) => k.startsWith("newChat/") || k.startsWith("newChat.lastIn/") || k === "newChat.last");
    if (kept.length === 0) return;
    const id = (address: string) => address.slice(address.lastIndexOf("/") + 1);
    const choices: Record<string, unknown> = {};
    for (const k of kept.filter((k) => k.startsWith("newChat/"))) {
      const v = this.strings(k);
      if (v.length >= 3) {
        choices[id(k.slice("newChat/".length))] = {
          runtime: v[0], model: v[1],
          effort: v[2] !== "-" ? v[2] : "", profile: v[3] !== undefined && v[3] !== "-" ? v[3] : "",
        };
      }
    }
    const lastIn: Record<string, string> = {};
    for (const k of kept.filter((k) => k.startsWith("newChat.lastIn/"))) {
      const first = this.strings(k)[0];
      if (first !== undefined) lastIn[k.slice("newChat.lastIn/".length)] = id(first);
    }
    const last = this.strings("newChat.last")[0];
    const params = { choices, lastIn, ...(last !== undefined ? { last: id(last) } : {}) };
    // A core that refuses it: kept here, tried again next time.
    core().call("newChat.migrate", params).then(() => { for (const k of kept) this.#prefs.remove(k); }, () => undefined);
  }
}

/** What a page asks `isDoing` about, as doing.ts matches it: null is any, as undefined is. */
function given(on: Record<string, unknown>): Record<string, string | number | boolean | undefined> {
  const out: Record<string, string | number | boolean | undefined> = {};
  for (const [k, v] of Object.entries(on)) out[k] = v === null || v === undefined ? undefined : typeof v === "number" || typeof v === "boolean" ? v : String(v);
  return out;
}

/** The reader's settings before the core has said (the core's readerOf). */
const READER_DEFAULTS: ReaderPrefs = { size: 18, line: 1.7, margin: 22, face: "sans", indent: true, paper: "follow" };

export const app = new AppState();

/** The app, for a page (LocalApp.current). */
export const LocalApp = createContext<AppState>(app);

/** What a page reads of the app, drawn again when it changes. `select` returns a value or one of the state's own objects. */
export function useApp<T>(select: (s: State) => T): T {
  return useSyncExternalStore(app.subscribe, () => select(app.state));
}

/** How long a chat read ahead of its page (`AppState.prime`) is kept for it. */
export const PRIME_MS = 3_000;

/** Where the app kept 我 → 通知 before the core did (AppState.moveNotify). */
const NOTIFY_FLAG = "notify";

/**
 * What the app's state tells the app, which this module does not see; the app says where each goes as it starts
 * (BarTiming.start, the app's start); before that, nowhere.
 */
export const AppHooks = {
  /** A place taken from the bottom bar, from the place before (BarTiming.placed). */
  placed: (_from: Screen | null, _to: Screen): void => undefined,
  /** An invitation's link opened: what it leads to, in a sheet (screens/Workspaces.tsx openInvite). */
  invite: (_app: AppState, _token: string): void => undefined,
};

/**
 * The language the core last said, kept for a push that wakes the app with no core to ask (Notices words); in the
 * app's prefs.
 */
export const KeptLang = {
  KEY: "lang",
  /** Whether this process has followed the core's language (keep): then it is the one. */
  followed: false,

  keep(prefs: DeviceStore, lang: string | null) {
    if (lang == null) return;
    KeptLang.followed = true;
    if (prefs.getString(KeptLang.KEY, null) !== lang) prefs.putString(KeptLang.KEY, lang);
  },

  /** The language kept, for a process that has not followed the core's. */
  kept(prefs: DeviceStore): string | null { return prefs.getString(KeptLang.KEY, null); },

  /**
   * The words, in the language last followed (a push, an installer's answer, may come with no app started).
   * NATIVE: a push handled with no JS app started (the Android app's Notices) reads the kept language natively; in JS the
   * words follow the prefs (src/i18n.ts), so there is nothing to load here.
   */
  words(): string | null { return KeptLang.followed ? null : KeptLang.kept(devicePrefs); },
};
