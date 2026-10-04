import { useDoing } from "../doing.ts";
// The workspace's stations on a narrow screen, as the Android app has them (apps/android/…/screens/Stations.kt): each
// with the buddy's face for its state and its load as rings; one station's page is the machine (its load, network,
// versions), with how many connects and profiles run on it (settings' lists have them, ./Settings.tsx).
import { useEffect, useRef, useState } from "react";
import { useParams } from "react-router";
import { useStations, type StationView } from "../api.ts";
import type { StationNet } from "../core/shapes.ts";
import { illustrationUrl } from "../brand.tsx";
import { ChevronRight, More, Plus } from "../icons.tsx";
import { cloud, useWorkspace } from "../cloud/api.ts";
import { track } from "../telemetry.ts";
import { useDark } from "../theme.ts";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { GoRow } from "./Settings.tsx";
import { ask, CommandBox, confirm } from "./sheets.tsx";
import { Versions } from "./Versions.tsx";
import { Net } from "../cloud/StationCards.tsx";
import { RetryPill } from "../Connection.tsx";
import { MeterChips } from "../components.tsx";
import { Button, Card, Field, Illustration, LargeTitle, ListCard, Loading, NavBar, NavButton, PickRow, SectionHeader, Spinner, TopBack } from "./parts.tsx";
import * as css from "./Stations.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as newChatCss from "./styles/new-chat.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
const BASE = import.meta.env.BASE_URL;

/** The buddy's face for a station: at work, idle, or asleep. */
export function Buddy({ s, size = 40 }: { s: StationView; size?: number }) {
  const dark = useDark();
  const face = s.face ?? "idle";
  return <img className={css.mBuddy} src={`${BASE}${face}${dark ? "-dark" : ""}.svg`} alt="" width={size} height={size} />;
}

export function StationsScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  const list = stations.value;
  const manager = useManager();
  // No station yet: adding the first one is the page.
  if (list && list.length === 0) {
    return (
      <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
        <TopBack label={t("web-mobile.nav.chats")} onBack={app.pop} />
        <FirstStation />
      </div>
    );
  }
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} trailing={manager && list ? <NavButton icon={Plus} iconSize={20} label={t("web-mobile.stations.add")} onClick={() => app.sheet({ height: 0.72, draggable: true, content: () => <AddStationSheet known={list.map((s) => s.id)} /> })} /> : undefined} />
      <LargeTitle small={list ? t("web-mobile.stations.small", { workspace: app.entry.name, online: list.filter((s) => s.online).length, n: list.length }) : app.entry.name} big="Station" />
      {!list ? <p className={`${partsCss.mMuted} ${css.mPad20}`}>{stations.error?.message ?? t("web-mobile.memory.readingStations")}</p> : list.map((s) => (
        <Card key={s.station} onClick={() => app.push(app.at(`/s/${s.id}/overview`))}>
          <span className={css.mStationHead}>
            <Buddy s={s} />
            <span className={partsCss.mGrow}><b className={css.mStationName}>{s.name}</b><span className={css.mStationSummary}>{s.summary}</span></span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </span>
          <StationBody s={s} />
        </Card>
      ))}
      <div style={{ height: 30 }} />
    </div>
  );
}

/** Laid out while a station has no network to show, so that its card keeps the room. */
const noNet: StationNet = { path: "直连", rtt: { text: "0 ms", level: "ok" }, rttHistory: [], down: " ", up: " ", total: "" };

/**
 * Under a station's name in the list: its load as rings and its network, in the same room whatever state it is in —
 * online, offline, or not yet read — so no card grows, shrinks or pushes the ones below it as states change.
 * Offline, a small picture of it asleep and a line saying so are there; not read yet, grey bars where the figures go.
 */
function StationBody({ s }: { s: StationView }) {
  const host = s.online ? s.host : undefined;
  const net = s.online ? s.net : undefined;
  return (
    <span className={css.mStationBody}>
      <span className={css.mStationLoad}>
        <span className={css.mStationRings} data-hidden={!host || undefined}><MeterChips meters={host?.meters ?? []} bare /></span>
        <span className={css.mStationNet} data-hidden={!net || undefined}><Net net={net ?? noNet} stacked /></span>
      </span>
      {!s.online ? (
        <span className={css.mStationNap}><img src={illustrationUrl("station-offline")} alt="" decoding="sync" /><span>{t("web-mobile.stations.longGone", { name: NAME })}</span></span>
      ) : (
        <span className={css.mStationBars} aria-hidden>
          <span className={css.mBarChips}>{!host && [46, 52, 50].map((w) => <i key={w} style={{ width: w }} />)}</span>
          {!net && <span className={css.mBarNet}><span><i style={{ width: 34 }} /><i style={{ width: 96 }} /></span><span><i style={{ width: 132 }} /><i style={{ width: 132 }} /></span></span>}
        </span>
      )}
    </span>
  );
}

/**
 * Adding a station: a name, then the command to run on that machine (which installs ember and joins it); the sheet
 * waits for it to join.
 */
function AddStationSheet({ known }: { known: string[] }) {
  const app = useApp();
  const me = app.entry.account;
  const stations = useStations(app.entry.id).value ?? [];
  const [name, setName] = useState("");
  const [made, setMade] = useState<{ install: string; command: string } | null>(null);
  const busy = useDoing("workspace.enroll", { account: me.sub, workspace: app.entry.id });
  const [error, setError] = useState<string | null>(null);
  const joined = made && stations.find((s) => !known.includes(s.id));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.stations.add")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        {!made ? (
          <>
            <p className={partsCss.mMuted}>{t("web-mobile.stations.addNote", { name: NAME })}</p>
            <b className={sheetsCss.mFormLabel}>{t("web-mobile.workspaces.name")}</b>
            <Field value={name} onChange={setName} placeholder={t("web-mobile.stations.namePlaceholder")} />
            {error && <p className={partsCss.mError}>{error}</p>}
            <div className={sheetsCss.mFormActions}>
              <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
              <Button label={t("web-mobile.stations.makeCommand")} primary busy={busy} enabled={!!name.trim()} onClick={() => {
                setError(null);
                cloud.enroll(me.sub, app.entry.id, name.trim()).then(setMade, (e: Error) => setError(e.message));
              }} />
            </div>
          </>
        ) : joined ? (
          <>
            <p>{t("web-mobile.stations.joined", { name: joined.name })}</p>
            <div className={sheetsCss.mFormActions}><Button label={t("common.done")} primary onClick={() => app.sheet(null)} /></div>
          </>
        ) : <EnrollSteps install={made.install} />}
      </div>
    </>
  );
}

export function StationScreen() {
  const app = useApp();
  const { station: id = "" } = useParams();
  const stations = useStations(app.entry.id);
  const s = stations.value?.find((x) => x.id === id);
  const manager = useManager();
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back="Station" onBack={app.pop} title={s?.name ?? id} sub={s ? <span className={barsCss.mNavbarNote}>{s.host?.cpuModel || (s.online ? t("web-mobile.stations.online") : t("web-mobile.stations.offline"))}</span> : undefined}
        trailing={s && manager ? <NavButton icon={More} label={t("common.more")} onClick={() => app.sheet({ height: 0.34, content: () => <StationMenu s={s} /> })} /> : undefined} />
      {!s ? <Loading text={stations.error?.message ?? t("web-mobile.reading")} /> : (
        <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
          {s.online && s.host ? (
            <Card>
              <span className={css.mStationRings}><MeterChips meters={s.host.meters} /></span>
              <span className={css.mStationLine}>{s.host.line}</span>
              {s.net && <Net net={s.net} stacked />}
              {s.overview?.processesText && <span className={css.mStationLine}>{s.overview.processesText}</span>}
            </Card>
          ) : !s.online ? (
            <Card><span className={css.mStationOffline}><Illustration name="station-offline" width={220} /><span>{t("web-mobile.stations.offlineNote", { name: NAME })}</span><RetryPill /></span></Card>
          ) : null}
          {/* What runs on it is in settings' lists, every station's together; here, how much of it there is, and its versions. */}
          {s.overview && (
            <>
              <SectionHeader title={t("web-mobile.stations.onThis")} start={24} />
              <ListCard>
                <GoRow title={t("web-mobile.settings.connects")} value={t("web-mobile.settings.connectsCount", { n: s.overview.connects.length })} onClick={() => app.push(app.at(`/settings/connects?station=${s.id}`))} />
                <GoRow title="Profile" value={t("web-mobile.settings.profilesCount", { n: s.overview.profiles.length })} onClick={() => app.push(app.at(`/settings/profiles?station=${s.id}`))} />
                <GoRow title={t("web-mobile.settings.memory")} onClick={() => app.push(app.at(`/s/${s.id}/memory`))} />
              </ListCard>
              {s.online && <Versions station={s.station} updates={s.overview.updates} manager={manager} beta={s.betaOffered ?? false} />}
            </>
          )}
          <div style={{ height: 30 }} />
        </div>
      )}
    </div>
  );
}

/** The command that adds a station, to copy and run on that machine, and the wait for it to join. */
function EnrollSteps({ install }: { install: string }) {
  return (
    <>
      <p>{t("web-mobile.stations.runThis")}</p>
      <CommandBox text={install} />
      <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.stations.runNote", { name: NAME })}</p>
      <p className={`${partsCss.mMuted} ${partsCss.mSmall} ${chatCss.mWaiting}`}><Spinner size={10} />{t("web-mobile.stations.waiting")}</p>
    </>
  );
}

/**
 * A workspace's first station, added in the page (as the desktop's Onboarding, ../cloud/workspace.tsx): what a station
 * is, its name, then the command to copy and the wait. The workspace's pages take over once it has joined. Only its
 * owner and admins add one; anyone else is told to wait for them.
 */
export function FirstStation() {
  const app = useApp();
  const view = useWorkspace(app.entry.id).value;
  const manager = view?.role === "owner" || view?.role === "admin";
  const [name, setName] = useState("");
  const [made, setMade] = useState<{ install: string } | null>(null);
  const busy = useDoing("workspace.enroll", { account: app.entry.account.sub, workspace: app.entry.id });
  const [error, setError] = useState<string | null>(null);
  const shown = useRef(0);
  useEffect(() => { if (made) shown.current = performance.now(); }, [made]);
  // Joined: the page is gone (the workspace has a station), so this is said as it goes.
  useEffect(() => () => { if (shown.current) track("station_added", { ms: Math.round(performance.now() - shown.current), first: true }); }, []);
  return (
    <div className={newChatCss.mNewNone}>
      <img className={partsCss.mIllus} src={illustrationUrl("no-station")} alt="" width={240} />
      <b>{t("web-mobile.stations.first")}</b>
      <p>{t("web-mobile.stations.firstNote")}</p>
      <div className={`${sheetsCss.mForm} ${settingsCss.mSteps}`} style={{ alignSelf: "stretch", padding: 0, textAlign: "left" }}>
        {!view ? <p className={`${partsCss.mMuted} ${chatCss.mWaiting}`}><Spinner size={13} />{t("web-mobile.workspace.reading")}</p>
          : !manager ? <p className={settingsCss.mCallout}>{t("web-mobile.stations.waitAdmin")}</p>
          : made ? <EnrollSteps install={made.install} />
          : (
            <>
              <b className={sheetsCss.mFormLabel}>{t("web-mobile.stations.nameIt")}</b>
              <Field value={name} onChange={setName} placeholder={t("web-mobile.stations.namePlaceholderShort")} />
              {error && <p className={partsCss.mError}>{error}</p>}
              <Button label={t("web-mobile.stations.makeCommand")} primary busy={busy} enabled={!!name.trim()} onClick={() => {
                setError(null);
                cloud.enroll(app.entry.account.sub, app.entry.id, name.trim()).then(setMade, (e: Error) => setError(e.message));
              }} />
            </>
          )}
      </div>
    </div>
  );
}

/** Whether the viewer may add, rename and remove stations: the workspace's owner and admins. */
function useManager(): boolean {
  const app = useApp();
  const role = useWorkspace(app.entry.id).value?.role;
  return role === "owner" || role === "admin";
}

function StationMenu({ s }: { s: StationView }) {
  const app = useApp();
  const me = app.entry.account;
  return (
    <>
      <SheetGrab />
      <SheetHead title={s.name} />
      <div className={sheetsCss.mSheetScroll}>
        <PickRow label={t("web-mobile.stations.rename")} onClick={() => ask(app, { title: t("web-mobile.stations.renameTitle"), value: s.name, placeholder: t("web-mobile.stations.renamePlaceholder"), action: t("common.save"), atOnce: "web-main.rename.failed",
          run: (name) => cloud.renameStation(me.sub, app.entry.id, s.id, name).then(() => app.toast(t("web-mobile.workspace.renamed"))) })} />
        <PickRow label={t("web-mobile.stations.remove")} accent onClick={() => confirm(app, {
          title: t("web-mobile.stations.removeAsk", { name: s.name }), action: t("web-mobile.stations.removeAction"), danger: true,
          text: t("web-mobile.stations.removeText", { name: NAME }), atOnce: "web-mobile.workspace.removeFailed",
          run: () => { app.pop(); return cloud.removeStation(me.sub, app.entry.id, s.id).then(() => app.toast(t("web-mobile.stations.removed"))); },
        })} />
      </div>
    </>
  );
}
