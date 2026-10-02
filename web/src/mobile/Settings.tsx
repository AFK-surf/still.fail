// Settings on a narrow screen, one page from the gear on Home (as the Android app has it, apps/android/…/screens/
// SettingsHome.kt): who is signed in, then the workspace's (its people, stations, connects, profiles, memory), then this
// device's (how it looks, whether it notifies). Each row says how things stand at its end, what is wrong in red, so the
// page is worth a look before anything is opened.
import { useState, type ReactNode } from "react";
import { useDoing } from "../doing.ts";
import { useStations, useConnects } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import { ChevronRight } from "../icons.tsx";
import { useAppearance, type Appearance } from "../theme.ts";
import { CAN_NOTIFY, setNotify, useNotifyState } from "../notify.ts";
import { useApp } from "./app.tsx";
import { t } from "../i18n.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useChangelog } from "../changelog.ts";
import { Presence } from "./Connects.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, Seg, Spinner, TopBack } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as css from "./Settings.css.ts";

export function themes(): [Appearance, string][] {
  return [["system", t("web-mobile.settings.appearance.system")], ["light", t("web-mobile.settings.appearance.light")], ["dark", t("web-mobile.settings.appearance.dark")]];
}

/** The languages to choose from: as the device is (null), or one. */
export function languages(): ["zh" | "en" | null, string][] {
  return [[null, t("common.language.system")], ["zh", t("common.language.zh")], ["en", t("common.language.en")]];
}

/** A row that opens a page: its name, how things stand (`bad` in red), a chevron. */
export function GoRow({ title, value, bad = false, lead, onClick }: { title: string; value?: ReactNode; bad?: boolean; lead?: ReactNode; onClick: () => void }) {
  return (
    <ListRow onClick={onClick}>
      {lead}
      <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{title}</span>
      {value !== undefined && <span className={`${css.mValue} ${bad ? partsCss.mRed : ""}`}>{value}</span>}
      <ChevronRight size={14} className={partsCss.mSubtle} />
    </ListRow>
  );
}

export function SettingsScreen() {
  const app = useApp();
  const me = app.entry.account;
  const view = useWorkspace(app.entry.id).value;
  const stations = useStations(app.entry.id).value;
  const connects = useConnects(app.entry.id).value;
  const [appearance] = useAppearance();
  const build = useChangelog().value?.build;
  const manager = view?.role === "owner" || view?.role === "admin";
  const waiting = view ? view.added.length + view.invitations.length : 0;
  const online = stations?.filter((s) => s.online).length ?? 0;
  const troubled = stations?.some((s) => !s.online) ?? false;
  const failing = connects?.items.filter((i) => i.connect.presence === "error").length ?? 0;
  const profiles = stations?.flatMap((s) => s.overview?.profiles ?? []) ?? [];
  const short = profiles.filter((p) => p.trouble != null).length;
  const language = usePrefs().language ?? null;
  const at = (path: string) => () => app.push(app.at(path));
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.nav.chats")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-mobile.settings.title")} />
      <Card onClick={at("/settings/account")}>
        <span className={css.mMe}>
          <Avatar id={me.email} name={me.name || me.email} size={46} picture={me.picture} />
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><b>{me.name || me.email}</b><span className={listsCss.mRowNote}>{me.email}</span></span>
          <ChevronRight size={14} className={partsCss.mSubtle} />
        </span>
      </Card>
      <SectionHeader title={view ? t("web-mobile.settings.workspaceRole", { workspace: view.name, role: ROLE_LABEL[view.role] }) : app.entry.name} start={24} />
      <ListCard>
        <GoRow title="Workspace" value={view ? (manager && waiting ? t("web-mobile.settings.membersWaiting", { n: view.members.length, waiting }) : t("web-mobile.settings.members", { n: view.members.length })) : undefined} onClick={at("/settings/workspace")} />
        <GoRow title="Station" value={stations ? <>{troubled && <Presence state="error" />}{t("web-mobile.settings.stationsOnline", { online, n: stations.length })}</> : undefined} onClick={at("/settings/stations")} />
        <GoRow title={t("web-mobile.settings.connects")} bad={failing > 0} value={connects ? (failing ? t("web-mobile.settings.connectsFailing", { n: failing }) : t("web-mobile.settings.connectsCount", { n: connects.items.length })) : undefined} onClick={at("/settings/connects")} />
        <GoRow title="Profile" bad={short > 0} value={stations ? (short ? t("web-mobile.settings.profilesShort", { n: short }) : t("web-mobile.settings.profilesCount", { n: profiles.length })) : undefined} onClick={at("/settings/profiles")} />
        <GoRow title="自动决策" onClick={at("/settings/automatic-decisions")} />
        <GoRow title={t("web-mobile.settings.memory")} onClick={at("/settings/memory")} />
        <GoRow title={t("web-mobile.settings.usage")} onClick={at("/settings/usage")} />
      </ListCard>
      <SectionHeader title={t("web-mobile.settings.device")} start={24} />
      <ListCard>
        <GoRow title={t("web-mobile.settings.appearance.title")} value={themes().find(([v]) => v === appearance)?.[1]} onClick={at("/settings/appearance")} />
        <GoRow title={t("common.language")} value={languages().find(([v]) => v === language)?.[1]} onClick={at("/settings/language")} />
        <Notify />
        <GoRow title={t("web-mobile.settings.changelog")} value={build != null ? `0.1.${build}` : undefined} onClick={at("/settings/changelog")} />
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Whether this browser tells about the chats (notify.ts). */
function Notify() {
  const app = useApp();
  const state = useNotifyState();
  // What was asked shows at once, with a spinner, while the browser asks for leave and the core answers (`notify.set`);
  // then how it is, and a word if that is not what was asked.
  const [asked, setAsked] = useState<boolean | null>(null);
  const setting = useDoing("notify.set");
  if (!CAN_NOTIFY) return null;
  const busy = asked !== null || setting;
  const on = asked ?? state === "on";
  const note = state === "denied" ? t("web-mobile.settings.notify.denied") : t("web-mobile.settings.notify.note");
  return (
    <ListRow onClick={busy ? undefined : () => {
      if (state === "denied" || state === "unsupported") return;
      const want = state !== "on";
      setAsked(want);
      setNotify(want).then((now) => {
        if (now === "denied") app.toast(t("web-mobile.settings.notify.notAllowed"));
        else if ((now === "on") !== want) app.toast(t(want ? "web-mobile.settings.notify.onFailed" : "web-mobile.settings.notify.offFailed"));
      }, (e: unknown) => app.toast(t(want ? "web-mobile.settings.notify.onFailedWhy" : "web-mobile.settings.notify.offFailedWhy", { error: e instanceof Error ? e.message : String(e) }))).finally(() => setAsked(null));
    }}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{t("web-mobile.settings.notify.title")}</span>
        <span className={listsCss.mRowNote}>{note}</span>
      </span>
      {busy && <Spinner size={14} />}
      <span className={connectsCss.mSwitch} data-on={on || undefined} />
    </ListRow>
  );
}

/** How this device shows still.fail: its theme. */
export function AppearanceScreen() {
  const app = useApp();
  const [appearance, setAppearance] = useAppearance();
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-mobile.settings.appearance.title")} />
      <SectionHeader title={t("web-mobile.settings.appearance.theme")} start={24} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={themes().map(([, label]) => label)} selected={Math.max(0, themes().findIndex(([v]) => v === appearance))}
          onSelect={(i) => setAppearance(themes()[i]![0])} height={34} fill />
      </div>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Which language still.fail speaks on this device: as the device does, or one chosen (prefs `language`). */
export function LanguageScreen() {
  const app = useApp();
  const language = usePrefs().language ?? null;
  const options = languages();
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("common.language")} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={options.map(([, label]) => label)} selected={Math.max(0, options.findIndex(([v]) => v === language))}
          onSelect={(i) => setPrefs({ language: options[i]![0] })} height={34} fill />
      </div>
      <div style={{ height: 30 }} />
    </div>
  );
}
