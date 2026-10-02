// A station's worth of TypeScript from the code ported here, to time the tools at the Rust station's size: src/admin
// copied `n` times into gen/c<k>/ (each copy its own modules) and gen/index.ts using every copy, so no bundler can
// leave one out. node scale.mjs <n>
import { cpSync, mkdirSync, rmSync, writeFileSync } from "node:fs";

const n = Number(process.argv[2]);
rmSync("gen", { recursive: true, force: true });
const lines = [];
for (let k = 1; k <= n; k++) {
  mkdirSync(`gen/c${k}`, { recursive: true });
  cpSync("src/admin", `gen/c${k}/admin`, { recursive: true });
  lines.push(`import { chats as chats${k}, entries as entries${k} } from "./c${k}/admin/views.ts";`);
}
lines.push(`export const all = [${Array.from({ length: n }, (_, i) => `[chats${i + 1}, entries${i + 1}]`).join(", ")}];`);
lines.push(`console.log(all.length);`);
writeFileSync("gen/index.ts", lines.join("\n") + "\n");
