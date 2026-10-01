import { core } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import * as css from "./Connection.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";

/** 重试 as a small grey pill: the connections tried again at once (client/core/src/wake.rs `retry`). On a station down,
 * where it is tried again (cloud/StationCards.tsx, mobile/Stations.tsx); turning while that goes. */
export function RetryPill() {
  const trying = useDoing("client.wake", { retry: true });
  return (
    <button type="button" className={css.connectionRetry} disabled={trying} aria-busy={trying || undefined} onClick={() => core().retry()}>
      {trying && <span className={`${waitingCss.spinner} ${css.retrySpinner}`} aria-hidden="true" />}重试
    </button>
  );
}
