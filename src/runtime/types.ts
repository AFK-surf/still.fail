// The seam between ember and a coding-agent runtime. Everything above this
// file is runtime-agnostic.
import type { Profile, RuntimeKind } from "../config.ts";

export type FailureReason = "auth" | "rate_limit" | "model" | "exited" | "other";

export type TurnOutcome =
  | { kind: "completed" }
  | { kind: "aborted" }
  | { kind: "failed"; reason: FailureReason; message: string };

export interface OpenOptions {
  profile: Profile;
  cwd: string;
  /** Runtime-native session id to resume; a new session when absent. */
  resume?: string;
  model?: string;
  /** Reasoning effort, in the runtime's own terms. */
  effort?: string;
  /** Appended to the runtime's own system prompt. */
  instructions: string;
  /** Bearer token the session presents to ember's MCP endpoint. */
  mcpToken: string;
  mcpUrl: string;
  /** Stable per-session routing id for provider affinity headers. */
  route: string;
}

export interface SessionEvents {
  /**
   * A turn started without a prompt of ours: input written while the previous
   * turn was finishing became a turn of its own.
   */
  turnStarted(): void;
  turnEnded(outcome: TurnOutcome): void;
  /** The runtime process (or its shared host) went away; the session is unusable. */
  closed(reason: string): void;
}

export interface AgentSession {
  /** Runtime-native id: claude session id, codex thread id. Persist it to resume. */
  readonly id: string;
  readonly busy: boolean;
  /** Starts a turn. Throws when a turn is already running. */
  prompt(text: string): Promise<void>;
  /** Adds input to the running turn. False when nothing is running or the turn cannot take it. */
  steer(text: string): Promise<boolean>;
  /** Interrupts the running turn; its end still arrives through turnEnded. */
  abort(): Promise<void>;
  /** Releases the session; ends the runtime process when it is not shared. */
  dispose(): Promise<void>;
}

export interface AgentDriver {
  readonly runtime: RuntimeKind;
  open(options: OpenOptions, events: SessionEvents): Promise<AgentSession>;
  /** Ends every process this driver started. */
  shutdown(): Promise<void>;
}
