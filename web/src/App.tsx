import { Tooltip } from "radix-ui";
import { Navigate, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { NewChat } from "./NewChat.tsx";
import { useRememberChat } from "./lastChat.ts";
import { useOverview } from "./api.ts";
import { AccountPage, AccountsPage } from "./pages/Accounts.tsx";
import { ConnectPage } from "./pages/Connect.tsx";
import { ConnectsPage } from "./pages/Connects.tsx";
import { DevicePage } from "./pages/Device.tsx";
import { ChatPage } from "./pages/ChatPage.tsx";
import { Sidebar } from "./Sidebar.tsx";
import { ToastProvider } from "./toast.tsx";
import { Loading } from "./ui.tsx";
import { Mark } from "./brand.tsx";

/** On phones the sidebar is the home screen; any opened item takes the whole screen. */
function useDetailOpen(): boolean {
  const path = useLocation().pathname;
  return /^\/(new$|chats\/.+|connects\/.+|settings(\/.*)?$)/.test(path);
}

export function App() {
  useRememberChat("local", (p) => /^\/(new|chats\/.+)$/.test(p));
  const overview = useOverview("local");
  const detail = useDetailOpen();

  // Once read, the page stays up through a passing error; the core keeps retrying.
  if (!overview.value && overview.error) {
    const denied = overview.error.status === 403;
    return (
      <div className="gate">
        <Mark size={40} />
        <h1>{denied ? "没有访问权限" : "连不上 ember"}</h1>
        <p>{overview.error.message}</p>
      </div>
    );
  }
  if (!overview.value) return <div className="gate"><Loading label="正在连接 ember…" /></div>;

  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400} skipDelayDuration={200}>
      <div className="shell" data-detail={detail}>
        <Sidebar />
        <main className="main">
          <Routes>
            <Route path="/" element={<Navigate to="/chats" replace />} />
            <Route path="/chats/:chat?" element={<ChatPage />} />
            <Route path="/new" element={<LocalNewChat />} />
            <Route path="/connects/:id" element={<ConnectPage />} />
            <Route path="/bots/:id" element={<LegacyBot />} />
            <Route path="/settings" element={<Navigate to="/settings/connects" replace />} />
            <Route path="/settings/connects" element={<ConnectsPage />} />
            <Route path="/settings/device" element={<DevicePage />} />
            <Route path="/settings/accounts" element={<AccountsPage />} />
            <Route path="/settings/accounts/:id" element={<AccountPage />} />
            <Route path="*" element={<Navigate to="/chats" replace />} />
          </Routes>
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
  return <NewChat scope="local" onCreated={(_, thread) => navigate(`/chats/${thread}`)} />;
}
