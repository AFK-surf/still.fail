// Reads a runtime's own session transcript into one readable timeline for the
// admin page. Formats (pinned against real files, 2026-09):
// - claude: $CLAUDE_CONFIG_DIR/projects/<cwd>/<id>.jsonl, lines of
//   {type: user|assistant, message: {content: string | blocks}, isSidechain}
// - codex:  $CODEX_HOME/sessions/**/rollout-*<id>.jsonl, lines of
//   {type: response_item, payload: message | reasoning | function_call | …}
import { closeSync, existsSync, openSync, readSync, readdirSync, statSync } from "node:fs";
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

function clip(text: string): string {
  return text.length > MAX_TEXT ? `${text.slice(0, MAX_TEXT)}\n… (${text.length - MAX_TEXT} more characters)` : text;
}

function toText(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map((v) => (typeof v === "object" && v && "text" in v ? String(v.text) : toText(v))).join("\n");
  return JSON.stringify(value, null, 2);
}

/** Posting a message: the station keeps what an agent posted (its messages), so a transcript's copies of the calls are left out. */
export const POSTING = /^mcp__ember__chat_post$/;

/** What reading a transcript keeps between reads: the calls left out (their results follow later), and calls taken out of a script. */
interface ReadState { skip: Set<string>; inner: Map<string, number> }

function claudeTimeline(records: Record<string, any>[], state: ReadState): TimelineEntry[] {
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
        if (POSTING.test(String(block.name))) { if (block.id) state.skip.add(String(block.id)); continue; }
        out.push({ ...base, kind: "tool_call", tool: String(block.name), text: clip(JSON.stringify(block.input, null, 2)), ...(block.id ? { callId: String(block.id) } : {}) });
      } else if (block.type === "tool_result") {
        if (block.tool_use_id && state.skip.has(String(block.tool_use_id))) continue;
        out.push({ ...base, kind: "tool_result", ok: !block.is_error, text: clip(toText(block.content)), ...(block.tool_use_id ? { callId: String(block.tool_use_id) } : {}) });
      }
    }
  }
  return out;
}

/** Codex prepends context it generated itself as user messages; they are not what anyone said. */
const INJECTED = /^\s*<(environment_context|user_instructions|permissions|skills_instructions|collaboration_mode)\b/;

function codexTimeline(records: Record<string, any>[], state: ReadState): TimelineEntry[] {
  const { skip, inner } = state;
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
    } else if (p.type === "custom_tool_call" && p.name === "exec") {
      // Codex's code mode: the model calls tools from a script. The calls in it are the steps (posts are the station's
      // own record); the script itself is one only when it does more than call them.
      const script = String(p.input ?? "");
      const id = p.call_id ? String(p.call_id) : null;
      const { calls, only } = scriptCalls(script);
      const others = calls.filter((c) => !POSTING.test(c.tool));
      if (only && others.length === 0) { if (id) skip.add(id); continue; }
      if (!only) out.push({ at, kind: "tool_call", tool: "exec", text: clip(script), ...(id ? { callId: id } : {}) });
      others.forEach((c, i) => out.push({
        at, kind: "tool_call", tool: c.tool, text: clip(JSON.stringify(c.args, null, 2)),
        // The script's output answers its first call when the script is nothing but calls.
        ...(id ? { callId: only && i === 0 ? id : `${id}#${i}` } : {}),
      }));
      // Calls taken out of a script that does more: they are done when the script is.
      if (!only && id && others.length) inner.set(id, others.length);
    } else if (p.type === "function_call" || p.type === "custom_tool_call") {
      if (POSTING.test(String(p.name))) { if (p.call_id) skip.add(String(p.call_id)); continue; }
      let args: string = String(p.arguments ?? p.input ?? "");
      try {
        args = JSON.stringify(JSON.parse(args), null, 2);
      } catch {
        // not JSON (custom tools take free text); show as is
      }
      out.push({ at, kind: "tool_call", tool: String(p.name), text: clip(args), ...(p.call_id ? { callId: String(p.call_id) } : {}) });
    } else if (p.type === "function_call_output" || p.type === "custom_tool_call_output") {
      if (p.call_id && skip.has(String(p.call_id))) continue;
      const text = toText(p.output);
      const failed = /Process exited with code [1-9]/.test(text);
      out.push({ at, kind: "tool_result", ok: !failed, text: clip(text), ...(p.call_id ? { callId: String(p.call_id) } : {}) });
      const count = p.call_id ? inner.get(String(p.call_id)) : undefined;
      for (let i = 0; i < (count ?? 0); i++) out.push({ at, kind: "tool_result", ok: !failed, text: "（结果在脚本的输出里）", callId: `${String(p.call_id)}#${i}` });
    }
  }
  return out;
}

/**
 * Reads a transcript as it grows: each read returns the timeline entries of
 * the lines written since the last one, and the usage so far. Lines are
 * independent, so parsing only the new ones gives what a full read would.
 * Everything read is kept, so watchers joining later are served from memory.
 */
/**
 * The tool calls in a code-mode script, `tools.<name>({…})` with a literal argument (read as data, never run), and
 * whether the script is nothing else (each call alone, or wrapped in `text(await …)`).
 */
export function scriptCalls(script: string): { calls: { tool: string; args: unknown }[]; only: boolean } {
  const calls: { tool: string; args: unknown }[] = [];
  let rest = script;
  const call = /tools\.([A-Za-z_$][\w$]*)\s*\(/g;
  for (let m = call.exec(script); m; m = call.exec(script)) {
    const read = readLiteral(script, m.index + m[0].length);
    if (!read || !/^\s*\)/.test(script.slice(read.end))) continue;
    calls.push({ tool: m[1]!, args: read.value });
    rest = rest.replace(script.slice(m.index, read.end + script.slice(read.end).indexOf(")") + 1), "");
  }
  // What is left once the calls are out: nothing but their wrapping.
  const only = calls.length > 0 && /^[\s;]*$/.test(rest.replace(/text\(\s*await\s*\)|await|text\(\s*\)/g, ""));
  return { calls, only };
}

/** A JavaScript literal (object, array, string, number, true/false/null) at `at`, as data; null when it is anything else. */
function readLiteral(src: string, at: number): { value: unknown; end: number } | null {
  let i = at;
  const space = () => { while (i < src.length && /\s/.test(src[i]!)) i++; };
  const value = (): unknown => {
    space();
    const ch = src[i];
    if (ch === "{") {
      i++;
      const obj: Record<string, unknown> = {};
      for (;;) {
        space();
        if (src[i] === "}") { i++; return obj; }
        let key: string;
        if (src[i] === '"' || src[i] === "'") key = string() as string;
        else {
          const m = /^[A-Za-z_$][\w$]*/.exec(src.slice(i));
          if (!m) throw new Error("key");
          key = m[0];
          i += key.length;
        }
        space();
        if (src[i] !== ":") throw new Error(":");
        i++;
        obj[key] = value();
        space();
        if (src[i] === ",") { i++; continue; }
        if (src[i] === "}") { i++; return obj; }
        throw new Error("object");
      }
    }
    if (ch === "[") {
      i++;
      const list: unknown[] = [];
      for (;;) {
        space();
        if (src[i] === "]") { i++; return list; }
        list.push(value());
        space();
        if (src[i] === ",") { i++; continue; }
        if (src[i] === "]") { i++; return list; }
        throw new Error("array");
      }
    }
    if (ch === '"' || ch === "'" || ch === "`") return string();
    const m = /^(-?\d+(\.\d+)?([eE][+-]?\d+)?|true|false|null)/.exec(src.slice(i));
    if (!m) throw new Error("value");
    i += m[0].length;
    return JSON.parse(m[0]);
  };
  const string = (): string => {
    const quote = src[i++]!;
    let out = "";
    while (i < src.length && src[i] !== quote) {
      if (quote === "`" && src[i] === "$" && src[i + 1] === "{") throw new Error("template");
      if (src[i] === "\\") {
        const next = src[i + 1]!;
        const simple: Record<string, string> = { n: "\n", t: "\t", r: "\r", b: "\b", f: "\f", v: "\v", "0": "\0" };
        if (next === "u") { out += String.fromCharCode(parseInt(src.slice(i + 2, i + 6), 16)); i += 6; continue; }
        out += simple[next] ?? next;
        i += 2;
        continue;
      }
      out += src[i++];
    }
    if (src[i] !== quote) throw new Error("string");
    i++;
    return out;
  };
  try {
    const v = value();
    return { value: v, end: i };
  } catch {
    return null;
  }
}

export class TranscriptTail {
  readonly runtime: RuntimeKind;
  readonly path: string;
  #offset = 0;
  #partial = "";
  /** Timeline entries read so far. */
  readonly entries: TimelineEntry[] = [];
  readonly usage: TranscriptUsage = { modelCalls: 0, inputTokens: 0, cachedTokens: 0, outputTokens: 0, model: null };
  readonly #seen = new Set<string>();
  readonly #state: ReadState = { skip: new Set(), inner: new Map() };

  constructor(runtime: RuntimeKind, path: string) {
    this.runtime = runtime;
    this.path = path;
  }

  /** New entries since the last read, with the index of the first. */
  read(): { start: number; entries: TimelineEntry[] } {
    const start = this.entries.length;
    let size: number;
    try {
      size = statSync(this.path).size;
    } catch {
      return { start, entries: [] };
    }
    if (size < this.#offset) { this.#offset = 0; this.#partial = ""; this.entries.length = 0; } // rewritten: start over
    if (size === this.#offset) return { start, entries: [] };
    const fd = openSync(this.path, "r");
    const buffer = Buffer.alloc(size - this.#offset);
    try {
      readSync(fd, buffer, 0, buffer.length, this.#offset);
    } finally {
      closeSync(fd);
    }
    this.#offset = size;
    const text = this.#partial + buffer.toString("utf8");
    const lines = text.split("\n");
    this.#partial = lines.pop() ?? ""; // a line still being written waits for the next read
    const recs = lines.filter(Boolean).flatMap((line) => {
      try {
        return [JSON.parse(line) as Record<string, any>];
      } catch {
        return [];
      }
    });
    this.#addUsage(recs);
    const entries = this.runtime === "claude" ? claudeTimeline(recs, this.#state) : codexTimeline(recs, this.#state);
    this.entries.push(...entries);
    return { start, entries };
  }

  /**
   * Weaves entries from elsewhere (the station's record of ember's own tool calls) into what was read, by time. For a
   * tail nobody has been told of yet: it reorders what is there.
   */
  weave(entries: TimelineEntry[]): void {
    if (entries.length === 0) return;
    const time = (e: TimelineEntry) => (e.at ? Date.parse(e.at) : NaN);
    const merged: TimelineEntry[] = [];
    let next = 0;
    for (const e of this.entries) {
      const t = time(e);
      while (next < entries.length && !Number.isNaN(t) && time(entries[next]!) <= t) merged.push(entries[next++]!);
      merged.push(e);
    }
    merged.push(...entries.slice(next));
    this.entries.length = 0;
    this.entries.push(...merged);
  }

  /** Entries from elsewhere that happen now: after all that was read. Returns where they start. */
  append(entries: TimelineEntry[]): number {
    const start = this.entries.length;
    this.entries.push(...entries);
    return start;
  }

  #addUsage(recs: Record<string, any>[]): void {
    const u = this.usage;
    for (const r of recs) {
      if (this.runtime === "claude") {
        const m = r.type === "assistant" ? r.message : undefined;
        if (!m?.usage || !m.id || this.#seen.has(m.id)) continue;
        this.#seen.add(m.id);
        const cached = (m.usage.cache_read_input_tokens ?? 0) + (m.usage.cache_creation_input_tokens ?? 0);
        u.modelCalls++;
        u.inputTokens += (m.usage.input_tokens ?? 0) + cached;
        u.cachedTokens += m.usage.cache_read_input_tokens ?? 0;
        u.outputTokens += m.usage.output_tokens ?? 0;
        if (typeof m.model === "string" && m.model !== "<synthetic>") u.model = m.model;
      } else {
        const p = r.payload ?? {};
        if (r.type === "turn_context" && typeof p.model === "string") u.model = p.model;
        const last = r.type === "event_msg" && p.type === "token_count" ? p.info?.last_token_usage : undefined;
        if (!last) continue;
        u.modelCalls++;
        u.inputTokens += last.input_tokens ?? 0;
        u.cachedTokens += last.cached_input_tokens ?? 0;
        u.outputTokens += last.output_tokens ?? 0;
      }
    }
  }
}
