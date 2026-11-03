// The share card's looks' files on still.fail's site (web/public/share-looks/<drawing>/: their pictures, the face their
// words are in) as the core fetches them (client/core-ts/src/share-looks.ts: each file's size and hash, a file had
// whole and checked by them before it is kept). Run after a drawing's files are put there or made again
// (scripts/fonts.py --share makes its faces):
//
//   node scripts/share-looks.ts           client/core-ts/src/share-looks.ts written again from the files
//   node scripts/share-looks.ts --check   fails where it does not say the files as they are
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dirname, "..");
const SITE = join(ROOT, "web/public/share-looks");
const OUT = join(ROOT, "client/core-ts/src/share-looks.ts");

export function made(): string {
  const lines: string[] = [];
  for (const drawing of readdirSync(SITE).filter((d) => /^[0-9]+$/.test(d)).sort((a, b) => Number(a) - Number(b))) {
    for (const name of readdirSync(join(SITE, drawing)).sort()) {
      const bytes = readFileSync(join(SITE, drawing, name));
      lines.push(`  "${drawing}/${name}": { bytes: ${bytes.length}, sha256: "${createHash("sha256").update(bytes).digest("hex")}" },`);
    }
  }
  return `// Made by scripts/share-looks.ts from web/public/share-looks/: do not edit.
// The share card's looks' files on still.fail's site (\`<drawing>/<name>\`), each its size and hash: the core has one
// whole and as said before it keeps it (font-files.ts \`share\`).
export const SHARE_LOOKS_FILES: Record<string, { bytes: number; sha256: string }> = {
${lines.join("\n")}
};
`;
}

if (import.meta.main) {
  const text = made();
  if (process.argv.includes("--check")) {
    if (readFileSync(OUT, "utf8") !== text) {
      console.error("client/core-ts/src/share-looks.ts does not say web/public/share-looks/ as it is: node scripts/share-looks.ts");
      process.exit(1);
    }
  } else {
    writeFileSync(OUT, text);
  }
}
