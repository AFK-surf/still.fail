// Whether anything that answers the app reads a station's chats whole (its `chatRows` or `archivedRows` as a value):
// what answering reads follows what it sends (AGENTS.md), so a view reads the `chat` table by what it shows, through
// the declared reads (src/db/chat-reads.ts: one row by a key, the first rows of an order, counts SQLite makes), never
// a station's list loaded into memory (src/db/account.ts #collection). A view may still watch such a topic (`#sources`:
// what tells the sync the archive is shown, `inUse`), which loads nothing.
//
// Refused: a line of src/ outside the database's own (src/db/, src/data.ts) and the sync that writes the lists
// (src/station/) naming one of the two topics and reading a value (`value(`, `ok(`, `shared(`, `select(`, `.get(`,
// `loaded(`), unless it is one of WHOLE below, each with why and what takes it away.
//
//   node scripts/whole-lists.ts [--check]
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("..", import.meta.url));

/// Where a station's chats are still read whole: [file, what the line says, why, what takes it away].
export const WHOLE: [file: string, line: string, why: string, until: string][] = [
  [
    "src/views/views.ts",
    `return this.value({ topic: kind === "chats" ? "chatRows" : "archivedRows", station });`,
    "listKnown: whether a list is known, read only while it is not (nothing held then, nothing loaded)",
    "stays: it reads no row",
  ],
  [
    "src/views/views.ts",
    `: head !== null && data.listed(s.address, "chats") ? ({ ok: head.get(s.address) ?? [] } as Value) : this.value({ topic: "chatRows", station: s.address }); // whole-lists: #chatsWhole`,
    "#chatsWhole: search, chatSearch (and the `@` menu's other workspaces) and a share's choice find what is typed in every chat's row as the list makes it (refs.ts search: its title, its agents' and origin's words, its last line, its station's name)",
    "each chat's find text kept beside its record (the next change: one kept-rows mechanism with `chat_row`)",
  ],
  [
    "src/views/views.ts",
    `const unloaded = known.filter((s) => !data.loaded({ topic: "chatRows", station: s }));`,
    "#chatsWhole's first screen while its stations' rows are not loaded (#head), as above",
    "as above",
  ],
  [
    "src/views/views.ts",
    `data.shared({ topic: "chatRows", station });`,
    "#head: #chatsWhole's stations' rows loaded behind its first screen, as above",
    "as above",
  ],
];

const SKIPPED = [/^src\/db\//, /^src\/data\.ts$/, /^src\/station\//];
const TOPIC = /"(chatRows|archivedRows)"/;
const READ = /\b(value|ok|shared|select|loaded)\(|\.get\(/;

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? files(p) : p.endsWith(".ts") ? [p] : [];
  });
}

export function found(): { refused: string[]; unused: string[] } {
  const refused: string[] = [];
  const used = new Set<number>();
  for (const path of files(join(ROOT, "src"))) {
    const file = relative(ROOT, path);
    if (SKIPPED.some((r) => r.test(file))) continue;
    readFileSync(path, "utf8").split("\n").forEach((text, i) => {
      if (!TOPIC.test(text) || !READ.test(text)) return;
      const at = WHOLE.findIndex(([f, line]) => f === file && text.trim() === line);
      if (at >= 0) used.add(at);
      else refused.push(`${file}:${i + 1}: ${text.trim()}`);
    });
  }
  return { refused, unused: WHOLE.filter((_, i) => !used.has(i)).map(([f, line]) => `${f}: ${line}`) };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { refused, unused } = found();
  for (const r of refused) console.log(`reads a station's chats whole: ${r}\n  read what it shows through src/db/chat-reads.ts (one row by a key, a window, a count), or say why in WHOLE`);
  for (const u of unused) console.log(`WHOLE names a line that is not there any more: ${u}`);
  if (process.argv.includes("--check") && (refused.length > 0 || unused.length > 0)) process.exit(1);
}
