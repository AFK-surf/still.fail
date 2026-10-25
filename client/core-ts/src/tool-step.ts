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
  try { return JSON.parse(close(t.slice(0, cut.index))); } catch { return undefined; }
}

/**
 * JSON the station cut short (a long call is kept to its first 4000 characters, then `… (n more characters)`), closed
 * where it stops: the string it was in ends with an ellipsis, and what was open is closed.
 */
function close(json: string): string {
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
  const c = a.command ?? a.cmd;
  if (typeof c === "string") return c;
  if (Array.isArray(c) && c.every((p) => typeof p === "string")) {
    const parts = c as string[];
    return /^(ba|z)?sh$/.test(parts[0]?.replace(/.*\//, "") ?? "") && parts[1] === "-lc" ? parts.slice(2).join(" ") : parts.join(" ");
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
  const skip = said ? ["description"] : [];
  const command = commandOf(a);
  const file = str(a.file_path) ?? str(a.notebook_path) ?? str(a.path);
  if (command !== undefined) return [code(command, "sh"), ...facts(a, [...skip, "command", "cmd"])];
  if (file && typeof a.old_string === "string" && typeof a.new_string === "string") {
    return [path(file, a.replace_all ? say("web-main.tool.replaceAll") : undefined), diff(a.old_string, a.new_string)];
  }
  if (file && Array.isArray(a.edits)) {
    return [path(file), ...a.edits.filter(isArgs).map((e) => diff(str(e.old_string) ?? "", str(e.new_string) ?? ""))];
  }
  if (file && typeof a.content === "string") return [path(file), code(a.content, languageOf(file))];
  if (Array.isArray(a.todos) || Array.isArray(a.plan)) {
    const items = ((a.todos ?? a.plan) as unknown[]).filter(isArgs).map((t) => ({ text: str(t.content) ?? str(t.step) ?? "", status: str(t.status) ?? "" }));
    return [...(typeof a.explanation === "string" ? [{ kind: "markdown", text: a.explanation } as ToolPart] : []), { kind: "plan", items }];
  }
  if (typeof a.prompt === "string" && (name === "Agent" || name === "Task" || name === "subagent" || a.prompt.length > 200)) {
    return [...facts(a, [...skip, "prompt"]), { kind: "markdown", text: a.prompt }];
  }
  if (typeof a.text === "string" && a.text.length > 0 && Object.values(a).filter((v) => typeof v === "string" && v.length > 120).length <= 1) {
    return [...facts(a, [...skip, "text"]), { kind: "markdown", text: a.text }];
  }
  if (file && Object.keys(a).every((k) => ["file_path", "path", "notebook_path", "offset", "limit", ...skip].includes(k))) {
    const from = typeof a.offset === "number" ? a.offset : undefined;
    const count = typeof a.limit === "number" ? a.limit : undefined;
    const range = from !== undefined && count !== undefined ? say("web-main.tool.linesFromCount", { from, n: count })
      : from !== undefined ? say("web-main.tool.linesFrom", { from }) : count !== undefined ? say("web-main.tool.lines", { n: count }) : undefined;
    return [path(file, range)];
  }
  // DeepSeek Harness's web_search: several queries at once.
  if (Array.isArray(a.queries) && a.queries.length > 0 && a.queries.every((q) => typeof q === "string")) {
    return [...(a.queries as string[]).map((q): ToolPart => ({ kind: "lead", text: q })), ...facts(a, [...skip, "queries"])];
  }
  if (typeof a.pattern === "string" || typeof a.query === "string" || typeof a.url === "string") {
    const main = str(a.pattern) ?? str(a.query) ?? str(a.url) ?? "";
    const key = typeof a.pattern === "string" ? "pattern" : typeof a.query === "string" ? "query" : "url";
    return [{ kind: "lead", text: main }, fields(a, [...skip, key], say)];
  }
  return [fields(a, skip, say)];
}

/** Codex's command output: how it ended in a header, then the output. */
function commandOutput(text: string, say: Say): { facts: string[]; output: string } | null {
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

/** What a call gave back. */
export function toolResult(name: string, call: string, result: string, failed: boolean, say: Say): ToolPart[] {
  if (!result.trim()) return [{ kind: "none", text: say("web-main.tool.noOutput") }];
  const args = parse(call);
  const file = isArgs(args) ? str(args.file_path) ?? str(args.path) : undefined;
  const output = (text: string, red: boolean): ToolPart => (red ? { kind: "output", text, failed: true } : { kind: "output", text });
  const codex = commandOutput(result, say) ?? (name === "bash" ? exitMarker(result, say) : null);
  if (codex) {
    return [
      ...(codex.facts.length > 0 ? [{ kind: "facts", items: codex.facts.map((f) => ({ key: f, plain: true as const })) } as ToolPart] : []),
      codex.output.trim() ? output(codex.output, failed) : { kind: "none", text: say("web-main.tool.noOutput") },
    ];
  }
  const read = !failed && (name === "Read" || name === "NotebookRead") ? readLines(result) : null;
  if (read !== null) return [code(read, languageOf(file))];
  const inner = !failed && (name === "read" || name === "write") ? unwrap(result) : null;
  if (inner !== null) {
    const lines = name === "read" ? readLines(inner, /^\d+: ?/) : null;
    return [lines !== null ? code(lines, languageOf(file)) : output(inner, false)];
  }
  const parsed = failed ? undefined : parse(result);
  if (parsed !== undefined) return [isArgs(parsed) ? fields(parsed, [], say) : { kind: "json", text: JSON.stringify(parsed, null, 2) }];
  return [output(result, failed)];
}
