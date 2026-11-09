// A station's files as they are browsed on this device (src/views/browse.ts, src/drive-browse.ts): a place's folders in
// the order kept on the device, hidden ones once asked; what a press and the keys choose there, and what they have the
// client do; columns carrying the choice that opened a folder, a tree opening folders in place, what was opened chosen
// as a folder is come back to, columns' widths; the files' page's tabs kept among the prefs; a folder typed by its path;
// the stations with a drive; the names a new folder or a copy kept takes, and the renames a drag makes.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply as applyDelta } from "../src/delta.ts";
import { arrange, Browsing } from "../src/drive-browse.ts";
import { collate } from "../src/hosts/collate.ts";
import type { CoreMessage } from "../src/protocol.ts";
import { call, subscribe } from "./helpers.ts";
import { base, overview, started, stationReplies } from "./station-fixture.ts";

const ST = "ws/st";
const ROOT = "/Users/a";
const entry = (name: string, dir = false, size = 0, mtime = 0) => ({ name, dir, size, mtime, type: "" });
const FOLDERS: Record<string, unknown[]> = {
  "": [entry("b", true), entry("A", true), entry(".env"), entry("note-10.md", false, 5, 300), entry("note-2.md", false, 9, 100)],
  A: [entry("x.txt"), entry("y.txt")],
  b: [],
  hidden: [entry(".draft")],
};

/// A core whose station has a drive (its home ROOT, FOLDERS in it), each folder read as a page shows it; `values`: each
/// subscription's value now; `ask`: a call, answered.
async function browsing() {
  const s = await started({ ...base(), "GET /overview": { ...overview, drive: { roots: [], anywhere: true, home: ROOT } } });
  stationReplies(s.host, (req) => {
    const m = /\/admin\/api\/drive\/list\?root=[^&]*&path=(.*)$/.exec(req.url);
    if (!m) return undefined;
    const path = decodeURIComponent(m[1]!);
    return { path, entries: FOLDERS[path] ?? [], truncated: false };
  });
  const ui = s.core.connect();
  const values = new Map<number, any>();
  const answered = new Map<number, any>();
  const pump = () => {
    for (const [, message] of s.host.takeEmitted()) {
      const m = message as CoreMessage & Record<string, any>;
      if ("value" in m) values.set(m.id, m.value);
      else if ("delta" in m) values.set(m.id, applyDelta(values.get(m.id), m.delta));
      else if ("ok" in m) answered.set(m.id, m.ok);
      else if ("error" in m && !values.has(m.id)) answered.set(m.id, { error: m.error });
    }
  };
  let id = 1000;
  for (const path of Object.keys(FOLDERS)) subscribe(s.core, ui, id++, { topic: "drive", station: ST, root: ROOT, path });
  await s.host.settle();
  const ask = async (name: string, params: unknown) => {
    const n = id++;
    call(s.core, ui, n, name, params);
    await s.host.settle();
    pump();
    return answered.get(n);
  };
  const watch = async (n: number, topic: Record<string, unknown>) => {
    subscribe(s.core, ui, n, topic as never);
    await s.host.settle();
    pump();
    return () => values.get(n);
  };
  return { ...s, ui, values, ask, watch };
}

const place = (place: string, view: string, path = "", more: Record<string, unknown> = {}) => ({ owner: "page", place, view, station: ST, root: ROOT, path, ...more });

test("names go in the order the host's language reads them, else by hand", () => {
  const es = ["报告", "数据", "测试", "b10", "B2", "a"].map((name) => ({ name, dir: false, size: 0, mtime: 0, kind: "text" }));
  const by = { by: "name" as const, down: false, hidden: false };
  // By hand: case aside, numbers by value, the rest by its characters.
  assert.deepEqual(arrange(es, by).map((e) => e.name), ["a", "B2", "b10", "报告", "数据", "测试"]);
  // As a host has them (here: 中文 by pinyin, as a page in Chinese does): its places, its ties by hand.
  const pinyin: Record<string, number> = { a: 0, B2: 1, b10: 2, 报告: 3, 测试: 4, 数据: 5 };
  assert.deepEqual(arrange(es, by, (names) => names.map((n) => pinyin[n] ?? 0)).map((e) => e.name), ["a", "B2", "b10", "报告", "测试", "数据"]);
  // One that cannot say: by hand.
  assert.deepEqual(arrange(es, by, () => null).map((e) => e.name), ["a", "B2", "b10", "报告", "数据", "测试"]);
  // The page's and Node's hosts: the language's collation, equal names in one place.
  assert.deepEqual(collate(["b10", "B2", "a", "A"]), [3, 2, 0, 0]);
});

test("a place shows its folders in the order kept on the device, hidden files once asked", async () => {
  const { core, ask, watch } = await browsing();
  const now = await watch(1, { topic: "driveBrowse", ...place("p", "list") });
  assert.deepEqual(now().arrangement, { by: "name", down: false, hidden: false });
  assert.deepEqual(now().folders, { "": ["A", "b", "note-2.md", "note-10.md"] });
  assert.deepEqual(await ask("drive.arrange", { by: "time" }), { by: "time", down: false, hidden: false });
  assert.deepEqual(now().folders[""], ["A", "b", "note-10.md", "note-2.md"], "folders first, the newest file first");
  // ⌘⇧. shows hidden files.
  assert.ok(now().keys.includes("mod+shift+Period"));
  await ask("drive.browse", { ...place("p", "list"), act: "key", key: "mod+shift+Period" });
  assert.deepEqual(now().folders[""], ["A", "b", "note-10.md", "note-2.md", ".env"]);
  assert.equal(now().arrangement.hidden, true);
  core.close();
});

test("the folder's count follows the files actually shown", async () => {
  const { core, ask, watch } = await browsing();
  const at = place("count", "list");
  const now = await watch(1, { topic: "driveBrowse", ...at });
  assert.equal(now().countText, "2 个文件夹 · 2 个文件");
  const hidden = await watch(3, { topic: "driveBrowse", ...place("hidden", "list", "hidden") });
  assert.equal(hidden().countText, "没有可见的项目");
  await ask("drive.browse", { ...at, act: "key", key: "mod+shift+Period" });
  assert.equal(now().countText, "2 个文件夹 · 3 个文件");
  assert.equal(hidden().countText, "1 个文件");
  const empty = await watch(2, { topic: "driveBrowse", ...place("empty", "columns", "b") });
  assert.equal(empty().countText, "暂无内容");
  core.close();
});

test("a press chooses (⌘ one more or less, ⇧ those between), the keys move, and the view says which keys act", async () => {
  const { core, ask, watch } = await browsing();
  const at = place("p", "list", "", { write: true });
  const now = await watch(1, { topic: "driveBrowse", ...at });
  assert.deepEqual(now().chosen, { folder: "", names: [] });
  assert.ok(now().keys.includes("ArrowDown"));
  assert.ok(!now().keys.includes("Escape"), "nothing chosen: esc is the page's");
  assert.ok(!now().keys.includes("Enter"));
  const pressed = await ask("drive.browse", { ...at, act: "press", folder: "", name: "A" });
  assert.deepEqual(pressed.chosen, { folder: "", names: ["A"], anchor: "A", lead: "A" });
  assert.deepEqual(pressed.show, { folder: "", name: "A" });
  assert.equal(pressed.go, undefined, "a list goes nowhere on a press");
  await ask("drive.browse", { ...at, act: "press", folder: "", name: "note-10.md", shift: true });
  assert.deepEqual(now().chosen.names, ["A", "b", "note-2.md", "note-10.md"]);
  await ask("drive.browse", { ...at, act: "press", folder: "", name: "b", mod: true });
  assert.deepEqual(now().chosen.names, ["A", "note-2.md", "note-10.md"]);
  await ask("drive.browse", { ...at, act: "press", folder: "", name: "A" });
  await ask("drive.browse", { ...at, act: "key", key: "ArrowDown" });
  assert.deepEqual(now().chosen.names, ["b"]);
  await ask("drive.browse", { ...at, act: "key", key: "ArrowDown", shift: true });
  assert.deepEqual(now().chosen, { folder: "", names: ["b", "note-2.md"], anchor: "b", lead: "note-2.md" });
  // One chosen, where names change: ⏎ changes its name; space previews a file; ⌘⌫ deletes what is chosen.
  await ask("drive.browse", { ...at, act: "key", key: "End" });
  assert.deepEqual(now().chosen.names, ["note-10.md"]);
  assert.deepEqual((await ask("drive.browse", { ...at, act: "key", key: "Enter" })).rename, { folder: "", name: "note-10.md", dir: false });
  assert.deepEqual((await ask("drive.browse", { ...at, act: "key", key: " " })).preview, { folder: "", name: "note-10.md", dir: false });
  assert.deepEqual((await ask("drive.browse", { ...at, act: "key", key: "mod+Backspace" })).remove, [{ folder: "", name: "note-10.md", dir: false }]);
  // ⌘↑ goes up from a folder below.
  const below = place("q", "list", "A");
  assert.deepEqual((await ask("drive.browse", { ...below, act: "key", key: "mod+ArrowUp" })).go, { path: "", replace: false });
  // Letters typed go to the first name they start: within a second, together.
  await ask("drive.browse", { ...at, act: "type", letter: "n" });
  assert.deepEqual(now().chosen.names, ["note-2.md"]);
  await ask("drive.browse", { ...at, act: "type", letter: "O" });
  assert.deepEqual(now().chosen.names, ["note-2.md"]);
  assert.equal((await ask("drive.browse", { ...at, act: "type", letter: "z" })).acted, false);
  assert.ok(now().keys.includes("Escape"));
  await ask("drive.browse", { ...at, act: "key", key: "Escape" });
  assert.deepEqual(now().chosen, { folder: "", names: [] });
  // A right click on one chosen keeps what is chosen; on another, that one alone.
  await ask("drive.browse", { ...at, act: "key", key: "mod+a" });
  assert.equal(now().chosen.names.length, 4);
  await ask("drive.browse", { ...at, act: "menu", folder: "", name: "b" });
  assert.equal(now().chosen.names.length, 4);
  // Not where nothing changes: ⏎ opens.
  const reading = place("r", "list");
  await ask("drive.browse", { ...reading, act: "press", folder: "", name: "b" });
  assert.deepEqual((await ask("drive.browse", { ...reading, act: "key", key: "Enter" })).open, { folder: "", name: "b", dir: true });
  core.close();
});

test("columns open the folder chosen and carry the choice there; what was opened is chosen coming back", async () => {
  const { core, ask, watch } = await browsing();
  const root = place("c", "columns");
  await watch(1, { topic: "driveBrowse", ...root });
  const pressed = await ask("drive.browse", { ...root, act: "press", folder: "", name: "A" });
  assert.deepEqual(pressed.go, { path: "A", replace: false });
  // The client goes there: the same place, at A.
  const inA = place("c", "columns", "A");
  const now = await watch(2, { topic: "driveBrowse", ...inA });
  await ask("drive.browse", { ...inA, act: "at" });
  assert.deepEqual(now().chosen, { folder: "", names: ["A"], anchor: "A", lead: "A" });
  assert.deepEqual(Object.keys(now().folders).sort(), ["", "A"]);
  await ask("drive.browse", { ...inA, act: "key", key: "ArrowRight" });
  assert.deepEqual(now().chosen.names, ["x.txt"]);
  assert.equal(now().chosen.folder, "A");
  const back = await ask("drive.browse", { ...inA, act: "key", key: "ArrowLeft" });
  assert.deepEqual(back.chosen, { folder: "", names: ["A"], anchor: "A", lead: "A" });
  // A column's width dragged, kept for when it is shown again; ⌥ every one as wide again.
  await ask("drive.browse", { ...inA, act: "width", width: 300.4 });
  assert.deepEqual(now().widths, { A: 300 });
  await ask("drive.browse", { owner: "page", act: "widths" });
  assert.deepEqual(now().widths, {});
  // What was last opened in a folder is chosen as it is shown again.
  await ask("drive.browse", { ...place("", "list", "A"), act: "opened", name: "y.txt" });
  const again = await watch(3, { topic: "driveBrowse", ...place("d", "list", "A") });
  assert.deepEqual(again().chosen, { folder: "A", names: ["y.txt"], anchor: "y.txt", lead: "y.txt" });
  core.close();
});

test("a tree opens folders in place: → opens and goes in, ← goes out and closes", async () => {
  const { core, ask, watch } = await browsing();
  const at = place("t", "tree");
  const now = await watch(1, { topic: "driveBrowse", ...at });
  await ask("drive.browse", { ...at, act: "press", folder: "", name: "A" });
  await ask("drive.browse", { ...at, act: "key", key: "ArrowRight" });
  assert.deepEqual(now().open, ["A"]);
  assert.deepEqual(now().folders.A, ["x.txt", "y.txt"]);
  await ask("drive.browse", { ...at, act: "key", key: "ArrowRight" });
  assert.deepEqual(now().chosen, { folder: "A", names: ["x.txt"], anchor: "x.txt", lead: "x.txt" });
  // The keys go over the rows open in it.
  await ask("drive.browse", { ...at, act: "key", key: "ArrowDown" });
  await ask("drive.browse", { ...at, act: "key", key: "ArrowDown" });
  assert.deepEqual(now().chosen.names, ["b"]);
  await ask("drive.browse", { ...at, act: "key", key: "ArrowUp" });
  await ask("drive.browse", { ...at, act: "key", key: "ArrowLeft" });
  assert.deepEqual(now().chosen.names, ["A"]);
  await ask("drive.browse", { ...at, act: "key", key: "ArrowLeft" });
  assert.deepEqual(now().open, []);
  await ask("drive.browse", { ...at, act: "tree", folder: "b" });
  assert.deepEqual(now().open, ["b"]);
  core.close();
});

test("the files' page's tabs: arrive, open, shown, closed; kept among the prefs", async () => {
  const { core, ask, watch } = await browsing();
  const now = await watch(1, { topic: "filesTabs", workspace: "ws" });
  const prefs = await watch(2, { topic: "prefs" });
  assert.equal(now(), null);
  const home = { station: ST, root: ROOT, path: "" };
  const a = { station: ST, root: ROOT, path: "A" };
  const first = await ask("files.tabs", { workspace: "ws", act: "arrive", pane: home });
  assert.equal(first.tabs.length, 1);
  assert.deepEqual(now().front, home);
  await ask("files.tabs", { workspace: "ws", act: "open", pane: a });
  assert.equal(now().tabs.length, 2);
  assert.deepEqual(now().front, a);
  await ask("files.tabs", { workspace: "ws", act: "show", id: first.current });
  assert.deepEqual(now().front, home);
  await ask("files.tabs", { workspace: "ws", act: "arrive", pane: { ...home, path: "b" } });
  assert.equal(now().front.path, "b");
  await ask("files.tabs", { workspace: "ws", act: "split" });
  assert.equal(now().tabs.find((t: any) => t.id === now().current).panes.length, 2);
  await ask("files.tabs", { workspace: "ws", act: "close", id: first.current });
  assert.equal(now().tabs.length, 1);
  assert.deepEqual(JSON.parse(prefs().filesTabs.ws).tabs.map((t: any) => t.panes.map((p: any) => p.path)), [["A"]]);
  core.close();
});

test("a folder typed by its path, among the workspace's stations with a drive; those stations, this machine's first", async () => {
  const { core, ask, watch } = await browsing();
  assert.deepEqual(await ask("files.go", { workspace: "ws", typed: "stu:~/Pro", station: ST, abs: ROOT }), { station: ST, abs: "/Users/a/Pro", parent: "/Users/a", partial: "Pro" });
  assert.deepEqual(await ask("files.go", { workspace: "ws", typed: "A/", station: ST, abs: ROOT }), { station: ST, abs: "/Users/a/A", parent: "/Users/a/A", partial: "" });
  assert.equal(await ask("files.go", { workspace: "ws", typed: "nobody:~", station: ST, abs: ROOT }), null);
  const stations = await watch(1, { topic: "stations", scope: "ws", drive: true, here: ST });
  assert.deepEqual(stations().map((s: any) => s.station), [ST]);
  core.close();
});

test("a new folder's name and a copy kept beside another; the renames a drag into a folder makes", async () => {
  const { core, ask } = await browsing();
  assert.deepEqual(await ask("drive.name", { name: "a", station: ST, root: ROOT, path: "" }), { name: "a 2" });
  assert.deepEqual(await ask("drive.name", { name: "new", taken: ["New", "new 2"] }), { name: "new 3" });
  assert.deepEqual(await ask("drive.name", { name: "note-2.md", station: ST, root: ROOT, path: "", beside: true }), { name: "note-2 2.md" });
  const moved = await ask("drive.moves", { items: [{ station: ST, root: ROOT, abs: "/Users/a/b", name: "b" }, { station: ST, root: ROOT, abs: "/Users/a/A", name: "A" }], into: { station: ST, root: ROOT, path: "A" } });
  assert.deepEqual(moved, { moves: [{ root: ROOT, from: "b", to: "A/b" }] }, "not into itself");
  core.close();
});

test("a snapshot given to a new browsing answers each act as the one it was taken of", () => {
  const folders: Record<string, { name: string; dir: boolean; size: number; mtime: number; kind: string }[]> = {
    "": [{ name: "b", dir: true, size: 0, mtime: 2, kind: "folder" }, { name: "A", dir: true, size: 0, mtime: 1, kind: "folder" }, { name: "c.txt", dir: false, size: 3, mtime: 5, kind: "text" }],
    A: [{ name: "x.txt", dir: false, size: 1, mtime: 1, kind: "text" }, { name: "y.txt", dir: false, size: 2, mtime: 2, kind: "text" }],
    b: [],
  };
  // A device of its own for each browsing: the same prefs and folders, the same time and ids, as they go.
  const device = () => {
    let prefs: Record<string, any> = {};
    let n = 0;
    let now = 1000;
    return {
      prefs: () => prefs,
      countText: (dirs: number, files: number, hiddenOnly: boolean) => `${dirs}/${files}/${hiddenOnly}`,
      setPrefs: (patch: Record<string, any>) => {
        const next = { ...prefs };
        for (const [k, v] of Object.entries(patch)) next[k] = { ...(prefs[k] ?? {}), ...v };
        prefs = next;
      },
      entries: (_s: string, _r: string, path: string) => folders[path] ?? null,
      stations: () => [{ station: ST, name: "Studio", home: ROOT }],
      now: () => (now += 300),
      newId: () => `t${n++}`,
      invalid: (what: string) => new Error(what),
      changed: () => {},
    };
  };
  const live = new Browsing(device());
  const at = (view: string, path = "") => ({ owner: "page", place: "p1", view, station: ST, root: ROOT, path });
  assert.equal(Object.hasOwn(live.view(at("list", "unread")), "countText"), false, "a folder being read has no count yet");
  const acts: [string, Record<string, unknown>][] = [
    ["drive.browse", { ...at("columns"), act: "at" }],
    ["drive.browse", { ...at("columns"), act: "press", folder: "", name: "A" }],
    ["drive.browse", { ...at("columns", "A"), act: "key", key: "ArrowRight" }],
    ["drive.browse", { ...at("columns", "A"), act: "type", letter: "y" }],
    ["drive.browse", { ...at("columns", "A"), act: "width", width: 300 }],
    ["drive.browse", { ...at("tree"), act: "tree", folder: "A" }],
    ["drive.browse", { ...at("tree"), act: "press", folder: "A", name: "x.txt", shift: true }],
    ["drive.browse", { ...at("list"), act: "opened", name: "c.txt" }],
    ["drive.browse", { ...at("list"), act: "key", key: "mod+shift+Period" }],
    ["drive.arrange", { by: "time" }],
    ["files.tabs", { workspace: "ws", act: "arrive", pane: { station: ST, root: ROOT, path: "" } }],
    ["files.tabs", { workspace: "ws", act: "open", pane: { station: ST, root: ROOT, path: "A" } }],
    ["drive.browse", { ...at("list"), act: "key", key: "ArrowDown" }],
  ];
  // Each act answered by the live one, and by one made from a snapshot of the one before it (on a device of its own,
  // gone through the same acts), and the same after it.
  const other = device();
  let restored = new Browsing(other);
  for (const [name, params] of acts) {
    restored = new Browsing(other, JSON.parse(JSON.stringify(restored.snapshot())));
    assert.deepEqual(restored.call(name, params), live.call(name, params), `${name} ${JSON.stringify(params)}`);
    assert.deepEqual(restored.snapshot(), live.snapshot());
    for (const view of ["columns", "tree", "list"]) assert.deepEqual(restored.view(at(view, "A")), live.view(at(view, "A")));
    assert.deepEqual(restored.tabsView("ws"), live.tabsView("ws"));
  }
});
