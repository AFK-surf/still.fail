// What an agent at work is doing, as a chat shows it (activity.rs): one line, the thing it does now. From a `live`
// topic's value into `activity`: `{ now: { key, text } }`.
import { t } from "./i18n.ts";
import { get } from "./util.ts";

/// A tool's name without its MCP prefix.
export function toolName(tool: string): string {
  for (const p of ["mcp__stillfail__", "stillfail__", "stillfail.", "mcp__ember__", "ember__", "ember."]) if (tool.startsWith(p)) return tool.slice(p.length);
  return tool;
}

/// What kind of thing a tool does, for its icon and its verb.
export function kindOf(tool: string): string {
  switch (toolName(tool)) {
    case "Read":
    case "NotebookRead":
    case "view_image":
      return "read";
    case "Glob":
    case "Grep":
    case "LS":
    case "ToolSearch":
      return "search";
    case "Edit":
    case "MultiEdit":
    case "Write":
    case "NotebookEdit":
    case "apply_patch":
      return "edit";
    case "Bash":
    case "BashOutput":
    case "KillShell":
    case "exec_command":
    case "shell":
    case "local_shell":
    case "write_stdin":
    case "unified_exec":
      return "command";
    case "WebFetch":
    case "WebSearch":
    case "web_search":
      return "web";
    case "Task":
    case "Agent":
    case "spawn_agent":
      return "agent";
    case "chat_history":
    case "chat_list":
    case "chat_read":
    case "session_history":
      return "thread";
    default:
      return "other";
  }
}

function verb(kind: string): string {
  return ["read", "search", "edit", "command", "web", "agent", "thread"].includes(kind) ? t(`core-logic.activity.verb.${kind}`) : t("core-logic.activity.verb.other");
}

// deno-lint-ignore no-explicit-any
type J = any;

function parseObject(text: string): Record<string, J> | null {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

/// A call's input as an object: whole, kept to its first characters (a transcript's `… (n more characters)`), or cut
/// short anywhere (an older station's live step carried its first 300 characters).
export function args(text: string): Record<string, J> | null {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    // Not whole: read below.
  }
  // A long call is kept to its first characters, then `… (n more characters)`: read what is there.
  const at = text.lastIndexOf("\n… (");
  if (at >= 0 && text.endsWith(" more characters)")) return cutShort(text.slice(0, at));
  return text.trimStart().startsWith("{") ? cutShort(text) : null;
}

/// JSON cut short, read as far as it goes: closed where it stops, or (cut in a key, `{"a":"x","descr`) at the field before.
function cutShort(json: string): Record<string, J> | null {
  const whole = parseObject(close(json));
  if (whole) return whole;
  let quoted = false;
  let escaped = false;
  let comma = -1;
  for (let i = 0; i < json.length; i++) {
    const c = json[i];
    if (escaped) escaped = false;
    else if (quoted) {
      if (c === "\\") escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === ",") comma = i;
  }
  return comma < 0 ? null : parseObject(close(json.slice(0, comma)));
}

/// JSON cut short, closed where it stops: the string it was in ends with an ellipsis, and what was open is closed.
function close(json: string): string {
  const open: string[] = [];
  let quoted = false;
  let escaped = false;
  for (const c of json) {
    if (escaped) escaped = false;
    else if (quoted) {
      if (c === "\\") escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === "{") open.push("}");
    else if (c === "[") open.push("]");
    else if (c === "}" || c === "]") open.pop();
  }
  let out = json;
  if (quoted) {
    if (escaped) out = out.slice(0, -1);
    out += '…"';
  }
  out = out.trimEnd();
  if (out.endsWith(":")) out += "null";
  else if (out.endsWith(",")) out = out.slice(0, -1);
  return out + open.reverse().join("");
}

const firstLine = (s: string) => (s.split(/\r?\n/).find((l) => l.trim() !== "") ?? "").trim();

/// What a call does, in a few words: its own description, else its verb and what it works on. The chat's activity
/// says a running call so, and an execution history names a group of calls by its latest the same way.
export function doing(tool: string, input: string): string {
  const a = args(input) ?? {};
  const said = typeof a.description === "string" ? firstLine(a.description) : "";
  if (said) return said;
  const kind = kindOf(tool);
  let target = "";
  for (const name of ["command", "cmd", "file_path", "path", "pattern", "url", "query", "prompt"]) {
    const v = a[name];
    const s = typeof v === "string" ? v : Array.isArray(v) ? v.filter((p): p is string => typeof p === "string").join(" ") : null;
    if (s === null) continue;
    const line = firstLine(s);
    target = kind === "read" || kind === "edit" ? (line.split("/").pop() ?? line) : line;
    break;
  }
  return `${kind === "other" ? toolName(tool) : verb(kind)} ${target}`.trim();
}

/// Milliseconds since the epoch of an RFC 3339 time; null for anything else.
export function epochMs(at: string): number | null {
  if (at.length < 19 || at[4] !== "-" || at[10] !== "T") return null;
  const num = (a: number, b: number) => {
    const s = at.slice(a, b);
    return /^[+-]?\d+$/.test(s) ? Number(s) : null;
  };
  const [y0, m, d, hh, mm, ss] = [num(0, 4), num(5, 7), num(8, 10), num(11, 13), num(14, 16), num(17, 19)];
  if ([y0, m, d, hh, mm, ss].some((v) => v === null)) return null;
  const fracMatch = at.slice(19).startsWith(".") ? /^\d*/.exec(at.slice(20))![0] : "";
  const ms = fracMatch === "" ? 0 : Number(`0.${fracMatch}`) * 1000;
  const y = m! <= 2 ? y0! - 1 : y0!;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const doy = Math.trunc((153 * (m! > 2 ? m! - 3 : m! + 9) + 2) / 5) + d! - 1;
  const doe = yoe * 365 + Math.trunc(yoe / 4) - Math.trunc(yoe / 100) + doy;
  const days = era * 146097 + doe - 719468;
  return (((days * 24 + hh!) * 60 + mm!) * 60 + ss!) * 1000 + ms;
}

/// What the agent does now: the call its execution history shows running (the transcript's, said by `doing`), else
/// what its live steps and phase say (thinking, writing, replying). The live steps' own copy of a call's input is not
/// read: the transcript is the one record of what a call runs.
export function present(live: unknown): unknown {
  const steps = (get(live, "steps") as unknown[] | undefined) ?? [];
  const s = (v: unknown, k: string) => {
    const x = get(v, k);
    return typeof x === "string" ? x : "";
  };
  const flag = (v: unknown, k: string) => get(v, k) === true;
  let call: [string, string] | null = null;
  let replying = false;
  let thinking = false;
  // This turn's calls with no result yet, as the execution history pairs them (history.ts present): a result by its
  // call's id, or one without an id the latest call before it.
  const timeline = (get(live, "timeline") as unknown[] | undefined) ?? [];
  const running: [string, number][] = [];
  (Array.isArray(timeline) ? timeline : []).forEach((e, i) => {
    const kind = s(e, "kind");
    if (kind === "user") running.length = 0;
    else if (kind === "tool_call" && !flag(e, "subagent")) running.push([s(e, "callId"), i]);
    else if (kind === "tool_result" && !flag(e, "subagent")) {
      const id = s(e, "callId");
      const at = id !== "" ? running.findIndex(([c]) => c === id) : running.length - 1;
      if (at >= 0) running.splice(at, 1);
    }
  });
  for (const [id, i] of running) {
    const e = timeline[i];
    const name = toolName(s(e, "tool"));
    if (name === "chat_post") replying = true;
    else if (name !== "chat_state") call = [id !== "" ? id : `call:${i}`, doing(s(e, "tool"), s(e, "text"))];
  }
  for (const step of Array.isArray(steps) ? steps : []) {
    if (flag(step, "ended") || flag(step, "subagent")) continue;
    const kind = s(step, "step");
    if (kind === "thinking") thinking = true;
    else if (kind === "tool" && toolName(s(step, "tool")) === "chat_post") replying = true;
  }
  const r = get(live, "rate");
  const rate = typeof r === "number" && Number.isInteger(r) && r >= 0 ? r : 0;
  const phase = s(get(live, "phase"), "phase");
  let key: string;
  let text: string;
  if (call) [key, text] = call;
  else if (replying) {
    key = "reply";
    text = rate > 0 ? `${t("core-logic.activity.replying")} · ≈ ${rate} token/s` : t("core-logic.activity.replying");
  } else {
    let k: string;
    let w: string;
    if (thinking) [k, w] = ["think", "core-logic.activity.thinking"];
    else if (phase === "starting") [k, w] = ["starting", "core-logic.activity.starting"];
    else if (phase === "requesting") [k, w] = ["requesting", "core-logic.activity.requesting"];
    else if (phase === "thinking") [k, w] = ["think", "core-logic.activity.thinking"];
    else if (phase === "responding") [k, w] = ["write", "core-logic.activity.writing"];
    else [k, w] = ["busy", "core-logic.activity.busy"];
    key = k;
    const said = t(w);
    text = rate > 0 ? `${said} · ≈ ${rate} token/s` : said;
  }
  return { now: { key, text } };
}
