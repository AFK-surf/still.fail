// The app: signed out it is the sign-in page; signed in, the chats of one workspace are home, and everything else is a
// page pushed over it (no tab bar), or a sheet from the bottom (the Android app's App.kt).
import { createContext, memo, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { BackHandler, Keyboard, Linking, StyleSheet, View, useWindowDimensions } from "react-native";
import { requireOptionalNativeModule } from "expo-modules-core";
import Animated, { Easing, cancelAnimation, runOnJS, useAnimatedStyle, useSharedValue, withTiming, type SharedValue } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { Topic } from "../../../web/src/core/client.ts";
import { core, useTopic } from "../../../web/src/core/react.ts";
import type { StatusView } from "../../../web/src/core/shapes.ts";
import { usePrefs } from "../../../web/src/prefs.ts";
import { AppHooks, screenId, sameScreen, useApp, type AppState, type Screen } from "./AppState";
import { BarTiming } from "./BarTiming";
import { entries, type Account, type AccountWorkspaces, type WorkspaceEntry } from "./data/Accounts";
import { DriveCache } from "./data/DriveCache";
import { LocalPageTopics, PageTopics, preread, Topics } from "./data/Topics";
import { FilesScreen } from "./drive/Files";
import { DriveScreen } from "./drive/DriveScreen";
import { PlayerScreen } from "./drive/Player";
import { ReaderScreen } from "./drive/Reader";
import { t } from "./i18n";
import { Notifier, rememberNotificationAsk } from "./Notices";
import { BAR_ROOM, LocalBarRoom, LocalPlaceRoot, PLACES, PlaceBar, PlaceRoot, placeOf, screenOf } from "./Places";
import { AdbShareScreen } from "./screens/AdbShare";
import { ArchiveScreen } from "./screens/Archive";
import { AutomaticDecisionCompletionScreen, AutomaticDecisionPolicyScreen, AutomaticDecisionsScreen } from "./screens/AutomaticDecisions";
import { BarSettingsScreen } from "./screens/BarSettings";
import { ChangelogScreen } from "./screens/Changelog";
import { ChatHost } from "./screens/ChatHost";
import { ConnectRunScreen, ConnectScreen, ConnectsScreen, NewConnectScreen } from "./screens/Connects";
import { DecisionsScreen } from "./screens/Decisions";
import { FileViewers, ViewerHost } from "./screens/FilePreview";
import { HistoryScreen, RunSettingsScreen } from "./screens/History";
import { HomeScreen } from "./screens/Home";
import { KeptChatScreen, KeptFilesScreen } from "./screens/KeptFiles";
import { MeScreen } from "./screens/Me";
import { MemoriesScreen, MemoryDocScreen, MemoryScreen } from "./screens/Memory";
import { PreviewFileScreen, PreviewScreen } from "./screens/Preview";
import { NewProfileScreen, ProfileAccountScreen, ProfileScreen, ProfilesScreen } from "./screens/Profiles";
import { LockGate, SecurityOpenScreen, SecurityScreen } from "./screens/Security";
import { WorkspaceScreen } from "./screens/Settings";
import { AppearanceScreen, SettingsScreen } from "./screens/SettingsHome";
import { SignInScreen } from "./screens/SignIn";
import { SlackAppScreen } from "./screens/SlackApp";
import { StationScreen, StationsScreen } from "./screens/Stations";
import { UsagePricesScreen, UsageScreen } from "./screens/Usage";
import { VaultItemScreen, VaultScreen } from "./screens/Vault";
import { WideAt, WideCorners } from "./screens/Wide";
import { Blocked, Landing, openInvite } from "./screens/Workspaces";
import { LocalWide } from "./ui/ChatInk";
import { KeyboardInsets } from "./ui/Keyboard";
import { Splash, reducedMotion } from "./ui/Parts";
import { MenuHost, ReaderHost, SheetHost, ToastHost } from "./ui/Sheet";
import { useC } from "./ui/Theme";

/**
 * Links in what agents write go through here (Compose's LocalUriHandler): still.fail's own open in the app
 * (AppState.openLink), the rest by the system.
 */
export const LocalUriHandler = createContext<{ openUri: (uri: string) => void }>({ openUri: (uri) => { void Linking.openURL(uri).catch(() => undefined); } });

export function StillFailApp({ app }: { app: AppState }) {
  // An invitation's link opens its sheet, a page of the app's (AppState.openLink).
  AppHooks.invite = openInvite;
  // Where files of a drive are kept once read (the reader, the viewer and the player find it there).
  useState(() => { DriveCache.start(); return true; });
  return <KeyboardInsets><AppContent app={app} /></KeyboardInsets>;
}

function AppContent({ app }: { app: AppState }) {
  const C = useC();
  const accounts = useTopic<Account[]>(Topics.accounts);
  const workspaces = useTopic<AccountWorkspaces[]>(Topics.workspaces);
  // Nothing on the phone opens it (a bare file name, an unknown scheme): said, not a crash.
  const [links] = useState(() => ({
    openUri: (uri: string) => app.openLink(uri, false, null, () => {
      Linking.openURL(uri).catch(() => { app.toast = t("android-misc.link.cantOpen"); });
    }),
  }));
  const signedIn = accounts.value;
  const stack = useApp((s) => s.stack);
  const sheet = useApp((s) => s.sheet);
  const reader = useApp((s) => s.reader);
  const menu = useApp((s) => s.menu);
  const toast = useApp((s) => s.toast);
  const inFront = useApp((s) => s.inFront);
  const top = stack[stack.length - 1] ?? null;
  // A chat opened: its notification is read (its tag, as Notices shows it).
  useEffect(() => {
    if (top?.kind === "Chat" && "session" in top.of) Notifier.cancel(`${top.station}/${top.of.session}`);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [top]);
  // Looked at while in front with a chat on top (the chat itself says which, screens/Chat.tsx): its notices are not
  // shown then (client/core-ts/src/attend.ts).
  const lookedAt = inFront && top?.kind === "Chat";
  useEffect(() => { core().focus({ visible: inFront, focused: lookedAt }).catch(() => undefined); }, [inFront, lookedAt]);
  return (
    <LocalUriHandler.Provider value={links}>
      <View style={{ flex: 1, backgroundColor: C.bg }}>
        <View style={{ flex: 1, backgroundColor: C.bg }}>
          {signedIn == null ? <Splash label={accounts.error?.message ?? null} now={accounts.error != null} />
            : signedIn.length === 0 ? <SignInScreen />
            : <SignedIn app={app} signedIn={signedIn} workspaces={workspaces.value} workspacesError={workspaces.error?.message ?? null} />}
        </View>
        {/* An image or a video opened, over the pages (it grows out of its thumbnail in the chat); sheets and notes over it. */}
        <ViewerHost />
        <SheetHost spec={sheet} haze={app.haze} close={() => { app.sheet?.onClose?.(); app.sheet = null; }} />
        <ReaderHost spec={reader} close={() => { app.reader = null; }} />
        <MenuHost spec={menu} closed={() => { app.menu = null; }} />
        <ToastHost toast={toast} done={() => { app.toast = null; }} />
      </View>
    </LocalUriHandler.Provider>
  );
}

/** How long an opening page waits for what the core has on the device (web motion.ts LOCAL_MS): never for a station. */
const LOCAL_MS = 100;
/** How long a workspace's lists read ahead of switching to it are kept for it (AppState.kt PRIME_MS). */
const PRIME_MS = 3_000;

/** A workspace's lists (screens/Home.tsx), as it follows them: read ahead of switching to it. */
const homeLists = (workspace: string): Topic[] => [Topics.chats(workspace, false), Topics.chats(workspace, true), Topics.chats(workspace, false, true)];

/** What is shown by a workspace's lists (screens/Home.tsx, OpenJobs.tsx), as they follow it. */
const homeExtras = (workspace: string): Topic[] => [Topics.workspaceMarks(workspace), Topics.status(workspace), Topics.longJobs(workspace)];

/** What a page shows first, which it waits for as it opens (Pages): its main topics, as its screen follows them. */
function opening(screen: Screen, workspace: string): Topic[] {
  switch (screen.kind) {
    case "Chat": return [Topics.chat(screen.station, screen.of)];
    case "History": return [Topics.chat(screen.station, screen.of), Topics.history(screen.station, screen.key)];
    case "Preview": return [Topics.job(screen.station, screen.job)];
    case "Station": return [Topics.stations(workspace)];
    // A folder as it was last read (held on the device): the page slides in with its rows.
    case "Drive": return screen.root != null ? [Topics.drive(screen.station, screen.root, screen.path)] : [];
    // A secret's page: what it is (its row), its uses after.
    case "VaultItem": return [Topics.vaultItems(workspace, screen.vault)];
    case "Archive": return [Topics.archive(workspace)];
    case "Decisions": return [Topics.decisions(workspace)];
    case "Files": case "Stations": return [Topics.stations(workspace)];
    default: return [];
  }
}

/** Signed in: the workspace in view (the one last open, else the first), its pages; or why there is none yet. */
function SignedIn({ app, signedIn, workspaces: all, workspacesError }: { app: AppState; signedIn: Account[]; workspaces: AccountWorkspaces[] | undefined; workspacesError: string | null }) {
  const chosen = usePrefs((p) => p.workspace ?? null);
  const list = all !== undefined ? entries(all) : null;
  // Only once every account has answered does "no workspace" mean none: not before, not after a failure.
  // The one last open, or one just joined, may not be in what was kept yet: until the accounts answer (or fail), it is
  // waited for rather than another put in its place.
  const answered = all !== undefined && all.every((a) => a.loaded === true || a.error != null);
  const target = list?.find((e) => e.workspace.id === chosen) ?? ((chosen == null || answered) ? list?.[0] ?? null : null) ?? null;
  const targetId = target?.workspace.id ?? null;
  useEffect(() => { if (target != null && target.workspace.id !== app.workspace) app.pickWorkspace(target.workspace.id); }, [targetId]); // eslint-disable-line react-hooks/exhaustive-deps
  // Switched to another workspace, the one shown stays until the core has given what its list shows, from what is on
  // the device (LOCAL_MS at most, as a page opening): not its list swapped for the loading look and placeholders, then
  // the rows a few frames later (a flash, under the switcher closing).
  const [shown, setShown] = useState<string | null>(null);
  const shownRef = useRef<string | null>(null);
  useEffect(() => {
    let live = true;
    const id = targetId;
    (async () => {
      if (id != null && shownRef.current != null && id !== shownRef.current) {
        // What is by the list (its marks, status, what is left up) read ahead too, but only the list waited for.
        void preread(core(), homeExtras(id), 0, PRIME_MS);
        await preread(core(), homeLists(id), LOCAL_MS, PRIME_MS);
      }
      if (!live) return;
      shownRef.current = id;
      setShown(id);
    })();
    return () => { live = false; };
  }, [targetId]);
  const current = target == null ? null : list?.find((e) => e.workspace.id === shown) ?? target;
  // The beta app, and an account not let into the beta (the core says so): said, with a way out.
  const blocked = all?.find((a) => a.blocked != null) ?? null;
  if (current == null && blocked != null) return <Blocked entry={blocked} />;
  if (current == null) {
    if (list == null || all === undefined || !all.every((a) => a.loaded === true)) {
      const failed = workspacesError ?? (all?.some((a) => a.error != null) ? t("android-misc.workspaces.loadFailed") : null);
      return <Loading failed={failed} />;
    }
    return <Landing accounts={signedIn} workspaces={all} />;
  }
  return <InWorkspace app={app} current={current} />;
}

/** The workspaces being read: what the core has been waiting on for a while under it (the core's `status`), as the web's splash says. */
function Loading({ failed }: { failed: string | null }) {
  const status = useTopic<StatusView>(Topics.status());
  return <Splash label={failed ?? [t("android-misc.workspaces.loading"), status.value?.text].filter((s) => s != null && s !== "").join("\n")} now={failed != null} />;
}

function InWorkspace({ app, current }: { app: AppState; current: WorkspaceEntry }) {
  rememberNotificationAsk(app, true);
  // The core hears which workspace the app is in: what it tells the viewer is of it (attend.ts).
  useEffect(() => { core().focus({ workspace: current.workspace.id }).catch(() => undefined); }, [current.workspace.id]);
  return <Pages app={app} current={current} />;
}

// ── the pages' transitions ─────────────────────────────────────────────

/** What a page's motion moves: across, down, how opaque. */
type Prop = "x" | "y" | "alpha";
/** The curves by number, as worklets read them: linear, FastOutSlowIn (Ease.Standard), Ease.Arrive, easeOutQuad. */
const LINEAR = 0;
const STANDARD = 1;
const ARRIVE = 2;
const EASE_OUT = 3;
const standardEase = Easing.bezierFn(0.4, 0, 0.2, 1);
const arriveEase = Easing.bezierFn(0.2, 0.8, 0.2, 1);
/** Out of a swipe let go: starts moving, no ease in (easeOutQuad). */
const outEase = Easing.bezierFn(0.25, 0.46, 0.45, 0.94);
function curve(easing: number, t: number): number {
  "worklet";
  if (easing === STANDARD) return standardEase(t);
  if (easing === ARRIVE) return arriveEase(t);
  if (easing === EASE_OUT) return outEase(t);
  return t;
}

/** One animation of a page coming or going (Compose's slideIn/Out, fadeIn/Out): a property from, to, over `ms` on a curve. */
interface Part { prop: Prop; from: number; to: number; ms: number; easing: number }
/**
 * What a change of page does (Compose's ContentTransform): the page coming (`enter`) and the one going (`exit`), how
 * long it all takes (the longest of them), and where the page coming is drawn (`z`, over the pages under it).
 */
interface Spec { enter: Part[]; exit: Part[]; total: number; z: number }
const spec = (enter: Part[], exit: Part[], z: number): Spec => ({ enter, exit, z, total: Math.max(1, ...enter.map((p) => p.ms), ...exit.map((p) => p.ms)) });
const part = (prop: Prop, from: number, to: number, ms: number, easing: number): Part => ({ prop, from, to, ms, easing });
/** Compose's tween with no curve given is FastOutSlowIn. */
const fadeIn = (ms: number, easing = STANDARD, initial = 0) => part("alpha", initial, 1, ms, easing);
const fadeOut = (ms: number, easing = STANDARD, target = 0) => part("alpha", 1, target, ms, easing);

/** Where a page is `ms` into its motion: across and down (dp), and how opaque. */
function sample(parts: Part[], ms: number): { x: number; y: number; alpha: number } {
  "worklet";
  const at = { x: 0, y: 0, alpha: 1 };
  for (const p of parts) {
    const t = p.ms <= 0 ? 1 : Math.min(1, Math.max(0, ms / p.ms));
    at[p.prop] = p.from + (p.to - p.from) * curve(p.easing, t);
  }
  return at;
}

/** The places' top pages (Places.tsx): their state is kept while they are not in the stack, as the bar switches between them. */
const PLACE_PAGES = new Set(PLACES.map((p) => screenId(screenOf(p))));
/** Each place's top page's id, to its place. */
const PLACE_OF_PAGE = new Map(PLACES.map((p) => [screenId(screenOf(p)), p] as const));

/**
 * Switched on the bar from one place's page to another's (not a push: nothing to go back to): a shared axis along the
 * bar. The page coming in moves 30dp in from the side the ball goes to, fading in (220 ms); the one going fades out in
 * the first 90 ms, moving 30dp the other way. To a place not in the bar in view (chosen through the panel of the other
 * bars), no side to come from: it only fades in over the page going (180 ms). Reduced motion: at once.
 */
function placeSwitch(from: Screen, to: Screen, bars: { sets: string[][]; current: number }, still: boolean, shift: number): Spec {
  if (still) return { enter: [], exit: [], total: 0, z: 0 };
  const bar = bars.sets[Math.trunc(bars.current)] ?? [];
  const pa = placeOf(from);
  const pb = placeOf(to);
  const a = pa == null ? -1 : bar.indexOf(pa);
  const b = pb == null ? -1 : bar.indexOf(pb);
  if (a < 0 || b < 0 || a === b) return spec([fadeIn(180, ARRIVE)], [fadeOut(180, STANDARD, 0.99)], 0);
  const way = b > a ? 1 : -1;
  return spec(
    [part("x", way * shift, 0, 220, ARRIVE), fadeIn(220, ARRIVE)],
    [part("x", 0, -way * shift, 220, ARRIVE), fadeOut(90, LINEAR)],
    0,
  );
}

/**
 * Swiped back: the page goes right with the finger (linear in the seek, so it is where the finger is) and the one under
 * it comes along beside it, edge to edge, as a tapped back moves them. Settings came from the left (`toLeft`): they go
 * back that way, the list coming from the right. An unsent new chat (`rose`) rose from the bottom: it sinks back down
 * with the finger over the page under it, as a tapped back takes it.
 */
function swipe(toLeft: boolean, z: number, rose: boolean, w: number, h: number): Spec {
  const way = toLeft ? -1 : 1;
  if (rose) return spec([], [part("y", 0, h, 300, LINEAR)], z);
  return spec([part("x", -way * w, 0, 300, LINEAR)], [part("x", 0, way * w, 300, LINEAR)], z);
}

/**
 * Pages move side by side, as the list's two panes do when switched: the new one pushes in whole from the right and the
 * old goes out whole to the left (and back the other way), nothing fading. Settings (from the gear at the top left)
 * come from the left instead; a new chat rises from the bottom.
 */
function transition(from: Screen, to: Screen, forward: boolean, z: number, rose: boolean, w: number, h: number): Spec {
  const time = 380;
  const slide = (a: number, b: number) => part("x", a, b, 300, STANDARD);
  if (forward && to.kind === "NewChat") return spec([part("y", h, 0, time, ARRIVE)], [fadeOut(time, STANDARD, 0.99)], z);
  // Only the new-chat screen sinks back down; a chat it made returns sideways.
  if (!forward && rose) return spec([fadeIn(1, STANDARD, 0.99)], [part("y", 0, h, time, ARRIVE)], z);
  // Settings are to the left of the list (the gear is at the list's left): they come and go that way.
  if (forward && to.kind === "Settings") return spec([slide(-w, 0)], [slide(0, w)], z);
  if (!forward && from.kind === "Settings") return spec([slide(w, 0)], [slide(0, -w)], z);
  if (forward) return spec([slide(w, 0)], [slide(0, -w)], z);
  return spec([slide(-w, 0)], [slide(0, w)], z);
}

// ── back ───────────────────────────────────────────────────────────────

/** A back gesture's step as the system says it (BackEventCompat): where the finger is (dp across), from which edge. */
interface BackEvent { touchX: number; progress: number; swipeEdge: number }
const EDGE_RIGHT = 1;

interface BackNative {
  setEnabled(enabled: boolean): void;
  addListener(event: "started" | "progressed", listener: (e: BackEvent) => void): { remove(): void };
  addListener(event: "cancelled" | "invoked", listener: () => void): { remove(): void };
}
// NATIVE: the system's predictive back as it goes (an OnBackPressedCallback's handleOnBackStarted / Progressed /
// Cancelled / Pressed with the event's touchX in dp and swipeEdge), as a module `StillfailBack` with setEnabled; React
// Native's BackHandler hears only that back was done. Without it, back is a tapped back (the page goes as tapped).
const StillfailBack = requireOptionalNativeModule<BackNative>("StillfailBack");

/**
 * androidx.activity's PredictiveBackHandler as the pages use it: while `enabled`, the gesture's steps go to `progress`,
 * its end to `done` and its calling off to `cancel` (`begin` as it starts). Without the system's steps (a tapped back,
 * or no module for them), only `begin` and `done`. The last added is asked first, as React Native's BackHandler asks.
 */
function PredictiveBackHandler({ enabled, begin, progress, done, cancel }: { enabled: boolean; begin: () => void; progress: (e: BackEvent) => void; done: () => void; cancel: () => void }) {
  const now = useRef({ enabled, begin, progress, done, cancel });
  now.current = { enabled, begin, progress, done, cancel };
  useEffect(() => { StillfailBack?.setEnabled(enabled); }, [enabled]);
  useEffect(() => {
    let going = false;
    const subs = StillfailBack ? [
      StillfailBack.addListener("started", (e) => { if (!now.current.enabled) return; going = true; now.current.begin(); now.current.progress(e); }),
      StillfailBack.addListener("progressed", (e) => { if (going) now.current.progress(e); }),
      StillfailBack.addListener("cancelled", () => { if (going) { going = false; now.current.cancel(); } }),
      StillfailBack.addListener("invoked", () => {
        if (!going) { if (!now.current.enabled) return; now.current.begin(); }
        going = false;
        now.current.done();
      }),
    ] : [];
    const press = BackHandler.addEventListener("hardwareBackPress", () => {
      if (!now.current.enabled) return false;
      now.current.begin();
      now.current.done();
      return true;
    });
    return () => { press.remove(); for (const s of subs) s.remove(); };
  }, []);
  return null;
}

/** androidx.activity's BackHandler: back while `enabled` runs `onBack`. */
function BackHandlerOf({ enabled, onBack }: { enabled: boolean; onBack: () => void }) {
  const now = useRef({ enabled, onBack });
  now.current = { enabled, onBack };
  useEffect(() => {
    const press = BackHandler.addEventListener("hardwareBackPress", () => {
      if (!now.current.enabled) return false;
      now.current.onBack();
      return true;
    });
    return () => press.remove();
  }, []);
  return null;
}

// ── the pages ──────────────────────────────────────────────────────────

/** A change of page under way: from which page to which (keys), how, and whether it is the finger's (seeked). */
interface Run { id: number; from: string; to: string; spec: Spec }

function useKeyboardUp(): boolean {
  const [up, setUp] = useState(false);
  useEffect(() => {
    const show = Keyboard.addListener("keyboardDidShow", () => setUp(true));
    const hide = Keyboard.addListener("keyboardDidHide", () => setUp(false));
    return () => { show.remove(); hide.remove(); };
  }, []);
  return up;
}

function Pages({ app, current }: { app: AppState; current: WorkspaceEntry }) {
  const stack = useApp((s) => s.stack);
  const sheet = useApp((s) => s.sheet);
  const menu = useApp((s) => s.menu);
  const reader = useApp((s) => s.reader);
  const barAway = useApp((s) => s.barAway);
  useApp((s) => s.madeChat);
  const top = stack[stack.length - 1]!;
  const { width, height } = useWindowDimensions();
  const still = reducedMotion();
  const workspace = current.workspace.id;
  const keyOf = (screen: Screen) => `${workspace}|${app.pageOf(screen)}`;

  // The pages as Compose's SeekableTransitionState has them: the one at rest (`currentState`), the one it goes to
  // (`targetState`), and the change under way between them (`run`, its time `play` in ms, seeked by a swipe).
  const pages = useRef({ currentState: top, targetState: top });
  const [run, setRun] = useState<Run | null>(null);
  const runRef = useRef<Run | null>(null);
  runRef.current = run;
  const [, setRest] = useState(0);
  const play = useSharedValue(0);
  const runs = useRef(0);
  /** Where each page is drawn as it last came in (a page's zIndex is fixed when it comes in, as AnimatedContent keeps it). */
  const zOf = useRef(new Map<string, number>());
  // Swiped back (the system's back gesture, predictive back): the page follows the finger and the one under it shows a
  // little behind (web mobile/app.tsx's own edge swipe); let go, it goes on from there, or back if the system says so.
  const swiped = useRef(false);

  /** The change from the page shown to `to`, as AnimatedContent's transitionSpec says it (`seek`: by the finger). */
  const specFor = (from: Screen, to: Screen): Spec => {
    // Switched on the bar: in place, nothing slides.
    if (app.switched) return placeSwitch(from, to, app.bars, still, 30);
    // Layered by depth in the stack, the deeper page over: a page's zIndex is fixed when it comes in (AnimatedContent
    // keeps the first spec's), so by the way it came it was wrong later (one come back to, then swiped away, went under).
    const st = app.stack;
    let z = 0;
    for (let i = st.length - 1; i >= 0; i--) if (app.pageOf(st[i]!) === app.pageOf(to)) { z = i; break; }
    // Sharing the host keeps the composer in place, but only an unsent new chat exits down.
    const rose = from.kind === "NewChat";
    return swiped.current ? swipe(from.kind === "Settings", z, rose, width, height) : transition(from, to, app.forward, z, rose, width, height);
  };

  const settled = (id: number) => {
    const r = runRef.current;
    if (r == null || r.id !== id) return;
    pages.current.currentState = pages.current.targetState;
    runRef.current = null;
    setRun(null);
  };
  /** Starts the change to `to` (its time from 0), or puts `to` in place at once when it is the same page. */
  const begin = (to: Screen, seeking: boolean): Run | null => {
    const r = runRef.current;
    // Another change while one is under way: from where that one was going.
    const from = r != null ? pages.current.targetState : pages.current.currentState;
    if (r != null) pages.current.currentState = from;
    pages.current.targetState = to;
    if (keyOf(from) === keyOf(to)) {
      // A new chat and the chat it becomes are one page (ChatHost): it stays, rather than slide in again.
      pages.current.currentState = to;
      cancelAnimation(play);
      runRef.current = null;
      setRun(null);
      setRest((n) => n + 1);
      return null;
    }
    const s = specFor(from, to);
    zOf.current.set(keyOf(to), s.z);
    cancelAnimation(play);
    play.value = 0;
    const next: Run = { id: ++runs.current, from: keyOf(from), to: keyOf(to), spec: s };
    runRef.current = next;
    setRun(next);
    if (!seeking) {
      if (s.total <= 0) { settled(next.id); return null; }
      play.value = withTiming(s.total, { duration: s.total, easing: Easing.linear }, (finished) => { if (finished) runOnJS(settled)(next.id); });
    }
    return next;
  };
  /** As SeekableTransitionState.animateTo: to `to` from where it is; `tween`: the seek's own way on from there. */
  const animateTo = (to: Screen, tween: { ms: number } | null) => {
    const r = runRef.current;
    if (tween != null && r != null && r.to === keyOf(to)) {
      pages.current.targetState = to;
      play.value = withTiming(r.spec.total, { duration: tween.ms, easing: Easing.bezier(0.4, 0, 0.2, 1) }, (finished) => { if (finished) runOnJS(settled)(r.id); });
      return;
    }
    begin(to, false);
  };
  const seekTo = (fraction: number, to: Screen) => {
    let r = runRef.current;
    if (r == null || r.to !== keyOf(to)) r = begin(to, true);
    if (r == null) return;
    play.value = fraction * r.spec.total;
  };
  const fraction = () => {
    const r = runRef.current;
    return r == null ? 0 : Math.min(1, Math.max(0, play.value / r.spec.total));
  };
  /** Seeks from `from` to `to` over `ms` (the seek is what the pages draw), then `then`. */
  const seekAlong = (from: number, to: number, ms: number, easing: number, then: () => void) => {
    const r = runRef.current;
    if (r == null) { then(); return; }
    play.value = from * r.spec.total;
    play.value = withTiming(to * r.spec.total, { duration: ms, easing: easing === EASE_OUT ? Easing.bezier(0.25, 0.46, 0.45, 0.94) : Easing.bezier(0.4, 0, 0.2, 1) }, (finished) => { if (finished) runOnJS(then)(); });
  };
  const snapTo = (to: Screen) => {
    cancelAnimation(play);
    pages.current.currentState = to;
    pages.current.targetState = to;
    runRef.current = null;
    setRun(null);
    setRest((n) => n + 1);
  };

  // What is over the pages takes back first: its own handlers say so (each is asked as long as it is there), and this
  // one steps aside while any of them is open.
  const backing = useRef<{ under: Screen | null; start: number | null; following: boolean }>({ under: null, start: null, following: false });
  const overlaid = sheet != null || menu != null || reader != null || FileViewers.open;

  // Each page's topics, followed while it is in the stack (data/Topics.ts: PageTopics); those of the pages gone from it
  // let go, once they are not drawn either (a page going away is drawn until it has).
  const followed = useRef(new Map<string, PageTopics>()).current;
  const topicsOf = (key: string) => {
    let topics = followed.get(key);
    if (!topics) { topics = new PageTopics(); followed.set(key, topics); }
    return topics;
  };
  // A place's top page of this workspace, switched away from on the bar, keeps its state (PLACE_PAGES, below), and its
  // topics: still followed while its place is in one of the bars (coming back, what it shows is there and up to date at
  // once); paused otherwise, what they showed kept, so it comes back drawn as it was left and followed again from
  // there. Any other page's are let go.
  const letGo = (keep: (key: string) => boolean) => {
    for (const key of [...followed.keys()]) {
      if (keep(key)) continue;
      const place = key.startsWith(`${workspace}|`) ? PLACE_OF_PAGE.get(key.slice(workspace.length + 1)) ?? null : null;
      if (place == null) { followed.get(key)?.close(); followed.delete(key); }
      else if (!app.bars.sets.some((set) => set.includes(place))) followed.get(key)?.pause();
    }
  };
  // A page's own state (its scroll place, what is open on it) is kept while it is in the stack, and forgotten once it
  // leaves: a chat closed and opened again starts afresh. Here a page keeps its state by staying mounted, out of sight.
  // The places' top pages keep theirs (where the list was scrolled to), switched away from and back on the bar.
  const kept = useRef(new Set<string>()).current;
  const stackKey = stack.map(keyOf).join("\n");
  useEffect(() => {
    const stacked = new Set(stack.map(keyOf));
    stacked.add(keyOf(pages.current.currentState));
    letGo((k) => stacked.has(k));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stackKey, workspace]);

  // The page on top changed: in as the change says.
  const topKey = JSON.stringify(top);
  useLayoutEffect(() => {
    const ps = pages.current;
    if (sameScreen(ps.currentState, top) && sameScreen(ps.targetState, top) && runRef.current == null) return;
    let live = true;
    // A place switched to on the bar: in place, no slide, at once (the frame after the tap): what it shows is there if
    // it was shown before (its topics kept, above), else it comes in on the page; not waited for (up to LOCAL_MS, which
    // could hold the page back while the ball was on its way).
    if (app.switched) {
      BarTiming.effect();
      const topics = topicsOf(keyOf(top));
      for (const topic of opening(top, workspace)) topics.of(core(), topic);
      BarTiming.snapped(false, false);
      swiped.current = false;
      // In at once, with the switch's own short motion (placeSwitch), not a push's.
      animateTo(top, null);
      return;
    }
    // A page opened slides in once the core has given what it shows, from what is on the device (LOCAL_MS at most, as
    // web mobile/Chat.tsx useReady): not first as its loading look swapped for it a frame or two later. What has to come
    // from a station is not waited for: the page slides in, showing it coming.
    const shows = app.forward && !swiped.current && app.pageOf(top) !== "new-chat" ? opening(top, workspace) : [];
    const go = () => {
      if (!live) return;
      animateTo(top, swiped.current ? { ms: 300 } : null);
      swiped.current = false;
    };
    if (shows.length === 0) { go(); return () => { live = false; }; }
    const topics = topicsOf(keyOf(top));
    const states = shows.map((topic) => topics.of(core(), topic));
    const ready = () => states.every((s) => s.get().value !== undefined || s.get().error != null);
    if (ready()) { go(); return () => { live = false; }; }
    const timer = setTimeout(finish, LOCAL_MS);
    const offs = states.map((s) => s.subscribe(() => { if (ready()) finish(); }));
    function finish() {
      clearTimeout(timer);
      for (const off of offs) off();
      go();
    }
    return () => { live = false; clearTimeout(timer); for (const off of offs) off(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [topKey]);

  // Wider than a phone (screens/Wide.tsx): the pages the screen's whole width, the latest chats and the new-chat button at its corners.
  const wide = width >= WideAt;
  const keyboardUp = useKeyboardUp();
  const root = stack.length === 1 ? stack[0]! : null;

  // The pages drawn: those in the stack, the one going, and the places' top pages switched away from, each kept
  // mounted (out of sight) while it is so; in the order they first came, each drawn at its depth.
  const order = useRef<string[]>([]);
  const screens = useRef(new Map<string, Screen>()).current;
  const mounted = new Set<string>();
  for (const s of stack) { const k = keyOf(s); mounted.add(k); screens.set(k, s); }
  const shownKeys = [keyOf(pages.current.currentState), ...(run ? [run.from, run.to] : [])];
  for (const k of shownKeys) mounted.add(k);
  if (!screens.has(keyOf(pages.current.currentState))) screens.set(keyOf(pages.current.currentState), pages.current.currentState);
  for (const k of [...kept]) if (k.startsWith(`${workspace}|`)) mounted.add(k); else kept.delete(k);
  for (const k of mounted) if (PLACE_PAGES.has(k.slice(workspace.length + 1))) kept.add(k);
  order.current = [...order.current.filter((k) => mounted.has(k)), ...[...mounted].filter((k) => !order.current.includes(k))];
  for (const k of [...screens.keys()]) if (!mounted.has(k)) screens.delete(k);

  return (
    <View style={{ flex: 1 }}>
      {/* Back first, so what is drawn after it (the bar's panel) is asked before it. */}
      <PredictiveBackHandler
        enabled={stack.length > 1 && !overlaid}
        begin={() => { backing.current = { under: app.stack[app.stack.length - 2] ?? null, start: null, following: false }; }}
        progress={(e) => {
          const b = backing.current;
          // Only from a page at rest (not while one still moves in); by the finger's own way from where it began.
          if (b.under == null || (runRef.current != null && !b.following)) return;
          const x0 = b.start ?? (b.start = e.touchX);
          const dx = e.swipeEdge === EDGE_RIGHT ? x0 - e.touchX : e.touchX - x0;
          if (!b.following) { swiped.current = true; b.following = true; }
          seekTo(Math.min(1, Math.max(0, dx / Math.max(1, width))), b.under);
        }}
        done={() => {
          const b = backing.current;
          // Let go: on from where the finger left it at once, moving as it was (out, easing to rest), and only then off
          // the stack. Popping first waited for the pages to render again, then started from still: a stop where the
          // finger let go. Not called off once let go (another swipe meanwhile would run it backwards).
          if (b.following && b.under != null) {
            const under = b.under;
            const from = fraction();
            seekAlong(from, 1, Math.max(120, 280 * (1 - from)), EASE_OUT, () => {
              snapTo(under);
              swiped.current = false;
              app.pop();
            });
            return;
          }
          app.pop();
        }}
        cancel={() => {
          const b = backing.current;
          // Called off: back along the same way (the seek run backwards to 0, 200ms), then at rest on the page again.
          if (b.following && b.under != null) {
            seekAlong(fraction(), 0, 200, STANDARD, () => {
              snapTo(app.stack[app.stack.length - 1]!);
              swiped.current = false;
            });
          }
        }}
      />
      {/*
        A place's top page other than the chats, with nothing over it: back goes to the chats (the app's first place), in
        place as the bar switches, rather than out of the app.
      */}
      <BackHandlerOf enabled={root != null && root.kind !== "Home" && placeOf(root) != null && !overlaid} onBack={() => app.place({ kind: "Home" })} />
      {/* A view of its own (not flattened into its parent): the pages' zIndex orders them among themselves, not over the bar. */}
      <View style={{ flex: 1 }} collapsable={false}>
        <LocalWide.Provider value={wide}>
          {order.current.map((key) => {
            const screen = screens.get(key);
            if (screen == null) return null;
            const role: Role = run ? (key === run.to ? "in" : key === run.from ? "out" : "hidden") : key === keyOf(pages.current.currentState) ? "rest" : "hidden";
            const parts = run == null ? null : role === "in" ? run.spec.enter : role === "out" ? run.spec.exit : null;
            const z = zOf.current.get(key) ?? 0;
            return (
              <PageView
                key={key} pageKey={key} app={app} current={current} screen={screen} role={role} parts={parts} play={play} width={width}
                zIndex={role === "hidden" ? 0 : 1 + z * 2 + (role === "in" ? 1 : 0)} wide={wide} topics={topicsOf(key)}
                inStack={stack.some((s) => sameScreen(s, screen))} isRoot={stack.length > 0 && sameScreen(stack[0], screen)}
                letGoOf={() => { if (!app.stack.some((s) => keyOf(s) === key)) letGo((k) => k !== key); }}
              />
            );
          })}
        </LocalWide.Provider>
      </View>
      {/* The bottom bar (Places.tsx): a phone's, on a place's top page with nothing over it; the keyboard up (a field on the page): out of its way. */}
      {!wide ? <PlaceBar app={app} current={current} haze={null} shown={root != null && placeOf(root) != null && !keyboardUp && !barAway} /> : null}
      {wide ? <WideCorners current={current} top={top} /> : null}
    </View>
  );
}

type Role = "in" | "out" | "rest" | "hidden";

/**
 * One page of the stack, drawn where its change has it (or out of sight, kept): its topics, what it is to the bar, the
 * room it keeps for the bar, and the paper behind the status bar.
 */
const PageView = memo(function PageView({
  pageKey, app, current, screen, role, parts, play, width, zIndex, wide, topics, inStack, isRoot, letGoOf,
}: {
  pageKey: string; app: AppState; current: WorkspaceEntry; screen: Screen; role: Role; parts: Part[] | null; play: SharedValue<number>;
  width: number; zIndex: number; wide: boolean; topics: PageTopics; inStack: boolean; isRoot: boolean; letGoOf: () => void;
}) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const shown = role !== "hidden";
  useEffect(() => { topics.drawn = shown; }, [topics, shown]);
  useEffect(() => () => { topics.drawn = false; letGoOf(); }, [pageKey]); // eslint-disable-line react-hooks/exhaustive-deps
  // A place's top page: no back with the bar under it (room kept for the bar at its foot); on a wide screen, which has
  // no bar, back to the chats. A page going (switched away from on the bar, still drawn until the one coming has what it
  // shows) stays as it was: not a pushed page all at once, its back showing and its foot's room gone for a moment.
  const now = !isRoot || placeOf(screen) == null ? PlaceRoot.None : wide ? PlaceRoot.Wide : PlaceRoot.Bar;
  const held = useRef(now);
  if (inStack) held.current = now;
  const placeRoot = held.current;
  BarTiming.page(screen);
  const look = useAnimatedStyle(() => {
    if (role === "hidden") return { opacity: 0, transform: [{ translateX: width * 2 }, { translateY: 0 }] };
    if (parts == null) return { opacity: 1, transform: [{ translateX: 0 }, { translateY: 0 }] };
    const at = sample(parts, play.value);
    return { opacity: at.alpha, transform: [{ translateX: at.x }, { translateY: at.y }] };
  }, [role, parts, width]);
  return (
    <Animated.View
      style={[StyleSheet.absoluteFill, { zIndex, backgroundColor: C.bg }, look]}
      pointerEvents={shown ? "auto" : "none"}
      importantForAccessibility={shown ? "auto" : "no-hide-descendants"}
      collapsable={false}
    >
      <LocalPageTopics.Provider value={topics}>
        <LocalPlaceRoot.Provider value={placeRoot}>
          <LocalBarRoom.Provider value={placeRoot !== PlaceRoot.Bar ? 0 : BAR_ROOM}>
            <PageContent screen={screen} current={current} />
            {/*
              The page scrolls under the status bar; it keeps the paper behind its icons, moving with its page (the list, a
              place's top page with the bar and a chat have frosted bars there instead, which show what runs under them). A
              book and a film draw their own paper (or black) there.
            */}
            {screen.kind !== "Home" && placeRoot !== PlaceRoot.Bar && screen.kind !== "Chat" && screen.kind !== "NewChat" && screen.kind !== "DriveRead" && screen.kind !== "DrivePlay"
              ? <View pointerEvents="none" style={{ position: "absolute", left: 0, right: 0, top: 0, height: insets.top, backgroundColor: C.bg }} />
              : null}
          </LocalBarRoom.Provider>
        </LocalPlaceRoot.Provider>
      </LocalPageTopics.Provider>
    </Animated.View>
  );
});

/** What a page of the stack is. */
function PageContent({ screen, current }: { screen: Screen; current: WorkspaceEntry }): ReactNode {
  switch (screen.kind) {
    case "Home": return <LockGate current={current}><HomeScreen current={current} /></LockGate>;
    case "Chat": case "NewChat": return <ChatHost current={current} screen={screen} />;
    case "Stations": return <StationsScreen current={current} />;
    case "Station": return <StationScreen current={current} address={screen.address} />;
    case "AdbShare": return <AdbShareScreen current={current} address={screen.address} />;
    case "Profile": return <ProfileScreen current={current} address={screen.address} id={screen.profile} />;
    case "History": return <HistoryScreen station={screen.station} of={screen.of} sessionKey={screen.key} entry={screen.entry ?? null} />;
    case "RunSettings": return <RunSettingsScreen station={screen.station} of={screen.of} sessionKey={screen.key} />;
    case "Me": return <MeScreen current={current} />;
    case "Settings": return <SettingsScreen current={current} />;
    case "Appearance": return <AppearanceScreen />;
    case "KeptFiles": return <KeptFilesScreen />;
    case "KeptChat": return <KeptChatScreen station={screen.station} thread={screen.thread} />;
    case "Changelog": return <ChangelogScreen />;
    case "Connects": return <ConnectsScreen current={current} only={screen.station ?? null} />;
    case "Profiles": return <ProfilesScreen current={current} only={screen.station ?? null} />;
    case "ProfileAccount": return <ProfileAccountScreen current={current} accountKey={screen.key} />;
    case "AutomaticDecisions": return <AutomaticDecisionsScreen />;
    case "AutomaticDecisionCompletion": return <AutomaticDecisionCompletionScreen current={current} />;
    case "AutomaticDecisionPolicy": return <AutomaticDecisionPolicyScreen current={current} station={screen.station} />;
    case "Memories": return <MemoriesScreen current={current} />;
    case "Usage": return <UsageScreen current={current} />;
    case "UsagePrices": return <UsagePricesScreen current={current} days={screen.days} />;
    case "Workspace": return <WorkspaceScreen current={current} />;
    case "Security": return <SecurityScreen current={current} />;
    case "SecurityOpen": return <SecurityOpenScreen current={current} />;
    case "Vault": return <VaultScreen current={current} />;
    case "VaultItem": return <VaultItemScreen current={current} vault={screen.vault} item={screen.item} />;
    case "Preview": return <PreviewScreen station={screen.station} service={screen.job} />;
    case "PreviewFile": return <PreviewFileScreen station={screen.station} session={screen.session} path={screen.path} name={screen.name} />;
    case "Connect": return <ConnectScreen station={screen.station} id={screen.connect} />;
    case "ConnectRun": return <ConnectRunScreen station={screen.station} id={screen.connect} />;
    case "NewConnect": return <NewConnectScreen station={screen.station} />;
    case "NewProfile": return <NewProfileScreen current={current} address={screen.station} />;
    case "Archive": return <ArchiveScreen current={current} />;
    case "Decisions": return <DecisionsScreen current={current} />;
    case "Files": return <FilesScreen current={current} />;
    case "BarSettings": return <BarSettingsScreen />;
    case "Memory": return <MemoryScreen current={current} address={screen.station} />;
    case "MemoryDoc": return <MemoryDocScreen current={current} address={screen.station} skill={screen.skill} at={screen.at ?? 0} />;
    case "SlackApp": return <SlackAppScreen station={screen.station} connect={screen.connect} />;
    case "Drive": return <DriveScreen current={current} station={screen.station} root={screen.root} path={screen.path} />;
    case "DriveRead": return <ReaderScreen station={screen.station} root={screen.root} path={screen.path} />;
    case "DrivePlay": return <PlayerScreen station={screen.station} root={screen.root} path={screen.path} />;
  }
}

