// What was said in a chat besides words (the `chatThings` view, things.ts): its pictures and videos, its files, its web
// links and its pull requests, each once and the latest first, found among those of each kind by their words; a pull
// request as its card says it; an image opened stepping through all of the chat's held.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply, subscribe, v } from "./helpers.ts";
import { base, started, threadView } from "./station-fixture.ts";
import { linksOf, pullOf, siteOf } from "../src/things.ts";

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

test("a_messages_links_are_those_drawn_and_a_pull_request_is_known_by_its_address", () => {
  // A person's words are not Markdown: their addresses as written bare, without the marks closing them.
  assert.deepEqual(linksOf({ authorKind: "person", text: "[x](https://a.com) 和 https://b.com/c。" }).map((l) => l.url), ["https://a.com", "https://b.com/c"]);
  assert.deepEqual(pullOf("https://github.com/AFK-surf/still.fail/pull/2647/files?w=1"), { repository: "AFK-surf/still.fail", number: 2647 });
  assert.equal(pullOf("https://github.com/acme/app/issues/3"), null);
  assert.equal(pullOf("https://github.com/acme/app/pull/12abc"), null);
  assert.equal(siteOf("https://www.example.com/a/b/?q=1#x"), "www.example.com/a/b");
});
