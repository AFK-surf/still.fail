// A static site of a self-hosted cloud (config.ts: web, admin, preview), as Cloudflare serves a Worker's assets: its
// files (FILES, a directory on disk), a page's .html at its address without it, a directory's index.html, the headers
// its _headers says, and what is not there as its wrangler file's not_found_handling says (HANDLING). The web app's
// answers go through src/web.ts as stillfail-web's do, and its pages say where this cloud's preview host is
// (<meta name="stillfail-preview">, web/src/previewOrigin.ts), which a build made for any cloud cannot know.
import { serveWeb } from "../src/web.ts";

export type StaticEnv = {
  FILES: Fetcher;
  SITE: "web" | "admin" | "preview";
  HANDLING: { html: string; notFound: string };
  PUBLIC_ORIGIN: string;
  PUBLIC_ORIGIN_ALIASES?: string | null;
  BETA_ORIGIN?: string | null;
  PREVIEW_ORIGIN?: string | null;
};

const TYPES: Record<string, string> = {
  html: "text/html; charset=utf-8", js: "text/javascript; charset=utf-8", mjs: "text/javascript; charset=utf-8", css: "text/css; charset=utf-8",
  json: "application/json", webmanifest: "application/manifest+json", svg: "image/svg+xml", png: "image/png", jpg: "image/jpeg",
  jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", ico: "image/x-icon", wasm: "application/wasm", woff2: "font/woff2",
  ttf: "font/ttf", txt: "text/plain; charset=utf-8", xml: "application/xml", pdf: "application/pdf", mp4: "video/mp4", gz: "application/gzip",
};

/** A path's type by its extension (application/octet-stream for one not known). */
export const typeOf = (path: string) => TYPES[/\.([a-z0-9]+)$/i.exec(path)?.[1]?.toLowerCase() ?? ""] ?? "application/octet-stream";

/** _headers as Cloudflare reads it: a path (its * matching the rest), then its headers, indented. */
export function parseHeaders(text: string): { path: string; headers: [string, string][] }[] {
  const rules: { path: string; headers: [string, string][] }[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim() || line.trim().startsWith("#")) continue;
    if (!/^\s/.test(line)) rules.push({ path: line.trim(), headers: [] });
    else {
      const colon = line.indexOf(":");
      if (colon > 0 && rules.length) rules.at(-1)!.headers.push([line.slice(0, colon).trim(), line.slice(colon + 1).trim()]);
    }
  }
  return rules;
}

const matches = (rule: string, path: string) => (rule.endsWith("*") ? path.startsWith(rule.slice(0, -1)) : rule === path);

let headerRules: Promise<{ path: string; headers: [string, string][] }[]> | null = null;

/** A file of the site, by its path; null where there is none (a directory is none). */
async function file(env: StaticEnv, path: string, method: string): Promise<Response | null> {
  if (path.endsWith("/") || path.split("/").some((part) => part === ".." || part.startsWith("."))) return null;
  const answer = await env.FILES.fetch(new Request(`http://files${path}`, { method: method === "HEAD" ? "HEAD" : "GET" }));
  if (!answer.ok) return null;
  // (the disk service lists a directory as JSON: not a file)
  if (answer.headers.get("content-type")?.startsWith("application/json") && !path.endsWith(".json")) return null;
  return answer;
}

/** The site's answer to `request` from its files, as Cloudflare's assets would give it. */
export async function serveFiles(request: Request, env: StaticEnv): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
  const path = decodeURIComponent(new URL(request.url).pathname);
  const tried = path.endsWith("/") ? [`${path}index.html`] : /\.\w+$/.test(path) ? [path] : env.HANDLING.html === "none" ? [path] : [path, `${path}.html`, `${path}/index.html`];
  let found: Response | null = null, at = path, status = 200;
  for (const candidate of tried) if ((found = await file(env, candidate, request.method))) { at = candidate; break; }
  if (!found && env.HANDLING.notFound === "single-page-application") found = await file(env, (at = "/index.html"), request.method);
  if (!found && env.HANDLING.notFound === "404-page") {
    found = await file(env, (at = "/404.html"), request.method);
    status = 404;
  }
  if (!found) return new Response("Not found", { status: 404 });
  const headers = new Headers({ "content-type": typeOf(at) });
  for (const name of ["content-length", "last-modified"]) if (found.headers.has(name)) headers.set(name, found.headers.get(name)!);
  headerRules ??= file(env, "/_headers", "GET").then(async (r) => (r ? parseHeaders(await r.text()) : []));
  for (const rule of await headerRules) if (matches(rule.path, path)) for (const [name, value] of rule.headers) headers.set(name, value);
  return new Response(request.method === "HEAD" ? null : found.body, { status, headers });
}

/** A page of the web app saying where this cloud's preview host is. */
function withPreview(answer: Response, preview: string): Response {
  if (!(answer.headers.get("content-type") ?? "").startsWith("text/html")) return answer;
  const meta = `<meta name="stillfail-preview" content="${preview.replace(/[&"<>]/g, "")}">`;
  return new HTMLRewriter().on("head", { element: (head) => void head.prepend(meta, { html: true }) }).transform(answer);
}

export default {
  async fetch(request: Request, env: StaticEnv): Promise<Response> {
    if (env.SITE !== "web") return serveFiles(request, env);
    const answer = await serveWeb(request, { PUBLIC_ORIGIN: env.PUBLIC_ORIGIN, PUBLIC_ORIGIN_ALIASES: env.PUBLIC_ORIGIN_ALIASES ?? undefined, BETA_ORIGIN: env.BETA_ORIGIN ?? undefined }, (r) => serveFiles(r, env));
    return env.PREVIEW_ORIGIN ? withPreview(answer, env.PREVIEW_ORIGIN) : answer;
  },
} satisfies ExportedHandler<StaticEnv>;
