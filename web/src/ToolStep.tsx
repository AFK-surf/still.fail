// A tool call in the execution history, drawn by what it is rather than as its arguments' JSON: a command as a command,
// an edit as a diff, a file written as highlighted code, a plan as a list; anything else as its fields, one to a row.
// The core gives each step its call (the arguments, pretty JSON or the tool's own free text) and its result as text.
import type { ReactNode } from "react";
import { Code, Prose } from "./Prose.tsx";
import * as css from "./ToolStep.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import { t } from "./i18n.ts";

type Args = Record<string, unknown>;

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

/** The language a file is in, by its extension (Shiki knows most by it: ts, rs, py, kt, …). */
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

/** The small facts beside the main thing (a timeout, a directory, a flag), as `key value` chips. */
function Facts({ a, skip }: { a: Args; skip: string[] }) {
  const rest = Object.entries(a).filter(([k, v]) => !skip.includes(k) && v !== null && v !== undefined && v !== false && typeof v !== "object");
  if (!rest.length) return null;
  return (
    <div className={css.facts}>
      {rest.map(([k, v]) => <span key={k} className={css.fact}>{v === true ? k : <>{k} <b>{String(v)}</b></>}</span>)}
    </div>
  );
}

function Path({ path, extra }: { path: string; extra?: ReactNode | undefined }) {
  return <div className={css.path}><span>{path}</span>{extra && <span className={css.pathExtra}>{extra}</span>}</div>;
}

/** Lines taken out and put in, with the lines both share at the ends as context. */
function Diff({ from, to }: { from: string; to: string }) {
  const a = from.split("\n");
  const b = to.split("\n");
  let head = 0;
  while (head < a.length && head < b.length && a[head] === b[head]) head++;
  let tail = 0;
  while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] === b[b.length - 1 - tail]) tail++;
  const rows: [string, string][] = [
    ...a.slice(0, head).map((l): [string, string] => [" ", l]),
    ...a.slice(head, a.length - tail).map((l): [string, string] => ["-", l]),
    ...b.slice(head, b.length - tail).map((l): [string, string] => ["+", l]),
    ...a.slice(a.length - tail).map((l): [string, string] => [" ", l]),
  ];
  return <Lines rows={rows} />;
}

function Lines({ rows }: { rows: [string, string][] }) {
  return (
    <pre className={css.diff}>
      {rows.map(([mark, text], i) => <div key={i} className={css.diffLine} data-mark={mark === " " ? undefined : mark}>{text || " "}</div>)}
    </pre>
  );
}

/** A patch as apply_patch takes it: file headers, and lines put in and taken out. */
function Patch({ text }: { text: string }) {
  const rows = text.replace(/\n$/, "").split("\n").map((line): [string, string] => {
    if (/^\*\*\* (Add|Update|Delete) File:|^\*\*\* Move to:|^@@/.test(line)) return ["@", line];
    if (/^\*\*\* (Begin|End) Patch/.test(line)) return ["#", line];
    if (line.startsWith("+")) return ["+", line.slice(1)];
    if (line.startsWith("-")) return ["-", line.slice(1)];
    return [" ", line.startsWith(" ") ? line.slice(1) : line];
  }).filter(([mark]) => mark !== "#");
  return <Lines rows={rows} />;
}

function Markdown({ text }: { text: string }) {
  return <div className={`${css.prose} ${conversationCss.markdown}`}><Prose>{text}</Prose></div>;
}

function Block({ text, language }: { text: string; language?: string | undefined }) {
  return <div className={`${css.block} ${conversationCss.markdown}`}><Code text={text} language={language} /></div>;
}

/** A list of things to do, as TodoWrite and update_plan give it. */
function Plan({ items }: { items: { text: string; status: string }[] }) {
  return (
    <ul className={css.plan}>
      {items.map((t, i) => (
        <li key={i} data-status={t.status}><span className={css.planMark} aria-hidden="true">{t.status === "completed" ? "✓" : t.status === "in_progress" ? "›" : "·"}</span>{t.text}</li>
      ))}
    </ul>
  );
}

/** Fields one to a row: short ones inline, long text as a block, nested data as compact JSON. */
function Fields({ a, skip = [] }: { a: Args; skip?: string[] }) {
  const rows = Object.entries(a).filter(([k, v]) => !skip.includes(k) && v !== null && v !== undefined && v !== "");
  if (!rows.length) return <div className={css.none}>{t("web-main.tool.noArgs")}</div>;
  return (
    <dl className={css.fields}>
      {rows.map(([k, v]) => (
        <div key={k} className={css.field}>
          <dt>{k}</dt>
          <dd>{typeof v === "string"
            ? v.includes("\n") || v.length > 120 ? <div className={css.long}>{v}</div> : <span className={css.value}>{v}</span>
            : typeof v === "object" ? <pre className={css.json}>{JSON.stringify(v, null, 2)}</pre>
            : <span className={css.value}>{String(v)}</span>}</dd>
        </div>
      ))}
    </dl>
  );
}

/** What a call asked for. `said`: its description already shows as the step's name. */
export function ToolCall({ name, call, said }: { name: string; call: string; said: boolean }) {
  const parsed = parse(call);
  if (!isArgs(parsed)) {
    if (/^\*\*\* Begin Patch/.test(call.trim())) return <Patch text={call.trim()} />;
    return call.trim() ? <Block text={call} language={name === "exec" ? "js" : undefined} /> : null;
  }
  const a = parsed;
  const skip = said ? ["description"] : [];
  const command = commandOf(a);
  const file = str(a.file_path) ?? str(a.notebook_path) ?? str(a.path);
  if (command !== undefined) {
    return <><Block text={command} language="sh" /><Facts a={a} skip={[...skip, "command", "cmd"]} /></>;
  }
  if (file && typeof a.old_string === "string" && typeof a.new_string === "string") {
    return <><Path path={file} extra={a.replace_all ? t("web-main.tool.replaceAll") : undefined} /><Diff from={a.old_string} to={a.new_string} /></>;
  }
  if (file && Array.isArray(a.edits)) {
    return (
      <><Path path={file} />{a.edits.filter(isArgs).map((e, i) => <Diff key={i} from={str(e.old_string) ?? ""} to={str(e.new_string) ?? ""} />)}</>
    );
  }
  if (file && typeof a.content === "string") {
    return <><Path path={file} /><Block text={a.content} language={languageOf(file)} /></>;
  }
  if (Array.isArray(a.todos) || Array.isArray(a.plan)) {
    const items = ((a.todos ?? a.plan) as unknown[]).filter(isArgs).map((t) => ({ text: str(t.content) ?? str(t.step) ?? "", status: str(t.status) ?? "" }));
    return <>{typeof a.explanation === "string" && <Markdown text={a.explanation} />}<Plan items={items} /></>;
  }
  if (typeof a.prompt === "string" && (name === "Agent" || name === "Task" || a.prompt.length > 200)) {
    return <><Facts a={a} skip={[...skip, "prompt"]} /><Markdown text={a.prompt} /></>;
  }
  if (typeof a.text === "string" && a.text.length > 0 && Object.values(a).filter((v) => typeof v === "string" && v.length > 120).length <= 1) {
    return <><Facts a={a} skip={[...skip, "text"]} /><Markdown text={a.text} /></>;
  }
  if (file && Object.keys(a).every((k) => ["file_path", "path", "notebook_path", "offset", "limit", ...skip].includes(k))) {
    const from = typeof a.offset === "number" ? a.offset : undefined;
    const count = typeof a.limit === "number" ? a.limit : undefined;
    const range = from !== undefined && count !== undefined ? t("web-main.tool.linesFromCount", { from, n: count })
      : from !== undefined ? t("web-main.tool.linesFrom", { from }) : count !== undefined ? t("web-main.tool.lines", { n: count }) : undefined;
    return <Path path={file} extra={range} />;
  }
  if (typeof a.pattern === "string" || typeof a.query === "string" || typeof a.url === "string") {
    const main = str(a.pattern) ?? str(a.query) ?? str(a.url)!;
    const key = typeof a.pattern === "string" ? "pattern" : typeof a.query === "string" ? "query" : "url";
    return <><div className={css.lead}>{main}</div><Fields a={a} skip={[...skip, key]} /></>;
  }
  return <Fields a={a} skip={skip} />;
}

/** Codex's command output: how it ended in a header, then the output. */
function commandOutput(text: string): { facts: string[]; output: string } | null {
  const m = /^(?:Chunk ID: .*\n)?(?:Wall time: (.*)\n)?(?:Process exited with code (-?\d+)\n)?(?:Original token count: .*\n)?Output:\n?/.exec(text);
  if (!m || (!m[1] && !m[2])) return null;
  return { facts: [m[2] !== undefined ? t("web-main.tool.exitCode", { code: m[2] }) : "", m[1] ? t("web-main.tool.took", { time: m[1] }) : ""].filter(Boolean), output: text.slice(m[0].length) };
}

/**
 * Claude Code's Read: `cat -n` lines (`   12→text` or `   12\ttext`), without their numbers; what follows them (a note
 * to the model, where the station cut it short) is left out.
 */
function readLines(text: string): string | null {
  const lines = text.split("\n");
  const numbered = /^\s*\d+(→|\t)/;
  let end = 0;
  while (end < lines.length && numbered.test(lines[end]!)) end++;
  if (end === 0) return null;
  return lines.slice(0, end).map((l) => l.replace(numbered, "")).join("\n");
}

/** What a call gave back. */
export function ToolResult({ name, call, result, failed }: { name: string; call: string; result: string; failed: boolean }) {
  if (!result.trim()) return <div className={css.none}>{t("web-main.tool.noOutput")}</div>;
  const args = parse(call);
  const file = isArgs(args) ? str(args.file_path) ?? str(args.path) : undefined;
  const codex = commandOutput(result);
  if (codex) {
    return (
      <div className={css.result} data-failed={failed || undefined}>
        {codex.facts.length > 0 && <div className={css.facts}>{codex.facts.map((f) => <span key={f} className={css.fact}>{f}</span>)}</div>}
        {codex.output.trim() ? <pre className={css.output}>{codex.output}</pre> : <div className={css.none}>{t("web-main.tool.noOutput")}</div>}
      </div>
    );
  }
  const read = !failed && (name === "Read" || name === "NotebookRead") ? readLines(result) : null;
  if (read !== null) return <div className={css.result}><Block text={read} language={languageOf(file)} /></div>;
  const parsed = failed ? undefined : parse(result);
  if (parsed !== undefined) {
    return <div className={css.result}>{isArgs(parsed) ? <Fields a={parsed} /> : <pre className={css.json}>{JSON.stringify(parsed, null, 2)}</pre>}</div>;
  }
  return <div className={css.result} data-failed={failed || undefined}><pre className={css.output}>{result}</pre></div>;
}
