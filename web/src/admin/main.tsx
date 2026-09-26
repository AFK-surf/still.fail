// The admin's console as an app of its own, on its own host (admin.ember.3720.org).
// Its origin gives it its own client core and so its own signed-in accounts:
// signing in here signs in nowhere else. Sign-in goes through ember cloud like
// the web app's and comes back to this host's /auth/callback.
import { Tooltip } from "radix-ui";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Route, Routes } from "react-router";
import "@fontsource-variable/inter";
import { Illustration } from "../brand.tsx";
import { signIn, signOut, useAccounts } from "../cloud/accounts.ts";
import { Callback, SignInPage } from "../cloud/gate.tsx";
import { ToastProvider } from "../toast.tsx";
import { Button, Loading } from "../ui.tsx";
import { Console, useAdminAccount } from "./console.tsx";
import "../theme.css";
import "../app.css";

function AdminApp() {
  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400}>
        <BrowserRouter>
          <Routes>
            <Route path="/auth/callback" element={<Callback />} />
            <Route path="*" element={<Home />} />
          </Routes>
        </BrowserRouter>
      </Tooltip.Provider>
    </ToastProvider>
  );
}

function Home() {
  const list = useAccounts();
  const account = useAdminAccount();
  if (list?.length === 0) return <SignInPage title="ember 管理后台" lead="只有 ember 的管理员能用这里。用管理员的 Google 账号登录。" />;
  if (account === undefined) return <div className="gate"><Loading /></div>;
  if (account === null) return <NoPermission />;
  return <Console account={account} />;
}

/** Signed in, but with no account that is the admin's. */
function NoPermission() {
  const list = useAccounts() ?? [];
  return (
    <div className="gate">
      <Illustration name="sign-in" />
      <h1>没有权限</h1>
      <p>{list.map((a) => a.email).join("、")} 不是 ember 的管理员。</p>
      <Button variant="primary" onClick={() => void Promise.all(list.map((a) => signOut(a.sub)))}>退出登录</Button>
      <Button variant="ghost" onClick={() => void signIn()}>换一个账号</Button>
    </div>
  );
}

createRoot(document.getElementById("app")!).render(<StrictMode><AdminApp /></StrictMode>);
