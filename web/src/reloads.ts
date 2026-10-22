// Why a page was loaded again (docs/telemetry.md, `page_loaded`). Each place that reloads the page says why first, in
// the tab's sessionStorage, and the page that comes next reports it. A page loaded again with no reason given was not
// loaded by us: Safari's own reload, or the browser bringing back a page it had put away (iOS ends a hidden tab's
// process when memory is short, and loads it again when it is looked at).
import { track } from "./telemetry.ts";

/** Why the page itself is loaded again: the phone's chat list pulled down (mobile/pull.ts), the newer build asked for
 *  (webUpdates.ts), an older build's core retired by a newer one's (core/worker.ts), a 「重新加载」 button. */
export type ReloadReason = "pull" | "update" | "retired" | "button";

/** The reason, as the reload leaves it; the inline one in index.html writes the same. */
const REASON = "stillfail-reload";
/** This tab's page: when it started and since when it has been hidden, for the next page in the tab to say. */
const PAGE = "stillfail-page";
/** A reason older than this was not for the page loading now (a reload that never happened). */
const REASON_MS = 60_000;

type Page = { since: number; hidden: number | null };

function read<T>(key: string): T | null {
  try {
    const value = sessionStorage.getItem(key);
    sessionStorage.removeItem(key);
    return value ? JSON.parse(value) as T : null;
  } catch {
    return null;
  }
}

function write(key: string, value: unknown): void {
  try { sessionStorage.setItem(key, JSON.stringify(value)); } catch { /* No storage (a private window's quota): nothing kept. */ }
}

/** Loads the page again, having said why. */
export function reload(reason: ReloadReason): void {
  write(REASON, { reason, at: Date.now() });
  location.reload();
}

/**
 * Reports how this page came to be loaded, once, as it starts: `reason` (what reloaded it, `none` when nothing here
 * did), `navigation` (the browser's: navigate, reload, back_forward), and of the page before it in this tab, if any:
 * `after_s` (how long it had been up) and `hidden_s` (how long it had been hidden, -1 when it was in view).
 */
export function followPageLoads(): void {
  const now = Date.now();
  const before = read<Page>(PAGE);
  const said = read<{ reason?: unknown; at?: unknown }>(REASON);
  const reason = typeof said?.reason === "string" && typeof said.at === "number" && now - said.at < REASON_MS ? said.reason : "none";
  const navigation = (performance.getEntriesByType("navigation")[0] as PerformanceNavigationTiming | undefined)?.type ?? "unknown";
  const properties: Record<string, string | number | boolean> = { reason, navigation, follows: before !== null };
  if (before && typeof before.since === "number") {
    properties.after_s = Math.round((now - before.since) / 1000);
    properties.hidden_s = typeof before.hidden === "number" ? Math.round((now - before.hidden) / 1000) : -1;
  }
  track("page_loaded", properties);
  const page: Page = { since: now, hidden: document.visibilityState === "hidden" ? now : null };
  write(PAGE, page);
  document.addEventListener("visibilitychange", () => {
    page.hidden = document.visibilityState === "hidden" ? Date.now() : null;
    write(PAGE, page);
  });
}
