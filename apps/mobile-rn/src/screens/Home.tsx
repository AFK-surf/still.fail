// Home is the `chats` view as the web's sidebar lists it: one kind of item (an agent with its chat, or an agent with no
// chat yet), newest first and grouped by day. A fixed head (settings · workspace · the filter · stations); at the bottom
// the bar of places floats over it (ui/Bar.tsx: 奏 and 令 are there).
import * as Haptics from "expo-haptics";
import { createContext, useContext, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { Platform, Pressable, StyleSheet, View, useWindowDimensions, type LayoutChangeEvent, type PressableProps, type StyleProp, type TextLayoutEventData, type NativeSyntheticEvent, type ViewStyle } from "react-native";
import { FlatList, Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, {
  Easing, cancelAnimation, interpolateColor, runOnJS, useAnimatedReaction, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withSpring, withTiming,
} from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Circle, Path } from "react-native-svg";
import type { ChatItem, ChatsView, StatusView, WorkspaceMarksView } from "../../../../web/src/core/shapes.ts";
import { usePrefs } from "../../../../web/src/prefs.ts";
import { MenuItem, MenuSpec, app, useApp, type AppState } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { Topics, page, rememberTopic, type TopicState } from "../data/Topics";
import { t } from "../i18n";
import { LocalBarRoom } from "../Places";
import { DoingMark } from "../ui/Controls";
import { Illustration } from "../ui/Drawing";
import { Icon, Icons } from "../ui/Icon";
import { Ease, MoveSpring } from "../ui/Motion";
import { NavButton, SectionHeader, SlackMark, StationMark, hasStationMark, reducedMotion } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { StationGlyph, glyphCounts } from "../ui/StationGlyph";
import { doneLead, waitLead } from "../ui/StatusText";
import { T } from "../ui/Text";
import { lerpColor, useC, withAlpha } from "../ui/Theme";
import { Waiting } from "../ui/Waiting";
import { ChangelogNews } from "./Changelog";
import { askTitle } from "./ChatInfo";
import { chatLink, copyChatLink } from "./ChatLink";
import { ArriveEasing, CssEaseOut, Ghost, HeldOrder, LEAVE_MS, ListMotion, MarksSeen, dayKey, rowKey } from "./ListMotion";
import { OpenJobs } from "./OpenJobs";
import { SettingsGear, TopBarTitle, TopGlassBar } from "./PlacePage";
import { RowAside } from "./RowPicture";
import { SearchField, SearchPage } from "./Search";
import { MarkBlue, MarkRed, WorkspaceMark } from "./SettingParts";
import { FirstStation, confirm } from "./Settings";
import { invitationsWaiting, openWorkspaces } from "./Workspaces";
import { Quiet } from "../ui/Quiet";

type Filter = "all" | "mine" | "watching";

/** A tap's ripple, as Compose's clickable draws it (the content colour, faint). */
const ripple = (ink: string) => ({ color: withAlpha(ink, 0.1), borderless: false });

/** Android's touch slop (ViewConfiguration), in dp: what a finger moves before it is a drag. */
const TOUCH_SLOP = 8;
/** Android's long press timeout (ViewConfiguration), which Compose's detectTapGestures waits. */
const LONG_PRESS_MS = 400;

export function HomeScreen({ current }: { current: WorkspaceEntry }) {
  const C = useC();
  const scope = current.workspace.id;
  // The lists (all, mine, watching) are followed at once, side by side: switching slides from one to another with
  // nothing to wait for.
  const all = rememberTopic<ChatsView>(Topics.chats(scope, false));
  const mine = rememberTopic<ChatsView>(Topics.chats(scope, true));
  const watching = rememberTopic<ChatsView>(Topics.chats(scope, false, true));
  const filter = usePrefs(() => app.chatFilter(scope));
  const at = (f: Filter) => (f === "mine" ? 1 : f === "watching" ? 2 : 0);
  const shift = useSharedValue(at(filter));
  useEffect(() => {
    shift.value = withTiming(at(filter), { duration: 240, easing: Ease.Standard });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter]);
  const insets = useSafeAreaInsets();
  // The top bar's height kept with the page: coming back to the list, it is laid out with it at once, so a list left at
  // its end is not first clamped short of it (with no room under the bars) and stays there. The first time, the top
  // bar as it is laid out (the status bar, 8 + 34 + 8dp) rather than none: a note at the list's top is not drawn under
  // the bar until it has been measured (which a busy start can take a while to do).
  const [topBar, setTopBar] = useState(insets.top + 50);
  // At the foot, room for the bottom bar (App.tsx Pages: none on a wide screen, whose corners have 奏 and 令).
  const room = useContext(LocalBarRoom);
  const foot = room > 0 ? insets.bottom + room : 8;
  const padding = { top: topBar + 8, bottom: foot };
  // Searching (Search.tsx): where the field at the list's top was when tapped, and how wide. The lists go up and away,
  // the bars fade.
  const [searchFrom, setSearchFrom] = useState<number | null>(null);
  const [searchWidth, setSearchWidth] = useState(0);
  // Away while the search is open; as it closes the lists come back in the same 240 ms as its field goes back, so the
  // field lands where the list's is, together (not the field first, then the list coming down a second time).
  const [searchOpen, setSearchOpen] = useState(false);
  const away = useSharedValue(0);
  useEffect(() => {
    away.value = withTiming(searchOpen ? 1 : 0, { duration: searchOpen ? 280 : 240, easing: searchOpen ? Ease.Arrive : Ease.Standard });
    // The bottom bar out of the search's way while it is open.
    app.barAway = searchOpen;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchOpen]);
  useEffect(() => () => { app.barAway = false; }, []);
  const awayBy = 56;
  const window = useWindowDimensions();
  const [width, setWidth] = useState(window.width);
  const listsStyle = useAnimatedStyle(() => ({ transform: [{ translateY: -awayBy * away.value }], opacity: 1 - away.value }));
  const barStyle = useAnimatedStyle(() => ({ opacity: 1 - away.value }));
  const onSearch = (top: number, wide: number) => { setSearchFrom(top); setSearchWidth(wide); setSearchOpen(true); };
  const searching = searchFrom !== null;

  const marks = rememberTopic<WorkspaceMarksView>(Topics.workspaceMarks(current.workspace.id));
  const others = marks.value?.others;
  const invited = invitationsWaiting(app);
  // A newer build of the app that brings something the changelog says (one that does not waits in the settings until
  // one does): tapped, it is downloaded and handed to the installer (Updates.ts).
  const updates = useApp(() => app.updates);
  const filterButton = useRef<View>(null);
  // The stations at a glance (ui/StationGlyph.tsx); its page says which is which. The core reaching nothing at all
  // (`status` in trouble) puts it to sleep. Only on a wide screen: under the bottom bar they are a place of it
  // (Places.tsx PlaceBar), drawn and said the same.
  const status = rememberTopic<StatusView>(room === 0 ? Topics.status(scope) : null);

  return (
    <View style={{ flex: 1 }}>
      <Animated.View style={[StyleSheet.absoluteFill, { overflow: "hidden" }, listsStyle]} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
        <ChatPane current={current} chats={all} filter="all" padding={padding} onSearch={onSearch} searching={searching} index={0} shift={shift} width={width} />
        <ChatPane current={current} chats={mine} filter="mine" padding={padding} onSearch={onSearch} searching={searching} index={1} shift={shift} width={width} />
        <ChatPane current={current} chats={watching} filter="watching" padding={padding} onSearch={onSearch} searching={searching} index={2} shift={shift} width={width} />
      </Animated.View>
      {/* The top bar (PlacePage.tsx has every place's page wear it too). */}
      <Animated.View style={[{ position: "absolute", left: 0, top: 0, right: 0 }, barStyle]} onLayout={(e) => setTopBar(e.nativeEvent.layout.height)}>
        <TopGlassBar>
          {/* Settings, at the top left (SettingsHome.tsx): the account, the workspace's things, this device's. */}
          <SettingsGear />
          <Smooth radius={8} style={{ flex: 1, minWidth: 0 }}>
            <Pressable onPress={() => openWorkspaces(app)} android_ripple={ripple(C.ink)} style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
              <TopBarTitle text={current.workspace.name} style={{ flexShrink: 1, minWidth: 0 }} />
              {/* The other workspaces have something waiting: its dot by the name, before an invitation's. */}
              {others != null ? (
                <WorkspaceMark tone={others} label={marks.value?.othersLabel ?? ""} />
              ) : invited ? (
                <View accessible accessibilityLabel={t("android-chat.home.invited")} style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: C.accent }} />
              ) : null}
              <Icon icon={Icons.ChevronDown} size={16} color={C.muted} />
            </Pressable>
          </Smooth>
          {(updates.progress != null || (updates.available?.news ?? []).length > 0) && (
            // Quiet like the bar's other buttons: the icon with a dot; while it downloads, how far it is instead.
            updates.progress != null ? (
              <T size={13} color={C.muted} numberOfLines={1} accessibilityLabel={updates.progress}>{after(updates.progress, " ", "…")}</T>
            ) : (
              <View accessible accessibilityLabel={t("android-chat.home.update", { version: updates.available?.versionName ?? "" })}>
                <NavButton icon={Icons.Download} onClick={() => { void updates.install().then((said: string | null) => { if (said) app.toast = said; }); }} iconSize={20} />
                <View pointerEvents="none" style={{ position: "absolute", right: 3, top: 3, width: 13, height: 13, borderRadius: 6.5, backgroundColor: C.bg, padding: 2 }}>
                  <View style={{ flex: 1, borderRadius: 4.5, backgroundColor: C.accent }} />
                </View>
              </View>
            )
          )}
          {/* The filter, and the archive in its menu, as on the wide screen (web mobile/Home.tsx FilterButton): nothing to
              narrow or look back on with no station. The accent while it narrows the list. */}
          {(all.value?.stations.length ?? 0) > 0 && (
            <View ref={filterButton} collapsable={false} style={{ width: 34, height: 34, borderRadius: 17, overflow: "hidden" }}>
              <Pressable
                accessibilityLabel={t("android-chat.home.filter.label", { filter: filter === "mine" ? t("android-chat.home.filter.mine") : filter === "watching" ? t("android-chat.home.filter.watching") : t("android-chat.home.filter.all") })}
                android_ripple={ripple(C.ink)}
                style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
                onPress={() => filterButton.current?.measureInWindow((x, y, w, h) => {
                  // The menu is 180 wide (Sheet.tsx MenuHost): its right edge under the button's.
                  const left = x + w - 180;
                  app.menu = new MenuSpec({ left, top: y, right: left, bottom: y + h }, [
                    new MenuItem(t("android-chat.home.filter.all"), filter === "all" ? Icons.Check : null, () => app.showChats(scope, "all")),
                    new MenuItem(t("android-chat.home.filter.mine"), filter === "mine" ? Icons.Check : null, () => app.showChats(scope, "mine")),
                    new MenuItem(t("android-chat.home.filter.watching"), filter === "watching" ? Icons.Check : null, () => app.showChats(scope, "watching")),
                    new MenuItem(t("android-chat.home.filter.archived"), Icons.Archive, () => app.push({ kind: "Archive" })),
                  ]);
                })}
              >
                <Icon icon={Icons.Filter} size={20} color={filter !== "all" ? C.accent : C.ink} />
              </Pressable>
            </View>
          )}
          {room === 0 && <StationsButton all={all.value} status={status.value} />}
        </TopGlassBar>
      </Animated.View>
      {searchFrom !== null && (
        <SearchPage scope={scope} from={searchFrom} wide={searchWidth} onLeave={() => setSearchOpen(false)} onClose={() => setSearchFrom(null)} />
      )}
    </View>
  );
}

/** Kotlin's substringAfter(delimiter, missing): what follows the first `delimiter`, else `missing`. */
function after(text: string, delimiter: string, missing: string): string {
  const at = text.indexOf(delimiter);
  return at < 0 ? missing : text.substring(at + delimiter.length);
}

/** The stations' glyph in the top bar (wide screens), to their page. */
function StationsButton({ all, status }: { all: ChatsView | undefined; status: StatusView | undefined }) {
  const C = useC();
  const counts = glyphCounts(all ?? null, status?.state === "trouble");
  // Asleep, what the core cannot reach says it; else the stations in words (the core's), and what is wrong with them.
  const said = counts.asleep ? status?.text ?? "" : all?.glyph?.label ?? "";
  const label = all?.trouble ? t("android-chat.home.stations.trouble", { said, trouble: all.trouble.text }) : t("android-chat.home.stations", { said });
  return (
    <Pressable
      onPress={() => app.push({ kind: "Stations" })}
      accessibilityLabel={label}
      android_ripple={ripple(C.ink)}
      style={{ width: 34, height: 34, borderRadius: 17, overflow: "hidden", alignItems: "center", justifyContent: "center" }}
    >
      <StationGlyph counts={counts} />
    </Pressable>
  );
}

// ── one list ─────────────────────────────────────────────────────────

type PaneItem =
  | { key: "search"; kind: "search" }
  | { key: "changelog-news"; kind: "news" }
  | { key: "wait"; kind: "wait" }
  | { key: "empty"; kind: "empty" }
  | { key: "open-jobs"; kind: "jobs" }
  | { key: string; kind: "day"; label: string }
  | { key: string; kind: "row"; item: ChatItem };

/** What a list's rows share of it, for the cells that place them (FlatList draws its cells itself). */
interface Pane { motion: ListMotion; still: boolean; sizes: Map<string, number> }
const PaneContext = createContext<Pane | null>(null);

/**
 * One of the lists, all, the viewer's or the watching ones: its states (connecting, failing, empty) and its days; an
 * offline station's chats say so row by row. `index` is its place side by side, `shift` the filter's slide.
 */
function ChatPane({ current, chats, filter, padding, onSearch, searching, index, shift, width }: {
  current: WorkspaceEntry; chats: TopicState<ChatsView>; filter: Filter; padding: { top: number; bottom: number };
  onSearch: (top: number, wide: number) => void; searching: boolean; index: number; shift: { value: number }; width: number;
}) {
  const view = chats.value;
  // The rows move as the list changes (ListMotion.tsx); while a finger is on the list or it scrolls, they keep their
  // places (the web holds them while the mouse is over the list), and move when it is let go.
  const still = reducedMotion();
  const motion = useMemo(() => new ListMotion(), [current.workspace.id]);
  const order = useMemo(() => new HeldOrder(), [current.workspace.id]);
  const sizes = useMemo(() => new Map<string, number>(), [current.workspace.id]);
  useSyncExternalStore(motion.subscribe, motion.version);
  const [pressed, setPressed] = useState(false);
  const [scrolling, setScrolling] = useState(false);
  const settle = useRef<ReturnType<typeof setTimeout> | null>(null);
  const viewport = useRef(0);
  const hold = pressed || scrolling;
  const days = view?.days
    ? (() => {
        for (const day of view.days) for (const item of day.items) MarksSeen.note(rowKey(item), rowTone(item));
        return order.of(view.days, hold);
      })()
    : [];
  // The keys on screen now: only those leave by a copy.
  const visible = new Set<string>();
  for (const [key, y] of motion.placed) {
    const h = sizes.get(key) ?? 0;
    if (y + h > motion.offset && y < motion.offset + viewport.current) visible.add(key);
  }
  motion.update(days, visible, still);
  // Each workspace's lists start at their top, not where the one switched from was scrolled to: their first row, with
  // the search above it there once scrolled to (as the list first read, which the search comes in over).
  const [top] = useState(() => (view != null && view.note?.empty !== true ? SEARCH_HEIGHT : 0));
  const paneStyle = useAnimatedStyle(() => ({ transform: [{ translateX: (index - shift.value) * width }] }));

  const items: PaneItem[] = [];
  // The search (Search.tsx), at the list's top: there once the list is scrolled to it.
  if (view != null && view.note?.empty !== true) items.push({ key: "search", kind: "search" });
  // What the last update brought (Changelog.tsx), until it is seen: even while the list is being read.
  items.push({ key: "changelog-news", kind: "news" });
  if (view == null) items.push({ key: "wait", kind: "wait" });
  else {
    // A station's link coming back is said on its rows; only with no rows to show does the list say it (the core's
    // `note`): what it waits on over the rows to come, or the stations it cannot read over faded ones.
    const note = view.note;
    const waiting = note?.reading === true;
    if (waiting || (note?.failing.length ?? 0) > 0) items.push({ key: "wait", kind: "wait" });
    if (note?.empty === true) items.push({ key: "empty", kind: "empty" });
    // What is left up a long while on the stations (OpenJobs.tsx): nothing while there is none.
    items.push({ key: "open-jobs", kind: "jobs" });
    for (const day of days) {
      items.push({ key: dayKey(day), kind: "day", label: day.label });
      for (const item of day.items) items.push({ key: rowKey(item), kind: "row", item });
    }
  }
  const note = view?.note;
  const waiting = note?.reading === true;
  // Starting past the search field (Kotlin's LazyListState(1)): Android's list takes no first offset (contentOffset is
  // iOS's), so it is scrolled there once it has rows.
  const list = useRef<FlatList<PaneItem>>(null);
  const placed = useRef(false);
  // Asked again as its rows come (the first ones may not fill the screen, the offset then cut short), until it is there
  // or a finger has moved it.
  const place = () => {
    if (placed.current || view == null || items.length === 0 || view.note?.empty === true) return;
    // The frame after: the list takes no offset before its rows are laid out.
    requestAnimationFrame(() => list.current?.scrollToOffset({ offset: SEARCH_HEIGHT, animated: false }));
  };

  return (
    <Animated.View
      style={[{ position: "absolute", top: 0, bottom: 0, left: 0, width }, paneStyle]}
      onTouchStart={() => setPressed(true)}
      onTouchEnd={(e) => { if (e.nativeEvent.touches.length === 0) setPressed(false); }}
      onTouchCancel={() => setPressed(false)}
    >
      {/* Rows gone, each drawn where it was as it goes, under the rows closing over it. */}
      {view != null && motion.ghosts.map((g) => <Leaving key={`${g.key}@${g.at}`} g={g} view={view} motion={motion} />)}
      <PaneContext.Provider value={{ motion, still, sizes }}>
        <FlatList
          ref={list}
          style={StyleSheet.absoluteFill}
          data={items}
          onContentSizeChange={place}
          keyExtractor={(i) => i.key}
          extraData={hold}
          contentOffset={{ x: 0, y: top }}
          contentContainerStyle={{ paddingTop: padding.top, paddingBottom: padding.bottom }}
          CellRendererComponent={Cell}
          scrollEventThrottle={16}
          onLayout={(e) => { viewport.current = e.nativeEvent.layout.height; }}
          onScroll={(e) => { motion.offset = e.nativeEvent.contentOffset.y; if (motion.offset >= SEARCH_HEIGHT - 1) placed.current = true; }}
          onScrollBeginDrag={() => { placed.current = true; if (settle.current) clearTimeout(settle.current); setScrolling(true); }}
          onScrollEndDrag={() => {
            // A fling goes on by itself (its momentum begins at once); let go still, the scroll is over.
            if (settle.current) clearTimeout(settle.current);
            settle.current = setTimeout(() => setScrolling(false), 50);
          }}
          onMomentumScrollBegin={() => { if (settle.current) clearTimeout(settle.current); setScrolling(true); }}
          onMomentumScrollEnd={() => setScrolling(false)}
          renderItem={({ item: i }) => {
            switch (i.kind) {
              case "search": return <SearchField onOpen={onSearch} hidden={searching} />;
              case "news": return <ChangelogNews />;
              // Not even the stations known yet: the rows to come, and what is wrong if the list cannot be read (ui/Waiting.tsx).
              case "wait": return view == null ? <Waiting text={t("android-chat.home.loading")} error={chats.error?.message ?? null} /> : <Waiting count={waiting ? 7 : 4} text={t("android-chat.home.loading")} note={note ?? null} />;
              case "empty": return view ? <Empty current={current} view={view} filter={filter} /> : null;
              case "jobs": return <OpenJobs scope={current.workspace.id} />;
              case "day": return <Moving motion={motion} rowKey={i.key} still={still}><SectionHeader title={i.label} /></Moving>;
              case "row": return view ? <Moving motion={motion} rowKey={i.key} still={still}><ChatRow item={i.item} view={view} motion={motion} /></Moving> : null;
            }
          }}
        />
      </PaneContext.Provider>
    </Animated.View>
  );
}

/** The search's row at a list's top: its field and the room under it (Search.tsx: 38 + 6). */
const SEARCH_HEIGHT = 44;

/**
 * A list's cell: a row or day heading is placed by the list's motion (its layout transition: from where it was to where
 * it is, ListMotion.placement), over the rest while it overtakes them on its way up; it says where it is laid out.
 */
function Cell({ item, style, onLayout, children }: { item: PaneItem; style?: StyleProp<ViewStyle>; onLayout?: (e: LayoutChangeEvent) => void; children?: ReactNode }) {
  const pane = useContext(PaneContext)!;
  const moving = item.kind === "day" || item.kind === "row";
  const key = item.key;
  const lifting = moving && !pane.still && pane.motion.liftedAt(key) !== null;
  const layout = (e: LayoutChangeEvent) => {
    onLayout?.(e);
    if (!moving) return;
    pane.motion.placed.set(key, e.nativeEvent.layout.y);
    pane.sizes.set(key, e.nativeEvent.layout.height);
  };
  return (
    <Animated.View style={[style, { zIndex: lifting ? 1 : 0 }]} onLayout={layout} layout={moving && !pane.still ? pane.motion.placement(key) : undefined}>
      {children}
    </Animated.View>
  );
}

/**
 * A row (or day heading) of the list as it moves (its cell places it): growing in when new, and on a ground of its own
 * over the rest when it overtakes them on its way up (web: listMotion.ts).
 */
function Moving({ motion, rowKey: key, still, children }: { motion: ListMotion; rowKey: string; still: boolean; children: ReactNode }) {
  const C = useC();
  const [arrives] = useState(() => !still && motion.arriving(key));
  const arrive = useSharedValue(arrives ? 0 : 1);
  useEffect(() => {
    if (arrives) arrive.value = withDelay(100, withTiming(1, { duration: 240, easing: ArriveEasing }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const lift = motion.liftedAt(key);
  const raise = useSharedValue(1);
  useEffect(() => {
    if (lift === null) return;
    raise.value = 0;
    raise.value = withTiming(1, { duration: 480, easing: Easing.linear }, () => runOnJS(drop)(key, lift));
    return () => motion.dropLift(key, lift);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lift]);
  const drop = (k: string, l: number) => motion.dropLift(k, l);
  const lifting = lift !== null && !still;
  const ground = lerpColor(C.bg, C.ink, 0.06);
  const grown = useAnimatedStyle(() => ({ opacity: arrive.value, transform: [{ scale: 0.9 + 0.1 * arrive.value }] }));
  // Held to 60 %, then fading as it arrives (the web's keyframes: ground, ground at 0.6, transparent).
  const raised = useAnimatedStyle(() => {
    const p = raise.value;
    return { opacity: p < 0.6 ? 1 : 1 - (p - 0.6) / 0.4 };
  });
  return (
    <Animated.View style={grown}>
      {lifting && <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: ground }, raised]} />}
      {children}
    </Animated.View>
  );
}

/** A row gone from the list: a copy of it where it was shrinks and fades (200 ms, ease-out), then is dropped. */
function Leaving({ g, view, motion }: { g: Ghost; view: ChatsView; motion: ListMotion }) {
  const p = useSharedValue(0);
  useEffect(() => {
    p.value = withTiming(1, { duration: LEAVE_MS, easing: CssEaseOut }, () => runOnJS(drop)());
    return () => { cancelAnimation(p); motion.dropGhost(g); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const drop = () => motion.dropGhost(g);
  const style = useAnimatedStyle(() => ({ opacity: 1 - p.value, transform: [{ scale: 1 - 0.1 * p.value }] }));
  return (
    <Animated.View
      pointerEvents="none"
      importantForAccessibility="no-hide-descendants"
      accessibilityElementsHidden
      style={[{ position: "absolute", left: 0, right: 0, top: g.y }, style]}
    >
      {g.item ? <ChatRow item={g.item} view={view} live={false} /> : g.label ? <SectionHeader title={g.label} /> : null}
    </Animated.View>
  );
}

function Empty({ current, view, filter }: { current: WorkspaceEntry; view: ChatsView; filter: Filter }) {
  const C = useC();
  // No station yet: nothing else works, so adding the first one is the page.
  if (view.stations.length === 0 && filter === "all") return <FirstStation current={current} />;
  return (
    <View style={{ paddingHorizontal: 30, paddingVertical: 20, alignItems: "center", gap: 8 }}>
      <Illustration light="illus_new_chat" dark="illus_new_chat_dark" width={240} />
      {filter === "mine" ? (
        <T size={14} color={C.muted}>{t("android-chat.home.empty.mine")}</T>
      ) : filter === "watching" ? (
        <T size={14} color={C.muted}>{t("android-chat.home.empty.watching")}</T>
      ) : (
        <>
          <T size={14} color={C.muted} align="center">{view.stations.length > 1 ? t("android-chat.home.empty.many") : t("android-chat.home.empty.one")}</T>
          <Pressable onPress={() => app.push({ kind: "NewChat" })} android_ripple={ripple(C.ink)}>
            <T size={14} color={C.accent}>{t("android-chat.newChat")}</T>
          </Pressable>
        </>
      )}
    </View>
  );
}

// ── a row ────────────────────────────────────────────────────────────

function haptic(kind: "long" | "move") {
  if (Platform.OS === "android") void Haptics.performAndroidHapticsAsync(kind === "long" ? Haptics.AndroidHaptics.Long_Press : Haptics.AndroidHaptics.Text_Handle_Move);
  else if (kind === "long") void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  else void Haptics.selectionAsync();
}

/**
 * A row: its title (bold while something in it is unread) and, for an agent that came from Slack, the connect's mark;
 * under it the last thing said; the chat's state a dot before its title (ChatMark), who is in it small at the second
 * line's end (RowPicture.tsx). Two lines, always the same height. The time shows only while the row is held.
 */
function ChatRow({ item, view, live = true, motion = null }: { item: ChatItem; view: ChatsView; live?: boolean; motion?: ListMotion | null }) {
  const [held, setHeld] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const row = useRef<View>(null);
  // Its state line: tapped while it names a message (`stateAbout`: not one that asks for a decision, which the chat
  // itself leads to), the chat opens there; not with something unread: it opens at the unread line, as any tap on the
  // row (the message is read on from there). Measured where it is as it is tapped.
  const line = useRef<View | null>(null);
  const menu = useApp((s) => s.menu);
  useEffect(() => { if (menu === null && menuOpen) setMenuOpen(false); }, [menu, menuOpen]);
  // What is under way (the core's doing list, in the app's state): the row drawn again as it changes.
  useApp((s) => s.doing);
  const busy = rowBusy(app, item);
  const failed = rowFailed(app, item);
  // Nothing left in it: archived with one tap on the 归档 at its start (as its menu's 归档), or swiped away to the left.
  const archivable = live && item.archivable === true && item.offline == null && item.pending !== true;
  const onArchive = archivable ? () => { if (!busy) archiveRow(app, item); } : undefined;
  const body: PressableProps | undefined = !live ? undefined : {
    // Pressed, the chat is read ahead of its page (AppState.prime).
    onPressIn: () => app.prime(item.station, page(item)),
    onPressOut: () => setHeld(false),
    delayLongPress: LONG_PRESS_MS,
    onLongPress: (e) => {
      setHeld(true);
      const x0 = e.nativeEvent.pageX;
      // Held long, what can be done to the chat, as the wide screen's right click: always just below the row (over it
      // when there is no room below), centred on the finger across (the menu is 180 wide, Sheet.tsx MenuHost, which
      // keeps it on the screen).
      const items = rowMenu(app, item, busy);
      if (!items) return;
      haptic("long");
      setMenuOpen(true);
      row.current?.measureInWindow((_x, y, _w, h) => {
        const x = x0 - 90;
        app.menu = new MenuSpec({ left: x, top: y, right: x, bottom: y + h }, items, () => setMenuOpen(false));
      });
    },
    onPress: (e) => {
      const px = e.nativeEvent.pageX;
      const py = e.nativeEvent.pageY;
      const open = (about: number | undefined) => app.push({ kind: "Chat", station: item.station, of: page(item), at: about });
      const about = item.unread ? undefined : item.stateAbout;
      if (about === undefined || !line.current) return open(undefined);
      line.current.measure((_x, _y, w, h, lx, ly) => open(px >= lx && px <= lx + w && py >= ly && py <= ly + h ? about : undefined));
    },
  };
  const lead = view.leading ?? "agents";
  if (!archivable) {
    return (
      <View ref={row} collapsable={false}>
        <ChatRowBody item={item} lead={lead} held={held || menuOpen} busy={busy} failed={failed} onStateLine={(v) => { line.current = v; }} modifier={body} />
      </View>
    );
  }
  return (
    <View ref={row} collapsable={false}>
      <SwipeToArchive item={item} motion={motion} busy={busy}>
        <ChatRowBody item={item} lead={lead} held={held || menuOpen} busy={busy} failed={failed} onArchive={onArchive} onStateLine={(v) => { line.current = v; }} modifier={body} />
      </SwipeToArchive>
    </View>
  );
}

/** Let go past this share of its width (or flung left), a row is archived. */
const ARCHIVE_AT = 0.35;

/**
 * An archivable row, swiped left to archive it (web mobile/Home.tsx): it follows the finger, uncovering 归档 at the
 * right edge (filled in ink once letting go would archive it); let go past [ARCHIVE_AT] of its width or flung left, it
 * goes off to the left and is archived (no copy left behind as it leaves the list, ListMotion.swiped), else it springs
 * back. Archiving refused, it comes back. The drag is read on the row's frame, which does not move: across first it is
 * the swipe and the row's tap and hold let go (the gesture, once active, cancels them); up or down first it is the
 * list's (it scrolls). One keeping watch springs back and asks first, as its menu's 归档.
 */
function SwipeToArchive({ item, motion, busy, children }: { item: ChatItem; motion: ListMotion | null; busy: boolean; children: ReactNode }) {
  const C = useC();
  const still = reducedMotion();
  const key = rowKey(item);
  const drag = useSharedValue(0);
  const width = useSharedValue(1);
  const gone = useSharedValue(false);
  const fill = useSharedValue(0);
  // What the finger did since it came down: where from, where the row was then, and the drag's start once it is one.
  const start = useSharedValue(0);
  const downX = useSharedValue(0);
  const downY = useSharedValue(0);
  const base = useSharedValue(0);
  const wasPast = useSharedValue(false);
  const busyNow = useRef(busy);
  busyNow.current = busy;
  const itemNow = useRef(item);
  itemNow.current = item;
  useAnimatedReaction(() => drag.value < -width.value * ARCHIVE_AT, (past, was) => {
    if (past !== was) fill.value = withTiming(past ? 1 : 0, { duration: 140, easing: Ease.Standard });
  });

  const back = (v = 0) => {
    drag.value = still ? 0 : withSpring(0, { ...MoveSpring, velocity: v });
  };
  const archive = (v: number) => {
    const it = itemNow.current;
    if (gone.value || busyNow.current) return back(v);
    if (it.watch != null) { back(v); archiveRow(app, it); return; }
    gone.value = true;
    motion?.swiped.add(key);
    const act = () => app.act(t("android-chat.archive.verb"), async () => {
      await app.api(it.station).setArchived(it.thread ?? null, it.session, true);
      app.toast = t("android-chat.archived");
    }, undefined, () => { motion?.swiped.delete(key); gone.value = false; back(); });
    if (!still) drag.value = withTiming(-width.value, { duration: 200, easing: Ease.Standard }, () => runOnJS(act)());
    else { drag.value = -width.value; act(); }
  };

  const pan = useMemo(() => Gesture.Pan()
    .manualActivation(true)
    .onTouchesDown((e, m) => {
      if (gone.value) { m.fail(); return; }
      const f = e.allTouches[0]!;
      downX.value = f.absoluteX;
      downY.value = f.absoluteY;
      start.value = drag.value;
    })
    .onTouchesMove((e, m) => {
      const f = e.allTouches[0]!;
      const across = f.absoluteX - downX.value;
      const upDown = f.absoluteY - downY.value;
      // Up or down first: the list's (it scrolls), not a swipe.
      if (Math.abs(upDown) > TOUCH_SLOP && Math.abs(upDown) > Math.abs(across)) { m.fail(); return; }
      if (Math.abs(across) <= TOUCH_SLOP) return;
      // Right from where it rests: nothing there.
      if (across > 0 && start.value >= 0) { m.fail(); return; }
      m.activate();
    })
    .onStart((e) => {
      base.value = e.translationX;
      wasPast.value = false;
    })
    .onUpdate((e) => {
      const to = Math.min(0, Math.max(-width.value, start.value + e.translationX - base.value));
      const nowPast = to < -width.value * ARCHIVE_AT;
      if (nowPast !== wasPast.value) { wasPast.value = nowPast; if (nowPast) runOnJS(haptic)("move"); }
      drag.value = to;
    })
    .onEnd((e) => {
      const v = e.velocityX;
      const at = drag.value;
      const fling = v < -500 && at < -16;
      if (at < -width.value * ARCHIVE_AT || fling) runOnJS(archive)(v);
      else drag.value = still ? 0 : withSpring(0, { ...MoveSpring, velocity: v });
    }),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  [key, still]);

  const under = useAnimatedStyle(() => ({ opacity: drag.value !== 0 ? 1 : 0, backgroundColor: interpolateColor(fill.value, [0, 1], [C.chip, C.ink]) }));
  const word = useAnimatedStyle(() => ({ color: interpolateColor(fill.value, [0, 1], [C.muted, C.bg]) }));
  const moved = useAnimatedStyle(() => ({ transform: [{ translateX: drag.value }], backgroundColor: drag.value !== 0 ? C.bg : "transparent" }));

  return (
    <GestureDetector gesture={pan}>
      <View
        style={{ overflow: "hidden" }}
        onLayout={(e) => { width.value = Math.max(1, e.nativeEvent.layout.width); }}
        accessibilityActions={[{ name: "archive", label: t("android-chat.archive") }]}
        onAccessibilityAction={(e) => { if (e.nativeEvent.actionName === "archive") archive(0); }}
      >
        {/* Under it, at the right edge it uncovers: 归档, quiet until letting go would archive it, then filled in ink. */}
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { paddingHorizontal: 22, alignItems: "flex-end", justifyContent: "center" }, under]}>
          <Animated.Text importantForAccessibility="no" style={[{ fontSize: 15, lineHeight: 21, fontWeight: "600", includeFontPadding: false }, word]}>{t("android-chat.archive")}</Animated.Text>
        </Animated.View>
        <Animated.View style={moved}>{children}</Animated.View>
      </View>
    </GestureDetector>
  );
}

/**
 * What can be done to a chat from its row (web mobile/Home.tsx useRowMenu): pin it, rename it, copy its link, archive
 * it. None for a new chat its station has not made yet, or one on a station offline.
 */
function rowMenu(app: AppState, item: ChatItem, busy: boolean): MenuItem[] | null {
  // Pinning or archiving under way (a spinner on the row): not asked again meanwhile.
  if (item.offline != null || item.pending === true || busy) return null;
  const api = app.api(item.station);
  const run = (what: string, block: () => Promise<unknown>) => app.act(what, block);
  const items: MenuItem[] = [];
  // A station from before pins says nothing of them: its chats are not pinned from here.
  const pinned = item.pinned;
  if (pinned !== undefined) {
    items.push(new MenuItem(pinned ? t("android-chat.unpin") : t("android-chat.pin"), Icons.Pin, () => run(pinned ? t("android-chat.unpin.verb") : t("android-chat.pin.verb"), () => api.setPinned(item.session, !pinned))));
  }
  items.push(new MenuItem(t("android-chat.rename"), Icons.Edit, () => askTitle(app, item.station, item.thread ?? null, item.session, item.title)));
  const link = chatLink(app.cloudOrigin, item.station, item.session);
  if (link != null) items.push(new MenuItem(t("web-main.chat.copyLink"), Icons.Copy, () => copyChatLink(app, item.title, link)));
  items.push(new MenuItem(t("android-chat.archive"), Icons.Archive, () => archiveRow(app, item)));
  return items;
}

/** Archives a row's chat; one keeping watch only once asked: its watch runs on in the archive (the core's words). */
function archiveRow(app: AppState, item: ChatItem) {
  const api = app.api(item.station);
  const watch = item.watch;
  const run = async () => { await api.setArchived(item.thread ?? null, item.session, true); app.toast = t("android-chat.archived"); };
  if (watch != null) confirm(app, t("android-chat.archive.ask", { title: item.title }), watch.ask, t("android-chat.archive"), false, t("android-chat.archive.verb"), () => {}, run);
  else app.act(t("android-chat.archive.verb"), run);
}

/** Whether the row's menu set its chat's pin or archive going, not answered yet. */
function rowBusy(app: AppState, item: ChatItem): boolean {
  return app.isDoing(["chat.pin", "chat.archive"], { station: item.station, session: item.session });
}

/** Why the row's menu's pin or archive failed a moment ago, if it did. */
function rowFailed(app: AppState, item: ChatItem): string | null {
  return app.failedOf(["chat.pin", "chat.archive"], { station: item.station, session: item.session });
}

/**
 * Text moved so its characters' ink, not its line, is in the middle of its box: the marks centred beside it are then
 * centred on its words. A Chinese font's line has more room above its characters than below (its ascent is the line's),
 * so they sit low in it; a character's ink is centred 0.38em above the baseline. Read from the text's laid out line.
 */
function useInkCentred(size: number) {
  const [dy, setDy] = useState(0);
  const onTextLayout = (e: NativeSyntheticEvent<TextLayoutEventData>) => {
    const l = e.nativeEvent.lines[0];
    if (!l) return;
    const base = l.y + l.ascender;
    const next = Math.round(l.height / 2 - base + 0.38 * size);
    if (next !== dy) setDy(next);
  };
  return { onTextLayout, style: { transform: [{ translateY: dy }] } };
}

/**
 * What a row shows, `lead` leading who is in it (RowPicture.tsx); its station by its icon (the core gives one only with
 * several stations); the time while it is `held`; `busy`: a spinner where its mark goes; `failed`: a red mark there a
 * moment (DoingMark). `onStateLine` is given the state line's view (to know a tap on it); `modifier` what the row does
 * when touched (Compose's modifier there: a Pressable's props here, the row pressable with them).
 */
export function ChatRowBody({ item, lead, held, busy = false, failed = null, onArchive, onStateLine = () => {}, modifier }: {
  item: ChatItem; lead: string; held: boolean; busy?: boolean; failed?: string | null; onArchive?: () => void;
  onStateLine?: (line: View | null) => void; modifier?: PressableProps;
}) {
  const C = useC();
  // Its station offline: greyed, and marked where a Slack chat's mark goes (the core says so, row by row).
  const offline = item.offline;
  const dim = offline != null ? 0.45 : 1;
  const ink = useInkCentred(16);
  const reconnecting = item.reconnecting;
  // Where it stands (奏 · …, 在等：…, 做完了), from a station that says; else what was said last.
  const state = item.stateText ?? item.decision?.text;
  const frame: ViewStyle = { height: 66, backgroundColor: held ? withAlpha(C.ink, 0.05) : "transparent" };
  const content = (
    // Nothing left in it (its agents all done, nothing at work, waiting or unread): the row faded (the core says so),
    // its 归档 at its start not.
    <View style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: 6, paddingLeft: 22, paddingRight: 16 }}>
      {/* A small 归档 at its start (a tap archives it; swiping it left does too, SwipeToArchive). */}
      {onArchive && (
        <Pressable
          disabled={busy}
          onPress={onArchive}
          accessibilityLabel={t("android-chat.archive.named", { title: item.title })}
          android_ripple={ripple(C.ink)}
          style={{ borderRadius: 999, overflow: "hidden", backgroundColor: C.chip, paddingHorizontal: 10, paddingVertical: 4, alignItems: "center", justifyContent: "center" }}
        >
          <T size={12} line={16} weight="500" color={C.muted}>{t("android-chat.archive")}</T>
        </Pressable>
      )}
      <View style={{ flex: 1, minWidth: 0, justifyContent: "center", opacity: item.settled === true ? 0.45 : 1 }}>
        <View style={{ height: 22, flexDirection: "row", alignItems: "center", gap: 8 }}>
          <ChatMark item={item} />
          <T
            size={16} line={22} weight={item.unread ? "600" : "400"} color={C.ink} numberOfLines={1} ellipsizeMode="tail"
            onTextLayout={ink.onTextLayout} style={[{ flex: 1, minWidth: 0, opacity: dim }, ink.style]}
          >
            {item.title}
          </T>
          {/* The station it runs on, by its icon (the core gives one only with several stations), as on the web. */}
          {hasStationMark(item.stationEmoji ?? null, item.stationIcon ?? null) && (
            <View accessible accessibilityLabel={item.stationName} style={{ opacity: dim }}>
              <StationMark emoji={item.stationEmoji ?? null} icon={item.stationIcon ?? null} size={12} tint={C.muted} />
            </View>
          )}
          {/* Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too.
              Its slot only when there is one. */}
          {(busy || failed != null || offline != null || reconnecting != null || item.connect != null) && (
            <View style={{ width: 14, alignItems: "center", justifyContent: "center" }}>
              {busy || failed != null ? (
                <DoingMark running={busy} failed={failed} inline />
              ) : offline != null ? (
                // Its station offline, or its link coming back: unplugged (a spinner is only something its person did).
                <View accessible accessibilityLabel={offline}><Icon icon={Icons.Unplug} size={13} color={C.subtle} /></View>
              ) : reconnecting != null ? (
                <View accessible accessibilityLabel={reconnecting}><Icon icon={Icons.Unplug} size={13} color={C.subtle} /></View>
              ) : item.connect != null ? (
                <View accessible accessibilityLabel={item.originText ?? "Slack"}><SlackMark size={13} /></View>
              ) : null}
            </View>
          )}
        </View>
        <View style={{ height: 20, flexDirection: "row", alignItems: "center", gap: 8 }}>
          <View style={{ flex: 1, minWidth: 0, opacity: dim, justifyContent: "center", alignItems: "flex-start" }}>
            {state != null ? (
              <View ref={onStateLine} collapsable={false} style={{ alignSelf: "stretch" }}>
                <StateLine state={state} />
              </View>
            ) : item.last ? <LastMessage item={item} /> : null}
          </View>
          {held ? (
            <T size={12} color={C.subtle} numberOfLines={1}>{item.time?.["lastActiveAt"]?.ago ?? ""}</T>
          ) : (
            <RowAside item={item} lead={lead} style={{ opacity: dim }} />
          )}
        </View>
      </View>
    </View>
  );
  if (!modifier) return <View style={frame}>{content}</View>;
  // Named by its title, what it says under it as the hint (Compose merges a clickable row's words into it; a Pressable
  // here is one node, its words not read through).
  return <Pressable accessibilityLabel={item.title} accessibilityHint={state ?? undefined} {...modifier} style={frame}>{content}</Pressable>;
}

/**
 * What a chat's row says of it (web/src/ChatMark.tsx): red when it wants someone now, yellow at work, blue ended well
 * and unread; a blue ring when something in it waits on the viewer, a grey one when only on others.
 */
export enum RowTone { Busy = "Busy", Done = "Done", Alert = "Alert", Wait = "Wait", Other = "Other" }

/** The core's `tone` when it says one (a station with pieces of work); otherwise from the row's state, as before. */
export function rowTone(item: ChatItem): RowTone | null {
  switch (item.tone) {
    case "alert": return RowTone.Alert;
    case "busy": return RowTone.Busy;
    case "done": return RowTone.Done;
    case "wait": return RowTone.Wait;
    case "other": return RowTone.Other;
  }
  switch (item.state) {
    case "block": case "failed": return RowTone.Alert;
    case "run": return RowTone.Busy;
    default: return item.unread ? RowTone.Done : null;
  }
}

const MarkYellow = "#F2B01E";

/** The mark's canvas (10dp) and the room drawn round it (the alert's halo goes past it, as Compose's Canvas lets it). */
const MARK = 10;
const MARK_OUT = 4;

/**
 * A chat's state, a dot before its title (web: ChatMark.css.ts chatMarkInline): a blue dot done and unread, a red one
 * with a soft halo to be seen now, a turning yellow ring with a gap at work. Nothing otherwise.
 */
function ChatMark({ item }: { item: ChatItem }) {
  const C = useC();
  const tone = rowTone(item);
  // A mark that comes while the chat is in view pops in (web: ChatMark.tsx, 320 ms ease-out, 0 → 1.3 at 60 % → 1);
  // ones there when the list is first drawn do not.
  const still = reducedMotion();
  const pops = useMemo(() => !still && MarksSeen.fresh(rowKey(item)), [tone]); // eslint-disable-line react-hooks/exhaustive-deps
  const pop = useSharedValue(pops ? 0 : 1);
  useEffect(() => {
    if (!pops) { pop.value = 1; return; }
    pop.value = 0;
    pop.value = withTiming(1, { duration: 320, easing: CssEaseOut });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tone]);
  const turning = tone === RowTone.Busy && !still;
  const turn = useSharedValue(0);
  useEffect(() => {
    if (!turning) { cancelAnimation(turn); turn.value = 0; return; }
    turn.value = 0;
    turn.value = withRepeat(withTiming(360, { duration: 1200, easing: Easing.linear }), -1, false);
    return () => cancelAnimation(turn);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [turning]);
  const popped = useAnimatedStyle(() => {
    const p = pop.value;
    const k = p < 0.6 ? (1.3 * p) / 0.6 : 1.3 - (0.3 * (p - 0.6)) / 0.4;
    return { transform: [{ scale: k }] };
  });
  const turned = useAnimatedStyle(() => ({ transform: [{ rotate: `${turn.value}deg` }] }));
  if (tone === null) return null;
  const label = {
    [RowTone.Busy]: t("android-chat.home.mark.busy"), [RowTone.Done]: t("android-chat.home.mark.done"), [RowTone.Alert]: t("android-chat.home.mark.alert"),
    [RowTone.Wait]: t("android-chat.home.mark.wait"), [RowTone.Other]: t("android-chat.home.mark.other"),
  }[tone];
  const c = MARK / 2 + MARK_OUT;
  const r = MARK / 2;
  const ring = 2;
  const box = MARK - ring;
  // Round ends (web: styles/busyRing.ts), the arc shortened by the half stroke they add so the gap stays a quarter.
  const cap = ((ring / box) * 180) / Math.PI;
  return (
    <Animated.View accessible accessibilityLabel={label} style={[{ width: MARK, height: MARK }, popped]}>
      <Quiet style={{ position: "absolute", left: -MARK_OUT, top: -MARK_OUT, width: MARK + 2 * MARK_OUT, height: MARK + 2 * MARK_OUT }}>
      <Animated.View style={[{ width: MARK + 2 * MARK_OUT, height: MARK + 2 * MARK_OUT }, tone === RowTone.Busy && turned]}>
        <Svg width={MARK + 2 * MARK_OUT} height={MARK + 2 * MARK_OUT}>
          {tone === RowTone.Alert && <Circle cx={c} cy={c} r={r - 1 + 3} fill={withAlpha(MarkRed, 0.25)} />}
          {tone === RowTone.Done && <Circle cx={c} cy={c} r={r - 1} fill={MarkBlue} />}
          {tone === RowTone.Alert && <Circle cx={c} cy={c} r={r - 1} fill={MarkRed} />}
          {/* A hollow ring, 2dp, 9dp across: blue when it waits on the viewer, grey when only on others. */}
          {(tone === RowTone.Wait || tone === RowTone.Other) && <Circle cx={c} cy={c} r={4.5 - ring / 2} fill="none" stroke={tone === RowTone.Wait ? MarkBlue : C.subtle} strokeWidth={ring} />}
          {tone === RowTone.Busy && (
            <>
              {/* A faint track, a solid three-quarter arc on it; turning. */}
              <Circle cx={c} cy={c} r={box / 2} fill="none" stroke={withAlpha(MarkYellow, 0.25)} strokeWidth={ring} />
              <Path d={arc(c, c, box / 2, 45 + cap, 270 - 2 * cap)} fill="none" stroke={MarkYellow} strokeWidth={ring} strokeLinecap="round" />
            </>
          )}
        </Svg>
      </Animated.View>
      </Quiet>
    </Animated.View>
  );
}

/** An arc as Compose's drawArc has it: from `start` degrees (0 at three o'clock, clockwise), `sweep` degrees on. */
function arc(cx: number, cy: number, r: number, start: number, sweep: number): string {
  const rad = (d: number) => (d * Math.PI) / 180;
  const x0 = cx + r * Math.cos(rad(start));
  const y0 = cy + r * Math.sin(rad(start));
  const x1 = cx + r * Math.cos(rad(start + sweep));
  const y1 = cy + r * Math.sin(rad(start + sweep));
  return `M${x0} ${y0}A${r} ${r} 0 ${sweep > 180 ? 1 : 0} 1 ${x1} ${y1}`;
}

/**
 * Where the chat stands, in its last message's place (the core's `stateText`): a decision waiting for the viewer
 * (奏 · …) in ink with its 奏 bold; anything else in the secondary colour. A lead said as an icon (要你帮忙 a bell, in
 * ink; 在等 an open arc and dots, 监控中 a radar before its words, 做完了 a check) sits where the title's mark does, what
 * follows where the title starts.
 */
function StateLine({ state, style }: { state: string; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const need = needLead.exec(state);
  const done = need == null ? doneLead.exec(state) : null;
  const wait = need == null && done == null ? waitLead.exec(state) : null;
  const watch = need == null && done == null && wait == null ? watchLead.exec(state) : null;
  const iconLead = need ?? done ?? wait ?? watch;
  if (iconLead != null) {
    // Watching keeps its words after its radar.
    const rest = watch != null ? state : state.substring(iconLead[0].length);
    const tint = need != null ? C.ink : C.muted;
    const icon = need != null ? Icons.Bell : done != null ? Icons.Check : watch != null ? Icons.Watch : Icons.Wait;
    return (
      <View accessible accessibilityLabel={state} style={[{ flexDirection: "row", alignItems: "center", gap: 8 }, style]}>
        {/* The title's mark's place (ChatMark, 10dp then 8dp): centred under a mark, at the title's start with none, so
            what follows starts where the title does in a marked row, every row's icon in the same column. */}
        <View style={{ width: 10, alignItems: "center", justifyContent: "center" }}>
          <View style={{ width: 14, height: 14 }}><Icon icon={icon} size={14} color={tint} /></View>
        </View>
        {rest.length > 0 && <T size={14} line={20} color={tint} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1, textAlignVertical: "center" }}>{rest}</T>}
      </View>
    );
  }
  // The core's lead in either language: 奏 · …, Decision · ….
  const lead = ["奏", "Decision"].find((it) => state === it || state.startsWith(`${it} · `));
  return (
    <T size={14} line={20} color={lead != null ? C.ink : C.muted} numberOfLines={1} ellipsizeMode="tail" style={[{ textAlignVertical: "center" }, style as object]}>
      {lead != null ? <><T size={14} line={20} weight="700" color={C.ink}>{lead}</T>{state.substring(lead.length)}</> : state}
    </T>
  );
}

/** The core's words for an agent needing the viewer, in either language, with what follows them. */
const needLead = /^(?:要你帮忙|需要你处理|Needs you)(?:[：:]\s*|$)/;

/** The core's words for an agent waiting on a watch of its own (present.ts), in either language. */
const watchLead = /^(?:监控中|Watching)(?:：|: |$)/;

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  const C = useC();
  return <T size={14} line={20} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ textAlignVertical: "center" }}>{item.last!.preview}</T>;
}

/** How many decisions wait for the viewer in the workspace (the core's marks: the home page's 奏 N); 0 from a core before them. Read while drawn (a hook). */
export function decisionsWaiting(current: WorkspaceEntry): number {
  const marks = rememberTopic<WorkspaceMarksView>(Topics.workspaceMarks(current.workspace.id));
  return marks.value?.workspaces?.[current.workspace.id]?.decisions ?? 0;
}

/**
 * 奏 N: the decisions page's way in, there at 0 too (奏 alone then, a disc), a capsule of the new-chat button's glass
 * (`ground`) beside it, as tall. `ground` draws the glass round what it is given (Compose's modifier there), at `style`'s size.
 */
export function DecisionsCapsule({ n, ground }: { n: number; ground: (content: ReactNode, style: StyleProp<ViewStyle>) => ReactNode }) {
  const C = useC();
  const press = (style: ViewStyle, content: ReactNode) => (
    <Pressable
      onPress={() => app.push({ kind: "Decisions" })}
      accessibilityLabel={t("android-chat.home.decisions", { n })}
      android_ripple={ripple(C.ink)}
      style={[{ height: 56 }, style]}
    >
      {content}
    </Pressable>
  );
  if (n === 0) {
    return ground(press({ width: 56, alignItems: "center", justifyContent: "center" }, <Icon icon={Icons.Zou} size={40} color={C.ink} />), { height: 56, width: 56 });
  }
  // How many, drawn (design/icons num-*): 1 to 9, and + past that.
  const digit = n >= 1 && n <= 9 ? [Icons.Num1, Icons.Num2, Icons.Num3, Icons.Num4, Icons.Num5, Icons.Num6, Icons.Num7, Icons.Num8, Icons.Num9][n - 1]! : Icons.NumMore;
  return ground(
    press({ flexDirection: "row", alignItems: "center", gap: 6, paddingLeft: 10, paddingRight: 20 }, (
      <>
        <Icon icon={Icons.Zou} size={40} color={C.ink} />
        <Icon icon={digit} size={24} color={C.ink} />
      </>
    )),
    { height: 56 },
  );
}
