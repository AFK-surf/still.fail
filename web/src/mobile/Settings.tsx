// Settings on a narrow screen, one page from the gear on Home (as the Android app has it, apps/android/…/screens/
// SettingsHome.kt): who is signed in and the workspace in view, each a card; then the workspace's in small groups (who
// may do what; its stations and what they run; its agents), then this device's (how it looks, its bar, its language,
// whether it notifies), then 关于 (what changed, whether it sends usage statistics, still.fail's terms and privacy
// policy). Each row has its icon, and says how things stand at its end, what is wrong in red, so the page is worth a
// look before anything is opened.
import { useState, type ReactNode } from "react";
import { useDoing } from "../doing.ts";
import { useStations, useConnects } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import { useLock } from "../cloud/Security.tsx";
import { useVaults } from "../vault.ts";
import { Archive, ArrowUpRight, Bell, Brain, Chart, Check, ChevronRight, Im, Info, Key, Quota, Refresh, Server, ShieldCheck, Sliders, ViewColumns, Web, type IconProps } from "@stillfail/ui/icons.tsx";
import type { ComponentType } from "react";
import { WorkspaceMark, marked } from "../WorkspaceMark.tsx";
import { isPicture } from "../StationMark.tsx";
import { useAppearance, useMotionSetting, type Appearance } from "../theme.ts";
import { CAN_NOTIFY, setNotify, useNotifyState } from "../notify.ts";
import { HAS_TELEMETRY, setTelemetry, useTelemetryOn } from "../telemetry.ts";
import { reload } from "../reloads.ts";
import { legalPages, legalUrl } from "../pages/About.tsx";
import { NAME } from "../channel.ts";
import { useApp } from "./app.tsx";
import { t } from "../i18n.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useChangelog } from "../changelog.ts";
import { standalone } from "../standalone.ts";
import { download, downloadsOffered, onAndroid } from "../downloads.ts";
import { Presence } from "./Connects.tsx";
import { FontRow } from "./Fonts.tsx";
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

/** A settings row's icon, before its name (Android's RowIcon): the line art in the muted ink. */
export function RowIcon({ icon: I }: { icon: ComponentType<IconProps> }) {
  return <I size={22} className={css.mRowIcon} />;
}

/** A row that opens a page: its icon (settings' rows), its name, how things stand (`bad` in red), a chevron. */
export function GoRow({ title, value, bad = false, icon, lead, onClick }: { title: string; value?: ReactNode; bad?: boolean; icon?: ComponentType<IconProps>; lead?: ReactNode; onClick: () => void }) {
  return (
    <ListRow onClick={onClick}>
      {icon && <RowIcon icon={icon} />}
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
  // (what the core says of it at the row's end)
  const vaults = useVaults(app.entry.id);
  const vault = vaults ? { text: vaults.statusText ?? "", bad: vaults.statusBad === true } : undefined;
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
      {/* The workspace as the account is: its mark, its name, the viewer's role in it and its people. */}
      <Card onClick={at("/settings/workspace")}>
        <span className={css.mMe}>
          <span className={css.mWorkspace} data-marked={(view && marked(view)) || undefined} data-picture={(view && isPicture(view.icon)) || undefined}>
            <WorkspaceMark w={view ?? app.entry} size={26} picture={46} />
          </span>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <b>{view?.name ?? app.entry.name}</b>
            <span className={listsCss.mRowNote}>{[view ? ROLE_LABEL[view.role] : null, view ? (manager && waiting ? t("web-mobile.settings.membersWaiting", { n: view.members.length, waiting }) : t("web-mobile.settings.members", { n: view.members.length })) : null].filter(Boolean).join(" · ")}</span>
          </span>
          <ChevronRight size={14} className={partsCss.mSubtle} />
        </span>
      </Card>
      {/* Who may do what: security mode, where the workspace has it, and the vault. */}
      <ListCard>
        {lock?.available && <GoRow icon={ShieldCheck} title={t("web-pages.security.title")} bad={lock.attention > 0} value={lock.locked ? (lock.attention > 0 ? t("web-mobile.settings.securityWaiting", { n: lock.attention }) : t("web-mobile.settings.securityOn")) : t("web-mobile.settings.securityOff")} onClick={at("/settings/security")} />}
        <GoRow icon={Key} title={t("web-pages.vault.title")} bad={vault?.bad ?? false} value={vault?.text} onClick={at("/settings/vault")} />
      </ListCard>
      {/* Its stations and what they run: the chats' ways in and the agents' accounts. */}
      <ListCard>
        <GoRow icon={Server} title="Station" value={stations ? <>{troubled && <Presence state="error" />}{t("web-mobile.settings.stationsOnline", { online, n: stations.length })}</> : undefined} onClick={at("/settings/stations")} />
        <GoRow icon={Im} title={t("web-mobile.settings.connects")} bad={failing > 0} value={connects ? (failing ? t("web-mobile.settings.connectsFailing", { n: failing }) : t("web-mobile.settings.connectsCount", { n: connects.items.length })) : undefined} onClick={at("/settings/connects")} />
        <GoRow icon={Quota} title="Profile" bad={short > 0} value={stations ? (short ? t("web-mobile.settings.profilesShort", { n: short }) : t("web-mobile.settings.profilesCount", { n: profiles.length })) : undefined} onClick={at("/settings/profiles")} />
      </ListCard>
      {/* Its agents: when their chats are archived, what they decide by themselves, what they remember, what they used. */}
      <ListCard>
        <GoRow icon={Archive} title={t("web-pages.archiving.title")} onClick={at("/settings/archive")} />
        <GoRow icon={Check} title={t("web-pages.automaticDecisions.title")} onClick={at("/settings/automatic-decisions")} />
        <GoRow icon={Brain} title={t("web-mobile.settings.memory")} onClick={at("/settings/memory")} />
        <GoRow icon={Chart} title={t("web-mobile.settings.usage")} onClick={at("/settings/usage")} />
      </ListCard>
      <SectionHeader title={t("web-mobile.settings.device")} start={24} />
      <ListCard>
        <GoRow icon={Sliders} title={t("web-mobile.settings.appearance.title")} value={themes().find(([v]) => v === appearance)?.[1]} onClick={at("/settings/appearance")} />
        <GoRow icon={ViewColumns} title={t("web-mobile.bar.title")} value={bars.sets.length > 1 ? t("web-mobile.bar.count", { n: bars.sets.length }) : bars.sets[0]!.map((k) => railLabel(k as BarPlace)).join("、")} onClick={at("/settings/bar")} />
        <GoRow icon={Web} title={t("common.language")} value={languages().find(([v]) => v === language)?.[1]} onClick={at("/settings/language")} />
        <Notify />
        {/* An app on the home screen has no browser round it to reload the page: here it can. */}
        {standalone() && <ListRow onClick={() => reload("button")}><RowIcon icon={Refresh} /><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("common.reload")}</span></ListRow>}
      </ListCard>
      <ListCard>
        <GoRow icon={Info} title={t("web-pages.settings.nav.about")} value={build != null ? `0.1.${build}` : undefined} onClick={at("/settings/about")} />
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/**
 * About still.fail, as the wide screen's 关于 and Android's: what changed (this build's number), this channel's Android
 * app on an Android phone's browser, whether usage statistics are sent, and the terms and privacy policy on still.fail's
 * site, in a tab of their own.
 */
export function AboutScreen() {
  const app = useApp();
  const build = useChangelog().value?.build;
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-pages.settings.nav.about")} />
      <ListCard>
        <GoRow title={t("web-mobile.settings.changelog")} value={build != null ? `0.1.${build}` : undefined} onClick={() => app.push(app.at("/settings/changelog"))} />
        {downloadsOffered() && onAndroid() && <GoRow title={t("web-mobile.settings.downloadAndroid")} onClick={() => { location.href = download("android"); }} />}
      </ListCard>
      {HAS_TELEMETRY && <ListCard><Telemetry /></ListCard>}
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
  // (its switch says whether: a note only where the browser refused it)
  const note = state === "denied" ? t("web-mobile.settings.notify.denied") : null;
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
      <RowIcon icon={Bell} />
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{t("web-mobile.settings.notify.title")}</span>
        {note && <span className={listsCss.mRowNote}>{note}</span>}
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
      <div style={{ height: 12 }} />
      <ListCard><FontRow /></ListCard>
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
