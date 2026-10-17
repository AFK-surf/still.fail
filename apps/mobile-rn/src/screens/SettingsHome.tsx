// Settings, one page from the gear on Home, as the narrow web has it (web/src/mobile/Settings.tsx): who is signed in,
// then the workspace's (its people, stations, connects, profiles, memory), then this device's (how it looks, whether it
// notifies, this build). Each row says how things stand at its end, what is wrong in red, so the page is worth a look
// before anything is opened. And how this device shows still.fail (外观). The Android app's screens/SettingsHome.kt.
import Constants from "expo-constants";
import { useContext, useEffect, useState } from "react";
import { ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { ConnectsView, LockView, StationView } from "../../../../web/src/core/shapes.ts";
import { LocalApp, useApp } from "../AppState";
import { APP_NAME } from "../build";
import { ROLE_LABEL, type WorkspaceEntry, type WorkspaceView } from "../data/Accounts";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { rememberNotificationAsk } from "../Notices";
import { LocalWide } from "../ui/ChatInk";
import { fileSize } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, Seg } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { Spinner } from "../ui/Waiting";
import { barsValue } from "./BarSettings";
import { Switch } from "./Connects";
import { KeptFiles } from "./KeptFiles";
import { GoRow } from "./SettingParts";
import { TopBack } from "./Stations";
import { VaultSettingsRow } from "./Vault";

const themes = (): [string, string][] => [["system", t("android-settings.theme.system")], ["light", t("android-settings.theme.light")], ["dark", t("android-settings.theme.dark")]];

/** The languages to choose: null follows the phone (the core's `language`, client/core-ts/src/prefs.ts). */
const languages = (): [string | null, string][] => [[null, t("common.language.system")], ["zh", t("common.language.zh")], ["en", t("common.language.en")]];

export function SettingsScreen({ current }: { current: WorkspaceEntry }) {
  const app = useContext(LocalApp);
  const C = useC();
  const insets = useSafeAreaInsets();
  const wide = useContext(LocalWide);
  const me = current.account;
  const view = rememberTopic<WorkspaceView>(Topics.workspace(current.workspace.id)).value;
  const stations = rememberTopic<StationView[]>(Topics.stations(current.workspace.id)).value;
  const connects = rememberTopic<ConnectsView>(Topics.connects(current.workspace.id, false)).value;
  const lock = rememberTopic<LockView>(Topics.lock(current.workspace.id)).value;
  const theme = useApp(() => app.theme);
  const bars = useApp(() => barsValue(app));
  const waiting = view ? (view.added ?? []).length + (view.invitations ?? []).length : 0;
  const manager = view?.role === "owner" || view?.role === "admin";
  const online = stations?.filter((s) => s.online).length ?? 0;
  const troubled = stations?.some((s) => !s.online) ?? false;
  const failing = connects?.items.filter((i) => i.connect.presence === "error").length ?? 0;
  const profiles = (stations ?? []).flatMap((s) => s.overview?.profiles ?? []);
  const short = profiles.filter((p) => p.trouble != null).length;
  const name = me.name || me.email;
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.home.back")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("android-settings.title")} />
      <Card onClick={() => app.push({ kind: "Me" })}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 14 }}>
          <Avatar id={me.email} name={name} size={46} picture={me.picture ?? null} />
          <View style={{ flex: 1, minWidth: 0 }}>
            <T size={16} weight="700" color={C.ink} numberOfLines={1}>{name}</T>
            <T size={13} color={C.muted} numberOfLines={1}>{me.email}</T>
          </View>
          <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
        </View>
      </Card>
      <SectionHeader title={view ? t("android-settings.home.workspace", { name: view.name ?? "", role: ROLE_LABEL[view.role ?? "member"] ?? view.role ?? "member" }) : current.workspace.name} start={24} />
      <ListCard>
        <GoRow
          title="Workspace"
          value={view ? (manager && waiting > 0 ? t("android-settings.members.waiting", { n: (view.members ?? []).length, waiting }) : t("android-settings.members.count", { n: (view.members ?? []).length })) : null}
          onClick={() => app.push({ kind: "Workspace" })}
        />
        {lock?.available ? (
          <GoRow
            title={t("web-pages.security.title")}
            value={!lock.locked ? t("web-mobile.settings.securityOff") : lock.attention > 0 ? t("web-mobile.settings.securityWaiting", { n: lock.attention }) : t("web-mobile.settings.securityOn")}
            bad={lock.attention > 0}
            onClick={() => app.push({ kind: "Security" })}
          />
        ) : null}
        <VaultSettingsRow ws={current.workspace.id} />
        <GoRow title="Station" value={stations ? t("android-settings.home.online", { online, total: stations.length }) : null} dot={troubled} onClick={() => app.push({ kind: "Stations" })} />
        <GoRow
          title={t("android-settings.connects.title")}
          value={connects ? (failing > 0 ? t("android-settings.home.failing", { n: failing }) : t("android-settings.count", { n: connects.items.length })) : null}
          bad={failing > 0}
          onClick={() => app.push({ kind: "Connects" })}
        />
        <GoRow
          title="Profile"
          value={stations ? (short > 0 ? t("android-settings.home.short", { n: short }) : t("android-settings.count", { n: profiles.length })) : null}
          bad={short > 0}
          onClick={() => app.push({ kind: "Profiles" })}
        />
        <GoRow title={t("web-pages.automaticDecisions.title")} onClick={() => app.push({ kind: "AutomaticDecisions" })} />
        <GoRow title={t("android-settings.memory")} onClick={() => app.push({ kind: "Memories" })} />
        <GoRow title={t("android-settings.home.usage")} onClick={() => app.push({ kind: "Usage" })} />
      </ListCard>
      <SectionHeader title={t("android-settings.home.device")} start={24} />
      <ListCard>
        <GoRow title={t("android-settings.appearance.title")} value={themes().find(([k]) => k === theme)?.[1] ?? null} onClick={() => app.push({ kind: "Appearance" })} />
        {/* The bottom bar's places (BarSettings): a phone's only, a wide screen has none. */}
        {!wide ? <GoRow title={t("android-misc.bar.title")} value={bars} onClick={() => app.push({ kind: "BarSettings" })} /> : null}
        <KeptFilesRow />
        <Notify />
        <Version />
        <GoRow title={t("android-settings.changelog.title")} onClick={() => app.push({ kind: "Changelog" })} />
      </ListCard>
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

/** What this device keeps (its chats' messages and files, and the rest), how much it takes. */
function KeptFilesRow() {
  const app = useContext(LocalApp);
  const [total, setTotal] = useState<number | null>(null);
  useEffect(() => {
    let live = true;
    KeptFiles.read(app).then((kept: { total: number }) => { if (live) setTotal(kept.total); }, () => undefined);
    return () => { live = false; };
  }, [app]);
  return <GoRow title={t("android-settings.files.title")} value={total != null ? fileSize(total) : null} onClick={() => app.push({ kind: "KeptFiles" })} />;
}

/** Local notices and pushes alike, on this device (Notices, Push); turned on, the system is asked too. */
function Notify() {
  const app = useContext(LocalApp);
  const C = useC();
  const ask = rememberNotificationAsk(app, false);
  const notify = useApp((s) => s.notify);
  // Switched and not answered yet: shown as asked, with a spinner, and not switched again meanwhile.
  const pending = useApp(() => app.isDoing("notify.set"));
  return (
    <ListRow
      onClick={pending ? null : () => {
        const on = !app.notify;
        if (on) ask();
        // NATIVE: this device's pushes (Push.sync: FCM's token to the accounts when the core wants pushes held, gone
        // when not); here only the core is told.
        app.scope.launch(() => app.useNotify(on));
      }}
    >
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} color={C.ink}>{t("android-settings.notify.title")}</T>
        <T size={13} color={C.muted}>{notify ? t("android-settings.notify.on") : t("android-settings.notify.off")}</T>
      </View>
      {pending ? <Spinner /> : null}
      <Switch on={notify} />
    </ListRow>
  );
}

/**
 * This build, and a newer one when still.fail cloud has it: tapped, it is downloaded and installed; with none known yet,
 * tapping asks still.fail cloud again right away.
 */
function Version() {
  const app = useContext(LocalApp);
  const C = useC();
  const updates = app.updates;
  const newer = useApp(() => updates.available);
  const progress = useApp(() => updates.progress);
  const checking = useApp(() => updates.checking);
  useEffect(() => { void app.checkUpdates(); }, [app]);
  const busy = progress != null || checking;
  // The beta app goes by its own name (build.ts APP_NAME).
  const version = Constants.expoConfig?.version ?? "";
  return (
    <ListRow
      onClick={busy ? null : () => {
        (newer == null ? updates.checkNow() : updates.install()).then((said) => { if (said != null) app.toast = said; }, () => undefined);
      }}
    >
      <T size={15} color={C.ink} style={{ flex: 1 }}>{`${APP_NAME} ${version}`}</T>
      <T size={15} color={newer != null && !busy ? C.accent : C.muted}>
        {progress ?? (checking ? t("android-settings.version.checking") : null) ?? (newer != null ? t("android-settings.version.update", { version: newer.versionName }) : t("android-settings.version.check"))}
      </T>
    </ListRow>
  );
}

/** How this device shows still.fail: its theme, and the language it speaks. */
export function AppearanceScreen() {
  const app = useContext(LocalApp);
  const insets = useSafeAreaInsets();
  const theme = useApp(() => app.theme);
  const list = themes();
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.title")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("android-settings.appearance.title")} />
      <SectionHeader title={t("android-settings.appearance.theme")} start={24} />
      <Seg
        options={list.map(([, label]) => label)}
        selected={Math.max(0, list.findIndex(([k]) => k === theme))}
        onSelect={(i: number) => app.useTheme(list[i]![0])}
        style={{ marginHorizontal: 12, alignSelf: "stretch" }}
        height={34}
        fill
      />
      <Language />
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

/**
 * The language things are said in: the phone's (the default), Chinese or English, as the core keeps it (prefs
 * `language`); the core's `lang` then changes the app's words (src/i18n.ts).
 */
function Language() {
  const app = useContext(LocalApp);
  const language = useApp(() => app.language);
  const list = languages();
  return (
    <>
      <SectionHeader title={t("common.language")} start={24} />
      <Seg
        options={list.map(([, label]) => label)}
        selected={Math.max(0, list.findIndex(([k]) => k === language))}
        onSelect={(i: number) => {
          const value = list[i]![0];
          if (value !== app.language) app.setLanguage(value);
        }}
        style={{ marginHorizontal: 12, alignSelf: "stretch" }}
        height={34}
        fill
      />
    </>
  );
}
