// A chat shared with the viewer's other workspaces (views/xshare.ts, docs/chat-share.md): what its "…" shows, and
// `chat.xshare` — the chat's station told first, then each workspace newly given it through one of its own stations
// that answers; shown at once and under way (`doing`) until its station has it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import type { HttpRequest } from "../src/host.ts";
import type { StationAddr } from "../src/station/addr.ts";
import { HostWire, type RequestHead, type StationWire, type WireReply } from "../src/station/wire.ts";
import { jsonResponse, type FakeHost } from "../src/testing.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { base, started, stationReplies, status, threadView } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const ORIGIN = "https://stillfail.test";
const json = (b: Uint8Array | null | undefined) => (b ? JSON.parse(new TextDecoder().decode(b)) : null);

/// What the other workspaces' stations were asked: by station, method and path, with the body.
type Asked = { station: string; method: string; path: string; body: J };

/// `ws/st` as the fixture has it; every other station answers only `PUT /xshare/hosts` (`down`: not reached), and
/// nothing else (its links stay down).
class Wire implements StationWire {
  readonly asked: Asked[] = [];
  readonly down = new Set<string>();
  /// Stations answered as `ws/st` is (by the fixture), besides it.
  readonly served = new Set<string>(["ws/st"]);
  readonly #host: HostWire;
  constructor(host: FakeHost) {
    this.#host = new HostWire(host);
  }
  request(station: StationAddr, head: RequestHead, body: Uint8Array) {
    const at = station.toString();
    if (this.served.has(at)) return this.#host.request(station, head, body);
    const path = head.path.replace("/admin/api", "");
    if (!(head.method === "PUT" && path === "/xshare/hosts")) return Effect.fail(CoreError.host("连不上"));
    this.asked.push({ station: at, method: head.method, path, body: json(body) });
    if (this.down.has(at)) return Effect.fail(CoreError.host("连不上"));
    const bytes = new TextEncoder().encode(JSON.stringify({ ok: true }));
    let given = false;
    const reply: WireReply = { status: 200, headers: [], body: { take: Effect.sync(() => (given ? null : ((given = true), bytes))) }, via: null };
    return Effect.succeed(reply);
  }
}

/// The viewer is in three workspaces: the chat's (`ws`, W, as `role`), 甲 (`wa`, one station) and 丙 (`wc`, two).
async function setUp(role = "admin", thread: J = threadView(7, 3), chats?: J[], roleC = "member") {
  let wire: Wire | null = null;
  const s = await started({ ...base(), "GET /threads": [thread], ...(chats ? { "GET /chats": chats } : {}) }, 0, (host) => (wire = new Wire(host)), ({ host }) => {
    const fetch = host.fetch.bind(host);
    host.fetch = (req: HttpRequest) => {
      const path = req.url.replace(ORIGIN, "");
      if (path === "/v1/me") {
        return Effect.succeed(jsonResponse(200, {
          workspaces: [{ id: "ws", name: "W", role }, { id: "wa", name: "甲", role: "member" }, { id: "wc", name: "丙", role: roleC }],
          invitations: [],
          relay_url: null,
        }));
      }
      if (path === "/v1/workspaces/wa") return Effect.succeed(jsonResponse(200, { id: "wa", role: "member", stations: [{ id: "a1", name: "A1", last_seen: null }] }));
      if (path === "/v1/workspaces/wc") return Effect.succeed(jsonResponse(200, { id: "wc", role: "member", stations: [{ id: "c1", name: "C1", online: true, last_seen: null }, { id: "c2", name: "C2", online: true, last_seen: null }] }));
      return fetch(req);
    };
  });
  await s.host.time.pass(500);
  return { ...s, wire: wire! };
}

/// The chat's station: `PUT /sessions/k1/xshare` answered as it would (the shares asked, `at` 5), its bodies kept;
/// `PUT /xshare/hosts` (`trusted`) answered too, what it was told kept.
function shareAnswers(host: FakeHost, answer?: (body: J) => unknown, trusted: J[] = []) {
  const bodies: J[] = [];
  stationReplies(host, (req) => {
    if (req.method === "PUT" && req.url === `${ORIGIN}/admin/api/xshare/hosts`) {
      trusted.push(json(req.body));
      return { ok: true };
    }
    if (!(req.method === "PUT" && req.url === `${ORIGIN}/admin/api/sessions/k1/xshare`)) return undefined;
    const body = json(req.body);
    bodies.push(body);
    if (answer) return answer(body);
    const to = body.to.map((w: J) => ({ workspace: w.workspace, name: w.name }));
    return { xshare: to.length === 0 ? null : { to, write: body.write, by: "a@x.com", at: 5 } };
  });
  return bodies;
}

function answerOf(host: FakeHost, values: Map<number, unknown>, id: number): J {
  const said = host.takeEmitted();
  const found = said.map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m));
  host.emitted.push(...said);
  apply(host, values);
  return found;
}

test("a_chat_shared_shows_at_once_and_tells_each_new_workspace_through_a_station_that_answers", async () => {
  const { host, core, wire } = await setUp();
  const bodies = shareAnswers(host);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  subscribe(core, ui, 2, { topic: "doing" });
  await host.settle();
  apply(host, values);
  // Not shared: the viewer's other workspaces to tick; an admin of the chat's may. Kept by its thread's first session
  // (a Slack thread's; one of its own has `home`).
  assert.deepEqual(v(values, 1).xshare, {
    session: "k1", text: "未分享", to: [], write: false, may: true,
    places: [{ workspace: "wa", name: "甲", on: false }, { workspace: "wc", name: "丙", on: false }],
  });

  // Shared with both, read only: shown so at once, under way until its station has it.
  const release = host.hold("/sessions/k1/xshare");
  call(core, ui, 3, "chat.xshare", { station: "ws/st", session: "k1", thread: 7, to: ["wa", "wc", "wa"], write: false });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).xshare.text, "甲、丙 · 只读");
  assert.deepEqual(v(values, 1).xshare.places.map((p: J) => p.on), [true, true]);
  assert.deepEqual(v(values, 2).doing.map((d: J) => [d.call, d.params.station, d.params.session, d.stage]), [["chat.xshare", "ws/st", "k1", "running"]]);
  // c1 is not reached: c2, the other of 丙's, is told instead.
  wire.down.add("wc/c1");
  release();
  await host.settle();
  const answered = answerOf(host, values, 3);
  assert.ok(answered && "ok" in answered, JSON.stringify(answered));
  // The chat's station got every workspace with its stations, as the viewer's account has them.
  assert.deepEqual(bodies, [{
    to: [
      { workspace: "wa", name: "甲", stations: [{ id: "a1", name: "A1" }] },
      { workspace: "wc", name: "丙", stations: [{ id: "c1", name: "C1" }, { id: "c2", name: "C2" }] },
    ],
    write: false,
  }]);
  const told = { workspace: "ws", name: "W", station: "st", stationName: "studio" };
  assert.deepEqual(wire.asked, [
    { station: "wa/a1", method: "PUT", path: "/xshare/hosts", body: told },
    { station: "wc/c1", method: "PUT", path: "/xshare/hosts", body: told },
    { station: "wc/c2", method: "PUT", path: "/xshare/hosts", body: told },
  ]);
  // Done: as its station has it now (into its thread as held), nothing under way.
  assert.equal(v(values, 1).xshare.text, "甲、丙 · 只读");
  assert.deepEqual(v(values, 2).doing, []);

  // Down to 甲, its agents sending too: 甲 was told already, nobody is told again.
  call(core, ui, 4, "chat.xshare", { station: "ws/st", session: "k1", thread: 7, to: ["wa"], write: true });
  await host.settle();
  assert.ok("ok" in answerOf(host, values, 4));
  assert.deepEqual(bodies[1], { to: [{ workspace: "wa", name: "甲", stations: [{ id: "a1", name: "A1" }] }], write: true });
  assert.equal(wire.asked.length, 3);
  assert.equal(v(values, 1).xshare.text, "甲 · 可发消息");

  // None: no longer shared.
  call(core, ui, 5, "chat.xshare", { station: "ws/st", session: "k1", thread: 7, to: [] });
  await host.settle();
  assert.ok("ok" in answerOf(host, values, 5));
  assert.deepEqual(bodies[2], { to: [], write: false });
  assert.equal(v(values, 1).xshare.text, "未分享");
  core.close();
});

test("a_share_that_fails_is_shown_as_it_was_and_says_why", async () => {
  const { host, core, wire } = await setUp();
  // A station from before sharing has no such route.
  shareAnswers(host, () => status(404, { error: "no route PUT /sessions/k1/xshare" }));
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  subscribe(core, ui, 2, { topic: "doing" });
  await host.settle();
  call(core, ui, 3, "chat.xshare", { station: "ws/st", session: "k1", thread: 7, to: ["wa"], write: false });
  await host.settle();
  const answered = answerOf(host, values, 3);
  assert.equal(answered.error.message, "此 station 需要更新");
  assert.equal(v(values, 1).xshare.text, "未分享");
  assert.deepEqual(v(values, 2).doing.map((d: J) => [d.call, d.stage, d.error]), [["chat.xshare", "failed", "此 station 需要更新"]]);
  assert.deepEqual(wire.asked, [], "nobody is told of a share its station does not have");
  core.close();
});

test("a_workspace_with_no_station_answering_is_said_by_name", async () => {
  const { host, core, wire } = await setUp();
  shareAnswers(host);
  wire.down.add("wc/c1");
  wire.down.add("wc/c2");
  const ui = core.connect();
  const values = new Map<number, unknown>();
  call(core, ui, 1, "chat.xshare", { station: "ws/st", session: "k1", thread: 7, to: ["wc"], write: false });
  await host.settle();
  assert.equal(answerOf(host, values, 1).error.message, "丙 没有在线的 station");
  core.close();
});

test("a_member_sees_how_it_is_shared_and_its_starter_may_change_it", async () => {
  {
    // Shared by its station with 甲 and with a workspace the viewer is not in: those are named as the station has them.
    const shared = { ...threadView(7, 3), xshare: { to: [{ workspace: "wa", name: "甲" }, { workspace: "wz", name: "Z" }], write: true, by: "b@x.com", at: 5 } };
    const { host, core } = await setUp("member", shared);
    const bodies = shareAnswers(host);
    const ui = core.connect();
    const values = new Map<number, unknown>();
    subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
    await host.settle();
    apply(host, values);
    const x = v(values, 1).xshare;
    assert.equal(x.text, "甲、Z · 可发消息");
    assert.equal(x.may, false);
    assert.deepEqual(x.places, [{ workspace: "wa", name: "甲", on: true }, { workspace: "wc", name: "丙", on: false }]);
    // What the viewer cannot tick stays shared whatever is ticked.
    call(core, ui, 2, "chat.xshare", { station: "ws/st", session: "k1", thread: 7, to: ["wc"], write: true });
    await host.settle();
    assert.deepEqual(bodies[0].to.map((w: J) => w.workspace), ["wc", "wz"]);
    core.close();
  }
  const mine = { ...threadView(7, 3), home: "k0", creator: { id: "a@x.com", name: "a", via: "cloud" }, createdBy: "a@x.com" };
  const { host, core } = await setUp("member", mine);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).xshare.may, true);
  assert.equal(v(values, 1).xshare.session, "k0", "a chat of its own is kept by its home session");
  core.close();
});

test("a_chat_of_another_workspace_referred_to_is_found_by_the_menu_and_shared_with_the_one_it_is_sent_in", async () => {
  // Written in W (`ws/st`), referring to a chat of 丙 (`wc`), whose stations answer as the fixture does.
  const { host, core, wire } = await setUp("admin", threadView(7, 3), [row()]);
  wire.served.add("wc/c1").add("wc/c2");
  const trusted: J[] = [];
  const bodies = shareAnswers(host, undefined, trusted);
  const ui = core.connect();
  const values = new Map<number, unknown>();
  // Nothing typed: the `@` menu in W lists only W's own.
  subscribe(core, ui, 6, { topic: "chatSearch", scope: "ws", query: "", elsewhere: true, limit: 8 });
  // Typed: 丙's chats whose title has it too, after W's own, saying whose.
  subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "部署", elsewhere: true, limit: 8 });
  await host.settle();
  await host.time.pass(500);
  await host.settle();
  await host.time.pass(2000);
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 6).items.map((i: J) => [i.station, i.outside ?? null]), [["ws/st", null]]);
  const items = v(values, 1).items;
  assert.deepEqual(items.map((i: J) => [i.station, i.outside ?? null]), [["ws/st", null], ["wc/c1", "丙"], ["wc/c2", "丙"]]);
  const item = items[1];
  // Picked: its mark kept for W's messages too.
  call(core, ui, 2, "chat.ref", { station: item.station, id: item.id, title: item.title, base: ORIGIN, into: "ws" });
  await host.settle();
  const mark = answerOf(host, values, 2).ok.mark;
  call(core, ui, 3, "chat.outsideRefs", { station: "ws/st", text: `看看 ${mark} 怎么说` });
  await host.settle();
  const found = answerOf(host, values, 3).ok.chats;
  assert.deepEqual(found.map((c: J) => [c.station, c.id, c.workspace, c.workspaceName, c.may]), [["wc/c1", item.id, "wc", "丙", false]]);
  // Its own workspace's chats are never asked about.
  call(core, ui, 4, "chat.outsideRefs", { station: "wc/c1", text: mark });
  await host.settle();
  assert.deepEqual(answerOf(host, values, 4).ok.chats, []);
  // Shared with W (as it was otherwise), W told through the station the message goes to.
  call(core, ui, 5, "chat.xshareAdd", { station: "wc/c1", id: item.id, workspace: "ws", prefer: "ws/st" });
  await host.settle();
  const added = answerOf(host, values, 5);
  assert.ok("ok" in added, JSON.stringify(added));
  assert.equal(bodies.length, 1);
  assert.deepEqual([bodies[0].to.map((w: J) => w.workspace), bodies[0].write], [["ws"], false]);
  assert.deepEqual(trusted.map((t) => [t.workspace, t.name, t.station]), [["wc", "丙", "c1"]]);
  core.close();
});

test("a_chat_already_shared_with_the_workspace_written_in_asks_nothing", async () => {
  const { host, core, wire } = await setUp("admin", threadView(7, 3), [row({ xshare: { to: ["ws"], write: false } })]);
  wire.served.add("wc/c1").add("wc/c2");
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "部", elsewhere: true, limit: 8 });
  await host.settle();
  await host.time.pass(2000);
  await host.settle();
  apply(host, values);
  const item = v(values, 1).items.find((i: J) => i.station === "wc/c1");
  assert.deepEqual(item.xshare, { to: ["ws"], write: false });
  call(core, ui, 2, "chat.ref", { station: item.station, id: item.id, title: item.title, base: ORIGIN, into: "ws" });
  await host.settle();
  const mark = answerOf(host, values, 2).ok.mark;
  call(core, ui, 3, "chat.outsideRefs", { station: "ws/st", text: mark });
  await host.settle();
  assert.deepEqual(answerOf(host, values, 3).ok.chats, []);
  // One whose row is not read: not shared, lest whom it is shared with be lost.
  call(core, ui, 4, "chat.xshareAdd", { station: "wc/c1", id: "nope", workspace: "ws" });
  await host.settle();
  assert.equal(answerOf(host, values, 4).error.code, "not_ready");
  core.close();
});


/// A chat's row as its station lists it (`GET /chats`).
const row = (more: J = {}) => ({ id: "k1", session: "k1", thread: 7, title: "部署", agents: [], last: null, unread: false, mine: true, lastActiveAt: 1, connect: null, origin: null, ...more });

test("what_a_message_refers_to_is_shared_by_the_core_those_the_viewer_may_and_none_else", async () => {
  // An admin of 丙: may share its chats with W; a member (the test above) may not, and nothing is shared.
  for (const [roleC, shared] of [["admin", 1], ["member", 0]] as const) {
    const { host, core, wire } = await setUp("admin", threadView(7, 3), [row()], roleC);
    wire.served.add("wc/c1").add("wc/c2");
    const trusted: J[] = [];
    const bodies = shareAnswers(host, undefined, trusted);
    const ui = core.connect();
    const values = new Map<number, unknown>();
    subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "部署", elsewhere: true, limit: 8 });
    await host.settle();
    await host.time.pass(2000);
    await host.settle();
    apply(host, values);
    const item = v(values, 1).items.find((i: J) => i.station === "wc/c1");
    call(core, ui, 2, "chat.ref", { station: item.station, id: item.id, title: item.title, base: ORIGIN, into: "ws" });
    await host.settle();
    const mark = answerOf(host, values, 2).ok.mark;
    call(core, ui, 3, "chat.outsideShare", { station: "ws/st", text: `看看 ${mark} 怎么说` });
    await host.settle();
    const done = answerOf(host, values, 3);
    assert.deepEqual(done.ok, { shared }, JSON.stringify(done));
    assert.equal(bodies.length, shared);
    if (shared) assert.deepEqual(bodies[0].to.map((w: J) => w.workspace), ["ws"]);
    // Words with no mark: nothing to share.
    call(core, ui, 4, "chat.outsideShare", { station: "ws/st", text: "没有引用" });
    await host.settle();
    assert.deepEqual(answerOf(host, values, 4).ok, { shared: 0 });
    core.close();
  }
});
