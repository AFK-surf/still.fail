import assert from "node:assert/strict";
import { test } from "node:test";
import { parse } from "../src/markdown.ts";
import { mdHead, mdLines, textHead, textLines } from "../src/mdHead.ts";

test("mdHead_words_that_may_fill_fewer_lines_are_whole", () => {
  assert.equal(mdHead(parse("一段\n\n- 一\n- 二\n\n```\na\nb\n```"), 8), null);
  assert.equal(mdHead(parse("字".repeat(500)), 8), null);
  assert.equal(textHead("一行\n两行", 8), null);
});

test("mdHead_keeps_the_blocks_that_fill_the_lines_and_no_more", () => {
  const md = parse(Array.from({ length: 20 }, (_, i) => `第 ${i} 段`).join("\n\n"));
  assert.deepEqual(mdHead(md, 8), md.slice(0, 8));
  // The blocks kept are the tree's own: a view draws again only what changed.
  assert.equal(mdHead(md, 8)![0], md[0]);
});

test("mdHead_cuts_within_a_long_paragraph_a_list_a_code_block_and_a_table", () => {
  assert.deepEqual(mdHead(parse("a".repeat(5000)), 8), [["p", ["a".repeat(8 * 160)]]]);
  assert.deepEqual(mdHead(parse("字".repeat(5000)), 8), [["p", ["字".repeat(8 * 80)]]]);
  const list = mdHead(parse(Array.from({ length: 30 }, (_, i) => `- 项 ${i}`).join("\n")), 8)!;
  assert.equal((list[0] as [string, unknown[]])[1].length, 8);
  assert.deepEqual(mdHead(parse("```ts\n" + Array.from({ length: 40 }, (_, i) => `line ${i}`).join("\n") + "\n```"), 3), [["pre", { code: "line 0\nline 1\nline 2", lang: "ts" }]]);
  const table = mdHead(parse("| a |\n|--|\n" + Array.from({ length: 30 }, (_, i) => `| ${i} |`).join("\n")), 8)!;
  assert.equal((table[0] as [string, unknown[], unknown])[1].length, 8);
  assert.deepEqual((table[0] as [string, unknown[], unknown])[2], { align: [null] });
});

test("mdHead_a_chart_whole_and_what_follows_it_left", () => {
  const chart = "```mermaid\n" + Array.from({ length: 40 }, (_, i) => `a${i} --> b${i}`).join("\n") + "\n```";
  const md = parse(`${chart}\n\n后面`);
  assert.deepEqual(mdHead(md, 8), [md[0]]);
});

test("textHead_the_first_lines_of_plain_words", () => {
  assert.equal(textHead(Array.from({ length: 30 }, (_, i) => `行 ${i}`).join("\n"), 3), "行 0\n行 1\n行 2");
  assert.equal(textHead("a".repeat(5000), 2), "a".repeat(320));
  assert.equal(textHead("a\nb\nc", 3), null);
});

test("mdLines_the_least_lines_words_fill_at_a_width_no_further_than_asked", () => {
  assert.equal(mdLines(parse("一行"), 70, 5), 1);
  assert.equal(mdLines(parse("a".repeat(150)), 70, 5), 3);
  assert.equal(mdLines(parse("- 一\n- 二\n\n后面"), 70, 5), 3);
  assert.equal(mdLines(parse("a".repeat(5000)), 70, 5), 5);
  assert.equal(textLines("一行\n两行", 70, 5), 2);
  assert.equal(textLines("a".repeat(5000), 70, 5), 5);
});
