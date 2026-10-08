// Whether this client tells its person about their chats (notify.ts, docs/notifications.md).
import { useEffect, useState } from "react";
import type { DockSettings } from "../core/client.ts";
import { setNotify, useNotifyState } from "../notify.ts";
import { MobileBack, Section, SwitchRow } from "../ui.tsx";
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
      <DockSwitches />
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

/** The desktop dock's settings (apps/desktop/src/dock.mts): only in a Mac app that can run it. */
function DockSwitches() {
  const bridge = window.stillfailDesktop?.dock;
  const [settings, setSettings] = useState<DockSettings | null>(null);
  const [busy, setBusy] = useState<keyof DockSettings | null>(null);
  const toast = useToast();
  useEffect(() => { void bridge?.get().then(setSettings, () => setSettings(null)); }, [bridge]);
  if (!bridge || !settings) return null;
  const change = (key: keyof DockSettings, on: boolean) => {
    setBusy(key);
    bridge.set({ [key]: on }).then((now) => { if (now) setSettings(now); }, (e: unknown) => toast(t("web-pages.dock.failed", { error: failure(e) })))
      .finally(() => setBusy(null));
  };
  return (
    <Section title={t("web-pages.dock.title")} description={t("web-pages.dock.note")}>
      <SwitchRow title={t("web-pages.dock.title")} checked={settings.on} busy={busy === "on"} onChange={(on) => change("on", on)} />
      <SwitchRow title={t("web-pages.dock.peek")} description={t("web-pages.dock.peekNote")} checked={settings.peek} busy={busy === "peek"} disabled={!settings.on} onChange={(on) => change("peek", on)} />
      <SwitchRow title={t("web-pages.dock.unread")} description={t("web-pages.dock.unreadNote")} checked={settings.unread} busy={busy === "unread"} disabled={!settings.on} onChange={(on) => change("unread", on)} />
    </Section>
  );
}
