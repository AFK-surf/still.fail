// Mermaid's charts made in the engine the apps run (Hermes, no JIT) as the core makes them (mermaid.ts): the first one
// with mermaid loaded for it, then each kind again, timed, and what each came to. Bundled as the core is and run by
// Hermes's own command: apps/mbui/scripts/core.sh mermaid.
import { mermaidChart, type MermaidLook } from "../src/mermaid.ts";

declare const print: (line: string) => void;
// What the core's Hermes has and Hermes's own command has not (hosts/hermes-globals.ts): a console (what mermaid says to it
// goes), structuredClone of plain data, crypto.getRandomValues (no more than that: as the core has it).
const g = globalThis as Record<string, unknown>;
const quiet = () => {};
g.console ??= { log: quiet, info: quiet, debug: quiet, warn: quiet, error: quiet, trace: quiet };
g.structuredClone ??= (v: unknown) => (v === undefined ? v : JSON.parse(JSON.stringify(v)));
g.crypto ??= {
  getRandomValues<T extends ArrayBufferView>(buf: T): T {
    const b = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
    for (let i = 0; i < b.length; i++) b[i] = Math.floor(Math.random() * 256);
    return buf;
  },
};

const look: MermaidLook = { dark: false, background: "#ffffff", card: "#ffffff", border: "#c8c8c8", text: "#171717", line: "#737373", accent: "#f5f5f5", muted: "#f5f5f5", brand: "#ea580c" };
const CHARTS: [string, string][] = [
  ["flowchart", "flowchart TD\n  A[用户发消息] --> B{有附件吗?}\n  B -->|有| C[上传到 station]\n  B -->|没有| D[直接发送]\n  C --> E[Agent 处理]\n  D --> E"],
  ["sequence", "sequenceDiagram\n  participant App\n  participant Core\n  App->>Core: mermaid.chart\n  Core-->>App: SVG\n  Note over App,Core: 不再需要网页视图"],
  ["class", "classDiagram\n  class Animal {\n    +String name\n    +makeSound() void\n  }\n  Animal <|-- Dog\n  Animal <|-- Cat"],
  ["state", "stateDiagram-v2\n  [*] --> Idle\n  Idle --> Loading: open\n  Loading --> Shown\n  Shown --> [*]"],
  ["er", "erDiagram\n  CHAT ||--o{ MESSAGE : has\n  MESSAGE { string ts }"],
  ["gantt", "gantt\n  dateFormat YYYY-MM-DD\n  section Core\n  Shim :a1, 2026-11-01, 2d\n  Widths :a2, after a1, 3d"],
  ["pie", "pie title 时间\n  \"编译\" : 45\n  \"测试\" : 30"],
  ["mindmap", "mindmap\n  root((still.fail))\n    App\n    Core\n    Station"],
  ["journey", "journey\n  title A day\n  section Work\n    Code: 5: Me"],
  ["timeline", "timeline\n  title History\n  2025 : mbui\n  2026 : svg"],
  ["git", "gitGraph\n  commit\n  branch dev\n  commit\n  checkout main\n  merge dev"],
  ["quadrant", "quadrantChart\n  title Reach\n  x-axis Low --> High\n  y-axis Low --> High\n  A: [0.3, 0.6]"],
  ["xychart", "xychart-beta\n  x-axis [a, b, c]\n  bar [1, 3, 2]"],
];

async function main() {
  let t = Date.now();
  for (const [name, code] of CHARTS) {
    try {
      const { svg } = await mermaidChart(code, look, 600);
      print(`${name}: ${Date.now() - t} ms, ${svg.length} chars`);
    } catch (e) {
      print(`${name}: refused after ${Date.now() - t} ms: ${e instanceof Error ? e.message : String(e)}`.slice(0, 300));
    }
    t = Date.now();
  }
}
main().catch((e) => print("FAILED " + (e?.stack ?? e)));
