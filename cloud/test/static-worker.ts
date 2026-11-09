// Only the test bundler imports this entry: a stand-in for the static Workers (stillfail-web, stillfail-admin, stillfail-preview),
// as Cloudflare serves their assets — by host (each on its new name and its old one), from its own
// directory (ASSETS gets /<site>/<path>): the file (the web app's pages also at their address without .html), or the
// site's index.html for any other path (the web app and the console), or its 404.html (the preview host). Only GET and
// HEAD. The web app's old host redirects its pages to the new one first, as stillfail-web's own code does (src/web.ts). The
// test channel's host (BETA_ORIGIN, stillfail-web-beta) is the web app's files through the same code. The share host
// (SHARE_ORIGIN, stillfail-share) answers with the headers its _headers says (src/share.ts), read as Cloudflare reads
// it: a path (or one ending in *), then its headers, indented.
import { serveWeb } from "../src/web.ts";
type StaticEnv = { ASSETS: Fetcher; PUBLIC_ORIGIN: string; ADMIN_ORIGIN: string; PREVIEW_ORIGIN: string; PUBLIC_ORIGIN_ALIASES: string; ADMIN_ORIGIN_ALIASES: string; PREVIEW_ORIGIN_ALIASES: string; BETA_ORIGIN: string };
type Site = "web" | "admin" | "preview";

const FRAME = /^\/_stillfail\/frame$/, WORKER = /^\/_stillfail\/sw\.js$/;

export default {
  async fetch(request: Request, env: StaticEnv): Promise<Response> {
    const url = new URL(request.url);
    const on = (origin: string, alias: string) => url.origin === origin || url.origin === alias;
    const site: Site | null = on(env.PUBLIC_ORIGIN, env.PUBLIC_ORIGIN_ALIASES) || url.origin === env.BETA_ORIGIN ? "web" : on(env.ADMIN_ORIGIN, env.ADMIN_ORIGIN_ALIASES) ? "admin" : on(env.PREVIEW_ORIGIN, env.PREVIEW_ORIGIN_ALIASES) ? "preview" : null;
    if (!site) return new Response("no such host", { status: 404 });
    return site === "web" ? serveWeb(request, env, (r) => files(r, env, site)) : files(request, env, site);
  },
};

async function files(request: Request, env: StaticEnv, site: "web" | "admin" | "preview"): Promise<Response> {
  const url = new URL(request.url);
  if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
  const get = (path: string) => env.ASSETS.fetch(new Request(new URL(`/${site}${path}`, url), request));
  const path = site === "preview" && FRAME.test(url.pathname) ? `${url.pathname}.html` : url.pathname;
  const asked = await get(path.endsWith("/") ? `${path}index.html` : path);
  // (a page's .html at its address without it, as Cloudflare serves it)
  const file = asked.status === 404 && site === "web" && !/\.\w+$/.test(path) ? await get(`${path}.html`) : asked;
  // What the preview host's _headers says (src/preview.ts).
  if (site === "preview" && WORKER.test(path) && file.ok) return new Response(file.body, { headers: { "content-type": "text/javascript; charset=utf-8", "service-worker-allowed": "/" } });
  if (file.status !== 404) return file;
  if (site === "preview") return new Response((await get("/404.html")).body, { status: 404, headers: { "content-type": "text/html; charset=utf-8" } });
  return get("/index.html");
}
