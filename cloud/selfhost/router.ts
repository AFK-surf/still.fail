// What Cloudflare's routing is in front of a self-hosted cloud (config.ts): each request to the Worker its host and
// path are routed to (ROUTES, made from the wrangler files). It listens where only the proxy in front reaches it
// (Caddy, which ends TLS: workerd takes its X-Forwarded-Proto for the URL's scheme), and says who asked as Cloudflare
// says it, cf-connecting-ip, from the proxy's X-Forwarded-For (the login limits count by it).
import type { Role, Route } from "./config.ts";

export type RouterEnv = { PUBLIC_ORIGIN: string; ADMIN_ORIGIN: string; PREVIEW_ORIGIN: string | null; ROUTES: Route[] } & Record<"API" | "WEB" | "ADMIN" | "PREVIEW", Fetcher>;

/** The Worker that answers a request to `url`, or null for a host that is none of the cloud's. */
export function routeOf(env: Omit<RouterEnv, "API" | "WEB" | "ADMIN" | "PREVIEW">, url: URL): Route["to"] | null {
  const role: Role | null = url.origin === env.PUBLIC_ORIGIN ? "public" : url.origin === env.ADMIN_ORIGIN ? "admin" : env.PREVIEW_ORIGIN && url.origin === env.PREVIEW_ORIGIN ? "preview" : null;
  if (!role) return null;
  const path = url.pathname;
  return env.ROUTES.find((r) => r.role === role && (r.path === "*" || (r.path.endsWith("*") ? path.startsWith(r.path.slice(0, -1)) : path === r.path)))?.to ?? null;
}

export default {
  fetch(request: Request, env: RouterEnv): Promise<Response> | Response {
    const to = routeOf(env, new URL(request.url));
    if (!to) return new Response("no such host", { status: 404 });
    const asked = new Request(request);
    const from = request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim();
    // (only the proxy's word: whatever a client sent as cf-connecting-ip is not believed)
    asked.headers.delete("cf-connecting-ip");
    if (from) asked.headers.set("cf-connecting-ip", from);
    return ({ api: env.API, web: env.WEB, admin: env.ADMIN, preview: env.PREVIEW })[to].fetch(asked);
  },
} satisfies ExportedHandler<RouterEnv>;
