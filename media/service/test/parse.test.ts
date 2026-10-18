// Reading books (src/html.ts, epub.ts, txt.ts, zip.ts, images.ts): XHTML to blocks, EPUB structure and tables of
// contents, plain text's encodings and chapters, and how a chapter's offsets are counted (blocks.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { blockChars, chapterChars, type Block } from "../src/blocks.ts";
import { parseEpub, resolve } from "../src/epub.ts";
import { decode, toBlocks } from "../src/html.ts";
import { sniff } from "../src/images.ts";
import { parseBook } from "../src/importer.ts";
import { decodeText, headingOf, parseTxt } from "../src/txt.ts";
import { readZip, unzip } from "../src/zip.ts";
import { epub2, epub3, gb18030, jpeg, png, zip } from "./helpers.ts";

const none = () => null;

test("entities: named, decimal, hex; unknown ones left as they are", () => {
  assert.equal(decode("&amp;&lt;&gt;&quot;&apos;&nbsp;&hellip;&#20013;&#x6587;&#X1F600;&nosuch;"), "&<>\"' …中文😀&nosuch;");
});

test("XHTML to blocks: paragraphs, runs, ruby, headings, rules, line breaks; white space as HTML collapses it", () => {
  const blocks = toBlocks(
    `<html><head><title>不要</title><style>p{}</style></head><body>
      <h2>标题 <b>一</b></h2>
      <p>　　缩进的
         段落，跨行。</p>
      <p>Hello   <b>bold</b> <i>it</i> <a href="x.html#a">link</a>!</p>
      <p><strong>全部粗体</strong></p>
      <p><ruby>東京<rt>とうきょう</rt></ruby>へ</p>
      <div>a<br>b<br/><br/>c</div>
      <hr>
      <p><a id="anchor">no href</a></p>
      <!-- <p>comment</p> -->
      <p><![CDATA[x<y]]></p>
      <script>alert("no")</script>
    </body></html>`,
    none,
  );
  assert.deepEqual(blocks, [
    { t: "h", level: 2, text: "标题 一" },
    { t: "p", text: "缩进的段落，跨行。" },
    { t: "p", runs: [{ text: "Hello " }, { text: "bold", b: true }, { text: " " }, { text: "it", i: true }, { text: " " }, { text: "link", href: "x.html#a" }, { text: "!" }] },
    { t: "p", runs: [{ text: "全部粗体", b: true }] },
    { t: "p", runs: [{ text: "東京", ruby: "とうきょう" }, { text: "へ" }] },
    { t: "p", text: "a" },
    { t: "p", text: "b" },
    { t: "p", text: "c" },
    { t: "hr" },
    { t: "p", text: "no href" },
    { t: "p", text: "x<y" },
  ]);
});

test("XHTML to blocks: images (img, svg image) resolved, unknown ones dropped, tolerant of broken markup", () => {
  const seen: string[] = [];
  const blocks = toBlocks(
    `<body><p>before<img src="a.png"/>after</p><svg><text>no</text><image xlink:href="b.jpg" /></svg><img src="missing.gif"><p unclosed>tail <b>bold`,
    (src) => {
      seen.push(src);
      return src === "missing.gif" ? null : { ref: `r-${src}`, w: 4, h: 3 };
    },
  );
  assert.deepEqual(seen, ["a.png", "b.jpg", "missing.gif"]);
  assert.deepEqual(blocks, [
    { t: "p", text: "before" },
    { t: "img", ref: "r-a.png", w: 4, h: 3 },
    { t: "p", text: "after" },
    { t: "img", ref: "r-b.jpg", w: 4, h: 3 },
    { t: "p", runs: [{ text: "tail " }, { text: "bold", b: true }] },
  ]);
});

test("offsets: a block's chars are its text's UTF-16 length (ruby readings not counted); img and hr count 1", () => {
  const blocks: Block[] = [
    { t: "h", level: 1, text: "第一章" },
    { t: "p", text: "😀ab" },
    { t: "p", runs: [{ text: "漢", ruby: "かん" }, { text: "字", ruby: "じ" }, { text: "x", b: true }] },
    { t: "img", ref: "r" },
    { t: "hr" },
  ];
  assert.deepEqual(blocks.map(blockChars), [3, 4, 3, 1, 1]);
  assert.equal(chapterChars(blocks), 12);
});

test("images: PNG, JPEG, GIF, WebP sizes from their headers; SVG by its text", () => {
  assert.deepEqual(sniff(png(320, 240), ""), { type: "image/png", w: 320, h: 240 });
  assert.deepEqual(sniff(jpeg(600, 800), ""), { type: "image/jpeg", w: 600, h: 800 });
  const gif = Buffer.from("GIF89a\x05\x00\x07\x00\x00\x00\x00", "latin1");
  assert.deepEqual(sniff(gif, ""), { type: "image/gif", w: 5, h: 7 });
  const vp8x = Buffer.alloc(30);
  vp8x.write("RIFF", 0, "latin1");
  vp8x.write("WEBPVP8X", 8, "latin1");
  vp8x.writeUIntLE(99, 24, 3);
  vp8x.writeUIntLE(49, 27, 3);
  assert.deepEqual(sniff(vp8x, ""), { type: "image/webp", w: 100, h: 50 });
  assert.deepEqual(sniff(Buffer.from(`<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>`), ""), { type: "image/svg+xml" });
  assert.deepEqual(sniff(Buffer.from("????"), "image/x-thing"), { type: "image/x-thing" });
});

test("zip: entries stored and deflated read back; names in UTF-8", () => {
  const z = zip([
    { name: "a.txt", data: "stored", stored: true },
    { name: "目录/b.txt", data: "deflated ".repeat(100) },
  ]);
  const entries = readZip(z);
  assert.deepEqual([...entries.keys()], ["a.txt", "目录/b.txt"]);
  assert.equal(unzip(z, entries.get("a.txt")!).toString(), "stored");
  assert.equal(unzip(z, entries.get("目录/b.txt")!).toString(), "deflated ".repeat(100));
});

test("EPUB paths: relative to the file naming them, %-escapes and fragments", () => {
  assert.equal(resolve("OEBPS/text/ch1.xhtml", "../images/pic%201.png#x"), "OEBPS/images/pic 1.png");
  assert.equal(resolve("content.opf", "a.html"), "a.html");
  assert.equal(resolve("OEBPS/content.opf", "/abs/x.png"), "abs/x.png");
});

test("EPUB 3: metadata, spine order, nav titles and levels, cover, images by content, empty files left out", () => {
  const book = parseEpub(epub3(), "x.epub");
  assert.equal(book.title, "测试之书");
  assert.equal(book.author, "张三、李四");
  assert.equal(book.format, "epub");
  const toc = book.chapters.map((c) => [c.title, c.level, chapterChars(c.blocks)]);
  assert.deepEqual(toc, [
    ["封面", 1, 1],
    ["第一章 开始", 1, 54],
    ["第二部", 1, 8],
  ]);
  const [cover, ch1, ch2] = book.chapters;
  assert.equal(cover!.blocks.length, 1);
  const coverImg = cover!.blocks[0] as { t: "img"; ref: string; w: number; h: number };
  assert.deepEqual([coverImg.t, coverImg.w, coverImg.h], ["img", 600, 800]);
  assert.equal(book.cover, coverImg.ref, "the cover image is the one the cover page shows");
  assert.equal(book.images.get(coverImg.ref)!.type, "image/jpeg");
  const blocks = ch1!.blocks;
  assert.deepEqual(blocks[0], { t: "h", level: 1, text: "第一章　开始" });
  assert.deepEqual(blocks[1], { t: "p", text: "他说：“你好，世界。”" });
  assert.deepEqual(blocks[2], {
    t: "p",
    runs: [{ text: "这是" }, { text: "粗体", b: true }, { text: "和" }, { text: "斜体", i: true }, { text: "，还有" }, { text: "链接", href: "https://example.com/x" }, { text: "。" }],
  });
  assert.deepEqual(blocks[3], { t: "p", runs: [{ text: "漢", ruby: "かん" }, { text: "字", ruby: "じ" }, { text: "を読む" }] });
  assert.deepEqual(blocks.slice(4, 6), [{ t: "p", text: "第一行" }, { t: "p", text: "第二行" }]);
  assert.deepEqual(blocks[6], { t: "hr" });
  const pic = blocks[7] as { t: "img"; ref: string; w: number; h: number };
  assert.deepEqual([pic.t, pic.w, pic.h], ["img", 320, 240]);
  assert.equal(book.images.get(pic.ref)!.type, "image/png");
  assert.deepEqual(blocks[8], { t: "p", text: "A & B < C ©" });
  assert.equal(blocks.length, 9, "the script and the empty paragraph are not text");
  assert.deepEqual(ch2!.blocks, [{ t: "h", level: 2, text: "第二部" }, { t: "p", text: "最后一段。" }]);
  assert.equal(book.images.size, 2);
});

test("EPUB 2: toc.ncx titles and levels, a chapter it does not name titled by its heading, <meta name=cover>", () => {
  const book = parseEpub(epub2(), "old.epub");
  assert.equal(book.title, "Old Book");
  assert.equal(book.author, "Ann Author");
  assert.deepEqual(book.chapters.map((c) => [c.title, c.level]), [["Part One", 1], ["Chapter 1", 2], ["Unnamed & found", 1]]);
  assert.deepEqual(book.chapters[1]!.blocks, [
    { t: "h", level: 3, text: "B heading" },
    { t: "p", runs: [{ text: "Some " }, { text: "bold ", b: true }, { text: "both", b: true, i: true }, { text: " text." }] },
  ]);
  assert.ok(book.cover);
  assert.equal(book.images.get(book.cover!)!.type, "image/png");
});

test("EPUB: DRM-encrypted content is refused; a broken zip is a 400", () => {
  const locked = zip([
    { name: "mimetype", data: "application/epub+zip", stored: true },
    { name: "META-INF/container.xml", data: `<container><rootfiles><rootfile full-path="c.opf"/></rootfiles></container>` },
    { name: "META-INF/encryption.xml", data: `<encryption><EncryptedData><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/><CipherData><CipherReference URI="a.html"/></CipherData></EncryptedData></encryption>` },
    { name: "c.opf", data: `<package><manifest><item id="a" href="a.html" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>` },
    { name: "a.html", data: "garbage" },
  ]);
  assert.throws(() => parseEpub(locked, "l.epub"), (e: any) => e.status === 415);
  assert.throws(() => parseBook(Buffer.from("PK\x03\x04 not really", "latin1"), "b.epub"), (e: any) => e.status === 400);
});

test("formats: MOBI by its header or name is 415; other binary is 415", () => {
  const mobi = Buffer.alloc(100);
  mobi.write("BOOKMOBI", 60, "latin1");
  assert.throws(() => parseBook(mobi, "book.bin"), (e: any) => e.status === 415 && /MOBI/.test(e.message));
  assert.throws(() => parseBook(Buffer.from("text"), "book.azw3"), (e: any) => e.status === 415);
  assert.throws(() => parseBook(Buffer.from([0, 1, 2, 3]), "x.bin"), (e: any) => e.status === 415);
});

const NOVEL = "书名：测试\n作者：王五\n\n第一章 风起\n　　第一段。\n　　第二段。\r\n\r\n第二章 云涌\n内容。\n";

test("TXT encodings: UTF-8 (with and without BOM), UTF-16 by BOM, else GB18030", () => {
  assert.equal(decodeText(Buffer.from(`﻿${NOVEL}`, "utf8")), NOVEL);
  assert.equal(decodeText(Buffer.from(NOVEL, "utf8")), NOVEL);
  assert.equal(decodeText(Buffer.from(`﻿${NOVEL}`, "utf16le")), NOVEL);
  const be = Buffer.from(`﻿${NOVEL}`, "utf16le").swap16();
  assert.equal(decodeText(be), NOVEL);
  assert.equal(decodeText(gb18030(NOVEL)), NOVEL);
});

test("TXT chapters: text before the first heading is 前言, headings start chapters, full-width indents dropped", () => {
  const book = parseTxt(NOVEL, "《测试》全本.txt");
  assert.equal(book.title, "测试");
  assert.equal(book.author, "王五");
  assert.deepEqual(book.chapters, [
    { title: "前言", level: 1, blocks: [{ t: "p", text: "书名：测试" }, { t: "p", text: "作者：王五" }] },
    { title: "第一章 风起", level: 1, blocks: [{ t: "h", level: 1, text: "第一章 风起" }, { t: "p", text: "第一段。" }, { t: "p", text: "第二段。" }] },
    { title: "第二章 云涌", level: 1, blocks: [{ t: "h", level: 1, text: "第二章 云涌" }, { t: "p", text: "内容。" }] },
  ]);
  assert.equal(parseTxt("第一章\n正文", "a.txt").chapters.length, 1, "no 前言 when nothing comes before");
});

test("TXT headings: Chinese numerals, digits, 回/节/卷, Chapter N; not a sentence that starts like one", () => {
  for (const h of ["第一章", "第十二章 名字", "第123章：数字", "第１２章", "第三回 回目", "第五节", "第一卷 天", "Chapter 7", "CHAPTER IV: The End", "楔子"]) {
    assert.ok(headingOf(h), h);
  }
  for (const p of ["第一章的时候他还小", "第一个人走了", "Chapters are long", "他在第一章里写道"]) assert.equal(headingOf(p), null, p);
  assert.equal(headingOf("第一卷 天")!.volume, true);
});

test("TXT: a list of chapters at the top is not chapters; volumes are level 1 over their chapters", () => {
  const listed = parseTxt("目录\n第一章 甲\n第二章 乙\n第一章 甲\n正文一\n第二章 乙\n正文二", "a.txt");
  assert.deepEqual(listed.chapters.map((c) => c.title), ["前言", "第一章 甲", "第二章 乙"]);
  const volumes = parseTxt("第一卷 天\n第一章 a\nx\n第二章 b\ny", "v.txt");
  assert.deepEqual(volumes.chapters.map((c) => [c.title, c.level]), [["第一卷 天", 1], ["第一章 a", 2], ["第二章 b", 2]]);
  const english = parseTxt("Chapter 1\nHello\nChapter 2: Next\nWorld", "e.txt");
  assert.deepEqual(english.chapters.map((c) => c.title), ["Chapter 1", "Chapter 2: Next"]);
});

test("TXT without headings: parts of about 20 000 characters, split between paragraphs", () => {
  const para = "字".repeat(1000);
  const book = parseTxt(Array.from({ length: 30 }, () => para).join("\n"), "long.txt");
  assert.deepEqual(book.chapters.map((c) => [c.title, chapterChars(c.blocks)]), [["第 1 部分", 20_000], ["第 2 部分", 10_000]]);
});
