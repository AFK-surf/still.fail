// What the app itself has to say (no one's chat or station: those are the rail's bell, Attention.tsx), as bubbles
// rising at the page's bottom left by the rail, over whatever is there, the sidebar open or closed: the page's newer
// build (to load), what the update just installed brought (the changelog).
// Each says it in a line, with what can be done and a way to put it away.
import { useLayoutEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { Link } from "react-router";
import { webUpdates } from "./core/webUpdates.ts";
import { useChangelog, useChangelogSeen } from "./changelog.ts";
import { Close, Refresh, Sparks } from "@stillfail/ui/icons.tsx";
import { play } from "@stillfail/ui/motion.ts";
import * as css from "./SystemBubbles.css.ts";
import { t } from "./i18n.ts";

export function SystemBubbles({ scope }: { scope: string }) {
  return (
    <div className={css.stack} role="region" aria-label={t("web-main.system.label")}>
      <ChangelogBubble scope={scope} />
      <WebBubble />
    </div>
  );
}

const EASE = "cubic-bezier(.2, .7, .2, 1)";

/**
 * One bubble in its slot: coming, the slot opens (those above it moving up to make room) as it rises in; put away (its
 * close, or `action`'s `away`), it fades off to the left and its slot closes after it, then `onClose`.
 */
function Bubble({ icon, children, action, onClose, closeLabel }: {
  icon: ReactNode; children: ReactNode; action?: ((away: (then: () => void) => void) => ReactNode) | false;
  onClose?: (() => void) | undefined; closeLabel: string;
}) {
  const slot = useRef<HTMLDivElement>(null);
  const [leaving, setLeaving] = useState(false);
  useLayoutEffect(() => {
    const el = slot.current;
    if (!el) return;
    play(el, [{ height: "0px", marginTop: "-8px" }, { height: `${el.offsetHeight}px`, marginTop: "0px" }], { duration: 260, easing: EASE });
    play(el.firstElementChild, [{ opacity: 0, transform: "translateY(10px) scale(.96)" }, { opacity: 1, transform: "none" }], { duration: 320, easing: EASE });
  }, []);
  const away = (then: () => void) => {
    const el = slot.current;
    if (!el || leaving) { then(); return; }
    setLeaving(true);
    play(el.firstElementChild, [{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateX(-16px) scale(.96)" }], { duration: 180, easing: EASE, fill: "forwards" });
    void play(el, [{ height: `${el.offsetHeight}px`, marginTop: "0px" }, { height: "0px", marginTop: "-8px" }], { duration: 220, delay: 120, easing: EASE, fill: "forwards" })
      .finished.then(then, then);
  };
  return (
    <div ref={slot} className={css.slot} data-leaving={leaving || undefined}>
      <div className={css.bubble} role="status">
        <span className={css.icon}>{icon}</span>
        <span className={css.text}>{children}</span>
        {action && action(away)}
        {onClose && <button type="button" className={css.close} aria-label={closeLabel} title={closeLabel} onClick={() => away(onClose)}><Close size={14} strokeWidth={1.8} /></button>}
      </div>
    </div>
  );
}

/** The page's newer build: loaded when asked, or put away (webUpdates says when it comes again). */
function WebBubble() {
  const update = useSyncExternalStore(webUpdates.subscribe, webUpdates.snapshot, () => null);
  if (!update) return null;
  return (
    <Bubble icon={<Refresh size={16} />} closeLabel={t("web-main.webUpdate.later")} onClose={webUpdates.dismiss}
      action={() => <button type="button" className={css.action} data-tone="accent" onClick={webUpdates.refresh}>{t("web-main.webUpdate.refresh")}</button>}>
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
      action={(away) => <Link className={css.action} data-tone="accent" to={`/w/${scope}/settings/changelog`} onClick={() => away(seen)}>{t("web-main.system.changelog")}</Link>}>
      <b>{news.build ? t("web-pages.changelog.updatedTo", { build: news.build }) : t("web-pages.changelog.updated")}</b>
      {first && <span className={css.line}>{first}</span>}
    </Bubble>
  );
}
