// still.fail's own links (/o/<workspace>/<station>/<session>, as agents post them), read back into what they name: a session
// of a workspace's station, maybe one of its web services (`?service=<job>`). The desktop's chat reads them the same way
// (pages/ChatPage.tsx); the narrow pages (mobile/Chat.tsx) open them in the app instead of loading the page again.
import type { MouseEvent as ReactMouseEvent } from "react";

export interface StillFailLink { workspace: string; station: string; session: string; service: string | null; search: string; sameOrigin: boolean }

/** What an ember link names, or null when it is not one. */
export function stillfailLink(href: string): StillFailLink | null {
  let url: URL;
  try { url = new URL(href, location.href); } catch { return null; }
  const item = /^\/o\/([^/]+)\/([^/]+)\/([^/]+)\/?$/.exec(url.pathname);
  if (!item) return null;
  return {
    workspace: item[1]!, station: item[2]!, session: decodeURIComponent(item[3]!),
    service: url.searchParams.get("service"), search: url.search, sameOrigin: url.origin === location.origin,
  };
}

/** The ember link a click (a plain one: no modifier, the main button) lands on, or null. */
export function stillfailLinkClicked(event: MouseEvent | ReactMouseEvent): StillFailLink | null {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return null;
  const anchor = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
  return anchor ? stillfailLink(anchor.href) : null;
}
