import { ArchivingScreen, StationArchivingScreen } from "./Archiving.tsx";
import { AutomaticDecisionCompletionScreen, AutomaticDecisionPolicyScreen, AutomaticDecisionsScreen } from "./AutomaticDecisions.tsx";
// A workspace on a narrow screen: the Android app's pages (./app.tsx), at the desktop's addresses where it has them, so
// a link opens the same thing on either.
import { useCallback, useEffect } from "react";
import { Navigate, Route, Routes, useParams, type Location } from "react-router";
import { useStations } from "../api.ts";
import { StationContext, useStationList, type Station } from "../station.tsx";
import { MobileShell, useApp, type Entry } from "./app.tsx";
import { ArchiveScreen } from "./Archive.tsx";
import { ChatHost } from "./ChatHost.tsx";
import { ConnectRunScreen, ConnectScreen, ConnectsScreen, NewConnectScreen } from "./Connects.tsx";
import { HistoryScreen, RunSettingsScreen } from "./History.tsx";
import { Home, Recent, WaitingHome } from "./Home.tsx";
import { MeScreen } from "./Me.tsx";
import { MemoriesScreen, MemoryDocScreen, MemoryScreen } from "./Memory.tsx";
import { DrivePlayScreen, DriveReadScreen, DriveScreen } from "./Drive.tsx";
import { FilesScreen } from "./Files.tsx";
import { BarSettingsScreen } from "./BarSettings.tsx";
import { UsageScreen, UsagePricesScreen } from "./Usage.tsx";
import { PreviewScreen } from "./Preview.tsx";
import { ScreenScreen } from "./Screen.tsx";
import { Gone, NavBar } from "./parts.tsx";
import { Waiting } from "@stillfail/ui/waiting.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import { StationScreen, StationsScreen } from "./Stations.tsx";
import { NewProfileScreen, PickModelsScreen, ProfileAccountScreen, ProfileModelsScreen, ProfileScreen, ProfilesScreen } from "./Profiles.tsx";
import { AboutScreen, AppearanceScreen, LanguageScreen, SettingsScreen } from "./Settings.tsx";
import { FontScreen } from "./Fonts.tsx";
import { ChangelogScreen } from "./Changelog.tsx";
import { WorkspaceScreen } from "./WorkspacePage.tsx";
import { SecurityOpenScreen, SecurityPrompt, SecurityScreen } from "./Security.tsx";
import { ShareInSheet } from "./ShareIn.tsx";
import { useLock } from "../cloud/Security.tsx";
import { VaultAllScreen, VaultItemScreen, VaultScreen } from "./Vault.tsx";
import { identify } from "../telemetry.ts";
import { t } from "../i18n.ts";

export function MobileWorkspace({ entry }: { entry: Entry }) {
  // Who is using the page, as the wide screen's shell says it (cloud/workspace.tsx): a phone's events were anonymous.
  useEffect(() => identify(entry.account), [entry.account]);
  const found = useStations(entry.id);
  const stations = useStationList(found.value, entry.id);
  // The same while the stations are: a page is drawn again when what it is given changes, not whenever this is.
  const routes = useCallback((location: Location) => (
    <LockGate workspace={entry.id} path={location.pathname}>
    <Routes location={location}>
      <Route index element={<Home />} />
      {/* A new chat and a chat are one page (ChatHost.tsx): as one becomes the other, its composer stays. */}
      <Route path="new" element={<ChatHost stations={stations} />} />
      <Route path="archive" element={<ArchiveScreen />} />
      {/* 文件 as a place (the bottom bar's): every station's folders in one list. */}
      <Route path="files" element={<FilesScreen />} />
      {/* Settings: one page from the gear on Home, and a page for each of its rows, at the desktop's addresses. */}
      <Route path="settings" element={<SettingsScreen />} />
      <Route path="settings/account" element={<MeScreen />} />
      <Route path="settings/appearance" element={<AppearanceScreen />} />
      <Route path="settings/appearance/fonts" element={<FontScreen />} />
      <Route path="settings/bar" element={<BarSettingsScreen />} />
      <Route path="settings/language" element={<LanguageScreen />} />
      <Route path="settings/changelog" element={<ChangelogScreen />} />
      <Route path="settings/about" element={<AboutScreen />} />
      <Route path="settings/workspace" element={<WorkspaceScreen />} />
      <Route path="settings/security" element={<SecurityScreen />} />
      <Route path="settings/security/open" element={<SecurityOpenScreen />} />
      <Route path="settings/vault" element={<VaultScreen />} />
      <Route path="settings/vault/all" element={<VaultAllScreen />} />
      <Route path="settings/vault/:vault/:item" element={<VaultItemScreen />} />
      <Route path="settings/stations" element={<StationsScreen />} />
      <Route path="settings/connects" element={<ConnectsScreen />} />
      <Route path="settings/archive" element={<ArchivingScreen />} />
      <Route path="settings/archive/:station" element={<StationArchivingScreen />} />
      <Route path="settings/automatic-decisions" element={<AutomaticDecisionsScreen />} />
      <Route path="settings/automatic-decisions/completion" element={<AutomaticDecisionCompletionScreen />} />
      <Route path="settings/automatic-decisions/completion/:station" element={<AutomaticDecisionPolicyScreen />} />
      <Route path="settings/profiles" element={<ProfilesScreen />} />
      <Route path="settings/profiles/account/:key" element={<ProfileAccountScreen />} />
      <Route path="settings/memory" element={<MemoriesScreen />} />
      <Route path="settings/usage/prices" element={<UsagePricesScreen />} />
      <Route path="settings/usage" element={<UsageScreen />} />
      {/* The workspace's page at the addresses it had before (links sent keep working). */}
      <Route path="settings/general" element={<WorkspaceScreen />} />
      <Route path="settings/members" element={<WorkspaceScreen />} />
      <Route path="settings/leave" element={<WorkspaceScreen />} />
      <Route path="s/:station/chats/:chat" element={<ChatHost stations={stations} />} />
      <Route path="s/:station/chats/:chat/history/:agent" element={<InStation stations={stations}><HistoryScreen /></InStation>} />
      <Route path="s/:station/chats/:chat/run/:agent" element={<InStation stations={stations}><RunSettingsScreen /></InStation>} />
      <Route path="s/:station/chats/:chat/services/:service" element={<InStation stations={stations}><PreviewScreen /></InStation>} />
      <Route path="s/:station/overview" element={<InStation stations={stations}><StationScreen /></InStation>} />
      {/* A login's link, as its agent posts it (docs/remote-login.md): the station's page, the login's sheet over it. */}
      <Route path="s/:station/login/:login" element={<InStation stations={stations}><StationScreen /></InStation>} />
      <Route path="s/:station/memory" element={<InStation stations={stations}><MemoryScreen /></InStation>} />
      <Route path="s/:station/memory/global" element={<InStation stations={stations}><MemoryDocScreen /></InStation>} />
      <Route path="s/:station/memory/skill/:name" element={<InStation stations={stations}><MemoryDocScreen /></InStation>} />
      {/* A station's drive: its folders, each folder a page (?root=&path=), a file read or played on a page of its own. */}
      <Route path="s/:station/files" element={<InStation stations={stations}><DriveScreen /></InStation>} />
      <Route path="s/:station/files/read" element={<InStation stations={stations}><DriveReadScreen /></InStation>} />
      <Route path="s/:station/files/play" element={<InStation stations={stations}><DrivePlayScreen /></InStation>} />
      {/* One of its screens, seen and driven by a finger (docs/remote-screens.md). */}
      <Route path="s/:station/screen/:id" element={<InStation stations={stations}><ScreenScreen /></InStation>} />
      <Route path="s/:station/connects/new" element={<InStation stations={stations}><NewConnectScreen /></InStation>} />
      <Route path="s/:station/connects/:id" element={<InStation stations={stations}><ConnectScreen /></InStation>} />
      <Route path="s/:station/connects/:id/run" element={<InStation stations={stations}><ConnectRunScreen /></InStation>} />
      <Route path="s/:station/settings/accounts/:id" element={<InStation stations={stations}><ProfileScreen /></InStation>} />
      <Route path="s/:station/settings/accounts/:id/models" element={<InStation stations={stations}><PickModelsScreen /></InStation>} />
      <Route path="s/:station/settings/accounts/:id/models/edit" element={<InStation stations={stations}><ProfileModelsScreen /></InStation>} />
      <Route path="s/:station/profiles/new" element={<InStation stations={stations}><NewProfileScreen /></InStation>} />
      {/* What the narrow app has no page for (the desktop's settings, a station's bare address) is the list. */}
      <Route path="*" element={<Navigate to={`/w/${entry.id}`} replace />} />
    </Routes>
    </LockGate>
  ), [stations, entry.id]);
  return <MobileShell entry={entry} routes={routes} recent={() => <Recent />} over={<><SecurityPrompt /><ShareInSheet /></>} />;
}

/** A device waiting to be confirmed into the workspace's lock sees that instead of its pages (but the settings). */
function LockGate({ workspace, path, children }: { workspace: string; path: string; children: React.ReactNode }) {
  const lock = useLock(workspace);
  if (lock?.me?.waiting && !/\/settings(\/|$)/.test(path)) return <WaitingHome lock={lock} />;
  return <>{children}</>;
}

/** A station's page: its station in context, once the workspace's stations are known. */
function InStation({ stations, children }: { stations: Station[] | undefined; children: React.ReactNode }) {
  const { station: id } = useParams();
  const app = useApp();
  // Which page it is is not known before its station is: a bare bar, back, over what it waits on (no page's bones: which
  // page's they would be is not known either).
  const bare = (body: React.ReactNode) => <div className={pagesCss.mScreen}><NavBar back={t("common.back")} onBack={app.pop} title="" />{body}</div>;
  if (!stations) return bare(<Waiting fill text={t("common.readingStations")} sample={null} />);
  const station = stations.find((s) => s.id === id);
  if (!station) return bare(<Gone text={t("web-mobile.noStation")} />);
  return <StationContext.Provider value={station}>{children}</StationContext.Provider>;
}
