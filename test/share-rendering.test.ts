import assert from "node:assert/strict";
import { test } from "node:test";
import { markdown } from "../client/core-ts/src/markdown.ts";
import { ink } from "../client/core-ts/src/highlight.ts";
import { core } from "../web/src/share/stand-ins/core/react.ts";

const examples = [
  "# 标题\n\n**粗体** *斜体* ~~删除~~ `行内代码`\n\n> 引用\n\n---",
  "| 项目 | 数量 |\n|:---|---:|\n| 表格 | 42 |",
  "1. 有序\n   - 嵌套\n\n- [x] 完成\n- [ ] 未完成",
  "```ts\nconst answer = 42; // 注释\n```",
  String.raw`行内 \(x^2\)，块级：` + "\n\n$$\n\\frac{a}{b}\n$$",
  "[文档](https://example.com) https://example.com/path\n\n[附件](report.md)\n\n![图片](image.png)",
  "```mermaid\ngraph LR\n A --> B\n```",
  '<script>alert(1)</script>\n\n[unsafe](javascript:alert%281%29)',
];

test("share messages and file previews use the core's complete Markdown trees", async () => {
  for (const text of examples) {
    const answer = await core().call("markdown", { text });
    assert.deepEqual(answer, { md: markdown(text) });
    assert.notDeepEqual(answer, { md: [["p", [text]]] }, "must not fall back to unparsed text");
  }
});

test("share code uses the core's colours, including unknown languages and empty input", async () => {
  for (const [code, lang] of [["const x = 42;", "ts"], ["print('hi')", "python"], ["words", "unknown"], ["", "ts"]]) {
    assert.deepEqual(await core().call("code.ink", { code, lang }), { ink: ink(code!, lang!) });
  }
});

test("a share visitor has no account, station or binary core operations", async () => {
  for (const method of ["screen.view", "station.call", "reader.book", "markdown", "code.ink"]) {
    await assert.rejects(core().call(method, {}), /no core on the share page/);
  }
  await assert.rejects(core().callBytes("anything"), /no core on the share page/);
});
