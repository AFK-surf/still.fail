// What an agent at work is doing, as a chat shows it (activity.rs): one line, the thing it does now. From a `live`
// topic's value into `activity`: `{ now: { key, text } }`.
import { t } from "./i18n.ts";
import { get, isObject } from "./util.ts";

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

/// A string field of a tool's input, read even when the input is cut short.
export function field(input: string, name: string): string | null {
  try {
    const args = JSON.parse(input) as unknown;
    if (isObject(args)) {
      const v = args[name];
      if (typeof v === "string") return v;
      if (Array.isArray(v)) return v.filter((p): p is string => typeof p === "string").join(" ");
      return null;
    }
  } catch {}
  const at = input.indexOf(`"${name}"`);
  if (at < 0) return null;
  let rest = input.slice(at + name.length + 2).trimStart();
  if (!rest.startsWith(":")) return null;
  rest = rest.slice(1).trimStart();
  if (!rest.startsWith('"')) return null;
  rest = rest.slice(1);
  let out = "";
  const chars = [...rest];
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i];
    if (c === '"') break;
    if (c === "\\") {
      const next = chars[++i];
      if (next === undefined) break;
      out += next === "n" ? "\n" : next === "t" ? "\t" : next;
    } else out += c;
  }
  return out;
}

/// What a call does, in a few words.
export function callText(tool: string, input: string): string {
  const said = field(input, "description")?.trim();
  if (said) return said;
  const kind = kindOf(tool);
  let target: string | null = null;
  for (const name of ["command", "cmd", "file_path", "path", "pattern", "url", "query", "prompt"]) {
    const v = field(input, name);
    if (v !== null) {
      const line = (v.split(/\r?\n/)[0] ?? "").trim();
      target = kind === "read" || kind === "edit" ? (line.split("/").pop() ?? line) : line;
      break;
    }
  }
  const what = target ? `${verb(kind)} ${[...target].slice(0, 80).join("")}` : verb(kind);
  return kind === "other" && toolName(tool) !== "" ? `${verb(kind)} ${toolName(tool)}` : what;
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

/// What the agent does now.
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
  for (const step of Array.isArray(steps) ? steps : []) {
    if (flag(step, "ended") || flag(step, "subagent")) continue;
    const kind = s(step, "step");
    if (kind === "thinking") thinking = true;
    else if (kind === "tool") {
      const tool = s(step, "tool");
      const name = toolName(tool);
      if (name === "chat_post") replying = true;
      else if (name === "chat_state") {
      } else if (s(step, "input").trim() === "" && kindOf(tool) !== "other") {
      } else call = [s(step, "id"), callText(tool, s(step, "input"))];
    }
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
