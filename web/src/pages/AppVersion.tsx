// The desktop app's own version, and looking for a newer build now rather than at the next check (apps/desktop/src/main.ts).
import { useState } from "react";
import { useAppUpdate } from "../brand.tsx";
import type { UpdateCheck } from "../core/client.ts";
import { Button, MobileBack, Section } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./AppVersion.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
/** Only the desktop app has a version of its own to show. */
export const HAS_VERSION = typeof window !== "undefined" && !!window.stillfailDesktop?.version;

export function AppVersionPage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.settings.nav.version")}</h1></div></header>
      <Section title={t("web-pages.version.title", { name: NAME })} description={t("web-pages.version.lead")}>
        <AppVersion />
      </Section>
    </div>
  );
}

function AppVersion() {
  const desktop = window.stillfailDesktop;
  const update = useAppUpdate();
  const [checking, setChecking] = useState(false);
  const [found, setFound] = useState<UpdateCheck | null>(null);
  const check = desktop?.appUpdate?.check;
  const run = () => {
    if (!check) return;
    setChecking(true);
    void check().then(setFound, (error: Error) => setFound({ current: desktop?.version ?? "", error: error.message })).finally(() => setChecking(false));
  };
  const note = update?.phase === "downloading" ? t("web-pages.version.downloading", { version: update.version, percent: update.percent })
    : update?.phase === "installing" ? t("web-pages.version.installing", { version: update.version })
    : update?.phase === "failed" ? t("web-pages.version.failed", { version: update.version, error: update.message })
    : update ? t("web-pages.version.available", { version: update.version })
    : checking ? t("web-pages.version.checking")
    : found?.error ? t("web-pages.version.checkFailed", { error: found.error })
    : found ? t("web-pages.version.latest")
    : null;
  const bad = update?.phase === "failed" || (!update && !checking && !!found?.error);
  const busy = update?.phase === "downloading" || update?.phase === "installing";
  return (
    <div className={css.row}>
      <div className={css.text}>
        <span>{desktop?.version}</span>
        {note && <span className={bad ? css.failed : css.note}>{note}</span>}
      </div>
      {update
        ? <Button variant="primary" busy={busy} onClick={() => desktop?.appUpdate?.start()}>{update.phase === "failed" ? t("common.retry") : t("web-pages.version.updateTo", { version: update.version })}</Button>
        : check && <Button busy={checking} onClick={run}>{t("web-pages.version.check")}</Button>}
    </div>
  );
}
