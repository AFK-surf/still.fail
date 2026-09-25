// Shapes of the admin API responses, shared with the web client (type-only imports).
import type { RuntimeKind } from "../config.ts";
import type { ConnectKind, ConnectMode } from "../config.ts";
import type { ConnectState } from "../connections.ts";
import type { LoginJob, LoginState } from "../login.ts";
import type { ChatMessageRow, ChatRow } from "../store.ts";
import type { MeshStatus } from "../mesh.ts";
import type { Viewer } from "./access.ts";
import type { AccessKind, ProfileCheck } from "../profiles.ts";
import type { TimelineEntry, TranscriptUsage } from "../transcript.ts";

export type { ChatMessageRow, ChatRow, LoginJob, LoginState, MeshStatus };
export type { AccessKind, ConnectKind, ConnectMode, ConnectState, ProfileCheck, RuntimeKind, TimelineEntry, TranscriptUsage };

export type ProcessState = "running" | "warm" | "cold";

export interface ConnectView {
  id: string;
  name: string;
  enabled: boolean;
  kind: ConnectKind;
  mode: ConnectMode;
  requireMention: boolean;
  bind: { runtime: RuntimeKind; profiles: string[]; model: string | null };
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
  /** Hand-set variables only; the ones an access kind derives are not listed. */
  env: EnvView[];
  usedBy: string[];
  /** Run on the ember host to sign a subscription profile in. */
  loginCommand: string;
  /** Latest check, if one ran since ember started. */
  check: ProfileCheck | null;
  /** The sign-in started from the admin page, running or last finished. */
  login: LoginJob | null;
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
  /** Who started it, resolved for people; filled in lists and details. */
  creator?: Creator | null;
  channel: string;
  threadTs: string;
  runtime: RuntimeKind;
  profile: string;
  model: string | null;
  runtimeSessionId: string | null;
  workspace: string;
  running: boolean;
  createdAt: number;
  lastActiveAt: number;
  process: ProcessState;
  turns: number;
  pending: number;
  firstText: string | null;
  lastTurn: TurnSummary | null;
}

export interface TurnRecord extends TurnSummary {
  id: string;
}

export interface InboundView {
  connect: string;
  channel: string;
  threadTs: string;
  ts: string;
  sessionKey: string;
  user: string;
  text: string;
  status: "pending" | "delivered";
  receivedAt: number;
}

export interface SessionDetail {
  session: SessionSummary;
  /** Display names of the people in its threads, by chat user id, where known. */
  people: Record<string, string>;
  /** Channel names by id, where known; direct messages have none. */
  channels: Record<string, string>;
  /** Chats opened on this session from the admin page, with their messages. */
  chats: (ChatRow & { creator: Creator | null; messages: ChatMessageRow[] })[];
  /** The threads the session has messages from, most recent first. */
  threads: { channel: string; threadTs: string; messages: number; lastTs: string }[];
  turns: TurnRecord[];
  inbound: InboundView[];
  transcript: { path: string; timeline: TimelineEntry[]; usage: TranscriptUsage } | null;
}

/** PUT /connects/:id. Blank or missing tokens keep the stored ones. */
export interface ConnectInput {
  name?: string;
  enabled?: boolean;
  kind?: ConnectKind;
  mode?: ConnectMode;
  requireMention?: boolean;
  bind?: { runtime?: RuntimeKind; profiles?: string[]; model?: string };
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
