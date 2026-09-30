// Only the test bundler imports this entry: a stand-in for the three static Workers (ember-web, ember-admin,
// ember-preview), as Cloudflare serves their assets — by host (each on its new name and its old one), from its own
// directory (ASSETS gets /<site>/<path>): the file, or the site's index.html for any other path (the web app and the
// console), or its 404.html (the preview host). Only GET and HEAD. The web app's old host redirects its pages to the
// new one first, as ember-web's own code does (src/web.ts).
import { moved } from "../src/web.ts";
type StaticEnv = { ASSETS: Fetcher; PUBLIC_ORIGIN: string; ADMIN_ORIGIN: string; PREVIEW_ORIGIN: string; PUBLIC_ORIGIN_ALIASES: string; ADMIN_ORIGIN_ALIASES: string; PREVIEW_ORIGIN_ALIASES: string };

const FRAME = /^\/_(stillfail|ember)\/frame$/, WORKER = /^\/_(stillfail|ember)\/sw\.js$/;

export default {
  async fetch(request: Request, env: StaticEnv): Promise<Response> {
    const url = new URL(request.url);
    const on = (origin: string, alias: string) => url.origin === origin || url.origin === alias;
    const site = on(env.PUBLIC_ORIGIN, env.PUBLIC_ORIGIN_ALIASES) ? "web" : on(env.ADMIN_ORIGIN, env.ADMIN_ORIGIN_ALIASES) ? "admin" : on(env.PREVIEW_ORIGIN, env.PREVIEW_ORIGIN_ALIASES) ? "preview" : null;
    if (!site) return new Response("no such host", { status: 404 });
    const redirect = site === "web" ? moved(request, env) : null;
    if (redirect) return redirect;
    if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
    const get = (path: string) => env.ASSETS.fetch(new Request(new URL(`/${site}${path}`, url), request));
    const path = site === "preview" && FRAME.test(url.pathname) ? `${url.pathname}.html` : url.pathname;
    const file = await get(path.endsWith("/") ? `${path}index.html` : path);
    // What the preview host's _headers says (src/preview.ts).
    if (site === "preview" && WORKER.test(path) && file.ok) return new Response(file.body, { headers: { "content-type": "text/javascript; charset=utf-8", "service-worker-allowed": "/" } });
    if (file.status !== 404) return file;
    if (site === "preview") return new Response((await get("/404.html")).body, { status: 404, headers: { "content-type": "text/html; charset=utf-8" } });
    return get("/index.html");
  },
};
