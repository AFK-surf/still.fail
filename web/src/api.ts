import { bindStationOperations } from "./core/operations.ts";
// A station's data, through the client core (docs/client-core.md): screens
// subscribe to the views the core puts together; what they have done is a
// call by its name (client/core/src/ops.rs), never a request made here, and the
// core brings whatever it touches up to date before it answers. Types come
// from client/shapes (core/shapes.ts); what is only sent to a station is
// declared here.
import { createContext, useCallback, useContext, useMemo, useRef } from "react";
import { useCall, useTopic, useTopics, type TopicState } from "./core/react.ts";
import { CoreError } from "./core/client.ts";
import { scopeOf, useOnlyMine, useStation, type Me } from "./station.tsx";
import type { ArchiveView, Attachment, ChatJobsView, ChatSearchView, ChatsView, Quote, ChatView, ConnectsView, HistoryView, Host, Live, Overview, Session, Stamp, StationView, StatusView, ChatThread } from "./core/shapes.ts";
import type { AccessKind, ConnectMode, Job, LoginJob, ProfileCheck, Quota, RuntimeKind, SlackAppLinks, SlackIdentity } from "./core/shapes.ts";
import type { SlackPerson } from "./cloud/adding.ts";
import { t } from "./i18n.ts";

export type { TopicState };
export { CoreError };

// ── what is sent to a station (its admin API's inputs) ──

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
  access?: { kind: AccessKind; key?: string; endpoint?: string };
  home?: string;
  model?: string;
  /** Replaces the enabled models. */
  models?: string[];
  env?: Record<string, string | null>;
  /** Claude Code: a message to a running turn moves what it waits on to the background first. */
  backgroundOnMessage?: boolean;
  fast?: boolean;
}

/** The groups of scopes and events a Slack app made here asks for (mesh/app/src/chat/slack_apps.rs). */
export type SlackGroup =
  | "base" | "public" | "dm" | "customize" | "files" | "reactions" | "channels" | "people" | "extras"
  | "canvases" | "lists" | "topics" | "usergroups" | "search" | "connect" | "more";

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

/** A time of anything the core sent, in words, by its field (for what still.fail cloud sends, which has no shape yet). */
export function stamp(of: object, field: string): Stamp | undefined {
  return (of as { time?: Record<string, Stamp> }).time?.[field];
}

/** A scope's chat list: all, the viewer's (`mine`), or the watching ones (`watching`). */
export function useChats(scope: string, mine: boolean, watching = false): TopicState<ChatsView> {
  return useTopic<ChatsView>({ topic: "chats", scope, mine, ...(watching ? { watching } : {}) });
}

/**
 * The chats of `scope` a few words find, titles first (the `chatSearch` topic): only `station`'s if given, not
 * `exclude`, `limit` at most. While the next words are looked up, what the last ones found stays.
 */
export function useChatSearch({ scope, query, station, exclude, limit }: { scope: string; query: string; station?: string; exclude?: string | null; limit?: number }): TopicState<ChatSearchView> {
  const state = useTopic<ChatSearchView>({ topic: "chatSearch", scope, query, ...(station ? { station } : {}), ...(exclude ? { exclude } : {}), ...(limit ? { limit } : {}) });
  const last = useRef<ChatSearchView | undefined>(undefined);
  if (state.value) last.current = state.value;
  return state.value || !last.current || state.error ? state : { ...state, value: last.current };
}

/**
 * What the core is waiting on, when it is worth saying: something slow, a connection down (`state` absent: nothing).
 * Of a workspace (its stations, its account's socket, the relay): nothing of another one; with none, all of it.
 */
export function useStatus(workspace?: string): StatusView | undefined {
  return useTopic<StatusView>(workspace ? { topic: "status", workspace } : STATUS).value;
}
const STATUS = { topic: "status" } as const;

/** The archive of a scope's stations online (client/core/src/views/archive.rs). */
export function useArchiveView(scope: string): TopicState<ArchiveView> {
  return useTopic<ArchiveView>({ topic: "archive", scope });
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

/** A chat's services and background jobs as its pages show them (the same `of` as its `useChat`). */
export function useChatJobs(station: string, of: { thread: number } | { session: string }): TopicState<ChatJobsView> {
  return useTopic<ChatJobsView>({ topic: "chatJobs", station, ...of });
}

/** A job as it is now (null: none). */
export function useJob(station: string, id: string | null): TopicState<Job> {
  return useTopic<Job>(id ? { topic: "job", station, id } : null);
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
  /** Has the core do `name` (client/core/src/ops.rs) on this station, with `params`. */
  op<T>(name: string, params?: Record<string, unknown>): Promise<T>;
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
    reader.onerror = () => reject(reader.error ?? new Error(t("web-main.file.unreadable")));
    reader.readAsDataURL(file);
  });
}

export function useStationCall(station: string): StationCall {
  const call = useCall();
  return useMemo(() => stationCall(call, station), [call, station]);
}

/** A station's calls through the core's `call` (useCall), for what reaches more than one station. */
export function stationCall(call: ReturnType<typeof useCall>, station: string): StationCall {
  return {
    op: <T,>(name: string, params: Record<string, unknown> = {}) => call(name, { ...params, station }) as Promise<T>,
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
  };
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
  /** Its runtime, where it ran (the home directory as ~) and how long ago, in a line (the core's). */
  meta?: string;
}

/** Something said in one of the machine's sessions: by the person, else by its agent; when, in ms. */
export interface MachineSaid { person: boolean; text: string; at: number | null }

/** The admin API of one station, by what each call does. */

export function stationApi(t: StationCall) {
  const ops = bindStationOperations((name, params) => t.op(name, params));
  return {
    keepChat: (thread: number) => ops.chatKeep({ thread }),
    stop: (key: string) => ops.sessionStop<{ ok: true }>({ key }),
    /** A chat into the archive or back: its thread (with its session when it is that session's own), or an agent with no chat yet. */
    archive: (of: { thread?: number | null; session: string }, archived: boolean) =>
      ops.chatArchive<unknown>({ session: of.session, ...(of.thread == null ? {} : { thread: of.thread }), archived }),
    /** Names a chat (its thread, or an agent with no chat yet); an empty name leaves it named by its first message. */
    rename: (of: { thread?: number | null; session: string }, title: string) =>
      ops.chatRename<unknown>({ session: of.session, ...(of.thread == null ? {} : { thread: of.thread }), title }),
    /** Keeps a chat at the top of the viewer's list, or lets it go (by its item's id, its session's key). */
    pin: (of: { session: string }, pinned: boolean) => ops.chatPin<unknown>({ session: of.session, pinned }),
    deleteSession: (key: string) => ops.sessionDelete<{ ok: true }>({ key }),
    evict: (key: string) => ops.sessionEvict<{ ok: true }>({ key }),
    putConnect: (id: string, input: ConnectInput) => ops.connectPut<Overview>({ id, input }),
    deleteConnect: (id: string) => ops.connectDelete<Overview>({ id }),
    reconnect: (id: string) => ops.connectReconnect<{ ok: true }>({ id }),
    putProfile: (id: string, input: ProfileInput) => ops.profilePut<Overview>({ id, input }),
    /** One model named by hand, added to those enabled (a provider that does not list its models). */
    addModel: (id: string, model: string) => ops.profileAddModel<Overview>({ id, model }),
    resetQuota: (id: string) => ops.profileResetQuota({ id }),
    refreshQuota: (id: string) => ops.profileQuota<Quota | null>({ id }),
    checkProfile: (id: string) => ops.profileCheck<ProfileCheck>({ id }),
    verifySlack: (input: { connect?: string; install?: string; appToken?: string; botToken?: string }) =>
      ops.slackVerify<{ identity: SlackIdentity | null; errors: string[] }>(input),
    bindSession: (connect: string, session: string | null, title?: string) =>
      ops.connectBindSession<{ session: string }>({ connect, session, ...(title ? { title } : {}) }),
    /** Starts the session's runtime ahead of a message. */
    warm: (key: string) => ops.sessionWarm<{ ok: true }>({ key }),
    /** What an inline visualization (Viz.tsx) kept: by the session that sent its file and the file's path. */
    widgetState: (key: string, path: string) => ops.widgetState<{ state: unknown }>({ key, path }),
    setWidgetState: (key: string, path: string, state: unknown) => ops.widgetSetState<{ ok: true }>({ key, path, state }),
    /** The chat of an agent that has none yet, bound to its session. */
    chatFor: (session: string) => ops.chatForSession<{ id: number }>({ session }),
    /** Sessions the machine's own Claude Code and Codex kept (in a terminal); a station from before them answers 404. */
    machineSessions: () => ops.machineSessionsList<{ sessions: MachineSession[] }>(),
    /** One of them to look at first: what was said in it, the latest `limit` of `total`. */
    machineSession: (runtime: RuntimeKind, id: string, limit = 200) =>
      ops.machineSessionsRead<{ session: MachineSession; total: number; said: MachineSaid[] }>({ runtime, id, limit }),
    /** A chat going on with one of them (the one already going on with it, if any). */
    continueMachineSession: (runtime: RuntimeKind, id: string) => ops.machineSessionsContinue<{ key: string; thread: ChatThread }>({ runtime, id }),
    file: t.file,
    uploadFile: t.upload,
    startLogin: (profile: string) => ops.profileLogin<{ job: LoginJob }>({ id: profile }),
    cancelLogin: (profile: string) => ops.profileCancelLogin<{ job: LoginJob | null }>({ id: profile }),
    loginCode: (profile: string, code: string) => ops.profileLoginCode<{ job: LoginJob }>({ id: profile, code }),
    /** A subscription signed in before its profile exists; the station makes the profile when it succeeds. */
    newLogin: (runtime: RuntimeKind) => ops.loginNew<{ id: string; job: LoginJob }>({ runtime }),
    newLoginCode: (id: string, code: string) => ops.loginCode<{ job: LoginJob }>({ id, code }),
    dropLogin: (id: string) => ops.loginDrop<{ ok: true }>({ id }),
    /** A profile on the machine's own login of `runtime` (one kept in a file). */
    useMachineLogin: (runtime: RuntimeKind) => ops.profileUseMachineLogin<{ id: string; overview: Overview }>({ runtime }),
    /** A keyed profile, made only once its key is checked. */
    addProfile: (input: { runtime?: RuntimeKind; access: { kind: AccessKind; key?: string; provider?: string; endpoint?: string } }) => ops.profileAdd<{ id: string; overview: Overview }>(input),
    putSlackApp: (connect: string, input: Partial<SlackAppSettings> & { icon?: string }) =>
      ops.connectPutSlackApp<{ permissionsUpdated: boolean; iconError: string | null; links: SlackAppLinks }>({ connect, input }),
    /** Makes a Slack app with the workspace's configuration token (still.fail's manifest, Socket Mode on), for a connect to come. */
    /** `install`: Slack's install link, when the app is installed through OAuth (a station in still.fail cloud); `state` names it. */
    /** The app is kept on the station, waiting for its connect (the overview's `slackApps`); this says which it is. */
    makeSlackApp: (input: { team: string; settings: SlackAppSettings; icon?: string }) => ops.slackMakeApp<{ appId: string; iconError: string | null }>(input),
    /** Drops an app made here from the waiting ones; it stays in Slack. */
    dropSlackApp: (appId: string) => ops.slackDropApp<Overview>({ appId }),
    /** Hands Slack's install code to the station that made the app. */
    slackInstalled: (code: string, state: string) => ops.slackInstalled<{ team: string | null }>({ code, state }),
    /** The people of the Slack workspaces this station's connects are in, and what could not be read. */
    slackPeople: () => ops.slackPeople<{ people: SlackPerson[]; errors: string[] }>(),
    /** A new Slack connect from its tokens: the station names it as its bot is named in Slack. */
    createConnect: (input: ConnectInput) => ops.connectCreate<{ id: string; overview: Overview }>({ input }),
    /** How a session runs from its next turn on: its profile, model, effort (null: the runtime's default). */
    sessionSettings: (key: string, input: { profile?: string | null; model?: string | null; effort?: string | null }) => ops.sessionSettings<{ ok: true }>({ key, ...input }),
    /** Adds a Slack workspace's app configuration token; answers which workspace it is. */
    addConfigToken: (refreshToken: string) => ops.slackAddConfigToken<{ teamId: string; overview: Overview }>({ refreshToken }),
    removeConfigToken: (team: string) => ops.slackRemoveConfigToken<Overview>({ team }),
    deleteProfile: (id: string) => ops.profileDelete<Overview>({ id }),
    /** "这是我" (bound) or "不是我" on a Slack user: the station takes them for the viewer, or no longer. */
    slackIdentity: (user: string, bound: boolean) => ops.slackIdentity<Overview>({ user, bound }),
    createAppUrl: (name: string) => ops.slackCreateAppUrl<{ url: string }>({ name }),
    /** Stops a job from the page (its agent is told who did); the core puts it in place as it is now. */
    stopJob: (id: string) => ops.jobStop<Job>({ id }),
    /** Takes a session's jobs that are over off its record; the core reads the session again. */
    clearEndedJobs: (session: string) => ops.jobClearEnded<{ removed: string[] }>({ session }),
    /** What the station's agents remember (their memory and skills). */
    memory: <T,>() => ops.memoryGet<T>(),
    /** Brings a piece of the station's software up to date, or checks what is new. */
    updateAllSoftware: <T,>() => ops.softwareUpdateAll<T>(),
    updateSoftware: <T,>(id: string) => ops.softwareUpdate<T>({ id }),
    checkSoftware: <T,>() => ops.softwareCheck<T>(),
    /** Puts the station on the stable channel or the test channel's; the core reads its versions again. */
    setSoftwareChannel: <T,>(channel: "stable" | "beta") => ops.softwareChannel<T>({ channel }),
    /** Turns the station's updating by itself on or off; turned on, it reads what is out and updates at once. */
    setSoftwareAuto: <T,>(on: boolean) => ops.softwareAuto<T>({ on }),
  };
}

export type Api = ReturnType<typeof stationApi>;

/**
 * A chat's calls, by its thread (or, for a chat made here, the key the core gave it: `chat.create`). Sending: the
 * message shows at once from the core's outbox; a failed one can be sent again or dropped. `older` / `newer` load the page before / after the messages shown, `latest` goes to the chat's end, `place` says
 * where the reader left it; `read` records how far the viewer has read.
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
    /** The page after them, while the chat shows a window short of its end (`chat.newer`); as many go at its start. */
    newer: (thread: number) => call("chat.newer", { station, thread }) as Promise<{ more: boolean }>,
    /** The chat's latest page in place of what it shows: the reader goes to its end. */
    latest: (thread: number) => call("chat.latest", { station, thread }),
    /** Where the reader leaves the chat: the message at the top of what shows (`seq`) and how far below the list's top
     *  its top is (`offset`, px), or none at its end. */
    place: (thread: number, seq: number | null, offset: number | null = null) => call("chat.place", { station, thread, seq, offset }),
    /** Only for a core from before `client.focus` (an older desktop app's), which does not read chats itself. */
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

export { useAction, type Action } from "./action.ts";
