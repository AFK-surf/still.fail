import assert from "node:assert/strict";
import { test } from "node:test";
import { book, findChapters, headingLines, keepBook, keptBook, markdownChapters, reflow, search, searchBook, wrapWidth } from "../src/reader.ts";

test("reader_chapters_strict_and_a_stray_title_only_far_from_the_last", () => {
  const text = "序章\n很久以前的事。\n第一章 车站\n他到了。\n第 12 节\n又一节。\nChapter 3 The Key\nwords.\n正文 第三卷 回程\n";
  const marks = findChapters(text, false);
  assert.deepEqual(marks.map((m) => m.title), ["序章", "第一章 车站", "第 12 节", "Chapter 3 The Key", "正文 第三卷 回程"]);
  assert.equal(marks[1]!.offset, text.indexOf("第一章"));
  // a sentence that starts with 第 is none
  assert.equal(findChapters("第一次见到他的时候，天已经黑了，路上一个人也没有。\n", false).length, 0);
  // the heading lines a client does not indent
  assert.deepEqual(headingLines("第一章 车站\n  他到了。\n"), [0]);
});

test("reader_a_hard_wrapped_text_is_joined_into_paragraphs_a_heading_its_own", () => {
  const line = "这一行正好二十五个字这一行正好二十五个字这一行正好二";
  const lines: string[] = [];
  for (let i = 0; i < 14; i++) lines.push(i % 4 === 3 ? "结束了。" : line);
  const text = "第一章 开头\n" + lines.join("\n");
  const wrap = wrapWidth(text);
  assert.equal(wrap, line.length);
  const flowed = reflow(text, wrap, new Set(findChapters(text, false).map((c) => c.offset)));
  const paras = flowed.split("\n");
  assert.equal(paras[0], "第一章 开头");
  assert.equal(paras[1], line + line + line + "结束了。");
  // a paragraph a line is left alone
  assert.equal(wrapWidth("短的一行。\n另一行，长一点点的。\n"), 0);
  // a book does both, and finds its chapters again in what it joined
  const b = book(text.replace(/\n/g, "\r\n"), false);
  assert.equal(b.wrapped, line.length);
  assert.equal(b.text, flowed);
  assert.deepEqual(b.chapters.map((c) => c.title), ["第一章 开头"]);
});

test("reader_markdown_is_never_joined_its_chapters_its_headings_as_its_tree_reads_them", () => {
  const md = "# 一\n```\n# 不是\n```\n## 二 **粗**\n#### 太深\n\n标题\n===\n";
  assert.deepEqual(markdownChapters(md), [
    { title: "一", offset: 0 },
    { title: "二 粗", offset: md.indexOf("## 二") },
    { title: "标题", offset: md.indexOf("标题") },
  ]);
  const text = "# 标题\n" + "一行写得很长很长很长很长很长很长很长很长很长。\n".repeat(20);
  const b = book(text, true);
  assert.equal(b.wrapped, 0);
  assert.equal(b.text, text);
  assert.deepEqual(b.chapters, [{ title: "标题", offset: 0 }]);
  assert.deepEqual(b.heads, []);
  assert.equal(b.md?.[0]?.[0], "h");
  assert.equal(book(text, false).md, null);
});

test("reader_a_markdown_book_searched_in_its_words_as_drawn_told_where_they_stand", () => {
  const text = "# 钥匙\n\n**钥**匙在 [这里](https://example.com/钥匙)。\n\n| a | 钥匙 |\n|---|---|\n| `钥匙` | b |\n";
  const b = book(text, true);
  const at = searchBook(b, "钥匙");
  // the heading's, the one its bold splits, the table's head's and its code's: not the link's address
  assert.equal(at.length, 4);
  assert.deepEqual(at.map((i) => text.slice(i, i + 1)), ["钥", "钥", "钥", "钥"]);
  assert.equal(at[1], text.indexOf("**钥") + 2);
  // a plain book's search is its text's
  assert.deepEqual(searchBook(book("钥匙 **钥匙**", false), "钥匙"), [0, 5]);
});

test("reader_search_every_place_letters_without_case_when_nothing_else", () => {
  assert.deepEqual(search("钥匙在这里，钥匙也在那里", "钥匙"), [0, 6]);
  assert.deepEqual(search("Key and KEY", "key"), [0, 8]);
  assert.deepEqual(search("Key and key", "key"), [8]);
  assert.deepEqual(search("text", ""), []);
});

test("reader_books_kept_by_their_id_the_latest_three", () => {
  const ids = [1, 2, 3, 4].map((i) => keepBook(`第${i}本\n`, false).id);
  assert.equal(keptBook(ids[0]!), undefined);
  assert.equal(keptBook(ids[3]!)!.text, "第4本\n");
});
