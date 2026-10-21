import assert from "node:assert/strict";
import { test } from "node:test";
import { INK_LIMIT, SCOPES, ink, inkKept, runsOf } from "../src/highlight.ts";
import { parseCall } from "../src/core/calls.ts";

type Scope = keyof typeof SCOPES;

/// `code`'s `ink` holds what `expected` says of each piece (as the Android app's Highlight.kt coloured it), where a
/// colour shows: spaces and line ends go with the run before them.
function paints(code: string, language: string, expected: [string, Scope][]) {
  assert.equal(expected.map(([t]) => t).join(""), code, "the expected pieces are the code");
  const want = expected.flatMap(([t, scope]) => [...t].map(() => SCOPES[scope]));
  const got = runsOf(code, ink(code, language) ?? "").flatMap(([t, letter]) => [...t].map(() => letter));
  const at = [...code].findIndex((c, i) => !" \t\n\r".includes(c) && got[i] !== want[i]);
  assert.equal(at, -1, `${language}: ${JSON.stringify(code.slice(at, at + 12))} is ${got[at]}, not ${want[at]} (ink ${ink(code, language)})`);
}

test("highlight_typescript_declarations_variables_calls_numbers_and_strings", () => {
  paints('const x = foo(1, "a")', "ts", [
    ["const", "storage"], [" ", "text"], ["x", "variable"], [" ", "text"], ["=", "punct"], [" ", "text"], ["foo", "func"], ["(", "punct"],
    ["1", "number"], [",", "punct"], [" ", "text"], ['"', "quote"], ["a", "string"], ['"', "quote"], [")", "punct"],
  ]);
});

test("highlight_typescript_comments_a_types_name_a_key_in_braces_a_builtin_type", () => {
  paints("// note\ninterface Foo { bar: string }", "typescript", [
    ["// note", "comment"], ["\n", "text"], ["interface", "storage"], [" ", "text"], ["Foo", "type"], [" ", "text"], ["{", "punct"], [" ", "text"],
    ["bar", "property"], [":", "punct"], [" ", "text"], ["string", "type"], [" ", "text"], ["}", "punct"],
  ]);
});

test("highlight_python_def_plain_names_none_a_comment_and_a_triple_quoted_string", () => {
  paints("def f(x):\n    return None  # done", "py", [
    ["def", "storage"], [" ", "text"], ["f", "func"], ["(", "punct"], ["x", "text"], ["):", "punct"], ["\n    ", "text"], ["return", "control"],
    [" ", "text"], ["None", "control"], ["  ", "text"], ["# done", "comment"],
  ]);
  paints('s = """a"""', "python", [["s ", "text"], ["=", "punct"], [" ", "text"], ['"""', "quote"], ["a", "string"], ['"""', "quote"]]);
});

test("highlight_kotlin_plain_punctuation_types_after_a_colon_solid_quotes", () => {
  paints("val s: String? = null", "kotlin", [["val", "control"], [" s: ", "text"], ["String", "type"], ["? ", "text"], ["=", "punct"], [" ", "text"], ["null", "storage"]]);
  paints('println("hi")', "kt", [["println", "func"], ["(", "text"], ['"hi"', "string"], [")", "text"]]);
});

test("highlight_a_shells_commands_arguments_variables_options_and_pipes", () => {
  paints('echo "hi" $HOME -n | grep x', "sh", [
    ["echo", "property"], [" ", "text"], ['"', "quote"], ["hi", "string"], ['"', "quote"], [" ", "text"], ["$HOME", "variable"], [" ", "text"],
    ["-n", "constant"], [" ", "text"], ["|", "storage"], [" ", "text"], ["grep", "func"], [" ", "text"], ["x", "string"],
  ]);
  paints("# c\nFOO=1 make 2", "bash", [
    ["# c", "comment"], ["\n", "text"], ["FOO", "variable"], ["=", "punct"], ["1", "number"], [" ", "text"], ["make", "func"], [" ", "text"], ["2", "number"],
  ]);
});

test("highlight_json_keys_numbers_and_constants", () => {
  paints('{"a": [1, -2.5e3, true, null]}', "json", [
    ["{", "punct"], ['"', "propertyQuote"], ["a", "property"], ['"', "propertyQuote"], [":", "punct"], [" ", "text"], ["[", "punct"], ["1", "number"],
    [",", "punct"], [" ", "text"], ["-2.5e3", "number"], [",", "punct"], [" ", "text"], ["true", "control"], [",", "punct"], [" ", "text"],
    ["null", "control"], ["]}", "punct"],
  ]);
});

test("highlight_yaml_keys_plain_values_items_comments_block_scalars_and_a_carriage_return", () => {
  paints("name: app\n- 3 # n\nlist: |", "yaml", [
    ["name", "property"], [":", "punct"], [" ", "text"], ["app", "string"], ["\n", "text"], ["-", "punct"], [" ", "text"], ["3", "number"],
    [" ", "text"], ["# n", "comment"], ["\n", "text"], ["list", "property"], [":", "punct"], [" ", "text"], ["|", "punct"],
  ]);
  paints('a: "x" # c', "yml", [["a", "property"], [":", "punct"], [" ", "text"], ['"', "quote"], ["x", "string"], ['"', "quote"], [" ", "text"], ["# c", "comment"]]);
  paints("k: v\r", "yaml", [["k", "property"], [":", "punct"], [" ", "text"], ["v", "string"], ["\r", "text"]]);
});

test("highlight_html_tags_attributes_values_text_and_comments", () => {
  paints('<a href="x">hi</a>', "html", [
    ["<", "punct"], ["a", "control"], [" ", "text"], ["href", "variable"], ["=", "punct"], ['"', "quote"], ["x", "string"], ['"', "quote"],
    [">", "punct"], ["hi", "text"], ["</", "punct"], ["a", "control"], [">", "punct"],
  ]);
  paints("<!-- c -->\n<br/>", "xml", [["<!-- c -->", "comment"], ["\n", "text"], ["<", "punct"], ["br", "control"], ["/>", "punct"]]);
});

test("highlight_css_selectors_properties_colours_and_numbers_with_units", () => {
  paints(".a > p { color: #fff; margin: 0 2px; }", "css", [
    [".", "punct"], ["a", "variable"], [" ", "text"], [">", "storage"], [" ", "text"], ["p", "control"], [" ", "text"], ["{", "punct"], [" ", "text"],
    ["color", "property"], [":", "punct"], [" ", "text"], ["#", "punct"], ["fff", "constant"], [";", "punct"], [" ", "text"], ["margin", "property"],
    [":", "punct"], [" ", "text"], ["0", "number"], [" ", "text"], ["2", "number"], ["px", "storage"], [";", "punct"], [" ", "text"], ["}", "punct"],
  ]);
});

test("highlight_a_diffs_files_hunk_removed_and_added_lines", () => {
  paints("--- a\n+++ b\n@@ -1 +1 @@ x\n-old\n+new\n ctx", "diff", [
    ["---", "punct"], [" a", "removed"], ["\n", "text"], ["+++", "punct"], [" b", "added"], ["\n", "text"], ["@@", "punct"], [" -1 +1 ", "range"],
    ["@@", "punct"], [" x\n", "text"], ["-old", "removed"], ["\n", "text"], ["+new", "added"], ["\n ctx", "text"],
  ]);
});

test("highlight_sql_keywords_in_any_case_builtins_and_comments", () => {
  paints("SELECT count(*) FROM t -- c", "sql", [
    ["SELECT", "control"], [" ", "text"], ["count", "property"], ["(", "punct"], ["*", "storage"], [")", "punct"], [" ", "text"], ["FROM", "control"],
    [" t ", "text"], ["-- c", "comment"],
  ]);
});

test("highlight_ink_is_short_spaces_going_with_the_run_before_them", () => {
  assert.equal(ink("const x = 1", "ts"), "h6j2c2f");
  // a language's name in any case, an unknown one read as C's family
  assert.equal(ink("const x = 1", "TS"), "h6j2c2f");
  assert.equal(ink("int x = 1;", "zig"), "h4a2c2fc");
  // text to the end is left out
  assert.equal(ink("x = 1  # n", "py"), "a2c2f3b3");
  assert.equal(ink("- a\nb", "diff"), "p4");
});

test("highlight_nothing_to_paint_in_plain_text_markdown_text_alone_or_code_past_the_limit", () => {
  for (const language of ["", "text", "plain", "txt", "plaintext", "md", "markdown", null, undefined]) assert.equal(ink("a = 1", language), null);
  assert.equal(ink("plain words", "py"), null);
  assert.equal(ink("   \n ", "ts"), null);
  assert.equal(ink("", "ts"), null);
  assert.equal(ink("1;".repeat(INK_LIMIT), "ts"), null);
});

test("highlight_runs_cover_the_code_whatever_it_is", () => {
  const samples = ['a "unclosed\n', "/* open", "`${x}` 'y", "<a b='c", ".a { b: 1", "@@ x", "$", "x\\\n y", "😀 = 1 // é", "0x 1e 1.e5"];
  for (const language of ["ts", "py", "kt", "rs", "go", "sh", "sql", "json", "yaml", "toml", "html", "css", "diff", "c"]) {
    for (const code of samples) {
      const i = ink(code, language);
      if (i === null) continue;
      assert.match(i, /^([a-q]\d*)+$/);
      assert.equal(runsOf(code, i).map(([t]) => t).join(""), code, `${language} ${JSON.stringify(code)}`);
    }
  }
});

test("highlight_code_ink_a_call_of_the_clients_kept_by_its_code", () => {
  assert.deepEqual(parseCall("code.ink", { code: "x = 1", lang: "py" }), { kind: "codeInk", code: "x = 1", lang: "py" });
  assert.deepEqual(parseCall("markdown", { text: "# a" }), { kind: "markdown", text: "# a" });
  assert.throws(() => parseCall("code.ink", { code: "x = 1" }));
  assert.equal(inkKept("x = 1", "py"), "a2c2f");
  assert.equal(inkKept("x = 1", "py"), "a2c2f");
  assert.equal(inkKept("x = 1", "text"), null);
});
