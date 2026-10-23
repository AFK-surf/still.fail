// The files' page, as the core works it out for every client (client/core-ts/src/drive-browse.ts): its tabs following
// the page's address, opened, closed and split, kept as written and read back; a folder typed by its path worked out; a
// name kept beside one there, as the station names it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { arrive as arriveWith, besides, closed, frontOf, fronted, keptName, MOST_TABS, opened as openedWith, readTabs, resolveTyped, shown, split, type FilesTabs, type Pane } from "../client/core-ts/src/drive-browse.ts";

let ids = 0;
const newId = () => `t${++ids}`;
const arrive = (s: FilesTabs | null, p: Pane) => arriveWith(s, p, newId);
const opened = (s: FilesTabs, p: Pane) => openedWith(s, p, newId);

const pane = (station: string, root: string, path = ""): Pane => ({ station, root, path });
const STUDIO = pane("w/studio", "/Users/lin");
const MBA = pane("w/mba", "/Users/mei", "照片");

test("tabs: the address moves the side in front; new ones open beside the one shown; the last one stays", () => {
  let s = arrive(null, STUDIO);
  assert.equal(s.tabs.length, 1);
  assert.deepEqual(frontOf(s), STUDIO);
  // The same address again changes nothing.
  assert.deepEqual(arrive(s, STUDIO).tabs, s.tabs);
  s = arrive(s, pane("w/studio", "/Users/lin", "code"));
  assert.deepEqual(frontOf(s).path, "code");
  const first = s.current;
  s = opened(s, MBA);
  assert.equal(s.tabs.length, 2);
  assert.deepEqual(frontOf(s), MBA);
  // The address moving now moves the new one; the first keeps its folder.
  s = arrive(s, pane("w/mba", "/Users/mei", "照片/2026"));
  assert.equal(s.tabs[0]!.panes[0]!.path, "code");
  assert.equal(frontOf(s).path, "照片/2026");
  s = shown(s, first);
  assert.equal(frontOf(s).path, "code");
  s = closed(s, first);
  assert.equal(s.tabs.length, 1);
  assert.equal(frontOf(s).station, "w/mba");
  assert.equal(closed(s, s.current), s, "the last tab stays");
});

test("tabs: split shows a second side (in front), unsplit keeps the one in front; opened beside replaces the other", () => {
  let s = arrive(null, STUDIO);
  s = split(s);
  assert.equal(s.tabs[0]!.panes.length, 2);
  assert.equal(s.tabs[0]!.front, 1);
  s = arrive(s, MBA);
  assert.deepEqual(s.tabs[0]!.panes, [STUDIO, MBA]);
  s = fronted(s, 0);
  assert.deepEqual(frontOf(s), STUDIO);
  s = besides(s, pane("w/mba", "/Users/mei", "项目"));
  assert.deepEqual(s.tabs[0]!.panes.map((p) => p.path), ["", "项目"]);
  assert.equal(s.tabs[0]!.front, 1);
  s = split(s);
  assert.deepEqual(s.tabs[0]!.panes.map((p) => p.path), ["项目"]);
  // One tab alone, opened beside: split first.
  assert.deepEqual(besides(arrive(null, STUDIO), MBA).tabs[0]!.panes, [STUDIO, MBA]);
});

test("tabs: kept as written and read back; what does not hold together let go; at most MOST_TABS", () => {
  let s: FilesTabs = arrive(null, STUDIO);
  for (let i = 0; i < MOST_TABS + 3; i++) s = opened(s, pane("w/studio", "/Users/lin", `f${i}`));
  assert.equal(s.tabs.length, MOST_TABS);
  assert.deepEqual(readTabs(JSON.stringify(s)), s);
  assert.equal(readTabs("not json"), null);
  assert.equal(readTabs(JSON.stringify({ tabs: [{ id: "a", panes: [], front: 0 }], current: "a" })), null);
  const kept = readTabs(JSON.stringify({ tabs: [{ id: "a", panes: [STUDIO, MBA], front: 7 }, { id: "b", panes: [{ station: 1 }], front: 0 }], current: "zz" }))!;
  assert.deepEqual(kept.tabs.map((t) => [t.id, t.front]), [["a", 0]]);
  assert.equal(kept.current, "a");
});

test("a folder by its path: the station before a colon, ~ its home, a relative path under the folder shown", () => {
  const views = [
    { station: "w/studio", name: "Studio", home: "/Users/lin" },
    { station: "w/mba", name: "MBA", home: "/Users/mei" },
    { station: "w/win", name: "Box", home: "C:\\Users\\me" },
  ];
  const from = { station: "w/studio", abs: "/Users/lin/code" };
  assert.deepEqual(resolveTyped("mba:~/Pro", views, from), { station: "w/mba", abs: "/Users/mei/Pro", parent: "/Users/mei", partial: "Pro" });
  assert.deepEqual(resolveTyped("mb:~/", views, from), { station: "w/mba", abs: "/Users/mei", parent: "/Users/mei", partial: "" });
  assert.deepEqual(resolveTyped("acme/web", views, from), { station: "w/studio", abs: "/Users/lin/code/acme/web", parent: "/Users/lin/code/acme", partial: "web" });
  assert.deepEqual(resolveTyped("/tmp/", views, from), { station: "w/studio", abs: "/tmp", parent: "/tmp", partial: "" });
  assert.deepEqual(resolveTyped("~", views, from), { station: "w/studio", abs: "/Users/lin", parent: "/Users/lin", partial: "" });
  // A drive's letter is not a station's name.
  assert.equal(resolveTyped("C:\\Users", views, { station: "w/win", abs: "C:\\" })?.station, "w/win");
  assert.equal(resolveTyped("nobody:~", views, from), null);
});

test("a name kept beside one there, as the station names it: numbered before the extension; a folder whole", () => {
  const taken = [{ name: "a.txt" }, { name: "A 2.txt" }, { name: "v1.2" }];
  assert.equal(keptName(taken, "a.txt"), "a 3.txt");
  assert.equal(keptName(taken, "v1.2", true), "v1.2 2");
  assert.equal(keptName(taken, ".env"), ".env 2");
});
