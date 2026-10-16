// One station in several workspaces (views/memberships.ts, docs/multi-workspace.md): which stations of the viewer's
// other workspaces could be added to one (`joinable`), `station.join` (an enrollment made there, the station told to
// join with it over its home link) and what it says when it cannot, and the workspaces a station is in.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import type { HttpRequest } from "../src/host.ts";
import type { StationAddr } from "../src/station/addr.ts";
import { HostWire, type RequestHead, type StationWire, type WireReply } from "../src/station/wire.ts";
import { jsonResponse, type FakeHost } from "../src/testing.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { base, overview, started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const ORIGIN = "https://stillfail.test";

/// What a station other than `ws/st` answers, by `<address> <METHOD> <path>`: a body (200), or `[status, body]`.
type Table = Record<string, unknown>;

/// `ws/st` as the fixture has it; every other station answers from `table`, what it was asked kept.
class Wire implements StationWire {
  readonly asked: { station: string; method: string; path: string; body: J }[] = [];
  readonly table: Table = {};
  readonly #host: HostWire;
  constructor(host: FakeHost) {
    this.#host = new HostWire(host);
  }
  request(station: StationAddr, head: RequestHead, body: Uint8Array) {
    const at = station.toString();
    if (at === "ws/st") return this.#host.request(station, head, body);
    const path = head.path.replace("/admin/api", "");
    this.asked.push({ station: at, method: head.method, path, body: body.length > 0 ? JSON.parse(new TextDecoder().decode(body)) : null });
    const key = `${at} ${head.method} ${path}`;
    if (!(key in this.table)) return Effect.fail(CoreError.host("连不上"));
    const said = this.table[key];
    const [code, answer] = Array.isArray(said) ? (said as [number, unknown]) : [200, said];
    const bytes = new TextEncoder().encode(JSON.stringify(answer));
    let given = false;
    const reply: WireReply = { status: code, headers: [], body: { take: Effect.sync(() => (given ? null : ((given = true), bytes))) }, via: null };
    return Effect.succeed(reply);
  }
}

/// The viewer: an admin of W (`ws`, the fixture's `st`, and x1, which W joined: its home is 甲), the owner of 甲 (`wa`:
/// a1 up, a2 joined from elsewhere, st which 甲 joined, x1), a member of 丙 (`wc`, c1) and an admin of 乙 (`wb`, b1
/// down). What still.fail cloud was asked to make (enrollments) is kept.
async function setUp(o: { stJoined?: boolean; answers?: ReturnType<typeof base> } = {}) {
  let wire: Wire | null = null;
  const made: { path: string; body: J }[] = [];
  const s = await started(o.answers ?? base(), 0, (host) => (wire = new Wire(host)), ({ host }) => {
    const fetch = host.fetch.bind(host);
    host.fetch = (req: HttpRequest) => {
      const path = req.url.replace(ORIGIN, "");
      const ws = (id: string, stations: J[]) => Effect.succeed(jsonResponse(200, { id, stations }));
      if (path === "/v1/me") {
        return Effect.succeed(jsonResponse(200, {
          workspaces: [{ id: "ws", name: "W", role: "admin" }, { id: "wa", name: "甲", role: "owner" }, { id: "wc", name: "丙", role: "member" }, { id: "wb", name: "乙", role: "admin" }],
          invitations: [],
          relay_url: null,
        }));
      }
      if (path === "/v1/workspaces/ws") return ws("ws", [{ id: "st", name: "studio", online: true, last_seen: null, ...(o.stJoined ? { joined: true } : {}) }, { id: "x1", name: "X1", online: true, last_seen: null, joined: true }]);
      if (path === "/v1/workspaces/wa") {
        return ws("wa", [
          { id: "a1", name: "A1", online: true, last_seen: null },
          { id: "a2", name: "A2", online: true, last_seen: null, joined: true },
          { id: "st", name: "studio", online: true, last_seen: null, ...(o.stJoined ? {} : { joined: true }) },
          { id: "x1", name: "X1", online: true, last_seen: null },
        ]);
      }
      if (path === "/v1/workspaces/wc") return ws("wc", [{ id: "c1", name: "C1", online: true, last_seen: null }]);
      if (path === "/v1/workspaces/wb") return ws("wb", [{ id: "b1", name: "B1", online: false, last_seen: null }]);
      if (req.method === "POST" && path === "/v1/workspaces/ws/enrollments") {
        made.push({ path, body: JSON.parse(new TextDecoder().decode(req.body!)) });
        return Effect.succeed(jsonResponse(200, { token: "tok-1", expires_at: 1, install: "", command: "" }));
      }
      return fetch(req);
    };
  });
  await s.host.time.pass(500);
  return { ...s, wire: wire!, made };
}

function answerOf(host: FakeHost, values: Map<number, unknown>, id: number): J {
  const said = host.takeEmitted();
  const found = said.map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m));
  host.emitted.push(...said);
  apply(host, values);
  return found;
}

/// The workspaces `wa/a1` is in once it joined W, as its admin API answers.
const BOTH = [{ workspace: "wa", workspaceName: "甲", name: "A1", home: true }, { workspace: "ws", workspaceName: "W", name: "A1", home: false }];

test("the stations to add are those whose home the viewer manages and that are not in the workspace", async () => {
  const { host, core } = await setUp();
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "joinable", workspace: "ws" });
  subscribe(core, ui, 2, { topic: "stations", scope: "ws" });
  await host.settle();
  apply(host, values);
  // a2 and st are not 甲's own; x1 is in W already; 丙's the viewer does not manage.
  assert.deepEqual(v(values, 1), {
    offered: true,
    loading: false,
    items: [
      { station: "wa/a1", id: "a1", name: "A1", workspace: "wa", workspaceName: "甲", online: true, line: "甲 · 在线" },
      { station: "wb/b1", id: "b1", name: "B1", workspace: "wb", workspaceName: "乙", online: false, line: "乙 · 离线" },
    ],
  });
  // In W's list, the one W joined says so, and where it is from.
  const listed = (v(values, 2) as J[]).map((s) => [s.id, s.joined, s.home ?? null]);
  assert.deepEqual(listed, [["st", false, null], ["x1", true, "甲"]]);
  core.close();
});

test("a_station_joins_with_an_enrollment_of_the_workspace_over_its_home_link", async () => {
  const { host, core, wire, made } = await setUp();
  wire.table["wa/a1 POST /workspaces/join"] = { joined: { workspace: "ws", workspaceName: "W", name: "A1" }, workspaces: BOTH, canJoin: true };
  wire.table["wa/a1 GET /workspaces"] = { workspaces: BOTH, canJoin: true };
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "doing" });
  await host.settle();
  call(core, ui, 2, "station.join", { workspace: "ws", station: "wa/a1" });
  await host.settle();
  const answered = answerOf(host, values, 2);
  assert.deepEqual(answered.ok, { joined: { workspace: "ws", workspaceName: "W", name: "A1" } });
  // Made in W under its name in 甲; the token taken to the station over 甲's link.
  assert.deepEqual(made, [{ path: "/v1/workspaces/ws/enrollments", body: { name: "A1" } }]);
  assert.deepEqual(wire.asked.filter((a) => a.path === "/workspaces/join"), [{ station: "wa/a1", method: "POST", path: "/workspaces/join", body: { token: "tok-1" } }]);
  assert.deepEqual(v(values, 1).doing, []);

  // Its workspaces, its home first.
  subscribe(core, ui, 3, { topic: "memberships", station: "wa/a1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 3), {
    manages: true,
    loading: false,
    canJoin: true,
    workspaces: [
      { workspace: "wa", name: "甲", stationName: "A1", home: true, here: true, line: "主 workspace" },
      { workspace: "ws", name: "W", stationName: "A1", home: false, here: false, line: "加入的 workspace" },
    ],
  });

  core.close();
});

test("a_station_that_cannot_join_says_why_in_words", async () => {
  const cases: [unknown, string][] = [
    // A station from before several workspaces: no such route.
    [[404, { error: "no route POST /workspaces/join" }], "此 station 尚不支持加入多个 workspace，请先更新"],
    // A cloud from before them: the station says so.
    [[409, { error: "still.fail cannot add a station to more than one workspace yet; nothing changed" }], "cloud 尚不支持一台 station 加入多个 workspace，未做任何更改"],
    [[409, { error: "still.fail answered 409: {\"error\":\"locked_workspace\"}" }], "此 station 所在的 workspace 已开启安全模式，只能加入同样开启安全模式的 workspace"],
    [[409, { error: "something else" }], "无法加入：something else"],
  ];
  for (const [said, words] of cases) {
    const { host, core, wire } = await setUp();
    wire.table["wa/a1 POST /workspaces/join"] = said;
    const ui = core.connect();
    const values = new Map<number, unknown>();
    subscribe(core, ui, 1, { topic: "doing" });
    await host.settle();
    call(core, ui, 2, "station.join", { workspace: "ws", station: "wa/a1" });
    await host.settle();
    assert.equal(answerOf(host, values, 2).error.message, words);
    assert.deepEqual(v(values, 1).doing.map((d: J) => [d.call, d.params.workspace, d.params.station, d.stage, d.error]), [["station.join", "ws", "wa/a1", "failed", words]]);
    core.close();
  }
});

test("only_the_managers_of_a_station's_home_see_its_workspaces", async () => {
  const { host, core, wire } = await setUp();
  wire.table["wc/c1 GET /workspaces"] = { workspaces: [{ workspace: "wc", workspaceName: "丙", name: "C1", home: true }], canJoin: false };
  const ui = core.connect();
  const values = new Map<number, unknown>();
  // A member of 丙; and x1 in W, which W joined (its home is 甲): neither is asked.
  subscribe(core, ui, 1, { topic: "memberships", station: "wc/c1" });
  subscribe(core, ui, 2, { topic: "memberships", station: "ws/x1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1), { manages: false, loading: false, canJoin: false, workspaces: [] });
  assert.deepEqual(v(values, 2), { manages: false, loading: false, canJoin: false, workspaces: [] });
  assert.deepEqual(wire.asked.filter((a) => a.path === "/workspaces"), []);
  // A station from before several workspaces: in its home one alone, said so.
  wire.table["wa/a1 GET /workspaces"] = [404, { error: "no route GET /workspaces" }];
  subscribe(core, ui, 3, { topic: "memberships", station: "wa/a1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 3), { manages: true, loading: false, canJoin: false, workspaces: [], error: "此 station 尚不支持加入多个 workspace，请先更新" });
  core.close();
});

test("a_new_chat_on_a_joined_station_none_of_whose_profiles_is_open_here_says_whom_to_ask", async () => {
  // st's home is 甲; W joined it, and none of its profiles is open to W (its overview to W lists none).
  const { host, core } = await setUp({ stJoined: true, answers: { ...base(), "GET /overview": { ...overview, profiles: [] } } });
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "newChat", scope: "ws" });
  await host.settle();
  apply(host, values);
  const n = v(values, 1);
  assert.equal(n.station.id, "st");
  assert.equal(n.blocked, "shared");
  assert.equal(n.problem, "studio 属于 甲，其 Profile 尚未对此 workspace 开放：请 甲 的管理员在 Profile 页开启「同时用于 W」");
  core.close();
});
