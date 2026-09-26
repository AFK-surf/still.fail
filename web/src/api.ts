// A station's data, through the client core (docs/client-core.md): screens
// subscribe to the views the core puts together, writes go through
// `station.request` and the core refreshes whatever they touch. Types come
// straight from the server code.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { useCall, useTopic, useTopics, type TopicState } from "./core/react.ts";
import { CoreError } from "./core/client.ts";
import { scopeOf, useOnlyMine, useStation, type Me } from "./station.tsx";
import type { SlackIdentity } from "../../src/chat/slack.ts";
import type {
  Attachment, ConnectInput, ConnectView, Creator, HostInfo, LivePhase, LiveStep, LoginJob, MessageView, Overview, ProfileCheck, ProfileInput, ProfileQuota, ProfileView, Quote, RuntimeKind,
  SessionSummary, ThreadView, TimelineEntry, TranscriptUsage, TurnRecord,
} from "../../src/admin/types.ts";
import type { SlackAppSettings, SlackGroup } from "../../src/chat/slack-apps.ts";

export type * from "../../src/admin/types.ts";
export type { SlackAppSettings, SlackGroup, SlackIdentity, TopicState };
export { CoreError };

export interface SlackAppLinks { settings: string; install: string; appToken: string; oauth: string }
export type SlackAppView =
  | { state: "no_app"; appId: null; links: null; settings: null; groups: SlackGroup[]; error?: string }
  | { state: "no_config_token"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[] }
  | { state: "ok"; appId: string; links: SlackAppLinks; settings: SlackAppSettings; groups: SlackGroup[] }
  | { state: "error"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[]; error: string };

// ── views ───────────────────────────────────────────────────────────────

/** A station's mesh link as the core holds it. */
export interface LinkView { state: "connecting" | "online" | "offline" | "error"; message?: string | null }

/** An agent of a chat as the sidebar has it: what it runs on and where its work stands (what `sessionStatus` reads). */
export type ChatAgent = Pick<SessionSummary, "key" | "runtime" | "model" | "effort" | "process" | "pending" | "lastTurn">;
/**
 * A chat in the sidebar: a thread (a Slack thread or a chat on ember's page), what it is called, its agents and
 * people, the last thing said, whether the viewer has read everything in it, and the connect a Slack thread came through.
 */
export interface ChatItem {
  station: string; stationName: string;
  thread: Pick<ThreadView, "id" | "surface" | "channel" | "channelName" | "threadTs" | "title" | "createdAt" | "creator">;
  title: string;
  agents: ChatAgent[];
  people: Creator[];
  /** Its text cut to 200 characters. */
  last: Pick<MessageView, "seq" | "authorKind" | "author" | "authorName" | "text" | "createdAt" | "deletedAt"> | null;
  unread: boolean;
  lastActiveAt: number;
  connect: ConnectView | null;
}
export interface ChatDay { daysAgo: number; at: number; items: ChatItem[] }
export interface ChatsView {
  me: Me;
  stations: { station: string; id: string; name: string; state: "online" | "connecting" | "offline" | "error"; message: string | null }[];
  /** An online station has not answered yet. */
  loading: boolean;
  days: ChatDay[];
}

export interface StationView {
  station: string; id: string; name: string;
  online: boolean; lastSeen: number | null; version: string | null;
  link: LinkView;
  overview: Overview | null;
  host: HostInfo | null;
  /** Runtimes with an enabled model, and those models. */
  runtimes: { runtime: RuntimeKind; models: string[] }[];
}

export interface ConnectsView { items: { station: string; stationName: string; connect: ConnectView }[]; loading: boolean }

/** A message sent from here that the chat does not show yet; `seq` once the station has it. */
export interface OutboxMessage {
  id: string; text: string; attachments: Attachment[]; quotes: Quote[]; createdAt: number;
  state: "sending" | "failed"; error: string | null; seq?: number;
}

/** An agent taking part in a chat: its session, the connect that started it, its profile, its turns and every thread it is in. */
export interface ChatAgentView { session: SessionSummary; connect: ConnectView | null; profile: ProfileView | null; turns: TurnRecord[]; threads: ThreadView[] }

/**
 * One chat: its thread (with the viewer's read position), what it is called,
 * its people and agents, the messages loaded so far (`more`: older ones
 * exist), and what was sent from here that it does not show yet.
 */
export interface ChatView {
  me: Me;
  thread: ThreadView;
  title: string;
  people: Creator[];
  agents: ChatAgentView[];
  messages: MessageView[];
  more: boolean;
  outbox: OutboxMessage[];
  link: LinkView;
}

/** A step in flight; an ended one stays until the transcript entry that records it arrives. */
export type ShownStep = LiveStep & { ended?: boolean };
/** Where the turn stands with the model, since when. */
export interface ShownPhase { phase: LivePhase; since: number }
/** A session as it runs: its transcript (all of it once `loaded`), the model's use, and the steps in flight. */
export interface LiveView { loaded: boolean; timeline: TimelineEntry[]; usage: TranscriptUsage | null; steps: ShownStep[]; phase: ShownPhase | null }

export function useChats(scope: string, mine: boolean): TopicState<ChatsView> {
  return useTopic<ChatsView>({ topic: "chats", scope, mine });
}

export function useStations(scope: string): TopicState<StationView[]> {
  return useTopic<StationView[]>({ topic: "stations", scope });
}

export function useConnects(scope: string, mine = false): TopicState<ConnectsView> {
  return useTopic<ConnectsView>({ topic: "connects", scope, mine });
}

export function useChat(station: string, thread: number): TopicState<ChatView> {
  return useTopic<ChatView>({ topic: "chat", station, thread });
}

export function useLive(station: string, key: string): TopicState<LiveView> {
  return useTopic<LiveView>({ topic: "live", station, key });
}

/** Each session's live topic, by key: the agents of a chat as they run. */
export function useLives(station: string, keys: string[]): ReadonlyMap<string, LiveView> {
  const states = useTopics<LiveView>(keys.map((key) => ({ topic: "live", station, key })));
  return useMemo(() => new Map(keys.flatMap((key, i) => (states[i]?.value ? [[key, states[i]!.value!] as const] : []))), [states, keys.join("\n")]);
}

// One station's own topics, for its settings pages.

export function useOverview(station: string): TopicState<Overview> {
  return useTopic<Overview>({ topic: "overview", station });
}

export function useSessions(station: string): TopicState<SessionSummary[]> {
  return useTopic<SessionSummary[]>({ topic: "sessions", station });
}

/** Every thread of a station, latest message first. */
export function useThreads(station: string): TopicState<ThreadView[]> {
  return useTopic<ThreadView[]>({ topic: "threads", station });
}

export function useHost(station: string): TopicState<HostInfo> {
  return useTopic<HostInfo>({ topic: "host", station });
}

/** Who is looking, where a list already knows it (the sidebar provides it for its rows). */
export const MeContext = createContext<Me | null>(null);

/** Whether something was created by whoever is looking. */
export function useIsMine(): (creator: { id: string; email?: string | null } | null | undefined) => boolean {
  const given = useContext(MeContext);
  const station = useStation();
  const [onlyMine] = useOnlyMine();
  // The sidebar's own view, already subscribed: reading `me` from it costs the core nothing.
  const chats = useTopic<ChatsView>(given ? null : { topic: "chats", scope: scopeOf(station.address), mine: onlyMine });
  const me = given ?? chats.value?.me ?? (station.address === "local" ? { id: "local", email: null } : null);
  return (creator) => Boolean(creator && me) && (creator!.id === me!.id || (Boolean(me!.email) && creator!.email?.toLowerCase() === me!.email!.toLowerCase()));
}

// ── calls ───────────────────────────────────────────────────────────────

export interface StationCall {
  request<T>(method: string, path: string, body?: unknown): Promise<T>;
  /** Puts a file in the session's workspace on the station; send the result with a message. */
  upload(key: string, file: File): Promise<Attachment>;
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
    upload: async (key, file) => {
      const saved = await call("station.upload", { station, key, name: file.name, bytes: await toBase64(file) }) as Attachment;
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
export function stationApi(t: StationCall) {
  const { request } = t;
  const at = (id: string) => encodeURIComponent(id);
  return {
    stop: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/stop`),
    evict: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/evict`),
    putConnect: (id: string, input: ConnectInput) => request<Overview>("PUT", `/connects/${at(id)}`, input),
    deleteConnect: (id: string) => request<Overview>("DELETE", `/connects/${at(id)}`),
    reconnect: (id: string) => request<{ ok: true }>("POST", `/connects/${at(id)}/reconnect`),
    putProfile: (id: string, input: ProfileInput) => request<Overview>("PUT", `/profiles/${at(id)}`, input),
    refreshQuota: (id: string) => request<ProfileQuota | null>("POST", `/profiles/${at(id)}/quota`),
    checkProfile: (id: string) => request<ProfileCheck>("POST", `/profiles/${at(id)}/check`),
    verifySlack: (input: { connect?: string; appToken?: string; botToken?: string }) =>
      request<{ identity: SlackIdentity | null; errors: string[] }>("POST", "/slack/verify", input),
    bindSession: (connect: string, session: string | null, title?: string) =>
      request<{ session: string }>("POST", `/connects/${at(connect)}/session`, { session, ...(title ? { title } : {}) }),
    /** Starts the session's runtime ahead of a message. */
    warm: (key: string) => request<{ ok: true }>("POST", `/sessions/${at(key)}/warm`),
    /** A new chat: its session and its thread, made before its first message so files can go into it. */
    newChat: (input: { runtime: RuntimeKind; profile?: string; model?: string; effort?: string }) => request<{ key: string; thread: ThreadView }>("POST", "/sessions", input),
    file: t.file,
    uploadFile: t.upload,
    startLogin: (profile: string) => request<{ job: LoginJob }>("POST", `/profiles/${at(profile)}/login`),
    cancelLogin: (profile: string) => request<{ job: LoginJob | null }>("DELETE", `/profiles/${at(profile)}/login`),
    loginCode: (profile: string, code: string) => request<{ job: LoginJob }>("POST", `/profiles/${at(profile)}/login-code`, { code }),
    slackApp: (connect: string) => request<SlackAppView>("GET", `/connects/${at(connect)}/slack-app`),
    putSlackApp: (connect: string, input: Partial<SlackAppSettings> & { icon?: string }) =>
      request<{ permissionsUpdated: boolean; iconError: string | null; links: SlackAppLinks }>("PUT", `/connects/${at(connect)}/slack-app`, input),
    putConfigToken: (refreshToken: string) => request<{ configured: boolean; teamId: string | null }>("PUT", "/slack/config-token", { refreshToken }),
    deleteProfile: (id: string) => request<Overview>("DELETE", `/profiles/${at(id)}`),
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

/**
 * A GET that is no topic of the core (a Slack app's settings, read from
 * Slack through the station): read on mount, and again on `reload`.
 */
export function useStationGet<T>(station: string, path: string): TopicState<T> & { reload(): void } {
  const { request } = useStationCall(station);
  const [state, setState] = useState<TopicState<T>>({ value: undefined, error: null, loading: true });
  const [round, setRound] = useState(0);
  useEffect(() => {
    let current = true;
    request<T>("GET", path).then(
      (value) => { if (current) setState({ value, error: null, loading: false }); },
      (error: CoreError) => { if (current) setState((s) => ({ value: s.value, error, loading: false })); },
    );
    return () => { current = false; };
  }, [request, path, round]);
  return { ...state, reload: useCallback(() => setRound((n) => n + 1), []) };
}
