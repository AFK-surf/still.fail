import { core } from "./core/react.ts";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import * as css from "./Connection.css.ts";
import { t } from "./i18n.ts";

/** 重试 as a small grey pill: the connections tried again at once (client/core-ts/src/wake.ts `retry`). On a station down,
 * where it is tried again (cloud/StationCards.tsx, mobile/Stations.tsx); turning while that goes and while `trying` (the
 * station's link `retrying`: down, and tried again just now), a red mark a moment if it failed. */
export function RetryPill({ trying: retrying = false }: { trying?: boolean }) {
  const doing = useDoingState("client.wake", { retry: true });
  const state = retrying ? { ...doing, running: true } : doing;
  const trying = state.running;
  return (
    <button type="button" className={css.connectionRetry} disabled={trying} aria-busy={trying || undefined} onClick={() => core().retry()}>
      <DoingShown state={state} inline />{t("common.retry")}
    </button>
  );
}
