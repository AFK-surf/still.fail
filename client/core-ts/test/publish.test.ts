// A chat made public (views/publish.ts, docs/public-share.md): the links its "…" lists, put together from what its
// station keeps (`published`); `chat.publishPreview` shaped for the panel, with the workspace's names; `chat.publish`
// shown at once with its link; `chat.unpublish` gone from the list at once, back if its station says no.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { HttpRequest } from "../src/host.ts";
import { jsonResponse, type FakeHost } from "../src/testing.ts";
import { linkOf, linkStation, previewShown, turnOf } from "../src/views/publish.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { base, started, stationReplies, status, threadView } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const ORIGIN = "https://stillfail.test";
const json = (b: Uint8Array | null | undefined) => (b && b.length > 0 ? JSON.parse(new TextDecoder().decode(b)) : null);

/// A station's iroh key as its id has it (hex), and as a link has it (base64url).
const HEX = Array.from({ length: 32 }, (_, i) => i.toString(16).padStart(2, "0")).join("");
const B64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";

/// A snapshot as the station's thread view lists it.
const published = (id: string, at: number, by: string, byName: string) => ({ id, key: `key-${id}`, title: "部署", at, by, byName, size: 10, upto: 3 });

/// The viewer (a@x.com, as the fixture signs in) is `role` in `ws`, whose members are named.
async function setUp(role = "member", thread: J = threadView(7, 3), answers: J = {}) {
  const s = await started({ ...base(), "GET /threads": [thread], ...answers }, 0, undefined, ({ host }) => {
    const fetch = host.fetch.bind(host);
    host.fetch = (req: HttpRequest) => {
      const path = req.url.replace(ORIGIN, "");
      if (path === "/v1/me") return Effect.succeed(jsonResponse(200, { workspaces: [{ id: "ws", name: "W", role }], invitations: [], relay_url: null }));
      if (path === "/v1/workspaces/ws") {
        return Effect.succeed(jsonResponse(200, {
          id: "ws", role, stations: [{ id: "st", name: "studio", online: true, last_seen: null }],
          members: [{ sub: "s1", email: "a@x.com", name: "安", role }, { sub: "s2", email: "b@x.com", name: "Bo", role: "member" }, { sub: "s3", email: "c@x.com", name: "", role: "member" }],
        }));
      }
      return fetch(req);
    };
  });
  await s.host.time.pass(500);
  return s;
}

function answerOf(host: FakeHost, values: Map<number, unknown>, id: number): J {
  const said = host.takeEmitted();
  const found = said.map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m));
  host.emitted.push(...said);
  apply(host, values);
  return found;
}

/// What the station was asked under `/admin/api<prefix>`: method, path and body.
function asked(host: FakeHost, prefix: string): { method: string; path: string; body: J }[] {
  return host.requests.filter((r) => r.url.startsWith(`${ORIGIN}/admin/api${prefix}`)).map((r) => ({ method: r.method, path: r.url.replace(`${ORIGIN}/admin/api`, ""), body: json(r.body) }));
}

test("a_link_is_the_share_origin_with_the_stations_key_in_base64url_and_the_snapshot_after_the_hash", () => {
  assert.equal(linkStation(HEX), B64);
  assert.equal(linkStation(HEX.toUpperCase()), B64);
  assert.equal(linkStation("ff".repeat(32)), "_".repeat(42) + "8");
  assert.equal(linkStation(B64), B64, "one in base64url already stays");
  assert.equal(linkOf(HEX, "abcdefghijklmnop", "k".repeat(43)), `https://share.still.fail/#${B64}.abcdefghijklmnop.${"k".repeat(43)}`);
});

test("a_preview_says_how_many_things_each_message_had_hidden_and_has_its_attachments_as_the_chat_does", () => {
  const shown = previewShown({
    upto: 9,
    title: "部署",
    entries: [
      { n: 4, at: 1_000, authorKind: "person", author: "安", text: "key: [已隐藏]", files: ["f0"], person: "A@x.com" },
      { n: 9, at: 2_000, authorKind: "agent", author: "奏", text: "好了", files: ["f1"], model: "claude-opus-4-1", maker: "anthropic", runtime: "claude" },
    ],
    redacted: [{ n: 4, count: 2 }, { n: 4, count: 1 }],
    files: [
      { k: "f0", name: "a.png", size: 5, type: "image/png", n: 4, width: 4, height: 3, thumbhash: "th", path: "/w/s1/uploads/a.png", owner: "s1" },
      // From a station before `path` and `owner`: a card only.
      { k: "f1", name: "big.zip", size: 11 * 1024 * 1024, type: "application/zip", n: 9 },
    ],
  }, { now: 3_000, offsetMin: 0 }, [{ email: "a@x.com", name: "安", picture: "https://p/a.png" }]);
  assert.equal(shown.upto, 9);
  assert.equal(shown.title, "部署");
  assert.equal(shown.hidden, 3);
  assert.equal(shown.hiddenText, "共隐藏 3 处疑似机密");
  assert.deepEqual(shown.messages.map((m: J) => [m.n, m.author, m.agent, m.hidden, m.hiddenText ?? null, m.files.map((f: J) => [f.k, f.name])]), [[4, "安", false, 3, "已隐藏 3 处", [["f0", "a.png"]]], [9, "奏", true, 0, null, [["f1", "big.zip"]]]]);
  assert.ok(shown.messages[0].time.createdAt.ago, "its time in words");
  // Drawn as the chat draws them: the person by their picture, the agent by its maker's mark.
  assert.deepEqual(shown.messages.map((m: J) => [m.picture ?? null, m.maker?.id ?? null, m.runtime ?? null]), [["https://p/a.png", null, null], [null, "anthropic", "claude"]]);
  assert.deepEqual(shown.files.map((f: J) => f.file), [
    { name: "a.png", path: "/w/s1/uploads/a.png", size: 5, width: 4, height: 3, thumbhash: "th", owner: "s1" },
    { name: "big.zip", path: "", size: 11 * 1024 * 1024 },
  ]);
  assert.equal(shown.files[1].sizeText, "11 MB");
});

test("an_agents_words_in_a_preview_are_read_as_markdown_with_the_files_they_place", () => {
  const shown = previewShown({
    upto: 2,
    entries: [
      { n: 1, at: 1, authorKind: "person", author: "安", text: "看 ![](a.png)", files: ["f0"] },
      { n: 2, at: 2, authorKind: "agent", author: "奏", text: "截图 ![](shot.png)，日志在 `deploy.log`", files: ["f1", "f2"] },
    ],
    files: [
      { k: "f0", name: "a.png", size: 1, type: "image/png", n: 1 },
      { k: "f1", name: "shot.png", size: 1, type: "image/png", n: 2 },
      { k: "f2", name: "deploy.log", size: 1, type: "text/plain", n: 2 },
    ],
  }, { now: 3, offsetMin: 0 });
  // A person's words place nothing and are not read; an agent's place what they link (not a name in code).
  assert.equal(shown.messages[0].placed, undefined);
  assert.equal(shown.messages[0].md, undefined);
  assert.deepEqual(shown.messages[1].placed, ["shot.png"]);
  assert.ok(shown.messages[1].md, "read as Markdown");
});

test("the_chats_links_are_listed_newest_first_and_each_is_revoked_by_its_publisher_or_a_manager", async () => {
  const thread = { ...threadView(7, 3), published: [published("p1", 1_000, "b@x.com", "Bo"), published("p2", 2_000, "A@x.com", "安")] };
  {
    const { host, core } = await setUp("member", thread);
    const ui = core.connect();
    const values = new Map<number, unknown>();
    subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
    await host.settle();
    apply(host, values);
    const p = v(values, 1).publish;
    assert.equal(p.may, true);
    assert.deepEqual(p.links.map((l: J) => [l.id, l.byName, l.mayRevoke, l.createdAt]), [["p2", "安", true, 2_000], ["p1", "Bo", false, 1_000]]);
    // By its station's id (`st` here; a real one is its key in hex, as above).
    assert.equal(p.links[0].link, "https://share.still.fail/#st.p2.key-p2");
    assert.ok(p.links[0].time.createdAt.ago);
    core.close();
  }
  {
    const { host, core } = await setUp("admin", thread);
    const ui = core.connect();
    const values = new Map<number, unknown>();
    subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
    await host.settle();
    apply(host, values);
    assert.deepEqual(v(values, 1).publish.links.map((l: J) => l.mayRevoke), [true, true]);
    core.close();
  }
  // A read-only member publishes nothing; a station from before publishing lists none.
  const { host, core } = await setUp("viewer");
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).publish, { may: false, links: [] });
  core.close();
});

/// The viewer's chat 7 as its station gives its entries, held once its page has been open.
async function holding(entries: J[]) {
  const last = Math.max(...entries.map((e) => e.n));
  const s = await setUp("member", threadView(7, last), { "GET /threads/7/entries?limit=50": { first: Math.min(...entries.map((e) => e.n)), last, entries } });
  const ui = s.core.connect();
  const values = new Map<number, unknown>();
  subscribe(s.core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await s.host.settle();
  await s.host.time.pass(500);
  return { ...s, ui, values };
}

const message = (n: number, authorKind: string, text: string, more: J = {}) => ({
  kind: "message", n, at: n, ts: `t${n}`, thread: 7, authorKind, author: authorKind === "person" ? "a@x.com" : "k1", text, attachments: [], quotes: [], ...more,
});

test("a_preview_is_made_of_what_the_device_holds_of_the_chat_its_secrets_hidden_and_its_station_not_asked", async () => {
  const { host, core, ui, values } = await holding([
    message(1, "person", "部署一下"),
    message(2, "person", "key: sk-ant-abcdefghijklmnopqrstuvwx", { attachments: [{ name: "a.png", path: "/w/uploads/a.png", size: 1 }] }),
    message(3, "agent", "好了"),
  ]);
  // The station busy with something else: nothing of it is waited on.
  const release = host.hold("/threads/7/publish");
  call(core, ui, 3, "chat.publishPreview", { station: "ws/st", thread: 7 });
  await host.settle();
  const answered = answerOf(host, values, 3).ok;
  assert.equal(answered.upto, 3);
  assert.deepEqual(answered.list.map((m: J) => [m.seq, m.text]), [[1, "部署一下"], [2, "key: [已隐藏]"], [3, "好了"]]);
  assert.deepEqual(answered.messages.map((m: J) => [m.n, m.hidden]), [[1, 0], [2, 1], [3, 0]]);
  assert.equal(answered.messages[1].hiddenText, "已隐藏 1 处");
  assert.deepEqual(answered.files.map((f: J) => [f.k, f.n, f.file.path]), [["f0", 2, "/w/uploads/a.png"]]);
  assert.equal(answered.hidden, 1);
  assert.deepEqual(asked(host, "/threads/7/publish"), []);
  release();
  core.close();
});

test("a_previews_messages_are_the_chats_as_its_page_draws_them_cards_and_the_viewers_own_included", async () => {
  const { host, core, ui, values } = await holding([
    message(3, "person", "key: sk-ant-abcdefghijklmnopqrstuvwx"),
    message(4, "agent", "申请使用「Axiom」", { authorModel: "claude-opus-4-1", authorRuntime: "claude",
      card: { type: "options", options: [], vault: { request: "r1", name: "Axiom", mode: "proxy", hosts: ["api.axiom.co"], command: "curl -H \"Authorization: Bearer abcdefghijklmnopqrstuvwxyz\"" } } }),
    message(5, "agent", "**好了**"),
    // An edit of the agent's words since, and its request's card restated with how it ended: as the chat shows them.
    { kind: "edit", n: 6, target: 5, at: 6, thread: 7, authorKind: "agent", author: "k1", text: "**都好了**", attachments: [], quotes: [] },
    { kind: "edit", n: 7, target: 4, at: 7, thread: 7, authorKind: "agent", author: "k1", text: "申请使用「Axiom」", attachments: [], quotes: [],
      card: { type: "options", options: [], vault: { request: "r1", name: "Axiom", mode: "proxy", hosts: ["api.axiom.co"], command: "curl -H \"Authorization: Bearer abcdefghijklmnopqrstuvwxyz\"", outcome: { status: "granted", scope: "chat" } } } },
  ]);
  call(core, ui, 2, "chat.publishPreview", { station: "ws/st", thread: 7 });
  await host.settle();
  const answered = answerOf(host, values, 2).ok;
  const list = answered.list;
  // The viewer's own (theirs by their address), an agent's request about a vault item as its card, an agent's words as
  // edited since, read as Markdown; what was hidden counted where the card has it too.
  assert.deepEqual(list.map((m: J) => [m.seq, m.mine, m.authorKind, m.card?.vaultAsk?.name ?? null, m.text]), [
    [3, true, "person", null, "key: [已隐藏]"],
    [4, false, "agent", "Axiom", "申请使用「Axiom」"],
    [5, false, "agent", null, "**都好了**"],
  ]);
  assert.ok(list[2].md, "read as Markdown");
  assert.deepEqual([list[1].card.vaultAsk.status, list[1].card.vaultAsk.scope], ["granted", "chat"], "how it ended, as the chat says it");
  assert.ok(list[0].time.createdAt.ago, "its time in words");
  assert.equal(answered.hidden, 2);
  core.close();
});

test("a_turn_is_the_persons_words_that_began_it_and_all_said_after_them_until_a_person_speaks_again", () => {
  const said = (kinds: string) => [...kinds].map((k, i) => ({ n: i + 1, authorKind: k === "p" ? "person" : k === "s" ? "stillfail" : "agent" }));
  // asked twice, answered, a notice, answered again; then asked anew
  const chat = said("ppasapa");
  for (const n of [1, 2, 3, 4, 5]) assert.deepEqual(turnOf(chat, n), { from: 1, upto: 5 }, `from message ${n}`);
  assert.deepEqual(turnOf(chat, 7), { from: 6, upto: 7 });
  // an agent's words before anyone asked: from them on; a question not answered yet: itself
  assert.deepEqual(turnOf(said("aap"), 2), { from: 1, upto: 2 });
  assert.deepEqual(turnOf(said("ap"), 2), { from: 2, upto: 2 });
  assert.equal(turnOf(chat, 9), null);
});

test("a_turns_preview_holds_its_messages_their_attachments_and_edits_alone", async () => {
  const png = (name: string) => ({ name, path: `/w/uploads/${name}`, size: 1 });
  const { host, core, ui, values } = await holding([
    message(2, "person", "先查日志"),
    message(3, "person", "key: sk-ant-abcdefghijklmnopqrstuvwx"),
    message(4, "agent", "好", { attachments: [png("a.png")] }),
    message(5, "person", "谢谢", { attachments: [png("b.png")] }),
    { kind: "edit", n: 6, target: 4, at: 6, thread: 7, authorKind: "agent", author: "k1", text: "好了", attachments: [png("a.png")], quotes: [] },
  ]);
  call(core, ui, 2, "chat.publishPreview", { station: "ws/st", thread: 7, turn: 4 });
  await host.settle();
  const answered = answerOf(host, values, 2).ok;
  assert.equal(answered.upto, 4);
  assert.deepEqual(answered.list.map((m: J) => [m.seq, m.text]), [[2, "先查日志"], [3, "key: [已隐藏]"], [4, "好了"]]);
  assert.deepEqual(answered.messages.map((m: J) => m.n), [2, 3, 4]);
  assert.deepEqual(answered.files.map((f: J) => f.k), ["f0"]);
  assert.equal(answered.hidden, 1);
  core.close();
});

test("a_chat_published_shows_its_link_at_once_and_a_revoked_one_goes_at_once", async () => {
  const thread = { ...threadView(7, 3), published: [published("p1", 1_000, "a@x.com", "安")] };
  const { host, core } = await setUp("member", thread);
  let refuse = false;
  stationReplies(host, (req) => {
    if (req.method === "POST" && req.url === `${ORIGIN}/admin/api/threads/7/publish`) return { published: published("p2", 2_000, "a@x.com", "安") };
    if (req.method === "DELETE" && req.url.startsWith(`${ORIGIN}/admin/api/published/`)) return refuse ? status(500, { error: "坏了" }) : { ok: true };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  subscribe(core, ui, 2, { topic: "doing" });
  await host.settle();
  apply(host, values);

  // Under way until the station has kept it; then its link, in the list at once (not read again).
  const release = host.hold("/threads/7/publish");
  call(core, ui, 3, "chat.publish", { station: "ws/st", thread: 7, upto: 3, files: ["f0", "f0"] });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 2).doing.map((d: J) => [d.call, d.params.station, d.params.thread, d.stage]), [["chat.publish", "ws/st", "7", "running"]]);
  release();
  await host.settle();
  const answered = answerOf(host, values, 3);
  assert.equal(answered.ok.link, "https://share.still.fail/#st.p2.key-p2");
  assert.deepEqual(asked(host, "/threads/7/publish"), [{ method: "POST", path: "/threads/7/publish", body: { upto: 3, files: ["f0"], names: { "a@x.com": "安", "b@x.com": "Bo" } } }]);
  assert.deepEqual(v(values, 1).publish.links.map((l: J) => l.id), ["p2", "p1"]);
  assert.deepEqual(v(values, 2).doing, []);

  // Revoked: gone at once, under way until its station answers.
  const held = host.hold("/published/p1");
  call(core, ui, 4, "chat.unpublish", { station: "ws/st", thread: 7, id: "p1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).publish.links.map((l: J) => l.id), ["p2"]);
  assert.deepEqual(v(values, 2).doing.map((d: J) => [d.call, d.params.id, d.stage]), [["chat.unpublish", "p1", "running"]]);
  held();
  await host.settle();
  assert.ok("ok" in answerOf(host, values, 4));
  assert.deepEqual(asked(host, "/published"), [{ method: "DELETE", path: "/published/p1", body: null }]);
  assert.deepEqual(v(values, 1).publish.links.map((l: J) => l.id), ["p2"]);

  // One its station would not revoke comes back, and says why.
  refuse = true;
  call(core, ui, 5, "chat.unpublish", { station: "ws/st", thread: 7, id: "p2" });
  await host.settle();
  const failed = answerOf(host, values, 5);
  assert.ok("error" in failed);
  assert.deepEqual(v(values, 1).publish.links.map((l: J) => l.id), ["p2"]);
  assert.deepEqual(v(values, 2).doing.map((d: J) => [d.call, d.stage]), [["chat.unpublish", "failed"]]);
  core.close();
});
