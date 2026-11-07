// Markdown as agents write it, for the benches (chat-open.ts, md-parse.ts): this repository's docs cut at blank lines
// into parts of 600 to 3 000 characters (paragraphs, lists, tables, code), the same every run.
import { readFileSync } from "node:fs";
import { join } from "node:path";

export function replies(): string[] {
  const root = join(import.meta.dirname, "..", "..", "..");
  const files = ["docs/development.md", "docs/operations.md", "docs/release-signing.md", "apps/mbui/docs/media.md", "apps/mbui/docs/figures.md", "apps/mbui/docs/perf-record.md"];
  const out: string[] = [];
  for (const f of files) {
    let text: string;
    try {
      text = readFileSync(join(root, f), "utf8");
    } catch {
      continue;
    }
    let cur = "";
    let fenced = false;
    for (const line of text.split("\n")) {
      if (line.startsWith("```")) fenced = !fenced;
      cur += line + "\n";
      if (!fenced && line.trim() === "" && cur.length >= 600 + (out.length % 5) * 500) {
        out.push(cur.trim());
        cur = "";
      }
    }
    if (cur.trim()) out.push(cur.trim());
  }
  return out;
}
