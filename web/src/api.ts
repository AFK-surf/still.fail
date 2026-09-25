// Talking to ember's admin API. Types come straight from the server code.
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import type { BotInput, Overview, ProfileInput, SessionDetail, SessionSummary } from "../../src/admin/types.ts";

export type * from "../../src/admin/types.ts";

export class ApiError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const response = await fetch(`/admin/api${path}`, {
    method,
    credentials: "same-origin",
    headers: body === undefined ? {} : { "content-type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await response.json().catch(() => ({})) as { error?: string };
  if (!response.ok) throw new ApiError(response.status, data.error ?? `请求失败（${response.status}）`);
  return data as T;
}

export const api = {
  stop: (key: string) => request<{ ok: true }>("POST", `/sessions/${encodeURIComponent(key)}/stop`),
  evict: (key: string) => request<{ ok: true }>("POST", `/sessions/${encodeURIComponent(key)}/evict`),
  putBot: (id: string, input: BotInput) => request<Overview>("PUT", `/bots/${encodeURIComponent(id)}`, input),
  deleteBot: (id: string) => request<Overview>("DELETE", `/bots/${encodeURIComponent(id)}`),
  reconnect: (id: string) => request<{ ok: true }>("POST", `/bots/${encodeURIComponent(id)}/reconnect`),
  putProfile: (id: string, input: ProfileInput) => request<Overview>("PUT", `/profiles/${encodeURIComponent(id)}`, input),
  deleteProfile: (id: string) => request<Overview>("DELETE", `/profiles/${encodeURIComponent(id)}`),
  createAppUrl: (name: string) => request<{ url: string }>("GET", `/slack/create-app-url?name=${encodeURIComponent(name)}`),
};

export const keys = {
  overview: ["overview"] as const,
  sessions: ["sessions"] as const,
  session: (key: string) => ["session", key] as const,
};

export function useOverview() {
  // Connection states and process memory change without events; refresh them now and then.
  return useQuery({ queryKey: keys.overview, queryFn: () => request<Overview>("GET", "/overview"), refetchInterval: 10_000 });
}

export function useSessions() {
  return useQuery({ queryKey: keys.sessions, queryFn: () => request<SessionSummary[]>("GET", "/sessions") });
}

export function useSession(key: string | undefined) {
  return useQuery({
    queryKey: keys.session(key ?? ""),
    queryFn: () => request<SessionDetail>("GET", `/sessions/${encodeURIComponent(key!)}`),
    enabled: Boolean(key),
  });
}

/**
 * Follows ember's event stream: a changed session invalidates the list and that
 * session; a config edit invalidates the overview. Bursts are coalesced.
 */
export function useLiveUpdates(enabled: boolean): void {
  const client = useQueryClient();
  useEffect(() => {
    if (!enabled) return;
    const source = new EventSource("/admin/api/events");
    const dirty = new Set<string>();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const flush = () => {
      timer = undefined;
      void client.invalidateQueries({ queryKey: keys.sessions });
      void client.invalidateQueries({ queryKey: keys.overview });
      for (const key of dirty) void client.invalidateQueries({ queryKey: keys.session(key) });
      dirty.clear();
    };
    source.addEventListener("session", (event) => {
      dirty.add((JSON.parse((event as MessageEvent<string>).data) as { key: string }).key);
      timer ??= setTimeout(flush, 400);
    });
    source.addEventListener("config", () => void client.invalidateQueries({ queryKey: keys.overview }));
    // After a reconnect, anything may have changed while we were away.
    source.addEventListener("open", () => void client.invalidateQueries());
    return () => {
      source.close();
      if (timer) clearTimeout(timer);
    };
  }, [enabled, client]);
}
