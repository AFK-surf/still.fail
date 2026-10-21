import assert from "node:assert/strict";
import { test } from "node:test";
import { type Md, parse } from "../src/markdown.ts";
import { mdHead as head, mdLines as linesOf, textHead, textLines } from "../src/mdHead.ts";
import { wordsIn } from "./md-words.ts";

// The text each tree was read from, by the tree: these read them as the clients do.
const read = new WeakMap<Md, string>();
const md = (text: string): Md => {
  const tree = parse(text);
  read.set(tree, text);
  return tree;
};
const mdHead = (tree: Md, lines: number) => {
  const cut = head(tree, read.get(tree)!, lines);
  return cut === null ? null : wordsIn(cut, read.get(tree)!);
};
const mdLines = (tree: Md, per: number, most: number) => linesOf(tree, read.get(tree)!, per, most);

test("mdHead_words_that_may_fill_fewer_lines_are_whole", () => {
  assert.equal(mdHead(md("一段\n\n- 一\n- 二\n\n```\na\nb\n```"), 8), null);
  assert.equal(mdHead(md("字".repeat(500)), 8), null);
  assert.equal(textHead("一行\n两行", 8), null);
});

test("mdHead_keeps_the_blocks_that_fill_the_lines_and_no_more", () => {
  const text = Array.from({ length: 20 }, (_, i) => `第 ${i} 段`).join("\n\n");
  const tree = md(text);
  assert.deepEqual(mdHead(tree, 8), wordsIn(tree.slice(0, 8), text));
  // The blocks kept are the tree's own: a view draws again only what changed.
  assert.equal(head(tree, text, 8)![0], tree[0]);
});

test("mdHead_cuts_within_a_long_paragraph_a_list_a_code_block_and_a_table", () => {
  assert.deepEqual(mdHead(md("a".repeat(5000)), 8), [["p", ["a".repeat(8 * 160)]]]);
  assert.deepEqual(mdHead(md("字".repeat(5000)), 8), [["p", ["字".repeat(8 * 80)]]]);
  const list = mdHead(md(Array.from({ length: 30 }, (_, i) => `- 项 ${i}`).join("\n")), 8)!;
  assert.equal((list[0] as [string, unknown[]])[1].length, 8);
  assert.deepEqual(mdHead(md("```ts\n" + Array.from({ length: 40 }, (_, i) => `line ${i}`).join("\n") + "\n```"), 3), [["pre", { code: "line 0\nline 1\nline 2", lang: "ts", ink: "j5f2j5f2j5f" }]]);
  const table = mdHead(md("| a |\n|--|\n" + Array.from({ length: 30 }, (_, i) => `| ${i} |`).join("\n")), 8)!;
  assert.equal((table[0] as [string, unknown[], unknown])[1].length, 8);
  assert.deepEqual((table[0] as [string, unknown[], unknown])[2], { align: [null] });
});

test("mdHead_a_chart_whole_and_what_follows_it_left", () => {
  const chart = "```mermaid\n" + Array.from({ length: 40 }, (_, i) => `a${i} --> b${i}`).join("\n") + "\n```";
  const tree = md(`${chart}\n\n后面`);
  assert.deepEqual(head(tree, `${chart}\n\n后面`, 8), [tree[0]]);
});

test("textHead_the_first_lines_of_plain_words", () => {
  assert.equal(textHead(Array.from({ length: 30 }, (_, i) => `行 ${i}`).join("\n"), 3), "行 0\n行 1\n行 2");
  assert.equal(textHead("a".repeat(5000), 2), "a".repeat(320));
  assert.equal(textHead("a\nb\nc", 3), null);
});

test("mdLines_the_least_lines_words_fill_at_a_width_no_further_than_asked", () => {
  assert.equal(mdLines(md("一行"), 70, 5), 1);
  assert.equal(mdLines(md("a".repeat(150)), 70, 5), 3);
  assert.equal(mdLines(md("- 一\n- 二\n\n后面"), 70, 5), 3);
  assert.equal(mdLines(md("a".repeat(5000)), 70, 5), 5);
  assert.equal(textLines("一行\n两行", 70, 5), 2);
  assert.equal(textLines("a".repeat(5000), 70, 5), 5);
});
