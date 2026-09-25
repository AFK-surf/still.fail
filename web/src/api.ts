// Talking to ember's admin API. Types come straight from the server code.
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import type { SlackIdentity } from "../../src/chat/slack.ts";
import type { ConnectInput, LoginJob, Overview, ProfileCheck, ProfileInput, SessionDetail, SessionSummary } from "../../src/admin/types.ts";
import type { SlackAppSettings, SlackGroup } from "../../src/chat/slack-apps.ts";

export type * from "../../src/admin/types.ts";
export type { SlackAppSettings, SlackGroup, SlackIdentity };

export interface SlackAppLinks { settings: string; install: string; appToken: string; oauth: string }
export type SlackAppView =
  | { state: "no_app"; appId: null; links: null; settings: null; groups: SlackGroup[]; error?: string }
  | { state: "no_config_token"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[] }
  | { state: "ok"; appId: string; links: SlackAppLinks; settings: SlackAppSettings; groups: SlackGroup[] }
  | { state: "error"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[]; error: string };

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
  putConnect: (id: string, input: ConnectInput) => request<Overview>("PUT", `/connects/${encodeURIComponent(id)}`, input),
  deleteConnect: (id: string) => request<Overview>("DELETE", `/connects/${encodeURIComponent(id)}`),
  reconnect: (id: string) => request<{ ok: true }>("POST", `/connects/${encodeURIComponent(id)}/reconnect`),
  putProfile: (id: string, input: ProfileInput) => request<Overview>("PUT", `/profiles/${encodeURIComponent(id)}`, input),
  checkProfile: (id: string) => request<ProfileCheck>("POST", `/profiles/${encodeURIComponent(id)}/check`),
  verifySlack: (input: { connect?: string; appToken?: string; botToken?: string }) =>
    request<{ identity: SlackIdentity | null; errors: string[] }>("POST", "/slack/verify", input),
  bindSession: (connect: string, session: string | null, title?: string) =>
    request<{ session: string }>("POST", `/connects/${encodeURIComponent(connect)}/session`, { session, ...(title ? { title } : {}) }),
  setTitle: (key: string, title: string) => request<{ ok: true }>("POST", `/sessions/${encodeURIComponent(key)}/title`, { title }),
  startLogin: (profile: string) => request<{ job: LoginJob }>("POST", `/profiles/${encodeURIComponent(profile)}/login`),
  cancelLogin: (profile: string) => request<{ job: LoginJob | null }>("DELETE", `/profiles/${encodeURIComponent(profile)}/login`),
  loginCode: (profile: string, code: string) => request<{ job: LoginJob }>("POST", `/profiles/${encodeURIComponent(profile)}/login-code`, { code }),
  slackApp: (connect: string) => request<SlackAppView>("GET", `/connects/${encodeURIComponent(connect)}/slack-app`),
  putSlackApp: (connect: string, input: Partial<SlackAppSettings> & { icon?: string }) =>
    request<{ permissionsUpdated: boolean; iconError: string | null; links: SlackAppLinks }>("PUT", `/connects/${encodeURIComponent(connect)}/slack-app`, input),
  configToken: () => request<{ configured: boolean; teamId: string | null }>("GET", "/slack/config-token"),
  putConfigToken: (refreshToken: string) => request<{ configured: boolean; teamId: string | null }>("PUT", "/slack/config-token", { refreshToken }),
  deleteConfigToken: () => request<{ configured: boolean; teamId: string | null }>("DELETE", "/slack/config-token"),
  deleteProfile: (id: string) => request<Overview>("DELETE", `/profiles/${encodeURIComponent(id)}`),
  createAppUrl: (name: string) => request<{ url: string }>("GET", `/slack/create-app-url?name=${encodeURIComponent(name)}`),
};

export const keys = {
  overview: ["overview"] as const,
  sessions: ["sessions"] as const,
  session: (key: string) => ["session", key] as const,
  slackApp: (connect: string) => ["slack-app", connect] as const,
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
    source.addEventListener("login", () => void client.invalidateQueries({ queryKey: keys.overview }));
    // After a reconnect, anything may have changed while we were away.
    source.addEventListener("open", () => void client.invalidateQueries());
    return () => {
      source.close();
      if (timer) clearTimeout(timer);
    };
  }, [enabled, client]);
}
