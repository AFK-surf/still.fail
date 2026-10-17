// An item's page, one for every item (web/src/pages/ChatPage.tsx, Chat.tsx):
// its chat's messages (none before its agent has a chat), the composer, and
// each agent's execution history as a sheet opened from its mark or name.
// Your messages sit right in a bubble; everyone else gets a face, a name and
// the time over their words. Long-press quotes or copies a message; ＋ adds files.
import { useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { FlatList, Pressable, Text, View, type LayoutChangeEvent, type StyleProp, type ViewStyle } from "react-native";
import Animated, { Easing as REasing, FadeOut, runOnJS, useAnimatedProps, useAnimatedStyle, useSharedValue, withRepeat, withSpring, withTiming, type SharedValue } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Circle, Path } from "react-native-svg";
import { CoreError } from "../../../../web/src/core/client.ts";
import { core, useTopics } from "../../../../web/src/core/react.ts";
import type { ActivityNow, AgentWait, Attachment, ChatAgent, ChatJobsView, ChatMessage, ChatSentElsewhere, ChatView, Live, Maker, Outgoing, Quote, Stamp } from "../../../../web/src/core/shapes.ts";
import { app, screenId, useApp, type AppState } from "../AppState";
import { errorText } from "../data/Calls";
import { chatAgentState, type ChatState } from "../data/Chats";
import { rememberTopic, Topics, type ChatOf } from "../data/Topics";
import { t } from "../i18n";
import { AnnotatedText, thenText, type InlineTextContent, type TextLayout } from "../ui/Annotated";
import { chatInk, rememberStationName } from "../ui/ChatInk";
import { DoingMark } from "../ui/Controls";
import { awayFromEnd, endInView, rememberFollow, rememberLazyListState, type Follow, type LazyListState } from "../ui/Follow";
import { Floating, TopGlass } from "../ui/Glass";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { letsGoOfKeyboard } from "../ui/Keyboard";
import { LocalMdInk, Markdown, withRefs } from "../ui/Markdown";
import { Ease } from "../ui/Motion";
import { linkHold } from "../ui/Links";
import { Avatar, MakerIcon, Mark, ModelMark, NavButton, PeopleStack, reducedMotion, SlackMark } from "../ui/Parts";
import { LocalPickedWords, pickable, pickedText, textLayoutOf, type TextHook } from "../ui/Pick";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { LocalTextMark, markWeight, middleIn, passageMark } from "../ui/TextMark";
import { lerpColor, useC, withAlpha } from "../ui/Theme";
import { Spinner, WaitShape, Waiting } from "../ui/Waiting";
import { openAgent } from "./AgentSheet";
import { Files } from "./ChatFiles";
import {
  boxIn, ComposerSpec, Flying, LocalFlight, LocalFlightCopy, LocalFlightHost, LocalRow, SendReflow, useHost,
  type Flight, type Host,
} from "./ChatHost";
import { openChatInfo } from "./ChatInfo";
import { accentBg, ChatMotion, EmitOut, Flashed, flashing, LocalChatMotion, Pose, useAnimatable, useChatMotion, useTicking, eased } from "./ChatMotion";
import { chatComposer, rememberDraft, type Draft } from "./Composer";
import { DecisionUnder, OptionButton } from "./Decisions";
import { around, Message, openHistory, Pill, Place, Strong } from "./History";
import { openJobs, Tone, toneOf } from "./Jobs";
import { Hold, letsGoOfPick, LocalMessagePick, MessagePick, messagePick, PickLayer, type PickHold } from "./MessagePick";
import { TakeDraftOffers } from "./Preview";
import { AgentWords } from "./Prose";
import { LocalSendTextWidth, SendTextStyle } from "./SendText";
import { StationUpdateControl } from "./StationUpdate";
import { AgentStationMark, ChatStationChip } from "./Stations";

/** An agent of this chat as its messages and activity show it: who it is, and its execution history as it runs. */
export class AgentHere {
  constructor(readonly view: ChatAgent, readonly live: Live | null) {}
  get key() { return this.view.session.key; }
  get runtime() { return this.view.session.runtime; }
  get maker() { return this.view.session.maker ?? null; }
  get who() { return this.view.session.agentText; }
  get state(): ChatState { return chatAgentState(this.view); }
}

// ── times ──

/** Times in messages say how long ago; a tap on one says when, in all of them (web ui.tsx → Time), until tapped again. */
let absoluteTimes = false;
const timeListeners = new Set<() => void>();
function toggleTimes() { absoluteTimes = !absoluteTimes; for (const l of timeListeners) l(); }
function useAbsoluteTimes() {
  return useSyncExternalStore((l) => { timeListeners.add(l); return () => { timeListeners.delete(l); }; }, () => absoluteTimes);
}

export function MessageTime({ stamp, style }: { stamp: Stamp | null | undefined; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const abs = useAbsoluteTimes();
  if (stamp == null) return null;
  return (
    <View style={style}>
      <T size={10} line={16} color={chatInk(C).muted} numberOfLines={1} onPress={toggleTimes} suppressHighlighting>
        {abs ? stamp.full : stamp.ago}
      </T>
    </View>
  );
}

// ── the page ──

/** A chat's page, above its host's composer (ChatHost.tsx), which it says what to write to. */
export function ChatScreen({ station, of, host }: { station: string; of: ChatOf; host: Host }) {
  const chat = rememberTopic<ChatView>(Topics.chat(station, of));
  const view = chat.value;
  // The chat's own draft, kept as the chat is left and the app closed (Composer.tsx → Drafts).
  const draft = rememberDraft(station, of);
  // The bar's height, which the list keeps its top clear of: from the first frame what the bar is laid out as (the
  // status bar, and its row: 6 + 40 + 8dp), and measured from the bar itself, the loading one's too, so the list's
  // first frame is not laid out under a bar of no height and pushed down the next.
  const insets = useSafeAreaInsets();
  const [topBar, setTopBar] = useState(insets.top + 54);
  if (view == null) return <ChatLoading station={station} host={host} draft={draft} error={chat.error} setTopBar={setTopBar} />;
  return <ChatRead station={station} of={of} view={view} host={host} draft={draft} topBar={topBar} setTopBar={setTopBar} />;
}

/**
 * Until the core has the chat, the page is already a chat's page (its bar, empty): what comes fills it in place
 * instead of replacing another page. Its composer is there, not sending yet.
 */
function ChatLoading({ station, host, draft, error, setTopBar }: { station: string; host: Host; draft: Draft; error: CoreError | null; setTopBar: (h: number) => void }) {
  const C = useC();
  useLayoutEffect(() => {
    host.spec = ComposerSpec({ station, here: null, draft, placeholder: t("android-chat.chat.placeholder"), onPlus: () => undefined, onSend: () => undefined });
  });
  // A chat just made here from a new chat (its scene leaving, its first words on their way) is the core's own:
  // nothing to read from a station, so no reading over it for the frames until the core's view of it comes.
  const leaving = useHost(host, (h) => h.leaving) ?? false;
  const carried = useHost(host, (h) => h.flight?.carried === true) ?? false;
  const made = leaving || carried;
  const name = rememberStationName(station);
  // What the composer's glass frosts, as the messages are once read: the page's paper under it.
  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      {/* The read chat's bar is glass over its messages, with a hairline under it (Glass.tsx TopGlass); this one is
          plain paper, the same line under it so the bar does not change as the chat comes. */}
      <BarFrame title="" more={false} style={{ backgroundColor: C.bg }} onLayout={(e) => setTopBar(e.nativeEvent.layout.height)} line />
      {/* Read from its station meanwhile, over the messages to come (ui/Waiting.tsx); what is wrong in red, over still ones. */}
      {(error != null || !made) && (
        <Waiting
          shape={WaitShape.Messages} text={t("android-chat.chat.loadingFrom", { name })}
          error={error ? t("android-chat.chat.unreadable", { error: error.message }) : null} modifier={{ flex: 1 }}
        />
      )}
    </View>
  );
}

function ChatRead({ station, of, view, host, draft, topBar, setTopBar }: { station: string; of: ChatOf; view: ChatView; host: Host; draft: Draft; topBar: number; setTopBar: (h: number) => void }) {
  const C = useC();
  const lives = useTopics<Live>(view.agents.map((a) => Topics.live(station, a.session.key)));
  const agents = view.agents.map((a, i) => new AgentHere(a, lives[i]?.value ?? null));
  // Who is in this chat, for the links in it: one naming an agent here opens over this page (AppState.openLink).
  const keys = view.agents.map((a) => a.session.key);
  useEffect(() => { app.chatAgents.set(screenId({ kind: "Chat", station, of }), new Set(keys)); });
  const spec = chatComposer(host, station, of, view, agents, draft);
  useLayoutEffect(() => { host.spec = spec; });
  const room = useHost(host, (h) => h.roomForList()) ?? 0;
  // Its own paper under all of it: the bars are see-through, and what is under the page must not show in them.
  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      {/* What a preview's marks put into this chat's draft (Preview.tsx). */}
      <TakeDraftOffers station={station} sessions={keys} draft={draft} />
      {/* The messages run under the bar and the composer, which are frosted glass over them. */}
      <Messages station={station} of={of} view={view} agents={agents} draft={draft} style={{ flex: 1, backgroundColor: C.bg }} top={topBar} bottom={room} host={host} />
      <ChatBar station={station} of={of} view={view} agents={agents} onLayout={(e) => setTopBar(e.nativeEvent.layout.height)} />
    </View>
  );
}

// A quick start and a soft landing, shared by both archive actions.
const ArchiveEase = REasing.bezier(0.16, 1, 0.3, 1);

/**
 * Something that comes and goes as the archive actions do (AnimatedVisibility with fade, scale from .85 and its room
 * opening or closing along `axis`, 280ms ArchiveEase; not clipped). `enter`: whether its coming is animated too;
 * `from`: the end its room opens from; `origin`: where it scales from.
 */
function Expanding({ visible, axis, from = "start", enter = true, origin = "center", children }: { visible: boolean; axis: "x" | "y"; from?: "start" | "end"; enter?: boolean; origin?: string; children?: ReactNode }) {
  const [mounted, setMounted] = useState(visible);
  const [size, setSize] = useState<{ width: number; height: number } | null>(null);
  const p = useSharedValue(visible ? 1 : 0);
  useEffect(() => {
    if (visible) setMounted(true);
    if (visible && !enter) { p.value = 1; return; }
    p.value = withTiming(visible ? 1 : 0, { duration: 280, easing: ArchiveEase }, (done) => { if (done && !visible) runOnJS(setMounted)(false); });
  }, [visible, enter, p]);
  const room = useAnimatedStyle(() => (size == null ? { width: 0, height: 0 } : axis === "x" ? { width: size.width * p.value, height: size.height } : { height: size.height * p.value, width: "100%" }), [size, axis]);
  const look = useAnimatedStyle(() => ({ opacity: p.value, transform: [{ scale: 0.85 + 0.15 * p.value }] }));
  if (!mounted) return null;
  return (
    <Animated.View style={[room, { overflow: "visible" }]}>
      <Animated.View
        onLayout={(e) => { const { width, height } = e.nativeEvent.layout; if (size?.width !== width || size?.height !== height) setSize({ width, height }); }}
        style={[{ position: "absolute", top: 0, transformOrigin: origin }, axis === "x" ? (from === "end" ? { right: 0 } : { left: 0 }) : { left: 0, right: 0 }, look]}
      >
        {children}
      </Animated.View>
    </Animated.View>
  );
}

/**
 * The chat's bar: its title from the left, then its people, then its agents' marks (each opens its card, the first's
 * tile carrying the station it runs on, whose card leads on to the station's); its
 * services and jobs (with a dot when one died lately or a service restarts), and "…", the chat's own page.
 */
function ChatBar({ station, of, view, agents, onLayout }: { station: string; of: ChatOf; view: ChatView; agents: AgentHere[]; onLayout: (e: LayoutChangeEvent) => void }) {
  const C = useC();
  useApp((s) => s.doing);
  const thread = view.thread ?? null;
  const jobs = rememberTopic<ChatJobsView>(Topics.chatJobs(station, of));
  const alarm = jobs.value?.alarm != null ? toneOf(jobs.value.alarm) : null;
  // Nothing left in it: archived with one tap from its bar (as its row's 归档).
  const session = archiveSession(of, view, agents);
  const canArchive = view.archivable === true && view.archived !== true && session != null;
  const archiving = app.isDoing("chat.archive", { station, session });
  return (
    <TopGlass style={{ position: "absolute", left: 0, right: 0, top: 0 }}>
      <View onLayout={onLayout}>
        <BarFrame
          title={view.title} more={thread != null}
          onMore={() => { if (thread != null) openChatInfo(app, station, of, thread, view); }}
          trailing={
            <>
              <Expanding visible={canArchive} axis="x" from="end">
                <View>
                  {archiving
                    ? <View accessible accessibilityLabel={t("android-chat.archive")} style={{ width: 34, height: 34, alignItems: "center", justifyContent: "center" }}><Spinner /></View>
                    : <NavButton icon={Icons.Archive} label={t("android-chat.archive")} onClick={() => { if (canArchive && session != null) archiveChat(app, station, view, session); }} />}
                </View>
              </Expanding>
              {(jobs.value?.jobs?.length ?? 0) > 0 && (
                <View>
                  <NavButton icon={Icons.Web} onClick={() => openJobs(app, station, of)} />
                  {alarm != null && (
                    <View style={{ position: "absolute", top: 6, right: 6, width: 11, height: 11, borderRadius: 5.5, backgroundColor: C.bg, padding: 2 }}>
                      <View style={{ flex: 1, borderRadius: 3.5, backgroundColor: alarm === Tone.Fail ? C.red : C.warn }} />
                    </View>
                  )}
                </View>
              )}
            </>
          }
        >
          {/* The station on its own while the chat has no agent; else on the first agent's tile. */}
          {agents.length === 0 && <ChatStationChip address={station} />}
          <StationUpdateControl station={station} notice={view.stationUpdate ?? null} />
          {view.people.length > 0 && <PeopleStack people={view.people.slice(0, 5)} size={16} />}
          {agents.map((a, i) =>
            i === 0
              ? <AgentStationMark key={a.key} address={station} who={a.who} maker={a.maker} runtime={a.runtime} state={a.state} onAgent={() => openAgent(app, station, of, a.view)} />
              // Not clipped: the state's dot sits over the mark's corner, partly outside it.
              : <Pressable key={a.key} onPress={() => openAgent(app, station, of, a.view)}><ModelMark maker={a.maker} runtime={a.runtime} size={22} state={a.state} listMark /></Pressable>,
          )}
        </BarFrame>
      </View>
    </TopGlass>
  );
}

/** The bar's frame, the same while the chat loads and once it has: back, the title, what follows it, what is at its end, and "…". */
function BarFrame({ title, more, onMore = () => undefined, style, onLayout, line = false, trailing, children }: { title: string; more: boolean; onMore?: () => void; style?: StyleProp<ViewStyle>; onLayout?: (e: LayoutChangeEvent) => void; line?: boolean; trailing?: ReactNode; children?: ReactNode }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  return (
    <View style={[{ width: "100%", paddingTop: insets.top }, style]} onLayout={onLayout}>
      <View style={{ flexDirection: "row", alignItems: "center", paddingLeft: 4, paddingRight: 16, paddingTop: 6, paddingBottom: 8 }}>
        <Pressable onPress={() => app.pop()} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }} style={{ width: 40, height: 40, borderRadius: 20, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
          <Icon icon={Icons.ChevronLeft} size={22} color={C.accent} />
        </Pressable>
        <View style={{ flex: 1, minWidth: 0, paddingRight: 8, flexDirection: "row", alignItems: "center", gap: 8 }}>
          <T size={16} weight="600" color={C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{title}</T>
          {children}
        </View>
        {trailing}
        {more && <NavButton icon={Icons.More} label={t("android-chat.info.title")} onClick={onMore} />}
      </View>
      {line && <View style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 0.5, backgroundColor: C.line }} />}
    </View>
  );
}

// ── the list ───────────────────────────────────────────────────────────

/** A long chat coming in from its newest: how many of its last rows are in the list so far. */
class Reveal {
  decided = false;
  count = Number.MAX_SAFE_INTEGER;
  get revealing() { return this.count !== Number.MAX_SAFE_INTEGER; }
}

/** An item new to the list comes up a little as it fades in (web mRise: 14px and opacity together, 320ms --m-standard). */
function Rise({ on, children }: { on: boolean; children?: ReactNode }) {
  const y = useSharedValue(on ? 1 : 0);
  useEffect(() => { if (on) y.value = withTiming(0, { duration: 320, easing: Ease.Standard }); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const style = useAnimatedStyle(() => ({ transform: [{ translateY: y.value * 14 }], opacity: 1 - y.value }));
  return <Animated.View style={style}>{children}</Animated.View>;
}

type Entry =
  | { kind: "Older"; id: "older" }
  /** The page after what shows coming in (the chat's window short of its end). */
  | { kind: "Newer"; id: "newer" }
  | { kind: "Empty"; id: "empty" }
  | { kind: "Line"; id: "line" }
  /** `sent`: the outbox entry it was sent from here as, whose row it goes on being (its key kept: not a row leaving and another coming). */
  | { kind: "Said"; id: string; m: ChatMessage; sent: string | null }
  | { kind: "Out"; id: string; o: Outgoing }
  /** What was said in Slack by or to an agent of the chat (the core's `elsewhere`): shown, not one of the chat's. */
  | { kind: "Sent"; id: string; s: ChatSentElsewhere }
  | { kind: "Working"; id: string; agent: AgentAtWork }
  /** The room an activity that folded away leaves behind (as the web's floor): what is above it does not drop. */
  | { kind: "Floor"; id: "floor"; px: number };

const Entry = {
  Older: { kind: "Older", id: "older" } as Entry,
  Newer: { kind: "Newer", id: "newer" } as Entry,
  Empty: { kind: "Empty", id: "empty" } as Entry,
  Line: { kind: "Line", id: "line" } as Entry,
  Said: (m: ChatMessage, sent: string | null = null): Entry => ({ kind: "Said", id: sent != null ? `o:${sent}` : `m:${m.ts}`, m, sent }),
  Out: (o: Outgoing): Entry => ({ kind: "Out", id: `o:${o.id}`, o }),
  Sent: (s: ChatSentElsewhere): Entry => ({ kind: "Sent", id: `s:${s.key}`, s }),
  Working: (agent: AgentAtWork): Entry => ({ kind: "Working", id: `act:${agent.key}`, agent }),
  Floor: (px: number): Entry => ({ kind: "Floor", id: "floor", px }),
};

/** How a place in the chat is kept (Messages → places) and a message found: by the message, however its row is keyed. */
const placeOf = (e: Entry) => (e.kind === "Said" ? `m:${e.m.ts}` : e.id);

/** An agent at work: who it is, its transcript and steps in flight, since when its turn runs, and while it waits on work
 * it started, since when and for how long at most. */
export class AgentAtWork {
  constructor(readonly key: string, readonly who: string, readonly runtime: string, readonly maker: Maker | null, readonly live: Live | null, readonly since: number | null, readonly wait: AgentWait | null = null) {}
}

/**
 * What the messages need to know about the chat: who is who, and whose workspace keeps a file. `orOwner`: the session
 * that keeps files when no agent of the chat is known (the decisions page shows a chat's messages without its agents).
 */
export class Here {
  constructor(readonly station: string, readonly of: ChatOf, readonly view: ChatView, readonly agents: AgentHere[], readonly orOwner: string | null = null) {}
  agent(key: string) { return this.agents.find((a) => a.key === key) ?? null; }
  mine(m: ChatMessage) { return m.mine; }
  #archiveUnder: number | null | undefined;
  /** The post 归档这个 chat goes under: the agents' latest that ended all done, while the chat can be archived. */
  get archiveUnder(): number | null {
    if (this.#archiveUnder === undefined) {
      const v = this.view;
      this.#archiveUnder = v.archivable !== true || v.archived === true || v.pending === true ? null
        : v.messages.findLast((m) => m.authorKind === "agent" && m.ending === "all_done")?.seq ?? null;
    }
    return this.#archiveUnder;
  }
  #checkUnder: number | null | undefined;
  /** The post what the archive check made of the chat goes under: the agents' latest, when it ended all done. */
  get checkUnder(): number | null {
    if (this.#checkUnder === undefined) {
      const last = this.view.archiveCheck == null ? null : this.view.messages.findLast((m) => m.authorKind === "agent" && !m.system) ?? null;
      this.#checkUnder = last?.ending === "all_done" ? last.seq : null;
    }
    return this.#checkUnder;
  }
  /** Files are kept in a session's workspace: the agent whose workspace holds it, else the first. */
  owner(file: Attachment): string | null {
    return this.agents.find((a) => file.path.startsWith(`${a.view.session.workspace}/`))?.key ?? this.agents[0]?.key ?? this.orOwner;
  }
}

/** How an activity glides to a new place (web useActivityGlide: a spring, 0.3s, no bounce: damping ratio 1, stiffness 300). */
const ACTIVITY_GLIDE = { mass: 1, stiffness: 300, damping: 2 * Math.sqrt(300) };

/** How long an activity stays once its agent stops, then how long it takes to fade (web Chat.tsx HOLD_MS, FADE_MS). */
const HOLD_MS = 600;
const FADE_MS = 220;
/** How long words sent wait for the list to be laid out with the composer's room before they fly all the same. */
const LAYOUT_MS = 100;

/** The list's gap between messages (web mobile: --list-gap 20px). */
const GAP = 20;

const frame = () => new Promise<number>((r) => requestAnimationFrame(r));

/** What is read of the list, drawn again as it changes (`select` gives something compared as it is). */
function useListSelect<T>(list: LazyListState, select: (l: LazyListState) => T): T {
  return useSyncExternalStore(list.subscribe, () => select(list));
}
/** What is read of the following, drawn again as it changes. */
function useFollowSelect<T>(follow: Follow, select: (f: Follow) => T): T {
  return useSyncExternalStore(follow.subscribe, () => select(follow));
}

/** Where each row's cell is in the list's content (its top), as last laid out, and who wants to know when it moves. */
class CellTops {
  readonly #y = new Map<string, number>();
  readonly #watch = new Map<string, Set<(was: number, now: number) => void>>();
  laid(key: string | undefined, y: number) {
    if (key == null) return;
    const was = this.#y.get(key);
    this.#y.set(key, y);
    if (was != null && was !== y) for (const w of this.#watch.get(key) ?? []) w(was, y);
  }
  watch(key: string, w: (was: number, now: number) => void) {
    let set = this.#watch.get(key);
    if (!set) this.#watch.set(key, (set = new Set()));
    set.add(w);
    return () => { set!.delete(w); };
  }
}

/**
 * A row pushed by what comes in above it glides to its new place, going on from where it is and its speed when pushed
 * again (Modifier.animateItem's placement: web useActivityGlide): drawn where it was, then sprung home.
 */
function Glide({ tops, id, on, children }: { tops: CellTops; id: string; on: boolean; children?: ReactNode }) {
  const off = useSharedValue(0);
  const now = useRef(on);
  now.current = on;
  useEffect(() => tops.watch(id, (was, y) => {
    if (!now.current) { off.value = 0; return; }
    off.value = off.value + (was - y);
    off.value = withSpring(0, ACTIVITY_GLIDE);
  }), [tops, id, off]);
  const style = useAnimatedStyle(() => ({ transform: [{ translateY: off.value }] }));
  return <Animated.View style={style}>{children}</Animated.View>;
}

/** What the rows share of the list they are in (the page's, as Messages has them). */
interface ListCtx {
  ctx: Here; draft: Draft; list: LazyListState; rows: Entry[]; host: Host; motion: ChatMotion; now: number; tops: CellTops;
  arrived: Set<string>; heights: Map<string, number>; floor: { current: number }; setFloor: (px: number) => void;
  leaving: (key: string) => boolean;
}

/** `top` and `bottom`: the bars over it, which the list keeps its ends clear of. */
function Messages({ station, of, view, agents, draft, style, top = 0, bottom = 0, host }: { station: string; of: ChatOf; view: ChatView; agents: AgentHere[]; draft: Draft; style?: StyleProp<ViewStyle>; top?: number; bottom?: number; host: Host }) {
  const C = useC();
  const ink = chatInk(C);
  useApp((s) => s.doing);
  const inFront = useApp((s) => s.inFront);
  const ctx = new Here(station, of, view, agents);
  const thread = view.thread ?? null;
  const api = app.api(station);
  const messages = view.messages;

  // The unread line, as the core puts it (client/core-ts/src/attend.ts): over the first message not read when the chat
  // opened, not the viewer's, held for the visit; while it lies above what is loaded, the core loads older pages
  // first (none meanwhile).
  const lineAt = view.unreadLine ?? null;
  const above = view.unreadAbove === true;
  const first = view.messages[0]?.seq ?? null;

  // Messages the agents have not taken yet (the core says which): after a second, yours say they wait.
  const [now, setNow] = useState(() => Date.now());
  const youngest = messages.filter((m) => m.waiting).reduce((a, m) => Math.max(a, m.createdAt), 0);
  useEffect(() => {
    const wait = youngest + 1000 - Date.now();
    if (youngest > 0 && wait > 0) { const id = setTimeout(() => setNow(Date.now()), wait + 20); return () => clearTimeout(id); }
  }, [youngest]);

  // Agents' messages coming out of their activity's avatar (ChatMotion.tsx), and a quoted message flashing.
  const reduced = reducedMotion();
  const motion = useMemo(() => new ChatMotion(reduced), []); // eslint-disable-line react-hooks/exhaustive-deps
  useSyncExternalStore(motion.subscribe, () => motion.version);
  motion.ring = ringClock();
  // Each agent at work, and each that stopped a moment ago, on its own (web useLinger): one whose turn ends stays
  // 600ms (a turn ending and the next starting leave a moment between), then fades 220ms and goes, whatever the others
  // do. Only an agent that has taken a message and runs is at work (not one with messages waiting for it): until then
  // the message itself says it waits. One whose messages are still coming out of its avatar stays too.
  const keeps = motion.keeps();
  const lingering = useRef(new Map<string, [AgentAtWork, number | null]>()).current;
  const [, setLingered] = useState(0);
  const nowMs = performance.now();
  const running = agents.filter((a) => a.view.status === "running").map((a) => new AgentAtWork(a.key, a.who, a.runtime, a.maker, a.live, a.view.since ?? null, a.view.wait ?? null));
  for (const a of running) lingering.set(a.key, [a, null]);
  for (const [k, v] of [...lingering]) {
    if (running.some((r) => r.key === k)) continue;
    if (keeps.has(k)) { lingering.set(k, [v[0], null]); continue; }
    let stopped = v[1];
    if (stopped == null) { stopped = nowMs; lingering.set(k, [v[0], stopped]); }
    if (nowMs - stopped >= HOLD_MS + FADE_MS) lingering.delete(k);
  }
  let nextChange: number | null = null;
  for (const [, s] of lingering.values()) {
    if (s == null) continue;
    const at = nowMs - s < HOLD_MS ? s + HOLD_MS : s + HOLD_MS + FADE_MS;
    nextChange = nextChange == null ? at : Math.min(nextChange, at);
  }
  useEffect(() => {
    if (nextChange == null) return;
    const id = setTimeout(() => setLingered((n) => n + 1), Math.max(0, nextChange - performance.now()));
    return () => clearTimeout(id);
  }, [nextChange]);
  const atWork = [...lingering.values()].map((v) => v[0]);
  const leaving = (key: string) => { const s = lingering.get(key)?.[1]; return s != null && nowMs - s >= HOLD_MS; };
  // The list never gets shorter under the reader: an activity that fades away leaves its height as a floor (what is
  // under it, another activity, glides up into its place), which what comes next (a message, another activity) takes
  // back as it arrives.
  const heights = useRef(new Map<string, number>()).current;
  const floor = useRef(0);
  const [, setFloorTick] = useState(0);
  const setFloor = (px: number) => { if (px !== floor.current) { floor.current = px; setFloorTick((n) => n + 1); } };
  const gapPx = GAP;
  // Taken in the same drawing the activity leaves in (an effect would leave a frame without either, the list
  // shorter by it, and its end pulled up), and exactly its room: each activity and the gap before it, less the gap
  // the floor itself brings when it comes in.
  const shownActs = new Set(atWork.map((a) => `act:${a.key}`));
  const wasActs = useRef(new Set<string>()).current;
  const gone = [...wasActs].filter((k) => !shownActs.has(k));
  if (gone.length > 0) {
    const acts = gone.map((k) => heights.get(k)).filter((h): h is number => h != null);
    if (acts.length > 0) floor.current += acts.reduce((a, b) => a + b, 0) + acts.length * gapPx - (floor.current === 0 ? gapPx : 0);
    for (const k of gone) heights.delete(k);
  }
  wasActs.clear();
  for (const k of shownActs) wasActs.add(k);

  // Messages said while the chat shows (the core says which: `said`), from an agent whose activity shows, wait their
  // turn out of the list.
  motion.take(messages, new Set(atWork.map((a) => a.key)));
  // A message sent from here stays the row it was in the outbox once the chat shows it: by the seq the station gave
  // it (Outgoing.seq), or the identity carried by the message if the UI skipped that acknowledgement.
  const sentAs = useRef(new Map<number, string>()).current;
  for (const o of view.outbox) if (o.seq != null) sentAs.set(o.seq, o.id);
  for (const m of messages) if (m.outgoing != null) sentAs.set(m.seq, m.outgoing);
  // The chat shows a window short of its end (the core's `newer`): the page after comes in as the reader nears the
  // list's end, which is not the chat's; what goes on at the chat's end (its activity) is not here, and nothing said
  // joins the list meanwhile (it waits, counted in the thread's `unread`).
  const short = view.newer === true;
  const all: Entry[] = [];
  if (view.more) all.push(Entry.Older);
  if (messages.length === 0 && view.outbox.length === 0 && (view.elsewhere ?? []).length === 0) all.push(Entry.Empty);
  {
    // What its agents sent to Slack meanwhile, each after the message it followed (0: before the first).
    const elsewhere = new Map<number, ChatSentElsewhere[]>();
    for (const s of view.elsewhere ?? []) { const l = elsewhere.get(s.after) ?? []; l.push(s); elsewhere.set(s.after, l); }
    for (const s of elsewhere.get(0) ?? []) all.push(Entry.Sent(s));
    for (const m of messages) {
      if (motion.held(m.seq)) continue;
      if (m.seq === lineAt) all.push(Entry.Line);
      all.push(Entry.Said(m, sentAs.get(m.seq) ?? null));
      for (const s of elsewhere.get(m.seq) ?? []) all.push(Entry.Sent(s));
    }
  }
  if (short) all.push(Entry.Newer);
  for (const o of view.outbox) all.push(Entry.Out(o));
  // The activity is always the last thing in the chat (a reply comes whole, as a message).
  if (!short) {
    for (const a of atWork) all.push(Entry.Working(a));
    if (floor.current > 0) all.push(Entry.Floor(floor.current));
  }

  const placeKey = `${station}:${thread?.id ?? agents[0]?.key ?? ""}`;
  // Left at its end with nothing new since: it opens at its end, following it, as if new to it (web Chat.tsx →
  // useRememberPlace); the top message's offset would not land there once what is below it lays out otherwise
  // (images still loading, an activity come or gone).
  const kept = app.places.get(placeKey) ?? null;
  const leftAtEnd = kept?.bottom != null && kept.bottom === messages[messages.length - 1]?.ts;
  const place = leftAtEnd ? null : kept;
  // Where the core opened it (`at`), unless it was left here at its end since: the chat's view can outlive the page
  // (opened again before the core lets it go) and still say where it was opened the first time.
  const openedAt = leftAtEnd ? null : view.at ?? null;
  // A long chat opened at its newest: the newest few first, at the bottom, and the rest rising in above them a
  // few a frame, rather than one frame building a screenful. (Opened elsewhere, at a place or the unread line, or
  // a window short of the chat's end, it is all there at once, to be put in place.)
  const reveal = useRef(new Reveal()).current;
  const [, setRevealed] = useState(0);
  if (!reveal.decided && messages.length > 0) {
    reveal.decided = true;
    if (all.length > 8 && place == null && !short && openedAt == null && !all.some((e) => e.kind === "Line")) reveal.count = 3;
  }
  const allSize = useRef(all.length);
  allSize.current = all.length;
  useEffect(() => {
    if (!reveal.decided || !reveal.revealing) return;
    let id = requestAnimationFrame(function step() {
      reveal.count = reveal.count + 2 >= allSize.current ? Number.MAX_SAFE_INTEGER : reveal.count + 2;
      setRevealed((n) => n + 1);
      if (reveal.revealing) id = requestAnimationFrame(step);
    });
    return () => cancelAnimationFrame(id);
  }, [reveal.decided]); // eslint-disable-line react-hooks/exhaustive-deps
  const rows = reveal.count < all.length ? all.slice(all.length - reveal.count) : all;
  host.rows = new Set(all.map((e) => e.id));
  // What was in the list the last time it was drawn: an item new to it rises in; one scrolled to does not, nor one
  // caught up on rather than said while the chat is open: the core says which (attend.ts: a message `said`, an agent
  // `started` while the chat shows).
  const known = useRef(new Set<string>()).current;
  const started = new Set(agents.filter((a) => a.view.started === true).map((a) => a.key));
  const caught = (row: Entry) => (row.kind === "Said" ? row.m.said !== true : row.kind === "Working" ? !started.has(row.agent.key) : false);
  // What is new is told here, as the list is drawn: its rows are drawn later (as it is laid out), after the
  // effect below has counted them in. Nothing is new on the first draw, nor with the reader away from the end
  // (not following it): what arrives out of view is there when scrolled to, not coming in then.
  const arrived = useRef(new Set<string>()).current;
  const drawn = useRef(false);
  const following = useRef<Follow | null>(null);
  if (drawn.current && following.current?.on !== false) for (const r of rows) if (!known.has(r.id) && !caught(r)) arrived.add(r.id);
  useEffect(() => { for (const r of rows) known.add(r.id); drawn.current = true; });
  // The unread line near the top, below the bar, with about four lines of what came before it still in view (web
  // Chat.tsx → useUnreadLine: the bar's room and four of the list's 23px lines).
  const lineOffset = -85;
  // Where the core opened the chat, short of its end (its first unread, where it was left: `at`): that message at the
  // top, when nothing here says otherwise (a place kept here, the unread line).
  const atFound = openedAt == null ? -1 : rows.findIndex((e) => e.kind === "Said" && e.m.seq >= openedAt);
  const atIndex = atFound >= 0 ? atFound : null;
  // Where that message's top was when the chat was left there (`atOffset`, as this app told the core: px here dp).
  const atRow = atIndex != null ? rows[atIndex] : null;
  const atOffset = view.atOffset != null && openedAt != null && atRow?.kind === "Said" && atRow.m.seq === openedAt ? Math.round(view.atOffset) : 0;
  // The list starts where it is going (the unread line, where the chat was left, or the newest), rather than
  // drawing its top only to jump away from it.
  const lineRow = rows.findIndex((e) => e.kind === "Line");
  const placeRow = place ? rows.findIndex((e) => placeOf(e) === place.id) : -1;
  const start: [number, number] = lineRow >= 0 ? [lineRow, lineOffset]
    : place && placeRow >= 0 ? [placeRow, -place.offset]
    : atIndex != null ? [atIndex, -atOffset] : [Math.max(0, rows.length - 1), 0];
  const list = rememberLazyListState();
  const follow = rememberFollow(list);
  following.current = follow;
  useLayoutEffect(() => { follow.short = short; });
  motion.follow = follow;
  const placed = useFollowSelect(follow, (f) => f.placed);
  const jumpTo = rememberJump(list, rows, motion);
  const accent = ink.accent;
  const tops = useRef(new CellTops()).current;
  const pane = useRef<View | null>(null);
  motion.where = host.where;
  host.where.list = list;
  host.where.start = 14;

  // Its first frame is where it is put (the unread line with what came before it, the place with its offset): the
  // list shows once it is there, so putting it there once it has laid out moves nothing.
  const [begun, setBegun] = useState(false);
  const [laid, setLaid] = useState(false);
  const startNow = useRef(start);
  startNow.current = start;
  useEffect(() => {
    if (begun || !laid || messages.length === 0) return;
    let gone = false;
    void list.scrollToItem(startNow.current[0], startNow.current[1]).catch(() => undefined).then(() => { if (!gone) setBegun(true); });
    return () => { gone = true; };
  }, [begun, laid, messages.length > 0]); // eslint-disable-line react-hooks/exhaustive-deps

  // What waits to be decided (the core's `asks`) whose post does not show in the list (web Chat.tsx useAsksShown): a
  // bell over the list leads to it (JumpToAsk). One whose post is not loaded does not show.
  const asks = view.archived === true || thread == null ? [] : view.asks ?? [];
  const posts = asks.map((a) => rows.find((r) => r.kind === "Said" && r.m.seq === a.seq)?.id ?? null);
  const shownKeys = useListSelect(list, (l) => l.layoutInfo.visibleItemsInfo.map((i) => i.key).join("\u0000"));
  const asksShow = posts.every((p) => p != null) && posts.every((p) => shownKeys.split("\u0000").includes(p!));
  const [askTurn, setAskTurn] = useState(0);
  // The page before asked for (once per page: here, or near the top below).
  const asked = useRef<number | null>(null);
  // Whether the unread line was gone to (or is not to be: the chat opened at a message asked for, below).
  const lineShown = useRef(false);
  const revealing = reveal.revealing;
  // Opened at a message (a row's state line: what it is about), or asked to show one while open (the bell that leads to
  // what waits to be decided: JumpToAsk), once the list is in place: there, flashing; the pages before brought in until
  // it is loaded (none left, or it is gone: where the chat opened).
  const goTo = useHost(host, (h) => h.goTo) ?? null;
  useEffect(() => {
    const target = host.goTo;
    if (target == null || !placed || revealing) return;
    const m = rows.find((r) => r.kind === "Said" && r.m.seq === target);
    if (m && m.kind === "Said") {
      // There it stays: the unread line showing after it does not take the chat away from it.
      host.goTo = null;
      lineShown.current = true;
      // Opened from a search: its words marked in it, the first in view, rather than the message flashing.
      const words = host.goToWords;
      host.goToWords = [];
      if (words.length > 0) motion.markWords(m.m.ts, words, accent);
      jumpTo(m.m.ts, words.length > 0 ? FOUND : "");
    } else if (view.more && thread != null && first != null && first > target) {
      asked.current = first;
      api.older(thread.id).catch(() => { host.goTo = null; });
    } else host.goTo = null;
  }, [placed, first, revealing, goTo]); // eslint-disable-line react-hooks/exhaustive-deps
  // Put in place once: at the unread line (even coming back: something unread goes over where the chat was left),
  // else back where the chat was left, else where the core opened it (`at`), else at the newest.
  useEffect(() => {
    if (!begun || follow.placed || above) return;
    let gone = false;
    void (async () => {
      const saved = place;
      const back = saved ? rows.findIndex((r) => placeOf(r) === saved.id) : -1;
      const line = rows.findIndex((r) => r.kind === "Line");
      if (line >= 0) await list.scrollToItem(line, lineOffset);
      else if (saved && back >= 0) await list.scrollToItem(back, -saved.offset);
      else if (atIndex != null) await list.scrollToItem(atIndex, -atOffset);
      else await follow.toEnd();
      if (gone) return;
      lineShown.current = line >= 0;
      follow.short = short;
      follow.placed = true;
      follow.on = follow.atEnd();
    })().catch(() => undefined);
    return () => { gone = true; };
  }, [begun, above, messages.length > 0]); // eslint-disable-line react-hooks/exhaustive-deps
  // Something unread that shows only after opening (from the station, after what was kept): the chat jumps to it once.
  const lineIndex = rows.findIndex((r) => r.kind === "Line");
  useEffect(() => {
    if (!placed || lineShown.current || lineIndex < 0) return;
    lineShown.current = true;
    follow.anchor = null;
    void list.scrollToItem(lineIndex, lineOffset).then(() => { follow.on = follow.atEnd(); });
  }, [lineIndex, placed]); // eslint-disable-line react-hooks/exhaustive-deps
  // A message arriving at the end while it is followed is kept in view from its top (the activity never is: it folds away).
  follow.indexOf = (key) => rows.findIndex((r) => r.id === key);
  const newestKey = rows.findLast((r) => r.kind !== "Working" && r.kind !== "Floor" && r.kind !== "Newer")?.id ?? null;
  const knownNewest = useRef<string | null>(null);
  useEffect(() => {
    if (!placed) return;
    if (knownNewest.current != null && newestKey !== knownNewest.current && follow.on) follow.anchor = newestKey;
    knownNewest.current = newestKey;
  }, [newestKey, placed]); // eslint-disable-line react-hooks/exhaustive-deps
  // Remember where the chat is left: the message at the top and its offset, so what arrives below does not move it;
  // and whether it was left at its end (not a window short of it). The core is told too (`chat.place`): the message
  // at the top short of the end, none at it; it opens the chat's window there next, while nothing is unread.
  // It is told as the reader comes to rest too, not only on leaving (web Chat.tsx): an app gone from memory or
  // swiped away never leaves the page, and the core keeps what it was told last on the device.
  const nowRef = useRef({ rows, newest: messages[messages.length - 1]?.ts ?? null, short, thread: thread?.id ?? null });
  nowRef.current = { rows, newest: messages[messages.length - 1]?.ts ?? null, short, thread: thread?.id ?? null };
  const leave = () => {
    const n = nowRef.current;
    const atEnd = !n.short && (follow.on || !list.canScrollForward);
    const bottomTs = atEnd ? n.newest : null;
    let topRow: [Entry & { kind: "Said" }, number] | null = null;
    for (const item of list.layoutInfo.visibleItemsInfo) {
      const r = n.rows.find((e) => e.id === item.key && e.kind === "Said");
      if (r && r.kind === "Said") { topRow = [r, item.offset]; break; }
    }
    if (topRow) app.places.set(placeKey, { id: placeOf(topRow[0]), offset: topRow[1], bottom: bottomTs });
    const id = n.thread;
    if (id != null && follow.placed) {
      const seq = atEnd ? null : topRow?.[0].m.seq ?? null;
      const offset = atEnd ? null : topRow?.[1] ?? null;
      app.scope.launch(() => api.place(id, seq, offset).catch(() => undefined));
    }
  };
  const leaveNow = useRef(leave);
  leaveNow.current = leave;
  useEffect(() => {
    if (!placed) return;
    let was = list.isScrollInProgress;
    return list.subscribe(() => {
      const moving = list.isScrollInProgress;
      if (was && !moving) leaveNow.current();
      was = moving;
    });
  }, [placeKey, placed, list]);
  useEffect(() => () => leaveNow.current(), [placeKey]);
  // A page coming in at either end (or going at the other) leaves what is in view where it is. The list keeps its
  // first item in view by its key; when that is a page's spinner, the first row after it is kept where it is instead.
  // The window put back at the chat's end in place of what showed (`chat.latest`; sending from short of it): the list
  // goes to its end.
  const headKey = rows.find((r) => r.kind === "Said")?.id ?? null;
  const lastHead = useRef<string | null>(null);
  // The reader asked for the chat's end (the jump button short of it): the window put there shows at its end at once.
  const toLatest = useRef(false);
  const lastRow = rows.length - 1;
  const atLatest = () => {
    follow.anchor = null;
    // Past the last row's top by more than it can be: the list lays out its end.
    void list.scrollToItem(lastRow, 1_000_000);
    follow.on = true;
  };
  // Complete the normal list layout before starting FLIP. The real row supplies the destination, including
  // the list's own scroll clamping in a short chat; scrolling is never an animation clock.
  const flying = useHost(host, (h) => h.flight) ?? null;
  const followMargin = 12;
  useLayoutEffect(() => {
    host.prepareFlight = async (f: Flight) => {
      // Laid out with the room the flight keeps for the composer, and a few frames at most, never a wait for something
      // to happen.
      const until = performance.now() + LAYOUT_MS;
      while (performance.now() < until && list.layoutInfo.afterContentPadding !== host.roomForList() + 10) await frame();
      if (!nowRef.current.short && host.flight === f) {
        follow.paused = true;
        const index = f.key != null ? follow.indexOf(f.key) : -1;
        if (index >= 0) {
          follow.anchor = f.key;
          // Same destination as normal follow: the new message's top, clamped by the actual list end.
          await list.scrollToItem(index, -followMargin);
        }
      }
    };
  });
  useEffect(() => { if (flying == null) follow.paused = false; }, [flying, follow]);
  // A message sent from up the list takes the reader to its end at once, following again (web Chat.tsx useToEnd). Told
  // by the composer as it sends, not by the outbox growing: on a quick link the station has the message before the
  // outbox ever shows it.
  const sends = useHost(host, (h) => h.sends) ?? 0;
  const sentCount = useRef(sends);
  useLayoutEffect(() => {
    const was = lastHead.current;
    lastHead.current = headKey;
    const sent = sends > sentCount.current;
    sentCount.current = sends;
    // Words sent flying in, while it follows: it is put in place by them (below), not glided after their row.
    if (sent && host.flight?.carried === false && !short) follow.paused = true;
    if (toLatest.current && !short) { toLatest.current = false; atLatest(); return; }
    // Not only from up the list: while it follows a long message from its top (its anchor), the end is below what
    // shows too, and a row put there would never come into sight (the words stayed in the composer, then went).
    if (sent && !short && follow.placed && (!follow.on || follow.anchor != null || list.canScrollForward)) { atLatest(); return; }
    if (was == null || was === headKey || !follow.placed || reveal.revealing) return;
    // Not laid out anew yet: what is in view is what was.
    const shown = list.layoutInfo.visibleItemsInfo;
    const at = shown.find((i) => i.key !== Entry.Older.id && i.key !== Entry.Newer.id);
    if (!at) return;
    const index = rows.findIndex((r) => r.id === at.key);
    if (index < 0) { if (!short) atLatest(); }
    else if (shown[0]!.key !== at.key && index !== at.index) void list.scrollToItem(index, -at.offset);
  });
  // Near the top: the page before comes in (once per page); what is on screen stays put.
  useEffect(() => {
    if (!view.more || thread == null || !placed || revealing) return;
    const check = () => {
      if (list.firstVisibleItemIndex <= 2 && asked.current !== first) {
        asked.current = first;
        api.older(thread.id).catch(() => { asked.current = null; });
      }
    };
    check();
    return list.subscribe(check);
  }, [view.more, first, placed, revealing]); // eslint-disable-line react-hooks/exhaustive-deps
  // Near the end, short of the chat's: the page after comes in (once per page), read rather than said (no motion);
  // as many go at the start, and what is on screen stays put.
  const lastSeq = messages[messages.length - 1]?.seq ?? null;
  const askedNewer = useRef<number | null>(null);
  useEffect(() => {
    if (!short || thread == null || !placed || revealing) return;
    const check = () => {
      const info = list.layoutInfo;
      const near = (info.visibleItemsInfo[info.visibleItemsInfo.length - 1]?.index ?? -1) >= info.totalItemsCount - 3;
      if (near && askedNewer.current !== lastSeq) {
        askedNewer.current = lastSeq;
        api.newer(thread.id).catch(() => { askedNewer.current = null; });
      }
    };
    check();
    return list.subscribe(check);
  }, [short, lastSeq, placed, revealing]); // eslint-disable-line react-hooks/exhaustive-deps
  // What is shown is read: up to the newest message, once the end is in view on a page in front.
  // (The end of a window short of the chat's end is not its end: nothing past it has shown. Nor is the end of the
  // list as last laid out while rows that came since are not: a page landing at the end would be read unseen.)
  const lastRowKey = rows[rows.length - 1]?.id ?? null;
  const lastLaidOut = useListSelect(list, (l) => { const v = l.layoutInfo.visibleItemsInfo; return v[v.length - 1]?.key ?? null; }) === lastRowKey;
  const inView = endInView(list);
  const followOn = useFollowSelect(follow, (f) => f.on);
  const seen = !short && inView && lastLaidOut && placed && inFront;
  // Only what is watched comes out of an avatar: the page in front, the reader at the end; else all shows at once.
  const watched = followOn && inFront;
  useLayoutEffect(() => { motion.watched = watched; motion.start(); });
  useEffect(() => { if (!watched) motion.release(); }, [watched, motion]);
  const current = motion.current;
  useEffect(() => { if (current) void motion.play(current); }, [current, motion]);
  // The core is told this chat shows, and whether its end is (`seen`): what is read, where the unread line goes and
  // which notices are left out follow there (client/core-ts/src/attend.ts).
  const session = ("session" in of ? of.session : null) ?? view.key ?? agents[0]?.key ?? null;
  const shownAs = (end: boolean | null) => ({ station, thread: thread?.id ?? null, session, ...(end != null ? { end } : {}) });
  useEffect(() => { core().focus({ chat: shownAs(seen) }).catch(() => undefined); }, [station, thread?.id, session, seen]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => { core().focus({ left: shownAs(null) }).catch(() => undefined); }, [station, thread?.id, session]); // eslint-disable-line react-hooks/exhaustive-deps

  // A new chat's first words on their way (ChatHost.tsx): the list comes up after them, out of the composer's top edge.
  const flight = flying;
  // A passage of a message picked where it is, to quote into the draft or copy (MessagePick.tsx).
  const pick = useMemo(() => new MessagePick(draft), [draft]);
  const moving = useListSelect(list, (l) => l.isScrollInProgress);
  const scrolled = useListSelect(list, (l) => l.firstVisibleItemIndex * 1e6 + l.firstVisibleItemScrollOffset);
  // Its latest page asked for and not come yet: a spinner in it, not asked again.
  const fetching = thread != null && app.isDoing("chat.latest", { station, thread: thread.id });
  const toEnd = awayFromEnd(list) || short;
  const keyboard = letsGoOfKeyboard();
  // The list's binding (Follow.tsx), its cells telling where they are as they are laid out.
  const binding = list.bind(rows.length, { before: top + 14, after: bottom + 10, spacing: GAP });
  const Cell = useMemo(() => {
    const Theirs = binding.CellRendererComponent;
    return function Cell(props: { cellKey?: string; index: number; onLayout?: (e: LayoutChangeEvent) => void; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
      return <Theirs {...props} onLayout={(e: LayoutChangeEvent) => { props.onLayout?.(e); tops.laid(props.cellKey, e.nativeEvent.layout.y); }} />;
    };
  }, [binding.CellRendererComponent, tops]);
  const lc: ListCtx = { ctx, draft, list, rows, host, motion, now, tops, arrived, heights, floor, setFloor, leaving };
  // Where the list is cut (the composer's top edge, words of a new chat coming up under it), as the page is laid out.
  const paneTop = flight?.carried ? boxIn(pane.current, host.where.overlay)?.y ?? null : null;
  const cut = flight?.carried && paneTop != null ? flight.top - paneTop : null;
  const shift = host.shift;
  const [paneH, setPaneH] = useState<number | null>(null);
  const carriedStyle = useAnimatedStyle(() => ({ transform: [{ translateY: flight?.carried ? shift.value : 0 }] }), [flight?.carried]);
  return (
    <View
      ref={(v) => { pane.current = v; host.where.pane = v; }}
      collapsable={false}
      style={[style, { width: "100%" }]}
      onLayout={(e) => setPaneH(e.nativeEvent.layout.height)}
      {...letsGoOfPick(pick)}
    >
      <LocalChatMotion.Provider value={motion}>
        <LocalMessagePick.Provider value={pick}>
          {/* The list is what the bars and capsules over it frost (the button over it too, so it is not in it). */}
          {/* A new chat's first words coming up: the list after them, cut at the composer's top edge. */}
          <View style={[{ position: "absolute", left: 0, right: 0, top: 0 }, cut != null ? { height: Math.max(0, cut), overflow: "hidden" } : { bottom: 0 }]}>
            <Animated.View style={[{ position: "absolute", left: 0, right: 0, top: 0 }, paneH != null ? { height: paneH } : { bottom: 0 }, carriedStyle]}>
              {/* Reading on (a tap, a drag): the keyboard goes, out of the way. */}
              <View style={{ flex: 1, opacity: begun || messages.length === 0 ? 1 : 0 }} {...keyboard}>
                <FlatList
                  style={{ flex: 1, backgroundColor: C.bg }}
                  data={rows}
                  keyExtractor={(r) => r.id}
                  renderItem={({ item }) => <RowItem row={item} lc={lc} />}
                  ref={binding.ref as never}
                  onScroll={binding.onScroll}
                  scrollEventThrottle={binding.scrollEventThrottle}
                  onLayout={binding.onLayout}
                  onContentSizeChange={(w, h) => { binding.onContentSizeChange(w, h); if (h > 0 && !laid) setLaid(true); }}
                  onScrollBeginDrag={binding.onScrollBeginDrag}
                  onScrollEndDrag={binding.onScrollEndDrag}
                  onMomentumScrollBegin={binding.onMomentumScrollBegin}
                  onMomentumScrollEnd={binding.onMomentumScrollEnd}
                  onScrollToIndexFailed={binding.onScrollToIndexFailed}
                  CellRendererComponent={Cell as never}
                  contentContainerStyle={[
                    { paddingLeft: 14, paddingRight: 14, paddingTop: top + 14, paddingBottom: bottom + 10, gap: GAP },
                    // Arrangement.Bottom while it comes in from its newest: what is there sits at the list's end.
                    revealing && { flexGrow: 1, justifyContent: "flex-end" },
                  ]}
                  initialNumToRender={Math.max(10, rows.length)}
                  windowSize={21}
                  // A page coming in above leaves what is in view where it is (the row after a page's spinner, not the spinner).
                  maintainVisibleContentPosition={{ minIndexForVisible: rows[0]?.kind === "Older" ? 1 : 0 }}
                  removeClippedSubviews={false}
                  keyboardShouldPersistTaps="handled"
                />
              </View>
            </Animated.View>
          </View>
          {/* Over the list, under the bar and the composer: the picked passage's handles and what to do with it. */}
          <PickLayer pick={pick} follow={() => scrolled} moving={moving} top={top} bottom={bottom} style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }} />
          {/* Over the send button, in line with it (the composer's capsule insets it 18dp from the edge); it comes up
              growing and goes the way it came (web mobile/Chat.css.ts → mJump: from translateY(18px) scale(.6), its
              opacity 180ms and the rest 220ms --m-standard; going, 150ms and 180ms; turned back mid-way from where it is).
              Short of the chat's end it shows at the list's end too, saying how many new messages wait there; it puts the
              chat's latest page in place of what shows and goes to its end at once. */}
          <JumpToLatest
            shown={toEnd} count={short && thread != null && thread.unread > 0 ? thread.unread : null}
            style={{ position: "absolute", right: 18, bottom: bottom + 2 }} busy={fetching}
            onJump={async () => {
              if (!short || thread == null) return follow.jump();
              toLatest.current = true;
              try { await api.latest(thread.id); } catch (e) { toLatest.current = false; app.toast = t("android-chat.chat.latest.failed", { error: e instanceof CoreError ? errorText(e) : String(e) }); }
            }}
          />
          {/* What waits to be decided and does not show: a bell there, no words (over the way to the end when both show),
              leading to its post, then the next one's, round again. */}
          <JumpToAsk
            shown={asks.length > 0 && !asksShow} lift={toEnd ? 44 : 0} bottom={bottom + 2}
            onJump={() => {
              const a = asks[askTurn % Math.max(asks.length, 1)];
              if (a) { host.goTo = a.seq; setAskTurn((n) => n + 1); }
            }}
          />
        </LocalMessagePick.Provider>
      </LocalChatMotion.Provider>
      {/* The avatar flying with a message out of it: over the list, under the bars and the composer (as the web's, in
          the pane). */}
      <Flyer motion={motion} atWork={atWork} />
    </View>
  );
}

/** One row of the list: how it comes and goes, the room it makes as words fly in, and what it is. */
function RowItem({ row, lc }: { row: Entry; lc: ListCtx }) {
  const { host, motion, ctx, draft, list, rows, now, tops, arrived, heights, floor, setFloor, leaving } = lc;
  const [fresh] = useState(() => arrived.delete(row.id));
  const view = useRef<View | null>(null);
  useHost(host, (h) => h.flight);
  // What was just sent from here flies in from the composer instead (ChatHost.tsx); an activity opens in its
  // own way, and a message out of an avatar comes out of it instead.
  const flies = host.takes(row.id, row.kind === "Out" || (row.kind === "Said" && row.m.mine && !row.m.system));
  const f = flies ? host.flight : null;
  // Flown in, it is where it came to once it lands: it does not rise in again as the flight lets it go.
  const flew = useRef(false);
  if (flies) flew.current = true;
  const eases = fresh && !flew.current && row.kind !== "Working" && !(row.kind === "Said" && motion.emits(row.m.seq));
  // Only what goes from the chat fades out (an activity done, a message dropped from the outbox); rows going
  // because the window moved or was put elsewhere (a page in at the other end, the latest page) are gone at once.
  const fades = row.kind === "Working" || row.kind === "Out" || row.kind === "Floor";
  // An activity pushed by what comes in above it (a message, one coming out of an avatar) glides to its new
  // place, going on from where it is and its speed when pushed again (web useActivityGlide); folded to an
  // avatar that is out flying it shows nothing, and is put there at once for the avatar to fly to.
  const glides = row.kind === "Working" && !motion.away(row.agent.key);
  useEffect(() => {
    if (view.current) host.where.rows.set(row.id, view.current);
    return () => { if (host.where.rows.get(row.id) === view.current) host.where.rows.delete(row.id); };
  }, [host, row.id]);
  const content = (() => {
    switch (row.kind) {
      case "Older": return <View style={{ width: "100%", paddingTop: 4, paddingBottom: 8, alignItems: "center" }}><Spinner /></View>;
      case "Newer": return <View style={{ width: "100%", paddingTop: 8, paddingBottom: 4, alignItems: "center" }}><Spinner /></View>;
      case "Empty": return <EmptyLine />;
      case "Line": return <UnreadLine />;
      case "Said": return <Said ctx={ctx} m={row.m} draft={draft} list={list} rows={rows} waitingNow={row.m.waiting && now - row.m.createdAt > 1000} />;
      case "Out": return <Out ctx={ctx} o={row.o} />;
      case "Sent": return <SentElsewhere ctx={ctx} s={row.s} />;
      case "Working": return <Activity ctx={ctx} agent={row.agent} leaving={leaving(row.agent.key)} opening={fresh} />;
      case "Floor": return <View style={{ width: "100%", height: row.px }} />;
    }
  })();
  return (
    <View
      ref={view}
      collapsable={false}
      onLayout={(e) => {
        if (view.current) host.where.rows.set(row.id, view.current);
        if (row.kind === "Floor") return;
        const h = e.nativeEvent.layout.height;
        const before = heights.get(row.id);
        heights.set(row.id, h);
        // Something new took its place at the bottom: the floor gives that much back.
        if (before == null && fresh && floor.current > 0) setFloor(Math.max(0, floor.current - h - GAP));
      }}
    >
      <Animated.View exiting={fades ? FadeOut.duration(200) : undefined}>
        <SendReflow host={host} id={row.id}>
          <Glide tops={tops} id={row.id} on={glides && host.flight == null}>
            <Rise on={eases}>
              <LocalRow.Provider value={row.id}>
                <LocalFlight.Provider value={f}>
                  <LocalFlightHost.Provider value={host}>
                    <Flying host={host} f={f} row={row.id}>
                      {f ? <FlightProviders f={f} host={host} motion={motion} row={row.id}>{content}</FlightProviders> : content}
                    </Flying>
                  </LocalFlightHost.Provider>
                </LocalFlight.Provider>
              </LocalRow.Provider>
            </Rise>
          </Glide>
        </SendReflow>
      </Animated.View>
    </View>
  );
}

/** What a row flown into is drawn with again over the composer (ChatHost.tsx draws it there): the same as in the list. */
function FlightProviders({ f, host, motion, row, children }: { f: Flight; host: Host; motion: ChatMotion; row: string; children?: ReactNode }) {
  const pick = useContext(LocalMessagePick);
  const width = useContext(LocalSendTextWidth);
  return (
    <LocalSendTextWidth.Provider value={width}>
      <LocalChatMotion.Provider value={motion}>
        <LocalMessagePick.Provider value={pick}>
          <LocalRow.Provider value={row}>
            <LocalFlight.Provider value={f}>
              <LocalFlightHost.Provider value={host}>{children}</LocalFlightHost.Provider>
            </LocalFlight.Provider>
          </LocalRow.Provider>
        </LocalMessagePick.Provider>
      </LocalChatMotion.Provider>
    </LocalSendTextWidth.Provider>
  );
}

function EmptyLine() {
  const C = useC();
  return <T size={15} line={24} color={chatInk(C).muted} align="center" style={{ width: "100%", paddingVertical: 30, paddingHorizontal: 24 }}>{t("android-chat.chat.empty")}</T>;
}

/** The copy of an activity's avatar (with its ring) that flies to where its message goes and back. */
function Flyer({ motion, atWork }: { motion: ChatMotion; atWork: AgentAtWork[] }) {
  useAnimatable(motion.clock);
  const turn = motion.current;
  const agent = turn && turn.pose !== Pose.Fold ? atWork.find((a) => a.key === turn.agent) ?? null : null;
  // Read where it is put each frame it is drawn: the real avatar hides in the frame this one first shows, and shows in
  // the frame it is gone. Drawn for another agent's turn than now flies (the turn moved on since): not shown until drawn anew.
  const f = turn && agent && motion.current?.agent === turn.agent ? motion.flight() : null;
  useLayoutEffect(() => { motion.copied = f && turn ? turn.agent : null; });
  useEffect(() => () => { motion.copied = null; }, [motion]);
  if (!turn || !agent) return null;
  const ring = 3;
  const at = f?.at ?? { x: -10_000, y: 0 };
  const sx = f?.sx ?? 1;
  const sy = f?.sy ?? 1;
  return (
    <View
      pointerEvents="none"
      style={{
        position: "absolute", left: at.x - ring, top: at.y - ring, width: 24, height: 24, alignItems: "center", justifyContent: "center",
        // Squashed and stretched standing on its foot, the face's bottom (9dp under its middle).
        transform: [{ translateY: 9 * (1 - sy) }, { scaleX: sx }, { scaleY: sy }],
      }}
    >
      <AgentAvatar maker={agent.maker} runtime={agent.runtime} />
      <View style={{ position: "absolute", left: 0, top: 0 }}><WorkRing waiting={agent.wait != null} leaving={false} shared={motion.ring} /></View>
    </View>
  );
}

/** How the way to the end and the bell come and go (web mJump): the fade 180ms in / 150 out, the rest 220 / 180. */
function useJumpMotion(shown: boolean) {
  const fade = useSharedValue(shown ? 1 : 0);
  const grow = useSharedValue(shown ? 1 : 0);
  const [here, setHere] = useState(shown);
  useEffect(() => {
    if (shown) setHere(true);
    fade.value = withTiming(shown ? 1 : 0, { duration: shown ? 180 : 150, easing: Ease.Css });
    grow.value = withTiming(shown ? 1 : 0, { duration: shown ? 220 : 180, easing: Ease.Standard }, (done) => { if (done && !shown) runOnJS(setHere)(false); });
  }, [shown, fade, grow]);
  const style = useAnimatedStyle(() => ({
    opacity: fade.value,
    transform: [{ translateY: 18 * (1 - grow.value) }, { scale: 0.6 + 0.4 * grow.value }],
  }));
  return [here, style] as const;
}

function JumpToLatest({ shown, count, style, busy = false, onJump }: { shown: boolean; count: number | null; style?: StyleProp<ViewStyle>; busy?: boolean; onJump: () => Promise<void> | void }) {
  const C = useC();
  // What it says stays as it goes.
  const said = useRef<number | null>(null);
  if (shown) said.current = count;
  const [here, motionStyle] = useJumpMotion(shown);
  if (!here) return null;
  const n = said.current;
  return (
    <Animated.View style={[style, motionStyle]}>
      <Floating radius={18} style={{ height: 36, minWidth: 36 }}>
        <Pressable
          disabled={!shown || busy}
          onPress={() => { void onJump(); }}
          accessibilityLabel={t("android-chat.chat.latest")}
          style={{ height: 36, minWidth: 36, alignItems: "center", justifyContent: "center" }}
        >
          {n == null ? (busy ? <Spinner /> : <Icon icon={Icons.ArrowDown} size={18} color={C.ink} />) : (
            <View style={{ paddingLeft: 10, paddingRight: 14, flexDirection: "row", alignItems: "center", gap: 4 }}>
              {busy ? <Spinner /> : <Icon icon={Icons.ArrowDown} size={18} color={C.ink} />}
              <T size={13} weight="500" color={C.ink} numberOfLines={1}>{t("android-chat.chat.newMessages", { n })}</T>
            </View>
          )}
        </Pressable>
      </Floating>
    </Animated.View>
  );
}

/** 忽略 under a post that asks what no one has decided: the viewer lets it go, going at once and back if that fails. */
function AskDismiss({ ctx, m }: { ctx: Here; m: ChatMessage }) {
  const C = useC();
  const [gone, setGone] = useState(false);
  useEffect(() => setGone(false), [m.seq]);
  // Going as the archive buttons go (below), rather than vanishing; back at once if letting it go failed.
  return (
    <Expanding visible={m.asked === true && !gone} axis="y" enter={false} origin="0% 0%">
      <T
        size={12} line={18} color={C.muted} style={{ paddingTop: 6, alignSelf: "flex-start" }}
        onPress={() => {
          setGone(true);
          app.act(t("android-misc.decisions.dismissWhat"), () => app.api(ctx.station).dismissDecision(m.thread, m.seq), null, () => setGone(false));
        }}
      >
        {t("android-chat.asks.dismiss")}
      </T>
    </Expanding>
  );
}

/** The way to what waits to be decided in the chat: a bell, as the way to its end (JumpToLatest) comes and goes. */
function JumpToAsk({ shown, lift, bottom, onJump }: { shown: boolean; lift: number; bottom: number; onJump: () => void }) {
  const C = useC();
  const [here, motionStyle] = useJumpMotion(shown);
  const up = useSharedValue(lift);
  useEffect(() => { up.value = withTiming(lift, { duration: 200, easing: Ease.Standard }); }, [lift, up]);
  const lifted = useAnimatedStyle(() => ({ bottom: bottom + up.value }), [bottom]);
  if (!here) return null;
  return (
    <Animated.View style={[{ position: "absolute", right: 18 }, lifted]}>
      <Animated.View style={motionStyle}>
        <Floating radius={18} style={{ width: 36, height: 36 }}>
          <Pressable disabled={!shown} onPress={onJump} accessibilityLabel={t("android-chat.asks.go")} style={{ width: 36, height: 36, alignItems: "center", justifyContent: "center" }}>
            <Icon icon={Icons.Bell} size={18} color={C.ink} />
          </Pressable>
        </Floating>
      </Animated.View>
    </Animated.View>
  );
}

/** Over the first message that was unread when the chat opened: the accent, a rule each side (web Chat.css.ts → chatUnreadLine). */
function UnreadLine() {
  const C = useC();
  const accent = chatInk(C).accent;
  return (
    <View style={{ width: "100%", flexDirection: "row", alignItems: "center", gap: 10 }}>
      <View style={{ flex: 1, height: 1, backgroundColor: withAlpha(accent, 0.5) }} />
      <T size={13} weight="500" color={accent}>{t("android-chat.chat.newBelow")}</T>
      <View style={{ flex: 1, height: 1, backgroundColor: withAlpha(accent, 0.5) }} />
    </View>
  );
}

/** A message's picture (web Chat.tsx → MessageAvatar): an agent's model maker in the agents' ground, still.fail's mark, or a person's face. */
function MessageAvatar({ m }: { m: ChatMessage }) {
  switch (m.authorKind) {
    case "agent": return <AgentAvatar maker={m.by.maker ?? null} runtime={m.by.runtime ?? null} />;
    case "ember":
    case "stillfail": return <AgentAvatar maker={null} runtime={null} />;
    default: return <Avatar id={m.author} name={m.by.name} size={18} picture={m.by.picture ?? null} />;
  }
}

/** An agent's picture in a chat: its model's maker (still.fail's mark without one), small on a round grey ground. */
export function AgentAvatar({ maker, runtime }: { maker: Maker | null | undefined; runtime: string | null | undefined }) {
  const C = useC();
  return (
    <View style={{ width: 18, height: 18, borderRadius: 9, overflow: "hidden", backgroundColor: chatInk(C).neutral, alignItems: "center", justifyContent: "center" }}>
      {runtime != null ? <MakerIcon maker={maker} runtime={runtime} size={12} /> : <Mark size={12} />}
    </View>
  );
}

/** Someone's words as they wrote them (web Chat.tsx → PersonWords): a reference to another chat as its chip, a link held its menu. */
function PersonWords({ text }: { text: string }) {
  const C = useC();
  const words = markWeight(pickedText(withRefs(text)));
  const mark = passageMark(words.text);
  const links = linkHold(words);
  const pick = pickable(words.text);
  return <AnnotatedText text={words} style={{ fontSize: 15, lineHeight: 23, color: chatInk(C).text }} modifier={thenText(mark[0], links[0], pick[0])} onTextLayout={laidBy(mark, links, pick)} />;
}

/** What each of a text's hooks is given of its layout, and `then` after them. */
function laidBy(...hooks: (TextHook | ((e: TextLayout) => void))[]) {
  return (e: TextLayout) => { for (const h of hooks) (typeof h === "function" ? h : h[1])(e); };
}

/** A message's words as read, without markdown's marks: what a quote carries. */
function plain(text: string) { return text.replace(/[`*#>]/g, "").replace(/\s+/g, " ").trim(); }

function Said({ ctx, m, draft, list, rows, waitingNow }: { ctx: Here; m: ChatMessage; draft: Draft; list: LazyListState; rows: Entry[]; waitingNow: boolean }) {
  // A quote led here: the passage it quotes is marked where these words hold it (TextMark.tsx).
  const motion = useChatMotion();
  const mark = (motion?.flashed === m.ts ? motion.mark : null) ?? (motion?.foundAt === m.ts ? motion.found : null);
  return <LocalTextMark.Provider value={mark ?? null}><SaidRow ctx={ctx} m={m} draft={draft} list={list} rows={rows} waitingNow={waitingNow} /></LocalTextMark.Provider>;
}

/** A name over what is said: an agent's opens its card, another chat's agent that chat (session_send). */
function Name({ who, onClick }: { who: string; onClick: (() => void) | null }) {
  const C = useC();
  return (
    // FontWeight(650): React Native draws weights by the hundred; 600 is the nearest it has.
    <T size={15} weight="600" color={chatInk(C).name} numberOfLines={1} ellipsizeMode="tail" style={{ maxWidth: 240 }} onPress={onClick ?? undefined} suppressHighlighting>
      {who}
    </T>
  );
}

/**
 * What an agent of the chat said in Slack rather than here, or a person's Slack message it was given (web Chat.tsx →
 * SentElsewhere): an avatar and name as messages have them, Slack's mark on the avatar, then where it went or came from
 * over its words beside a bar, as the execution history draws them.
 */
function SentElsewhere({ ctx, s }: { ctx: Here; s: ChatSentElsewhere }) {
  const C = useC();
  const ink = chatInk(C);
  const agent = s.by.agent != null ? ctx.agent(s.by.agent) : null;
  const received = s.received === true;
  const [before, after] = around(received ? "android-chat.chat.slack.from" : "android-chat.history.sent.to");
  return (
    <View style={{ width: "100%" }}>
      <View style={{ position: "absolute", left: 0, top: 3 }}>
        {received ? <Avatar id={s.by.name} name={s.by.name} size={18} /> : <AgentAvatar maker={s.by.maker ?? null} runtime={s.by.runtime ?? null} />}
        {/* Said in Slack, not here: Slack's mark on its corner (web: msgAvatarSlack). */}
        <View style={{ position: "absolute", left: 18 - 14 + 6, top: 18 - 14 + 6, width: 14, height: 14, borderRadius: 7, overflow: "hidden", backgroundColor: ink.canvas, borderWidth: 1, borderColor: C.line, alignItems: "center", justifyContent: "center" }}>
          <SlackMark size={9} />
        </View>
      </View>
      <View style={{ width: "100%", gap: 4 }}>
        <View style={{ paddingLeft: 25, minHeight: 24, flexDirection: "row", alignItems: "center", gap: 6 }}>
          <Name who={s.by.name} onClick={agent ? () => openAgent(app, ctx.station, ctx.of, agent.view) : null} />
          <MessageTime stamp={s.time?.["createdAt"]} />
        </View>
        <Message
          icon={received ? Icons.Received : Icons.Send}
          label={() => (
            <>
              <T size={13} color={C.muted}>{before}</T>
              <View style={{ flexShrink: 1 }}>
                {s.place != null ? <Place station={ctx.station} of={ctx.of} place={s.place} /> : <View style={{ flexDirection: "row", alignItems: "center" }}><SlackMark size={12} /><Strong text=" Slack" /></View>}
              </View>
              <T size={13} color={C.muted}>{after}</T>
              {s.failed === true && <Pill text={t("android-chat.history.send.failed")} color={C.red} />}
            </>
          )}
          text={s.text}
          full={() => <Markdown text={s.text} size={15} />}
        />
      </View>
    </View>
  );
}

/**
 * A message drawn as the chat draws it, outside its list (the decisions page, Decisions.tsx): the same row, without its
 * options (the page has them at its foot) and without a draft to put follow-ups in.
 */
export function SaidAlone({ ctx, m }: { ctx: Here; m: ChatMessage }) {
  const list = rememberLazyListState();
  return <SaidRow ctx={ctx} m={m} draft={null} list={list} rows={[]} waitingNow={false} decide={false} />;
}

function SaidRow({ ctx, m, draft, list, rows, waitingNow, decide = true }: { ctx: Here; m: ChatMessage; draft: Draft | null; list: LazyListState; rows: Entry[]; waitingNow: boolean; decide?: boolean }) {
  const C = useC();
  const jump = rememberJump(list, rows);
  const ink = chatInk(C);
  const motion = useChatMotion();
  const flash = accentBg();
  const row = useContext(LocalRow);
  const mine = ctx.mine(m);
  const agent = !mine && m.by.agent != null ? ctx.agent(m.by.agent) : null;
  const who = m.by.name;
  // A finger held on the words picks a passage of them, here (MessagePick.tsx).
  const [hold, words] = messagePick(m.ts, mine ? t("android-chat.annotate.you") : who, mine || m.authorKind !== "agent" ? "person" : "agent", m.system ? "" : m.text);
  const landing = useRef<View | null>(null);
  // What still.fail itself says (role "ember", as the core sends it): a notice across the chat, apart from people's and agents' messages.
  if (m.system) return <SystemNotice text={m.text} time={m.time?.["createdAt"]} toProfile={m.profile != null ? () => app.push({ kind: "Profile", address: ctx.station, profile: m.profile! }) : null} />;
  if (mine) {
    // Flashing, your words' bubble takes the accent's ground (it is the message); with no words, the row does.
    return (
      <Flashed motion={motion} ts={m.text.length === 0 ? m.ts : null} color={flash} style={{ width: "100%", alignItems: "flex-end", gap: 4 }}>
        <QuoteCards quotes={m.quotes} onJump={jump} side="flex-end" />
        {m.text.length > 0 && <LocalPickedWords.Provider value={words}><Bubble text={m.text} hold={hold} ts={m.ts} /></LocalPickedWords.Provider>}
        <Files ctx={ctx} list={m.attachments} mine />
        {/* Not taken by its agents yet: after a second it says it waits. */}
        {waitingNow ? <UnderWay text={t("android-chat.chat.waitingAgent")} />
          // Coming in with the words, when they fly here from the composer.
          : <FlightFade><MessageTime stamp={m.time?.["createdAt"]} /></FlightFade>}
      </Flashed>
    );
  }
  // Someone else's: the avatar and name in line over what they say (web: the phone's inline heads), the name an
  // agent's opens its card (AgentSheet.tsx).
  const from = m.by.from ?? null;
  const onName = agent ? () => openAgent(app, ctx.station, ctx.of, agent.view)
    // Another chat's agent (session_send): its name opens that chat.
    : from != null ? () => app.openLink(from) : null;
  const check = decide && ctx.checkUnder === m.seq ? ctx.view.archiveCheck ?? null : null;
  return (
    <Flashed motion={motion} ts={m.ts} color={flash} style={{ width: "100%" }}>
      {/* Where a message out of an agent's avatar lands: its own avatar, hidden while the flying one is over it. */}
      <View
        ref={(v) => { landing.current = v; if (v) motion?.landings.set(m.seq, { view: v, row }); else if (motion?.landings.get(m.seq)?.view === landing.current) motion?.landings.delete(m.seq); }}
        collapsable={false}
        style={{ position: "absolute", left: 0, top: 3, opacity: motion?.emitting(m.seq) ? 0 : 1 }}
      >
        <MessageAvatar m={m} />
      </View>
      <EmitOut motion={motion} seq={m.seq} style={{ width: "100%" }}>
        <View style={{ width: "100%", gap: 4 }}>
          <View style={{ paddingLeft: 25, minHeight: 24, flexDirection: "row", alignItems: "center", gap: 6 }}>
            <Name who={who} onClick={onName} />
            <MessageTime stamp={m.time?.["createdAt"]} />
          </View>
          <QuoteCards quotes={m.quotes} onJump={jump} side="flex-start" />
          <Hold hold={hold}>
            <LocalPickedWords.Provider value={words}>
              {/* A person's words as yours are drawn: a reference to another chat as its chip (web Chat.tsx → PersonWords). */}
              {m.authorKind === "person"
                ? (m.text.length > 0 ? <PersonWords text={m.text} /> : null)
                : <AgentWords ctx={ctx} text={m.text} files={m.attachments} names={m.placed ?? []} draft={draft} />}
            </LocalPickedWords.Provider>
          </Hold>
          {/* An agent's files are placed in its words (Prose.tsx), the rest below them there. */}
          {m.authorKind === "person" && <Files ctx={ctx} list={m.attachments} />}
          {/* A decision it asks (its options): them under it, a line saying how it went once it has. */}
          {decide && <DecisionUnder ctx={ctx} m={m} />}
          {/* It asks what no one has decided (the core's `asked`): letting it go, right under it (web Chat.tsx AskDismiss). */}
          {decide && <AskDismiss ctx={ctx} m={m} />}
          {/* What the archive check made of the chat (web Chat.tsx archiveCheck): a quiet line, red when it failed. */}
          {check != null && <T size={12} line={18} color={check.failed ? C.red : C.muted} style={{ paddingTop: 6 }}>{check.text}</T>}
          {/* Under its agent's latest 做完了 while nothing is left in the chat: archiving it, right there.
              Keep the button alive until its exit finishes; the rest of the row closes the space with it. */}
          {decide && (
            <Expanding visible={ctx.archiveUnder === m.seq} axis="y" origin="50% 0%">
              <ArchiveUnder ctx={ctx} enabled={ctx.archiveUnder === m.seq} />
            </Expanding>
          )}
        </View>
      </EmitOut>
    </Flashed>
  );
}

/** What comes in with words flown here from the composer (their row's time): faded in as they come. */
function FlightFade({ children }: { children?: ReactNode }) {
  const f = useContext(LocalFlight);
  useAnimatable(f?.progress);
  return <View style={{ opacity: f ? f.e() : 1 }}>{children}</View>;
}

/** The session a chat is archived by: the page's, the one its station made of it, else its first agent's. */
function archiveSession(of: ChatOf, view: ChatView, agents: AgentHere[]): string | null {
  return ("session" in of ? of.session : null) ?? view.key ?? agents[0]?.key ?? null;
}

/**
 * Archives the chat (its bar's 归档, and the one under its last 做完了): home at once, the chat gone from the list
 * meanwhile (the core's), not waiting on the station; back in the list, and said, if it could not.
 */
function archiveChat(app: AppState, station: string, view: ChatView, session: string) {
  app.home();
  app.act(t("android-chat.archive.verb"), () => app.api(station).setArchived(view.thread?.id ?? null, session, true), t("android-chat.archived"));
}

/**
 * 归档这个 chat, full width under the agent's latest post that ended its turn all done, while nothing is left in the
 * chat (the core's `archivable`): drawn as buttons (Decisions.tsx OptionButton), this one in the accent, a spinner on it meanwhile.
 */
function ArchiveUnder({ ctx, enabled }: { ctx: Here; enabled: boolean }) {
  useApp((s) => s.doing);
  const session = archiveSession(ctx.of, ctx.view, ctx.agents);
  const thread = ctx.view.thread?.id ?? null;
  if (session == null || thread == null) return null;
  const label = t("android-chat.chat.archiveThis");
  const busy = app.isDoing("chat.archive", { station: ctx.station, session });
  const keep = t("android-chat.chat.keep");
  const keeping = app.isDoing("chat.keep", { station: ctx.station, thread });
  return (
    <View style={{ width: "100%", paddingTop: 6, flexDirection: "row", gap: 6 }}>
      <OptionButton
        label={keep} style={{ flex: 1 }}
        enabled={enabled && !ctx.view.offline && !busy} busy={keeping}
        failed={app.failedOf("chat.keep", { station: ctx.station, thread })}
        onPick={() => app.act(t("android-chat.chat.keep.verb"), async () => { await app.api(ctx.station).keepChat(thread); app.toast = t("android-chat.chat.kept"); })}
      />
      <OptionButton
        label={label} style={{ flex: 1 }} strong
        enabled={enabled && !ctx.view.offline && !keeping} busy={busy}
        onPick={() => archiveChat(app, ctx.station, ctx.view, session)}
      />
    </View>
  );
}

/**
 * What still.fail itself says (web Chat.tsx → SystemNotice): a pill across the chat, in one line and no time, cut short
 * where it does not fit. A tap opens it: all its words, wrapped, and its time under it. The station begins its failures
 * with ⚠️; here a failure is the pill in red instead. A notice is a line of the UI, not prose: no 。 at its end.
 */
function SystemNotice({ text, time, toProfile }: { text: string; time: Stamp | null | undefined; toProfile: (() => void) | null }) {
  const C = useC();
  const failed = useMemo(() => /^⚠️\s*/.exec(text), [text]);
  const said = useMemo(() => (failed ? text.substring(failed[0].length) : text).replace(/。\s*$/, ""), [text, failed]);
  const [open, setOpen] = useState(false);
  const dark = C.dark;
  // The web's --hover (the offline notice's grey), --red-bg and --red.
  const ground = failed ? (dark ? "#442322" : "#FFF0EF") : dark ? withAlpha("#FFFFFF", 0.05) : withAlpha("#262117", 0.065);
  const ink = failed ? (dark ? "#F68482" : "#A12F35") : chatInk(C).text;
  // In one about a profile (its sign-in failed), what went wrong (after its ：) links to that profile's page.
  const colon = toProfile != null ? (said.indexOf("：") >= 0 ? said.indexOf("：") : said.indexOf(":")) : -1;
  const body = toProfile != null && colon >= 0 ? (
    <T size={15} line={24.75} color={ink} numberOfLines={open ? undefined : 1} ellipsizeMode="tail">
      {said.substring(0, colon + 1)}
      <Text style={{ textDecorationLine: "underline" }} onPress={toProfile}>{said.substring(colon + 1)}</Text>
    </T>
  ) : open ? (
    <LocalMdInk.Provider value={ink}><Markdown text={said} /></LocalMdInk.Provider>
  ) : (
    <T size={15} line={24.75} color={ink} numberOfLines={1} ellipsizeMode="tail">{plain(said.split("\n").find((l) => l.trim().length > 0) ?? said)}</T>
  );
  const box: ViewStyle = { backgroundColor: ground, paddingHorizontal: 14, paddingVertical: 6 };
  return (
    <View style={{ width: "100%", alignItems: "center", gap: 4 }}>
      <Pressable onPress={() => setOpen(!open)} style={{ maxWidth: "100%" }}>
        {open ? <Smooth radius={16} style={box}>{body}</Smooth> : <View style={[box, { borderRadius: 999, overflow: "hidden" }]}>{body}</View>}
      </Pressable>
      {open && <MessageTime stamp={time} />}
    </View>
  );
}

/** A spinner and a word, small, under a message of yours: waiting for its agents, or on its way (the chat's own size, not WaitLine's). */
function UnderWay({ text }: { text: string }) {
  const C = useC();
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 5 }}>
      <Spinner inline />
      <T size={10} line={16} color={chatInk(C).muted}>{text}</T>
    </View>
  );
}

/** Your words, in their bubble on the right, a reference to another chat as its chip (ui/Markdown.tsx → withRefs). */
function Bubble({ text, hold, ts = null }: { text: string; hold: PickHold | null; ts?: string | null }) {
  const C = useC();
  const ink = chatInk(C);
  const motion = useChatMotion();
  const flash = lerpColor(ink.neutral, ink.accent, 0.2);
  // Words flying here from the composer (ChatHost.tsx): their bubble forms round them as they come.
  const flight = useContext(LocalFlight);
  const host = useContext(LocalFlightHost);
  const copy = useContext(LocalFlightCopy);
  const row = useContext(LocalRow);
  const fieldWidth = useContext(LocalSendTextWidth);
  useAnimatable(flight?.progress);
  useAnimatable(motion && flashing(motion, ts) ? motion.flash : null);
  useHost(host, (h) => h.flight);
  const bubble = useRef<View | null>(null);
  const [room, setRoom] = useState(0);
  if (flight && !copy) { flight.groundColor = ink.neutral; flight.wordsColor = ink.text; }
  const words = markWeight(pickedText(withRefs(text)));
  const mark = passageMark(words.text);
  // A link in them held: its menu (ui/Links.tsx).
  const links = linkHold(words);
  // A passage picked from them (MessagePick.tsx).
  const pick = pickable(words.text);
  const away = flight != null && host != null && host.flight === flight && flight.pieces() != null;
  // Flown in piece by piece, its ground is the host's (round the words on their way); else it comes in with them.
  const alpha = flight == null ? 1 : !flight.carried && away ? 0 : flight.e();
  const lit = motion != null && flashing(motion, ts) ? motion.flash.value : 0;
  const most = fieldWidth > 0 ? fieldWidth + 28 : room * 0.78;
  const bubbleBox = (
    <Smooth
      radius={18}
      style={{ maxWidth: most > 0 ? most : undefined, paddingHorizontal: 14, paddingVertical: 8 }}
    >
      <View pointerEvents="none" style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0, backgroundColor: lerpColor(ink.neutral, flash, lit), opacity: alpha }} />
      {/* On their way, its words are drawn piece by piece over the composer (ChatHost.tsx FlightLayer), not here. */}
      <View style={{ opacity: away ? 0 : 1 }}>
        {/* NATIVE: a lone full-width mark (？ ！ 。) sits at the left of its wide cell; the Android app cuts that cell to the
            glyph with proportional alternates ("palt"), which React Native's Text cannot ask of the font. */}
        <AnnotatedText
          text={words} modifier={thenText(mark[0], links[0], pick[0])}
          style={[SendTextStyle, { color: ink.text }]}
          onTextLayout={laidBy(mark, links, pick, (e) => { if (flight && !copy) flight.words = textLayoutOf(words.text, e.nativeEvent.lines, SendTextStyle.fontSize); })}
        />
      </View>
    </Smooth>
  );
  return (
    <View style={{ width: "100%", alignItems: "flex-end" }} onLayout={(e) => setRoom(e.nativeEvent.layout.width)}>
      <View
        ref={bubble}
        collapsable={false}
        onLayout={() => { if (flight && host && !copy) flight.bubbleAt({ view: bubble.current, row }, host, { x: 14, y: 8 }, SendTextStyle.lineHeight, SendTextStyle.fontSize); }}
      >
        {hold ? <Hold hold={hold}>{bubbleBox}</Hold> : bubbleBox}
      </View>
    </View>
  );
}

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
function Out({ ctx, o }: { ctx: Here; o: Outgoing }) {
  const C = useC();
  useApp((s) => s.doing);
  const thread = ctx.view.thread ?? null;
  // With no thread yet (a chat made here, or an agent's before its station has made its chat): what failed in it goes
  // by the page's key.
  const pending = "session" in ctx.of ? ctx.of.session : null;
  const failed = o.state === "failed";
  const flight = useContext(LocalFlight);
  const host = useContext(LocalFlightHost);
  useHost(host, (h) => h.flight);
  // On its way, it says so only if that takes a moment, counted from when it was sent: the row is drawn anew as a chat
  // made here takes the page, and counting from then would hide what already showed.
  const [slow, setSlow] = useState(false);
  useEffect(() => { const id = setTimeout(() => setSlow(true), Math.max(0, o.createdAt + 800 - Date.now())); return () => clearTimeout(id); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const on = { station: ctx.station, id: o.id };
  const retrying = app.isDoing("chat.retry", on);
  const discarding = app.isDoing("chat.discard", on);
  return (
    <View style={{ width: "100%", alignItems: "flex-end", gap: 4 }}>
      {/* Not sent: what was written faded. */}
      <View style={{ width: "100%", alignItems: "flex-end", gap: 4, opacity: failed ? 0.55 : 1 }}>
        <QuoteCards quotes={o.quotes} onJump={null} side="flex-end" />
        {o.text.length > 0 && <Bubble text={o.text} hold={null} />}
        <Files ctx={ctx} list={o.attachments} mine />
      </View>
      {/* Said briefly (a tap says why); sending it again or dropping it right beside. */}
      {failed ? (
        <View style={{ paddingTop: 4, flexDirection: "row", alignItems: "center", gap: 2 }}>
          <Pressable
            onPress={() => { app.toast = o.error != null ? t("android-chat.chat.unsent.why", { error: o.error }) : t("android-chat.chat.unsent.toast"); }}
            style={{ paddingRight: 6, flexDirection: "row", alignItems: "center", gap: 4 }}
          >
            <Icon icon={Icons.Info} size={12} color={C.red} />
            <T size={13} color={C.red}>{t("android-chat.chat.unsent")}</T>
          </Pressable>
          {/* Either under way: a spinner on it, neither pressed again. */}
          <UnsentButton
            icon={Icons.Retry} label={t("common.retry")} enabled={!ctx.view.offline && ctx.view.archived !== true && !discarding} busy={retrying} failed={app.failedOf("chat.retry", on)}
            onClick={() => app.act(t("android-chat.chat.retry.verb"), async () => { if (thread) await app.api(ctx.station).retry(thread.id, o.id); else if (pending != null) await app.api(ctx.station).retryIn(pending, o.id); })}
          />
          <UnsentButton
            icon={Icons.Trash} label={t("common.delete")} enabled={!retrying} busy={discarding} failed={app.failedOf("chat.discard", on)}
            onClick={() => app.act(t("android-chat.chat.delete.verb"), async () => { if (thread) await app.api(ctx.station).discard(thread.id, o.id); else if (pending != null) await app.api(ctx.station).discardIn(pending, o.id); })}
          />
        </View>
      ) : slow ? (
        // Not while its words are on their way here (ChatHost.tsx): only once they have landed, if it is still going.
        <View style={{ opacity: flight != null && host?.flight === flight ? 0 : 1 }}><UnderWay text={t("android-chat.chat.sending")} /></View>
      ) : null}
    </View>
  );
}

function UnsentButton({ icon, label, enabled = true, busy = false, failed = null, onClick }: { icon: IconPaths; label: string; enabled?: boolean; busy?: boolean; failed?: string | null; onClick: () => void }) {
  const C = useC();
  const muted = chatInk(C).muted;
  return (
    <Smooth radius={7} style={{ opacity: enabled ? 1 : 0.5 }}>
      <Pressable
        disabled={!enabled || busy} onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1) }}
        style={{ paddingHorizontal: 7, paddingVertical: 3, flexDirection: "row", alignItems: "center", gap: 4 }}
      >
        {busy || failed != null ? <DoingMark running={busy} failed={failed} inline /> : <Icon icon={icon} size={12} color={muted} />}
        <T size={13} color={muted}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/**
 * Goes to a quoted message by its ts, as the web does (Chat.tsx → Quotes → jump): at once, its passage in the middle of
 * the list, or a whole message (no passage) at the top as the unread line puts one; then it flashes (a reader's move:
 * the list follows the newest again only if that leaves it at the end).
 */
function rememberJump(list: LazyListState, rows: Entry[], given?: ChatMotion | null): (ts: string, passage: string) => void {
  const C = useC();
  const fromContext = useContext(LocalChatMotion);
  const motion = given === undefined ? fromContext : given;
  const accent = chatInk(C).accent;
  return (ts, passage) => {
    const index = rows.findIndex((r) => r.kind === "Said" && r.m.ts === ts);
    // Opened from a search: its words are marked already (ChatMotion.markWords), nothing flashes.
    const found = passage === FOUND;
    if (index < 0 || !motion) return;
    void (async () => {
      const follow = motion.follow;
      if (follow) follow.anchor = null;
      if (!found) motion.lead(ts, passage, accent);
      // The list's own move (not the reader's): it stays there through a resize, the keyboard going as the chat
      // opens from a search (Follow.topHeld), until the reader moves it.
      if (follow) follow.own = follow.own + 1;
      try {
        // Its top just below the bar (the list's top padding).
        await list.scrollToItem(index);
        const pane = motion.where?.pane ?? null;
        const height = list.layoutInfo.viewportSize.height;
        if (found) {
          // The first word low in a long message: it is what comes to the middle.
          await frame();
          const mid = pane && motion.found ? await middleIn(motion.found, pane) : null;
          if (mid && mid.y > height * 0.8) await list.scrollBy(mid.y - height / 2);
        } else if (passage.length > 0) {
          const info = list.layoutInfo;
          const item = info.visibleItemsInfo.find((i) => i.index === index);
          if (item) await list.scrollBy(item.offset + item.size / 2 - (info.viewportStartOffset + info.viewportEndOffset) / 2);
          // The passage, found in its words, is what goes in the middle (web: the range's middle at the pane's).
          await frame();
          const mid = pane && motion.mark ? await middleIn(motion.mark, pane) : null;
          if (mid) await list.scrollBy(mid.y - height / 2);
        }
      } catch { /* taken over by the reader */ } finally {
        if (follow) follow.own = follow.own - 1;
      }
      if (follow) { follow.topHeld = true; follow.on = follow.atEnd(); }
      if (found) await motion.drawFound(); else await motion.playFlash();
    })();
  };
}

/** What rememberJump is given in place of a passage for a message opened from a search (its words marked instead). */
const FOUND = "\u0000found";

/** A quote's passage as a card shows it: the mark in the accent, whose it is, what it says (words to put in a Text). */
export function quoteLine(who: string, text: string): ReactNode {
  const C = useC();
  const ink = chatInk(C);
  return (
    <>
      <View style={{ width: 15, height: 13, justifyContent: "center" }}><Icon icon={Icons.Quote} size={11} color={ink.accent} /></View>
      <Text style={{ color: ink.text, fontWeight: "500" }}>{t("android-chat.quote.who", { name: who })}</Text>
      {text}
    </>
  );
}

/** The mark before a quote's passage, as inline content (quoteLine draws it in its words itself). */
export function quoteMark(): Record<string, InlineTextContent> {
  const C = useC();
  const accent = chatInk(C).accent;
  return { quote: { width: 15, height: 13, children: <View style={{ flex: 1, justifyContent: "center" }}><Icon icon={Icons.Quote} size={11} color={accent} /></View> } };
}

/**
 * Quotes as sent, each a card of its own ahead of the message (web Chat.tsx → Quotes, QuoteCard): the passage, small and
 * grey, leading back to it; then what was said about it.
 */
function QuoteCards({ quotes, onJump, side }: { quotes: Quote[]; onJump: ((ts: string, passage: string) => void) | null; side: "flex-start" | "flex-end" }) {
  const [width, setWidth] = useState(0);
  if (quotes.length === 0) return null;
  const most = Math.min(380, width * 0.88);
  return (
    <View style={{ width: "100%", alignItems: side, gap: 4 }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
      {quotes.map((q, i) => <QuoteCard key={i} q={q} onJump={onJump} style={{ maxWidth: most > 0 ? most : undefined }} />)}
    </View>
  );
}

function QuoteCard({ q, onJump, style }: { q: Quote; onJump: ((ts: string, passage: string) => void) | null; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const ink = chatInk(C);
  const ts = q.ts ?? null;
  const line = (
    <T size={13} line={19.5} color={ink.muted} numberOfLines={2} ellipsizeMode="tail" style={{ paddingLeft: 11, paddingRight: 11, paddingTop: 7, paddingBottom: q.comment.length === 0 ? 7 : 0 }}>
      {quoteLine(q.author, q.text)}
    </T>
  );
  return (
    <Smooth radius={12} style={[{ backgroundColor: ink.card }, style]}>
      {ts != null && onJump != null ? <Pressable onPress={() => onJump(ts, q.text)} android_ripple={{ color: withAlpha(C.ink, 0.1) }}>{line}</Pressable> : line}
      {q.comment.length > 0 && <T size={15} line={22.5} color={ink.text} style={{ paddingLeft: 11, paddingRight: 11, paddingTop: 3, paddingBottom: 8 }}>{q.comment}</T>}
    </Smooth>
  );
}

// ── the running turn ───────────────────────────────────────────────────

/** A move of `ms` along `easing` to `to` (Compose's animateFloatAsState with a tween). */
function useTweened(to: number, ms: number, easing?: (typeof Ease)[keyof typeof Ease]) {
  const v = useSharedValue(to);
  useEffect(() => { v.value = withTiming(to, { duration: ms, ...(easing ? { easing } : {}) }); }, [to, ms, easing, v]);
  return v;
}

/** What the activity says now, coming in from a quarter below and the one before going a quarter up (AnimatedContent, 240ms). */
const nowIn = (values: { targetHeight: number }) => {
  "worklet";
  return {
    initialValues: { opacity: 0, transform: [{ translateY: values.targetHeight / 4 }] },
    animations: { opacity: withTiming(1, { duration: 240 }), transform: [{ translateY: withTiming(0, { duration: 240 }) }] },
  };
};
const nowOut = (values: { currentHeight: number }) => {
  "worklet";
  return {
    initialValues: { opacity: 1, transform: [{ translateY: 0 }] },
    animations: { opacity: withTiming(0, { duration: 240 }), transform: [{ translateY: withTiming(-values.currentHeight / 4, { duration: 240 }) }] },
  };
};

/**
 * An agent at work, in one line (as the web's): its avatar, ringed while it works, and what it does now (as the core
 * says), with how long its turn has run. No name: the avatar says whose. A new thing crossfades in once the shown one
 * has stayed a moment, so a passing 请求中 does not flicker by; the same thing's new words (its rate) show at once.
 */
function Activity({ ctx, agent, leaving, opening = false }: { ctx: Here; agent: AgentAtWork; leaving: boolean; opening?: boolean }) {
  const C = useC();
  const motion = useChatMotion();
  const row = useContext(LocalRow);
  // A message coming out of its avatar: the line folds to its avatar (what it does, 200ms --ease-out; faded by 160ms),
  // and the avatar is away while its copy flies (ChatMotion.tsx).
  const folded = motion?.folded(agent.key) === true;
  const tail = useTweened(folded ? 0 : 1, 200, Ease.Out);
  const tailFade = useTweened(folded ? 0 : 1, 160, Ease.Out);
  // Coming in, its room opens from nothing (web activityIn: grid rows 0fr → 1fr, 220ms --ease-out) as it fades in and grows.
  const open = useSharedValue(opening ? 0 : 1);
  useEffect(() => { open.value = withTiming(1, { duration: 220, easing: Ease.Out }); }, [open]);
  const wait = agent.wait;
  const ink = chatInk(C);
  const shown = steady(wait != null ? { key: "wait", text: wait.text ?? t("android-chat.chat.waiting") } : agent.live?.activity?.now ?? { key: "busy", text: t("android-chat.chat.working") });
  useTicking(true, 1000);
  const now = Date.now();
  const fade = useTweened(leaving ? 0 : 1, 220);
  const [pressed, setPressed] = useState(false);
  const [natural, setNatural] = useState<{ width: number; height: number } | null>(null);
  const [tailWidth, setTailWidth] = useState<number | null>(null);
  const avatar = useRef<View | null>(null);
  const rowView = useRef<View | null>(null);
  useEffect(() => () => {
    if (motion?.activityAvatars.get(agent.key)?.view === avatar.current) motion?.activityAvatars.delete(agent.key);
    if (motion?.activityRows.get(agent.key)?.view === rowView.current) motion?.activityRows.delete(agent.key);
  }, [motion, agent.key]);
  // Nothing is cut: its room opens (what is under it moves down) while it fades in and grows from its avatar,
  // .5 → 1 (the ring reaches 3dp past the row's start, into the list's side room). Its press is drawn round
  // rather than clipped, and it fades by a layer that does not clip.
  const roomStyle = useAnimatedStyle(() => (natural ? { height: natural.height * open.value } : {}), [natural]);
  const look = useAnimatedStyle(() => ({ opacity: open.value * fade.value, transform: [{ scale: 0.5 + 0.5 * open.value }] }));
  const tailStyle = useAnimatedStyle(() => (tailWidth != null ? { width: tailWidth * tail.value, opacity: tailFade.value } : { opacity: tailFade.value }), [tailWidth]);
  const copied = motion?.copied === agent.key;
  return (
    <Animated.View style={[{ width: "100%" }, roomStyle]}>
      <Animated.View
        ref={(v: View | null) => { rowView.current = v; if (v) motion?.activityRows.set(agent.key, { view: v, row }); }}
        collapsable={false}
        onLayout={(e) => setNatural({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}
        style={[{ width: "100%", transformOrigin: [9, "50%", 0] }, look]}
      >
        {pressed && <Smooth radius={6} pointerEvents="none" style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0, backgroundColor: withAlpha(C.ink, 0.1) }} />}
        <Pressable
          onPress={() => openHistory(app, ctx.station, ctx.of, agent.key)}
          onPressIn={() => setPressed(true)} onPressOut={() => setPressed(false)}
          style={{ flexDirection: "row", alignItems: "center", gap: 5 }}
        >
          {/* The avatar where its message lands (the messages' 18dp), its ring 3dp round it. Hidden and shown in the
              very frame its flying copy takes over and lets go. */}
          <View style={{ width: 24, height: 24, marginLeft: -3, marginRight: 3, alignItems: "center", justifyContent: "center", opacity: copied ? 0 : 1 }}>
            <View ref={(v) => { avatar.current = v; if (v) motion?.activityAvatars.set(agent.key, { view: v, row }); }} collapsable={false}>
              <AgentAvatar maker={agent.maker} runtime={agent.runtime} />
            </View>
            <View style={{ position: "absolute", left: 0, top: 0 }}><WorkRing waiting={wait != null} leaving={leaving} shared={motion?.ring ?? null} /></View>
          </View>
          <Animated.View style={[{ flexShrink: 1, overflow: "hidden" }, tailStyle]}>
            <View
              style={{ flexDirection: "row", alignItems: "center", gap: 5, alignSelf: "flex-start" }}
              onLayout={(e) => { if (!folded || tailWidth == null) setTailWidth(e.nativeEvent.layout.width); }}
            >
              <View style={{ flexShrink: 1 }}>
                <Animated.View key={shown.key} entering={nowIn} exiting={nowOut}>
                  <T size={15} color={ink.muted} numberOfLines={1} ellipsizeMode="tail">{shown.text}</T>
                </Animated.View>
              </View>
              <View style={{ width: 3 }} />
              {wait != null ? (
                <T size={15} color={ink.subtle} numberOfLines={1}>
                  {elapsed((wait.seconds != null ? Math.min(now, wait.since + wait.seconds * 1000) : now) - wait.since) + (wait.seconds != null ? ` / ${elapsed(wait.seconds * 1000)}` : "")}
                </T>
              ) : agent.since != null ? <T size={15} color={ink.subtle} numberOfLines={1}>{elapsed(now - agent.since)}</T> : null}
            </View>
          </Animated.View>
        </Pressable>
      </Animated.View>
    </Animated.View>
  );
}

const AnimatedPath = Animated.createAnimatedComponent(Path);

/**
 * The ring round an agent at work (as the web's activityRing): an arc in the accent that stretches and shrinks as it
 * turns, each 1.5s from 5° to 235° and back while its tail runs a full round, ahead of a steady turn every 2s. Waiting on
 * work it started, a still, quiet one.
 */
function WorkRing({ waiting, leaving, shared = null }: { waiting: boolean; leaving: boolean; shared?: SharedValue<number> | null }) {
  const C = useC();
  const accent = chatInk(C).accent;
  // The chat's own clock (ChatMotion.ring), when there is one: the flying avatar's ring and its activity's as one,
  // and do not jump as the one hands over to the other.
  const own = ringClock();
  const clock = shared ?? own;
  const shown = useTweened(leaving ? 0 : 1, 160);
  const fade = useAnimatedStyle(() => ({ opacity: shown.value }));
  const w = 1.5;
  const r = (24 - w) / 2;
  const props = useAnimatedProps(() => {
    const t = clock.value;
    // Each half of its 1.5s eased in and out (the web's ease-in-out keyframes): growing, its tail 0 → 60°; shrinking, 60 → 360°.
    const p = (t % 1500) / 1500;
    const k = ringEase(p < 0.5 ? p * 2 : p * 2 - 1);
    const tail = p < 0.5 ? 60 * k : 60 + 300 * k;
    const sweep = p < 0.5 ? 5 + 230 * k : 235 - 230 * k;
    const from = ((t / 2000) * 360 + tail) * (Math.PI / 180);
    const to = from + sweep * (Math.PI / 180);
    const c = 12;
    const x0 = c + r * Math.cos(from);
    const y0 = c + r * Math.sin(from);
    const x1 = c + r * Math.cos(to);
    const y1 = c + r * Math.sin(to);
    return { d: `M ${x0} ${y0} A ${r} ${r} 0 ${sweep > 180 ? 1 : 0} 1 ${x1} ${y1}` };
  });
  return (
    <Animated.View style={[{ width: 24, height: 24 }, fade]}>
      <Svg width={24} height={24}>
        {waiting
          ? <Circle cx={12} cy={12} r={r} stroke={C.line} strokeWidth={w} fill="none" />
          : <AnimatedPath animatedProps={props} stroke={accent} strokeWidth={w} strokeLinecap="round" fill="none" />}
      </Svg>
    </Animated.View>
  );
}

/** CSS's ease-in-out (.42, 0, .58, 1), on the UI thread. */
const RING_EASE = REasing.bezierFn(0.42, 0, 0.58, 1);
function ringEase(x: number) { "worklet"; return RING_EASE(x); }

/** The work ring's clock: ms into its 6s loop, which its turn (2s) and its stretch (1.5s) both come round in. */
function ringClock(): SharedValue<number> {
  const v = useSharedValue(0);
  useEffect(() => { v.value = withRepeat(withTiming(6000, { duration: 6000, easing: REasing.linear }), -1, false); }, [v]);
  return v;
}

/** What an activity shows, steadied: another thing replaces the shown one after it has stayed 700 ms. */
function steady(said: ActivityNow): ActivityNow {
  const [shown, setShown] = useState(said);
  const at = useRef(0);
  const latest = useRef(said);
  latest.current = said;
  useEffect(() => {
    if (said.key === shown.key || said.text === shown.text) { setShown(said); return; }
    const id = setTimeout(() => { setShown(latest.current); at.current = Date.now(); }, Math.max(0, at.current + 700 - Date.now()));
    return () => clearTimeout(id);
  }, [said.key, said.text]); // eslint-disable-line react-hooks/exhaustive-deps
  return shown;
}

/** A running clock's reading in short, as the web's: 45s, 3m 20s, 1h 5m. */
export function elapsed(ms: number): string {
  const s = Math.max(0, Math.trunc(ms / 1000));
  if (s < 60) return `${s}s`;
  if (s < 3600) return s % 60 !== 0 ? `${Math.trunc(s / 60)}m ${s % 60}s` : `${Math.trunc(s / 60)}m`;
  return Math.trunc((s % 3600) / 60) !== 0 ? `${Math.trunc(s / 3600)}h ${Math.trunc((s % 3600) / 60)}m` : `${Math.trunc(s / 3600)}h`;
}
