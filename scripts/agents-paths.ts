// The paths the agents' rules name (every AGENTS.md: the root AGENTS.md, These files are kept true) are there: a word in
// backticks that reads as a path (a slash in it; no space, pattern, placeholder or `…`; its first part a directory
// there, or its last a file's name) names a file or directory the repository tracks, from the AGENTS.md's own
// directory or from the root. (`origin/main`, `thread/start` read as none.) A change that moves or removes one corrects
// the rule in the same change. Prints each one that is not, and fails then.
//   node scripts/agents-paths.ts
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, normalize } from "node:path";

const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" }).split("\0").filter((f) => f !== "");
const there = new Set<string>();
for (const file of tracked) {
  there.add(file);
  for (let d = dirname(file); d !== "."; d = dirname(d)) there.add(d);
}

const PATH = /^[\w.@+-]+(\/[\w.@+-]+)*\/?$/;
const missing: string[] = [];
for (const file of tracked.filter((f) => f === "AGENTS.md" || f.endsWith("/AGENTS.md"))) {
  const dir = dirname(file);
  const lines = readFileSync(join(root, file), "utf8").split("\n");
  lines.forEach((line, i) => {
    for (const [, word] of line.matchAll(/`([^`\n]+)`/g)) {
      if (!word.includes("/") || !PATH.test(word) || word.startsWith("@")) continue;
      const path = word.replace(/\/$/, "");
      const from = [normalize(join(dir, path)), normalize(path)];
      const first = path.split("/")[0];
      const named = /\.\w+$/.test(path);
      if (!named && !there.has(normalize(join(dir, first))) && !there.has(first)) continue;
      if (!from.some((p) => there.has(p))) missing.push(`${file}:${i + 1}: \`${word}\` is not in the repository`);
    }
  });
}
if (missing.length > 0) {
  console.log(missing.join("\n"));
  console.log("(an AGENTS.md names a path that is not there: say where it went, or take the rule out)");
  process.exit(1);
}
