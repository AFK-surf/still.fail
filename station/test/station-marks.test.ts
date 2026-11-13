// The stations' names and marks kept by the stations (src/mesh/station-marks.ts): none at first (the device goes by
// still.fail cloud's list); this station's own changed by an owner or admin, kept across a restart and told; a copy of
// each brought level between two stations; the newer kept; only a workspace's own stations' given or taken.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import type { Admitted } from "../src/mesh/credential.ts";
import { stationMarksRoute } from "../src/mesh/serve.ts";
import { MarkRefusal, StationMarks, answerMarks, followMarks, markIcon, stationMarksOf, tellMarks } from "../src/mesh/station-marks.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const OURS = ["https://app.still.fail"];
const A = "a".repeat(64);
const B = "b".repeat(64);
const C = "c".repeat(64);
const PICTURE = "https://app.still.fail/v1/icons/0123456789abcdef0123456789abcdef.png";

/// A station `me` of WS, its peers A and B (and `more`).
function station(me: string, more: string[] = []) {
  const data = mkdtempSync(join(tmpdir(), "station-marks-"));
  writeState(data, { origin: "https://app.still.fail", station: me, workspace: WS, workspace_name: "Team", name: "studio", relay_url: OURS[0]!, relay_urls: OURS, grant_keys: { keys: [] }, peers: [], revocations: [] });
  const cloud = new Cloud(data, false);
  applyState(cloud, JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "studio", origin: "https://app.still.fail", relay_url: OURS[0], relay_urls: OURS, peers: [A, B, ...more].map((id) => ({ id, name: id.slice(0, 1) })), revocations: [] }));
  // (the one the routes and the peers' answers go by)
  return { cloud, marks: stationMarksOf(cloud) };
}

const viewer = (role = "admin"): Admitted["viewer"] => ({ sub: "ana", email: "ana@x", name: "Ana", role, workspace: WS, device: "d" });
const body = (v: unknown) => Buffer.from(JSON.stringify(v));

test("none kept at first; this station's own set by an admin, kept after a restart, and told", async () => {
  const s = station(A);
  assert.deepEqual(stationMarksRoute(s.cloud, "GET", Buffer.alloc(0), viewer("member"), false), [200, { marks: {} }]);
  const told: string[] = [];
  const stop = tellMarks(s.marks, (event, data) => told.push(`${event} ${JSON.stringify(data)}`));
  const [status, r] = stationMarksRoute(s.cloud, "PUT", body({ name: "  Studio  Mac ", emoji: "", icon: PICTURE }), viewer(), true) as [number, any];
  assert.equal(status, 200);
  assert.deepEqual({ ...r, at: 0 }, { name: "Studio Mac", emoji: "", icon: PICTURE, at: 0 });
  assert.deepEqual(told, [`stationMarks {"workspace":"${WS}"}`]);
  // Taken away: "" for none; what is left out stays.
  const [, gone] = stationMarksRoute(s.cloud, "PUT", body({ icon: "" }), viewer("owner"), true) as [number, any];
  assert.equal(gone.name, "Studio Mac");
  assert.equal(gone.icon, "");
  assert.ok(gone.at > r.at, "made the newest");
  stop();
  await s.marks.written();
  const again = new StationMarks(s.cloud, join(s.cloud.data, "mesh", "station-marks.json"));
  assert.deepEqual(again.record(A), gone, "kept after a restart");
  assert.deepEqual(stationMarksRoute(s.cloud, "GET", Buffer.alloc(0), viewer("viewer"), false), [200, { marks: { [A]: s.marks.record(A) } }]);
});

test("only an owner or admin changes it, and only to a name, an emoji and an icon as the cloud takes them", () => {
  const s = station(A);
  for (const role of ["member", "viewer"]) assert.equal(stationMarksRoute(s.cloud, "PUT", body({ name: "x" }), viewer(role), true)[0], 403, role);
  assert.equal(stationMarksRoute(s.cloud, "GET", Buffer.alloc(0), viewer(), true)[0], 405, "its own is read in the list");
  assert.equal(stationMarksRoute(s.cloud, "PUT", body({ name: "x" }), viewer(), false)[0], 405, "the list is not written");
  for (const bad of [{ name: "" }, { name: "x".repeat(81) }, { emoji: "a" }, { icon: "https://evil.test/track.png" }, { icon: "data:image/png;base64,AAAA" }, { icon: `${PICTURE}?x=1` }])
    assert.equal(stationMarksRoute(s.cloud, "PUT", body(bad), viewer(), true)[0], 400, JSON.stringify(bad));
  assert.equal(stationMarksRoute(s.cloud, "PUT", Buffer.from("{"), viewer(), true)[0], 400);
  assert.equal(s.marks.record(A), null, "nothing refused was kept");
  // Where it keeps none yet, its name is the cloud's: an icon alone set keeps that name.
  const [, r] = stationMarksRoute(s.cloud, "PUT", body({ emoji: "🦊 and more", icon: "glyph:server:blue" }), viewer(), true) as [number, any];
  assert.deepEqual([r.name, r.emoji, r.icon], ["studio", "🦊", "glyph:server:blue"]);
  assert.equal(markIcon("https://monoid.test/v1/icons/0123456789abcdef0123456789abcdef.webp"), "https://monoid.test/v1/icons/0123456789abcdef0123456789abcdef.webp", "a picture of whichever cloud the device is signed in to");
  assert.throws(() => new StationMarks(station("").cloud).change({ name: "x" }, { name: "", emoji: "", icon: "" }), MarkRefusal);
});

test("a peer's copy: the newer kept; only of the workspace's own stations; a malformed one refused", () => {
  const s = station(A);
  const r = (at: number, name: string) => ({ name, emoji: "", icon: "", at });
  assert.deepEqual(answerMarks(s.marks, { method: "stationMarks.put", marks: { [B]: r(10, "b1") } }, WS), { taken: [B] });
  assert.deepEqual(answerMarks(s.marks, { method: "stationMarks.put", marks: { [B]: r(9, "old") } }, WS), { taken: [] });
  assert.deepEqual(answerMarks(s.marks, { method: "stationMarks.put", marks: { [C]: r(11, "not ours") } }, WS), { taken: [] }, "a station of no workspace here");
  assert.deepEqual(answerMarks(s.marks, { method: "stationMarks.get" }, WS), { marks: { [B]: r(10, "b1") } });
  assert.deepEqual(answerMarks(s.marks, { method: "stationMarks.get" }, "01HYYYYYYYYYYYYYYYYYYYYYYY"), { marks: {} }, "another workspace is given nothing");
  assert.throws(() => answerMarks(s.marks, { method: "stationMarks.put", marks: { [B]: { name: "", at: 12 } } }, WS), /malformed/);
  assert.throws(() => answerMarks(s.marks, { method: "stationMarks.nothing" }, WS), /unknown/);
});

test("two stations brought level: each one's own reaches the other, which gives it while the first is off", async () => {
  const a = station(A);
  const b = station(B);
  const byId = new Map([[A, a], [B, b]]);
  const off = new Set<string>();
  const call = async (peer: string, ws: string | null, request: any) => {
    if (off.has(peer)) throw new Error("station unreachable");
    return answerMarks(byId.get(peer)!.marks, request, ws ?? WS) as any;
  };
  const later: (() => void)[] = [];
  const after = (_ms: number, f: () => void) => { later.push(f); return () => {}; };
  const settle = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
  const stopA = followMarks(a.marks, call, after);
  const stopB = followMarks(b.marks, call, after);
  stationMarksRoute(a.cloud, "PUT", body({ name: "A's", emoji: "🦊", icon: "" }), viewer(), true);
  await settle();
  assert.deepEqual(b.marks.record(A), a.marks.record(A), "b keeps a's");
  stationMarksRoute(b.cloud, "PUT", body({ name: "B's", emoji: "", icon: "glyph:server" }), viewer(), true);
  await settle();
  assert.deepEqual(a.marks.record(B), b.marks.record(B), "and a keeps b's");
  // a is off: b still gives a's to a device.
  off.add(A);
  assert.deepEqual(Object.keys((stationMarksRoute(b.cloud, "GET", Buffer.alloc(0), viewer("member"), false)[1] as any).marks).sort(), [A, B]);
  // b's changed while a is off: tried again later, and a has it once it is back.
  stationMarksRoute(b.cloud, "PUT", body({ name: "B again" }), viewer(), true);
  await settle();
  assert.equal(a.marks.record(B)!.name, "B's");
  assert.equal(later.length, 1, "a retry waits");
  off.delete(A);
  later.shift()!();
  await settle();
  assert.equal(a.marks.record(B)!.name, "B again");
  stopA();
  stopB();

  // One from before knows no `stationMarks.*`: asked once, not again until a record here changes.
  const c = station(A);
  let asked = 0;
  const old = async () => { asked += 1; throw new Error("unknown method"); };
  const stop = followMarks(c.marks, old, after);
  stationMarksRoute(c.cloud, "PUT", body({ name: "x" }), viewer(), true);
  await settle();
  const was = asked;
  c.cloud.lapsed();
  await settle();
  assert.equal(asked, was, "not asked again for nothing");
  stop();
});
