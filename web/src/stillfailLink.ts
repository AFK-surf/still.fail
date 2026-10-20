// still.fail's own links (/o/<workspace>/<station>/<session>, as agents post them; a chat's page,
// /w/<workspace>/s/<station>/chats/<id>, as a reference written on the web is), read back into what they name: a session
// of a workspace's station, maybe one of its web services (`?service=<job>`). The desktop's chat reads them the same way
// (pages/ChatPage.tsx); the narrow pages (mobile/Chat.tsx) open them in the app instead of loading the page again. A
// screen's page (/w/<workspace>/s/<station>/screen/<id>, an agent asking a person to take over) opens its viewer.
import type { MouseEvent as ReactMouseEvent } from "react";

/** `own`: on this app's cloud, under any of its names (ownOrigin), so opened here rather than on another site. */
export interface StillFailLink { workspace: string; station: string; session: string; service: string | null; search: string; own: boolean }

/**
 * still.fail cloud's hosts: the released app's, the test channel's (youdid.wtf, the same cloud), and ember's from before
 * the rename (client/core-ts/src/asks.ts CLOUD_HOSTS).
 */
const CLOUD_HOSTS = ["app.still.fail", "app.youdid.wtf", "ember.3720.org"];

const cloudHost = (url: URL) => url.protocol === "https:" && url.port === "" && CLOUD_HOSTS.includes(url.hostname);

/**
 * Whether `url` is on the cloud the app at `here` (its page's origin) and `cloud` (the desktop app's cloud origin) is:
 * either of them, or, when the app is on still.fail cloud, any of its hosts: a link agents post names app.still.fail,
 * a reference written on the test channel's web app names app.youdid.wtf, and both are this app's own wherever it is.
 */
export function ownOrigin(url: URL, here: string = location.origin, cloud: string | null = window.stillfailDesktop?.cloudOrigin ?? null): boolean {
  if (url.origin === here || (cloud !== null && url.origin === cloud)) return true;
  const ours = (origin: string | null) => {
    try { return origin !== null && cloudHost(new URL(origin)); } catch { return false; }
  };
  return cloudHost(url) && (ours(here) || ours(cloud));
}

/** What an ember link names, or null when it is not one. */
export function stillfailLink(href: string): StillFailLink | null {
  let url: URL;
  try { url = new URL(href, location.href); } catch { return null; }
  const item = /^\/o\/([^/]+)\/([^/]+)\/([^/]+)\/?$/.exec(url.pathname) ?? /^\/w\/([^/]+)\/s\/([^/]+)\/chats\/([^/]+)\/?$/.exec(url.pathname);
  if (!item) return null;
  return {
    workspace: item[1]!, station: item[2]!, session: decodeURIComponent(item[3]!),
    service: url.searchParams.get("service"), search: url.search, own: ownOrigin(url),
  };
}

/** The ember link a click (a plain one: no modifier, the main button) lands on, or null. */
export function stillfailLinkClicked(event: MouseEvent | ReactMouseEvent): StillFailLink | null {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return null;
  const anchor = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
  return anchor ? stillfailLink(anchor.href) : null;
}

/**
 * A page of one of a station's screens (`/w/<workspace>/s/<station>/screen/<id>`, as the agents' `screen` tool links
 * it: docs/remote-screens.md), read back: `path` the app's own address of it.
 */
export interface ScreenLink { workspace: string; station: string; screen: string; path: string; own: boolean }

export function screenLink(href: string): ScreenLink | null {
  let url: URL;
  try { url = new URL(href, location.href); } catch { return null; }
  const page = /^\/w\/([^/]+)\/s\/([^/]+)\/screen\/([^/]+)\/?$/.exec(url.pathname);
  if (!page) return null;
  let screen: string;
  try { screen = decodeURIComponent(page[3]!); } catch { return null; }
  return { workspace: page[1]!, station: page[2]!, screen, path: `/w/${page[1]}/s/${page[2]}/screen/${page[3]}`, own: ownOrigin(url) };
}

/** The screen's page a click (a plain one) lands on, or null. */
export function screenLinkClicked(event: MouseEvent | ReactMouseEvent): ScreenLink | null {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return null;
  const anchor = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
  return anchor ? screenLink(anchor.href) : null;
}
