import { Tooltip } from "radix-ui";
import { Navigate, Route, Routes, useLocation, useParams } from "react-router";
import { ApiError, useLiveUpdates, useOverview } from "./api.ts";
import { AccountPage, AccountsPage } from "./pages/Accounts.tsx";
import { ConnectPage } from "./pages/Connect.tsx";
import { ConnectsPage } from "./pages/Connects.tsx";
import { SessionPage } from "./pages/Session.tsx";
import { Sidebar } from "./Sidebar.tsx";
import { ToastProvider } from "./toast.tsx";
import { Loading } from "./ui.tsx";

/** On phones the sidebar is the home screen; any opened item takes the whole screen. */
function useDetailOpen(): boolean {
  const path = useLocation().pathname;
  return /^\/(sessions\/.+|connects\/.+|settings(\/.*)?$)/.test(path);
}

export function App() {
  const overview = useOverview();
  const detail = useDetailOpen();
  useLiveUpdates(overview.isSuccess);

  if (overview.isPending) return <div className="gate"><Loading label="正在连接 ember…" /></div>;
  if (overview.isError) {
    const denied = overview.error instanceof ApiError && overview.error.status === 403;
    return (
      <div className="gate">
        <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={40} height={40} />
        <h1>{denied ? "没有访问权限" : "连不上 ember"}</h1>
        <p>{overview.error.message}</p>
      </div>
    );
  }

  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400} skipDelayDuration={200}>
      <div className="shell" data-detail={detail}>
        <Sidebar />
        <main className="main">
          <Routes>
            <Route path="/" element={<Navigate to="/sessions" replace />} />
            <Route path="/sessions/:key?" element={<SessionPage />} />
            <Route path="/connects/:id" element={<ConnectPage />} />
            <Route path="/bots/:id" element={<LegacyBot />} />
            <Route path="/settings" element={<Navigate to="/settings/connects" replace />} />
            <Route path="/settings/connects" element={<ConnectsPage />} />
            <Route path="/settings/accounts" element={<AccountsPage />} />
            <Route path="/settings/accounts/:id" element={<AccountPage />} />
            <Route path="*" element={<Navigate to="/sessions" replace />} />
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
