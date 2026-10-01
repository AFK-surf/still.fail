import { useSyncExternalStore } from "react";
import { webUpdates } from "./core/webUpdates.ts";
import * as css from "./WebUpdate.css.ts";

/** A persistent, non-modal notice shared by phone and desktop browsers. */
export function WebUpdate() {
  const update = useSyncExternalStore(webUpdates.subscribe, webUpdates.snapshot, () => null);
  if (!update) return null;
  return <aside className={css.notice} aria-label="网页更新">
    <span role="status">发现新版本</span>
    <button className={css.refresh} onClick={webUpdates.refresh}>刷新更新</button>
    <button className={css.later} onClick={webUpdates.dismiss}>稍后</button>
  </aside>;
}
