// A station's data, through the client core (docs/client-core.md): screens
// subscribe to the views the core puts together, writes go through
// `station.request` and the core refreshes whatever they touch. Types come
// from client/shapes (core/shapes.ts); what is only sent to a station is
// declared here.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { useCall, useTopic, useTopics, type TopicState } from "./core/react.ts";
import { CoreError } from "./core/client.ts";
import { scopeOf, useOnlyMine, useStation, type Me } from "./station.tsx";
import type { Attachment, ChatsView, Quote, ChatView, ConnectsView, HistoryView, Host, Live, Overview, Session, Stamp, StationView, StatusView, ChatThread } from "./core/shapes.ts";
import type { AccessKind, ConnectMode, LoginJob, ProfileCheck, Quota, RuntimeKind, SlackAppLinks, SlackIdentity } from "./core/shapes.ts";

export type { TopicState };
export { CoreError };

// ── what is sent to a station (its admin API's inputs) ──

/**
 * An item of a station's archive (GET /chats?archived=1), as the station sends it: its sidebar row with when it was
 * archived, by a person or by the station for idling, and whether the chat went alone (its agents still at work) or
 * with its session.
 */
export interface ArchivedChat {
  id: string;
  session: string;
  thread: number | null;
  title: string;
  last: { text: string | null } | null;
  lastActiveAt: number;
  archived?: { at: number; by: "manual" | "auto"; alone: boolean };
}

export type ConnectKind = "slack";

/** POST /connects, PUT /connects/:id. Blank or missing tokens keep the stored ones. */
export interface ConnectInput {
  enabled?: boolean;
  kind?: ConnectKind;
  mode?: ConnectMode;
  requireMention?: boolean;
  bind?: { runtime?: RuntimeKind; model?: string; effort?: string; profile?: string | null };
  /** `install`: an app installed through Slack's OAuth (its state), whose bot token the station has. */
  slack?: { appToken?: string; botToken?: string; appId?: string; install?: string };
  /** Hands the connect to someone else (an email). Owners, admins, the station itself, or the current owner. */
  owner?: { id: string; name?: string };
}

/** PUT /profiles/:id. env: a string sets, null removes, an omitted key is kept. A blank access key keeps the stored one. */
export interface ProfileInput {
  name?: string;
  runtime?: RuntimeKind;
  access?: { kind: AccessKind; key?: string };
  home?: string;
  model?: string;
  /** Replaces the enabled models. */
  models?: string[];
  env?: Record<string, string | null>;
  /** Claude Code: a message to a running turn moves what it waits on to the background first. */
  backgroundOnMessage?: boolean;
}

/** The groups of scopes and events a Slack app made here asks for (mesh/app/src/chat/slack_apps.rs). */
export type SlackGroup = "base" | "public" | "dm" | "customize" | "files" | "reactions" | "channels" | "people" | "extras";

/** A Slack app as its settings form shows it. */
export interface SlackAppSettings {
  name: string;
  displayName: string;
  description: string;
  longDescription: string;
  backgroundColor: string;
  groups: Record<SlackGroup, boolean>;
}

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

/** What the core is waiting on, when it is worth saying: something slow, a connection down (`state` absent: nothing). */
export function useStatus(): StatusView | undefined {
  return useTopic<StatusView>(STATUS).value;
}
const STATUS = { topic: "status" } as const;

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

/** Loads the page of an agent's execution history before what it shows (the core has its latest entries first). */
export function useHistoryOlder(station: string, key: string): () => Promise<{ more: boolean }> {
  const call = useCall();
  return useCallback(() => call("history.older", { station, key }) as Promise<{ more: boolean }>, [call, station, key]);
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
  /** A file sent to the session, as a blob for previews; `thumb`: an image as a chat shows it (its thumbnail, where the station keeps one). */
  /** `onProgress`: bytes so far and the whole size (null when the station does not say) as a whole file comes. */
  file(key: string, name: string, thumb?: boolean, onProgress?: (got: FileProgress) => void): Promise<Blob>;
}

/** The whole file as base64, the protocol's form for bytes. */
/** Bytes from base64: natively where the browser can (a chat's images are megabytes; decoding them char by char held up frames). */
/** How much of a file has come. */
export interface FileProgress { loaded: number; total: number | null }

function fromBase64(text: string): Uint8Array<ArrayBuffer> {
  const native = (Uint8Array as unknown as { fromBase64?: (s: string) => Uint8Array<ArrayBuffer> }).fromBase64;
  return native ? native(text) : Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
}

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
    file: async (key, name, thumb = false, onProgress) => {
      const { type, bytes } = await call("station.file", { station, key, name, ...(thumb ? { thumb } : {}), ...(onProgress ? { progress: true } : {}) },
        onProgress && ((got) => onProgress(got as FileProgress))) as { type: string; bytes: string };
      return new Blob([fromBase64(bytes)], { type });
    },
  }), [call, station]);
}

/** A session the machine's own Claude Code or Codex kept, run in a terminal. */
export interface MachineSession {
  runtime: RuntimeKind;
  id: string;
  /** The directory it ran in. */
  cwd: string;
  title: string | null;
  /** What was asked first. */
  first: string | null;
  /** The model it last ran (a station from before this does not say). */
  model?: string | null;
  updatedAt: number;
  size: number;
  /** The station's session already going on with it. */
  session: string | null;
}

/** Something said in one of the machine's sessions: by the person, else by its agent; when, in ms. */
export interface MachineSaid { person: boolean; text: string; at: number | null }

/** The admin API of one station, by what each call does. */

export function stationApi(t: StationCall) {
  const { request } = t;
  const at = (id: string) => encodeURIComponent(id);
  return {
    stop: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/stop`),
    /** A chat into the archive or back: its thread (with its session when it is that session's own), or an agent with no chat yet. */
    archive: async (of: { thread?: number | null; session: string }, archived: boolean) => {
      const method = archived ? "POST" : "DELETE";
      const bySession = () => request<unknown>(method, `/sessions/${at(of.session)}/archive`);
      if (of.thread == null) return bySession();
      try {
        return await request<unknown>(method, `/threads/${of.thread}/archive`);
      } catch (error) {
        // A station from before chats were archived by themselves: its session instead, as it always was.
        if (error instanceof CoreError && error.status === 404) return bySession();
        throw error;
      }
    },
    /** The archive's items; a station from before it answers its shown ones (none say `archived`), so none. */
    archivedChats: async () => (await request<ArchivedChat[]>("GET", "/chats?archived=1")).filter((row) => row.archived),
    deleteSession: (key: string) => request<{ ok: true }>("DELETE", `/sessions/${at(key)}`),
    evict: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/evict`),
    putConnect: (id: string, input: ConnectInput) => request<Overview>("PUT", `/connects/${at(id)}`, input),
    deleteConnect: (id: string) => request<Overview>("DELETE", `/connects/${at(id)}`),
    reconnect: (id: string) => request<{ ok: true }>("POST", `/connects/${at(id)}/reconnect`),
    putProfile: (id: string, input: ProfileInput) => request<Overview>("PUT", `/profiles/${at(id)}`, input),
    refreshQuota: (id: string) => request<Quota | null>("POST", `/profiles/${at(id)}/quota`),
    checkProfile: (id: string) => request<ProfileCheck>("POST", `/profiles/${at(id)}/check`),
    verifySlack: (input: { connect?: string; install?: string; appToken?: string; botToken?: string }) =>
      request<{ identity: SlackIdentity | null; errors: string[] }>("POST", "/slack/verify", input),
    bindSession: (connect: string, session: string | null, title?: string) =>
      request<{ session: string }>("POST", `/connects/${at(connect)}/session`, { session, ...(title ? { title } : {}) }),
    /** Starts the session's runtime ahead of a message. */
    warm: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/warm`),
    /** What an inline visualization (Viz.tsx) kept: by the session that sent its file and the file's path. */
    widgetState: (key: string, path: string) => request<{ state: unknown }>("GET", `/sessions/${at(key)}/widget-state?path=${encodeURIComponent(path)}`),
    setWidgetState: (key: string, path: string, state: unknown) => request<{ ok: true }>("PUT", `/sessions/${at(key)}/widget-state`, { path, state }),
    /** A new chat: its session and its thread, made with its first message. */
    newChat: (input: { runtime: RuntimeKind; profile?: string; model?: string; effort?: string }) => request<{ key: string; thread: ChatThread }>("POST", "/sessions", input),
    /** Sessions the machine's own Claude Code and Codex kept (in a terminal); a station from before them answers 404. */
    machineSessions: () => request<{ sessions: MachineSession[] }>("GET", "/machine-sessions"),
    /** One of them to look at first: what was said in it, the latest `limit` of `total`. */
    machineSession: (runtime: RuntimeKind, id: string, limit = 200) =>
      request<{ session: MachineSession; total: number; said: MachineSaid[] }>("GET", `/machine-sessions/${at(runtime)}/${at(id)}?limit=${limit}`),
    /** A chat going on with one of them (the one already going on with it, if any). */
    continueMachineSession: (runtime: RuntimeKind, id: string) => request<{ key: string; thread: ChatThread }>("POST", "/machine-sessions", { runtime, id }),
    file: t.file,
    uploadFile: t.upload,
    startLogin: (profile: string) => request<{ job: LoginJob }>("POST", `/profiles/${at(profile)}/login`),
    cancelLogin: (profile: string) => request<{ job: LoginJob | null }>("DELETE", `/profiles/${at(profile)}/login`),
    loginCode: (profile: string, code: string) => request<{ job: LoginJob }>("POST", `/profiles/${at(profile)}/login-code`, { code }),
    /** A subscription signed in before its profile exists; the station makes the profile when it succeeds. */
    newLogin: (runtime: RuntimeKind) => request<{ id: string; job: LoginJob }>("POST", "/logins", { runtime }),
    newLoginCode: (id: string, code: string) => request<{ job: LoginJob }>("POST", `/logins/${at(id)}/code`, { code }),
    dropLogin: (id: string) => request<{ ok: true }>("DELETE", `/logins/${at(id)}`),
    /** A profile on the machine's own login of `runtime` (one kept in a file). */
    useMachineLogin: (runtime: RuntimeKind) => request<{ id: string; overview: Overview }>("POST", "/profiles/machine", { runtime }),
    /** A keyed profile, made only once its key is checked. */
    addProfile: (input: { runtime?: RuntimeKind; access: { kind: AccessKind; key?: string } }) => request<{ id: string; overview: Overview }>("POST", "/profiles", input),
    slackApp: (connect: string) => request<SlackAppView>("GET", `/connects/${at(connect)}/slack-app`),
    putSlackApp: (connect: string, input: Partial<SlackAppSettings> & { icon?: string }) =>
      request<{ permissionsUpdated: boolean; iconError: string | null; links: SlackAppLinks }>("PUT", `/connects/${at(connect)}/slack-app`, input),
    /** Makes a Slack app with the workspace's configuration token (ember's manifest, Socket Mode on), for a connect to come. */
    /** `install`: Slack's install link, when the app is installed through OAuth (a station in ember cloud); `state` names it. */
    /** The app is kept on the station, waiting for its connect (the overview's `slackApps`); this says which it is. */
    makeSlackApp: (input: { team: string; settings: SlackAppSettings; icon?: string }) => request<{ appId: string; iconError: string | null }>("POST", "/slack/apps", input),
    /** Drops an app made here from the waiting ones; it stays in Slack. */
    dropSlackApp: (appId: string) => request<Overview>("DELETE", `/slack/apps/${at(appId)}`),
    /** Hands Slack's install code to the station that made the app. */
    slackInstalled: (code: string, state: string) => request<{ team: string | null }>("POST", "/slack/installs", { code, state }),
    /** A new Slack connect from its tokens: the station names it as its bot is named in Slack. */
    createConnect: (input: ConnectInput) => request<{ id: string; overview: Overview }>("POST", "/connects", input),
    /** How a session runs from its next turn on: its profile, model, effort (null: the runtime's default). */
    sessionSettings: (key: string, input: { profile?: string | null; model?: string | null; effort?: string | null }) => request<{ ok: true }>("POST", `/sessions/${at(key)}/settings`, input),
    /** Adds a Slack workspace's app configuration token; answers which workspace it is. */
    addConfigToken: (refreshToken: string) => request<{ teamId: string; overview: Overview }>("POST", "/slack/config-tokens", { refreshToken }),
    removeConfigToken: (team: string) => request<Overview>("DELETE", `/slack/config-tokens/${at(team)}`),
    deleteProfile: (id: string) => request<Overview>("DELETE", `/profiles/${at(id)}`),
    /** "这是我" (bound) or "不是我" on a Slack user: the station takes them for the viewer, or no longer. */
    slackIdentity: (user: string, bound: boolean) => request<Overview>(bound ? "PUT" : "DELETE", `/me/slack/${at(user)}`),
    createAppUrl: (name: string) => request<{ url: string }>("GET", `/slack/create-app-url?name=${encodeURIComponent(name)}`),
  };
}

export type Api = ReturnType<typeof stationApi>;

/**
 * A chat's calls, by its thread (or, for a chat made here, the key the core gave it: `chat.create`). Sending: the
 * message shows at once from the core's outbox; a failed one can be sent again or dropped. `older` loads the page before the messages shown; `read` records how far the viewer has read.
 * The station is the one in context, or `address` (a page outside its StationContext, the phone's ChatHost).
 */
export function useChatSend(address?: string) {
  const call = useCall();
  const inContext = useStation().address;
  const station = address ?? inContext;
  return useMemo(() => ({
    send: (to: ChatTo, text: string, attachments: Attachment[], quotes: Quote[]) => call("chat.send", { station, ...chatTo(to), text, attachments, quotes }),
    retry: (to: ChatTo, id: string) => call("chat.retry", { station, ...chatTo(to), id }),
    discard: (to: ChatTo, id: string) => call("chat.discard", { station, ...chatTo(to), id }),
    /** A new chat: there at once under the key answered (its page, its row); the station makes it behind it. */
    create: (input: { runtime: RuntimeKind; profile?: string; model?: string; effort?: string }) => call("chat.create", { station, ...input }) as Promise<{ key: string }>,
    older: (thread: number) => call("chat.older", { station, thread }) as Promise<{ more: boolean }>,
    read: (thread: number, seq: number) => call("chat.read", { station, thread, seq }),
  }), [call, station]);
}

/** Where a message goes: a chat's thread, or the key of a chat made here (`chat.create`), made by its station or not. */
export type ChatTo = number | string;
const chatTo = (to: ChatTo) => (typeof to === "number" ? { thread: to } : { session: to });

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

