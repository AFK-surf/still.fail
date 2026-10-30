// A workspace in still.fail cloud: every station's chats and connects in one
// place. The core reaches each station and puts the workspace's views
// together (docs/client-core.md); a page opened from the sidebar talks to the
// station the item belongs to (StationContext).
import { ProcessesFirst, stationLoginPage, StationSettings, StationsFirst, StationsNav, useStationsSide } from "./StationPage.tsx";
import { ShareInPanel } from "../ShareIn.tsx";
import { Check, ChevronsUpDown, Plus, Settings, UserPlus } from "@stillfail/ui/icons.tsx";
import { NewChat } from "../NewChat.tsx";
import { lastChatOf, useLastChat, useRememberChat, useWorkspaceMarks } from "../lastChat.ts";
import { DropdownMenu } from "radix-ui";
import { memo, useEffect, useMemo, useRef, useState, useSyncExternalStore, type CSSProperties, type ReactNode } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { useChats, useStationViews, useStations } from "../api.ts";
import { useGo } from "../go.ts";
import type { Topic } from "../core/client.ts";
import { useReady, useTopics } from "../core/react.ts";
import { LOCAL_MS } from "@stillfail/ui/motion.ts";
import { AccountPage, PickModelsPage } from "../pages/Accounts.tsx";
import { ConnectPage } from "../pages/Connect.tsx";
import { DriveHome, DrivePage, DrivePlayPage, DriveReadPage } from "../pages/Drive.tsx";
import { FilesNav } from "../pages/FilesNav.tsx";
import { ChatPage } from "../pages/ChatPage.tsx";
import { ScreenPage } from "../screen/ScreenPage.tsx";
import { ChatList, StationTrouble, useGlassBands } from "../Sidebar.tsx";
import { Rail, SidebarEdge, openingWidth, placeOf, useRailItems, type RailItem } from "../Rail.tsx";
import { SystemBubbles } from "../SystemBubbles.tsx";
import * as railCss from "../Rail.css.ts";
import { drivePath } from "../drive/useDrive.ts";
import { Folder, Server } from "@stillfail/ui/icons.tsx";
import { AttentionEntry } from "../Attention.tsx";
import { MarkCounts } from "../ChatMark.tsx";
import { WorkspaceBadge } from "../WorkspaceMark.tsx";
import { OpenJobsChip } from "../OpenJobs.tsx";
import { GlobalShortcuts } from "../Switcher.tsx";
import { workspaceIndexOf, workspaceKeyLabel } from "../keymap.ts";
import { ArchivePage } from "../pages/Archive.tsx";
import { AppearancePage } from "../pages/Appearance.tsx";
import { NotificationsPage } from "../pages/Notifications.tsx";
import { ArchivingPage } from "../pages/Archiving.tsx";
import { PermissionsPage } from "../pages/Permissions.tsx";
import { ChangelogNews, ChangelogPage } from "../pages/Changelog.tsx";
import { AboutPage } from "../pages/About.tsx";
import { AddProfile } from "../pages/AddProfile.tsx";
import { ProfilesNav } from "../ProfilesNav.tsx";
import { NavAction, NavList, NavItem, NavSection, NavTop } from "../SidebarList.tsx";
import { SecurityOpen, SecurityPrompt, SecuritySettings, SecurityWaiting, useLock } from "./Security.tsx";
import { VaultAll, VaultSettings } from "./Vault.tsx";
import { VaultItemPage } from "./VaultItem.tsx";
import { AutomaticDecisionCompletionSettings, AutomaticDecisionPolicySettings, StationArchivingSettings, AutomaticDecisionsSettings, AccountSettings, ConnectsSettings, FirstStation, JoinExistingLink, MemoryDocSettings, MemorySettings, MemoryStationSettings, ProfileAccountSettings, RuntimeSettings, SettingsNav, useSettingsCommands, StationsSettings, UsageSettings, UsagePricesSettings, WorkspaceSettings } from "./settings.tsx";
import { PeopleContext, profilesPage, scopeOf, StationContext, stationBase, useSidebarMode, useStationList, type Station } from "../station.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { Button, Dialog, Empty, Field, ICON, Select, Tip, Spinner, Waiting } from "../ui.tsx";
import { ChatSample, toMadeChat } from "../Chat.tsx";
import { ComposerDock } from "../dock.tsx";
import { Previews } from "../Previews.tsx";
import { useAccounts, useSignIn, type Account } from "./accounts.ts";
import { cloud, errorText, inviteCode, needsInviteCode, useAction, useWorkspace, useWorkspaces, type PendingInvitation } from "./api.ts";
import { Illustration, PageBrand, SidebarBrand, useSidebarClosed } from "../brand.tsx";
import { identify, track } from "../telemetry.ts";
import { useInWorkspace } from "../notify.ts";
import * as nav from "../Sidebar.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./workspace.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as chatMarkCss from "../ChatMark.css.ts";

import { WebUpdate } from "../WebUpdate.tsx";
import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { StationWordsIn } from "../StationNamed.tsx";
import { tx } from "./words.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";
/** The workspace in view and the signed-in account that reaches it. */
export interface WorkspaceEntry { id: string; name: string; account: Account }

const NO_STATIONS: Station[] = [];

interface InvitationEntry extends PendingInvitation { account: Account }

/** Nothing to hear: whether the page is built ahead (on the server) does not change once it is drawn. */
const never = () => () => undefined;

/**
 * Drawn again only as the page changes (its path) or its stations do: what changes more often (the workspace's members,
 * the views kept read, what the core marks) is read below it, where it is used, so a message coming in or the side panel
 * opening does not draw the sidebar and the page again from here.
 */
export const WorkspaceShell = memo(function WorkspaceShell({ entry }: { entry: WorkspaceEntry }) {
  // Come from another workspace (a navigation, so a transition), the one left stays until this one's stations are
  // known, as a chat's page waits for its chat: not a page of nothing first.
  useReady({ topic: "stations", scope: entry.id }, LOCAL_MS);
  const known = useStationViews(entry.id);
  const stations = useStationList(known, entry.id) ?? NO_STATIONS;
  const path = useLocation().pathname;
  const navigate = useGo();
  const detail = /\/(s\/[^/]+\/.+|settings|new$|files$)/.test(path);
  // Settings, a connect or a station's runtime accounts: the sidebar becomes the settings menu.
  // A place in the rail (Station, Profile, 连接, 用量) is a page of its own beside the chats, not one of the settings: those
  // left out of it are reached in the settings, and are among them there.
  const railed = useRailItems();
  const wide = useWide();
  const place = placeOf(path);
  const settings = /^\/w\/[^/]+\/(settings|s\/[^/]+\/(connects|settings))(\/|$)/.test(path)
    && !(place !== "settings" && place !== "files" && railed.includes(place as RailItem) && wide);
  // Which sidebar is drawn. A page in the rail with none of its own (连接, 用量) closes it (Rail.tsx): the one
  // it had stays while it goes, not the chats' list first; opened again there, it is the chats'.
  const own = settings ? "settings" : place === "files" || place === "profiles" || place === "stations" ? place : "chats";
  const bare = !settings && (place === "connects" || place === "usage") && railed.includes(place as RailItem) && wide;
  const closed = useSidebarClosed();
  const kept = useRef<{ side: typeof own; closed: boolean; reopened: boolean }>({ side: own, closed, reopened: false });
  if (!bare) kept.current = { side: own, closed, reopened: false };
  else { if (kept.current.closed && !closed) kept.current.reopened = true; kept.current.closed = closed; }
  const side = bare && !kept.current.reopened ? kept.current.side : own;
  // Built to HTML ahead (the site's demo: demo/prerender.tsx), where no effect puts the sidebar's width on the page's
  // root (Rail.tsx widthFor), the shell says the width it opens at itself.
  const ahead = useSyncExternalStore(never, () => false, () => true);
  const opening = ahead ? openingWidth(side) : "";
  const [mode, setMode] = useSidebarMode();
  const lock = useLock(entry.id);
  const waiting = lock?.me?.waiting === true;
  // The archive's page, come to any way (a link, the phone's way): the sidebar shows the archive.
  const archive = /^\/w\/[^/]+\/archive$/.test(path);
  useEffect(() => { if (archive && mode !== "archive") setMode("archive"); }, [archive]); // eslint-disable-line react-hooks/exhaustive-deps

  // No station yet: nothing of the workspace's pages works, so none is shown; adding the first station is the page.
  // The devices waiting on this one (in any workspace of the person's) are put up on each of its pages.
  if (known && known.length === 0 && !settings) return <><WorkspaceKept entry={entry} /><SecurityPrompt /><Onboarding entry={entry} /></>;
  // A device waiting to be confirmed into the workspace's lock: nothing of it is reached until it is (its settings are).
  if (waiting && !settings) {
    return (
      <><WorkspaceKept entry={entry} /><SecurityPrompt />
        <Bare entry={entry}><main>{lock && <SecurityWaiting entry={entry} lock={lock} />}</main></Bare>
      </>
    );
  }

  return (
    <WorkspacePeople id={entry.id}>
      <WorkspaceKept entry={entry} />
      <div className={shellCss.shell} data-detail={detail} data-rail="" style={opening ? { "--sidebar-w": opening } as CSSProperties : undefined}>

        <GlobalShortcuts scope={entry.id} newChat={`/w/${entry.id}/new`} settings={`/w/${entry.id}/settings`} />
        {/* The rail and the sidebar in one block, which closes to the rail as a bar (shell.css.ts dock). */}
        <div className={shellCss.dock}>
        <Rail scope={entry.id} workspace={<WorkspaceSwitcher current={entry} adder />} />
        {side === "settings"
          ? <nav className={nav.sidebar} aria-label={t("web-pages.settings.title")}><div className={`${nav.brand} ${nav.brandCompact}`}><SidebarBrand rail /></div><SettingsNav entry={entry} /><div className={nav.navFoot}><div className={railCss.narrowOnly}><WebUpdate /><WorkspaceSwitcher current={entry} /></div></div></nav>
          : side === "files" ? <FilesSidebar entry={entry} />
          : side === "profiles" ? <ProfilesSidebar entry={entry} />
          : side === "stations" ? <StationsSidebar entry={entry} />
          : <WorkspaceSidebar entry={entry} />}
        </div>
        <SidebarEdge />
        <SystemBubbles scope={entry.id} />
        <SecurityPrompt />
        {/* What another app shares (shareIn.ts), over whichever page is open. */}
        <ShareInPanel scope={entry.id} />
        <main className={shellCss.main}>
          <ComposerDock>
          <Routes>
            <Route index element={<WorkspaceHome id={entry.id} stations={known && stations} />} />
            {/* The settings come to their list's first row's page, the account's (settingsList.tsx). */}
            <Route path="settings" element={<Navigate to="account" replace />} />
            <Route path="settings/appearance" element={<AppearancePage back={`/w/${entry.id}/settings`} />} />
            {/* A phone's page of the fonts (mobile/Fonts.tsx): the wide screen has them on 外观. */}
            <Route path="settings/appearance/fonts" element={<AppearancePage back={`/w/${entry.id}/settings`} />} />
            <Route path="settings/notifications" element={<NotificationsPage back={`/w/${entry.id}/settings`} workspace={entry.id} />} />
            <Route path="settings/permissions" element={<PermissionsPage back={`/w/${entry.id}/settings`} />} />
            <Route path="settings/changelog" element={<ChangelogPage back={`/w/${entry.id}/settings`} />} />
            <Route path="settings/about" element={<AboutPage back={`/w/${entry.id}/settings`} />} />
            <Route path="settings/account" element={<AccountSettings entry={entry} />} />
            <Route path="settings/workspace" element={<WorkspaceSettings entry={entry} />} />
            <Route path="settings/security" element={<SecuritySettings entry={entry} />} />
            <Route path="settings/security/open" element={<SecurityOpen entry={entry} />} />
            <Route path="settings/vault" element={<VaultSettings entry={entry} />} />
            <Route path="settings/vault/all" element={<VaultAll entry={entry} />} />
            <Route path="settings/vault/:vault/:item" element={<VaultItemPage entry={entry} />} />
            {/* Pages the workspace page took in: links to them still land there. */}
            <Route path="settings/general" element={<Navigate to={`/w/${entry.id}/settings/workspace`} replace />} />
            <Route path="settings/members" element={<Navigate to={`/w/${entry.id}/settings/workspace`} replace />} />
            <Route path="settings/stations" element={<StationsIndex entry={entry} />} />
            <Route path="settings/stations/:station" element={<StationSettings entry={entry} />} />
            <Route path="settings/connects" element={<ConnectsSettings entry={entry} />} />
            <Route path="settings/archive" element={<ArchivingPage back={`/w/${entry.id}/settings`} workspace={entry.id} />} />
            <Route path="settings/archive/:station" element={<StationArchivingSettings entry={entry} />} />
            <Route path="settings/automatic-decisions" element={<AutomaticDecisionsSettings entry={entry} />} />
            <Route path="settings/automatic-decisions/completion" element={<AutomaticDecisionCompletionSettings entry={entry} />} />
            <Route path="settings/automatic-decisions/completion/:station" element={<AutomaticDecisionPolicySettings entry={entry} />} />
            <Route path="settings/profiles/add/:provider?" element={<AddProfile workspace={entry.id} />} />
            <Route path="settings/profiles" element={<RuntimeSettings entry={entry} />} />
            <Route path="settings/profiles/account/:key" element={<ProfileAccountSettings entry={entry} />} />
            <Route path="settings/memory" element={<MemorySettings entry={entry} />} />
            <Route path="settings/memory/:station" element={<MemoryStationSettings entry={entry} />} />
            <Route path="settings/memory/:station/global" element={<MemoryDocSettings entry={entry} />} />
            <Route path="settings/memory/:station/skill/:name" element={<MemoryDocSettings entry={entry} />} />
            <Route path="settings/usage/prices" element={<UsagePricesSettings entry={entry} />} />
            <Route path="settings/usage" element={<UsageSettings entry={entry} />} />
            <Route path="settings/resources" element={<ProcessesFirst entry={entry} />} />
            <Route path="settings/stations/:station/footprint" element={<Navigate to={`/w/${entry.id}/settings/stations`} replace />} />
            <Route path="settings/leave" element={<Navigate to={`/w/${entry.id}/settings/workspace`} replace />} />
            <Route path="s/:station/*" element={<StationPages stations={known && stations} />} />
            <Route path="files" element={<DriveHome scope={entry.id} />} />
            <Route path="archive" element={<ArchivePage scope={entry.id} wide={wide} />} />
            <Route path="new" element={<NewChat scope={entry.id} onCreated={(station, session) => toMadeChat(() => navigate(`${stationBase(station)}/chats/${encodeURIComponent(session)}`))} />} />
            <Route path="*" element={<Navigate to={`/w/${entry.id}`} replace />} />
          </Routes>
          </ComposerDock>
        </main>
        <Previews />
      </div>
    </WorkspacePeople>
  );
});

/** The workspace's members, by email, for what shows people (PeopleContext), and its stations for the words that name them (StationWordsIn): read here, not by the shell. */
function WorkspacePeople({ id, children }: { id: string; children: ReactNode }) {
  const members = useWorkspace(id).value?.members;
  const people = useMemo(() => new Map((members ?? []).map((m) => [m.email.toLowerCase(), { name: m.name, email: m.email, picture: m.picture }])), [members]);
  return <PeopleContext.Provider value={people}><StationWordsIn scope={id}>{children}</StationWordsIn></PeopleContext.Provider>;
}

/**
 * What the workspace's page keeps going while it is open, drawing nothing: its commands, the chat last open (a core from
 * before it keeps that itself), who is signed in, and the views its pages and settings show, subscribed from the start:
 * a page opened the first time draws at once, with no frame waiting for the core's first answer. What the core keeps in
 * sync is its own call (sync/scheduler.ts); these only read it.
 */
const WorkspaceKept = memo(function WorkspaceKept({ entry }: { entry: WorkspaceEntry }) {
  const found = useStations(entry.id);
  useSettingsCommands(entry);
  useRememberChat(entry.id, (p) => /^\/w\/[^/]+\/(new|s\/[^/]+\/chats\/.+)$/.test(p));
  useEffect(() => identify(entry.account), [entry.account]);
  useInWorkspace(entry.id);
  useTopics<unknown>([
    { topic: "connects", scope: entry.id, mine: false },
    { topic: "connects", scope: entry.id, mine: true },
    { topic: "chats", scope: entry.id, mine: false },
    { topic: "chats", scope: entry.id, mine: true },
    { topic: "loginSessions", account: entry.account.sub },
    ...(found.value ?? []).map((s): Topic => ({ topic: "overview", station: s.station })),
  ]);
  return null;
});

/** Whether the rail is there (Rail.css.ts): a wide screen, followed as the window is resized. */
function useWide(): boolean {
  const query = typeof window === "undefined" ? null : window.matchMedia("(min-width: 701px)");
  return useSyncExternalStore((f) => { query?.addEventListener("change", f); return () => query?.removeEventListener("change", f); }, () => query?.matches ?? true, () => true);
}

/** `stations` is undefined until the core has listed them: until then nothing is said (least of all "no such station"). */
function StationPages({ stations }: { stations: Station[] | undefined }) {
  const { station: id } = useParams();
  if (!stations) return null;
  const station = stations.find((s) => s.id === id);
  if (!station) return <Empty><p>{t("web-pages.workspace.noSuchStation")}</p></Empty>;
  // Offline, its pages still show what the core kept of it; the core says where nothing can be done.
  return (
    <StationContext.Provider value={station}>
      <Routes>
        <Route path="chats/:chat?" element={<ChatPage />} />
        <Route path="connects/:id" element={<ConnectPage />} />
        {/* Its drive (docs/drive.md): a folder (?root=&path=), a file read or played on a page of its own. */}
        <Route path="files" element={<DrivePage />} />
        <Route path="files/read" element={<DriveReadPage />} />
        <Route path="files/play" element={<DrivePlayPage />} />
        {/* One of its screens, seen and driven (docs/remote-screens.md): its row on the station's page, an agent's link. */}
        <Route path="screen/:id" element={<ScreenPage />} />
        {/* A station's 共享调试 is the Android app's (its agent links here: the Rust station's adb.rs). */}
        <Route path="adb" element={<Empty><p>{t("web-pages.workspace.adbOnPhone")}</p></Empty>} />
        {/* A login's link, as its agent posts it (docs/remote-login.md): the station's page with its panel open. */}
        <Route path="login/:login" element={<LoginLink station={station} />} />
        {/* One Profile page for the workspace: a station's own list is it. */}
        <Route path="settings/accounts" element={<Navigate to={profilesPage(station)} replace />} />
        <Route path="settings/accounts/:id" element={<AccountPage />} />
        <Route path="settings/accounts/:id/models" element={<PickModelsPage />} />
        <Route path="*" element={<Navigate to="chats" replace />} />
      </Routes>
    </StationContext.Provider>
  );
}

/** A workspace with none of its pages yet (no station, or this device not yet approved): the brand and the workspace
 * switcher over the one page there is. */
function Bare({ entry, children }: { entry: WorkspaceEntry; children: ReactNode }) {
  return (
    <div className={css.onboarding}>
      <header className={css.onboardingBar}>
        <div className={`${nav.brand} ${nav.brandCompact}`}><PageBrand /></div>
        <div className={css.onboardingAccount}><WorkspaceSwitcher current={entry} /></div>
      </header>
      {children}
    </div>
  );
}

/** `login/<id>` of a station: its page, the login's panel open over it. */
function LoginLink({ station }: { station: Station }) {
  const { login = "" } = useParams();
  return <Navigate to={stationLoginPage(scopeOf(station.address), station.id, login)} replace />;
}

/**
 * A workspace with no station: what a station is and adding the first one, in the page; the workspace switcher (the
 * account, other workspaces) and the workspace's settings (inviting people) stay at hand. Its pages come once a station
 * has joined.
 */
function Onboarding({ entry }: { entry: WorkspaceEntry }) {
  return (
    <Bare entry={entry}>
      <main className={css.onboardingMain}>
        <Illustration name="no-station" />
        <h1 className={css.onboardingTitle}>{t("web-pages.workspace.onboarding.title")}</h1>
        <p className={css.onboardingLead}>{t("web-pages.workspace.onboarding.lead")}</p>
        <FirstStation entry={entry} />
        <p className={`${css.onboardingFoot} ${shellCss.muted}`}>
          <Link className={chatCss.inlineLink} to={`/w/${entry.id}/settings/workspace`}>{t("web-pages.workspace.onboarding.invite")}</Link>
          <span aria-hidden="true"> · </span>
          <Link className={chatCss.inlineLink} to={`/w/${entry.id}/settings/workspace`}>{t("web-pages.workspace.onboarding.settings")}</Link>
          <JoinExistingLink entry={entry} className={`${chatCss.inlineLink} ${css.onboardingLinkButton}`} />
        </p>
      </main>
    </Bare>
  );
}

/** `stations` is undefined until the core has listed them. */
function WorkspaceHome({ id, stations }: { id: string; stations: Station[] | undefined }) {
  const last = useLastChat(id, `/w/${id}/new`);
  if (!stations) return <Waiting fill text={t("common.readingStations")} sample={<ChatSample />} />;
  // With stations there is always a chat in view: the one last open (the core keeps it), or a new one.
  if (stations.length) return last ? <Navigate to={last} replace /> : <Waiting fill sample={<ChatSample />} />;
  return (
    <Empty>
      <Illustration name="no-station" />
      <h2>{t("web-pages.workspace.empty.title")}</h2>
      <p>{tx("web-pages.workspace.empty.body", { name: NAME, link: <Link className={chatCss.inlineLink} to={`/w/${id}/settings/stations`}>{t("web-pages.workspace.empty.link")}</Link> })}</p>
    </Empty>
  );
}

// ── sidebar ─────────────────────────────────────────────────────────────

/** Drawn again only for another workspace: its lists and foot follow what they show themselves. */
const WorkspaceSidebar = memo(function WorkspaceSidebar({ entry }: { entry: WorkspaceEntry }) {
  return (
    <nav ref={useGlassBands()} className={nav.sidebar} aria-label={t("web-pages.workspace.navigation")}>
      <ChatList top={<div className={`${nav.brand} ${nav.brandCompact}`}><SidebarBrand rail /></div>} scope={entry.id} newChat={`/w/${entry.id}/new`} stationsPage={`/w/${entry.id}/settings/stations`} archive={`/w/${entry.id}/archive`}
        below={<SidebarTodo scope={entry.id} />} />
      <WorkspaceSidebarFooter entry={entry} />
    </nav>
  );
});

/** 待处理 under 新建对话; with it in the rail (Rail.tsx), only on a narrow screen (no rail there). */
function SidebarTodo({ scope }: { scope: string }) {
  const railed = useRailItems().includes("attention");
  return <div className={railed ? `${nav.navTodo} ${railCss.narrowOnly}` : nav.navTodo}><AttentionEntry scope={scope} /></div>;
}

/** Under the sidebar's lists: workspace controls, and what wants the viewer. */
function WorkspaceSidebarFooter({ entry }: { entry: WorkspaceEntry }) {
  const railed = useRailItems().includes("attention");
  return (
      <div className={nav.navFoot}>
        {/* Beside the rail the app's own news is its bubbles (SystemBubbles.tsx); on a narrow screen, here. */}
        <div className={railCss.narrowOnly}><WebUpdate /><ChangelogNews to={`/w/${entry.id}/settings/changelog`} /></div>
        {/* How the stations are, and the services left up long, in one line; what wants the viewer is at the top. With
            the rail's bell (Attention.tsx), they are in it. */}
        <div className={railed ? `${nav.navFootStatus} ${railCss.narrowOnly}` : nav.navFootStatus}>
          <StationTrouble scope={entry.id} to={`/w/${entry.id}/settings/stations`} />
          <OpenJobsChip scope={entry.id} />
        </div>
        <div className={`${nav.navFootRow} ${railCss.narrowOnly}`}>
          <WorkspaceSwitcher current={entry} />
          <Tip label={t("web-pages.settings.title")} side="top"><NavLink className={pageCss.iconBtn} to={`/w/${entry.id}/settings`} aria-label={t("web-pages.settings.title")}><Settings {...ICON} /></NavLink></Tip>
        </div>
      </div>
  );
}

/** The sidebar while in the files (Rail.tsx): the folders each station lends, under its name. */
function FilesSidebar({ entry }: { entry: WorkspaceEntry }) {
  return (
    <nav ref={useGlassBands()} className={nav.sidebar} aria-label={t("web-pages.drive.title")}>
      <FilesNav scope={entry.id} top={<div className={`${nav.brand} ${nav.brandCompact}`}><SidebarBrand rail /></div>} />
      <WorkspaceSidebarFooter entry={entry} />
    </nav>
  );
}

/** The sidebar while in the profiles, with Profile in the rail (Rail.tsx): every profile of the workspace. */
function ProfilesSidebar({ entry }: { entry: WorkspaceEntry }) {
  return (
    <nav ref={useGlassBands()} className={nav.sidebar} aria-label="Profile">
      <ProfilesNav scope={entry.id} top={<div className={`${nav.brand} ${nav.brandCompact}`}><SidebarBrand rail /></div>} />
      <WorkspaceSidebarFooter entry={entry} />
    </nav>
  );
}

/** The sidebar while in Station (Rail.tsx): the stations, each opening its page (StationPage.tsx). */
function StationsSidebar({ entry }: { entry: WorkspaceEntry }) {
  return (
    <nav ref={useGlassBands()} className={nav.sidebar} aria-label="Station">
      <StationsNav entry={entry} top={<div className={`${nav.brand} ${nav.brandCompact}`}><SidebarBrand rail /></div>} />
      <WorkspaceSidebarFooter entry={entry} />
    </nav>
  );
}

/** Station's page: with the sidebar of their own, the first of them; else the settings' list of them. */
function StationsIndex({ entry }: { entry: WorkspaceEntry }) {
  return useStationsSide() ? <StationsFirst entry={entry} /> : <StationsSettings entry={entry} />;
}

/** At the sidebar's foot: the workspace in view, which account it belongs to, and the others. */
/**
 * `adder`: in the rail (Rail.tsx), under the workspaces it lists: a dashed ＋ whose menu is making a workspace, signing in
 * another account and the invitations, no list of the workspaces (the rail has them); a dot on it while one waits.
 */
function WorkspaceSwitcher({ current, adder }: { current: WorkspaceEntry; adder?: boolean }) {
  const byAccount = useWorkspaces().value ?? [];
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const toast = useToast();
  const [creating, setCreating] = useState(false);
  const signIn = useSignIn();
  const respond = useAction(
    ({ invite, accept }: { invite: InvitationEntry; accept: boolean }) =>
      accept ? cloud.acceptInvitationById(invite.account.sub, invite.id) : cloud.declineInvitation(invite.account.sub, invite.id).then(() => null),
    (joined, { invite }) => {
      if (joined) { toast(t("web-pages.workspace.joined", { name: invite.name })); navigate(`/w/${joined.id}`); } else toast(t("web-pages.workspace.ignored"));
    },
  );
  const pending = byAccount.flatMap((a) => a.invitations.map((i): InvitationEntry => ({ ...i, account: a.account })));
  const isCurrent = (sub: string, id: string) => id === current.id && sub === current.account.sub;
  const all = byAccount.flatMap(({ account, workspaces: items }) => items.map((w) => ({ account, w })));
  // What the others have waiting, as the core counts it: one dot on the trigger, one by each in the menu.
  const marks = useWorkspaceMarks(current.id);
  const othersTone = marks?.others;
  // Straight to the chat last open there (WorkspaceHome would go on to it after drawing a page of its own first).
  const to = (id: string) => lastChatOf(marks, id) ?? `/w/${id}`;
  const allRef = useRef(all);
  allRef.current = all;
  const toRef = useRef(to);
  toRef.current = to;
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const i = workspaceIndexOf(e);
      const to = i === null ? undefined : allRef.current[i];
      if (!to) return;
      e.preventDefault();
      if (!isCurrent(to.account.sub, to.w.id)) navigate(toRef.current(to.w.id));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });
  return (
    <>
      <DropdownMenu.Root modal={false}>
        <DropdownMenu.Trigger asChild>
          {adder ? (
            <button type="button" className={railCss.workspaceAdd} aria-label={t("web-main.rail.addWorkspace")} title={t("web-main.rail.addWorkspace")}>
              {respond.busy || signIn.busy ? <Spinner /> : <Plus size={16} />}
              {pending.length > 0 && <span className={railCss.mark}><span className={css.inviteDot} role="img" aria-label={t("web-pages.workspace.invitationsCount", { n: pending.length })} /></span>}
            </button>
          ) : (
          <button type="button" className={css.accountTrigger}>
            <span className={css.accountText}>
              <span className={css.accountName}>{current.name}</span>
            </span>
            {othersTone
              ? <span className={chatMarkCss.chatMarkInline} data-tone={othersTone} role="img" aria-label={marks?.othersLabel ?? ""} title={marks?.othersLabel ?? undefined} />
              : pending.length > 0 && <span className={css.inviteDot} role="img" aria-label={t("web-pages.workspace.invitationsCount", { n: pending.length })} />}
            {respond.busy || signIn.busy
              ? <Spinner className={css.accountSpinner} label={signIn.busy ? t("web-pages.workspace.openingSignIn") : t("web-pages.workspace.answering")} />
              : <ChevronsUpDown {...ICON} size={14} />}
          </button>
          )}
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${css.accountMenu}`} side={adder ? "right" : "top"} align={adder ? "end" : "start"} sideOffset={adder ? 10 : 6}>
            {/* Seldom done: a line of small words atop, the list nearest the trigger it opens from; not rows to land on when reaching for a workspace. */}
            {/* The rail's ＋ is for them alone: they are its rows. */}
            {adder ? (
              <>
                <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => setCreating(true)}><Plus {...ICON} />{t("web-pages.workspace.create")}</DropdownMenu.Item>
                <DropdownMenu.Item className={controlsCss.menuItem} disabled={signIn.busy} onSelect={() => void signIn.signIn()}><UserPlus {...ICON} />{t("web-pages.workspace.addAccount")}</DropdownMenu.Item>
                {pending.length > 0 && <DropdownMenu.Separator className={controlsCss.menuSep} />}
              </>
            ) : (
            <div className={css.menuRare}>
              <DropdownMenu.Item className={css.menuRareItem} onSelect={() => setCreating(true)}><span className={css.menuRareIcon}><Plus {...ICON} size={13} /></span>{t("web-pages.workspace.create")}</DropdownMenu.Item>
              <DropdownMenu.Item className={css.menuRareItem} disabled={signIn.busy} onSelect={() => void signIn.signIn()}><span className={css.menuRareIcon}><UserPlus {...ICON} size={13} /></span>{t("web-pages.workspace.addAccount")}</DropdownMenu.Item>
            </div>
            )}
            {pending.length > 0 && (
              <>
                <DropdownMenu.Label className={controlsCss.menuLabel}>{t("web-pages.workspace.invitations")}</DropdownMenu.Label>
                {pending.map((invite) => (
                  <div key={invite.id} className={css.menuInvite}>
                    <span className={css.threadItem}>
                      <span>{t("web-pages.workspace.invitedYou", { inviter: invite.inviter || t("web-pages.cloud.someone"), name: invite.name })}</span>
                      <span className={shellCss.muted}>{invite.account.email}{list.length > 1 ? "" : ""}</span>
                    </span>
                    {/* The menu stays open while it goes: the button turns, and what went wrong shows under it. */}
                    <span className={css.menuInviteActions}>
                      <DropdownMenu.Item className={`${controlsCss.btn} ${controlsCss.btnPrimary} ${css.menuInviteBtn}`} disabled={respond.busy}
                        aria-busy={(respond.busy && respond.arg?.invite.id === invite.id && respond.arg.accept) || undefined}
                        onSelect={(e) => { e.preventDefault(); respond.run({ invite, accept: true }); }}>
                        {respond.busy && respond.arg?.invite.id === invite.id && respond.arg.accept && <Spinner />}{t("web-pages.cloud.join")}
                      </DropdownMenu.Item>
                      <DropdownMenu.Item className={`${controlsCss.btn} ${controlsCss.btnGhost} ${css.menuInviteBtn}`} disabled={respond.busy}
                        aria-busy={(respond.busy && respond.arg?.invite.id === invite.id && !respond.arg.accept) || undefined}
                        onSelect={(e) => { e.preventDefault(); respond.run({ invite, accept: false }); }}>
                        {respond.busy && respond.arg?.invite.id === invite.id && !respond.arg.accept && <Spinner />}{t("web-pages.workspace.ignore")}
                      </DropdownMenu.Item>
                    </span>
                    {respond.error && respond.arg?.invite.id === invite.id && <p className={`${controlsCss.fieldError} ${css.menuInviteError}`} role="alert">{respond.arg.accept ? t("web-pages.cloud.joinFailed", { error: errorText(respond.error) }) : t("web-pages.workspace.ignoreFailed", { error: errorText(respond.error) })}</p>}
                  </div>
                ))}
                {!adder && <DropdownMenu.Separator className={controlsCss.menuSep} />}
              </>
            )}
            {/* Every workspace, the one in use among them, in an order of their own: switching often, each stays where the hand knows it. */}
            {/* Each says whose it is under its name when there are accounts to tell apart, and the key that switches to it at its end. */}
            {/* Its page goes back to the chat last open there (WorkspaceHome). */}
            {!adder && all.map(({ account, w }, i) => {
              const here = isCurrent(account.sub, w.id);
              return (
              <DropdownMenu.Item key={`${account.sub}/${w.id}`} className={controlsCss.menuItem} aria-current={here || undefined} onSelect={() => { if (!here) navigate(to(w.id)); }}>
                <span className={css.menuCheck}>{here && <Check {...ICON} size={14} />}</span>
                <span className={css.menuWorkspace}>
                  <span className={css.menuWorkspaceName}>
                    <WorkspaceBadge w={w} size={14} still={!here} />
                    <span className={css.menuWorkspaceText}>{w.name}</span>
                    {!here && <MarkCounts mark={marks?.workspaces[w.id]} />}
                  </span>
                  {byAccount.length > 1 && <span className={shellCss.muted}>{account.email}</span>}
                </span>
                {i < 9 && <span className={css.menuKey}>{workspaceKeyLabel(i)}</span>}
              </DropdownMenu.Item>
              );
            })}
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
      <NewWorkspaceDialog open={creating} onClose={() => setCreating(false)} />
    </>
  );
}

function NewWorkspaceDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [owner, setOwner] = useState(list[0]?.sub ?? "");
  // Sent every time: the server looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
  const [code, setCode] = useState(inviteCode);
  const create = useAction(() => cloud.createWorkspace(owner || list[0]!.sub, name, code.trim()), (w) => { track("workspace_created", { first: false }); setName(""); onClose(); navigate(`/w/${w.id}`); });
  const [asked, setAsked] = useState(false);
  useEffect(() => { if (needsInviteCode(create.error)) setAsked(true); }, [create.error]);
  const asking = asked || needsInviteCode(create.error);
  return (
    <Dialog open={open} onClose={onClose} title={t("web-pages.workspace.create")} description={t("web-pages.workspace.createLead")}
      footer={<><Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button><Button variant="primary" disabled={!name.trim()} busy={create.busy} onClick={() => create.run()}>{t("web-pages.workspace.createAction")}</Button></>}>
      <Field label={t("web-pages.settings.workspace.name")} htmlFor="ws-name">
        <input id="ws-name" className={controlsCss.input} value={name} autoFocus onChange={(e) => setName(e.target.value)} placeholder={t("web-pages.workspace.namePlaceholder")} maxLength={80}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim() && !create.busy) create.run(); }} />
      </Field>
      {list.length > 1 && (
        <Field label={t("web-pages.workspace.owner")} htmlFor="ws-owner">
          <Select id="ws-owner" value={owner} onChange={setOwner} options={list.map((a) => ({ value: a.sub, label: a.email }))} />
        </Field>
      )}
      {asking && (
        <Field label={t("web-pages.cloud.inviteCode")} htmlFor="ws-code" error={create.error && needsInviteCode(create.error) && code.trim() ? errorText(create.error) : undefined}
          hint={t("web-pages.workspace.codeHint", { name: NAME })}>
          <input id="ws-code" className={`${controlsCss.input} ${shellCss.mono}`} value={code} autoFocus onChange={(e) => setCode(e.target.value)} placeholder="XXXX-XXXX-XXXX" maxLength={32} spellCheck={false} autoComplete="off"
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim() && code.trim() && !create.busy) create.run(); }} />
        </Field>
      )}
      {create.error && !needsInviteCode(create.error) && <p className={controlsCss.fieldError} role="alert">{errorText(create.error)}</p>}
    </Dialog>
  );
}

