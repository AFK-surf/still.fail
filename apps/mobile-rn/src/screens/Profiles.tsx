// Profiles (as the narrow web's web/src/mobile/Profiles.tsx, from the desktop's pages/Accounts.tsx): every station's in
// one list, a profile's page
// (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its key or
// variables; renaming, checking and deleting under "…"), and a new one.
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { BackHandler, Linking, Pressable, ScrollView, TextInput, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { CoreError } from "../../../../web/src/core/client.ts";
import { core, useTopic } from "../../../../web/src/core/react.ts";
import type { LoginJob, MachineLogin, MembershipsView, Overview, Profile, ProfileFlowView, ProfilesView, Quota, ShareStation, StationView } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import { app, SheetSpec, type AppState } from "../AppState";
import { APP_NAME } from "../build";
import type { WorkspaceEntry } from "../data/Accounts";
import { errorText } from "../data/Calls";
import { ACCESS_LABEL, KEYED, RUNTIME_LABEL } from "../data/Words";
import { t } from "../i18n";
import { BarAction } from "../ui/Bar";
import { Button, DoingMark, Field, PickRow } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { Card, ListCard, ListRow, NavBar, NavButton, ProviderMark, QuotaDials, QuotaRings, SectionHeader, SlackMark } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { CODE_FONT, useC, withAlpha } from "../ui/Theme";
import { Spinner, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { Action, useAction } from "./Action";
import { PresenceDot, SecretField, Switch } from "./Connects";
import { PlaceEmpty } from "./PlaceRows";
import { PlacePage } from "./PlacePage";
import { ask, CommandBox, confirm } from "./Settings";
import { BarRoom, toneDot } from "./Stations";

const SIGNING_IN: ReadonlySet<string> = new Set(["starting", "needs_code", "needs_approval", "verifying"]);

/** A check's tone as a colour (the core's: accent | green | blue | red | neutral). A hook (the palette in use). */
export function toneColor(tone: string): string {
  const C = useC();
  switch (tone) {
    case "green": return C.green;
    case "red": return C.red;
    case "blue": return C.blue;
    case "accent": return C.accent;
    default: return C.muted;
  }
}

/** A state as the pages say it: a small dot in its colour, then its words. */
export function StateDot({ color, size = 7 }: { color: string; size?: number }) {
  return <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: color }} />;
}

/** Why an allowance could not be read (an account its provider refuses, a sign-in gone stale), in the provider's words. */
export function quotaTrouble(quota: Quota | null | undefined): string | null {
  if (!quota || !(quota.state === "blocked" || quota.state === "unavailable")) return null;
  const detail = quota.detail;
  return detail == null || detail.trim() === "" ? null : detail;
}

/** The runtime a machine login is of, by name. */
const MACHINE_RUNTIME = RUNTIME_LABEL;

// ── small helpers for what Kotlin's collections do ──

/** Kotlin's groupBy: the groups in the order their first member came. */
function groupBy<X>(xs: readonly X[], by: (x: X) => string | null | undefined): X[][] {
  const groups = new Map<string | null | undefined, X[]>();
  for (const x of xs) {
    const k = by(x);
    const g = groups.get(k);
    if (g) g.push(x);
    else groups.set(k, [x]);
  }
  return [...groups.values()];
}

/** Kotlin's distinct. */
const distinct = <X,>(xs: readonly X[]): X[] => [...new Set(xs)];

/** Kotlin's `list - element`: the first one of it taken out. */
function minus<X>(xs: readonly X[], x: X): X[] {
  const i = xs.indexOf(x);
  return i < 0 ? [...xs] : [...xs.slice(0, i), ...xs.slice(i + 1)];
}

/** What a failure says (a CoreException's message). */
const message = (e: unknown) => (e instanceof Error ? e.message : String(e));

/** What a failure says to people (Calls.kt errorText for the core's; the rest as they say it). */
const said = (e: unknown) => (e instanceof CoreError ? errorText(e) : message(e));

/** Compose's Column leaves a child its own width (a button, a mark): here it is held to it, not stretched. */
function Start({ children }: { children: ReactNode }) {
  return <View style={{ alignSelf: "flex-start" }}>{children}</View>;
}

/**
 * Every station's profiles on one page, from settings (SettingsHome.kt), as the narrow web's ProfilesScreen: each station
 * under its name, what can be added there (a profile, the machine's own logins) with it; one offline says so.
 */
export function ProfilesScreen({ current, only = null }: { current: WorkspaceEntry; only?: string | null }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const topic = useTopic<StationView[]>({ topic: "stations", scope: current.workspace.id });
  // From a station's page: that station's only, back to it.
  const all = topic.value;
  const stations = all == null ? null : only == null ? all : all.filter((it) => it.station === only);
  const one = only != null ? (stations?.[0] ?? null) : null;
  const online = (stations ?? []).filter((it) => it.online);
  // A profile is added on a station online (the only one, without asking).
  const add = online.length > 0
    ? new BarAction("add-profile", t("android-misc.bar.action.profiles"), Icons.Plus, () => {
      if (online.length === 1) app.push({ kind: "NewProfile", station: online[0]!.station });
      else openPickStation(app, t("android-settings.profile.add"), online, (it) => app.push({ kind: "NewProfile", station: it.station }));
    })
    : null;
  // A station's own (from its page): back to it.
  return (
    <PlacePage current={current} place="profiles" primary={add} known={topic.value != null || topic.error != null} back={one?.name ?? t("android-settings.title")}
      content={(top: number) => (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom, paddingTop: top }}>
          {/* The workspace's: one list, each shared profile once (the core's `profiles`), waiting on its own; a station's
              own: as before, its first read the page's. */}
          {only != null && stations == null
            ? <Waiting shape={WaitShape.Rows} count={3} text={t("common.readingStations")} error={topic.error?.message} />
            : one == null ? <WorkspaceList scope={current.workspace.id} /> : null}
          {stations == null
            ? (only == null && topic.error != null ? <View style={{ padding: 20 }}><WaitLine text={topic.error.message} error /></View> : null)
            : one == null
              ? online.map((s) => (s.overview != null ? <MachineLoginOffers key={s.station} station={s.station} overview={s.overview} /> : null))
              : stations.map((s) => {
                const overview = s.overview;
                return (
                  <View key={s.station}>
                    {one == null && <SectionHeader title={s.online ? s.name : t("android-settings.connects.offline", { name: s.name })} start={24} />}
                    {overview == null || overview.profiles.length === 0
                      ? (
                        <ListCard>
                          {overview == null
                            ? <ListRow>{s.online ? <WaitLine text={t("common.reading")} /> : <T size={15} color={C.muted}>{t("android-settings.profiles.stationOffline")}</T>}</ListRow>
                            : <ListRow><T size={15} color={C.muted}>{t("android-settings.profiles.empty")}</T></ListRow>}
                        </ListCard>
                      )
                      // A section each kind of account, as the workspace's list (the core lists them by kind, in order).
                      : groupBy(overview.profiles, (it) => it.group).map((g) => (
                        <View key={g[0]!.group ?? ""}>
                          <SectionHeader title={g[0]!.groupTitle ?? ""} start={24} />
                          <ListCard>{g.map((it) => <ProfileRow key={it.id} station={s.station} p={it} />)}</ListCard>
                        </View>
                      ))}
                    {/* The machine's own logins not used yet, each offered as a profile. */}
                    {s.online && overview != null && <MachineLoginOffers station={s.station} overview={overview} />}
                  </View>
                );
              })}
          <View style={{ height: 30 }} />
          <BarRoom />
        </ScrollView>
      )}
    />
  );
}

/** The workspace's profiles, a section each kind of account: a shared one once, where it is under it; one whose
 * subscription's station is away dimmed, said why (as the narrow web's WorkspaceList). */
function WorkspaceList({ scope }: { scope: string }) {
  const C = useC();
  const topic = useTopic<ProfilesView>({ topic: "profiles", scope });
  const view = topic.value;
  if (view == null) return <Waiting shape={WaitShape.Rows} count={3} text={t("common.reading")} error={topic.error?.message} />;
  // None to show yet: the stations not read yet, or those that could not be.
  if (view.items.length === 0 && (view.wait.reading || view.wait.failing.length > 0)) return <Waiting shape={WaitShape.Rows} count={3} note={view.wait} />;
  return (
    <>
      {view.items.length === 0 && (
        <>
          <ListCard><ListRow><T size={15} color={C.muted}>{t("android-settings.profiles.empty")}</T></ListRow></ListCard>
          {/* What a profile is, said while there is none (the page has no note at its top). */}
          <PlaceEmpty text={t("android-settings.profiles.note")} />
        </>
      )}
      {/* A section each kind of account (the core lists them by kind, in order). */}
      {groupBy(view.items, (it) => it.group).map((g) => (
        <View key={g[0]!.group}>
          <SectionHeader title={g[0]!.groupTitle} start={24} />
          <ListCard>
            {g.map((e) => {
              const p = e.profile;
              return (
                <ListRow key={e.key} onClick={() => app.push((e.members ?? []).filter((it) => it.role !== "user").length > 1 ? { kind: "ProfileAccount", key: e.key } : { kind: "Profile", address: e.station, profile: p.id })}>
                  <View style={{ flex: 1, minWidth: 0, opacity: e.usable ? 1 : 0.55 }}>
                    <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                      <PresenceDot state={e.usable ? toneDot(p.checkTone) : "error"} />
                      <T size={15} color={C.ink} numberOfLines={1} style={{ flexShrink: 1 }}>{p.name}</T>
                    </View>
                    <T size={13} color={C.muted} numberOfLines={1}>
                      {!e.usable
                        ? t("web-pages.settings.profiles.hostAway", { station: e.hostName })
                        : e.where !== "" ? e.where : [p.checkText, (p.usesText ? p.usesText : null) ?? ACCESS_LABEL[p.access.kind] ?? p.access.kind].filter((x) => x != null).join(" · ")}
                    </T>
                  </View>
                  {e.usable && <QuotaRings quota={p.quota} />}
                  <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
                </ListRow>
              );
            })}
          </ListCard>
        </View>
      ))}
      {/* Some shown, a station's still to come. */}
      {view.wait.reading && <ListCard><ListRow><WaitLine text={view.wait.text ?? t("common.reading")} /></ListRow></ListCard>}
    </>
  );
}

/** An account on several stations (as the narrow web's ProfileAccountScreen): what they have in common, then each
 * station's part, each leading to its page there. `accountKey` is Kotlin's `key` (React keeps `key` for itself). */
export function ProfileAccountScreen({ current, accountKey }: { current: WorkspaceEntry; accountKey: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const topic = useTopic<ProfilesView>({ topic: "profiles", scope: current.workspace.id });
  const e = topic.value?.items?.find((it) => it.key === accountKey);
  if (e == null) {
    return (
      <View style={{ flex: 1 }}>
        <NavBar back="Profile" onBack={() => app.pop()} title="Profile" />
        {/* Read, and not among them (gone since): said, not waited on. */}
        {topic.value != null
          ? <PlaceEmpty text={t("android-settings.profile.none")} />
          : <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={topic.error?.message} />}
      </View>
    );
  }
  const p = e.profile;
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back="Profile"
        onBack={() => app.pop()}
        title={p.name}
        sub={<T size={11} color={C.muted} numberOfLines={1} ellipsizeMode="clip">{[p.email, p.machine === true ? t("android-settings.profile.machine") : p.providerName ?? ACCESS_LABEL[p.access.kind] ?? p.access.kind].filter((x) => x != null).join(" · ")}</T>}
      />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom, paddingTop: 4 }}>
        <View style={{ height: 12 }} />
        <ListCard>
          <ListRow>
            <View style={{ flex: 1, minWidth: 0 }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                <PresenceDot state={toneDot(p.checkTone)} />
                <T size={15} color={C.ink} style={{ flexShrink: 1 }}>{p.checkText}</T>
              </View>
              <T size={13} color={C.muted}>{p.check?.detail ?? t("android-settings.profile.notChecked")}</T>
            </View>
          </ListRow>
        </ListCard>
        <QuotaSection station={e.station} p={p} />
        <SectionHeader title={t("web-pages.profiles.account.each")} start={24} />
        <ListCard>
          {/* The stations it is signed in on: one borrowing it has nothing of its own to set. */}
          {(e.members ?? []).filter((it) => it.role !== "user").map((m) => (
            <ListRow key={m.station} onClick={() => app.push({ kind: "Profile", address: m.station, profile: m.profileId })}>
              <View style={{ flex: 1, minWidth: 0 }}>
                <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                  <PresenceDot state={!m.online ? "offline" : !m.usable ? "error" : toneDot(m.checkTone)} />
                  <T size={15} color={C.ink} style={{ flexShrink: 1 }}>{m.stationName}</T>
                </View>
                <T size={13} color={C.muted}>{m.online ? m.about : t("android-settings.profiles.stationOffline")}</T>
              </View>
              <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
            </ListRow>
          ))}
        </ListCard>
        <View style={{ height: 30 }} />
      </ScrollView>
    </View>
  );
}

/**
 * Which of the workspaces the station joined may run their chats on it too (as the web's WorkspacesSection), a switch
 * each: for its home workspace's owners and admins (the core's `memberships`), once the station is in more than one.
 */
function WorkspacesSection({ address, p }: { address: string; p: Profile }) {
  const C = useC();
  const api = app.api(address);
  const topic = useTopic<MembershipsView>({ topic: "memberships", station: address });
  const busy = useDoing("profile.put", { station: address, id: p.id });
  const failed = useDoingFailed("profile.put", { station: address, id: p.id });
  const view = topic.value;
  if (view == null) return null;
  const joined = view.manages ? view.workspaces.filter((it) => !it.home) : [];
  if (joined.length === 0) return null;
  const now = p.workspaces ?? [];
  return (
    <>
      <SectionHeader title={t("web-pages.profiles.workspaces.title")} start={24} />
      <ListCard>
        {joined.map((w) => {
          const on = now.includes(w.workspace);
          return (
            <ListRow
              key={w.workspace}
              onClick={busy ? undefined : () => {
                const next = on ? minus(now, w.workspace) : [...now, w.workspace];
                app.act(
                  t("web-pages.profiles.workspaces.what"),
                  () => api.putProfile(p.id, { workspaces: next }),
                  t(on ? "web-pages.profiles.workspaces.turnedOff" : "web-pages.profiles.workspaces.turnedOn", { name: w.name }),
                );
              }}
            >
              <View style={{ flex: 1, minWidth: 0 }}>
                <T size={15} color={C.ink}>{t("web-pages.profiles.workspaces.for", { name: w.name })}</T>
                <T size={13} color={C.muted}>{t(on ? "web-pages.profiles.workspaces.on" : "web-pages.profiles.workspaces.off", { name: w.name })}</T>
              </View>
              <DoingMark running={busy} failed={failed} />
              <Switch on={on} />
            </ListRow>
          );
        })}
      </ListCard>
    </>
  );
}

/**
 * Sharing a profile with the workspace's other stations (as the desktop's ShareSection): a switch; once on, where a
 * subscription is signed in (moved from here) and which stations may use it. A copy of another station's says whose.
 */
function ShareSection({ current, s, p }: { current: WorkspaceEntry; s: StationView; p: Profile }) {
  const C = useC();
  const api = app.api(s.station);
  const topic = useTopic<ProfilesView>({ topic: "profiles", scope: current.workspace.id });
  const sharing = useDoing("profile.share", { station: s.station, id: p.id });
  const moving = useDoing("profile.move", { station: s.station, id: p.id });
  const shareFailed = useDoingFailed("profile.share", { station: s.station, id: p.id });
  const moveFailed = useDoingFailed("profile.move", { station: s.station, id: p.id });
  const share = p.share;
  // Its row of the workspace's list (the account it is), and there the station that lends it.
  const entry = topic.value?.items?.find((e) => (e.members ?? []).some((it) => it.station === s.station && it.profileId === p.id));
  const stations = entry?.stations ?? [];
  const lender = share != null ? entry?.members?.find((it) => it.stationId === share.host && it.role === "host") : undefined;
  const subscription = p.access.kind === "subscription";
  if (share?.role === "user") {
    const host = stations.find((it) => it.id === share.host)?.name ?? share.host.slice(0, 8);
    return (
      <>
        <SectionHeader title={t("web-pages.profiles.share.title")} start={24} />
        <ListCard>
          <ListRow onClick={lender != null ? () => app.push({ kind: "Profile", address: lender.station, profile: lender.profileId }) : undefined}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{t("web-main.memory.share.from", { station: host })}</T>
              <T size={13} color={C.muted}>{t("web-pages.profiles.share.changeThere")}</T>
              {subscription && share.reachable === false && <T size={13} color={C.red}>{t("web-pages.profiles.share.hostAway", { station: host })}</T>}
            </View>
            {lender != null && <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />}
          </ListRow>
        </ListCard>
      </>
    );
  }
  const shared = share != null;
  const allowed = share?.allow;
  const names = allowed == null
    ? t("web-pages.profiles.share.everyStation")
    : stations.filter((it) => allowed.includes(it.id) || it.id === s.id).map((it) => it.name).join(t("web-main.list.separator"));
  const targets = stations.filter((it) => it.id !== s.id);
  const users = share?.users ?? [];
  return (
    <>
      <SectionHeader title={t("web-pages.profiles.share.title")} start={24} />
      <ListCard>
        <ListRow
          onClick={sharing ? undefined : () => {
            app.act(t("web-pages.profiles.share.switch"), () => api.shareProfile(p.id, !shared, null), shared ? t("web-pages.profiles.share.unshared") : t("web-pages.profiles.share.shared"));
          }}
        >
          <View style={{ flex: 1, minWidth: 0 }}>
            <T size={15} color={C.ink}>{t("web-pages.profiles.share.switch")}</T>
            <T size={13} color={C.muted}>{!shared ? t("web-pages.profiles.share.onlyHere", { station: s.name }) : subscription ? t("web-pages.profiles.share.lent") : t("web-pages.profiles.share.copied")}</T>
          </View>
          <DoingMark running={sharing} failed={shareFailed} />
          <Switch on={shared} />
        </ListRow>
        {shared && subscription && p.machine !== true && (
          <ListRow onClick={moving || targets.length === 0 ? undefined : () => openMove(app, s, p, targets)}>
            <T size={15} color={C.ink} style={{ flex: 1, minWidth: 0 }}>{t("web-pages.profiles.share.signedIn")}</T>
            <DoingMark running={moving} failed={moveFailed} />
            <T size={13} color={C.muted}>{s.name}</T>
            <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
          </ListRow>
        )}
        {shared && (
          <ListRow onClick={() => openPickShare(app, s, p, stations, allowed)}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{t("web-pages.profiles.share.stations")}</T>
              {users.length > 0 && (
                <T size={13} color={C.muted}>
                  {t("web-pages.profiles.share.users", { stations: users.map((u) => stations.find((it) => it.id === u)?.name ?? u.slice(0, 8)).join(t("web-main.list.separator")) })}
                </T>
              )}
            </View>
            <T size={13} color={C.muted} numberOfLines={1} style={{ flexShrink: 1 }}>{names}</T>
            <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
          </ListRow>
        )}
      </ListCard>
    </>
  );
}

function openMove(app: AppState, s: StationView, p: Profile, targets: ShareStation[]) {
  app.sheet = new SheetSpec(0.5, false, null, null, false, () => <MoveSheet s={s} p={p} targets={targets} />);
}

function MoveSheet({ s, p, targets }: { s: StationView; p: Profile; targets: ShareStation[] }) {
  const C = useC();
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.profiles.share.moveTitle")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 6 }}>{t("web-pages.profiles.share.moveLead", { station: s.name })}</T>
        {targets.map((x) => (
          <PickRow
            key={x.id}
            label={x.name}
            sub={x.online ? undefined : t("android-settings.profiles.stationOffline")}
            enabled={x.online}
            onClick={() => {
              app.sheet = null;
              app.act(t("web-pages.profiles.share.move"), () => app.api(s.station).moveProfile(p.id, x.id), t("web-pages.profiles.share.moved", { station: x.name }));
            }}
          />
        ))}
      </ScrollView>
    </>
  );
}

/** Which stations may use a shared profile, ticked in a sheet; all ticked is every station (those to come too). */
function openPickShare(app: AppState, s: StationView, p: Profile, stations: ShareStation[], allowed: string[] | null | undefined) {
  app.sheet = new SheetSpec(0.6, false, null, null, false, () => <PickShareSheet s={s} p={p} stations={stations} allowed={allowed} />);
}

function PickShareSheet({ s, p, stations, allowed }: { s: StationView; p: Profile; stations: ShareStation[]; allowed: string[] | null | undefined }) {
  const C = useC();
  const [ticked, setTicked] = useState<ReadonlySet<string>>(() => new Set(allowed ?? stations.map((it) => it.id)));
  const all = stations.every((it) => it.id === s.id || ticked.has(it.id));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.profiles.share.stations")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 6 }}>{all ? t("web-pages.profiles.share.futureIn") : t("web-pages.profiles.share.futureOut")}</T>
        {stations.map((x) => (
          <PickRow
            key={x.id}
            label={x.name}
            checked={x.id === s.id || ticked.has(x.id)}
            enabled={x.id !== s.id}
            onClick={() => {
              const next = new Set(ticked);
              if (ticked.has(x.id)) next.delete(x.id);
              else next.add(x.id);
              setTicked(next);
            }}
          />
        ))}
        <PickRow
          label={t("web-pages.profiles.share.done")}
          color={C.accent}
          onClick={() => {
            app.sheet = null;
            const allow = all ? null : [...new Set([...ticked, s.id])];
            app.act(t("web-pages.profiles.share.stations"), () => app.api(s.station).shareProfile(p.id, true, allow));
          }}
        />
      </ScrollView>
    </>
  );
}

/** Where something is added: one of the stations online, picked in a sheet. */
export function openPickStation(app: AppState, title: string, stations: StationView[], go: (s: StationView) => void) {
  app.sheet = new SheetSpec(0.5, false, null, null, false, () => <PickStationSheet title={title} stations={stations} go={go} />);
}

function PickStationSheet({ title, stations, go }: { title: string; stations: StationView[]; go: (s: StationView) => void }) {
  const C = useC();
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 6 }}>{t("android-settings.pickStation")}</T>
        {stations.map((s) => <PickRow key={s.station} label={s.name} onClick={() => { app.sheet = null; go(s); }} />)}
      </ScrollView>
    </>
  );
}

/**
 * A profile in the list of profiles: whether it works (a dot before its name, its state in words, why when its provider
 * refuses it), what it is, how many of its models are enabled, and its allowance; its page picks them.
 */
export function ProfileRow({ station, p }: { station: string; p: Profile }) {
  const C = useC();
  const calls = ["profile.check", "profile.quota"];
  const running = useDoing(calls, { station, id: p.id });
  const failed = useDoingFailed(calls, { station, id: p.id });
  const trouble = quotaTrouble(p.quota);
  const problem = p.trouble;
  return (
    <ListRow onClick={() => app.push({ kind: "Profile", address: station, profile: p.id })}>
      <View style={{ flex: 1, minWidth: 0 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          <PresenceDot state={toneDot(p.checkTone)} />
          <T size={15} color={C.ink} numberOfLines={1} style={{ flexShrink: 1 }}>{p.name}</T>
        </View>
        <T size={13} color={C.muted} numberOfLines={1}>
          {[p.checkText, p.machine === true ? t("android-settings.profile.machine") : (p.usesText ? p.usesText : null) ?? ACCESS_LABEL[p.access.kind] ?? p.access.kind, p.modelsText].filter((x) => x != null).join(" · ")}
        </T>
        {problem != null
          ? (
            <>
              <T size={13} color={C.muted}>{`${problem.title} · ${problem.detail}`}</T>
              <T size={13} color={C.accent}>{t("android-settings.profile.seeFix")}</T>
            </>
          )
          : trouble != null ? <T size={13} color={C.muted}>{trouble}</T> : null}
      </View>
      <DoingMark running={running} failed={failed} />
      <QuotaRings quota={p.quota} />
      <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
    </ListRow>
  );
}

export function ProfileScreen({ current, address, id }: { current: WorkspaceEntry; address: string; id: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const stations = useTopic<StationView[]>({ topic: "stations", scope: current.workspace.id });
  // The switch flipped and not answered yet: shown flipped, with a spinner.
  const [flipping, setFlipping] = useState<boolean | null>(null);
  const checking = useDoing("profile.check", { station: address, id });
  const checkFailed = useDoingFailed(["profile.check", "profile.quota"], { station: address, id });
  const putting = useDoing("profile.put", { station: address, id });
  const putFailed = useDoingFailed("profile.put", { station: address, id });
  const s = stations.value?.find((it) => it.station === address);
  const p = s?.overview?.profiles?.find((it) => it.id === id);
  if (s == null || p == null) {
    return (
      <View style={{ flex: 1 }}>
        <NavBar back={s?.name ?? "Station"} onBack={() => app.pop()} title="Profile" />
        {/* The station read, and the profile not on it (gone since): said, not waited on. */}
        {s?.overview != null && stations.error == null
          ? <PlaceEmpty text={t("android-settings.profile.none")} />
          : <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={stations.error?.message} />}
      </View>
    );
  }
  const api = app.api(address);
  const setModels = (models: string[]) => {
    app.act(t("android-settings.profile.saveModels"), () => api.setModels(p.id, models));
  };
  const users = p.usedBy.map((u) => s.overview?.connects?.find((it) => it.id === u)).filter((c): c is NonNullable<typeof c> => c != null);
  const kind = p.access.kind;
  // A copy of another station's: shown, used, changed only there.
  const copy = p.share?.role === "user";
  const fast = p.fast;
  // A station older than the setting says nothing of it.
  const background = flipping ?? p.backgroundOnMessage;
  const checkedAt = p.check?.time?.["checkedAt"];
  const endpoint = p.access.endpoint;
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back={s.name}
        onBack={() => app.pop()}
        title={p.name}
        sub={<T size={11} color={C.muted}>{p.machine === true ? t("android-settings.profile.machine") : p.providerName ?? ACCESS_LABEL[kind] ?? kind}</T>}
        trailing={copy ? undefined : <NavButton icon={Icons.More} onClick={() => openProfileMenu(app, address, p)} />}
      />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom, paddingTop: 12 }}>
        <Card>
          <View style={{ flexDirection: "row", alignItems: "flex-start", gap: 12 }}>
            <ProviderMark runtime={p.runtime} kind={kind} size={26} mark={p.providerMark} />
            <View style={{ flex: 1, minWidth: 0, gap: 4 }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                <TonePill text={p.checkText} tone={p.checkTone} />
                {/* Its check or allowance refresh (asked from its menu, gone) failed a moment ago: a red mark, a tap says why. */}
                {checking
                  ? <WaitLine text={t("android-settings.version.checking")} />
                  : <DoingMark running={false} failed={checkFailed} inline />}
              </View>
              <T size={13} color={C.muted}>
                {(p.check?.detail?.replace(/^(可用[，,]|Works,)\s*/, "") ?? t("android-settings.profile.notChecked")) + (checkedAt != null ? t("android-settings.profile.checkedAt", { ago: checkedAt.ago }) : "")}
              </T>
            </View>
          </View>
        </Card>
        {p.trouble != null && <ProfileRecovery station={s} p={p} />}
        {!copy && kind === "subscription" && p.machine !== true && (
          <SignIn station={address} p={p} needed={p.check?.state === "login" || (p.login != null && SIGNING_IN.has(p.login.state))} />
        )}
        {p.trouble?.action !== "quota" && <QuotaSection station={address} p={p} />}
        {s.overview?.sharing === true && <ShareSection current={current} s={s} p={p} />}
        {!copy && <WorkspacesSection address={address} p={p} />}
        {!copy && fast != null && (
          <>
            <SectionHeader title={t("android-settings.profile.run")} start={24} />
            <ListCard>
              <ListRow onClick={putting ? undefined : () => { app.act(t("android-settings.profile.saveFast"), () => api.putProfile(p.id, { fast: !fast }), fast ? t("android-settings.profile.fastOff") : t("android-settings.profile.fastOn")); }}>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} color={C.ink}>{t("android-settings.profile.fast")}</T>
                  <T size={13} color={C.muted}>{t("android-settings.profile.fastNote")}</T>
                </View>
                <DoingMark running={putting} failed={putFailed} />
                <Switch on={fast} />
              </ListRow>
            </ListCard>
          </>
        )}
        {!copy && <ModelsSection station={address} p={p} models={p.models} saving={p.modelsSaving != null} onSave={(models) => setModels(models)} />}
        {!copy && p.runtimes.includes("claude") && background != null && (
          <>
            <SectionHeader title={t("android-settings.profile.run")} start={24} />
            <ListCard>
              <ListRow
                onClick={flipping != null ? undefined : () => {
                  setFlipping(!background);
                  void (async () => {
                    try {
                      await api.putProfile(p.id, { backgroundOnMessage: !background });
                      app.toast = background ? t("android-settings.profile.turnedOff") : t("android-settings.profile.turnedOn");
                    } catch (e) {
                      app.toast = t("android-settings.run.saveFailed", { error: said(e) });
                    } finally {
                      setFlipping(null);
                    }
                  })();
                }}
              >
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} color={C.ink}>{t("android-settings.profile.background")}</T>
                  <T size={13} color={C.muted}>{background ? t("android-settings.profile.backgroundOn") : t("android-settings.profile.backgroundOff")}</T>
                </View>
                {flipping != null && <Spinner />}
                <Switch on={background} />
              </ListRow>
            </ListCard>
          </>
        )}
        <SectionHeader title={t("android-settings.profile.users")} start={24} />
        <ListCard>
          {users.length === 0 && <ListRow><T size={15} color={C.muted}>{t("android-settings.profile.noUsers")}</T></ListRow>}
          {users.map((c) => (
            <ListRow key={c.id} onClick={() => app.push({ kind: "Connect", station: address, connect: c.id })}>
              <SlackMark size={15} />
              <T size={15} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{c.name}</T>
              <T size={13} color={C.muted}>{c.modelName ?? (p.model != null ? (p.names[p.model] ?? p.model) : null) ?? t("android-settings.profile.defaultModel")}</T>
            </ListRow>
          ))}
        </ListCard>
        {copy
          ? null
          : p.machine === true
            ? (() => {
              // On the machine's own login: whose it is is changed on that machine, not here.
              const runtime = MACHINE_RUNTIME[p.runtime] ?? p.runtime;
              return (
                <>
                  <SectionHeader title={t("android-settings.run.account")} start={24} />
                  <Card>
                    <T size={15} color={C.ink}>{t("android-settings.profile.machineLogin", { station: s.name, runtime })}</T>
                    <T size={13} color={C.muted} style={{ paddingTop: 4 }}>{t("android-settings.profile.machineNote", { runtime })}</T>
                  </Card>
                </>
              );
            })()
            : KEYED.has(kind)
              ? (() => {
                const name = kind === "opencode-go" ? "OpenCode Go key" : p.providerName != null ? `${p.providerName} key` : "API key";
                return (
                  <>
                    <SectionHeader title={t("android-settings.run.account")} start={24} />
                    <ListCard>
                      <ListRow
                        onClick={() => {
                          ask(app, kind === "opencode-go" ? t("android-settings.profile.newGoKey") : t("android-settings.profile.newApiKey"), "", t("android-settings.profile.pasteKey"), t("common.save"), { secret: true, hint: t("android-settings.profile.keyHint"), what: t("android-settings.profile.keyWhat") }, async (key: string) => {
                            await api.putProfile(p.id, { access: { kind, key } }); app.toast = t("android-settings.profile.savedChecking");
                          });
                        }}
                      >
                        <View style={{ flex: 1, minWidth: 0 }}>
                          <T size={15} color={C.ink}>{name}</T>
                          <T size={13} color={C.muted} mono>{p.access.key !== "" ? p.access.key : t("android-settings.profile.notSaved")}</T>
                        </View>
                        {/* A key saved (the sheet that asked gone): a spinner until the station has it. */}
                        <DoingMark running={putting} failed={putFailed} />
                        <T size={14} color={C.accent}>{t("android-settings.profile.change")}</T>
                      </ListRow>
                      {/* Where a provider is at an address of the person's own, that can be changed too. */}
                      {endpoint != null && (
                        <ListRow
                          onClick={() => {
                            ask(app, t("common.provider.endpoint"), endpoint, "https://", t("common.save"), async (value: string) => {
                              await api.putProfile(p.id, { access: { kind, endpoint: value.trim() } }); app.toast = t("android-settings.profile.savedChecking");
                            });
                          }}
                        >
                          <View style={{ flex: 1, minWidth: 0 }}>
                            <T size={15} color={C.ink}>{t("common.provider.endpoint")}</T>
                            <T size={13} color={C.muted} mono>{endpoint}</T>
                          </View>
                          <T size={14} color={C.accent}>{t("android-settings.profile.change")}</T>
                        </ListRow>
                      )}
                    </ListCard>
                  </>
                );
              })()
              : null}
        {kind === "env" && !copy && (
          <>
            <SectionHeader title={t("android-settings.env.title")} start={24} />
            <ListCard>
              {p.env.map((e) => (
                <ListRow key={e.key}>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <T size={15} color={C.ink} mono>{e.key}</T>
                    <T size={13} color={C.muted} mono numberOfLines={1}>{e.value}</T>
                  </View>
                </ListRow>
              ))}
              <ListRow onClick={() => { app.sheet = new SheetSpec(0.8, true, null, null, false, () => <EnvSheet station={address} p={p} />); }}>
                <T size={15} color={C.accent} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.env.edit")}</T>
                {/* Saved (the sheet gone): a spinner until the station has them. */}
                <DoingMark running={putting} failed={putFailed} />
              </ListRow>
            </ListCard>
          </>
        )}
        <View style={{ height: 30 }} />
      </ScrollView>
    </View>
  );
}

/** The same core-provided diagnosis and next step as the mobile web. */
function ProfileRecovery({ station, p }: { station: StationView; p: Profile }) {
  const C = useC();
  const address = station.station;
  const checking = useDoing("profile.check", { station: address, id: p.id });
  const refreshing = useDoing("profile.quota", { station: address, id: p.id });
  const failed = useDoingFailed(["profile.check", "profile.quota"], { station: address, id: p.id });
  const issue = p.trouble;
  if (issue == null) return null;
  const api = app.api(address);
  return (
    <>
      <SectionHeader title={issue.title} start={24} />
      <Card>
        <View style={{ gap: 10 }}>
          <T size={13} color={C.ink}>{issue.detail}</T>
          <T size={13} color={C.muted}>{issue.next}</T>
          {!station.online && <T size={13} color={C.muted}>{t("android-settings.profile.offline", { name: station.name })}</T>}
          {issue.action === "command" && <CommandBox text={p.loginCommand} />}
          {issue.action !== "login" && (
            <Start>
              <Button
                label={issue.label}
                primary={false}
                enabled={station.online}
                busy={checking || refreshing}
                onClick={() => {
                  switch (issue.action) {
                    case "key":
                      ask(app, t("android-settings.profile.newKey"), "", t("android-settings.profile.pasteKey"), t("common.save"), { secret: true, hint: t("android-settings.profile.keyHintShort"), what: t("android-settings.profile.keyWhat") }, async (key: string) => {
                        await api.putProfile(p.id, { access: { kind: p.access.kind, key } });
                      });
                      break;
                    case "env":
                      app.sheet = new SheetSpec(0.8, true, null, null, false, () => <EnvSheet station={address} p={p} />);
                      break;
                    case "quota":
                      app.act(t("android-settings.quota.checkWhat"), () => api.refreshQuota(p.id), t("android-settings.quota.updated"));
                      break;
                    default:
                      app.act(t("android-settings.profile.checkWhat"), () => api.checkProfile(p.id), t("android-settings.profile.checked"));
                  }
                }}
              />
            </Start>
          )}
          {(issue.action === "key" || issue.action === "env") && (
            <Start>
              <Button
                label={t("android-settings.profile.recheck")}
                primary={false}
                enabled={station.online}
                busy={checking}
                onClick={() => { app.act(t("android-settings.profile.checkWhat"), () => api.checkProfile(p.id), t("android-settings.profile.checked")); }}
              />
            </Start>
          )}
          <Start><DoingMark running={false} failed={failed} /></Start>
        </View>
      </Card>
    </>
  );
}

/** Renaming, checking, deleting it (not while a connect uses it). */
function openProfileMenu(app: AppState, station: string, p: Profile) {
  app.sheet = new SheetSpec(0.5, false, null, null, false, () => <ProfileMenuSheet station={station} p={p} />);
}

function ProfileMenuSheet({ station, p }: { station: string; p: Profile }) {
  const C = useC();
  const api = app.api(station);
  // Goes on past the sheet; the profile's page shows it under way (a spinner by its state or its allowance).
  const run = (what: string, done: string, call: () => Promise<unknown>) => { app.sheet = null; app.act(what, call, done); };
  const checking = useDoing("profile.check", { station, id: p.id });
  const checkFailed = useDoingFailed("profile.check", { station, id: p.id });
  // One on the machine's login is stopped rather than deleted: the login stays the machine's, to be used again.
  const machine = p.machine === true;
  return (
    <>
      <SheetGrab />
      <SheetHead title={p.name} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        {p.machine !== true && (
          <PickRow
            label={t("android-settings.station.rename")}
            onClick={() => {
              ask(app, t("android-settings.profile.nameTitle"), p.name, t("android-settings.station.name"), t("common.save"), { what: t("android-settings.profile.renameWhat") }, async (name: string) => {
                await api.putProfile(p.id, { name }); app.toast = t("android-settings.renamed");
              });
            }}
          />
        )}
        <PickRow
          label={t("android-settings.profile.recheck")}
          busy={checking}
          failed={checkFailed}
          onClick={() => run(t("android-settings.profile.checkShort"), t("android-settings.profile.checked"), () => api.checkProfile(p.id))}
        />
        <PickRow
          label={machine ? t("android-settings.connect.disable") : t("android-settings.profile.delete")}
          color={C.red}
          onClick={() => {
            if (machine) {
              confirm(app, t("android-settings.profile.disableTitle", { name: p.name }), t("android-settings.profile.disableText", { app: APP_NAME, runtime: MACHINE_RUNTIME[p.runtime] ?? p.runtime }), t("android-settings.connect.disable"), true,
                t("android-settings.profile.disableWhat"), () => app.pop(), async () => {
                  await api.deleteProfile(p.id); app.toast = t("android-settings.profile.disabled");
                });
            } else {
              confirm(app, t("android-settings.connect.deleteTitle", { name: p.name }), t("android-settings.profile.deleteText", { app: APP_NAME }), t("android-settings.profile.delete"), true,
                t("android-settings.profile.deleteWhat"), () => app.pop(), async () => {
                  await api.deleteProfile(p.id); app.toast = t("android-settings.profile.deleted");
                });
            }
          }}
        />
      </ScrollView>
    </>
  );
}

/** Its allowance, window by window: what is left and when it refills; why it cannot be read, when the provider says. */
function QuotaSection({ station, p }: { station: string; p: Profile }) {
  const C = useC();
  const refreshing = useDoing("profile.quota", { station, id: p.id });
  const failed = useDoingFailed("profile.quota", { station, id: p.id });
  const resetting = useDoing("profile.resetQuota", { station, id: p.id });
  const resetFailed = useDoingFailed("profile.resetQuota", { station, id: p.id });
  const windows = p.quota?.state === "ok" ? p.quota.windows : [];
  const trouble = quotaTrouble(p.quota);
  const checkedAt = p.quota?.time?.["checkedAt"];
  const checked = refreshing ? t("android-settings.refreshing") : checkedAt != null ? t("android-settings.quota.checkedAt", { ago: checkedAt.ago }) : null;
  const head = (
    <>
      <View style={{ alignSelf: "stretch", paddingHorizontal: 24, paddingTop: 14, paddingBottom: 6, flexDirection: "row", alignItems: "center" }}>
        <T size={15} weight="600" color={C.ink}>{t("android-settings.quota.title")}</T>
        <View style={{ flex: 1 }} />
        <Pressable
          disabled={refreshing}
          android_ripple={{ color: withAlpha(C.ink, 0.1) }}
          onPress={() => { app.act(t("android-settings.quota.checkWhat"), () => app.api(station).refreshQuota(p.id), t("android-settings.quota.updated")); }}
          style={{ paddingVertical: 4, flexDirection: "row", alignItems: "center", gap: 6 }}
        >
          <DoingMark running={refreshing} failed={failed} inline />
          <T size={14} color={refreshing ? C.muted : C.accent}>{refreshing ? t("android-settings.quota.checking") : t("android-settings.quota.check")}</T>
        </Pressable>
      </View>
      {checked != null && !refreshing && <T size={12} color={C.muted} style={{ paddingLeft: 24, paddingBottom: 8 }}>{checked}</T>}
    </>
  );
  if (trouble != null) {
    const blocked = p.quota?.state === "blocked";
    return (
      <>
        {head}
        <ListCard>
          <ListRow>
            <View style={{ flex: 1, minWidth: 0 }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                <PresenceDot state={blocked ? "error" : "offline"} />
                <T size={15} color={C.ink} style={{ flexShrink: 1 }}>{blocked ? t("android-settings.quota.blocked") : t("android-settings.quota.unavailable")}</T>
              </View>
              <T size={13} color={C.muted}>{trouble}</T>
            </View>
          </ListRow>
        </ListCard>
      </>
    );
  }
  if (windows.length === 0 && p.quota?.creditsText == null && p.quota?.resetCount == null) {
    const detail = p.quota?.detail;
    return (
      <>
        {head}
        <T size={13} color={C.muted} style={{ paddingHorizontal: 24, paddingBottom: 10 }}>{detail != null && detail.trim() !== "" ? detail : t("android-settings.quota.none")}</T>
      </>
    );
  }
  const quota = p.quota;
  const creditsText = quota?.creditsText;
  const count = quota?.resetCount;
  return (
    <>
      {head}
      <ListCard>
        {windows.length > 0 && <View style={{ paddingLeft: 16, paddingRight: 16, paddingTop: 16, paddingBottom: 14 }}><QuotaDials quota={p.quota} /></View>}
        {creditsText != null && (
          <ListRow>
            <T size={15} color={C.ink} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.quota.credits")}</T>
            <T size={13} color={C.muted}>{creditsText}</T>
          </ListRow>
        )}
        {quota != null && count != null && (
          <ListRow
            onClick={count <= 0 || resetting ? undefined : () => {
              // Kotlin puts a missing resetText in as "null"; here as nothing.
              confirm(app, t("android-settings.quota.resetTitle"), t("android-settings.quota.resetText", { name: p.name, text: quota.resetText ?? "" }), t("android-settings.quota.resetUse"), { what: t("android-settings.quota.resetWhat") }, async () => {
                await app.api(station).resetQuota(p.id); app.toast = t("android-settings.quota.resetDone");
              });
            }}
          >
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{t("android-settings.quota.resets")}</T>
              <T size={13} color={C.muted}>{quota.resetText ?? ""}</T>
            </View>
            <DoingMark running={resetting} failed={resetFailed} />
            <T size={14} color={count > 0 ? C.accent : C.muted}>{t("android-settings.quota.reset")}</T>
          </ListRow>
        )}
      </ListCard>
    </>
  );
}

/** A check's state in its words on a soft pill of its tone (the core's: accent | green | blue | red | amber | neutral). */
export function TonePill({ text, tone, size = 12 }: { text: string; tone: string; size?: number }) {
  const C = useC();
  const color = tone === "green" ? C.green : tone === "red" ? C.red : tone === "blue" ? C.blue : tone === "accent" ? C.accentInk : tone === "amber" ? C.warn : C.muted;
  const bg = tone === "neutral" ? C.chip : withAlpha(color, tone === "amber" ? 0.14 : 0.12);
  // The row holds the pill to its words' width, in a column as in a row (Compose's Text wraps its content).
  return (
    <View style={{ flexDirection: "row" }}>
      <Smooth radius={6} style={{ backgroundColor: bg, paddingHorizontal: 6, paddingVertical: 1 }}>
        <T size={size} color={color} numberOfLines={1} ellipsizeMode="clip">{text}</T>
      </Smooth>
    </View>
  );
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
export function ModelsSection({ station, p, models, saving, onSave }: { station: string; p: Profile; models: string[]; saving: boolean; onSave: (models: string[]) => void }) {
  const C = useC();
  const checking = useDoing("profile.check", { station, id: p.id });
  const checkFailed = useDoingFailed("profile.check", { station, id: p.id });
  const [filter, setFilter] = useState("");
  const all = [...(p.available ?? distinct([...(p.check?.models ?? []), ...p.models]))].sort();
  const needle = filter.trim().toLowerCase();
  const shown = all.filter((m) => [m, p.names[m] ?? m].some((it) => it.toLowerCase().includes(needle)));
  const save = (next: string[]) => onSave(distinct(next).sort());
  const filtered = filter.trim() !== "";
  // A provider that answers the automatic decisions alone: the models its probe found, as they are.
  if (p.decisionOnly === true) {
    return (
      <>
        <SectionHeader title={t("web-mobile.profiles.decisionModels")} start={24} />
        {(p.decisionModels ?? []).map((m) => <T key={m} size={15} color={C.ink} style={{ paddingHorizontal: 24, paddingVertical: 6 }}>{m}</T>)}
        {p.decisionText != null && <T size={13} color={C.muted} style={{ paddingHorizontal: 24, paddingBottom: 6 }}>{p.decisionText}</T>}
      </>
    );
  }
  const ripple = { color: withAlpha(C.ink, 0.1) };
  return (
    <>
      <SectionHeader title={t(saving ? "android-settings.models.headerSaving" : "android-settings.models.header", { on: models.length, n: all.length })} start={24} />
      <T size={13} color={C.muted} style={{ paddingHorizontal: 24, paddingBottom: 6 }}>
        {all.length === 0 ? t("android-settings.models.empty") : t("android-settings.models.note")}
      </T>
      <View style={{ paddingHorizontal: 24, paddingBottom: 8, flexDirection: "row", alignItems: "center", gap: 12 }}>
        <Pressable
          disabled={checking}
          android_ripple={ripple}
          onPress={() => { app.act(t("android-settings.models.refreshWhat"), () => app.api(station).checkProfile(p.id), t("android-settings.models.refreshed")); }}
          style={{ flexDirection: "row", alignItems: "center", gap: 6 }}
        >
          <DoingMark running={checking} failed={checkFailed} inline />
          <T size={14} color={checking ? C.muted : C.accent}>{checking ? t("android-settings.refreshing") : t("android-settings.models.refresh")}</T>
        </Pressable>
        <View style={{ flex: 1 }} />
        {all.length > 0 && (
          <>
            <Pressable disabled={saving} android_ripple={ripple} onPress={() => save([...models, ...shown])}>
              <T size={14} color={C.accent}>{filtered ? t("android-settings.models.allFiltered") : t("android-settings.all")}</T>
            </Pressable>
            <Pressable disabled={saving} android_ripple={ripple} onPress={() => save(models.filter((m) => !shown.includes(m)))}>
              <T size={14} color={C.accent}>{filtered ? t("android-settings.models.noneFiltered") : t("android-settings.none")}</T>
            </Pressable>
          </>
        )}
      </View>
      {/* A provider that does not list its models: one is named by hand. */}
      {p.canAddModel === true && <AddModel station={station} p={p} />}
      {all.length > 10 && (
        <View style={{ paddingHorizontal: 24, paddingBottom: 8 }}>
          <Field value={filter} onChange={setFilter} placeholder={t("android-settings.models.filter")} />
        </View>
      )}
      {/* Plain rows on the page, no card behind them; by series, newest first (the core's). */}
      {p.series.map((series) => {
        const list = series.models.filter((it) => shown.includes(it));
        return (
          <View key={series.name}>
            {list.length > 0 && <T size={13} color={C.muted} style={{ paddingHorizontal: 24, paddingTop: 14, paddingBottom: 2 }}>{series.name}</T>}
            {list.map((m) => {
              const on = models.includes(m);
              return (
                <Pressable
                  key={m}
                  disabled={saving}
                  android_ripple={ripple}
                  onPress={() => save(on ? minus(models, m) : [...models, m])}
                  style={{ alignSelf: "stretch", paddingHorizontal: 24, paddingVertical: 11, flexDirection: "row", alignItems: "center", gap: 12 }}
                >
                  <Smooth radius={6} style={{ width: 20, height: 20, backgroundColor: on ? C.accent : C.chip, alignItems: "center", justifyContent: "center" }}>
                    {on && <Icon icon={Icons.Check} size={13} color={C.bg} />}
                  </Smooth>
                  <T size={14} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{p.names[m] ?? m}</T>
                  {/* Ticked here, not the station's yet. */}
                  {(p.modelsSaving ?? []).includes(m) && <Spinner inline />}
                </Pressable>
              );
            })}
          </View>
        );
      })}
    </>
  );
}

/** A model named by hand (ModelsSection's `canAddModel` part: what is typed lives while that part is shown, as Kotlin's remember inside its `if`). */
function AddModel({ station, p }: { station: string; p: Profile }) {
  const C = useC();
  const [typed, setTyped] = useState("");
  const adding = useDoing("profile.addModel", { station, id: p.id });
  const blank = typed.trim() === "";
  return (
    <View style={{ paddingHorizontal: 24, paddingBottom: 8, flexDirection: "row", alignItems: "center", gap: 12 }}>
      <View style={{ flex: 1, minWidth: 0 }}>
        <Field value={typed} onChange={setTyped} placeholder={t("web-mobile.profiles.addModelPlaceholder")} mono />
      </View>
      {adding
        ? <Spinner />
        : (
          <Pressable
            disabled={blank}
            android_ripple={{ color: withAlpha(C.ink, 0.1) }}
            onPress={() => {
              const model = typed.trim(); setTyped("");
              app.act(t("android-settings.models.refreshWhat"), () => app.api(station).addModel(p.id, model));
            }}
          >
            <T size={14} color={blank ? C.muted : C.accent}>{t("web-mobile.profiles.addModel")}</T>
          </Pressable>
        )}
    </View>
  );
}

/** A subscription's sign-in: run on the station's machine, the browser steps relayed here. */
function SignIn({ station, p, needed }: { station: string; p: Profile; needed: boolean }) {
  const C = useC();
  const api = app.api(station);
  const job = p.login;
  const active = job != null && SIGNING_IN.has(job.state);
  const provider = p.runtime === "claude" ? "Claude" : "ChatGPT";
  const busy = useDoing("profile.login", { station, id: p.id });
  const cancelling = useDoing("profile.cancelLogin", { station, id: p.id });
  const [manual, setManual] = useState(false);
  const [previous, setPrevious] = useState<string | undefined>(job?.state);
  useEffect(() => {
    if (job?.state === "done" && previous != null && previous !== "done") app.toast = t("android-settings.login.done");
    setPrevious(job?.state);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [job?.state]);
  return (
    <>
      <SectionHeader
        title={active ? t("android-settings.login.active", { provider }) : needed ? t("android-settings.login.needed", { provider }) : t("android-settings.login.subscription", { provider })}
        start={24}
      />
      <Card>
        <View style={{ gap: 10 }}>
          {active
            ? (
              <>
                <LoginSteps job={job} provider={provider} send={(code) => api.loginCode(p.id, code)} />
                <Start>
                  <Button label={t("android-settings.login.cancel")} primary={false} busy={cancelling} onClick={() => { app.act(t("android-settings.login.cancelWhat"), () => api.cancelLogin(p.id)); }} />
                </Start>
              </>
            )
            : (
              <>
                <T size={13} color={C.muted}>
                  {job?.state === "failed"
                    ? t("android-settings.login.failed", { error: job.error ?? "" })
                    : job?.state === "done" ? t("android-settings.login.signedIn") : t("android-settings.login.note", { app: APP_NAME })}
                </T>
                <Start>
                  <Button
                    label={job?.state === "done" || !needed ? t("android-settings.login.again") : t("android-settings.login.signIn")}
                    primary={needed}
                    busy={busy}
                    onClick={() => {
                      void (async () => {
                        try { await api.startLogin(p.id); } catch (e) { app.toast = t("android-settings.signIn.beginFailed", { error: said(e) }); }
                      })();
                    }}
                  />
                </Start>
                <Pressable android_ripple={{ color: withAlpha(C.ink, 0.1) }} onPress={() => setManual(!manual)} style={{ alignSelf: "flex-start", paddingVertical: 4 }}>
                  <T size={13} color={C.muted}>{t("android-settings.login.manual")}</T>
                </Pressable>
                {manual && <CommandBox text={p.loginCommand} />}
              </>
            )}
        </View>
      </Card>
    </>
  );
}

/**
 * What the person does in the browser for a sign-in under way: open the page and paste the code back (Claude), or copy
 * the code and open the page (Codex).
 */
function LoginSteps({ job, provider, send }: { job: LoginJob | null | undefined; provider: string; send: (code: string) => Promise<void> }) {
  const C = useC();
  const [code, setCode] = useState("");
  const operation = useAction(() => new Action(app));
  const busy = operation.busy;
  const error = operation.error?.message;
  const [copied, setCopied] = useState(false);
  const open = (url: string) => { void Linking.openURL(url); };
  const waiting = (text: string) => <WaitLine text={text} />;
  const url = job?.url;
  const userCode = job?.userCode;
  if (job == null || job.state === "starting") return waiting(t("android-settings.login.making", { provider }));
  if (job.state === "verifying") return waiting(t("android-settings.login.finishing"));
  if (job.state === "done") return waiting(t("android-settings.login.adding"));
  if (job.state === "needs_approval" && url != null && userCode != null) {
    return (
      <View style={{ gap: 10 }}>
        <Smooth radius={10} style={{ alignSelf: "flex-start", backgroundColor: C.chip, paddingHorizontal: 14, paddingVertical: 8 }}>
          <T size={22} color={C.ink} style={{ letterSpacing: 2, fontFamily: CODE_FONT }}>{userCode}</T>
        </Smooth>
        <Start>
          <Button
            label={copied ? t("android-settings.login.reopen") : t("android-settings.login.copyOpen")}
            primary
            onClick={() => {
              // NATIVE: a clipboard module (expo-clipboard) to put the code on it (Kotlin: ClipData "still.fail", userCode)
              setCopied(true); open(url);
            }}
          />
        </Start>
        <T size={13} color={C.muted}>{t("android-settings.login.codexNote", { app: APP_NAME })}</T>
      </View>
    );
  }
  if (job.state === "needs_code" && url != null) {
    return (
      <View style={{ gap: 10 }}>
        <View style={{ flexDirection: "row" }}>
          <T size={13} color={C.ink}>1. </T>
          <Pressable android_ripple={{ color: withAlpha(C.ink, 0.1) }} onPress={() => open(url)}>
            <T size={13} color={C.accent}>{t("android-settings.login.openPage")}</T>
          </Pressable>
          <T size={13} color={C.ink} style={{ flexShrink: 1 }}>{t("android-settings.login.openPageRest", { app: APP_NAME })}</T>
        </View>
        <T size={13} color={C.ink}>{t("android-settings.login.step2")}</T>
        <Field value={code} onChange={setCode} placeholder={t("android-settings.login.pasteCode")} mono />
        {error != null && <T size={13} color={C.red}>{error}</T>}
        <Start>
          <Button
            label={t("android-settings.login.finish")}
            primary
            busy={busy}
            enabled={code.trim() !== ""}
            onClick={() => {
              operation.run(async () => { await send(code.trim()); setCode(""); });
            }}
          />
        </Start>
      </View>
    );
  }
  return null;
}

/**
 * A variable being edited: its row, name and value; a secret one saved before shows masked and is kept when left blank.
 * (Kotlin's class with its own mutable state; here a plain record, changed by putting a new one in the list.)
 */
interface EnvRow { readonly row: number; key: string; value: string; readonly masked: string | null; readonly original: string | null }

/** The variables a custom profile runs with: what reaches its runtime's model service, set by hand. */
function EnvSheet({ station, p }: { station: string; p: Profile }) {
  const C = useC();
  const [next, setNext] = useState(1);
  const [rows, setRows] = useState<EnvRow[]>(() => p.env.map((e, i) => ({ row: -i - 1, key: e.key, value: e.secret ? "" : e.value, masked: e.secret ? e.value : null, original: e.key })));
  const busy = useDoing("profile.put", { station, id: p.id });
  const patch = () => {
    const kept = new Set(rows.map((it) => it.key.trim()));
    const out = new Map<string, string | null>();
    for (const it of p.env) if (!kept.has(it.key)) out.set(it.key, null);
    for (const r of rows) {
      const key = r.key.trim();
      if (key === "") continue;
      if (r.original != null && r.original !== key) out.set(r.original, null);
      if (r.masked != null && r.value === "" && r.original === key) continue;
      out.set(key, r.value);
    }
    return Object.fromEntries(out);
  };
  const change = (row: number, part: Partial<Pick<EnvRow, "key" | "value">>) => setRows(rows.map((it) => (it.row === row ? { ...it, ...part } : it)));
  const ripple = { color: withAlpha(C.ink, 0.1) };
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-settings.env.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, gap: 10 }}>
        <T size={12} color={C.muted}>{t("android-settings.env.note")}</T>
        {rows.map((r) => {
          const placeholder = r.masked != null ? t("android-settings.tokens.kept", { token: r.masked }) : t("android-settings.env.value");
          return (
            <View key={r.row} style={{ gap: 6 }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Field value={r.key} onChange={(it: string) => change(r.row, { key: it })} placeholder="NAME" mono />
                </View>
                <Pressable android_ripple={ripple} onPress={() => setRows(rows.filter((it) => it.row !== r.row))}>
                  <T size={14} color={C.accent}>{t("common.delete")}</T>
                </Pressable>
              </View>
              {r.masked != null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key)
                ? <SecretField value={r.value} onChange={(it: string) => change(r.row, { value: it })} placeholder={placeholder} />
                : <Field value={r.value} onChange={(it: string) => change(r.row, { value: it })} placeholder={placeholder} mono />}
            </View>
          );
        })}
        <Pressable
          android_ripple={ripple}
          onPress={() => { setRows([...rows, { row: next, key: "", value: "", masked: null, original: null }]); setNext(next + 1); }}
          style={{ alignSelf: "flex-start" }}
        >
          <T size={14} color={C.accent}>{t("android-settings.env.add")}</T>
        </Pressable>
        <View style={{ alignSelf: "stretch", flexDirection: "row", justifyContent: "flex-end", gap: 8 }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button
            label={t("common.save")}
            primary
            enabled={!busy}
            onClick={() => {
              const env = patch();
              app.sheet = null;
              app.act(t("android-settings.env.saveWhat"), () => app.api(station).putProfile(p.id, { env }), t("android-settings.saved"));
            }}
          />
        </View>
      </ScrollView>
    </>
  );
}

/**
 * A new profile on a station, as the core's add flow has it (the `profileFlow` topic, as the web's profileFlow.ts): the
 * providers by group, then how to connect the one picked (a plan signed in, or a key checked first: the profile is made
 * only if it works).
 */
export function NewProfileScreen({ current, address }: { current: WorkspaceEntry; address: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const api = app.api(address);
  const stations = useTopic<StationView[]>({ topic: "stations", scope: current.workspace.id });
  const s = stations.value?.find((it) => it.station === address);
  const form = useMemo(() => crypto.randomUUID(), [address]);
  const topic = useTopic<ProfileFlowView>({ topic: "profileFlow", station: address, form });
  function edit(input: Record<string, unknown>): void;
  function edit(key: string, value: string): void;
  function edit(a: Record<string, unknown> | string, value?: string): void {
    const input = typeof a === "string" ? { [a]: value } : a;
    app.act(t("web-pages.addProfile.editAction"), () => core().call("profile.flow.edit", { station: address, form, input }));
  }
  useEffect(() => {
    app.act(t("web-pages.addProfile.openAction"), () => core().call("profile.flow.open", { station: address, form }));
  }, [address, form]);
  useEffect(() => () => {
    void (async () => { try { await core().call("profile.flow.drop", { station: address, form }); } catch { /* gone with the page */ } })();
  }, [address, form]);
  const d = topic.value;
  const submitting = useDoing("profile.flow.submit", { station: address, form });
  const [login, setLogin] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const pending = login != null ? s?.overview?.logins?.find((it) => it.id === login) : undefined;
  const go = (id: string, text: string) => { app.toast = text; app.replace({ kind: "Profile", address, profile: id }); };
  // The sign-in made its profile: on to it.
  useEffect(() => {
    if (pending?.created != null) go(pending.created, t("android-settings.profile.addedLogin"));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pending?.created]);
  const runtime = d?.tile?.runtime === "codex" ? "codex" : "claude";
  // A plan's sign-in starts when it is chosen; leaving before it made its profile leaves nothing behind.
  const planning = d?.step === "connect" && d.method === "plan";
  useEffect(() => {
    if (!planning) return;
    // Kotlin's LaunchedEffect is cancelled when `planning` changes: what comes after is not taken.
    let gone = false;
    setError(null);
    api.newLogin(runtime).then((id) => { if (!gone) setLogin(id); }, (e: unknown) => { if (!gone) setError(message(e)); });
    return () => { gone = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [planning]);
  const dropLogin = () => {
    const l = login;
    if (l != null && pending?.created == null) void (async () => { try { await api.dropLogin(l); } catch { /* nothing left to drop */ } })();
    setLogin(null);
  };
  const leave = () => { if (d != null && d.step !== "pick") { dropLogin(); edit("provider", ""); } else app.pop(); };
  // BackHandler { leave() }: the latest `leave`, the handler set once.
  const leaving = useRef(leave);
  leaving.current = leave;
  useEffect(() => {
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { leaving.current(); return true; });
    return () => sub.remove();
  }, []);
  const job = pending?.job;
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back={d != null && d.step !== "pick" ? t("web-mobile.profiles.pick") : t("common.cancel")}
        onBack={leave}
        title={d?.title ?? t("android-settings.profile.add")}
        sub={<T size={11} color={C.muted}>{s?.name ?? ""}</T>}
      />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom + 30, paddingHorizontal: 18, paddingTop: 8, gap: 12 }}>
        {d == null
          ? <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={topic.error?.message} />
          : d.step === "pick"
            ? (
              <>
                <T size={13} color={C.muted}>{d.hint}</T>
                {/* The machine's own logins not used yet: a profile on one needs no sign-in. */}
                {s?.overview != null && (
                  <MachineLoginOffers station={address} overview={s.overview} inset={0} onLogin={(rt) => edit({ provider: rt === "claude" ? "anthropic" : "openai", method: "plan" })} />
                )}
                {d.groups.map((g) => (
                  <View key={g.id} style={{ gap: 12 }}>
                    <T size={13} color={C.muted} style={{ paddingLeft: 6, paddingTop: 6 }}>{g.title}</T>
                    <Smooth radius={16} style={{ alignSelf: "stretch", backgroundColor: C.surface }}>
                      {g.providers.map((p) => (
                        <ListRow key={p.id} onClick={() => edit("provider", p.id)}>
                          <ProviderMark runtime={p.runtime ?? "claude"} kind={p.kind ? p.kind : "api-provider"} size={18} mark={p.mark} />
                          <T size={15} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{p.name}</T>
                          <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
                        </ListRow>
                      ))}
                    </Smooth>
                  </View>
                ))}
              </>
            )
            : d.step === "method"
              ? (
                <Smooth radius={16} style={{ alignSelf: "stretch", backgroundColor: C.surface }}>
                  {d.choices.map((c) => (
                    <PickRow
                      key={c.id}
                      label={c.title}
                      sub={c.hint}
                      leading={<ProviderMark runtime={runtime} kind={c.id === "plan" ? "subscription" : d.tile?.kind ?? "api-provider"} size={18} mark={d.tile?.mark} />}
                      onClick={() => edit("method", c.id)}
                    />
                  ))}
                </Smooth>
              )
              : d.method === "plan"
                ? (
                  <>
                    {error != null || job?.state === "failed" || job?.state === "cancelled"
                      ? (
                        <>
                          <T size={13} color={C.red}>{error ?? job?.error ?? t("android-settings.login.unfinished")}</T>
                          <Start>
                            <Button
                              label={t("android-settings.login.restart")}
                              primary={false}
                              onClick={() => {
                                dropLogin(); setError(null);
                                void (async () => { try { setLogin(await api.newLogin(runtime)); } catch (e) { setError(message(e)); } })();
                              }}
                            />
                          </Start>
                        </>
                      )
                      : (
                        <LoginSteps
                          job={job}
                          provider={runtime === "claude" ? "Claude" : "ChatGPT"}
                          send={async (code) => { const l = login; if (l == null) return; await api.newLoginCode(l, code); }}
                        />
                      )}
                    {d.usesLine !== "" && <T size={13} color={C.muted}>{d.usesLine}</T>}
                  </>
                )
                : (
                  // What is typed is kept per provider (Kotlin's remember(d.tile?.id)): a new one starts its form anew.
                  <ConnectForm
                    key={d.tile?.id ?? ""}
                    d={d}
                    edit={(key, value) => edit(key, value)}
                    busy={submitting}
                    submit={() => {
                      void (async () => {
                        try {
                          const response = await core().call("profile.flow.submit", { station: address, form }) as { id: string };
                          go(String(response.id), t("android-settings.profile.verifiedAdded"));
                        } catch { /* the form says what went wrong */ }
                      })();
                    }}
                  />
                )}
      </ScrollView>
    </View>
  );
}

/** The form of a key: what is typed is kept here as it is typed (the core has it as it is named, and judges it). */
function ConnectForm({ d, edit, busy, submit }: { d: ProfileFlowView; edit: (key: string, value: string) => void; busy: boolean; submit: () => void }) {
  const C = useC();
  const [endpoint, setEndpoint] = useState(d.endpoint);
  const [key, setKey] = useState(d.key);
  const note = d.error ?? d.keyHint;
  return (
    <>
      {d.showEndpoint && (
        <>
          <T size={13} weight="600" color={C.ink}>{t("common.provider.endpoint")}</T>
          <Smooth radius={12} stroke={{ width: 1, color: C.line }} style={{ alignSelf: "stretch", backgroundColor: C.surface, paddingHorizontal: 12, paddingVertical: 10 }}>
            {endpoint === "" && (
              <T size={15} color={C.subtle} mono numberOfLines={1} style={{ position: "absolute", left: 12, right: 12, top: 10 }}>{d.tile?.endpointExample ?? "https://"}</T>
            )}
            <TextInput
              value={endpoint}
              onChangeText={(it) => { const v = it.trim(); setEndpoint(v); edit("endpoint", v); }}
              multiline={false}
              autoCapitalize="none"
              cursorColor={C.accent}
              selectionColor={withAlpha(C.accent, 0.4)}
              style={{ alignSelf: "stretch", color: C.ink, fontSize: 15, lineHeight: 21, fontFamily: CODE_FONT, padding: 0, includeFontPadding: false }}
            />
          </Smooth>
          {d.endpointHint != null && <T size={12} color={C.muted}>{d.endpointHint}</T>}
        </>
      )}
      {(d.regions?.length ?? 0) > 1 && (
        <>
          <T size={13} weight="600" color={C.ink}>{t("web-mobile.profiles.region")}</T>
          <Smooth radius={16} style={{ alignSelf: "stretch", backgroundColor: C.surface }}>
            {(d.regions ?? []).map((r) => <PickRow key={r.id} label={r.label} checked={r.id === d.region} onClick={() => edit("region", r.id)} />)}
          </Smooth>
        </>
      )}
      {d.protocols.length > 1 && (
        <>
          <T size={13} weight="600" color={C.ink}>{t("web-mobile.profiles.protocol")}</T>
          <Smooth radius={16} style={{ alignSelf: "stretch", backgroundColor: C.surface }}>
            {d.protocols.map((p) => <PickRow key={p.id} label={p.label} checked={p.id === d.protocol} onClick={() => edit("protocol", p.id)} />)}
          </Smooth>
        </>
      )}
      {d.showKey && (
        <>
          <T size={13} weight="600" color={C.ink}>{d.keyLabel}</T>
          <SecretField value={key} onChange={(it: string) => { setKey(it); edit("key", it); }} placeholder={t("android-settings.profile.keyPlaceholder")} />
          {note != null && <T size={12} color={d.error != null ? C.red : C.muted}>{note}</T>}
        </>
      )}
      <View style={{ alignSelf: "stretch", flexDirection: "row", justifyContent: "flex-end" }}>
        <Button label={d.submitLabel} primary busy={busy || d.pending} enabled={d.canSubmit} onClick={() => submit()} />
      </View>
      {d.usesLine !== "" && <T size={13} color={C.muted}>{d.usesLine}</T>}
    </>
  );
}

/**
 * The accounts this station machine's own Claude Code and Codex are signed in with and no profile uses yet (the station
 * reads them), each with its plan beside its runtime, its state and allowance: one kept in a file is used as it is (a
 * profile on the machine's login, no sign-in); one only in the keychain is signed in again for still.fail; a refused one is
 * only said so. `inset`: the list's side margin (none inside a padded page). On the new-profile page (`onLogin`) the
 * profile made takes its place, and signing in again picks that runtime's subscription there.
 */
export function MachineLoginOffers({ station, overview, inset = 12, onLogin }: { station: string; overview: Overview; inset?: number; onLogin?: ((runtime: string) => void) | null }) {
  const C = useC();
  const offers = (overview.machineLogins ?? []).filter((it) => it.offered === true);
  if (offers.length === 0) return null;
  return (
    <>
      <T size={13} color={C.muted} style={{ paddingLeft: inset + 12, paddingRight: inset + 12, paddingTop: 8, paddingBottom: 4 }}>{t("android-settings.machine.title")}</T>
      <View style={{ alignSelf: "stretch", paddingHorizontal: inset, paddingBottom: 10 }}>
        <Smooth radius={16} style={{ backgroundColor: C.surface }}>
          {offers.map((l) => (
            <MachineLoginOffer
              key={l.runtime}
              station={station}
              l={l}
              onUse={() => {
                if (l.usable === true) {
                  void (async () => {
                    try {
                      const id = await app.api(station).useMachineLogin(l.runtime);
                      app.toast = t("android-settings.machine.added");
                      if (onLogin != null) app.replace({ kind: "Profile", address: station, profile: id });
                      else app.push({ kind: "Profile", address: station, profile: id });
                    } catch (e) { app.toast = message(e); }
                  })();
                } else if (onLogin != null) onLogin(l.runtime);
                else app.push({ kind: "NewProfile", station });
              }}
            />
          ))}
        </Smooth>
      </View>
    </>
  );
}

/** One offer of MachineLoginOffers: what it set going under way, asked per login (a hook, so a component of its own). */
function MachineLoginOffer({ station, l, onUse }: { station: string; l: MachineLogin; onUse: () => void }) {
  const busy = useDoing("profile.useMachineLogin", { station, runtime: l.runtime });
  return <MachineLoginRow l={l} busy={busy} onUse={onUse} />;
}

/** A machine login as a profile could be made with it: its runtime and plan, a dot and its state, who, its allowance; and what to do. */
function MachineLoginRow({ l, busy, onUse }: { l: MachineLogin; busy: boolean; onUse: () => void }) {
  const C = useC();
  const blocked = l.quota?.state === "blocked";
  const plan = l.plan != null ? l.plan.charAt(0).toUpperCase() + l.plan.slice(1) : null;
  const trouble = quotaTrouble(l.quota);
  return (
    <ListRow>
      <ProviderMark runtime={l.runtime} kind="subscription" size={18} />
      <View style={{ flex: 1, minWidth: 0, gap: 2 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="clip" style={{ flexShrink: 1 }}>{MACHINE_RUNTIME[l.runtime] ?? l.runtime}</T>
          {plan != null && <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="clip" style={{ flexShrink: 1 }}>{plan}</T>}
        </View>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 5 }}>
          <StateDot color={blocked ? C.red : C.green} size={6} />
          <T size={12} color={blocked ? C.red : C.muted}>{blocked ? t("android-settings.quota.blocked") : t("android-settings.machine.signedIn")}</T>
          <T size={12} color={C.muted} numberOfLines={1} style={{ flexShrink: 1 }}>{`· ${l.email ?? t("android-settings.machine.someone")}`}</T>
        </View>
        {trouble != null && <T size={12} color={blocked ? C.red : C.muted}>{trouble}</T>}
      </View>
      <QuotaRings quota={l.quota} />
      {/* A refused account is said so, with nothing to do with it here. */}
      {!blocked && (busy
        ? <Spinner />
        : (
          <Pressable android_ripple={{ color: withAlpha(C.ink, 0.1) }} onPress={onUse}>
            <T size={14} color={C.accent}>{l.usable === true ? t("android-settings.machine.use") : t("android-settings.login.signIn")}</T>
          </Pressable>
        ))}
    </ListRow>
  );
}
