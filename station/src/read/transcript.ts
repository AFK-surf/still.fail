// A runtime's own session transcript as one readable timeline for the pages (the Rust station's transcript.rs), read whole
// as a session nobody watches is (live.rs `before`): its file, or its `.zst` once put away; the agent's own posts left
// out of it and woven back in from the station's record of them (hub.rs `post_entries`).
// - claude: <home>/projects/<cwd>/<id>.jsonl, lines of {type: user|assistant, message: {content: string | blocks}}
// - codex: <home>/sessions/**/rollout-*<id>.jsonl, lines of {type: response_item, payload: message | reasoning | …}
// - dsh: <home>/dsh-sessions/<cwd>/<id>/session.v<N>.jsonl, lines of {type: user/message | assistant/message |
//   tool/result | …, time, data}
// - cursor: <home>/cursor/sessions/<id>.jsonl, the station's own (agents/cursor-bridge.mjs), lines of {time, type: user |
//   assistant | thinking | tool | usage | end, …}
// - devin: <home>/devin/sessions/<id>.jsonl, the station's own (agents/devin.ts), lines as Cursor's
//
// JSON is read with JSON.parse, so a value shows as JavaScript has it: a number written `1.0` shows `1`, a key that is
// an integer comes first, a number past 2^53 rounds (serde_json keeps each as written). Transcripts rarely have them.
import { closeSync, existsSync, openSync, readdirSync, readSync, realpathSync, statSync } from "node:fs";
import { join } from "node:path";
import { zstdDecompressSync } from "node:zlib";
import { tr } from "./spoken.ts";
import type { Json } from "./store.ts";
import type { RuntimeKind } from "../agents/runtime.ts";

/// TimelineEntry as serde writes it: `tool`, `ok`, `callId`, `subagent` left out when none; `brief` when what it says is
/// cut to what a history shows before it is opened (`brief`).
export type TimelineEntry = { at: string | null; kind: string; text: string; tool?: string; ok?: boolean; callId?: string; subagent?: boolean; brief?: boolean };

const MAX_TEXT = 4000;

// ---- Rust's char classes (Unicode White_Space, Alphabetic, Numeric) ----

const WS = /^\p{White_Space}$/u;
const isWs = (c: string | undefined) => c !== undefined && WS.test(c);
const isAlphabetic = (c: string | undefined) => c !== undefined && /^\p{Alphabetic}$/u.test(c);
const isAlphanumeric = (c: string | undefined) => c !== undefined && /^[\p{Alphabetic}\p{N}]$/u.test(c);
const trimStart = (s: string) => s.replace(/^\p{White_Space}+/u, "");
const trim = (s: string) => s.replace(/^\p{White_Space}+|\p{White_Space}+$/gu, "");
const isStr = (v: Json): v is string => typeof v === "string";
const isObj = (v: Json) => v !== null && typeof v === "object" && !Array.isArray(v);
/// serde_json's `value.get(key)`: an object's field, else none.
const get = (v: Json, key: string): Json | undefined => (isObj(v) && Object.hasOwn(v, key) ? v[key] : undefined);
const stringOf = (v: Json | undefined): string | undefined => (isStr(v) ? v : undefined);

// ---- an entry in brief ----

/// What is whole in brief too: up to this many characters.
const SMALL = 600;
/// How much of each field that says what a call does its brief keeps, and of a thought its first line.
const BRIEF_CHARS = 300;
/// The fields of a call's input that say what it does: what an execution history names a call by before it is opened,
/// and a chat's activity says it does (client/core-ts/src/activity.ts doing, history.ts describe, hint, fileOf).
const SAYING = ["description", "command", "cmd", "file_path", "path", "notebook_path", "pattern", "url", "query", "prompt"];
/// Calls whole in brief too: what they hold is what a history shows of them (a post, a state, what went to Slack).
const WHOLE = new Set(["chat_post", "chat_state", "slack_api"]);
/// Each call's brief, as it was read (from its whole input, not one cut to MAX_TEXT).
const briefs = new WeakMap<TimelineEntry, string>();

const toolName = (tool: string) => tool.replace(/^(mcp__stillfail__|stillfail__|stillfail\.|mcp__ember__|ember__|ember\.)/, "");
const firstChars = (text: string, n: number) => Array.from(text).slice(0, n).join("");

/// A call's input in brief: of an object, only the fields that say what it does, each cut short; anything else cut short.
function briefOf(input: Json | undefined): string {
  if (isObj(input)) {
    const kept: Record<string, string | string[]> = {};
    for (const name of SAYING) {
      const v = get(input, name);
      if (isStr(v)) kept[name] = firstChars(v, BRIEF_CHARS);
      else if (Array.isArray(v)) kept[name] = v.filter(isStr).map((p) => firstChars(p, BRIEF_CHARS));
    }
    return JSON.stringify(kept);
  }
  return firstChars(isStr(input) ? input : JSON.stringify(input ?? null), BRIEF_CHARS);
}

/// A call entry, its brief kept beside it.
function withBrief(e: TimelineEntry, input: Json | undefined): TimelineEntry {
  briefs.set(e, briefOf(input));
  return e;
}

/// Lines' bytes as text (str::from_utf8_lossy): a byte order mark stays, so a line starting with one is no record however
/// lines are cut into what is decoded at once (here a line at a time, read/tail.ts a piece).
export const utf8 = new TextDecoder("utf-8", { ignoreBOM: true });

/// How lines are read into entries (`timelineOf`): a change to how many entries a line gives, or which, takes this one
/// higher, so what was counted and marked of transcripts the way before is read anew (read/transcripts.ts).
export const READING = 2;

/**
 * An entry as an execution history shows it before it is opened (`brief: true` when anything was left out; the whole of
 * it is read again by its index when it is): a call by what says what it does, a result without what it gave (Slack's
 * answer kept to whether it went and its ts), a thought by its first line. What it said or was given, posts, states and
 * what went to Slack, and anything short, whole.
 */
export function brief(e: TimelineEntry): TimelineEntry {
  if (Array.from(e.text).length <= SMALL) return e;
  if (e.kind === "tool_call") {
    if (WHOLE.has(toolName(e.tool ?? ""))) return e;
    return { ...e, text: briefs.get(e) ?? firstChars(e.text, BRIEF_CHARS), brief: true };
  }
  if (e.kind === "tool_result") {
    let text = "";
    try {
      const v = JSON.parse(e.text);
      if (isObj(v) && typeof v.ok === "boolean") text = JSON.stringify(isStr(v.ts) ? { ok: v.ok, ts: v.ts } : { ok: v.ok });
    } catch {
      // Not Slack's answer: nothing of it.
    }
    return { ...e, text, brief: true };
  }
  if (e.kind === "thinking") {
    const first = e.text.split("\n").find((l) => trim(l) !== "") ?? "";
    return { ...e, text: firstChars(trim(first), BRIEF_CHARS), brief: true };
  }
  return e;
}

/// archive.rs `storage`: the file, or its `.zst` once put away.
export const storage = (path: string) => (existsSync(path) ? path : `${path}.zst`);
const isFile = (path: string) => {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
};
const isDir = (path: string) => {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
};
const entriesOf = (dir: string): string[] | null => {
  try {
    return readdirSync(dir);
  } catch {
    return null;
  }
};

/// Where in a home a runtime keeps its transcripts: Claude Code's projects/, Codex's sessions/, DeepSeek Harness's
/// dsh-sessions/ as dsh.ts sets it, Grok Build's grok/sessions/, Cursor's and Devin's cursor/sessions/ and devin/sessions/
/// as cursor.ts and devin.ts keep them. In a home the station keeps it is a link to the runtime's shared place
/// (`sharedTranscripts`, sessions/agent-home.ts `linkTranscripts`).
export const transcriptDir = (runtime: string) => (runtime === "claude" ? "projects" : runtime === "codex" ? "sessions" : runtime === "grok" ? "grok/sessions" : runtime === "cursor" ? "cursor/sessions" : runtime === "devin" ? "devin/sessions" : runtime === "hermes" ? "hermes/sessions" : "dsh-sessions");

/// The one place a runtime's transcripts are kept on the station, whichever account's home wrote them.
export const sharedTranscripts = (dataDir: string, runtime: string) => join(dataDir, "transcripts", runtime);

/// transcript_path: where a runtime keeps a session's transcript in a home, if it is there.
export function transcriptPath(runtime: RuntimeKind, home: string, id: string): string | null {
  return transcriptIn(runtime, join(home, transcriptDir(runtime)), id);
}

/// The directory Claude Code keeps a working directory's transcripts in, in projects/ (its sanitizePath): each character
/// but an ASCII letter or digit a dash. Past 200 characters it shortens the name and adds a hash of it: none said.
export function claudeProject(cwd: string): string | null {
  const name = cwd.replace(/[^a-zA-Z0-9]/g, "-");
  return name.length <= 200 ? name : null;
}

/// Where a Claude session's transcript is in a directory of them when it ran in one of `places` (the session's working
/// directories): looked for there alone, a file or two, not in every project's directory (the shared place has one for
/// each chat the station ever had: 923 on ccvm, each looked at in turn on the main thread).
function placedIn(runtime: RuntimeKind, dir: string, id: string, places: readonly string[]): string | null {
  if (runtime !== "claude") return null;
  for (const place of places) {
    const project = claudeProject(place);
    if (project === null) continue;
    const path = join(dir, project, `${id}.jsonl`);
    if (isFile(storage(path))) return path;
  }
  return null;
}

/// The Claude transcripts found in a project not of their session's places (it ran before the data directory moved, or
/// in a terminal's directory), by directory and id: a transcript stays where it is (put away, its `.zst` beside), so each
/// is looked for in every project once a process.
const elsewhere = new Map<string, string>();

/// Where a session's transcript is in a directory of the runtime's transcripts (a home's, `transcriptDir`, or the shared
/// place), if it is there.
function transcriptIn(runtime: RuntimeKind, dir: string, id: string): string | null {
  if (runtime === "dsh") return dshTranscript(dir, id);
  if (runtime === "grok") return grokTranscript(dir, id);
  if (runtime === "cursor" || runtime === "devin" || runtime === "hermes") {
    const path = join(dir, `${id}.jsonl`);
    return isFile(storage(path)) ? path : null;
  }
  if (runtime === "claude") {
    const at = `${dir}\0${id}`;
    const kept = elsewhere.get(at);
    if (kept !== undefined && isFile(storage(kept))) return kept;
    for (const project of entriesOf(dir) ?? []) {
      const path = join(dir, project, `${id}.jsonl`);
      if (isFile(storage(path))) return (elsewhere.set(at, path), path);
    }
    return null;
  }
  const find = (dir: string): string | null => {
    for (const name of entriesOf(dir) ?? []) {
      const path = join(dir, name);
      if (isDir(path)) {
        const found = find(path);
        if (found !== null) return found;
      } else if (name.startsWith("rollout-") && name.endsWith(`${id}.jsonl`)) {
        return path;
      } else if (name.startsWith("rollout-") && name.endsWith(`${id}.jsonl.zst`)) {
        return path.slice(0, -".zst".length);
      }
    }
    return null;
  };
  return find(dir);
}

/// dsh's: the session's directory holds one file per format it was written in (session.v<N>.jsonl); the current is the
/// highest N. Its directory is under one named for its working directory (any).
function dshTranscript(root: string, id: string): string | null {
  for (const dir of entriesOf(root) ?? []) {
    const files = (entriesOf(join(root, dir, id)) ?? [])
      .map((name) => [name, /^session\.v(\d+)\.jsonl$/.exec(name)?.[1]] as const)
      .filter((f): f is readonly [string, string] => f[1] !== undefined)
      .sort((a, b) => Number(b[1]) - Number(a[1]));
    if (files.length > 0) return join(root, dir, id, files[0]![0]);
  }
  return null;
}

/// Grok Build's: sessions/<working directory, escaped>/<id>/chat_history.jsonl in its home (agents/grok.ts).
function grokTranscript(root: string, id: string): string | null {
  for (const dir of entriesOf(root) ?? []) {
    const path = join(root, dir, id, "chat_history.jsonl");
    if (isFile(storage(path))) return path;
  }
  return null;
}

/// Profiles' homes, `first`'s (a session's profile, if it still has one) first.
export const homesFirst = (profiles: readonly { id: string; home: string }[], first: string | null): string[] => [
  ...profiles.filter((p) => p.id === first).map((p) => p.home),
  ...profiles.filter((p) => p.id !== first).map((p) => p.home),
];

/// The transcripts of a session's runtime sessions (`ids`, the first first, ending with its current one): each looked
/// for in the runtime's shared place in data directory `dataDir`, where every home the station keeps has its runtimes
/// write them, whichever account and home a runtime session ran on and whatever the config says now; then in each of
/// `homes` (its profile's first) for a home that keeps its own (one outside the data directory that had transcripts in
/// it before it was a profile's, agent-home.ts `linkTranscripts`). `current` is whether the current one's is there: a
/// runtime writes it only once its conversation has begun. `places`: where the session works and worked (`sessionPlaces`),
/// where a Claude transcript is looked for first, in every directory, before anywhere else in them.
export function transcriptPaths(runtime: RuntimeKind, dataDir: string, homes: string[], ids: string[], places: readonly string[] = []): { paths: string[]; current: boolean } {
  // Each directory once, however it is reached (a home's that links to the shared place is that place), the homes' made
  // out only once one is to be looked in: nearly every transcript is in the shared place, the first.
  const shared = sharedTranscripts(dataDir, runtime);
  const ways = homes.map((home) => join(home, transcriptDir(runtime)));
  const real = (dir: string): string | null => {
    try {
      return realpathSync(dir);
    } catch {
      return null;
    }
  };
  let seen: Set<string> | null = null;
  const dirs = [shared];
  const dirAt = (i: number): string | undefined => {
    while (dirs.length <= i && ways.length > 0) {
      seen ??= new Set([real(shared) ?? shared]);
      const dir = ways.shift()!;
      const at = real(dir);
      if (at !== null && !seen.has(at)) (seen.add(at), dirs.push(dir));
    }
    return dirs[i];
  };
  const inDirs = (look: (dir: string) => string | null): string | null => {
    for (let i = 0; dirAt(i) !== undefined; i++) {
      const path = look(dirs[i]!);
      if (path !== null) return path;
    }
    return null;
  };
  const found = ids.map((id) => inDirs((dir) => placedIn(runtime, dir, id, places)) ?? inDirs((dir) => transcriptIn(runtime, dir, id)));
  return { paths: found.filter((p) => p !== null), current: found.at(-1) != null };
}

/// Where a session works and worked, for `transcriptPaths`: the directory it was moved to, and its workspace.
export const sessionPlaces = (row: { cwd: string | null; workspace: string }): string[] => (row.cwd !== null && row.cwd !== row.workspace ? [row.cwd, row.workspace] : [row.workspace]);

function clip(text: string): string {
  const chars = Array.from(text);
  return chars.length > MAX_TEXT ? `${chars.slice(0, MAX_TEXT).join("")}\n… (${chars.length - MAX_TEXT} more characters)` : text;
}

/// serde_json::to_string_pretty.
const pretty = (v: Json) => JSON.stringify(v, null, 2) ?? "null";

function toText(v: Json): string {
  if (isStr(v)) return v;
  if (Array.isArray(v)) {
    return v
      .map((item) => {
        // A screenshot a tool gave (the computer tool's): named, not its base64.
        if (get(item, "type") === "image") return "[image]";
        const text = get(item, "text");
        return text !== undefined ? (isStr(text) ? text : JSON.stringify(text)) : toText(item);
      })
      .join("\n");
  }
  return pretty(v);
}

/// A post: shown whole in the history, where the agent made it (its words are what people read, not a call to cut).
export const isPosting = (tool: string) => tool === "mcp__stillfail__chat_post" || tool === "mcp__ember__chat_post";

/// What reading keeps between lines: calls taken out of a script.
export type ReadState = { inner: Map<string, number> };

/// A record's timeline entries, read on from `state` (what TranscriptTail keeps between reads): for a reader that takes
/// a transcript a piece at a time as it grows (src/sessions/live.ts).
export function timelineOf(runtime: RuntimeKind, record: Json, state: ReadState, out: TimelineEntry[]): void {
  if (runtime === "claude") claudeTimeline(record, state, out);
  else if (runtime === "dsh") dshTimeline(record, out);
  else if (runtime === "grok") grokTimeline(record, out);
  else if (runtime === "cursor" || runtime === "devin" || runtime === "hermes") cursorTimeline(record, out);
  else codexTimeline(record, state, out);
}

/// What a dsh content part says: its text, an image named.
const dshText = (content: Json): string =>
  (Array.isArray(content) ? content : [])
    .map((c) => (get(c, "type") === "image" ? "[image]" : (stringOf(get(c, "text")) ?? "")))
    .filter((t) => t !== "")
    .join("\n");

function dshTimeline(r: Json, out: TimelineEntry[]) {
  const kind = stringOf(get(r, "type")) ?? "";
  const time = get(r, "time");
  const at = typeof time === "number" && Number.isFinite(time) ? new Date(time).toISOString() : null;
  const data = get(r, "data");
  const message = get(data, "message") ?? data;
  if (kind === "user/message") {
    // What a person (the station) said, not the context dsh adds as a user's message.
    if (get(get(data, "source"), "kind") !== "user") return;
    const text = dshText(get(data, "content"));
    if (trim(text) !== "") out.push({ at, kind: "user", text: clip(text) });
  } else if (kind === "assistant/message") {
    for (const block of Array.isArray(get(message, "content")) ? get(message, "content") : []) {
      const type = stringOf(get(block, "type"));
      const text = stringOf(get(block, "text")) ?? "";
      if (type === "text" && trim(text) !== "") out.push({ at, kind: "assistant", text: clip(text) });
      else if (type === "reasoning" && trim(text) !== "") out.push({ at, kind: "thinking", text: clip(text) });
      else if (type === "tool-call") {
        const name = stringOf(get(block, "name")) ?? "";
        const raw = stringOf(get(block, "arguments")) ?? "";
        let input: Json = raw;
        let args = raw;
        try {
          input = JSON.parse(raw);
          args = pretty(input);
        } catch {}
        const e: TimelineEntry = { at, kind: "tool_call", text: isPosting(name) ? args : clip(args), tool: name };
        const id = stringOf(get(block, "id"));
        if (id !== undefined) e.callId = id;
        out.push(withBrief(e, input));
      }
    }
  } else if (kind === "tool/result") {
    const e: TimelineEntry = { at, kind: "tool_result", text: clip(dshText(get(message, "content"))), ok: get(message, "isError") !== true };
    const id = stringOf(get(message, "toolCallId"));
    if (id !== undefined) e.callId = id;
    out.push(e);
  }
}

/// What a person said as Grok Build keeps it: in a <user_query> it wraps it in.
const grokQuery = (text: string): string => {
  const m = /^\s*<user_query>\n?([\s\S]*?)\n?<\/user_query>\s*$/.exec(text);
  return m ? m[1]! : text;
};

/// Grok Build's chat_history.jsonl: a line a message (system, user, reasoning, assistant with its tool calls,
/// tool_result), with no time of its own.
function grokTimeline(r: Json, out: TimelineEntry[]) {
  const kind = stringOf(get(r, "type")) ?? "";
  const content = get(r, "content");
  if (kind === "user") {
    // What the station said (a prompt), not the context Grok Build adds as a user's message.
    if (get(r, "synthetic_reason") !== undefined || get(r, "prompt_index") === undefined) return;
    const text = grokQuery(isStr(content) ? content : dshText(content));
    if (trim(text) !== "") out.push({ at: null, kind: "user", text: clip(text) });
  } else if (kind === "reasoning") {
    const text = (Array.isArray(get(r, "summary")) ? get(r, "summary") : []).map((s: Json) => stringOf(get(s, "text")) ?? "").filter((t: string) => t !== "").join("\n\n");
    if (trim(text) !== "") out.push({ at: null, kind: "thinking", text: clip(text) });
  } else if (kind === "assistant") {
    const text = isStr(content) ? content : dshText(content);
    if (trim(text) !== "") out.push({ at: null, kind: "assistant", text: clip(text) });
    for (const call of Array.isArray(get(r, "tool_calls")) ? get(r, "tool_calls") : []) {
      let name = stringOf(get(call, "name")) ?? "";
      const raw = stringOf(get(call, "arguments")) ?? "";
      let input: Json = raw;
      let args = raw;
      try {
        input = JSON.parse(raw);
        // An MCP server's tool, reached through its use_tool: named as the tool itself, as Claude Code names one
        // (mcp__server__tool; agents/live.ts acpCall).
        if (name === "use_tool" && isStr(get(input, "tool_name"))) [name, input] = [`mcp__${get(input, "tool_name")}`, get(input, "tool_input") ?? {}];
        args = pretty(input);
      } catch {}
      const e: TimelineEntry = { at: null, kind: "tool_call", text: isPosting(name) ? args : clip(args), tool: name };
      const id = stringOf(get(call, "id"));
      if (id !== undefined) e.callId = id;
      out.push(withBrief(e, input));
    }
  } else if (kind === "tool_result") {
    const text = isStr(content) ? content : toText(content ?? null);
    const e: TimelineEntry = { at: null, kind: "tool_result", text: clip(text), ok: get(r, "is_error") !== true };
    const id = stringOf(get(r, "tool_call_id"));
    if (id !== undefined) e.callId = id;
    out.push(e);
  }
}

/// Cursor's: what the station's driver kept of a session (agents/cursor-bridge.mjs), each call with what it gave back.
function cursorTimeline(r: Json, out: TimelineEntry[]) {
  const kind = stringOf(get(r, "type")) ?? "";
  const time = get(r, "time");
  const at = typeof time === "number" && Number.isFinite(time) ? new Date(time).toISOString() : null;
  if (kind === "user" || kind === "assistant" || kind === "thinking") {
    const text = stringOf(get(r, "text")) ?? "";
    if (trim(text) !== "") out.push({ at, kind, text: clip(text) });
  } else if (kind === "tool") {
    let name = stringOf(get(r, "name")) ?? "";
    let input: Json = get(r, "args") ?? {};
    // An MCP server's tool named as Claude Code names one (mcp__server__tool; agents/live.ts cursorCall).
    if (name === "mcp" && isStr(get(input, "providerIdentifier")) && isStr(get(input, "toolName"))) [name, input] = [`mcp__${get(input, "providerIdentifier")}__${get(input, "toolName")}`, get(input, "args") ?? {}];
    const args = pretty(input);
    const id = stringOf(get(r, "id"));
    const call: TimelineEntry = { at, kind: "tool_call", text: isPosting(name) ? args : clip(args), tool: name };
    if (id !== undefined) call.callId = id;
    out.push(withBrief(call, input));
    const result: TimelineEntry = { at, kind: "tool_result", text: clip(cursorResult(get(r, "result"))), ok: get(r, "status") !== "error" };
    if (id !== undefined) result.callId = id;
    out.push(result);
  }
}

/// What a call of Cursor's gave back, as the history shows it: a command's output, an MCP tool's text, else as it is.
function cursorResult(result: Json): string {
  let r: Json = result;
  if (isStr(r)) {
    try {
      r = JSON.parse(r);
    } catch {
      return r as string;
    }
  }
  const v = get(r, "value") ?? r;
  if (isStr(get(v, "stdout")) || isStr(get(v, "stderr"))) return [stringOf(get(v, "stdout")) ?? "", stringOf(get(v, "stderr")) ?? ""].filter((t) => t !== "").join("\n");
  const content = get(v, "content");
  if (Array.isArray(content)) return content.map((c: Json) => stringOf(get(get(c, "text"), "text")) ?? stringOf(get(c, "text")) ?? "").filter((t: string) => t !== "").join("\n");
  return r === null || r === undefined ? "" : isStr(r) ? r : pretty(r);
}

function claudeTimeline(r: Json, state: ReadState, out: TimelineEntry[]) {
  const kind = stringOf(get(r, "type")) ?? "";
  const at = stringOf(get(r, "timestamp")) ?? null;
  const subagent = get(r, "isSidechain") === true;
  const entry = (kind: string, text: string): TimelineEntry => {
    const e: TimelineEntry = { at, kind, text };
    if (subagent) e.subagent = true;
    return e;
  };
  // A prompt that came while the agent worked (a message, a notice, a background task's end), given to it between two of
  // its calls: Claude Code keeps it as a queued command, not as a user's message, but it is one as much as a prompt
  // that began a turn.
  const queued = get(r, "attachment");
  if (kind === "attachment" && get(queued, "type") === "queued_command") {
    const prompt = get(queued, "prompt");
    for (const t of isStr(prompt) ? [prompt] : (Array.isArray(prompt) ? prompt : []).map((b: Json) => (get(b, "type") === "text" ? stringOf(get(b, "text")) : undefined))) {
      if (t !== undefined && trim(t) !== "") out.push(entry("user", clip(t)));
    }
    return;
  }
  if ((kind !== "user" && kind !== "assistant") || get(r, "isMeta") === true) return;
  // Fields in serde's order: at, kind, text, tool, ok, callId, subagent.
  const withFields = (e: TimelineEntry, more: Partial<TimelineEntry>): TimelineEntry => {
    const v: TimelineEntry = { at: e.at, kind: e.kind, text: e.text };
    if (more.tool !== undefined) v.tool = more.tool;
    if (more.ok !== undefined) v.ok = more.ok;
    if (more.callId !== undefined) v.callId = more.callId;
    if (e.subagent !== undefined) v.subagent = e.subagent;
    return v;
  };
  const content = get(get(r, "message"), "content");
  // A command run in Claude Code itself (`/compact`, asked by hand) and what it printed: the station says it in the chat.
  if (isStr(content) && kind === "user" && /^\s*<(command-name|local-command-stdout|local-command-caveat)>/.test(content)) return;
  if (isStr(content)) {
    out.push(entry(kind, clip(content)));
    return;
  }
  for (const block of Array.isArray(content) ? content : []) {
    const textOf = (k: string) => {
      const t = get(block, k);
      return isStr(t) && t !== "" ? t : undefined;
    };
    switch (stringOf(get(block, "type"))) {
      case "text": {
        const t = textOf("text");
        if (t !== undefined) out.push(entry(kind, clip(t)));
        break;
      }
      case "thinking": {
        const t = textOf("thinking");
        if (t !== undefined) out.push(entry("thinking", clip(t)));
        break;
      }
      case "tool_use": {
        const name = stringOf(get(block, "name")) ?? "";
        const id = stringOf(get(block, "id"));
        const input = pretty(get(block, "input") ?? null);
        out.push(withBrief(withFields(entry("tool_call", isPosting(name) ? input : clip(input)), { tool: name, callId: id }), get(block, "input")));
        break;
      }
      case "tool_result": {
        const id = stringOf(get(block, "tool_use_id"));
        const isError = get(block, "is_error");
        const failed = typeof isError === "boolean" ? isError : false;
        out.push(withFields(entry("tool_result", clip(toText(get(block, "content") ?? null))), { ok: !failed, callId: id }));
        break;
      }
    }
  }
}

/// injected: context Codex prepends as user messages; not what anyone said.
export function injected(text: string): boolean {
  const t = trimStart(text);
  return ["environment_context", "user_instructions", "permissions", "skills_instructions", "collaboration_mode"].some((tag) => {
    if (!t.startsWith(`<${tag}`)) return false;
    const next = Array.from(t.slice(tag.length + 1))[0];
    return next === undefined || (!isAlphanumeric(next) && next !== "_");
  });
}

/// machine_sessions.rs `typed_parts`: what a person typed in a Codex user message, without the context Codex adds.
function typedParts(content: Json): string {
  if (isStr(content)) return content;
  return (Array.isArray(content) ? content : [])
    .map((b) => get(b, "text"))
    .filter(isStr)
    .map(typed)
    .filter((t): t is string => t !== null && trim(t) !== "" && !injected(t) && !wrapped(t))
    .join("\n");
}

/// machine_sessions.rs `typed`: none of the instructions Codex adds; of an editor's context before a request, the request.
function typed(text: string): string | null {
  const t = trimStart(text);
  if (t.startsWith("# AGENTS.md instructions")) return null;
  if (!t.startsWith("#")) return text;
  for (const mark of ["## My request for Codex:", "## My request:"]) {
    const at = t.lastIndexOf(mark);
    if (at >= 0) return trim(t.slice(at + mark.length));
  }
  return text;
}

/// machine_sessions.rs `wrapped`: context Codex adds as a person's message, one tag around all of it.
function wrapped(text: string): boolean {
  const t = trim(text);
  if (!t.startsWith("<")) return false;
  const close = t.indexOf(">", 1);
  if (close < 0) return false;
  const name = t.slice(1, close);
  return name !== "" && /^[A-Za-z0-9_-]+$/.test(name) && t.endsWith(`</${name}>`);
}

function codexTimeline(r: Json, state: ReadState, out: TimelineEntry[]) {
  if (get(r, "type") !== "response_item") return;
  const p = get(r, "payload") ?? null;
  const at = stringOf(get(r, "timestamp")) ?? null;
  const kind = stringOf(get(p, "type")) ?? "";
  const name = stringOf(get(p, "name")) ?? "";
  const callId = stringOf(get(p, "call_id"));
  const call = (tool: string, id: string | undefined, text: string): TimelineEntry => {
    const e: TimelineEntry = { at, kind: "tool_call", text, tool };
    if (id !== undefined) e.callId = id;
    return e;
  };
  const result = (ok: boolean, id: string | undefined, text: string): TimelineEntry => {
    const e: TimelineEntry = { at, kind: "tool_result", text, ok };
    if (id !== undefined) e.callId = id;
    return e;
  };
  switch (kind) {
    case "message": {
      const role = stringOf(get(p, "role")) ?? "";
      if (role !== "user" && role !== "assistant") return;
      const content = get(p, "content") ?? null;
      // A person's: what they typed, without the context Codex adds as parts of their own.
      const text = role === "user" ? typedParts(content) : toText(content);
      if (role === "user" && injected(text)) return;
      if (trim(text) !== "") out.push({ at, kind: role, text: clip(text) });
      return;
    }
    case "reasoning": {
      const content = get(p, "content");
      const chosen = Array.isArray(content) && content.length > 0 ? content : (get(p, "summary") ?? []);
      const text = toText(chosen);
      if (trim(text) !== "") out.push({ at, kind: "thinking", text: clip(text) });
      return;
    }
  }
  if (kind === "custom_tool_call" && name === "exec") {
    // Codex's code mode: the calls in the script are the steps; the script itself is one only when it does more than
    // call them.
    const script = stringOf(get(p, "input")) ?? "";
    const [calls, only] = scriptCalls(script);
    if (!only) out.push(withBrief(call("exec", callId, clip(script)), script));
    calls.forEach(([tool, args], i) => {
      // The script's output answers its first call when the script is nothing but calls.
      const id = callId === undefined ? undefined : only && i === 0 ? callId : `${callId}#${i}`;
      out.push(withBrief(call(tool, id, isPosting(tool) ? pretty(args) : clip(pretty(args))), args));
    });
    // Calls taken out of a script that does more: they are done when the script is.
    if (!only && callId !== undefined && calls.length > 0) state.inner.set(callId, calls.length);
    return;
  }
  if (kind === "function_call" || kind === "custom_tool_call") {
    const given = get(p, "arguments") ?? get(p, "input");
    const raw = given === undefined ? "" : isStr(given) ? given : JSON.stringify(given);
    // Not JSON (custom tools take free text): shown as is.
    let args: string;
    let input: Json = raw;
    try {
      input = JSON.parse(raw);
      args = pretty(input);
    } catch {
      args = raw;
    }
    out.push(withBrief(call(name, callId, isPosting(name) ? args : clip(args)), input));
    return;
  }
  if (kind === "function_call_output" || kind === "custom_tool_call_output") {
    const text = toText(get(p, "output") ?? null);
    const said = text.indexOf("Process exited with code ");
    const failed = said >= 0 && /^[1-9]/.test(text.slice(said + 25));
    out.push(result(!failed, callId, clip(text)));
    const count = callId === undefined ? 0 : (state.inner.get(callId) ?? 0);
    // Done with: what is kept between lines (and at every mark, read/transcripts.ts) is the scripts still running.
    if (callId !== undefined) state.inner.delete(callId);
    for (let i = 0; i < count; i++) out.push(result(!failed, `${callId ?? ""}#${i}`, tr("station.transcript.inScriptOutput")));
  }
}

// ---- code mode's scripts ----

/// script_calls: the tool calls in a code-mode script, `tools.<name>({…})` with a literal argument (read as data,
/// never run), and whether the script is nothing else.
export function scriptCalls(script: string): [[string, Json][], boolean] {
  const chars = Array.from(script);
  const calls: [string, Json][] = [];
  let rest = script;
  let i = 0;
  for (let found = findFrom(chars, i, "tools."); found !== null; found = findFrom(chars, i, "tools.")) {
    let j = found + 6;
    const nameStart = j;
    while (j < chars.length && (isAlphanumeric(chars[j]) || chars[j] === "_" || chars[j] === "$")) j++;
    const name = chars.slice(nameStart, j).join("");
    const first = chars[nameStart];
    const firstOk = first !== undefined && (isAlphabetic(first) || first === "_" || first === "$");
    while (j < chars.length && isWs(chars[j])) j++;
    i = found + 6;
    if (!firstOk || chars[j] !== "(") continue;
    const literal = readLiteral(chars, j + 1);
    if (literal === null) continue;
    let k = literal[1];
    while (k < chars.length && isWs(chars[k])) k++;
    if (chars[k] !== ")") continue;
    calls.push([name, literal[0]]);
    const whole = chars.slice(found, k + 1).join("");
    const at = rest.indexOf(whole);
    if (at >= 0) rest = rest.slice(0, at) + rest.slice(at + whole.length);
    i = k + 1;
  }
  // What is left once the calls are out: nothing but their wrapping.
  const stripped = stripWrapping(rest);
  const only = calls.length > 0 && Array.from(stripped).every((c) => isWs(c) || c === ";");
  return [calls, only];
}

function findFrom(chars: string[], from: number, needle: string): number | null {
  const n = Array.from(needle);
  for (let i = from; i < Math.max(0, chars.length - (n.length - 1)); i++) {
    if (n.every((c, k) => chars[i + k] === c)) return i;
  }
  return null;
}

const bytes = (s: string) => Buffer.byteLength(s);

/// strip_wrapping: `text(await )`, `await` and `text()` taken out (spaces inside allowed), until none is left. As the
/// Rust does, what spaces it skips it counts in bytes over characters.
function stripWrapping(rest: string): string {
  let s = rest;
  for (;;) {
    const before = s;
    let out = "";
    const chars = Array.from(s);
    let i = 0;
    while (i < chars.length) {
      const tail = chars.slice(i).join("");
      if (tail.startsWith("text(")) {
        const after = tail.slice(5);
        const trimmed = trimStart(after);
        const skipped = bytes(after) - bytes(trimmed);
        if (trimmed.startsWith("await")) {
          const afterAwait = trimmed.slice(5);
          const t2 = trimStart(afterAwait);
          if (t2.startsWith(")")) {
            i += 5 + skipped + 5 + (bytes(afterAwait) - bytes(t2)) + 1;
            continue;
          }
        } else if (trimmed.startsWith(")")) {
          i += 5 + skipped + 1;
          continue;
        }
      }
      if (tail.startsWith("await")) {
        i += 5;
        continue;
      }
      out += chars[i];
      i += 1;
    }
    s = out;
    if (s === before) return s;
  }
}

/// read_literal: a JavaScript literal (object, array, string, number, true/false/null) at `at`, as data, and its end;
/// null when it is anything else.
function readLiteral(src: string[], at: number): [Json, number] | null {
  let i = at;
  const space = () => {
    while (i < src.length && isWs(src[i])) i++;
  };
  const string = (): string | null => {
    const quote = src[i];
    i++;
    let out = "";
    while (i < src.length && src[i] !== quote) {
      if (quote === "`" && src[i] === "$" && src[i + 1] === "{") return null;
      if (src[i] === "\\") {
        const next = src[i + 1];
        if (next === undefined) return null;
        if (next === "u") {
          if (i + 6 > src.length) return null;
          const hex = src.slice(i + 2, i + 6).join("");
          // u32::from_str_radix takes a leading +; char::from_u32 no surrogate.
          if (!/^\+?[0-9a-fA-F]+$/.test(hex)) return null;
          const code = parseInt(hex, 16);
          if (code >= 0xd800 && code <= 0xdfff) return null;
          out += String.fromCodePoint(code);
          i += 6;
          continue;
        }
        const escapes: Record<string, string> = { n: "\n", t: "\t", r: "\r", b: "\b", f: "\f", v: "\v", "0": "\0" };
        out += escapes[next] ?? next;
        i += 2;
        continue;
      }
      out += src[i];
      i++;
    }
    if (src[i] !== quote) return null;
    i++;
    return out;
  };
  const value = (): Json | undefined => {
    space();
    const c = src[i];
    if (c === undefined) return undefined;
    if (c === "{") {
      i++;
      const obj: Json = {};
      for (;;) {
        space();
        if (src[i] === "}") {
          i++;
          return obj;
        }
        let key: string;
        if (src[i] === '"' || src[i] === "'") {
          const k = string();
          if (k === null) return undefined;
          key = k;
        } else {
          const start = i;
          const first = src[i];
          if (first === undefined || !(isAlphabetic(first) || first === "_" || first === "$")) return undefined;
          while (i < src.length && (isAlphanumeric(src[i]) || src[i] === "_" || src[i] === "$")) i++;
          key = src.slice(start, i).join("");
        }
        space();
        if (src[i] !== ":") return undefined;
        i++;
        const v = value();
        if (v === undefined) return undefined;
        obj[key] = v;
        space();
        if (src[i] === ",") i++;
        else if (src[i] === "}") {
          i++;
          return obj;
        } else return undefined;
      }
    }
    if (c === "[") {
      i++;
      const list: Json[] = [];
      for (;;) {
        space();
        if (src[i] === "]") {
          i++;
          return list;
        }
        const v = value();
        if (v === undefined) return undefined;
        list.push(v);
        space();
        if (src[i] === ",") i++;
        else if (src[i] === "]") {
          i++;
          return list;
        } else return undefined;
      }
    }
    if (c === '"' || c === "'" || c === "`") return string() ?? undefined;
    const rest = src.slice(i, i + 64).join("");
    for (const word of ["true", "false", "null"]) {
      if (rest.startsWith(word)) {
        i += word.length;
        return JSON.parse(word);
      }
    }
    const len = numberLen(rest);
    if (len === null) return undefined;
    i += len;
    try {
      return JSON.parse(rest.slice(0, len));
    } catch {
      return undefined;
    }
  };
  const v = value();
  return v === undefined ? null : [v, i];
}

/// number_len: the length of a JSON-like number at the start (-?\d+(\.\d+)?([eE][+-]?\d+)?), if one is there.
function numberLen(s: string): number | null {
  const m = /^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/.exec(s);
  return m ? m[0].length : null;
}

// ---- times ----

/// Rust's `str::parse::<i64>` of a few bytes: digits with a sign at most.
function num(b: Buffer, from: number, len: number): number | null {
  if (from + len > b.length) return null;
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(b.subarray(from, from + len));
  } catch {
    return null;
  }
  return /^[+-]?\d+$/.test(text) ? Number(text) : null;
}

const divEuclid = (a: number, b: number) => Math.floor(a / b);

/// parse_iso: milliseconds of an ISO timestamp as transcripts write them, if it is one.
export function parseIso(at: string): number | null {
  const b = Buffer.from(at);
  const parts = [num(b, 0, 4), num(b, 5, 2), num(b, 8, 2), num(b, 11, 2), num(b, 14, 2), num(b, 17, 2)];
  if (parts.some((p) => p === null)) return null;
  const [y, mo, d, h, mi, s] = parts as number[];
  let ms = 0;
  if (b[19] === 0x2e) {
    const frac = /^[0-9]*/.exec(b.subarray(20).toString("utf8"))![0];
    ms = Number(frac.slice(0, 3).padEnd(3, "0"));
  }
  // Days from the civil date (Howard Hinnant's algorithm).
  const [yy, mm] = mo <= 2 ? [y - 1, mo + 9] : [y, mo - 3];
  const era = divEuclid(yy, 400);
  const yoe = yy - era * 400;
  const doy = Math.trunc((153 * mm + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.trunc(yoe / 4) - Math.trunc(yoe / 100) + doy;
  const days = era * 146_097 + doe - 719_468;
  return (days * 86_400 + h * 3600 + mi * 60 + s) * 1000 + ms;
}

/// iso: an ISO timestamp of milliseconds since the epoch, as toISOString writes it (any year, as the Rust does).
export function iso(ms: number): string {
  const days = divEuclid(ms, 86_400_000);
  const rest = ms - days * 86_400_000;
  const z = days + 719_468;
  const era = divEuclid(z, 146_097);
  const doe = z - era * 146_097;
  const yoe = Math.trunc((doe - Math.trunc(doe / 1460) + Math.trunc(doe / 36_524) - Math.trunc(doe / 146_096)) / 365);
  const doy = doe - (365 * yoe + Math.trunc(yoe / 4) - Math.trunc(yoe / 100));
  const mp = Math.trunc((5 * doy + 2) / 153);
  const d = doy - Math.trunc((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  const y = yoe + era * 400 + (m <= 2 ? 1 : 0);
  const pad = (n: number, w: number) => (n < 0 ? `-${String(-n).padStart(w - 1, "0")}` : String(n).padStart(w, "0"));
  const [h, mi, s, milli] = [Math.trunc(rest / 3_600_000), Math.trunc(rest / 60_000) % 60, Math.trunc(rest / 1000) % 60, rest % 1000];
  return `${pad(y, 4)}-${pad(m, 2)}-${pad(d, 2)}T${pad(h, 2)}:${pad(mi, 2)}:${pad(s, 2)}.${pad(milli, 3)}Z`;
}

// ---- reading ----

/// The bytes of a transcript: its file, or its `.zst` decompressed (archive.rs `reader`); null when neither reads.
function transcriptBytes(path: string): { file: number; size: number } | { bytes: Buffer } | null {
  const disk = storage(path);
  try {
    if (disk === path) {
      const file = openSync(path, "r");
      return { file, size: statSync(path).size };
    }
    return { bytes: zstdDecompressSync(readFileOf(disk)) };
  } catch {
    return null;
  }
}

function readFileOf(path: string): Buffer {
  const file = openSync(path, "r");
  try {
    const size = statSync(path).size;
    const out = Buffer.alloc(size);
    let at = 0;
    while (at < size) {
      const n = readSync(file, out, at, size - at, at);
      if (n === 0) break;
      at += n;
    }
    return out.subarray(0, at);
  } finally {
    closeSync(file);
  }
}

/// TranscriptTail::read from the start: the timeline entries of every whole line (one still being written waits). Read
/// a piece at a time, so a long transcript is never one string.
export function readTimeline(runtime: RuntimeKind, path: string): TimelineEntry[] {
  const source = transcriptBytes(path);
  if (source === null) return [];
  const out: TimelineEntry[] = [];
  const state: ReadState = { inner: new Map() };
  const line = (bytes: Buffer) => {
    // str::lines: a line's \r before its \n goes; from_utf8_lossy.
    const text = utf8.decode(bytes.at(-1) === 0x0d ? bytes.subarray(0, -1) : bytes);
    if (text === "") return;
    let record: Json;
    try {
      record = JSON.parse(text);
    } catch {
      return;
    }
    timelineOf(runtime, record, state, out);
  };
  const lines = (chunk: Buffer, carry: Buffer): Buffer => {
    let data: Buffer = carry.length > 0 ? Buffer.concat([carry, chunk]) : chunk;
    for (let nl = data.indexOf(0x0a); nl >= 0; nl = data.indexOf(0x0a)) {
      line(data.subarray(0, nl));
      data = data.subarray(nl + 1);
    }
    return Buffer.from(data);
  };
  if ("bytes" in source) {
    lines(source.bytes, Buffer.alloc(0));
    return out;
  }
  try {
    const piece = Buffer.alloc(4 << 20);
    let carry: Buffer = Buffer.alloc(0);
    for (let at = 0; at < source.size; ) {
      const n = readSync(source.file, piece, 0, Math.min(piece.length, source.size - at), at);
      if (n === 0) break;
      at += n;
      carry = lines(piece.subarray(0, n), carry);
    }
  } catch {
    // As the Rust's read failing: nothing.
    return [];
  } finally {
    closeSync(source.file);
  }
  return out;
}
