// Connects (as the narrow web's web/src/mobile/Connects.tsx, from the desktop's Connects.tsx and Connect.tsx): the
// list of every station's, all or the viewer's; a connect's page (how it runs, how its conversations become sessions, its Slack link, what
// is done to it less often under "…"); how it runs, picked on a page of its own; a new one, a step a screen.
// (The Android app's screens/Connects.kt.)
import { useEffect, useMemo, useState, useSyncExternalStore, type ReactNode } from "react";
import { BackHandler, Linking, Pressable, ScrollView, TextInput, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { core, useTopic } from "../../../../web/src/core/react.ts";
import type { Connect, ConnectFlowView, ConnectItem, ConnectsView, MadeSlackApp, PickView, SlackTokenForm, SlackTokensView, StationView } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import type { CoreError } from "../../../../web/src/core/client.ts";
import { app as theApp, SheetSpec, type AppState } from "../AppState";
import { APP_NAME } from "../build";
import type { WorkspaceEntry, WorkspaceView } from "../data/Accounts";
import { errorText } from "../data/Calls";
import { MODE_LABEL, MODE_TEXT, RUNTIME_LABEL } from "../data/Words";
import { t } from "../i18n";
import { Button, DoingMark, Field, GroupLabel, PickRow } from "../ui/Controls";
import { Illustration } from "../ui/Drawing";
import { Icon, Icons } from "../ui/Icon";
import { BarAction } from "../ui/Bar";
import { Avatar, Card, ListCard, ListRow, MakerIcon, NavBar, NavButton, SectionHeader, Seg, SlackMark } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { StatusText } from "../ui/StatusText";
import { T } from "../ui/Text";
import { CODE_FONT, useC, withAlpha } from "../ui/Theme";
import { BusyIcon, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { rememberConnectFlow, type ConnectFlow } from "./ConnectFlow";
import { PlacePage } from "./PlacePage";
import { BandFilter, PlaceEmpty } from "./PlaceRows";
import { openPickStation } from "./Profiles";
import { confirm } from "./Settings";
import { AccountList, EffortChips, ModelList, SettingRow } from "./SettingParts";
import { AppDraft, AppLook, ConfigTokenSteps, FormLabel, type IconPick } from "./SlackApp";
import { BarRoom } from "./Stations";

/** What a failure says (Kotlin's `e.message`). */
const messageOf = (e: unknown) => (e instanceof Error ? e.message : String(e));

/** A connect's presence as a dot: online green, at work orange, failing red, offline hollow. */
export function PresenceDot({ state }: { state: string }) {
  const C = useC();
  const m = { width: 7, height: 7, borderRadius: 3.5 } as const;
  return (
    <View
      style={
        state === "online" ? { ...m, backgroundColor: C.green }
          : state === "busy" ? { ...m, backgroundColor: C.accent }
            : state === "error" ? { ...m, backgroundColor: C.red }
              : { ...m, borderWidth: 1.5, borderColor: C.subtle }
      }
    />
  );
}

/** A connect as its people see it in Slack: its bot's picture; Slack's mark until Slack has said what that is. */
export function ConnectAvatar({ c, size }: { c: Connect; size: number }) {
  const image = c.botImage;
  if (image != null) return <Avatar id={c.id} name={c.name} size={size} picture={image} />;
  return (
    <View style={{ width: size, height: size, alignItems: "center", justifyContent: "center" }}>
      <SlackMark size={size * 0.55} />
    </View>
  );
}

/** A connect in its station's list: its bot's picture and name, how it runs, and its presence. */
export function ConnectRow({ station, c }: { station: string; c: Connect }) {
  const C = useC();
  const app = theApp;
  const runs = [c.modeText, c.runtimeText, c.bind.model != null ? (c.modelName ?? c.bind.model) : null].filter((x): x is string => x != null);
  return (
    <ListRow onClick={() => app.push({ kind: "Connect", station, connect: c.id })}>
      <ConnectAvatar c={c} size={30} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} color={C.ink} numberOfLines={1}>{c.name + (c.team != null ? ` · ${c.team}` : "")}</T>
        <T size={13} color={C.muted} numberOfLines={1}>{runs.join(" · ")}</T>
      </View>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 5 }}>
        <PresenceDot state={c.presence} />
        <StatusText text={c.statusText} fontSize={12} color={C.muted} />
      </View>
    </ListRow>
  );
}

/**
 * A connect by its station and id, as the workspace's connects view has it; and what its page shows while it is not
 * there: the view's first read waited on (what could not be read in red), or, read, that there is none.
 * (A hook: Kotlin's name kept.)
 */
function rememberConnect(station: string, id: string): [ConnectItem | null, () => ReactNode] {
  const connects = useTopic<ConnectsView>({ topic: "connects", scope: station.split("/")[0]!, mine: false });
  const view = connects.value;
  const item = view?.items.find((it) => it.station === station && it.connect.id === id) ?? null;
  const error = connects.error?.message;
  const missing = (): ReactNode => {
    if (view == null || error != null) return <Waiting shape={WaitShape.Cards} text={t("android-settings.connects.reading")} error={error} />;
    if (view.wait.reading || view.wait.failing.length > 0) return <Waiting shape={WaitShape.Cards} note={view.wait} />;
    return <PlaceEmpty text={t("android-settings.connects.none")} />;
  };
  return [item, missing];
}

/**
 * Every station's connects on one page, from settings (SettingsHome.tsx), as the narrow web's ConnectsScreen: all or those
 * the viewer made, each station's under its name with the Slack apps made there and not connected yet; a station offline
 * says so. A new one is added on a station picked (the only one online, without asking).
 */
export function ConnectsScreen({ current, only = null }: { current: WorkspaceEntry; only?: string | null }) {
  const C = useC();
  const app = theApp;
  const insets = useSafeAreaInsets();
  const [mine, setMine] = useState(false);
  const connects = useTopic<ConnectsView>({ topic: "connects", scope: current.workspace.id, mine });
  const topic = useTopic<StationView[]>({ topic: "stations", scope: current.workspace.id });
  // From a station's page: that station's only, back to it.
  const stations = topic.value != null ? (only == null ? topic.value : topic.value.filter((it) => it.station === only)) : null;
  const one = only != null ? (stations?.[0] ?? null) : null;
  const online = (stations ?? []).filter((it) => it.online);
  const view = connects.value;
  // A connect is added on a station online (the only one, without asking).
  const add = online.length > 0
    ? new BarAction("add-connect", t("android-misc.bar.action.connects"), Icons.Plus, () => {
      if (online.length === 1) openNewConnect(app, online[0]!.station);
      else openPickStation(app, t("android-settings.flow.title"), online, (it: StationView) => openNewConnect(app, it.station));
    })
    : null;
  // A station's own (from its page): back to it.
  const filters = [t("android-settings.connects.all"), t("android-settings.connects.mine")];
  // None to show yet (no connect, no app made): the stations not read yet, or those that could not be.
  const none = view != null && view.items.length === 0 && (stations ?? []).every((it) => (it.overview?.slackApps ?? []).length === 0);
  const waits = view != null && (view.wait.reading || view.wait.failing.length > 0);
  // All or the viewer's, as the chats' filter: a menu in the top bar.
  return (
    <PlacePage
      current={current}
      place="connects"
      primary={add}
      known={topic.value != null || topic.error != null}
      back={one?.name ?? t("android-settings.title")}
      actions={<BandFilter label={t("android-settings.connects.title")} options={filters} selected={mine ? 1 : 0} onSelect={(it: number) => setMine(it === 1)} />}
    >
      {(top: number) => (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom, paddingTop: top }}>
          {stations == null || view == null ? (
            <Waiting shape={WaitShape.Rows} count={3} text={t("android-settings.connects.reading")} error={connects.error?.message ?? topic.error?.message} />
          ) : one == null && none && waits ? (
            <Waiting shape={WaitShape.Rows} count={3} note={view.wait} />
          ) : (
            stations.map((s) => {
              const here = view.items.filter((it) => it.station === s.station);
              const waiting = s.overview?.slackApps ?? [];
              if (s.online && here.length === 0 && waiting.length === 0 && mine && one == null) return null;
              return (
                <View key={s.station}>
                  {one == null && <SectionHeader title={s.online ? s.name : t("android-settings.connects.offline", { name: s.name })} start={24} />}
                  <ListCard>
                    {!s.online && here.length === 0 ? (
                      <ListRow><T size={15} color={C.muted}>{t("android-settings.connects.stationOffline")}</T></ListRow>
                    ) : here.length === 0 && waiting.length === 0 ? (
                      <ListRow>{s.overview != null ? <T size={15} color={C.muted}>{t("android-settings.connects.empty")}</T> : <WaitLine text={t("common.reading")} />}</ListRow>
                    ) : null}
                    {here.map((it) => <ConnectRow key={it.connect.id} station={it.station} c={it.connect} />)}
                    {/* The Slack apps made here that no connect has taken yet: to be finished any time. */}
                    {waiting.map((a) => <WaitingApp key={a.appId} app={app} station={s.station} a={a} online={s.online} />)}
                  </ListCard>
                </View>
              );
            })
          )}
          {/* What a connect is, said while there is none (the page has no note at its top). */}
          {one == null && none && !waits && <PlaceEmpty text={t("android-settings.connects.note", { app: APP_NAME })} />}
          <View style={{ height: 30 }} />
          <BarRoom />
        </ScrollView>
      )}
    </PlacePage>
  );
}

const CONNECT_CHANGES = ["connect.reconnect", "connect.put"];

export function ConnectScreen({ station, id }: { station: string; id: string }) {
  const C = useC();
  const app = theApp;
  const insets = useSafeAreaInsets();
  const [item, missing] = rememberConnect(station, id);
  // A change asked from its menu or sheets (they close at once): a spinner until the station has it, a red mark a moment if it failed.
  const changing = useDoing(CONNECT_CHANGES, { station, id });
  const changeFailed = useDoingFailed(CONNECT_CHANGES, { station, id });
  const binding = useDoing("connect.bindSession", { station, connect: id });
  const bindFailed = useDoingFailed("connect.bindSession", { station, connect: id });
  if (item == null) {
    return (
      <View style={{ flex: 1 }}>
        <NavBar back={t("android-settings.connects.title")} onBack={() => app.pop()} title={t("android-settings.connects.title")} />
        {missing()}
      </View>
    );
  }
  const connect = item.connect;
  const c = connect.connection;
  const runLine = [
    connect.bind.model != null ? (connect.modelName ?? connect.bind.model) : t("android-settings.connect.pickModel"),
    connect.bind.effort ? connect.bind.effort : t("android-settings.connect.defaultEffort"),
    connect.bind.profile != null ? t("android-settings.connect.fixedAccount") : t("android-settings.connect.autoAccount"),
  ].join(" · ");
  const ripple = { color: withAlpha(C.ink, 0.1) };
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back={t("android-settings.connects.title")}
        onBack={() => app.pop()}
        title={connect.name}
        sub={<><PresenceDot state={connect.presence} /><StatusText text={connect.statusText} fontSize={11} color={C.muted} /></>}
        trailing={<NavButton icon={Icons.More} onClick={() => openConnectMenu(app, station, connect)} />}
      />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom, paddingTop: 12 }}>
        {/* Who it is in Slack: its bot's picture, its Slack workspace, whose it is. */}
        <Card>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
            <ConnectAvatar c={connect} size={44} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink} numberOfLines={1}>{connect.team ?? "Slack"}</T>
              <T size={13} color={C.muted} numberOfLines={1}>
                {item.stationName + (connect.createdBy != null ? t("android-settings.connect.owner", { name: connect.createdBy.shown?.display ?? connect.createdBy.name }) : "")}
              </T>
            </View>
            <DoingMark running={changing} failed={changeFailed} />
          </View>
        </Card>
        {(c.state === "no_tokens" || c.state === "error" || (c.state === "reconnecting" && c.lastError != null)) && (
          <Callout>
            {c.state === "no_tokens" ? (
              <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                <T size={13} color={C.ink}>{t("android-settings.connect.noTokens")}</T>
                <Pressable onPress={() => openTokens(app, station, connect)} android_ripple={ripple}>
                  <T size={13} color={C.accent}>{t("android-settings.connect.fillTokens")}</T>
                </Pressable>
              </View>
            ) : (
              <T size={13} color={C.ink}>{c.state === "error" ? (c.error ?? "") : t("android-settings.connect.reconnecting", { error: c.lastError ?? "" })}</T>
            )}
          </Callout>
        )}
        <SectionHeader title={t("android-settings.connect.run")} start={24} />
        <ListCard>
          <ListRow onClick={() => app.push({ kind: "ConnectRun", station, connect: connect.id })}>
            <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="clip" style={{ minWidth: 32 }}>{t("android-settings.connect.model")}</T>
            <T size={15} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{runLine}</T>
            <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
          </ListRow>
          <ListRow onClick={() => { app.sheet = new SheetSpec(0.8, true, null, null, false, () => <ModeSheet station={station} item={item} />); }}>
            <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="clip" style={{ minWidth: 32 }}>{t("android-settings.connect.sessions")}</T>
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{MODE_LABEL[connect.mode] ?? connect.mode}</T>
              <T size={13} color={C.muted}>
                {(MODE_TEXT[connect.mode] ?? "") + (connect.mode === "single-session" ? (connect.requireMention ? t("android-settings.connect.mentionOnly") : t("android-settings.connect.everyMessage")) : "")}
              </T>
            </View>
            <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
          </ListRow>
          {connect.mode === "single-session" && (
            <ListRow onClick={() => { app.sheet = new SheetSpec(0.7, true, null, null, false, () => <SessionSheet station={station} item={item} />); }}>
              <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="clip" style={{ minWidth: 32 }}>{t("android-settings.connect.current")}</T>
              <T size={15} color={item.bound != null ? C.ink : C.muted} style={{ flex: 1, minWidth: 0 }}>{item.bound?.titleText ?? t("android-settings.connect.noSession")}</T>
              <DoingMark running={binding} failed={bindFailed} />
              <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
            </ListRow>
          )}
        </ListCard>
        <T size={13} color={C.muted} style={{ paddingHorizontal: 24, paddingVertical: 4 }}>{t("android-settings.connect.runtime", { runtime: connect.runtimeText })}</T>
        {/* Its Slack app, changed now and then: name, picture, colour, permissions (the desktop's SlackAppSection). */}
        <SectionHeader title="Slack app" start={24} />
        <ListCard>
          <ListRow onClick={() => app.push({ kind: "SlackApp", station, connect: connect.id })}>
            <SlackMark size={16} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{t("android-settings.slack.sub")}</T>
              <T size={13} color={C.muted}>{t("android-settings.connect.slackAppNote")}</T>
            </View>
            <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
          </ListRow>
        </ListCard>
        <SectionHeader title={t("android-settings.connect.recent")} start={24} />
        <ListCard>
          {item.sessions.length === 0 && <ListRow><T size={15} color={C.muted}>{t("android-settings.connect.noSessions", { name: connect.name })}</T></ListRow>}
          {item.sessions.map((s) => (
            <ListRow key={s.key} onClick={() => app.push({ kind: "Chat", station, of: { session: s.key } })}>
              <T size={15} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{s.titleText}</T>
              <StatusText text={s.statusText} fontSize={13} color={C.muted} />
            </ListRow>
          ))}
        </ListCard>
        <View style={{ height: 30 }} />
      </ScrollView>
    </View>
  );
}

function Callout({ children }: { children: ReactNode }) {
  const C = useC();
  return (
    <View style={{ paddingHorizontal: 12, paddingBottom: 10 }}>
      <Smooth radius={12} style={{ backgroundColor: withAlpha(C.warn, 0.12), paddingHorizontal: 12, paddingVertical: 10 }}>{children}</Smooth>
    </View>
  );
}

/** What is done to a connect less often: reconnecting, its tokens, Slack, turning it off or on, its owner, deleting it. */
function openConnectMenu(app: AppState, station: string, connect: Connect) {
  const api = app.api(station);
  app.sheet = new SheetSpec(0.6, false, null, null, false, () => <ConnectMenuSheet app={app} api={api} station={station} connect={connect} />);
}

/** openConnectMenu's sheet (a component, for what it reads of the doing list). */
function ConnectMenuSheet({ app, api, station, connect }: { app: AppState; api: ReturnType<AppState["api"]>; station: string; connect: Connect }) {
  const C = useC();
  // Under way (asked a moment ago, the sheet opened again): a spinner on its row, and neither tapped again.
  const reconnecting = useDoing("connect.reconnect", { station, id: connect.id });
  const switching = useDoing("connect.put", { station, id: connect.id });
  // Failed a moment ago (the sheet may have been closed meanwhile): a red mark on its row, a tap says why.
  const reconnectFailed = useDoingFailed("connect.reconnect", { station, id: connect.id });
  const switchFailed = useDoingFailed("connect.put", { station, id: connect.id });
  // Closes at once and goes on by itself: the connect's page marks it under way, a toast says how it ended.
  const act = (what: string, done: string, call: () => Promise<unknown>) => { app.sheet = null; app.act(what, call, done); };
  const url = connect.connection.workspace?.url;
  return (
    <>
      <SheetGrab />
      <SheetHead title={connect.name} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <PickRow label={t("android-settings.connect.reconnect")} enabled={!switching} busy={reconnecting} failed={reconnectFailed}
          onClick={() => act(t("android-settings.connect.reconnectWhat"), t("android-settings.connect.reconnected"), () => api.reconnect(connect.id))} />
        <PickRow label={t("android-settings.connect.changeTokens")} onClick={() => openTokens(app, station, connect)} />
        {url != null && <PickRow label={t("android-settings.connect.openSlack")} onClick={() => { void Linking.openURL(url); }} />}
        {connect.enabled ? (
          <PickRow label={t("android-settings.connect.disable")} sub={t("android-settings.connect.disableNote")} enabled={!reconnecting} busy={switching} failed={switchFailed}
            onClick={() => act(t("android-settings.connect.disableWhat"), t("android-settings.connect.disabled"), () => api.putConnect(connect.id, { enabled: false }))} />
        ) : (
          <PickRow label={t("android-settings.connect.enable")} enabled={!reconnecting} busy={switching} failed={switchFailed}
            onClick={() => act(t("android-settings.connect.enableWhat"), t("android-settings.connect.enabled"), () => api.putConnect(connect.id, { enabled: true }))} />
        )}
        <PickRow label={t("android-settings.connect.changeOwner")} sub={connect.createdBy?.shown?.display ?? connect.createdBy?.name}
          onClick={() => { app.sheet = new SheetSpec(0.6, false, null, null, false, () => <OwnerSheet station={station} connect={connect} />); }} />
        <PickRow label={t("android-settings.connect.delete")} color={C.red} onClick={() => {
          confirm(app, t("android-settings.connect.deleteTitle", { name: connect.name }),
            connect.sessions > 0 ? t("android-settings.connect.deleteTextSessions", { n: connect.sessions }) : t("android-settings.connect.deleteText"),
            t("android-settings.connect.delete"), true, t("android-settings.connect.deleteWhat"), () => app.pop(),
            async () => { await api.deleteConnect(connect.id); app.toast = t("android-settings.connect.deleted"); });
        }} />
      </ScrollView>
    </>
  );
}

/** Hands a connect to another person of the workspace. */
function OwnerSheet({ station, connect }: { station: string; connect: Connect }) {
  const C = useC();
  const app = theApp;
  const ws = useTopic<WorkspaceView>({ topic: "workspace", workspace: station.split("/")[0]! });
  // The one picked closes the sheet at once; the connect's page marks it under way until the station has it.
  const busy = useDoing("connect.put", { station, id: connect.id });
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.connect.changeOwner")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <T size={12} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 4 }}>{t("android-settings.connect.ownerNote")}</T>
        {(ws.value?.members ?? []).map((m) => {
          const current = connect.createdBy != null && m.email.toLowerCase() === connect.createdBy.id.toLowerCase();
          return (
            <PickRow key={m.email} label={m.name || m.email} sub={m.email} checked={current} enabled={!busy} onClick={() => {
              app.sheet = null;
              if (!current) app.act(t("android-settings.connect.ownerWhat"), () => app.api(station).putConnect(connect.id, { owner: { id: m.email, name: m.name || m.email } }), t("android-settings.connect.ownerChanged"));
            }} />
          );
        })}
      </ScrollView>
    </>
  );
}

/** What switching a connect to `next` does to its conversations, in plain words (web/src/pages/Connect.tsx → consequences). */
function consequences(connect: Connect, mode: string, requireMention: boolean, running: number): string[] {
  const out: string[] = [];
  if (connect.mode === "multi-session" && mode === "single-session") {
    out.push(t("android-settings.mode.toSingle"));
    out.push(connect.session != null ? t("android-settings.mode.keepSession") : t("android-settings.mode.newSession"));
    if (!requireMention) out.push(t("android-settings.mode.noMention"));
  } else if (connect.mode === "single-session" && mode === "multi-session") {
    out.push(t("android-settings.mode.toMulti"));
    out.push(t("android-settings.mode.oldThreads"));
    out.push(t("android-settings.mode.back"));
  } else if (requireMention !== connect.requireMention) {
    out.push(requireMention ? t("android-settings.mode.mention") : t("android-settings.mode.noMention"));
  }
  if (running > 0) out.push(t("android-settings.mode.running", { n: running }));
  return out;
}

/** The mode picker: each way with what it means, and in single-session whether it waits for an @. */
function ModeChoices({ mode, requireMention, onChange }: { mode: string; requireMention: boolean; onChange: (mode: string, requireMention: boolean) => void }) {
  const C = useC();
  const ripple = { color: withAlpha(C.ink, 0.1) };
  return (
    <View style={{ gap: 8 }}>
      {["multi-session", "single-session"].map((m) => {
        const on = mode === m;
        return (
          <Smooth key={m} radius={14} stroke={{ width: on ? 2 : 1, color: on ? C.accent : C.line }} style={{ backgroundColor: C.surface }}>
            <Pressable onPress={() => onChange(m, m === "multi-session" ? true : requireMention)} android_ripple={ripple} style={{ paddingHorizontal: 14, paddingVertical: 12 }}>
              <T size={15} weight="600" color={C.ink}>{MODE_LABEL[m] ?? m}</T>
              <T size={13} color={C.muted}>{MODE_TEXT[m] ?? ""}</T>
            </Pressable>
          </Smooth>
        );
      })}
      {mode === "single-session" && (
        <Smooth radius={14} style={{ backgroundColor: C.chip }}>
          <Pressable onPress={() => onChange(mode, !requireMention)} android_ripple={ripple}
            style={{ paddingHorizontal: 14, paddingVertical: 10, flexDirection: "row", alignItems: "center", gap: 12 }}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={14} weight="600" color={C.ink}>{t("android-settings.mode.mentionTitle")}</T>
              <T size={13} color={C.muted}>{requireMention ? t("android-settings.mode.mentionOn") : t("android-settings.mode.mentionOff")}</T>
            </View>
            <Switch on={requireMention} />
          </Pressable>
        </Smooth>
      )}
    </View>
  );
}

export function Switch({ on }: { on: boolean }) {
  const C = useC();
  return (
    <Smooth radius={13} style={{ width: 44, height: 26, backgroundColor: on ? C.green : C.line, justifyContent: "center" }}>
      <View style={{ transform: [{ translateX: on ? 21 : 3 }], width: 20, height: 20, borderRadius: 10, backgroundColor: "#FFFFFF" }} />
    </Smooth>
  );
}

/** How its conversations become sessions: picked, with what changing it does said before it is done. */
function ModeSheet({ station, item }: { station: string; item: ConnectItem }) {
  const C = useC();
  const app = theApp;
  const connect = item.connect;
  const [mode, setMode] = useState<string>(connect.mode);
  const [mention, setMention] = useState(connect.requireMention);
  const busy = useDoing("connect.put", { station, id: connect.id });
  const changed = mode !== connect.mode || (mode === "single-session" && mention !== connect.requireMention);
  const effects = changed ? consequences(connect, mode, mention, item.running) : [];
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.mode.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, gap: 10 }}>
        <ModeChoices mode={mode} requireMention={mention} onChange={(m, r) => { setMode(m); setMention(r); }} />
        {effects.length > 0 && (
          <Smooth radius={12} style={{ backgroundColor: withAlpha(C.warn, 0.12), padding: 12, gap: 4 }}>
            <T size={13} weight="600" color={C.ink}>{t("android-settings.mode.after")}</T>
            {effects.map((it, i) => <T key={i} size={13} color={C.ink}>{`· ${it}`}</T>)}
          </Smooth>
        )}
        <View style={{ flexDirection: "row", gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button
            label={mode === connect.mode ? t("android-settings.mode.confirm") : mode === "single-session" ? t("android-settings.mode.toSingleButton") : t("android-settings.mode.toMultiButton")}
            primary
            enabled={changed && !busy}
            onClick={() => {
              const [m, r] = [mode, mention];
              app.sheet = null;
              app.act(t("android-settings.mode.changeWhat"), () => app.api(station).putConnect(connect.id, { mode: m, requireMention: r }), t("android-settings.mode.changed"));
            }}
          />
        </View>
      </ScrollView>
    </>
  );
}

/** A single-session connect's session: the one its messages go into, switched, or a new one. */
function SessionSheet({ station, item }: { station: string; item: ConnectItem }) {
  const C = useC();
  const app = theApp;
  const connect = item.connect;
  const [choice, setChoice] = useState(connect.session ?? "new");
  const [title, setTitle] = useState("");
  const busy = useDoing("connect.bindSession", { station, connect: connect.id });
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.session.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24, gap: 4 }}>
        <T size={12} color={C.muted} style={{ paddingHorizontal: 20 }}>{t("android-settings.session.note", { name: connect.name })}</T>
        <PickRow label={t("android-settings.session.new")} sub={t("android-settings.session.newNote")} checked={choice === "new"} onClick={() => setChoice("new")} />
        {choice === "new" && <View style={{ paddingHorizontal: 20 }}><Field value={title} onChange={setTitle} placeholder={t("android-settings.session.namePlaceholder")} /></View>}
        {item.candidates.map((s) => <PickRow key={s.key} label={s.titleText} sub={s.agentText} checked={choice === s.key} onClick={() => setChoice(s.key)} />)}
        <View style={{ paddingHorizontal: 20, paddingVertical: 6, flexDirection: "row", gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button
            label={choice === "new" ? t("android-settings.session.createUse") : t("android-settings.session.use")}
            primary
            enabled={choice !== connect.session && !busy}
            onClick={() => {
              const [picked, name] = [choice, title];
              app.sheet = null;
              app.act(
                picked === "new" ? t("android-settings.session.createWhat") : t("android-settings.session.switchWhat"),
                () => app.api(station).bindSession(connect.id, picked === "new" ? null : picked, name),
                picked === "new" ? t("android-settings.session.created") : t("android-settings.session.switched"),
              );
            }}
          />
        </View>
      </ScrollView>
    </>
  );
}

// ── tokens ─────────────────────────────────────────────────────────────

const NO_TOKENS: SlackTokensView = { appToken: "", botToken: "", errors: [], ready: false };

/**
 * The form is owned by the shared core; this adapter only binds its values to React. Kotlin's `view` and the echoes
 * are Compose state: here the echoes (typed into the fields, between renders) are observed (`subscribe`, read with
 * useSyncExternalStore by what shows them), and `view` and `checking` are what rememberTokens' hooks read, put here each
 * render (as Kotlin's `tokens.view = topic.value`).
 */
class Tokens {
  view: SlackTokensView = NO_TOKENS;
  // Immediate text-field echo; readiness, validation and the draft itself belong to core.
  #appEcho = "";
  #botEcho = "";
  #checking = false;
  readonly #listeners = new Set<() => void>();
  #version = 0;
  readonly address: SlackTokenForm;

  constructor(private readonly owner: AppState, private readonly station: string, readonly form: string) {
    this.address = { station, form };
  }

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  #changed() { this.#version++; for (const l of this.#listeners) l(); }

  get app(): string { return this.#appEcho; }
  set app(value: string) { this.#appEcho = value; this.#changed(); this.#edit({ appToken: value }); }
  get bot(): string { return this.#botEcho; }
  set bot(value: string) { this.#botEcho = value; this.#changed(); this.#edit({ botToken: value }); }
  get verified() { return this.view.appToken === this.#appEcho && this.view.botToken === this.#botEcho ? (this.view.verified ?? null) : null; }
  get errors() { return this.view.errors; }
  get checking() { return this.#checking; }
  get ready() { return this.view.ready; }
  /** What rememberTokens' hooks read this render: the core's view, and whether a check is under way. */
  seen(view: SlackTokensView, checking: boolean) { this.view = view; this.#checking = checking; }

  call(action: string, input: Record<string, unknown> | null = null): Promise<unknown> {
    return core().call(`slack.tokens.${action}`, { ...this.address, ...(input != null ? { input } : {}) });
  }
  #edit(input: Record<string, unknown>) { this.owner.act(t("android-settings.tokens.edit"), () => this.call("edit", input)); }
  reset() { this.#edit({ clear: true }); }
  then(go: () => Promise<void>) {
    if (this.checking) return;
    this.owner.act(t("android-settings.tokens.verify"), async () => { if ((await this.call("verify")) === true) await go(); });
  }
}

/** A hook (Kotlin's name kept): the tokens' form on `station` (`form`, else a new one), for `connect` or an `install`, dropped with the page. */
function rememberTokens(app: AppState, station: string, connect: string | null = null, install: string | null = null, form: string | null = null): Tokens {
  const tokens = useMemo(() => new Tokens(app, station, form ?? crypto.randomUUID()), [app, station, form]);
  useSyncExternalStore(tokens.subscribe, () => tokens.version);
  const topic = useTopic<SlackTokensView>({ topic: "slackTokens", ...tokens.address });
  const checking = useDoing("slack.tokens.verify", { station, form: tokens.form });
  tokens.seen(topic.value ?? NO_TOKENS, checking);
  useEffect(() => {
    tokens.call("edit", { connect, install }).catch((e: unknown) => { app.toast = messageOf(e); });
  }, [tokens, connect, install]);
  useEffect(() => () => {
    app.act(t("android-settings.tokens.drop"), () => tokens.call("drop"));
  }, [tokens]);
  return tokens;
}

/** Replaces a connect's Slack tokens (either one; the other kept), verified before they are saved. */
function openTokens(app: AppState, station: string, connect: Connect) {
  app.sheet = new SheetSpec(0.72, true, null, null, false, () => <TokensSheet app={app} station={station} connect={connect} />);
}

/** openTokens' sheet (a component, for its form and what it reads of the doing list). */
function TokensSheet({ app, station, connect }: { app: AppState; station: string; connect: Connect }) {
  const C = useC();
  const tokens = rememberTokens(app, station, connect.id);
  const busy = useDoing("connect.put", { station, id: connect.id });
  return (
    <>
      <SheetGrab />
      <SheetHead title="Slack token" />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, gap: 10 }}>
        <T size={12} color={C.muted}>{t("android-settings.tokens.note")}</T>
        <TokenFields tokens={tokens} masked={[connect.slack.appToken, connect.slack.botToken]} />
        <View style={{ flexDirection: "row", gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button label={t("android-settings.tokens.save")} primary busy={busy || tokens.checking} enabled={tokens.ready} onClick={() => {
            tokens.then(async () => {
              try {
                await app.api(station).putConnect(connect.id, { slack: { appToken: tokens.app, botToken: tokens.bot } });
                app.toast = t("android-settings.tokens.saved");
                app.sheet = null;
              } catch (e) { app.toast = messageOf(e); }
            });
          }} />
        </View>
      </ScrollView>
    </>
  );
}

/** A token's line: shown as dots, pasted into. */
export function SecretField({ value, onChange, placeholder }: { value: string; onChange: (value: string) => void; placeholder: string }) {
  const C = useC();
  return (
    <Smooth radius={12} stroke={{ width: 1, color: C.line }} style={{ alignSelf: "stretch", backgroundColor: C.surface, paddingHorizontal: 12, paddingVertical: 10 }}>
      {value === "" && (
        <T size={15} color={C.subtle} mono numberOfLines={1} style={{ position: "absolute", left: 12, right: 12, top: 10 }}>{placeholder}</T>
      )}
      <TextInput
        value={value}
        onChangeText={(it) => onChange(it.trim())}
        secureTextEntry
        autoCapitalize="none"
        autoCorrect={false}
        selectionColor={C.accent}
        cursorColor={C.accent}
        underlineColorAndroid="transparent"
        style={{ alignSelf: "stretch", color: C.ink, fontSize: 15, fontFamily: CODE_FONT, padding: 0, margin: 0, includeFontPadding: false }}
      />
    </Smooth>
  );
}

/**
 * The two tokens, checked by the button that goes on (`Tokens.then`), whose failures are said under them. For an
 * existing connect a blank field keeps the stored token. An app installed through Slack's OAuth (`install`) has its bot
 * token on the station already: only the app-level token is asked for.
 */
function TokenFields({ tokens, masked = null, install = null }: { tokens: Tokens; masked?: [string, string] | null; install?: string | null }) {
  const C = useC();
  useSyncExternalStore(tokens.subscribe, () => tokens.version);
  const verified = tokens.verified;
  return (
    <View style={{ gap: 8 }}>
      <T size={13} weight="600" color={C.ink}>App-Level Token</T>
      <SecretField value={tokens.app} onChange={(it) => { tokens.app = it; }} placeholder={masked?.[0] ? t("android-settings.tokens.kept", { token: masked[0] }) : "xapp-…"} />
      {install == null && (
        <>
          <T size={13} weight="600" color={C.ink}>Bot Token</T>
          <SecretField value={tokens.bot} onChange={(it) => { tokens.bot = it; }} placeholder={masked?.[1] ? t("android-settings.tokens.kept", { token: masked[1] }) : "xoxb-…"} />
        </>
      )}
      {verified != null && <T size={12} color={C.green}>{t("android-settings.tokens.verified", { team: verified.team, bot: verified.botName })}</T>}
      {tokens.errors.map((it, i) => <T key={i} size={13} color={C.red}>{it}</T>)}
    </View>
  );
}

// ── how it runs ────────────────────────────────────────────────────────

/** The model a connect runs, how hard it thinks and who runs it: picked like an agent's (History.tsx), saved for new sessions. */
export function ConnectRunScreen({ station, id }: { station: string; id: string }) {
  const C = useC();
  const app = theApp;
  const insets = useSafeAreaInsets();
  const [item, missing] = rememberConnect(station, id);
  const pickOf = `connect:${id}`;
  const picking = useTopic<PickView>({ topic: "pick", station, of: pickOf });
  const v = picking.value;
  const pick = (fill: Record<string, unknown>) => { app.act(t("android-settings.flow.choose"), () => app.api(station).pickSet(pickOf, fill)); };
  useEffect(() => { pick({ open: true }); }, [station, id]);
  const [list, setList] = useState<string | null>(null);
  useEffect(() => {
    if (list == null) return;
    const s = BackHandler.addEventListener("hardwareBackPress", () => { setList(null); return true; });
    return () => s.remove();
  }, [list]);
  const busy = useDoing("pick.save", { station, of: pickOf });
  const body = (): ReactNode => {
    if (item == null) return missing();
    if (v == null) return <Waiting shape={WaitShape.Cards} error={picking.error?.message} />;
    const connect = item.connect;
    const runtime = connect.bind.runtime;
    const models = v.options;
    const model = v.draft.model;
    const effort = v.draft.effort;
    const profile = v.draft.profile;
    const accounts = v.accounts;
    const efforts = v.efforts;
    const changed = v.changed;
    if (list === "model") return <ModelList models={models} runtime={runtime} picked={model ?? null} onPick={(m: string) => { pick({ model: m }); setList(null); }} />;
    if (list === "account") return <AccountList accounts={accounts} runtime={runtime} picked={profile ?? null} onPick={(p: string | null) => { pick({ profile: p }); setList(null); }} />;
    return (
      <>
        <ScrollView style={{ flex: 1, alignSelf: "stretch" }} contentContainerStyle={{ paddingHorizontal: 18 }}>
          {models.length === 0 && <T size={13} color={C.warn} style={{ paddingTop: 8 }}>{t("android-settings.run.noModels", { runtime: connect.runtimeText })}</T>}
          <GroupLabel text={t("android-settings.connect.model")} />
          <SettingRow onClick={() => setList("model")} leading={<MakerIcon maker={v.maker} runtime={runtime} size={18} />}>
            <T size={15} color={C.ink}>{v.modelText}</T>
          </SettingRow>
          <GroupLabel text={t("android-settings.run.effort")} />
          <EffortChips efforts={[null, ...efforts]} picked={effort ?? null} onPick={(e: string | null) => pick({ effort: e })} />
          <GroupLabel text={t("android-settings.run.account")} />
          <SettingRow onClick={() => setList("account")}>
            <T size={15} color={C.ink}>{v.accountText}</T>
            <T size={12} color={C.muted}>{v.accountNote}</T>
          </SettingRow>
          <T size={12} color={C.subtle} style={{ paddingVertical: 12 }}>{t("android-settings.run.note")}</T>
        </ScrollView>
        <View style={{ paddingBottom: insets.bottom }}>
          <View style={{ paddingHorizontal: 18, paddingVertical: 12 }}>
            <Smooth radius={16} style={{ minHeight: 52, backgroundColor: changed ? C.ink : C.chip }}>
              <Pressable
                disabled={!(!busy && !(changed && model == null))}
                android_ripple={{ color: withAlpha(C.ink, 0.1) }}
                onPress={() => {
                  // Back at once, not waiting on the station; failed, a toast says why.
                  app.pop();
                  if (!changed) return;
                  void (async () => {
                    try {
                      await app.api(station).pickSave(pickOf);
                      app.toast = t("android-settings.run.saved");
                    } catch (e) { app.toast = t("android-settings.run.saveFailed", { error: errorText(e as CoreError) }); }
                  })();
                }}
                style={{ minHeight: 52, paddingHorizontal: 16, paddingVertical: 12, alignItems: "center", justifyContent: "center" }}
              >
                <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                  {/* Solid while changed: its spinner in its words' colour. */}
                  <BusyIcon busy={busy} solid={changed ? C.bg : null} />
                  <T size={15} weight="600" color={changed ? C.bg : C.ink}>{v.saveText}</T>
                </View>
              </Pressable>
            </Smooth>
          </View>
        </View>
      </>
    );
  };
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back={list != null ? t("android-settings.run.title") : t("common.back")}
        onBack={() => { if (list != null) setList(null); else app.pop(); }}
        title={list === "model" ? t("android-settings.connect.pickModel") : list === "account" ? t("android-settings.run.pickAccount") : t("android-settings.run.title")}
      />
      {body()}
    </View>
  );
}

// ── a new connect ──────────────────────────────────────────────────────

/**
 * A new Slack connect, a step a screen: the Slack workspace to make its app in (a configuration token each, or a new
 * one); the app's name and description; making and installing it, then the app-level token; last, the model it runs and
 * how its conversations become sessions. Without a configuration token the app is made in Slack by hand and both
 * tokens are pasted.
 */
export function NewConnectScreen({ station }: { station: string }) {
  const app = theApp;
  // The Slack app to go on with, read once as the page opens and let go (Kotlin's remember { resume.also { setResume(null) } }).
  const [resume] = useState(() => app.resume(station));
  useEffect(() => { app.setResume(station, null); }, []);
  const flow = rememberConnectFlow(app, station, resume);
  const tokens = rememberTokens(app, station, null, flow.view?.made?.state ?? null, flow.form);
  const view = flow.view;
  if (view == null) return <NavBar back={t("common.cancel")} onBack={() => app.pop()} title={t("android-settings.flow.title")} />;
  // What Kotlin remembers after this point (the app's draft, the icon, the back handler) is its own component here:
  // hooks cannot come after the return above, and as in Compose they start again if the view is ever gone.
  return <NewConnectSteps key={flow.form} app={app} station={station} flow={flow} tokens={tokens} view={view} />;
}

/** NewConnectScreen once the flow's view is read. */
function NewConnectSteps({ app, station, flow, tokens, view }: { app: AppState; station: string; flow: ConnectFlow; tokens: Tokens; view: ConnectFlowView }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const api = app.api(station);
  const step = view.step;
  const teams = view.teams;
  const chosen = view.chosen;
  const models = view.pick?.options ?? [];
  const entry = view.pick?.valueOption;
  const rt = view.pick?.value.runtime ?? "claude";
  const made = view.made;
  const mode = view.mode;
  const mention = view.requireMention;
  const busy = flow.busy;
  const error = flow.error;
  const [draft] = useState(() => new AppDraft(
    { name: view.settings.name, displayName: view.settings.displayName, description: view.settings.description, longDescription: view.settings.longDescription, backgroundColor: view.settings.backgroundColor, groups: view.settings.groups },
    (settings) => flow.edit({ settings }),
  ));
  useSyncExternalStore(draft.subscribe, () => draft.version);
  // Bitmap decoding/rendering is platform work; the chosen image and its error are in the core draft.
  const [icon, setIcon] = useState<IconPick | null>(null);
  const iconError = view.iconError;
  const back = () => flow.go("back", () => app.pop());
  const backEnabled = step !== "team";
  useEffect(() => {
    if (!backEnabled) return;
    const s = BackHandler.addEventListener("hardwareBackPress", () => { back(); return true; });
    return () => s.remove();
  }, [backEnabled, flow]);
  const open = (url: string) => { void Linking.openURL(url); };
  const ripple = { color: withAlpha(C.ink, 0.1) };
  const link = (text: string, onClick: () => void, color: string = C.accent) => (
    <Pressable onPress={onClick} android_ripple={ripple} style={{ alignSelf: "flex-start" }}>
      <T size={14} color={color}>{text}</T>
    </Pressable>
  );
  // A connect runs a profile's model: with none on this station, that comes first.
  const noProfile = view.noProfile;
  const stepBody = (): ReactNode => {
    switch (step) {
      case "team":
        if (teams.length === 0) {
          return (
            <>
              <T size={14} color={C.muted}>{t("android-settings.flow.tokenNote", { app: APP_NAME })}</T>
              <View style={{ flexDirection: "row", justifyContent: "flex-end" }}><Button label={t("android-settings.slack.addToken")} primary onClick={() => flow.go("token")} /></View>
              {link(t("android-settings.flow.manualInSlack"), () => flow.go("manual"))}
            </>
          );
        }
        return (
          <>
            <T size={14} color={C.muted}>{t("android-settings.flow.whichTeam")}</T>
            <Smooth radius={16} style={{ backgroundColor: C.surface }}>
              {teams.map((team) => (
                <PickRow
                  key={team.teamId}
                  label={team.name}
                  sub={team.owner != null ? team.owner.user + (team.owner.teamDomain != null ? ` · ${team.owner.teamDomain}.slack.com` : "") : null}
                  checked={chosen?.teamId === team.teamId}
                  onClick={() => flow.edit({ team: team.teamId })}
                />
              ))}
            </Smooth>
            {link(t("android-settings.flow.addTeamToken"), () => flow.go("token"))}
            {chosen != null && link(t("android-settings.flow.removeToken", { name: chosen.name }), () => {
              confirm(app, t("android-settings.flow.removeTokenTitle", { name: chosen.name }), t("android-settings.flow.removeTokenText", { app: APP_NAME }), t("android-settings.members.remove"), true,
                t("android-settings.flow.removeTokenWhat"), () => flow.edit({ team: null }),
                async () => { await api.removeConfigToken(chosen.teamId); app.toast = t("android-settings.flow.tokenRemoved"); });
            }, C.muted)}
            {link(t("android-settings.flow.manual"), () => flow.go("manual"))}
            <View style={{ flexDirection: "row", justifyContent: "flex-end" }}><Button label={t("android-settings.flow.next")} primary enabled={chosen != null} onClick={() => flow.go("app")} /></View>
          </>
        );
      case "token":
        return <ConfigTokenSteps station={station} flow={flow} onSaved={() => {}} />;
      case "app":
        return (
          <>
            <FormLabel text={t("android-settings.slack.name")} />
            <Field value={draft.name} onChange={(it: string) => { draft.name = it; }} placeholder={APP_NAME} />
            <FormLabel text={t("android-settings.flow.description")} />
            <Field value={draft.description} onChange={(it: string) => { draft.description = it; }} placeholder={t("android-settings.slack.descriptionPlaceholder")} />
            <AppLook draft={draft} icon={icon} onIcon={(i, e) => { setIcon(i); flow.edit({ icon: i?.data ?? null, iconError: e ?? null }); }} fresh />
            {iconError != null && <T size={13} color={C.red}>{iconError}</T>}
            <T size={13} color={C.muted}>{t("android-settings.flow.permsNote")}</T>
            <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
              <Button label={t("android-settings.flow.make")} primary busy={busy} enabled={view.canMake} onClick={() => flow.act("make")} />
            </View>
          </>
        );
      case "install": {
        if (made == null) return <WaitLine text={t("android-settings.flow.readingApp")} />;
        const m = made;
        const install = m.install;
        return (
          <>
            {iconError != null && <T size={13} color={C.red}>{t("android-settings.flow.iconFailed", { error: iconError })}</T>}
            <Steps steps={[
              [
                install != null ? (m.installed ? t("android-settings.flow.installed", { team: m.installedTeam ?? m.team ?? t("android-settings.flow.team") }) : t("android-settings.flow.installOauth")) : t("android-settings.flow.installManual"),
                m.installed ? null : () => open(install ?? m.links.install),
              ],
              [t("android-settings.flow.appToken"), () => open(m.links.appToken)],
              [install != null ? t("android-settings.flow.pasteAppToken") : t("android-settings.flow.pasteTokens"), null],
            ]} />
            {install == null && link(t("android-settings.flow.oauthPage"), () => open(m.links.oauth))}
            <TokenFields tokens={tokens} install={m.state ?? null} />
            <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
              <Button label={t("android-settings.flow.next")} primary busy={busy} enabled={tokens.ready} onClick={() => flow.act("verify")} />
            </View>
          </>
        );
      }
      case "manual":
        return (
          <>
            <Steps steps={[
              [t("android-settings.flow.manual1", { app: APP_NAME }), () => { app.act(t("android-settings.flow.openSlack"), async () => { open(await api.createAppUrl(APP_NAME)); }); }],
              [t("android-settings.flow.manual2"), null],
              [t("android-settings.flow.manual3"), null],
              [t("android-settings.flow.pasteTokens"), null],
            ]} />
            <TokenFields tokens={tokens} />
            <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
              <Button label={t("android-settings.flow.next")} primary busy={busy} enabled={tokens.ready} onClick={() => flow.act("verify")} />
            </View>
          </>
        );
      default:
        return (
          <>
            <GroupLabel text={t("android-settings.connect.model")} />
            {models.length === 0 ? (
              <T size={13} color={C.warn}>{t("android-settings.flow.noModels")}</T>
            ) : (
              <Smooth radius={16} style={{ backgroundColor: C.surface }}>
                {models.map((m) => (
                  <PickRow
                    key={m.model}
                    label={m.name}
                    sub={m.runtimes.map((it) => RUNTIME_LABEL[it] ?? it).join(" · ")}
                    checked={entry?.model === m.model}
                    leading={<MakerIcon maker={m.maker} runtime={m.runtimes[0]} size={18} />}
                    onClick={() => flow.choose({ model: m.model })}
                  />
                ))}
              </Smooth>
            )}
            {entry != null && entry.runtimes.length > 1 && (
              <>
                <GroupLabel text={t("android-settings.flow.runtime")} />
                <View style={{ alignSelf: "stretch" }}>
                  <Seg options={entry.runtimes.map((it) => RUNTIME_LABEL[it] ?? it)} selected={Math.max(0, entry.runtimes.indexOf(rt))} onSelect={(it: number) => flow.choose({ runtime: entry.runtimes[it] })} height={36} fill />
                </View>
              </>
            )}
            <GroupLabel text={t("android-settings.mode.title")} />
            <ModeChoices mode={mode} requireMention={mention} onChange={(m, r) => flow.edit({ mode: m, requireMention: r })} />
            <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
              <Button label={t("android-settings.flow.create")} primary busy={busy} enabled={entry != null} onClick={() => {
                flow.act("create", (result) => {
                  app.toast = t("android-settings.flow.created");
                  app.replace({ kind: "Connect", station, connect: String(result["id"]) });
                });
              }} />
            </View>
          </>
        );
    }
  };
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back={view.back === "close" ? t("common.cancel") : t("android-settings.flow.previous")}
        onBack={back}
        title={t("android-settings.flow.title")}
        sub={<T size={11} color={C.muted}>{`${view.title} · ${view.number} / ${view.total}`}</T>}
      />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom + 30, paddingHorizontal: 18, paddingTop: 8, gap: 12 }}>
        {step === "team" && noProfile ? (
          <View style={{ alignSelf: "stretch", padding: 30, alignItems: "center", gap: 10 }}>
            <Illustration light="illus_no_profile" dark="illus_no_profile_dark" width={240} />
            <T size={17} weight="600" color={C.ink}>{t("android-settings.flow.noProfile")}</T>
            <T size={14} color={C.muted} align="center">{t("android-settings.flow.noProfileNote")}</T>
            <Button label={t("android-settings.flow.addProfile")} primary onClick={() => app.replace({ kind: "NewProfile", station })} />
          </View>
        ) : stepBody()}
        {error != null && <T size={13} color={C.red}>{error}</T>}
      </ScrollView>
    </View>
  );
}

/** The new-connect page, from the start or (`resume`) going on with a Slack app made before; a screen carries only its station. */
export function openNewConnect(app: AppState, station: string, resume: string | null = null) {
  app.setResume(station, resume);
  app.push({ kind: "NewConnect", station });
}

/**
 * A Slack app made on a station that no connect has taken yet (the viewer's): where it stands (to install, or only its
 * app-level token left), going on from there while the station is online, or dropping it (it stays in Slack).
 */
export function WaitingApp({ app, station, a, online }: { app: AppState; station: string; a: MadeSlackApp; online: boolean }) {
  const C = useC();
  // Being dropped (the sheet that asked gone): a spinner until the station has it, a red mark a moment if it failed.
  const dropping = useDoing("slack.dropApp", { station, appId: a.appId });
  const dropFailed = useDoingFailed("slack.dropApp", { station, appId: a.appId });
  const where = a.installed
    ? t("android-settings.waiting.installed", { team: a.installedTeam ?? a.team ?? t("android-settings.flow.team") })
    : a.install != null ? t("android-settings.waiting.notInstalled") : t("android-settings.waiting.noTokens");
  return (
    <ListRow onClick={online ? () => openWaitingMenu(app, station, a) : undefined}>
      <View style={{ width: 30, height: 30, alignItems: "center", justifyContent: "center" }}><SlackMark size={16} /></View>
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} color={C.ink} numberOfLines={1}>{a.name + (a.team != null ? ` · ${a.team}` : "")}</T>
        <T size={13} color={C.muted} numberOfLines={2} ellipsizeMode="clip">{where}</T>
      </View>
      <DoingMark running={dropping} failed={dropFailed} />
      {online ? (
        <Pressable onPress={() => openNewConnect(app, station, a.appId)} android_ripple={{ color: withAlpha(C.ink, 0.1) }}>
          <T size={14} color={C.accent}>{t("android-settings.waiting.continue")}</T>
        </Pressable>
      ) : (
        <T size={12} color={C.muted}>{t("android-settings.waiting.offline")}</T>
      )}
    </ListRow>
  );
}

/** Going on with a waiting app, or dropping it from still.fail (it stays in Slack). */
function openWaitingMenu(app: AppState, station: string, a: MadeSlackApp) {
  app.sheet = new SheetSpec(0.36, false, null, null, false, () => <WaitingMenuSheet app={app} station={station} a={a} />);
}

/** openWaitingMenu's sheet (a component, for the palette it reads). */
function WaitingMenuSheet({ app, station, a }: { app: AppState; station: string; a: MadeSlackApp }) {
  const C = useC();
  return (
    <>
      <SheetGrab />
      <SheetHead title={a.name} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <PickRow label={t("android-settings.waiting.continueRow")} onClick={() => openNewConnect(app, station, a.appId)} />
        <PickRow label={t("android-settings.waiting.remove")} color={C.red} onClick={() => {
          confirm(app, t("android-settings.station.removeTitle", { name: a.name }), t("android-settings.waiting.removeText", { app: APP_NAME }), t("android-settings.members.remove"), true,
            t("android-settings.waiting.removeWhat"), undefined,
            async () => { await app.api(station).dropSlackApp(a.appId); app.toast = t("android-settings.members.removed"); });
        }} />
      </ScrollView>
    </>
  );
}

/** Numbered steps, each a line; one with a link opens it. */
export function Steps({ steps }: { steps: [string, (() => void) | null][] }) {
  const C = useC();
  return (
    <View style={{ gap: 8 }}>
      {steps.map(([text, open], i) => (
        <View key={i} style={{ flexDirection: "row", gap: 8 }}>
          <T size={14} color={C.muted}>{`${i + 1}.`}</T>
          <View style={{ flex: 1, minWidth: 0, gap: 4 }}>
            <T size={14} color={C.ink}>{text}</T>
            {open != null && (
              <Pressable onPress={() => open()} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ alignSelf: "flex-start" }}>
                <T size={14} color={C.accent}>{t("android-settings.open")}</T>
              </Pressable>
            )}
          </View>
        </View>
      ))}
    </View>
  );
}
