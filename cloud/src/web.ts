// The web app's Worker (ember-web, wrangler.web.jsonc): its static files, and on its old host (ember.3720.org, from
// before the rename) the pages moved to the new one — the same path and query on PUBLIC_ORIGIN, so links already sent
// (Slack's, invitations, bookmarks) open the app where it now lives. Only the pages: the API's and the relay's paths
// on the old host are routes of their own (wrangler.jsonc), which stations and apps from before the rename keep
// calling, and never reach this Worker. 302, not 301, which browsers would remember for good.
import { publicOrigins } from "./compat.ts";

export type WebEnv = { ASSETS: Fetcher; PUBLIC_ORIGIN: string; PUBLIC_ORIGIN_ALIASES?: string };

/** Where a page asked for on an old host has moved to, or null when it is served here. */
export function moved(request: Request, env: Omit<WebEnv, "ASSETS">): Response | null {
  const url = new URL(request.url);
  if (url.origin === env.PUBLIC_ORIGIN || !publicOrigins(env).includes(url.origin)) return null;
  // The notifications' service worker stays: a browser checking it for an update follows no redirect, and pushes
  // subscribed on the old host keep coming through it.
  if (url.pathname === "/sw.js") return null;
  return Response.redirect(`${env.PUBLIC_ORIGIN}${url.pathname}${url.search}`, 302);
}

export default {
  fetch(request: Request, env: WebEnv): Response | Promise<Response> {
    return moved(request, env) ?? env.ASSETS.fetch(request);
  },
};
