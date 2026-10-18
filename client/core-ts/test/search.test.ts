// The search (docs/search.md, views/search.ts): what the device holds and what each station finds, one list.
import assert from "node:assert/strict";
import { test } from "node:test";
import { SEARCH_SETTLE_MS } from "../src/station/sync.ts";
import { apply, subscribe, v } from "./helpers.ts";
import { base, started, threadView } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const row = (id: string, thread: number, title: string) => ({ id, session: id, thread, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: thread, connect: null, origin: null });
const said = (thread: number, n: number, text: string, at: number) => ({ thread, n, kind: "message", ts: `${n}.0`, authorKind: "person", author: "a@x", authorName: "阿甲", text, at });

const found = {
  building: false,
  groups: [
    { kind: "chat", more: false, hits: [{ kind: "chat", key: "c:9", title: "旧的部署", text: "", at: 50, thread: 9, chat: "old", archived: true }] },
    {
      kind: "message",
      more: false,
      hits: [
        // One the device holds too: listed once.
        { kind: "message", key: "m:7:1", title: "", text: "部署 studio", at: 1000, thread: 7, seq: 1, chat: "a", authorKind: "person", author: "a@x" },
        { kind: "message", key: "m:9:3", title: "", text: "部署完了", at: 3000, thread: 9, seq: 3, chat: "old", chatTitle: "旧的部署", authorKind: "agent", author: "old", archived: true },
      ],
    },
    { kind: "history", more: true, hits: [{ kind: "history", key: "h:a:4", title: "", text: "bash\npnpm run 部署", at: 2000, session: "a", index: 4, chat: "a", chatTitle: "部署页", thread: 7 }] },
    { kind: "job", more: false, hits: [{ kind: "job", key: "j:j1", title: "部署预览", text: "pnpm dev", at: 10, job: "j1", port: 5173, session: "a", chat: "a" }] },
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
  assert.deepEqual(view.items.map((i: J) => [i.id, i.archived ?? false]), [["a", false], ["old", true]]);
  // Newest first, the one both have once.
  assert.deepEqual(view.messages.map((m: J) => [m.thread, m.seq]), [[9, 3], [7, 1]]);
  assert.equal(view.messages[0].chat.title, "旧的部署");
  assert.deepEqual(view.groups.map((g: J) => [g.kind, g.items.length, g.more]), [["history", 1, true], ["job", 1, false]]);
  const step = view.groups[0].items[0];
  assert.deepEqual([step.title, step.session, step.index, step.station], ["部署页", "a", 4, "ws/st"]);
  assert.deepEqual(step.marks.length > 0, true);
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
