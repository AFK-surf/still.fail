// What was said in a chat besides words (the `chatThings` view, things.ts): its pictures and videos, its files, its web
// links and its pull requests, each once and the latest first, found among those of each kind by their words; a pull
// request as its card says it; an image opened stepping through all of the chat's held.
import assert from "node:assert/strict";
import { test } from "node:test";
import { answers, apply, call, subscribe, v } from "./helpers.ts";
import { base, started, threadView } from "./station-fixture.ts";
import { isMedia, isVideo, linksOf, pullOf, siteOf } from "../src/things.ts";

test("3GPP videos appear among a chat's media", () => {
  for (const file of ["clip.3gp", "clip.3G2"]) {
    assert.equal(isMedia(file), true);
    assert.equal(isVideo(file), true);
  }
  assert.equal(isVideo("song.ogg"), false);
});

// deno-lint-ignore no-explicit-any
type J = any;
const S = "ws/st";
const PR = "https://github.com/acme/app/pull/12";
const said = (n: number, over: J = {}) => ({ thread: 7, n, kind: "message", ts: `${n}.0`, authorKind: "agent", author: "k1", authorName: null, text: "好", at: n * 1000, ...over });
const file = (name: string) => ({ name, path: `/w/k1/${name}`, size: 10 });

test("a_chats_things_are_its_files_links_and_pull_requests_each_once_the_latest_first", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /threads": [threadView(7, 7)],
    "GET /threads/7/entries?limit=50": { first: 1, last: 7, entries: [
      // A person's link written bare; their picture.
      said(1, { authorKind: "person", author: "me@x", text: "看这个 https://example.com/a/ 和截图", attachments: [file("shot.png")] }),
      // An agent's: linked by words, a pull request, an address in code (no link), a report and a video.
      said(2, { text: "[设计稿](https://example.com/a) 已改，开了 [#12](https://github.com/acme/app/pull/12)。\n\n```\ncurl https://api.example.com/x\n```", attachments: [file("report.pdf"), file("demo.mp4")] }),
      said(3, { text: "没有链接的话" }),
      // The pull request again, with what comes after its number; another link.
      said(4, { text: `CI 绿了：${PR}/checks ，文档在 https://docs.example.com/guide#part` }),
      said(5, { authorKind: "person", author: "me@x", text: "再来一张", attachments: [file("shot.png")] }),
      said(6), said(7),
    ] },
    [`GET /link-preview?url=${encodeURIComponent(PR)}`]: {
      kind: "github_pull_request", url: PR, repository: "acme/app", number: 12, title: "列表按天分组", state: "merged",
      author: { login: "lin" }, additions: 1, deletions: 1, changedFiles: 1, updatedAt: 3000, checks: { passed: 9, failed: 0, pending: 0 },
    },
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chatThings", station: S, thread: 7 });
  await host.time.pass(500, 10);
  apply(host, values);
  const things = v(values, 1);
  assert.equal(things.whole, true);
  assert.deepEqual(things.counts, { media: 3, files: 1, links: 2, pulls: 1 });
  // One per message it was sent with, the latest first, as its message has it (who keeps it).
  assert.deepEqual(things.media.map((t: J) => [t.seq, t.file.name]), [[5, "shot.png"], [2, "demo.mp4"], [1, "shot.png"]]);
  assert.equal(things.media[1].file.owner, "k1");
  assert.deepEqual(things.files.map((t: J) => [t.seq, t.file.name]), [[2, "report.pdf"]]);
  // A link once however often said (its fragment and closing slash aside), at the latest, by the words it was linked by.
  assert.deepEqual(things.links.map((t: J) => [t.url, t.site, t.title ?? null, t.count, t.seq]), [
    ["https://docs.example.com/guide#part", "docs.example.com/guide", null, 1, 4],
    ["https://example.com/a", "example.com/a", "设计稿", 2, 2],
  ]);
  // A pull request once, as its card says it.
  const [pr] = things.pulls;
  assert.deepEqual([pr.url, pr.repository, pr.number, pr.count, pr.seq, pr.title, pr.state], [PR, "acme/app", 12, 2, 4, "列表按天分组", "merged"]);
  assert.equal(typeof pr.time.updatedAt.ago, "string");
  assert.equal(typeof pr.time.createdAt.ago, "string", "when it was last said, in words too");
  // Found by their words, each kind's own; the counts stay the chat's.
  subscribe(core, ui, 2, { topic: "chatThings", station: S, thread: 7, q: "SHOT" });
  subscribe(core, ui, 3, { topic: "chatThings", station: S, thread: 7, q: "按天" });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.deepEqual(v(values, 2).media.map((t: J) => t.seq), [5, 1]);
  assert.deepEqual(v(values, 2).links, []);
  assert.deepEqual(v(values, 2).counts, things.counts);
  assert.deepEqual(v(values, 3).pulls.map((t: J) => t.number), [12]);
  // An image opened steps through the chat's.
  subscribe(core, ui, 4, { topic: "imageNear", station: S, thread: 7, path: "/w/k1/shot.png" });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(v(values, 4).count, 2);
  core.close();
});

test("every_pull_request_of_a_chat_says_what_its_card_says_not_only_one_whose_card_showed", async () => {
  const pr = (n: number) => `https://github.com/acme/app/pull/${n}`;
  const card = (n: number) => ({
    kind: "github_pull_request", url: pr(n), repository: "acme/app", number: n, title: `标题 ${n}`, state: "open",
    author: { login: "lin" }, additions: 1, deletions: 1, changedFiles: 1, updatedAt: 3000,
  });
  const { host, core } = await started({
    ...base(),
    "GET /threads": [threadView(7, 4)],
    "GET /threads/7/entries?limit=50": { first: 1, last: 4, entries: [
      said(1, { text: `开了 ${pr(1)}` }), said(2, { text: `还有 ${pr(2)}` }), said(3, { text: `和 ${pr(3)}` }), said(4),
    ] },
    ...Object.fromEntries([1, 2, 3].map((n) => [`GET /link-preview?url=${encodeURIComponent(pr(n))}`, card(n)])),
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chatThings", station: S, thread: 7 });
  await host.time.pass(2000, 20);
  apply(host, values);
  assert.deepEqual(v(values, 1).pulls.map((t: J) => [t.number, t.title ?? null]), [[3, "标题 3"], [2, "标题 2"], [1, "标题 1"]]);
  core.close();
});

test("a_chats_pictures_come_by_the_message_they_were_sent_with_and_are_found_by_what_it_says", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /threads": [threadView(7, 4)],
    "GET /threads/7/entries?limit=50": { first: 1, last: 4, entries: [
      said(1, { authorKind: "person", author: "me@x", text: "\n  列表跳了一下\n第二行", attachments: [file("phone.png")] }),
      // An agent's: its first words, a heading's, inline code's among them; its pictures in the order it has them.
      said(2, { text: "## 改了 `rows.mbt` 的高度\n\n改前改后：", attachments: [file("before.png"), file("after.png"), file("notes.pdf")] }),
      said(3, { text: "```\nlog\n```\n\n录屏", attachments: [file("demo.mp4")] }),
      said(4, { authorKind: "person", author: "me@x", text: "", attachments: [file("only.png")] }),
    ] },
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chatThings", station: S, thread: 7 });
  await host.time.pass(500, 10);
  apply(host, values);
  const things = v(values, 1);
  // By the day, then the message, the latest first; a message's as it has them, with when, who and its first words.
  assert.equal(things.mediaDays.length, 1);
  const [day] = things.mediaDays;
  assert.notEqual(day.day, "");
  assert.deepEqual(day.groups.map((g: J) => [g.seq, g.words, g.items.map((t: J) => t.file.name)]), [
    [4, "", ["only.png"]],
    [3, "录屏", ["demo.mp4"]],
    [2, "改了 rows.mbt 的高度", ["before.png", "after.png"]],
    [1, "列表跳了一下", ["phone.png"]],
  ]);
  assert.match(day.groups[0].clock, /^\d\d:\d\d$/);
  assert.equal(things.files[0].words, "改了 rows.mbt 的高度");
  // Found by what their message says, not only their names (a screenshot's name says nothing).
  subscribe(core, ui, 2, { topic: "chatThings", station: S, thread: 7, q: "高度" });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.deepEqual(v(values, 2).media.map((t: J) => t.file.name), ["after.png", "before.png"]);
  assert.deepEqual(v(values, 2).mediaDays[0].groups.map((g: J) => g.seq), [2]);
  core.close();
});

test("a_messages_links_are_those_drawn_and_a_pull_request_is_known_by_its_address", () => {
  // A person's words are not Markdown: their addresses as written bare, without the marks closing them.
  assert.deepEqual(linksOf({ authorKind: "person", text: "[x](https://a.com) 和 https://b.com/c。" }).map((l) => l.url), ["https://a.com", "https://b.com/c"]);
  assert.deepEqual(pullOf("https://github.com/AFK-surf/still.fail/pull/2647/files?w=1"), { repository: "AFK-surf/still.fail", number: 2647 });
  assert.equal(pullOf("https://github.com/acme/app/issues/3"), null);
  assert.equal(pullOf("https://github.com/acme/app/pull/12abc"), null);
  assert.equal(siteOf("https://www.example.com/a/b/?q=1#x"), "www.example.com/a/b");
});

// A chat's outline (the `chatOutline` view): what people said in it, by the day, as far as it is on the device.
const DAY = 86_400_000;
const AT = Date.UTC(2026, 0, 5, 9, 30);

test("a_chats_outline_is_what_people_said_by_the_day_oldest_first_and_asks_nothing", async () => {
  const { host, core, push } = await started({
    ...base(),
    "GET /threads": [threadView(7, 5)],
    "GET /threads/7/entries?limit=50": { first: 1, last: 5, entries: [
      said(1, { authorKind: "person", author: "a@x.com", text: "\n  先看列表\n第二行", at: AT }),
      // An agent's and still.fail's own: not listed.
      said(2, { text: "好，我看看", at: AT + 1000 }),
      said(3, { authorKind: "person", author: "b@x.com", authorName: "Bo", text: "", attachments: [file("shot.png")], at: AT + 2000 }),
      said(4, { authorKind: "station", author: "station", text: "⚠️ 出错了", at: AT + 3000 }),
      said(5, { authorKind: "person", author: "a@x.com", text: "第二天再说", at: AT + DAY }),
    ] },
  });
  const ui = core.connect();
  const values = new Map();
  await host.time.pass(500, 10);
  const asked = host.requests.length;
  // Its parameters as a UI says them (protocol.ts TOPICS): one it does not take is left out.
  core.receiveRaw(ui, { id: 1, subscribe: { topic: "chatOutline", station: S, thread: 7, q: "x" } });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(host.requests.slice(asked).filter((r) => !r.url.includes("/timeline?")).length, 0, "subscribing asks nothing");
  const outline = v(values, 1);
  assert.deepEqual([outline.count, outline.whole, outline.held, outline.of], [3, true, 5, 5]);
  assert.equal(outline.days.length, 2);
  assert.ok(outline.days.every((d: J) => d.day !== ""));
  assert.notEqual(outline.days[0].day, outline.days[1].day);
  assert.deepEqual(outline.days.map((d: J) => d.items.map((i: J) => [i.seq, i.mine, i.author, i.by.name, i.words])), [
    [[1, true, "a@x.com", "a@x.com", "先看列表"], [3, false, "b@x.com", "Bo", "（文件）"]],
    [[5, true, "a@x.com", "a@x.com", "第二天再说"]],
  ]);
  assert.match(outline.days[0].items[0].clock, /^\d\d:\d\d$/);
  // A message said later comes in by itself, only it sent (the rest as they were).
  push("thread", { id: 7, entries: [said(6, { authorKind: "person", author: "b@x.com", authorName: "Bo", text: "还有一件", at: AT + DAY + 1000 })] });
  await host.time.pass(500, 10);
  const sent = host.emitted.map(([, m]) => m as J).filter((m) => m.id === 1 && "delta" in m);
  apply(host, values);
  assert.deepEqual(v(values, 1).days[1].items.map((i: J) => [i.seq, i.words]), [[5, "第二天再说"], [6, "还有一件"]]);
  assert.equal(v(values, 1).count, 4);
  const ops = JSON.stringify(sent.flatMap((m) => m.delta));
  assert.ok(ops.includes("还有一件") && !ops.includes("先看列表") && !ops.includes("第二天再说"), ops);
  // An agent's message changing as it works changes nothing of it; a person's edited, that item.
  push("thread", { id: 7, entries: [said(2, { text: "好，我看看，改了", at: AT + 1000 })] });
  await host.time.pass(500, 10);
  assert.equal(host.emitted.filter(([, m]) => (m as J).id === 1).length, 0, "nothing sent");
  push("thread", { id: 7, entries: [{ thread: 7, n: 7, kind: "edit", target: 1, ts: "7.0", authorKind: "person", author: "a@x.com", text: "先看看列表", at: AT + DAY + 2000 }] });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.deepEqual(v(values, 1).days.map((d: J) => d.items.map((i: J) => [i.seq, i.words])), [[[1, "先看看列表"], [3, "（文件）"]], [[5, "第二天再说"], [6, "还有一件"]]]);
  core.close();
});

test("what_a_chats_outline_finds_is_listed_by_the_day_with_the_line_that_has_the_words", async () => {
  const long = "这是一段很长很长很长很长很长的话，说了好多别的事情之后才说到部署的事";
  const { host, core } = await started({
    ...base(),
    "GET /threads": [threadView(7, 4)],
    "GET /threads/7/entries?limit=50": { first: 1, last: 4, entries: [
      said(1, { authorKind: "person", author: "a@x.com", text: "部署之前先看一下", at: AT }),
      said(2, { authorKind: "person", author: "b@x.com", text: long, at: AT + 1000 }),
      said(3, { text: "第一行\n第二行说**部署**好了\n第三行", at: AT + DAY }),
      said(4, { authorKind: "person", author: "a@x.com", text: "无关", at: AT + DAY + 1000 }),
    ] },
  });
  const ui = core.connect();
  await host.time.pass(500, 10);
  call(core, ui, 1, "chat.outline.find", { station: S, thread: 7, query: "部署" });
  await host.time.pass(500, 10);
  const found = (answers(host.takeEmitted(), 1) as J).ok;
  assert.deepEqual([found.words, found.total, found.held, found.of, found.whole], [["部署"], 3, 4, 4, true]);
  assert.equal(found.days.length, 2);
  const rows = found.days.flatMap((d: J) => d.items);
  assert.deepEqual(rows.map((r: J) => [r.seq, r.mine, r.agent, r.snippet]), [
    // The match at its line's start; one far into a line: its start cut, 12 before it.
    [1, true, false, "部署之前先看一下"],
    [2, false, false, `…${long.slice(long.indexOf("部署") - 12)}`],
    // An agent's, on a later line of it, its marks out.
    [3, false, true, "第二行说部署好了"],
  ]);
  assert.equal(rows[2].by.agent, "k1");
  assert.match(rows[0].clock, /^\d\d:\d\d$/);
  // A line is cut at 120 after where it starts, and never goes on to the next.
  const { excerpt } = await import("../src/refs.ts");
  const cut = excerpt(`${"字".repeat(20)}部署${"长".repeat(200)}\n下一行`, ["部署"], 12, 120).text;
  assert.equal(cut, `…${"字".repeat(12)}部署${"长".repeat(106)}`);
  core.close();
});
