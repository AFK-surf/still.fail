// A workspace on a narrow screen: the Android app's pages (./app.tsx), at the desktop's addresses where it has them, so
// a link opens the same thing on either.
import { useMemo } from "react";
import { Navigate, Route, Routes, useParams, type Location } from "react-router";
import { useStations } from "../api.ts";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { MobileShell, type Entry } from "./app.tsx";
import { AnnotateScreen } from "./Annotate.tsx";
import { ArchiveScreen } from "./Archive.tsx";
import { ChatHost } from "./ChatHost.tsx";
import { ConnectRunScreen, ConnectScreen, ConnectsScreen, NewConnectScreen } from "./Connects.tsx";
import { RunSettingsScreen } from "./History.tsx";
import { Home, Recent } from "./Home.tsx";
import { MeScreen } from "./Me.tsx";
import { MemoriesScreen, MemoryScreen } from "./Memory.tsx";
import { UsageScreen } from "./Usage.tsx";
import { PreviewScreen } from "./Preview.tsx";
import { Loading } from "./parts.tsx";
import { StationScreen, StationsScreen } from "./Stations.tsx";
import { NewProfileScreen, ProfileScreen, ProfilesScreen } from "./Profiles.tsx";
import { AppearanceScreen, SettingsScreen } from "./Settings.tsx";
import { ChangelogScreen } from "./Changelog.tsx";
import { WorkspaceScreen } from "./WorkspacePage.tsx";

export function MobileWorkspace({ entry }: { entry: Entry }) {
  const found = useStations(entry.id);
  const stations = useMemo<Station[] | undefined>(() => found.value?.map((s) => ({
    id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${entry.id}/settings`,
  })), [found.value, entry.id]);
  const routes = (location: Location) => (
    <Routes location={location}>
      <Route index element={<Home />} />
      {/* A new chat and a chat are one page (ChatHost.tsx): as one becomes the other, its composer stays. */}
      <Route path="new" element={<ChatHost stations={stations} />} />
      <Route path="archive" element={<ArchiveScreen />} />
      {/* Settings: one page from the gear on Home, and a page for each of its rows, at the desktop's addresses. */}
      <Route path="settings" element={<SettingsScreen />} />
      <Route path="settings/account" element={<MeScreen />} />
      <Route path="settings/appearance" element={<AppearanceScreen />} />
      <Route path="settings/changelog" element={<ChangelogScreen />} />
      <Route path="settings/workspace" element={<WorkspaceScreen />} />
      <Route path="settings/stations" element={<StationsScreen />} />
      <Route path="settings/connects" element={<ConnectsScreen />} />
      <Route path="settings/profiles" element={<ProfilesScreen />} />
      <Route path="settings/memory" element={<MemoriesScreen />} />
      <Route path="settings/usage" element={<UsageScreen />} />
      {/* The workspace's page at the addresses it had before (links sent keep working). */}
      <Route path="settings/general" element={<WorkspaceScreen />} />
      <Route path="settings/members" element={<WorkspaceScreen />} />
      <Route path="settings/leave" element={<WorkspaceScreen />} />
      <Route path="s/:station/chats/:chat" element={<ChatHost stations={stations} />} />
      <Route path="s/:station/chats/:chat/run/:agent" element={<InStation stations={stations}><RunSettingsScreen /></InStation>} />
      <Route path="s/:station/chats/:chat/messages/:ts" element={<InStation stations={stations}><AnnotateScreen /></InStation>} />
      <Route path="s/:station/chats/:chat/services/:service" element={<InStation stations={stations}><PreviewScreen /></InStation>} />
      <Route path="s/:station/overview" element={<InStation stations={stations}><StationScreen /></InStation>} />
      <Route path="s/:station/memory" element={<InStation stations={stations}><MemoryScreen /></InStation>} />
      <Route path="s/:station/connects/new" element={<InStation stations={stations}><NewConnectScreen /></InStation>} />
      <Route path="s/:station/connects/:id" element={<InStation stations={stations}><ConnectScreen /></InStation>} />
      <Route path="s/:station/connects/:id/run" element={<InStation stations={stations}><ConnectRunScreen /></InStation>} />
      <Route path="s/:station/settings/accounts/:id" element={<InStation stations={stations}><ProfileScreen /></InStation>} />
      <Route path="s/:station/profiles/new" element={<InStation stations={stations}><NewProfileScreen /></InStation>} />
      {/* What the narrow app has no page for (the desktop's settings, a station's bare address) is the list. */}
      <Route path="*" element={<Navigate to={`/w/${entry.id}`} replace />} />
    </Routes>
  );
  return <MobileShell entry={entry} routes={routes} recent={() => <Recent />} />;
}

/** A station's page: its station in context, once the workspace's stations are known. */
function InStation({ stations, children }: { stations: Station[] | undefined; children: React.ReactNode }) {
  const { station: id } = useParams();
  if (!stations) return <Loading text="正在读取…" />;
  const station = stations.find((s) => s.id === id);
  if (!station) return <Loading text="这个 workspace 里没有这台 station。" />;
  return <StationContext.Provider value={station}>{children}</StationContext.Provider>;
}
