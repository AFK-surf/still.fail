// Settings on a narrow screen, one page from the gear on Home (as the Android app has it, apps/android/…/screens/
// SettingsHome.kt): who is signed in, then the workspace's (its people, stations, connects, profiles, memory), then this
// device's (how it looks, whether it notifies, whether it sends usage statistics), then still.fail's terms and privacy
// policy. Each row says how things stand at its end, what is wrong in red, so the page is worth a look before anything
// is opened.
import { useState, type ReactNode } from "react";
import { useDoing } from "../doing.ts";
import { useStations, useConnects } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import { useLock } from "../cloud/Security.tsx";
import { useVaults, vaultStatus } from "../vault.ts";
import { ArrowUpRight, ChevronRight } from "@stillfail/ui/icons.tsx";
import { useAppearance, useMotionSetting, type Appearance } from "../theme.ts";
import { CAN_NOTIFY, setNotify, useNotifyState } from "../notify.ts";
import { HAS_TELEMETRY, setTelemetry, useTelemetryOn } from "../telemetry.ts";
import { legalPages, legalUrl } from "../pages/About.tsx";
import { NAME } from "../channel.ts";
import { useApp } from "./app.tsx";
import { t } from "../i18n.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useChangelog } from "../changelog.ts";
import { standalone } from "../standalone.ts";
import { download, downloadsOffered, onAndroid } from "../downloads.ts";
import { Presence } from "./Connects.tsx";
import { FontRows } from "./Fonts.tsx";
import { railLabel } from "../Rail.tsx";
import { useBars, type BarPlace } from "./Bar.tsx";
import { Avatar, Card, LargeTitle, ListCard, ListRow, SectionHeader, Seg, TopBack } from "./parts.tsx";
import { Spinner } from "@stillfail/ui/waiting.tsx";
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
  const language = usePrefs((p) => p.language) ?? null;
  const bars = useBars();
  const lock = useLock(app.entry.id);
  const vault = vaultStatus(useVaults(app.entry.id));
  const at = (path: string) => () => app.push(app.at(path));
  const under = app.under();
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      {/* Back to the place it was opened from (the gear of each place's head). */}
      <TopBack label={under && under !== "chats" ? railLabel(under) : t("web-mobile.nav.chats")} onBack={app.pop} />
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
        {lock?.available && <GoRow title={t("web-pages.security.title")} bad={lock.attention > 0} value={lock.locked ? (lock.attention > 0 ? t("web-mobile.settings.securityWaiting", { n: lock.attention }) : t("web-mobile.settings.securityOn")) : t("web-mobile.settings.securityOff")} onClick={at("/settings/security")} />}
        <GoRow title={t("web-pages.vault.title")} bad={vault?.bad ?? false} value={vault?.text} onClick={at("/settings/vault")} />
        <GoRow title="Station" value={stations ? <>{troubled && <Presence state="error" />}{t("web-mobile.settings.stationsOnline", { online, n: stations.length })}</> : undefined} onClick={at("/settings/stations")} />
        <GoRow title={t("web-mobile.settings.connects")} bad={failing > 0} value={connects ? (failing ? t("web-mobile.settings.connectsFailing", { n: failing }) : t("web-mobile.settings.connectsCount", { n: connects.items.length })) : undefined} onClick={at("/settings/connects")} />
        <GoRow title="Profile" bad={short > 0} value={stations ? (short ? t("web-mobile.settings.profilesShort", { n: short }) : t("web-mobile.settings.profilesCount", { n: profiles.length })) : undefined} onClick={at("/settings/profiles")} />
        <GoRow title={t("web-pages.archiving.title")} onClick={at("/settings/archive")} />
        <GoRow title={t("web-pages.automaticDecisions.title")} onClick={at("/settings/automatic-decisions")} />
        <GoRow title={t("web-mobile.settings.memory")} onClick={at("/settings/memory")} />
        <GoRow title={t("web-mobile.settings.usage")} onClick={at("/settings/usage")} />
      </ListCard>
      <SectionHeader title={t("web-mobile.settings.device")} start={24} />
      <ListCard>
        <GoRow title={t("web-mobile.settings.appearance.title")} value={themes().find(([v]) => v === appearance)?.[1]} onClick={at("/settings/appearance")} />
        <GoRow title={t("web-mobile.bar.title")} value={bars.sets.length > 1 ? t("web-mobile.bar.count", { n: bars.sets.length }) : bars.sets[0]!.map((k) => railLabel(k as BarPlace)).join("、")} onClick={at("/settings/bar")} />
        <GoRow title={t("common.language")} value={languages().find(([v]) => v === language)?.[1]} onClick={at("/settings/language")} />
        <Notify />
        <Telemetry />
        <GoRow title={t("web-mobile.settings.changelog")} value={build != null ? `0.1.${build}` : undefined} onClick={at("/settings/changelog")} />
        {/* On an Android phone's browser, this channel's app. */}
        {downloadsOffered() && onAndroid() && <GoRow title={t("web-mobile.settings.downloadAndroid")} onClick={() => { location.href = download("android"); }} />}
        {/* An app on the home screen has no browser round it to reload the page: here it can. */}
        {standalone() && <ListRow onClick={() => location.reload()}><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("common.reload")}</span></ListRow>}
      </ListCard>
      {/* On still.fail's site, in a tab of their own. */}
      <SectionHeader title={t("web-pages.settings.nav.about")} start={24} />
      <ListCard>
        {legalPages().map(([page, label]) => (
          <ListRow key={page} onClick={() => { window.open(legalUrl(page), "_blank", "noopener"); }}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{label}</span>
            <ArrowUpRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        ))}
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
      {busy && <Spinner inline />}
      <span className={connectsCss.mSwitch} data-on={on || undefined} />
    </ListRow>
  );
}

/** Whether this browser sends usage statistics and error reports (telemetry.ts); none to send in a build without PostHog. */
function Telemetry() {
  const sending = useTelemetryOn();
  if (!HAS_TELEMETRY) return null;
  return (
    <ListRow onClick={() => setTelemetry(!sending)}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{t("common.telemetry.title")}</span>
        <span className={listsCss.mRowNote}>{t("common.telemetry.note", { name: NAME })}</span>
      </span>
      <span className={connectsCss.mSwitch} data-on={sending || undefined} />
    </ListRow>
  );
}

/** How this device shows still.fail: its theme, its motion and its fonts (the wide screen's 外观 page has the same). */
export function AppearanceScreen() {
  const app = useApp();
  const [appearance, setAppearance] = useAppearance();
  const [motion, setMotion] = useMotionSetting();
  const motions = [["system", t("web-pages.appearance.motion.system")], ["reduce", t("web-pages.appearance.motion.reduce")], ["full", t("web-pages.appearance.motion.full")]] as const;
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-mobile.settings.appearance.title")} />
      <SectionHeader title={t("web-mobile.settings.appearance.theme")} start={24} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={themes().map(([, label]) => label)} selected={Math.max(0, themes().findIndex(([v]) => v === appearance))}
          onSelect={(i) => setAppearance(themes()[i]![0])} height={34} fill />
      </div>
      <FontRows />
      <SectionHeader title={t("web-pages.appearance.motion.title")} start={24} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={motions.map(([, label]) => label)} selected={Math.max(0, motions.findIndex(([v]) => v === motion))}
          onSelect={(i) => setMotion(motions[i]![0])} height={34} fill />
      </div>
      <div className={css.mSegNote}>{t("web-pages.appearance.motion.description")}</div>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Which language still.fail speaks on this device: as the device does, or one chosen (prefs `language`). */
export function LanguageScreen() {
  const app = useApp();
  const language = usePrefs((p) => p.language) ?? null;
  const bars = useBars();
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
