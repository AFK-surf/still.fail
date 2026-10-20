// A runtime's stream as live steps (runtime/claude.rs LiveFromClaude, runtime/codex.rs LiveFromCodex): a step starts,
// grows by deltas and ends; the phase says where the turn stands with the model. What each keeps between frames is
// plain data (`state`), so a station taking a session up goes on with the steps in flight.
import type { LiveEvent } from "./runtime.ts";
import { wall } from "../ops/fibers.ts";

type Json = any;
type Phase = "starting" | "requesting" | "responding" | "working";
type Step = "text" | "thinking" | "tool";

const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const nonEmpty = (v: unknown): string | undefined => (typeof v === "string" && v !== "" ? v : undefined);
/// At most `n` characters (Rust's chars().take(n)).
export const chars = (text: string, n: number): string => {
  if (text.length <= n) return text;
  return Array.from(text).slice(0, n).join("");
};

/// Claude Code's step event, as LiveEvent::Start serializes: fields that are none left out.
function start(id: string, step: Step, tool?: string, input?: string, subagent?: boolean, parent?: string): LiveEvent {
  const event: LiveEvent = { kind: "start", id, step };
  if (tool !== undefined) event.tool = tool;
  if (input !== undefined) event.input = input;
  if (subagent !== undefined) event.subagent = subagent;
  if (parent !== undefined) event.parent = parent;
  return event;
}

/// The most of a call's input kept as it streams in (a file written whole can be large; past this it is cut short).
const INPUT_MOST = 256 * 1024;

type Block = { id: string; step: Step; tool?: string; input?: string; subagent?: string };
export type ClaudeLiveState = { message: string; blocks: [number, Block][]; tools: string[] };

/// Claude Code's partial messages (--include-partial-messages) as live steps. Each content block of a model response is
/// a step: text and thinking end with their block; a tool call ends when its result comes back, which also carries the
/// output (Claude Code does not stream tool output).
export class LiveFromClaude {
  private message = "";
  private blocks = new Map<number, Block>();
  private tools = new Set<string>();

  constructor(state?: ClaudeLiveState) {
    if (state) {
      this.message = state.message;
      this.blocks = new Map(state.blocks);
      this.tools = new Set(state.tools);
    }
  }

  state(): ClaudeLiveState {
    return { message: this.message, blocks: [...this.blocks.entries()], tools: [...this.tools] };
  }

  feed(frame: Json): LiveEvent[] {
    const out: LiveEvent[] = [];
    const kind = str(frame?.type) ?? "";
    if (kind === "system" && frame.subtype === "status" && frame.status === "requesting") {
      out.push({ kind: "phase", phase: "requesting" });
    } else if (kind === "stream_event") {
      const e = frame.event ?? null;
      // A sub-agent's steps name the tool call (Task/Agent) that started it.
      const parent = nonEmpty(frame.parent_tool_use_id);
      const event = str(e?.type) ?? "";
      if (event === "message_stop" && parent === undefined) out.push({ kind: "phase", phase: "working" });
      const index = Number.isInteger(e?.index) ? (e.index as number) : -1;
      if (event === "message_start") {
        this.message = str(e?.message?.id) ?? String(wall.now());
        this.blocks.clear();
        if (parent === undefined) out.push({ kind: "phase", phase: "responding" });
      } else if (event === "content_block_start") {
        const b = e?.content_block ?? null;
        const type = str(b?.type);
        const step: Step | undefined = type === "text" ? "text" : type === "thinking" ? "thinking" : type === "tool_use" ? "tool" : undefined;
        if (step === undefined) return out;
        const id = step === "tool" && typeof b?.id === "string" ? (b.id as string) : `${this.message}:${index}`;
        const tool = step === "tool" ? (str(b?.name) ?? "tool") : undefined;
        if (step === "tool") this.tools.add(id);
        out.push(start(id, step, tool, undefined, parent !== undefined ? true : undefined, parent));
        this.blocks.set(index, { id, step, tool, input: tool !== undefined ? "" : undefined, subagent: parent });
      } else if (event === "content_block_delta") {
        const block = this.blocks.get(index);
        if (!block) return out;
        const d = e?.delta ?? null;
        const type = str(d?.type);
        if (type === "text_delta") {
          const t = nonEmpty(d.text);
          if (t !== undefined) out.push({ kind: "delta", id: block.id, field: "text", text: t });
        } else if (type === "thinking_delta") {
          const t = nonEmpty(d.thinking);
          if (t !== undefined) out.push({ kind: "delta", id: block.id, field: "text", text: t });
        } else if (type === "input_json_delta") {
          const partial = nonEmpty(d.partial_json);
          if (partial !== undefined) {
            // A call's input streams in after it starts; kept whole (its start, a moment before, came without it), for
            // what says what it runs may come after a long command (sessions/live.ts briefInput).
            if (block.input !== undefined && block.input.length < INPUT_MOST) block.input += partial;
            out.push({ kind: "delta", id: block.id, field: "input", text: partial });
          }
        }
      } else if (event === "content_block_stop") {
        const block = this.blocks.get(index);
        if (block) {
          if (block.step !== "tool") out.push({ kind: "end", id: block.id });
          else if (block.input !== undefined && block.input !== "") {
            // Its input complete, the call starts again with it: what it runs can be said now.
            out.push(start(block.id, "tool", block.tool, block.input, block.subagent !== undefined ? true : undefined, block.subagent));
          }
        }
      }
    } else if (kind === "user") {
      const content = Array.isArray(frame.message?.content) ? frame.message.content : [];
      for (const c of content) {
        const id = str(c?.tool_use_id) ?? "";
        if (c?.type !== "tool_result" || !this.tools.has(id)) continue;
        const text =
          typeof c.content === "string"
            ? c.content
            : Array.isArray(c.content)
              ? c.content.map((x: Json) => str(x?.text) ?? "").join("\n")
              : "";
        if (text !== "") out.push({ kind: "delta", id, field: "output", text: chars(text, 8000) });
        out.push({ kind: "end", id });
        this.tools.delete(id);
      }
    }
    return out;
  }
}

const TOOL_ITEMS = ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"];

export type CodexLiveState = { open: string[]; phase: Phase | null };

/// Rust's serde_json::to_string_pretty: two-space indent, "key": value.
const pretty = (v: unknown) => JSON.stringify(v ?? {}, null, 2) ?? "{}";

/// The app-server's item notifications as live steps: an item starts, grows by deltas (the reply, reasoning, a
/// command's output as it runs) and completes.
export class LiveFromCodex {
  private open = new Set<string>();
  private phase: Phase | null = null;

  constructor(state?: CodexLiveState) {
    if (state) {
      this.open = new Set(state.open);
      this.phase = state.phase;
    }
  }

  state(): CodexLiveState {
    return { open: [...this.open], phase: this.phase };
  }

  feed(method: string, params: Json): LiveEvent[] {
    const out: LiveEvent[] = [];
    const to = (next: Phase) => {
      if (this.phase !== next) {
        this.phase = next;
        out.push({ kind: "phase", phase: next });
      }
    };
    const itemType = str(params?.item?.type) ?? "";
    if (method === "turn/started") to("requesting");
    else if (method === "turn/completed") this.phase = null;
    else if (method === "item/agentMessage/delta" || method.startsWith("item/reasoning/")) to("responding");
    else if (method === "item/started" && TOOL_ITEMS.includes(itemType)) to("working");
    else if (method === "item/completed" && TOOL_ITEMS.includes(itemType)) to("requesting");

    const text = (v: unknown) => str(v) ?? "";
    if (method === "item/started") {
      const item = params?.item ?? null;
      const id = typeof item?.id === "string" ? item.id : typeof item?.id === "number" ? String(item.id) : "";
      let begun: [Step, string | undefined, string | undefined] | undefined;
      if (itemType === "agentMessage") begun = ["text", undefined, undefined];
      else if (itemType === "reasoning") begun = ["thinking", undefined, undefined];
      else if (itemType === "commandExecution") begun = ["tool", "shell", text(item.command)];
      else if (itemType === "fileChange")
        begun = ["tool", "apply_patch", (Array.isArray(item.changes) ? item.changes : []).map((c: Json) => text(c?.path)).join("\n")];
      else if (itemType === "mcpToolCall") begun = ["tool", `${text(item.server)}.${text(item.tool)}`, pretty(item.arguments)];
      else if (itemType === "dynamicToolCall") begun = ["tool", text(item.tool), pretty(item.arguments)];
      else if (itemType === "webSearch") begun = ["tool", "web_search", text(item.query)];
      if (id !== "" && begun) {
        this.open.add(id);
        out.push(start(id, begun[0], begun[1], begun[2]));
      }
    } else if (
      method === "item/agentMessage/delta" ||
      method === "item/reasoning/textDelta" ||
      method === "item/reasoning/summaryTextDelta" ||
      method === "item/plan/delta" ||
      method === "item/commandExecution/outputDelta"
    ) {
      const id = text(params?.itemId);
      const delta = text(params?.delta);
      if (this.open.has(id) && delta !== "") {
        out.push({ kind: "delta", id, field: method === "item/commandExecution/outputDelta" ? "output" : "text", text: delta });
      }
    } else if (method === "item/completed") {
      const id = text(params?.item?.id);
      if (this.open.delete(id)) out.push({ kind: "end", id });
    }
    return out;
  }
}

export type DshLiveState = { open: [string, Step][]; calls: [string, string][]; phase: Phase | null };

/// DeepSeek Harness's output as the station's driver plugin sends it (agents/dsh-bridge.mjs) as live steps: the model's
/// stream (`stream`: a block of text, thinking or a call's input starts, grows and ends) and the session's events
/// (`event`: a call runs from tool/call until its tool/result, which carries the output; the turn's end ends all).
export class LiveFromDsh {
  /// Steps started and not ended, with what they are.
  private open = new Map<string, Step>();
  /// A stream block's call: attempt#index → the call's id (its deltas after the first name only the index).
  private calls = new Map<string, string>();
  private phase: Phase | null = null;

  constructor(state?: DshLiveState) {
    if (state) {
      this.open = new Map(state.open);
      this.calls = new Map(state.calls);
      this.phase = state.phase;
    }
  }

  state(): DshLiveState {
    return { open: [...this.open.entries()], calls: [...this.calls.entries()], phase: this.phase };
  }

  private to(next: Phase, out: LiveEvent[]) {
    if (this.phase !== next) {
      this.phase = next;
      out.push({ kind: "phase", phase: next });
    }
  }

  private end(id: string, out: LiveEvent[]) {
    if (this.open.delete(id)) out.push({ kind: "end", id });
  }

  /// A prompt was given: the turn is with the model.
  prompted(): LiveEvent[] {
    const out: LiveEvent[] = [];
    this.to("requesting", out);
    return out;
  }

  feed(message: Json): LiveEvent[] {
    const out: LiveEvent[] = [];
    if (message?.ev === "stream") this.stream(message.frame, out);
    else if (message?.ev === "event") this.event(str(message.type) ?? "", message.data ?? {}, out);
    return out;
  }

  private stream(frame: Json, out: LiveEvent[]) {
    const attempt = str(frame?.attemptId) ?? "";
    if (frame?.type === "start") return this.to("requesting", out);
    if (frame?.type === "end") {
      // An attempt that did not commit (cancelled, failed, retried): what it said so far ends with it.
      if (frame.outcome?.kind !== "committed") for (const [id, step] of [...this.open]) if (step !== "tool" && id.startsWith(`${attempt}#`)) this.end(id, out);
      return;
    }
    const chunk = frame?.chunk;
    if (frame?.type !== "chunk" || !chunk) return;
    const block = `${attempt}#${typeof chunk.index === "number" ? chunk.index : ""}`;
    const kind = str(chunk.type) ?? "";
    if (kind === "block-start" && (chunk.blockType === "text" || chunk.blockType === "reasoning")) {
      this.open.set(block, chunk.blockType === "text" ? "text" : "thinking");
      out.push(start(block, chunk.blockType === "text" ? "text" : "thinking"));
    } else if (kind === "text-delta" || kind === "reasoning-delta") {
      const text = str(chunk.text) ?? "";
      if (!this.open.has(block) || text === "") return;
      this.to("responding", out);
      out.push({ kind: "delta", id: block, field: "text", text });
    } else if (kind === "tool-call-delta") {
      let call = this.calls.get(block);
      const id = nonEmpty(chunk.id);
      if (call === undefined && id !== undefined) {
        call = id;
        this.calls.set(block, id);
        this.open.set(id, "tool");
        this.to("responding", out);
        out.push(start(id, "tool", str(chunk.name) ?? "", ""));
      }
      const delta = str(chunk.argumentsDelta) ?? "";
      if (call !== undefined && delta !== "") out.push({ kind: "delta", id: call, field: "input", text: delta });
    } else if (kind === "block-end") {
      // A call goes on until its result.
      if (this.open.get(block) !== undefined) this.end(block, out);
      this.calls.delete(block);
    }
  }

  private event(type: string, data: Json, out: LiveEvent[]) {
    if (type === "tool/call") {
      const id = nonEmpty(data.callId);
      if (id === undefined) return;
      this.to("working", out);
      // One not seen streaming (taken up after it streamed): started with its input whole.
      if (!this.open.has(id)) {
        this.open.set(id, "tool");
        let input = str(data.arguments) ?? "";
        try {
          input = pretty(JSON.parse(input));
        } catch {}
        out.push(start(id, "tool", str(data.name) ?? "", chars(input, INPUT_MOST)));
      }
    } else if (type === "tool/result") {
      const result = data.message ?? {};
      const id = nonEmpty(result.toolCallId);
      if (id === undefined || !this.open.has(id)) return;
      const output = (Array.isArray(result.content) ? result.content : []).map((c: Json) => str(c?.text) ?? "").filter((t: string) => t !== "").join("\n");
      if (output !== "") out.push({ kind: "delta", id, field: "output", text: output });
      this.end(id, out);
      if (![...this.open.values()].includes("tool")) this.to("requesting", out);
    } else if (type === "turn/end") {
      out.push(...this.ended());
    }
  }

  /// The turn ended: whatever is still open ends with it.
  ended(): LiveEvent[] {
    const out: LiveEvent[] = [...this.open.keys()].map((id) => ({ kind: "end", id }) as LiveEvent);
    this.open.clear();
    this.calls.clear();
    this.phase = null;
    return out;
  }
}

export type AcpLiveState = { open: string[]; said: string | null; n: number; phase: Phase | null };

/// What a content block of an ACP update says (its text; anything else nothing).
const acpText = (content: Json): string => {
  if (typeof content?.text === "string") return content.text;
  if (content?.type === "content") return acpText(content.content);
  return "";
};

/// A call as it is named and given: Grok Build reaches an MCP server's tools through its `use_tool` (the tool's full
/// name, server__tool, and its input inside), named here as the tool itself, as Claude Code names one
/// (mcp__server__tool).
export function acpCall(name: string, input: Json): [string, Json] {
  if (name === "use_tool" && typeof input?.tool_name === "string") return [`mcp__${input.tool_name}`, input.tool_input ?? {}];
  return [name, input];
}

/// An ACP agent's `session/update`s as live steps (Grok Build's). What the model says streams in chunks with no id of
/// their own: a run of chunks of one kind is a step, which ends when something else begins (a thought, a call) or the
/// turn ends; a call starts with `tool_call` and ends with the update that says it completed or failed, which carries
/// its output.
export class LiveFromAcp {
  private open = new Set<string>();
  /// The step what is being said goes into (text or thinking), and how many steps were made.
  private said: string | null = null;
  private n = 0;
  private phase: Phase | null = null;

  constructor(state?: AcpLiveState) {
    if (state) {
      this.open = new Set(state.open);
      this.said = state.said;
      this.n = state.n;
      this.phase = state.phase;
    }
  }

  state(): AcpLiveState {
    return { open: [...this.open], said: this.said, n: this.n, phase: this.phase };
  }

  private to(next: Phase, out: LiveEvent[]) {
    if (this.phase !== next) {
      this.phase = next;
      out.push({ kind: "phase", phase: next });
    }
  }

  /// Ends the step of what was being said (a call keeps going until its result).
  private endSaid(out: LiveEvent[]) {
    if (this.said === null) return;
    this.open.delete(this.said);
    out.push({ kind: "end", id: this.said });
    this.said = null;
  }

  /// A prompt was given: the turn is with the model.
  prompted(): LiveEvent[] {
    const out: LiveEvent[] = [];
    this.to("requesting", out);
    return out;
  }

  /// The call that started last of those still running (what a subagent spawned now was spawned by).
  openCall(): string | undefined {
    return [...this.open].filter((id) => id.startsWith("call:")).at(-1);
  }

  feed(update: Json): LiveEvent[] {
    const out: LiveEvent[] = [];
    const kind = str(update?.sessionUpdate) ?? "";
    if (kind === "agent_message_chunk" || kind === "agent_thought_chunk") {
      const step: Step = kind === "agent_message_chunk" ? "text" : "thinking";
      const text = acpText(update.content);
      if (text === "") return out;
      this.to("responding", out);
      if (this.said === null || !this.said.endsWith(`/${step}`)) {
        this.endSaid(out);
        this.n += 1;
        this.said = `said:${this.n}/${step}`;
        this.open.add(this.said);
        out.push(start(this.said, step));
      }
      out.push({ kind: "delta", id: this.said, field: "text", text });
    } else if (kind === "tool_call") {
      const callId = nonEmpty(update.toolCallId);
      if (callId === undefined) return out;
      const id = `call:${callId}`;
      this.endSaid(out);
      this.to("working", out);
      if (!this.open.has(id)) {
        this.open.add(id);
        const [name, input] = acpCall(str(update._meta?.["x.ai/tool"]?.name) ?? str(update.title) ?? "", update.rawInput ?? null);
        out.push(start(id, "tool", name, chars(pretty(input), INPUT_MOST)));
      }
      this.result(id, update, out);
    } else if (kind === "tool_call_update") {
      const callId = nonEmpty(update.toolCallId);
      if (callId !== undefined && this.open.has(`call:${callId}`)) this.result(`call:${callId}`, update, out);
    }
    return out;
  }

  /// A call's output once it is done, and its end.
  private result(id: string, update: Json, out: LiveEvent[]) {
    if (update.status !== "completed" && update.status !== "failed") return;
    const output = (Array.isArray(update.content) ? update.content : []).map(acpText).filter((t: string) => t !== "").join("\n");
    if (output !== "") out.push({ kind: "delta", id, field: "output", text: chars(output, INPUT_MOST) });
    this.open.delete(id);
    out.push({ kind: "end", id });
    if (![...this.open].some((o) => o.startsWith("call:"))) this.to("requesting", out);
  }

  /// The turn ended: whatever is still open ends with it.
  ended(): LiveEvent[] {
    const out: LiveEvent[] = [...this.open].map((id) => ({ kind: "end", id }) as LiveEvent);
    this.open.clear();
    this.said = null;
    this.phase = null;
    return out;
  }
}

export type CursorLiveState = { open: [string, Step][]; said: string | null; n: number; phase: Phase | null };

/// A call of Cursor's as the station names it: the station's tools (and any MCP server's) as Claude Code names an MCP
/// tool, mcp__<server>__<tool>, with the tool's own input; the others by Cursor's name (shell, read, edit…).
export function cursorCall(name: string, args: Json): [string, Json] {
  if (name === "mcp" && typeof args?.providerIdentifier === "string" && typeof args?.toolName === "string") return [`mcp__${args.providerIdentifier}__${args.toolName}`, args.args ?? {}];
  return [name, args ?? {}];
}

/// What a call of Cursor's gave back, as text: a command's output, an MCP tool's content, else as it is.
export function cursorOutput(result: unknown): string {
  let r: Json = result;
  if (typeof r === "string") {
    try {
      r = JSON.parse(r);
    } catch {
      return r as string;
    }
  }
  const v = r?.value ?? r;
  if (typeof v?.stdout === "string" || typeof v?.stderr === "string") return [str(v.stdout) ?? "", str(v.stderr) ?? ""].filter((t) => t !== "").join("\n");
  if (Array.isArray(v?.content)) return v.content.map((c: Json) => str(c?.text?.text) ?? str(c?.text) ?? "").filter((t: string) => t !== "").join("\n");
  if (typeof r?.error === "string") return r.error;
  return r === null || r === undefined ? "" : typeof r === "string" ? r : JSON.stringify(r);
}

/// Cursor's SDK messages (as agents/cursor-bridge.mjs sends them) as live steps: the model's text and thoughts come in
/// pieces with no id of their own (a step lasts until something else comes), a call starts running and comes back done.
export class LiveFromCursor {
  private open = new Map<string, Step>();
  /// The text or thoughts step under way.
  private said: string | null = null;
  private n = 0;
  private phase: Phase | null = null;

  constructor(state?: CursorLiveState) {
    if (state) {
      this.open = new Map(state.open);
      this.said = state.said;
      this.n = state.n;
      this.phase = state.phase;
    }
  }

  state(): CursorLiveState {
    return { open: [...this.open.entries()], said: this.said, n: this.n, phase: this.phase };
  }

  private to(next: Phase, out: LiveEvent[]) {
    if (this.phase !== next) {
      this.phase = next;
      out.push({ kind: "phase", phase: next });
    }
  }

  private end(id: string, out: LiveEvent[]) {
    if (this.open.delete(id)) out.push({ kind: "end", id });
  }

  /// The text or thoughts under way ends: something else came.
  private stopSaying(out: LiveEvent[]) {
    if (this.said !== null) this.end(this.said, out);
    this.said = null;
  }

  /// A prompt was given: the turn is with the model.
  prompted(): LiveEvent[] {
    const out: LiveEvent[] = [];
    this.to("requesting", out);
    return out;
  }

  feed(message: Json): LiveEvent[] {
    const out: LiveEvent[] = [];
    const type = str(message?.type) ?? "";
    if (type === "status" && message.status === "RUNNING") this.to("requesting", out);
    else if (type === "thinking" || type === "assistant") {
      const step: Step = type === "thinking" ? "thinking" : "text";
      const text = type === "thinking" ? (str(message.text) ?? "") : (Array.isArray(message.message?.content) ? message.message.content : []).map((c: Json) => (c?.type === "text" ? (str(c.text) ?? "") : "")).join("");
      if (this.said === null || this.open.get(this.said) !== step) {
        if (text === "") return out;
        this.stopSaying(out);
        this.said = `${str(message.run_id) ?? "cursor"}:${this.n++}`;
        this.open.set(this.said, step);
        out.push(start(this.said, step));
      }
      if (step === "text") this.to("responding", out);
      if (text !== "") out.push({ kind: "delta", id: this.said, field: "text", text });
    } else if (type === "tool_call") {
      const id = nonEmpty(message.call_id);
      if (id === undefined) return out;
      this.stopSaying(out);
      if (message.status === "running") {
        if (this.open.has(id)) return out;
        const [name, input] = cursorCall(str(message.name) ?? "tool", message.args);
        this.open.set(id, "tool");
        this.to("working", out);
        out.push(start(id, "tool", name, chars(pretty(input), INPUT_MOST)));
        return out;
      }
      if (!this.open.has(id)) {
        // One done that this station did not see start (taken up after it started): started with its input whole.
        const [name, input] = cursorCall(str(message.name) ?? "tool", message.args);
        this.open.set(id, "tool");
        out.push(start(id, "tool", name, chars(pretty(input), INPUT_MOST)));
      }
      const output = cursorOutput(message.result);
      if (output !== "") out.push({ kind: "delta", id, field: "output", text: chars(output, INPUT_MOST) });
      this.end(id, out);
      if (![...this.open.values()].includes("tool")) this.to("requesting", out);
    } else if (type === "user") {
      // A message put in the turn: what the model says next is a step of its own.
      this.stopSaying(out);
    }
    return out;
  }

  /// The turn ended: whatever is still open ends with it.
  ended(): LiveEvent[] {
    const out: LiveEvent[] = [...this.open.keys()].map((id) => ({ kind: "end", id }) as LiveEvent);
    this.open.clear();
    this.said = null;
    this.phase = null;
    return out;
  }
}
