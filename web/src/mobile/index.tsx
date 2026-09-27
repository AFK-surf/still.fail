// A workspace on a narrow screen: the Android app's pages (./app.tsx), at the desktop's addresses where it has them, so
// a link opens the same thing on either.
import { useMemo } from "react";
import { Navigate, Route, Routes, useParams, type Location } from "react-router";
import { useStations } from "../api.ts";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { MobileShell, type Entry } from "./app.tsx";
import { ChatScreen } from "./Chat.tsx";
import { ConnectRunScreen, ConnectScreen, NewConnectScreen } from "./Connects.tsx";
import { RunSettingsScreen } from "./History.tsx";
import { Home } from "./Home.tsx";
import { MeScreen } from "./Me.tsx";
import { NewChatScreen } from "./NewChat.tsx";
import { PreviewScreen } from "./Preview.tsx";
import { Loading } from "./parts.tsx";
import { StationScreen, StationsScreen } from "./Stations.tsx";
import { NewProfileScreen, ProfileScreen } from "./Profiles.tsx";
import { WorkspaceScreen } from "./WorkspacePage.tsx";

export function MobileWorkspace({ entry }: { entry: Entry }) {
  const found = useStations(entry.id);
  const stations = useMemo<Station[] | undefined>(() => found.value?.map((s) => ({
    id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${entry.id}/settings`,
  })), [found.value, entry.id]);
  const routes = (location: Location) => (
    <Routes location={location}>
      <Route index element={<Home />} />
      <Route path="new" element={<NewChatScreen />} />
      <Route path="settings/stations" element={<StationsScreen />} />
      <Route path="settings/account" element={<MeScreen />} />
      {/* The desktop's 通用, 成员 and 退出与删除 are one page here. */}
      <Route path="settings/general" element={<WorkspaceScreen />} />
      <Route path="settings/members" element={<WorkspaceScreen />} />
      <Route path="settings/leave" element={<WorkspaceScreen />} />
      <Route path="s/:station/chats/:chat" element={<InStation stations={stations}><ChatScreen /></InStation>} />
      <Route path="s/:station/chats/:chat/run/:agent" element={<InStation stations={stations}><RunSettingsScreen /></InStation>} />
      <Route path="s/:station/chats/:chat/preview/:port" element={<InStation stations={stations}><PreviewScreen /></InStation>} />
      <Route path="s/:station/overview" element={<InStation stations={stations}><StationScreen /></InStation>} />
      <Route path="s/:station/connects/new" element={<InStation stations={stations}><NewConnectScreen /></InStation>} />
      <Route path="s/:station/connects/:id" element={<InStation stations={stations}><ConnectScreen /></InStation>} />
      <Route path="s/:station/connects/:id/run" element={<InStation stations={stations}><ConnectRunScreen /></InStation>} />
      <Route path="s/:station/settings/accounts/:id" element={<InStation stations={stations}><ProfileScreen /></InStation>} />
      <Route path="s/:station/profiles/new" element={<InStation stations={stations}><NewProfileScreen /></InStation>} />
      {/* What the narrow app has no page for (the desktop's settings, a station's bare address) is the list. */}
      <Route path="*" element={<Navigate to={`/w/${entry.id}`} replace />} />
    </Routes>
  );
  return <MobileShell entry={entry} routes={routes} />;
}

/** A station's page: its station in context, once the workspace's stations are known. */
function InStation({ stations, children }: { stations: Station[] | undefined; children: React.ReactNode }) {
  const { station: id } = useParams();
  if (!stations) return <Loading text="正在读取…" />;
  const station = stations.find((s) => s.id === id);
  if (!station) return <Loading text="这个 workspace 里没有这台 station。" />;
  return <StationContext.Provider value={station}>{children}</StationContext.Provider>;
}
