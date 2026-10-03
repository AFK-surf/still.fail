// What the core's tests share (core/tests.rs): a fake still.fail cloud, values with their deltas applied.
import { STORAGE_KEY, type StoredAccount } from "../src/accounts.ts";
import { Core } from "../src/core.ts";
import { apply as applyOps } from "../src/delta.ts";
import type { HttpRequest } from "../src/host.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { CoreMessage, RequestId, Topic } from "../src/protocol.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";

holdLanguage();

export const nowS = () => Date.now() / 1000;

export function account(sub: string, email: string, name: string, access: string, refresh: string, expires: number): StoredAccount {
  return { sub, email, name, picture: "", access, refresh, access_expires: expires };
}

/// A core with one signed-in account whose token expires in 30 s, still.fail cloud answering `/v1/me`, the
/// workspace and token refreshes.
export async function cloudCore(): Promise<{ host: FakeHost; core: Core }> {
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "stale", "r0", nowS() + 30)]);
  let refreshes = 0;
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    switch (path) {
      case "/v1/me":
        return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: "https://relay.test" });
      case "/v1/workspaces/ws":
        return jsonResponse(200, { id: "ws", stations: [{ id: "st", name: "studio", online: false, last_seen: 1 }] });
      case "/v1/auth/sessions":
        return jsonResponse(200, { sessions: [{ id: "d1", current: true }] });
      case "/v1/auth/sessions/d2":
        return jsonResponse(200, { ok: true });
      case "/v1/auth/refresh":
        refreshes++;
        return jsonResponse(200, { access_token: `fresh-${refreshes}`, refresh_token: "r", subject: "s1", email: "a@x.com", expires_at: nowS() + 30 });
      default:
        return jsonResponse(404, { error: "not_found" });
    }
  });
  const core = await Core.create(host, { clock: host.time.clock });
  return { host, core };
}

/// Signs `host` in as one account, whose workspace `ws` has one station, `st`.
export function signIn(host: FakeHost): void {
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "", "tok", "r0", nowS() + 3600)]);
}

/// Answers still.fail cloud as `signIn` has it, and the station's admin API (the rest) with `station`.
export function stationAnswers(host: FakeHost, station: (req: HttpRequest) => ReturnType<typeof jsonResponse> | Promise<ReturnType<typeof jsonResponse>>): void {
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: "https://relay.test" });
    if (path === "/v1/workspaces/ws") return jsonResponse(200, { id: "ws", stations: [{ id: "st", name: "studio", last_seen: null }] });
    return station(req);
  });
}

export function count(host: FakeHost, path: string): number {
  return host.requests.filter((r) => r.url.endsWith(path) && r.method === "GET").length;
}

/// The value subscription `id` has now, deltas applied.
export function apply(host: FakeHost, values: Map<RequestId, unknown>): void {
  for (const [, message] of host.takeEmitted()) {
    const m = message as Record<string, unknown>;
    if ("value" in m) values.set(m.id as number, m.value);
    else if ("delta" in m) {
      if (!values.has(m.id as number)) throw new Error("a delta needs a value");
      values.set(m.id as number, applyOps(values.get(m.id as number), m.delta as never));
    }
  }
}

export function subscribe(core: Core, ui: number, id: number, topic: Topic): void {
  core.receive(ui, { kind: "subscribe", id, subscribe: topic });
}

export function call(core: Core, ui: number, id: number, name: string, params: unknown): void {
  core.receive(ui, { kind: "call", id, call: name, params });
}

export function answers(emitted: [number, CoreMessage][], id: number): Record<string, unknown> | undefined {
  return emitted.map(([, m]) => m as Record<string, unknown>).find((m) => m.id === id && ("ok" in m || "error" in m));
}

export function v(values: Map<RequestId, unknown>, id: number): any {
  return values.get(id) as any;
}
