import assert from "node:assert/strict";
import { test } from "node:test";
import { markdown, parse, plainOf } from "../src/markdown.ts";
import { wordsIn } from "./md-words.ts";

/// The tree of `text` with its runs read out of it, as a client draws it.
// Syntax/source contracts are independent of the derived drawing, checked below and in math.test.ts.
const withoutDrawing = <T,>(value: T): T => JSON.parse(JSON.stringify(value, (key, v: unknown) => key === "drawing" ? undefined : v)) as T;
const read = (text: string) => withoutDrawing(wordsIn(parse(text), text));

test("markdown_reads_blocks_as_html_names_them", () => {
  assert.deepEqual(read("# 标题\n\n一段 **粗** *斜* ~~删~~ `code`\n\n---\n\n> 引用"), [
    ["h", ["标题"], { depth: 1 }],
    ["p", ["一段 ", ["b", ["粗"]], " ", ["i", ["斜"]], " ", ["s", ["删"]], " ", ["code", { content: "code" }]]],
    ["hr"],
    ["quote", [["p", ["引用"]]]],
  ]);
  assert.deepEqual(read("```ts\nconst a = 1;\n```\n\n```\nplain\n```"), [["pre", { code: "const a = 1;", lang: "ts", ink: "h6j2c2fc" }], ["pre", { code: "plain" }]]);
});

test("markdown_a_tight_list_holds_its_words_a_loose_one_its_paragraphs", () => {
  assert.deepEqual(read("- 一\n- 二"), [["list", [["li", ["一"]], ["li", ["二"]]]]]);
  assert.deepEqual(read("1. 一\n\n2. 二"), [["list", [["li", [["p", ["一"]]]], ["li", [["p", ["二"]]]]], { ordered: true }]]);
  assert.deepEqual(read("3. 三\n4. 四"), [["list", [["li", ["三"]], ["li", ["四"]]], { ordered: true, start: 3 }]]);
  assert.deepEqual(read("- [x] 好了\n- [ ] 没好"), [["list", [["li", ["好了"], { checked: true }], ["li", ["没好"], { checked: false }]]]]);
  assert.deepEqual(read("- 外\n  - 内"), [["list", [["li", ["外", ["list", [["li", ["内"]]]]]]]]]);
});

test("markdown_a_table_its_header_cells_then_its_rows", () => {
  assert.deepEqual(read("| 项 | 数 |\n|:--|--:|\n| 打开 | 1ms |"), [
    ["table", [["tr", [["th", ["项"]], ["th", ["数"]]]], ["tr", [["td", ["打开"]], ["td", ["1ms"]]]]], { align: ["left", "right"] }],
  ]);
});

test("markdown_links_as_written_and_bare_addresses_where_a_reader_sees_them_end", () => {
  assert.deepEqual(read("[PR](https://x.dev/1 \"它\") 和 <https://y.dev>"), [
    ["p", [["a", ["PR"], { href: "https://x.dev/1", title: "它" }], " 和 ", ["a", ["https://y.dev"], { href: "https://y.dev" }]]],
  ]);
  // GFM's own finding would take `）已改到` with it.
  assert.deepEqual(read("（https://github.com/a/b/pull/2854）已改到"), [
    ["p", ["（", ["a", ["https://github.com/a/b/pull/2854"], { href: "https://github.com/a/b/pull/2854" }], "）已改到"]],
  ]);
  assert.deepEqual(read("www.x.dev 和 a@b.dev"), [["p", ["www.x.dev 和 a@b.dev"]]]);
  // Within a link's words an address is words.
  assert.deepEqual(read("[https://a.dev](https://b.dev)"), [["p", [["a", ["https://a.dev"], { href: "https://b.dev" }]]]]);
  assert.deepEqual(read("看 [这里][1]，图 ![图][2]，[没有][3]\n\n[1]: https://a.dev\n[2]: shot.png \"截图\""), [
    ["p", ["看 ", ["a", ["这里"], { href: "https://a.dev" }], "，图 ", ["img", { src: "shot.png", alt: "图", title: "截图" }], "，[没有][3]"]],
  ]);
});

test("markdown_leaves_raw_html_out_and_breaks_lines_where_written", () => {
  assert.deepEqual(read("a <b>x</b> c\n\n<div>块</div>"), [["p", ["a ", "x", " c"]]]);
  assert.deepEqual(read("一行  \n二行"), [["p", ["一行", ["br"], "二行"]]]);
});

test("markdown_is_read_once_while_it_is_kept", () => {
  const text = `只读一次 ${Math.random()}`;
  assert.equal(markdown(text), markdown(text));
  assert.deepEqual(markdown(text), parse(text));
});

test("math_is_code_with_a_rendering_hint_and_keeps_its_source_runs", () => {
  const text = "预测 $p_7 = p_1 + r$。\n\n$$\n\\frac{y_7-y_1}{y_1}\n$$";
  assert.deepEqual(read(text), [
    ["p", ["预测 ", ["code", { content: "p_7 = p_1 + r", math: true }], "。"]],
    ["pre", { code: "\\frac{y_7-y_1}{y_1}", math: true }],
  ]);
  assert.equal(plainOf(parse(text), text), "预测 p_7 = p_1 + r。\n\n\\frac{y_7-y_1}{y_1}");
  assert.deepEqual(withoutDrawing(parse("中 $x$")), [["p", [[0, 2], ["code", { content: [3, 4], math: true }]]]]);
  // A dollar inside TeX must not be mistaken for the opening delimiter.
  assert.deepEqual(read("值 $$ $ $$"), [["p", ["值 ", ["code", { content: "$", math: true }]]]]);
  assert.deepEqual(read("$$\n\\sum_{i=1}^n x_i\n$$"), [["pre", { code: "\\sum_{i=1}^n x_i", math: true }]]);
});

test("math_leaves_escaped_dollars_code_and_unmatched_inline_delimiters_alone", () => {
  assert.deepEqual(read("费用 \\$5 和 \\$10；未完 $x"), [["p", ["费用 $5 和 $10；未完 $x"]]]);
  assert.deepEqual(read("`$x$`\n\n```tex\n$$x$$\n```"), [
    ["p", [["code", { content: "$x$" }]]],
    ["pre", { code: "$$x$$", lang: "tex" }],
  ]);
  assert.deepEqual(read("| 预测 |\n|---|\n| $x^2$ |"), [
    ["table", [["tr", [["th", ["预测"]]]], ["tr", [["td", [["code", { content: "x^2", math: true }]]]]]], { align: [null] }],
  ]);
});

test("markdown_words_without_marks", () => {
  const text = "# 题\n\n**一** `二`\n\n```\n三\n```";
  assert.equal(plainOf(parse(text), text), "题\n\n一 二\n\n三");
});

test("markdown_words_are_runs_of_the_text_so_they_go_once", () => {
  assert.deepEqual(parse("一段 **粗** `c`\n\n```ts\nx = 1\n```"), [
    ["p", [[0, 3], ["b", [[5, 6]]], [8, 9], ["code", { content: [10, 11] }]]],
    ["pre", { code: [20, 25], lang: "ts", ink: "j2c2f" }],
  ]);
  // what reading changed: its own words
  assert.deepEqual(parse("a\\*b &amp; c"), [["p", ["a*b & c"]]]);
  assert.deepEqual(parse("    indented\n    code"), [["pre", { code: "indented\ncode" }]]);
  // a fence's language that its code starts with is not taken for its code
  assert.deepEqual(parse("```x\nx\n```"), [["pre", { code: [5, 6], lang: "x" }]]);
  // an agent's words: the tree is a small part of them
  const words = Array.from({ length: 12 }, (_, i) => `第 ${i} 段：station 上的任务已经跑完，测试全部通过，结果在 \`out/report-${i}.md\`，见 https://still.fail/c/${i}。`).join("\n\n");
  const tree = Buffer.byteLength(JSON.stringify(parse(words)));
  const read = Buffer.byteLength(JSON.stringify(wordsIn(parse(words), words)));
  assert.ok(tree < Buffer.byteLength(words) && tree < read, `${tree} bytes beside ${Buffer.byteLength(words)} of words; ${read} with them`);
});


test("core markdown includes the formula layout while copying keeps the TeX source", () => {
  const text = "中 $x^2$\n\n$$\n\\frac{1}{2}\n$$";
  const trees = markdown(text);
  const seen: Record<string, unknown>[] = [];
  const walk = (value: unknown): void => {
    if (Array.isArray(value)) value.forEach(walk);
    else if (value && typeof value === "object") {
      const attrs = value as Record<string, unknown>;
      if (attrs.math === true) seen.push(attrs);
    }
  };
  walk(trees);
  assert.equal(seen.length, 2);
  for (const attrs of seen) {
    const d = attrs.drawing as { font: string; draw: unknown[]; width: number };
    assert.equal(d.font, "tex-4.1.3");
    assert(d.draw.length > 0 && d.width > 0);
    assert(!("paths" in d));
  }
  assert.equal(plainOf(trees, text), "中 x^2\n\n\\frac{1}{2}");
});
