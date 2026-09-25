// Shapes of the admin API responses, shared with the web client (type-only imports).
import type { RuntimeKind } from "../config.ts";
import type { BotState } from "../bots.ts";
import type { TimelineEntry } from "../transcript.ts";

export type { BotState, RuntimeKind, TimelineEntry };

export type ProcessState = "running" | "warm" | "cold";

export interface BotView {
  id: string;
  name: string;
  enabled: boolean;
  runtime: RuntimeKind;
  profiles: string[];
  model: string | null;
  /** Masked; empty when unset. */
  slack: { appToken: string; botToken: string };
  connection: BotState;
  sessions: number;
}

export interface EnvView {
  key: string;
  secret: boolean;
  /** Masked when secret. */
  value: string;
}

export interface ProfileView {
  id: string;
  runtime: RuntimeKind;
  home: string;
  homeExists: boolean;
  model: string | null;
  env: EnvView[];
  usedBy: string[];
}

export interface ProcessView {
  pgid: number;
  startedAt: number;
  runtime: RuntimeKind;
  label: string;
  rssMb: number | null;
}

export interface Overview {
  bots: BotView[];
  profiles: ProfileView[];
  processes: ProcessView[];
  counts: { sessions: number; running: number; warm: number };
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
  bot: string;
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
  bot: string;
  channel: string;
  ts: string;
  sessionKey: string;
  user: string;
  text: string;
  status: "pending" | "delivered";
  receivedAt: number;
}

export interface SessionDetail {
  session: SessionSummary;
  turns: TurnRecord[];
  inbound: InboundView[];
  transcript: { path: string; timeline: TimelineEntry[] } | null;
}

/** PUT /bots/:id. Blank or missing tokens keep the stored ones. */
export interface BotInput {
  name?: string;
  enabled?: boolean;
  runtime?: RuntimeKind;
  profiles?: string[];
  model?: string;
  slack?: { appToken?: string; botToken?: string };
}

/** PUT /profiles/:id. env: a string sets, null removes, an omitted key is kept. */
export interface ProfileInput {
  runtime?: RuntimeKind;
  home?: string;
  model?: string;
  env?: Record<string, string | null>;
}
