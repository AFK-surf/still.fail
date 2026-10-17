// A tool call in the execution history, drawn by what it is rather than as its arguments' JSON (web/src/ToolStep.tsx):
// a command as a command, an edit as a diff, a file written or read as highlighted code, a patch as its lines, a plan
// as a list; anything else as its fields, one to a row. The core gives each step its call (the arguments, pretty JSON
// or the tool's own free text) and its result as text. (The Android app's ui/ToolStep.kt.)
import { useMemo, type ReactNode } from "react";
import { ScrollView, Text, View } from "react-native";
import { t } from "../i18n";
import { AnnotatedText } from "./Annotated";
import { highlight } from "./Highlight";
import { Markdown, codeGround, webMuted, webSubtle } from "./Markdown";
import { Smooth } from "./Smooth";
import { T } from "./Text";
import { CODE_FONT, useC, type StillFailColors } from "./Theme";

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
type JsonObject = { [k: string]: Json };

const isObject = (v: Json | undefined): v is JsonObject => v != null && typeof v === "object" && !Array.isArray(v);

function parse(text: string): Json | null {
  const tr = text.trim();
  if (!tr.startsWith("{") && !tr.startsWith("[")) return null;
  try { return JSON.parse(tr) as Json; } catch { /* cut short, perhaps */ }
  const cut = /\n… \(\d+ more characters\)$/.exec(tr);
  if (!cut) return null;
  try { return JSON.parse(close(tr.substring(0, cut.index))) as Json; } catch { return null; }
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
    else if (quoted) { if (c === "\\") escaped = true; else if (c === "\"") quoted = false; }
    else if (c === "\"") quoted = true;
    else if (c === "{") open.push("}");
    else if (c === "[") open.push("]");
    else if (c === "}" || c === "]") open.pop();
  }
  let out = json;
  if (quoted) out = `${escaped ? out.slice(0, -1) : out}…"`;
  out = out.trimEnd();
  if (out.endsWith(":")) out += "null"; else if (out.endsWith(",")) out = out.slice(0, -1);
  return out + open.reverse().join("");
}

const str = (v: Json | undefined): string | null => (typeof v === "string" ? v : null);
const num = (v: Json | undefined): number | null => (typeof v === "number" ? v : null);
const isScalar = (v: Json | undefined) => typeof v === "string" || typeof v === "number" || typeof v === "boolean";

/** A scalar as written: a string's words, a number or true as JSON has them. */
const text = (v: string | number | boolean): string => (typeof v === "string" ? v : String(v));

/** The language a file is in, by its extension. */
function languageOf(path: string | null | undefined): string | null {
  const m = /\.(\w+)$/.exec(path ?? "");
  if (!m) return null;
  const ext = m[1]!.toLowerCase();
  const as: Record<string, string> = { mjs: "js", cjs: "js", mts: "ts", yml: "yaml", zsh: "sh", bash: "sh", h: "c", hpp: "cpp" };
  return as[ext] ?? ext;
}

/** A command as it would be typed: `["bash", "-lc", "ls"]` is `ls`. */
function commandOf(a: JsonObject): string | null {
  const c = a.command ?? a.cmd;
  const s = str(c);
  if (s != null) return s;
  if (Array.isArray(c) && c.every((p) => str(p) != null)) {
    const parts = c as string[];
    const first = parts[0] ?? "";
    return /^(ba|z)?sh$/.test(first.substring(first.lastIndexOf("/") + 1)) && parts[1] === "-lc" ? parts.slice(2).join(" ") : parts.join(" ");
  }
  return null;
}

// ── the parts (ToolStep.css.ts) ────────────────────────────────────────

const red = (C: StillFailColors) => (C.dark ? "#F68482" : "#A12F35");
const redBg = (C: StillFailColors) => (C.dark ? "#442322" : "#FFF0EF");
const green = (C: StillFailColors) => (C.dark ? "#68C894" : "#006A3F");
const greenBg = (C: StillFailColors) => (C.dark ? "#1B3426" : "#E7F6ED");

/** The quiet tinted box code and output sit in, kept to `max` high (it scrolls within). */
function Boxed({ max = 360, ground, vertical = 8, horizontal = 12, children }: { max?: number; ground?: string; vertical?: number; horizontal?: number; children: ReactNode }) {
  const C = useC();
  return (
    <Smooth radius={10} style={{ alignSelf: "stretch", backgroundColor: ground ?? codeGround(C) }}>
      <ScrollView nestedScrollEnabled style={{ maxHeight: max }} contentContainerStyle={{ paddingHorizontal: horizontal, paddingVertical: vertical }}>
        {children}
      </ScrollView>
    </Smooth>
  );
}

const mono = CODE_FONT;

/** Highlighted code (a command, a file written, a file read), as markdown shows it but wrapping and capped in height. */
function Block({ text: code, language }: { text: string; language: string | null }) {
  const C = useC();
  const dark = C.dark;
  const colored = useMemo(() => highlight(code, language, dark), [code, language, dark]);
  return (
    <Smooth radius={12} style={{ alignSelf: "stretch", backgroundColor: codeGround(C) }}>
      <ScrollView nestedScrollEnabled style={{ maxHeight: 360 }} contentContainerStyle={{ paddingHorizontal: 12, paddingVertical: 8 }}>
        <AnnotatedText text={colored} style={{ fontFamily: mono, fontSize: 12, lineHeight: 18.6, color: C.ink }} />
      </ScrollView>
    </Smooth>
  );
}

function Prose({ text: words }: { text: string }) {
  return <Boxed max={100000}><Markdown text={words} size={12} /></Boxed>;
}

/** The small facts beside the main thing (a timeout, a directory, a flag), as `key value`. */
function Facts({ a, skip }: { a: JsonObject; skip: string[] }) {
  const rest = Object.entries(a).filter(([k, v]) => !skip.includes(k) && isScalar(v) && v !== false);
  if (rest.length === 0) return null;
  return <FactRow facts={rest.map(([k, v]) => [k, v === true ? null : text(v as string | number | boolean)])} />;
}

function FactRow({ facts }: { facts: [string, string | null][] }) {
  const C = useC();
  const subtle = webSubtle(C);
  const muted = webMuted(C);
  return (
    <View style={{ paddingHorizontal: 2, flexDirection: "row", flexWrap: "wrap", columnGap: 10, rowGap: 4 }}>
      {facts.map(([k, v], i) => (
        <T key={i} size={11} color={subtle}>
          {k}
          {v != null && <>{" "}<Text style={{ fontWeight: "500", color: muted, fontFamily: mono }}>{v}</Text></>}
        </T>
      ))}
    </View>
  );
}

function PathLine({ path, extra }: { path: string; extra?: string | null }) {
  const C = useC();
  return (
    <View style={{ paddingHorizontal: 2, flexDirection: "row", gap: 8, alignItems: "flex-end" }}>
      <T size={12} line={18} color={C.ink} style={{ fontFamily: mono, flexShrink: 1 }}>{path}</T>
      {extra != null && <T size={11} line={18} color={webSubtle(C)}>{extra}</T>}
    </View>
  );
}

type Mark = " " | "-" | "+" | "@";

/** Lines taken out and put in, with the lines both share at the ends as context. */
function Diff({ from, to }: { from: string; to: string }) {
  const a = from.split("\n");
  const b = to.split("\n");
  let head = 0;
  while (head < a.length && head < b.length && a[head] === b[head]) head++;
  let tail = 0;
  while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] === b[b.length - 1 - tail]) tail++;
  const rows: [Mark, string][] = [
    ...a.slice(0, head).map((l): [Mark, string] => [" ", l]),
    ...a.slice(head, a.length - tail).map((l): [Mark, string] => ["-", l]),
    ...b.slice(head, b.length - tail).map((l): [Mark, string] => ["+", l]),
    ...a.slice(a.length - tail).map((l): [Mark, string] => [" ", l]),
  ];
  return <Lines rows={rows} />;
}

function Lines({ rows }: { rows: [Mark, string][] }) {
  const C = useC();
  return (
    <Boxed vertical={6} horizontal={0}>
      <View>
        {rows.map(([mark, line], i) => {
          const ground = mark === "-" ? redBg(C) : mark === "+" ? greenBg(C) : "transparent";
          const ink = mark === "-" || mark === "+" ? C.ink : mark === "@" ? C.blue : webMuted(C);
          return (
            <View key={i} style={{ paddingTop: mark === "@" ? 4 : 0 }}>
              <View style={{ backgroundColor: ground }}>
                {(mark === "-" || mark === "+") && (
                  <T size={12} line={18.6} color={mark === "-" ? red(C) : green(C)} style={{ fontFamily: mono, position: "absolute", left: 9, top: 0 }}>{mark}</T>
                )}
                <T size={12} line={18.6} color={ink} weight={mark === "@" ? "500" : undefined} style={{ fontFamily: mono, paddingLeft: 22, paddingRight: 12 }}>{line === "" ? " " : line}</T>
              </View>
            </View>
          );
        })}
      </View>
    </Boxed>
  );
}

/** A patch as apply_patch takes it: file headers, and lines put in and taken out. */
function Patch({ text: patch }: { text: string }) {
  const rows = patch.replace(/\n$/, "").split("\n").flatMap((line): [Mark, string][] => {
    if (/^\*\*\* (Add|Update|Delete) File:|^\*\*\* Move to:|^@@/.test(line)) return [["@", line]];
    if (/^\*\*\* (Begin|End) Patch/.test(line)) return [];
    if (line.startsWith("+")) return [["+", line.substring(1)]];
    if (line.startsWith("-")) return [["-", line.substring(1)]];
    return [[" ", line.startsWith(" ") ? line.substring(1) : line]];
  });
  return <Lines rows={rows} />;
}

/** A list of things to do, as TodoWrite and update_plan give it. */
function Plan({ items }: { items: [string, string][] }) {
  const C = useC();
  const accent = C.accent;
  const greenMark = green(C);
  const subtle = webSubtle(C);
  const muted = webMuted(C);
  return (
    <View style={{ paddingHorizontal: 2, gap: 2 }}>
      {items.map(([words, status], i) => (
        <View key={i} style={{ flexDirection: "row" }}>
          <T size={12} line={18} color={status === "completed" ? greenMark : status === "in_progress" ? accent : subtle} style={{ width: 16 }}>
            {status === "completed" ? "✓" : status === "in_progress" ? "›" : "·"}
          </T>
          <T
            size={12} line={18} color={status === "completed" ? muted : C.ink} weight={status === "in_progress" ? "600" : undefined}
            style={{ flexShrink: 1, textDecorationLine: status === "completed" ? "line-through" : "none" }}
          >
            {words}
          </T>
        </View>
      ))}
    </View>
  );
}

/** Fields one to a row: short ones inline, long text as a block, nested data as compact JSON. */
function Fields({ a, skip = [] }: { a: JsonObject; skip?: string[] }) {
  const C = useC();
  const rows = Object.entries(a).filter(([k, v]) => !skip.includes(k) && v !== null && str(v) !== "");
  if (rows.length === 0) return <None text={t("android-misc.tool.noArgs")} />;
  return (
    <View style={{ paddingHorizontal: 2, gap: 4 }}>
      {rows.map(([k, v]) => {
        const s = str(v);
        return (
          <View key={k} style={{ flexDirection: "row", gap: 12 }}>
            <T size={11} line={18} color={webSubtle(C)} style={{ minWidth: 64, maxWidth: 120 }}>{k}</T>
            <View style={{ flex: 1, minWidth: 0 }}>
              {s != null && (s.includes("\n") || s.length > 120) ? <Boxed max={240}><T size={12} line={19.2} color={C.ink}>{s}</T></Boxed>
                : s != null ? <T size={12} line={18} color={C.ink} style={{ fontFamily: mono }}>{s}</T>
                : v !== null && typeof v === "object" ? <JsonBlock v={v} />
                : <T size={12} line={18} color={C.ink} style={{ fontFamily: mono }}>{text(v as number | boolean)}</T>}
            </View>
          </View>
        );
      })}
    </View>
  );
}

function JsonBlock({ v }: { v: Json }) {
  const C = useC();
  return <Boxed max={240}><T size={12} line={18.6} color={C.ink} style={{ fontFamily: mono }}>{JSON.stringify(v, null, 2)}</T></Boxed>;
}

function None({ text: words }: { text: string }) {
  const C = useC();
  return <T size={11} color={webSubtle(C)} style={{ paddingHorizontal: 2 }}>{words}</T>;
}

/** A step opened: what the call asked for, then what came back. */
export function ToolStepBody({ name, call, said, result, failed }: { name: string; call: string; said: boolean; result: string | null | undefined; failed: boolean }) {
  return (
    <View style={{ alignSelf: "stretch", paddingLeft: 6, paddingRight: 6, paddingTop: 4, paddingBottom: 10, gap: 8 }}>
      <View style={{ gap: 6 }}><ToolCall name={name} call={call} said={said} /></View>
      {result != null && <ToolResult name={name} call={call} result={result} failed={failed} />}
    </View>
  );
}

/** What a call asked for. `said`: its description already shows as the step's name. */
export function ToolCall({ name, call, said }: { name: string; call: string; said: boolean }) {
  const C = useC();
  const parsed = parse(call);
  const a = isObject(parsed) ? parsed : null;
  if (a == null) {
    if (/^\*\*\* Begin Patch/.test(call.trim())) return <Patch text={call.trim()} />;
    if (call.trim() !== "") return <Block text={call} language={name === "exec" ? "js" : null} />;
    return null;
  }
  const skip = said ? ["description"] : [];
  const command = commandOf(a);
  const file = str(a.file_path) ?? str(a.notebook_path) ?? str(a.path);
  const edits = Array.isArray(a.edits) ? a.edits : null;
  const list = Array.isArray(a.todos) ? a.todos : Array.isArray(a.plan) ? a.plan : null;
  const prompt = str(a.prompt);
  const words = str(a.text);
  const queries = Array.isArray(a.queries) && a.queries.length > 0 && a.queries.every((q) => str(q) != null) ? (a.queries as string[]) : null;
  const plain = (s: string) => <T size={12} line={18} color={C.ink} style={{ fontFamily: mono, paddingHorizontal: 2 }}>{s}</T>;
  if (command != null) return <><Block text={command} language="sh" /><Facts a={a} skip={[...skip, "command", "cmd"]} /></>;
  if (file != null && str(a.old_string) != null && str(a.new_string) != null) {
    return <><PathLine path={file} extra={a.replace_all === true ? t("android-misc.tool.replaceAll") : null} /><Diff from={str(a.old_string)!} to={str(a.new_string)!} /></>;
  }
  if (file != null && edits != null) {
    return <><PathLine path={file} />{edits.filter(isObject).map((e, i) => <Diff key={i} from={str(e.old_string) ?? ""} to={str(e.new_string) ?? ""} />)}</>;
  }
  if (file != null && str(a.content) != null) return <><PathLine path={file} /><Block text={str(a.content)!} language={languageOf(file)} /></>;
  if (list != null) {
    const explanation = str(a.explanation);
    return <>{explanation != null && <Prose text={explanation} />}<Plan items={list.filter(isObject).map((x) => [str(x.content) ?? str(x.step) ?? "", str(x.status) ?? ""])} /></>;
  }
  if (prompt != null && (name === "Agent" || name === "Task" || name === "subagent" || prompt.length > 200)) return <><Facts a={a} skip={[...skip, "prompt"]} /><Prose text={prompt} /></>;
  if (words != null && words !== "" && Object.values(a).filter((v) => (str(v)?.length ?? 0) > 120).length <= 1) return <><Facts a={a} skip={[...skip, "text"]} /><Prose text={words} /></>;
  if (file != null && Object.keys(a).every((k) => ["file_path", "path", "notebook_path", "offset", "limit", ...skip].includes(k))) {
    const from = num(a.offset) != null ? Math.trunc(num(a.offset)!) : null;
    const count = num(a.limit) != null ? Math.trunc(num(a.limit)!) : null;
    const range = from != null && count != null ? t("android-misc.tool.linesFrom", { from, n: count })
      : from != null ? t("android-misc.tool.from", { from }) : count != null ? t("android-misc.tool.lines", { n: count }) : null;
    return <PathLine path={file} extra={range} />;
  }
  // DeepSeek Harness's web_search: several queries at once.
  if (queries != null) return <>{queries.map((q, i) => <View key={i}>{plain(q)}</View>)}<Facts a={a} skip={[...skip, "queries"]} /></>;
  if (str(a.pattern) != null || str(a.query) != null || str(a.url) != null) {
    const key = ["pattern", "query", "url"].find((k) => str(a[k]) != null)!;
    return <>{plain(str(a[key])!)}<Fields a={a} skip={[...skip, key]} /></>;
  }
  return <Fields a={a} skip={skip} />;
}

/** Codex's command output: how it ended in a header, then the output. */
function commandOutput(result: string): [string[], string] | null {
  const m = /^(?:Chunk ID: .*\n)?(?:Wall time: (.*)\n)?(?:Process exited with code (-?\d+)\n)?(?:Original token count: .*\n)?Output:\n?/.exec(result);
  if (!m) return null;
  const wall = m[1];
  const code = m[2];
  if (wall == null && code == null) return null;
  return [[...(code != null ? [t("android-misc.tool.exitCode", { code })] : []), ...(wall != null ? [t("android-misc.tool.took", { time: wall })] : [])], result.substring(m[0].length)];
}

/** DeepSeek Harness's bash: its output, then how it ended where that was not well (`[exit code: 1]`). */
function exitMarker(result: string): [string[], string] | null {
  const m = /\n?\[exit code: (-?\d+)\]\s*$/.exec(result);
  if (!m) return null;
  return [[t("android-misc.tool.exitCode", { code: m[1]! })], result.substring(0, m.index)];
}

/** DeepSeek Harness's read and write: the file's path and kind, then what is in it (or what was done), in tags (the end missing where the station cut it short). */
function unwrap(result: string): string | null {
  return /^<path>[^\n]*<\/path>\n<type>[^\n]*<\/type>\n<content>\n?([\s\S]*?)\n?(?:<\/content>\s*)?$/.exec(result)?.[1] ?? null;
}

/** Claude Code's Read: `cat -n` lines (`   12→text` or `   12\ttext`), without their numbers; what follows them is left out. DeepSeek Harness's read numbers them `12: text`. */
function readLines(result: string, numbered: RegExp = /^\s*\d+(→|\t)/): string | null {
  const lines = result.split("\n");
  const first = lines.findIndex((l) => !numbered.test(l));
  const end = first < 0 ? lines.length : first;
  if (end === 0) return null;
  return lines.slice(0, end).map((l) => l.replace(numbered, "")).join("\n");
}

function Output({ text: output, failed }: { text: string; failed: boolean }) {
  const C = useC();
  return (
    <Boxed ground={failed ? redBg(C) : codeGround(C)}>
      <T size={12} line={18.6} color={failed ? C.ink : webMuted(C)} style={{ fontFamily: mono }}>{output}</T>
    </Boxed>
  );
}

/** What a call gave back. */
export function ToolResult({ name, call, result, failed }: { name: string; call: string; result: string; failed: boolean }) {
  if (result.trim() === "") return <None text={t("android-misc.tool.noOutput")} />;
  const parsedCall = parse(call);
  const args = isObject(parsedCall) ? parsedCall : null;
  const file = args ? str(args.file_path) ?? str(args.path) : null;
  const codex = commandOutput(result) ?? (name === "bash" ? exitMarker(result) : null);
  const read = !failed && (name === "Read" || name === "NotebookRead") ? readLines(result) : null;
  const inner = !failed && codex == null && read == null && (name === "read" || name === "write") ? unwrap(result) : null;
  const innerLines = inner != null && name === "read" ? readLines(inner, /^\d+: ?/) : null;
  const parsed = failed || codex != null || read != null || inner != null ? null : parse(result);
  let body: ReactNode;
  if (codex != null) {
    body = <>
      {codex[0].length > 0 && <FactRow facts={codex[0].map((f) => [f, null])} />}
      {codex[1].trim() !== "" ? <Output text={codex[1]} failed={failed} /> : <None text={t("android-misc.tool.noOutput")} />}
    </>;
  } else if (read != null) body = <Block text={read} language={languageOf(file)} />;
  else if (innerLines != null) body = <Block text={innerLines} language={languageOf(file)} />;
  else if (inner != null) body = <Output text={inner} failed={false} />;
  else if (isObject(parsed)) body = <Fields a={parsed} />;
  else if (parsed != null) body = <JsonBlock v={parsed} />;
  else body = <Output text={result} failed={failed} />;
  return <View style={{ alignSelf: "stretch", gap: 4 }}>{body}</View>;
}
