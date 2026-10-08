// Whether this client tells its person about their chats (notify.ts, docs/notifications.md).
import { useEffect, useState } from "react";
import type { DockSettings } from "../core/client.ts";
import type { NotifyKinds, NotifyView } from "../core/shapes.ts";
import { core, useTopic } from "../core/react.ts";
import { CAN_NOTIFY, setNotify, useNotifyState } from "../notify.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { Choices, MobileBack, Section, Segmented, SwitchRow } from "../ui.tsx";
import { failure, useToast } from "../toast.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Notifications.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
export function NotificationsPage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.settings.nav.notifications")}</h1></div></header>
      <div className={css.lead}><NotifySwitch /></div>
      {CAN_NOTIFY && <NotifyKindsSection />}
      <BadgeSection />
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

const KINDS: NotifyKinds = { wait: true, failed: true, done: "away", message: true };

/** Which notices this device tells (the core's `notify` `kinds`, `notify.set`): each kind on or off, a turn done also
 * only while the app is not in front. With notifications off, there is nothing to choose. */
function NotifyKindsSection() {
  const state = useNotifyState();
  const view = useTopic<NotifyView>({ topic: "notify" }).value;
  const [kinds, setKinds] = useState<NotifyKinds | null>(null);
  const toast = useToast();
  useEffect(() => { if (view?.kinds) setKinds(view.kinds); }, [view?.kinds?.wait, view?.kinds?.failed, view?.kinds?.done, view?.kinds?.message]);
  const now = kinds ?? view?.kinds ?? KINDS;
  const off = state !== "on";
  const change = (patch: Partial<NotifyKinds>) => {
    setKinds({ ...now, ...patch });
    core().call("notify.set", { kinds: patch }).catch((e: unknown) => { setKinds(null); toast(t("web-pages.notifications.kindsFailed", { error: failure(e) })); });
  };
  const sound = !!window.stillfailDesktop && /Mac/.test(navigator.platform);
  return (
    <Section title={t("web-pages.notifications.kinds.title")} description={off ? t("web-pages.notifications.kinds.off") : t("web-pages.notifications.kinds.note")}>
      <div className={css.rows}>
      <SwitchRow title={t("web-pages.notifications.kinds.wait")} description={t("web-pages.notifications.kinds.waitNote")} checked={now.wait !== false} disabled={off} onChange={(wait) => change({ wait })} />
      <SwitchRow title={t("web-pages.notifications.kinds.failed")} description={t("web-pages.notifications.kinds.failedNote")} checked={now.failed !== false} disabled={off} onChange={(failed) => change({ failed })} />
      <div className={css.row}>
        <span className={css.rowText}><span>{t("web-pages.notifications.kinds.done")}</span><span className={shellCss.muted}>{t("web-pages.notifications.kinds.doneNote")}</span></span>
        <Segmented className={css.doneChoice} label={t("web-pages.notifications.kinds.done")} value={(now.done || "away") as "off" | "away" | "always"} onChange={(done) => change({ done })}
          options={[
            { value: "off", label: t("web-pages.notifications.kinds.doneOff"), disabled: off },
            { value: "away", label: t("web-pages.notifications.kinds.doneAway"), disabled: off },
            { value: "always", label: t("web-pages.notifications.kinds.doneAlways"), disabled: off },
          ]} />
      </div>
      <SwitchRow title={t("web-pages.notifications.kinds.message")} description={t("web-pages.notifications.kinds.messageNote")} checked={now.message !== false} disabled={off} onChange={(message) => change({ message })} />
      {sound && <p className={css.hint}>{t("web-pages.notifications.sound", { name: NAME })}</p>}
      </div>
    </Section>
  );
}

/** What the badge counts (the prefs' `badge`; the Dock's, and the sidebar's 需要你). */
function BadgeSection() {
  const badge = usePrefs().badge ?? "attention";
  return (
    <Section title={t("web-pages.notifications.badge.title")} description={t("web-pages.notifications.badge.note")}>
      <Choices label={t("web-pages.notifications.badge.title")} value={badge as "decisions" | "attention" | "all"} onChange={(v) => setPrefs({ badge: v === "attention" ? null : v })}
        options={[
          { value: "decisions", title: t("web-pages.notifications.badge.decisions"), description: t("web-pages.notifications.badge.decisionsNote") },
          { value: "attention", title: t("web-pages.notifications.badge.attention"), description: t("web-pages.notifications.badge.attentionNote") },
          { value: "all", title: t("web-pages.notifications.badge.all"), description: t("web-pages.notifications.badge.allNote") },
        ]} />
    </Section>
  );
}
