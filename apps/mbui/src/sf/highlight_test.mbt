// vitesse-light's colours, as highlight gives them

///|
let hl_text : Int64 = 0x393A34FFL

///|
let hl_comment : Int64 = 0xA0ADA0FFL

///|
let hl_punct : Int64 = 0x999999FFL

///|
let hl_string : Int64 = 0xB56959FFL

///|
let hl_quote : Int64 = 0xB5695977L

///|
let hl_number : Int64 = 0x2F798AFFL

///|
let hl_control : Int64 = 0x1E754FFFL

///|
let hl_storage : Int64 = 0xAB5959FFL

///|
let hl_function : Int64 = 0x59873AFFL

///|
let hl_variable : Int64 = 0xB07D48FFL

///|
let hl_constant : Int64 = 0xA65E2BFFL

///|
let hl_type : Int64 = 0x2E8F82FFL

///|
let hl_property : Int64 = 0x998418FFL

///|
let hl_property_quote : Int64 = 0x99841877L

///|
let hl_added : Int64 = 0x22863AFFL

///|
let hl_removed : Int64 = 0xB31D28FFL

///|
let hl_range : Int64 = 0x6F42C1FFL

///|
/// The runs of `code` in `language` (light), as text and colour.
fn hl_runs(code : String, language : String) -> Array[(String, Int64)] {
  @sf.highlight(code, language, false).unwrap().map(fn(r) { (r.text, r.color) })
}

///|
test "highlight: TypeScript's declarations, variables, calls, numbers and strings" {
  assert_eq(hl_runs("const x = foo(1, \"a\")", "ts"), [
    ("const", hl_storage),
    (" ", hl_text),
    ("x", hl_variable),
    (" ", hl_text),
    ("=", hl_punct),
    (" ", hl_text),
    ("foo", hl_function),
    ("(", hl_punct),
    ("1", hl_number),
    (",", hl_punct),
    (" ", hl_text),
    ("\"", hl_quote),
    ("a", hl_string),
    ("\"", hl_quote),
    (")", hl_punct),
  ])
  // every run in the code face, with a colour of its own
  for r in @sf.highlight("const x = foo(1, \"a\")", "ts", false).unwrap() {
    assert_true(r.mono)
    assert_true(r.color != 0L)
  }
}

///|
test "highlight: TypeScript's comments, a type's name, a key in braces, a builtin type" {
  assert_eq(hl_runs("// note\ninterface Foo { bar: string }", "typescript"), [
    ("// note", hl_comment),
    ("\n", hl_text),
    ("interface", hl_storage),
    (" ", hl_text),
    ("Foo", hl_type),
    (" ", hl_text),
    ("{", hl_punct),
    (" ", hl_text),
    ("bar", hl_property),
    (":", hl_punct),
    (" ", hl_text),
    ("string", hl_type),
    (" ", hl_text),
    ("}", hl_punct),
  ])
}

///|
test "highlight: Python's def, plain names, None, a comment and a triple-quoted string" {
  assert_eq(hl_runs("def f(x):\n    return None  # done", "py"), [
    ("def", hl_storage),
    (" ", hl_text),
    ("f", hl_function),
    ("(", hl_punct),
    ("x", hl_text),
    ("):", hl_punct),
    ("\n    ", hl_text),
    ("return", hl_control),
    (" ", hl_text),
    ("None", hl_control),
    ("  ", hl_text),
    ("# done", hl_comment),
  ])
  assert_eq(hl_runs("s = \"\"\"a\"\"\"", "python"), [
    ("s ", hl_text),
    ("=", hl_punct),
    (" ", hl_text),
    ("\"\"\"", hl_quote),
    ("a", hl_string),
    ("\"\"\"", hl_quote),
  ])
}

///|
test "highlight: Kotlin's plain punctuation, types after a colon, solid quotes" {
  assert_eq(hl_runs("val s: String? = null", "kotlin"), [
    ("val", hl_control),
    (" s: ", hl_text),
    ("String", hl_type),
    ("? ", hl_text),
    ("=", hl_punct),
    (" ", hl_text),
    ("null", hl_storage),
  ])
  assert_eq(hl_runs("println(\"hi\")", "kt"), [
    ("println", hl_function),
    ("(", hl_text),
    ("\"hi\"", hl_string),
    (")", hl_text),
  ])
}

///|
test "highlight: a shell's commands, arguments, variables, options and pipes" {
  assert_eq(hl_runs("echo \"hi\" $HOME -n | grep x", "sh"), [
    ("echo", hl_property),
    (" ", hl_text),
    ("\"", hl_quote),
    ("hi", hl_string),
    ("\"", hl_quote),
    (" ", hl_text),
    ("$HOME", hl_variable),
    (" ", hl_text),
    ("-n", hl_constant),
    (" ", hl_text),
    ("|", hl_storage),
    (" ", hl_text),
    ("grep", hl_function),
    (" ", hl_text),
    ("x", hl_string),
  ])
}

///|
test "highlight: a shell's comments, assignments and numeric arguments" {
  assert_eq(hl_runs("# c\nFOO=1 make 2", "bash"), [
    ("# c", hl_comment),
    ("\n", hl_text),
    ("FOO", hl_variable),
    ("=", hl_punct),
    ("1", hl_number),
    (" ", hl_text),
    ("make", hl_function),
    (" ", hl_text),
    ("2", hl_number),
  ])
}

///|
test "highlight: JSON's keys, numbers and constants" {
  assert_eq(hl_runs("{\"a\": [1, -2.5e3, true, null]}", "json"), [
    ("{", hl_punct),
    ("\"", hl_property_quote),
    ("a", hl_property),
    ("\"", hl_property_quote),
    (":", hl_punct),
    (" ", hl_text),
    ("[", hl_punct),
    ("1", hl_number),
    (",", hl_punct),
    (" ", hl_text),
    ("-2.5e3", hl_number),
    (",", hl_punct),
    (" ", hl_text),
    ("true", hl_control),
    (",", hl_punct),
    (" ", hl_text),
    ("null", hl_control),
    ("]}", hl_punct),
  ])
}

///|
test "highlight: YAML's keys, plain values, items, comments and block scalars" {
  assert_eq(hl_runs("name: app\n- 3 # n\nlist: |", "yaml"), [
    ("name", hl_property),
    (":", hl_punct),
    (" ", hl_text),
    ("app", hl_string),
    ("\n", hl_text),
    ("-", hl_punct),
    (" ", hl_text),
    ("3", hl_number),
    (" ", hl_text),
    ("# n", hl_comment),
    ("\n", hl_text),
    ("list", hl_property),
    (":", hl_punct),
    (" ", hl_text),
    ("|", hl_punct),
  ])
}

///|
test "highlight: YAML's quoted values, and a line ending in a carriage return" {
  assert_eq(hl_runs("a: \"x\" # c", "yml"), [
    ("a", hl_property),
    (":", hl_punct),
    (" ", hl_text),
    ("\"", hl_quote),
    ("x", hl_string),
    ("\"", hl_quote),
    (" ", hl_text),
    ("# c", hl_comment),
  ])
  assert_eq(hl_runs("k: v\r", "yaml"), [
    ("k", hl_property),
    (":", hl_punct),
    (" ", hl_text),
    ("v", hl_string),
    ("\r", hl_text),
  ])
}

///|
test "highlight: HTML's tags, attributes, values, text and comments" {
  assert_eq(hl_runs("<a href=\"x\">hi</a>", "html"), [
    ("<", hl_punct),
    ("a", hl_control),
    (" ", hl_text),
    ("href", hl_variable),
    ("=", hl_punct),
    ("\"", hl_quote),
    ("x", hl_string),
    ("\"", hl_quote),
    (">", hl_punct),
    ("hi", hl_text),
    ("</", hl_punct),
    ("a", hl_control),
    (">", hl_punct),
  ])
  assert_eq(hl_runs("<!-- c -->\n<br/>", "xml"), [
    ("<!-- c -->", hl_comment),
    ("\n", hl_text),
    ("<", hl_punct),
    ("br", hl_control),
    ("/>", hl_punct),
  ])
}

///|
test "highlight: CSS's selectors, properties, colours and numbers with units" {
  assert_eq(hl_runs(".a > p { color: #fff; margin: 0 2px; }", "css"), [
    (".", hl_punct),
    ("a", hl_variable),
    (" ", hl_text),
    (">", hl_storage),
    (" ", hl_text),
    ("p", hl_control),
    (" ", hl_text),
    ("{", hl_punct),
    (" ", hl_text),
    ("color", hl_property),
    (":", hl_punct),
    (" ", hl_text),
    ("#", hl_punct),
    ("fff", hl_constant),
    (";", hl_punct),
    (" ", hl_text),
    ("margin", hl_property),
    (":", hl_punct),
    (" ", hl_text),
    ("0", hl_number),
    (" ", hl_text),
    ("2", hl_number),
    ("px", hl_storage),
    (";", hl_punct),
    (" ", hl_text),
    ("}", hl_punct),
  ])
}

///|
test "highlight: a diff's files, hunk, removed and added lines" {
  assert_eq(hl_runs("--- a\n+++ b\n@@ -1 +1 @@ x\n-old\n+new\n ctx", "diff"), [
    ("---", hl_punct),
    (" a", hl_removed),
    ("\n", hl_text),
    ("+++", hl_punct),
    (" b", hl_added),
    ("\n", hl_text),
    ("@@", hl_punct),
    (" -1 +1 ", hl_range),
    ("@@", hl_punct),
    (" x\n", hl_text),
    ("-old", hl_removed),
    ("\n", hl_text),
    ("+new", hl_added),
    ("\n ctx", hl_text),
  ])
}

///|
test "highlight: SQL's keywords in any case, builtins and comments" {
  assert_eq(hl_runs("SELECT count(*) FROM t -- c", "sql"), [
    ("SELECT", hl_control),
    (" ", hl_text),
    ("count", hl_property),
    ("(", hl_punct),
    ("*", hl_storage),
    (")", hl_punct),
    (" ", hl_text),
    ("FROM", hl_control),
    (" t ", hl_text),
    ("-- c", hl_comment),
  ])
}

///|
test "highlight: dark takes each colour's vitesse-dark twin" {
  let runs = @sf.highlight("x = 1", "js", true).unwrap().map(fn(r) { (r.text, r.color) })
  assert_eq(runs, [
    ("x", 0xBD976AFFL),
    (" ", 0xDBD7CAEEL),
    ("=", 0x666666FFL),
    (" ", 0xDBD7CAEEL),
    ("1", 0x4C9A91FFL),
  ])
}

///|
test "highlight: plain text is not coloured; Markdown is one run in the text colour" {
  assert_true(@sf.highlight("a = 1", "text", false) is None)
  assert_true(@sf.highlight("a = 1", "", false) is None)
  assert_true(@sf.highlight("a = 1", "plaintext", true) is None)
  assert_eq(hl_runs("# a\n*b*", "md"), [("# a\n*b*", hl_text)])
}
