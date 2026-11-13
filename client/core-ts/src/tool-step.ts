// A tool call in an agent's execution history, read by what it is rather than as its arguments' JSON (web/src/ToolStep.tsx
// and the mbui app's sfdesk draw what this gives): a command as a command, an edit as a diff, a file written as code, a
// plan as a list; anything else as its fields, one to a row. The history gives each step its call (the arguments, pretty
// JSON or the tool's own free text) and its result as text; this reads them into parts a client draws in order. Asked
// of the core as `history.tool`; self-contained (the words through `say`): the web imports it, typechecked as the web is.

/// A part of a call or of what came back, in the order drawn.
export type ToolPart =
  /** Code (a command, a file written or read), in `lang` where known. */
  | { kind: "code"; text: string; lang?: string }
  /** The small facts beside the main thing: `key value`, a flag alone (`value` absent), or words alone (`key` only, `plain`). */
  | { kind: "facts"; items: { key: string; value?: string; plain?: true }[] }
  /** A file's path, with what of it (a range, 全部替换). */
  | { kind: "path"; path: string; extra?: string }
  /** Lines: ` ` the same, `-` taken out, `+` put in, `@` a file's or a hunk's header. */
  | { kind: "diff"; rows: [string, string][] }
  /** Words as Markdown. */
  | { kind: "markdown"; text: string }
  /** A list of things to do: completed, in_progress, or anything else. */
  | { kind: "plan"; items: { text: string; status: string }[] }
  /** Fields one to a row: short in a line, long as a block, nested data as JSON. */
  | { kind: "fields"; rows: { key: string; value: string; form: "short" | "long" | "json" }[] }
  /** The one thing it asked about (a search's words, an address), in a line of its own. */
  | { kind: "lead"; text: string }
  /** Nothing to show, said. */
  | { kind: "none"; text: string }
  /** Program output (`failed`: on the red ground). */
  | { kind: "output"; text: string; failed?: true }
  /** Data that is not fields, as JSON. */
  | { kind: "json"; text: string };

type Args = Record<string, unknown>;
type Say = (key: string, args?: Record<string, string | number>) => string;

function parse(text: string): unknown {
  const t = text.trim();
  if (!t.startsWith("{") && !t.startsWith("[")) return undefined;
  try { return JSON.parse(t); } catch { /* cut short, perhaps */ }
  const cut = /\n… \(\d+ more characters\)$/.exec(t);
  if (!cut) return undefined;
  try { return JSON.parse(closeCut(t.slice(0, cut.index))); } catch { return undefined; }
}

/**
 * JSON the station cut short (a long call is kept to its first 4000 characters, then `… (n more characters)`), closed
 * where it stops: the string it was in ends with an ellipsis, and what was open is closed. (activity.ts too.)
 */
export function closeCut(json: string): string {
  const open: string[] = [];
  let quoted = false;
  let escaped = false;
  for (const c of json) {
    if (escaped) escaped = false;
    else if (quoted) { if (c === "\\") escaped = true; else if (c === '"') quoted = false; }
    else if (c === '"') quoted = true;
    else if (c === "{") open.push("}");
    else if (c === "[") open.push("]");
    else if (c === "}" || c === "]") open.pop();
  }
  let out = json;
  if (quoted) out = `${escaped ? out.slice(0, -1) : out}…"`;
  out = out.replace(/\s+$/, "");
  if (out.endsWith(":")) out += "null";
  else if (out.endsWith(",")) out = out.slice(0, -1);
  return out + open.reverse().join("");
}

/** A workspace path stripped of its session workspace root (`/Users/.../.stillfail/sessions/.../workspace/(stillfail/)?`). */
export function cleanPath(p: string): string {
  const ws = /^(?:\/Users\/[^/]+|\/home\/[^/]+|\/var\/[^/]+|~)?\/?\.(?:stillfail|ember)\/sessions\/[^/]+\/[^/]+\/workspace(?:\/stillfail)?(?:\/(.+))?$/.exec(p);
  if (ws) return ws[1] || ".";
  const brain = /^(?:\/Users\/[^/]+|\/home\/[^/]+|~)?\/?\.(?:stillfail|ember)\/homes\/[^/]+\/agy\/\.gemini\/antigravity-cli\/brain\/[^/]+\/(?:\.system_generated\/)?(.+)$/.exec(p);
  if (brain?.[1]) return brain[1];
  const builtin = /^(?:\/Users\/[^/]+|\/home\/[^/]+|~)?\/?\.(?:stillfail|ember)\/homes\/[^/]+\/agy\/\.gemini\/antigravity-cli\/builtin\/(.+)$/.exec(p);
  if (builtin?.[1]) return builtin[1];
  const agent = /^(?:\/Users\/[^/]+|\/home\/[^/]+|~)?\/?\.(?:stillfail|ember)\/agent\/(.+)$/.exec(p);
  if (agent?.[1]) return agent[1];
  const grokMem = /^(?:\/Users\/[^/]+|\/home\/[^/]+|~)?\/?\.(?:stillfail|ember)\/homes\/[^/]+\/grok\/memory[^/]*\/workspaces\/[^/]+\/(.+)$/.exec(p);
  if (grokMem?.[1]) return `memory/${grokMem[1]}`;
  const homeRuntime = /^(?:\/Users\/[^/]+|\/home\/[^/]+|~)?\/?\.(?:stillfail|ember)\/homes\/[^/]+\/([^/]+)\/(?:sessions\/[^/]+\/)?(.+)$/.exec(p);
  if (homeRuntime?.[1] && homeRuntime[2]) return `${homeRuntime[1]}/${homeRuntime[2]}`;
  const shared = /^(?:\/Users\/[^/]+|\/home\/[^/]+|~)?\/?\.(?:stillfail|ember)\/(?:repos|transcripts)\/(.+)$/.exec(p);
  if (shared?.[1]) return shared[1];
  const overflow = /^(?:\/private)?\/var\/folders\/[^/]+\/[^/]+\/T\/devin-overflows-[^/]+\/(.+)$/.exec(p);
  if (overflow?.[1]) return `devin-overflow/${overflow[1]}`;
  const userHome = /^(?:\/Users|\/home)\/[^/]+\/(.+)$/.exec(p);
  if (userHome?.[1]) return `~/${userHome[1]}`;
  return p;
}

/** A command stripped of a leading `cd /absolute/workspace &&` prefix when present. */
export function cleanCommand(cmd: string): string {
  const m = /^cd\s+(?:"[~/][^"]*"|'[~/][^']*'|[~/][^\s;&|]*)\s*(?:&&|;)\s*([\s\S]+)$/.exec(cmd);
  return m && m[1] ? m[1] : cmd;
}

/** One-line summary of a shell command for collapsed step rows, skipping leading `export` / `cd` / comment lines. */
export function summaryCommand(cmd: string): string {
  const cleanWs = (s: string): string =>
    s.replace(
      /(?:\/Users\/[^/\s"']+|\/home\/[^/\s"']+|~)\/\.(?:stillfail|ember)\/sessions\/[^/\s"']+\/[^/\s"']+\/workspace(?:\/stillfail)?\/?/g,
      "",
    );
  const cleaned = cleanCommand(cmd.trim());
  const lines = cleaned
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith("#"));
  const stripSetup = (line: string): string => {
    let s = line;
    while (true) {
      const next = s
        .replace(/^(?:export\s+[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s;&|]+)\s*(?:&&|;)\s*)/, "")
        .replace(/^(?:cd\s+(?:"[~/][^"]*"|'[~/][^']*'|[~/][^\s;&|]*)\s*(?:&&|;)\s*)/, "");
      if (next === s) break;
      s = next.trim();
    }
    return s;
  };
  const isSetupOnly = (line: string): boolean =>
    /^(?:export\s+[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s;&|]+)|cd\s+(?:"[^"]*"|'[^']*'|[^\s;&|]+)|set\s+-[euo]+(?:\s+pipefail)?)$/.test(
      line,
    );
  const idx = lines.findIndex((l) => {
    const stripped = stripSetup(l);
    return stripped.length > 0 && !isSetupOnly(stripped);
  });
  const firstIdx = idx >= 0 ? idx : 0;
  const first = cleanWs(stripSetup(lines[firstIdx] ?? ""));
  if (/(?:-[ec]\s+['"]|<<-?\s*['"]?\w+['"]?)$/.test(first) && firstIdx + 1 < lines.length) {
    const bodyLine = lines
      .slice(firstIdx + 1)
      .find((l) => !/^(?:import\s|from\s+\S+\s+import\s|['"]use strict['"])/.test(l) && !/^[)}'"]+$/.test(l));
    if (bodyLine) return `${first} ${cleanWs(bodyLine)}`;
  }
  return first || cleanWs(lines[0] ?? "");
}

const isArgs = (v: unknown): v is Args => typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown): string | undefined => typeof v === "string" ? v : undefined;

/** The language a file is in, by its extension (the highlighter knows most by it: ts, rs, py, kt, …). */
function languageOf(path: string | undefined): string | undefined {
  const ext = /\.(\w+)$/.exec(path ?? "")?.[1]?.toLowerCase();
  if (!ext) return undefined;
  return ({ mjs: "js", cjs: "js", mts: "ts", yml: "yaml", zsh: "sh", bash: "sh", h: "c", hpp: "cpp" } as Record<string, string>)[ext] ?? ext;
}

/** A command as it would be typed: `["bash", "-lc", "ls"]` is `ls`. */
function commandOf(a: Args): string | undefined {
  const c = a.command ?? a.cmd ?? a.CommandLine;
  if (typeof c === "string") return cleanCommand(c);
  if (Array.isArray(c) && c.every((p) => typeof p === "string")) {
    const parts = c as string[];
    const joined = /^(ba|z)?sh$/.test(parts[0]?.replace(/.*\//, "") ?? "") && parts[1] === "-lc" ? parts.slice(2).join(" ") : parts.join(" ");
    return cleanCommand(joined);
  }
  return undefined;
}

const code = (text: string, lang?: string): ToolPart => (lang === undefined ? { kind: "code", text } : { kind: "code", text, lang });

/** The small facts beside the main thing (a timeout, a directory, a flag); none, nothing. */
function facts(a: Args, skip: string[]): ToolPart[] {
  const rest = Object.entries(a).filter(([k, v]) => !skip.includes(k) && v !== null && v !== undefined && v !== false && typeof v !== "object");
  if (!rest.length) return [];
  return [{ kind: "facts", items: rest.map(([k, v]) => (v === true ? { key: k } : { key: k, value: String(v) })) }];
}

const path = (p: string, extra?: string): ToolPart => (extra === undefined ? { kind: "path", path: p } : { kind: "path", path: p, extra });

/** Lines taken out and put in, with the lines both share at the ends as context. */
function diff(from: string, to: string): ToolPart {
  const a = from.split("\n");
  const b = to.split("\n");
  let head = 0;
  while (head < a.length && head < b.length && a[head] === b[head]) head++;
  let tail = 0;
  while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] === b[b.length - 1 - tail]) tail++;
  return {
    kind: "diff",
    rows: [
      ...a.slice(0, head).map((l): [string, string] => [" ", l]),
      ...a.slice(head, a.length - tail).map((l): [string, string] => ["-", l]),
      ...b.slice(head, b.length - tail).map((l): [string, string] => ["+", l]),
      ...a.slice(a.length - tail).map((l): [string, string] => [" ", l]),
    ],
  };
}

/** A patch as apply_patch takes it: file headers, and lines put in and taken out. */
function patch(text: string): ToolPart {
  const rows = text.replace(/\n$/, "").split("\n").map((line): [string, string] => {
    if (/^\*\*\* (Add|Update|Delete) File:|^\*\*\* Move to:|^@@/.test(line)) return ["@", line];
    if (/^\*\*\* (Begin|End) Patch/.test(line)) return ["#", line];
    if (line.startsWith("+")) return ["+", line.slice(1)];
    if (line.startsWith("-")) return ["-", line.slice(1)];
    return [" ", line.startsWith(" ") ? line.slice(1) : line];
  }).filter(([mark]) => mark !== "#");
  return { kind: "diff", rows };
}

/** Fields one to a row: short ones inline, long text as a block, nested data as compact JSON. */
function fields(a: Args, skip: string[], say: Say): ToolPart {
  const rows = Object.entries(a).filter(([k, v]) => !skip.includes(k) && v !== null && v !== undefined && v !== "");
  if (!rows.length) return { kind: "none", text: say("web-main.tool.noArgs") };
  return {
    kind: "fields",
    rows: rows.map(([k, v]) => typeof v === "string"
      ? { key: k, value: v, form: v.includes("\n") || v.length > 120 ? "long" : "short" }
      : typeof v === "object" ? { key: k, value: JSON.stringify(v, null, 2), form: "json" }
      : { key: k, value: String(v), form: "short" }),
  };
}

/** What a call asked for. `said`: its description already shows as the step's name. */
export function toolCall(name: string, call: string, said: boolean, say: Say): ToolPart[] {
  const parsed = parse(call);
  if (!isArgs(parsed)) {
    if (/^\*\*\* Begin Patch/.test(call.trim())) return [patch(call.trim())];
    return call.trim() ? [code(call, name === "exec" ? "js" : undefined)] : [];
  }
  const a = parsed;
  const skip = said ? ["description", "toolSummary", "explanation"] : ["toolSummary"];
  const command = commandOf(a);
  const rawFile = str(a.file_path) ?? str(a.notebook_path) ?? str(a.target_file) ?? str(a.path) ?? str(a.Path);
  const file = rawFile !== undefined ? cleanPath(rawFile) : undefined;
  if (command !== undefined) return [code(command, "sh"), ...facts(a, [...skip, "command", "cmd", "CommandLine", "WaitMsBeforeAsync"])];
  const oldStr = str(a.old_string) ?? str(a.Target);
  const newStr = str(a.new_string) ?? str(a.Replacement);
  if (file && oldStr !== undefined && newStr !== undefined) {
    return [path(file, a.replace_all ? say("web-main.tool.replaceAll") : undefined), diff(oldStr, newStr)];
  }
  if (file && Array.isArray(a.edits)) {
    return [path(file), ...a.edits.filter(isArgs).map((e) => diff(str(e.old_string) ?? str(e.Target) ?? "", str(e.new_string) ?? str(e.Replacement) ?? ""))];
  }
  const fileContent = str(a.content) ?? str(a.Content);
  if (file && fileContent !== undefined) return [path(file), code(fileContent, languageOf(file))];
  if (Array.isArray(a.todos) || Array.isArray(a.plan)) {
    const items = ((a.todos ?? a.plan) as unknown[]).filter(isArgs).map((t) => ({ text: str(t.content) ?? str(t.step) ?? "", status: str(t.status) ?? "" }));
    return [...(typeof a.explanation === "string" ? [{ kind: "markdown", text: a.explanation } as ToolPart] : []), { kind: "plan", items }];
  }
  const prompt = str(a.prompt) ?? str(a.Prompt);
  if (prompt !== undefined && (name === "Agent" || name === "Task" || name === "subagent" || name === "invoke_subagent" || prompt.length > 200)) {
    return [...facts(a, [...skip, "prompt", "Prompt"]), { kind: "markdown", text: prompt }];
  }
  if (typeof a.text === "string" && a.text.length > 0 && Object.values(a).filter((v) => typeof v === "string" && v.length > 120).length <= 1) {
    return [...facts(a, [...skip, "text"]), { kind: "markdown", text: a.text }];
  }
  if (file && Object.keys(a).every((k) => ["file_path", "target_file", "path", "Path", "notebook_path", "offset", "limit", "StartLine", "EndLine", "ByteOffset", "start_line", "end_line", ...skip].includes(k))) {
    const startLine = typeof a.StartLine === "number" ? a.StartLine : typeof a.start_line === "number" ? a.start_line : undefined;
    const endLine = typeof a.EndLine === "number" ? a.EndLine : typeof a.end_line === "number" ? a.end_line : undefined;
    const from = startLine ?? (typeof a.offset === "number" ? a.offset : undefined);
    const count = startLine !== undefined && endLine !== undefined && endLine >= startLine
      ? endLine - startLine + 1
      : typeof a.limit === "number" ? a.limit : undefined;
    const range = from !== undefined && count !== undefined ? say("web-main.tool.linesFromCount", { from, n: count })
      : from !== undefined ? say("web-main.tool.linesFrom", { from }) : count !== undefined ? say("web-main.tool.lines", { n: count }) : undefined;
    return [path(file, range)];
  }
  // DeepSeek Harness's web_search: several queries at once.
  if (Array.isArray(a.queries) && a.queries.length > 0 && a.queries.every((q) => typeof q === "string")) {
    return [...(a.queries as string[]).map((q): ToolPart => ({ kind: "lead", text: q })), ...facts(a, [...skip, "queries"])];
  }
  const searchKey = ["pattern", "Pattern", "query", "Query", "url"].find((k) => typeof a[k] === "string");
  if (searchKey !== undefined) {
    const main = str(a[searchKey]) ?? "";
    return [{ kind: "lead", text: main }, fields(a, [...skip, searchKey], say)];
  }
  return [fields(a, skip, say)];
}

/** Codex's or Antigravity's command output: how it ended in a header, then the output. */
function commandOutput(text: string, say: Say): { facts: string[]; output: string } | null {
  const agy = /^(?:The tool's output was truncated[^\n]*\n\nHere is a preview[^\n]*\n)?Created At:\s*(\S+)\r?\nCompleted At:\s*(\S+)\r?\nCommand exited with code (-?\d+)\.?(?:(?:\r?\n)+Command output:\r?\n?)?/.exec(text);
  if (agy && agy[3] !== undefined) {
    return {
      facts: [say("web-main.tool.exitCode", { code: agy[3] })],
      output: text.slice(agy[0].length),
    };
  }
  const m = /^(?:Chunk ID: .*\n)?(?:Wall time: (.*)\n)?(?:Process exited with code (-?\d+)\n)?(?:Original token count: .*\n)?Output:\n?/.exec(text);
  if (!m || (!m[1] && !m[2])) return null;
  return { facts: [m[2] !== undefined ? say("web-main.tool.exitCode", { code: m[2] }) : "", m[1] ? say("web-main.tool.took", { time: m[1] }) : ""].filter(Boolean), output: text.slice(m[0].length) };
}

/** DeepSeek Harness's bash: its output, then how it ended where that was not well (`[exit code: 1]`). */
function exitMarker(text: string, say: Say): { facts: string[]; output: string } | null {
  const m = /\n?\[exit code: (-?\d+)\]\s*$/.exec(text);
  return m ? { facts: [say("web-main.tool.exitCode", { code: m[1] ?? "" })], output: text.slice(0, m.index) } : null;
}

/** DeepSeek Harness's read and write: the file's path and kind, then what is in it (or what was done), in tags (the end
 * missing where the station cut it short). */
function unwrap(text: string): string | null {
  const m = /^<path>[^\n]*<\/path>\n<type>[^\n]*<\/type>\n<content>\n?([\s\S]*?)\n?(?:<\/content>\s*)?$/.exec(text);
  return m ? m[1] ?? "" : null;
}

/**
 * Claude Code's Read: `cat -n` lines (`   12→text` or `   12\ttext`), without their numbers; what follows them (a note
 * to the model, where the station cut it short) is left out. DeepSeek Harness's read numbers them `12: text`.
 */
function readLines(text: string, numbered = /^\s*\d+(→|\t)/): string | null {
  const lines = text.split("\n");
  let end = 0;
  while (end < lines.length && numbered.test(lines[end] ?? "")) end++;
  if (end === 0) return null;
  return lines.slice(0, end).map((l) => l.replace(numbered, "")).join("\n");
}

const FILE_STEP_NAMES = new Set([
  "Read",
  "Edit",
  "Write",
  "MultiEdit",
  "NotebookRead",
  "NotebookEdit",
  "read",
  "edit",
  "write",
  "read_file",
  "edit_file",
  "write_file",
  "search_replace",
]);

/** What a call gave back. */
export function toolResult(name: string, call: string, result: string, failed: boolean, say: Say): ToolPart[] {
  const isFileStep = FILE_STEP_NAMES.has(name) || name.startsWith("File ");
  if (!result.trim()) return !failed && isFileStep ? [] : [{ kind: "none", text: say("web-main.tool.noOutput") }];
  const args = parse(call);
  const rawFile = isArgs(args) ? str(args.file_path) ?? str(args.target_file) ?? str(args.path) ?? str(args.Path) : undefined;
  const file = rawFile !== undefined ? cleanPath(rawFile) : undefined;
  const output = (text: string, red: boolean): ToolPart => (red ? { kind: "output", text, failed: true } : { kind: "output", text });
  const codex = commandOutput(result, say) ?? (name === "bash" ? exitMarker(result, say) : null);
  if (codex) {
    return [
      ...(codex.facts.length > 0 ? [{ kind: "facts", items: codex.facts.map((f) => ({ key: f, plain: true as const })) } as ToolPart] : []),
      codex.output.trim() ? output(codex.output, failed) : { kind: "none", text: say("web-main.tool.noOutput") },
    ];
  }
  const stripped = result.replace(/^(?:The tool's output was truncated[^\n]*\n\nHere is a preview[^\n]*\n)?Created At:\s*\S+\r?\nCompleted At:\s*\S+(?:\r?\n)+/, "");
  const agyReadBody = stripped
    .replace(
      /(?:^|\r?\n)(?:(?:The tool's output was truncated[^\n]*\n\nHere is a preview[^\n]*\n)?Created At:\s*\S+\r?\nCompleted At:\s*\S+(?:\r?\n)+)?(?:Partial read[^\n]*\r?\n)?Showing lines \d+-\d+ of \d+\r?\n/g,
      "\n",
    )
    .replace(/^\n+/, "");
  const read = !failed && (name === "Read" || name === "NotebookRead" || name === "read_file" || name.startsWith("File "))
    ? (readLines(result) ?? (agyReadBody !== stripped ? readLines(agyReadBody, /^\d+: ?/) : null))
    : null;
  if (read !== null) return [code(read, languageOf(file))];
  if (!failed && (name === "Edit" || name === "edit" || name === "edit_file" || name === "search_replace" || name.startsWith("File "))) {
    const cleanStripped = stripped
      .replace(/(?:^|\r?\n)Created At:\s*\S+\r?\nCompleted At:\s*\S+(?:\r?\n)+/g, "\n")
      .trim();
    const agyEdit = /^Made \d+ replacements? in .+ starting at line (\d+) \(\+(\d+)\/-(\d+) lines\)\.\s*$/.exec(cleanStripped);
    if (agyEdit) {
      return [{ kind: "facts", items: [{ key: `第 ${agyEdit[1]} 行 · +${agyEdit[2]} / -${agyEdit[3]}`, plain: true }] }];
    }
    if (cleanStripped.split(/\r?\n/).every((l) => /^Made \d+ replacements? in [^\n]+$/.test(l.trim()))) {
      return [];
    }
  }
  const inner = !failed && (name === "read" || name === "write") ? unwrap(result) : null;
  if (inner !== null) {
    const lines = name === "read" ? readLines(inner, /^\d+: ?/) : null;
    return [lines !== null ? code(lines, languageOf(file)) : output(inner, false)];
  }
  const body = stripped.trim() !== "" ? stripped : result;
  const parsed = failed ? undefined : parse(body);
  if (parsed !== undefined) return [isArgs(parsed) ? fields(parsed, [], say) : { kind: "json", text: JSON.stringify(parsed, null, 2) }];
  return [output(body, failed)];
}
