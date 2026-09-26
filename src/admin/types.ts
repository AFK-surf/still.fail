// Shapes of the admin API responses, shared with the web client (type-only imports).
import type { RuntimeKind } from "../config.ts";
import type { ConnectKind, ConnectMode } from "../config.ts";
import type { ConnectState } from "../connections.ts";
import type { LoginJob, LoginState } from "../login.ts";
import type { Attachment, AuthorKind, Membership, Quote } from "../store.ts";
import type { MeshStatus } from "../mesh.ts";
import type { HostInfo } from "../host.ts";
import type { LiveMessage, LivePhaseView, LiveStep } from "../live.ts";
import type { LiveEvent, LivePhase } from "../runtime/types.ts";
import type { ProfileQuota, QuotaWindow } from "../quota.ts";
import type { Viewer } from "./access.ts";
import type { AccessKind, ProfileCheck } from "../profiles.ts";
import type { TimelineEntry, TranscriptUsage } from "../transcript.ts";

export type { LiveEvent, LiveMessage, LivePhase, LivePhaseView, LiveStep };
export type { Attachment, AuthorKind, Membership, Quote, HostInfo, LoginJob, LoginState, MeshStatus, ProfileQuota, QuotaWindow };
export type { AccessKind, ConnectKind, ConnectMode, ConnectState, ProfileCheck, RuntimeKind, TimelineEntry, TranscriptUsage };

export type ProcessState = "running" | "warm" | "cold";

export interface ConnectView {
  id: string;
  name: string;
  enabled: boolean;
  kind: ConnectKind;
  mode: ConnectMode;
  requireMention: boolean;
  bind: { runtime: RuntimeKind; profiles: string[]; model: string | null; effort: string | null };
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

/** GET /sessions/:key. Messages are read per thread; the transcript comes from /sessions/:key/live. */
export interface SessionDetail {
  session: SessionSummary;
  threads: ThreadView[];
  turns: TurnRecord[];
}

/** Something said in a thread. */
export interface MessageView {
  /** Orders the thread; `before` pages back by it. */
  seq: number;
  /** The change cursor; `after` follows it. Grows on every insert, edit and delete, across threads. */
  rev: number;
  thread: number;
  ts: string;
  authorKind: AuthorKind;
  /** person: Slack user id, email or "local"; agent: its session key; ember: "ember". */
  author: string;
  /** Who that is in words, where known: a person's name, the name an agent goes by there. */
  authorName: string | null;
  /** Markdown; empty once deleted. */
  text: string;
  attachments: Attachment[];
  quotes: Quote[];
  /** final or block, when an agent's post ended its work with it. */
  declared: string | null;
  createdAt: number;
  editedAt: number | null;
  deletedAt: number | null;
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
  last: MessageView | null;
  /** The thread's latest rev: follow it with GET /threads/:id/messages?after=. */
  rev: number;
  /** The viewer's read position (a seq), 0 if never read. */
  read: number;
  /** Messages after it, not deleted and not the viewer's own. */
  unread: number;
}

/** GET /threads/:id/messages. */
export interface ThreadMessages {
  /** The thread's latest rev when this was read: ask `after` it next. */
  rev: number;
  messages: MessageView[];
  /** A page back through history (`before`, or no cursor) may have older messages before it. */
  more: boolean;
}

/** What GET /events sends, by event name. */
export interface StationEvents {
  session: SessionSummary;
  "session-removed": { key: string };
  thread: { id: number; rev: number; messages: MessageView[] };
  /** Only to the viewer it is about. */
  read: { viewer: string; thread: number; seq: number };
  overview: Overview;
  /** Only to streams opened with ?host=1. */
  host: HostInfo;
}

/** PUT /connects/:id. Blank or missing tokens keep the stored ones. */
export interface ConnectInput {
  name?: string;
  enabled?: boolean;
  kind?: ConnectKind;
  mode?: ConnectMode;
  requireMention?: boolean;
  bind?: { runtime?: RuntimeKind; profiles?: string[]; model?: string; effort?: string };
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
