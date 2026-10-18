// The workspace's stations: each with the buddy's face for its state and its
// load as rings; one station's page is the machine (its load, network,
// versions), with how many connects and profiles run on it (settings' lists
// have them, SettingsHome.tsx).
import { useContext, useState, type ReactNode } from "react";
import { Pressable, ScrollView, View, type StyleProp, type TextStyle, type ViewStyle } from "react-native";
import Animated from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Circle } from "react-native-svg";
import { useTopic } from "../../../../web/src/core/react.ts";
import type { AdbShareView, Host, Maker, MembershipsView, NetFigure, ScreensView, StationNet, StationView } from "../../../../web/src/core/shapes.ts";
import { app, SheetSpec, type AppState } from "../AppState";
import { APP_NAME } from "../build";
import type { WorkspaceEntry } from "../data/Accounts";
import type { ChatState } from "../data/Chats";
import { driveValue } from "../data/Drives";
import { Topics } from "../data/Topics";
import { t } from "../i18n";
import { LocalBarRoom } from "../Places";
import { stationName } from "../ui/ChatInk";
import { Drawing, Illustration } from "../ui/Drawing";
import { Icon, Icons } from "../ui/Icon";
import { AgentStateMark, Card, HostDetails, ListCard, ListRow, MakerIcon, MeterChips, MeterDials, ModelMark, NavBack, NavBar, NavButton, SectionHeader, StationMark, hasStationMark } from "../ui/Parts";
import { BarAction } from "../ui/Bar";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { dp, useC, withAlpha } from "../ui/Theme";
import { Spinner, WaitShape, Waiting, breathing, rememberBreath } from "../ui/Waiting";
import { RetryPill } from "./Connection";
import { PlacePage } from "./PlacePage";
import { FirstStation, isManager, managerOf, openAddStation, openStationMenu } from "./Settings";
import { GoRow } from "./SettingParts";
import { StationPermissionsSection } from "./StationPermissions";
import { Versions } from "./Versions";
import { Quiet } from "../ui/Quiet";

/** The buddy's face for a station: at work, idle, or asleep. */
export function Buddy({ s, size = 40 }: { s: StationView; size?: number }) {
  const C = useC();
  const dark = C.dark;
  const face = s.face === "offline" ? (dark ? "buddy_offline_dark" : "buddy_offline")
    : s.face === "working" ? (dark ? "buddy_working_dark" : "buddy_working")
    : (dark ? "buddy_idle_dark" : "buddy_idle");
  return <Drawing name={face} width={size} height={size} />;
}

/** Where a station this workspace joined is at home (docs/multi-workspace.md), as grey words before what is said of it; null for one at home here. */
export function joinedMark(s: StationView): string | null {
  if (s.joined !== true) return null;
  return s.home != null ? t("web-pages.stations.joinedFrom", { name: s.home }) : t("web-pages.stations.joinedElsewhere");
}

/** Back, at the top of a large-title page (settings' own); `trailing`, an action at its other end (a ＋). */
export function TopBack({ label, onBack, trailing }: { label: string; onBack: () => void; trailing?: ReactNode }) {
  const insets = useSafeAreaInsets();
  return (
    <View style={{ alignSelf: "stretch", paddingTop: insets.top + dp(6), paddingLeft: dp(10), paddingRight: dp(10), paddingBottom: dp(4), flexDirection: "row", alignItems: "center", justifyContent: "space-between" }}>
      <NavBack label={label} onClick={onBack} />
      {trailing}
    </View>
  );
}

/** The room a place's top page keeps at its foot for the bottom bar (none elsewhere). */
export function BarRoom() {
  return <View style={{ height: useContext(LocalBarRoom) }} />;
}

export function StationsScreen({ current }: { current: WorkspaceEntry }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const ws = current.workspace;
  const stations = useTopic<StationView[]>(Topics.stations(ws.id));
  const list = stations.value;
  const manager = managerOf(current);
  // Adding a station: the workspace's owners and admins.
  const add = list != null && manager === true
    ? new BarAction("add-station", t("android-misc.bar.action.stations"), Icons.Plus, () => openAddStation(app, current, list.map((s) => s.id)))
    : null;
  return (
    <PlacePage current={current} place="stations" primary={add} known={(list != null || stations.error != null) && manager != null}
      content={(top: number) => (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: top, paddingBottom: insets.bottom }}>
          {list != null && list.length === 0 ? (
            // No station yet: adding the first one is the page.
            <><FirstStation current={current} /><BarRoom /></>
          ) : (
            <>
              {list == null ? (
                <Waiting shape={WaitShape.Cards} text={t("common.readingStations")} error={stations.error?.message} />
              ) : list.map((s) => (
                <Card key={s.station} onClick={() => app.push({ kind: "Station", address: s.station })}>
                  <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
                    <Buddy s={s} />
                    <View style={{ flex: 1, minWidth: 0 }}>
                      {/* Line heights set: a line in Chinese is otherwise a little taller than one in Latin. */}
                      <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                        {hasStationMark(s.emoji, s.icon) && <StationMark emoji={s.emoji} icon={s.icon} size={16} tint={C.ink} />}
                        <T size={16} line={22} weight="700" color={C.ink} numberOfLines={1} style={{ flexShrink: 1 }}>{s.name}</T>
                      </View>
                      {/* A station this workspace joined: where it is at home first (the line is cut short at its end). */}
                      <T size={13} line={18} color={C.muted} numberOfLines={1}>{[joinedMark(s), s.summary.length > 0 ? s.summary : null].filter((x): x is string => x != null).join(" · ")}</T>
                    </View>
                    {s.reconnecting === true && <Reconnecting />}
                    <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
                  </View>
                  <StationBody s={s} />
                </Card>
              ))}
              <View style={{ height: 30 }} />
              <BarRoom />
            </>
          )}
        </ScrollView>
      )}
    />
  );
}

/** Laid out unseen while a station has no network to show, so that its card keeps the room (its path in Chinese, as tall as a real one). */
const noNet: StationNet = { path: "直连", rtt: { text: "0 ms", level: "ok" }, rttHistory: [], down: " ", up: " ", total: "" };

/**
 * Under a station's name in the list: what of its load runs low (as the web's cards: none while all is well) and its network, in the same room whatever state it is in —
 * online, offline, or not yet read — so no card grows, shrinks or pushes the ones below it as states change.
 * Offline, a small picture of it asleep and a line saying so are there; not read yet, grey bars where the figures go.
 */
function StationBody({ s }: { s: StationView }) {
  const C = useC();
  const host = s.online ? s.host : undefined;
  const net = s.online ? s.net : undefined;
  // How tall the room is, for the picture of it asleep (as tall as the room).
  const [height, setHeight] = useState(0);
  return (
    <View style={{ alignSelf: "stretch", paddingTop: 10 }}>
      <View onLayout={(e) => setHeight(e.nativeEvent.layout.height)}>
        {/* Reconnecting: the figures as last heard, faded. */}
        <View style={{ alignSelf: "stretch", opacity: s.reconnecting === true ? 0.45 : 1 }}>
          <View style={{ height: 20, opacity: host != null ? 1 : 0 }}><MeterChips meters={host?.meters ?? []} alerts /></View>
          <NetLine net={net ?? noNet} style={{ paddingTop: 10, opacity: net != null ? 1 : 0 }} />
        </View>
        {!s.online ? (
          <View style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0, flexDirection: "row", alignItems: "center", gap: 12 }}>
            {height > 0 && <Drawing name={C.dark ? "illus_station_offline_dark" : "illus_station_offline"} height={height} />}
            <T size={13} line={18} color={C.muted} numberOfLines={3} style={{ flexShrink: 1 }}>{t("android-settings.stations.silent", { app: APP_NAME })}</T>
          </View>
        ) : (
          <>
            {host == null && (
              <View style={{ position: "absolute", left: 0, top: 0, height: 20, flexDirection: "row", gap: 4 }}>
                {[46, 52, 50].map((w, i) => <Bar key={i} width={w} height={20} radius={6} />)}
              </View>
            )}
            {net == null && (
              <View style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0, paddingTop: 30, flexDirection: "row", alignItems: "center" }}>
                <View style={{ flex: 1, gap: 9 }}><Bar width={34} /><Bar width={96} /></View>
                <View style={{ gap: 9 }}><Bar width={132} /><Bar width={132} /></View>
              </View>
            )}
          </>
        )}
      </View>
    </View>
  );
}

/**
 * An online station's machine on its page, as the web's MachineDetails (web/src/cloud/StationCards.tsx): what it is,
 * what is left of it large, its network, the rest a row each, its agents' processes; in its room whether known yet or
 * not (grey bars until it is); reconnecting, as last heard, faded. `peek` (a chat's station card): what it is, what is
 * left of it in the allowance's boxes and its network, the rest on its page.
 */
function StationFigures({ s, peek = false }: { s: StationView; peek?: boolean }) {
  const host = s.host;
  const net = s.net;
  const running = s.overview?.processesText ? s.overview.processesText : null;
  const fill = { position: "absolute", left: 0, top: 0, right: 0, bottom: 0 } as const;
  return (
    <View style={{ opacity: s.reconnecting === true ? 0.45 : 1 }}>
      {/* What it is: on its page, under the page's title; in a chat's card, in the line above. */}
      {peek ? (
        <View style={{ paddingVertical: 4 }}>
          <View style={{ height: 20 }}>
            {host != null
              ? <MeterChips meters={host.meters} />
              : <View style={{ flexDirection: "row", gap: 4 }}>{[46, 52, 50].map((w, i) => <Bar key={i} width={w} height={20} radius={6} />)}</View>}
          </View>
        </View>
      ) : (
        // Not read yet: laid out unseen as when it is, grey bars over it, so nothing below moves as it comes.
        <View style={{ paddingTop: 4 }}>
          <View>
            <View style={{ opacity: host != null ? 1 : 0 }}><MeterDials meters={(host ?? unreadHost).meters} /></View>
            {host == null && <View style={[fill, { flexDirection: "row", gap: 16 }]}>{[0, 1, 2].map((i) => <Bar key={i} width={90} height={76} radius={6} />)}</View>}
          </View>
        </View>
      )}
      <View style={{ paddingTop: peek ? 6 : 14 }}>
        <View>
          <NetLine net={net ?? noNet} style={{ opacity: net != null ? 1 : 0 }} />
          {net == null && (
            <View style={[fill, { flexDirection: "row", alignItems: "center" }]}>
              <View style={{ flex: 1, gap: 9 }}><Bar width={34} /><Bar width={96} /></View>
              <View style={{ gap: 9 }}><Bar width={132} /><Bar width={132} /></View>
            </View>
          )}
        </View>
      </View>
      {!peek && (
        <>
          <View style={{ paddingTop: 16 }}>
            <View>
              <View style={{ opacity: host != null ? 1 : 0 }}><HostDetails details={(host ?? unreadHost).details} /></View>
              {host == null && <View style={[fill, { justifyContent: "space-evenly" }]}>{[0, 1, 2, 3].map((i) => <Bar key={i} width={180} />)}</View>}
            </View>
          </View>
          <Line text={running} bar={120} style={{ paddingTop: 8 }} />
        </>
      )}
    </View>
  );
}

/** What a machine not read yet is laid out as, unseen: its figures and rows as tall as a real one's (their words in Chinese). */
const unreadHost: Host = {
  hostname: "", os: "", arch: "", cpus: 0, cpuModel: "", load: 0, uptimeSec: 0,
  memory: { totalBytes: 0, usedBytes: 0 }, disk: { path: "", totalBytes: 0, freeBytes: 0 }, emberRssBytes: 0, checkedAt: 0,
  summary: "", line: "", facts: [], usage: "", emberText: "", identity: "",
  meters: [0, 1, 2].map((i) => ({ label: `${i}`, short: "", percent: 0, left: 0, level: "ok", value: "", remaining: "", big: "0", unit: "%", title: "内存剩", total: "共 0 GB" })),
  details: [0, 1, 2, 3].map(() => ({ label: "主机名", value: "直连" })),
};

/** A grey line of text, one line however long; a grey bar `bar` wide in its room while it is not known. */
function Line({ text, bar, style }: { text: string | null; bar: number; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  return (
    <View style={style}>
      <View style={{ justifyContent: "center" }}>
        {/* Its room, as tall as a line in Chinese (a line in Latin is a little shorter), whatever it says. */}
        <T size={13} line={18} numberOfLines={1} ellipsizeMode="clip" style={{ opacity: 0 }}>直连</T>
        <View style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0, justifyContent: "center", alignItems: "flex-start" }}>
          {text != null ? <T size={13} line={18} color={C.muted} numberOfLines={1}>{text}</T> : <Bar width={bar} />}
        </View>
      </View>
    </View>
  );
}

/** The station is up but not reached just now: what shows of it is from before. */
function Reconnecting() {
  const C = useC();
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 5 }}>
      <Spinner inline />
      <T size={12} line={16} color={C.muted} numberOfLines={1} ellipsizeMode="clip">{t("common.reconnecting")}</T>
    </View>
  );
}

/** A grey bar where a figure would be, not known now: breathing as every wait's shapes (Waiting.tsx). */
function Bar({ width, height = 10, radius = 5 }: { width: number; height?: number; radius?: number }) {
  const C = useC();
  const breath = rememberBreath();
  return (
    <Quiet style={{ width, height }}>
      <Animated.View style={[{ width, height }, breathing(breath)]}>
        <Smooth radius={radius} style={{ width, height, backgroundColor: C.bubble }} />
      </Animated.View>
    </Quiet>
  );
}

export function StationScreen({ current, address }: { current: WorkspaceEntry; address: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const stations = useTopic<StationView[]>(Topics.stations(current.workspace.id));
  const s = stations.value?.find((x) => x.station === address);
  const shared = useTopic<AdbShareView>(Topics.adbShare);
  const manager = isManager(current);
  const bar = (
    <NavBar
      back="Station"
      onBack={() => app.pop()}
      title={s?.name ?? stationName(address)}
      sub={s != null ? (
        // As tall either way: the title does not move as the station comes and goes.
        <View style={{ height: 16, justifyContent: "center" }}>
          {s.reconnecting === true ? <Reconnecting /> : (
            <T size={11} color={C.muted} numberOfLines={1}>
              {[joinedMark(s), (s.host?.identity ?? s.line) || null].filter((x): x is string => x != null).join(" · ")}
            </T>
          )}
        </View>
      ) : undefined}
      trailing={s != null && manager ? <NavButton icon={Icons.More} onClick={() => openStationMenu(app, current, s)} /> : undefined}
    />
  );
  if (s == null) return (
    <View style={{ flex: 1 }}>
      {bar}
      <Waiting shape={WaitShape.Cards} error={stations.error?.message} />
    </View>
  );
  const overview = s.overview;
  const drive = overview?.drive;
  return (
    <View style={{ flex: 1 }}>
      {bar}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: 12, paddingBottom: insets.bottom }}>
        {/* Every part keeps its room as what it shows comes and goes (not read yet: grey bars); only being online or
            offline changes what the page is. */}
        {s.online ? <Card><StationFigures s={s} /></Card> : (
          <Card>
            <View style={{ alignSelf: "stretch", alignItems: "center", gap: 4 }}>
              <Illustration light="illus_station_offline" dark="illus_station_offline_dark" width={220} />
              <T size={13} color={C.muted} align="center">{t("android-settings.stations.offline", { app: APP_NAME })}</T>
              <RetryPill style={{ marginTop: 6 }} retrying={s.link.retrying === true} />
            </View>
          </Card>
        )}
        {/* What runs on it is in settings' lists, every station's together; here, how much of it there is (once read). */}
        <SectionHeader title={t("android-settings.stations.onIt")} start={24} />
        <ListCard>
          <GoRow title={t("android-settings.connects.title")} value={overview != null ? t("android-settings.count", { n: overview.connects.length }) : undefined} onClick={() => app.push({ kind: "Connects", station: address })} />
          <GoRow title="Profile" value={overview != null ? t("android-settings.count", { n: overview.profiles.length }) : undefined} onClick={() => app.push({ kind: "Profiles", station: address })} />
          <GoRow title={t("android-settings.memory")} onClick={() => app.push({ kind: "Memory", station: address })} />
          {/* This phone's adb, lent to its agents (AdbShare.tsx). */}
          <GoRow title={t("android-misc.adb.title")} value={shared.value != null && shared.value.sharing && shared.value.station === address ? t("android-misc.adb.sharing") : undefined} onClick={() => app.push({ kind: "AdbShare", address })} />
          {/* The folders it lends its members (docs/drive.md); none offered by a station from before the drive. */}
          {drive != null && <GoRow title={t("android-misc.drive.title")} value={driveValue(drive.roots)} onClick={() => app.push({ kind: "Drive", station: address, root: null, path: "" })} />}
        </ListCard>
        <StationScreens address={address} />
        {/* What macOS lets a Mac station's helper do (StationPermissions.tsx); nothing from another or an older one. */}
        {s.online && overview?.permissions != null && <StationPermissionsSection address={address} name={s.name} p={overview.permissions} />}
        {manager && s.joined !== true && <StationWorkspaces address={address} />}
        {/* Its updates are its home workspace's managers' (docs/multi-workspace.md). */}
        {s.online && overview != null && <Versions station={address} updates={overview.updates} manager={manager && s.joined !== true} beta={s.betaOffered === true} />}
        <View style={{ height: 30 }} />
      </ScrollView>
    </View>
  );
}

/**
 * The station's screens a person can see and drive (docs/remote-screens.md: its display, its browser's tabs), a row
 * each opening the viewer (remote/ScreenActivity.kt); a station from before them, or none to show, says why in a quiet
 * row. Nothing while the station has not said which it has.
 */
function StationScreens({ address }: { address: string }) {
  const C = useC();
  const topic = useTopic<ScreensView>(Topics.screens(address));
  const view = topic.value;
  if (view == null) return null;
  const why = view.note ?? (view.outdated ? t("android-misc.screen.outdatedRow") : null);
  if (view.screens.length === 0 && why == null) return null;
  return (
    <>
      <SectionHeader title={t("android-misc.screen.section")} start={24} />
      <ListCard>
        {view.screens.map((screen) => (
          // NATIVE: the remote screen viewer (remote/ScreenActivity.kt); AppState's openScreen hands a screen to it.
          <ListRow key={screen.id} onClick={() => app.openScreen(address, screen.id, screen.title)}>
            <Icon icon={screen.kind === "browser" ? Icons.Web : Icons.Monitor} size={18} color={C.muted} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} line={20} color={C.ink} numberOfLines={1}>{screen.title}</T>
              {/* A grant missing (its line says which): the one thing on the row in colour. */}
              <T size={13} line={18} color={screen.access != null ? C.warn : C.muted} numberOfLines={2}>{screen.line}</T>
            </View>
            <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
          </ListRow>
        ))}
        {view.screens.length === 0 && why != null && (
          <ListRow><T size={14} line={20} color={C.muted} style={{ flex: 1, minWidth: 0 }}>{why}</T></ListRow>
        )}
      </ListCard>
    </>
  );
}

/**
 * The workspaces a station is in, a row each (its name, and what it has of the machine: 主 workspace, or the folders
 * opened to it), on its page in its home workspace for that one's owners and admins; only once it is in more than one
 * (as the narrow web's).
 */
function StationWorkspaces({ address }: { address: string }) {
  const C = useC();
  const topic = useTopic<MembershipsView>(Topics.memberships(address));
  const view = topic.value;
  if (view == null) return null;
  if (!view.manages || view.workspaces.length < 2) return null;
  return (
    <>
      <SectionHeader title="Workspace" start={24} />
      <ListCard>
        {view.workspaces.map((w) => (
          <ListRow key={w.workspace}>
            <T size={15} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{w.name}</T>
            <T size={14} color={C.muted} numberOfLines={1} style={{ maxWidth: 220 }}>{w.line}</T>
          </ListRow>
        ))}
      </ListCard>
    </>
  );
}

/**
 * This device's connection to a station: how it goes (and packets lost, when some were) over its round trip on the
 * left; on the right, ↑ over ↓, the speed each way and what went that way since it opened, each in a column of its own.
 * Grey, but for what the core says is off. Every line is one line, the figures in fixed-width digits with room kept for
 * them: nothing wraps or moves as the figures change.
 */
export function NetLine({ net, style }: { net: StationNet; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const tone = (f: NetFigure) => (f.level === "red" ? C.red : f.level === "amber" ? C.warn : C.ink);
  // The figures' own style, as Kotlin's TextStyle(13.sp, Medium, "tnum"): its line the font's own, not the page's 1.4.
  const figure: TextStyle = { fontWeight: "500", fontVariant: ["tabular-nums"], lineHeight: undefined };
  const rows: [string, string, string | undefined][] = [["↑", net.up, net.upTotal], ["↓", net.down, net.downTotal]];
  return (
    <View style={[{ flexDirection: "row", alignItems: "center", gap: 10 }, style]}>
      <View style={{ flex: 1, minWidth: 0, gap: 2 }}>
        <View style={{ flexDirection: "row", alignItems: "baseline", gap: 8 }}>
          <T size={13} color={C.muted} numberOfLines={1} style={{ flexShrink: 1 }}>{net.path}</T>
          {net.loss != null && <T size={13} color={tone(net.loss)} numberOfLines={1} style={[figure, { flexShrink: 1, minWidth: 0 }]}>{net.loss.text}</T>}
        </View>
        {net.rtt != null && (
          <View style={{ flexDirection: "row", alignItems: "baseline" }}>
            <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="clip">{t("android-settings.stations.rtt")}</T>
            <T size={13} color={tone(net.rtt)} numberOfLines={1} ellipsizeMode="clip" style={figure}>{net.rtt.text}</T>
          </View>
        )}
      </View>
      <View style={{ gap: 2 }}>
        {rows.map(([arrow, rate, total]) => (
          <View key={arrow} style={{ flexDirection: "row", alignItems: "center" }}>
            <T size={13} color={C.muted}>{arrow}</T>
            <T size={13} color={C.ink} numberOfLines={1} ellipsizeMode="clip" style={[figure, { marginLeft: 5, width: 68 }]}>{rate}</T>
            {total != null && <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="clip" style={[figure, { fontWeight: "400", minWidth: 60 }]}>{t("android-settings.stations.total", { total })}</T>}
          </View>
        ))}
      </View>
    </View>
  );
}

/** A check's tone as a presence dot: green up, red failing, the rest on its way or unknown. */
export function toneDot(tone: string): string {
  switch (tone) {
    case "green": return "online";
    case "red": return "error";
    case "neutral": return "offline";
    default: return "busy";
  }
}

/**
 * The station a chat runs on, in its bar: its icon and name, short; a tap opens
 * its card (the web's is a hover card over the same tag: web/src/cloud/StationCards.tsx StationPeek).
 */
export function ChatStationChip({ address }: { address: string }) {
  const stations = useTopic<StationView[]>(Topics.stations(address.split("/")[0]!));
  const list = stations.value;
  if (list == null) return null;
  const s = list.find((x) => x.station === address);
  if (s == null) return null;
  return <StationTag name={s.name} emoji={s.emoji} icon={s.icon} onClick={() => openStationPeek(app, address)} via={stationVia(s)} />;
}

/**
 * How this device reaches a station, as a dot where a chat names it (web StationLink.tsx): straight there (green),
 * through a relay (amber), away (red), else coming back or a way still being chosen (a grey ring); null before it is known.
 */
export function stationVia(s: StationView): string | null {
  if (!s.online) return "offline";
  if (s.reconnecting === true) return "waiting";
  switch (s.net?.via) {
    case "direct": return "direct";
    case "relay": return "relay";
    case "choosing": return "waiting";
    default: return null;
  }
}

/** The dot of [stationVia], `size` across with a ring of the ground round it when [ring] is given (on a tile's corner). */
export function StationViaDot({ via, size, ring = 0, style }: { via: string; size: number; ring?: number; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const r = size / 2;
  const inner = r - ring;
  const w = 1.5;
  return (
    <View style={[{ width: size, height: size }, style]}>
      <Svg width={size} height={size}>
        {ring > 0 && <Circle cx={r} cy={r} r={r} fill={C.bg} />}
        {via === "direct" ? <Circle cx={r} cy={r} r={inner} fill={C.green} />
          : via === "relay" ? <Circle cx={r} cy={r} r={inner} fill={C.warn} />
          : via === "offline" ? <Circle cx={r} cy={r} r={inner} fill={C.red} />
          : <Circle cx={r} cy={r} r={inner - w / 2} fill="none" stroke={C.muted} strokeWidth={w} />}
      </Svg>
    </View>
  );
}

/**
 * A chat's first agent in its bar with the station it runs on, one tile (web ui.tsx AgentMark with children, as the phone
 * web's bar): the maker's square, then the station's icon, or its name where it has none; the agent's state on the
 * maker's corner, how the station is reached on the tile's (StationViaDot). One tap for all of it (halves
 * this small are not told apart under a finger): the agent's card, which leads on to the station's. Until the station
 * is known, the agent's mark alone.
 */
export function AgentStationMark({ address, who, maker, runtime, state, onAgent }: { address: string; who: string; maker: Maker | null | undefined; runtime: string; state: ChatState | null | undefined; onAgent: () => void }) {
  const C = useC();
  const stations = useTopic<StationView[]>(Topics.stations(address.split("/")[0]!));
  const s = stations.value?.find((x) => x.station === address);
  // Not clipped: the state's dot sits over the tile's corner, partly outside it.
  if (s == null) {
    return <Pressable onPress={onAgent}><ModelMark maker={maker} runtime={runtime} size={22} state={state} listMark /></Pressable>;
  }
  const via = stationVia(s);
  return (
    <View accessible accessibilityLabel={`${who} · ${s.name}`}>
      <Smooth radius={6} stroke={{ width: 1, color: C.line }} style={{ height: 22, backgroundColor: C.surface }}>
        <Pressable onPress={onAgent} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ height: 22, flexDirection: "row", alignItems: "center" }}>
          <View style={{ width: 22, height: 22, alignItems: "center", justifyContent: "center" }}><MakerIcon maker={maker} runtime={runtime} size={13.2} /></View>
          <View style={{ maxWidth: 96, paddingHorizontal: 5, alignItems: "center", justifyContent: "center" }}>
            {hasStationMark(s.emoji, s.icon)
              ? <StationMark emoji={s.emoji} icon={s.icon} size={13} tint={C.muted} />
              : <T size={12} line={14} color={C.muted} numberOfLines={1}>{s.name}</T>}
          </View>
        </Pressable>
      </Smooth>
      {/* The agent's state on the maker's corner; the station's on the tile's, how it is reached. */}
      {state != null && <View pointerEvents="none" style={{ position: "absolute", left: 13, bottom: -3 }}><AgentStateMark state={state} around={C.bg} /></View>}
      {via != null && <StationViaDot via={via} size={10} ring={2} style={{ position: "absolute", right: -3, bottom: -3 }} />}
    </View>
  );
}

/** A station named in a small outlined tag, its icon before its name (in a chat's bar, how it is reached as a dot before both): in a chat's bar (ChatStationChip) and the composer's chats from elsewhere. `onClick`: Kotlin's clickable modifier. */
export function StationTag({ name, emoji, icon, onClick, via = null }: { name: string; emoji: string | null | undefined; icon: string | null | undefined; onClick?: () => void; via?: string | null }) {
  const C = useC();
  return (
    <View style={{ maxWidth: 104, borderRadius: 999, overflow: "hidden", borderWidth: 1, borderColor: C.line }}>
      <Pressable
        disabled={onClick == null}
        onPress={onClick}
        accessibilityLabel={name}
        android_ripple={onClick != null ? { color: withAlpha(C.ink, 0.1) } : undefined}
        style={{ paddingHorizontal: 8, paddingVertical: 2, flexDirection: "row", alignItems: "center", gap: 4 }}
      >
        {via != null && <StationViaDot via={via} size={7} />}
        {hasStationMark(emoji, icon) && <StationMark emoji={emoji} icon={icon} size={12} tint={C.muted} />}
        <T size={12} line={16} color={C.muted} numberOfLines={1} style={{ flexShrink: 1 }}>{name}</T>
      </Pressable>
    </View>
  );
}

/** A station's card, from a chat's bar: whether it is up and what its agents do, its machine and network, and its page. */
export function openStationPeek(app: AppState, address: string) {
  app.sheet = new SheetSpec(0.5, false, null, null, false, () => <StationPeek app={app} address={address} />);
}

function StationPeek({ app, address }: { app: AppState; address: string }) {
  const C = useC();
  const stations = useTopic<StationView[]>(Topics.stations(address.split("/")[0]!));
  const s = stations.value?.find((x) => x.station === address);
  const drive = s?.overview?.drive;
  return (
    <>
      <SheetGrab />
      <SheetHead title={s?.name ?? stationName(address)} lead={s != null && hasStationMark(s.emoji, s.icon) ? <StationMark emoji={s.emoji} icon={s.icon} size={17} tint={C.ink} /> : undefined} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24, gap: 10 }}>
        {s != null && (
          <View style={{ paddingHorizontal: 20, gap: 10 }}>
            <T size={13} line={18} color={C.muted}>{s.summary}</T>
            {/* What its agents' processes are is on its page, a tap away. */}
            {s.online ? <StationFigures s={s} peek /> : <T size={13} line={18} color={C.muted}>{t("android-settings.stations.offline", { app: APP_NAME })}</T>}
          </View>
        )}
        <ListCard>
          {/* Its files (docs/drive.md), where it has a drive: a way there from where it is named, as the wide screen's card has. */}
          {drive != null && <GoRow title={t("android-misc.drive.title")} value={driveValue(drive.roots)} onClick={() => { app.sheet = null; app.push({ kind: "Drive", station: address, root: null, path: "" }); }} />}
          <GoRow title={t("android-chat.station.details")} onClick={() => { app.sheet = null; app.push({ kind: "Station", address }); }} />
        </ListCard>
      </ScrollView>
    </>
  );
}
