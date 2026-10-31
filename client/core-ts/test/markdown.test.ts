import assert from "node:assert/strict";
import { test } from "node:test";
import { createHash } from "node:crypto";
import { MD_READING, type MdStore, lineOf, markdown, mdKey, parse, plainOf } from "../src/markdown.ts";
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

test("markdown_reads_emphasis_next_to_cjk_punctuation_and_words", () => {
  // The two bold spans from an agent's reply must not merge when the first ends with a Chinese full stop.
  assert.deepEqual(read("- **原因还没有官方定论。**有实验显示，**额度扣得更快**，但样本有限。"), [
    ["list", [["li", [["b", ["原因还没有官方定论。"]], "有实验显示，", ["b", ["额度扣得更快"]], "，但样本有限。"]]]],
  ]);
  assert.deepEqual(read("前面**“强调。”**后面"), [["p", ["前面", ["b", ["“强调。”"]], "后面"]]]);
  assert.deepEqual(read("前面*「斜体。」*后面"), [["p", ["前面", ["i", ["「斜体。」"]], "后面"]]]);
  assert.deepEqual(read("前面~~「删除。」~~后面"), [["p", ["前面", ["s", ["「删除。」"]], "后面"]]]);
  assert.deepEqual(read("前面**`代码`**后面"), [["p", ["前面", ["b", [["code", { content: "代码" }]]], "后面"]]]);
  assert.deepEqual(read("**この文です。**次の文。"), [["p", [["b", ["この文です。"]], "次の文。"]]]);
  assert.deepEqual(read("**이 용어(term)**를 강조"), [["p", [["b", ["이 용어(term)"]], "를 강조"]]]);
  // The same marks in code stay literal, as does an English-only case under CommonMark's usual rules.
  assert.deepEqual(read("`**原文。**继续`"), [["p", [["code", { content: "**原文。**继续" }]]]]);
  assert.deepEqual(read("**words.**next"), [["p", ["**words.**next"]]]);
});

test("markdown_an_inline_code_or_a_link_naming_a_file_says_its_path_its_line_and_a_chips_words", () => {
  assert.deepEqual(read("见 `src/a.ts:12`，`npm test` 不是，[说明](docs/notes.md#L3)"), [
    ["p", [
      "见 ",
      ["code", { content: "src/a.ts:12", path: "src/a.ts", line: 12 }],
      "，",
      ["code", { content: "npm test" }],
      " 不是，",
      ["a", ["说明"], { href: "docs/notes.md#L3", path: "docs/notes.md", line: 3 }],
    ]],
  ]);
  // a home directory as ~, a long one cut in its middle
  const [[, [code]]] = read("`/Users/lin/projects/shop/apps/web/src/components/list/Row.tsx`") as [[string, [[string, Record<string, unknown>]]]];
  assert.equal(code[1].shown, "~/projects/…/list/Row.tsx");
});

test("markdown_a_tight_list_holds_its_words_a_loose_one_its_paragraphs", () => {
  assert.deepEqual(read("- 一\n- 二"), [["list", [["li", ["一"]], ["li", ["二"]]]]]);
  assert.deepEqual(read("1. 一\n\n2. 二"), [["list", [["li", [["p", ["一"]]]], ["li", [["p", ["二"]]]]], { ordered: true }]]);
  assert.deepEqual(read("3. 三\n4. 四"), [["list", [["li", ["三"]], ["li", ["四"]]], { ordered: true, start: 3 }]]);
  assert.deepEqual(read("- [x] 好了\n- [ ] 没好"), [["list", [["li", ["好了"], { checked: true }], ["li", ["没好"], { checked: false }]]]]);
  assert.deepEqual(read("- 外\n  - 内"), [["list", [["li", ["外", ["list", [["li", ["内"]]]]]]]]]);
});

test("markdown_strikes_through_with_one_tilde_or_two_as_github_does_and_not_three", () => {
  assert.deepEqual(read("~一~ 和 ~~二~~ 和 ~~~三~~~"), [["p", [["s", ["一"]], " 和 ", ["s", ["二"]], " 和 ~~~三~~~"]]]);
  // a run closes one of as many
  assert.deepEqual(read("~~不~ 配"), [["p", ["~~不~ 配"]]]);
  assert.deepEqual(read("3~5 天"), [["p", ["3~5 天"]]]);
});

test("markdown_a_task_is_a_list_item_whose_words_begin_with_its_box", () => {
  assert.deepEqual(read("- [x] 好了\n- [ ]\n  下一行\n- [ ]\n- [x]没空格"), [
    ["list", [["li", ["好了"], { checked: true }], ["li", ["下一行"], { checked: false }], ["li", ["[ ]"]], ["li", ["[x]没空格"]]]],
  ]);
});

test("markdown_a_table_its_header_cells_then_its_rows", () => {
  assert.deepEqual(read("| 项 | 数 |\n|:--|--:|\n| 打开 | 1ms |"), [
    ["table", [["tr", [["th", ["项"]], ["th", ["数"]]]], ["tr", [["td", ["打开"]], ["td", ["1ms"]]]]], {
      align: ["left", "right"], md: "| 项 | 数 |\n| :-- | --: |\n| 打开 | 1ms |", csv: "项,数\n打开,1ms",
    }],
  ]);
});

test("markdown_a_table_says_itself_as_markdown_and_as_csv_to_copy", () => {
  // In a quote, its cells as written (a bar in one escaped, in code too, as GitHub reads it); its words as CSV, an image
  // by its words or else its address.
  const text = "> | 名 | 说明 | 数 |\n> |:-:|---|--:|\n> | **粗** | a, \"b\" | \\| 竖线 |\n> | [链接](https://x.dev) | ![图](a.png) ![](b.png) | `x\\|y` |\n> | 少一格 |";
  const [[, [table]]] = read(text) as [[string, [[string, unknown[], { md: string; csv: string }]]]];
  assert.equal(table[2].md, [
    "| 名 | 说明 | 数 |",
    "| :-: | --- | --: |",
    "| **粗** | a, \"b\" | \\| 竖线 |",
    "| [链接](https://x.dev) | ![图](a.png) ![](b.png) | `x\\|y` |",
    "| 少一格 |  |  |",
  ].join("\n"));
  assert.equal(table[2].csv, ["名,说明,数", "粗,\"a, \"\"b\"\"\",| 竖线", "链接,图 b.png,x|y", "少一格,,"].join("\n"));
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

test("markdown_is_read_once_on_the_device_where_its_tree_is_kept", () => {
  const kept = new Map<string, string>();
  const puts: string[] = [];
  const store: MdStore = { has: (k) => kept.has(k), get: (k) => kept.get(k) ?? null, put: (k, json) => (puts.push(k), kept.set(k, json)) };
  // Read the first time: kept.
  const text = `第一次 **读** ${Math.random()}`;
  assert.deepEqual(markdown(text, store), parse(text));
  assert.deepEqual(puts, [mdKey(text)]);
  assert.equal(kept.get(mdKey(text)), JSON.stringify(parse(text)));
  // One kept on the device (read by a core before) is what it shows, not read again; nothing kept again.
  const other = `读过了 ${Math.random()}`;
  kept.set(mdKey(other), JSON.stringify([["p", ["已读的树"]]]));
  assert.deepEqual(markdown(other, store), [["p", ["已读的树"]]]);
  assert.equal(puts.length, 1);
  // One that is no tree: read afresh, kept again.
  const broken = `坏的 ${Math.random()}`;
  kept.set(mdKey(broken), "{");
  assert.deepEqual(markdown(broken, store), parse(broken));
  assert.equal(kept.get(mdKey(broken)), JSON.stringify(parse(broken)));
  // A reply kept by the previous reader is read again, so corrections apply to messages already on the device.
  const old = `**旧消息。**后面 ${Math.random()}`;
  const oldKey = mdKey(old).replace(/^\d+\./, `${MD_READING - 1}.`);
  kept.set(oldKey, JSON.stringify([["p", ["old reading"]]]));
  assert.deepEqual(markdown(old, store), parse(old));
  assert.equal(kept.get(mdKey(old)), JSON.stringify(parse(old)));
  // The key: the reading, the length, then the text's hashes.
  assert.ok(mdKey("ab").startsWith(`${MD_READING}.2.`));
  assert.notEqual(mdKey("ab"), mdKey("ba"));
});

test("markdown_kept_on_the_device_is_read_as_this_reading_reads_it_or_its_reading_says_otherwise", () => {
  // What these are read as, as a digest: changed, the trees kept on devices by cores before are not this reading's
  // (MD_READING one more in markdown.ts, so they are read afresh), and this with it.
  const texts = [
    "# 标题\n\n一段 **粗** *斜* ~~删~~ `code`，[链接](https://x.dev \"它\") 和 https://y.dev/a?b=1。\n\n---\n\n> 引用\n> - 列表",
    "- 一\n- 二\n  - 内\n\n1. 一\n\n2. 二\n\n- [x] 好了\n- [ ] 没好",
    "| 项 | 数 |\n|:--|--:|\n| 打开 | 1ms |\n| 读 | \\| 竖线 |",
    "```ts\nconst a: number = 1; // 注释\nexport function f() { return `x${a}`; }\n```\n\n```sh\necho \"$HOME\" && ls -la\n```\n\n```\nplain\n```",
    "行内 $x^2 + y_1$ 和 \\(\\frac{a}{b}\\)，\n\n$$\n\\sum_{i=0}^{n} i = \\frac{n(n+1)}{2}\n$$\n\n\\[ e^{i\\pi} + 1 = 0 \\]\n\n价格 $5 和 $10",
    "<b>不要</b> 原样\n第二行  \n硬换行 &amp; &lt; &#x4e2d;\n\n![图](a.png \"标题\") [引用][r]\n\n[r]: https://r.dev",
    "前面**“强调。”**后面，*斜体。*继续，~~删除。~~继续。",
  ];
  const digest = createHash("sha256").update(JSON.stringify(texts.map(parse))).digest("hex").slice(0, 16);
  assert.equal(`${MD_READING}:${digest}`, "6:ebb30f81510c7bf3", "what Markdown is read as changed: MD_READING one more (markdown.ts) and this digest with it");
});

test("a_link_or_picture_alone_on_its_line_is_a_paragraph_of_its_own_with_no_blank_line_round_it", () => {
  // a file's link written on a line of its own, its words on the next: placed, not a link within a sentence
  assert.deepEqual(read("**看图**\n[cmp.mp4](https://x.dev/cmp.mp4)\n图离放大后的位置有多远就走多久。"), [
    ["p", [["b", ["看图"]]]],
    ["p", [["a", ["cmp.mp4"], { href: "https://x.dev/cmp.mp4" }]]],
    ["p", ["图离放大后的位置有多远就走多久。"]],
  ]);
  assert.deepEqual(read("前一行\n![](shot.png)"), [["p", ["前一行"]], ["p", [["img", { src: "shot.png" }]]]]);
  // within a line, or lines of words alone: as Markdown has them
  assert.deepEqual(read("看 [这里](https://x.dev) 吧\n第二行"), [["p", ["看 ", ["a", ["这里"], { href: "https://x.dev" }], " 吧\n第二行"]]]);
  assert.deepEqual(read("一\n二"), [["p", ["一\n二"]]]);
});

test("math_is_code_with_a_rendering_hint_and_keeps_its_source_runs", () => {
  const text = "预测 \\(p_7 = p_1 + r\\)。\n\n$$\n\\frac{y_7-y_1}{y_1}\n$$";
  assert.deepEqual(read(text), [
    ["p", ["预测 ", ["code", { content: "p_7 = p_1 + r", math: true }], "。"]],
    ["pre", { code: "\\frac{y_7-y_1}{y_1}", math: true }],
  ]);
  assert.equal(plainOf(parse(text), text), "预测 p_7 = p_1 + r。\n\n\\frac{y_7-y_1}{y_1}");
  assert.deepEqual(withoutDrawing(parse("中 \\(x\\)")), [["p", [[0, 2], ["code", { content: [4, 5], math: true }]]]]);
  // A dollar inside TeX must not be mistaken for the opening delimiter.
  assert.deepEqual(read("值 \\(\\$\\)"), [["p", ["值 ", ["code", { content: "\\$", math: true }]]]]);
  assert.deepEqual(read("$$\n\\sum_{i=1}^n x_i\n$$"), [["pre", { code: "\\sum_{i=1}^n x_i", math: true }]]);
});

test("math_leaves_escaped_dollars_code_and_unmatched_inline_delimiters_alone", () => {
  assert.deepEqual(read("费用 \\$5 和 \\$10；未完 $x"), [["p", ["费用 $5 和 $10；未完 $x"]]]);
  assert.deepEqual(read("`$x$`\n\n```tex\n$$x$$\n```"), [
    ["p", [["code", { content: "$x$" }]]],
    ["pre", { code: "$$x$$", lang: "tex" }],
  ]);
  assert.deepEqual(read("| 预测 |\n|---|\n| \\(x^2\\) |"), [
    ["table", [["tr", [["th", ["预测"]]]], ["tr", [["td", [["code", { content: "x^2", math: true }]]]]]], { align: [null], md: "| 预测 |\n| --- |\n| \\(x^2\\) |", csv: "预测\nx^2" }],
  ]);
});

test("markdown_words_without_marks", () => {
  const text = "# 题\n\n**一** `二`\n\n```\n三\n```";
  assert.equal(plainOf(parse(text), text), "题\n\n一 二\n\n三");
});

test("markdown_line_is_its_first_words_without_marks", () => {
  const line = (text: string) => lineOf(parse(text), text);
  assert.equal(line("**Planning the fix**\n\nI will read [the list](https://a.b/c) first."), "Planning the fix");
  assert.equal(line("## 总结\n\n改好了"), "总结");
  assert.equal(line("- **一** 改了 `list.mbt`\n- 二"), "一 改了 list.mbt");
  assert.equal(line("1. 第一\n\n   第二段\n2. 二"), "第一");
  assert.equal(line("> 引用的 *话*\n\n后面"), "引用的 话");
  assert.equal(line("```\n\nerror: no display\nmore\n```"), "error: no display");
  assert.equal(line("| 名 | 值 |\n|---|---|\n| a | 1 |"), "名 | 值");
  assert.equal(line("---\n\n第二块"), "第二块");
  assert.equal(line(""), "");
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
  // an agent's words: the tree carries none of them, only where they are (a file's path too: a run), so it is less
  // than they are with it, and about as big as they are (each path it marks a few bytes more: where it is)
  const words = Array.from({ length: 12 }, (_, i) => `第 ${i} 段：station 上的任务已经跑完，测试全部通过，结果在 \`out/report-${i}.md\`，见 https://still.fail/c/${i}。`).join("\n\n");
  const json = JSON.stringify(parse(words));
  const tree = Buffer.byteLength(json);
  const read = Buffer.byteLength(JSON.stringify(wordsIn(parse(words), words)));
  assert.ok(!json.includes("report-") && !json.includes("任务"), json);
  assert.ok(tree < read && tree < Buffer.byteLength(words) * 1.2, `${tree} bytes beside ${Buffer.byteLength(words)} of words; ${read} with them`);
});


test("core markdown includes the formula layout while copying keeps the TeX source", () => {
  const text = "中 \\(x^2\\)\n\n$$\n\\frac{1}{2}\n$$";
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

test("formula delimiters leave dollar amounts and shell variables as prose", () => {
  for (const text of ["$5 and $10", "$5/月，$10/月", "$100–$200", "$HOME and $PATH", "$x^2$", "inline $$x^2$$"])
    assert.deepEqual(read(text), [["p", [text]]]);
});

test("bracket display math uses the same block as dollar fences, including containers", () => {
  const code = "\\frac{1}{2}";
  const want = [["pre", { code, math: true }]];
  for (const text of [`\\[${code}\\]`, `\\[\n${code}\n\\]`, `\\[\r\n${code}\r\n\\]`, `$$\n${code}\n$$`])
    assert.deepEqual(read(text), want);
  assert.deepEqual(read(`> \\[\n> ${code}\n> \\]`), [["quote", want]]);
  assert.deepEqual(read(`- \\[\n  ${code}\n  \\]`), [["list", [["li", want]]]]);
  assert.deepEqual(read(`before\n\\[${code}\\]\nafter`), [["p", ["before"]], ...want, ["p", ["after"]]]);
  assert.deepEqual(withoutDrawing(parse("\\[x\\]")), [["pre", { code: [2, 3], math: true }]]);
});

test("bracket math respects code, escaped delimiters, TeX escapes and missing closers", () => {
  assert.deepEqual(read("`\\(x\\)` and `\\[x\\]`"), [["p", [["code", { content: "\\(x\\)" }], " and ", ["code", { content: "\\[x\\]" }]]]]);
  assert.deepEqual(read("```\n\\[x\\]\n```"), [["pre", { code: "\\[x\\]" }]]);
  assert.deepEqual(read(String.raw`\\(x\\)`), [["p", [String.raw`\(x\)`]]]);
  assert.deepEqual(read(String.raw`\(x\\) + y\)`), [["p", [["code", { content: String.raw`x\\) + y`, math: true }]]]]);
  assert.deepEqual(read(String.raw`未完成 \(x`), [["p", ["未完成 (x"]]]);
  assert.deepEqual(read("\\[\nx"), [["p", ["[\nx"]]]);
  assert.deepEqual(read(String.raw`\(x\]`), [["p", ["(x]"]]]);
  assert.deepEqual(read("\\(x\\) 与 \\(y\\)"), [["p", [["code", { content: "x", math: true }], " 与 ", ["code", { content: "y", math: true }]]]]);
});

test("unclosed display math cannot consume text outside its quote or list", () => {
  assert.deepEqual(read("> \\[\n> x\n\n# 正文标题\n\\]"), [
    ["quote", [["p", ["[\nx"]]]], ["h", ["正文标题"], { depth: 1 }], ["p", ["]"]],
  ]);
  assert.deepEqual(read("- \\[\n  x\n\n正文\n\\]"), [
    ["list", [["li", ["[\nx"]]]], ["p", ["正文\n]"]],
  ]);
  // Without a blank line, ordinary Markdown may continue the paragraph lazily,
  // but a closing delimiter outside the container must not complete a formula.
  assert.deepEqual(read("> \\[\n> x\n\\]"), [["quote", [["p", ["[\nx\n]"]]]]]);
  assert.deepEqual(read("- \\[\n  x\n\\]"), [["list", [["li", ["[\nx\n]"]]]]]);
});
