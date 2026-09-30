import { useEffect, useRef, useState } from "react";
import { useStatus, type Link, type StatusView } from "./api.ts";
import { core } from "./core/react.ts";
import { StatusDot, Tip } from "./ui.tsx";
import * as css from "./Connection.css.ts";
import * as nav from "./Sidebar.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";

/** How long "连上了" stays once all is well again. */
const BACK_MS = 1500;

type Shown = { tone: "busy" | "trouble" | "back"; text: string; detail?: string | undefined; items?: StatusView["items"] | undefined };

/**
 * What is not as it should be with the connection to this chat's station, or with what the core waits on (its
 * `status`: what, how long, how fast): nothing while all is well. Down, it offers to try again at once (no more
 * waiting, the connections tried against new ones: client/core/src/wake.rs `retry`); back, it says so a moment.
 */
export function ConnectionPill({ link, name, phone }: { link?: Link | undefined; name?: string | undefined; phone?: boolean }) {
  const status = useStatus();
  const now = shownOf(link, name, status);
  const [back, setBack] = useState(false);
  const was = useRef(false);
  useEffect(() => {
    if (now) {
      was.current = true;
      setBack(false);
      return;
    }
    if (!was.current) return;
    was.current = false;
    setBack(true);
    const done = setTimeout(() => setBack(false), BACK_MS);
    return () => clearTimeout(done);
  }, [!!now]);
  const shown: Shown | null = now ?? (back ? { tone: "back", text: "已连上" } : null);
  if (!shown) return null;
  const pill = (
    <div className={phone ? `${css.connection} ${css.connectionPhone}` : css.connection} data-tone={shown.tone} role="status" tabIndex={shown.items?.length ? 0 : undefined}>
      <span className={css.connectionMark}>
        {shown.tone === "busy" ? <span className={`${waitingCss.spinner} ${nav.rowSpinner}`} aria-hidden="true" />
          : shown.tone === "trouble" ? <StatusDot state="error" /> : <span className={css.connectionBack} />}
      </span>
      <span className={css.connectionText}>{shown.text}</span>
      {shown.detail && <span className={css.connectionDetail}>{shown.detail}</span>}
      {shown.tone === "trouble" && <button type="button" className={css.connectionRetry} onClick={() => core().retry()}>重试</button>}
    </div>
  );
  if (!shown.items?.length) return pill;
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

function shownOf(link: Link | undefined, name: string | undefined, status: StatusView | undefined): Shown | null {
  const station = name ? `「${name}」` : " station";
  if (link?.state === "offline" || link?.state === "error") return { tone: "trouble", text: `连不上${station}`, detail: why(link.message) };
  if (link?.state === "reconnecting") return { tone: "busy", text: `正在重连${station}`, items: status?.items };
  if (status?.state === "trouble") return { tone: "trouble", text: status.text ?? "连不上 still.fail cloud", items: status.items };
  if (status?.state === "slow") return { tone: "busy", text: status.text ?? "", items: status.items };
  return null;
}

/** Why the link is down, less its own "连不上这台 station：" (the pill says that already). */
function why(message: string | undefined): string | undefined {
  if (!message) return undefined;
  const at = message.indexOf("：");
  return at >= 0 && message.slice(0, at).includes("连不上") ? message.slice(at + 1) : message;
}
