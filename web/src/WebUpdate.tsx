import { useSyncExternalStore } from "react";
import { webUpdates } from "./core/webUpdates.ts";
import { Refresh } from "./icons.tsx";
import * as css from "./WebUpdate.css.ts";
import { t } from "./i18n.ts";

/** In the desktop sidebar's foot; phones without a sidebar use the floating notice. */
export function WebUpdate({ floating = false }: { floating?: boolean }) {
  const update = useSyncExternalStore(webUpdates.subscribe, webUpdates.snapshot, () => null);
  if (!update) return null;
  return <aside className={floating ? css.notice : css.sidebar} aria-label={t("web-main.webUpdate.label")}>
    {floating ? <>
      <span role="status">{t("web-main.webUpdate.found")}</span>
      <button className={css.refresh} onClick={webUpdates.refresh}>{t("web-main.webUpdate.refresh")}</button>
    </> : <button className={css.sidebarRefresh} onClick={webUpdates.refresh} aria-label={t("web-main.webUpdate.foundRefresh")}>
      <Refresh size={14} /><span role="status">{t("web-main.webUpdate.short")}</span>
    </button>}
    <button className={css.later} onClick={webUpdates.dismiss}>{t("web-main.webUpdate.later")}</button>
  </aside>;
}
