// The admin's console (main.tsx): on the core, the accounts the sign-in page signed in taken into it first.
import { followAppearance } from "../theme.ts";
import { startScrollbars } from "../scrollbars.ts";
import { Tooltip } from "radix-ui";
import { StrictMode } from "preact/compat";
import { createRoot } from "preact/compat/client";
import { I18nRoot, t } from "../i18n.ts";
import { Illustration } from "../brand.tsx";
import { useAccounts, useSignOut } from "../cloud/accounts.ts";
import { signInHere, takeSignedIn } from "../pages/core.ts";
import { addWords, type Words } from "@stillfail/ui/i18n.ts";
import zhPages from "../../../client/i18n/catalog/zh/web-pages.json" with { type: "json" };
import enPages from "../../../client/i18n/catalog/en/web-pages.json" with { type: "json" };
import { ToastProvider } from "@stillfail/ui/toast.tsx";
import { Button, WaitLine } from "../ui.tsx";
import { Console, useAdminAccount } from "./console.tsx";
import * as shellCss from "../styles/shell.css.ts";
import { NAME } from "../channel.ts";

function AdminApp() {
  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400}>
        <Home />
      </Tooltip.Provider>
    </ToastProvider>
  );
}

function Home() {
  const list = useAccounts();
  const account = useAdminAccount();
  if (list?.length === 0) {
    location.replace(signInHere());
    return null;
  }
  if (account === undefined) return <div className={shellCss.gate}><WaitLine /></div>;
  if (account === null) return <NoPermission />;
  return <Console account={account} />;
}

/** Signed in, but with no account that is the admin's. */
function NoPermission() {
  const list = useAccounts() ?? [];
  const signOut = useSignOut();
  return (
    <div className={shellCss.gate}>
      <Illustration name="sign-in" />
      <h1>{t("web-pages.admin.noPermission.title")}</h1>
      <p>{t("web-pages.admin.noPermission.body", { emails: list.map((a) => a.email).join(t("web-pages.admin.noPermission.separator")), name: NAME })}</p>
      <Button variant="primary" busy={signOut.busy()} onClick={() => { for (const a of list) void signOut.signOut(a.sub); }}>{t("web-pages.admin.signOut")}</Button>
      <Button variant="ghost" onClick={() => location.assign(signInHere())}>{t("web-pages.admin.switchAccount")}</Button>
    </div>
  );
}

addWords({ zh: zhPages as Words, en: enPages as Words });

export async function show(root: HTMLElement): Promise<void> {
  followAppearance();
  startScrollbars();
  await takeSignedIn();
  // (in place of the splash index.html paints first)
  root.replaceChildren();
  createRoot(root).render(<StrictMode><I18nRoot><AdminApp /></I18nRoot></StrictMode>);
}
