// The settings' list, one for every screen (docs/ui-panels.md 设置的目录; the app's is apps/mbui
// src/sfpages/settings_list.mbt): the wide screen's sidebar beside the settings' pages (cloud/settings.tsx SettingsNav)
// and the narrow screen's settings page (mobile/Settings.tsx SettingsScreen) draw the same rows in the same groups and
// order. Who is signed in and the workspace in view; then the workspace's, in small groups (who may reach what:
// security mode and the vault; where its agents run: its stations, connects and profiles; how its agents work: what
// they decide by themselves, what they remember, when chats are archived, what they used); then this device's (how it
// looks, whether it notifies, its bottom bar on a phone, its keys, the desktop app's own station); then 关于. Each row
// says how things stand at its end, what is wrong in red. Station, 连接, Profile and 用量 are rows wherever the rail has
// them too: the settings are one more way to them, not where they live (the user, 2026-10-15). What another page holds
// (更新日志 in 关于, the system's permission on 通知's page) is not a row of its own.
import type { ComponentType } from "react";
import { Archive, Bell, Brain, Chart, Check, Command, Im, Info, Key, Monitor, Quota, Server, ShieldCheck, Sliders, User, Users, ViewColumns, type IconProps } from "@stillfail/ui/icons.tsx";
import { useConnects, useProfiles, useStations } from "./api.ts";
import { useWorkspace } from "./cloud/api.ts";
import { useLock } from "./cloud/Security.tsx";
import type { WorkspaceEntry } from "./cloud/workspace.tsx";
import { useVaults } from "./vault.ts";
import { useAppearance } from "./theme.ts";
import { CAN_NOTIFY, useNotifyState } from "./notify.ts";
import { CHANGEABLE } from "./keymap.ts";
import { HAS_LOCAL_STATION } from "./pages/LocalStation.tsx";
import { useChangelog } from "./changelog.ts";
import { t } from "./i18n.ts";

/** A row of the settings' list: where it goes (under the workspace's /settings), its key, what it is by (an icon; the
 *  account's picture, `who: "person"`; the workspace's mark, `who: "space"`), its name, the line under it on a card,
 *  how things stand at its end (`bad` in red; `dot`, a red dot before it: something there is not right, nothing wrong
 *  to say). */
export interface SettingsRow {
  key: string;
  path: string;
  icon: ComponentType<IconProps>;
  who?: "person" | "space";
  title: string;
  line?: string | undefined;
  value?: string | undefined;
  bad?: boolean | undefined;
  dot?: boolean | undefined;
}

/** A group of the list's rows, a heading over it where it has one. */
export interface SettingsPart {
  heading?: string;
  rows: SettingsRow[];
}

/** The theme's words (light, dark, the system's). */
function themeWords(appearance: string): string {
  return appearance === "light" ? t("web-mobile.settings.appearance.light") : appearance === "dark" ? t("web-mobile.settings.appearance.dark") : t("web-mobile.settings.appearance.system");
}

/**
 * The settings' list as it stands, in its order. `phone`: the narrow screen's (a phone's browser), which has a bottom
 * bar (`bars`: what its row says of it) and no keys to change; the wide screen's has its keys, and the desktop app its
 * own station.
 */
export function useSettingsList(entry: WorkspaceEntry, phone: boolean, bars?: string): SettingsPart[] {
  const me = entry.account;
  const view = useWorkspace(entry.id).value;
  const stations = useStations(entry.id).value;
  const connects = useConnects(entry.id).value;
  const profiles = useProfiles(entry.id).value;
  const lock = useLock(entry.id);
  const vaults = useVaults(entry.id);
  const [appearance] = useAppearance();
  const notify = useNotifyState();
  const build = useChangelog().value?.build;
  const manager = view?.role === "owner" || view?.role === "admin";
  const waiting = view ? view.added.length + view.invitations.length : 0;
  const online = stations?.filter((s) => s.online).length ?? 0;
  const failing = connects?.items.filter((i) => i.connect.presence === "error").length ?? 0;
  const roleWords = view ? (t(`web-pages.roles.${view.role}`)) : "";
  const people = view ? (manager && waiting ? t("web-mobile.settings.membersWaiting", { n: view.members.length, waiting }) : t("web-mobile.settings.members", { n: view.members.length })) : "";
  const parts: SettingsPart[] = [];
  parts.push({
    rows: [
      { key: "account", path: "account", icon: User, who: "person", title: me.name || me.email, line: me.email },
      { key: "workspace", path: "workspace", icon: Users, who: "space", title: view?.name ?? entry.name, line: [roleWords, people].filter(Boolean).join(" · ") },
    ],
  });
  // who may reach what: security mode where the workspace has it, and the vault
  const access: SettingsRow[] = [];
  // (still being read: a row already, so it does not push the rest down as it comes; none here: null)
  if (lock === undefined || lock?.available) {
    access.push({
      key: "security", path: "security", icon: ShieldCheck, title: t("web-pages.security.title"), bad: (lock?.attention ?? 0) > 0,
      value: !lock ? undefined : !lock.locked ? t("web-mobile.settings.securityOff") : lock.attention > 0 ? t("web-mobile.settings.securityWaiting", { n: lock.attention }) : t("web-mobile.settings.securityOn"),
    });
  }
  access.push({ key: "vault", path: "vault", icon: Key, title: t("web-pages.vault.title"), value: vaults?.statusText ?? undefined, bad: vaults?.statusBad === true });
  parts.push({ rows: access });
  // where its agents run: its stations, the chats' ways in, the agents' accounts
  parts.push({
    rows: [
      { key: "stations", path: "stations", icon: Server, title: "Station", value: stations ? t("web-mobile.settings.stationsOnline", { online, n: stations.length }) : undefined, dot: stations ? online < stations.length : false },
      { key: "connects", path: "connects", icon: Im, title: t("web-mobile.settings.connects"), bad: failing > 0, value: connects ? (failing ? t("web-mobile.settings.connectsFailing", { n: failing }) : t("web-mobile.settings.connectsCount", { n: connects.items.length })) : undefined },
      // (as many as their list has, those that need a look as the core counts them)
      { key: "profiles", path: "profiles", icon: Quota, title: "Profile", bad: (profiles?.attention ?? 0) > 0, value: profiles ? (profiles.attention ? t("web-mobile.settings.profilesShort", { n: profiles.attention }) : t("web-mobile.settings.profilesCount", { n: profiles.items.length })) : undefined },
    ],
  });
  // how its agents work
  parts.push({
    rows: [
      { key: "automatic-decisions", path: "automatic-decisions", icon: Check, title: t("web-pages.automaticDecisions.title") },
      { key: "memory", path: "memory", icon: Brain, title: t("web-mobile.settings.memory") },
      { key: "archive", path: "archive", icon: Archive, title: t("web-pages.archiving.title") },
      { key: "usage", path: "usage", icon: Chart, title: t("web-mobile.settings.usage") },
    ],
  });
  // this device's: what there is of it here
  const device: SettingsRow[] = [{ key: "appearance", path: "appearance", icon: Sliders, title: t("web-mobile.settings.appearance.title"), value: themeWords(appearance) }];
  if (CAN_NOTIFY) {
    device.push({
      key: "notifications", path: "notifications", icon: Bell, title: t("web-pages.settings.nav.notifications"), bad: notify === "denied",
      value: notify === "denied" ? t("web-pages.permissions.state.denied") : notify === "on" ? t("web-pages.notifications.on") : t("web-pages.notifications.off"),
    });
  }
  if (phone) device.push({ key: "bar", path: "bar", icon: ViewColumns, title: t("web-mobile.bar.title"), value: bars });
  if (!phone && CHANGEABLE) device.push({ key: "shortcuts", path: "shortcuts", icon: Command, title: t("web-pages.settings.nav.shortcuts") });
  if (!phone && HAS_LOCAL_STATION) device.push({ key: "local-station", path: "local-station", icon: Monitor, title: t("web-pages.localStation.title") });
  parts.push({ heading: t("web-mobile.settings.device"), rows: device });
  // 关于: this build
  parts.push({ rows: [{ key: "about", path: "about", icon: Info, title: t("web-pages.settings.nav.about"), value: build != null ? `0.1.${build}` : undefined }] });
  return parts;
}
