// Code blocks coloured as the web colours them: Shiki with its dual themes, vitesse-light and vitesse-dark
// (web/src/Prose.tsx). Not a grammar per language as Shiki has, but a light tokenizer that knows how the common
// languages write comments, strings and numbers, and, per language family, which words vitesse draws as control words
// (green), which as declarations and operators (red), and whether plain names are variables (brown) or plain text; the
// colours below are the theme's, token for token as Shiki gives them (checked against `codeToTokens` on samples of each
// family). Dark takes each light colour's vitesse-dark twin ([DARK], the pairs Shiki gives the same tokens).
// (The Android app's ui/Highlight.kt, ported as it is.)
import { AnnotatedString, AnnotatedStringBuilder } from "./Annotated";

/** vitesse-light's colours (its tokenColors), by what they colour. */
const V = {
  text: "#393A34",
  comment: "#A0ADA0",
  punct: "#999999",
  string: "#B56959",
  quote: "#B5695977",
  number: "#2F798A",
  /** keyword, keyword.control, constant.language (true, None), entity.name.tag */
  control: "#1E754F",
  /** storage (function, const, class), keyword.operator, null, undefined */
  storage: "#AB5959",
  function: "#59873A",
  variable: "#B07D48",
  /** constant, variable.language (this, self), an option (-x) */
  constant: "#A65E2B",
  type: "#2E8F82",
  /** property names, support (builtins as print, echo) */
  property: "#998418",
  propertyQuote: "#99841877",
  /** a diff's lines added and removed, a hunk's range (Shiki's own diff colours) */
  added: "#22863A",
  removed: "#B31D28",
  range: "#6F42C1",
} as const;

type Color = string;

/** vitesse-dark's colour for each of vitesse-light's (Shiki's `--shiki-dark` beside the light colour, same token). */
const DARK: Record<string, Color> = {
  [V.text]: "#DBD7CAEE", [V.comment]: "#758575DD", [V.punct]: "#666666",
  [V.string]: "#C98A7D", [V.quote]: "#C98A7D77", [V.number]: "#4C9A91",
  [V.control]: "#4D9375", [V.storage]: "#CB7676", [V.function]: "#80A665",
  [V.variable]: "#BD976A", [V.constant]: "#C99076", [V.type]: "#5DA994",
  [V.property]: "#B8A965", [V.propertyQuote]: "#B8A96577",
  [V.added]: "#85E89D", [V.removed]: "#FDAEB7", [V.range]: "#B392F0",
};

/** How a family of languages is written and coloured. */
interface Lang {
  control: ReadonlySet<string>;
  storage: ReadonlySet<string>;
  /** constant.language drawn green (true, false, None). */
  green: ReadonlySet<string>;
  /** constant.language drawn red (null, undefined in TypeScript). */
  red: ReadonlySet<string>;
  builtins: ReadonlySet<string>;
  types: ReadonlySet<string>;
  /** Plain names are variables (brown), as TypeScript, Rust and Go have them; else plain text. */
  variables: boolean;
  /** Brackets, commas and colons in the text colour (Kotlin's grammar leaves them unscoped); else grey. */
  plainPunct: boolean;
  /** Quotes in the string's colour, not the fainter one. */
  solidQuotes: boolean;
  hash: boolean;
  slash: boolean;
  dashDash: boolean;
  caseless: boolean;
}

const set = (...words: string[]): ReadonlySet<string> => new Set(words);

function lang(l: Partial<Lang> & { control: ReadonlySet<string>; storage: ReadonlySet<string> }): Lang {
  return {
    green: set("true", "false"), red: set(), builtins: set(), types: set(), variables: false, plainPunct: false,
    solidQuotes: false, hash: false, slash: true, dashDash: false, caseless: false, ...l,
  };
}

const TS = lang({
  control: set("if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default", "import", "from", "export",
    "as", "try", "catch", "finally", "throw", "await", "yield", "of", "with", "debugger"),
  storage: set("function", "const", "let", "var", "class", "interface", "enum", "type", "namespace", "declare", "abstract", "async",
    "static", "public", "private", "protected", "readonly", "extends", "implements", "new", "delete", "typeof", "instanceof", "in",
    "keyof", "void", "get", "set", "override", "satisfies"),
  red: set("null", "undefined"),
  types: set("string", "number", "boolean", "any", "unknown", "never", "object", "bigint", "symbol"),
  variables: true,
});
const PYTHON = lang({
  control: set("if", "elif", "else", "for", "while", "return", "break", "continue", "import", "from", "as", "try", "except", "finally",
    "raise", "with", "yield", "await", "pass", "assert", "match", "case", "del", "global", "nonlocal"),
  storage: set("def", "class", "lambda", "async", "and", "or", "not", "in", "is"),
  green: set("True", "False", "None"),
  builtins: set("print", "len", "range", "str", "int", "float", "dict", "list", "set", "tuple", "open", "isinstance", "super", "sorted",
    "enumerate", "zip", "map", "filter", "min", "max", "sum", "any", "all", "type", "repr", "bool", "input", "abs", "round", "getattr", "setattr", "hasattr"),
  hash: true, slash: false,
});
const KOTLIN = lang({
  control: set("if", "else", "for", "while", "do", "return", "break", "continue", "when", "try", "catch", "finally", "throw", "package",
    "import", "as", "is", "in", "fun", "val", "var", "class", "object", "interface", "typealias", "true", "false", "this", "super", "where", "by", "constructor", "init"),
  storage: set("override", "private", "public", "protected", "internal", "open", "abstract", "final", "data", "sealed", "enum", "inline",
    "suspend", "lateinit", "const", "companion", "operator", "infix", "tailrec", "external", "annotation", "inner", "vararg", "reified", "crossinline", "noinline"),
  red: set("null"),
  plainPunct: true, solidQuotes: true,
});
const RUST = lang({
  control: set("if", "else", "for", "while", "loop", "return", "break", "continue", "match", "use", "mod", "fn", "impl", "pub", "crate",
    "as", "in", "where", "async", "await", "move", "unsafe", "extern", "trait", "type", "dyn"),
  storage: set("let", "mut", "struct", "enum", "const", "static", "ref"),
  types: set("i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str"),
  variables: true,
});
const GO = lang({
  control: set("if", "else", "for", "range", "return", "break", "continue", "switch", "case", "default", "package", "import", "func",
    "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "select", "fallthrough", "goto"),
  storage: set("string", "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float32", "float64",
    "bool", "byte", "rune", "error", "any"),
  red: set("nil"),
  variables: true,
});
const C_LIKE = lang({
  control: set("if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default", "import", "package",
    "try", "catch", "finally", "throw", "throws", "using", "namespace", "include", "define", "goto", "yield", "await", "guard", "defer", "func", "fun", "fn", "def"),
  storage: set("class", "struct", "enum", "interface", "const", "static", "public", "private", "protected", "final", "abstract", "virtual",
    "override", "extends", "implements", "new", "delete", "void", "int", "long", "short", "char", "float", "double", "bool", "boolean",
    "unsigned", "signed", "auto", "let", "var", "val", "typedef", "extern", "inline", "volatile", "sizeof", "instanceof", "async"),
  red: set("null", "nil", "nullptr", "NULL"),
});
const SHELL = lang({
  control: set("if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "return", "exit", "select"),
  storage: set("export", "local", "declare", "readonly", "unset", "alias"),
  builtins: set("echo", "cd", "printf", "read", "source", "set", "shift", "eval", "exec", "test", "trap", "wait", "kill", "pwd", "type", "ulimit", "umask", "true", "false"),
  green: set(),
  hash: true, slash: false,
});
const SQL = lang({
  control: set("select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create", "table",
    "drop", "alter", "add", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "offset", "as",
    "distinct", "union", "all", "in", "is", "like", "between", "exists", "case", "when", "then", "else", "end", "primary", "key", "index",
    "unique", "default", "references", "foreign", "asc", "desc", "with", "returning", "view", "if", "begin", "commit", "rollback"),
  storage: set(),
  green: set("true", "false", "null"),
  builtins: set("count", "sum", "avg", "min", "max", "coalesce", "length", "lower", "upper", "substr", "replace", "json_extract", "now", "date", "cast", "ifnull", "round"),
  slash: false, dashDash: true, caseless: true,
});
const DATA = lang({ control: set(), storage: set(), green: set("true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null", "NULL", "~") });

function langOf(language: string): Lang | null {
  switch (language) {
    case "ts": case "tsx": case "typescript": case "js": case "jsx": case "javascript": case "mjs": case "cjs": case "mts": case "cts": case "vue": case "svelte": return TS;
    case "py": case "python": case "python3": return PYTHON;
    case "kt": case "kts": case "kotlin": return KOTLIN;
    case "rs": case "rust": return RUST;
    case "go": case "golang": return GO;
    case "sh": case "bash": case "zsh": case "shell": case "console": case "shellscript": case "fish": return SHELL;
    case "sql": case "sqlite": case "postgres": case "postgresql": case "mysql": return SQL;
    case "json": case "jsonc": case "json5": case "yaml": case "yml": case "toml": return DATA;
    case "html": case "xml": case "svg": case "htm": case "css": case "scss": case "less": case "diff": case "patch": case "markdown": case "md": return null;
    default: return C_LIKE;
  }
}

// Kotlin's Char tests, by Unicode category as Kotlin has them.
const isLetter = (c: string | undefined) => c !== undefined && /\p{L}/u.test(c);
const isDigit = (c: string | undefined) => c !== undefined && /\p{Nd}/u.test(c);
const isLetterOrDigit = (c: string | undefined) => isLetter(c) || isDigit(c);
const isWhitespace = (c: string | undefined) => c !== undefined && /\s/u.test(c);
const isUpperCase = (c: string | undefined) => c !== undefined && /\p{Lu}/u.test(c);

const NUMBER = /(0x[0-9a-fA-F_]+|\d[\d_]*(\.\d+)?([eE][+-]?\d+)?)/y;
const NUMBER_ENTIRE = /^(0x[0-9a-fA-F_]+|\d[\d_]*(\.\d+)?([eE][+-]?\d+)?)$/;
const WORD = /[A-Za-z_$][A-Za-z0-9_$]*!?/y;

/** Regex.matchAt: the match starting exactly at `i`, as its end (exclusive), or null. */
function matchAt(re: RegExp, code: string, i: number): number | null {
  re.lastIndex = i;
  const m = re.exec(code);
  return m ? i + m[0].length : null;
}

const PLAIN = new Set(["text", "plain", "txt", "plaintext"]);

export function highlight(code: string, language: string | null | undefined, dark: boolean): AnnotatedString {
  if (language == null || PLAIN.has(language)) return new AnnotatedString(code);
  const b = new AnnotatedStringBuilder();
  b.withStyle({ color: V.text }, () => {
    switch (language) {
      case "json": case "jsonc": case "json5": data(b, code, true); break;
      case "yaml": case "yml": yaml(b, code); break;
      case "toml": case "ini": case "conf": data(b, code, false); break;
      case "html": case "htm": case "xml": case "svg": markup(b, code); break;
      case "css": case "scss": case "less": css(b, code); break;
      case "diff": case "patch": diff(b, code); break;
      case "markdown": case "md": b.append(code); break;
      default: program(b, code, langOf(language) ?? C_LIKE, langOf(language) === SHELL);
    }
  });
  const light = b.toAnnotatedString();
  if (!dark) return light;
  return new AnnotatedString(
    light.text,
    light.spanStyles.map((r) => ({ item: { ...r.item, color: (r.item.color && DARK[r.item.color]) ?? r.item.color }, start: r.start, end: r.end })),
  );
}

type B = AnnotatedStringBuilder;

function put(b: B, code: string, from: number, until: number, color: Color | null): void {
  if (until <= from) return;
  if (color == null) b.append(code, from, until);
  else b.withStyle({ color }, () => b.append(code, from, until));
}

const lineEnd = (code: string, i: number) => { const e = code.indexOf("\n", i); return e < 0 ? code.length : e; };

/** A string from its opening quote at `i`: the quotes fainter than what is between (or `solid`), `${…}` and `{…}` left in it. */
function string(b: B, code: string, i: number, color: Color = V.string, quote: Color = V.quote): number {
  const q = code[i]!;
  const triple = code.startsWith(q.repeat(3), i);
  const open = triple ? 3 : 1;
  let j = i + open;
  while (j < code.length) {
    if (code[j] === "\\") { j += 2; continue; }
    if (triple && code.startsWith(q.repeat(3), j)) break;
    if (!triple && code[j] === q) break;
    if (code[j] === "\n" && q !== "`" && !triple) break;
    j++;
  }
  const end = Math.min(code.length, j);
  const close = end < code.length && code[end] !== "\n" ? open : 0;
  put(b, code, i, i + open, quote);
  put(b, code, i + open, end, color);
  put(b, code, end, Math.min(code.length, end + close), quote);
  return Math.min(code.length, end + close);
}

/** The next character that is not a space or tab, from `j`. */
function next(code: string, j: number): string | undefined {
  let k = j;
  while (k < code.length && (code[k] === " " || code[k] === "\t")) k++;
  return code[k];
}

/** The last character before `j` that is not a space or tab. */
function before(code: string, j: number): string | undefined {
  let k = j - 1;
  while (k >= 0 && (code[k] === " " || code[k] === "\t")) k--;
  return k >= 0 ? code[k] : undefined;
}

const OPERATORS = "+-*/%!&|^~?<>=";
const PUNCT = "{}[]();,.:";
const has = (chars: string, c: string | undefined) => c !== undefined && c.length === 1 && chars.includes(c);

function program(b: B, code: string, l: Lang, shell: boolean): void {
  let i = 0;
  const n = code.length;
  // Open brackets: a name and a colon inside braces is a key, inside parentheses a parameter.
  const brackets: string[] = [];
  let previousWord = "";
  // In a shell: at a command's first word (the start of a line, after | ; && then do).
  let command = true;
  let afterColon = false;
  while (i < n) {
    const c = code[i]!;
    if (c === "\n") { b.append(c); i++; if (shell) command = true; afterColon = false; }
    else if (c === " " || c === "\t" || c === "\r") { b.append(c); i++; }
    else if (l.hash && c === "#" && (i === 0 || isWhitespace(code[i - 1]))) { const e = lineEnd(code, i); put(b, code, i, e, V.comment); i = e; }
    else if (l.slash && code.startsWith("//", i)) { const e = lineEnd(code, i); put(b, code, i, e, V.comment); i = e; }
    else if (l.slash && code.startsWith("/*", i)) { const at = code.indexOf("*/", i + 2); const e = at < 0 ? n : at + 2; put(b, code, i, e, V.comment); i = e; }
    else if (l.dashDash && code.startsWith("--", i)) { const e = lineEnd(code, i); put(b, code, i, e, V.comment); i = e; }
    else if (c === "\"" || c === "'" || c === "`") {
      i = l.solidQuotes ? string(b, code, i, V.string, V.string) : string(b, code, i);
      if (shell) command = false;
    } else if (shell && c === "$" && i + 1 < n && (isLetter(code[i + 1]) || code[i + 1] === "_" || code[i + 1] === "{")) {
      let j = i + 1;
      if (code[j] === "{") { const at = code.indexOf("}", j); j = at < 0 ? n : at + 1; }
      else while (j < n && (isLetterOrDigit(code[j]) || code[j] === "_")) j++;
      put(b, code, i, j, V.variable); i = j; command = false;
    } else if (shell && c === "-" && (i === 0 || isWhitespace(code[i - 1])) && i + 1 < n && (isLetter(code[i + 1]) || code[i + 1] === "-")) {
      let j = i + 1;
      while (j < n && !isWhitespace(code[j]) && !has(";|&)=", code[j])) j++;
      put(b, code, i, j, V.constant); i = j;
    } else if (shell && !command && !isWhitespace(c) && !has(";|&<>()[]", c) && !code.startsWith("\\\n", i)) {
      // An argument: Shiki's shell grammar draws words after the command as strings.
      let j = i;
      while (j < n && !isWhitespace(code[j]) && !has(";|&<>()[]\"'`$", code[j])) j++;
      if (j === i) j = i + 1;
      const word = code.substring(i, j);
      put(b, code, i, j, [...word].every((ch) => isDigit(ch)) ? V.number : V.string); i = j;
    } else if (isDigit(c) && (i === 0 || (!isLetterOrDigit(code[i - 1]) && code[i - 1] !== "_"))) {
      const m = matchAt(NUMBER, code, i);
      if (m != null) { put(b, code, i, m, V.number); i = m; } else { b.append(c); i++; }
    } else if (isLetter(c) || c === "_" || (c === "$" && !shell) || (shell && command && (c === "." || c === "/" || c === "~"))) {
      let end: number;
      if (shell && command) {
        end = i;
        while (end < n && !isWhitespace(code[end]) && !has(";|&<>()=\"'`", code[end])) end++;
      } else {
        const m = matchAt(WORD, code, i);
        end = m != null ? m : i + 1;
      }
      // A name with the macro's bang (Rust's println!) only where the language has them.
      if (l !== RUST && end > i && code[end - 1] === "!") end--;
      const word = code.substring(i, end);
      const key = l.caseless ? word.toLowerCase() : word;
      const nextChar = next(code, end);
      const prev = before(code, i);
      let color: Color | null;
      if (shell && command && end < n && code[end] === "=") { color = V.variable; command = true; }
      else if (shell && command) {
        if (l.control.has(key)) color = V.control;
        else if (l.storage.has(key)) { color = V.storage; command = false; }
        else if (l.builtins.has(key)) { color = V.property; command = false; }
        else { color = V.function; command = false; }
      } else if (shell && prev === "=") color = V.variable;
      else if (l.control.has(key)) color = V.control;
      else if (l.storage.has(key)) color = V.storage;
      else if (l.green.has(key)) color = V.control;
      else if (l.red.has(key)) color = V.storage;
      else if (word === "this" || word === "self" || word === "Self") color = V.constant;
      else if (["function", "def", "fun", "fn", "func"].includes(previousWord)) color = V.function;
      else if (["class", "interface", "type", "struct", "enum", "trait", "impl", "object", "typealias"].includes(previousWord)) color = V.type;
      else if (["new", "extends", "implements"].includes(previousWord)) color = V.function;
      else if (nextChar === "(" || (l === RUST && word.endsWith("!"))) color = l.builtins.has(key) ? V.property : V.function;
      else if (l.types.has(key)) color = V.type;
      else if (afterColon && l !== PYTHON && isUpperCase(word[0])) color = V.type;
      else if (l === KOTLIN && isUpperCase(word[0])) color = V.type;
      else if (l === TS && isUpperCase(word[0]) && nextChar === "<") color = V.type;
      else if (l === RUST && isUpperCase(word[0])) color = V.type;
      else if (l === RUST && nextChar === ":" && code.startsWith("::", end)) color = V.function;
      else if (l === TS && nextChar === ":" && brackets[brackets.length - 1] === "{" && prev !== "?") color = V.property;
      else if (l.variables) color = V.variable;
      else color = null;
      put(b, code, i, end, color);
      previousWord = key;
      afterColon = false;
      i = end;
    } else if (has("([{", c)) { brackets.push(c); put(b, code, i, i + 1, l.plainPunct ? null : V.punct); i++; if (shell) command = true; }
    else if (has(")]}", c)) { brackets.pop(); put(b, code, i, i + 1, l.plainPunct ? null : V.punct); i++; }
    else if (has(OPERATORS, c) || c === ":") {
      let j = i;
      while (j < n && (has(OPERATORS, code[j]) || code[j] === ":")) j++;
      const op = code.substring(i, j);
      const spaced = (i === 0 || isWhitespace(code[i - 1])) && (j >= n || isWhitespace(code[j]));
      let color: Color | null;
      if (shell) color = op === "|" || op === "||" || op === ">" || op === ">>" || op === "<" ? V.storage : V.punct;
      else if (op === "=" || op === ":=" || op === "=>") color = V.punct;
      else if (op === ":") color = l === RUST ? V.storage : l.plainPunct ? null : V.punct;
      else if (op === "::" || op === "->") color = l === RUST ? V.storage : V.punct;
      else if ((op === "<" || op === ">") && !spaced) color = l.plainPunct ? null : V.punct;
      else if (op === "?" && l.plainPunct) color = null;
      else if (op === "?" && next(code, j) === ":") color = V.storage;
      else color = V.storage;
      put(b, code, i, j, color);
      afterColon = op === ":" || op === "?:" || op === "->" || op === "):";
      if (shell && (op === "|" || op === "||" || op === "&&" || op === "&")) command = true;
      i = j;
    } else if (has(PUNCT, c)) {
      put(b, code, i, i + 1, l.plainPunct ? null : V.punct); i++;
      if (shell && c === ";") command = true;
      if (c === ",") afterColon = false;
    } else { b.append(c); i++; }
  }
}

/** JSON (keys in the property colour, their quotes fainter) and TOML/INI (`key = value`). */
function data(b: B, code: string, json: boolean): void {
  let i = 0;
  const n = code.length;
  while (i < n) {
    const c = code[i]!;
    if (!json && c === "#") { const e = lineEnd(code, i); put(b, code, i, e, V.comment); i = e; }
    else if (json && code.startsWith("//", i)) { const e = lineEnd(code, i); put(b, code, i, e, V.comment); i = e; }
    else if (c === "\"" || c === "'") {
      // A key: the string before a colon (JSON).
      let j = i + 1;
      while (j < n && code[j] !== c && code[j] !== "\n") j += code[j] === "\\" ? 2 : 1;
      const key = json && next(code, j + 1) === ":";
      i = key ? string(b, code, i, V.property, V.propertyQuote) : string(b, code, i);
    } else if (c === "-" || isDigit(c)) {
      const m = matchAt(NUMBER, code, c === "-" ? i + 1 : i);
      if (m != null) { put(b, code, i, m, V.number); i = m; } else { put(b, code, i, i + 1, V.punct); i++; }
    } else if (isLetter(c) || c === "_") {
      let j = i;
      while (j < n && (isLetterOrDigit(code[j]) || has("_-.", code[j]))) j++;
      const word = code.substring(i, j);
      const color = DATA.green.has(word) ? V.control : !json && next(code, j) === "=" ? V.property : null;
      put(b, code, i, j, color); i = j;
    } else if (has("{}[],:=", c)) { put(b, code, i, i + 1, V.punct); i++; }
    else { b.append(c); i++; }
  }
}

/** YAML: keys in the property colour; plain values are strings to Shiki. */
function yaml(b: B, code: string): void {
  let i = 0;
  const n = code.length;
  while (i < n) {
    const e = lineEnd(code, i);
    let j = i;
    while (j < e && (code[j] === " " || code[j] === "\t")) j++;
    put(b, code, i, j, null);
    if (j < e && code[j] === "-" && (j + 1 === e || code[j + 1] === " ")) {
      put(b, code, j, j + 1, V.punct); j++;
      while (j < e && code[j] === " ") { b.append(" "); j++; }
    }
    if (j < e && code[j] === "#") { put(b, code, j, e, V.comment); j = e; }
    const colon = /^[^#'"]*?:(\s|$)/.exec(code.substring(j, e));
    if (colon != null) {
      const k = j + colon[0].trimEnd().length - 1;
      put(b, code, j, k, V.property); put(b, code, k, k + 1, V.punct); j = k + 1;
    }
    while (j < e) {
      const c = code[j]!;
      if (c === " ") { b.append(c); j++; }
      else if (c === "#" && code[j - 1] === " ") { put(b, code, j, e, V.comment); j = e; }
      else if (c === "\"" || c === "'") j = Math.min(e, string(b, code, j));
      else {
        const at = code.indexOf(" #", j);
        const hashAt = at < 0 || at > e ? e : at;
        const value = code.substring(j, hashAt).trimEnd();
        const color = DATA.green.has(value) ? V.control
          : NUMBER_ENTIRE.test(value) ? V.number
          : ["|", ">", "|-", ">-", "[]", "{}"].includes(value) ? V.punct
          : V.string;
        put(b, code, j, j + value.length, color); j += value.length;
        // A value that is only blank (a tab, a \r) would leave `j` where it is, the loop never ending (it does in
        // Highlight.kt): it is taken as it is.
        if (value.length === 0) { b.append(code[j]!); j++; }
      }
    }
    if (e < n) b.append("\n");
    i = e + 1;
  }
}

/** HTML and XML: tags green, attribute names brown, values strings, the brackets grey. */
function markup(b: B, code: string): void {
  let i = 0;
  const n = code.length;
  while (i < n) {
    if (code.startsWith("<!--", i)) { const at = code.indexOf("-->", i); const e = at < 0 ? n : at + 3; put(b, code, i, e, V.comment); i = e; }
    else if (code[i] === "<") {
      let j = i + 1;
      if (j < n && (code[j] === "/" || code[j] === "!" || code[j] === "?")) j++;
      put(b, code, i, j, V.punct);
      let k = j;
      while (k < n && (isLetterOrDigit(code[k]) || has("-_:.", code[k]))) k++;
      put(b, code, j, k, V.control);
      i = k;
      while (i < n && code[i] !== ">") {
        const c = code[i]!;
        if (c === "\"" || c === "'") i = string(b, code, i);
        else if (c === "=" || c === "/" || c === "?") { put(b, code, i, i + 1, V.punct); i++; }
        else if (isWhitespace(c)) { b.append(c); i++; }
        else {
          let e = i;
          while (e < n && !isWhitespace(code[e]) && !has("=>/\"'", code[e])) e++;
          if (e === i) e = i + 1;
          put(b, code, i, e, i > 0 && code[i - 1] === "=" ? V.string : V.variable); i = e;
        }
      }
      if (i < n) { put(b, code, i, i + 1, V.punct); i++; }
    } else {
      const at = code.indexOf("<", i);
      const e = at < 0 ? n : at;
      put(b, code, i, e, null); i = e;
    }
  }
}

/** CSS: selectors (classes brown, elements green), properties, numbers with their units red, colours as constants. */
function css(b: B, code: string): void {
  let i = 0;
  const n = code.length;
  let depth = 0;
  while (i < n) {
    const c = code[i]!;
    let inBlock = false;
    if (depth > 0) {
      // Inside a rule's braces, and not in a nested selector (a word followed by `{`).
      let stop = -1;
      for (let k = i; k < n; k++) if (code[k] === ";" || code[k] === "{" || code[k] === "}") { stop = k; break; }
      inBlock = stop < 0 || code[stop] !== "{";
    }
    if (code.startsWith("/*", i)) { const at = code.indexOf("*/", i + 2); const e = at < 0 ? n : at + 2; put(b, code, i, e, V.comment); i = e; }
    else if (c === "\"" || c === "'") i = string(b, code, i);
    else if (c === "{") { depth++; put(b, code, i, i + 1, V.punct); i++; }
    else if (c === "}") { depth = Math.max(0, depth - 1); put(b, code, i, i + 1, V.punct); i++; }
    else if (c === "#" && inBlock) {
      let j = i + 1;
      while (j < n && isLetterOrDigit(code[j])) j++;
      put(b, code, i, i + 1, V.punct); put(b, code, i + 1, j, V.constant); i = j;
    } else if ((isDigit(c) || (c === "." && i + 1 < n && isDigit(code[i + 1]))) && inBlock) {
      let j = i;
      while (j < n && (isDigit(code[j]) || code[j] === ".")) j++;
      let u = j;
      while (u < n && (isLetter(code[u]) || code[u] === "%")) u++;
      put(b, code, i, j, V.number); put(b, code, j, u, V.storage); i = u;
    } else if (isLetter(c) || c === "-" || c === "_") {
      let j = i;
      while (j < n && (isLetterOrDigit(code[j]) || has("-_", code[j]))) j++;
      const word = code.substring(i, j);
      const color = inBlock && next(code, j) === ":" ? (word.startsWith("--") ? V.variable : V.property)
        : inBlock ? null
        : i > 0 && (code[i - 1] === "." || code[i - 1] === ":" || code[i - 1] === "#") ? V.variable
        : V.control;
      put(b, code, i, j, color); i = j;
    } else if (c === ">" || c === "+" || c === "~") { put(b, code, i, i + 1, depth === 0 || !inBlock ? V.storage : V.punct); i++; }
    else if (has(".:;,()@#*[]", c)) { put(b, code, i, i + 1, V.punct); i++; }
    else { b.append(c); i++; }
  }
}

/** A diff as Shiki colours one: removed lines red, added green (their `---`/`+++` marks grey), a hunk's range purple between grey `@@`. */
function diff(b: B, code: string): void {
  let i = 0;
  while (i < code.length) {
    const e = lineEnd(code, i);
    if (code.startsWith("+++", i) || code.startsWith("---", i)) {
      put(b, code, i, i + 3, V.punct); put(b, code, i + 3, e, code[i] === "+" ? V.added : V.removed);
    } else if (code.startsWith("@@", i)) {
      const at = code.indexOf("@@", i + 2);
      const close = at >= 0 && at < e ? at : null;
      put(b, code, i, i + 2, V.punct);
      if (close == null) put(b, code, i + 2, e, V.range);
      else { put(b, code, i + 2, close, V.range); put(b, code, close, close + 2, V.punct); put(b, code, close + 2, e, null); }
    } else if (code.startsWith("+", i)) put(b, code, i, e, V.added);
    else if (code.startsWith("-", i)) put(b, code, i, e, V.removed);
    else put(b, code, i, e, null);
    if (e < code.length) b.append("\n");
    i = e + 1;
  }
}
