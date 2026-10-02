import { useStatus, type StatusView } from "./api.ts";
import { core } from "./core/react.ts";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import { StatusDot, Tip } from "./ui.tsx";
import * as nav from "./Sidebar.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import { t } from "./i18n.ts";

/** What the core is waiting on (see StationTrouble); down, it offers to try again at once (client/core/src/wake.rs). */
export function Waiting({ status }: { status: StatusView }) {
  return (
    <Tip label={<WaitingItems status={status} />} side="top">
      <div className={`${nav.navRow} ${nav.stationTrouble}`} data-state={status.state} role="status" tabIndex={0}>
        <span className={nav.stationTroubleMark}>
          {status.state === "trouble" ? <StatusDot state="offline" /> : <span className={`${waitingCss.spinner} ${nav.rowSpinner}`} aria-hidden="true" />}
        </span>
        <span className={nav.stationTroubleText}>{status.text}</span>
        {status.state === "trouble" && <Retry inTip />}
      </div>
    </Tip>
  );
}

/** Each thing the core waits on, how long and how fast: on hover of what says it waits. */
export function WaitingItems({ status }: { status: StatusView }) {
  return (
    <span className={nav.waitingItems}>
      {status.items.map((item, i) => (
        <span key={i} className={nav.waitingItem} data-state={item.state}>
          <span>{item.text}</span>
          <span className={nav.waitingDetail}>{item.detail}</span>
        </span>
      ))}
    </span>
  );
}

/**
 * Tried again at once: no more waiting, the connections tried against new ones (client/core/src/wake.rs `retry`).
 * Failed: a red mark before it a few seconds, why on hover (`inTip`: in a row whose own tip shows instead, none).
 */
export function Retry({ inTip = false }: { inTip?: boolean }) {
  const state = useDoingState("client.wake", { retry: true });
  const trying = state.running;
  return (
    <button type="button" className={nav.waitingRetry} disabled={trying} aria-busy={trying || undefined} onClick={() => core().retry()}>
      {trying ? <><DoingShown state={state} className={nav.rowSpinner} />{t("web-main.retrying")}</> : <><DoingShown state={state} size={12} bare={inTip} />{t("common.retry")}</>}
    </button>
  );
}

/**
 * Under a page's "loading…": what the core has been waiting on for a while, if anything (the core's `status`): of the
 * page's workspace, or before there is one all of it.
 */
export function StatusLine({ workspace }: { workspace?: string }) {
  const text = useStatus(workspace)?.text;
  return text ? <span className={nav.statusLine}>{text}</span> : null;
}
