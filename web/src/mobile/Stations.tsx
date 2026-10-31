import { NetworkSection } from "../StationNetwork.tsx";
import { useDoing, useDoingFailed } from "../doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
// The workspace's stations on a narrow screen, as the Android app has them (apps/android/…/screens/Stations.kt): each
// with its mark and what it is doing, and its load as rings; one station's page is the machine (its load, network,
// versions), with how many connects and profiles run on it (settings' lists have them, ./Settings.tsx).
import { useReady } from "../core/react.ts";
import { LOCAL_MS } from "@stillfail/ui/motion.ts";
import { Fragment, useEffect, useRef, useState } from "react";
import { useParams } from "react-router";
import { LoginCard, ToolMark, useMachineLogins } from "../MachineLogins.tsx";
import * as loginsCss from "../MachineLogins.css.ts";
import { useJoinable, useMemberships, useStations, type StationView } from "../api.ts";
import type { EnvVar, Host, JoinableStation, StationElevation, StationNet } from "../core/shapes.ts";
import { illustrationUrl } from "../brand.tsx";
import { Check, ChevronRight, Close, ImageUpload, More } from "@stillfail/ui/icons.tsx";
import { cloud, useWorkspace } from "../cloud/api.ts";
import { track } from "../telemetry.ts";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { GoRow } from "./Settings.tsx";
import { ask, CommandBox, confirm } from "./sheets.tsx";
import { Versions } from "./Versions.tsx";
import { joinedText, MachineDetails, Net, useStationNet } from "../cloud/StationCards.tsx";
import { ColorRow, EmojiGrid, GlyphGrid } from "../cloud/MarkPick.tsx";
import { glyphColor, isPicture, MarkOrLetter, StationMark, stationGlyph } from "../StationMark.tsx";
import { emojiMark, firstEmoji, glyphMark, kindOf, NO_MARK, pictureMark, pictureOf, same, type Kind, type Mark } from "../stationPick.ts";
import { RetryPill } from "../Connection.tsx";
import { MeterChips } from "../components.tsx";
import { Button, Card, FailedMark, Field, Illustration, LinkButton, ListCard, ListRow, NavBar, NavButton, PickRow, PlaceHead, SectionHeader, Seg } from "./parts.tsx";
import * as profilesCss from "./Profiles.css.ts";
import { Bones, sampleWords, Spinner, Waiting, WaitLine } from "@stillfail/ui/waiting.tsx";
import { sampleStations } from "../samples.ts";
import { usePlaceActions } from "./placeActions.tsx";
import { ScreensCard } from "./Screen.tsx";
import { PermissionsCard } from "./StationPermissions.tsx";
import { AgentEnvText, useAgentEnvForm } from "../AgentEnvText.tsx";
import { useSetPersonal } from "../StationSearch.tsx";
import { useSetAfresh } from "../StationContext.tsx";
import { useSetLogs } from "../StationDiagnostics.tsx";
import { useSetElevation } from "../StationElevation.tsx";
import * as elevationCss from "../StationElevation.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as css from "./Stations.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as settingsPageCss from "./Settings.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as newChatCss from "./styles/new-chat.css.ts";

import { NAME } from "../channel.ts";
import { WorkspaceBadge } from "../WorkspaceMark.tsx";
import { t } from "../i18n.ts";
import { LookInWords } from "../StationNamed.tsx";

export function StationsScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  const list = stations.value;
  const actions = usePlaceActions();
  // No station yet: adding the first one is the page.
  if (list && list.length === 0) {
    return (
      <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
        <PlaceHead title="Station" back={t("web-mobile.settings.title")} onBack={app.pop} />
        <FirstStation />
      </div>
    );
  }
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <PlaceHead title="Station" back={t("web-mobile.settings.title")} onBack={app.pop} primary={actions.stations} />
      {!list ? <Waiting text={t("common.readingStations")} error={stations.error?.message} sample={SAMPLE_STATIONS.map((s) => <StationCard key={s.station} s={s} />)} />
        : list.map((s) => <StationCard key={s.station} s={s} />)}
      <div style={{ height: 30 }} />
    </div>
  );
}

/**
 * An online station's machine on its page, as the wide screen's details (../cloud/StationCards.tsx MachineDetails): what
 * it is, what is left of it large, its network, the rest a row each, its agents' processes; in its room whether known
 * yet or not (in its bones until it is); reconnecting, as last heard, faded.
 */
function StationFigures({ s }: { s: StationView }) {
  const processes = s.overview?.processesText || null;
  return (
    <span className={css.mStationFaded} data-stale={s.reconnecting || undefined}>
      {/* Not read yet: as it will be, made up, in its bones, so nothing below moves as it comes. */}
      {s.host ? <MachineDetails s={s} phone /> : <Bones><MachineDetails s={{ ...s, host: SAMPLE_HOST, online: true }} phone /></Bones>}
      <Known text={processes} letters={9} />
    </span>
  );
}

/** A station's card in the list: its mark, name and what it is, opening its page; its load and network under them. */
function StationCard({ s }: { s: StationView }) {
  const app = useApp();
  return (
    <Card onClick={() => app.push(app.at(`/s/${s.id}/overview`))}>
      <span className={css.mStationHead}>
        {/* Its own mark leads, the server's where it has none (what it is doing is said under its name). */}
        <StationMark emoji={s.emoji} icon={s.icon} size={28} className={css.mMark} />
        <span className={partsCss.mGrow}><b className={css.mStationName}>{s.name}</b><span className={css.mStationSummary}>{[joinedText(s), s.summary].filter(Boolean).join(" · ")}</span></span>
        {s.reconnecting && <Reconnecting />}
        <ChevronRight size={14} className={partsCss.mSubtle} />
      </span>
      <StationBody s={s} />
    </Card>
  );
}

/** Stations made up, for what the list and a station's page show while they are read (in their bones). */
const SAMPLE_STATIONS = sampleStations(2);

/** A machine made up, for what its page shows while it is read (in its bones): its figures, its rows. */
const SAMPLE_HOST: Host = {
  hostname: "", os: "", arch: "", cpus: 0, cpuModel: "", load: 0, uptimeSec: 0, memory: { totalBytes: 0, usedBytes: 0 }, disk: { path: "", totalBytes: 0, freeBytes: 0 },
  emberRssBytes: 0, checkedAt: 0, summary: "", line: "", facts: [], usage: "", emberText: "", identity: "",
  meters: [0, 1, 2].map((i) => ({ label: String(i), short: "", percent: 60, left: 40, level: "ok", value: "", remaining: "", big: sampleWords(2), unit: "%", title: sampleWords(3), total: sampleWords(4) })),
  details: [3, 2, 3, 2].map((n, i) => ({ label: sampleWords(n), value: sampleWords(6 + i) })),
};

/** A station's network made up, for what its card shows while it is read (in its bones). */
const SAMPLE_NET: StationNet = { path: sampleWords(2), rtt: { text: sampleWords(4), level: "ok" }, rttHistory: [], down: sampleWords(6), up: sampleWords(6), total: "" };

/** A grey line of text, one line however long; while it is not known, `letters` made up in its bones (@stillfail/ui
 *  waiting.tsx), the line as tall either way. */
function Known({ text, letters }: { text: string | null; letters: number }) {
  return <span className={css.mStationLine}>{text ?? <Bones>{sampleWords(letters)}</Bones>}</span>;
}

/** The station is up but not reached just now: what shows of it is from before. */
function Reconnecting() {
  return <span className={css.mReconnecting}><Spinner inline />{t("common.reconnecting")}</span>;
}

/**
 * Under a station's name in the list: what of its load runs low (as the desktop's cards: none while all is well) and its network, in the same room whatever state it is in —
 * online, offline, or not yet read — so no card grows, shrinks or pushes the ones below it as states change.
 * Offline, a small picture of it asleep and a line saying so are there; not read yet, its network in its bones.
 */
function StationBody({ s }: { s: StationView }) {
  const host = s.online ? s.host : undefined;
  const net = useStationNet(s.online ? s.station : null) ?? undefined;
  return (
    <span className={css.mStationBody}>
      <span className={css.mStationLoad} data-stale={s.reconnecting || undefined}>
        <span className={css.mStationRings} data-hidden={!host || undefined}><MeterChips meters={host?.meters ?? []} bare alerts /></span>
        {/* (offline: laid out unseen, keeping its room; not read yet: as it will be, in its bones) */}
        <span className={css.mStationNet} data-hidden={!s.online || undefined}>
          {net ? <Net net={net} stacked /> : s.online ? <Bones><Net net={SAMPLE_NET} stacked /></Bones> : <Net net={SAMPLE_NET} stacked />}
        </span>
      </span>
      {!s.online && <span className={css.mStationNap}><img src={illustrationUrl("station-offline")} alt="" decoding="sync" /><span>{t("web-mobile.stations.longGone", { name: NAME })}</span></span>}
    </span>
  );
}

/**
 * Adding a station: a name, then the command to run on that machine (which installs ember and joins it); the sheet
 * waits for it to join.
 */
/// `existing`: a station of another workspace first (the first station's page asks for it).
export function AddStationSheet({ known, existing: first = false }: { known: string[]; existing?: boolean }) {
  const app = useApp();
  const me = app.entry.account;
  const stations = useStations(app.entry.id).value ?? [];
  const [name, setName] = useState("");
  const [made, setMade] = useState<{ install: string; command: string } | null>(null);
  const busy = useDoing("workspace.enroll", { account: me.sub, workspace: app.entry.id });
  const [error, setError] = useState<string | null>(null);
  const joined = made && stations.find((s) => !known.includes(s.id));
  // A station the viewer manages in another workspace, offered beside a new machine (docs/multi-workspace.md).
  const joinable = useJoinable(app.entry.id).value;
  const [existing, setExisting] = useState(first);
  // The stations of other workspaces joined from this sheet: kept in the list where they were, said to have joined, so
  // the next is a tap away (the core's `joinable` has them no more).
  const [took, setTook] = useState<JoinableStation[]>([]);
  const order = useRef(new Map<string, number>());
  for (const s of joinable?.items ?? []) if (!order.current.has(s.station)) order.current.set(s.station, order.current.size);
  const rows = [...(joinable?.items ?? []).filter((s) => !took.some((x) => x.station === s.station)), ...took]
    .sort((a, b) => (order.current.get(a.station) ?? 0) - (order.current.get(b.station) ?? 0));
  const offered = joinable?.offered && rows.length > 0 && !made;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.stations.add")} />
      {/* The choice stays at the top; only what is under it scrolls. */}
      {offered && (
        <div className={sheetsCss.mSheetTop}>
          <Seg options={[t("web-pages.settings.stations.kindNew"), t("web-pages.settings.stations.kindExisting")]} selected={existing ? 1 : 0}
            onSelect={(i) => setExisting(i === 1)} fill height={34} radius={17} />
        </div>
      )}
      {offered && existing ? <JoinStation rows={rows} loading={joinable.loading} took={took} onJoined={(s) => setTook((was) => [...was, s])} /> : (
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
          ) : joined ? <JoinedBody text={t("web-mobile.stations.joined", { name: joined.name })} />
            : <EnrollSteps install={made.install} />}
        </div>
      )}
    </>
  );
}

/** A station joined, in 添加 station: said in green (as the desktop's), and the sheet closed by Done. */
function JoinedBody({ text }: { text: string }) {
  const app = useApp();
  return (
    <>
      <p className={settingsCss.mCallout} data-tone="green"><Check size={16} /><span>{text}</span></p>
      <div className={sheetsCss.mFormActions}><Button label={t("common.done")} primary onClick={() => app.sheet(null)} /></div>
    </>
  );
}

/**
 * 添加 station with a station the viewer manages in another workspace: picked from `rows` (the core's `joinable`, with
 * those `took` here already), then added as it is (`station.join`); `onJoined` with it. One that joined stays in its
 * place, said so, and the next one open is picked: several are added one after another. What that shares of the
 * machine is said under the list.
 */
function JoinStation({ rows, loading, took, onJoined }: { rows: JoinableStation[]; loading: boolean; took: JoinableStation[]; onJoined(s: JoinableStation): void }) {
  const app = useApp();
  const joined = (s: JoinableStation) => took.some((x) => x.station === s.station);
  // One whose home's security mode keeps it out is shown, not picked.
  const open = rows.filter((s) => !s.needsLock && !joined(s));
  const [picked, setPicked] = useState<string>(open[0]?.station ?? "");
  const chosen = open.find((s) => s.station === picked) ?? open[0];
  const busy = useDoing("station.join", { workspace: app.entry.id, station: chosen?.station ?? "" });
  const [error, setError] = useState<string | null>(null);
  // The stations scroll; the actions stay under them.
  return (
    <>
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={partsCss.mMuted}>{t("web-pages.settings.stations.existingLead")}</p>
        {rows.length > 0 ? (
          <div>
            {rows.map((s) => joined(s) ? (
              <PickRow key={s.station} label={s.name} sub={t("web-pages.settings.stations.joinedRow")} done
                leading={<MarkOrLetter emoji={s.emoji} icon={s.icon} name={s.name} />} onClick={() => undefined} />
            ) : (
              <PickRow key={s.station} label={s.name} sub={s.line} checked={s.station === chosen?.station} enabled={!s.needsLock && !busy}
                leading={<MarkOrLetter emoji={s.emoji} icon={s.icon} name={s.name} />} onClick={() => setPicked(s.station)} />
            ))}
          </div>
        ) : loading ? <WaitLine /> : <p className={partsCss.mMuted}>{t("web-pages.settings.stations.existingNone")}</p>}
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-pages.settings.stations.softIsolation")}</p>
        {error && <p className={partsCss.mError}>{error}</p>}
      </div>
      <div className={sheetsCss.mSheetFoot}>
        <Button label={t(took.length > 0 ? "common.done" : "common.cancel")} primary={false} onClick={() => app.sheet(null)} />
        <Button label={t("web-pages.settings.stations.joinAction")} primary busy={busy} enabled={!!chosen} onClick={() => {
          if (!chosen) return;
          setError(null);
          cloud.joinStation(app.entry.id, chosen.station).then(() => onJoined(chosen), (e: Error) => setError(e.message));
        }} />
      </div>
    </>
  );
}

export function StationScreen() {
  const app = useApp();
  const { station: id = "" } = useParams();
  // Slides in once what it shows is read from the device (LOCAL_MS at most, as Chat.tsx): not its loading look first.
  useReady({ topic: "stations", scope: app.entry.id }, LOCAL_MS);
  const stations = useStations(app.entry.id);
  const s = stations.value?.find((x) => x.id === id);
  const manager = useManager();
  // A login's link (`s/<station>/login/<id>`, docs/remote-login.md): its card brought into view.
  const { login } = useParams();
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back="Station" onBack={app.pop} title={s?.name ?? id} sub={s?.reconnecting ? <Reconnecting /> : s ? <span className={barsCss.mNavbarNote}>{[joinedText(s), s.host?.identity || (s.online ? t("web-mobile.stations.online") : s.blocked ? s.summary : t("web-mobile.stations.offline"))].filter(Boolean).join(" · ")}</span> : undefined}
        trailing={s && manager ? <NavButton icon={More} label={t("common.more")} onClick={() => app.sheet({ height: 0.34, content: () => <StationMenu s={s} /> })} /> : undefined} />
      {!s ? <Waiting fill error={stations.error?.message} sample={<StationPage s={SAMPLE_STATIONS[0]!} manager={false} login={null} />} />
        : <StationPage s={s} manager={manager} login={login ?? null} />}
    </div>
  );
}

/** A station's page under its bar: how its machine is, what runs on it, its screens, logins, settings and versions. */
function StationPage({ s, manager, login }: { s: StationView; manager: boolean; login: string | null }) {
  const app = useApp();
  return (
    <div className={`${pagesCss.mScroll} ${settingsCss.mStationPage}`}>
      {/* Every part keeps its room as what it shows comes and goes (not read yet: in its bones); only being online or
          offline changes what the page is. */}
      {s.online ? <Card><StationFigures s={s} /></Card> : (
        <Card><span className={css.mStationOffline}><Illustration name="station-offline" width={220} /><span>{s.blocked ?? t("web-mobile.stations.offlineNote", { name: NAME })}</span><RetryPill trying={s.link.retrying === true} /></span></Card>
      )}
      {/* What runs on it is in settings' lists, every station's together; here, how much of it there is (once read), and its versions. */}
      <SectionHeader title={t("web-mobile.stations.onThis")} start={24} />
      <ListCard>
        <GoRow title={t("web-mobile.settings.connects")} value={s.overview ? t("web-mobile.settings.connectsCount", { n: s.overview.connects.length }) : undefined} onClick={() => app.push(app.at(`/settings/connects?station=${s.id}`))} />
        <GoRow title="Profile" value={s.overview ? t("web-mobile.settings.profilesCount", { n: s.overview.profiles.length }) : undefined} onClick={() => app.push(app.at(`/settings/profiles?station=${s.id}`))} />
        <GoRow title={t("web-mobile.settings.memory")} onClick={() => app.push(app.at(`/s/${s.id}/memory`))} />
        {/* Its drive, where the station has one (one from before it has none: nothing offered). */}
        {s.overview?.drive && <GoRow title={t("web-pages.drive.title")} value={s.overview.drive.roots.length ? t("web-pages.drive.rootsCount", { n: s.overview.drive.roots.length }) : t("web-pages.drive.notShared")}
          onClick={() => app.push(app.at(`/s/${s.id}/files`))} />}
      </ListCard>
      {/* Its screens, to see and drive (docs/remote-screens.md). */}
      <ScreensCard station={s.station} />
      {/* What macOS lets its still.fail Helper do (a Mac's station only), each grant asked for from here. */}
      {s.online && s.overview?.permissions && <PermissionsCard station={s.station} permissions={s.overview.permissions} />}
      {/* What its search finds of the machine (docs/search.md): the person's own data only where its managers say. */}
      {s.online && s.overview?.search?.files === "spotlight" && <SearchCard station={s.station} personal={s.overview.search.personal} manager={manager} />}
      {s.overview?.context && <ContextCard station={s.station} on={s.overview.context.afreshWhenCold} manager={manager} />}
      {s.overview?.diagnostics && <DiagnosticsCard station={s.station} on={s.overview.diagnostics.logs} manager={manager} />}
      {s.online && s.overview?.elevation && <ElevationCard station={s.station} elevation={s.overview.elevation} />}
      <Logins station={s.station} marked={login} />
      {/* The variables what it starts for its agents runs with (docs/agent-env.md); none from a station from before them. */}
      {s.overview?.agentEnv && <AgentEnv station={s.station} env={s.overview.agentEnv} manager={manager} />}
      {manager && <Workspaces s={s} />}
      {s.overview?.network && <NetworkSection station={s.station} network={s.overview.network} manager={manager} />}
      {s.online && s.overview && <Versions station={s.station} updates={s.overview.updates} manager={manager} beta={s.betaOffered ?? false} />}
      <div style={{ height: 30 }} />
    </div>
  );
}

/**
 * The logins done on it through still.fail (as the wide screen's station page, ../MachineLogins.tsx LoginsSection):
 * agents start them; one under way is its card, as in its chat; those ended, a row per program saying who last logged
 * in to it and how many tries, tapped open to them. Nothing when there are none.
 */
function Logins({ station, marked }: { station: string; marked: string | null }) {
  const view = useMachineLogins(station);
  const [open, setOpen] = useState<string | null>(null);
  const holding = view?.tools.find((tool) => tool.tries.some((l) => l.id === marked))?.name ?? null;
  if (!view || !view.supported || view.logins.length === 0) return null;
  const active = view.logins.filter((l) => l.active);
  const opened = open ?? holding;
  return (
    <>
      <SectionHeader title={t("web-main.logins.title")} start={24} />
      {active.length > 0 && <div className={loginsCss.phoneCards}>{active.map((l) => <LoginCard key={l.id} station={station} id={l.id} marked={l.id === marked} />)}</div>}
      {view.tools.length > 0 && (
        <ListCard>
          {view.tools.map((tool) => {
            const said = [tool.summaryText, tool.chatTitle ? `「${tool.chatTitle}」` : null].filter(Boolean).join(" · ");
            const on = opened === tool.name;
            return (
              <Fragment key={tool.name}>
                <ListRow onClick={() => setOpen(on ? "" : tool.name)}>
                  <ToolMark tool={tool} size={22} />
                  <span className={loginsCss.phoneRowText}>
                    <span className={listsCss.mRowTitle}>{tool.name}</span>
                    <span className={tool.failed ? loginsCss.phoneFailed : loginsCss.phoneState}>{said}</span>
                  </span>
                  <span className={loginsCss.phoneCount}>{tool.countText}<span className={`${loginsCss.toggle} ${on ? loginsCss.toggleOpen : ""}`}><ChevronRight size={14} /></span></span>
                </ListRow>
                {on && tool.tries.map((l) => (
                  <div key={l.id} className={loginsCss.phoneTry} data-marked={l.id === marked || undefined}>
                    <span className={l.state === "failed" ? loginsCss.phoneFailed : loginsCss.phoneState}>{[l.whenText, l.doneByText || l.statusText].filter(Boolean).join(" · ")}</span>
                    {l.chatTitle && <span className={loginsCss.phoneState}>「{l.chatTitle}」</span>}
                  </div>
                ))}
              </Fragment>
            );
          })}
        </ListCard>
      )}
      <p className={loginsCss.phoneLead}>{t("web-main.logins.lead")}</p>
    </>
  );
}

/**
 * The variables everything it starts for its agents runs with (docs/agent-env.md: a proxy, mostly), a row each, a
 * secret's value masked; its managers edit them in a sheet as a .env file's lines.
 */
function AgentEnv({ station, env, manager }: { station: string; env: EnvVar[]; manager: boolean }) {
  const app = useApp();
  if (env.length === 0 && !manager) return null;
  return (
    <>
      <SectionHeader title={t("web-mobile.stations.agentEnv")} start={24} />
      <ListCard>
        {env.length === 0 && <ListRow><span className={`${partsCss.mGrow} ${partsCss.mMuted}`}>{t("web-mobile.stations.agentEnvEmpty")}</span></ListRow>}
        {env.map((e) => <ListRow key={e.key}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={`${listsCss.mRowTitle} ${profilesCss.mMono}`}>{e.key}</span><span className={`${listsCss.mRowNote} ${profilesCss.mMono}`}>{e.value}</span></span></ListRow>)}
        {manager && (
          <ListRow onClick={() => app.sheet({ height: 0.8, draggable: true, content: () => <AgentEnvSheet station={station} /> })}>
            <span className={`${partsCss.mGrow} ${partsCss.mAccent} ${listsCss.mRowTitle}`}>{t("web-mobile.profiles.editEnv")}</span>
            <AgentEnvDoing station={station} />
          </ListRow>
        )}
      </ListCard>
    </>
  );
}

/** The variables as a .env file's lines (../AgentEnvText.tsx), to paste into and change; saved whole, the sheet closed at once. */
function AgentEnvSheet({ station }: { station: string }) {
  const app = useApp();
  const form = useAgentEnvForm(station);
  const close = () => { form.reset(); app.sheet(null); };
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.stations.agentEnv")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.stations.agentEnvNote")}</p>
        <AgentEnvText form={form} fieldClass={listsCss.mField} label={t("web-mobile.stations.agentEnv")} />
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={close} />
          <Button label={t("common.save")} primary busy={form.saving} enabled={form.canSave} onClick={() => { form.save(); app.sheet(null); }} />
        </div>
      </div>
    </>
  );
}

/** Saved (the sheet gone): a spinner until the station has them; why it failed, a moment. */
function AgentEnvDoing({ station }: { station: string }) {
  const busy = useDoing("agentEnv.form.save", { station });
  const failed = useDoingFailed("agentEnv.form.save", { station });
  return busy ? <Spinner /> : failed ? <FailedMark error={failed} /> : null;
}

/** The workspaces it is in, for the owners and admins of its home one (this), once it is in more than one (as the wide
 * screen's station page, ../cloud/StationPage.tsx): its home first, what each has of the machine. */
function Workspaces({ s }: { s: StationView }) {
  const m = useMemberships(s.station).value;
  if (!m?.manages || m.workspaces.length < 2) return null;
  return (
    <>
      <SectionHeader title="Workspace" start={24} />
      <ListCard>
        {m.workspaces.map((w) => (
          <ListRow key={w.workspace}>
            <WorkspaceBadge w={w} size={20} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{w.name}</span>
            <span className={settingsPageCss.mValue}><span className={css.mMembershipLine}>{w.line}</span></span>
          </ListRow>
        ))}
      </ListCard>
    </>
  );
}

/** The command that adds a station, to copy and run on that machine, and the wait for it to join. */
function EnrollSteps({ install }: { install: string }) {
  return (
    <>
      <p>{t("web-mobile.stations.runThis")}</p>
      <CommandBox text={install} />
      <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.stations.runNote", { name: NAME })}</p>
      <WaitLine text={t("web-mobile.stations.waiting")} />
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
  const joinable = useJoinable(app.entry.id).value;
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
        {!view ? <WaitLine text={t("web-mobile.workspace.reading")} />
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
              {/* A station the viewer manages in another workspace, added here as it is instead (docs/multi-workspace.md). */}
              {joinable?.offered && joinable.items.length > 0 && <LinkButton label={t("web-pages.settings.stations.firstExisting")}
                onClick={() => app.sheet({ height: 0.72, draggable: true, content: () => <AddStationSheet known={[]} existing /> })} />}
            </>
          )}
      </div>
    </div>
  );
}

/** Whether the viewer may add, rename and remove stations: the workspace's owner and admins. */
export function useManager(): boolean {
  const app = useApp();
  const role = useWorkspace(app.entry.id).value?.role;
  return role === "owner" || role === "admin";
}

/**
 * A station's or a workspace's mark picked in a sheet (the wide screen's popover: ../cloud/MarkPick.tsx): one of
 * still.fail's icons or an emoji (any, pasted or typed), a picture put up, or none; set at once by `set`.
 */
export function MarkSheet({ s, set }: { s: { name: string; emoji?: string | null | undefined; icon?: string | null | undefined }; set(mark: Mark): Promise<unknown> }) {
  const app = useApp();
  const act = useAct();
  const [kind, setKind] = useState<Kind>(() => kindOf(s.emoji, s.icon));
  const [typed, setTyped] = useState("");
  const file = useRef<HTMLInputElement>(null);
  const [color, setColor] = useState(() => glyphColor(s.icon));
  const [query, setQuery] = useState("");
  const pick = (m: Mark, stay?: boolean) => {
    if (!stay) app.sheet(null);
    if (!same(m, s.emoji, s.icon)) act(set(m), t("web-mobile.stations.emojiWhat"), t("web-mobile.stations.emojiSet"));
  };
  const upload = (f: Blob) => pictureOf(f).then((url) => pick(pictureMark(url)),
    (e: unknown) => app.toast(t((e as Error).message === "too_big" ? "web-pages.stations.mark.tooBig" : "web-pages.stations.mark.unreadable")));
  const picture = isPicture(s.icon) ? s.icon : null;
  return (
    <>
      <SheetGrab />
      <SheetHead title={<LookInWords look={s} text={t("web-mobile.stations.emojiTitle", { name: s.name })} />} />
      <div className={sheetsCss.mSheetScroll}>
        <div className={css.mMarkHead}>
          <Seg options={[t("web-pages.stations.mark.glyphs"), "Emoji"]} selected={kind === "glyph" ? 0 : 1} onSelect={(i) => setKind(i === 0 ? "glyph" : "emoji")} fill height={34} radius={17} />
          {kind === "glyph" && <input className={css.mMarkField} value={query} placeholder={t("web-pages.stations.mark.search")} aria-label={t("web-pages.stations.mark.search")} onChange={(e) => setQuery(e.target.value)} />}
          {kind === "emoji" && (
            <input className={css.mMarkField} value={typed} placeholder={t("web-pages.stations.emoji.paste")} aria-label={t("web-pages.stations.emoji.paste")}
              onChange={(e) => { setTyped(e.target.value); const one = firstEmoji(e.target.value); if (one) pick(emojiMark(one)); }} />
          )}
        </div>
        {kind === "glyph" && <ColorRow color={color} className={css.mMarkColors} onColor={(c) => { setColor(c); const g = stationGlyph(s.icon); if (g) pick(glyphMark(g, c), true); }} />}
        {kind === "glyph" ? <GlyphGrid icon={s.icon} color={color} query={query} size={24} className={css.mMarkGrid} onPick={pick} />
          : <EmojiGrid emoji={stationGlyph(s.icon) || picture ? null : s.emoji} className={`${css.mMarkGrid} ${css.mMarkEmoji}`} onPick={pick} />}
        <PickRow label={t(picture ? "web-pages.stations.mark.another" : "web-pages.stations.mark.upload")}
          leading={picture ? <img src={picture} alt="" className={css.mMarkPicture} /> : <ImageUpload size={20} />} onClick={() => file.current?.click()} />
        {(s.emoji || s.icon) && <PickRow label={t("web-mobile.stations.emojiClear")} leading={<Close size={20} />} onClick={() => pick(NO_MARK)} />}
        <input ref={file} type="file" accept="image/png,image/jpeg,image/webp,image/gif" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void upload(f); }} />
      </div>
    </>
  );
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
        <PickRow label={t("web-mobile.stations.emoji")} mark={(s.emoji || s.icon) ? <StationMark emoji={s.emoji} icon={s.icon} size={18} /> : undefined}
          onClick={() => app.sheet({ height: 0.78, content: () => <MarkSheet s={s} set={(m) => cloud.setStationMark(me.sub, app.entry.id, s.id, m)} /> })} />
        <PickRow label={t("web-mobile.stations.remove")} accent onClick={() => confirm(app, {
          title: t("web-mobile.stations.removeAsk", { name: s.name }), action: t("web-mobile.stations.removeAction"), danger: true,
          text: t("web-mobile.stations.removeText", { name: NAME }), atOnce: "web-mobile.workspace.removeFailed",
          run: () => { app.pop(); return cloud.removeStation(me.sub, app.entry.id, s.id).then(() => app.toast(t("web-mobile.stations.removed"))); },
        })} />
      </div>
    </>
  );
}

/** Whether a session whose prompt cache is over goes on afresh by itself (the wide page's StationContext.tsx): its
 *  managers switch it, others read it. */
function ContextCard({ station, on, manager }: { station: string; on: boolean; manager: boolean }) {
  const { busy, set } = useSetAfresh(station);
  return (
    <>
      <SectionHeader title={t("web-pages.stations.context.section")} start={24} />
      <ListCard>
        <button type="button" className={connectsCss.mSwitchRow} disabled={!manager || busy} onClick={() => void set(!on)}>
          <span className={partsCss.mGrow}><b>{t("web-pages.stations.context.afresh")}</b><span>{t("web-pages.stations.context.afreshLine")}</span></span>
          {busy ? <Spinner /> : <span className={connectsCss.mSwitch} data-on={on || undefined} />}
        </button>
      </ListCard>
    </>
  );
}

/** Whether the station sends its log to still.fail (the wide page's StationDiagnostics.tsx): its managers switch it,
 *  others read it. */
function DiagnosticsCard({ station, on, manager }: { station: string; on: boolean; manager: boolean }) {
  const { busy, set } = useSetLogs(station);
  return (
    <>
      <SectionHeader title={t("web-pages.stations.diagnostics.section")} start={24} />
      <ListCard>
        <button type="button" className={connectsCss.mSwitchRow} disabled={!manager || busy} onClick={() => void set(!on)}>
          <span className={partsCss.mGrow}><b>{t("web-pages.stations.diagnostics.logs")}</b><span>{t("web-pages.stations.diagnostics.logsLine")}</span></span>
          {busy ? <Spinner /> : <span className={connectsCss.mSwitch} data-on={on || undefined} />}
        </button>
      </ListCard>
    </>
  );
}

/** Whether a Windows station runs as the machine's administrator (the wide page's StationElevation.tsx): its managers
 *  switch it, others read it; how a change goes, and how the last one failed, under it. */
function ElevationCard({ station, elevation }: { station: string; elevation: StationElevation }) {
  const { doing, set } = useSetElevation(station);
  const busy = doing || elevation.busy;
  return (
    <>
      <SectionHeader title={t("web-pages.stations.elevation.section")} start={24} />
      <ListCard>
        <button type="button" className={connectsCss.mSwitchRow} disabled={!elevation.canChange || busy} onClick={() => void set(!elevation.on)}>
          <span className={partsCss.mGrow}>
            <b>{t("web-pages.stations.elevation.admin")}</b>
            <span>{elevation.line}</span>
            {elevation.failed && <span className={elevationCss.failed}>{elevation.failed}</span>}
          </span>
          {busy ? <Spinner /> : <span className={connectsCss.mSwitch} data-on={elevation.on || undefined} />}
        </button>
      </ListCard>
    </>
  );
}

/** Whether the station's search finds the machine's person's own mail, messages and the like (the wide page's
 *  StationSearch.tsx): its managers switch it, others read it. */
function SearchCard({ station, personal, manager }: { station: string; personal: boolean; manager: boolean }) {
  const { busy, set } = useSetPersonal(station);
  return (
    <>
      <SectionHeader title={t("web-pages.stations.search.section")} start={24} />
      <ListCard>
        <button type="button" className={connectsCss.mSwitchRow} disabled={!manager || busy} onClick={() => void set(!personal)}>
          <span className={partsCss.mGrow}><b>{t("web-pages.stations.search.personal")}</b><span>{t("web-pages.stations.search.personalLine")}</span></span>
          {busy ? <Spinner /> : <span className={connectsCss.mSwitch} data-on={personal || undefined} />}
        </button>
      </ListCard>
    </>
  );
}
