import assert from "node:assert/strict";
import { test } from "node:test";
import { pathIn } from "../web/src/paths.ts";

test("inline code that names a file: paths, with the line they point at", () => {
  const yes: [string, string, number | null][] = [
    ["web/src/Chat.tsx:1520", "web/src/Chat.tsx", 1520],
    ["/Users/me/a.png", "/Users/me/a.png", null],
    ["/Volumes/disk/repo", "/Volumes/disk/repo", null],
    ["~/notes.md", "~/notes.md", null],
    ["./run.sh", "./run.sh", null],
    ["src/a.ts#L12", "src/a.ts", 12],
    ["src/a.ts:3:9", "src/a.ts", 3],
    ["Sidebar.tsx", "Sidebar.tsx", null],
    ["package.json", "package.json", null],
    ["web/src/", "web/src/", null],
  ];
  for (const [code, path, line] of yes) assert.deepEqual(pathIn(code), { path, line }, code);
  for (const no of ["origin/main", "/admin/api", "node.js", "Next.js", "https://x.y/a.ts", "a b.ts", "pnpm test", "1.2.3", "v1/api", "foo()", "/", "--flag=a.ts", "x.ts:abc", "web-main.chat.copyLink"]) {
    assert.equal(pathIn(no), null, no);
  }
});
