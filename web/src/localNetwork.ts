// macOS's Local Network for the desktop app (apps/desktop/src/local-network.ts), as the pages show it: whether it may
// reach the LAN it is on (the permissions page), and whether it is kept from a station at the LAN addresses the station
// said (its row and its page say so, with the way to System Settings). Not let, the app reaches a station on its LAN only
// past the router or over a relay (a MacBook on studio's Wi-Fi, 2026-10-18). Not a Mac's app: never kept.
import { useEffect, useState } from "react";

const DESKTOP = typeof window === "undefined" ? undefined : window.stillfailDesktop?.localNetwork;
/** The desktop app on a Mac, from a build that can tell. */
export const CAN_LOCAL_NETWORK = DESKTOP !== undefined && /Mac/.test(navigator.platform);
/** A station's addresses are asked again at most this often, by every row and page showing it at once. */
const AGAIN_MS = 10_000;

const kept = new Map<string, { at: number; kept: boolean; asking?: Promise<boolean> }>();

function ask(addrs: string[]): Promise<boolean> {
  const key = addrs.join(" ");
  const was = kept.get(key);
  if (was?.asking) return was.asking;
  if (was && Date.now() - was.at < AGAIN_MS) return Promise.resolve(was.kept);
  const asking = DESKTOP!.kept(addrs).catch(() => false);
  kept.set(key, { at: was?.at ?? 0, kept: was?.kept ?? false, asking });
  return asking.then((k) => (kept.set(key, { at: Date.now(), kept: k }), k));
}

/** Whether macOS keeps this app from the station at `lan` (where it said it is on its LAN): asked as it shows, every
 *  AGAIN_MS while the page is seen, and as the window comes back to the front (from System Settings). */
export function useLanKept(lan: string[] | undefined): boolean {
  const key = CAN_LOCAL_NETWORK && lan?.length ? lan.join(" ") : "";
  const [now, setNow] = useState(() => (key ? (kept.get(key)?.kept ?? false) : false));
  useEffect(() => {
    if (!key) return setNow(false);
    let live = true;
    const look = () => {
      if (document.visibilityState === "visible") void ask(key.split(" ")).then((k) => live && setNow(k));
    };
    look();
    const every = setInterval(look, AGAIN_MS);
    window.addEventListener("focus", look);
    return () => {
      live = false;
      clearInterval(every);
      window.removeEventListener("focus", look);
    };
  }, [key]);
  return now;
}

/** Whether the app may reach the LAN it is on: granted | denied | unknown. */
export function checkLocalNetwork(): Promise<string> {
  return DESKTOP ? DESKTOP.check().catch(() => "unknown") : Promise.resolve("unknown");
}

/** System Settings' Local Network list, where it is switched on. */
export function openLocalNetwork(): void {
  void DESKTOP?.settings();
}
