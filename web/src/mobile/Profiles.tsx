// Profiles on a narrow screen (what the desktop's ../pages/Accounts.tsx does, in the Android app's manner): every
// station's in one list, a profile's
// page (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its
// key or variables; renaming, checking and deleting under "…"), and a new one.
import { useEffect, useMemo, useRef, useState } from "react";
import { useParams, useSearchParams } from "react-router";
import { stationApi, useAction, useOverview, useStationCall, useStations, type LoginJob, type Profile, type Quota, type StationView, type Tone } from "../api.ts";
import type { MachineLogin, ProfileFlowView } from "../core/shapes.ts";
import { ACCESS, KEYED } from "../format.ts";
import { Check, ChevronRight, More, Plus } from "../icons.tsx";
import type { Choice } from "../pages/Accounts.tsx";
import { useProfileFlow } from "../profileFlow.ts";
import { QuotaBars } from "../components.tsx";
import { StationContext, stationBase, useStation } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Presence } from "./Connects.tsx";
import { Button, FailedMark, failedIn, Field, LargeTitle, LinkButton, ListCard, ListRow, Loading, NavBar, NavButton, PickRow, ProviderMark, QuotaRings, SectionHeader, SlackMark, Spinner, TopBack, tNodes } from "./parts.tsx";
import { useAct } from "../toast.tsx";
import { doingMatches, failed, useDoing, useDoingFailed, useDoingList } from "../doing.ts";
import { ask, CommandBox, confirm } from "./sheets.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as historyCss from "./styles/history.css.ts";
import * as css from "./Profiles.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as chatCss from "./styles/chat.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
function useApi() {
  const station = useStation();
  const call = useStationCall(station.address);
  return useMemo(() => stationApi(call), [call]);
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
      <TopBack label={one?.name ?? t("web-mobile.settings.title")} onBack={app.pop} trailing={online.length > 0 ? <NavButton icon={Plus} iconSize={20} label={t("web-mobile.newChat.addProfile")} onClick={add} /> : undefined} />
      <LargeTitle small={one ? t("web-mobile.connects.on", { station: one.name }) : ""} big="Profile" />
      <p className={settingsCss.mPageNote}>{t("web-mobile.profiles.note")}</p>
      {!stations ? <Loading text={t("web-mobile.memory.readingStations")} /> : stations.map((s) => (
        <StationContext.Provider key={s.id} value={{ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${app.entry.id}/settings` }}>
          {!one && <SectionHeader title={s.online ? s.name : t("web-mobile.connects.stationOfflineTitle", { station: s.name })} start={24} />}
          <ListCard>
            {!s.overview ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{s.online ? t("web-mobile.reading") : t("web-mobile.profiles.offline")}</span></ListRow>
              : s.overview.profiles.length === 0 ? <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{t("web-mobile.profiles.none")}</span></ListRow>
              : s.overview.profiles.map((p) => <ProfileRow key={p.id} station={s} p={p} />)}
          </ListCard>
          {/* The machine's own logins not used yet, each offered as a profile. */}
          {s.online && s.overview && <MachineLoginOffers logins={s.overview.machineLogins} onSignIn={(kind) => app.push(app.at(`/s/${s.id}/profiles/new?kind=${kind}`))} />}
        </StationContext.Provider>
      ))}
      <div style={{ height: 30 }} />
    </div>
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
        {stations.map((s) => <PickRow key={s.id} label={s.name} onClick={() => { app.sheet(null); app.push(app.at(to(s))); }} />)}
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
  if (!p) return <div className={pagesCss.mScreen}><NavBar back={station.name || "Station"} onBack={app.pop} title="Profile" /><Loading text={overview.error?.message ?? (overview.value ? t("web-mobile.profiles.notFound") : t("web-mobile.reading"))} /></div>;
  return <ProfilePage p={p} />;
}

function ProfilePage({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const overview = useOverview(station.address).value;
  const users = p.usedBy.map((id) => overview?.connects.find((c) => c.id === id)).filter((c) => c !== undefined);
  // Asked from its menu, which has closed by then: the card says it is under way, and a few seconds why it failed.
  const checking = useDoing("profile.check", { station: station.address, id: p.id });
  const refreshing = useDoing("profile.quota", { station: station.address, id: p.id });
  const checkFailed = useDoingFailed("profile.check", { station: station.address, id: p.id });
  const quotaFailed = useDoingFailed("profile.quota", { station: station.address, id: p.id });
  const signingIn = !!p.login && ["starting", "needs_code", "needs_approval", "verifying"].includes(p.login.state);
  const keyed = KEYED.has(p.access.kind);
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name || "Station"} onBack={app.pop} title={p.name} sub={<span className={barsCss.mNavbarNote}>{accessLabel(p)}</span>}
        trailing={<NavButton icon={More} label={t("common.more")} onClick={() => app.sheet({ height: 0.5, content: () => <ProfileMenu p={p} /> })} />} />
      <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
        <div className={`${listsCss.mCard} ${settingsCss.mProfileHead}`}>
          <ProviderMark runtime={p.runtime} kind={p.access.kind} mark={p.providerMark} size={26} />
          <span className={partsCss.mGrow}>
            <span className={`${historyCss.mPill} ${css.mCheckPill}`} data-tone={p.checkTone}>{p.checkText}</span>
            <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{p.check ? p.check.detail.replace(/^可用[，,]\s*/, "") : t("web-mobile.profiles.notChecked")}{p.check?.time?.checkedAt ? t("web-mobile.profiles.checkedAgo", { ago: p.check.time.checkedAt.ago }) : ""}</span>
            {(checking || refreshing) && <span className={`${listsCss.mRowNote} ${chatCss.mWaiting}`}><Spinner size={12} />{checking ? t("web-mobile.versions.checking") : t("web-mobile.profiles.refreshingQuota")}</span>}
            {!checking && checkFailed !== undefined && <span className={`${listsCss.mRowNote} ${chatCss.mWaiting} ${partsCss.mRed}`}><FailedMark error={checkFailed} size={12} />{t("web-mobile.profiles.checkFailed", { error: checkFailed })}</span>}
            {!refreshing && quotaFailed !== undefined && <span className={`${listsCss.mRowNote} ${chatCss.mWaiting} ${partsCss.mRed}`}><FailedMark error={quotaFailed} size={12} />{t("web-mobile.profiles.quotaFailed", { error: quotaFailed })}</span>}
          </span>
        </div>
        {p.trouble && <ProfileRecovery p={p} />}
        {p.access.kind === "subscription" && !p.machine && <SignIn p={p} needed={p.check?.state === "login" || signingIn} />}
        {p.trouble?.action !== "quota" && <Quota p={p} />}
        {p.fast != null && <><SectionHeader title={t("web-mobile.profiles.run")} start={24} /><ListCard><FastRow p={p} /></ListCard></>}
        <Models p={p} put={(models) => api.putProfile(p.id, { models })} />
        {/* A station older than the setting says nothing of it. */}
        {p.runtimes.includes("claude") && p.backgroundOnMessage !== undefined && (
          <>
            <SectionHeader title={t("web-mobile.profiles.run")} start={24} />
            <ListCard>
              <BackgroundRow p={p} put={(on) => api.putProfile(p.id, { backgroundOnMessage: on })} />
            </ListCard>
          </>
        )}
        <SectionHeader title={t("web-mobile.profiles.usedBy")} start={24} />
        <ListCard>
          {users.length === 0 && <ListRow><span className={`${partsCss.mMuted} ${listsCss.mRowTitle}`}>{t("web-mobile.profiles.unused")}</span></ListRow>}
          {users.map((c) => (
            <ListRow key={c.id} onClick={() => app.push(`${stationBase(station.address)}/connects/${encodeURIComponent(c.id)}`)}>
              <SlackMark size={15} /><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{c.name}</span><span className={listsCss.mRowNote}>{c.modelName ?? (p.model ? p.names[p.model] ?? p.model : t("web-mobile.profiles.defaultModel"))}</span>
            </ListRow>
          ))}
        </ListCard>
        {keyed && (
          <>
            <SectionHeader title={t("web-mobile.history.account")} start={24} />
            <ListCard>
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
            </ListCard>
          </>
        )}
        {p.access.kind === "env" && (
          <>
            <SectionHeader title={t("web-mobile.profiles.env")} start={24} />
            <ListCard>
              {p.env.map((e) => <ListRow key={e.key}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={`${listsCss.mRowTitle} ${css.mMono}`}>{e.key}</span><span className={`${listsCss.mRowNote} ${css.mMono}`}>{e.value}</span></span></ListRow>)}
              <ListRow onClick={() => app.sheet({ height: 0.8, draggable: true, content: () => <EnvSheet p={p} /> })}><span className={`${partsCss.mAccent} ${listsCss.mRowTitle}`}>{t("web-mobile.profiles.editEnv")}</span></ListRow>
            </ListCard>
          </>
        )}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/** The core supplies the diagnosis and next step; the view opens the existing operation or editor. */
function ProfileRecovery({ p }: { p: Profile }) {
  const app = useApp();
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
    else if (issue.action === "env") app.sheet({ height: 0.8, draggable: true, content: () => <EnvSheet p={p} /> });
    else if (issue.action === "quota") act(api.refreshQuota(p.id), t("web-mobile.profiles.what.quota"), t("web-mobile.profiles.quotaUpdated"));
    else act(api.checkProfile(p.id), t("web-mobile.profiles.what.check"), t("web-mobile.profiles.checked"));
  };
  return <>
    <SectionHeader title={issue.title} start={24} />
    <div className={`${listsCss.mCard} ${settingsCss.mFormGroup}`}>
      <p className={`${partsCss.mSmall} ${settingsCss.mWrap}`}>{issue.detail}</p>
      <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{issue.next}</p>
      {!station.online && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.profiles.stationOffline", { station: station.name })}</p>}
      {issue.action === "command" && <CommandBox text={p.loginCommand} />}
      {issue.action !== "login" && <LinkButton label={issue.label} enabled={station.online}
        busy={checking || refreshing} failed={issue.action === "quota" ? quotaFailed : checkFailed} onClick={run} />}
      {["key", "env"].includes(issue.action) && <LinkButton label={t("web-mobile.profiles.recheck")} enabled={station.online} busy={checking} failed={checkFailed}
        onClick={() => act(api.checkProfile(p.id), t("web-mobile.profiles.what.check"), t("web-mobile.profiles.checked"))} />}
    </div>
  </>;
}

/** Renaming, checking, refreshing its allowance, deleting it (stopping one on the machine's login); not while a connect uses it. */
function ProfileMenu({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const station = useStation().address;
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
        <PickRow label={t("web-mobile.profiles.recheck")} busy={checking} failed={checkFailed} onClick={() => { app.sheet(null); api.checkProfile(p.id).then(() => app.toast(t("web-mobile.profiles.checked")), failed("web-mobile.profiles.checkFailed")); }} />
        <PickRow label={t("web-mobile.profiles.refreshQuota")} busy={refreshing} failed={quotaFailed} onClick={() => { app.sheet(null); api.refreshQuota(p.id).then(() => app.toast(t("web-mobile.profiles.quotaRefreshed")), failed("web-mobile.profiles.quotaFailed")); }} />
        <PickRow label={p.usedBy.length ? t("web-mobile.profiles.inUse", { action: p.machine ? t("web-mobile.connects.disable") : t("web-mobile.profiles.delete") }) : p.machine ? t("web-mobile.connects.disable") : t("web-mobile.profiles.delete")} accent enabled={p.usedBy.length === 0} onClick={() => confirm(app, p.machine ? {
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

/** Its allowance, window by window: what is left and when it refills; why it cannot be read, when the provider says. */
function FastRow({ p }: { p: Profile }) {
  const api = useApi();
  const station = useStation();
  const act = useAct();
  const busy = useDoing("profile.put", { station: station.address, id: p.id });
  const error = useDoingFailed("profile.put", { station: station.address, id: p.id });
  return <ListRow onClick={busy ? undefined : () => act(api.putProfile(p.id, { fast: !p.fast }), t("web-mobile.profiles.what.fast"), p.fast ? t("web-mobile.profiles.fastOff") : t("web-mobile.profiles.fastOn"))}>
    <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{t("web-mobile.profiles.fast")}</span>
      <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{t("web-mobile.profiles.fastNote")}</span></span>
    {busy && <Spinner size={14} />}{error && <FailedMark error={error} size={14} />}
    <span className={connectsCss.mSwitch} data-on={p.fast || undefined} />
  </ListRow>;
}

function Quota({ p }: { p: Profile }) {
  const app = useApp();
  const api = useApi();
  const station = useStation();
  const busy = useDoing("profile.resetQuota", { station: station.address, id: p.id });
  const error = useDoingFailed("profile.resetQuota", { station: station.address, id: p.id });
  const windows = p.quota?.state === "ok" ? p.quota.windows : [];
  const trouble = quotaTrouble(p.quota);
  if (trouble) {
    return (
      <>
        <SectionHeader title={t("web-mobile.profiles.quota")} trailing={p.quota?.time?.checkedAt ? t("web-mobile.profiles.quotaChecked", { ago: p.quota.time.checkedAt.ago }) : undefined} start={24} />
        <ListCard>
          <ListRow>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}><Presence state={p.quota?.state === "blocked" ? "error" : "offline"} /> {p.quota?.state === "blocked" ? t("web-mobile.history.blocked") : t("web-mobile.profiles.noQuota")}</span>
              <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{trouble}</span>
            </span>
          </ListRow>
        </ListCard>
      </>
    );
  }
  if (!windows.length && !p.quota?.creditsText && p.quota?.resetCount == null) return null;
  return (
    <>
      <SectionHeader title={t("web-mobile.profiles.quota")} trailing={p.quota?.time?.checkedAt ? t("web-mobile.profiles.quotaChecked", { ago: p.quota.time.checkedAt.ago }) : undefined} start={24} />
      <ListCard>
        {!!windows.length && <div className={css.mQuotaDials}><QuotaBars quota={p.quota} /></div>}
        {p.quota?.creditsText && <ListRow><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("web-mobile.profiles.credits")}</span><span className={listsCss.mRowNote}>{p.quota.creditsText}</span></ListRow>}
        {p.quota?.resetCount != null && <ListRow onClick={p.quota.resetCount > 0 && !busy ? () => confirm(app, {
          title: t("web-mobile.profiles.resetAsk"), text: t("web-mobile.profiles.resetText", { name: p.name, reset: p.quota?.resetText ?? "" }), action: t("web-mobile.profiles.resetAction"), atOnce: "web-mobile.profiles.resetFailed",
          run: () => api.resetQuota(p.id).then(() => app.toast(t("web-mobile.profiles.resetDone"))),
        }) : undefined}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{t("web-mobile.profiles.resets")}</span><span className={listsCss.mRowNote}>{p.quota.resetText}</span></span>
          {busy && <Spinner size={14} />}{error && <FailedMark error={error} size={14} />}
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
      {busy && <Spinner size={14} />}
      <span className={connectsCss.mSwitch} data-on={on || undefined} />
    </ListRow>
  );
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
function Models({ p, put }: { p: Profile; put: (models: string[]) => Promise<unknown> }) {
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
  const save = (next: string[]) => ask([...new Set(next)].sort());
  const filtered = !!filter.trim();
  const [typed, setTyped] = useState("");
  const adding = useDoing("profile.addModel", { station: station.address, id: p.id });
  const addTyped = () => { if (typed.trim() && !adding) { act(api.addModel(p.id, typed.trim()), t("web-mobile.profiles.what.models")); setTyped(""); } };
  return (
    <>
      <SectionHeader title={t(busy ? "web-mobile.profiles.modelsSaving" : "web-mobile.profiles.models", { on: models.length, n: all.length })} start={24} />
      <p className={css.mProfileNote}>{all.length === 0 ? t("web-mobile.profiles.modelsEmpty") : t("web-mobile.profiles.modelsNote")}</p>
      <div className={settingsCss.mProfileTools}>
        <button type="button" className={partsCss.mLink} disabled={checking} onClick={() => act(api.checkProfile(p.id), t("web-mobile.profiles.what.refreshModels"), t("web-mobile.profiles.checkDone"))}>
          {checking ? <Spinner size={12} /> : checkFailed ? <FailedMark error={checkFailed} size={12} /> : null}{checking ? t("web-mobile.profiles.refreshing") : t("web-mobile.profiles.refreshModels")}
        </button>
        <span className={partsCss.mGrow} />
        {all.length > 0 && <>
          <button type="button" className={partsCss.mLink} disabled={busy} onClick={() => save([...models, ...shown])}>{filtered ? t("web-mobile.profiles.selectAllFiltered") : t("web-mobile.annotate.selectAll")}</button>
          <button type="button" className={partsCss.mLink} disabled={busy} onClick={() => save(models.filter((m) => !shown.includes(m)))}>{filtered ? t("web-mobile.profiles.selectNoneFiltered") : t("web-mobile.workspace.selectNone")}</button>
        </>}
      </div>
      {/* A provider that does not list its models: one is named by hand. */}
      {p.canAddModel && <div className={settingsCss.mProfileTools}><Field value={typed} onChange={setTyped} placeholder={t("web-mobile.profiles.addModelPlaceholder")} /><button type="button" className={partsCss.mLink} disabled={!typed.trim() || adding} onClick={addTyped}>{adding ? <Spinner size={12} /> : t("web-mobile.profiles.addModel")}</button></div>}
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
                  {saving && <Spinner size={13} />}
                </button>
              );
            })}
          </div>
        );
      })}
    </>
  );
}

/** A subscription's sign-in: run on the station's machine, the browser steps relayed here. */
function SignIn({ p, needed }: { p: Profile; needed: boolean }) {
  const app = useApp();
  const api = useApi();
  const job = p.login;
  const active = !!job && ["starting", "needs_code", "needs_approval", "verifying"].includes(job.state);
  const provider = p.runtime === "claude" ? "Claude" : "ChatGPT";
  const busy = useDoing("profile.login", { station: useStation().address, id: p.id });
  const cancelling = useDoing("profile.cancelLogin", { station: useStation().address, id: p.id });
  const previous = useRef(job?.state);
  useEffect(() => {
    if (job?.state === "done" && previous.current && previous.current !== "done") app.toast(t("web-mobile.profiles.signedIn"));
    previous.current = job?.state;
  }, [job?.state]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
      <SectionHeader title={active ? t("web-mobile.profiles.loginActive", { provider }) : needed ? t("web-mobile.profiles.loginNeeded", { provider }) : t("web-mobile.profiles.subscription", { provider })} start={24} />
      <div className={`${listsCss.mCard} ${settingsCss.mFormGroup}`}>
        {active ? (
          <>
            <LoginSteps job={job} provider={provider} send={(code) => api.loginCode(p.id, code)} />
            <Button label={t("web-mobile.profiles.cancelLogin")} primary={false} busy={cancelling}
              onClick={() => { api.cancelLogin(p.id).catch((e: Error) => app.toast(t("web-mobile.profiles.cancelLoginFailed", { error: e.message }))); }} />
          </>
        ) : (
          <>
            <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{job?.state === "failed" ? t("web-mobile.profiles.loginFailed", { error: job.error ?? "" }) : job?.state === "done" ? t("web-mobile.profiles.loginDone") : t("web-mobile.profiles.loginWhere", { name: NAME })}</p>
            <Button label={job?.state === "done" || !needed ? t("web-mobile.profiles.relogin") : t("web-mobile.workspaces.signIn")} primary={needed} busy={busy}
              onClick={() => { api.startLogin(p.id).catch((e: Error) => app.toast(t("web-mobile.profiles.startLoginFailed", { error: e.message }))); }} />
            <details className={css.mDetails}><summary>{t("web-mobile.profiles.manualLogin")}</summary><CommandBox text={p.loginCommand} /></details>
          </>
        )}
      </div>
    </>
  );
}

/** What the person does in the browser for a sign-in under way: open the page and paste the code back (Claude), or copy the code and open the page (Codex). */
function LoginSteps({ job, provider, send }: { job: LoginJob | null | undefined; provider: string; send: (code: string) => Promise<unknown> }) {
  const app = useApp();
  const [code, setCode] = useState("");
  const operation = useAction(send, () => setCode(""));
  const busy = operation.busy;
  const error = operation.error?.message;
  const [copied, setCopied] = useState(false);
  if (!job || job.state === "starting") return <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />{t("web-mobile.profiles.loginLink", { provider })}</p>;
  if (job.state === "verifying") return <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />{t("web-mobile.profiles.finishing")}</p>;
  if (job.state === "done") return <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />{t("web-mobile.profiles.adding")}</p>;
  if (job.state === "needs_approval" && job.url && job.userCode) {
    return (
      <>
        <span className={css.mDeviceCode}>{job.userCode}</span>
        <Button label={copied ? t("web-mobile.profiles.reopen") : t("web-mobile.profiles.copyOpen")} primary
          onClick={() => { void navigator.clipboard.writeText(job.userCode!).then(() => setCopied(true), () => app.toast(t("web-mobile.profiles.copyCodeFailed"))).finally(() => window.open(job.url!, "_blank", "noopener")); }} />
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.profiles.codexNote", { name: NAME })}</p>
      </>
    );
  }
  if (job.state === "needs_code" && job.url) {
    return (
      <>
        <p className={partsCss.mSmall}>{tNodes("web-mobile.profiles.claudeStep1", { link: <a href={job.url} target="_blank" rel="noopener">{t("web-mobile.profiles.openAuth")}</a> }, { name: NAME })}</p>
        <p className={partsCss.mSmall}>{t("web-mobile.profiles.claudeStep2")}</p>
        <input className={listsCss.mField} data-mono autoComplete="off" spellCheck={false} value={code} placeholder={t("web-mobile.profiles.pasteCode")} onChange={(e) => setCode(e.target.value)} />
        {error && <p className={partsCss.mError}>{error}</p>}
        <Button label={t("web-mobile.profiles.finishLogin")} primary busy={busy} enabled={!!code.trim()}
          onClick={() => { void operation.run(code.trim()); }} />
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
  const pending = login ? overview?.logins.find((l) => l.id === login) : undefined;
  const runtime = d?.tile?.runtime === "codex" ? "codex" : "claude";
  const go = (id: string, message: string) => { app.toast(message); app.replace(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(id)}`); };
  // The sign-in made its profile: on to it.
  useEffect(() => { if (pending?.created) go(pending.created, t("web-mobile.profiles.signedInAdded")); }, [pending?.created]); // eslint-disable-line react-hooks/exhaustive-deps
  // A plan's sign-in starts when it is chosen; leaving before it made its profile leaves nothing behind.
  const planning = d?.step === "connect" && d.method === "plan";
  const started = useRef(false);
  const dropped = (e: Error) => app.toast(t("web-mobile.profiles.dropFailed", { error: e.message }));
  useEffect(() => {
    if (planning && !started.current) { started.current = true; setError(null); api.newLogin(runtime).then(({ id }) => setLogin(id), (e: Error) => setError(e.message)); }
    if (!planning && started.current) { started.current = false; if (login && !pending?.created) api.dropLogin(login).catch(dropped); setLogin(null); }
  }, [planning]); // eslint-disable-line react-hooks/exhaustive-deps
  // Back goes a step back, from the picker out.
  const leave = () => { if (d && d.step !== "pick") edit({ provider: "" }); else app.pop(); };
  const job = pending?.job ?? null;
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={d && d.step !== "pick" ? t("common.back") : t("common.cancel")} onBack={leave} title={d?.title ?? t("web-mobile.newChat.addProfile")} sub={<span className={barsCss.mNavbarNote}>{station.name}</span>} />
      <div className={`${pagesCss.mScroll} ${partsCss.mPadX18} ${settingsCss.mSteps}`}>
        {!d ? <Loading text={t("web-mobile.profiles.loading")} /> : d.step === "pick" ? (
          <>
            <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{d.hint}</p>
            {overview && <div><MachineLoginOffers inForm logins={overview.machineLogins} onSignIn={(c) => edit({ provider: c === "claude-sub" ? "anthropic" : "openai", method: "plan" })} /></div>}
            {d.groups.map((g) => (
              <div key={g.id}>
                <SectionHeader title={g.title} start={6} />
                <ListCard>
                  {g.providers.map((p) => (
                    <ListRow key={p.id} onClick={() => edit({ provider: p.id })}>
                      <ProviderMark runtime={p.runtime ?? "claude"} kind={p.kind || "api-provider"} mark={p.mark} size={18} />
                      <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{p.name}</span>
                      <ChevronRight size={16} />
                    </ListRow>
                  ))}
                </ListCard>
              </div>
            ))}
          </>
        ) : d.step === "method" ? (
          <ListCard>
            {d.choices.map((c) => <PickRow key={c.id} label={c.title} sub={c.hint} onClick={() => edit({ method: c.id })} leading={<ProviderMark runtime={runtime} kind={c.id === "plan" ? "subscription" : d.tile?.kind ?? "api-provider"} mark={d.tile?.mark} size={18} />} />)}
          </ListCard>
        ) : d.method === "plan" ? (
          error || pending?.error || job?.state === "failed" || job?.state === "cancelled" ? (
            <>
              <p className={partsCss.mError}>{error ?? pending?.error ?? job?.error ?? t("web-mobile.profiles.loginIncomplete")}</p>
              <Button label={t("web-mobile.profiles.restart")} primary={false} onClick={() => { if (login) api.dropLogin(login).catch(dropped); setLogin(null); setError(null); api.newLogin(runtime).then(({ id }) => setLogin(id), (e: Error) => setError(e.message)); }} />
            </>
          ) : <LoginSteps job={job} provider={runtime === "claude" ? "Claude" : "ChatGPT"} send={(code) => api.newLoginCode(login!, code)} />
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
          <input className={listsCss.mField} data-mono autoComplete="off" spellCheck={false} autoCapitalize="none" disabled={d.pending} value={endpoint} placeholder={d.tile?.endpointExample ?? "https://"}
            onChange={(e) => { setEndpoint(e.target.value); edit({ endpoint: e.target.value }); }} />
          {d.endpointHint && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{d.endpointHint}</p>}
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

const MACHINE_RUNTIME: Record<MachineLogin["runtime"], string> = { claude: "Claude Code", codex: "Codex" };

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
      app.replace(`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(id)}`);
    }, (e: Error) => app.toast(t("web-mobile.profiles.addFailed", { error: e.message })));
  };
  return (
    <>
      {inForm ? <b className={sheetsCss.mFormLabel}>{t("web-mobile.profiles.machineLogins")}</b> : <SectionHeader title={t("web-mobile.profiles.machineLogins")} start={24} />}
      <ListCard>
        {offers.map((l) => {
          const blocked = l.quota?.state === "blocked";
          const trouble = quotaTrouble(l.quota);
          const plan = l.plan ? `${l.plan[0]!.toUpperCase()}${l.plan.slice(1)}` : null;
          return (
            <ListRow key={l.runtime}>
              <ProviderMark runtime={l.runtime} kind="subscription" size={18} />
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}><Presence state={blocked ? "error" : "online"} /> {MACHINE_RUNTIME[l.runtime]}{plan && <span className={settingsCss.mRowAside}> · {plan}</span>}</span>
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
