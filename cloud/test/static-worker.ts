// Only the test bundler imports this entry: a stand-in for the three static Workers (ember-web, ember-admin,
// ember-preview), as Cloudflare serves their assets — by host, from its own directory (ASSETS gets
// /<site>/<path>): the file, or the site's index.html for any other path (the web app and the console), or its
// 404.html (the preview host). Only GET and HEAD.
type StaticEnv = { ASSETS: Fetcher; PUBLIC_ORIGIN: string; ADMIN_ORIGIN: string; PREVIEW_ORIGIN: string };

export default {
  async fetch(request: Request, env: StaticEnv): Promise<Response> {
    const url = new URL(request.url);
    const site = url.origin === env.PUBLIC_ORIGIN ? "web" : url.origin === env.ADMIN_ORIGIN ? "admin" : url.origin === env.PREVIEW_ORIGIN ? "preview" : null;
    if (!site) return new Response("no such host", { status: 404 });
    if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
    const get = (path: string) => env.ASSETS.fetch(new Request(new URL(`/${site}${path}`, url), request));
    const path = site === "preview" && url.pathname === "/_ember/frame" ? "/_ember/frame.html" : url.pathname;
    const file = await get(path.endsWith("/") ? `${path}index.html` : path);
    // What the preview host's _headers says (src/preview.ts).
    if (site === "preview" && path === "/_ember/sw.js" && file.ok) return new Response(file.body, { headers: { "content-type": "text/javascript; charset=utf-8", "service-worker-allowed": "/" } });
    if (file.status !== 404) return file;
    if (site === "preview") return new Response((await get("/404.html")).body, { status: 404, headers: { "content-type": "text/html; charset=utf-8" } });
    return get("/index.html");
  },
};
