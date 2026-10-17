// The places of the phone's bottom bar (ui/Bar.tsx): which page each is, what it looks like, and the bar as the app
// wires it (the core keeps the bars whole in the device's prefs, `bars`: client/core-ts/src/prefs.ts barsOf). Places.kt.
import { createContext, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { ChatsView, BarPrefs, StatusView, WorkspaceMarksView } from "../../../web/src/core/shapes.ts";
import { useTopic } from "../../../web/src/core/react.ts";
import { LocalApp, useApp, type AppState, type Screen } from "./AppState";
import type { WorkspaceEntry } from "./data/Accounts";
import { Topics } from "./data/Topics";
import { t } from "./i18n";
import { BarAction, BottomBar } from "./ui/Bar";
import { Icon } from "./ui/Icon";
import { Icons, type IconPaths } from "./ui/IconSet";
import { StationGlyph, glyphCounts, type GlyphCounts } from "./ui/StationGlyph";
import { useC } from "./ui/Theme";

/** Every place a bar can hold, in the order the picker lists them (the core's BAR_PLACES). */
export const PLACES = ["chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive"];

/** At most this many places in one bar (the core's BAR_SIZE). */
export const BAR_SIZE = 4;

/** The chats' family: on their pages 令 (a new chat) stands in the bar's notch; the other places' pages say theirs (PlaceAction). */
export const CHAT_FAMILY: ReadonlySet<string> = new Set(["chats", "decisions", "archive"]);

/** The bars before the core has said (the core's BARS_DEFAULT). */
export const DEFAULT_BARS: BarPrefs = { sets: [["chats", "files", "profiles", "stations"], ["decisions", "usage", "connects", "archive"]], current: 0 };

/**
 * The bars whole, as the core keeps them (barsOf): each bar one to four known places, none twice; empty bars dropped;
 * none left, the default ones; the one in view one of them.
 */
export function barsOf(sets: string[][], current: number): BarPrefs {
  const kept = sets.map((set) => [...new Set(set.filter((p) => PLACES.includes(p)))].slice(0, BAR_SIZE)).filter((set) => set.length > 0);
  if (kept.length === 0) return DEFAULT_BARS;
  return { sets: kept, current: Math.min(Math.max(Math.trunc(current), 0), kept.length - 1) };
}

/** The place a page is the top of (null: it is not a place's): the workspace's profiles and connects, not a station's. */
export function placeOf(screen: Screen): string | null {
  switch (screen.kind) {
    case "Home": return "chats";
    case "Decisions": return "decisions";
    case "Files": return "files";
    case "Stations": return "stations";
    case "Profiles": return screen.station == null ? "profiles" : null;
    case "Connects": return screen.station == null ? "connects" : null;
    case "Usage": return "usage";
    case "Archive": return "archive";
    default: return null;
  }
}

/** A place's page. */
export function screenOf(place: string): Screen {
  switch (place) {
    case "decisions": return { kind: "Decisions" };
    case "files": return { kind: "Files" };
    case "stations": return { kind: "Stations" };
    case "profiles": return { kind: "Profiles" };
    case "connects": return { kind: "Connects" };
    case "usage": return { kind: "Usage" };
    case "archive": return { kind: "Archive" };
    default: return { kind: "Home" };
  }
}

/** A place's name (the settings' cards, the picker, what a screen reader says on the bar). */
export function placeLabel(place: string): string {
  return t(`android-misc.bar.place.${place}`);
}

/**
 * What a page is to the bar: not a place's top (`None`); a place's top with the bar under it (`Bar`: no back, room at
 * its foot for the bar); a place's top on a wide screen, which has no bar (`Wide`: its back goes to the chats).
 */
export enum PlaceRoot { None = "None", Bar = "Bar", Wide = "Wide" }

export const LocalPlaceRoot = createContext<PlaceRoot>(PlaceRoot.None);

/** The room a place's top page keeps at its foot (over the navigation bar) for the bar to float over: none without it. */
export const LocalBarRoom = createContext<number>(0);

/**
 * The bar's height, its distance from the foot (over the navigation bar), a little air over it, and the action in its
 * notch, which stands 32 over the bar (ui/Bar.tsx: half of it, and its lift): what a page keeps clear. Every place's page
 * keeps it, with an action or not, so nothing moves as one comes and goes.
 */
export const BAR_ROOM = 56 + 22 + 16 + 32;

/** A place's icon, 28 as the bar draws them. */
export function PlaceIcon({ place, tint, glyph }: { place: string; tint: string; glyph: GlyphCounts | null }) {
  if (place === "stations") return glyph != null ? <StationGlyph counts={glyph} size={28} tint={tint} /> : <Icon icon={Icons.Server} size={28} color={tint} />;
  return <Icon icon={placeIcon(place)} size={28} color={tint} />;
}

/**
 * A place's top page says its primary action (null: none) for the bar's notch (PlaceBar), while it is the bar's page; on
 * the chats' pages it is always 令. Kept once said, by workspace and place, so coming back to a place the notch is as it
 * will be at once. `known` false: what decides it is not read yet, and the notch stays as it is meanwhile, rather than
 * closing only to open again.
 */
export function PlaceAction({ workspace, place, action, known = true }: { workspace: string; place: string; action: BarAction | null; known?: boolean }) {
  const app = useContext(LocalApp);
  const root = useContext(LocalPlaceRoot);
  // After every drawing, as Compose's SideEffect.
  useLayoutEffect(() => {
    if (root !== PlaceRoot.Bar || CHAT_FAMILY.has(place)) return;
    if (!known) return;
    const key = `${workspace}|${place}`;
    const actions = app.placeActions;
    const was = actions[key] ?? null;
    // The same action: its latest doing, nothing for the bar to redraw.
    if (action != null && was != null && was.key === action.key && was.label === action.label) was.run = action.run;
    else if (was !== action || !(key in actions)) app.setPlaceAction(key, action);
  });
  return null;
}

function placeIcon(place: string): IconPaths {
  switch (place) {
    case "chats": return Icons.Chats;
    case "decisions": return Icons.Zou;
    case "files": return Icons.Folder;
    case "profiles": return Icons.Quota;
    case "connects": return Icons.Im;
    case "usage": return Icons.Chart;
    case "archive": return Icons.Archive;
    default: return Icons.Server;
  }
}

/**
 * The bottom bar on the pages of `current` (App.tsx Pages): shown on a place's top page with nothing over it; its dots
 * as Home and Settings say them (奏 waiting for the viewer, a station in trouble).
 */
export function PlaceBar({ app, current, haze, shown }: { app: AppState; current: WorkspaceEntry; haze: unknown; shown: boolean }) {
  const C = useC();
  const ws = current.workspace.id;
  const bars = useApp(() => app.bars);
  const root = useApp((s) => s.stack[0]!);
  const active = placeOf(root);
  const marks = useTopic<WorkspaceMarksView>(Topics.workspaceMarks(ws));
  const decisions = Math.trunc(marks.value?.workspaces?.[ws]?.decisions ?? 0);
  const chats = useTopic<ChatsView>(Topics.chats(ws, false));
  const status = useTopic<StatusView>(Topics.status(ws));
  const glyph = useMemo(() => glyphCounts(chats.value ?? null, status.value?.state === "trouble"), [chats.value, status.value?.state]);
  // The stations in trouble as the core says it (web mobile/Bar.tsx the same); in words, what Home's corner said.
  const trouble = chats.value?.trouble;
  const said = glyph.asleep ? (status.value?.text ?? "") : (chats.value?.glyph?.label ?? "");
  const stationsSaid = trouble != null ? t("android-chat.home.stations.trouble", { said, trouble: trouble.text }) : t("android-chat.home.stations", { said });
  const accent = C.accent;
  const red = C.red;
  const dots: Record<string, string> = {};
  if (decisions > 0) dots.decisions = accent;
  if (trouble != null) dots.stations = red;
  // The notch's action: 令 on the chats' pages, else what the place's page said (PlaceAction); a page not drawn yet
  // that has not said, the notch as it was until it does (from 令 to a "+", it stays open), a second at most.
  const lingLabel = t("android-chat.newChat");
  const ling = useMemo(() => new BarAction("ling", lingLabel, Icons.Ling, () => app.push({ kind: "NewChat" })), [lingLabel, app]);
  const actions = useApp((s) => s.placeActions);
  const held = useRef<BarAction | null>(null);
  const keyNow = `${ws}|${active}`;
  const [waitedFor, setWaitedFor] = useState<string | null>(null);
  const waited = waitedFor === keyNow;
  useEffect(() => {
    const timer = setTimeout(() => setWaitedFor(keyNow), 1000);
    return () => clearTimeout(timer);
  }, [keyNow]);
  const action: BarAction | null =
    active == null ? null
    : CHAT_FAMILY.has(active) ? ling
    : `${ws}|${active}` in actions ? (actions[`${ws}|${active}`] ?? null)
    : waited ? null
    : held.current;
  held.current = action;
  return (
    <BottomBar
      sets={bars.sets} cur={Math.trunc(bars.current)} active={active} action={action} shown={shown}
      haze={haze} dots={dots} labelOf={(key: string) => (key === "stations" && said !== "" ? stationsSaid : placeLabel(key))}
      notches={(place: string) => CHAT_FAMILY.has(place) || actions[`${ws}|${place}`] != null}
      icon={(place: string, tint: string) => <PlaceIcon place={place} tint={tint} glyph={glyph} />}
      onTab={(place: string) => { if (app.stack.length === 1) app.place(screenOf(place)); }}
      onSwitch={(i: number, place: string | null) => {
        const now = app.bars;
        app.setBars(now.sets, i);
        // Only from a place's top: a page pushed meanwhile (a notification opened) stays.
        if (place != null && app.stack.length === 1 && placeOf(app.stack[0]!) !== place) app.place(screenOf(place));
      }}
    />
  );
}
