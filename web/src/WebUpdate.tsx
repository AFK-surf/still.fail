import { useSyncExternalStore } from "react";
import { webUpdates } from "./core/webUpdates.ts";
import { Refresh } from "./icons.tsx";
import * as css from "./WebUpdate.css.ts";

/** In the desktop sidebar's foot; phones without a sidebar use the floating notice. */
export function WebUpdate({ floating = false }: { floating?: boolean }) {
  const update = useSyncExternalStore(webUpdates.subscribe, webUpdates.snapshot, () => null);
  if (!update) return null;
  return <aside className={floating ? css.notice : css.sidebar} aria-label="网页更新">
    {floating ? <>
      <span role="status">发现新版本</span>
      <button className={css.refresh} onClick={webUpdates.refresh}>刷新更新</button>
    </> : <button className={css.sidebarRefresh} onClick={webUpdates.refresh} aria-label="发现新版本，刷新更新">
      <Refresh size={14} /><span role="status">有新版本，刷新</span>
    </button>}
    <button className={css.later} onClick={webUpdates.dismiss}>稍后</button>
  </aside>;
}
