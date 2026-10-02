// The admin's console as an app of its own, on its own host (admin.still.fail).
// Its origin gives it its own client core and so its own signed-in accounts:
// signing in here signs in nowhere else. Sign-in goes through still.fail cloud like
// the web app's and comes back to this host's /auth/callback.
import "../renamed.ts";
import "../styles/index.ts";
import { followAppearance } from "../theme.ts";
import { startScrollbars } from "../scrollbars.ts";
import { Tooltip } from "radix-ui";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { I18nRoot, t } from "../i18n.ts";
import { BrowserRouter, Route, Routes } from "react-router";
import "@fontsource-variable/inter";
import { Illustration } from "../brand.tsx";
import { useAccounts, useSignIn, useSignOut } from "../cloud/accounts.ts";
import { Callback, SignInPage } from "../cloud/gate.tsx";
import { ToastProvider } from "../toast.tsx";
import { Button, Loading } from "../ui.tsx";
import { Console, useAdminAccount } from "./console.tsx";
import * as shellCss from "../styles/shell.css.ts";

import { NAME } from "../channel.ts";
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
  if (list?.length === 0) return <SignInPage title={t("web-pages.admin.signIn.title", { name: NAME })} lead={t("web-pages.admin.signIn.lead", { name: NAME })} />;
  if (account === undefined) return <div className={shellCss.gate}><Loading /></div>;
  if (account === null) return <NoPermission />;
  return <Console account={account} />;
}

/** Signed in, but with no account that is the admin's. */
function NoPermission() {
  const list = useAccounts() ?? [];
  const signIn = useSignIn();
  const signOut = useSignOut();
  return (
    <div className={shellCss.gate}>
      <Illustration name="sign-in" />
      <h1>{t("web-pages.admin.noPermission.title")}</h1>
      <p>{t("web-pages.admin.noPermission.body", { emails: list.map((a) => a.email).join(t("web-pages.admin.noPermission.separator")), name: NAME })}</p>
      <Button variant="primary" busy={signOut.busy()} onClick={() => { for (const a of list) void signOut.signOut(a.sub); }}>{t("web-pages.admin.signOut")}</Button>
      <Button variant="ghost" busy={signIn.busy} onClick={() => void signIn.signIn()}>{t("web-pages.admin.switchAccount")}</Button>
    </div>
  );
}

followAppearance();
startScrollbars();
createRoot(document.getElementById("app")!).render(<StrictMode><I18nRoot><AdminApp /></I18nRoot></StrictMode>);
