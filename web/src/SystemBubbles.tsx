// What the app itself has to say (no one's chat or station: those are the rail's bell, Attention.tsx), as bubbles
// rising at the page's bottom left by the rail, over whatever is there, the sidebar open or closed: the desktop app's
// newer build (to install), the page's newer build (to load), what the update just installed brought (the changelog).
// Each says it in a line, with what can be done and a way to put it away.
import { useState, useSyncExternalStore, type ReactNode } from "react";
import { Link } from "react-router";
import { webUpdates } from "./core/webUpdates.ts";
import { useAppUpdate } from "./brand.tsx";
import { useChangelog, useChangelogSeen } from "./changelog.ts";
import { Close, Download, Refresh, Sparks } from "./icons.tsx";
import { NAME } from "./channel.ts";
import * as css from "./SystemBubbles.css.ts";
import { t } from "./i18n.ts";

export function SystemBubbles({ scope }: { scope: string }) {
  return (
    <div className={css.stack} role="region" aria-label={t("web-main.system.label")}>
      <ChangelogBubble scope={scope} />
      <WebBubble />
      <AppBubble />
    </div>
  );
}

function Bubble({ icon, children, action, onClose, closeLabel }: { icon: ReactNode; children: ReactNode; action?: ReactNode; onClose?: (() => void) | undefined; closeLabel: string }) {
  return (
    <div className={css.bubble} role="status">
      <span className={css.icon}>{icon}</span>
      <span className={css.text}>{children}</span>
      {action}
      {onClose && <button type="button" className={css.close} aria-label={closeLabel} title={closeLabel} onClick={onClose}><Close size={14} strokeWidth={1.8} /></button>}
    </div>
  );
}

/** The desktop app's newer build: installed (and the app restarted) when asked; put away for this run of the page. */
function AppBubble() {
  const updates = typeof window === "undefined" ? undefined : window.stillfailDesktop?.appUpdate;
  const state = useAppUpdate();
  const [away, setAway] = useState(false);
  if (!updates || !state || (away && state.phase !== "downloading" && state.phase !== "installing")) return null;
  const busy = state.phase === "downloading" || state.phase === "installing";
  const text = state.phase === "downloading" ? t("web-main.appUpdate.downloading", { percent: state.percent })
    : state.phase === "installing" ? t("web-main.appUpdate.restarting")
    : state.phase === "failed" ? state.message || t("web-main.appUpdate.failed")
    : t("web-main.appUpdate.title", { version: state.version, app: NAME });
  return (
    <Bubble icon={<Download size={16} />} closeLabel={t("web-main.webUpdate.later")} onClose={busy ? undefined : () => setAway(true)}
      action={!busy && <button type="button" className={css.action} onClick={() => updates.start()}>{state.phase === "failed" ? t("web-main.appUpdate.failed") : t("web-main.versions.update")}</button>}>
      {text}
    </Bubble>
  );
}

/** The page's newer build: loaded when asked, or put away (webUpdates says when it comes again). */
function WebBubble() {
  const update = useSyncExternalStore(webUpdates.subscribe, webUpdates.snapshot, () => null);
  if (!update) return null;
  return (
    <Bubble icon={<Refresh size={16} />} closeLabel={t("web-main.webUpdate.later")} onClose={webUpdates.dismiss}
      action={<button type="button" className={css.action} onClick={webUpdates.refresh}>{t("web-main.webUpdate.refresh")}</button>}>
      {t("web-main.webUpdate.found")}
    </Bubble>
  );
}

/** What the update just installed brought: its first line, the rest in the changelog; put away, seen. */
function ChangelogBubble({ scope }: { scope: string }) {
  const news = useChangelog().value?.news;
  const seen = useChangelogSeen();
  if (!news) return null;
  const first = news.entries.flatMap((e) => e.text)[0];
  return (
    <Bubble icon={<Sparks size={16} strokeWidth={1.8} />} closeLabel={t("web-pages.changelog.dismiss")} onClose={seen}
      action={<Link className={css.action} to={`/w/${scope}/settings/changelog`} onClick={seen}>{t("web-main.system.changelog")}</Link>}>
      <b>{news.build ? t("web-pages.changelog.updatedTo", { build: news.build }) : t("web-pages.changelog.updated")}</b>
      {first && <span className={css.line}>{first}</span>}
    </Bubble>
  );
}
