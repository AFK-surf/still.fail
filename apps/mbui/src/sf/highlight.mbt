// Code blocks coloured as the web colours them: Shiki with its dual themes,
// vitesse-light and vitesse-dark (web/src/Prose.tsx), as the Android app's
// ui/Highlight.kt has it. Not a grammar per language as Shiki has, but a
// light tokenizer that knows how the common languages write comments,
// strings and numbers, and, per language family, which words vitesse draws
// as control words (green), which as declarations and operators (red), and
// whether plain names are variables (brown) or plain text; the colours are
// the theme's, token for token as Shiki gives them. Dark takes each light
// colour's vitesse-dark twin (the pairs Shiki gives the same tokens).

///|
/// What vitesse colours a piece of code as.
priv enum Scope {
  Text
  Comment
  Punct
  Str
  /// a string's quotes
  Quote
  Num
  /// keyword, keyword.control, constant.language (true, None), entity.name.tag
  Control
  /// storage (function, const, class), keyword.operator, null, undefined
  Storage
  Func
  Var
  /// constant, variable.language (this, self), an option (-x)
  Constant
  TypeName
  /// property names, support (builtins as print, echo)
  Property
  PropertyQuote
  /// a diff's lines added and removed, a hunk's range (Shiki's own diff colours)
  Added
  Removed
  Hunk
} derive(Eq)

///|
/// vitesse-light's colour (its tokenColors).
fn Scope::light(self : Scope) -> Int64 {
  match self {
    Text => 0x393A34FFL
    Comment => 0xA0ADA0FFL
    Punct => 0x999999FFL
    Str => 0xB56959FFL
    Quote => 0xB5695977L
    Num => 0x2F798AFFL
    Control => 0x1E754FFFL
    Storage => 0xAB5959FFL
    Func => 0x59873AFFL
    Var => 0xB07D48FFL
    Constant => 0xA65E2BFFL
    TypeName => 0x2E8F82FFL
    Property => 0x998418FFL
    PropertyQuote => 0x99841877L
    Added => 0x22863AFFL
    Removed => 0xB31D28FFL
    Hunk => 0x6F42C1FFL
  }
}

///|
/// vitesse-dark's colour for the same (Shiki's `--shiki-dark` beside the light one).
fn Scope::dark(self : Scope) -> Int64 {
  match self {
    Text => 0xDBD7CAEEL
    Comment => 0x758575DDL
    Punct => 0x666666FFL
    Str => 0xC98A7DFFL
    Quote => 0xC98A7D77L
    Num => 0x4C9A91FFL
    Control => 0x4D9375FFL
    Storage => 0xCB7676FFL
    Func => 0x80A665FFL
    Var => 0xBD976AFFL
    Constant => 0xC99076FFL
    TypeName => 0x5DA994FFL
    Property => 0xB8A965FFL
    PropertyQuote => 0xB8A96577L
    Added => 0x85E89DFFL
    Removed => 0xFDAEB7FFL
    Hunk => 0xB392F0FFL
  }
}

///|
priv enum Family {
  Ts
  Python
  Kotlin
  Rust
  Go
  CLike
  Shell
  Sql
  Data
} derive(Eq)

///|
/// How a family of languages is written and coloured.
priv struct Lang {
  family : Family
  control : Map[String, Bool]
  storage : Map[String, Bool]
  /// constant.language drawn green (true, false, None)
  green : Map[String, Bool]
  /// constant.language drawn red (null, undefined in TypeScript)
  red : Map[String, Bool]
  builtins : Map[String, Bool]
  types : Map[String, Bool]
  /// plain names are variables (brown), as TypeScript, Rust and Go have them; else plain text
  variables : Bool
  /// brackets, commas and colons in the text colour (Kotlin's grammar leaves them unscoped); else grey
  plain_punct : Bool
  /// quotes in the string's colour, not the fainter one
  solid_quotes : Bool
  hash_comment : Bool
  slash_comment : Bool
  dash_comment : Bool
  caseless : Bool
}

///|
fn word_set(words : Array[String]) -> Map[String, Bool] {
  let m : Map[String, Bool] = {}
  for w in words {
    m[w] = true
  }
  m
}

///|
fn lang(
  family : Family,
  control : Array[String],
  storage : Array[String],
  green? : Array[String] = ["true", "false"],
  red? : Array[String] = [],
  builtins? : Array[String] = [],
  types? : Array[String] = [],
  variables? : Bool = false,
  plain_punct? : Bool = false,
  solid_quotes? : Bool = false,
  hash? : Bool = false,
  slash? : Bool = true,
  dash_dash? : Bool = false,
  caseless? : Bool = false,
) -> Lang {
  {
    family,
    control: word_set(control),
    storage: word_set(storage),
    green: word_set(green),
    red: word_set(red),
    builtins: word_set(builtins),
    types: word_set(types),
    variables,
    plain_punct,
    solid_quotes,
    hash_comment: hash,
    slash_comment: slash,
    dash_comment: dash_dash,
    caseless,
  }
}

///|
let ts_lang : Lang = lang(
  Ts,
  [
    "if", "else", "for", "while", "do", "return", "break", "continue", "switch",
    "case", "default", "import", "from", "export", "as", "try", "catch", "finally",
    "throw", "await", "yield", "of", "with", "debugger",
  ],
  [
    "function", "const", "let", "var", "class", "interface", "enum", "type", "namespace",
    "declare", "abstract", "async", "static", "public", "private", "protected", "readonly",
    "extends", "implements", "new", "delete", "typeof", "instanceof", "in", "keyof",
    "void", "get", "set", "override", "satisfies",
  ],
  red=["null", "undefined"],
  types=[
    "string", "number", "boolean", "any", "unknown", "never", "object", "bigint", "symbol",
  ],
  variables=true,
)

///|
let python_lang : Lang = lang(
  Python,
  [
    "if", "elif", "else", "for", "while", "return", "break", "continue", "import",
    "from", "as", "try", "except", "finally", "raise", "with", "yield", "await", "pass",
    "assert", "match", "case", "del", "global", "nonlocal",
  ],
  ["def", "class", "lambda", "async", "and", "or", "not", "in", "is"],
  green=["True", "False", "None"],
  builtins=[
    "print", "len", "range", "str", "int", "float", "dict", "list", "set", "tuple",
    "open", "isinstance", "super", "sorted", "enumerate", "zip", "map", "filter", "min",
    "max", "sum", "any", "all", "type", "repr", "bool", "input", "abs", "round", "getattr",
    "setattr", "hasattr",
  ],
  hash=true,
  slash=false,
)

///|
let kotlin_lang : Lang = lang(
  Kotlin,
  [
    "if", "else", "for", "while", "do", "return", "break", "continue", "when", "try",
    "catch", "finally", "throw", "package", "import", "as", "is", "in", "fun", "val",
    "var", "class", "object", "interface", "typealias", "true", "false", "this", "super",
    "where", "by", "constructor", "init",
  ],
  [
    "override", "private", "public", "protected", "internal", "open", "abstract", "final",
    "data", "sealed", "enum", "inline", "suspend", "lateinit", "const", "companion",
    "operator", "infix", "tailrec", "external", "annotation", "inner", "vararg", "reified",
    "crossinline", "noinline",
  ],
  red=["null"],
  plain_punct=true,
  solid_quotes=true,
)

///|
let rust_lang : Lang = lang(
  Rust,
  [
    "if", "else", "for", "while", "loop", "return", "break", "continue", "match", "use",
    "mod", "fn", "impl", "pub", "crate", "as", "in", "where", "async", "await", "move",
    "unsafe", "extern", "trait", "type", "dyn",
  ],
  ["let", "mut", "struct", "enum", "const", "static", "ref"],
  types=[
    "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize",
    "f32", "f64", "bool", "char", "str",
  ],
  variables=true,
)

///|
let go_lang : Lang = lang(
  Go,
  [
    "if", "else", "for", "range", "return", "break", "continue", "switch", "case", "default",
    "package", "import", "func", "var", "const", "type", "struct", "interface", "map", "chan",
    "go", "defer", "select", "fallthrough", "goto",
  ],
  [
    "string", "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32",
    "uint64", "float32", "float64", "bool", "byte", "rune", "error", "any",
  ],
  red=["nil"],
  variables=true,
)

///|
let c_like_lang : Lang = lang(
  CLike,
  [
    "if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case",
    "default", "import", "package", "try", "catch", "finally", "throw", "throws", "using",
    "namespace", "include", "define", "goto", "yield", "await", "guard", "defer", "func",
    "fun", "fn", "def",
  ],
  [
    "class", "struct", "enum", "interface", "const", "static", "public", "private",
    "protected", "final", "abstract", "virtual", "override", "extends", "implements", "new",
    "delete", "void", "int", "long", "short", "char", "float", "double", "bool", "boolean",
    "unsigned", "signed", "auto", "let", "var", "val", "typedef", "extern", "inline",
    "volatile", "sizeof", "instanceof", "async",
  ],
  red=["null", "nil", "nullptr", "NULL"],
)

///|
let shell_lang : Lang = lang(
  Shell,
  [
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
    "in", "function", "return", "exit", "select",
  ],
  ["export", "local", "declare", "readonly", "unset", "alias"],
  builtins=[
    "echo", "cd", "printf", "read", "source", "set", "shift", "eval", "exec", "test", "trap",
    "wait", "kill", "pwd", "type", "ulimit", "umask", "true", "false",
  ],
  green=[],
  hash=true,
  slash=false,
)

///|
let sql_lang : Lang = lang(
  Sql,
  [
    "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update",
    "set", "delete", "create", "table", "drop", "alter", "add", "join", "left", "right",
    "inner", "outer", "on", "group", "by", "order", "having", "limit", "offset", "as",
    "distinct", "union", "all", "in", "is", "like", "between", "exists", "case", "when",
    "then", "else", "end", "primary", "key", "index", "unique", "default", "references",
    "foreign", "asc", "desc", "with", "returning", "view", "if", "begin", "commit", "rollback",
  ],
  [],
  green=["true", "false", "null"],
  builtins=[
    "count", "sum", "avg", "min", "max", "coalesce", "length", "lower", "upper", "substr",
    "replace", "json_extract", "now", "date", "cast", "ifnull", "round",
  ],
  slash=false,
  dash_dash=true,
  caseless=true,
)

///|
let data_lang : Lang = lang(Data, [], [], green=[
  "true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null", "NULL", "~",
])

///|
/// The words after which a name is a function's.
let fn_words : Map[String, Bool] = word_set(["function", "def", "fun", "fn", "func"])

///|
/// The words after which a name is a type's.
let type_words : Map[String, Bool] = word_set([
  "class", "interface", "type", "struct", "enum", "trait", "impl", "object", "typealias",
])

///|
/// The words after which a name is a constructor's.
let new_words : Map[String, Bool] = word_set(["new", "extends", "implements"])

///|
/// YAML's block scalars and empty collections.
let yaml_marks : Map[String, Bool] = word_set(["|", ">", "|-", ">-", "[]", "{}"])

///|
fn lang_of(language : String) -> Lang? {
  match language {
    "ts" | "tsx" | "typescript" | "js" | "jsx" | "javascript" | "mjs" | "cjs" | "mts" | "cts" |
    "vue" | "svelte" => Some(ts_lang)
    "py" | "python" | "python3" => Some(python_lang)
    "kt" | "kts" | "kotlin" => Some(kotlin_lang)
    "rs" | "rust" => Some(rust_lang)
    "go" | "golang" => Some(go_lang)
    "sh" | "bash" | "zsh" | "shell" | "console" | "shellscript" | "fish" => Some(shell_lang)
    "sql" | "sqlite" | "postgres" | "postgresql" | "mysql" => Some(sql_lang)
    "json" | "jsonc" | "json5" | "yaml" | "yml" | "toml" => Some(data_lang)
    "html" | "xml" | "svg" | "htm" | "css" | "scss" | "less" | "diff" | "patch" | "markdown" |
    "md" => None
    _ => Some(c_like_lang)
  }
}

///|
/// `code` coloured as the web colours it (Shiki's vitesse-light / vitesse-dark), as runs for @ui.Ctx::rich: each run
/// `@ui.span(text, mono=true, color=…)` (color 0L where the text keeps the paragraph's own colour). None of a language
/// it does not colour (text, plain, txt, plaintext, or an empty language): the caller draws it plain.
pub fn highlight(code : String, language : String, dark : Bool) -> Array[@ui.Run]? {
  match language {
    "" | "text" | "plain" | "txt" | "plaintext" => return None
    _ => ()
  }
  let h : Hl = { code, dark, runs: [], start: 0, end: 0, scope: Text }
  match language {
    "json" | "jsonc" | "json5" => h.data(true)
    "yaml" | "yml" => h.yaml()
    "toml" | "ini" | "conf" => h.data(false)
    "html" | "htm" | "xml" | "svg" => h.markup()
    "css" | "scss" | "less" => h.css()
    "diff" | "patch" => h.diff()
    "markdown" | "md" => h.put(0, code.length(), Text)
    _ => {
      let l = match lang_of(language) {
        Some(l) => l
        None => c_like_lang
      }
      h.program(l, l.family == Shell)
    }
  }
  h.flush()
  Some(h.runs)
}

///|
/// The runs being made: the one still open is `code` from `start` until `end`, in `scope`.
priv struct Hl {
  code : String
  dark : Bool
  runs : Array[@ui.Run]
  mut start : Int
  mut end : Int
  mut scope : Scope
}

///|
fn Hl::put(self : Hl, from : Int, until : Int, scope : Scope) -> Unit {
  if until <= from {
    return
  }
  if scope == self.scope && from == self.end && self.end > self.start {
    self.end = until
    return
  }
  self.flush()
  self.start = from
  self.end = until
  self.scope = scope
}

///|
fn Hl::flush(self : Hl) -> Unit {
  if self.end > self.start {
    let color = if self.dark { self.scope.dark() } else { self.scope.light() }
    let text = self.code.view(start_offset=self.start, end_offset=self.end).to_string()
    self.runs.push(@ui.span(text, mono=true, color~))
  }
  self.start = self.end
}

// ---------------------------------------------------------------------------
// Characters (UTF-16 code units)

///|
fn hl_cu(s : String, i : Int) -> Int {
  s.at(i).to_int()
}

///|
/// Kotlin's Char.isWhitespace.
fn hl_space(c : Int) -> Bool {
  c == 32 ||
  (c >= 9 && c <= 13) ||
  (c >= 0x1C && c <= 0x1F) ||
  c == 0xA0 ||
  c == 0x1680 ||
  (c >= 0x2000 && c <= 0x200A) ||
  c == 0x2028 ||
  c == 0x2029 ||
  c == 0x202F ||
  c == 0x205F ||
  c == 0x3000
}

///|
/// A letter: ASCII's, or any other character but a space (a surrogate, half an emoji, is none).
fn hl_letter(c : Int) -> Bool {
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  (c >= 0x80 && !hl_space(c) && !(c >= 0xD800 && c <= 0xDFFF))
}

///|
fn hl_digit(c : Int) -> Bool {
  c >= 48 && c <= 57
}

///|
fn hl_letter_or_digit(c : Int) -> Bool {
  hl_letter(c) || hl_digit(c)
}

///|
fn hl_upper(c : Int) -> Bool {
  c >= 65 && c <= 90
}

///|
fn hl_ascii_alnum(c : Int) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57)
}

///|
/// Whether `c` is one of `chars`.
fn hl_has(chars : String, c : Int) -> Bool {
  for k in 0..<chars.length() {
    if hl_cu(chars, k) == c {
      return true
    }
  }
  false
}

///|
/// Whether `pat` is in `s` at `i`.
fn hl_at(s : String, i : Int, pat : String) -> Bool {
  let m = pat.length()
  if i < 0 || i + m > s.length() {
    return false
  }
  for k in 0..<m {
    if hl_cu(s, i + k) != hl_cu(pat, k) {
      return false
    }
  }
  true
}

///|
/// Where `pat` is first in `s` from `from`, wholly before `limit` (-1 nowhere).
fn hl_index(s : String, pat : String, from : Int, limit : Int) -> Int {
  let mut p = if from < 0 { 0 } else { from }
  while p + pat.length() <= limit {
    if hl_at(s, p, pat) {
      return p
    }
    p = p + 1
  }
  -1
}

///|
fn hl_index_unit(s : String, c : Int, from : Int) -> Int {
  let mut p = if from < 0 { 0 } else { from }
  while p < s.length() {
    if hl_cu(s, p) == c {
      return p
    }
    p = p + 1
  }
  -1
}

///|
fn hl_line_end(s : String, i : Int) -> Int {
  let e = hl_index_unit(s, 10, i)
  if e < 0 {
    s.length()
  } else {
    e
  }
}

///|
/// The next character that is not a space or tab, from `j` (-1 none).
fn hl_next(s : String, j : Int) -> Int {
  let mut k = j
  while k < s.length() && (hl_cu(s, k) == 32 || hl_cu(s, k) == 9) {
    k = k + 1
  }
  if k >= 0 && k < s.length() {
    hl_cu(s, k)
  } else {
    -1
  }
}

///|
/// The last character before `j` that is not a space or tab (-1 none).
fn hl_before(s : String, j : Int) -> Int {
  let mut k = j - 1
  while k >= 0 && (hl_cu(s, k) == 32 || hl_cu(s, k) == 9) {
    k = k - 1
  }
  if k >= 0 && k < s.length() {
    hl_cu(s, k)
  } else {
    -1
  }
}

///|
fn hl_trim_end(s : String) -> String {
  let mut k = s.length()
  while k > 0 && hl_space(hl_cu(s, k - 1)) {
    k = k - 1
  }
  s.view(start_offset=0, end_offset=k).to_string()
}

///|
/// A number at `i`, `0x[0-9a-fA-F_]+|\d[\d_]*(\.\d+)?([eE][+-]?\d+)?`: where it ends (-1 none).
fn hl_number(s : String, i : Int) -> Int {
  let n = s.length()
  if i < 0 || i >= n || !hl_digit(hl_cu(s, i)) {
    return -1
  }
  if hl_cu(s, i) == 48 && i + 2 < n && hl_cu(s, i + 1) == 120 {
    let mut j = i + 2
    while j < n && (hl_has("0123456789abcdefABCDEF_", hl_cu(s, j))) {
      j = j + 1
    }
    if j > i + 2 {
      return j
    }
  }
  let mut j = i + 1
  while j < n && (hl_digit(hl_cu(s, j)) || hl_cu(s, j) == 95) {
    j = j + 1
  }
  if j + 1 < n && hl_cu(s, j) == 46 && hl_digit(hl_cu(s, j + 1)) {
    j = j + 2
    while j < n && hl_digit(hl_cu(s, j)) {
      j = j + 1
    }
  }
  if j < n && (hl_cu(s, j) == 101 || hl_cu(s, j) == 69) {
    let mut k = j + 1
    if k < n && (hl_cu(s, k) == 43 || hl_cu(s, k) == 45) {
      k = k + 1
    }
    if k < n && hl_digit(hl_cu(s, k)) {
      while k < n && hl_digit(hl_cu(s, k)) {
        k = k + 1
      }
      j = k
    }
  }
  j
}

///|
/// A name at `i`, `[A-Za-z_$][A-Za-z0-9_$]*!?`: where it ends (-1 none).
fn hl_word(s : String, i : Int) -> Int {
  let n = s.length()
  if i < 0 || i >= n {
    return -1
  }
  let c = hl_cu(s, i)
  if !((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36) {
    return -1
  }
  let mut j = i + 1
  while j < n && (hl_ascii_alnum(hl_cu(s, j)) || hl_cu(s, j) == 95 || hl_cu(s, j) == 36) {
    j = j + 1
  }
  if j < n && hl_cu(s, j) == 33 {
    j = j + 1
  }
  j
}

///|
/// A YAML key's colon in `s` from `j` until the line's end `e`, `^[^#'"]*?:(\s|$)`: where it is (-1 none).
fn hl_yaml_colon(s : String, j : Int, e : Int) -> Int {
  let mut p = j
  while p < e {
    let c = hl_cu(s, p)
    if c == 35 || c == 39 || c == 34 {
      return -1
    }
    if c == 58 {
      if p + 1 == e {
        return p
      }
      let d = hl_cu(s, p + 1)
      if d == 32 || (d >= 9 && d <= 13) {
        return p
      }
      // `$` also before a last line terminator
      if p + 2 == e && (d == 0x85 || d == 0x2028 || d == 0x2029) {
        return p
      }
    }
    p = p + 1
  }
  -1
}

// ---------------------------------------------------------------------------
// The tokenizers

///|
/// A string from its opening quote at `i`, not past `limit`: the quotes in `quote` (fainter than what is between, or
/// the same), `${…}` and `{…}` left in it. Where it ends.
fn Hl::quoted(self : Hl, i : Int, scope : Scope, quote : Scope, limit : Int) -> Int {
  let code = self.code
  let q = hl_cu(code, i)
  let triple = i + 2 < limit && hl_cu(code, i + 1) == q && hl_cu(code, i + 2) == q
  let quotes = if triple { 3 } else { 1 }
  let mut j = i + quotes
  while j < limit {
    let c = hl_cu(code, j)
    if c == 92 {
      j = j + 2
      continue
    }
    if triple && j + 2 < limit && c == q && hl_cu(code, j + 1) == q && hl_cu(code, j + 2) == q {
      break
    }
    if !triple && c == q {
      break
    }
    if c == 10 && q != 96 && !triple {
      break
    }
    j = j + 1
  }
  let end = if j < limit { j } else { limit }
  let close = if end < limit && hl_cu(code, end) != 10 { quotes } else { 0 }
  let stop = if end + close < limit { end + close } else { limit }
  self.put(i, i + quotes, quote)
  self.put(i + quotes, end, scope)
  self.put(end, stop, quote)
  stop
}

///|
fn Hl::program(self : Hl, l : Lang, shell : Bool) -> Unit {
  let code = self.code
  let n = code.length()
  let mut i = 0
  // Open brackets: a name and a colon inside braces is a key, inside parentheses a parameter.
  let brackets : Array[Int] = []
  let mut previous_word = ""
  // In a shell: at a command's first word (the start of a line, after | ; && then do).
  let mut command = true
  let mut after_colon = false
  let operators = "+-*/%!&|^~?<>="
  let bracket_tone : Scope = if l.plain_punct { Text } else { Punct }
  while i < n {
    let c = hl_cu(code, i)
    if c == 10 {
      self.put(i, i + 1, Text)
      i = i + 1
      if shell {
        command = true
      }
      after_colon = false
    } else if c == 32 || c == 9 || c == 13 {
      self.put(i, i + 1, Text)
      i = i + 1
    } else if l.hash_comment && c == 35 && (i == 0 || hl_space(hl_cu(code, i - 1))) {
      let e = hl_line_end(code, i)
      self.put(i, e, Comment)
      i = e
    } else if l.slash_comment && hl_at(code, i, "//") {
      let e = hl_line_end(code, i)
      self.put(i, e, Comment)
      i = e
    } else if l.slash_comment && hl_at(code, i, "/*") {
      let f = hl_index(code, "*/", i + 2, n)
      let e = if f < 0 { n } else { f + 2 }
      self.put(i, e, Comment)
      i = e
    } else if l.dash_comment && hl_at(code, i, "--") {
      let e = hl_line_end(code, i)
      self.put(i, e, Comment)
      i = e
    } else if c == 34 || c == 39 || c == 96 {
      i = self.quoted(i, Str, if l.solid_quotes { Str } else { Quote }, n)
      if shell {
        command = false
      }
    } else if shell &&
      c == 36 &&
      i + 1 < n &&
      (hl_letter(hl_cu(code, i + 1)) || hl_cu(code, i + 1) == 95 || hl_cu(code, i + 1) == 123) {
      let mut j = i + 1
      if hl_cu(code, j) == 123 {
        let f = hl_index_unit(code, 125, j)
        j = if f < 0 { n } else { f + 1 }
      } else {
        while j < n && (hl_letter_or_digit(hl_cu(code, j)) || hl_cu(code, j) == 95) {
          j = j + 1
        }
      }
      self.put(i, j, Var)
      i = j
      command = false
    } else if shell &&
      c == 45 &&
      (i == 0 || hl_space(hl_cu(code, i - 1))) &&
      i + 1 < n &&
      (hl_letter(hl_cu(code, i + 1)) || hl_cu(code, i + 1) == 45) {
      let mut j = i + 1
      while j < n && !hl_space(hl_cu(code, j)) && !hl_has(";|&)=", hl_cu(code, j)) {
        j = j + 1
      }
      self.put(i, j, Constant)
      i = j
    } else if shell &&
      !command &&
      !hl_space(c) &&
      !hl_has(";|&<>()[]", c) &&
      !hl_at(code, i, "\\\n") {
      // An argument: Shiki's shell grammar draws words after the command as strings.
      let mut j = i
      while j < n &&
            !hl_space(hl_cu(code, j)) &&
            !hl_has(";|&<>()[]\"'`$", hl_cu(code, j)) {
        j = j + 1
      }
      if j == i {
        j = i + 1
      }
      let mut digits = true
      for k in i..<j {
        if !hl_digit(hl_cu(code, k)) {
          digits = false
        }
      }
      self.put(i, j, if digits { Num } else { Str })
      i = j
    } else if hl_digit(c) &&
      (i == 0 || (!hl_letter_or_digit(hl_cu(code, i - 1)) && hl_cu(code, i - 1) != 95)) {
      let m = hl_number(code, i)
      if m >= 0 {
        self.put(i, m, Num)
        i = m
      } else {
        self.put(i, i + 1, Text)
        i = i + 1
      }
    } else if hl_letter(c) ||
      c == 95 ||
      (c == 36 && !shell) ||
      (shell && command && (c == 46 || c == 47 || c == 126)) {
      let mut end = if shell && command {
        let mut e = i
        while e < n &&
              !hl_space(hl_cu(code, e)) &&
              !hl_has(";|&<>()=\"'`", hl_cu(code, e)) {
          e = e + 1
        }
        e
      } else {
        let w = hl_word(code, i)
        if w < 0 {
          i + 1
        } else {
          w
        }
      }
      // A name with the macro's bang (Rust's println!) only where the language has them.
      if l.family != Rust && end > i && hl_cu(code, end - 1) == 33 {
        end = end - 1
      }
      let word = code.view(start_offset=i, end_offset=end).to_string()
      let key = if l.caseless { word.to_lower() } else { word }
      let next_char = hl_next(code, end)
      let prev = hl_before(code, i)
      let upper = hl_upper(c)
      let scope = if shell && command && end < n && hl_cu(code, end) == 61 {
        Var
      } else if shell && command {
        if l.control.contains(key) {
          Control
        } else if l.storage.contains(key) {
          command = false
          Storage
        } else if l.builtins.contains(key) {
          command = false
          Property
        } else {
          command = false
          Func
        }
      } else if shell && prev == 61 {
        Var
      } else if l.control.contains(key) {
        Control
      } else if l.storage.contains(key) {
        Storage
      } else if l.green.contains(key) {
        Control
      } else if l.red.contains(key) {
        Storage
      } else if word == "this" || word == "self" || word == "Self" {
        Constant
      } else if fn_words.contains(previous_word) {
        Func
      } else if type_words.contains(previous_word) {
        TypeName
      } else if new_words.contains(previous_word) {
        Func
      } else if next_char == 40 || (l.family == Rust && hl_cu(code, end - 1) == 33) {
        if l.builtins.contains(key) {
          Property
        } else {
          Func
        }
      } else if l.types.contains(key) {
        TypeName
      } else if after_colon && l.family != Python && upper {
        TypeName
      } else if l.family == Kotlin && upper {
        TypeName
      } else if l.family == Ts && upper && next_char == 60 {
        TypeName
      } else if l.family == Rust && upper {
        TypeName
      } else if l.family == Rust && next_char == 58 && hl_at(code, end, "::") {
        Func
      } else if l.family == Ts &&
        next_char == 58 &&
        brackets.last() == Some(123) &&
        prev != 63 {
        Property
      } else if l.variables {
        Var
      } else {
        Text
      }
      self.put(i, end, scope)
      previous_word = key
      after_colon = false
      i = end
    } else if hl_has("([{", c) {
      brackets.push(c)
      self.put(i, i + 1, bracket_tone)
      i = i + 1
      if shell {
        command = true
      }
    } else if hl_has(")]}", c) {
      brackets.pop() |> ignore
      self.put(i, i + 1, bracket_tone)
      i = i + 1
    } else if hl_has(operators, c) || c == 58 {
      let mut j = i
      while j < n && (hl_has(operators, hl_cu(code, j)) || hl_cu(code, j) == 58) {
        j = j + 1
      }
      let op = code.view(start_offset=i, end_offset=j).to_string()
      let spaced = (i == 0 || hl_space(hl_cu(code, i - 1))) &&
        (j >= n || hl_space(hl_cu(code, j)))
      let scope = if shell {
        if op == "|" || op == "||" || op == ">" || op == ">>" || op == "<" {
          Storage
        } else {
          Punct
        }
      } else if op == "=" || op == ":=" || op == "=>" {
        Punct
      } else if op == ":" {
        if l.family == Rust {
          Storage
        } else {
          bracket_tone
        }
      } else if op == "::" || op == "->" {
        if l.family == Rust {
          Storage
        } else {
          Punct
        }
      } else if (op == "<" || op == ">") && !spaced {
        bracket_tone
      } else if op == "?" && l.plain_punct {
        Text
      } else if op == "?" && hl_next(code, j) == 58 {
        Storage
      } else {
        Storage
      }
      self.put(i, j, scope)
      after_colon = op == ":" || op == "?:" || op == "->" || op == "):"
      if shell && (op == "|" || op == "||" || op == "&&" || op == "&") {
        command = true
      }
      i = j
    } else if hl_has("{}[]();,.:", c) {
      self.put(i, i + 1, bracket_tone)
      i = i + 1
      if shell && c == 59 {
        command = true
      }
      if c == 44 {
        after_colon = false
      }
    } else {
      self.put(i, i + 1, Text)
      i = i + 1
    }
  }
}

///|
/// JSON (keys in the property colour, their quotes fainter) and TOML/INI (`key = value`).
fn Hl::data(self : Hl, json : Bool) -> Unit {
  let code = self.code
  let n = code.length()
  let mut i = 0
  while i < n {
    let c = hl_cu(code, i)
    if !json && c == 35 {
      let e = hl_line_end(code, i)
      self.put(i, e, Comment)
      i = e
    } else if json && hl_at(code, i, "//") {
      let e = hl_line_end(code, i)
      self.put(i, e, Comment)
      i = e
    } else if c == 34 || c == 39 {
      // A key: the string before a colon (JSON).
      let mut j = i + 1
      while j < n && hl_cu(code, j) != c && hl_cu(code, j) != 10 {
        j = j + (if hl_cu(code, j) == 92 { 2 } else { 1 })
      }
      let key = json && hl_next(code, j + 1) == 58
      i = if key {
        self.quoted(i, Property, PropertyQuote, n)
      } else {
        self.quoted(i, Str, Quote, n)
      }
    } else if c == 45 || hl_digit(c) {
      let m = hl_number(code, if c == 45 { i + 1 } else { i })
      if m >= 0 {
        self.put(i, m, Num)
        i = m
      } else {
        self.put(i, i + 1, Punct)
        i = i + 1
      }
    } else if hl_letter(c) || c == 95 {
      let mut j = i
      while j < n && (hl_letter_or_digit(hl_cu(code, j)) || hl_has("_-.", hl_cu(code, j))) {
        j = j + 1
      }
      let word = code.view(start_offset=i, end_offset=j).to_string()
      let scope = if data_lang.green.contains(word) {
        Control
      } else if !json && hl_next(code, j) == 61 {
        Property
      } else {
        Text
      }
      self.put(i, j, scope)
      i = j
    } else if hl_has("{}[],:=", c) {
      self.put(i, i + 1, Punct)
      i = i + 1
    } else {
      self.put(i, i + 1, Text)
      i = i + 1
    }
  }
}

///|
/// YAML: keys in the property colour; plain values are strings to Shiki.
fn Hl::yaml(self : Hl) -> Unit {
  let code = self.code
  let n = code.length()
  let mut i = 0
  while i < n {
    let e = hl_line_end(code, i)
    let mut j = i
    while j < e && (hl_cu(code, j) == 32 || hl_cu(code, j) == 9) {
      j = j + 1
    }
    self.put(i, j, Text)
    if j < e && hl_cu(code, j) == 45 && (j + 1 == e || hl_cu(code, j + 1) == 32) {
      self.put(j, j + 1, Punct)
      j = j + 1
      while j < e && hl_cu(code, j) == 32 {
        self.put(j, j + 1, Text)
        j = j + 1
      }
    }
    if j < e && hl_cu(code, j) == 35 {
      self.put(j, e, Comment)
      j = e
    }
    let k = hl_yaml_colon(code, j, e)
    if k >= 0 {
      self.put(j, k, Property)
      self.put(k, k + 1, Punct)
      j = k + 1
    }
    while j < e {
      let c = hl_cu(code, j)
      if c == 32 {
        self.put(j, j + 1, Text)
        j = j + 1
      } else if c == 35 && j > 0 && hl_cu(code, j - 1) == 32 {
        self.put(j, e, Comment)
        j = e
      } else if c == 34 || c == 39 {
        j = self.quoted(j, Str, Quote, e)
      } else {
        let f = hl_index(code, " #", j, e)
        let hash_at = if f < 0 { e } else { f }
        let value = hl_trim_end(code.view(start_offset=j, end_offset=hash_at).to_string())
        if value.length() == 0 {
          // a tab or a carriage return
          self.put(j, j + 1, Text)
          j = j + 1
        } else {
          let scope = if data_lang.green.contains(value) {
            Control
          } else if hl_number(value, 0) == value.length() {
            Num
          } else if yaml_marks.contains(value) {
            Punct
          } else {
            Str
          }
          self.put(j, j + value.length(), scope)
          j = j + value.length()
        }
      }
    }
    if e < n {
      self.put(e, e + 1, Text)
    }
    i = e + 1
  }
}

///|
/// HTML and XML: tags green, attribute names brown, values strings, the brackets grey.
fn Hl::markup(self : Hl) -> Unit {
  let code = self.code
  let n = code.length()
  let mut i = 0
  while i < n {
    if hl_at(code, i, "<!--") {
      let f = hl_index(code, "-->", i, n)
      let e = if f < 0 { n } else { f + 3 }
      self.put(i, e, Comment)
      i = e
    } else if hl_cu(code, i) == 60 {
      let mut j = i + 1
      if j < n && hl_has("/!?", hl_cu(code, j)) {
        j = j + 1
      }
      self.put(i, j, Punct)
      let mut k = j
      while k < n && (hl_letter_or_digit(hl_cu(code, k)) || hl_has("-_:.", hl_cu(code, k))) {
        k = k + 1
      }
      self.put(j, k, Control)
      i = k
      while i < n && hl_cu(code, i) != 62 {
        let c = hl_cu(code, i)
        if c == 34 || c == 39 {
          i = self.quoted(i, Str, Quote, n)
        } else if c == 61 || c == 47 || c == 63 {
          self.put(i, i + 1, Punct)
          i = i + 1
        } else if hl_space(c) {
          self.put(i, i + 1, Text)
          i = i + 1
        } else {
          let mut e = i
          while e < n && !hl_space(hl_cu(code, e)) && !hl_has("=>/\"'", hl_cu(code, e)) {
            e = e + 1
          }
          if e == i {
            e = i + 1
          }
          self.put(i, e, if i > 0 && hl_cu(code, i - 1) == 61 { Str } else { Var })
          i = e
        }
      }
      if i < n {
        self.put(i, i + 1, Punct)
        i = i + 1
      }
    } else {
      let f = hl_index_unit(code, 60, i)
      let e = if f < 0 { n } else { f }
      self.put(i, e, Text)
      i = e
    }
  }
}

///|
/// Inside a rule's braces at `i`, and not in a nested selector (a word followed by `{`).
fn hl_css_in_block(code : String, depth : Int, i : Int) -> Bool {
  if depth <= 0 {
    return false
  }
  let mut p = i
  while p < code.length() {
    let c = hl_cu(code, p)
    if c == 59 || c == 123 || c == 125 {
      return c != 123
    }
    p = p + 1
  }
  true
}

///|
/// CSS: selectors (classes brown, elements green), properties, numbers with their units red, colours as constants.
fn Hl::css(self : Hl) -> Unit {
  let code = self.code
  let n = code.length()
  let mut i = 0
  let mut depth = 0
  while i < n {
    let c = hl_cu(code, i)
    if hl_at(code, i, "/*") {
      let f = hl_index(code, "*/", i + 2, n)
      let e = if f < 0 { n } else { f + 2 }
      self.put(i, e, Comment)
      i = e
    } else if c == 34 || c == 39 {
      i = self.quoted(i, Str, Quote, n)
    } else if c == 123 {
      depth = depth + 1
      self.put(i, i + 1, Punct)
      i = i + 1
    } else if c == 125 {
      depth = if depth - 1 < 0 { 0 } else { depth - 1 }
      self.put(i, i + 1, Punct)
      i = i + 1
    } else if c == 35 && hl_css_in_block(code, depth, i) {
      let mut j = i + 1
      while j < n && hl_letter_or_digit(hl_cu(code, j)) {
        j = j + 1
      }
      self.put(i, i + 1, Punct)
      self.put(i + 1, j, Constant)
      i = j
    } else if (hl_digit(c) || (c == 46 && i + 1 < n && hl_digit(hl_cu(code, i + 1)))) &&
      hl_css_in_block(code, depth, i) {
      let mut j = i
      while j < n && (hl_digit(hl_cu(code, j)) || hl_cu(code, j) == 46) {
        j = j + 1
      }
      let mut u = j
      while u < n && (hl_letter(hl_cu(code, u)) || hl_cu(code, u) == 37) {
        u = u + 1
      }
      self.put(i, j, Num)
      self.put(j, u, Storage)
      i = u
    } else if hl_letter(c) || c == 45 || c == 95 {
      let in_block = hl_css_in_block(code, depth, i)
      let mut j = i
      while j < n && (hl_letter_or_digit(hl_cu(code, j)) || hl_has("-_", hl_cu(code, j))) {
        j = j + 1
      }
      let scope = if in_block && hl_next(code, j) == 58 {
        if hl_at(code, i, "--") {
          Var
        } else {
          Property
        }
      } else if in_block {
        Text
      } else if i > 0 && hl_has(".:#", hl_cu(code, i - 1)) {
        Var
      } else {
        // an element, or an at-rule after its `@`
        Control
      }
      self.put(i, j, scope)
      i = j
    } else if c == 62 || c == 43 || c == 126 {
      let scope = if depth == 0 || !hl_css_in_block(code, depth, i) {
        Storage
      } else {
        Punct
      }
      self.put(i, i + 1, scope)
      i = i + 1
    } else if hl_has(".:;,()@#*[]", c) {
      self.put(i, i + 1, Punct)
      i = i + 1
    } else {
      self.put(i, i + 1, Text)
      i = i + 1
    }
  }
}

///|
/// A diff as Shiki colours one: removed lines red, added green (their `---`/`+++` marks grey), a hunk's range purple
/// between grey `@@`.
fn Hl::diff(self : Hl) -> Unit {
  let code = self.code
  let n = code.length()
  let mut i = 0
  while i < n {
    let e = hl_line_end(code, i)
    if hl_at(code, i, "+++") || hl_at(code, i, "---") {
      self.put(i, i + 3, Punct)
      self.put(i + 3, e, if hl_cu(code, i) == 43 { Added } else { Removed })
    } else if hl_at(code, i, "@@") {
      let close = hl_index(code, "@@", i + 2, e)
      self.put(i, i + 2, Punct)
      if close < 0 {
        self.put(i + 2, e, Hunk)
      } else {
        self.put(i + 2, close, Hunk)
        self.put(close, close + 2, Punct)
        self.put(close + 2, e, Text)
      }
    } else if hl_at(code, i, "+") {
      self.put(i, e, Added)
    } else if hl_at(code, i, "-") {
      self.put(i, e, Removed)
    } else {
      self.put(i, e, Text)
    }
    if e < n {
      self.put(e, e + 1, Text)
    }
    i = e + 1
  }
}
