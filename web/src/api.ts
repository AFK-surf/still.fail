// Talking to ember's admin API. Types come straight from the server code.
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useRef, useState } from "react";
import { useStation } from "./station.tsx";
import type { Transport } from "./transport.ts";
import type { SlackIdentity } from "../../src/chat/slack.ts";
import type { Attachment, ConnectInput, HostInfo, LiveMessage, LivePhase, LiveStep, LoginJob, Overview, ProfileCheck, ProfileInput, ProfileQuota, Quote, SessionDetail, SessionSummary } from "../../src/admin/types.ts";
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

async function call<T>(t: Transport, method: string, path: string, body?: unknown): Promise<T> {
  const { status, data } = await t.request(method, path, body);
  if (status < 200 || status >= 300) throw new ApiError(status, (data as { error?: string })?.error ?? `请求失败（${status}）`);
  return data as T;
}

/** The admin API of one station. */
export function makeApi(t: Transport) {
  const request = <T,>(method: string, path: string, body?: unknown) => call<T>(t, method, path, body);
  return {
  overview: () => request<Overview>("GET", "/overview"),
  host: () => request<HostInfo>("GET", "/host"),
  sessions: () => request<SessionSummary[]>("GET", "/sessions"),
  session: (key: string) => request<SessionDetail>("GET", `/sessions/${encodeURIComponent(key)}`),
  stop: (key: string) => request<{ ok: true }>("POST", `/sessions/${encodeURIComponent(key)}/stop`),
  evict: (key: string) => request<{ ok: true }>("POST", `/sessions/${encodeURIComponent(key)}/evict`),
  putConnect: (id: string, input: ConnectInput) => request<Overview>("PUT", `/connects/${encodeURIComponent(id)}`, input),
  deleteConnect: (id: string) => request<Overview>("DELETE", `/connects/${encodeURIComponent(id)}`),
  reconnect: (id: string) => request<{ ok: true }>("POST", `/connects/${encodeURIComponent(id)}/reconnect`),
  putProfile: (id: string, input: ProfileInput) => request<Overview>("PUT", `/profiles/${encodeURIComponent(id)}`, input),
  refreshQuota: (id: string) => request<ProfileQuota | null>("POST", `/profiles/${encodeURIComponent(id)}/quota`),
  checkProfile: (id: string) => request<ProfileCheck>("POST", `/profiles/${encodeURIComponent(id)}/check`),
  verifySlack: (input: { connect?: string; appToken?: string; botToken?: string }) =>
    request<{ identity: SlackIdentity | null; errors: string[] }>("POST", "/slack/verify", input),
  bindSession: (connect: string, session: string | null, title?: string) =>
    request<{ session: string }>("POST", `/connects/${encodeURIComponent(connect)}/session`, { session, ...(title ? { title } : {}) }),
  openChat: (key: string, title?: string) => request<{ threadTs: string }>("POST", `/sessions/${encodeURIComponent(key)}/chats`, title ? { title } : {}),
  sayToSession: (key: string, text: string, attachments: Attachment[] = [], quotes: Quote[] = []) =>
    request<{ threadTs: string }>("POST", `/sessions/${encodeURIComponent(key)}/messages`, { text, attachments, quotes }),
  /** Starts the session's runtime ahead of a message. */
  warm: (key: string) => request<{ ok: true }>("POST", `/sessions/${encodeURIComponent(key)}/warm`),
  /** A file sent to the session, as a blob for previews. */
  file: async (key: string, name: string) => {
    const r = await t.bytes(`/sessions/${encodeURIComponent(key)}/files?name=${encodeURIComponent(name)}`);
    if (r.status !== 200) throw new ApiError(r.status, "读不到文件");
    return new Blob([r.data as Uint8Array<ArrayBuffer>], { type: r.type });
  },
  /** Puts a file in the session's workspace on the station; send the result with a message. */
  uploadFile: async (key: string, file: File) =>
    request<Attachment>("POST", `/sessions/${encodeURIComponent(key)}/files?name=${encodeURIComponent(file.name)}`, new Uint8Array(await file.arrayBuffer())),
  sayInChat: (threadTs: string, text: string) => request<{ ok: true }>("POST", `/chats/${encodeURIComponent(threadTs)}/messages`, { text }),
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
}

export type Api = ReturnType<typeof makeApi>;

/** The admin API of the station in context. */
export function useApi(): Api {
  const station = useStation();
  return useMemo(() => makeApi(station.transport), [station.transport]);
}

/** Cache keys, per station: two stations' sessions never mix. */
export const keys = {
  overview: (station: string) => ["overview", station] as const,
  sessions: (station: string) => ["sessions", station] as const,
  session: (station: string, key: string) => ["session", station, key] as const,
  slackApp: (station: string, connect: string) => ["slack-app", station, connect] as const,
  host: (station: string) => ["host", station] as const,
};

export function useOverview() {
  const station = useStation();
  // Connection states and process memory change without events; refresh them now and then.
  return useQuery({ queryKey: keys.overview(station.id), queryFn: () => makeApi(station.transport).overview(), refetchInterval: 10_000, enabled: station.online });
}

export function useSessions() {
  const station = useStation();
  return useQuery({ queryKey: keys.sessions(station.id), queryFn: () => makeApi(station.transport).sessions(), enabled: station.online });
}

export function useSession(key: string | undefined) {
  const station = useStation();
  return useQuery({
    queryKey: keys.session(station.id, key ?? ""),
    queryFn: () => makeApi(station.transport).session(key!),
    enabled: Boolean(key) && station.online,
  });
}

/**
 * Follows the station's event stream: a changed session invalidates its list
 * and that session; a config edit invalidates the overview. Bursts are coalesced.
 */
export function useLiveUpdates(enabled: boolean): void {
  const client = useQueryClient();
  const station = useStation();
  useEffect(() => {
    if (!enabled || !station.online) return;
    const dirty = new Set<string>();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const flush = () => {
      timer = undefined;
      void client.invalidateQueries({ queryKey: keys.sessions(station.id) });
      void client.invalidateQueries({ queryKey: keys.overview(station.id) });
      for (const key of dirty) void client.invalidateQueries({ queryKey: keys.session(station.id, key) });
      dirty.clear();
    };
    const stop = station.transport.events((name, data) => {
      if (name === "session") {
        dirty.add((JSON.parse(data) as { key: string }).key);
        timer ??= setTimeout(flush, 400);
      } else {
        void client.invalidateQueries({ queryKey: keys.overview(station.id) });
      }
    }, () => {
      // After a reconnect, anything of this station may have changed.
      for (const kind of ["overview", "sessions", "session", "slack-app"]) void client.invalidateQueries({ queryKey: [kind, station.id] });
    });
    return () => {
      stop();
      if (timer) clearTimeout(timer);
    };
  }, [enabled, client, station]);
}

export function useHost() {
  const station = useStation();
  return useQuery({ queryKey: keys.host(station.id), queryFn: () => makeApi(station.transport).host(), refetchInterval: 15_000, enabled: station.online });
}

/** A step in flight on the page; an ended one stays until the transcript entry that records it arrives. */
export type ShownStep = LiveStep & { ended?: boolean };

/**
 * Follows one session as it runs: new transcript entries are appended to the
 * cached session (no refetch), and the steps the runtime is streaming are
 * returned, growing delta by delta.
 */
/** Where the turn stands with the model, since when (this browser's clock). */
export interface ShownPhase { phase: LivePhase; since: number }

export function useLiveSession(key: string | undefined): { steps: ShownStep[]; phase: ShownPhase | null } {
  const client = useQueryClient();
  const station = useStation();
  const [steps, setSteps] = useState<ShownStep[]>([]);
  const [phase, setPhase] = useState<ShownPhase | null>(null);
  const queryKey = useMemo(() => (key ? keys.session(station.id, key) : null), [station.id, key]);
  const known = useRef(0);
  useEffect(() => {
    if (!key || !queryKey || !station.online) return;
    setSteps([]);
    setPhase(null);
    const length = () => client.getQueryData<SessionDetail>(queryKey)?.transcript?.timeline.length ?? 0;
    const stop = station.transport.stream(
      () => `/sessions/${encodeURIComponent(key)}/live?from=${(known.current = length())}`,
      (_name, data) => {
        const message = JSON.parse(data) as LiveMessage;
        if (message.type === "timeline") {
          const detail = client.getQueryData<SessionDetail>(queryKey);
          if (!detail?.transcript) {
            // The session's first transcript: fetch it whole once.
            void client.invalidateQueries({ queryKey });
          } else {
            const have = detail.transcript.timeline;
            if (message.start > have.length) void client.invalidateQueries({ queryKey }); // a gap: start over
            else {
              const timeline = [...have.slice(0, message.start), ...message.entries];
              client.setQueryData<SessionDetail>(queryKey, { ...detail, transcript: { ...detail.transcript, timeline, usage: message.usage } });
            }
          }
          if (message.entries.length) setSteps((all) => all.filter((s) => !s.ended));
        } else if (message.type === "steps") {
          setSteps(message.steps);
          setPhase(message.phase ? { phase: message.phase.phase, since: Date.now() - message.phase.elapsedMs } : null);
        } else if (message.type === "clear") {
          setSteps([]);
          setPhase(null);
        } else {
          const e = message.event;
          if (e.kind === "phase") {
            setPhase({ phase: e.phase, since: Date.now() });
            return;
          }
          const apply = (all: ShownStep[]): ShownStep[] => {
            if (e.kind === "start") {
              return [...all.filter((s) => s.id !== e.id), {
                id: e.id, step: e.step, text: "", input: e.input ?? "", output: "", startedAt: Date.now(),
                ...(e.tool ? { tool: e.tool } : {}), ...(e.subagent ? { subagent: true } : {}), ...(e.parent ? { parent: e.parent } : {}),
              }];
            }
            if (e.kind === "delta") return all.map((s) => (s.id === e.id ? { ...s, [e.field]: s[e.field] + e.text } : s));
            return all.map((s) => (s.id === e.id ? { ...s, ended: true } : s));
          };
          setSteps(apply);
        }
      },
      () => {},
    );
    return () => stop();
    // The station object is rebuilt on every workspace refresh; follow only what identifies the stream.
  }, [key, queryKey, station.id, station.online, station.transport, client]);
  return { steps, phase };
}
