import assert from "node:assert/strict";
import { test } from "node:test";
import { markdown, parse, plainOf } from "../src/markdown.ts";

test("markdown_reads_blocks_as_html_names_them", () => {
  assert.deepEqual(parse("# 标题\n\n一段 **粗** *斜* ~~删~~ `code`\n\n---\n\n> 引用"), [
    ["h", ["标题"], { depth: 1 }],
    ["p", ["一段 ", ["b", ["粗"]], " ", ["i", ["斜"]], " ", ["s", ["删"]], " ", ["code", { content: "code" }]]],
    ["hr"],
    ["quote", [["p", ["引用"]]]],
  ]);
  assert.deepEqual(parse("```ts\nconst a = 1;\n```\n\n```\nplain\n```"), [["pre", { code: "const a = 1;", lang: "ts", ink: "h6j2c2fc" }], ["pre", { code: "plain" }]]);
});

test("markdown_a_tight_list_holds_its_words_a_loose_one_its_paragraphs", () => {
  assert.deepEqual(parse("- 一\n- 二"), [["list", [["li", ["一"]], ["li", ["二"]]]]]);
  assert.deepEqual(parse("1. 一\n\n2. 二"), [["list", [["li", [["p", ["一"]]]], ["li", [["p", ["二"]]]]], { ordered: true }]]);
  assert.deepEqual(parse("3. 三\n4. 四"), [["list", [["li", ["三"]], ["li", ["四"]]], { ordered: true, start: 3 }]]);
  assert.deepEqual(parse("- [x] 好了\n- [ ] 没好"), [["list", [["li", ["好了"], { checked: true }], ["li", ["没好"], { checked: false }]]]]);
  assert.deepEqual(parse("- 外\n  - 内"), [["list", [["li", ["外", ["list", [["li", ["内"]]]]]]]]]);
});

test("markdown_a_table_its_header_cells_then_its_rows", () => {
  assert.deepEqual(parse("| 项 | 数 |\n|:--|--:|\n| 打开 | 1ms |"), [
    ["table", [["tr", [["th", ["项"]], ["th", ["数"]]]], ["tr", [["td", ["打开"]], ["td", ["1ms"]]]]], { align: ["left", "right"] }],
  ]);
});

test("markdown_links_as_written_and_bare_addresses_where_a_reader_sees_them_end", () => {
  assert.deepEqual(parse("[PR](https://x.dev/1 \"它\") 和 <https://y.dev>"), [
    ["p", [["a", ["PR"], { href: "https://x.dev/1", title: "它" }], " 和 ", ["a", ["https://y.dev"], { href: "https://y.dev" }]]],
  ]);
  // GFM's own finding would take `）已改到` with it.
  assert.deepEqual(parse("（https://github.com/a/b/pull/2854）已改到"), [
    ["p", ["（", ["a", ["https://github.com/a/b/pull/2854"], { href: "https://github.com/a/b/pull/2854" }], "）已改到"]],
  ]);
  assert.deepEqual(parse("www.x.dev 和 a@b.dev"), [["p", ["www.x.dev 和 a@b.dev"]]]);
  // Within a link's words an address is words.
  assert.deepEqual(parse("[https://a.dev](https://b.dev)"), [["p", [["a", ["https://a.dev"], { href: "https://b.dev" }]]]]);
  assert.deepEqual(parse("看 [这里][1]，图 ![图][2]，[没有][3]\n\n[1]: https://a.dev\n[2]: shot.png \"截图\""), [
    ["p", ["看 ", ["a", ["这里"], { href: "https://a.dev" }], "，图 ", ["img", { src: "shot.png", alt: "图", title: "截图" }], "，[没有][3]"]],
  ]);
});

test("markdown_leaves_raw_html_out_and_breaks_lines_where_written", () => {
  assert.deepEqual(parse("a <b>x</b> c\n\n<div>块</div>"), [["p", ["a x c"]]]);
  assert.deepEqual(parse("一行  \n二行"), [["p", ["一行", ["br"], "二行"]]]);
});

test("markdown_is_read_once_while_it_is_kept", () => {
  const text = `只读一次 ${Math.random()}`;
  assert.equal(markdown(text), markdown(text));
  assert.deepEqual(markdown(text), parse(text));
});

test("markdown_words_without_marks", () => {
  assert.equal(plainOf(parse("# 题\n\n**一** `二`\n\n```\n三\n```")), "题\n\n一 二\n\n三");
});
