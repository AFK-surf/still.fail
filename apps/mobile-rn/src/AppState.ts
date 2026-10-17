// What the pages share of the app (the Android app's AppState.kt, ported as it is): where it is (its stack of pages,
// Screen), what is over it (a sheet, a menu, a toast, an entry read in full), and the ways to the core. A store the
// pages read with `useApp(select)` and change through `app`; the app draws it (src/App.tsx). How its person likes it
// on this device is the core's prefs, through web/src/prefs.ts (the web's own logic, one copy).
import { useSyncExternalStore } from "react";
import type { ReactNode } from "react";
import { core } from "../../../web/src/core/react.ts";
import { prefs, setPrefs } from "../../../web/src/prefs.ts";
import { t } from "./i18n";

/** An item's page: its chat by thread, or its agent (a session) before it has one (data/Chats.kt ChatOf). */
export type ChatOf = { thread: number } | { session: string };
export const chatOfKey = (of: ChatOf) => ("thread" in of ? String(of.thread) : of.session);

/** The pages (AppState.kt Screen), each with its id (`screenId`). */
export type Screen =
  | { kind: "Home" }
  /** `at`: a message (seq) to show once it opens, flashing; `words`: what to find in it. */
  | { kind: "Chat"; station: string; of: ChatOf; at?: number; words?: string[] }
  /** Rises from the bottom rather than coming in from the side. */
  | { kind: "NewChat" }
  | { kind: "Stations" }
  | { kind: "Station"; address: string }
  | { kind: "AdbShare"; address: string }
  | { kind: "History"; station: string; of: ChatOf; key: string; entry?: number }
  | { kind: "RunSettings"; station: string; of: ChatOf; key: string }
  | { kind: "Profile"; address: string; profile: string }
  /** Settings, one page from the gear on Home; it comes from the left. */
  | { kind: "Settings" }
  | { kind: "Me" }
  | { kind: "Appearance" }
  | { kind: "KeptFiles" }
  | { kind: "KeptChat"; station: string | null; thread: number | null }
  | { kind: "Changelog" }
  | { kind: "Connects"; station?: string }
  | { kind: "Profiles"; station?: string }
  | { kind: "ProfileAccount"; key: string }
  | { kind: "AutomaticDecisions" }
  | { kind: "AutomaticDecisionCompletion" }
  | { kind: "AutomaticDecisionPolicy"; station: string }
  | { kind: "Memories" }
  | { kind: "Usage" }
  | { kind: "UsagePrices"; days: number }
  | { kind: "Preview"; station: string; job: string }
  | { kind: "PreviewFile"; station: string; session: string; path: string; name: string }
  | { kind: "Workspace" }
  | { kind: "Security" }
  | { kind: "SecurityOpen" }
  | { kind: "Vault" }
  | { kind: "VaultItem"; vault: string; item: string }
  | { kind: "Connect"; station: string; connect: string }
  | { kind: "ConnectRun"; station: string; connect: string }
  | { kind: "NewConnect"; station: string }
  | { kind: "NewProfile"; station: string }
  | { kind: "Archive" }
  | { kind: "Decisions" }
  | { kind: "Files" }
  | { kind: "BarSettings" }
  | { kind: "Memory"; station: string }
  | { kind: "MemoryDoc"; station: string; skill: string | null; at?: number }
  | { kind: "Drive"; station: string; root: string | null; path: string }
  | { kind: "DriveRead"; station: string; root: string; path: string }
  | { kind: "DrivePlay"; station: string; root: string; path: string }
  | { kind: "SlackApp"; station: string; connect: string };

export type ScreenKind = Screen["kind"];

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

/** A sheet from the bottom (ui/Sheet.kt SheetSpec): what it shows, and what runs when it closes. */
export interface SheetSpec { content: () => ReactNode; onClose?: () => void; full?: boolean }
/** A menu by what opened it (ui/Sheet.kt MenuSpec): `at` the opener's box in the window, its items. */
export interface MenuItem { label: string; icon?: import("./ui/IconSet").IconPaths | null; danger?: boolean; onClick: () => void }
export interface MenuSpec { at: { x: number; y: number; width: number; height: number }; items: MenuItem[]; width?: number }
/** One entry of an execution history in full, over everything (ui/Sheet.kt ReaderSpec). */
export interface ReaderSpec { title: string; content: () => ReactNode }

/** An action of a place's page in the bottom bar's notch (ui/Bar.kt BarAction). */
export interface BarAction { icon: import("./ui/IconSet").IconPaths; label: string; onClick: () => void }

interface State {
  stack: Screen[];
  /** Whether the last move went deeper, for the direction of the transition. */
  forward: boolean;
  sheet: SheetSpec | null;
  menu: MenuSpec | null;
  toast: string | null;
  reader: ReaderSpec | null;
  /** The bottom bar out of the way (a search open over the list). */
  barAway: boolean;
  /** Each place's action in the bar's notch, by place. */
  placeActions: Record<string, BarAction | null>;
  /** The chat a new chat's page became (it stays the page it was, so the page does not slide). */
  madeChat: Screen | null;
  /** The app is on screen. */
  inFront: boolean;
}

type Listener = () => void;

class AppStore {
  #state: State = { stack: [{ kind: "Home" }], forward: true, sheet: null, menu: null, toast: null, reader: null, barAway: false, placeActions: {}, madeChat: null, inFront: true };
  /** The stack as it was when a place was put in place of it (`place`): a switch, not a push. */
  #placed: Screen[] | null = null;
  readonly #listeners = new Set<Listener>();
  /** Which agents each chat page shows, by its id (a link to one of them opens over it). */
  readonly chatAgents = new Map<string, Set<string>>();
  /** Where each chat was left: the message at its list's top, how far below the top it sat, and the newest then if at its end. */
  readonly places = new Map<string, { id: string; offset: number; bottom: string | null }>();

  get state(): State { return this.#state; }
  subscribe = (l: Listener) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  #set(next: Partial<State>) {
    this.#state = { ...this.#state, ...next };
    for (const l of this.#listeners) l();
  }

  get stack() { return this.#state.stack; }
  get top(): Screen { return this.#state.stack[this.#state.stack.length - 1]!; }

  set sheet(s: SheetSpec | null) { this.#set({ sheet: s }); }
  get sheet() { return this.#state.sheet; }
  set menu(m: MenuSpec | null) { this.#set({ menu: m }); }
  get menu() { return this.#state.menu; }
  set toast(text: string | null) { this.#set({ toast: text }); }
  set reader(r: ReaderSpec | null) { this.#set({ reader: r }); }
  set barAway(away: boolean) { if (away !== this.#state.barAway) this.#set({ barAway: away }); }
  set inFront(on: boolean) { if (on !== this.#state.inFront) this.#set({ inFront: on }); }
  setPlaceAction(place: string, action: BarAction | null) { this.#set({ placeActions: { ...this.#state.placeActions, [place]: action } }); }

  /** A place of the bottom bar in place of the whole stack: switched to, not pushed (no going back to the one before). */
  place(screen: Screen) {
    const to = [screen];
    this.#placed = to;
    this.#set({ sheet: null, menu: null, forward: true, stack: to });
  }
  /** The stack is a place just switched to (its page comes in as a switch, not a push). */
  get switched(): boolean { return this.#state.stack === this.#placed; }

  push(screen: Screen) {
    const madeChat = screen.kind === "NewChat" || (this.#state.madeChat && screenId(screen) === screenId(this.#state.madeChat)) ? null : this.#state.madeChat;
    this.#set({ sheet: null, menu: null, forward: true, madeChat, stack: [...this.#state.stack, screen] });
  }
  pop() {
    if (this.#state.stack.length > 1) this.#set({ sheet: null, menu: null, forward: false, stack: this.#state.stack.slice(0, -1) });
  }
  /** On top unless it is already: the page it is, or a new one pushed. */
  open(screen: Screen) {
    if (screenId(this.top) === screenId(screen)) return;
    this.push(screen);
  }
  replace(screen: Screen) { this.#set({ sheet: null, forward: true, stack: [...this.#state.stack.slice(0, -1), screen] }); }
  /** A new chat's page became `screen`: it stays (no slide), as the chat. */
  made(screen: Screen) { this.#set({ madeChat: screen }); this.replace(screen); }
  /** A page's id as the transitions see it: a new chat that became a chat is still the new chat's page. */
  pageOf(screen: Screen): string {
    const made = this.#state.madeChat;
    return screen.kind === "NewChat" || (made && screenId(screen) === screenId(made)) ? "new-chat" : screenId(screen);
  }
  home() { this.#set({ sheet: null, forward: false, stack: [{ kind: "Home" }] }); }

  /**
   * Something people set going that may fail (AppState.kt act): `run` under way, `done` said after, a failure said
   * (and `failed` run). What is under way shows on the control through the core's doing list (useDoing).
   */
  act(what: string, run: () => Promise<unknown>, done?: string, failed?: () => void) {
    run().then(
      () => { if (done) this.toast = done; },
      (e: unknown) => {
        failed?.();
        this.toast = t("android-misc.act.failed", { what, error: e instanceof Error ? e.message : String(e) });
      },
    );
  }

  /** The workspace shown (the core's prefs). */
  get workspace(): string | undefined { return prefs().workspace ?? undefined; }
  pickWorkspace(id: string) { if (id !== prefs().workspace) setPrefs({ workspace: id }); }

  /** What `workspace`'s chat list shows: "all", "mine" or "watching" (AppState.kt chatFilter). */
  chatFilter(workspace: string): "all" | "mine" | "watching" {
    const p = prefs();
    const mode = p.listFilter?.[workspace] ?? (p.onlyDecisions ? "decisions" : p.onlyWatching ? "watching" : p.onlyMine ? "mine" : "all");
    return mode === "mine" || mode === "watching" ? mode : "all";
  }
  showChats(workspace: string, filter: "all" | "mine" | "watching") { setPrefs({ listFilter: { [workspace]: filter } }); }

  call(name: string, params: unknown = {}) { return core().call(name, params); }
}

export const app = new AppStore();

/** What a page reads of the app, drawn again when it changes. */
export function useApp<T>(select: (s: State) => T): T {
  return useSyncExternalStore(app.subscribe, () => select(app.state));
}
