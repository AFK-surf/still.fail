import assert from "node:assert/strict";
import test from "node:test";
import { mermaidChart, MermaidRefused, type MermaidLook } from "../src/mermaid.ts";
import { wordsWidth } from "../src/mermaidDom.ts";

const look: MermaidLook = { dark: false, background: "#ffffff", card: "#ffffff", border: "#c8c8c8", text: "#171717", line: "#737373", accent: "#f5f5f5", muted: "#f5f5f5", brand: "#ea580c" };

const viewBox = (svg: string) => /viewBox="([^"]*)"/.exec(svg)![1]!.split(/\s+/).map(Number);

test("a flowchart in Chinese and English: SVG text, laid out from where its nodes are, each label inside its box", async () => {
  const { svg, width, height } = await mermaidChart("flowchart TD\n  A[用户发消息] --> B{有附件吗?}\n  B -->|有| C[上传到 station]\n  B -->|没有| D[直接发送]", look, 600);
  assert(!svg.includes("<foreignObject"), "no HTML in it");
  assert(svg.includes("用户发消息") && svg.includes("station"));
  // where its drawing begins, as a browser has it: empty labels (an edge's with no words) take no room
  const [x, y, w, h] = viewBox(svg);
  assert.equal(x, 0);
  assert.equal(y, 0);
  assert(w! > 100 && h! > 200, `${w}x${h}`);
  assert.deepEqual([width, height], [w, h], "its size as its viewBox says");
  // a node's box is wider than its words as the app sets them
  const box = /<rect[^>]*width="([\d.]+)"[^>]*class="basic label-container"/.exec(svg);
  assert(box, "a node's box");
  assert(Number(box[1]) > wordsWidth("用户发消息", 14, false), `${box[1]} wide`);
  // on the ground asked, the first thing drawn
  assert.match(svg, /^<svg[^>]*><rect x="0" y="0" width="[\d.]+" height="[\d.]+" fill="#ffffff"\/>/);
});

test("words measured as Inter sets them; Chinese a square each", () => {
  assert.equal(wordsWidth("中文", 14, false), 28);
  assert(wordsWidth("Wide", 14, true) > wordsWidth("Wide", 14, false));
  assert(Math.abs(wordsWidth("A", 2048, false) - 1413) < 1, "Inter's A at 400");
});

test("a sequence diagram and a gantt (which fills the width asked)", async () => {
  const { svg: seq } = await mermaidChart("sequenceDiagram\n  App->>Core: mermaid.chart\n  Core-->>App: SVG", look, 600);
  assert(seq.includes("mermaid.chart"));
  const gantt = await mermaidChart("gantt\n  dateFormat YYYY-MM-DD\n  section A\n  One :a1, 2026-11-01, 2d", look, 500);
  assert.equal(gantt.width, 500);
});

test("what mermaid does not read is refused, and kept refused", async () => {
  await assert.rejects(mermaidChart("flowchart TD\n  A --> ", look, 600), MermaidRefused);
  await assert.rejects(mermaidChart("not a chart at all", look, 600), MermaidRefused);
  // a chart after a refused one is made as ever
  assert((await mermaidChart("flowchart LR\n  A --> B", look, 600)).svg.includes("<svg"));
});

test("a mindmap (laid out by cytoscape, its hidden box sized as a browser has it) and a journey: SVG text, no HTML", async () => {
  const mindmap = await mermaidChart("mindmap\n  root((still.fail))\n    App\n    Core\n    Station", look, 600);
  assert(mindmap.width > 100 && mindmap.height > 100, `${mindmap.width}x${mindmap.height}`);
  assert(!mindmap.svg.includes("<foreignObject") && mindmap.svg.includes("Station"));
  // nothing of it left going (cytoscape's frames)
  assert.deepEqual(process.getActiveResourcesInfo().filter((r) => r === "Timeout"), []);
  const journey = await mermaidChart("journey\n  title A day\n  section Work\n    Code: 5: Me", look, 600);
  assert(!journey.svg.includes("<foreignObject") && journey.svg.includes("Code"));
});
