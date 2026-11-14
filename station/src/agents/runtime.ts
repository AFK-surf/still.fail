// The seam between the station and a coding-agent runtime (Claude Code, Codex, DeepSeek Harness, Grok Build, Cursor, Devin, Hermes Agent, Antigravity CLI), as the Rust station's
// runtime/mod.rs has it: everything above is runtime-agnostic. A driver opens sessions; what a session's runtime does
// comes back as events, in order, to the one listener it was opened with. Processes run under runners (./runner.ts): a
// station that starts again takes its sessions up from the runners (`adopt`), from what the previous one left
// (`snapshot`) or, after a crash, from what the runner kept unread.
import { startEnv } from "../ops/agent-env.ts";

/// The runtimes a station runs, in the order they are offered.
export type RuntimeKind = "claude" | "codex" | "dsh" | "grok" | "cursor" | "devin" | "hermes" | "agy";
export const RUNTIME_KINDS: RuntimeKind[] = ["claude", "codex", "dsh", "grok", "cursor", "devin", "hermes", "agy"];
/// A runtime as stored or sent (a name of one of them), none for anything else.
export const runtimeKind = (v: unknown): RuntimeKind | undefined => (RUNTIME_KINDS as unknown[]).includes(v) ? (v as RuntimeKind) : undefined;
/// How a runtime is named to people.
export const runtimeLabel = (r: RuntimeKind) => (r === "claude" ? "Claude Code" : r === "codex" ? "Codex" : r === "dsh" ? "DeepSeek Harness" : r === "grok" ? "Grok Build" : r === "cursor" ? "Cursor" : r === "hermes" ? "Hermes Agent" : r === "agy" ? "Antigravity CLI" : "Devin");

/// What failed a turn, as people are told it (sessions/actor.ts `failureNotice`, the client's `failureText`): the account
/// (`auth`), the provider turning away where the request comes from (`refused`: a region it does not serve, an address
/// or `blocked`: its CDN's firewall turning the address away, said so in its answer), or turning it away without saying why (`denied`: a bare 403), a limit, the provider out of room, the way to it (`network`), the conversation grown past what the model takes
/// (`context`), else the model's own error; the process gone (`exited`), or the station's (`other`).
export type FailureReason = "auth" | "refused" | "blocked" | "denied" | "rate_limit" | "overloaded" | "network" | "context" | "model" | "exited" | "other";

export type TurnOutcome = { kind: "completed" } | { kind: "aborted" } | { kind: "failed"; reason: FailureReason; message: string };

/// A turn's steps as they happen (runtime/mod.rs `LiveEvent`, the same JSON).
export type LiveEvent =
  | { kind: "start"; id: string; step: "text" | "thinking" | "tool"; tool?: string; input?: string; subagent?: boolean; parent?: string }
  /// `tokens`: how many tokens the model wrote by it, where the runtime says so instead of the words (Claude's thinking
  /// left out of the stream, its `estimated_tokens`): the rate counts these in place of guessing them of `text`.
  | { kind: "delta"; id: string; field: "text" | "input" | "output"; text: string; tokens?: number }
  | { kind: "end"; id: string }
  | { kind: "phase"; phase: "starting" | "requesting" | "responding" | "working" }
  /// What it has going in the background now, all of it (said again whenever it changes; none once its process ends).
  | { kind: "tasks"; tasks: BackgroundTask[] }
  /// Its checklist as it said it last, whole (an ACP runtime's `plan` update): a runtime that writes it with a tool
  /// call says it in its transcript instead (read/plan.ts).
  | { kind: "plan"; plan: PlanItem[] };

/// What a session's runtime says, in order.
export type RuntimeEvent =
  /// A turn started without a prompt of ours: input written while the previous turn was finishing became a turn.
  | { type: "turnStarted" }
  | { type: "turnEnded"; outcome: TurnOutcome }
  /// The runtime process (or its shared host) went away; the session is unusable.
  | { type: "closed"; why: string }
  /// The station's tools (its MCP endpoint) failed it as unreachable: what it says through them reaches nobody until its
  /// process starts again.
  | { type: "toolsLost"; why: string }
  /// It compacted its context (on its own as it filled, or asked for by hand): what it had read is now a summary.
  | { type: "compacted" }
  | { type: "live"; event: LiveEvent };

export type Profile = {
  id: string;
  runtime: RuntimeKind;
  /// The profile's home (CLAUDE_CONFIG_DIR / CODEX_HOME / DSH_HOME; Grok Build's GROK_HOME is its grok/, Cursor's keeps cursor/, Devin's devin/).
  home: string;
  /// Whatever else the profile's config says (env, access kind, machine…): read by the drivers as runtime/*.rs do.
  [key: string]: unknown;
};

export type OpenOptions = {
  /// The station's session key: the runner's id is made from it.
  key: string;
  profile: Profile;
  cwd: string;
  /// Runtime-native session id to resume; a new session when absent.
  resume?: string;
  model?: string;
  /// Reasoning effort, in the runtime's own terms.
  effort?: string;
  /// The most context it runs with, in tokens: it compacts on its own at it (sessions/context-cap.ts); none, the
  /// model's whole window. Taken by Claude Code and Codex alone, as they start.
  context?: number;
  /// Fast as the session is set (none: as its profile is), for a runtime that takes it as it starts (Claude Code).
  fast?: boolean;
  /// Appended to the runtime's own system prompt.
  instructions: string;
  /// The skills of the session's workspace (its agent home's skills/, sessions/agent-home.ts), for a runtime that
  /// loads skills from a folder of the session's own (Cursor, Devin); not a session continued from a terminal's.
  skills?: string;
  /// Bearer token the session presents to the station's MCP endpoint.
  mcpToken: string;
  mcpUrl: string;
  /// Stable per-session routing id for provider affinity headers.
  route: string;
  /// An isolated, temporary text-only request. Drivers must explicitly support this without exposing their tools.
  textOnly?: boolean;
};

export interface AgentSession {
  /// Runtime-native id: claude session id, codex thread id, dsh, grok or Devin session id, Cursor's agent id. Persist it to resume.
  id(): string;
  /// The version of the runtime serving this session, when it reports one (it may predate the installed binary).
  runtimeVersion?(): string | null;
  /// Whether the software page updates the executable serving this session.
  runtimeUpdateMatchesStation?(): Promise<boolean>;
  busy(): boolean;
  /// Starts a turn. Fails when a turn is already running (or the runtime cannot take one as it is).
  prompt(text: string): Promise<void>;
  /// Adds input to the running turn. False when nothing is running or the turn cannot take it.
  steer(text: string): Promise<boolean>;
  /// Moves the tool calls the running turn waits on to the background (Claude's ctrl+b); nothing for a runtime that
  /// cannot.
  backgroundTools(): Promise<void>;
  /// Interrupts the running turn; its end still arrives as turnEnded.
  abort(): Promise<void>;
  /// Between turns, compacts its context (asked for by hand): it runs as a turn of its own, whose end arrives as
  /// turnEnded (failed when nothing could be compacted). Absent for a runtime that cannot.
  compact?(): Promise<void>;
  /// Between turns, takes the model and effort of `options` (opened as they were otherwise) from its next turn on,
  /// without a new process. False when it cannot: it is then started again on them.
  retune?(options: OpenOptions): boolean;
  /// Releases the session; ends the runtime process when it is not shared.
  dispose(): Promise<void>;
  /// What a next station needs to take this session up (its turn's state): written by the session layer at handover.
  snapshot(): unknown;
  /// Lets go of the process without ending it (this station stops; a next one adopts it).
  detach(): void;
  /// The address of the station's tools the runtime was given (one taken up from another station: as it was given
  /// then); null when not known.
  mcpUrl?(): string | null;
  /// What it has going in the background past its turns (Claude's background commands and subagents): it ends with
  /// the process, and nothing of it reports back. Empty for a runtime that does not say.
  background?(): BackgroundTask[];
}

/// A background task of a runtime process: a subagent (resumed by its id) or a command; `startedAt` (ms) when it was
/// seen starting, where the runtime says (one from before it was kept says none).
export type BackgroundTask = { id: string; kind: "agent" | "command"; description: string; startedAt?: number };

/// An item of an agent's checklist (Claude Code's todos and tasks, Codex's plan, an ACP plan's entries): what, and
/// where it stands (completed, in_progress, or anything else: still to do).
export type PlanItem = { text: string; status: string };

/// The station's tools by their server's name.
export const TOOL_SERVERS = ["stillfail"];

/// A tool call's error that says the station's tools could not be reached at all (not that the tool refused).
export function unreachable(text: string): boolean {
  return /ECONNREFUSED|ECONNRESET|Unable to connect|is not connected|fetch failed|socket hang up|connection refused|failed to connect to mcp server/i.test(text);
}

/// Whether a call, by the name the station gives it, is to one of the station's tools: an MCP tool's name is
/// mcp__<server>__<tool>, or <server>__<tool> where a runtime calls it so itself (Grok Build).
export const stationTool = (name: string) => TOOL_SERVERS.some((s) => name.startsWith(`mcp__${s}__`) || name.startsWith(`${s}__`));

/// What a runtime's failures say beyond what all of them may: words of its error codes and phrases of its messages that
/// are about its account, or about its limits.
export type FailureWords = { authCodes?: string[]; auth?: string[]; limitCodes?: string[]; limit?: string[] };

/// What its messages (any runtime's) say when it is the account: signed out, a key refused, not allowed.
const AUTH = ["unauthorized", "authenticat", "not logged in", "sign in", "log in", "api key", "permission_denied", "invalid credential"];
/// What they say when the provider turns away where the request comes from, whoever asks: its region. Only what says
/// so: a 403 that does not is `denied`, its cause not known.
const REFUSED = ["request not allowed", "unsupported_country", "unsupported country", "not available in your region", "region is not supported", "not authorized in this region"];
/// What a 403 is answered with when the provider's CDN firewall blocks the address it comes from (its IP's reputation:
/// a datacenter's, a shared proxy's, whatever region): its page (Cloudflare's, HTML where an API answer was due).
const BLOCK_PAGE = ["<html", "<!doctype html", "attention required", "just a moment", "cloudflare"];
/// What they say when it is a limit: of rate, quota or usage.
const LIMIT = ["rate limit", "rate_limit", "quota", "usage limit", "limit reached", "resource_exhausted", "too many requests"];
/// What they say when it is the provider: the model has no room for anyone just now (whatever account asks).
export const OVERLOADED = ["overloaded", "at capacity"];
/// What they say when the conversation no longer fits the model.
/// pi-ai (DeepSeek Harness on a provider's route) says "context overflow" where the provider gave no words of its own,
/// and its code is CONTEXT_WINDOW_EXCEEDED (FB-17).
const CONTEXT = ["context window", "context_window", "context length", "context_length", "context overflow", "prompt is too long", "maximum context", "too many tokens", "input is too long"];
/// What they say when the way to the provider broke: the request not sent, its answer cut off.
const NETWORK = /stream disconnected|error sending request|connection (?:reset|refused|closed|error|failed)|network error|timed out|timeout|ECONNRESET|ECONNREFUSED|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|EPIPE|socket hang up|fetch failed|dns error|tls handshake/i;

/// The model whose own allowance a limit was, as the runtime named it (Claude Code's "You've reached your Fable limit.
/// Switch to another model…", or "You've hit your Fable limit · resets …": Fable has a weekly cap of its own, under the
/// account's), so it is told apart from the account's limit, whose quota then still shows room (#4365); null for the
/// account's own ("your weekly usage limit", "You've hit your weekly limit").
export function modelLimitOf(text: string): string | null {
  const name = /\b(?:reached|hit) your ([\w.\- ]+?) limit\b/i.exec(text)?.[1]?.trim();
  return name && !ACCOUNT_LIMIT.test(name) ? name : null;
}
const ACCOUNT_LIMIT = /\b(?:usage|session|weekly|daily|monthly|spend|rate|\d+[- ]hour)\b/i;

/// The rest of a failure, once neither the account, the provider nor a limit: the network, the conversation's size,
/// else the model.
export function failureRest(text: string): FailureReason {
  const lower = text.toLowerCase();
  if (CONTEXT.some((s) => lower.includes(s))) return "context";
  if (NETWORK.test(text)) return "network";
  return "model";
}

/// What failed a turn, from what the runtime said of it (its error's code first, where it gives one): the account, the
/// provider refusing it, a limit, the provider out of room, else `failureRest`.
export function failureOf(text: string, extra: FailureWords = {}): FailureReason {
  const lower = text.toLowerCase();
  const words = lower.split(/[^\p{L}\p{N}_]+/u);
  const word = (w: string) => words.includes(w);
  const says = (s: string) => lower.includes(s);
  const account = (more: string[] = []) => [...AUTH, ...(extra.auth ?? []), ...more].some(says);
  // A code decides before any phrase: a limit's message may well mention the account ("upgrade your subscription").
  if (["401", ...(extra.authCodes ?? [])].some(word)) return "auth";
  // A 403 is the account's where it says so, the request's origin where it says that; else not known.
  if (word("403")) return account(["token", "scope"]) ? "auth" : REFUSED.some(says) ? "refused" : BLOCK_PAGE.some(says) ? "blocked" : "denied";
  if (["429", ...(extra.limitCodes ?? [])].some(word)) return "rate_limit";
  if (word("529")) return "overloaded";
  if (REFUSED.some(says)) return "refused";
  if (says("forbidden")) return "denied";
  if (account()) return "auth";
  if ([...LIMIT, ...(extra.limit ?? [])].some(says)) return "rate_limit";
  if (OVERLOADED.some(says)) return "overloaded";
  return failureRest(text);
}

export interface AgentDriver {
  runtime(): RuntimeKind;
  open(options: OpenOptions, events: (event: RuntimeEvent) => void): Promise<AgentSession>;
  /// Takes up a session whose process a runner kept: `snapshot` as the previous station left it, or null after a crash
  /// (then what the runner kept unread says where the turn is). What it does comes to `events` from now on.
  adopt(options: OpenOptions, snapshot: unknown | null, events: (event: RuntimeEvent) => void): Promise<AgentSession>;
  /// Ends every process this driver started.
  shutdown(): Promise<void>;
  /// Lets go of every process without ending them (handover).
  detach(): void;
  /// Holds what is read of its processes for a handover (one read off the station's thread: agents/mb-agents.ts), and
  /// lets it be read on where the handover did not happen.
  freeze?(): Promise<void>;
  thaw?(): void;
}

/// A random UUID (v4), as runtimes take for session ids.
export const uuid = () => crypto.randomUUID();

/// The station's own environment with the variables its owners set for what it starts over it (ops/agent-env.ts), less
/// what would let a runtime authenticate as something other than its profile.
export const cleanEnv = (scrubbed: string[]): Record<string, string> => startEnv(scrubbed);
