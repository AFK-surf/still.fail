import { useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { NavLink, Navigate, Route, Routes } from "react-router";
import { api, ApiError, useLiveUpdates, useOverview } from "./api.ts";
import { ToastProvider } from "./toast.tsx";
import { BotsPage } from "./pages/Bots.tsx";
import { ProfilesPage } from "./pages/Profiles.tsx";
import { SessionsPage } from "./pages/Sessions.tsx";

export function App() {
  const overview = useOverview();
  const signedOut = overview.error instanceof ApiError && overview.error.status === 401;
  useLiveUpdates(overview.isSuccess);

  if (signedOut) return <SignIn />;
  if (overview.isPending) return null;
  if (overview.isError) return <div className="empty"><p>连不上 ember：{overview.error.message}</p></div>;

  return (
    <ToastProvider>
      <div className="frame">
        <Rail />
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

function Rail() {
  const client = useQueryClient();
  const signOut = async () => {
    await api.logout();
    await client.invalidateQueries();
  };
  return (
    <nav className="rail" aria-label="主导航">
      <img className="rail-mark" src="/admin/ember.svg" alt="ember" />
      <NavLink className="rail-link" to="/sessions">会话</NavLink>
      <NavLink className="rail-link" to="/bots">Bot</NavLink>
      <NavLink className="rail-link" to="/profiles">账号</NavLink>
      <span className="rail-spacer" />
      <button type="button" className="rail-link rail-button" onClick={() => void signOut()}>退出</button>
    </nav>
  );
}

function SignIn() {
  const client = useQueryClient();
  const [token, setToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setError(null);
    try {
      await api.login(token.trim());
      await client.invalidateQueries();
    } catch (e) {
      setError(e instanceof ApiError && e.status === 401 ? "token 不对。它在 ember 数据目录的 config.json 里，admin.token 字段。" : String(e));
    }
  };
  return (
    <div className="signin">
      <form className="signin-box" onSubmit={(e) => void submit(e)}>
        <img src="/admin/ember.svg" alt="" />
        <h1>登录 ember</h1>
        <p>输入管理 token。登录状态会保留 30 天。</p>
        <div className="field">
          <label htmlFor="token">管理 token</label>
          <input id="token" className="input" type="password" autoComplete="current-password" value={token}
            onChange={(e) => setToken(e.target.value)} autoFocus />
        </div>
        <button className="button button-primary" type="submit" disabled={!token.trim()}>登录</button>
        {error && <p className="error" role="alert">{error}</p>}
      </form>
    </div>
  );
}
