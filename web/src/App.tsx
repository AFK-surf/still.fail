import { Tooltip } from "radix-ui";
import { Navigate, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { NewChat } from "./NewChat.tsx";
import { useRememberChat } from "./lastChat.ts";
import { useOverview } from "./api.ts";
import { AccountPage, AccountsPage } from "./pages/Accounts.tsx";
import { ConnectPage } from "./pages/Connect.tsx";
import { ConnectsPage } from "./pages/Connects.tsx";
import { DevicePage } from "./pages/Device.tsx";
import { AppearancePage } from "./pages/Appearance.tsx";
import { MemoryPage } from "./Memory.tsx";
import { ArchivePage } from "./pages/Archive.tsx";
import { ChatPage } from "./pages/ChatPage.tsx";
import { Sidebar } from "./Sidebar.tsx";
import { ToastProvider } from "./toast.tsx";
import { Loading } from "./ui.tsx";
import { toMadeChat } from "./Chat.tsx";
import { ComposerDock } from "./dock.tsx";
import { Mark } from "./brand.tsx";
import { ServicePage } from "./Preview.tsx";
import * as shellCss from "./styles/shell.css.ts";

/** On phones the sidebar is the home screen; any opened item takes the whole screen. */
function useDetailOpen(): boolean {
  const path = useLocation().pathname;
  return /^\/(new$|archive$|chats\/.+|connects\/.+|settings(\/.*)?$)/.test(path);
}

export function App() {
  useRememberChat("local", (p) => /^\/(new|chats\/.+)$/.test(p));
  const overview = useOverview("local");
  const detail = useDetailOpen();
  // A web service on a page of its own: the whole window, no sidebar.
  const service = /^\/services\/([^/]+)$/.exec(useLocation().pathname)?.[1];
  if (service) return <ServicePage station="local" service={decodeURIComponent(service)} />;

  // Once read, the page stays up through a passing error; the core keeps retrying.
  if (!overview.value && overview.error) {
    const denied = overview.error.status === 403;
    return (
      <div className={shellCss.gate}>
        <Mark size={40} />
        <h1>{denied ? "没有访问权限" : "连不上 ember"}</h1>
        <p>{overview.error.message}</p>
      </div>
    );
  }
  if (!overview.value) return <div className={shellCss.gate}><Loading label="正在连接 ember…" /></div>;

  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400} skipDelayDuration={200}>
      <div className={shellCss.shell} data-detail={detail}>
        <Sidebar />
        <main className={shellCss.main}>
          <ComposerDock>
          <Routes>
            <Route path="/" element={<Navigate to="/chats" replace />} />
            <Route path="/chats/:chat?" element={<ChatPage />} />
            <Route path="/new" element={<LocalNewChat />} />
            <Route path="/archive" element={<ArchivePage scope="local" back="/chats" />} />
            <Route path="/connects/:id" element={<ConnectPage />} />
            <Route path="/bots/:id" element={<LegacyBot />} />
            <Route path="/settings" element={<Navigate to="/settings/connects" replace />} />
            <Route path="/settings/connects" element={<ConnectsPage />} />
            <Route path="/settings/device" element={<DevicePage />} />
            <Route path="/settings/appearance" element={<AppearancePage back="/settings" />} />
            <Route path="/settings/memory" element={<MemoryPage />} />
            <Route path="/settings/accounts" element={<AccountsPage />} />
            <Route path="/settings/accounts/:id" element={<AccountPage />} />
            <Route path="*" element={<Navigate to="/chats" replace />} />
          </Routes>
          </ComposerDock>
        </main>
      </div>
      </Tooltip.Provider>
    </ToastProvider>
  );
}

/** Links from before bots became connects. */
function LegacyBot() {
  return <Navigate to={`/connects/${useParams().id}`} replace />;
}

/** A new chat on this station. */
function LocalNewChat() {
  const navigate = useNavigate();
  return <NewChat scope="local" onCreated={(_, session) => toMadeChat(() => navigate(`/chats/${encodeURIComponent(session)}`))} />;
}
