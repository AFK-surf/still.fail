// The mesh's base imports nothing of the station's business (station/AGENTS.md, Its shape): the files another program
// is served by (the wire, the door, the endpoint and its connections' taking, and what watches a connection) import, by
// a relative path, only each other and the leaves below; node's own modules and npm's packages aside. A type counts as
// a value does: a file that names the station's credentials, locks or routes even in a type cannot be taken without
// them. Nor does their code say still.fail's name (an environment variable's, a file's, a process's): where the
// station's addon is and what its processes are called are the station's to give them. A comment may.
// It reads the files' text, comments left out, not the program: an import or a name put together as it runs (a path in
// pieces, `createRequire` under another name) passes. It is held against a slip, not against someone set on it.
// Prints each line that is not so, and fails then.
//   node scripts/mesh-base.ts
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/// The base. A file is added once it is so; none is taken out to let an import in.
const BASE = [
  "station/src/mesh/wire.ts",
  "station/src/mesh/door.ts",
  "station/src/mesh/accept.ts",
  "station/src/mesh/reply-watch.ts",
  // (mesh/native.ts was here until its endpoint was this file: what is left of it is the station's addon, the
  // thumbnails, the file locks, where STILLFAIL_MESH_NATIVE says it is, and nothing here imports it.)
  "station/src/mesh/endpoint.ts",
  "station/src/mesh/compress.ts",
  "station/src/mesh/storms.ts",
  "station/src/mesh/superseded.ts",
  "station/src/mesh/lan.ts",
  "station/src/mesh/settings.ts",
  "station/src/api/event-log.ts",
];

/// What the base may import besides itself: the station's log and its time, which import only each other. Held to the
/// same rule as the base, so that they stay leaves. This table only shrinks.
const LEAVES = ["station/src/ops/log.ts", "station/src/ops/fibers.ts"];

/// The file's text with its comments blanked (each character of one but a newline a space, so that a place in it is the
/// same place in the file) and its strings as they are. A regular expression is told from a division by what stands
/// before it, which is enough for it not to open a string or a comment here.
function codeOf(source: string): string {
  /// Past the end of the string or regular expression that opens at `from` with `quote` (a `/` that closes on no
  /// line was a division: past the `/` alone).
  const closed = (from: number, quote: string): number => {
    let inClass = false;
    for (let at = from + 1; at < source.length; at++) {
      const c = source[at]!;
      if (c === "\\") at++;
      else if (c === "\n") return quote === "/" ? from + 1 : at;
      else if (quote === "/" && (c === "[" || c === "]")) inClass = c === "[";
      else if (c === quote && !inClass) return at + 1;
    }
    return source.length;
  };
  let out = "";
  // The end of the code so far, its spaces as one: what a `/` stands after.
  let before = "";
  // Whether this place is in a template's text; and, of each `${` open around it, the braces open in it.
  let text = false;
  const braces: number[] = [];
  for (let i = 0; i < source.length; ) {
    const c = source[i]!;
    let to = i + 1;
    let comment = false;
    if (text) {
      if (c === "\\") to = i + 2;
      else if (c === "`") text = false;
      else if (source.startsWith("${", i)) {
        to = i + 2;
        braces.push(0);
        text = false;
      }
    } else if (source.startsWith("//", i) || source.startsWith("/*", i)) {
      comment = true;
      const end = c === "/" && source[i + 1] === "/" ? source.indexOf("\n", i) : source.indexOf("*/", i + 2) + 2;
      to = end < i + 2 ? source.length : end;
    } else if (c === "`") text = true;
    else if (c === '"' || c === "'") to = closed(i, c);
    else if (c === "/" && /(^|[=(,:;!&|?{}[+\-*%<>~^]|\b(return|typeof|case|of|in|await|yield|void|delete|throw|new|else|do)) ?$/.test(before)) to = closed(i, c);
    else if (c === "{" && braces.length > 0) braces[braces.length - 1]!++;
    else if (c === "}" && braces.length > 0 && braces[braces.length - 1]!-- === 0) {
      braces.pop();
      text = true;
    }
    const piece = source.slice(i, to);
    out += comment ? piece.replace(/[^\n]/g, " ") : piece;
    if (!comment) before = (before + piece).replace(/\s+/g, " ").slice(-10);
    i = to;
  }
  return out;
}

const allowed = new Set([...BASE, ...LEAVES]);
const wrong: string[] = [];
for (const file of allowed) {
  if (!existsSync(join(root, file))) {
    wrong.push(`${file}: listed in scripts/mesh-base.ts and not there`);
    continue;
  }
  const code = codeOf(readFileSync(join(root, file), "utf8"));
  const found: [number, string][] = [];
  const lineAt = (at: number) => code.slice(0, at).split("\n").length;
  // (Over the whole text, not a line at a time: a statement a formatter wrapped has its path on a line after its
  // `from` or its `import(`. Said at the line the path is on.)
  for (const match of code.matchAll(/\bfrom\s*["']([^"'\n]+)["']|\bimport\s*["']([^"'\n]+)["']|\b(?:import|require)\s*\(\s*["']([^"'\n]+)["']/g)) {
    const path = match[1] ?? match[2] ?? match[3] ?? "";
    if (!path.startsWith(".")) continue;
    const to = normalize(join(dirname(file), path));
    if (!allowed.has(to)) found.push([lineAt(match.index + match[0].length), `imports ${to}`]);
  }
  // (a path made as it runs could be any file's)
  for (const match of code.matchAll(/\b(?:import|require)\s*\(\s*[^"'\s)]/g)) found.push([lineAt(match.index + match[0].length), "imports a path it does not write out"]);
  code.split("\n").forEach((line, i) => {
    if (/stillfail|still\.fail/i.test(line)) found.push([i + 1, "says still.fail's name"]);
  });
  for (const [line, what] of found.sort((a, b) => a[0] - b[0])) wrong.push(`${file}:${line}: ${what}`);
}
if (wrong.length > 0) {
  console.log(wrong.join("\n"));
  console.log("(the mesh's base stands without the station's business: give it what it needs as a parameter, or keep what needs the import, or the name, outside it)");
  process.exit(1);
}
