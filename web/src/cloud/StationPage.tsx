// The stations on a wide screen with Station in the rail: the sidebar lists them (StationsNav), the page is the one picked
// (StationSettings), everything of it in one place: how it is, what is left of the machine, what runs on it (agents,
// profiles, connects, folders lent), its software and the machine itself. Elsewhere (no rail, or Station not in it) the
// settings' list of cards stays, each name opening this page.
import { useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import { Link, Navigate, NavLink, useParams, useSearchParams } from "react-router";
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
import { BackLink, Button, ICON, Menu, MobileBack, Pill, Section, Segmented, StatusDot, Time, Waiting } from "../ui.tsx";
import { SoftwareList } from "../Versions.tsx";
import { WorkspaceMark } from "../WorkspaceMark.tsx";
import { HostDetails, joinedText, LanKept, Net, silentOf, state, Uses, useStationNet } from "./StationCards.tsx";
import { ResourcesBody, useResources } from "../Resources.tsx";
import { useLanKept } from "../localNetwork.ts";
import { MarkPick } from "./MarkPick.tsx";
import { ProfileCard } from "../ProfileCard.tsx";
import type { EnvVar } from "../core/shapes.ts";
import { AgentEnvText, useAgentEnvForm } from "../AgentEnvText.tsx";
import { ScreensSection } from "../screen/ScreenList.tsx";
import { PermissionsSection } from "../StationPermissions.tsx";
import { SearchSection } from "../StationSearch.tsx";
import { LoginsSection } from "../MachineLogins.tsx";
import { NavAction, NavList, NavItem, NavLine, NavTop, navFill } from "../SidebarList.tsx";
import { AddStationDialog, useStationEdits, useWorkspace } from "./settings.tsx";
import { useStoppedHere, type StoppedHere } from "./thisMac.tsx";
import type { WorkspaceEntry } from "./workspace.tsx";
import * as railCss from "../Rail.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as settingsCss from "./settings.css.ts";
import * as css from "./StationPage.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { t } from "../i18n.ts";

const WIDE = typeof window === "undefined" ? null : window.matchMedia("(min-width: 701px)");

/** Whether the stations have the sidebar of their own: Station in the rail, and the rail there (a wide screen). */
export function useStationsSide(): boolean {
  const railed = useRailItems().includes("stations");
  const wide = useSyncExternalStore((f) => { WIDE?.addEventListener("change", f); return () => WIDE?.removeEventListener("change", f); }, () => WIDE?.matches ?? true, () => true);
  return railed && wide;
}

export const stationPage = (workspace: string, id: string) => `/w/${workspace}/settings/stations/${encodeURIComponent(id)}`;
/** A station's page with a login's panel open over it (the link agents post: docs/remote-login.md). */
/** Its 进程: what still.fail uses of the machine. */
export const stationProcesses = (workspace: string, id: string) => `${stationPage(workspace, id)}?part=processes`;
export const stationLoginPage = (workspace: string, id: string, login: string) => `${stationPage(workspace, id)}?login=${encodeURIComponent(login)}`;

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
 * seen while away); where it is from, if another workspace lent it; then, while it is up, what is left of its CPU, memory and disk in
 * small boxes (as in a chat's bar: their edge in their level's colour), and how this device reaches it, a newer version
 * there said too. Nothing in colour but what is off. */
function StationRow({ s: listed, to }: { s: StationView; to: string }) {
  // This machine's, stopped here: said at once, not when the cloud has seen it go.
  const here = useStoppedHere(listed);
  const s = here.stopped ? { ...listed, online: false } : listed;
  const meters = s.online ? s.host?.meters ?? [] : [];
  const net = useStationNet(s.online ? s.station : null);
  const lanKept = useLanKept(net?.lan);
  const newer = s.online && (s.overview?.updates ?? []).some((v) => v.installed && v.updatable && (v.newer || v.downgrade));
  return (
    <NavItem to={to} title={s.name}
      mark={s.emoji || s.icon ? <StationMark emoji={s.emoji} icon={s.icon} size={16} /> : <WorkspaceMark w={{ name: s.name }} size={16} />}
      end={<><span className={railCss.dot} data-online={s.online || undefined} />{here.stopped ? <span className={css.low} data-level="amber">{t("web-pages.stations.page.stopped")}</span> : brief(s)}</>}>
      {/* Where it is from, for one another workspace lent (what the machine is, its page says). */}
      {joinedText(s) && <NavLine><span className={navFill}>{joinedText(s)}</span></NavLine>}
      {meters.length > 0 && (
        <span className={css.rowMeters}>
          {meters.map((m) => <MeterChip key={m.label} meter={m} brief bare />)}
        </span>
      )}
      {s.online && (net || newer) && (
        <NavLine>
          <span className={navFill}>
            {net && <>{net.path}{net.rtt && <>{" · "}<span className={css.low} data-level={net.rtt.level}>{net.rtt.text}</span></>}</>}
            {net && lanKept && <>{" · "}<span className={css.low} data-level="amber">{t("web-pages.stations.page.lanKept")}</span></>}
            {net && newer && " · "}
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
/** Where the resources page was (Settings > 资源, a link from before): the first station's 进程. */
export function ProcessesFirst({ entry }: { entry: WorkspaceEntry }) {
  const first = useStations(entry.id).value?.[0];
  return first ? <Navigate to={stationProcesses(entry.id, first.id)} replace /> : <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}><Waiting shape="cards" text={t("common.readingStations")} /></div>;
}

export function StationsFirst({ entry }: { entry: WorkspaceEntry }) {
  const first = useStations(entry.id).value?.[0];
  return first ? <Navigate to={stationPage(entry.id, first.id)} replace /> : <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}><Waiting shape="cards" text={t("common.readingStations")} /></div>;
}

/** A station's own page. */
export function StationSettings({ entry }: { entry: WorkspaceEntry }) {
  const { station: id = "" } = useParams();
  const side = useStationsSide();
  const listed = useStations(entry.id).value;
  const { view, manager } = useWorkspace(entry);
  const edits = useStationEdits(view, entry.account, listed ?? []);
  const found = listed?.find((s) => s.id === id);
  // This machine's, stopped here: said at once (not when the cloud has seen it go), and started from its head.
  const here = useStoppedHere(found);
  const back = `/w/${entry.id}/settings/stations`;
  if (!listed) {
    return (
      <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
        {side ? <MobileBack to={back} label="Station" /> : <BackLink to={back} label="Station" />}
        <Waiting shape="cards" text={t("common.readingStations")} />
      </div>
    );
  }
  // Removed (or a link from before): the list, or the first of them.
  if (!found) return <Navigate to={back} replace />;
  const s = edits.shown(here.stopped ? { ...found, online: false } : found);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      {side ? <MobileBack to={back} label="Station" /> : <BackLink to={back} label="Station" />}
      <Head s={s} here={here} manager={manager} edits={edits} />
      {edits.dialogs}
      <Body s={s} manager={manager} workspace={entry.id} />
    </div>
  );
}

type Edits = ReturnType<typeof useStationEdits>;

/** Its mark and name (a title its managers rename where it is, as the workspace's), how it is and what it is; beside
 * them trying it again while away, and its ⋯ (its 文件 are opened from the overview's folders). */
function Head({ s, here, manager, edits }: { s: StationView; here: StoppedHere; manager: boolean; edits: Edits }) {
  const [name, setName] = useState(s.name);
  useEffect(() => setName(s.name), [s.name]);
  const keep = () => { const to = name.trim(); if (!to) setName(s.name); else edits.rename(s, to); };
  const silent = silentOf(s);
  // Stopped here: its 启动 says what to do, not how to reach it again.
  const wrong = here.stopped ? [] : s.problems;
  const items = edits.menu(s, manager, false);
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
            <span className={css.status}><StatusDot state={s.online ? "online" : "offline"} />{here.stopped ? t("web-pages.stations.page.stopped") : state(s)}</span>
            {s.host && <span>{s.host.identity}</span>}
            {s.version && <span>Station {s.version}</span>}
            {joinedText(s) && <span>{joinedText(s)}</span>}
          </p>
          {/* What is wrong with it, under how it is. */}
          {wrong.length > 0 && <div className={css.warn}>{wrong.map((p) => <span key={p.key} data-level={p.level}>{p.text}</span>)}</div>}
        </div>
        <div className={css.headActions}>
          {here.stopped
            ? <Button variant="primary" busy={here.starting} onClick={() => here.start.run()}>{t("web-pages.stations.page.start")}</Button>
            : (!s.online || silent) && <RetryPill trying={s.link.retrying === true} />}
          {manager && edits.busy(s)}
          {items.length > 0 && <Menu items={items} />}
        </div>
      </header>
    </>
  );
}

/** The page's parts, one shown at a time: how it is and what runs on it; what it is let do and set to; its software and
 * the machine. */
type Part = "overview" | "processes" | "settings" | "machine";
const PARTS: Part[] = ["overview", "processes", "settings", "machine"];

/** The rest of it in its parts (`?part=`, the overview by default), each section once there is something to show of it. */
function Body({ s, manager, workspace }: { s: StationView; manager: boolean; workspace: string }) {
  // A login's link (`/w/<ws>/s/<station>/login/<id>`, workspace.tsx) comes here with it: its card brought into view.
  const [search, setSearch] = useSearchParams();
  const asked = search.get("part") as Part | null;
  const part: Part = search.get("login") ? "settings" : asked && PARTS.includes(asked) ? asked : "overview";
  const show = (to: Part) => setSearch((was) => { const next = new URLSearchParams(was); next.delete("login"); if (to === "overview") next.delete("part"); else next.set("part", to); return next; }, { replace: true });
  return (
    <>
      <div className={css.parts}>
        <Segmented<Part> label={t("web-pages.stations.page.parts")} value={part} onChange={show}
          options={PARTS.map((p) => ({ value: p, label: t(`web-pages.stations.page.part.${p}`) }))} />
      </div>
      {part === "overview" && <Overview s={s} workspace={workspace} />}
      {part === "processes" && <Processes s={s} workspace={workspace} />}
      {part === "settings" && <Settings s={s} manager={manager} marked={search.get("login")} />}
      {part === "machine" && <Machine s={s} manager={manager} />}
    </>
  );
}

/** What still.fail uses of the machine, by chat and process, as Activity Monitor says it (../Resources.tsx). */
function Processes({ s, workspace }: { s: StationView; workspace: string }) {
  const resources = useResources(workspace, s.station);
  if (!s.online) return <p className={css.memory}>{t("web-pages.stations.processesOffline")}</p>;
  return (
    <div className={css.processes}>
      <p className={css.memory}>{t("web-pages.stations.processesLead")}</p>
      {resources.value ? <ResourcesBody view={resources.value} />
        : resources.error ? <p className={controlsCss.fieldError}>{t("web-pages.stations.processesFailed", { error: resources.error.message })}</p> : <Waiting shape="cards" />}
    </div>
  );
}

/** What is left of the machine (and what its agents take of it), and what runs on it: its screens, profiles, connects and
 * folders (its agents at work are in its head). */
function Overview({ s, workspace }: { s: StationView; workspace: string }) {
  const navigate = useGo();
  // What still.fail itself uses of the machine, opening the resources page: read (the station looking often) while shown.
  const uses = useResources(workspace, s.station).value?.stations[0]?.use;
  const o = s.overview;
  const base = stationBase(s.station);
  const folders = o?.drive?.roots ?? [];
  const net = useStationNet(s.online && s.host ? s.station : null);
  return (
    <>
      {s.online && s.host && (
        <Section title={t("web-pages.stations.page.resources")}>
          <div className={css.machine}>
            <MeterDials meters={s.host.meters} />
            {net && <Net net={net} flush />}
            {net && <LanKept lan={net.lan} />}
            {/* What its agents' processes take of the memory. */}
            {o && o.processes.length > 0 && <p className={css.memory}>{o.processesText}</p>}
            {uses && <Uses use={uses} to={stationProcesses(workspace, s.id)} flush />}
          </div>
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
      {/* Its drive (docs/drive.md): opened whole from here, or at one of the folders pinned. */}
      {o?.drive && (
        <Section title={<>{t("web-pages.drive.title")}{folders.length > 0 && <span className={settingsCss.titleCount}>{folders.length}</span>}</>}
          actions={<Button variant="ghost" icon={Folder} onClick={() => navigate(`${base}/files`)}>{t("web-pages.stations.page.openFiles")}</Button>}>
          {folders.length === 0 ? <p className={css.note}>{t("web-pages.drive.noneYet")}</p> : <ul className={pagesCss.list}>
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
          </ul>}
        </Section>
      )}
    </>
  );
}

/** What it is let do and set to: the grants macOS gives it, the tools logged in on it, its agents' variables, what its
 * search finds, the workspaces it is in. */
function Settings({ s, manager, marked }: { s: StationView; manager: boolean; marked: string | null }) {
  const o = s.overview;
  return (
    <>
      {/* What macOS lets its still.fail Helper do (a Mac's station only), each grant asked for from here. */}
      {s.online && o?.permissions && <PermissionsSection station={s.station} permissions={o.permissions} />}
      {/* The command-line tools its agents use, logged in here for every chat (docs/remote-login.md). */}
      <LoginsSection station={s.station} marked={marked} />
      {/* The variables what it starts for its agents runs with (docs/agent-env.md); none from a station from before them. */}
      {o?.agentEnv && <AgentEnv station={s.station} env={o.agentEnv} manager={manager} />}
      {/* What its search finds of the machine (docs/search.md): the person's own data only where its managers say. */}
      {s.online && o?.search && <SearchSection station={s.station} search={o.search} manager={manager} />}
      {manager && <Workspaces s={s} />}
    </>
  );
}

/** Its software, its updates, and the machine itself. */
function Machine({ s, manager }: { s: StationView; manager: boolean }) {
  const o = s.overview;
  return (
    <>
      {/* Its updates are its home workspace's managers' to make (docs/multi-workspace.md). */}
      <Section title={t("web-pages.stations.software")}>
        {s.online ? <SoftwareList station={s.station} updates={o?.updates} manager={manager} beta={s.betaOffered ?? false} /> : <p className={css.note}>{t("web-pages.stations.softwareOffline")}</p>}
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
 * The variables everything it starts for its agents runs with (docs/agent-env.md: a proxy, mostly): its managers edit
 * them as a .env file's lines (AgentEnvText.tsx); the others see them, a secret's value masked.
 */
function AgentEnv({ station, env, manager }: { station: string; env: EnvVar[]; manager: boolean }) {
  if (manager) return <AgentEnvEditor station={station} />;
  if (env.length === 0) return null;
  return (
    <Section title={t("web-pages.stations.agentEnv")}>
      <div className={pagesCss.card}>
        {env.map((e) => (
          <div key={e.key} className={pagesCss.cardRow}>
            <span className={pagesCss.cardRowText}><strong className={shellCss.mono}>{e.key}</strong><span className={`${shellCss.muted} ${shellCss.mono}`}>{e.value}</span></span>
          </div>
        ))}
      </div>
    </Section>
  );
}

function AgentEnvEditor({ station }: { station: string }) {
  const form = useAgentEnvForm(station);
  return (
    <Section title={t("web-pages.stations.agentEnv")} description={t("web-pages.stations.agentEnvLead")}>
      <div className={pagesCss.card}>
        <AgentEnvText form={form} fieldClass={`${controlsCss.input} ${css.envField}`} label={t("web-pages.stations.agentEnv")} />
        <div className={pagesCss.cardActions}>
          {form.d?.dirty && <Button variant="ghost" onClick={form.reset}>{t("common.cancel")}</Button>}
          <Button variant="primary" busy={form.saving} disabled={!form.canSave} onClick={form.save}>{t("common.save")}</Button>
        </div>
      </div>
    </Section>
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
