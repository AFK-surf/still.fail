// The order a folder's entries are shown in and the names a change gives, as the core works them out for every client
// (client/core-ts/src/drive-browse.ts; its topic and calls: client/core-ts/test/drive-browse.test.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { arrange, freeName, movesOf, type Arrangement } from "../client/core-ts/src/drive-browse.ts";
import type { DriveEntry } from "../web/src/core/shapes.ts";

const entry = (name: string, dir = false, size = 0, mtime = 0): DriveEntry =>
  ({ name, dir, size, mtime, type: "", kind: dir ? "folder" : name.endsWith(".md") ? "markdown" : "other", sizeText: "", timeText: "" }) as DriveEntry;
const names = (es: DriveEntry[]) => es.map((e) => e.name);
const by = (a: Partial<Arrangement>): Arrangement => ({ by: "name", down: false, hidden: false, ...a });

test("hidden files are left out unless asked for; folders come first, names in number order", () => {
  const es = [entry("note-10.md"), entry(".env"), entry("b", true), entry("note-2.md"), entry(".github", true), entry("A", true)];
  assert.deepEqual(names(arrange(es, by({}))), ["A", "b", "note-2.md", "note-10.md"]);
  assert.deepEqual(names(arrange(es, by({ hidden: true }))), [".github", "A", "b", ".env", "note-2.md", "note-10.md"]);
});

test("by time and size the newest and largest come first, turned the other way on asking; folders stay first", () => {
  const es = [entry("old", false, 5, 100), entry("new", false, 1, 300), entry("mid", false, 9, 200), entry("dir", true, 0, 50)];
  assert.deepEqual(names(arrange(es, by({ by: "time" }))), ["dir", "new", "mid", "old"]);
  assert.deepEqual(names(arrange(es, by({ by: "time", down: true }))), ["dir", "old", "mid", "new"]);
  assert.deepEqual(names(arrange(es, by({ by: "size" }))), ["dir", "mid", "old", "new"]);
});

test("a new folder takes the next free name, case aside", () => {
  assert.equal(freeName([entry("x")], "untitled folder"), "untitled folder");
  assert.equal(freeName([entry("Untitled Folder", true), entry("untitled folder 2", true)], "untitled folder"), "untitled folder 3");
});

const dragged = (abs: string, root: string, station = "w/s") => ({ station, root, abs, name: abs.split("/").pop()! });

test("files dragged into a folder under the same root are renamed by that root", () => {
  const into = { station: "w/s", root: "/Users/lin", path: "code/web" };
  assert.deepEqual(movesOf([dragged("/Users/lin/notes/a.md", "/Users/lin")], into, true), [{ root: "/Users/lin", from: "notes/a.md", to: "code/web/a.md" }]);
});

test("a file from a folder pinned elsewhere goes by the top of the disk, for a member who browses every folder only", () => {
  const into = { station: "w/s", root: "/Users/lin/Downloads", path: "" };
  const item = dragged("/Volumes/data/x.zip", "/Volumes/data");
  assert.deepEqual(movesOf([item], into, true), [{ root: "/", from: "Volumes/data/x.zip", to: "Users/lin/Downloads/x.zip" }]);
  assert.deepEqual(movesOf([item], into, false), []);
});

test("nothing moves into itself, where it is already, or from another station", () => {
  const into = { station: "w/s", root: "/r", path: "a/b" };
  assert.deepEqual(movesOf([dragged("/r/a", "/r"), dragged("/r/a/b/c.txt", "/r"), dragged("/r/d.txt", "/r", "w/other")], into, true), []);
});
