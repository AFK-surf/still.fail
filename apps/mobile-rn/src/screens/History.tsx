// An agent's execution history (web/src/mobile/History.tsx), as a full-screen page: what it received and what it sent, drawn
// alike (a line, then the words beside a bar); what it did in between,
// grouped, each group opening to its commands and output; and its details
// (model, allowance, the station it runs on). (The Android app's screens/History.kt.)
//
// A component's `key` is React's own: where the Kotlin's pages take an agent's `key`, they take `sessionKey` here.
import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { BackHandler, FlatList, Linking, Pressable, ScrollView, Text, View, type ViewToken } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Animated, { interpolateColor, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { CoreError } from "../../../../web/src/core/client.ts";
import type {
  AgentCardView, ChatAgent, ChatView, HistoryGroup, HistoryItem, HistoryLive, HistoryPhase, HistoryStep, HistoryView, Host, PickView, Place as PlaceShape,
} from "../../../../web/src/core/shapes.ts";
import { MenuItem, MenuSpec, ReaderSpec, app, useApp, type AppState } from "../AppState";
import { APP_NAME } from "../build";
import { chatAgentState } from "../data/Chats";
import { errorText } from "../data/Calls";
import { ChatOf, Topics, rememberTopic } from "../data/Topics";
import { lang, t } from "../i18n";
import { rememberStationName } from "../ui/ChatInk";
import { DoingMark, GroupLabel } from "../ui/Controls";
import { Follow, rememberFollow } from "../ui/Follow";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { Markdown } from "../ui/Markdown";
import { Ease } from "../ui/Motion";
import { MakerIcon, Mark, MeterChips, ModelMark, NavBar, NavButton, ProviderMark, QuotaChip, QuotaRings, Seg, SlackMark } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { Mono, useC, withAlpha } from "../ui/Theme";
import { ToolStepBody } from "../ui/ToolStep";
import { BusyIcon, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { AgentNotes, AgentStatus, AgentTiles } from "./AgentSheet";
import { chatLink, copyChatLink, encodeComponent } from "./ChatLink";
import { AccountList, EffortChips, ModelList, SettingRow } from "./SettingParts";

/** Opens an agent's execution history, over the item's page it belongs to. */
/** `entry`: the transcript entry to open at (an activity row's), else its newest. */
export function openHistory(app: AppState, station: string, of: ChatOf, key: string, entry: number | null = null): void {
  app.push({ kind: "History", station, of, key, entry });
}

const sameOf = (a: ChatOf, b: ChatOf) => ("thread" in a ? "thread" in b && a.thread === b.thread : "session" in b && a.session === b.session);

/** The words of a failure, as the Kotlin's `e.message` of a CoreException. */
const messageOf = (e: unknown) => (e instanceof Error ? e.message : String(e));

export function HistoryScreen({ station, of, sessionKey: key, entry = null }: { station: string; of: ChatOf; sessionKey: string; entry?: number | null }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const chat = rememberTopic<ChatView>(Topics.chat(station, of));
  // Its link, to paste into another chat for its agent to read (or a person to open here), as the web's.
  const title = chat.value?.title;
  const base = chatLink(app.cloudOrigin, station, key);
  const link = base != null ? `${base}?history=${encodeComponent(key)}` : null;
  return (
    <View style={{ flex: 1, backgroundColor: C.bg, paddingBottom: insets.bottom }}>
      <NavBar
        back={t("common.back")}
        onBack={() => app.pop()}
        title={t("android-chat.history.title")}
        trailing={title != null && link != null ? () => (
          <View accessibilityLabel={t("web-mobile.history.copyLink")}><NavButton icon={Icons.Copy} onClick={() => copyChatLink(app, title, link)} /></View>
        ) : null}
      />
      <HistoryContent station={station} of={of} sessionKey={key} entry={entry} />
    </View>
  );
}

function HistoryContent({ station, of, sessionKey: key, entry = null }: { station: string; of: ChatOf; sessionKey: string; entry?: number | null }) {
  const C = useC();
  const chat = rememberTopic<ChatView>(Topics.chat(station, of));
  const history = rememberTopic<HistoryView>(Topics.history(station, key));
  const host = rememberTopic<Host>(Topics.host(station));
  const agent = chat.value?.agents?.find((a) => a.session.key === key);
  const [tab, setTab] = useState(0);
  if (agent == null) return <Waiting shape={WaitShape.Messages} text={t("common.reading")} error={chat.error?.message ?? null} />;
  const s = agent.session;
  return (
    <>
      <View style={{ alignSelf: "stretch", paddingLeft: 18, paddingRight: 18, paddingTop: 4, flexDirection: "row", alignItems: "center", gap: 6 }}>
        <ModelMark maker={s.maker} runtime={s.runtime} size={20} state={chatAgentState(agent)} />
        {/* The page is the agent's history; its head is the agent, with the room its name needs. */}
        <T size={16} weight="700" color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{s.agentText}</T>
        <Actions station={station} agent={agent} />
        <Seg options={[t("android-chat.history.tab.steps"), t("android-chat.history.tab.details")]} selected={tab} onSelect={setTab} />
      </View>
      <Summary agent={agent} />
      <View style={{ flex: 1, alignSelf: "stretch" }}>
        {tab === 0
          ? <Steps station={station} of={of} agent={agent} history={history.value} entry={entry} />
          : <Details station={station} of={of} agent={agent} history={history.value} host={host.value} />}
      </View>
    </>
  );
}

/** One of what can be done to it right now. */
function Act({ station, sessionKey, icon, done, name, call }: { station: string; sessionKey: string; icon: IconPaths; done: string; name: string; call: () => Promise<void> }) {
  const C = useC();
  useApp((st) => st.doing);
  const busy = app.isDoing(name, { station, key: sessionKey });
  return (
    <View style={{ width: 28, height: 28, borderRadius: 14, overflow: "hidden", backgroundColor: C.chip }}>
      <Pressable
        disabled={busy}
        onPress={() => { void call().then(() => { app.toast = done; }, (e: unknown) => { if (e instanceof CoreError) app.toast = e.message; }); }}
        android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}
        style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
      >
        <BusyIcon busy={busy} icon={() => <Icon icon={icon} size={14} color={C.ink} />} />
      </Pressable>
    </View>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function Actions({ station, agent }: { station: string; agent: ChatAgent }) {
  const s = agent.session;
  const st = agent.status;
  return (
    <>
      {(st === "running" || st === "queued") && <Act station={station} sessionKey={s.key} icon={Icons.Stop} done={t("android-chat.history.stopped")} name="session.stop" call={() => app.api(station).stop(s.key)} />}
      {s.process === "warm" && <Act station={station} sessionKey={s.key} icon={Icons.Unplug} done={t("android-chat.history.evicted")} name="session.evict" call={() => app.api(station).evict(s.key)} />}
    </>
  );
}

/** The head's short line: only what is worth a look now (an account signed out, a quota running out, the disk filling up). */
function Summary({ agent }: { agent: ChatAgent }) {
  const C = useC();
  if (agent.attention.length === 0) return <View style={{ height: 8 }} />;
  return (
    <View style={{ alignSelf: "stretch", paddingLeft: 18, paddingRight: 18, paddingTop: 6, paddingBottom: 8, flexDirection: "row", gap: 10, alignItems: "center" }}>
      {agent.attention.map((a, i) => {
        const quota = a.quota;
        if (quota != null) return <QuotaChip key={i} mark={quota.mark} left={quota.left} level={quota.level} />;
        if (a.kind === "disk") return <T key={i} size={12} color={C.warn}>{a.text}</T>;
        return <T key={i} size={12} color={C.red}>{a.text}</T>;
      })}
    </View>
  );
}

type Line =
  | { kind: "Item"; item: HistoryItem }
  | { kind: "Live"; step: HistoryLive }
  | { kind: "Phase"; phase: HistoryPhase }
  | { kind: "Edge" };

const lineKey = (l: Line) => (l.kind === "Live" ? `live/${l.step.id}` : l.kind === "Phase" ? "phase" : l.kind === "Edge" ? "edge" : l.item.key);

function Steps({ station, of, agent, history, entry = null }: { station: string; of: ChatOf; agent: ChatAgent; history: HistoryView | undefined; entry?: number | null }) {
  const C = useC();
  const list = useRef<FlatList<Line>>(null);
  const follow = rememberFollow(list);
  const api = app.api(station);
  const items = history?.items ?? [];
  // Only its latest entries come first: near the top, the page before comes in (once per page).
  const more = history?.more === true;
  const first = items[0]?.key;
  const asked = useRef<string | null | undefined>(null);
  // The page before on its way: said at the top, where it comes in.
  const [older, setOlder] = useState(false);
  const [firstVisible, setFirstVisible] = useState(0);
  useEffect(() => {
    if (!more || !follow.placed) return;
    if (firstVisible <= 2 && asked.current !== first) {
      asked.current = first;
      setOlder(true);
      api.historyOlder(agent.session.key).catch((e: unknown) => { if (e instanceof CoreError) asked.current = null; }).finally(() => setOlder(false));
    }
  }, [more, first, follow.placed, firstVisible]);
  // It opens at its newest, and follows new steps while the reader stays there.
  // Opened at an entry (an activity row): that item, near the top, for a moment marked; else the newest, followed.
  // One before what is loaded: the pages before come first.
  const [marked, setMarked] = useState<string | null>(null);
  const before = entry != null && more && entry < (items[0]?.entries?.[0] ?? 0);
  useEffect(() => {
    if (history == null || history.empty) return;
    let live = true;
    let unmark: ReturnType<typeof setTimeout> | undefined;
    void (async () => {
      if (follow.placed) return;
      if (before) {
        setOlder(true);
        try { await api.historyOlder(agent.session.key); return; } catch { /* placed as it is */ } finally { if (live) setOlder(false); }
      }
      const found = entry != null ? items.findIndex((it) => it.entries.length === 2 && entry >= it.entries[0]! && entry <= it.entries[1]!) : -1;
      if (!live) return;
      if (found >= 0) {
        list.current?.scrollToIndex({ index: found + 1, viewOffset: 24, animated: false });
        follow.placed = true; follow.on = false;
        setMarked(items[found]!.key);
        unmark = setTimeout(() => setMarked(null), 1600);
      } else {
        await follow.toEnd(); follow.placed = true; follow.on = true;
      }
    })();
    return () => { live = false; if (unmark) clearTimeout(unmark); };
  }, [before, first, history == null]);
  const onViewable = useRef(({ viewableItems }: { viewableItems: ViewToken<Line>[] }) => {
    const at = viewableItems.reduce((m, v) => (v.index != null && v.index < m ? v.index : m), Number.MAX_SAFE_INTEGER);
    if (at !== Number.MAX_SAFE_INTEGER) setFirstVisible(at);
  }).current;
  // A step or thought in brief is read whole as it is opened (`history.detail`).
  const detail = (entries: number[]) => api.historyDetail(agent.session.key, entries);
  if (history == null) return <Waiting shape={WaitShape.Messages} text={t("android-chat.history.loading")} />;
  if (history.empty) return <Edge text={history.edge} />;
  const lines: Line[] = [{ kind: "Edge" }, ...items.map((item): Line => ({ kind: "Item", item })), ...history.live.map((step): Line => ({ kind: "Live", step })), ...(history.phase ? [{ kind: "Phase", phase: history.phase } as Line] : [])];
  return (
    <LocalFollow.Provider value={follow}>
      <LocalDetail.Provider value={detail}>
        <FlatList
          ref={list}
          data={lines}
          keyExtractor={lineKey}
          style={{ alignSelf: "stretch" }}
          contentContainerStyle={{ paddingLeft: 18, paddingRight: 18, paddingBottom: 24 }}
          ItemSeparatorComponent={Gap}
          onViewableItemsChanged={onViewable}
          onScrollToIndexFailed={(info) => {
            list.current?.scrollToOffset({ offset: info.averageItemLength * info.index, animated: false });
            requestAnimationFrame(() => list.current?.scrollToIndex({ index: info.index, viewOffset: 24, animated: false }));
          }}
          {...follow.listProps}
          renderItem={({ item: line }) => {
            switch (line.kind) {
              case "Edge": return older ? <View style={{ alignSelf: "stretch", paddingVertical: 10, alignItems: "center" }}><WaitLine /></View> : <Edge text={history.edge} />;
              case "Item": return <Marked on={line.item.key === marked}><Item item={line.item} station={station} of={of} agent={agent} /></Marked>;
              case "Live": return <T size={13} color={C.muted} numberOfLines={1}>{line.step.text}</T>;
              case "Phase": return <PhaseLine phase={line.phase} />;
            }
          }}
        />
      </LocalDetail.Provider>
    </LocalFollow.Provider>
  );
}

function Gap() { return <View style={{ height: 10 }} />; }

/** An item, its ground the accent's for a moment when it is the one opened at (900 ms in and out). */
function Marked({ on, children }: { on: boolean; children: ReactNode }) {
  const C = useC();
  const shade = useSharedValue(on ? 1 : 0);
  useEffect(() => { shade.value = withTiming(on ? 1 : 0, { duration: 900, easing: Ease.Standard }); }, [on]);
  const to = withAlpha(C.accent, 0.10);
  const from = withAlpha(C.accent, 0);
  const style = useAnimatedStyle(() => ({ backgroundColor: interpolateColor(shade.value, [0, 1], [from, to]) }));
  return <Smooth radius={8}><Animated.View style={style}>{children}</Animated.View></Smooth>;
}

/** The steps' list: a group or a step opened is read from its top, not followed down to the end. */
const LocalFollow = createContext<Follow | null>(null);

/** Reads whole what a step or thought in brief holds (its transcript entries), as it is opened. */
const LocalDetail = createContext<(entries: number[]) => Promise<void>>(async () => undefined);

function Edge({ text }: { text: string }) {
  const C = useC();
  return <T size={12} color={C.subtle} align="center" style={{ alignSelf: "stretch", paddingVertical: 10 }}>{text}</T>;
}

function Item({ item, station, of, agent }: { item: HistoryItem; station: string; of: ChatOf; agent: ChatAgent }) {
  const C = useC();
  const body = item.body;
  switch (body.kind) {
    case "received": {
      const content = body.content;
      return (
        <View style={{ gap: 10 }}>
          {content.note != null && (() => {
            const note = content.note;
            const [before, after] = around("android-chat.history.received.note");
            return (
              <Message
                icon={Icons.Received}
                label={() => <><T size={13} color={C.muted}>{before}</T><Strong text={APP_NAME} /><T size={13} color={C.muted}>{after}</T></>}
                text={note}
                full={() => <T size={15} line={23} color={C.ink}>{note}</T>}
              />
            );
          })()}
          {content.tasks.map((task, i) => {
            const icon = task.agent ? Icons.Agent : Icons.Command;
            const color = task.failed ? C.red : C.muted;
            const result = task.result;
            if (result != null) return <Message key={`t${i}`} icon={icon} label={() => <T size={13} color={color}>{task.text}</T>} text={result} full={() => <Markdown text={result} size={15} />} />;
            return (
              <View key={`t${i}`} style={{ flexDirection: "row", alignItems: "center", gap: 5 }}>
                <Icon icon={icon} size={14} color={color} />
                <T size={13} color={color} style={{ flexShrink: 1 }}>{task.text}</T>
              </View>
            );
          })}
          {content.messages.map((m) => (
            <Message
              key={m.key}
              icon={Icons.Received}
              label={() => {
                const [before, after] = around(m.notice === "job" ? "android-chat.history.received.jobMessage" : "android-chat.history.received.message");
                const user = m.from.slackUser;
                return (
                  <>
                    <T size={13} color={C.muted}>{before}</T>
                    {user != null ? <SlackName station={station} user={user} name={m.from.name} mine={m.from.bound} /> : <Strong text={m.notice === "stillfail" ? APP_NAME : m.from.name} style={{ flexShrink: 1 }} />}
                    <T size={13} color={C.muted}>{after}</T>
                    {m.place != null && <><T size={13} color={C.muted}>{" · "}</T><View style={{ flexShrink: 1 }}><Place station={station} of={of} place={m.place} /></View></>}
                  </>
                );
              }}
              text={m.text}
              // A job's words as it wrote them (program output), its columns kept.
              full={() => (m.notice === "job" ? <Text style={[Mono, { color: C.ink, includeFontPadding: false }]}>{m.text}</Text> : <T size={15} line={23} color={C.ink}>{m.text}</T>)}
            />
          ))}
        </View>
      );
    }
    case "post": {
      const post = body.content;
      return (
        <Message
          icon={Icons.Send}
          label={() => {
            const [before, after] = around("android-chat.history.sent.to");
            const place = post.place;
            return (
              <>
                <T size={13} color={C.muted}>{before}</T>
                <View style={{ flexShrink: 1 }}>
                  {place != null ? <Place station={station} of={of} place={place} /> : <View style={{ flexDirection: "row", alignItems: "center" }}><SlackMark size={12} /><Strong text=" Slack" /></View>}
                </View>
                <T size={13} color={C.muted}>{after}</T>
                {post.block && <Pill text="Block" color={C.blue} />}
                {post.failed && <Pill text={t("android-chat.history.send.failed")} color={C.red} />}
              </>
            );
          }}
          text={post.text}
          full={() => <Markdown text={post.text} size={15} />}
        />
      );
    }
    case "mark": {
      const wait = body.content.wait;
      return (
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          {wait != null && <Icon icon={Icons.Wait} size={14} color={C.muted} />}
          {/* A wait: how long it waited, said by the core once it is over; still waiting, it counts on here. */}
          {wait != null && wait.until == null ? <Waited since={wait.since} seconds={wait.seconds ?? null} what={wait.what ?? null} /> : <T size={13} color={C.muted} style={{ flexShrink: 1 }}>{body.content.text}</T>}
        </View>
      );
    }
    case "text": {
      const words = body.content.text;
      return (
        <View style={body.content.subagent ? { paddingLeft: 12 } : undefined}>
          <Brief text={words} open={() => { app.reader = new ReaderSpec(() => <T size={13} color={C.muted}>{t("android-chat.history.wrote", { name: agent.session.agentText })}</T>, () => <Markdown text={words} size={15} />); }} />
        </View>
      );
    }
    case "group": return <Group g={body.content} />;
  }
}

/** Now, each second. */
function useNow(): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  return now;
}

function Waited({ since, seconds, what }: { since: number; seconds: number | null; what: string | null }) {
  const C = useC();
  const now = useNow();
  const s = Math.max(0, Math.trunc((now - since) / 1000));
  const waited = seconds != null ? Math.min(s, seconds) : s;
  return (
    <T size={13} color={C.muted} style={{ flexShrink: 1 }}>
      {(what != null ? `${what} · ` : "") + t("android-chat.history.waiting", { time: shortSpan(waited) }) + (seconds != null ? ` / ${shortSpan(seconds)}` : "")}
    </T>
  );
}

/** What an entry says, in brief: its words as plain text, two lines at most. A tap opens it in full. */
function Brief({ text, open }: { text: string; open: () => void }) {
  const C = useC();
  return (
    <Smooth radius={6} style={{ alignSelf: "stretch" }}>
      <Pressable onPress={open} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}>
        <T size={14} line={21} color={C.ink} numberOfLines={2}>{plain(text)}</T>
      </Pressable>
    </Smooth>
  );
}

/** Markdown as one run of plain words, for a brief: no fences, headings, emphasis or line breaks. */
function plain(text: string): string {
  return text
    .replace(/```[^\n]*/g, " ")
    .replace(/^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+/gm, "")
    .replace(/\*\*|__|`/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

export function Strong({ text, style }: { text: string; style?: import("react-native").StyleProp<import("react-native").TextStyle> }) {
  const C = useC();
  return <T size={13} color={C.ink} weight="600" numberOfLines={1} style={style}>{text}</T>;
}

/**
 * A message in or out, drawn alike: a line saying what and where, then its words in brief beside a bar (they answer
 * each other). A tap on the words opens the whole of it on its own page, under the same line.
 */
export function Message({ icon, label, text, full }: { icon: IconPaths; label: () => ReactNode; text: string; full: () => ReactNode }) {
  const C = useC();
  const line = () => (
    <>
      <View style={{ paddingRight: 5 }}><Icon icon={icon} size={14} color={C.muted} /></View>
      {label()}
    </>
  );
  return (
    <View style={{ gap: 5 }}>
      <View style={{ flexDirection: "row", alignItems: "center" }}>{line()}</View>
      <View style={{ flexDirection: "row", alignItems: "stretch" }}>
        <View style={{ width: 2, borderRadius: 1, backgroundColor: C.line }} />
        <View style={{ paddingLeft: 10, flex: 1, minWidth: 0 }}><Brief text={text} open={() => { app.reader = new ReaderSpec(line, full); }} /></View>
      </View>
    </View>
  );
}

/** A sentence of the catalog's around a part drawn on its own (`{name}`): its words before it and after it. */
export function around(key: string): [string, string] {
  const words = t(key);
  const at = words.indexOf("{name}");
  return at < 0 ? [words, ""] : [words.substring(0, at), words.substring(at + "{name}".length)];
}

export function Pill({ text, color }: { text: string; color: string }) {
  return (
    <View style={{ marginLeft: 6 }}>
      <Smooth radius={6} style={{ backgroundColor: withAlpha(color, 0.12) }}>
        <T size={11} color={color} style={{ paddingHorizontal: 6, paddingVertical: 1 }}>{text}</T>
      </Smooth>
    </View>
  );
}

/**
 * A place, as the core names it: its platform's mark and its name; a chat on still.fail's page leads to it, a Slack thread
 * opens in Slack (its link, while a connect is signed in to its workspace).
 */
export function Place({ station, of, place }: { station: string; of: ChatOf; place: PlaceShape }) {
  const C = useC();
  // A still.fail chat (surface "ember") is its agent's item: opened by the session it is bound to.
  const session = place.session;
  const chat = session != null ? () => { if (!sameOf(of, ChatOf.Session(session))) app.push({ kind: "Chat", station, of: ChatOf.Session(session) }); else app.pop(); } : null;
  // A Slack thread by its link: the Slack app takes it when installed, the browser otherwise.
  const url = place.surface === "slack" ? place.url : undefined;
  const slack = url != null ? () => { void Linking.openURL(url).catch(() => { app.toast = t("android-chat.link.failed"); }); } : null;
  const open = chat ?? slack;
  const row = (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 3 }}>
      {place.surface === "ember" || place.surface === "stillfail" ? <Mark size={12} /> : <SlackMark size={12} />}
      <T size={13} weight="600" color={open != null ? C.accentInk : C.ink} numberOfLines={1} style={{ flexShrink: 1 }}>{place.name}</T>
    </View>
  );
  return (
    <Smooth radius={4}>
      {open != null ? <Pressable onPress={open} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}>{row}</Pressable> : row}
    </Smooth>
  );
}

/**
 * A Slack user's name (你 once the viewer said it is them, the core says). A tap offers "这是我" (the station then takes
 * that Slack user for the viewer), or "不是我" once it does.
 */
function SlackName({ station, user, name, mine }: { station: string; user: string; name: string; mine: boolean }) {
  const C = useC();
  const at = useRef<View>(null);
  // Said and not answered yet: a spinner beside the name, the menu not offered again meanwhile; failed: a red mark a moment.
  useApp((s) => s.doing);
  const binding = app.isDoing("slack.identity", { station, user });
  const failed = app.failedOf("slack.identity", { station, user });
  const open = () => {
    at.current?.measureInWindow((x, y, width, height) => {
      app.menu = new MenuSpec({ left: x, top: y, right: x + width, bottom: y + height }, [
        new MenuItem(mine ? t("android-chat.history.identity.notMe") : t("android-chat.history.identity.me"), mine ? Icons.Close : Icons.Check, () => {
          app.act(mine ? t("android-chat.history.identity.unbind") : t("android-chat.history.identity.bind"), () => app.api(station).slackIdentity(user, !mine));
        }),
      ]);
    });
  };
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 4, flexShrink: 1 }}>
      <View ref={at} collapsable={false} style={{ flexShrink: 1 }}>
        <Smooth radius={4}>
          <Pressable disabled={binding} onPress={open} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}>
            <T size={13} color={C.accentInk} weight="600">{name}</T>
          </Pressable>
        </Smooth>
      </View>
      <DoingMark running={binding} failed={failed} inline />
    </View>
  );
}

function Group({ g }: { g: HistoryGroup }) {
  const C = useC();
  const [open, setOpen] = useState(false);
  const follow = useContext(LocalFollow);
  const calls = g.rows.some((r) => r.kind === "step");
  return (
    <View>
      <Smooth radius={6} style={{ alignSelf: "stretch" }}>
        <Pressable
          onPress={() => { if (!open) follow?.stay(); setOpen(!open); }}
          android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}
          style={{ paddingVertical: 4, flexDirection: "row", gap: 6, alignItems: "center" }}
        >
          <Icon icon={open ? Icons.ChevronDown : Icons.ChevronRight} size={13} color={C.subtle} />
          <T size={14} color={g.failures > 0 ? C.red : C.muted} numberOfLines={open ? 3 : 1} style={{ flexShrink: 1 }}>{g.summary}</T>
          {g.failures > 0 && <Pill text={t("android-chat.history.group.failed", { n: g.failures })} color={C.red} />}
          {g.pending > 0 && <Pill text={t("android-chat.history.group.pending", { n: g.pending })} color={C.accentInk} />}
        </Pressable>
      </Smooth>
      {open && (
        <View style={{ paddingLeft: 19, paddingTop: 4, paddingBottom: 4, gap: 6 }}>
          {g.rows.map((row, i) => {
            if (row.kind === "step") return <StepRow key={i} step={row.content} />;
            const thought = row.content;
            const words = () => <Whole brief={thought.brief} entries={thought.entries} body={() => <T size={13} line={20} color={C.muted}>{thought.text}</T>} />;
            return !calls ? <View key={i}>{words()}</View> : <Folding key={i} name={t("android-chat.history.thinking")} hint={thought.first} meta={null} failed={false} body={words} />;
          })}
        </View>
      )}
    </View>
  );
}

function StepRow({ step }: { step: HistoryStep }) {
  // Opened: the call drawn by what it is (a command, a diff, code, a plan, its fields), then what came back (ui/ToolStep.tsx).
  return (
    <Folding
      name={step.said ?? step.name}
      hint={step.said == null ? step.hint : null}
      meta={step.meta}
      failed={step.failed}
      body={() => <Whole brief={step.brief} entries={step.entries} body={() => <ToolStepBody name={step.name} call={step.call} said={step.said != null} result={step.result} failed={step.failed} />} />}
    />
  );
}

/** How long what was read whole has to show before what is held is taken for all there is (it came back in brief). */
const SETTLE_MS = 1000;

/**
 * What a step or thought holds, as it shows: in brief (only what names it came), read whole now (and again when it is in
 * brief anew: its result came, in brief), saying so till it comes; read and in brief still a moment later, what is held
 * is all there is.
 */
function Whole({ brief, entries, body }: { brief: boolean; entries: number[]; body: () => ReactNode }) {
  if (!brief) return <>{body()}</>;
  return <WholeRead entries={entries} body={body} />;
}

function WholeRead({ entries, body }: { entries: number[]; body: () => ReactNode }) {
  const C = useC();
  const detail = useContext(LocalDetail);
  const [error, setError] = useState<string | null>(null);
  const [settled, setSettled] = useState(false);
  const id = entries.join(",");
  useEffect(() => {
    setError(null);
    setSettled(false);
    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    detail(entries).then(
      () => { timer = setTimeout(() => { if (live) setSettled(true); }, SETTLE_MS); },
      (e: unknown) => { if (live && e instanceof CoreError) setError(errorText(e)); },
    );
    return () => { live = false; if (timer) clearTimeout(timer); };
  }, [id]);
  if (settled) return <>{body()}</>;
  return <T size={13} color={C.muted}>{error != null ? t("android-chat.history.stepUnread", { error }) : t("common.reading")}</T>;
}

/** A line that opens to what is behind it. */
function Folding({ name, hint, meta, failed, body }: { name: string; hint: string | null; meta: string | null; failed: boolean; body: () => ReactNode }) {
  const C = useC();
  const [open, setOpen] = useState(false);
  const follow = useContext(LocalFollow);
  return (
    <View style={{ gap: 4 }}>
      <Pressable
        onPress={() => { if (!open) follow?.stay(); setOpen(!open); }}
        android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}
        style={{ alignSelf: "stretch", paddingVertical: 3, flexDirection: "row", gap: 8, alignItems: "center" }}
      >
        <T size={13} color={failed ? C.red : C.ink} weight={hint != null ? "500" : undefined} numberOfLines={1} style={hint == null ? { flex: 1, minWidth: 0 } : { maxWidth: 160 }}>{name}</T>
        {/* The hint takes all the width the name and meta leave: two weights would cut it at half the row. */}
        {hint != null && <Text numberOfLines={1} style={[Mono, { fontSize: 12, color: C.muted, flexShrink: 1, includeFontPadding: false }]}>{hint}</Text>}
        {meta != null && meta !== "" && <T size={11} color={failed ? C.red : C.subtle}>{meta}</T>}
      </Pressable>
      {open && body()}
    </View>
  );
}

/** The turn's state with the model (the core's words), with a running clock. */
function PhaseLine({ phase }: { phase: HistoryPhase }) {
  const C = useC();
  const now = useNow();
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
      <View style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: C.accent }} />
      <T size={13} color={C.ink}>{phase.text}</T>
      <T size={12} color={C.subtle}>{`${Math.max(0, Math.trunc((now - phase.since) / 1000))}s`}</T>
    </View>
  );
}

/** Where it stands and its figures, how it runs (which can be changed here), what it has used, the station. */
function Details({ station, of, agent, history, host }: { station: string; of: ChatOf; agent: ChatAgent; history: HistoryView | undefined; host: Host | undefined }) {
  const s = agent.session;
  const card = rememberTopic<AgentCardView>(Topics.agentCard(station, s.key));
  const stationName = rememberStationName(station);
  const usage = history?.usage;
  return (
    <ScrollView style={{ alignSelf: "stretch" }} contentContainerStyle={{ paddingLeft: 18, paddingRight: 18, paddingBottom: 30 }}>
      {/* Where it stands and the figures that say most, as its card has them (AgentSheet.tsx). */}
      <AgentStatus agent={agent} modifier={{ paddingTop: 2 }} />
      <AgentTiles card={card.value ?? null} />
      <AgentNotes card={card.value ?? null} />
      <View style={{ height: 6 }} />
      {/* Changing how it runs is a screen of its own. */}
      <RunRow agent={agent} onOpen={() => app.push({ kind: "RunSettings", station, of, key: s.key })} />
      <View style={{ paddingTop: 12, paddingBottom: 10, gap: 8 }}>
        <Detail label={t("android-chat.history.detail.runtime")} value={s.runtimeText} />
        {s.processText != null && <Detail label={t("android-chat.history.detail.process")} value={s.processText} />}
        {card.value?.work != null && <Detail label={t("android-chat.agent.turns")} value={card.value.work} />}
      </View>
      {usage != null && usage.length > 0 && (
        <>
          <GroupLabel text={t("android-chat.agent.usage")} />
          <View style={{ paddingTop: 6, paddingBottom: 10, gap: 8 }}>{usage.map((u, i) => <Detail key={i} label={u.label} value={u.value} />)}</View>
        </>
      )}
      <GroupLabel text="Station" />
      <View style={{ paddingTop: 6, paddingBottom: 10, gap: 8 }}>
        <Detail label={t("android-chat.history.detail.name")} value={stationName} />
        {host != null && <Detail label={t("android-chat.history.detail.machine")} value={host.identity} />}
      </View>
      {host != null && host.meters.some((m) => m.level !== "ok") && <MeterChips meters={host.meters} modifier={{ paddingVertical: 10 }} alerts />}
    </ScrollView>
  );
}

/** How it runs, in one line: the model (never cut short), how hard it thinks, the account (cut short first). */
function RunRow({ agent, onOpen }: { agent: ChatAgent; onOpen: () => void }) {
  const C = useC();
  const s = agent.session;
  // The account it runs on now, as the core says.
  const name = agent.account?.name ?? "";
  return (
    <View style={{ alignSelf: "stretch", paddingTop: 6 }}>
      <Smooth radius={10} stroke={{ width: 1, color: C.line }}>
        <Pressable onPress={onOpen} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }} style={{ paddingHorizontal: 12, paddingVertical: 10, flexDirection: "row", alignItems: "center", gap: 6 }}>
          <MakerIcon maker={s.maker} runtime={s.runtime} size={15} />
          <T size={14} color={C.ink} numberOfLines={1}>{s.model != null ? (s.modelName ?? s.model) : t("android-chat.pick.model")}</T>
          <T size={14} color={C.muted} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>
            {` · ${s.effort ?? t("android-chat.pick.effort.default")} · ${s.profilePinned === true ? name : t("android-chat.history.run.auto", { name })}`}
          </T>
          <QuotaRings quota={agent.account?.quota ?? null} />
          <Icon icon={Icons.ChevronDown} size={14} color={C.muted} />
        </Pressable>
      </Smooth>
    </View>
  );
}

/**
 * Changing how an agent runs, full screen: what it is now, then the model, how hard it thinks and who runs it (the
 * station's pick, or one profile kept to), each said in plain words. Picks are a draft; the button at the bottom says
 * what it becomes (不变 when nothing changed); back leaves it as it was. A profile kept to that does not run the model
 * picked gives way to the station's pick, said so.
 */
export function RunSettingsScreen({ station, of, sessionKey: key }: { station: string; of: ChatOf; sessionKey: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const chat = rememberTopic<ChatView>(Topics.chat(station, of));
  const agent = chat.value?.agents?.find((a) => a.session.key === key);
  // What it runs on, what is picked here and what that means, as the core has them (web/src/pick.ts).
  const pickOf = `session:${key}`;
  const picking = rememberTopic<PickView>({ topic: "pick", station, of: pickOf });
  const v = picking.value;
  const pick = (fill: Record<string, unknown>) => {
    app.api(station).pickSet(pickOf, fill).catch((e: unknown) => { app.toast = t("android-chat.pick.failed", { error: e instanceof CoreError ? errorText(e) : messageOf(e) }); });
  };
  // Picked from what it runs on now, each time it is opened.
  useEffect(() => { pick({ open: true }); }, [station, key]);
  // A long list (the models, the accounts) is a list of its own, picked from and back.
  const [list, setList] = useState<string | null>(null);
  useEffect(() => {
    if (list == null) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { setList(null); return true; });
    return () => sub.remove();
  }, [list]);
  useApp((s) => s.doing);
  const busy = app.isDoing("pick.save", { station, of: `session:${key}` });
  const nav = (
    <NavBar
      back={list != null ? t("android-chat.run.title") : t("common.back")}
      onBack={() => { if (list != null) setList(null); else app.pop(); }}
      title={list === "model" ? t("android-chat.pick.model") : list === "account" ? t("android-chat.run.account.choose") : t("android-chat.run.title")}
    />
  );
  if (agent == null || v == null) return <View style={{ flex: 1 }}>{nav}<Waiting shape={WaitShape.Cards} text={t("common.reading")} error={chat.error?.message ?? picking.error?.message ?? null} /></View>;
  const s = agent.session;
  const chosen = v.draft.profile ?? null;
  if (list === "model") return <View style={{ flex: 1 }}>{nav}<ModelList models={v.options} runtime={s.runtime} picked={v.option ?? null} onPick={(m: string) => { pick({ model: m }); setList(null); }} /></View>;
  if (list === "account") return <View style={{ flex: 1 }}>{nav}<AccountList accounts={v.accounts} runtime={s.runtime} picked={chosen} onPick={(p: string | null) => { pick({ profile: p }); setList(null); }} /></View>;
  const labels = [t("android-chat.run.label.model"), t("android-chat.run.label.effort"), t("android-chat.run.label.account"), ...(v.fastAvailable === true ? [t("android-chat.run.label.speed")] : [])];
  const asPlan = t("android-chat.pick.speed.follow");
  const standard = t("android-chat.pick.speed.standard");
  const account = chosen != null ? v.accounts.find((a) => a.id === chosen) : undefined;
  const go = v.changed && v.option != null && !busy;
  return (
    <View style={{ flex: 1 }}>
      {nav}
      <ScrollView style={{ flex: 1, alignSelf: "stretch" }} contentContainerStyle={{ paddingHorizontal: 18 }}>
        {/* Always on top: what it was, and what it becomes, the changes marked; and when the account must change, why. */}
        <View style={{ alignSelf: "stretch", paddingTop: 8 }}>
          <Smooth radius={14} style={{ backgroundColor: C.chip, padding: 14, gap: 6 }}>
            {/* Each property on its line: what it was, and, when it changes, an arrow to what it becomes. */}
            {labels.map((label, i) => {
              const was = v.was[i] ?? "";
              const becomes = v.becomes[i] ?? "";
              const moved = becomes !== was;
              return (
                <View key={i} style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                  <T size={13} color={C.muted} style={{ width: lang() === "zh" ? 32 : 60 }}>{label}</T>
                  <T size={14} color={moved ? C.muted : C.ink} numberOfLines={1} style={moved ? { flexShrink: 1 } : { flex: 1, minWidth: 0 }}>{was}</T>
                  {moved && (
                    <>
                      <Icon icon={Icons.ArrowRight} size={14} color={C.accent} />
                      <T size={14} color={C.accent} weight="600" numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{becomes}</T>
                    </>
                  )}
                </View>
              );
            })}
            {v.force != null && <T size={12} color={C.warn}>{v.force}</T>}
            <T size={12} color={C.subtle}>{t("android-chat.run.next")}</T>
          </Smooth>
        </View>
        <GroupLabel text={t("android-chat.run.label.model")} />
        <SettingRow onClick={() => setList("model")} leading={() => <MakerIcon maker={v.maker} runtime={s.runtime} size={18} />} content={() => <T size={15} color={C.ink}>{v.modelText}</T>} />
        <GroupLabel text={t("android-chat.run.effort.title")} />
        <T size={12} color={C.muted} style={{ paddingBottom: 8 }}>{t("android-chat.run.effort.note")}</T>
        <EffortChips efforts={[null, ...v.efforts]} picked={v.draft.effort ?? null} onPick={(e: string | null) => pick({ effort: e })} />
        {v.fastAvailable === true && (
          <>
            <GroupLabel text={t("android-chat.run.label.speed")} />
            <T size={12} color={C.muted} style={{ paddingBottom: 8 }}>{t("android-chat.run.speed.note")}</T>
            <EffortChips
              efforts={[asPlan, standard, "Fast"]}
              picked={v.draft.fast === true ? "Fast" : v.draft.fast === false ? standard : asPlan}
              onPick={(speed: string | null) => pick({ fast: speed === "Fast" ? true : speed === standard ? false : null })}
            />
          </>
        )}
        <GroupLabel text={t("android-chat.run.label.account")} />
        <SettingRow
          onClick={() => setList("account")}
          leading={() => (account != null ? <ProviderMark runtime={account.runtime ?? s.runtime} kind={account.kind} size={18} mark={account.mark} /> : null)}
          content={() => (
            <>
              <T size={15} color={C.ink} numberOfLines={1}>{v.accountText}</T>
              <T size={12} color={C.muted}>{v.accountNote}</T>
              {v.accountWarn && <T size={12} color={C.warn}>{t("android-chat.run.account.warn")}</T>}
            </>
          )}
        />
        <View style={{ height: 16 }} />
      </ScrollView>
      <View style={{ paddingBottom: insets.bottom }}>
        <View style={{ paddingHorizontal: 18, paddingVertical: 12, alignSelf: "stretch" }}>
          <Smooth radius={16} style={{ backgroundColor: v.changed ? C.ink : C.chip }}>
            <Pressable
              disabled={busy}
              onPress={() => {
                // Back at once, not waiting on the station; failed, a toast says why.
                app.pop();
                if (!go) return;
                app.api(station).pickSave(pickOf).then(
                  () => { app.toast = t("android-chat.run.saved"); },
                  (err: unknown) => { if (err instanceof CoreError) app.toast = t("android-chat.save.failed", { error: errorText(err) }); },
                );
              }}
              android_ripple={{ color: withAlpha(v.changed ? C.bg : C.ink, 0.12), borderless: false }}
              style={{ minHeight: 52, paddingHorizontal: 16, paddingVertical: 12, alignItems: "center", justifyContent: "center" }}
            >
              <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                <BusyIcon busy={busy} solid={v.changed ? C.bg : null} />
                <T size={15} weight="600" color={v.changed ? C.bg : C.ink} numberOfLines={2} align="center">{v.saveText}</T>
              </View>
            </Pressable>
          </Smooth>
        </View>
      </View>
    </View>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  const C = useC();
  return (
    <View style={{ flexDirection: "row", gap: 16 }}>
      {/* As wide as the longest of them (缓存命中率): a label is not broken. */}
      <T size={14} color={C.muted} numberOfLines={1} style={{ width: 76 }}>{label}</T>
      <T size={14} color={C.ink} style={{ flex: 1, minWidth: 0 }}>{value}</T>
    </View>
  );
}

/** Seconds in short, as the chat's activity says them: 45s, 3m 20s, 10m, 1h 5m. */
function shortSpan(s: number): string {
  if (s < 60) return `${s}s`;
  if (s < 3600) return s % 60 !== 0 ? `${Math.trunc(s / 60)}m ${s % 60}s` : `${Math.trunc(s / 60)}m`;
  return Math.trunc((s % 3600) / 60) !== 0 ? `${Math.trunc(s / 3600)}h ${Math.trunc((s % 3600) / 60)}m` : `${Math.trunc(s / 3600)}h`;
}
