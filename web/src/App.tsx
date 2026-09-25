import { NavLink, Navigate, Route, Routes } from "react-router";
import { ApiError, useLiveUpdates, useOverview, type Overview } from "./api.ts";
import { ToastProvider } from "./toast.tsx";
import { BotsPage } from "./pages/Bots.tsx";
import { ProfilesPage } from "./pages/Profiles.tsx";
import { SessionsPage } from "./pages/Sessions.tsx";

export function App() {
  const overview = useOverview();
  useLiveUpdates(overview.isSuccess);

  if (overview.isPending) return null;
  if (overview.isError) {
    const denied = overview.error instanceof ApiError && overview.error.status === 403;
    return (
      <div className="signin">
        <div className="signin-box">
          <img src="/admin/ember.svg" alt="" />
          <h1>{denied ? "没有访问权限" : "连不上 ember"}</h1>
          <p>{overview.error.message}</p>
        </div>
      </div>
    );
  }

  return (
    <ToastProvider>
      <div className="frame">
        <Rail viewer={overview.data.viewer} />
        <main className="page">
          <Routes>
            <Route path="/" element={<Navigate to="/sessions" replace />} />
            <Route path="/sessions/:key?" element={<SessionsPage />} />
            <Route path="/bots/:id?" element={<BotsPage />} />
            <Route path="/profiles/:id?" element={<ProfilesPage />} />
            <Route path="*" element={<Navigate to="/sessions" replace />} />
          </Routes>
        </main>
      </div>
    </ToastProvider>
  );
}

function Rail({ viewer }: { viewer: Overview["viewer"] }) {
  return (
    <nav className="rail" aria-label="主导航">
      <img className="rail-mark" src="/admin/ember.svg" alt="ember" />
      <NavLink className="rail-link" to="/sessions">会话</NavLink>
      <NavLink className="rail-link" to="/bots">Bot</NavLink>
      <NavLink className="rail-link" to="/profiles">账号</NavLink>
      <span className="rail-spacer" />
      <span className="rail-viewer" title={viewer.via === "access" ? `通过 Cloudflare Access 登录：${viewer.email}` : "在运行 ember 的机器上本地访问"}>
        {viewer.via === "access" ? viewer.email.split("@")[0] : "本机"}
      </span>
    </nav>
  );
}
