// Claude Code driver: one `claude -p` stream-json process per session.
//
// Behaviour pinned by spikes (spike/README.md) and oar's claude notes:
// - a turn is framed by system/init … result; `result.is_error` decides
//   success, not `subtype` (an auth failure ends as subtype "success");
// - 401/403 is retried silently for minutes, visible only as
//   system/api_retry frames, so the first one fails the turn;
// - input written while a turn is finishing may start a turn of its own
//   (a system/init with no prompt of ours);
// - interrupt is a control_request; the turn still ends with a result frame.
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { expandRoute } from "../config.ts";
import { log } from "../log.ts";
import { spawnGroup, type ProcessRegistry } from "./process.ts";
import type { AgentDriver, AgentSession, FailureReason, LiveEvent, LiveStepKind, OpenOptions, SessionEvents, TurnOutcome } from "./types.ts";

const MCP_TOKEN_VAR = "EMBER_MCP_TOKEN";
/** Inherited variables that would let a session authenticate as something other than its profile. */
const SCRUBBED = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CONFIG_DIR", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"];

export function userMessage(text: string): string {
  return JSON.stringify({ type: "user", message: { role: "user", content: [{ type: "text", text }] } });
}

/** Claude keeps a session at $CLAUDE_CONFIG_DIR/projects/<encoded cwd>/<id>.jsonl. */
export function transcriptExists(home: string, sessionId: string): boolean {
  const projects = join(home, "projects");
  if (!existsSync(projects)) return false;
  return readdirSync(projects, { withFileTypes: true })
    .some((dir) => dir.isDirectory() && existsSync(join(projects, dir.name, `${sessionId}.jsonl`)));
}

export function classifyResult(text: string): FailureReason {
  if (/\b(401|403)\b|authenticat|api key/i.test(text)) return "auth";
  if (/\b429\b|rate.?limit|usage limit|overloaded/i.test(text)) return "rate_limit";
  return "model";
}

export class ClaudeDriver implements AgentDriver {
  readonly runtime = "claude" as const;
  readonly #registry: ProcessRegistry;
  readonly #command: string;
  readonly #live = new Set<AgentSession>();

  constructor(registry: ProcessRegistry, command = "claude") {
    this.#registry = registry;
    this.#command = command;
  }

  async open(options: OpenOptions, events: SessionEvents): Promise<AgentSession> {
    mkdirSync(options.profile.home, { recursive: true });
    if (options.resume && !transcriptExists(options.profile.home, options.resume)) {
      // claude would start and exit at once; failing here lets the caller start fresh.
      throw new Error(`no claude transcript for session ${options.resume}`);
    }
    const sessionId = options.resume ?? randomUUID();
    const mcpConfig = {
      mcpServers: { ember: { type: "http", url: options.mcpUrl, headers: { Authorization: `Bearer \${${MCP_TOKEN_VAR}}` } } },
    };
    const model = options.model ?? options.profile.model;
    const args = [
      "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
      "--dangerously-skip-permissions",
      ...(options.resume ? ["--resume", sessionId] : ["--session-id", sessionId]),
      ...(model ? ["--model", model] : []),
      ...(options.effort ? ["--effort", options.effort] : []),
      "--append-system-prompt", options.instructions,
      "--mcp-config", JSON.stringify(mcpConfig),
    ];
    const env: NodeJS.ProcessEnv = { ...process.env };
    for (const name of SCRUBBED) delete env[name];
    Object.assign(env, expandRoute(options.profile.env, options.route), {
      CLAUDE_CONFIG_DIR: options.profile.home,
      [MCP_TOKEN_VAR]: options.mcpToken,
      // Lets the agent name its own transcript, e.g. for an independent reviewer (codex has CODEX_THREAD_ID).
      EMBER_RUNTIME_SESSION_ID: sessionId,
    });

    let busy = false;
    let aborting = false;
    let authFailure: string | null = null;
    let closed = false;

    const endTurn = (outcome: TurnOutcome) => {
      busy = false;
      aborting = false;
      authFailure = null;
      events.turnEnded(outcome);
    };
    const live = liveFromClaude((event) => events.live?.(event));

    const proc = spawnGroup({
      command: this.#command, args, cwd: options.cwd, env,
      runtime: "claude", label: `claude ${sessionId}`, registry: this.#registry,
      onLine: (line) => {
        let frame: Record<string, any>;
        try {
          frame = JSON.parse(line) as Record<string, any>;
        } catch {
          log.debug("claude non-json line", { line: line.slice(0, 500) });
          return;
        }
        live(frame);
        if (frame.type === "system" && frame.subtype === "init" && !busy) {
          busy = true;
          events.turnStarted();
        } else if (frame.type === "system" && frame.subtype === "api_retry") {
          const status = Number(frame.error_status);
          if ((status === 401 || status === 403) && authFailure === null) {
            authFailure = `${status} ${String(frame.error ?? "authentication failed")}`;
            void session.abort();
          }
        } else if (frame.type === "result") {
          const text = String(frame.result ?? frame.subtype ?? "");
          if (authFailure !== null) endTurn({ kind: "failed", reason: "auth", message: authFailure });
          else if (aborting) endTurn({ kind: "aborted" });
          else if (frame.is_error) endTurn({ kind: "failed", reason: classifyResult(text), message: text.slice(0, 1000) });
          else endTurn({ kind: "completed" });
        }
      },
    });

    void proc.exited.then((code) => {
      closed = true;
      this.#live.delete(session);
      if (busy) endTurn({ kind: "failed", reason: "exited", message: `claude exited (${code}) during the turn` });
      events.closed(`claude exited (${code})`);
    });

    const session: AgentSession = {
      id: sessionId,
      get busy() { return busy; },
      async prompt(text) {
        if (closed) throw new Error("claude session is closed");
        if (busy) throw new Error("a turn is already running");
        busy = true;
        proc.write(userMessage(text));
      },
      async steer(text) {
        if (closed || !busy) return false;
        proc.write(userMessage(text));
        return true;
      },
      async abort() {
        if (closed || !busy || aborting) return;
        aborting = true;
        proc.write(JSON.stringify({ type: "control_request", request_id: `interrupt-${randomUUID()}`, request: { subtype: "interrupt" } }));
      },
      async dispose() {
        await proc.kill();
      },
    };
    this.#live.add(session);
    return session;
  }

  async shutdown(): Promise<void> {
    await Promise.all([...this.#live].map((s) => s.dispose()));
  }
}

/**
 * Claude Code's partial messages (--include-partial-messages) as live steps.
 * Each content block of a model response is a step: text and thinking end
 * with their block; a tool call ends when its result comes back, which also
 * carries the output (Claude Code does not stream tool output).
 */
export function liveFromClaude(emit: (event: LiveEvent) => void): (frame: Record<string, any>) => void {
  let message = "";
  const blocks = new Map<number, { id: string; step: LiveStepKind }>();
  const tools = new Set<string>();
  return (frame) => {
    if (frame.type === "system" && frame.subtype === "status" && frame.status === "requesting") {
      emit({ kind: "phase", phase: "requesting" });
    } else if (frame.type === "stream_event") {
      const e = frame.event ?? {};
      // A sub-agent's steps name the tool call (Task/Agent) that started it.
      const subagent = frame.parent_tool_use_id ? { subagent: true, parent: String(frame.parent_tool_use_id) } : {};
      if (e.type === "message_stop" && !frame.parent_tool_use_id) emit({ kind: "phase", phase: "working" });
      if (e.type === "message_start") {
        message = String(e.message?.id ?? `${Date.now()}`);
        blocks.clear();
        if (!frame.parent_tool_use_id) emit({ kind: "phase", phase: "responding" });
      } else if (e.type === "content_block_start") {
        const b = e.content_block ?? {};
        const step: LiveStepKind | null = b.type === "text" ? "text" : b.type === "thinking" ? "thinking" : b.type === "tool_use" ? "tool" : null;
        if (!step) return;
        const id = step === "tool" && b.id ? String(b.id) : `${message}:${e.index}`;
        blocks.set(Number(e.index), { id, step });
        if (step === "tool") tools.add(id);
        emit({ kind: "start", id, step, ...(step === "tool" ? { tool: String(b.name ?? "tool") } : {}), ...subagent });
      } else if (e.type === "content_block_delta") {
        const block = blocks.get(Number(e.index));
        const d = e.delta ?? {};
        if (!block) return;
        if (d.type === "text_delta" && d.text) emit({ kind: "delta", id: block.id, field: "text", text: String(d.text) });
        else if (d.type === "thinking_delta" && d.thinking) emit({ kind: "delta", id: block.id, field: "text", text: String(d.thinking) });
        else if (d.type === "input_json_delta" && d.partial_json) emit({ kind: "delta", id: block.id, field: "input", text: String(d.partial_json) });
      } else if (e.type === "content_block_stop") {
        const block = blocks.get(Number(e.index));
        if (block && block.step !== "tool") emit({ kind: "end", id: block.id });
      }
    } else if (frame.type === "user" && Array.isArray(frame.message?.content)) {
      for (const c of frame.message.content) {
        if (c?.type !== "tool_result" || !tools.has(String(c.tool_use_id))) continue;
        const id = String(c.tool_use_id);
        const text = typeof c.content === "string" ? c.content : Array.isArray(c.content) ? c.content.map((x: any) => x?.text ?? "").join("\n") : "";
        if (text) emit({ kind: "delta", id, field: "output", text: text.slice(0, 8000) });
        emit({ kind: "end", id });
        tools.delete(id);
      }
    }
  };
}
