import { core } from "./core/react.ts";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import * as css from "./Connection.css.ts";

/** 重试 as a small grey pill: the connections tried again at once (client/core/src/wake.rs `retry`). On a station down,
 * where it is tried again (cloud/StationCards.tsx, mobile/Stations.tsx); turning while that goes, a red mark a moment if it failed. */
export function RetryPill() {
  const state = useDoingState("client.wake", { retry: true });
  const trying = state.running;
  return (
    <button type="button" className={css.connectionRetry} disabled={trying} aria-busy={trying || undefined} onClick={() => core().retry()}>
      <DoingShown state={state} className={css.retrySpinner} size={10} />重试
    </button>
  );
}
