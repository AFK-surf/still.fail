// ember's relay, a Worker of its own (ember-relay): deployed only when the relay changes, so the rest of ember cloud
// is deployed without dropping every device's and station's relay connection. It answers, on PUBLIC_ORIGIN's host
// (routes that take precedence over the web app's Custom Domain: wrangler.relay.jsonc):
//   /relay            the iroh relay (a WebSocket), through the service budget (relay.ts) to the relay process
//   /ping             iroh's latency probe (net_report)
//   /generate_204     iroh's captive portal check
//   /v1/admin/relay/* for operators: restart the relay process, where it runs
import { Container } from "@cloudflare/containers";
import { bearerToken, denied, digest, reply } from "./auth";
import type { RelayBudget } from "./relay";
export { RelayBudget } from "./relay";

export interface RelayEnv {
  RELAY_BUDGET: DurableObjectNamespace<RelayBudget>;
  RELAY: DurableObjectNamespace<Relay>;
  PUBLIC_ORIGIN: string;
  ADMIN_TOKEN?: string;
}

/** The iroh-relay process (Dockerfile), one, reached only by the budget. */
export class Relay extends Container<RelayEnv> {
  defaultPort = 8080;
  sleepAfter = "10m";
}

/** A challenge iroh-relay would answer (alphanumerics, '.', '-', '_', under 64 characters). */
const CHALLENGE = /^[A-Za-z0-9._-]{1,63}$/;

export default {
  async fetch(request: Request, env: RelayEnv): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    if (url.origin !== env.PUBLIC_ORIGIN) return reply({ error: "invalid_origin" }, 421);
    if (path === "/ping" && request.method === "GET") return reply({ service: "ember-relay", relay: "iroh-relay-1.1.0" });
    if (path === "/generate_204" && request.method === "GET") {
      const challenge = request.headers.get("x-iroh-challenge");
      return new Response(null, { status: 204, headers: challenge && CHALLENGE.test(challenge) ? { "x-iroh-response": `response ${challenge}` } : {} });
    }
    if (path === "/relay") {
      if (request.method !== "GET") return reply({ error: "method_not_allowed" }, 405);
      return env.RELAY_BUDGET.getByName("primary").fetch(request);
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
