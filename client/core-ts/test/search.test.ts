// The search (docs/search.md, views/search.ts): what the device holds and what each station finds, one list.
import assert from "node:assert/strict";
import { test } from "node:test";
import { SEARCH_SETTLE_MS, SEARCH_STALE_MS } from "../src/station/sync.ts";
import { openOf } from "../src/views/search.ts";
import { apply, subscribe, v } from "./helpers.ts";
import { base, started, threadView } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const row = (id: string, thread: number, title: string) => ({ id, session: id, thread, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: thread, connect: null, origin: null });
const said = (thread: number, n: number, text: string, at: number) => ({ thread, n, kind: "message", ts: `${n}.0`, authorKind: "person", author: "a@x", authorName: "阿甲", text, at });

const found = {
  building: false,
  groups: [
    { kind: "chat", more: false, hits: [
      { kind: "chat", key: "c:9", title: "旧的部署", text: "", at: 50, thread: 9, chat: "old", archived: true },
      // Its words late in its title: said where they are.
      { kind: "chat", key: "c:11", title: "动效测试（请照做）：先用命令运行 sleep 3，然后部署", text: "动效测试（请照做）：先用命令运行 sleep 3，然后部署", at: 40, thread: 11, chat: "motion", archived: true },
    ] },
    {
      kind: "message",
      more: false,
      hits: [
        // One the device holds too: listed once.
        { kind: "message", key: "m:7:1", title: "", text: "部署 studio", at: 1000, thread: 7, seq: 1, chat: "a", authorKind: "person", author: "a@x" },
        { kind: "message", key: "m:9:3", title: "", text: "部署完了", at: 3000, thread: 9, seq: 3, chat: "old", chatTitle: "旧的部署", authorKind: "agent", author: "old", archived: true },
      ],
    },
    { kind: "job", more: true, hits: [{ kind: "job", key: "j:j1", title: "部署预览", text: "pnpm dev --filter 部署", at: 10, job: "j1", port: 5173, session: "a", chat: "a", thread: 7 }] },
  ],
};

test("a_search_lists_what_the_device_holds_and_what_its_stations_find_each_once", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /chats": [row("a", 7, "部署页"), row("b", 8, "别的")],
    "GET /threads": [threadView(7, 1, 1, 0), threadView(8, 1, 1, 0)],
    "GET /threads/7/entries?limit=50": { first: 1, last: 1, entries: [said(7, 1, "部署 studio", 1000)] },
    "GET /threads/8/entries?limit=50": { first: 1, last: 1, entries: [said(8, 1, "无关", 500)] },
    "GET /search?q=%E9%83%A8%E7%BD%B2&limit=6": found,
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "search", scope: "ws", query: "部署" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  // Before the stations answer: what the device holds.
  assert.deepEqual(v(values, 1).items.map((i: J) => i.id), ["a"]);
  assert.deepEqual(v(values, 1).messages.map((m: J) => [m.thread, m.seq]), [[7, 1]]);
  assert.equal(v(values, 1).wait.reading, true);
  await host.time.pass(SEARCH_SETTLE_MS + 10);
  await host.settle();
  apply(host, values);
  const view = v(values, 1);
  // The archived chat a station found, after the device's.
  assert.deepEqual(view.items.map((i: J) => [i.id, i.archived ?? false]), [["a", false], ["old", true], ["motion", true]]);
  // A title with the words first says nothing more; one with them late, where they are.
  assert.equal(view.items[1].foundText, undefined);
  assert.match(view.items[2].foundText, /部署$/);
  assert.ok(view.items[2].foundMarks.length > 0);
  assert.equal(view.items[2].stateText, "已归档");
  // Newest first, the one both have once.
  assert.deepEqual(view.messages.map((m: J) => [m.thread, m.seq]), [[9, 3], [7, 1]]);
  assert.equal(view.messages[0].chat.title, "旧的部署");
  assert.deepEqual(view.groups.map((g: J) => [g.kind, g.items.length, g.more]), [["job", 1, true]]);
  const job = view.groups[0].items[0];
  assert.deepEqual([job.title, job.job, job.port, job.chat, job.station], ["部署预览", "j1", 5173, "a", "ws/st"]);
  // Where it opens: its chat, its page over it.
  assert.deepEqual(job.open, { to: "service", station: "ws/st", chat: "a", job: "j1" });
  assert.deepEqual(job.marks.length > 0, true);
  assert.equal(view.wait.reading, false);
  core.close();
});

test("a_station_from_before_search_is_said_to_need_an_update", async () => {
  const { host, core } = await started({ ...base(), "GET /chats": [row("a", 7, "部署页")], "GET /threads": [threadView(7, 0, 0, 0)] });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "search", scope: "ws", query: "部署" });
  await host.settle();
  await host.time.pass(SEARCH_SETTLE_MS + 10);
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.match(v(values, 1).note ?? "", /更新/);
  assert.deepEqual(v(values, 1).items.map((i: J) => i.id), ["a"]);
  core.close();
});

test("a_search_shown_again_asks_its_stations_again", async () => {
  const replies: Record<string, unknown> = { ...base(), "GET /chats": [row("a", 7, "部署页")], "GET /threads": [threadView(7, 0, 0, 0)], "GET /search?q=%E9%83%A8%E7%BD%B2&limit=6": found };
  const { host, core } = await started(replies);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "search", scope: "ws", query: "部署" });
  await host.settle();
  await host.time.pass(SEARCH_SETTLE_MS + 10);
  await host.settle();
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.settle();
  // Archived meanwhile: the station says so now.
  replies["GET /search?q=%E9%83%A8%E7%BD%B2&limit=6"] = { building: false, groups: [{ kind: "chat", more: false, hits: [{ kind: "chat", key: "c:7", title: "部署页", text: "", at: 9, thread: 7, chat: "a", archived: true }] }] };
  replies["GET /chats"] = [];
  subscribe(core, ui, 2, { topic: "search", scope: "ws", query: "部署" });
  await host.settle();
  await host.time.pass(SEARCH_SETTLE_MS + 10);
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 2).groups, []);
  assert.equal(v(values, 2).messages.length, 0);
  core.close();
});

test("a_search_shown_is_asked_again_when_its_station_says_a_chat_changed", async () => {
  const replies: Record<string, unknown> = { ...base(), "GET /chats": [row("a", 7, "部署页")], "GET /threads": [threadView(7, 0, 0, 0)], "GET /search?q=%E9%83%A8%E7%BD%B2&limit=6": found };
  const { host, core, push } = await started(replies);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "search", scope: "ws", query: "部署" });
  await host.settle();
  await host.time.pass(SEARCH_SETTLE_MS + 10);
  await host.settle();
  // Archived on the station: it says so, and finds it so.
  replies["GET /search?q=%E9%83%A8%E7%BD%B2&limit=6"] = { building: false, groups: [{ kind: "chat", more: false, hits: [{ kind: "chat", key: "c:7", title: "部署页", text: "", at: 9, thread: 7, chat: "a", archived: true }] }] };
  push("chat", { ...row("a", 7, "部署页"), lastActiveAt: 8 });
  // Told again and again meanwhile (a busy station): asked again once.
  push("chat", { ...row("a", 7, "部署页"), lastActiveAt: 8 });
  await host.settle();
  await host.time.pass(SEARCH_STALE_MS + SEARCH_SETTLE_MS + 10);
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).items.map((i: J) => [i.id, i.archived ?? false]), [["a", true]]);
  assert.equal(v(values, 1).messages.length, 0);
  core.close();
});

test("what_a_search_finds_says_where_it_opens_as_every_client_has_a_page_for_it", () => {
  const at = { station: "ws/st" };
  // A service its chat and its page over it, a task its chat with it picked, one with no id its chat; none without a chat.
  assert.deepEqual(openOf({ ...at, kind: "job", chat: "a", job: "j1", port: 5173 }), { to: "service", station: "ws/st", chat: "a", job: "j1" });
  assert.deepEqual(openOf({ ...at, kind: "job", chat: "a", job: "j2" }), { to: "task", station: "ws/st", chat: "a", job: "j2" });
  assert.deepEqual(openOf({ ...at, kind: "job", chat: "a" }), { to: "chat", station: "ws/st", chat: "a" });
  assert.equal(openOf({ ...at, kind: "job", job: "j1" }), null);
  // A station its page, a member the workspace's members, anything else in a chat that chat.
  assert.deepEqual(openOf({ ...at, kind: "station" }), { to: "station", station: "ws/st" });
  assert.deepEqual(openOf({ kind: "member", station: "" }), { to: "members", station: "" });
  assert.deepEqual(openOf({ ...at, kind: "skill", chat: "b" }), { to: "chat", station: "ws/st", chat: "b" });
  assert.equal(openOf({ ...at, kind: "skill" }), null);
  // A folder entered; a text read, a video played, in their folder; anything else its folder shown.
  const file = (path: string, fileKind: string, more: J = {}) => openOf({ ...at, kind: "file", path, fileKind, dir: fileKind === "folder", ...more });
  assert.deepEqual(file("/home/a/docs", "folder"), { to: "files", station: "ws/st", root: "/home/a/docs", path: "" });
  assert.deepEqual(file("/home/a/docs/README.md", "markdown"), { to: "files", station: "ws/st", root: "/home/a/docs", path: "README.md", how: "read" });
  assert.deepEqual(file("C:\\Users\\a\\clip.mp4", "video"), { to: "files", station: "ws/st", root: "C:\\Users\\a", path: "clip.mp4", how: "play" });
  assert.deepEqual(file("/home/a/docs/a.png", "image"), { to: "files", station: "ws/st", root: "/home/a/docs", path: "" });
  // Found under a folder a read-only member's workspace pinned: from there.
  const pinned = { root: "/srv/share", rel: "photos/2026/a.png" };
  assert.deepEqual(file("/srv/share/photos/2026/a.png", "image", pinned), { to: "files", station: "ws/st", root: "/srv/share", path: "photos/2026" });
  assert.deepEqual(file("/srv/share/notes/b.txt", "text", { root: "/srv/share", rel: "notes/b.txt" }), { to: "files", station: "ws/st", root: "/srv/share", path: "notes/b.txt", how: "read" });
  assert.deepEqual(file("/srv/share/notes", "folder", { root: "/srv/share", rel: "notes" }), { to: "files", station: "ws/st", root: "/srv/share", path: "notes" });
  // A file with no path opens nowhere.
  assert.equal(openOf({ ...at, kind: "file", chat: "a" }), null);
});

test("a_search_typed_on_asks_its_stations_for_the_last_words_alone_and_again_only_for_them", async () => {
  const replies: Record<string, unknown> = { ...base(), "GET /chats": [row("a", 7, "部署页")], "GET /threads": [threadView(7, 0, 0, 0)] };
  for (const q of ["u", "up", "upd"]) replies[`GET /search?q=${q}&limit=6`] = { building: false, groups: [] };
  const { host, core, push } = await started(replies);
  const ui = core.connect();
  // Typed: each words shown in place of the last (the ones let go are kept a while, not shown).
  let id = 0;
  for (const q of ["u", "up", "upd"]) {
    if (id > 0) core.receive(ui, { kind: "unsubscribe", id, unsubscribe: true });
    subscribe(core, ui, ++id, { topic: "search", scope: "ws", query: q });
    await host.settle();
    await host.time.pass(50);
  }
  await host.time.pass(SEARCH_SETTLE_MS + 10);
  await host.settle();
  const asked = (from: number) => host.requests.slice(from).map((r: J) => r.url as string).filter((u) => u.includes("/search?")).map((u) => u.split("q=")[1]);
  assert.deepEqual(asked(0), ["upd&limit=6"]);
  const before = host.requests.length;
  push("chat", { ...row("a", 7, "部署页"), lastActiveAt: 8 });
  await host.settle();
  await host.time.pass(SEARCH_STALE_MS + SEARCH_SETTLE_MS + 10);
  await host.settle();
  assert.deepEqual(asked(before), ["upd&limit=6"]);
  core.close();
});
