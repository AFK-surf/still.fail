// Whether this client tells its person about their chats (notify.ts, docs/notifications.md).
import { useState } from "react";
import { setNotify, useNotifyState } from "../notify.ts";
import { MobileBack, SwitchRow } from "../ui.tsx";
import { failure, useToast } from "../toast.tsx";
import * as pagesCss from "../styles/pages.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
export function NotificationsPage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.settings.nav.notifications")}</h1></div></header>
      <NotifySwitch />
    </div>
  );
}

export function NotifySwitch() {
  const state = useNotifyState();
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const desktop = !!window.stillfailDesktop;
  const note = state === "unsupported" ? t("web-pages.notifications.unsupported")
    : state === "denied" ? t("web-pages.notifications.denied")
    : desktop ? t("web-pages.notifications.noteDevice", { name: NAME }) : t("web-pages.notifications.noteBrowser");
  return (
    <SwitchRow title={t("web-pages.notifications.title")} description={note} checked={state === "on"} busy={busy} disabled={state === "denied" || state === "unsupported"}
      onChange={(on) => {
        setBusy(true);
        setNotify(on).then((now) => { if (on && now !== "on") toast(t("web-pages.notifications.notAllowed")); }, (e: unknown) => toast(on ? t("web-pages.notifications.onFailed", { error: failure(e) }) : t("web-pages.notifications.offFailed", { error: failure(e) })))
          .finally(() => setBusy(false));
      }} />
  );
}
