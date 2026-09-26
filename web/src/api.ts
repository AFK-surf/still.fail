// A station's data, through the client core (docs/client-core.md): screens
// subscribe to the views the core puts together, writes go through
// `station.request` and the core refreshes whatever they touch. Types come
// straight from the server code.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { useCall, useTopic, useTopics, type TopicState } from "./core/react.ts";
import { CoreError } from "./core/client.ts";
import { scopeOf, useOnlyMine, useStation, type Me } from "./station.tsx";
import type { SlackIdentity } from "../../src/chat/slack.ts";
import type { Attachment, ChatsView, Quote, ChatView, ConnectsView, HistoryView, Host, Live, Overview, Session, Stamp, StationView, ChatThread } from "./core/shapes.ts";
// What is sent to a station, and what its calls answer: its own declarations.
import type * as Station from "../../src/admin/types.ts";
import type { ConnectInput, ProfileInput } from "../../src/admin/types.ts";
import type { AccessKind, RuntimeKind } from "./core/shapes.ts";
import type { SlackAppSettings, SlackGroup } from "../../src/chat/slack-apps.ts";

export type { ConnectInput, ConnectKind, ProfileInput } from "../../src/admin/types.ts";
export type { SlackAppSettings, SlackGroup, SlackIdentity, TopicState };
export { CoreError };

export interface SlackAppLinks { settings: string; install: string; appToken: string; oauth: string }
export type SlackAppView =
  | { state: "no_app"; appId: null; links: null; settings: null; groups: SlackGroup[]; error?: string }
  | { state: "no_config_token"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[] }
  | { state: "ok"; appId: string; links: SlackAppLinks; settings: SlackAppSettings; groups: SlackGroup[] }
  | { state: "error"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[]; error: string };

// ── what the core gives: generated from client/shapes (core/shapes.ts), nothing hand-written ──

export type * from "./core/shapes.ts";

/** A time of anything the core sent, in words, by its field (for what ember cloud sends, which has no shape yet). */
export function stamp(of: object, field: string): Stamp | undefined {
  return (of as { time?: Record<string, Stamp> }).time?.[field];
}

export function useChats(scope: string, mine: boolean): TopicState<ChatsView> {
  return useTopic<ChatsView>({ topic: "chats", scope, mine });
}

export function useStations(scope: string): TopicState<StationView[]> {
  return useTopic<StationView[]>({ topic: "stations", scope });
}

export function useConnects(scope: string, mine = false): TopicState<ConnectsView> {
  return useTopic<ConnectsView>({ topic: "connects", scope, mine });
}

/** An item's page: its chat (`thread`), or its agent before it has one (`session`). */
export function useChat(station: string, of: { thread: number } | { session: string }): TopicState<ChatView> {
  return useTopic<ChatView>({ topic: "chat", station, ...of });
}

export function useHistory(station: string, key: string): TopicState<HistoryView> {
  return useTopic<HistoryView>({ topic: "history", station, key });
}

/** Each session's live topic, by key: the agents of a chat as they run. */
export function useLives(station: string, keys: string[]): ReadonlyMap<string, Live> {
  const states = useTopics<Live>(keys.map((key) => ({ topic: "live", station, key })));
  return useMemo(() => new Map(keys.flatMap((key, i) => (states[i]?.value ? [[key, states[i]!.value!] as const] : []))), [states, keys.join("\n")]);
}

// One station's own topics, for its settings pages.

export function useOverview(station: string): TopicState<Overview> {
  return useTopic<Overview>({ topic: "overview", station });
}

export function useSessions(station: string): TopicState<Session[]> {
  return useTopic<Session[]>({ topic: "sessions", station });
}

/** Every thread of a station, latest message first. */
export function useThreads(station: string): TopicState<ChatThread[]> {
  return useTopic<ChatThread[]>({ topic: "threads", station });
}

export function useHost(station: string): TopicState<Host> {
  return useTopic<Host>({ topic: "host", station });
}


// ── calls ───────────────────────────────────────────────────────────────

export interface StationCall {
  request<T>(method: string, path: string, body?: unknown): Promise<T>;
  /** Puts a file on the station, in no chat yet; a message that sends it takes it into its chat. */
  upload(file: File): Promise<Attachment>;
  /** A file sent to the session, as a blob for previews. */
  file(key: string, name: string): Promise<Blob>;
}

/** The whole file as base64, the protocol's form for bytes. */
function toBase64(file: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve((reader.result as string).slice((reader.result as string).indexOf(",") + 1));
    reader.onerror = () => reject(reader.error ?? new Error("读不了这个文件"));
    reader.readAsDataURL(file);
  });
}

export function useStationCall(station: string): StationCall {
  const call = useCall();
  return useMemo(() => ({
    request: <T,>(method: string, path: string, body?: unknown) =>
      call("station.request", { station, method, path, ...(body === undefined ? {} : { body }) }) as Promise<T>,
    upload: async (file) => {
      const saved = await call("station.upload", { station, name: file.name, bytes: await toBase64(file) }) as Attachment;
      // An image's size travels with it, so every page can hold its place before it loads.
      if (file.type.startsWith("image/")) {
        try {
          const bitmap = await createImageBitmap(file);
          const size = { width: bitmap.width, height: bitmap.height };
          bitmap.close();
          return { ...saved, ...size };
        } catch {
          // not decodable here; shown in a fixed box instead
        }
      }
      return saved;
    },
    file: async (key, name) => {
      const { type, bytes } = await call("station.file", { station, key, name }) as { type: string; bytes: string };
      return new Blob([Uint8Array.from(atob(bytes), (c) => c.charCodeAt(0))], { type });
    },
  }), [call, station]);
}

/** The admin API of one station, by what each call does. */
export interface MadeSlackApp { appId: string; links: SlackAppLinks; install: string | null; state: string | null; iconError: string | null }

export function stationApi(t: StationCall) {
  const { request } = t;
  const at = (id: string) => encodeURIComponent(id);
  return {
    stop: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/stop`),
    evict: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/evict`),
    putConnect: (id: string, input: ConnectInput) => request<Station.Overview>("PUT", `/connects/${at(id)}`, input),
    deleteConnect: (id: string) => request<Station.Overview>("DELETE", `/connects/${at(id)}`),
    reconnect: (id: string) => request<{ ok: true }>("POST", `/connects/${at(id)}/reconnect`),
    putProfile: (id: string, input: ProfileInput) => request<Station.Overview>("PUT", `/profiles/${at(id)}`, input),
    refreshQuota: (id: string) => request<Station.ProfileQuota | null>("POST", `/profiles/${at(id)}/quota`),
    checkProfile: (id: string) => request<Station.ProfileCheck>("POST", `/profiles/${at(id)}/check`),
    verifySlack: (input: { connect?: string; install?: string; appToken?: string; botToken?: string }) =>
      request<{ identity: SlackIdentity | null; errors: string[] }>("POST", "/slack/verify", input),
    bindSession: (connect: string, session: string | null, title?: string) =>
      request<{ session: string }>("POST", `/connects/${at(connect)}/session`, { session, ...(title ? { title } : {}) }),
    /** Starts the session's runtime ahead of a message. */
    warm: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/warm`),
    /** A new chat: its session and its thread, made with its first message. */
    newChat: (input: { runtime: RuntimeKind; profile?: string; model?: string; effort?: string }) => request<{ key: string; thread: Station.ThreadView }>("POST", "/sessions", input),
    file: t.file,
    uploadFile: t.upload,
    startLogin: (profile: string) => request<{ job: Station.LoginJob }>("POST", `/profiles/${at(profile)}/login`),
    cancelLogin: (profile: string) => request<{ job: Station.LoginJob | null }>("DELETE", `/profiles/${at(profile)}/login`),
    loginCode: (profile: string, code: string) => request<{ job: Station.LoginJob }>("POST", `/profiles/${at(profile)}/login-code`, { code }),
    /** A subscription signed in before its profile exists; the station makes the profile when it succeeds. */
    newLogin: (runtime: RuntimeKind) => request<{ id: string; job: Station.LoginJob }>("POST", "/logins", { runtime }),
    newLoginCode: (id: string, code: string) => request<{ job: Station.LoginJob }>("POST", `/logins/${at(id)}/code`, { code }),
    dropLogin: (id: string) => request<{ ok: true }>("DELETE", `/logins/${at(id)}`),
    /** A keyed profile, made only once its key is checked. */
    addProfile: (input: { runtime?: RuntimeKind; access: { kind: AccessKind; key?: string } }) => request<{ id: string; overview: Station.Overview }>("POST", "/profiles", input),
    slackApp: (connect: string) => request<SlackAppView>("GET", `/connects/${at(connect)}/slack-app`),
    putSlackApp: (connect: string, input: Partial<SlackAppSettings> & { icon?: string }) =>
      request<{ permissionsUpdated: boolean; iconError: string | null; links: SlackAppLinks }>("PUT", `/connects/${at(connect)}/slack-app`, input),
    /** Makes a Slack app with the workspace's configuration token (ember's manifest, Socket Mode on), for a connect to come. */
    /** `install`: Slack's install link, when the app is installed through OAuth (a station in ember cloud); `state` names it. */
    makeSlackApp: (input: { team: string; settings: SlackAppSettings; icon?: string }) => request<MadeSlackApp>("POST", "/slack/apps", input),
    /** Hands Slack's install code to the station that made the app. */
    slackInstalled: (code: string, state: string) => request<{ team: string | null }>("POST", "/slack/installs", { code, state }),
    /** A new Slack connect from its tokens: the station names it as its bot is named in Slack. */
    createConnect: (input: ConnectInput) => request<{ id: string; overview: Station.Overview }>("POST", "/connects", input),
    /** How a session runs from its next turn on: its profile, model, effort (null: the runtime's default). */
    sessionSettings: (key: string, input: { profile?: string | null; model?: string | null; effort?: string | null }) => request<{ ok: true }>("POST", `/sessions/${at(key)}/settings`, input),
    /** Adds a Slack workspace's app configuration token; answers which workspace it is. */
    addConfigToken: (refreshToken: string) => request<{ teamId: string; overview: Station.Overview }>("POST", "/slack/config-tokens", { refreshToken }),
    removeConfigToken: (team: string) => request<Station.Overview>("DELETE", `/slack/config-tokens/${at(team)}`),
    deleteProfile: (id: string) => request<Station.Overview>("DELETE", `/profiles/${at(id)}`),
    /** "这是我" (bound) or "不是我" on a Slack user: the station takes them for the viewer, or no longer. */
    slackIdentity: (user: string, bound: boolean) => request<Station.Overview>(bound ? "PUT" : "DELETE", `/me/slack/${at(user)}`),
    createAppUrl: (name: string) => request<{ url: string }>("GET", `/slack/create-app-url?name=${encodeURIComponent(name)}`),
  };
}

export type Api = ReturnType<typeof stationApi>;

/**
 * A chat's calls, by its thread. Sending: the message shows at once from the core's outbox; a failed one can be
 * sent again or dropped. `older` loads the page before the messages shown; `read` records how far the viewer has read.
 */
export function useChatSend() {
  const call = useCall();
  const station = useStation().address;
  return useMemo(() => ({
    send: (thread: number, text: string, attachments: Attachment[], quotes: Quote[]) => call("chat.send", { station, thread, text, attachments, quotes }),
    retry: (thread: number, id: string) => call("chat.retry", { station, thread, id }),
    discard: (thread: number, id: string) => call("chat.discard", { station, thread, id }),
    older: (thread: number) => call("chat.older", { station, thread }) as Promise<{ more: boolean }>,
    read: (thread: number, seq: number) => call("chat.read", { station, thread, seq }),
  }), [call, station]);
}

/** The admin API of the station in context. */
export function useApi(): Api {
  const call = useStationCall(useStation().address);
  return useMemo(() => stationApi(call), [call]);
}

/** A call in progress and how the last one went, for a button that makes it. */
export interface Action<A extends unknown[], T> {
  /** Resolves to the result, or undefined when it failed (`error` says why). */
  run(...args: A): Promise<T | undefined>;
  busy: boolean;
  error: Error | null;
  data: T | undefined;
  /** What the call in progress (or the last one) was made with. */
  args: A | undefined;
}

export function useAction<A extends unknown[], T>(fn: (...args: A) => Promise<T>, onDone?: (result: T, ...args: A) => void): Action<A, T> {
  const latest = useRef({ fn, onDone });
  latest.current = { fn, onDone };
  const [state, setState] = useState<{ busy: boolean; error: Error | null; data: T | undefined; args: A | undefined }>({ busy: false, error: null, data: undefined, args: undefined });
  const run = useCallback(async (...args: A) => {
    setState((s) => ({ ...s, busy: true, error: null, args }));
    try {
      const data = await latest.current.fn(...args);
      setState({ busy: false, error: null, data, args });
      latest.current.onDone?.(data, ...args);
      return data;
    } catch (error) {
      setState((s) => ({ ...s, busy: false, error: error instanceof Error ? error : new Error(String(error)) }));
      return undefined;
    }
  }, []);
  return { run, ...state };
}

