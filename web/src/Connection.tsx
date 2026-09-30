import { useConnection } from "./api.ts";
import { core } from "./core/react.ts";
import { StatusDot, Tip } from "./ui.tsx";
import * as css from "./Connection.css.ts";
import * as nav from "./Sidebar.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";

/**
 * What a chat on `station` says of its connection, as the core decides it (its `connection` topic,
 * client/core/src/pill.rs): its link down or coming back, or what its workspace's core waits on (what, how long, how
 * fast), and only once that has lasted; "已连上" a moment after. Nothing while all is well, nothing of another
 * workspace. Down, it offers to try again at once (no more waiting, the connections tried against new ones:
 * client/core/src/wake.rs `retry`).
 */
export function ConnectionPill({ station, phone }: { station: string; phone?: boolean }) {
  const shown = useConnection(station);
  if (!shown?.tone) return null;
  const pill = (
    <div className={phone ? `${css.connection} ${css.connectionPhone}` : css.connection} data-tone={shown.tone} role="status" tabIndex={shown.items.length ? 0 : undefined}>
      <span className={css.connectionMark}>
        {shown.tone === "busy" ? <span className={`${waitingCss.spinner} ${nav.rowSpinner}`} aria-hidden="true" />
          : shown.tone === "trouble" ? <StatusDot state="error" /> : <span className={css.connectionBack} />}
      </span>
      <span className={css.connectionText}>{shown.text}</span>
      {shown.detail && <span className={css.connectionDetail}>{shown.detail}</span>}
      {shown.tone === "trouble" && <RetryPill />}
    </div>
  );
  if (!shown.items.length) return pill;
  const items = (
    <span className={nav.waitingItems}>
      {shown.items.map((item, i) => (
        <span key={i} className={nav.waitingItem}>
          <span>{item.text}</span>
          <span className={nav.waitingDetail}>{item.detail}</span>
        </span>
      ))}
    </span>
  );
  return <Tip label={items} side="bottom">{pill}</Tip>;
}

/** 重试 as a small grey pill: the connections tried again at once (client/core/src/wake.rs `retry`). Here and on a
 * station down, where it is tried again (cloud/StationCards.tsx, mobile/Stations.tsx). */
export function RetryPill() {
  return <button type="button" className={css.connectionRetry} onClick={() => core().retry()}>重试</button>;
}
