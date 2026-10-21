// Code coloured once, here, for every client, as Markdown is read here (markdown.ts): a code block comes to the clients
// with its `ink`, what each piece of it is (a comment, a string, a keyword…), and each client only paints those in its
// theme's colours. The colours are Shiki's vitesse-light and vitesse-dark, as the web drew code before; the
// tokenizer is the light one the Android app had (ui/Highlight.kt), not a grammar per language as Shiki has: it knows
// how the common languages write comments, strings and numbers and, per language family, which words vitesse draws as
// control words (green), which as declarations and operators (red), and whether plain names are variables (brown) or
// plain text, token for token as Shiki gives them (checked against `codeToTokens` on samples of each family).
//
// `ink` is short, as it goes to the UIs beside the code: runs one after another from the code's start, each a scope's
// letter (`SCOPES`) and its length in UTF-16 units (none for 1); what is after the last run is text. Spaces and line
// ends have no colour of their own (none shows), so they go with the run before them and never split one: `const x = 1`
// is `h6j2c2f`. About a third as long as the code.

/// What a piece of code is, by the letter `ink` writes for it; a client keeps a colour for each, light and dark.
export const SCOPES = {
  text: "a",
  comment: "b",
  punct: "c",
  string: "d",
  /// a string's quotes
  quote: "e",
  number: "f",
  /// keyword, keyword.control, constant.language (true, None), entity.name.tag
  control: "g",
  /// storage (function, const, class), keyword.operator, null, undefined
  storage: "h",
  func: "i",
  variable: "j",
  /// constant, variable.language (this, self), an option (-x)
  constant: "k",
  type: "l",
  /// property names, support (builtins as print, echo)
  property: "m",
  propertyQuote: "n",
  /// a diff's lines added and removed, a hunk's range (Shiki's own diff colours)
  added: "o",
  removed: "p",
  range: "q",
} as const;

/// Code longer than this (UTF-16 units) is not coloured: it shows as it is.
export const INK_LIMIT = 256 * 1024;

const TEXT = 0, COMMENT = 1, PUNCT = 2, STRING = 3, QUOTE = 4, NUMBER = 5, CONTROL = 6, STORAGE = 7, FUNC = 8, VARIABLE = 9,
  CONSTANT = 10, TYPE = 11, PROPERTY = 12, PROPERTY_QUOTE = 13, ADDED = 14, REMOVED = 15, RANGE = 16;
const LETTERS = "abcdefghijklmnopq";

/// How a family of languages is written and coloured.
type Lang = {
  control: Set<string>;
  storage: Set<string>;
  /// constant.language drawn green (true, false, None)
  green: Set<string>;
  /// constant.language drawn red (null, undefined in TypeScript)
  red: Set<string>;
  builtins: Set<string>;
  types: Set<string>;
  /// Plain names are variables (brown), as TypeScript, Rust and Go have them; else plain text.
  variables: boolean;
  /// Brackets, commas and colons in the text colour (Kotlin's grammar leaves them unscoped); else grey.
  plainPunct: boolean;
  /// Quotes in the string's colour, not the fainter one.
  solidQuotes: boolean;
  hash: boolean;
  slash: boolean;
  dashDash: boolean;
  caseless: boolean;
};

const words = (s: string) => new Set(s.split(" "));

function lang(control: string, storage: string, more: Partial<Omit<Lang, "control" | "storage">> = {}): Lang {
  return {
    control: words(control),
    storage: words(storage),
    green: words("true false"),
    red: new Set(),
    builtins: new Set(),
    types: new Set(),
    variables: false,
    plainPunct: false,
    solidQuotes: false,
    hash: false,
    slash: true,
    dashDash: false,
    caseless: false,
    ...more,
  };
}

const TS = lang(
  "if else for while do return break continue switch case default import from export as try catch finally throw await yield of with debugger",
  "function const let var class interface enum type namespace declare abstract async static public private protected readonly extends implements new delete typeof instanceof in keyof void get set override satisfies",
  { red: words("null undefined"), types: words("string number boolean any unknown never object bigint symbol"), variables: true },
);
const PYTHON = lang(
  "if elif else for while return break continue import from as try except finally raise with yield await pass assert match case del global nonlocal",
  "def class lambda async and or not in is",
  {
    green: words("True False None"),
    builtins: words("print len range str int float dict list set tuple open isinstance super sorted enumerate zip map filter min max sum any all type repr bool input abs round getattr setattr hasattr"),
    hash: true,
    slash: false,
  },
);
const KOTLIN = lang(
  "if else for while do return break continue when try catch finally throw package import as is in fun val var class object interface typealias true false this super where by constructor init",
  "override private public protected internal open abstract final data sealed enum inline suspend lateinit const companion operator infix tailrec external annotation inner vararg reified crossinline noinline",
  { red: words("null"), plainPunct: true, solidQuotes: true },
);
const RUST = lang(
  "if else for while loop return break continue match use mod fn impl pub crate as in where async await move unsafe extern trait type dyn",
  "let mut struct enum const static ref",
  { types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str"), variables: true },
);
const GO = lang(
  "if else for range return break continue switch case default package import func var const type struct interface map chan go defer select fallthrough goto",
  "string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 bool byte rune error any",
  { red: words("nil"), variables: true },
);
const C_LIKE = lang(
  "if else for while do return break continue switch case default import package try catch finally throw throws using namespace include define goto yield await guard defer func fun fn def",
  "class struct enum interface const static public private protected final abstract virtual override extends implements new delete void int long short char float double bool boolean unsigned signed auto let var val typedef extern inline volatile sizeof instanceof async",
  { red: words("null nil nullptr NULL") },
);
const SHELL = lang(
  "if then else elif fi for while until do done case esac in function return exit select",
  "export local declare readonly unset alias",
  {
    builtins: words("echo cd printf read source set shift eval exec test trap wait kill pwd type ulimit umask true false"),
    green: new Set(),
    hash: true,
    slash: false,
  },
);
const SQL = lang(
  "select from where and or not insert into values update set delete create table drop alter add join left right inner outer on group by order having limit offset as distinct union all in is like between exists case when then else end primary key index unique default references foreign asc desc with returning view if begin commit rollback",
  "",
  {
    green: words("true false null"),
    builtins: words("count sum avg min max coalesce length lower upper substr replace json_extract now date cast ifnull round"),
    slash: false,
    dashDash: true,
    caseless: true,
  },
);
const DATA_GREEN = words("true false null yes no on off True False Null NULL ~");

function langOf(language: string): Lang {
  switch (language) {
    case "ts": case "tsx": case "typescript": case "js": case "jsx": case "javascript": case "mjs": case "cjs": case "mts": case "cts": case "vue": case "svelte":
      return TS;
    case "py": case "python": case "python3":
      return PYTHON;
    case "kt": case "kts": case "kotlin":
      return KOTLIN;
    case "rs": case "rust":
      return RUST;
    case "go": case "golang":
      return GO;
    case "sh": case "bash": case "zsh": case "shell": case "console": case "shellscript": case "fish":
      return SHELL;
    case "sql": case "sqlite": case "postgres": case "postgresql": case "mysql":
      return SQL;
    default:
      return C_LIKE;
  }
}

/// The `ink` of `code` in `language` (a Markdown block's or a file's, as named: `ts`, `python`, `json`…), or null for
/// code shown as it is: a language of plain text (or none), Markdown, or code past `INK_LIMIT`.
export function ink(code: string, language: string | null | undefined): string | null {
  const name = (language ?? "").trim().toLowerCase();
  if (name === "" || name === "text" || name === "plain" || name === "txt" || name === "plaintext" || name === "markdown" || name === "md") return null;
  if (code.length === 0 || code.length > INK_LIMIT) return null;
  const s = new Uint8Array(code.length);
  switch (name) {
    case "json": case "jsonc": case "json5": data(code, s, true); break;
    case "yaml": case "yml": yaml(code, s); break;
    case "toml": case "ini": case "conf": data(code, s, false); break;
    case "html": case "htm": case "xml": case "svg": markup(code, s); break;
    case "css": case "scss": case "less": css(code, s); break;
    case "diff": case "patch": diff(code, s); break;
    default: {
      const l = langOf(name);
      program(code, s, l, l === SHELL);
    }
  }
  return encode(code, s);
}

/// `ink`, kept for the latest code asked of (up to `KEPT_CHARS` of it): a client asks of a block each time it draws it
/// anew, the same block in light and dark, in a message and in its preview.
export function inkKept(code: string, language: string): string | null {
  const key = `${language}\n${code}`;
  if (kept.has(key)) {
    const hit = kept.get(key)!;
    kept.delete(key);
    kept.set(key, hit);
    return hit;
  }
  const made = ink(code, language);
  kept.set(key, made);
  keptChars += key.length;
  for (const [old] of kept) {
    if (keptChars <= KEPT_CHARS || kept.size <= 1) break;
    kept.delete(old);
    keptChars -= old.length;
  }
  return made;
}

const KEPT_CHARS = 2_000_000;
const kept = new Map<string, string | null>();
let keptChars = 0;

/// The runs of `s`, each piece's scope, as `ink` writes them.
function encode(code: string, s: Uint8Array): string | null {
  let out = "";
  let scope = -1;
  let start = 0;
  let coloured = false;
  const run = (end: number) => {
    out += LETTERS[scope];
    if (end - start !== 1) out += end - start;
  };
  for (let i = 0; i < code.length; i++) {
    if (space(code.charCodeAt(i)) || s[i] === scope) continue;
    if (s[i] !== TEXT) coloured = true;
    if (scope < 0) scope = s[i]!;
    else {
      run(i);
      scope = s[i]!;
      start = i;
    }
  }
  // All of it text: nothing to paint.
  if (!coloured) return null;
  // Text to the end goes without saying.
  if (scope !== TEXT) run(code.length);
  return out;
}

/// What `ink` says of `code`: its pieces and their scopes' letters, from its start (what a client paints).
export function runsOf(code: string, ink: string): [text: string, scope: string][] {
  const runs: [string, string][] = [];
  let at = 0;
  for (const [, letter, length] of ink.matchAll(/([a-z])(\d*)/g)) {
    const end = Math.min(code.length, at + (length ? Number(length) : 1));
    runs.push([code.slice(at, end), letter!]);
    at = end;
  }
  if (at < code.length) runs.push([code.slice(at), SCOPES.text]);
  return runs;
}

/// `ink` for the code's first `length` units alone (a block cut to its first lines): its runs up to there.
export function inkUpTo(ink: string, length: number): string | null {
  let at = 0;
  let out = "";
  for (const [, letter, n] of ink.matchAll(/([a-z])(\d*)/g)) {
    if (at >= length) break;
    const run = Math.min(n ? Number(n) : 1, length - at);
    out += run === 1 ? letter : letter! + run;
    at += run;
  }
  return out === "" ? null : out;
}

// ── reading the code ───────────────────────────────────────────────────

const space = (c: number) => c === 32 || c === 9 || c === 10 || c === 13;
const blank = (c: number) => space(c) || c === 11 || c === 12;
const digit = (c: number) => c >= 48 && c <= 57;
const letter = (c: number) => (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c > 127;
const upper = (c: number) => c >= 65 && c <= 90;
const letterOrDigit = (c: number) => letter(c) || digit(c);

function put(s: Uint8Array, from: number, until: number, scope: number): void {
  if (until > from) s.fill(scope, from, until);
}

function lineEnd(code: string, i: number): number {
  const e = code.indexOf("\n", i);
  return e < 0 ? code.length : e;
}

/// The next character that is not a space or tab, from `j` (-1 at the end).
function next(code: string, j: number): number {
  while (j < code.length && (code.charCodeAt(j) === 32 || code.charCodeAt(j) === 9)) j++;
  return j < code.length ? code.charCodeAt(j) : -1;
}

/// The last character before `j` that is not a space or tab (-1 at the start).
function before(code: string, j: number): number {
  let k = j - 1;
  while (k >= 0 && (code.charCodeAt(k) === 32 || code.charCodeAt(k) === 9)) k--;
  return k >= 0 ? code.charCodeAt(k) : -1;
}

const NUMBER_AT = /0x[0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?/y;
const NUMBER_WHOLE = /^(?:0x[0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)$/;
const WORD_AT = /[A-Za-z_$][A-Za-z0-9_$]*!?/y;

/// Where a number starting at `i` ends, or -1.
function numberAt(code: string, i: number): number {
  NUMBER_AT.lastIndex = i;
  const m = NUMBER_AT.exec(code);
  return m ? i + m[0].length : -1;
}

/// A string from its opening quote at `i`: the quotes fainter than what is between (or `quote` as the string), `${…}`
/// and `{…}` left in it. Where it ends.
function string(code: string, s: Uint8Array, i: number, color = STRING, quote = QUOTE): number {
  const n = code.length;
  const q = code[i]!;
  const triple = code.startsWith(q + q + q, i);
  const open = triple ? 3 : 1;
  let j = i + open;
  while (j < n) {
    if (code[j] === "\\") { j += 2; continue; }
    if (triple && code.startsWith(q + q + q, j)) break;
    if (!triple && code[j] === q) break;
    if (code[j] === "\n" && q !== "`" && !triple) break;
    j++;
  }
  const end = Math.min(n, j);
  const close = end < n && code[end] !== "\n" ? open : 0;
  put(s, i, i + open, quote);
  put(s, i + open, end, color);
  put(s, end, Math.min(n, end + close), quote);
  return Math.min(n, end + close);
}

const OPERATORS = "+-*/%!&|^~?<>=";
const PUNCTS = "{}[]();,.:";
const FN_WORDS = words("function def fun fn func");
const TYPE_WORDS = words("class interface type struct enum trait impl object typealias");
const NEW_WORDS = words("new extends implements");

function program(code: string, s: Uint8Array, l: Lang, shell: boolean): void {
  const n = code.length;
  let i = 0;
  // Open brackets: a name and a colon inside braces is a key, inside parentheses a parameter.
  const brackets: string[] = [];
  let previousWord = "";
  // In a shell: at a command's first word (the start of a line, after | ; && then do).
  let command = true;
  let afterColon = false;
  while (i < n) {
    const c = code[i]!;
    const cc = code.charCodeAt(i);
    if (c === "\n") {
      i++;
      if (shell) command = true;
      afterColon = false;
    } else if (c === " " || c === "\t" || c === "\r") i++;
    else if (l.hash && c === "#" && (i === 0 || blank(code.charCodeAt(i - 1)))) {
      const e = lineEnd(code, i);
      put(s, i, e, COMMENT);
      i = e;
    } else if (l.slash && code.startsWith("//", i)) {
      const e = lineEnd(code, i);
      put(s, i, e, COMMENT);
      i = e;
    } else if (l.slash && code.startsWith("/*", i)) {
      const close = code.indexOf("*/", i + 2);
      const e = close < 0 ? n : close + 2;
      put(s, i, e, COMMENT);
      i = e;
    } else if (l.dashDash && code.startsWith("--", i)) {
      const e = lineEnd(code, i);
      put(s, i, e, COMMENT);
      i = e;
    } else if (c === '"' || c === "'" || c === "`") {
      i = l.solidQuotes ? string(code, s, i, STRING, STRING) : string(code, s, i);
      if (shell) command = false;
    } else if (shell && c === "$" && i + 1 < n && (letter(code.charCodeAt(i + 1)) || code[i + 1] === "_" || code[i + 1] === "{")) {
      let j = i + 1;
      if (code[j] === "{") {
        const close = code.indexOf("}", j);
        j = close < 0 ? n : close + 1;
      } else while (j < n && (letterOrDigit(code.charCodeAt(j)) || code[j] === "_")) j++;
      put(s, i, j, VARIABLE);
      i = j;
      command = false;
    } else if (shell && c === "-" && (i === 0 || blank(code.charCodeAt(i - 1))) && i + 1 < n && (letter(code.charCodeAt(i + 1)) || code[i + 1] === "-")) {
      let j = i + 1;
      while (j < n && !blank(code.charCodeAt(j)) && !";|&)=".includes(code[j]!)) j++;
      put(s, i, j, CONSTANT);
      i = j;
    } else if (shell && !command && !blank(cc) && !";|&<>()[]".includes(c) && !code.startsWith("\\\n", i)) {
      // An argument: Shiki's shell grammar draws words after the command as strings.
      let j = i;
      while (j < n && !blank(code.charCodeAt(j)) && !";|&<>()[]\"'`$".includes(code[j]!)) j++;
      if (j === i) j = i + 1;
      put(s, i, j, /^\d+$/.test(code.slice(i, j)) ? NUMBER : STRING);
      i = j;
    } else if (digit(cc) && (i === 0 || (!letterOrDigit(code.charCodeAt(i - 1)) && code[i - 1] !== "_"))) {
      const e = numberAt(code, i);
      if (e > 0) {
        put(s, i, e, NUMBER);
        i = e;
      } else i++;
    } else if (letter(cc) || c === "_" || (c === "$" && !shell) || (shell && command && (c === "." || c === "/" || c === "~"))) {
      let end: number;
      if (shell && command) {
        end = i;
        while (end < n && !blank(code.charCodeAt(end)) && !";|&<>()=\"'`".includes(code[end]!)) end++;
      } else {
        WORD_AT.lastIndex = i;
        const m = WORD_AT.exec(code);
        end = m ? i + m[0].length : i + 1;
      }
      // A name with the macro's bang (Rust's println!) only where the language has them.
      if (l !== RUST && end > i && code[end - 1] === "!") end--;
      const word = code.slice(i, end);
      const key = l.caseless ? word.toLowerCase() : word;
      const nextChar = next(code, end);
      const prev = before(code, i);
      const first = word.charCodeAt(0);
      let color: number;
      if (shell && command && end < n && code[end] === "=") {
        color = VARIABLE;
        command = true;
      } else if (shell && command) {
        if (l.control.has(key)) color = CONTROL;
        else if (l.storage.has(key)) { color = STORAGE; command = false; }
        else if (l.builtins.has(key)) { color = PROPERTY; command = false; }
        else { color = FUNC; command = false; }
      } else if (shell && prev === 61) color = VARIABLE;
      else if (l.control.has(key)) color = CONTROL;
      else if (l.storage.has(key)) color = STORAGE;
      else if (l.green.has(key)) color = CONTROL;
      else if (l.red.has(key)) color = STORAGE;
      else if (word === "this" || word === "self" || word === "Self") color = CONSTANT;
      else if (FN_WORDS.has(previousWord)) color = FUNC;
      else if (TYPE_WORDS.has(previousWord)) color = TYPE;
      else if (NEW_WORDS.has(previousWord)) color = FUNC;
      else if (nextChar === 40 || (l === RUST && word.endsWith("!"))) color = l.builtins.has(key) ? PROPERTY : FUNC;
      else if (l.types.has(key)) color = TYPE;
      else if (afterColon && l !== PYTHON && upper(first)) color = TYPE;
      else if (l === KOTLIN && upper(first)) color = TYPE;
      else if (l === TS && upper(first) && nextChar === 60) color = TYPE;
      else if (l === RUST && upper(first)) color = TYPE;
      else if (l === RUST && nextChar === 58 && code.startsWith("::", end)) color = FUNC;
      else if (l === TS && nextChar === 58 && brackets[brackets.length - 1] === "{" && prev !== 63) color = PROPERTY;
      else if (l.variables) color = VARIABLE;
      else color = TEXT;
      put(s, i, end, color);
      previousWord = key;
      afterColon = false;
      i = end;
    } else if (c === "(" || c === "[" || c === "{") {
      brackets.push(c);
      put(s, i, i + 1, l.plainPunct ? TEXT : PUNCT);
      i++;
      if (shell) command = true;
    } else if (c === ")" || c === "]" || c === "}") {
      brackets.pop();
      put(s, i, i + 1, l.plainPunct ? TEXT : PUNCT);
      i++;
    } else if (OPERATORS.includes(c) || c === ":") {
      let j = i;
      while (j < n && (OPERATORS.includes(code[j]!) || code[j] === ":")) j++;
      const op = code.slice(i, j);
      const spaced = (i === 0 || blank(code.charCodeAt(i - 1))) && (j >= n || blank(code.charCodeAt(j)));
      let color: number;
      if (shell) color = op === "|" || op === "||" || op === ">" || op === ">>" || op === "<" ? STORAGE : PUNCT;
      else if (op === "=" || op === ":=" || op === "=>") color = PUNCT;
      else if (op === ":") color = l === RUST ? STORAGE : l.plainPunct ? TEXT : PUNCT;
      else if (op === "::" || op === "->") color = l === RUST ? STORAGE : PUNCT;
      else if ((op === "<" || op === ">") && !spaced) color = l.plainPunct ? TEXT : PUNCT;
      else if (op === "?" && l.plainPunct) color = TEXT;
      else color = STORAGE;
      put(s, i, j, color);
      afterColon = op === ":" || op === "?:" || op === "->" || op === "):";
      if (shell && (op === "|" || op === "||" || op === "&&" || op === "&")) command = true;
      i = j;
    } else if (PUNCTS.includes(c)) {
      put(s, i, i + 1, l.plainPunct ? TEXT : PUNCT);
      i++;
      if (shell && c === ";") command = true;
      if (c === ",") afterColon = false;
    } else i++;
  }
}

/// JSON (keys in the property colour, their quotes fainter) and TOML/INI (`key = value`).
function data(code: string, s: Uint8Array, json: boolean): void {
  const n = code.length;
  let i = 0;
  while (i < n) {
    const c = code[i]!;
    const cc = code.charCodeAt(i);
    if (!json && c === "#") {
      const e = lineEnd(code, i);
      put(s, i, e, COMMENT);
      i = e;
    } else if (json && code.startsWith("//", i)) {
      const e = lineEnd(code, i);
      put(s, i, e, COMMENT);
      i = e;
    } else if (c === '"' || c === "'") {
      // A key: the string before a colon (JSON).
      let j = i + 1;
      while (j < n && code[j] !== c && code[j] !== "\n") j += code[j] === "\\" ? 2 : 1;
      const key = json && next(code, j + 1) === 58;
      i = key ? string(code, s, i, PROPERTY, PROPERTY_QUOTE) : string(code, s, i);
    } else if (c === "-" || digit(cc)) {
      const e = numberAt(code, c === "-" ? i + 1 : i);
      if (e > 0) {
        put(s, i, e, NUMBER);
        i = e;
      } else {
        put(s, i, i + 1, PUNCT);
        i++;
      }
    } else if (letter(cc) || c === "_") {
      let j = i;
      while (j < n && (letterOrDigit(code.charCodeAt(j)) || "_-.".includes(code[j]!))) j++;
      const word = code.slice(i, j);
      put(s, i, j, DATA_GREEN.has(word) ? CONTROL : !json && next(code, j) === 61 ? PROPERTY : TEXT);
      i = j;
    } else if ("{}[],:=".includes(c)) {
      put(s, i, i + 1, PUNCT);
      i++;
    } else i++;
  }
}

const YAML_MARKS = words("| > |- >- [] {}");
const YAML_KEY = /^[^#'"]*?:(\s|$)/;

/// YAML: keys in the property colour; plain values are strings to Shiki.
function yaml(code: string, s: Uint8Array): void {
  const n = code.length;
  let i = 0;
  while (i < n) {
    const e = lineEnd(code, i);
    let j = i;
    while (j < e && (code[j] === " " || code[j] === "\t")) j++;
    if (j < e && code[j] === "-" && (j + 1 === e || code[j + 1] === " ")) {
      put(s, j, j + 1, PUNCT);
      j++;
      while (j < e && code[j] === " ") j++;
    }
    if (j < e && code[j] === "#") {
      put(s, j, e, COMMENT);
      j = e;
    }
    const colon = YAML_KEY.exec(code.slice(j, e));
    if (colon) {
      const k = j + colon[0].trimEnd().length - 1;
      put(s, j, k, PROPERTY);
      put(s, k, k + 1, PUNCT);
      j = k + 1;
    }
    while (j < e) {
      const c = code[j]!;
      if (c === " ") j++;
      else if (c === "#" && code[j - 1] === " ") {
        put(s, j, e, COMMENT);
        j = e;
      } else if (c === '"' || c === "'") j = Math.min(e, string(code, s, j));
      else {
        const hash = code.indexOf(" #", j);
        const hashAt = hash < 0 || hash > e ? e : hash;
        const value = code.slice(j, hashAt).trimEnd();
        put(s, j, j + value.length, DATA_GREEN.has(value) ? CONTROL : NUMBER_WHOLE.test(value) ? NUMBER : YAML_MARKS.has(value) ? PUNCT : STRING);
        j += value.length;
        // Only spaces after it before the comment, or a lone carriage return: plain.
        if (value.length === 0) j++;
      }
    }
    i = e + 1;
  }
}

/// HTML and XML: tags green, attribute names brown, values strings, the brackets grey.
function markup(code: string, s: Uint8Array): void {
  const n = code.length;
  let i = 0;
  while (i < n) {
    if (code.startsWith("<!--", i)) {
      const close = code.indexOf("-->", i);
      const e = close < 0 ? n : close + 3;
      put(s, i, e, COMMENT);
      i = e;
    } else if (code[i] === "<") {
      let j = i + 1;
      if (j < n && (code[j] === "/" || code[j] === "!" || code[j] === "?")) j++;
      put(s, i, j, PUNCT);
      let k = j;
      while (k < n && (letterOrDigit(code.charCodeAt(k)) || "-_:.".includes(code[k]!))) k++;
      put(s, j, k, CONTROL);
      i = k;
      while (i < n && code[i] !== ">") {
        const c = code[i]!;
        if (c === '"' || c === "'") i = string(code, s, i);
        else if (c === "=" || c === "/" || c === "?") {
          put(s, i, i + 1, PUNCT);
          i++;
        } else if (blank(code.charCodeAt(i))) i++;
        else {
          let e = i;
          while (e < n && !blank(code.charCodeAt(e)) && !"=>/\"'".includes(code[e]!)) e++;
          if (e === i) e = i + 1;
          put(s, i, e, i > 0 && code[i - 1] === "=" ? STRING : VARIABLE);
          i = e;
        }
      }
      if (i < n) {
        put(s, i, i + 1, PUNCT);
        i++;
      }
    } else {
      const lt = code.indexOf("<", i);
      i = lt < 0 ? n : lt;
    }
  }
}

/// CSS: selectors (classes brown, elements green), properties, numbers with their units red, colours as constants.
function css(code: string, s: Uint8Array): void {
  const n = code.length;
  let i = 0;
  let depth = 0;
  while (i < n) {
    const c = code[i]!;
    const cc = code.charCodeAt(i);
    // Inside a rule's braces, and not in a nested selector (a word followed by `{`).
    const inBlock = depth > 0 && (() => {
      for (let k = i; k < n; k++) {
        const x = code[k];
        if (x === ";" || x === "}") return true;
        if (x === "{") return false;
      }
      return true;
    })();
    if (code.startsWith("/*", i)) {
      const close = code.indexOf("*/", i + 2);
      const e = close < 0 ? n : close + 2;
      put(s, i, e, COMMENT);
      i = e;
    } else if (c === '"' || c === "'") i = string(code, s, i);
    else if (c === "{") {
      depth++;
      put(s, i, i + 1, PUNCT);
      i++;
    } else if (c === "}") {
      depth = Math.max(0, depth - 1);
      put(s, i, i + 1, PUNCT);
      i++;
    } else if (c === "#" && inBlock) {
      let j = i + 1;
      while (j < n && letterOrDigit(code.charCodeAt(j))) j++;
      put(s, i, i + 1, PUNCT);
      put(s, i + 1, j, CONSTANT);
      i = j;
    } else if ((digit(cc) || (c === "." && i + 1 < n && digit(code.charCodeAt(i + 1)))) && inBlock) {
      let j = i;
      while (j < n && (digit(code.charCodeAt(j)) || code[j] === ".")) j++;
      let u = j;
      while (u < n && (letter(code.charCodeAt(u)) || code[u] === "%")) u++;
      put(s, i, j, NUMBER);
      put(s, j, u, STORAGE);
      i = u;
    } else if (letter(cc) || c === "-" || c === "_") {
      let j = i;
      while (j < n && (letterOrDigit(code.charCodeAt(j)) || code[j] === "-" || code[j] === "_")) j++;
      const word = code.slice(i, j);
      let color: number;
      if (inBlock && next(code, j) === 58) color = word.startsWith("--") ? VARIABLE : PROPERTY;
      else if (inBlock) color = TEXT;
      else if (i > 0 && (code[i - 1] === "." || code[i - 1] === ":" || code[i - 1] === "#")) color = VARIABLE;
      else color = CONTROL;
      put(s, i, j, color);
      i = j;
    } else if (c === ">" || c === "+" || c === "~") {
      put(s, i, i + 1, depth === 0 || !inBlock ? STORAGE : PUNCT);
      i++;
    } else if (".:;,()@#*[]".includes(c)) {
      put(s, i, i + 1, PUNCT);
      i++;
    } else i++;
  }
}

/// A diff as Shiki colours one: removed lines red, added green (their `---`/`+++` marks grey), a hunk's range purple
/// between grey `@@`.
function diff(code: string, s: Uint8Array): void {
  let i = 0;
  while (i < code.length) {
    const e = lineEnd(code, i);
    if (code.startsWith("+++", i) || code.startsWith("---", i)) {
      put(s, i, i + 3, PUNCT);
      put(s, i + 3, e, code[i] === "+" ? ADDED : REMOVED);
    } else if (code.startsWith("@@", i)) {
      const close = code.indexOf("@@", i + 2);
      put(s, i, i + 2, PUNCT);
      if (close < 0 || close >= e) put(s, i + 2, e, RANGE);
      else {
        put(s, i + 2, close, RANGE);
        put(s, close, close + 2, PUNCT);
      }
    } else if (code.startsWith("+", i)) put(s, i, e, ADDED);
    else if (code.startsWith("-", i)) put(s, i, e, REMOVED);
    i = e + 1;
  }
}
