// Decisions (web mobile, the same interaction set): an agent's post that ends its turn asking people to decide carries
// options. In the chat they are a column of buttons right under the post, full width, one per line, the one the agent
// recommends last and filled in ink; a tap answers with it (the viewer's message, quoting the post). Answered (or
// replaced), the buttons go and a quiet line says how it went.
// The decisions page 「奏」 (from the home page's 奏 N) shows the workspace's decisions waiting for the viewer one at a
// time: the chat's title small at the top (to its chat), the messages before the post and the post itself as the chat
// draws them, and at the foot its options, the hint and `1 / N`. The whole decision is swiped: left 待定 (set aside on
// this device: last of the page, still waiting), right 不再提醒 (dismissed for the viewer). Let go past about a third
// of the width, or flung, it flies off and the next comes in; short of that it springs back.
// Options and text cards both have a multiline reply field on the page, below any options
// offered (the reply is the viewer's message quoting the post, `decision.reply`); a swipe never starts in the field. A card
// of a type this app does not know is answered in its chat. In a chat only an options card has anything under it.
import { useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Pressable, ScrollView, StyleSheet, View, type LayoutChangeEvent, type StyleProp, type ViewStyle } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { Easing, runOnJS, useAnimatedKeyboard, useAnimatedStyle, useSharedValue, withDelay, withSpring, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { Attachment, ChatMessage, ChatView, DecisionItem, DecisionOption, DecisionsView } from "../../../../web/src/core/shapes.ts";
import { LocalApp, useApp, type ChatOf } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { rememberTopic, Topics } from "../data/Topics";
import { errorText } from "../data/Calls";
import { ChatState } from "../data/Chats";
import { LocalBarRoom, placeLabel } from "../Places";
import { t } from "../i18n";
import { chatSubtle } from "../ui/ChatInk";
import { DoingMark } from "../ui/Controls";
import { Drawing } from "../ui/Drawing";
import { Icon, Icons } from "../ui/Icon";
import { Ease, MoveSpring } from "../ui/Motion";
import { AgentStateMark, reducedMotion } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { BusyIcon, WaitPill, WaitShape, Waiting } from "../ui/Waiting";
import { AttachLaunchers, openAttach } from "./Attach";
import { Here, SaidAlone } from "./Chat";
import { Host, HostComposer } from "./ChatHost";
import { rememberDraft, upload, type DraftQuote, type Pending, type Picked } from "./Composer";
import { closeGapSpring, CLOSE_DELAY_MS, CssEaseOut, LEAVE_MS } from "./ListMotion";
import { letsGoOfPick, LocalMessagePick, MessagePick, PickLayer } from "./MessagePick";
import { PlacePage } from "./PlacePage";
import { DecisionOptions } from "./SettingParts";
import { VaultApproval } from "./Vault";

/** A box in the window (what Compose's LayoutCoordinates give the deck here): where a text card's field is. */
interface Rect { x: number; y: number; width: number; height: number }

/** What a failure says (data/Calls.ts errorText), whatever was thrown. */
const why = (e: unknown) => (e instanceof CoreError ? errorText(e) : e instanceof Error ? e.message : String(e));

/** Compose's touch slop (ViewConfiguration's 8dp). */
const TOUCH_SLOP = 8;

// ── the options ────────────────────────────────────────────────────────

/**
 * A button as wide as it is given (留着 / 归档这个 chat under a post that ended all done, Chat.tsx ArchiveUnder): the
 * label in medium, in the accent with white words when `strong`, the chip colour otherwise; a spinner while `busy`,
 * a mark when `failed`.
 */
export function OptionButton({ label, style, strong = false, enabled = true, busy = false, failed: why = null, onPick }: { label: string; style?: StyleProp<ViewStyle>; strong?: boolean; enabled?: boolean; busy?: boolean; failed?: string | null; onPick: () => void }) {
  const C = useC();
  const still = reducedMotion();
  const ink = strong ? "#FFFFFF" : C.ink;
  const scale = useSharedValue(1);
  const press = (pressed: boolean) => {
    scale.value = withTiming(pressed && !still ? 0.97 : 1, { duration: still ? 0 : pressed ? 80 : 180, easing: Ease.Out });
  };
  const pressing = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));
  return (
    <Animated.View style={[{ alignSelf: "stretch" }, style, pressing]}>
      <Smooth radius={12} style={{ backgroundColor: strong ? C.accent : C.chip }}>
        <Pressable
          disabled={!enabled || busy}
          onPress={onPick}
          onPressIn={() => press(true)}
          onPressOut={() => press(false)}
          android_ripple={{ color: withAlpha(ink, 0.1) }}
          accessible
          style={{ paddingHorizontal: 14, paddingVertical: 10 }}
        >
          <View style={{ flexDirection: "row", alignItems: "center", gap: 8, opacity: enabled ? 1 : 0.5 }}>
            <T size={15} line={21} weight="500" color={ink} style={{ flex: 1, minWidth: 0 }}>{label}</T>
            {/* On the solid one the spinner turns in its words' white (BusyIcon's rule); what failed, the core's red mark. */}
            {busy ? <BusyIcon busy solid={strong ? ink : null} /> : why != null ? <DoingMark running={false} failed={why} /> : null}
          </View>
        </Pressable>
      </Smooth>
    </Animated.View>
  );
}

/**
 * What comes and goes under a post (Compose's AnimatedVisibility as DecisionUnder has it): going, it fades and (with
 * `scaleOut`) shrinks to 0.9 over LEAVE_MS while the delayed spring of the chat list's archive closes its space towards
 * its top, drawn beyond it as it closes (clip = false); coming (`enter`), its space opens with the same spring and it
 * fades in once what went has gone (a LEAVE_MS delay). Without `enter` it is there at once; reduced motion, all at once.
 */
function Fold({ visible, enter, scaleOut, still, children }: { visible: boolean; enter: boolean; scaleOut: boolean; still: boolean; children: ReactNode }) {
  const [present, setPresent] = useState(visible);
  // In flow as it is while it stays; its height held and moving while it comes or goes.
  const [folding, setFolding] = useState(false);
  const natural = useRef(0);
  const height = useSharedValue(0);
  const opacity = useSharedValue(1);
  const scale = useSharedValue(1);
  const was = useRef(visible);
  const settled = (shown: boolean) => { setFolding(false); if (!shown) setPresent(false); };
  useEffect(() => {
    if (was.current === visible) return;
    was.current = visible;
    if (visible) {
      setPresent(true);
      if (still || !enter) { setFolding(false); opacity.value = 1; scale.value = 1; return; }
      // Opened once it is laid out (its height known): from nothing.
      natural.current = 0;
      height.value = 0;
      opacity.value = 0;
      scale.value = 1;
      setFolding(true);
    } else {
      if (still) { setPresent(false); return; }
      height.value = natural.current;
      setFolding(true);
      opacity.value = withTiming(0, { duration: LEAVE_MS, easing: CssEaseOut });
      if (scaleOut) scale.value = withTiming(0.9, { duration: LEAVE_MS, easing: CssEaseOut });
      height.value = withDelay(CLOSE_DELAY_MS, withSpring(0, closeGapSpring, (done) => { if (done) runOnJS(settled)(false); }));
    }
  }, [visible]);
  const measured = (e: LayoutChangeEvent) => {
    const h = e.nativeEvent.layout.height;
    const first = natural.current === 0;
    natural.current = h;
    // Coming in: its space opens to what it measures, and it fades in after what went.
    if (folding && visible && first && h > 0) {
      height.value = withDelay(CLOSE_DELAY_MS, withSpring(h, closeGapSpring, (done) => { if (done) runOnJS(settled)(true); }));
      opacity.value = withDelay(LEAVE_MS, withTiming(1, { duration: LEAVE_MS, easing: CssEaseOut }));
    }
  };
  const held = useAnimatedStyle(() => ({ height: height.value, opacity: opacity.value, transform: [{ scale: scale.value }] }));
  if (!present) return null;
  if (!folding) return <View onLayout={(e) => { natural.current = e.nativeEvent.layout.height; }}>{children}</View>;
  return (
    <Animated.View style={[{ overflow: "visible" }, held]}>
      <View onLayout={measured}>{children}</View>
    </Animated.View>
  );
}

/**
 * Under a post in a chat (Chat.tsx SaidRow): its options while it waits, a tap answering with one; once answered (or
 * dismissed by the viewer, or replaced), no buttons, and how it went in a quiet line when the core says. Nothing under
 * other messages, nor from a station before decisions.
 */
export function DecisionUnder({ ctx, m }: { ctx: Here; m: ChatMessage }) {
  const app = useContext(LocalApp);
  const C = useC();
  const subtle = chatSubtle(C);
  const still = reducedMotion();
  useApp((s) => s.doing);
  const card = m.card;
  if (card == null && m.options == null) return null;
  // Buttons only for an options card (a core before cards: `options` alone); a text card is answered on the 奏 page.
  const options = card != null ? (card.type === "options" ? card.options : undefined) : m.options;
  const decision = m.decision;
  const resolved = decision?.resolved === true || decision?.dismissed === true;
  if (options == null || options.length === 0) {
    const label = resolved ? decision?.text : card?.assigneeText;
    return label != null ? <T size={13} line={19} color={subtle} style={{ paddingTop: 2 }}>{label}</T> : null;
  }
  const station = ctx.station;
  const busy = options.find((o) => app.isDoing("decision.answer", { station, thread: m.thread, seq: m.seq, option: o.label }))?.label ?? null;
  // An agent's request for a vault item: approved here (Vault.tsx), not answered in the chat.
  const vault = card?.vault;
  const me = ctx.view.me.email;
  const who = card?.assignee;
  return (
    <View>
      {/* Match chat-list archive: the whole group shrinks/fades, then a delayed spring closes its space. */}
      <Fold visible={!resolved} enter={false} scaleOut still={still}>
        <View>
          {card?.assigneeText != null && <T size={13} line={19} color={subtle} style={{ paddingTop: 2 }}>{card.assigneeText}</T>}
          {vault != null ? (
            <VaultApproval workspace={station.split("/")[0]!} request={vault} mine={who == null || me == null || who.toLowerCase() === me.toLowerCase()} style={{ paddingTop: 6 }} />
          ) : (
            <DecisionOptions
              options={options}
              style={{ paddingTop: 6 }}
              enabled={!ctx.view.offline && ctx.view.archived !== true}
              busy={busy}
              onPick={(o: DecisionOption) => { if (!resolved) app.act(t("android-misc.decisions.answerWhat"), () => app.api(station).answerDecision(m.thread, m.seq, o.label)); }}
            />
          )}
        </View>
      </Fold>
      <Fold visible={resolved && decision?.text != null} enter scaleOut={false} still={still}>
        <T size={13} line={19} color={subtle} style={{ paddingTop: 2 }}>{decision?.text ?? ""}</T>
      </Fold>
    </View>
  );
}

// ── the page ───────────────────────────────────────────────────────────

/** A decision's own key: its station, chat and post. */
const keyOf = (d: DecisionItem) => `${d.station}\t${d.thread}\t${d.seq}`;

/** Let go past this share of its width, the decision goes. */
const THRESHOLD = 0.35;

/**
 * What this device did to the page's decisions before the core says so (kept with the page): one answered or dismissed
 * is not shown, one set aside goes last; each until the core's list has it so. Changes draw the page again (`changed`).
 */
class DecisionsLocal {
  gone: string[] = [];
  later: string[] = [];
  /** The decision in front came in as the one before went: it comes in, not there at once. */
  arriving = false;
  // Keep a reply visible if the core removes it before its exit finishes.
  replying: DecisionItem | null = null;
  constructor(private readonly changed: () => void) {}

  addGone(key: string) { this.gone = [...this.gone, key]; this.changed(); }
  setLater(key: string) { this.later = [...this.later.filter((k) => k !== key), key]; this.changed(); }

  undo(key: string) {
    if (!this.gone.includes(key) && !this.later.includes(key)) return;
    this.gone = this.gone.filter((k) => k !== key);
    this.later = this.later.filter((k) => k !== key);
    this.changed();
  }

  caughtUp(items: DecisionItem[]) {
    const keys = new Set(items.map(keyOf));
    const gone = this.gone.filter((k) => keys.has(k));
    const later = this.later.filter((k) => keys.has(k));
    if (gone.length === this.gone.length && later.length === this.later.length) return;
    this.gone = gone;
    this.later = later;
    this.changed();
  }

  shown(items: DecisionItem[]): DecisionItem[] {
    const held = this.replying;
    const source = held != null ? [held, ...items.filter((i) => keyOf(i) !== keyOf(held))] : items;
    const left = source.filter((i) => !this.gone.includes(keyOf(i)));
    const moved = left.filter((i) => this.later.includes(keyOf(i)));
    const rest = left.filter((i) => !this.later.includes(keyOf(i)));
    return [...rest, ...this.later.map((k) => moved.find((i) => keyOf(i) === k)).filter((i): i is DecisionItem => i != null)];
  }
}

export function DecisionsScreen({ current }: { current: WorkspaceEntry }) {
  const topic = rememberTopic<DecisionsView>(Topics.decisions(current.workspace.id));
  const [, setVersion] = useState(0);
  const local = useMemo(() => new DecisionsLocal(() => setVersion((v) => v + 1)), []);
  const view = topic.value;
  const items = view?.items ?? [];
  useEffect(() => { local.caughtUp(items); });
  const shown = local.shown(items);
  // With none left the page stays, for the next to come.
  // Its foot over the bottom bar when it is there (the keyboard, when up, is higher: the bar steps aside for it).
  const room = useContext(LocalBarRoom);
  const insets = useSafeAreaInsets();
  const keyboard = useAnimatedKeyboard();
  const foot = useAnimatedStyle(() => ({ paddingBottom: Math.max(keyboard.height.value, insets.bottom + room) }));
  // 令 in the bar's notch, as on the chats' list; nothing of its own to add.
  return (
    <PlacePage current={current} place="decisions" primary={null} back={placeLabel("chats")}>
      {(top: number) => (
        <Animated.View style={[{ flex: 1 }, foot]}>
          {shown.length === 0 ? (
            // None yet while stations are still read is not none: their cards to come, and what each still waits on.
            // All read, the day so far (a station that could not be read said in red over it). It scrolls under the top bar.
            view != null && !view.wait.reading ? <Idle view={view} top={top} style={{ flex: 1 }} /> : (
              <>
                <View style={{ height: top }} />
                <Waiting shape={WaitShape.Cards} count={2} error={topic.error?.message ?? null} note={view?.wait ?? null} style={{ flex: 1 }} />
              </>
            )
          ) : (
            <>
              <View style={{ height: top }} />
              <Deck shown={shown} local={local} style={{ flex: 1 }} />
            </>
          )}
        </Animated.View>
      )}
    </PlacePage>
  );
}

/**
 * None left (web DecisionsIdle.tsx): the page stays for the next to come and says how the day went (how many answered,
 * how long they waited on average, how many agents are at work), where the next may come from (the viewer's chats with
 * an agent at work or waiting) and what was answered today. Each opens its chat.
 */
function Idle({ view, top, style }: { view: DecisionsView; top: number; style?: StyleProp<ViewStyle> }) {
  const app = useContext(LocalApp);
  const C = useC();
  const today = view.today;
  const working = view.working ?? [];
  const answered = view.answered ?? [];
  return (
    <ScrollView style={[{ alignSelf: "stretch" }, style]} contentContainerStyle={{ paddingLeft: 16, paddingRight: 16, paddingTop: top + 16, paddingBottom: 24 }}>
      <View style={{ alignSelf: "stretch", alignItems: "center" }}>
        {view.wait.failing.map((f, i) => <WaitPill key={i} text={f.text} error style={{ marginBottom: 8 }} />)}
        <Drawing name={C.dark ? "buddy_idle_dark" : "buddy_idle"} width={72} height={72} />
        <T size={17} weight="600" style={{ paddingTop: 8 }}>{t("android-misc.decisions.idle.title")}</T>
        <T size={14} color={C.muted} style={{ paddingTop: 4 }}>{t("android-misc.decisions.idle.note")}</T>
        {today != null && (
          <View style={{ flexDirection: "row", paddingTop: 14, gap: 28 }}>
            <Figure figure={String(today.count)} words={t("android-misc.decisions.idle.answered")} />
            {today.waited != null && <Figure figure={today.waited} words={t("android-misc.decisions.idle.waited")} />}
            <Figure figure={String(today.working)} words={t("android-misc.decisions.idle.working")} />
          </View>
        )}
      </View>
      {working.length > 0 && (
        <>
          <IdleTitle text={t("android-misc.decisions.idle.workingTitle")} />
          {working.map((w) => (
            <IdleRow key={`${w.station}/${w.session}`} main={w.title} meta={w.line} at={w.time?.["lastActiveAt"]?.ago ?? ""} busy onOpen={() => app.push({ kind: "Chat", station: w.station, of: { session: w.session } })} />
          ))}
        </>
      )}
      {answered.length > 0 && (
        <>
          <IdleTitle text={t("android-misc.decisions.idle.answeredTitle")} />
          {answered.map((a) => (
            <IdleRow key={`${a.station}/${a.thread}/${a.seq}`} main={a.text} meta={`${a.title} · ${a.answer}`} at={a.clock} busy={false} onOpen={() => app.push({ kind: "Chat", station: a.station, of: { session: a.session } })} />
          ))}
        </>
      )}
    </ScrollView>
  );
}

function Figure({ figure, words }: { figure: string; words: string }) {
  const C = useC();
  return (
    <View style={{ alignItems: "center" }}>
      <T size={20} weight="600">{figure}</T>
      <T size={12} color={C.subtle}>{words}</T>
    </View>
  );
}

function IdleTitle({ text }: { text: string }) {
  const C = useC();
  return <T size={12} weight="500" color={C.subtle} style={{ paddingLeft: 10, paddingTop: 28, paddingBottom: 4 }}>{text}</T>;
}

/** A chat at work (the turning yellow ring) or a card answered (a quiet dot): its words over where it is, when at its end. */
function IdleRow({ main, meta, at, busy, onOpen }: { main: string; meta: string; at: string; busy: boolean; onOpen: () => void }) {
  const C = useC();
  return (
    <Smooth radius={10} style={{ alignSelf: "stretch" }}>
      <Pressable onPress={onOpen} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ flexDirection: "row", paddingHorizontal: 10, paddingVertical: 8, gap: 10 }}>
        <View style={{ marginTop: 4, width: 12, height: 12, alignItems: "center", justifyContent: "center" }}>
          {busy ? <AgentStateMark state={ChatState.Running} around={C.bg} /> : <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: C.subtle }} />}
        </View>
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} weight="500" numberOfLines={1}>{main}</T>
          <T size={13} color={C.subtle} numberOfLines={1}>{meta}</T>
        </View>
        <T size={12} color={C.subtle}>{at}</T>
      </Pressable>
    </Smooth>
  );
}

/**
 * The decision in front, swiped where it rests: the drag is read on the page's frame (which does not move) before
 * anything in it, so it works over messages and buttons that take touches; across first, it is the swipe and they let
 * go (a tap on an option still answers); up or down first, it is theirs (the messages scroll).
 */
function Deck({ shown, local, style }: { shown: DecisionItem[]; local: DecisionsLocal; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const n = shown.length;
  // The frame's size (dp) and whether the front one is on its way out, kept as the front one changes.
  const [size, setSize] = useState({ width: 1, height: 1 });
  const [busy, setBusy] = useState(false);
  const item = shown[0]!;
  return (
    <View style={[{ alignSelf: "stretch" }, style]}>
      <View
        style={{ flex: 1, alignSelf: "stretch", overflow: "hidden" }}
        onLayout={(e) => setSize({ width: Math.max(1, e.nativeEvent.layout.width), height: Math.max(1, e.nativeEvent.layout.height) })}
      >
        {/* Its drag, its lift and its coming in are its own, new with another in front, so what went is not snapped back
            a frame before the next takes its place. */}
        <DeckFront key={keyOf(item)} shown={shown} local={local} width={size.width} height={size.height} busy={busy} setBusy={setBusy} />
      </View>
      {/* The hint and where this one is among them, still. */}
      <View style={{ alignSelf: "stretch", flexDirection: "row", paddingLeft: 16, paddingRight: 16, paddingTop: 8, paddingBottom: 10, alignItems: "center" }}>
        <T size={12} color={C.subtle} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{t("android-misc.decisions.hint")}</T>
        <T size={12} color={C.subtle} numberOfLines={1}>{`1 / ${n}`}</T>
      </View>
    </View>
  );
}

function DeckFront({ shown, local, width, height, busy, setBusy }: { shown: DecisionItem[]; local: DecisionsLocal; width: number; height: number; busy: boolean; setBusy: (busy: boolean) => void }) {
  const app = useContext(LocalApp);
  const C = useC();
  const item = shown[0]!;
  const key = keyOf(item);
  const n = shown.length;
  const still = reducedMotion();
  // The front one's way across (dp), its coming in (0 → 1) and its departure as it is answered.
  const drag = useSharedValue(0);
  const lift = useSharedValue(0);
  const arrive = useSharedValue(local.arriving && !still ? 0 : 1);
  useEffect(() => {
    local.arriving = false;
    if (arrive.value < 1) arrive.value = withTiming(1, { duration: 260, easing: Ease.Out });
  }, []);
  // What the swipe reads on the UI thread: busy, a reply held, the frame's width, and a text card's field (a touch that
  // begins in it is the field's: no swipe).
  const busyNow = useSharedValue(busy);
  const replyingNow = useSharedValue(local.replying != null);
  const widthNow = useSharedValue(width);
  const field = useSharedValue<Rect | null>(null);
  useEffect(() => { busyNow.value = busy; }, [busy]);
  useEffect(() => { replyingNow.value = local.replying != null; });
  useEffect(() => { widthNow.value = width; }, [width]);
  const busyRef = useRef(busy);
  busyRef.current = busy;

  /** Says it to the core; refused, the decision is back and why is said. */
  const call = (what: string, run: () => Promise<unknown>) => {
    run().catch((e: unknown) => {
      local.undo(key);
      app.toast = t(e instanceof CoreError && e.code === "unconfirmed" ? "android-misc.act.unconfirmed" : "android-misc.act.failed", { what, error: why(e) });
    });
  };

  /** The front one goes (`dir` its side, 0 up after answering), `then` is done, and the next comes in. */
  const go = (dir: number, then: () => void) => {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    busyNow.value = true;
    const after = () => {
      // The next card is already laid out underneath the departing one.
      local.arriving = n === 1;
      const alone = n === 1;
      then();
      busyRef.current = false;
      setBusy(false);
      // The only one, set aside: still the one in front; it comes in again.
      if (alone && !local.gone.includes(key)) {
        drag.value = 0;
        if (!still) { arrive.value = 0; arrive.value = withTiming(1, { duration: 260, easing: Ease.Out }); }
        local.arriving = false;
      }
    };
    if (still) { after(); return; }
    const done = (finished?: boolean) => { "worklet"; if (finished !== false) runOnJS(after)(); };
    if (dir === 0) lift.value = withTiming(height, { duration: 360, easing: Easing.bezier(0.55, 0, 0.85, 0.35) }, done);
    else drag.value = withTiming(dir * width * 1.25, { duration: 260, easing: Ease.Standard }, done);
  };
  const defer = () => { if (local.replying == null) go(-1, () => { local.setLater(key); call(t("android-misc.decisions.deferWhat"), () => app.api(item.station).deferDecision(item.thread, item.seq)); }); };
  const dismiss = () => { if (local.replying == null) go(1, () => { local.addGone(key); call(t("android-misc.decisions.dismissWhat"), () => app.api(item.station).dismissDecision(item.thread, item.seq)); }); };
  const answer = (o: DecisionOption) => { if (local.replying == null) go(0, () => { local.addGone(key); call(t("android-misc.decisions.answerWhat"), () => app.api(item.station).answerDecision(item.thread, item.seq, o.label)); }); };
  // A text card's reply: it goes as a message does, at once (its chat's outbox has it: sending, or not sent with a way
  // to send it again), not waiting on the station; refused by the core, the decision and what was written are back.
  const replyDraft = rememberDraft(`decision:${item.station}:${item.thread}:${item.seq}`);
  const reply = () => {
    if (replyDraft.ready && !busyRef.current && local.replying == null) {
      const taken = replyDraft.take();
      go(0, () => local.addGone(key));
      app.api(item.station).replyDecision(item.thread, item.seq, taken.text, taken.files.map((f: Pending) => f.done).filter((d: Attachment | null | undefined): d is Attachment => d != null), taken.quotes.map((q: DraftQuote) => q.sent())).catch((e: unknown) => {
        local.undo(key);
        if (e instanceof CoreError && e.code === "invalid_params" && replyDraft.empty) replyDraft.restore(taken);
        app.toast = t("android-misc.decisions.replyFailed", { error: why(e) });
      });
    }
  };

  // The swipe: read before what is in the frame takes the touch (a native gesture over the RN touches in it), decided
  // by which way it goes first past the touch slop.
  const start = useSharedValue({ x: 0, y: 0, pos: 0, base: 0, swiping: false });
  const pan = Gesture.Pan()
    .manualActivation(true)
    .onTouchesDown((e, manager) => {
      const touch = e.allTouches[0];
      const f = field.value;
      const inField = touch != null && f != null && touch.absoluteX >= f.x && touch.absoluteX <= f.x + f.width && touch.absoluteY >= f.y && touch.absoluteY <= f.y + f.height;
      if (busyNow.value || replyingNow.value || inField || touch == null) { manager.fail(); return; }
      start.value = { x: touch.absoluteX, y: touch.absoluteY, pos: drag.value, base: 0, swiping: false };
    })
    .onTouchesMove((e, manager) => {
      const touch = e.allTouches[0];
      if (touch == null || start.value.swiping) return;
      const across = touch.absoluteX - start.value.x;
      const upDown = touch.absoluteY - start.value.y;
      // Up or down first: the messages' (they scroll), not a swipe.
      if (Math.abs(upDown) > TOUCH_SLOP && Math.abs(upDown) > Math.abs(across)) { manager.fail(); return; }
      if (Math.abs(across) <= TOUCH_SLOP) return;
      manager.activate();
    })
    .onStart((e) => {
      // From here on it follows the finger, from where the decision was (what came before the slop is not moved).
      start.value = { ...start.value, base: e.translationX, swiping: true };
    })
    .onUpdate((e) => {
      if (busyNow.value) return;
      drag.value = start.value.pos + (e.translationX - start.value.base);
    })
    .onEnd((e) => {
      const v = e.velocityX;
      const at = drag.value;
      const w = widthNow.value;
      const fling = Math.abs(v) > 900 && Math.abs(at) > 16 && (v > 0) === (at > 0);
      if (busyNow.value) return;
      if (at > w * THRESHOLD || (fling && at > 0)) runOnJS(dismiss)();
      else if (at < -w * THRESHOLD || (fling && at < 0)) runOnJS(defer)();
      else drag.value = still ? 0 : withSpring(0, { ...MoveSpring, velocity: v });
    });

  // Under it, what letting it go that way does: left 待定 (at the right edge it uncovers), right 不再提醒.
  const dismissing = useAnimatedStyle(() => ({ opacity: drag.value > 0 ? Math.min(1, Math.max(0, Math.abs(drag.value) / (widthNow.value * 0.12))) : 0 }));
  const deferring = useAnimatedStyle(() => ({ opacity: drag.value < 0 ? Math.min(1, Math.max(0, Math.abs(drag.value) / (widthNow.value * 0.12))) : 0 }));
  const front = useAnimatedStyle(() => {
    const a = arrive.value;
    const progress = Math.min(1, Math.max(0, lift.value / height));
    const gathered = Math.min(1, Math.max(0, progress / 0.4));
    const s = (0.94 + (1 - 0.94) * a) * (1 + (0.88 - 1) * gathered);
    return {
      transform: [{ translateX: drag.value }, { translateY: -lift.value }, { rotate: `${(drag.value / widthNow.value) * 4}deg` }, { scale: s }],
      opacity: a,
    };
  });
  const [fieldRect, setFieldRect] = useState<Rect | null>(null);
  useEffect(() => { field.value = fieldRect; }, [fieldRect]);

  return (
    <GestureDetector gesture={pan}>
      <View
        style={{ flex: 1 }}
        accessibilityActions={[{ name: "defer", label: t("android-misc.decisions.defer") }, { name: "dismiss", label: t("android-misc.decisions.dismiss") }]}
        onAccessibilityAction={(e) => { if (e.nativeEvent.actionName === "defer") defer(); else if (e.nativeEvent.actionName === "dismiss") dismiss(); }}
      >
        {!busy && (
          <>
            <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { paddingHorizontal: 24, justifyContent: "center", alignItems: "flex-start" }, dismissing]}>
              <T size={16} weight="600" color={C.muted}>{t("android-misc.decisions.dismiss")}</T>
            </Animated.View>
            <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { paddingHorizontal: 24, justifyContent: "center", alignItems: "flex-end" }, deferring]}>
              <T size={16} weight="600" color={C.muted}>{t("android-misc.decisions.defer")}</T>
            </Animated.View>
          </>
        )}
        {busy && n > 1 && (
          <View style={[StyleSheet.absoluteFill, { backgroundColor: C.bg }]}>
            <Face item={shown[1]!} onPick={() => {}} onReply={() => {}} onField={() => {}} />
          </View>
        )}
        <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: C.bg, transformOrigin: "50% 0%" }, front]}>
          <Face item={item} onPick={answer} onReply={reply} onField={setFieldRect} />
        </Animated.View>
      </View>
    </GestureDetector>
  );
}

/**
 * A decision as the page shows it: its chat's title (to the chat), the messages before it and the post as the chat
 * draws them (scrolled to the post), its options under the post, the chat's composer floating over them at the foot.
 */
function Face({ item, onPick, onReply, onField }: { item: DecisionItem; onPick: (o: DecisionOption) => void; onReply: () => void; onField: (rect: Rect) => void }) {
  const app = useContext(LocalApp);
  const C = useC();
  const key = keyOf(item);
  const messages = useMemo(() => [...item.before, item.message], [item]);
  // The chat as far as these messages go: enough for them to be drawn as in it (files kept by the post's agent).
  const view = useMemo<ChatView>(() => ({
    me: {}, title: item.title, people: [], agents: [], messages, more: false, outbox: [], link: { state: "online" }, offline: false,
  }), [item, messages]);
  const of: ChatOf = { session: item.session };
  const ctx = useMemo(() => new Here(item.station, of, view, [], item.message.by.agent ?? item.session), [item, view]);
  const scroll = useRef<ScrollView>(null);
  const scrolled = useRef(0);
  const [moving, setMoving] = useState(false);
  const [postAt, setPostAt] = useState<number | null>(null);
  // Long, it opens at the post (what is to be decided), with a little of what came before above it.
  useEffect(() => {
    if (postAt == null) return;
    scroll.current?.scrollTo({ y: Math.max(0, postAt - 48), animated: false });
  }, [key, postAt]);
  const card = item.card;
  const type = card?.type ?? "options";
  // The composer floats over the messages, as in the chat: they scroll on under it, their end kept clear of it.
  const host = useMemo(() => new Host(), [key]);
  const [footHeight, setFootHeight] = useState(0);
  // The room an expanded composer's toolbar takes, kept clear at the messages' end.
  const [room, setRoom] = useState(0);
  // A passage of a message picked where it is (MessagePick.tsx): quoted into the reply's draft (DecisionComposer's), or
  // only copied where there is no composer.
  const replies = type === "options" || type === "text";
  const replyDraft = rememberDraft(`decision:${item.station}:${item.thread}:${item.seq}`);
  const draft = replies ? replyDraft : null;
  const pick = useMemo(() => new MessagePick(draft), [key, draft]);
  return (
    <>
      <Pressable
        onPress={() => app.push({ kind: "Chat", station: item.station, of })}
        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
        accessibilityLabel={t("android-misc.decisions.openChat", { title: item.title })}
        style={{ alignSelf: "stretch", paddingHorizontal: 16, paddingVertical: 8, flexDirection: "row", alignItems: "center", gap: 4 }}
      >
        <T size={13} color={C.muted} numberOfLines={1} style={{ flexShrink: 1, minWidth: 0 }}>{item.title}</T>
        <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
      </Pressable>
      {card?.assigneeText != null && <T size={13} color={C.muted} style={{ paddingHorizontal: 16, paddingVertical: 4 }}>{card.assigneeText}</T>}
      <View style={{ flex: 1, alignSelf: "stretch" }} {...letsGoOfPick(pick)}>
        <LocalMessagePick.Provider value={pick}>
          <ScrollView
            ref={scroll}
            style={{ flex: 1, backgroundColor: C.bg }}
            contentContainerStyle={{ paddingLeft: 14, paddingRight: 14, paddingTop: 10, paddingBottom: 10 + footHeight + room, gap: 20 }}
            scrollEventThrottle={16}
            onScroll={(e) => { scrolled.current = e.nativeEvent.contentOffset.y; }}
            onScrollBeginDrag={() => setMoving(true)}
            onScrollEndDrag={() => setMoving(false)}
            onMomentumScrollBegin={() => setMoving(true)}
            onMomentumScrollEnd={() => setMoving(false)}
          >
            {messages.map((m) => (
              <View key={m.seq} onLayout={m === item.message ? (e) => { const y = e.nativeEvent.layout.y; setPostAt((was) => was ?? y); } : undefined}>
                <SaidAlone ctx={ctx} m={m} />
              </View>
            ))}
            {/* Under the post, as in its chat: its options, or (a card this app does not know) the way to answer it there. */}
            {type === "options" ? (
              // An agent's request for a vault item: approved here (Vault.tsx); the 奏 page's are the viewer's.
              card?.vault != null
                ? <VaultApproval workspace={item.station.split("/")[0]!} request={card.vault} mine />
                : <DecisionOptions options={card?.options ?? item.options} onPick={onPick} />
            ) : type === "text" ? null : (
              <View style={{ alignSelf: "stretch", gap: 8 }}>
                <T size={13} color={C.muted}>{t("android-misc.decisions.replyInChat")}</T>
                <Smooth radius={12} style={{ alignSelf: "stretch", backgroundColor: C.ink }}>
                  <Pressable onPress={() => app.push({ kind: "Chat", station: item.station, of, at: item.seq })} android_ripple={{ color: withAlpha(C.bg, 0.1) }} style={{ paddingVertical: 12, alignItems: "center" }}>
                    <T size={15} weight="500" color={C.bg}>{t("android-misc.decisions.goReply")}</T>
                  </Pressable>
                </Smooth>
              </View>
            )}
          </ScrollView>
          <PickLayer pick={pick} follow={() => scrolled.current} moving={moving} top={0} bottom={footHeight} style={StyleSheet.absoluteFill} />
        </LocalMessagePick.Provider>
        {replies && (
          <View style={{ position: "absolute", left: 0, right: 0, bottom: 0 }} onLayout={(e) => setFootHeight(e.nativeEvent.layout.height)}>
            <DecisionComposer item={item} host={host} placeholder={type === "text" ? (card?.placeholder ?? null) : null} onRoom={setRoom} onField={onField} onReply={onReply} />
          </View>
        )}
      </View>
    </>
  );
}

/** Uses the chat's entire composer: attachments, references, draft extras, capsule and resizing. */
function DecisionComposer({ item, host, placeholder, onRoom, onField, onReply }: { item: DecisionItem; host: Host; placeholder: string | null; onRoom: (room: number) => void; onField: (rect: Rect) => void; onReply: () => void }) {
  const app = useContext(LocalApp);
  const draft = rememberDraft(`decision:${item.station}:${item.thread}:${item.seq}`);
  const launchers = AttachLaunchers((picked: Picked) => upload(app, draft, item.station, picked));
  useLayoutEffect(() => {
    host.spec = {
      station: item.station, here: item.session, draft, placeholder: placeholder ?? t("android-misc.decisions.placeholder"),
      onPlus: () => openAttach(app, launchers), onSend: onReply,
    };
  });
  // The toolbar an expanded composer adds, kept as room over the options (the messages' end clear of it), not
  // between them and the composer.
  const room = draft.composerExpanded ? 0 : 4 + 36;
  useEffect(() => { onRoom(room); }, [room]);
  const at = useRef<View>(null);
  return (
    <View ref={at} onLayout={() => at.current?.measureInWindow((x, y, width, height) => onField({ x, y, width, height }))}>
      <HostComposer host={host} besideRecent={false} />
    </View>
  );
}
