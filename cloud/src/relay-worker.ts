// still.fail's relay, a Worker of its own (ember-relay): deployed only when the relay changes, so the rest of
// still.fail cloud is deployed without dropping every device's and station's relay connection. It answers, on
// PUBLIC_ORIGIN's host and its old ones (routes that take precedence over the web app's Custom Domain:
// wrangler.relay.jsonc):
//   /relay            the iroh relay (a WebSocket): admitted by the service budget (relay.ts), then straight to the relay process
//   /ping             iroh's latency probe (net_report)
//   /generate_204     iroh's captive portal check
//   /v1/admin/relay/* for operators: restart the relay process, where it runs
import { Container } from "@cloudflare/containers";
import { bearerToken, denied, digest, limited, reply } from "./auth";
import { publicOrigins } from "./compat";
import type { RelayBudget } from "./relay";
export { RelayBudget } from "./relay";

export interface RelayEnv {
  RELAY_BUDGET: DurableObjectNamespace<RelayBudget>;
  RELAY: DurableObjectNamespace<Relay>;
  PUBLIC_ORIGIN: string;
  /** Its older origins, comma-separated (compat.ts): stations from before the rename have one as their relay. */
  PUBLIC_ORIGIN_ALIASES?: string;
  ADMIN_TOKEN?: string;
}

/** The iroh-relay process (Dockerfile), one; connections reach it only once the budget admits them. */
export class Relay extends Container<RelayEnv> {
  defaultPort = 8080;
  sleepAfter = "10m";
  /** Its metrics (relay-entrypoint.sh), for the budget; null while it is not running, without starting it. */
  async metrics(): Promise<string | null> {
    if (!this.ctx.container?.running) return null;
    const response = await this.containerFetch(new Request("http://relay/metrics", { signal: AbortSignal.timeout(5_000) }), 9090);
    return response.ok ? response.text() : null;
  }
}

/** A challenge iroh-relay would answer (alphanumerics, '.', '-', '_', under 64 characters). */
const CHALLENGE = /^[A-Za-z0-9._-]{1,63}$/;

export default {
  async fetch(request: Request, env: RelayEnv): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    if (!publicOrigins(env).includes(url.origin)) return reply({ error: "invalid_origin" }, 421);
    if (path === "/ping" && request.method === "GET") return reply({ service: "ember-relay", relay: "iroh-relay-1.1.0" });
    if (path === "/generate_204" && request.method === "GET") {
      const challenge = request.headers.get("x-iroh-challenge");
      return new Response(null, { status: 204, headers: challenge && CHALLENGE.test(challenge) ? { "x-iroh-response": `response ${challenge}` } : {} });
    }
    if (path === "/relay") {
      if (request.method !== "GET") return reply({ error: "method_not_allowed" }, 405);
      if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") return reply({ error: "websocket_required" }, 426);
      // Cloud account state does not govern transport; only the shared budget does.
      if (!(await env.RELAY_BUDGET.getByName("primary").admit())) return limited();
      const headers = new Headers({ upgrade: "websocket" });
      const protocol = request.headers.get("sec-websocket-protocol");
      if (protocol) headers.set("sec-websocket-protocol", protocol);
      try {
        // Fixed routing and a fresh URL keep credentials, cookies and query values from the relay process and its logs.
        const response = await env.RELAY.getByName("primary").fetch(new Request("http://relay/relay", { headers, signal: AbortSignal.timeout(15_000) }));
        if (!response.webSocket || response.status !== 101) return reply({ error: "relay_unavailable" }, 502);
        const selected = response.headers.get("sec-websocket-protocol");
        return new Response(null, { status: 101, webSocket: response.webSocket, headers: selected ? { "sec-websocket-protocol": selected } : undefined });
      } catch {
        return reply({ error: "relay_unavailable" }, 502);
      }
    }
    const restart = path === "/v1/admin/relay/restart";
    if ((restart || path === "/v1/admin/relay/where") && request.method === "POST") {
      const supplied = bearerToken(request);
      if (!env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 43 || !supplied || (await digest(supplied)) !== (await digest(env.ADMIN_TOKEN))) return denied();
      if (!restart) return reply(await env.RELAY_BUDGET.getByName("primary").where());
      // Cutovers from stateless admission must also retire the old process
      // and its untracked sockets; a started rollout is not that guarantee.
      await env.RELAY.getByName("primary").destroy();
      return reply({ restarted: true });
    }
    return reply({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<RelayEnv>;
