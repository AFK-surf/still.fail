// The seam between the station and a coding-agent runtime (Claude Code, Codex, DeepSeek Harness, Grok Build, Cursor, Devin), as the Rust station's
// runtime/mod.rs has it: everything above is runtime-agnostic. A driver opens sessions; what a session's runtime does
// comes back as events, in order, to the one listener it was opened with. Processes run under runners (./runner.ts): a
// station that starts again takes its sessions up from the runners (`adopt`), from what the previous one left
// (`snapshot`) or, after a crash, from what the runner kept unread.
import { startEnv } from "../ops/agent-env.ts";

/// The runtimes a station runs, in the order they are offered.
export type RuntimeKind = "claude" | "codex" | "dsh" | "grok" | "cursor" | "devin" | "hermes";
export const RUNTIME_KINDS: RuntimeKind[] = ["claude", "codex", "dsh", "grok", "cursor", "devin", "hermes"];
/// A runtime as stored or sent (a name of one of them), none for anything else.
export const runtimeKind = (v: unknown): RuntimeKind | undefined => (RUNTIME_KINDS as unknown[]).includes(v) ? (v as RuntimeKind) : undefined;
/// How a runtime is named to people.
export const runtimeLabel = (r: RuntimeKind) => (r === "claude" ? "Claude Code" : r === "codex" ? "Codex" : r === "dsh" ? "DeepSeek Harness" : r === "grok" ? "Grok Build" : r === "cursor" ? "Cursor" : r === "hermes" ? "Hermes Agent" : "Devin");

export type FailureReason = "auth" | "refused" | "rate_limit" | "overloaded" | "model" | "exited" | "other";

export type TurnOutcome = { kind: "completed" } | { kind: "aborted" } | { kind: "failed"; reason: FailureReason; message: string };

/// A turn's steps as they happen (runtime/mod.rs `LiveEvent`, the same JSON).
export type LiveEvent =
  | { kind: "start"; id: string; step: "text" | "thinking" | "tool"; tool?: string; input?: string; subagent?: boolean; parent?: string }
  | { kind: "delta"; id: string; field: "text" | "input" | "output"; text: string }
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
  /// Appended to the runtime's own system prompt.
  instructions: string;
  /// Directories it works with besides its own (a preset's, sessions/presets.ts): a runtime that can be given more
  /// gets them (their instructions and skills loaded as its own directory's are); the instructions name them anyway.
  dirs?: string[];
  /// Bearer token the session presents to the station's MCP endpoint.
  mcpToken: string;
  mcpUrl: string;
  /// Stable per-session routing id for provider affinity headers.
  route: string;
};

export interface AgentSession {
  /// Runtime-native id: claude session id, codex thread id, dsh, grok or Devin session id, Cursor's agent id. Persist it to resume.
  id(): string;
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

/// The station's tools by their server's name (before the rename: ember).
export const TOOL_SERVERS = ["stillfail", "ember"];

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
/// What they say when it is a limit: of rate, quota or usage.
const LIMIT = ["rate limit", "rate_limit", "quota", "usage limit", "limit reached", "resource_exhausted", "too many requests"];
/// What they say when it is the provider: the model has no room for anyone just now (whatever account asks).
export const OVERLOADED = ["overloaded", "at capacity"];

/// What failed a turn, from what the runtime said of it (its error's code first, where it gives one): the account, a
/// limit, the provider out of room, or else the model.
export function failureOf(text: string, extra: FailureWords = {}): FailureReason {
  const lower = text.toLowerCase();
  const words = lower.split(/[^\p{L}\p{N}_]+/u);
  const word = (w: string) => words.includes(w);
  const says = (s: string) => lower.includes(s);
  // A code decides before any phrase: a limit's message may well mention the account ("upgrade your subscription").
  if (["401", "403", ...(extra.authCodes ?? [])].some(word)) return "auth";
  if (["429", ...(extra.limitCodes ?? [])].some(word)) return "rate_limit";
  if (word("529")) return "overloaded";
  if ([...AUTH, ...(extra.auth ?? [])].some(says)) return "auth";
  if ([...LIMIT, ...(extra.limit ?? [])].some(says)) return "rate_limit";
  if (OVERLOADED.some(says)) return "overloaded";
  return "model";
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
}

/// A random UUID (v4), as runtimes take for session ids.
export const uuid = () => crypto.randomUUID();

/// The station's own environment with the variables its owners set for what it starts over it (ops/agent-env.ts), less
/// what would let a runtime authenticate as something other than its profile.
export const cleanEnv = (scrubbed: string[]): Record<string, string> => startEnv(scrubbed);
