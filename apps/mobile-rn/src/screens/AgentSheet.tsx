// An agent of the chat in brief: a sheet over the chat, opened from its name beside its messages, its mark in the
// chat's bar or its row in the chat's own sheet (web mobile/AgentSheet.tsx; the wide screen's card over its avatar,
// web AgentCard.tsx). What it runs and where it stands (with a stop while it works), its latest lines, the figures
// that say most (the core's `agentCard` view, client/core-ts/src/views/brief.ts), then where to go on: the station it
// runs on, its account (how it runs), its history, its jobs. Only what is worth a look is coloured. The same parts head its history's
// details (History.tsx).
import { useEffect, useState, type ReactNode } from "react";
import { Pressable, ScrollView, Text, View, type StyleProp, type ViewStyle } from "react-native";
import type { AgentCardView, ChatAgent, ChatView, StationView } from "../../../../web/src/core/shapes.ts";
import { SheetSpec, useApp, type AppState, type ChatOf } from "../AppState";
import { rememberTopic, Topics } from "../data/Topics";
import { chatAgentState } from "../data/Chats";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import { hasStationMark, ModelMark, QuotaRings, StationMark } from "../ui/Parts";
import { SheetGrab } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { Spinner } from "../ui/Waiting";
import { elapsed } from "./Chat";
import { InfoList, InfoRow } from "./ChatInfo";
import { openHistory } from "./History";
import { openJobs } from "./Jobs";
import { toneColor } from "./Profiles";
import { openStationPeek } from "./Stations";

const working = (agent: ChatAgent) => agent.status === "running" || agent.status === "queued";

/** Opens `agent`'s card over its chat, as tall as what it shows (its lines' and figures' room kept while they are read). */
export function openAgent(app: AppState, station: string, of: ChatOf, agent: ChatAgent) {
  const key = agent.session.key;
  const rows = 3 + (agent.jobs.length > 0 ? 1 : 0);
  // What is wrong, a line each but a quota's (its account's windows say that).
  const notes = agent.attention.filter((a) => a.kind !== "quota").length;
  const tall = 22 + 52 + (agent.turns.length > 0 ? 72 + 76 : 0) + (notes > 0 ? 8 + notes * 20 : 0) + 12 + rows * 40 + 24;
  app.sheet = new SheetSpec(0.55, false, tall, null, false, () => <AgentCard app={app} station={station} of={of} agent={agent} agentKey={key} />);
}

function AgentCard({ app, station, of, agent, agentKey: key }: { app: AppState; station: string; of: ChatOf; agent: ChatAgent; agentKey: string }) {
  const C = useC();
  const chat = rememberTopic<ChatView>(Topics.chat(station, of));
  const card = rememberTopic<AgentCardView>(Topics.agentCard(station, key));
  const stations = rememberTopic<StationView[]>(Topics.stations(station.split("/")[0]!));
  const here = stations.value?.find((s) => s.station === station);
  const a = chat.value?.agents?.find((x) => x.session.key === key) ?? agent;
  const s = a.session;
  // The account it runs on now, with what is left of it.
  const account = a.account != null ? { name: a.account.name, quota: a.account.quota } : a.profile != null ? { name: a.profile.name, quota: a.profile.quota } : null;
  return (
    <>
      <SheetGrab />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingLeft: 18, paddingRight: 18, paddingBottom: 24 }}>
        <View style={{ flexDirection: "row", paddingTop: 4, alignItems: "center", gap: 12 }}>
          <ModelMark maker={s.maker} runtime={s.runtime} size={40} state={chatAgentState(a)} around={C.surface} />
          <View style={{ flex: 1, minWidth: 0, gap: 1 }}>
            <T size={17} weight="700" numberOfLines={1}>{s.agentText}</T>
            <AgentStatus agent={a} />
          </View>
          {working(a) && <StopButton app={app} station={station} agentKey={key} />}
        </View>
        <AgentLines card={card.value} />
        <AgentTiles card={card.value} />
        <AgentNotes card={card.value} />
        <View style={{ height: 12 }} />
        {/* Each row leaves the sheet for where it leads. */}
        <InfoList>
          {/* The station's card in place of this one. */}
          {here != null && (
            <InfoRow onClick={() => openStationPeek(app, station)}>
              <T size={14} color={C.muted}>{t("android-chat.agent.station")}</T>
              <View style={{ flex: 1, minWidth: 0, flexDirection: "row", alignItems: "center", gap: 6 }}>
                {hasStationMark(here.emoji, here.icon) && <StationMark emoji={here.emoji} icon={here.icon} size={15} tint={C.ink} />}
                <T size={14} numberOfLines={1} style={{ flexShrink: 1 }}>{here.name}</T>
              </View>
              <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
            </InfoRow>
          )}
          <AgentRow
            label={t("android-chat.agent.account")}
            value={account != null ? (s.profilePinned === true ? account.name : t("android-chat.agent.account.auto", { name: account.name })) : t("android-chat.agent.account.none")}
            trailing={<QuotaRings quota={account?.quota} />}
            onClick={() => { app.sheet = null; app.push({ kind: "RunSettings", station, of, key }); }}
          />
          <AgentRow label={t("android-chat.agent.history")} value={card.value?.work ?? t("android-chat.agent.history.none")} onClick={() => { app.sheet = null; openHistory(app, station, of, key); }} />
          {a.jobs.length > 0 && <AgentRow label={t("android-chat.agent.jobs")} value={card.value?.jobs ?? t("android-chat.agent.jobs.idle")} onClick={() => openJobs(app, station, of)} />}
        </InfoList>
      </ScrollView>
    </>
  );
}

/** Stopping its turn, while it works: under way, a spinner in it, not pressed again. */
function StopButton({ app, station, agentKey: key }: { app: AppState; station: string; agentKey: string }) {
  const C = useC();
  useApp((s) => s.doing);
  const busy = app.isDoing("session.stop", { station, key });
  return (
    <Smooth radius={16} style={{ height: 32, backgroundColor: withAlpha(C.red, 0.14) }}>
      <Pressable
        disabled={busy}
        onPress={() => app.act(t("android-chat.agent.stop"), () => app.api(station).stop(key), t("android-chat.history.stopped"))}
        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
        style={{ flex: 1, paddingHorizontal: 14, flexDirection: "row", alignItems: "center", gap: 6 }}
      >
        {busy ? <Spinner inline /> : <Icon icon={Icons.Stop} size={11} color={C.red} />}
        <T size={13} weight="500" color={C.red}>{t("android-chat.agent.stop")}</T>
      </Pressable>
    </Smooth>
  );
}

/** A row of the card: what it is about, what there is of it, and where a tap leads. */
function AgentRow({ label, value, trailing = null, onClick }: { label: string; value: string; trailing?: ReactNode; onClick: () => void }) {
  const C = useC();
  return (
    <InfoRow onClick={onClick}>
      <T size={14} color={C.muted}>{label}</T>
      <T size={14} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{value}</T>
      {trailing}
      <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
    </InfoRow>
  );
}

/**
 * For how long an agent has stood where it does, in words: at work since its turn began, waiting as long as it has
 * (of at most), else when it was last at it; none when nothing says. Its clock runs each second. (A hook.)
 */
export function agentSince(agent: ChatAgent): string | null {
  const wait = agent.wait;
  const since = agent.since;
  const ticking = wait != null || since != null;
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!ticking) return;
    setNow(Date.now());
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [ticking]);
  if (!ticking) return agent.session.time?.["lastActiveAt"]?.ago ?? null;
  if (wait != null) {
    const most = wait.seconds != null ? ` / ${elapsed(wait.seconds * 1000)}` : "";
    const waited = wait.seconds != null ? Math.min(now, wait.since + wait.seconds * 1000) : now;
    return elapsed(waited - wait.since) + most;
  }
  return elapsed(now - since!);
}

/** Where it stands, in words after a dot in its tone, and for how long; two lines at most (a need or a failure can be long). */
export function AgentStatus({ agent, style }: { agent: ChatAgent; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const s = agent.session;
  const since = agentSince(agent);
  const tone = toneColor(s.tone);
  return (
    <View style={[{ flexDirection: "row", gap: 6 }, style]}>
      {/* On the first line's middle. */}
      <View style={{ marginTop: 6, width: 6, height: 6, borderRadius: 3, backgroundColor: s.tone === "neutral" ? C.subtle : tone }} />
      <T size={13} line={18} numberOfLines={2} style={{ flexShrink: 1 }}>
        {s.statusText}
        {since != null && <Text style={{ color: C.muted, fontVariant: ["tabular-nums"] }}>{` · ${since}`}</Text>}
      </T>
    </View>
  );
}

/** Its latest lines (the core's): the things it did, then what it does now, in the ink. */
function AgentLines({ card }: { card: AgentCardView | undefined }) {
  const C = useC();
  const latest = card?.latest ?? [];
  if (latest.length === 0) return null;
  return (
    <View style={{ alignSelf: "stretch", paddingTop: 12, gap: 3 }}>
      {latest.map((l) => <T key={l.key} size={13} line={18} color={l.now === true ? C.ink : C.muted} numberOfLines={1}>{l.text}</T>)}
    </View>
  );
}

/** A figure of more letters than this is drawn a size down (three tiles share a phone's width). */
const LONG = 6;

/**
 * The figures that say most, each large over its name, side by side: what it cost, the cache's hit rate, how full its
 * context is. In the ink, but a context worth a look in its level's colour.
 */
export function AgentTiles({ card, style = { paddingTop: 14 } }: { card: AgentCardView | undefined; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const context = card?.context;
  if (card?.cost == null && card?.cache == null && context == null) return null;
  const tile = (figure: string, name: string, color: string = C.ink) => (
    <Smooth
      key={name}
      radius={14}
      accessible
      accessibilityLabel={`${name} ${figure}`}
      style={{ flex: 1, minWidth: 0, backgroundColor: withAlpha(C.ink, 0.05), paddingLeft: 12, paddingRight: 12, paddingTop: 9, paddingBottom: 8 }}
    >
      <View style={{ height: 26, justifyContent: "center" }}>
        <T size={figure.length > LONG ? 16 : 20} weight="600" color={color} numberOfLines={1} style={{ fontVariant: ["tabular-nums"] }}>{figure}</T>
      </View>
      <T size={12} line={16} color={C.muted} numberOfLines={1}>{name}</T>
    </Smooth>
  );
  return (
    <View style={[style, { alignSelf: "stretch", flexDirection: "row", gap: 8 }]}>
      {card?.cost != null && tile(card.cost, t("android-chat.agent.cost"))}
      {card?.cache != null && tile(card.cache.text, t("android-chat.agent.cache"))}
      {/* How full, of a window that is known; else how much it holds. */}
      {context != null && (context.unknown === true
        ? tile(context.text, t("android-chat.agent.context"))
        : tile(`${Math.round(context.percent)}%`, t("android-chat.agent.context"), context.level === "red" ? C.red : context.level === "amber" ? C.warn : C.ink))}
    </View>
  );
}

/** What is wrong (an account that cannot run, the disk filling up), a line each in its level's colour. */
export function AgentNotes({ card, style = { paddingTop: 10 } }: { card: AgentCardView | undefined; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const notes = card?.attention ?? [];
  if (notes.length === 0) return null;
  return (
    <View style={[style, { gap: 2 }]}>
      {notes.map((a, i) => <T key={i} size={13} line={18} color={a.level === "amber" ? C.warn : C.red}>{a.text}</T>)}
    </View>
  );
}
