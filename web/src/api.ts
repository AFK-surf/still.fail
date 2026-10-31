import { bindStationOperations } from "./core/operations.ts";
// A station's data, through the client core (docs/client-core.md): screens
// subscribe to the views the core puts together; what they have done is a
// call by its name (client/core-ts/src/ops.ts), never a request made here, and the
// core brings whatever it touches up to date before it answers. Types come
// from client/core-ts/src/shapes/schema.ts (core/shapes.ts); what is only sent to a station is
// declared here.
import { createContext, useCallback, useContext, useMemo, useRef } from "react";
import { core, useCall, useTopic, useTopicSelect, useTopics, type TopicState } from "./core/react.ts";
import { CoreError } from "./core/client.ts";
import { scopeOf, useOnlyMine, useStation, type Me } from "./station.tsx";
import type { AgentCardView, ArchiveView, Attachment, ChatItem, ChatJobsView, ChatLettersView, ChatSearchView, ChatsView, Quote, SearchView, ChatView, ConnectsView, HistoryView, Host, JoinableView, Live, MembershipsView, Overview, ProfilesView, Session, Stamp, StationView, StatusView, ChatThread } from "./core/shapes.ts";
import type { AccessKind, ConnectMode, Job, LoginJob, ProfileCheck, Quota, RuntimeKind, SlackAppLinks, SlackGroupSection, SlackIdentity } from "./core/shapes.ts";
import type { ChatPublished, PublishPreview } from "./core/shapes.ts";
import type { SlackPerson } from "./cloud/adding.ts";
import { t } from "./i18n.ts";

export type { TopicState };
export { CoreError };

// ── what is sent to a station (its admin API's inputs) ──

export type ConnectKind = "slack" | "feishu";

/** POST /connects, PUT /connects/:id. Blank or missing tokens keep the stored ones. */
export interface ConnectInput {
  enabled?: boolean;
  kind?: ConnectKind;
  mode?: ConnectMode;
  requireMention?: boolean;
  bind?: { runtime?: RuntimeKind; model?: string; effort?: string; profile?: string | null };
  /** `install`: an app installed through Slack's OAuth (its state), whose bot token the station has. */
  slack?: { appToken?: string; botToken?: string; appId?: string; install?: string };
  /** A Feishu connect's App Secret replaced (blank: kept). */
  feishu?: { appSecret?: string };
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
  /** The workspaces the station joined whose chats may run on it too ([] or null: its home's only); its home's managers'. */
  workspaces?: string[] | null;
}

/** The groups of scopes and events a Slack app made here asks for (the Rust station's chat/slack_apps.rs). */
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

/** `sections`: its permissions as its form shows them (the core's). */
export type SlackAppView = { sections: SlackGroupSection[] } & (
  | { state: "no_app"; appId: null; links: null; settings: null; groups: SlackGroup[]; error?: string }
  | { state: "no_config_token"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[] }
  | { state: "ok"; appId: string; links: SlackAppLinks; settings: SlackAppSettings; groups: SlackGroup[] }
  | { state: "error"; appId: string; links: SlackAppLinks; settings: null; groups: SlackGroup[]; error: string });

// ── what the core gives: generated from client/core-ts/src/shapes/schema.ts (core/shapes.ts), nothing hand-written ──

export type * from "./core/shapes.ts";

/** A time of anything the core sent, in words, by its field (for what still.fail cloud sends, which has no shape yet). */
export function stamp(of: object, field: string): Stamp | undefined {
  return (of as { time?: Record<string, Stamp> }).time?.[field];
}

/** A scope's chat list: all, the viewer's (`mine`), or the watching ones (`watching`). */
export function useChats(scope: string, mine: boolean, watching = false): TopicState<ChatsView> {
  return useTopic<ChatsView>({ topic: "chats", scope, mine, ...(watching ? { watching } : {}) });
}

/** A chat (by its key or its agent's session) as its workspace's list has it: its title while the chat itself is read. */
export function useListedChat(station: string, chat: string): ChatItem | undefined {
  return useChats(scopeOf(station), false).value?.days.flatMap((d) => d.items).find((i) => i.station === station && (i.id === chat || i.session === chat));
}

/**
 * The chats of `scope` a few words find, titles first (the `chatSearch` topic): only `station`'s if given, not
 * `exclude`, `limit` at most; with `messages`, that many of the messages that have the words too, newest first. While the
 * next words are looked up, what the last ones found stays.
 */
export function useChatSearch({ scope, query, station, exclude, limit, messages, elsewhere }: { scope: string; query: string; station?: string; exclude?: string | null; limit?: number; messages?: number; elsewhere?: boolean }): TopicState<ChatSearchView> {
  const state = useTopic<ChatSearchView>({ topic: "chatSearch", scope, query, ...(station ? { station } : {}), ...(exclude ? { exclude } : {}), ...(limit ? { limit } : {}), ...(messages ? { messages } : {}), ...(elsewhere ? { elsewhere } : {}) });
  const last = useRef<ChatSearchView | undefined>(undefined);
  if (state.value) last.current = state.value;
  return state.value || !last.current || state.error ? state : { ...state, value: last.current };
}

/**
 * What a few words find in a workspace (the `search` topic, docs/search.md): the chats and messages the device holds and
 * what every station finds, by kind; with `kind`, that kind alone. While the next words are looked up, what the last
 * ones found stays.
 */
export function useSearch({ scope, query, kind }: { scope: string; query: string; kind?: string | null }): TopicState<SearchView> {
  const state = useTopic<SearchView>({ topic: "search", scope, query, ...(kind ? { kind } : {}) });
  const last = useRef<SearchView | undefined>(undefined);
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

/** The archive of a scope's stations online (client/core-ts/src/views/archive.ts): with `q`, those that have it; with
 * `limit`, only the newest so many. */
export function useArchiveView(scope: string, q = "", limit = 0): TopicState<ArchiveView> {
  return useTopic<ArchiveView>({ topic: "archive", scope, ...(q ? { q } : {}), ...(limit ? { limit } : {}) });
}

export function useStations(scope: string): TopicState<StationView[]> {
  return useTopic<StationView[]>({ topic: "stations", scope });
}

/** The workspace's stations with a drive, as the workspace lists them. */
export function useDriveStations(scope: string): TopicState<StationView[]> {
  return useTopic<StationView[]>({ topic: "stations", scope, drive: true });
}

/** The stations 添加 station offers to add to a workspace as they are: those of the viewer's other workspaces whose home
 * workspace they manage, not in this one yet (client/core-ts/src/views/memberships.ts). */
export function useJoinable(workspace: string): TopicState<JoinableView> {
  return useTopic<JoinableView>({ topic: "joinable", workspace });
}

/** The workspaces a station is in, for its home workspace's owners and admins (`manages`); null: not asked. */
export function useMemberships(station: string | null): TopicState<MembershipsView> {
  return useTopic<MembershipsView>(station ? { topic: "memberships", station } : null);
}

/**
 * A scope's stations, only what pages are placed by (each one's id, name, address and whether it is online): the same
 * list while those are, though the core's view changes much more often (its overview, its agents starting and stopping).
 * Undefined until the core has listed them.
 */
export function useStationViews(scope: string): StationView[] | undefined {
  return useTopicSelect<StationView[], StationView[] | undefined>({ topic: "stations", scope }, (s) => s.value, sameStations);
}
/** How a station looks where it is named (its name, emoji, icon); undefined until listed, or for one not listed. */
export interface StationLook { name: string; emoji?: string | null | undefined; icon?: string | null | undefined }

/** One station's look, by its address (null: none): the same while it is, whatever else of its view changes. */
export function useStationLook(address: string | null): StationLook | undefined {
  const scope = address?.split("/")[0];
  return useTopicSelect<StationView[], StationLook | undefined>(scope ? { topic: "stations", scope } : null, (s) => {
    const v = s.value?.find((x) => x.station === address);
    return v && { name: v.name, emoji: v.emoji, icon: v.icon };
  }, (a, b) => a === b || (!!a && !!b && a.name === b.name && a.emoji === b.emoji && a.icon === b.icon));
}

/** The system a station runs on, in words (its host's `os`: macOS 26.6.2, Windows 11 Pro…), by its address; undefined
 * until known. */
export function useStationOs(address: string): string | undefined {
  const scope = address.split("/")[0];
  return useTopicSelect<StationView[], string | undefined>(scope ? { topic: "stations", scope } : null, (s) => s.value?.find((x) => x.station === address)?.host?.os || undefined, (a, b) => a === b);
}

const sameStations = (a: StationView[] | undefined, b: StationView[] | undefined) =>
  a === b || (!!a && !!b && a.length === b.length && a.every((x, i) => x.id === b[i]!.id && x.name === b[i]!.name && x.online === b[i]!.online && x.station === b[i]!.station));

/** The workspace's profiles in one list: each shared one once (the core's `profiles` view). */
export function useProfiles(scope: string): TopicState<ProfilesView> {
  return useTopic<ProfilesView>({ topic: "profiles", scope });
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

/** What a chat's agents and other chats' wrote each other (`chatLetters`, Letters.tsx). */
export function useChatLetters(station: string, thread: number): TopicState<ChatLettersView> {
  return useTopic<ChatLettersView>({ topic: "chatLetters", station, thread });
}

/** A job as it is now (null: none). */
export function useJob(station: string, id: string | null): TopicState<Job> {
  return useTopic<Job>(id ? { topic: "job", station, id } : null);
}

/** A chat's agent in brief, for its card over its avatar (AgentCard.tsx). */
export function useAgentCard(station: string, key: string): TopicState<AgentCardView> {
  return useTopic<AgentCardView>({ topic: "agentCard", station, key });
}

export function useHistory(station: string, key: string): TopicState<HistoryView> {
  return useTopic<HistoryView>({ topic: "history", station, key });
}

/** Loads the page of an agent's execution history before what it shows (the core has its latest entries first). */
export function useHistoryOlder(station: string, key: string): () => Promise<{ more: boolean }> {
  const call = useCall();
  return useCallback(() => call("history.older", { station, key }) as Promise<{ more: boolean }>, [call, station, key]);
}

/** Reads whole the entries of an execution history's step or thought shown in brief (`brief`), as it is opened: the
 *  history shows them whole as they come. */
export function useHistoryDetail(station: string, key: string): (entries: number[]) => Promise<unknown> {
  const call = useCall();
  return useCallback((entries: number[]) => call("history.detail", { station, key, from: Math.min(...entries), to: Math.max(...entries) }), [call, station, key]);
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
  /** Has the core do `name` (client/core-ts/src/ops.ts) on this station, with `params`. */
  op<T>(name: string, params?: Record<string, unknown>): Promise<T>;
  /** Puts a file on the station, in no chat yet; a message that sends it takes it into its chat. `onProgress`: the bytes
   * the station has so far, after each part. */
  upload(file: File, onProgress?: (sent: number) => void): Promise<Attachment>;
  /** A file sent to the session, as a blob for previews; `thumb`: an image as a chat shows it (its thumbnail, where the station keeps one). */
  /** `onProgress`: bytes so far and the whole size (null when the station does not say) as a whole file comes. `size`:
   * the file's, as its message says: a big one comes a part at a time (`station.file.part`), never all through at once. */
  file(key: string, name: string, thumb?: boolean, onProgress?: (got: FileProgress) => void, size?: number): Promise<Blob>;
  /** A video's poster as the station makes it (a small JPEG of its first frame); null when it has none. */
  poster(key: string, name: string): Promise<Blob | null>;
  /** A file's first `length` bytes (`station.file.part`): enough to tell what it is without fetching all of it. Throws
   * `unsupported` from a station from before parts. */
  head(key: string, name: string, length: number): Promise<Blob>;
}

/** Over this a file comes a part at a time; a part's bytes. */
export const BIG_FILE = 16 * 1024 * 1024;
const FILE_PART = 4 * 1024 * 1024;
/** The most a station from before parts sends (whole). */
const WHOLE_FILE_MAX = 50 * 1024 * 1024;

/** How much of a file has come. */
export interface FileProgress { loaded: number; total: number | null }

/** The bytes of a file in one `station.upload.part`. */
const UPLOAD_PART = 4 * 1024 * 1024;

/** A part of a file read, as the core takes it beside a call (never base64). */
export async function bytesOf(file: Blob): Promise<Uint8Array<ArrayBuffer>> {
  try {
    return new Uint8Array(await file.arrayBuffer());
  } catch (e) {
    throw e instanceof Error ? e : new Error(t("web-main.file.unreadable"));
  }
}

/** The bytes beside a call's answer as a blob (none: empty). */
const blobOf = (bytes: Uint8Array | undefined, type?: string) => new Blob(bytes ? [bytes as Uint8Array<ArrayBuffer>] : [], type === undefined ? {} : { type });

export function useStationCall(station: string): StationCall {
  const call = useCall();
  return useMemo(() => stationCall(call, station), [call, station]);
}

/** A station's calls through the core's `call` (useCall), for what reaches more than one station. */
export function stationCall(call: ReturnType<typeof useCall>, station: string): StationCall {
  return {
    op: <T,>(name: string, params: Record<string, unknown> = {}) => call(name, { ...params, station }) as Promise<T>,
    upload: async (file, onProgress) => {
      // A part at a time (`station.upload.part`), read from the file as it goes: a big one is never all in memory.
      const id = Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, "0")).join("");
      let saved: Attachment | undefined;
      // Said at once (nothing yet), then as each part goes.
      onProgress?.(0);
      for (let have = 0; saved === undefined;) {
        const bytes = await bytesOf(file.slice(have, have + UPLOAD_PART));
        const from = have;
        const told = (await core().callBytes("station.upload.part", { station, id, name: file.name, size: file.size, offset: have, ...(onProgress ? { progress: true } : {}) }, bytes,
          onProgress && ((p) => onProgress(from + (p as { sent: number }).sent)))).value as { have: number; file?: Attachment };
        if (told.file) saved = told.file;
        // The station goes on from what it has (less, after it lost a part); nothing more is a part it could not take.
        else if (told.have === have) throw new Error(t("web-main.draft.uploadFailed"));
        else have = told.have;
        onProgress?.(told.file ? file.size : have);
      }
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
    file: async (key, name, thumb = false, onProgress, size) => {
      const whole = async () => {
        const got = await core().callBytes("station.file", { station, key, name, ...(thumb ? { thumb } : {}), ...(onProgress ? { progress: true } : {}) }, undefined,
          onProgress && ((p) => onProgress(p as FileProgress)));
        return blobOf(got.bytes, (got.value as { type: string }).type);
      };
      if (thumb || size === undefined || size <= BIG_FILE) return whole();
      // Big: a part at a time, each a blob of its own (the browser keeps big ones on the disk), so it is never all in
      // memory at once on its way.
      const parts: Blob[] = [];
      let type = "";
      // Said at once (nothing yet, out of how much), then as each part comes.
      onProgress?.({ loaded: 0, total: size });
      for (let at = 0, total = size; at < total;) {
        let got: { value: unknown; bytes?: Uint8Array };
        const from = at;
        try {
          got = await core().callBytes("station.file.part", { station, key, name, offset: at, length: FILE_PART, ...(onProgress ? { progress: true } : {}) }, undefined,
            onProgress && ((p) => onProgress({ loaded: from + (p as { loaded: number }).loaded, total })));
        } catch (e) {
          // A station from before parts sends it whole, as long as it is not too big for that.
          if (at === 0 && e instanceof CoreError && e.code === "unsupported" && size <= WHOLE_FILE_MAX) return whole();
          throw e;
        }
        const bytes = got.bytes ?? new Uint8Array();
        if (bytes.length === 0) break;
        parts.push(blobOf(bytes));
        const said = got.value as { type: string; total: number };
        type = said.type;
        total = said.total;
        at += bytes.length;
        onProgress?.({ loaded: at, total });
      }
      return new Blob(parts, { type });
    },
    head: async (key, name, length) => {
      return blobOf((await core().callBytes("station.file.part", { station, key, name, offset: 0, length })).bytes);
    },
    poster: async (key, name) => {
      const got = await core().callBytes("station.poster", { station, key, name });
      return got.value ? blobOf(got.bytes, (got.value as { type: string }).type) : null;
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

/** A channel or group a connect's bot is in (docs/relay.md): a Slack channel, a Feishu topic group, a Feishu group; `used`
 * when a chat was last relayed there (ms), if ever. */
export interface RelayPlace { id: string; name: string; kind: "channel" | "topics" | "group"; private?: boolean; used?: number }

/** A connect a chat can be relayed through, with its places (none, and why, when they could not be read). */
export interface RelayConnect { id: string; kind: "slack" | "feishu" | "lark"; name: string; team: string | null; botImage?: string | null; preferred?: boolean; places: RelayPlace[]; error?: string }

/** A person in a place, as a relayed chat's note can mention them (docs/relay.md「附言里 @ 人」). */
export interface RelayPerson { id: string; name: string; aka?: string; picture?: string }

/** Where a chat was relayed: the place's name, and its link where the platform has one. */
export interface Relayed { thread: number; to: string; place: string; link: string | null }

/** The admin API of one station, by what each call does. */

/**
 * A chat into the archive, said in `toast` at once by its title: the core has it out of the lists already. Its station's
 * no is the promise's (said in its own toast then, in place of this one).
 */
export function archiveSaid(api: ReturnType<typeof stationApi>, of: { thread?: number | null; session: string }, title: string, toast: (words: string) => void): Promise<unknown> {
  const archived = api.archive(of, true);
  toast(t("web-main.chat.archivedNamed", { title }));
  return archived;
}

export function stationApi(t: StationCall) {
  const ops = bindStationOperations((name, params) => t.op(name, params));
  return {
    /** How the station archives chats on its own (设置 › 归档): its managers'. */
    saveArchiving: (input: { days: number; slackDays: number; reviewed: boolean }) => ops.archivingSave(input),
    /** A chat kept (never offered for archiving, nor archived on its own), or let go (`kept: false`). */
    keepChat: (thread: number, kept = true) => ops.chatKeep(kept ? { thread } : { thread, kept }),
    stop: (key: string) => ops.sessionStop<{ ok: true }>({ key }),
    /** A chat into the archive or back: its thread (with its session when it is that session's own), or an agent with no chat yet. */
    archive: (of: { thread?: number | null; session: string }, archived: boolean) =>
      ops.chatArchive<unknown>({ session: of.session, ...(of.thread == null ? {} : { thread: of.thread }), archived }),
    /** Names a chat (its thread, or an agent with no chat yet); an empty name leaves it named by its first message. */
    rename: (of: { thread?: number | null; session: string }, title: string) =>
      ops.chatRename<unknown>({ session: of.session, ...(of.thread == null ? {} : { thread: of.thread }), title }),
    /** Keeps a chat at the top of the viewer's list, or lets it go (by its item's id, its session's key). */
    pin: (of: { session: string }, pinned: boolean) => ops.chatPin<unknown>({ session: of.session, pinned }),
    /** Shares a chat with the viewer's other workspaces ticked (none: no longer), their agents sending in it too when `write`. */
    xshare: (of: { thread?: number | null; session: string }, to: string[], write: boolean) =>
      t.op<unknown>("chat.xshare", { session: of.session, ...(of.thread == null ? {} : { thread: of.thread }), to, write }),
    /** What a public snapshot of the chat would hold now (nothing kept): its messages, what was hidden in them, its attachments. */
    publishPreview: (thread: number, turn?: number) => t.op<PublishPreview>("chat.publishPreview", { thread, ...(turn !== undefined ? { turn } : {}) }),
    /** Keeps a public snapshot of the chat up to `upto` (the preview's last message), with the attachments ticked: its link. */
    publish: (thread: number, upto: number, files: string[]) => t.op<ChatPublished>("chat.publish", { thread, upto, files }),
    /** Revokes one of the chat's public snapshots: its link opens nothing any more. */
    unpublish: (thread: number, id: string) => t.op<unknown>("chat.unpublish", { thread, id }),
    /** Where the chat can be relayed: each connect's channels and groups its bot is in. */
    relayPlaces: (thread: number) => ops.chatRelayPlaces<{ connects: RelayConnect[] }>({ thread }),
    /** The people of where the chat would be relayed, for its note to mention. */
    relayPeople: (thread: number, to: { connect: string; channel: string } | { link: string; connect?: string }) =>
      ops.chatRelayPeople<{ people: RelayPerson[] }>({ thread, ...to }),
    /** The chat relayed to a connect's channel or group, or the Slack thread of a message's link, with the person's note; its agent goes on there too. */
    relay: (thread: number, to: { connect: string; channel: string } | { link: string; connect?: string }, note: string) =>
      ops.chatRelay<Relayed>(note.trim() === "" ? { thread, ...to } : { thread, ...to, note }),
    deleteSession: (key: string) => ops.sessionDelete<{ ok: true }>({ key }),
    evict: (key: string) => ops.sessionEvict<{ ok: true }>({ key }),
    /** Its context compacted by hand, between turns (its chat is told when it is done). */
    compact: (key: string) => ops.sessionCompact<{ ok: true }>({ key }),
    /** Its context cleared by hand, between turns: its next message starts a new conversation. */
    clear: (key: string) => ops.sessionClear<{ ok: true }>({ key }),
    /** Whether it goes on afresh as it is next started once its cache is over (a new conversation that reads back what it needs), for its chat. */
    setAfresh: (key: string, afresh: boolean) => ops.sessionSettings<{ ok: true }>({ key, afresh }),
    putConnect: (id: string, input: ConnectInput) => ops.connectPut<Overview>({ id, input }),
    deleteConnect: (id: string) => ops.connectDelete<Overview>({ id }),
    /** A Feishu connect's App Secret replaced: verified by its station first, then it reconnects. */
    putFeishuSecret: (id: string, appSecret: string) => ops.feishuPutSecret<unknown>({ id, appSecret }),
    reconnect: (id: string) => ops.connectReconnect<{ ok: true }>({ id }),
    putProfile: (id: string, input: ProfileInput) => ops.profilePut<Overview>({ id, input }),
    /** One model named by hand, added to those enabled (a provider that does not list its models). */
    addModel: (id: string, model: string) => ops.profileAddModel<Overview>({ id, model }),
    resetQuota: (id: string) => ops.profileResetQuota({ id }),
    refreshQuota: (id: string) => ops.profileQuota<Quota | null>({ id }),
    checkProfile: (id: string) => ops.profileCheck<ProfileCheck>({ id }),
    /** Shared with the workspace's other stations (`allow` null: every one), or no longer. */
    shareProfile: (id: string, on: boolean, allow: string[] | null) => ops.profileShare<Overview>({ id, on, ...(allow === null ? {} : { allow }) }),
    /** A shared profile moved to another station (its subscription signed in there from now on). */
    moveProfile: (id: string, to: string) => ops.profileMove<Overview>({ id, to }),
    /** A skill shared with the workspace's other stations, or no longer. */
    shareSkill: (name: string, on: boolean, allow: string[] | null) => ops.skillShare<unknown>({ name, on, ...(allow === null ? {} : { allow }) }),
    verifySlack: (input: { connect?: string; install?: string; appToken?: string; botToken?: string }) =>
      ops.slackVerify<{ identity: SlackIdentity | null; errors: string[] }>(input),
    bindSession: (connect: string, session: string | null, title?: string) =>
      ops.connectBindSession<{ session: string }>({ connect, session, ...(title ? { title } : {}) }),
    /** Starts the session's runtime ahead of a message. */
    warm: (key: string) => ops.sessionWarm<{ ok: true }>({ key }),
    /** A file a message names by its path, for its card (Previews.tsx): what it is, a few lines or a thumbnail. */
    filePeek: <T>(key: string, path: string, line: number | null) => ops.filePeek<T>({ key, path, ...(line !== null ? { line } : {}) }),
    /** That file whole, for the preview over the window. */
    /** What a web link in a message is, as the station finds it (Previews.tsx). */
    linkPreview: <T>(url: string) => ops.linkPreview<T>({ url }),
    /** What an inline visualization (Viz.tsx) kept: by the session that sent its file and the file's path. */
    widgetState: (key: string, path: string) => ops.widgetState<{ state: unknown }>({ key, path }),
    /** Where its runtime keeps the session's transcript on the station's machine; null before it is written. */
    transcriptPath: (key: string) => ops.sessionTranscript<{ path: string | null }>({ key }).then((r) => r.path),
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
    poster: t.poster,
    fileHead: t.head,
    uploadFile: t.upload,
    startLogin: (profile: string) => ops.profileLogin<{ job: LoginJob }>({ id: profile }),
    cancelLogin: (profile: string) => ops.profileCancelLogin<{ job: LoginJob | null }>({ id: profile }),
    loginCode: (profile: string, code: string) => ops.profileLoginCode<{ job: LoginJob }>({ id: profile, code }),
    /** The sign-in's page opened in the station's own browser: the screen of its tab, to view. */
    loginBrowser: (profile: string) => ops.profileLoginBrowser<{ screen: string }>({ id: profile }),
    /** A subscription (or, `access` opencode-go, an OpenCode Console account) signed in before its profile exists; the
     *  station makes the profile when it succeeds. */
    newLogin: (runtime: RuntimeKind, access?: string | null) => ops.loginNew<{ id: string; job: LoginJob }>({ runtime, ...(access ? { access } : {}) }),
    newLoginCode: (id: string, code: string) => ops.loginCode<{ job: LoginJob }>({ id, code }),
    newLoginBrowser: (id: string) => ops.loginBrowser<{ screen: string }>({ id }),
    dropLogin: (id: string) => ops.loginDrop<{ ok: true }>({ id }),
    /** A profile on the machine's own login of `runtime` (one kept in a file). */
    useMachineLogin: (runtime: RuntimeKind) => ops.profileUseMachineLogin<{ id: string; overview: Overview }>({ runtime }),
    /** A keyed profile, made only once its key is checked. */
    addProfile: (input: { runtime?: RuntimeKind; access: { kind: AccessKind; key?: string; provider?: string; endpoint?: string } }) => ops.profileAdd<{ id: string; overview: Overview }>(input),
    /** `from`: the settings the form started from (only what differs from them is written). */
    putSlackApp: (connect: string, input: Partial<SlackAppSettings> & { icon?: string }, from?: SlackAppSettings) =>
      ops.connectPutSlackApp<{ permissionsUpdated: boolean; iconError: string | null; links: SlackAppLinks }>({ connect, input, ...(from ? { from } : {}) }),
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
/** What `chat.find` answers: the words looked for, the messages that have them (how many times each), and whether
 *  all the chat was looked in (`held` of its `of` entries are on the device). */
export interface ChatFound { words: string[]; hits: { seq: number; count: number }[]; held: number; of: number; whole: boolean }

export function useChatSend(address?: string) {
  const call = useCall();
  const inContext = useStation().address;
  const station = address ?? inContext;
  return useMemo(() => ({
    send: (to: ChatTo, text: string, attachments: Attachment[], quotes: Quote[], uploads: { id: string; name: string; size: number; width?: number; height?: number }[] = []) => call("chat.send", { station, ...chatTo(to), text, attachments, quotes, uploads }),
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
    /** The chat's window about one of its messages (`chat.around`): a page on either side, read where not held. */
    around: (thread: number, seq: number) => call("chat.around", { station, thread, seq }),
    /** The chat's messages that have every word of `query` (`chat.find`), oldest first; `bring`: what is not on the
     *  device is read first. */
    find: (thread: number, query: string, bring = false) => call("chat.find", { station, thread, query, bring }) as Promise<ChatFound>,
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
