// What an agent at work is doing, as a chat shows it (activity.rs): one line, the thing it does now. From a `live`
// topic's value into `activity`: `{ now: { key, text } }`.
import { t } from "./i18n.ts";
import { get } from "./util.ts";

/// A tool's name without its MCP prefix.
export function toolName(tool: string): string {
  for (const p of ["mcp__stillfail__", "stillfail__", "stillfail.", "mcp__ember__", "ember__", "ember."]) if (tool.startsWith(p)) return tool.slice(p.length);
  return tool;
}

/// What kind of thing a tool does, for its icon and its verb. Claude Code's names, Codex's, and DeepSeek Harness's
/// (lowercase: read, bash, …).
export function kindOf(tool: string): string {
  switch (toolName(tool)) {
    case "Read":
    case "NotebookRead":
    case "view_image":
    case "read":
      return "read";
    case "Glob":
    case "Grep":
    case "LS":
    case "ToolSearch":
    case "glob":
    case "grep":
      return "search";
    case "Edit":
    case "MultiEdit":
    case "Write":
    case "NotebookEdit":
    case "apply_patch":
    case "edit":
    case "write":
      return "edit";
    case "Bash":
    case "bash":
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
    case "web_fetch":
      return "web";
    case "Task":
    case "Agent":
    case "spawn_agent":
    case "subagent":
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

/// Steps worth retaining briefly in the chat's activity even if they finish quickly. A shell command or an unknown
/// tool can do many different things, so its importance is not guessed from its words. Routine reads, searches and
/// remote task status checks can instead be coalesced when the agent moves on at once.
export function importantCall(tool: string, input: string): boolean {
  const name = toolName(tool);
  const kind = kindOf(tool);
  if (kind === "edit" || kind === "agent") return true;
  if (name === "station_task") return args(input)?.action === "start";
  return ["request_user_input", "request_user_input_async", "chat_create", "session_send", "job_start"].includes(name);
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

/// What a call's words need beyond its input: the workspace's stations' names by id, and what the tasks prepared on
/// them earlier in the transcript run, by `<station>/<key>` (tasksOf).
export type Known = { stations?: ReadonlyMap<string, string>; tasks?: ReadonlyMap<string, string> };

/// The line of a command that says what it does: not `exec 2>&1`, `set -e`, a comment or a shebang.
function commandLine(command: string): string {
  const lines = command.split(/\r?\n/).map((l) => l.trim()).filter((l) => l !== "");
  return lines.find((l) => !/^(#|set\s+-|exec\s+\d*[<>])/.test(l)) ?? lines[0] ?? "";
}

/// What a station task runs, in a few words: the name it was given, else its command.
function taskOf(a: Record<string, J>): string {
  const name = typeof a.name === "string" ? firstLine(a.name) : "";
  return name || (typeof a.command === "string" ? commandLine(a.command) : "");
}

/// The tasks a transcript prepares on other stations (station_task prepare), by `<station>/<key>`: what each runs.
export function tasksOf(timeline: J[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const e of timeline) {
    if (e?.kind !== "tool_call" || typeof e.tool !== "string" || toolName(e.tool) !== "station_task" || typeof e.text !== "string") continue;
    const a = args(e.text);
    if (a?.action !== "prepare" || typeof a.station !== "string" || typeof a.key !== "string") continue;
    const what = taskOf(a);
    if (what) out.set(`${a.station}/${a.key}`, what);
  }
  return out;
}

/// A call of still.fail's own tools said in words rather than by its name: what it does on which station (station_task,
/// station_file), the tools it loads (ToolSearch's `select:`); null for any other.
export function told(tool: string, input: string, known: Known = {}): string | null {
  const a = args(input);
  if (!a) return null;
  const name = toolName(tool);
  if (name === "station_task" || name === "station_file") {
    const id = typeof a.station === "string" ? a.station : "";
    // An id not among the workspace's (or not read yet) is not shown as its 64 hex digits.
    const station = known.stations?.get(id) ?? (id === "" || /^[0-9a-f]{16,}$/.test(id) ? t("core-logic.activity.remote.another") : id);
    const key = typeof a.key === "string" ? a.key : "";
    if (name === "station_file") {
      const path = typeof a.path === "string" ? (a.path.split("/").pop() ?? a.path) : "";
      return t(`core-logic.activity.remote.${a.direction === "download" ? "download" : "upload"}`, { station, what: path || key });
    }
    if (a.action === "list") return t("core-logic.activity.remote.list", { station });
    if (!["prepare", "start", "get", "log", "stop"].includes(a.action)) return null;
    const what = (a.action === "prepare" ? taskOf(a) : "") || known.tasks?.get(`${id}/${key}`) || key;
    return t(`core-logic.activity.remote.${a.action}`, { station, what });
  }
  if (name === "ToolSearch" && typeof a.query === "string" && a.query.startsWith("select:")) {
    const names = a.query.slice("select:".length).split(",").map((n) => toolName(n.trim())).filter((n) => n !== "");
    if (names.length > 0) return t("core-logic.activity.tools", { names: names.join(t("core-logic.history.did.sep")) });
  }
  return null;
}

/// What a call does, in a few words: its own description, else what still.fail's own tools say of it (told), else its
/// verb and what it works on. The chat's activity says a running call so, and an execution history names a group of
/// calls by its latest the same way.
export function doing(tool: string, input: string, known: Known = {}): string {
  const a = args(input) ?? {};
  const said = typeof a.description === "string" ? firstLine(a.description) : "";
  if (said) return said;
  const own = told(tool, input, known);
  if (own) return own;
  const kind = kindOf(tool);
  let target = "";
  for (const name of ["command", "cmd", "file_path", "path", "pattern", "url", "query", "queries", "prompt"]) {
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
