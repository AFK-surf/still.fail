// The web app's Worker (ember-web, wrangler.web.jsonc): its static files, and on its old host (ember.3720.org, from
// before the rename) the pages moved to the new one — the same path and query on PUBLIC_ORIGIN, so links already sent
// (Slack's, invitations, bookmarks) open the app where it now lives. Only the pages: the API's and the relay's paths
// on the old host are routes of their own (wrangler.jsonc), which stations and apps from before the rename keep
// calling, and never reach this Worker. 302, not 301, which browsers would remember for good.
// The same code and the same files are the test channel's Worker too (ember-web-beta, wrangler.web-beta.jsonc, on
// BETA_ORIGIN): a build tried there is promoted to ember-web byte for byte (deploy.py promote-web). On that host every
// answer says not to index it, /robots.txt disallows everything, and each page gets
// <meta name="stillfail-beta" content="<PUBLIC_ORIGIN>">, by which the page knows it is the test channel and where the
// stable one is (web/src/cloud/beta.tsx); what the files call the product before any script runs (the title, the
// link previews' tags, the manifest's names) says the test channel's name instead, and its icons are the beta apps'
// face (dark, white eyes; design/app-icon/face-beta.svg) under the same paths.
import { betaOrigin, publicOrigins } from "./compat.ts";

export type WebEnv = { ASSETS: Fetcher; PUBLIC_ORIGIN: string; PUBLIC_ORIGIN_ALIASES?: string; BETA_ORIGIN?: string };

/** Where a page asked for on an old host has moved to, or null when it is served here. */
export function moved(request: Request, env: Omit<WebEnv, "ASSETS">): Response | null {
  const url = new URL(request.url);
  if (url.origin === env.PUBLIC_ORIGIN || !publicOrigins(env).includes(url.origin)) return null;
  // The notifications' service worker stays: a browser checking it for an update follows no redirect, and pushes
  // subscribed on the old host keep coming through it.
  if (url.pathname === "/sw.js") return null;
  return Response.redirect(`${env.PUBLIC_ORIGIN}${url.pathname}${url.search}`, 302);
}

const NOINDEX = "noindex, nofollow";

/** The test channel's name (still.fail's dual), as the page has it (web/src/channel.ts). */
const BETA_NAME = "youdid.wtf";

/** The icons the test channel serves at the stable one's paths (web/public): the beta apps' face. */
export const BETA_ICONS: Record<string, string> = {
  "/favicon.svg": "/favicon-beta.svg",
  "/favicon-32.png": "/favicon-beta-32.png",
  "/apple-touch-icon.png": "/apple-touch-icon-beta.png",
  "/icon-192.png": "/icon-beta-192.png",
  "/icon-512.png": "/icon-beta-512.png",
};

/** `text` with the product's name the test channel's: the word, not a host or a URL (app.still.fail stays). */
export function betaNamed(text: string): string {
  return text.replace(/(?<![\w./-])still\.fail(?![\w-]|\.\w)/g, BETA_NAME);
}

/** The web app's answer to `request`, its files got by `files`: as above, on the test channel's host or the others. */
export async function serveWeb(request: Request, env: Omit<WebEnv, "ASSETS">, files: (request: Request) => Promise<Response> | Response): Promise<Response> {
  const redirect = moved(request, env);
  if (redirect) return redirect;
  if (new URL(request.url).origin !== betaOrigin(env)) return files(request);
  if (new URL(request.url).pathname === "/robots.txt") {
    return new Response("User-agent: *\nDisallow: /\n", { headers: { "content-type": "text/plain; charset=utf-8", "x-robots-tag": NOINDEX } });
  }
  const icon = BETA_ICONS[new URL(request.url).pathname];
  const file = await files(icon ? new Request(new URL(icon, request.url), request) : request);
  if (new URL(request.url).pathname === "/site.webmanifest" && file.ok) {
    const answer = new Response(betaNamed(await file.text()), file);
    answer.headers.delete("content-length");
    answer.headers.set("x-robots-tag", NOINDEX);
    return answer;
  }
  const answer = new Response(file.body, file);
  answer.headers.set("x-robots-tag", NOINDEX);
  if (!(answer.headers.get("content-type") ?? "").startsWith("text/html")) return answer;
  const meta = `<meta name="stillfail-beta" content="${env.PUBLIC_ORIGIN.replace(/[&"<>]/g, "")}">`;
  return new HTMLRewriter()
    .on("head", { element: (head) => void head.prepend(meta, { html: true }) })
    .on("title", { text: (text) => {
      const named = betaNamed(text.text);
      if (named !== text.text) text.replace(named);
    } })
    .on("meta[content]", { element: (tag) => {
      const content = tag.getAttribute("content") ?? "";
      if (betaNamed(content) !== content) tag.setAttribute("content", betaNamed(content));
    } })
    .transform(answer);
}

export default {
  fetch(request: Request, env: WebEnv): Response | Promise<Response> {
    return serveWeb(request, env, (r) => env.ASSETS.fetch(r));
  },
};
