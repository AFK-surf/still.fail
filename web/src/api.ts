import { bindStationOperations } from "./core/operations.ts";
// A station's data, through the client core (docs/client-core.md): screens
// subscribe to the views the core puts together; what they have done is a
// call by its name (client/core-ts/src/ops.ts), never a request made here, and the
// core brings whatever it touches up to date before it answers. Types come
// from client/core-ts/src/shapes/schema.ts (core/shapes.ts); what is only sent to a station is
// declared here.
import { type TopicState } from "./core/react.ts";
import { CoreError } from "./core/client.ts";
import type { Attachment, Overview, Stamp, ChatThread } from "./core/shapes.ts";
import type { AccessKind, ConnectMode, Job, LoginJob, ProfileCheck, Quota, RuntimeKind, SlackAppLinks, SlackIdentity } from "./core/shapes.ts";
import type { PublishPreview } from "./core/shapes.ts";
import { t } from "./i18n.ts";

export type { TopicState };
export { CoreError };

// ── what is sent to a station (its admin API's inputs) ──

export type ConnectKind = "slack" | "feishu";

/** POST /connects, PUT /connects/:id. Blank or missing tokens keep the stored ones. */
interface ConnectInput {
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
interface ProfileInput {
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

// ── what the core gives: generated from client/core-ts/src/shapes/schema.ts (core/shapes.ts), nothing hand-written ──

export type * from "./core/shapes.ts";

/** A time of anything the core sent, in words, by its field (for what still.fail cloud sends, which has no shape yet). */
export function stamp(of: object, field: string): Stamp | undefined {
  return (of as { time?: Record<string, Stamp> }).time?.[field];
}


// ── calls ───────────────────────────────────────────────────────────────

interface StationCall {
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

/** How much of a file has come. */
interface FileProgress { loaded: number; total: number | null }

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
interface MachineSaid { person: boolean; text: string; at: number | null }

/** A channel or group a connect's bot is in (docs/relay.md): a Slack channel, a Feishu topic group, a Feishu group; `used`
 * when a chat was last relayed there (ms), if ever. */
export interface RelayPlace { id: string; name: string; kind: "channel" | "topics" | "group"; private?: boolean; used?: number }

/** A connect a chat can be relayed through, with its places (none, and why, when they could not be read). */
export interface RelayConnect { id: string; kind: "slack" | "feishu" | "lark"; name: string; team: string | null; botImage?: string | null; preferred?: boolean; places: RelayPlace[]; error?: string }

/** A person in a place, as a relayed chat's note can mention them (docs/relay.md「附言里 @ 人」). */
export interface RelayPerson { id: string; name: string; aka?: string; picture?: string }

/** Where a chat was relayed: the place's name, and its link where the platform has one. */
export interface Relayed { thread: number; to: string; place: string; link: string | null }

function stationApi(t: StationCall) {
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
    slackPeople: () => ops.slackPeople<{ people: unknown[]; errors: string[] }>(),
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

export { useAction, type Action } from "./action.ts";
