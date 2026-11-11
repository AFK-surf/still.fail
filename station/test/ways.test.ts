// A workspace's ways kept by its stations (src/mesh/ways.ts): first as still.fail cloud kept them, then as changed here;
// the newest of two kept; brought level between two stations; read and changed by members' devices (GET/POST /ways);
// added by an agent only once reached as a relay (src/tools/relays.ts).
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import type { Admitted } from "../src/mesh/credential.ts";
import { waysRoute } from "../src/mesh/serve.ts";
import { Ways, WaysRefusal, addRelay, answerWays, followWays, removeRelay, setRelays, setWay, tellWays } from "../src/mesh/ways.ts";
import { relayTools } from "../src/tools/relays.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const OURS = ["https://app.still.fail", "https://39.105.157.122"];
const A = "a".repeat(64);
const B = "b".repeat(64);

/// A station `me` of WS (the other its peer), on still.fail's relays; `ways` what the control plane kept.
function station(me: string, ways?: { relays: string[]; off: string[] }) {
  const data = mkdtempSync(join(tmpdir(), "ways-"));
  writeState(data, { origin: "https://app.still.fail", station: me, workspace: WS, workspace_name: "Team", name: "s", relay_url: OURS[0]!, relay_urls: OURS, grant_keys: { keys: [] }, peers: [], revocations: [] });
  const cloud = new Cloud(data, false);
  applyState(cloud, JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s", origin: "https://app.still.fail", relay_url: OURS[0], relay_urls: OURS, peers: [{ id: A, name: "a" }, { id: B, name: "b" }], revocations: [], ...(ways ? { ways } : {}) }));
  return { cloud, ways: new Ways(cloud, join(data, "mesh", "ways.json")) };
}

const viewer = (role = "member"): Admitted["viewer"] => ({ sub: "ana", email: "ana@x", name: "Ana", role, workspace: WS, device: "d" });

test("the first ways are still.fail cloud's; a change here is kept, survives a restart, and is told", async () => {
  const s = station(A, { relays: ["https://relay.pvg.test:8445/"], off: ["tailnet"] });
  assert.deepEqual(s.ways.view(WS), { relays: [{ url: "https://relay.pvg.test:8445" }], off: ["tailnet"], at: 0, station: "" });
  assert.deepEqual(s.ways.relays(), ["https://relay.pvg.test:8445"]);
  const told: string[] = [];
  const stop = tellWays(s.ways, (event, data) => told.push(`${event} ${JSON.stringify(data)}`));
  const r = addRelay(s.ways, WS, "https://relay.sz.test", "上海中继 chat");
  assert.deepEqual(r.relays, [{ url: "https://relay.pvg.test:8445" }, { url: "https://relay.sz.test", by: "上海中继 chat" }]);
  assert.deepEqual(r.off, ["tailnet"], "what the cloud kept goes on as it was");
  assert.equal(r.station, A);
  assert.deepEqual(told, [`ways {"workspace":"${WS}"}`]);
  stop();
  await s.ways.written();
  const again = new Ways(s.cloud, join(s.cloud.data, "mesh", "ways.json"));
  assert.deepEqual(again.record(WS), r, "kept after a restart");
});

test("what is refused: no relay URL, still.fail's own, a fifth, one not there, the last relay off", () => {
  const s = station(A);
  for (const url of ["ftp://x.test", "not a url", "https://u:p@x.test", "https://x.test/?a=1", "http://x.test"]) assert.throws(() => addRelay(s.ways, WS, url, null), WaysRefusal, url);
  assert.throws(() => addRelay(s.ways, WS, `${OURS[1]}/`, null), /still\.fail's own/);
  for (const n of [1, 2, 3, 4]) addRelay(s.ways, WS, `https://${n}.test`, null);
  addRelay(s.ways, WS, "https://1.test/", null);
  assert.equal(s.ways.view(WS).relays.length, 4, "one already there stays as it is");
  assert.throws(() => addRelay(s.ways, WS, "https://5.test", null), /at most 4/);
  assert.throws(() => removeRelay(s.ways, WS, "https://9.test"), /not one of/);
  // Every relay off but one; the last one stays on.
  for (const u of [...OURS, "https://1.test", "https://2.test", "https://3.test"]) setWay(s.ways, WS, u, false);
  assert.throws(() => setWay(s.ways, WS, "https://4.test", false), /last relay stays on/);
  assert.throws(() => setWay(s.ways, WS, "https://nowhere.test", false), /no such way/);
  setWay(s.ways, WS, "lan", false);
  // A relay taken away goes from those off too.
  removeRelay(s.ways, WS, "https://1.test");
  assert.deepEqual(s.ways.view(WS).off, [...OURS, "https://2.test", "https://3.test", "lan"]);
});

test("the whole list set from the app: who added those already there is kept", () => {
  const s = station(A);
  addRelay(s.ways, WS, "https://keep.test", "agent chat");
  setWay(s.ways, WS, "https://keep.test", false);
  addRelay(s.ways, WS, "https://drop.test", "agent chat");
  setWay(s.ways, WS, "https://drop.test", false);
  const r = setRelays(s.ways, WS, ["https://keep.test/", "https://new.test", OURS[0]], "Ana");
  assert.deepEqual(r.relays, [{ url: "https://keep.test", by: "agent chat" }, { url: "https://new.test", by: "Ana" }]);
  assert.deepEqual(r.off, ["https://keep.test"]);
  assert.throws(() => setRelays(s.ways, WS, ["https://1.test", "https://2.test", "https://3.test", "https://4.test", "https://5.test"], null), /at most 4/);
});

test("of two records the newer is kept: a later time, then the larger station", () => {
  const s = station(A);
  const r = (at: number, station: string, url: string) => ({ relays: [{ url }], off: [], at, station });
  assert.equal(s.ways.take(WS, r(10, A, "https://one.test")), true);
  assert.equal(s.ways.take(WS, r(9, B, "https://old.test")), false);
  assert.equal(s.ways.take(WS, r(10, B, "https://two.test")), true, "the same time: the larger station's");
  assert.equal(s.ways.take(WS, r(10, A, "https://one.test")), false);
  assert.equal(s.ways.view(WS).relays[0]!.url, "https://two.test");
  // A change made here goes after the newest, whatever this machine's clock says.
  assert.ok(addRelay(s.ways, WS, "https://three.test", null).at > 10);
  assert.throws(() => answerWays(s.ways, { method: "ways.put", record: { relays: "x" } }, WS), /malformed/);
});

test("two stations brought level: a change on one reaches the other; a station from before is let be", async () => {
  const a = station(A);
  const b = station(B);
  const byId = new Map([[A, a], [B, b]]);
  const call = async (peer: string, ws: string | null, request: any) => answerWays(byId.get(peer)!.ways, request, ws ?? WS) as any;
  const later: (() => void)[] = [];
  const after = (_ms: number, f: () => void) => { later.push(f); return () => {}; };
  const stopA = followWays(a.ways, call, after);
  const stopB = followWays(b.ways, call, after);
  addRelay(a.ways, WS, "https://relay.pvg.test:8445", "chat on a");
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.deepEqual(b.ways.record(WS), a.ways.record(WS), "b has a's");
  setWay(b.ways, WS, "direct", false);
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.deepEqual(a.ways.view(WS).off, ["direct"], "and a has b's");
  stopA();
  stopB();

  // One that knows no `ways.*`: asked once, not again until this station's ways change.
  const c = station(A);
  let asked = 0;
  const old = async () => { asked += 1; throw new Error("unknown method"); };
  const stop = followWays(c.ways, old, after);
  addRelay(c.ways, WS, "https://x.test", null);
  for (let i = 0; i < 10; i++) await Promise.resolve();
  const was = asked;
  c.cloud.lapsed();
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.equal(asked, was, "not asked again for nothing");
  assert.equal(later.length, 0, "and nothing waits to try it again");
  stop();
});

test("a member's device reads and changes the ways; a read-only member only reads", () => {
  const s = station(A, { relays: [], off: [] });
  const body = (v: unknown) => Buffer.from(JSON.stringify(v));
  assert.deepEqual(waysRoute(s.cloud, "GET", Buffer.alloc(0), viewer()), [200, { relays: [], off: [], at: 0, station: "" }]);
  const [status, said] = waysRoute(s.cloud, "POST", body({ relays: ["https://relay.pvg.test:8445"] }), viewer()) as [number, any];
  assert.equal(status, 200);
  assert.deepEqual(said.relays, [{ url: "https://relay.pvg.test:8445", by: "Ana" }]);
  assert.equal(waysRoute(s.cloud, "POST", body({ way: "lan", on: false }), viewer())[0], 200);
  assert.deepEqual((waysRoute(s.cloud, "GET", Buffer.alloc(0), viewer())[1] as any).off, ["lan"]);
  assert.equal(waysRoute(s.cloud, "POST", body({ relays: ["ftp://x"] }), viewer())[0], 400);
  assert.equal(waysRoute(s.cloud, "POST", body({ nothing: true }), viewer())[0], 400);
  assert.equal(waysRoute(s.cloud, "POST", body({ way: "lan", on: true }), viewer("viewer"))[0], 403);
  for (const u of [...OURS]) waysRoute(s.cloud, "POST", body({ way: u, on: false }), viewer());
  assert.equal(waysRoute(s.cloud, "POST", body({ way: "https://relay.pvg.test:8445", on: false }), viewer())[0], 409);
});

test("an agent adds a relay only once this station reached it as one, by its chat's name", async () => {
  const s = station(A);
  const probed: string[] = [];
  const answers: Record<string, { ok: true; ms: number } | { ok: false; why: string }> = {
    "https://relay.pvg.test:8445": { ok: true, ms: 12 },
    "https://example.test": { ok: false, why: "https://example.test/ping answered 404: not a relay" },
  };
  const [tool] = relayTools({ ways: () => s.ways, workspaceOf: () => WS, by: () => "上海中继", probe: async (url) => { probed.push(url); return answers[url]!; } });
  const run = (args: Record<string, unknown>) => tool!.run("session", args) as Promise<string>;
  const added = JSON.parse(await run({ action: "add", url: "https://relay.pvg.test:8445/" }));
  assert.equal(added.added, "https://relay.pvg.test:8445");
  assert.equal(added.round_trip_ms, 12);
  assert.deepEqual(added.own, [{ url: "https://relay.pvg.test:8445", by: "上海中继" }]);
  assert.deepEqual(added.still_fail, OURS);
  await assert.rejects(run({ action: "add", url: "https://example.test" }), /not added: .*404/);
  await assert.rejects(run({ action: "add", url: "ftp://x" }), /url:/);
  assert.deepEqual(probed, ["https://relay.pvg.test:8445", "https://example.test"], "nothing that is no URL is reached");
  assert.equal(JSON.parse(await run({ action: "list" })).own.length, 1);
  assert.deepEqual(JSON.parse(await run({ action: "remove", url: "https://relay.pvg.test:8445" })).own, []);
  await assert.rejects(run({ action: "remove", url: "https://relay.pvg.test:8445" }), /not removed/);
  const none = relayTools({ ways: () => null, workspaceOf: () => null, by: () => "" })[0]!;
  await assert.rejects(none.run("session", { action: "list" }) as Promise<string>, /in no workspace/);
});

test("a relay the cloud kept as the workspace's own is not taken for still.fail's; a change of it there is told", () => {
  // As the control plane tells it: the workspace's own after still.fail's in relay_urls, and in `ways`.
  const data = mkdtempSync(join(tmpdir(), "ways-"));
  writeState(data, { origin: "https://app.still.fail", station: A, workspace: WS, workspace_name: "Team", name: "s", relay_url: OURS[0]!, relay_urls: OURS, grant_keys: { keys: [] }, peers: [], revocations: [] });
  const cloud = new Cloud(data, false);
  const frame = (own: string[]) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s", origin: "https://app.still.fail", relay_url: OURS[0], relay_urls: [...OURS, ...own], peers: [{ id: A, name: "a" }], revocations: [], ways: { relays: own, off: [] } });
  applyState(cloud, frame(["https://pvg.test:8445"]));
  const ways = new Ways(cloud, join(data, "mesh", "ways.json"));
  const told: string[] = [];
  const stop = tellWays(ways, (_e, data) => told.push(JSON.stringify(data)));
  // Changed on the cloud by an app from before: told, as this station keeps none of its own yet.
  applyState(cloud, frame(["https://pvg.test:8445", "https://sz.test"]));
  assert.deepEqual(told, [`{"workspace":"${WS}"}`]);
  // The app's whole list: the cloud's own relay stays one of the workspace's, not dropped as still.fail's.
  const r = setRelays(ways, WS, ["https://pvg.test:8445", "https://new.test"], "Ana");
  assert.deepEqual(r.relays.map((x) => x.url), ["https://pvg.test:8445", "https://new.test"]);
  assert.deepEqual(addRelay(ways, WS, "https://pvg.test:8445", null).relays.length, 2, "already the workspace's: stays as it is");
  stop();
});
