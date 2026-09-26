// Shapes of the admin API responses, shared with the web client (type-only imports).
import type { RuntimeKind } from "../config.ts";
import type { ConnectKind, ConnectMode } from "../config.ts";
import type { ConnectState } from "../connections.ts";
import type { LoginJob, LoginState } from "../login.ts";
import type { Attachment, AuthorKind, EntryKind, Membership, Quote } from "../store.ts";
import type { MeshStatus } from "../mesh.ts";
import type { HostInfo } from "../host.ts";
import type { LiveMessage, LivePhaseView, LiveStep } from "../live.ts";
import type { LiveEvent, LivePhase } from "../runtime/types.ts";
import type { ProfileQuota, QuotaWindow } from "../quota.ts";
import type { Viewer } from "./access.ts";
import type { AccessKind, ProfileCheck } from "../profiles.ts";
import type { TimelineEntry, TranscriptUsage } from "../transcript.ts";

export type { LiveEvent, LiveMessage, LivePhase, LivePhaseView, LiveStep };
export type { Attachment, AuthorKind, EntryKind, Membership, Quote, HostInfo, LoginJob, LoginState, MeshStatus, ProfileQuota, QuotaWindow };
export type { AccessKind, ConnectKind, ConnectMode, ConnectState, ProfileCheck, RuntimeKind, TimelineEntry, TranscriptUsage };

export type ProcessState = "running" | "warm" | "cold";

export interface ConnectView {
  id: string;
  name: string;
  enabled: boolean;
  kind: ConnectKind;
  mode: ConnectMode;
  requireMention: boolean;
  bind: { runtime: RuntimeKind; model: string | null; effort: string | null };
  /** Masked; empty when unset. */
  slack: { appToken: string; botToken: string };
  connection: ConnectState;
  /** Who added it from the admin page (an email, or "local"); null for older ones. */
  createdBy: { id: string; name: string } | null;
  sessions: number;
  /** The session a single-session connect delivers into; null until its first message or after "new session". */
  session: string | null;
}

export interface EnvView {
  key: string;
  secret: boolean;
  /** Masked when secret. */
  value: string;
}

export interface ProfileView {
  id: string;
  name: string;
  runtime: RuntimeKind;
  access: { kind: AccessKind; key: string };
  home: string;
  homeExists: boolean;
  model: string | null;
  /** Models enabled for use; only these can be chosen for chats and connects. */
  models: string[];
  /** Hand-set variables only; the ones an access kind derives are not listed. */
  env: EnvView[];
  usedBy: string[];
  /** Run on the ember host to sign a subscription profile in. */
  loginCommand: string;
  /** Latest check; kept across restarts, and checked again at start. */
  check: ProfileCheck | null;
  /** The sign-in started from the admin page, running or last finished. */
  login: LoginJob | null;
  /** How much of the allowance is used, where the provider says; refreshed every few minutes while someone follows /events. */
  quota: ProfileQuota | null;
}

export interface ProcessView {
  pgid: number;
  startedAt: number;
  runtime: RuntimeKind;
  label: string;
  rssMb: number | null;
}

export interface Overview {
  /** Who is looking: a local visit, or the Cloudflare Access identity. */
  viewer: Viewer;
  connects: ConnectView[];
  profiles: ProfileView[];
  processes: ProcessView[];
  counts: { sessions: number; running: number; warm: number };
  /** This station's link to ember cloud; null where ember-mesh is not managed. */
  mesh: MeshStatus | null;
  /** The Slack users the viewer said are them (PUT /me/slack/:user): the station takes them for the viewer. */
  slackUsers: string[];
  /** The workspace's Slack app configuration token: with it, ember makes and edits connects' Slack apps. */
  slackConfig: { configured: boolean; teamId: string | null };
}

export interface TurnSummary {
  kind: string;
  outcome: string | null;
  declared: string | null;
  detail: string | null;
  startedAt: number;
  endedAt: number | null;
}

export interface SessionSummary {
  key: string;
  connect: string;
  /** thread: started by one thread; all: a single-session connect's session. */
  scope: "thread" | "all";
  title: string | null;
  createdBy: string | null;
  /** Single-session connects currently delivering into it. */
  boundTo: string[];
  /** Who started it, resolved for people. */
  creator: Creator | null;
  /** Everyone who wrote in its threads (Slack and ember's chat), once each, earliest first. */
  participants: Creator[];
  runtime: RuntimeKind;
  profile: string;
  model: string | null;
  effort: string | null;
  runtimeSessionId: string | null;
  workspace: string;
  running: boolean;
  createdAt: number;
  lastActiveAt: number;
  /** Hidden from lists (GET /sessions?archived=1 lists these); null while shown. */
  archivedAt: number | null;
  process: ProcessState;
  turns: number;
  /** Messages handed to it that it has not read yet. */
  pending: number;
  /** The first message it heard. */
  firstText: string | null;
  lastTurn: TurnSummary | null;
}

export interface TurnRecord extends TurnSummary {
  id: string;
}

/** GET /sessions/:key. Entries are read per thread; the transcript comes from /sessions/:key/live. */
export interface SessionDetail {
  session: SessionSummary;
  threads: ThreadView[];
  turns: TurnRecord[];
}

/** One entry of a thread's log (GET /threads/:id/entries). Entries never change; the client core merges them into messages. */
export interface EntryView {
  thread: number;
  /** 1, 2, 3 … within the thread, no gaps. */
  n: number;
  kind: EntryKind;
  /** edit: the n of the message it changes. */
  target: number | null;
  /** message: the platform's id (Slack ts). */
  ts: string | null;
  authorKind: AuthorKind;
  /** person: Slack user id, email or "local"; agent: its session key; ember: "ember". */
  author: string;
  /** Who that is in words, where known when the entry was read: a person's name, the name an agent goes by there. */
  authorName: string | null;
  /** message and edit: Markdown. */
  text: string | null;
  /** message and edit: its files and quotes (an edit gives the message's whole new version). */
  attachments: Attachment[];
  quotes: Quote[];
  /** message: final or block, when an agent's post ended its work with it. */
  declared: string | null;
  at: number;
}

/** A message as merged from its thread's entries: its latest edit's words, files and quotes. */
export interface MessageView {
  /** Its entry's n. */
  seq: number;
  thread: number;
  ts: string;
  authorKind: AuthorKind;
  author: string;
  authorName: string | null;
  text: string;
  attachments: Attachment[];
  quotes: Quote[];
  declared: string | null;
  createdAt: number;
  /** When its latest edit came; null if never edited. */
  editedAt: number | null;
}

/** A thread: a Slack thread or a chat on ember's page. */
export interface ThreadView {
  id: number;
  /** "slack:<team id>" or "ember". */
  surface: string;
  channel: string;
  /** A Slack channel's name, where Slack says; null for direct messages and ember's chats. */
  channelName: string | null;
  threadTs: string;
  title: string | null;
  createdBy: string | null;
  creator: Creator | null;
  createdAt: number;
  /** The sessions taking part, and the connect each posts through. */
  sessions: Membership[];
  /** Its last entry number, 0 before anything is said: follow it with GET /threads/:id/entries?after=. */
  last: number;
  /** The latest message as merged, for lists. */
  lastMessage: MessageView | null;
  /** The viewer's read position (an entry number), 0 if never read. */
  read: number;
  /** Messages after it that are not the viewer's own (nor of a Slack user they are). */
  unread: number;
  /** Everyone who wrote in it (Slack or ember's page), once each, earliest first. */
  people: Creator[];
  /** The first thing a person said in it (up to 300 characters), for a title. */
  firstText: string | null;
}

/** GET /threads/:id/entries. */
export interface ThreadEntries {
  /** The thread's last entry number when this was read. */
  last: number;
  entries: EntryView[];
}

/** An agent of an item of the sidebar: what it runs on and where its work stands. */
export type ChatRowAgent = Pick<SessionSummary, "key" | "runtime" | "model" | "effort" | "process" | "pending" | "lastTurn">;

/**
 * An item of the sidebar, for one viewer (GET /chats): an agent merged with its internal chat. Before the agent has
 * an internal chat, `thread` is null and the chat is made with the first message. A Slack thread is no item: it only
 * lends its agent's item a title (while the chat has no words of its own), the connect and the origin.
 */
export interface ChatRow {
  /** Where its page is, unique on the station: its chat's thread id, or its session's key while it has no chat. */
  id: string;
  /** Its agent (the first of its chat's). */
  session: string;
  /** Its internal chat; null until the first message makes it. */
  thread: number | null;
  title: string;
  agents: ChatRowAgent[];
  /** The internal chat's latest message, its text cut to 200 characters; null without a chat. */
  last: (Pick<MessageView, "seq" | "authorKind" | "author" | "authorName" | "createdAt"> & { text: string }) | null;
  /** Something after the viewer's read position that is not their own. */
  unread: boolean;
  /** The viewer takes part: started it, wrote in it or is among its people (as themselves or a Slack user they are). */
  mine: boolean;
  lastActiveAt: number;
  /** The connect its agent came from; null for one made on ember. */
  connect: string | null;
  /** The Slack thread its agent came from. */
  origin: { teamName: string | null; channel: string; channelName: string | null; threadTs: string } | null;
}

/** What GET /events sends, by event name. */
export interface StationEvents {
  session: SessionSummary;
  "session-removed": { key: string };
  /** Entries appended to a thread, contiguous and in order; none when its sessions changed. */
  thread: { id: number; entries: EntryView[] };
  /** A thread went, with all its entries: clients drop what they keep of it. */
  "thread-removed": { id: number };
  /** Only to the viewer it is about. */
  read: { viewer: string; thread: number; n: number };
  /** An item of the viewer's sidebar, new or changed; only to that viewer. */
  chat: ChatRow;
  /** An item gone from the viewer's sidebar. */
  "chat-removed": { id: string };
  overview: Overview;
  /** Only to streams opened with ?host=1. */
  host: HostInfo;
  /** A session the stream was opened for (`?live=<key>&from=<n>`), as it runs: LiveMessage with its key. */
  live: LiveMessage & { key: string };
}

/** PUT /connects/:id. Blank or missing tokens keep the stored ones. */
export interface ConnectInput {
  name?: string;
  enabled?: boolean;
  kind?: ConnectKind;
  mode?: ConnectMode;
  requireMention?: boolean;
  bind?: { runtime?: RuntimeKind; model?: string; effort?: string };
  slack?: { appToken?: string; botToken?: string };
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
}

/** Who started a session or chat, or added a connect. `email` ties them to an ember cloud account. */
export interface Creator {
  /** "local", an email, or "slack:<connect>:<user>". */
  id: string;
  name: string;
  email: string | null;
  via: "local" | "cloud" | "slack";
}
