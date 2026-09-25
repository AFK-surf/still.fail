// Reads a runtime's own session transcript into one readable timeline for the
// admin page. Formats (pinned against real files, 2026-09):
// - claude: $CLAUDE_CONFIG_DIR/projects/<cwd>/<id>.jsonl, lines of
//   {type: user|assistant, message: {content: string | blocks}, isSidechain}
// - codex:  $CODEX_HOME/sessions/**/rollout-*<id>.jsonl, lines of
//   {type: response_item, payload: message | reasoning | function_call | …}
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { RuntimeKind } from "./config.ts";

export interface TimelineEntry {
  at: string | null;
  kind: "user" | "assistant" | "thinking" | "tool_call" | "tool_result";
  text: string;
  /** Tool name for tool_call entries. */
  tool?: string;
  /** For tool_result: false when the tool reported an error. */
  ok?: boolean;
  /** Links a tool_call to its tool_result. */
  callId?: string;
  /** Produced by a subagent rather than the main conversation. */
  subagent?: boolean;
}

const MAX_TEXT = 4000;

export function transcriptPath(runtime: RuntimeKind, home: string, runtimeSessionId: string): string | undefined {
  if (runtime === "claude") {
    const projects = join(home, "projects");
    if (!existsSync(projects)) return undefined;
    for (const dir of readdirSync(projects)) {
      const path = join(projects, dir, `${runtimeSessionId}.jsonl`);
      if (existsSync(path)) return path;
    }
    return undefined;
  }
  const sessions = join(home, "sessions");
  if (!existsSync(sessions)) return undefined;
  const match = readdirSync(sessions, { recursive: true, withFileTypes: true })
    .find((e) => e.isFile() && e.name.startsWith("rollout-") && e.name.endsWith(`${runtimeSessionId}.jsonl`));
  return match ? join(match.parentPath, match.name) : undefined;
}

export interface TranscriptUsage {
  /** Model requests with reported usage. */
  modelCalls: number;
  /** Input tokens, cached ones included. */
  inputTokens: number;
  cachedTokens: number;
  outputTokens: number;
  /** The model the runtime last reported, if any. */
  model: string | null;
}

function records(path: string): Record<string, any>[] {
  return readFileSync(path, "utf8").split("\n").filter(Boolean).flatMap((line) => {
    try {
      return [JSON.parse(line) as Record<string, any>];
    } catch {
      return []; // a line still being written
    }
  });
}

export function readTimeline(runtime: RuntimeKind, path: string): TimelineEntry[] {
  return runtime === "claude" ? claudeTimeline(records(path)) : codexTimeline(records(path));
}

/** Token usage summed over the transcript's model requests. */
export function readUsage(runtime: RuntimeKind, path: string): TranscriptUsage {
  const usage: TranscriptUsage = { modelCalls: 0, inputTokens: 0, cachedTokens: 0, outputTokens: 0, model: null };
  if (runtime === "claude") {
    // One API response is split over several lines that share message.id and usage.
    const seen = new Set<string>();
    for (const r of records(path)) {
      const m = r.type === "assistant" ? r.message : undefined;
      if (!m?.usage || !m.id || seen.has(m.id)) continue;
      seen.add(m.id);
      const cached = (m.usage.cache_read_input_tokens ?? 0) + (m.usage.cache_creation_input_tokens ?? 0);
      usage.modelCalls++;
      usage.inputTokens += (m.usage.input_tokens ?? 0) + cached;
      usage.cachedTokens += m.usage.cache_read_input_tokens ?? 0;
      usage.outputTokens += m.usage.output_tokens ?? 0;
      if (typeof m.model === "string" && m.model !== "<synthetic>") usage.model = m.model;
    }
    return usage;
  }
  for (const r of records(path)) {
    const p = r.payload ?? {};
    if (r.type === "turn_context" && typeof p.model === "string") usage.model = p.model;
    const last = r.type === "event_msg" && p.type === "token_count" ? p.info?.last_token_usage : undefined;
    if (!last) continue;
    usage.modelCalls++;
    usage.inputTokens += last.input_tokens ?? 0;
    usage.cachedTokens += last.cached_input_tokens ?? 0;
    usage.outputTokens += last.output_tokens ?? 0;
  }
  return usage;
}

function clip(text: string): string {
  return text.length > MAX_TEXT ? `${text.slice(0, MAX_TEXT)}\n… (${text.length - MAX_TEXT} more characters)` : text;
}

function toText(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map((v) => (typeof v === "object" && v && "text" in v ? String(v.text) : toText(v))).join("\n");
  return JSON.stringify(value, null, 2);
}

function claudeTimeline(records: Record<string, any>[]): TimelineEntry[] {
  const out: TimelineEntry[] = [];
  for (const r of records) {
    if ((r.type !== "user" && r.type !== "assistant") || r.isMeta) continue;
    const at = typeof r.timestamp === "string" ? r.timestamp : null;
    const base = r.isSidechain ? { at, subagent: true } : { at };
    const content = r.message?.content;
    if (typeof content === "string") {
      out.push({ ...base, kind: r.type, text: clip(content) });
      continue;
    }
    for (const block of Array.isArray(content) ? content : []) {
      if (block.type === "text" && block.text) out.push({ ...base, kind: r.type, text: clip(block.text) });
      else if (block.type === "thinking" && block.thinking) out.push({ ...base, kind: "thinking", text: clip(block.thinking) });
      else if (block.type === "tool_use") {
        out.push({ ...base, kind: "tool_call", tool: String(block.name), text: clip(JSON.stringify(block.input, null, 2)), ...(block.id ? { callId: String(block.id) } : {}) });
      } else if (block.type === "tool_result") {
        out.push({ ...base, kind: "tool_result", ok: !block.is_error, text: clip(toText(block.content)), ...(block.tool_use_id ? { callId: String(block.tool_use_id) } : {}) });
      }
    }
  }
  return out;
}

/** Codex prepends context it generated itself as user messages; they are not what anyone said. */
const INJECTED = /^\s*<(environment_context|user_instructions|permissions|skills_instructions|collaboration_mode)\b/;

function codexTimeline(records: Record<string, any>[]): TimelineEntry[] {
  const out: TimelineEntry[] = [];
  for (const r of records) {
    if (r.type !== "response_item") continue;
    const p = r.payload ?? {};
    const at = typeof r.timestamp === "string" ? r.timestamp : null;
    if (p.type === "message" && (p.role === "user" || p.role === "assistant")) {
      const text = toText(p.content);
      if (p.role === "user" && INJECTED.test(text)) continue;
      if (text.trim()) out.push({ at, kind: p.role, text: clip(text) });
    } else if (p.type === "reasoning") {
      const text = toText(p.content?.length ? p.content : p.summary ?? []);
      if (text.trim()) out.push({ at, kind: "thinking", text: clip(text) });
    } else if (p.type === "function_call" || p.type === "custom_tool_call") {
      let args: string = String(p.arguments ?? p.input ?? "");
      try {
        args = JSON.stringify(JSON.parse(args), null, 2);
      } catch {
        // not JSON (custom tools take free text); show as is
      }
      out.push({ at, kind: "tool_call", tool: String(p.name), text: clip(args), ...(p.call_id ? { callId: String(p.call_id) } : {}) });
    } else if (p.type === "function_call_output" || p.type === "custom_tool_call_output") {
      const text = toText(p.output);
      const failed = /Process exited with code [1-9]/.test(text);
      out.push({ at, kind: "tool_result", ok: !failed, text: clip(text), ...(p.call_id ? { callId: String(p.call_id) } : {}) });
    }
  }
  return out;
}
