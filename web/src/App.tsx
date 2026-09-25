import { Navigate, Route, Routes, useLocation } from "react-router";
import { ApiError, useLiveUpdates, useOverview } from "./api.ts";
import { AccountPage, AccountsPage } from "./pages/Accounts.tsx";
import { BotPage } from "./pages/Bot.tsx";
import { SessionPage } from "./pages/Session.tsx";
import { Sidebar } from "./Sidebar.tsx";
import { ToastProvider } from "./toast.tsx";

/** On phones the sidebar is the home screen; any opened item takes the whole screen. */
function useDetailOpen(): boolean {
  const path = useLocation().pathname;
  return /^\/(sessions\/.+|bots\/.+|settings(\/.*)?$)/.test(path);
}

export function App() {
  const overview = useOverview();
  const detail = useDetailOpen();
  useLiveUpdates(overview.isSuccess);

  if (overview.isPending) return null;
  if (overview.isError) {
    const denied = overview.error instanceof ApiError && overview.error.status === 403;
    return (
      <div className="gate">
        <img src="/admin/ember.svg" alt="" width={40} height={40} />
        <h1>{denied ? "没有访问权限" : "连不上 ember"}</h1>
        <p>{overview.error.message}</p>
      </div>
    );
  }

  return (
    <ToastProvider>
      <div className="shell" data-detail={detail}>
        <Sidebar />
        <main className="main">
          <Routes>
            <Route path="/" element={<Navigate to="/sessions" replace />} />
            <Route path="/sessions/:key?" element={<SessionPage />} />
            <Route path="/bots/:id" element={<BotPage />} />
            <Route path="/settings" element={<Navigate to="/settings/accounts" replace />} />
            <Route path="/settings/accounts" element={<AccountsPage />} />
            <Route path="/settings/accounts/:id" element={<AccountPage />} />
            <Route path="*" element={<Navigate to="/sessions" replace />} />
          </Routes>
        </main>
      </div>
    </ToastProvider>
  );
}
