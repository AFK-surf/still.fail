// Profiles on a narrow screen (what the desktop's ../pages/Accounts.tsx does, in the Android app's manner): every
// station's in one list, a profile's
// page (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its
// key or variables; renaming, checking and deleting under "…"), and a new one.
import { Fragment, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useParams, useSearchParams } from "react-router";
import { stationApi, useAction, useMemberships, useOverview, useProfiles, useStationCall, useStations, type LoginJob, type Profile, type Quota, type StationView, type Tone } from "../api.ts";
import type { ApiProvider, MachineLogin, ProfileFlowView, ProviderGroup, RuntimeInstall, WorkspaceProfile } from "../core/shapes.ts";
import { hosts, profileGroups } from "../cloud/settings.tsx";
import { ACCESS, KEYED, RUNTIME_LABEL } from "../format.ts";
import { Check, ChevronRight, Key, More } from "@stillfail/ui/icons.tsx";
import type { Choice } from "../pages/Accounts.tsx";
import { useProfileFlow } from "../profileFlow.ts";
import { QuotaBars } from "../components.tsx";
import { StationContext, stationBase, useStation } from "../station.tsx";
import { SheetGrab, SheetHead, useApp, type SheetSpec } from "./app.tsx";
import { Presence } from "./Connects.tsx";
import { Button, failedIn, FailedMark, Field, Gone, LinkButton, ListCard, ListRow, NavBar, NavButton, PickRow, PlaceHead, PlaceNote, ProviderMark, QuotaRings, SectionHeader, SlackMark, tNodes } from "./parts.tsx";
import { Progress, Spinner, Waiting, WaitLine } from "@stillfail/ui/waiting.tsx";
import { useAct } from "@stillfail/ui/toast.tsx";
import { doingMatches, failed, useDoing, useDoingFailed, useDoingList } from "../doing.ts";
import { ask, CommandBox, confirm } from "./sheets.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as css from "./Profiles.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as chatCss from "./styles/chat.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { WorkspaceNamed } from "../WorkspaceMark.tsx";
import { StationMark } from "../StationMark.tsx";
import { useInStation } from "../screen/InStation.tsx";
import { StationInWords, StationNamedAt } from "../StationNamed.tsx";
import { sampleProfile, sampleProviders, sampleStation, sampleWords, sampleWorkspaceProfiles } from "../samples.ts";
function useApi() {
  const station = useStation();
  const call = useStationCall(station.address);
  return useMemo(() => stationApi(call), [call]);
}

/** Opens a sheet under this page's station: the app shows sheets outside the page, where no station is in context. */
function useStationSheet(): (spec: SheetSpec) => void {
  const app = useApp();
  const station = useStation();
  return (spec) => app.sheet({ ...spec, content: () => <StationContext.Provider value={station}>{spec.content()}</StationContext.Provider> });
}

/**
 * Every station's profiles on one page, from settings (./Settings.tsx), as the desktop's settings have them: each
 * station under its name, what can be added there (a profile, the machine's own logins) with it; one offline says so.
 */
export function ProfilesScreen() {
  const app = useApp();
  // From a station's page (?station=<id>): that station's only, back to it.
  const [params] = useSearchParams();
  const only = params.get("station");
  const listed = useStations(app.entry.id).value;
  const stations = only ? listed?.filter((s) => s.id === only) : listed;
  const one = only ? stations?.[0] : undefined;
  const online = stations?.filter((s) => s.online) ?? [];
  const add = () => online.length === 1
    ? app.push(app.at(`/s/${online[0]!.id}/profiles/new`))
    : app.sheet({ height: 0.5, content: () => <PickStation title={t("web-mobile.newChat.addProfile")} stations={online} to={(s) => `/s/${s.id}/profiles/new`} /> });
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <PlaceHead title="Profile" back={one?.name ?? t("web-mobile.settings.title")} onBack={app.pop}
        primary={online.length > 0 ? { key: "profile", label: t("web-mobile.newChat.addProfile"), run: add } : null} />
      {/* The workspace's: one list, each shared profile once (the core's `profiles`); a station's own: as before. */}
      {!one && <WorkspaceList scope={app.entry.id} />}
      {/* A station's own (?station=): its stations read first; the workspace's list waits on its own (WorkspaceList). */}
      {!stations ? (only ? <Waiting text={t("common.readingStations")} sample={<ProfileSections s={SAMPLE_STATION} profiles={SAMPLE_PROFILES} />} /> : null) : stations.filter(() => !!one).map((s) => (
        <StationContext.Provider key={s.id} value={{ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${app.entry.id}/settings` }}>
          {!one && <SectionHeader title={<StationInWords station={s.station} text={s.online ? s.name : t("web-mobile.connects.stationOfflineTitle", { station: s.name })} size={14} />} start={24} />}
          {!s.overview || s.overview.profiles.length === 0 ? (
            <ListCard>
              <ListRow>{!s.overview && s.online ? <WaitLine />
                : <span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{s.overview ? t("web-mobile.profiles.none") : t("web-mobile.profiles.offline")}</span>}</ListRow>
            </ListCard>
          ) : <ProfileSections s={s} profiles={s.overview.profiles} />}
          {/* The machine's own logins not used yet, each offered as a profile. */}
          {s.online && s.overview && <MachineLoginOffers logins={s.overview.machineLogins} onSignIn={(kind) => app.push(app.at(`/s/${s.id}/profiles/new?kind=${kind}`))} />}
        </StationContext.Provider>
      ))}
      {!one && online.map((s) => s.overview && (
        <StationContext.Provider key={s.id} value={{ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${app.entry.id}/settings` }}>
          <MachineLoginOffers logins={s.overview.machineLogins} onSignIn={(kind) => app.push(app.at(`/s/${s.id}/profiles/new?kind=${kind}`))} />
        </StationContext.Provider>
      ))}
      <div style={{ height: 30 }} />
    </div>
  );
}

/** A station's `profiles`, a section each kind of account, as the workspace's list (the core's order). */
function ProfileSections({ s, profiles }: { s: StationView; profiles: Profile[] }) {
  return profileGroups(profiles).map((g) => (
    <Fragment key={g[0]!.group}>
      <SectionHeader title={g[0]!.groupTitle ?? ""} start={24} mark={<GroupMark group={g[0]!.group} />} />
      <ListCard>{g.map((p) => <ProfileRow key={p.id} station={s} p={p} />)}</ListCard>
    </Fragment>
  ));
}

/** A station, its profiles and the workspace's made up, for what the screens show while they are read (in their bones). */
const SAMPLE_STATION = sampleStation(0);
const SAMPLE_PROFILES = [sampleProfile(6, 0), sampleProfile(9, 1)];
const SAMPLE_PROFILE = SAMPLE_PROFILES[1]!;
const SAMPLE_WORKSPACE = sampleWorkspaceProfiles();
const SAMPLE_PROVIDERS = sampleProviders();

/** A kind of account's mark, before its section's title: its vendor's for a subscription, a key for keys. */
function GroupMark({ group }: { group?: string | undefined }) {
  if (group === "kimi") return <ProviderMark runtime="claude" kind="api-provider" mark="kimi" size={16} />;
  if (group === "opencode") return <ProviderMark runtime="claude" kind="opencode-go" size={16} />;
  return group === "key" ? <Key size={16} /> : <ProviderMark runtime={group === "chatgpt" ? "codex" : group ?? "claude"} kind="subscription" size={16} />;
}

/** The workspace's profiles in one list: a shared one once, where it is (登录在 / 只给 …) under it; one whose
 * subscription's station is away dimmed, said why. */
function WorkspaceList({ scope }: { scope: string }) {
  const app = useApp();
  const profiles = useProfiles(scope);
  const view = profiles.value;
  if (!view) return <Waiting error={profiles.error?.message} sample={<WorkspaceGroups items={SAMPLE_WORKSPACE} />} />;
  // What it still waits on (the core's `wait`): with none to show, the cards to come under it; with some, a line after them.
  const wait = view.wait;
  if (view.items.length === 0 && (wait.reading || wait.failing.length > 0)) return <Waiting note={wait} sample={<WorkspaceGroups items={SAMPLE_WORKSPACE} />} />;
  return (
    <>
      {wait.empty && <ListCard><ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{t("web-pages.settings.profiles.none")}</span></ListRow></ListCard>}
      {/* What Profile is, said while there is none (the page says it nowhere else). */}
      {wait.empty && <PlaceNote>{t("web-mobile.profiles.note")}</PlaceNote>}
      <WorkspaceGroups items={view.items} />
      {(wait.reading || wait.failing.length > 0) && (
        <ListCard>
          {wait.reading && <ListRow><WaitLine text={wait.text ?? t("common.reading")} /></ListRow>}
          {wait.failing.map((f) => <ListRow key={f.station}><WaitLine text={f.text} error /></ListRow>)}
        </ListCard>
      )}
    </>
  );
}

/** The workspace's profiles (`items`), a section each kind of account (the core's order). */
function WorkspaceGroups({ items }: { items: WorkspaceProfile[] }) {
  const app = useApp();
  return profileGroups(items).map((g) => (
    <Fragment key={g[0]!.group}>
      <SectionHeader title={g[0]!.groupTitle} start={24} mark={<GroupMark group={g[0]!.group} />} />
      <ListCard>
        {g.map((e: WorkspaceProfile) => (
          <ListRow key={e.key} onClick={() => app.push(app.at(hosts(e).length > 1 ? `/settings/profiles/account/${encodeURIComponent(e.key)}` : `/s/${e.stationId}/settings/accounts/${encodeURIComponent(e.profile.id)}`))}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`} style={e.usable ? undefined : { opacity: 0.55 }}>
              {/* How it is where that is not simply fine, as the core says it (a dot in its tone; none while fine); what needs a look said in its line. */}
              <span className={listsCss.mRowTitle}>{e.state && <><Presence state={toneDot(e.state.tone)} /> </>}{e.title}</span>
              <span className={listsCss.mRowNote}>{e.look ? e.state?.text : e.where || `${e.profile.checkText} · ${e.profile.usesText || accessLabel(e.profile)}`}</span>
              {/* Its allowance a line of its own, so the name and where it is keep the row's width. */}
              {e.usable && e.profile.quota?.state === "ok" && e.profile.quota.windows.length > 0 && <span className={css.mRowQuota}><QuotaRings quota={e.profile.quota} /></span>}
            </span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        ))}
      </ListCard>
    </Fragment>
  ));
}

/** An account on several stations (as the desktop's ProfileAccountSettings): what they have in common, then each
 * station's part, each leading to its page there. */
export function ProfileAccountScreen() {
  const app = useApp();
  const { key = "" } = useParams();
  const profiles = useProfiles(app.entry.id);
  const view = profiles.value;
  const e = view?.items.find((x) => x.key === key);
  if (!e) {
    return (
      <div className={pagesCss.mScreen}>
        <NavBar back="Profile" onBack={app.pop} title="Profile" />
        {!view || view.wait.reading ? <Waiting fill error={profiles.error?.message} sample={<AccountBody e={SAMPLE_WORKSPACE[0]!} />} /> : <Gone text={t("web-mobile.profiles.notFound")} />}
      </div>
    );
  }
  const p = e.profile;
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back="Profile" onBack={app.pop} title={p.name} sub={<span className={barsCss.mNavbarNote}>{[p.email, accessLabel(p)].filter(Boolean).join(" · ")}</span>} />
      <AccountBody e={e} />
    </div>
  );
}

/** What an account on several stations (`e`) has in common, then each station's part, each leading to its page there. */
function AccountBody({ e }: { e: WorkspaceProfile }) {
  const app = useApp();
  const p = e.profile;
  return (
    <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
      <div style={{ height: 12 }} />
      <ListCard>
        <ListRow>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}><Presence state={toneDot(p.checkTone)} /> {p.checkText}</span>
            <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{p.check ? p.check.detail : t("web-mobile.profiles.notChecked")}</span>
          </span>
        </ListRow>
        {p.quota?.state === "ok" && p.quota.windows.length > 0 && <div className={css.mQuotaDials}><QuotaBars quota={p.quota} /></div>}
      </ListCard>
      <SectionHeader title={t("web-pages.profiles.account.each")} start={24} />
      <ListCard>
        {hosts(e).map((m) => (
          <ListRow key={`${m.station}/${m.profileId}`} onClick={() => app.push(app.at(`/s/${m.stationId}/settings/accounts/${encodeURIComponent(m.profileId)}`))}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}><Presence state={!m.online ? "offline" : !m.usable ? "error" : toneDot(m.checkTone)} /> <StationNamedAt station={m.station} name={m.title} /></span>
              <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{m.online ? m.about : t("web-mobile.profiles.offline")}</span>
            </span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        ))}
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Sharing a profile with the workspace's other stations (as the desktop's ShareSection): a switch; once on, where a
 * subscription is signed in (moved from here) and which stations may use it. A copy of another station's says whose. */
/**
 * Whom a profile is shared with, one card under 分享: the station's other workspaces whose chats may use it, the
 * workspace's other stations (a copy of another station's, whose it is). None of either to say, no section.
 */
function Sharing({ p }: { p: Profile }) {
  const station = useStation();
  const overview = useOverview(station.address).value;
  const m = useMemberships(station.address).value;
  const copy = p.share?.role === "user";
  const workspaces = !copy && !!m?.manages && m.workspaces.some((w) => !w.home);
  if (!workspaces && !overview?.sharing) return null;
  return (
    <>
      <SectionHeader title={t("web-pages.profiles.share.title")} start={24} />
      <ListCard>
        {workspaces && <WorkspaceRows p={p} />}
        {overview?.sharing && <ShareRows p={p} />}
      </ListCard>
    </>
  );
}

/** Its sharing with the workspace's other stations: rows of its 分享 card (Sharing). */
function ShareRows({ p }: { p: Profile }) {
  const app = useApp();
  const sheet = useStationSheet();
  const api = useApi();
  const act = useAct();
  const station = useStation();
  // Its row of the workspace's list (the account it is), and there the station that lends it.
  const entry = useProfiles(station.address.split("/")[0]!).value?.items.find((e) => e.members?.some((m) => m.station === station.address && m.profileId === p.id));
  const stations = entry?.stations ?? [];
  const lender = p.share ? entry?.members?.find((m) => m.stationId === p.share!.host && m.role === "host") : undefined;
  const on = { station: station.address, id: p.id };
  const sharing = useDoing("profile.share", on);
  const moving = useDoing("profile.move", on);
  const subscription = p.access.kind === "subscription";
  if (p.share?.role === "user") {
    const host = stations.find((x) => x.id === p.share!.host)?.name ?? p.share.host.slice(0, 8);
    return (
      <>
          <ListRow onClick={lender ? () => app.push(app.at(`/s/${lender.stationId}/settings/accounts/${encodeURIComponent(lender.profileId)}`)) : undefined}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}>{t("web-main.memory.share.from", { station: host })}</span>
              <span className={listsCss.mRowNote}>{t("web-pages.profiles.share.changeThere")}</span>
              {subscription && p.share.reachable === false && <span className={`${listsCss.mRowNote} ${partsCss.mRed}`}>{t("web-pages.profiles.share.hostAway", { station: host })}</span>}
            </span>
            {lender && <ChevronRight size={14} className={partsCss.mSubtle} />}
          </ListRow>
      </>
    );
  }
  const shared = p.share !== undefined;
  const allowed = p.share?.allow ?? null;
  const names = allowed === null ? t("web-pages.profiles.share.everyStation") : stations.filter((x) => allowed.includes(x.id) || x.id === station.id).map((x) => x.name).join(t("web-main.list.separator"));
  const targets = stations.filter((x) => x.id !== station.id);
  const pick = () => sheet({ height: 0.6, content: () => <PickShareStations p={p} stations={stations} self={station.id} allowed={allowed} /> });
  const move = () => app.sheet({ height: 0.5, content: () => (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.profiles.share.moveTitle")} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{<StationInWords station={station.address} text={t("web-pages.profiles.share.moveLead", { station: station.name })} />}</p>
        {targets.map((x) => <PickRow key={x.id} label={x.name} sub={x.online ? undefined : t("web-mobile.profiles.offline")} enabled={x.online}
          onClick={() => { app.sheet(null); act(api.moveProfile(p.id, x.id), t("web-pages.profiles.share.move"), t("web-pages.profiles.share.moved", { station: x.name })); }} />)}
      </div>
    </>
  ) });
  return (
    <>
        <ListRow onClick={sharing ? undefined : () => act(api.shareProfile(p.id, !shared, null), t("web-pages.profiles.share.switch"), shared ? t("web-pages.profiles.share.unshared") : t("web-pages.profiles.share.shared"))}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}>{t("web-pages.profiles.share.switch")}</span>
            <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{!shared ? <StationInWords station={station.address} text={t("web-pages.profiles.share.onlyHere", { station: station.name })} /> : subscription ? t("web-pages.profiles.share.lent") : t("web-pages.profiles.share.copied")}</span>
          </span>
          {sharing && <Spinner inline />}
          <span className={connectsCss.mSwitch} data-on={shared || undefined} />
        </ListRow>
        {shared && subscription && !p.machine && (
          <ListRow onClick={moving || targets.length === 0 ? undefined : move}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("web-pages.profiles.share.signedIn")}</span>
            {moving && <Spinner inline />}
            <span className={listsCss.mRowNote}><StationNamedAt station={station.address} name={station.name} /></span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        )}
        {shared && (
          <ListRow onClick={pick}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}>{t("web-pages.profiles.share.stations")}</span>
              {(p.share?.users?.length ?? 0) > 0 && <span className={listsCss.mRowNote}>{t("web-pages.profiles.share.users", { stations: p.share!.users!.map((u) => stations.find((x) => x.id === u)?.name ?? u.slice(0, 8)).join(t("web-main.list.separator")) })}</span>}
            </span>
            <span className={listsCss.mRowNote}>{names}</span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        )}
    </>
  );
}

/** Which stations may use a shared profile, ticked in a sheet; all ticked is every station (those to come too). */
function PickShareStations({ p, stations, self, allowed }: { p: Profile; stations: { id: string; name: string; online: boolean }[]; self: string; allowed: string[] | null }) {
  const app = useApp();
  const api = useApi();
  const act = useAct();
  const [ticked, setTicked] = useState<Set<string>>(() => new Set(allowed ?? stations.map((x) => x.id)));
  const all = stations.every((x) => x.id === self || ticked.has(x.id));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.profiles.share.stations")} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{all ? t("web-pages.profiles.share.futureIn") : t("web-pages.profiles.share.futureOut")}</p>
        {stations.map((x) => <PickRow key={x.id} label={x.name} checked={x.id === self || ticked.has(x.id)} enabled={x.id !== self}
          onClick={() => setTicked((was) => { const next = new Set(was); if (next.has(x.id)) next.delete(x.id); else next.add(x.id); return next; })} />)}
        <div className={partsCss.mPad}>
          <Button primary label={t("web-pages.profiles.share.done")} onClick={() => { app.sheet(null); act(api.shareProfile(p.id, true, all ? null : [...new Set([...ticked, self])]), t("web-pages.profiles.share.stations")); }} />
        </div>
      </div>
    </>
  );
}

/** Where something is added: one of the stations online, in a sheet. */
export function PickStation({ title, stations, to }: { title: string; stations: StationView[]; to: (s: StationView) => string }) {
  const app = useApp();
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{t("web-mobile.profiles.whichStation")}</p>
        {stations.map((s) => <PickRow key={s.id} label={s.name} leading={<StationMark emoji={s.emoji} icon={s.icon} size={22} />} onClick={() => { app.sheet(null); app.push(app.at(to(s))); }} />)}
      </div>
    </>
  );
}

/**
 * A profile in the list of profiles: whether it works (a dot before its name, its state in words, why when its provider
 * refuses it), what it is, how many of its models are enabled, and its allowance; its page picks them.
 */
export function ProfileRow({ station, p }: { station: StationView; p: Profile }) {
  const app = useApp();
  const trouble = quotaTrouble(p.quota);
  return (
    <ListRow onClick={() => app.push(app.at(`/s/${station.id}/settings/accounts/${encodeURIComponent(p.id)}`))}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}><Presence state={toneDot(p.checkTone)} /> {p.name}</span>
        <span className={listsCss.mRowNote}>{p.checkText} · {p.usesText || accessLabel(p)} · {p.modelsText}</span>
        {p.trouble ? <>
          <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}><b>{p.trouble.title}</b> · {p.trouble.detail}</span>
          <span className={`${listsCss.mRowNote} ${partsCss.mLink}`}>{t("web-mobile.profiles.seeFix")}</span>
        </> : trouble && <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>}
      </span>
      <QuotaRings quota={p.quota} />
      <ChevronRight size={14} className={partsCss.mSubtle} />
    </ListRow>
  );
}

/** A check's tone as a presence dot (./Connects.tsx): green up, red failing, the rest on its way or unknown. */
export function toneDot(tone: Tone | string): string {
  return tone === "green" ? "online" : tone === "red" ? "error" : tone === "neutral" ? "offline" : "busy";
}

/** Why an allowance could not be read (an account its provider refuses, a sign-in gone stale), when that is so. */
export function quotaTrouble(quota: Quota | null | undefined): string | null {
  return quota && (quota.state === "blocked" || quota.state === "unavailable") ? quota.detail ?? (quota.state === "blocked" ? t("web-mobile.profiles.blockedText") : t("web-mobile.profiles.noQuotaText")) : null;
}

/** What a profile is, in a word: the machine's own login, or its kind of access. */
export function accessLabel(p: Profile): string {
  return p.machine ? t("web-mobile.profiles.machineLogin") : p.providerName ?? ACCESS[p.access.kind].label;
}

/** A profile of the station in context, by the page's :id. */
export function ProfileScreen() {
  const app = useApp();
  const station = useStation();
  const { id = "" } = useParams();
  const overview = useOverview(station.address);
  const p = overview.value?.profiles.find((x) => x.id === id);
  if (!p) {
    return (
      <div className={pagesCss.mScreen}>
        <NavBar back={station.name ? <StationNamedAt station={station.address} name={station.name} /> : "Station"} onBack={app.pop} title="Profile" />
        {overview.value ? <Gone text={t("web-mobile.profiles.notFound")} /> : <Waiting fill error={overview.error?.message} sample={<ProfileBody p={SAMPLE_PROFILE} />} />}
      </div>
    );
  }
  return <ProfilePage p={p} />;
}

/** A profile's models to choose (`put`), what it is over them; while they are read, that. */
function PickModels({ p, put }: { p: Profile; put: (models: string[]) => Promise<unknown> }) {
  const listed = (p.available ?? []).length > 0;
  return (
    <div className={pagesCss.mScroll}>
      <p className={css.mProfileNote}>{t("web-mobile.profiles.pickModels.lead", { name: p.name })}</p>
      {p.modelsReading ? <WaitLine className={css.mProfileNote} text={t("web-mobile.profiles.pickModels.reading")} />
        : !listed && !p.canAddModel ? <p className={css.mProfileNote}>{p.check?.state === "ok" ? t("web-mobile.profiles.pickModels.none") : p.check?.detail || p.checkText}</p>
        : <Models p={p} put={put} bare />}
    </div>
  );
}

/**
 * The step right after a profile is added (s/<station>/settings/accounts/<id>/models): its models chosen on a screen of
 * their own, since chats use only those enabled, or skipped; either way on to its page. Its models are read by the check
 * the station runs once it is added (a few seconds): until then, that.
 */
export function PickModelsScreen() {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const { id = "" } = useParams();
  const overview = useOverview(station.address);
  const p = overview.value?.profiles.find((x) => x.id === id);
  const leave = () => app.replace(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(id)}`);
  const title = t("web-mobile.profiles.pickModels.title");
  if (!p) {
    return (
      <div className={pagesCss.mScreen}>
        <NavBar back="Profile" onBack={app.pop} title={title} />
        {overview.value ? <Gone text={t("web-mobile.profiles.notFound")} /> : <Waiting fill error={overview.error?.message} sample={<PickModels p={SAMPLE_PROFILE} put={() => Promise.resolve()} />} />}
      </div>
    );
  }
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back="Profile" onBack={leave} title={title} sub={p.models.length > 0 ? <span className={barsCss.mNavbarNote}>{t("web-mobile.profiles.pickModels.selected", { n: p.models.length })}</span> : undefined} />
      <PickModels p={p} put={(models) => api.putProfile(p.id, { models })} />
      <div className={css.mPickFoot}>
        <Button label={t("web-mobile.profiles.pickModels.skip")} primary={false} onClick={leave} />
        <Button label={t("common.done")} primary enabled={p.models.length > 0} onClick={leave} />
      </div>
    </div>
  );
}

function ProfilePage({ p }: { p: Profile }) {
  const app = useApp();
  const sheet = useStationSheet();
  const station = useStation();
  // A copy of another station's: shown, used, changed only there.
  const copy = p.share?.role === "user";
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name ? <StationNamedAt station={station.address} name={station.name} /> : "Station"} onBack={app.pop} title={p.name} sub={<span className={barsCss.mNavbarNote}>{accessLabel(p)}</span>}
        trailing={copy ? undefined : <NavButton icon={More} label={t("common.more")} onClick={() => sheet({ height: 0.5, content: () => <ProfileMenu p={p} /> })} />} />
      <ProfileBody p={p} />
    </div>
  );
}

/** A profile's page under its bar: where it stands, its allowance, its variables, what uses it, how it runs, its sharing. */
function ProfileBody({ p }: { p: Profile }) {
  const app = useApp();
  const sheet = useStationSheet();
  const api = useApi();
  const station = useStation();
  const overview = useOverview(station.address).value;
  const users = p.usedBy.map((id) => overview?.connects.find((c) => c.id === id)).filter((c) => c !== undefined);
  // Asked from its menu, which has closed by then: the card says it is under way, and a few seconds why it failed.
  const checking = useDoing("profile.check", { station: station.address, id: p.id });
  const refreshing = useDoing("profile.quota", { station: station.address, id: p.id });
  const checkFailed = useDoingFailed("profile.check", { station: station.address, id: p.id });
  const quotaFailed = useDoingFailed("profile.quota", { station: station.address, id: p.id });
  const keyed = KEYED.has(p.access.kind) && !p.access.login;
  // A copy of another station's: shown, used, changed only there.
  const copy = p.share?.role === "user";
  const signs = !copy && signsIn(p);
  const detail = p.check ? p.checkLine ?? "" : t("web-mobile.profiles.notChecked");
  const checked = p.check?.time?.checkedAt ? t("web-mobile.profiles.checkedAgo", { ago: p.check.time.checkedAt.ago }) : "";
  // What it is now in a line: what is wrong (its trouble's title), else what its check said beyond its words, else they;
  // under it a dot of its tone, its words (when that line is not they) and when it was checked, coloured only when off.
  const first = p.trouble?.title || (detail && detail !== p.checkText ? detail : p.checkText);
  const said = first !== p.checkText;
  const under = said ? p.checkText + checked : checked.replace(/^ · /, "");
  const head = (
    <span className={css.mAccount}>
      <span className={settingsCss.mProfileHead}>
        <ProviderMark runtime={p.runtime} kind={p.access.kind} mark={p.providerMark} size={26} />
        <span className={partsCss.mGrow}>
          <span className={`${listsCss.mRowTitle} ${settingsCss.mWrap}`}>{first}</span>
          {(checking || under) && <span className={`${listsCss.mRowNote} ${css.mAccountState}`} data-tone={said ? p.checkTone : undefined}>
            <Presence state={toneDot(p.checkTone)} />{checking ? <><Spinner inline />{t("web-mobile.versions.checking")}</> : under}
          </span>}
          {!checking && checkFailed !== undefined && <span className={`${listsCss.mRowNote} ${chatCss.mWaiting} ${partsCss.mRed}`}><FailedMark error={checkFailed} size={12} />{t("web-mobile.profiles.checkFailed", { error: checkFailed })}</span>}
          {!refreshing && quotaFailed !== undefined && <span className={`${listsCss.mRowNote} ${chatCss.mWaiting} ${partsCss.mRed}`}><FailedMark error={quotaFailed} size={12} />{t("web-mobile.profiles.quotaFailed", { error: quotaFailed })}</span>}
        </span>
      </span>
      {/* In trouble: why and what to do, on the same card. */}
      {p.trouble && <Trouble p={p} />}
    </span>
  );
  return (
    <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
      {/* Where it stands, on the account's one card: a subscription's heads its sign-in, a key's its key. */}
      {signs ? <SignIn p={p} head={head} />
        : keyed && !copy ? (
          <ListCard>
            <div className={`${settingsCss.mProfileHead} ${css.mHeadRow}`}>{head}</div>
            <KeyRows p={p} />
          </ListCard>
        )
        : <div className={`${listsCss.mCard} ${settingsCss.mProfileHead}`}>{head}</div>}
      {p.trouble?.action !== "quota" && <Quota p={p} />}
      {p.access.kind === "env" && !copy && (
        <>
          <SectionHeader title={t("web-mobile.profiles.env")} start={24} />
          <ListCard>
            {p.env.map((e) => <ListRow key={e.key}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={`${listsCss.mRowTitle} ${css.mMono}`}>{e.key}</span><span className={`${listsCss.mRowNote} ${css.mMono}`}>{e.value}</span></span></ListRow>)}
            <ListRow onClick={() => sheet({ height: 0.8, draggable: true, content: () => <EnvSheet p={p} /> })}><span className={`${partsCss.mAccent} ${listsCss.mRowTitle}`}>{t("web-mobile.profiles.editEnv")}</span></ListRow>
          </ListCard>
        </>
      )}
      {/* The connects bound to it (Slack, Feishu): none says nothing of the station's own chats, which run on any. */}
      {users.length > 0 && <SectionHeader title={t("web-mobile.profiles.usedBy")} start={24} />}
      {users.length > 0 && <ListCard>
        {users.map((c) => (
          <ListRow key={c.id} onClick={() => app.push(`${stationBase(station.address)}/connects/${encodeURIComponent(c.id)}`)}>
            <SlackMark kind={c.kind} size={15} /><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{c.name}</span><span className={listsCss.mRowNote}>{c.modelName ?? (p.model ? p.names[p.model] ?? p.model : t("web-mobile.profiles.defaultModel"))}</span>
          </ListRow>
        ))}
      </ListCard>}
      {/* A decision model's models are said, not picked. */}
      {!copy && p.decisionOnly && <Models p={p} put={(models) => api.putProfile(p.id, { models })} />}
      {!copy && <RunRows p={p} />}
      <Sharing p={p} />
      <div style={{ height: 30 }} />
    </div>
  );
}

/** A key's profile: its key, and its address where it has one of the person's own, each changed from its row. */
function KeyRows({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  return (
    <>
    <ListRow onClick={() => ask(app, { title: p.access.kind === "opencode-go" ? t("web-mobile.profiles.newOpencodeKey") : t("web-mobile.profiles.newApiKey"), value: "", placeholder: t("web-mobile.profiles.pasteKey"), action: t("common.save"), secret: true, atOnce: "web-mobile.profiles.saveFailed",
      hint: t("web-mobile.profiles.recheckHintFull"), run: (key) => api.putProfile(p.id, { access: { kind: p.access.kind, key } }).then(() => app.toast(t("web-mobile.profiles.savedChecking"))) })}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{p.access.kind === "opencode-go" ? "OpenCode Go key" : p.providerName ? `${p.providerName} key` : "API key"}</span><span className={`${listsCss.mRowNote} ${css.mMono}`}>{p.access.key || t("web-mobile.profiles.notSaved")}</span></span>
      <span className={partsCss.mLink}>{t("web-mobile.profiles.change")}</span>
    </ListRow>
    {p.access.endpoint !== undefined && (
      <ListRow onClick={() => ask(app, { title: t("common.provider.endpoint"), value: p.access.endpoint ?? "", placeholder: "https://", action: t("common.save"),
        run: (endpoint) => api.putProfile(p.id, { access: { kind: p.access.kind, endpoint: endpoint.trim() } }).then(() => app.toast(t("web-mobile.profiles.savedChecking"))) })}>
        <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{t("common.provider.endpoint")}</span><span className={`${listsCss.mRowNote} ${css.mMono}`}>{p.access.endpoint}</span></span>
        <span className={partsCss.mLink}>{t("web-mobile.profiles.change")}</span>
      </ListRow>
    )}
    </>
  );
}

/**
 * What is wrong with a profile in trouble and its next step, on its account's card under where it stands (whose first
 * line its title is): the core supplies the diagnosis; the view opens the existing operation or editor.
 */
function Trouble({ p }: { p: Profile }) {
  const app = useApp();
  const sheet = useStationSheet();
  const station = useStation();
  const api = useApi();
  const act = useAct();
  const issue = p.trouble!;
  const checking = useDoing("profile.check", { station: station.address, id: p.id });
  const refreshing = useDoing("profile.quota", { station: station.address, id: p.id });
  const checkFailed = useDoingFailed("profile.check", { station: station.address, id: p.id });
  const quotaFailed = useDoingFailed("profile.quota", { station: station.address, id: p.id });
  const run = () => {
    if (issue.action === "key") ask(app, { title: t("web-mobile.profiles.newKey"), value: "", placeholder: t("web-mobile.profiles.pasteKey"), action: t("common.save"), secret: true, atOnce: "web-mobile.profiles.saveFailed",
      hint: t("web-mobile.profiles.recheckHint"), run: (key) => api.putProfile(p.id, { access: { kind: p.access.kind, key } }) });
    else if (issue.action === "env") sheet({ height: 0.8, draggable: true, content: () => <EnvSheet p={p} /> });
    else if (issue.action === "quota") act(api.refreshQuota(p.id), t("web-mobile.profiles.what.quota"), t("web-mobile.profiles.quotaUpdated"));
    else act(api.checkProfile(p.id), t("web-mobile.profiles.what.check"), t("web-mobile.profiles.checked"));
  };
  return (
    <div className={css.mTrouble}>
      {issue.detail && <p className={`${partsCss.mSmall} ${settingsCss.mWrap}`}>{issue.detail}</p>}
      {issue.next && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{issue.next}</p>}
      {!station.online && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{<StationInWords station={station.address} text={t("web-mobile.profiles.stationOffline", { station: station.name })} />}</p>}
      {issue.action === "command" && <CommandBox text={p.loginCommand} />}
      {issue.action !== "login" && <LinkButton label={issue.label} enabled={station.online}
        busy={checking || refreshing} failed={issue.action === "quota" ? quotaFailed : checkFailed} onClick={run} />}
      {["key", "env"].includes(issue.action) && <LinkButton label={t("web-mobile.profiles.recheck")} enabled={station.online} busy={checking} failed={checkFailed}
        onClick={() => act(api.checkProfile(p.id), t("web-mobile.profiles.what.check"), t("web-mobile.profiles.checked"))} />}
    </div>
  );
}

/**
 * Renaming, checking (its allowance read again with it), signing its account in again or by hand on the machine while
 * its card asks for neither (signed in and well), deleting it (stopping one on the machine's login); not while a connect
 * uses it.
 */
function ProfileMenu({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const start = useStartSignIn(p);
  const station = useStation().address;
  const signing = useDoing("profile.login", { station, id: p.id });
  const failed = (key: string) => (e: Error) => app.toast(t(key, { error: e.message }));
  // The sheet closes at once; the profile's card says it is under way (ProfilePage), and these rows if opened again.
  const checking = useDoing("profile.check", { station, id: p.id });
  const refreshing = useDoing("profile.quota", { station, id: p.id });
  const checkFailed = useDoingFailed("profile.check", { station, id: p.id });
  const quotaFailed = useDoingFailed("profile.quota", { station, id: p.id });
  return (
    <>
      <SheetGrab />
      <SheetHead title={p.name} />
      <div className={sheetsCss.mSheetScroll}>
        {!p.machine && <PickRow label={t("web-mobile.stations.rename")} onClick={() => ask(app, { title: t("web-mobile.profiles.renameTitle"), value: p.name, placeholder: t("web-mobile.workspaces.name"), action: t("common.save"), atOnce: "web-main.rename.failed", run: (name) => api.putProfile(p.id, { name }).then(() => app.toast(t("web-mobile.workspace.renamed"))) })} />}
        {/* Checked again with its allowance read again: whether it works and how much is left, as of now. */}
        <PickRow label={t("web-mobile.profiles.recheck")} busy={checking || refreshing} failed={checkFailed ?? quotaFailed} onClick={() => {
          app.sheet(null);
          api.checkProfile(p.id).then(() => app.toast(t("web-mobile.profiles.checked")), failed("web-mobile.profiles.checkFailed"));
          if (p.quota && p.quota.state !== "unsupported") api.refreshQuota(p.id).catch(failed("web-mobile.profiles.quotaFailed"));
        }} />
        {signsIn(p) && !signInAsked(p) && <>
          <PickRow label={t("web-mobile.profiles.relogin")} busy={signing} onClick={() => { app.sheet(null); start(); }} />
          {/* OpenCode's has no command to run by hand. */}
          {p.loginCommand && <PickRow label={t("web-mobile.profiles.manualShort")} onClick={() => app.sheet({ height: 0.36, content: () => <ManualSignIn command={p.loginCommand} /> })} />}
        </>}
        <PickRow label={p.machine ? t("web-mobile.connects.disable") : t("web-mobile.profiles.delete")} accent onClick={() => confirm(app, p.machine ? {
          title: t("web-mobile.profiles.disableAsk", { name: p.name }), text: t("web-mobile.profiles.disableText", { name: NAME }), action: t("web-mobile.connects.disable"), danger: true, atOnce: "web-mobile.connects.disableFailed",
          run: () => { app.pop(); return api.deleteProfile(p.id).then(() => app.toast(t("web-mobile.profiles.disabled"))); },
        } : {
          title: t("web-mobile.archive.deleteAsk", { title: p.name }), text: t("web-mobile.profiles.deleteText", { name: NAME }), action: t("web-mobile.profiles.delete"), danger: true, atOnce: "web-main.chat.deleteFailed",
          run: () => { app.pop(); return api.deleteProfile(p.id).then(() => app.toast(t("web-mobile.profiles.deleted"))); },
        })} />
      </div>
    </>
  );
}

/** The command to sign a profile's account in on the machine by hand, in a sheet of its own (from its "…"). */
function ManualSignIn({ command }: { command: string }) {
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.profiles.manualShort")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}><CommandBox text={command} /></div>
    </>
  );
}

/**
 * Which of the workspaces the station joined may run their chats on it (as the desktop's WorkspacesSection), a
 * switch each: for its home workspace's owners and admins, once the station is in more than one.
 */
/**
 * Which of a profile's models may be used, on a screen of their own from its 运行's 模型 row
 * (s/<station>/settings/accounts/<id>/models/edit): how many are on under its title, then the models themselves.
 */
export function ProfileModelsScreen() {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const { id = "" } = useParams();
  const overview = useOverview(station.address);
  const p = overview.value?.profiles.find((x) => x.id === id);
  const title = t("web-pages.profiles.models");
  if (!p) {
    return (
      <div className={pagesCss.mScreen}>
        <NavBar back="Profile" onBack={app.pop} title={title} />
        {overview.value ? <Gone text={t("web-mobile.profiles.notFound")} />
          : <Waiting fill error={overview.error?.message} sample={<div className={pagesCss.mScroll}><Models p={SAMPLE_PROFILE} put={() => Promise.resolve()} page /></div>} />}
      </div>
    );
  }
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={p.name} onBack={app.pop} title={title} sub={p.models.length > 0 ? <span className={barsCss.mNavbarNote}>{t("web-mobile.profiles.pickModels.selected", { n: p.models.length })}</span> : undefined} />
      <div className={pagesCss.mScroll}>
        <Models p={p} put={(models) => api.putProfile(p.id, { models })} page />
      </div>
    </div>
  );
}

/** The station's other workspaces whose chats may use the profile too, a switch each: rows of its 分享 card (Sharing). */
function WorkspaceRows({ p }: { p: Profile }) {
  const api = useApi();
  const station = useStation();
  const act = useAct();
  const m = useMemberships(station.address).value;
  const busy = useDoing("profile.put", { station: station.address, id: p.id });
  const joined = m?.manages ? m.workspaces.filter((w) => !w.home) : [];
  const now = p.workspaces ?? [];
  if (joined.length === 0) return null;
  return (
    <>
        {joined.map((w) => {
          const on = now.includes(w.workspace);
          return (
            <ListRow key={w.workspace} onClick={busy ? undefined : () => act(api.putProfile(p.id, { workspaces: on ? now.filter((x) => x !== w.workspace) : [...now, w.workspace] }),
              t("web-pages.profiles.workspaces.what"), t(on ? "web-pages.profiles.workspaces.turnedOff" : "web-pages.profiles.workspaces.turnedOn", { name: w.name }))}>
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}><WorkspaceNamed w={w}>{t("web-pages.profiles.workspaces.for", { name: w.name })}</WorkspaceNamed></span>
                <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{t(on ? "web-pages.profiles.workspaces.on" : "web-pages.profiles.workspaces.off", { name: w.name })}</span>
              </span>
              {busy && <Spinner inline />}
              <span className={connectsCss.mSwitch} data-on={on || undefined} />
            </ListRow>
          );
        })}
    </>
  );
}

/**
 * How it runs, one card under 运行: which of its models may be used (a row to their page: how many of how many on), its
 * subscription's default Fast, and commands put to the background as a new message comes (Claude Code's; a station
 * older than the setting says nothing of it).
 */
function RunRows({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const picks = !p.decisionOnly;
  const background = p.runtimes.includes("claude") && p.backgroundOnMessage !== undefined;
  if (!picks && p.fast == null && !background) return null;
  const all = (p.available ?? []).length;
  return (
    <>
      <SectionHeader title={t("web-mobile.profiles.run")} start={24} />
      <ListCard>
        {picks && (
          <ListRow onClick={() => app.push(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(p.id)}/models/edit`)}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("web-pages.profiles.models")}</span>
            {p.modelsSaving != null && <Spinner inline />}
            <span className={listsCss.mRowNote}>{all > 0 ? `${p.models.length} / ${all}` : `${p.models.length}`}</span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        )}
        {p.fast != null && <FastRow p={p} />}
        {background && <BackgroundRow p={p} put={(on) => api.putProfile(p.id, { backgroundOnMessage: on })} />}
      </ListCard>
    </>
  );
}

function FastRow({ p }: { p: Profile }) {
  const api = useApi();
  const station = useStation();
  const act = useAct();
  const busy = useDoing("profile.put", { station: station.address, id: p.id });
  const error = useDoingFailed("profile.put", { station: station.address, id: p.id });
  return <ListRow onClick={busy ? undefined : () => act(api.putProfile(p.id, { fast: !p.fast }), t("web-mobile.profiles.what.fast"), p.fast ? t("web-mobile.profiles.fastOff") : t("web-mobile.profiles.fastOn"))}>
    <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{t("web-mobile.profiles.fast")}</span>
      <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{t("web-mobile.profiles.fastNote")}</span></span>
    {busy && <Spinner inline />}{error && <FailedMark error={error} size={14} />}
    <span className={connectsCss.mSwitch} data-on={p.fast || undefined} />
  </ListRow>;
}

/**
 * Its allowance, the card under its account's, no title over it (its windows say what they are): window by window what
 * is left and when it refills, its credits, its resets; when it was read under them (read again from the page's "…" with
 * its check). One that could not be read says why; none to read (a key's), no card.
 */
function Quota({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const refreshing = useDoing("profile.quota", { station: station.address, id: p.id });
  const busy = useDoing("profile.resetQuota", { station: station.address, id: p.id });
  const error = useDoingFailed("profile.resetQuota", { station: station.address, id: p.id });
  const windows = p.quota?.state === "ok" ? p.quota.windows : [];
  const trouble = quotaTrouble(p.quota);
  if (trouble) {
    return (
      <ListCard>
        <ListRow>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}><Presence state={p.quota?.state === "blocked" ? "error" : "offline"} /> {p.quota?.state === "blocked" ? t("web-mobile.history.blocked") : t("web-mobile.profiles.noQuota")}</span>
            <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>
          </span>
        </ListRow>
      </ListCard>
    );
  }
  if (!windows.length && !p.quota?.creditsText && p.quota?.resetCount == null) return null;
  return (
    <>
      <ListCard>
        {!!windows.length && (
          <div className={css.mQuotaDials}>
            <QuotaBars quota={p.quota} />
            {/* When it was read, under them (being read: said so). */}
            {refreshing ? <WaitLine className={css.mQuotaRead} text={t("web-mobile.profiles.refreshingQuota")} />
              : p.quota?.time?.checkedAt && <p className={css.mQuotaRead}>{t("web-mobile.profiles.quotaChecked", { ago: p.quota.time.checkedAt.ago })}</p>}
          </div>
        )}
        {p.quota?.creditsText && <ListRow><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("web-mobile.profiles.credits")}</span><span className={listsCss.mRowNote}>{p.quota.creditsText}</span></ListRow>}
        {p.quota?.resetCount != null && <ListRow onClick={p.quota.resetCount > 0 && !busy ? () => confirm(app, {
          title: t("web-mobile.profiles.resetAsk"), text: t("web-mobile.profiles.resetText", { name: p.name, reset: p.quota?.resetText ?? "" }), action: t("web-mobile.profiles.resetAction"), atOnce: "web-mobile.profiles.resetFailed",
          run: () => api.resetQuota(p.id).then(() => app.toast(t("web-mobile.profiles.resetDone"))),
        }) : undefined}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{t("web-mobile.profiles.resets")}</span><span className={listsCss.mRowNote}>{p.quota.resetText}</span></span>
          {busy && <Spinner inline />}{error && <FailedMark error={error} size={14} />}
          <span className={p.quota.resetCount > 0 ? partsCss.mLink : partsCss.mMuted}>{t("web-mobile.profiles.reset")}</span>
        </ListRow>}
      </ListCard>
    </>
  );
}

/**
 * What was asked of a setting, shown at once while the station saves it (`put`), then the station's own again. Each ask
 * builds on the one before, not on what the station said last; one at a time goes, the latest asked waiting for it, so
 * two quick taps both count. Failing, it goes back to how it is (and the toast says why).
 */
function useAsked<T>(id: string, real: T, put: (value: T) => Promise<unknown>, failed: string): { value: T; busy: boolean; ask: (value: T) => void } {
  const app = useApp();
  const [asked, setAsked] = useState<{ value: T; done: boolean } | null>(null);
  const busy = useDoing("profile.put", { station: useStation().address, id });
  const going = useRef(false);
  const next = useRef<{ value: T } | null>(null);
  const latest = useRef(real);
  latest.current = real;
  // The station's word after the last went through: its own again.
  useEffect(() => { setAsked((a) => (a?.done ? null : a)); }, [real]);
  const send = (value: T) => {
    going.current = true;
    put(value).then(
      () => { if (!next.current) setAsked(JSON.stringify(latest.current) === JSON.stringify(value) ? null : { value, done: true }); },
      (e: unknown) => { app.toast(t(failed, { error: e instanceof Error ? e.message : String(e) })); if (!next.current) setAsked(null); },
    ).finally(() => {
      const waiting = next.current;
      next.current = null;
      if (waiting) send(waiting.value);
      else { going.current = false;  }
    });
  };
  const ask = (value: T) => {
    setAsked({ value, done: false });
    if (going.current) next.current = { value };
    else send(value);
  };
  return { value: asked ? asked.value : real, busy, ask };
}

/** Whether a new message sends what runs to the background: the switch goes over at once, a spinner by it till saved. */
function BackgroundRow({ p, put }: { p: Profile; put: (on: boolean) => Promise<unknown> }) {
  const { value: on, busy, ask } = useAsked(p.id, !!p.backgroundOnMessage, put, "web-mobile.profiles.saveFailed");
  return (
    <ListRow onClick={() => ask(!on)}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{t("web-mobile.profiles.background")}</span>
        <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{on ? t("web-mobile.profiles.backgroundOn") : t("web-mobile.profiles.backgroundOff")}</span>
      </span>
      {busy && <Spinner inline />}
      <span className={connectsCss.mSwitch} data-on={on || undefined} />
    </ListRow>
  );
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
function Models({ p, put, bare = false, page = false }: { p: Profile; put: (models: string[]) => Promise<unknown>; bare?: boolean; page?: boolean }) {
  const station = useStation();
  const api = useApi();
  const act = useAct();
  const checking = useDoing("profile.check", { station: station.address, id: p.id });
  const checkFailed = useDoingFailed("profile.check", { station: station.address, id: p.id });
  const [filter, setFilter] = useState("");
  const all = [...(p.available ?? [])].sort();
  const shown = all.filter((m) => [m, p.names[m] ?? m].some((s) => s.toLowerCase().includes(filter.trim().toLowerCase())));
  // Ticked at once; each tick builds on the last asked (useAsked), not on the station's list from before it.
  const models = p.models;
  const busy = p.modelsSaving != null;
  const ask = (models: string[]) => act(put(models), t("web-mobile.profiles.what.models"));
  const save = (next: string[]) => ask(next);
  const filtered = !!filter.trim();
  const [typed, setTyped] = useState("");
  const adding = useDoing("profile.addModel", { station: station.address, id: p.id });
  const addTyped = () => { if (typed.trim() && !adding) { act(api.addModel(p.id, typed.trim()), t("web-mobile.profiles.what.models")); setTyped(""); } };
  // A provider that answers the automatic decisions alone: the models its probe found, as they are.
  if (p.decisionOnly) {
    return (
      <>
        <SectionHeader title={t("web-mobile.profiles.decisionModels")} start={24} />
        {(p.decisionModels ?? []).length > 0 && <ListCard>{(p.decisionModels ?? []).map((m) => <ListRow key={m}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{m}</span></span></ListRow>)}</ListCard>}
        {p.decisionText && <p className={css.mProfileNote}>{p.decisionText}</p>}
      </>
    );
  }
  return (
    <>
      {/* On the step after it is added (PickModelsScreen) the screen says what these are; on their own page
          (ProfileModelsScreen) its title how many are on. */}
      {!bare && !page && <SectionHeader title={t(busy ? "web-mobile.profiles.modelsSaving" : "web-mobile.profiles.models", { on: models.length, n: all.length })} start={24} />}
      {!bare && <p className={css.mProfileNote}>{all.length === 0 ? t("web-mobile.profiles.modelsEmpty") : t("web-mobile.profiles.modelsNote")}</p>}
      <div className={`${settingsCss.mProfileTools} ${settingsCss.mProfileLinks}`}>
        <button type="button" className={partsCss.mLink} disabled={checking} onClick={() => act(api.checkProfile(p.id), t("web-mobile.profiles.what.refreshModels"), t("web-mobile.profiles.checkDone"))}>
          {checking ? <Spinner inline /> : checkFailed ? <FailedMark error={checkFailed} size={12} /> : null}{checking ? t("web-mobile.profiles.refreshing") : t("web-mobile.profiles.refreshModels")}
        </button>
        <span className={partsCss.mGrow} />
        {all.length > 0 && <>
          <button type="button" className={partsCss.mLink} disabled={busy} onClick={() => save([...models, ...shown])}>{filtered ? t("web-mobile.profiles.selectAllFiltered") : t("web-mobile.annotate.selectAll")}</button>
          <button type="button" className={partsCss.mLink} disabled={busy} onClick={() => save(models.filter((m) => !shown.includes(m)))}>{filtered ? t("web-mobile.profiles.selectNoneFiltered") : t("web-mobile.workspace.selectNone")}</button>
        </>}
      </div>
      {/* A provider that does not list its models: one is named by hand. */}
      {p.canAddModel && <div className={settingsCss.mProfileTools}><Field value={typed} onChange={setTyped} placeholder={t("web-mobile.profiles.addModelPlaceholder")} /><button type="button" className={partsCss.mLink} disabled={!typed.trim() || adding} onClick={addTyped}>{adding ? <Spinner inline /> : t("web-mobile.profiles.addModel")}</button></div>}
      {all.length > 10 && <div className={settingsCss.mProfileTools}><Field value={filter} onChange={setFilter} placeholder={t("web-mobile.profiles.filterModels")} /></div>}
      {/* By series, newest first (the core's). */}
      {p.series.map((s) => {
        const list = s.models.filter((m) => shown.includes(m));
        if (list.length === 0) return null;
        return (
          <div key={s.name}>
            <div className={listsCss.mGroupLabel} style={{ paddingLeft: 24, paddingRight: 24 }}>{s.name}</div>
            {list.map((m) => {
              const on = models.includes(m);
              // Not yet as the station has it: on its way.
              const saving = p.modelsSaving?.includes(m);
              return (
                <button key={m} type="button" className={settingsCss.mModelRow} disabled={busy} onClick={() => save(on ? models.filter((x) => x !== m) : [...models, m])}>
                  <span className={settingsCss.mCheck} data-on={on || undefined}>{on && <Check size={14} />}</span>
                  <span className={partsCss.mGrow}>{p.names[m] ?? m}</span>
                  {saving && <Spinner inline />}
                </button>
              );
            })}
          </div>
        );
      })}
    </>
  );
}

const SIGNING_IN = ["starting", "needs_code", "needs_approval", "verifying"];
/** Whether a profile is signed in to its account from here (a subscription's, or one on an account: OpenCode Go's,
 *  Kimi Code's), not on the machine's own login. */
const signsIn = (p: Profile) => (p.access.kind === "subscription" || !!p.access.login) && !p.machine;
/** Whether its account is to be signed in to: its check says so, or a sign-in is under way. */
const signInNeeded = (p: Profile) => p.check?.state === "login" || (!!p.login && SIGNING_IN.includes(p.login.state));
/** Whether its sign-in's card asks for one (its buttons): needed, or the last one failed. Signed in and well, it is
 *  asked for from its "…" (ProfileMenu) instead. */
const signInAsked = (p: Profile) => signInNeeded(p) || p.login?.state === "failed";

/** Its sign-in begun on the station; one that could not begin, said so. */
function useStartSignIn(p: Profile) {
  const app = useApp();
  const api = useApi();
  return () => { api.startLogin(p.id).catch((e: Error) => app.toast(t("web-mobile.profiles.startLoginFailed", { error: e.message }))); };
}

/**
 * A subscription's sign-in: run on the station's machine, the browser steps relayed here. Signed in and well, the
 * card only says where it stands (signing in again is in its "…"), and while one asked from there starts, the wait for
 * its link.
 */
function SignIn({ p, head }: { p: Profile; head: ReactNode }) {
  const app = useApp();
  const api = useApi();
  const start = useStartSignIn(p);
  const job = p.login;
  const active = !!job && SIGNING_IN.includes(job.state);
  const needed = signInNeeded(p);
  const provider = p.access.kind === "opencode-go" ? "OpenCode" : p.access.provider === "kimi-code" ? "Kimi" : p.runtime === "claude" ? "Claude" : p.runtime === "grok" ? "Grok" : p.runtime === "cursor" ? "Cursor" : p.runtime === "devin" ? "Devin" : "ChatGPT";
  const busy = useDoing("profile.login", { station: useStation().address, id: p.id });
  const cancelling = useDoing("profile.cancelLogin", { station: useStation().address, id: p.id });
  const inStationBusy = useDoing("profile.loginBrowser", { station: useStation().address, id: p.id });
  const [manual, setManual] = useState(false);
  const previous = useRef(job?.state);
  useEffect(() => {
    if (job?.state === "done" && previous.current && previous.current !== "done") app.toast(t("web-mobile.profiles.signedIn"));
    previous.current = job?.state;
  }, [job?.state]); // eslint-disable-line react-hooks/exhaustive-deps
  // One card for the account: where it stands at its top (no title over it saying it again), while signing in a way out
  // at that line's end, then what to do.
  return (
    <div className={`${listsCss.mCard} ${settingsCss.mFormGroup} ${css.mSignIn}`}>
      <div className={css.mSignInHead}>
        <div className={settingsCss.mProfileHead}>{head}</div>
        {active && (
          <button type="button" className={css.mSignInCancel} disabled={cancelling} aria-busy={cancelling || undefined}
            onClick={() => { api.cancelLogin(p.id).catch((e: Error) => app.toast(t("web-mobile.profiles.cancelLoginFailed", { error: e.message }))); }}>
            {cancelling && <Spinner inline />}{t("web-mobile.profiles.cancelLogin")}
          </button>
        )}
      </div>
      {active ? <LoginSteps job={job} provider={provider} send={(code) => api.loginCode(p.id, code)} inStation={{ ask: () => api.loginBrowser(p.id), busy: inStationBusy }} /> : signInAsked(p) ? (
        <>
          {/* What was off, or how it is done, in words. */}
          {job?.state === "failed" ? <p className={`${partsCss.mError} ${partsCss.mSmall}`}>{t("web-mobile.profiles.loginFailed", { error: job.error ?? "" })}</p>
            : needed ? <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.profiles.loginWhere", { name: NAME })}</p> : null}
          <div className={css.mSignInActions}>
            <Button label={job?.state === "done" || !needed ? t("web-mobile.profiles.relogin") : t("web-mobile.workspaces.signIn")} primary={needed && job?.state !== "done"} busy={busy} onClick={start} />
            {/* OpenCode's has no command to run by hand. */}
            {p.loginCommand && <LinkButton label={t("web-mobile.profiles.manualShort")} onClick={() => setManual(!manual)} />}
          </div>
          {manual && p.loginCommand && <CommandBox text={p.loginCommand} />}
        </>
      ) : busy ? <WaitLine text={t("web-mobile.profiles.loginLink", { provider })} /> : null}
    </div>
  );
}

/**
 * A plan's sign-in on a station without the runtime it signs in with (core `install`): installing it first, how that
 * stands, and its button when the viewer may (`software.update`). The sign-in starts once it is installed.
 */
function InstallStep({ install }: { install: RuntimeInstall }) {
  const station = useStation().address;
  const busy = useDoing("software.update", { station, id: install.runtime });
  const api = useApi();
  const act = useAct();
  return (
    <div className={`${listsCss.mCard} ${settingsCss.mFormGroup} ${css.mSignIn} ${css.mFlowCard}`}>
      <b className={listsCss.mRowTitle}>{install.title}</b>
      {install.detail ? <p className={partsCss.mError}>{install.detail}</p> : <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{install.note ?? t("web-pages.profiles.installThenSignIn")}</p>}
      {install.state === "installing" && <Progress part={install.percent != null ? install.percent / 100 : null} label={install.title} />}
      {install.action && <Button label={install.action} primary busy={busy} onClick={() => act(api.updateSoftware(install.runtime), install.action!)} />}
    </div>
  );
}

/** What the person does in the browser for a sign-in under way: open the page and paste the code back (Claude, Devin), copy the code and open the page (Codex), or only open the page and confirm there (Cursor). Where its job says the
 * station has a browser of its own (`browser`), the same page there (`inStation`: what asks the station to open it),
 * seldom used: in a ⋯ after the page's button (docs/ui-panels.md: what is used least goes into the row's ⋯). Its tab's
 * view opens here (screen/InStation.tsx); Claude's comes back to its command there, with no code to paste. */
function LoginSteps({ job, provider, send, inStation }: {
  job: LoginJob | null | undefined; provider: string; send: (code: string) => Promise<unknown>; inStation?: { ask(): Promise<unknown>; busy: boolean } | undefined;
}) {
  const app = useApp();
  const station = useStation();
  const open = useInStation(station.address);
  // The same page in the station's browser (回到 … while its tab is open), in a ⋯ after the page's button.
  const label = t(job?.screen !== undefined ? "common.login.backToStation" : "common.login.openInStation", { station: station.name });
  const otherWays = t("common.login.otherWays");
  const stationStep = inStation && job?.browser ? (
    <button type="button" className={css.mStepMore} aria-label={otherWays} disabled={inStation.busy}
      onClick={() => app.sheet({ height: 0.25, content: () => (
        <>
          <SheetGrab />
          <SheetHead title={otherWays} />
          <div className={sheetsCss.mSheetScroll}>
            <PickRow label={label} onClick={() => { app.sheet(null); open(inStation.ask, label); }} />
          </div>
        </>
      ) })}>
      <More size={18} />
    </button>
  ) : null;
  const [code, setCode] = useState("");
  const operation = useAction(send, () => setCode(""));
  const busy = operation.busy;
  const error = operation.error?.message;
  const [copied, setCopied] = useState(false);
  const filled = provider === "OpenCode" || provider === "Kimi";
  if (!job || job.state === "starting") return <WaitLine text={t("web-mobile.profiles.loginLink", { provider })} />;
  if (job.state === "verifying") return <WaitLine text={t("web-mobile.profiles.finishing")} />;
  if (job.state === "done") return <WaitLine text={t("web-mobile.profiles.adding")} />;
  // No code: the page only asks to confirm (Cursor's).
  if (job.state === "needs_approval" && job.url && !job.userCode) {
    return (
      <>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.profiles.cursorNote")}</p>
        <span className={css.mStepButtons}>
          <Button label={t("web-mobile.profiles.openAuth")} primary onClick={() => void window.open(job.url!, "_blank", "noopener")} />
          {stationStep}
        </span>
      </>
    );
  }
  if (job.state === "needs_approval" && job.url && job.userCode) {
    return (
      <>
        <span className={css.mDeviceCode}>{job.userCode}</span>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{provider === "OpenCode" ? t("web-mobile.profiles.opencodeNote") : provider === "Kimi" ? t("web-mobile.profiles.kimiNote") : provider === "Grok" ? t("web-mobile.profiles.grokNote") : t("web-mobile.profiles.codexNote", { name: NAME })}</p>
        {/* OpenCode's and Kimi's pages have the code in their address: only compared there, not copied. */}
        <span className={css.mStepButtons}>
          <Button label={filled ? t("web-mobile.profiles.openAuth") : copied ? t("web-mobile.profiles.reopen") : t("web-mobile.profiles.copyOpen")} primary
            onClick={() => { if (filled) return void window.open(job.url!, "_blank", "noopener"); void navigator.clipboard.writeText(job.userCode!).then(() => setCopied(true), () => app.toast(t("web-mobile.profiles.copyCodeFailed"))).finally(() => window.open(job.url!, "_blank", "noopener")); }} />
          {stationStep}
        </span>
      </>
    );
  }
  // Two steps, each said once: what to do on the page (its button under it), then the code it gives, pasted beside
  // what sends it.
  if (job.state === "needs_code" && job.url) {
    return (
      <>
        <p className={css.mStep}><span className={css.mStepN}>1</span>{provider === "Devin" ? t("web-mobile.profiles.step1ShortDevin", { name: NAME }) : t("web-mobile.profiles.step1Short", { name: NAME })}</p>
        <span className={`${css.mStepBody} ${css.mStepButtons}`}><Button label={t("web-mobile.profiles.openAuth")} primary={!code.trim()} onClick={() => void window.open(job.url!, "_blank", "noopener")} />{stationStep}</span>
        <p className={css.mStep}><span className={css.mStepN}>2</span>{t("web-mobile.profiles.step2Short")}</p>
        {error && <p className={partsCss.mError}>{error}</p>}
        <div className={css.mCodeRow}>
          <input className={listsCss.mField} data-mono autoComplete="off" spellCheck={false} value={code} placeholder={t("web-mobile.profiles.pasteCode")} onChange={(e) => setCode(e.target.value)} />
          <Button label={t("web-mobile.profiles.finishShort")} primary busy={busy} enabled={!!code.trim()} onClick={() => { void operation.run(code.trim()); }} />
        </div>
      </>
    );
  }
  return null;
}

interface EnvRow { row: number; key: string; value: string; masked: string | null; original: string | null }

/** The variables a custom profile runs with: what reaches its runtime's model service, set by hand. */
function EnvSheet({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const next = useRef(1);
  const [rows, setRows] = useState<EnvRow[]>(() => p.env.map((e) => ({ row: next.current++, key: e.key, value: e.secret ? "" : e.value, masked: e.secret ? e.value : null, original: e.key })));
  const busy = useDoing("profile.put", { station: useStation().address, id: p.id });
  const patch = (): Record<string, string | null> => {
    const out: Record<string, string | null> = {};
    const kept = new Set(rows.map((r) => r.key.trim()));
    for (const e of p.env) if (!kept.has(e.key)) out[e.key] = null;
    for (const r of rows) {
      const key = r.key.trim();
      if (!key) continue;
      if (r.original && r.original !== key) out[r.original] = null;
      if (r.masked !== null && r.value === "" && r.original === key) continue;
      out[key] = r.value;
    }
    return out;
  };
  const update = (row: number, change: Partial<EnvRow>) => setRows(rows.map((r) => (r.row === row ? { ...r, ...change } : r)));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.profiles.env")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.profiles.envNote", { route: "{route}" })}</p>
        {rows.map((r) => (
          <div key={r.row} className={css.mEnvRow}>
            <input className={listsCss.mField} data-mono spellCheck={false} value={r.key} placeholder="NAME" onChange={(e) => update(r.row, { key: e.target.value })} />
            <input className={listsCss.mField} data-mono spellCheck={false} autoComplete="off" type={r.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key) ? "password" : "text"}
              value={r.value} placeholder={r.masked !== null ? t("web-mobile.connects.savedToken", { token: r.masked }) : t("web-mobile.profiles.value")} onChange={(e) => update(r.row, { value: e.target.value })} />
            <button type="button" className={partsCss.mLink} onClick={() => setRows(rows.filter((x) => x.row !== r.row))}>{t("common.delete")}</button>
          </div>
        ))}
        <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} onClick={() => setRows([...rows, { row: next.current++, key: "", value: "", masked: null, original: null }])}>{t("web-mobile.profiles.addEnv")}</button>
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={t("common.save")} primary busy={busy} onClick={() => { app.sheet(null); api.putProfile(p.id, { env: patch() }).then(() => app.toast(t("web-mobile.profiles.saved")), (e: Error) => app.toast(t("web-mobile.profiles.saveFailed", { error: e.message }))); }} />
        </div>
      </div>
    </>
  );
}

/** The providers to add a profile of (`groups`), a card each kind, under what to do (`hint`) and the machine's own
 *  logins offered (`offers`). */
function ProviderPick({ hint, offers, groups, onPick }: { hint: string; offers?: ReactNode; groups: ProviderGroup[]; onPick(p: ApiProvider): void }) {
  return (
    <>
      <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{hint}</p>
      {offers}
      {groups.map((g) => (
        <div key={g.id}>
          <SectionHeader title={g.title} start={6} />
          <ListCard>
            {g.providers.map((p) => (
              <ListRow key={p.id} onClick={() => onPick(p)}>
                <ProviderMark runtime={p.runtime ?? "claude"} kind={p.kind || "api-provider"} mark={p.mark} size={18} />
                <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{p.name}</span>
                <ChevronRight size={16} />
              </ListRow>
            ))}
          </ListCard>
        </div>
      ))}
    </>
  );
}
const SAMPLE_HINT = sampleWords(30);

/**
 * A new profile on the station in context, as the core's add flow has it (profileFlow.ts): the providers by group, then
 * how to connect the one picked (a plan signed in, or a key checked first: the profile is made only if it works).
 */
export function NewProfileScreen() {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const overview = useOverview(station.address).value;
  const { d, edit, submit, submitting } = useProfileFlow(station.address);
  // `?kind=`: a machine login kept in the keychain, signed in again for ember as the vendor's plan.
  const [params, setParams] = useSearchParams();
  const kind = params.get("kind");
  useEffect(() => {
    if (!d || !kind) return;
    if (!d.tile) edit({ provider: kind === "claude-sub" ? "anthropic" : "openai" });
    else if (d.step === "method") { edit({ method: "plan" }); setParams({}, { replace: true }); }
  }, [d?.tile?.id, d?.step, kind]); // eslint-disable-line react-hooks/exhaustive-deps
  const [login, setLogin] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const inStationBusy = useDoing("login.browser", { station: station.address, id: login ?? "" });
  const pending = login ? overview?.logins.find((l) => l.id === login) : undefined;
  // What the plan signs in to (the core's): a runtime's subscription, or OpenCode's account for OpenCode Go.
  const runtime = d?.signIn?.runtime ?? (d?.tile?.runtime === "codex" || d?.tile?.runtime === "grok" || d?.tile?.runtime === "cursor" || d?.tile?.runtime === "devin" ? d.tile.runtime : "claude");
  const provider = d?.signIn?.provider ?? (runtime === "claude" ? "Claude" : runtime === "grok" ? "Grok" : runtime === "cursor" ? "Cursor" : runtime === "devin" ? "Devin" : "ChatGPT");
  const begin = () => api.newLogin(runtime, d?.signIn?.access).then(({ id }) => setLogin(id), (e: Error) => setError(e.message));
  // Added: on to choosing its models (PickModelsScreen), the step chats need.
  const go = (id: string, message: string) => { app.toast(message); app.replace(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(id)}/models`); };
  // The sign-in made its profile: on to it.
  useEffect(() => { if (pending?.created) go(pending.created, t("web-mobile.profiles.signedInAdded")); }, [pending?.created]); // eslint-disable-line react-hooks/exhaustive-deps
  // A plan's sign-in starts when it is chosen; leaving before it made its profile leaves nothing behind.
  // A station without the runtime it signs in with installs it first (core `install`): the sign-in starts after.
  const planning = d?.step === "connect" && d.method === "plan" && !d.install;
  const started = useRef(false);
  const dropped = (e: Error) => app.toast(t("web-mobile.profiles.dropFailed", { error: e.message }));
  useEffect(() => {
    if (planning && !started.current) { started.current = true; setError(null); void begin(); }
    if (!planning && started.current) { started.current = false; if (login && !pending?.created) api.dropLogin(login).catch(dropped); setLogin(null); }
  }, [planning]); // eslint-disable-line react-hooks/exhaustive-deps
  // Back goes a step back, from the picker out.
  const leave = () => { if (d && d.step !== "pick") edit({ provider: "" }); else app.pop(); };
  const job = pending?.job ?? null;
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={d && d.step !== "pick" ? t("common.back") : t("common.cancel")} onBack={leave} title={d?.title ?? t("web-mobile.newChat.addProfile")} sub={<span className={barsCss.mNavbarNote}><StationNamedAt station={station.address} name={station.name} /></span>} />
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18} ${settingsCss.mSteps}`}>
        {!d ? <Waiting text={t("web-pages.profiles.loading")} sample={<ProviderPick hint={SAMPLE_HINT} groups={SAMPLE_PROVIDERS} onPick={() => undefined} />} /> : d.step === "pick" ? (
          <ProviderPick hint={d.hint} groups={d.groups} onPick={(p) => edit({ provider: p.id })}
            offers={overview && <div><MachineLoginOffers inForm logins={overview.machineLogins} onSignIn={(c) => edit({ provider: c === "claude-sub" ? "anthropic" : "openai", method: "plan" })} /></div>} />
        ) : d.step === "method" ? (
          <ListCard>
            {d.choices.map((c) => <PickRow key={c.id} label={c.title} sub={c.hint} onClick={() => edit({ method: c.id })} leading={<ProviderMark runtime={runtime} kind={c.id === "plan" && d.tile?.kind !== "opencode-go" && d.tile?.id !== "moonshotai" ? "subscription" : d.tile?.kind ?? "api-provider"} mark={d.tile?.mark} size={18} />} />)}
          </ListCard>
        ) : d.method === "plan" ? (
          d.install ? <InstallStep install={d.install} />
          : error || pending?.error || job?.state === "failed" || job?.state === "cancelled" ? (
            <>
              <p className={partsCss.mError}>{error ?? pending?.error ?? job?.error ?? t("web-mobile.profiles.loginIncomplete")}</p>
              <Button label={t("web-mobile.profiles.restart")} primary={false} onClick={() => { if (login) api.dropLogin(login).catch(dropped); setLogin(null); setError(null); void begin(); }} />
            </>
          ) : <LoginSteps job={job} provider={provider} send={(code) => api.newLoginCode(login!, code)}
            inStation={login ? { ask: () => api.newLoginBrowser(login), busy: inStationBusy } : undefined} />
        ) : (
          <ConnectForm key={d.tile?.id} d={d} edit={edit} busy={submitting}
            onSubmit={() => { submit().then(({ id }) => go(id, t("web-mobile.profiles.verifiedAdded")), () => undefined); }} />
        )}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/** The form of a key: what is typed is kept here as it is typed (the core has it as it is named, and judges it). */
function ConnectForm({ d, edit, busy, onSubmit }: { d: ProfileFlowView; edit(input: Record<string, unknown>): void; busy: boolean; onSubmit(): void }) {
  const [endpoint, setEndpoint] = useState(d.endpoint);
  const [key, setKey] = useState(d.key);
  return (
    <>
      {d.showEndpoint && (
        <>
          <b className={sheetsCss.mFormLabel}>{t("common.provider.endpoint")}</b>
          <input className={listsCss.mField} data-mono autoComplete="off" spellCheck={false} autoCapitalize="none" disabled={d.pending} value={endpoint} placeholder={d.endpointExample ?? "https://"}
            onChange={(e) => { setEndpoint(e.target.value); edit({ endpoint: e.target.value }); }} />
          {d.endpointHint && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{d.endpointHint}</p>}
        </>
      )}
      {(d.regions?.length ?? 0) > 1 && (
        <>
          <b className={sheetsCss.mFormLabel}>{t("web-mobile.profiles.region")}</b>
          <ListCard>
            {(d.regions ?? []).map((r) => <PickRow key={r.id} label={r.label} checked={r.id === d.region} onClick={() => edit({ region: r.id })} />)}
          </ListCard>
        </>
      )}
      {d.protocols.length > 1 && (
        <>
          <b className={sheetsCss.mFormLabel}>{t("web-mobile.profiles.protocol")}</b>
          <ListCard>
            {d.protocols.map((p) => <PickRow key={p.id} label={p.label} checked={p.id === d.protocol} onClick={() => edit({ protocol: p.id })} />)}
          </ListCard>
        </>
      )}
      {d.showKey && (
        <>
          <b className={sheetsCss.mFormLabel}>{d.keyLabel}</b>
          <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} disabled={d.pending} value={key} placeholder={t("web-mobile.profiles.keyPlaceholder")}
            onChange={(e) => { setKey(e.target.value); edit({ key: e.target.value }); }} />
          {d.error ? <p className={partsCss.mError}>{d.error}</p> : d.keyHint && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{d.keyHint}</p>}
        </>
      )}
      <Button label={d.submitLabel} primary busy={busy || d.pending} enabled={d.canSubmit} onClick={onSubmit} />
      {d.usesLine && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{d.usesLine}</p>}
    </>
  );
}

/** The machine's own logins a profile could use now (the core's `offered`). */
function machineOffers(logins: MachineLogin[] | undefined): MachineLogin[] {
  return (logins ?? []).filter((l) => l.offered);
}


/**
 * The accounts the station machine's own Claude Code and Codex are signed in with, not used by a profile yet (as the
 * desktop's MachineLoginOffers, ../pages/Accounts.tsx): one kept in a file is used as it is (a profile on the machine's
 * login, which follows it); one kept only in the keychain is offered as a sign-in with the same account (`onSignIn`); a
 * refused account is said so, with its reason, and nothing to do with it. The station in context.
 */
export function MachineLoginOffers({ logins, onSignIn, inForm = false }: { logins: MachineLogin[] | undefined; onSignIn: (choice: Choice) => void; inForm?: boolean }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  // The one asked spins till the station has made its profile; the others wait. One that failed has the failure mark a few seconds.
  const list = useDoingList();
  const doing = list.filter((d) => !failed(d) && doingMatches(d, "profile.useMachineLogin", { station: station.address }));
  const offers = machineOffers(logins);
  if (!offers.length) return null;
  const use = (l: MachineLogin) => {
    api.useMachineLogin(l.runtime).then(({ id }) => {
      app.toast(t("web-mobile.profiles.addedMachine"));
      app.replace(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(id)}/models`);
    }, (e: Error) => app.toast(t("web-mobile.profiles.addFailed", { error: e.message })));
  };
  return (
    <>
      <SectionHeader title={<StationInWords station={station.address} text={t("web-mobile.profiles.machineLogins", { station: station.name || t("web-main.machine.this") })} />} start={inForm ? 6 : 24} />
      <ListCard>
        {offers.map((l) => {
          const blocked = l.quota?.state === "blocked";
          const trouble = quotaTrouble(l.quota);
          const plan = l.planText || null;
          return (
            <ListRow key={l.runtime}>
              <ProviderMark runtime={l.runtime} kind="subscription" size={18} />
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}><Presence state={blocked ? "error" : "online"} /> {RUNTIME_LABEL[l.runtime]}{plan && <span className={settingsCss.mRowAside}> · {plan}</span>}</span>
                <span className={listsCss.mRowNote}>{blocked ? t("web-mobile.history.blocked") : t("web-mobile.profiles.machineSignedIn")}{l.email ? ` · ${l.email}` : ""}</span>
                {trouble && <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>}
              </span>
              <QuotaRings quota={l.quota} />
              {blocked ? null : l.usable
                ? <LinkButton label={t("web-mobile.profiles.useThis")} busy={doing.some((d) => d.params.runtime === l.runtime)}
                  failed={failedIn(list, "profile.useMachineLogin", { station: station.address, runtime: l.runtime })} enabled={doing.length === 0} onClick={() => use(l)} />
                : <button type="button" className={partsCss.mLink} onClick={() => onSignIn(l.runtime === "claude" ? "claude-sub" : "chatgpt-sub")}>{t("web-mobile.workspaces.signIn")}</button>}
            </ListRow>
          );
        })}
      </ListCard>
      {!inForm && <p className={settingsCss.mPageNote}>{t("web-mobile.profiles.machineNote", { name: NAME })}</p>}
    </>
  );
}
