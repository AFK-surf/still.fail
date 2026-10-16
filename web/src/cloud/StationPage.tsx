// The stations on a wide screen with Station in the rail: the sidebar lists them (StationsNav), the page is the one picked
// (StationSettings), everything of it in one place: how it is, what is left of the machine, what runs on it (agents,
// profiles, connects, folders lent), its software and the machine itself. Elsewhere (no rail, or Station not in it) the
// settings' list of cards stays, each name opening this page.
import { useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import { Link, Navigate, NavLink, useParams } from "react-router";
import { stamp, useMemberships, useStations, type StationView } from "../api.ts";
import { useGo } from "../go.ts";
import { MeterChip, MeterDials } from "../components.tsx";
import { RetryPill } from "../Connection.tsx";
import { drivePath } from "../drive/useDrive.ts";
import { ChevronRight, Folder, Plus } from "@stillfail/ui/icons.tsx";
import { useRailItems } from "../Rail.tsx";
import { stationBase } from "../station.tsx";
import { StationMark } from "../StationMark.tsx";
import { same } from "../stationPick.ts";
import { BackLink, Button, ICON, Loading, Menu, MobileBack, Pill, Section, StatusDot, Time } from "../ui.tsx";
import { SoftwareList } from "../Versions.tsx";
import { WorkspaceMark } from "../WorkspaceMark.tsx";
import { HostDetails, joinedText, Net, problems, state, useLong } from "./StationCards.tsx";
import { MarkPick } from "./MarkPick.tsx";
import { ProfileCard } from "../ProfileCard.tsx";
import { ScreensSection } from "../screen/ScreenList.tsx";
import { NavAction, NavList, NavItem, NavLine, NavTop, navFill } from "../SidebarList.tsx";
import { AddStationDialog, useStationEdits, useWorkspace } from "./settings.tsx";
import type { WorkspaceEntry } from "./workspace.tsx";
import * as railCss from "../Rail.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as settingsCss from "./settings.css.ts";
import * as css from "./StationPage.css.ts";
import { t } from "../i18n.ts";

const WIDE = typeof window === "undefined" ? null : window.matchMedia("(min-width: 701px)");

/** Whether the stations have the sidebar of their own: Station in the rail, and the rail there (a wide screen). */
export function useStationsSide(): boolean {
  const railed = useRailItems().includes("stations");
  const wide = useSyncExternalStore((f) => { WIDE?.addEventListener("change", f); return () => WIDE?.removeEventListener("change", f); }, () => WIDE?.matches ?? true, () => true);
  return railed && wide;
}

export const stationPage = (workspace: string, id: string) => `/w/${workspace}/settings/stations/${encodeURIComponent(id)}`;

/** The sidebar's list: adding one in the band over it (a manager), then each station, how it is at its row's end. */
export function StationsNav({ entry, top }: { entry: WorkspaceEntry; top?: ReactNode }) {
  const stations = useStations(entry.id).value ?? [];
  const { view, manager } = useWorkspace(entry);
  const [adding, setAdding] = useState(false);
  return (
    <>
      <NavTop top={top} action={manager && view && <NavAction icon={<Plus {...ICON} />} label={t("web-pages.settings.stations.add")} onClick={() => setAdding(true)} />} />
      <NavList>
        {stations.map((s) => <StationRow key={s.id} s={s} to={stationPage(entry.id, s.id)} />)}
        {adding && view && <AddStationDialog view={view} account={entry.account} stations={stations} onClose={() => setAdding(false)} thisMac />}
      </NavList>
    </>
  );
}

/** A station in the sidebar: its mark and name, how it is at the end of that line (its agents at work, when it was last
 * seen while away); what the machine is under them; then, while it is up, what is left of its CPU, memory and disk in
 * small boxes (as in a chat's bar: their edge in their level's colour), and how this device reaches it, a newer version
 * there said too. Nothing in colour but what is off. */
function StationRow({ s, to }: { s: StationView; to: string }) {
  const meters = s.online ? s.host?.meters ?? [] : [];
  const newer = s.online && (s.overview?.updates ?? []).some((v) => v.installed && v.updatable && (v.newer || v.downgrade));
  return (
    <NavItem to={to} title={s.name}
      mark={s.emoji || s.icon ? <StationMark emoji={s.emoji} icon={s.icon} size={16} /> : <WorkspaceMark w={{ name: s.name }} size={16} />}
      end={<><span className={railCss.dot} data-online={s.online || undefined} />{brief(s)}</>}>
      <NavLine><span className={navFill}>{/* Where it is from first: the machine's line is long, and the narrow row cuts it short at its end. */}{[joinedText(s), s.host?.identity ?? (s.online ? t("web-pages.stations.connecting") : t("web-pages.stations.offline"))].filter(Boolean).join(" · ")}</span></NavLine>
      {meters.length > 0 && (
        <span className={css.rowMeters}>
          {meters.map((m) => <MeterChip key={m.label} meter={m} brief bare />)}
        </span>
      )}
      {s.online && (s.net || newer) && (
        <NavLine>
          <span className={navFill}>
            {s.net && <>{s.net.path}{s.net.rtt && <>{" · "}<span className={css.low} data-level={s.net.rtt.level}>{s.net.rtt.text}</span></>}</>}
            {s.net && newer && " · "}
            {newer && t("web-pages.stations.page.newer")}
          </span>
        </NavLine>
      )}
    </NavItem>
  );
}

/** How it is in a word or two: its agents at work, else when it was last seen while away; nothing while idle. */
function brief(s: StationView): ReactNode {
  if (!s.online) return <Time stamp={stamp(s, "lastSeen")} />;
  const running = s.overview?.counts.running ?? 0;
  return running > 0 ? <span className={css.busy}>{t("web-pages.stations.page.runningShort", { n: running })}</span> : null;
}

/** `settings/stations` with the sidebar of their own: the first of them (there is no page of them all). */
export function StationsFirst({ entry }: { entry: WorkspaceEntry }) {
  const first = useStations(entry.id).value?.[0];
  return first ? <Navigate to={stationPage(entry.id, first.id)} replace /> : <Loading label={t("web-pages.settings.workspace.loading")} />;
}

/** A station's own page. */
export function StationSettings({ entry }: { entry: WorkspaceEntry }) {
  const { station: id = "" } = useParams();
  const side = useStationsSide();
  const listed = useStations(entry.id).value;
  const { view, manager } = useWorkspace(entry);
  const edits = useStationEdits(view, entry.account, listed ?? []);
  const found = listed?.find((s) => s.id === id);
  const back = `/w/${entry.id}/settings/stations`;
  if (!listed) return <Loading label={t("web-pages.settings.workspace.loading")} />;
  // Removed (or a link from before): the list, or the first of them.
  if (!found) return <Navigate to={back} replace />;
  const s = edits.shown(found);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      {side ? <MobileBack to={back} label="Station" /> : <BackLink to={back} label="Station" />}
      <Head s={s} manager={manager} edits={edits} />
      {edits.dialogs}
      <Body s={s} manager={manager} />
    </div>
  );
}

type Edits = ReturnType<typeof useStationEdits>;

/** Its mark and name (a title its managers rename where it is, as the workspace's), how it is and what it is; beside
 * them its folders, trying it again while away, and its ⋯. */
function Head({ s, manager, edits }: { s: StationView; manager: boolean; edits: Edits }) {
  const [name, setName] = useState(s.name);
  useEffect(() => setName(s.name), [s.name]);
  const keep = () => { const to = name.trim(); if (!to) setName(s.name); else edits.rename(s, to); };
  const silent = useLong(s.online && !s.host, 15_000);
  const wrong = problems(s, silent);
  const items = edits.menu(s, manager, false);
  const navigate = useGo();
  return (
    <>
      <header className={settingsCss.workspaceHead}>
        <MarkPick emoji={s.emoji} icon={s.icon} name={s.name} editable={manager} busy={edits.picking(s)} large
          empty={<WorkspaceMark w={{ name: s.name }} />} onPick={(m) => { if (!same(m, s.emoji, s.icon)) edits.setMark(s, m); }} />
        <div className={pagesCss.identityText}>
          {manager
            ? <input className={settingsCss.titleField} value={name} maxLength={80} aria-label={t("web-pages.settings.stations.namePrompt")}
                onChange={(e) => setName(e.target.value)} onBlur={keep}
                onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) e.currentTarget.blur(); if (e.key === "Escape") { setName(s.name); e.currentTarget.blur(); } }} />
            : <h1 className={pagesCss.identityName}>{s.name}</h1>}
          <p className={settingsCss.workspaceFacts}>
            <span className={css.status}><StatusDot state={s.online ? "online" : "offline"} />{state(s)}</span>
            {s.host && <span>{s.host.identity}</span>}
            {s.version && <span>Station {s.version}</span>}
            {joinedText(s) && <span>{joinedText(s)}</span>}
          </p>
          {/* What is wrong with it, under how it is. */}
          {wrong.length > 0 && <div className={css.warn}>{wrong.map((p) => <span key={p.key} data-level={p.level}>{p.text}</span>)}</div>}
        </div>
        <div className={css.headActions}>
          {(!s.online || silent) && <RetryPill />}
          {s.overview?.drive && <Button icon={Folder} onClick={() => navigate(`${stationBase(s.station)}/files`)}>{t("web-pages.drive.title")}</Button>}
          {manager && edits.busy(s)}
          {items.length > 0 && <Menu items={items} />}
        </div>
      </header>
    </>
  );
}

/** The rest of it, each part once there is something to show of it. */
function Body({ s, manager }: { s: StationView; manager: boolean }) {
  const o = s.overview;
  const base = stationBase(s.station);
  const folders = o?.drive?.roots ?? [];
  return (
    <>
      {s.online && s.host && (
        <Section title={t("web-pages.stations.page.resources")}>
          <div className={css.machine}>
            <MeterDials meters={s.host.meters} />
            {s.net && <Net net={s.net} flush />}
          </div>
        </Section>
      )}
      {o && (
        <Section title="Agent">
          <div className={css.figures}>
            <Figure n={o.counts.running} label={t("web-pages.stations.page.running")} accent={o.counts.running > 0} />
            <Figure n={o.counts.warm} label={t("web-pages.stations.page.warm")} />
            <Figure n={o.counts.sessions} label={t("web-pages.stations.page.sessions")} />
          </div>
          {o.processes.length > 0 && <p className={css.note}>{o.processesText}</p>}
        </Section>
      )}
      {/* Its screens, to see and drive (docs/remote-screens.md); a station from before them says so quietly. */}
      <ScreensSection station={s.station} />
      {o && o.profiles.length > 0 && (
        <Section title={<>Profile<span className={settingsCss.titleCount}>{o.profiles.length}</span></>}>
          <ul className={pagesCss.list}>
            {o.profiles.map((p) => (
              <li key={p.id}>
                {/* As the Profile page lists it: what it is, its models, who uses it, its allowance and its state. */}
                <ProfileCard profile={p} to={`${base}/settings/accounts/${encodeURIComponent(p.id)}`}
                  uses={p.usedBy.length ? t("web-pages.settings.profiles.usedBy", { n: p.usedBy.length }) : ""} />
              </li>
            ))}
          </ul>
        </Section>
      )}
      {o && o.connects.length > 0 && (
        <Section title={<>{t("web-pages.settings.nav.connects")}<span className={settingsCss.titleCount}>{o.connects.length}</span></>}>
          <ul className={pagesCss.list}>
            {o.connects.map((c) => (
              <li key={c.id}>
                <Link className={pagesCss.listRow} to={`${base}/connects/${encodeURIComponent(c.id)}`}>
                  <StatusDot state={c.presence} />
                  <span className={pagesCss.listRowText}>
                    <span className={pagesCss.listRowTitle}>{c.name}</span>
                    <span className={shellCss.muted}>{[c.team, c.runText].filter(Boolean).join(" · ")}</span>
                  </span>
                  {c.presence !== "online" && <span className={shellCss.muted}>{c.statusText}</span>}
                  <ChevronRight {...ICON} className={shellCss.muted} />
                </Link>
              </li>
            ))}
          </ul>
        </Section>
      )}
      {folders.length > 0 && (
        <Section title={<>{t("web-pages.drive.title")}<span className={settingsCss.titleCount}>{folders.length}</span></>}>
          <ul className={pagesCss.list}>
            {folders.map((r) => (
              <li key={r.path}>
                {/* Its name, where it is quiet after it, on one line. */}
                <Link className={`${pagesCss.listRow} ${css.folder}`} to={drivePath(base, r.path)} title={r.path}>
                  <Folder {...ICON} className={shellCss.muted} />
                  <span className={css.folderName}>{r.name}</span>
                  <span className={css.folderPath}>{r.path}</span>
                  <ChevronRight {...ICON} className={shellCss.muted} />
                </Link>
              </li>
            ))}
          </ul>
        </Section>
      )}
      {manager && !s.joined && <Workspaces s={s} />}
      {/* Its updates are its home workspace's managers' to make (docs/multi-workspace.md). */}
      <Section title={t("web-pages.stations.software")}>
        {s.online ? <SoftwareList station={s.station} updates={o?.updates} manager={manager && !s.joined} beta={s.betaOffered ?? false} /> : <p className={css.note}>{t("web-pages.stations.softwareOffline")}</p>}
        {!o?.updates?.length && s.version && <p className={css.note}>Station {s.version}</p>}
      </Section>
      <Section title={t("web-pages.stations.device")}>
        {s.host ? <HostDetails details={[...s.host.details, ...(o?.footprint?.text ? [{ label: t("web-pages.stations.page.footprint"), value: o.footprint.text }] : [])]} />
          : <p className={css.note}>{s.online ? t("web-pages.stations.deviceLoading") : t("web-pages.stations.deviceOffline")}</p>}
      </Section>
    </>
  );
}

/**
 * The workspaces it is in (docs/multi-workspace.md), for the owners and admins of its home one (this), once it is in more
 * than one: its home first, and what each has of the machine (the folders pinned for it).
 */
function Workspaces({ s }: { s: StationView }) {
  const m = useMemberships(s.station).value;
  if (!m?.manages || m.workspaces.length < 2) return null;
  return (
    <Section title={<>Workspace<span className={settingsCss.titleCount}>{m.workspaces.length}</span></>} description={t("web-pages.stations.workspacesLead")}>
      <div className={pagesCss.card}>
        {m.workspaces.map((w) => (
          <div key={w.workspace} className={pagesCss.cardRow}>
            <span className={pagesCss.cardRowText}><strong>{w.name}</strong><span className={shellCss.muted}>{w.line}</span></span>
          </div>
        ))}
      </div>
    </Section>
  );
}

/** A count large over what it counts, as the machine's dials are written; the agents at work in the accent. */
function Figure({ n, label, accent = false }: { n: number; label: string; accent?: boolean }) {
  return (
    <div className={css.figure}>
      <b className={css.figureNumber} data-accent={accent || undefined}>{n}</b>
      <span className={css.figureLabel}>{label}</span>
    </div>
  );
}
