import { core } from "./core/react.ts";
import * as css from "./Connection.css.ts";

/** 重试 as a small grey pill: the connections tried again at once (client/core/src/wake.rs `retry`). On a station down,
 * where it is tried again (cloud/StationCards.tsx, mobile/Stations.tsx). */
export function RetryPill() {
  return <button type="button" className={css.connectionRetry} onClick={() => core().retry()}>重试</button>;
}
