// A station in several workspaces (docs/multi-workspace.md): joining one more through the control plane, kept in
// cloud.json's `joined` as the state frames say it; each workspace's members admitted with their own revocations; the
// station's own settings and the workspaces it joins left to its home workspace's owners and admins.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Fiber, Stream, SubscriptionRef } from "effect";
import { enroll, joinWorkspace, staysIn } from "../src/cli.ts";
import { loadKey } from "../src/cloud/key.ts";
import { makeControlPlane } from "../src/cloud/plane.ts";
import { Cloud } from "../src/cloud/state.ts";
import { applyState } from "../src/cloud/presence.ts";
import { managesStation, verifyMemberOf } from "../src/mesh/credential.ts";
import { routes } from "../src/api/routes/workspaces.ts";
import { FakeControlPlane } from "./fake-control-plane.ts";

/// Looks every 20 ms until `what` holds: what comes over real connections has no event here. No deadline.
const until = async (what: () => boolean) => {
  while (!what()) await new Promise((r) => setTimeout(r, 20));
};

const quietly = async <T>(f: () => Promise<T>): Promise<T> => {
  const said = console.log;
  console.log = () => {};
  try {
    return await f();
  } finally {
    console.log = said;
  }
};

async function enrolled(t: { after(f: () => unknown): void }, joins: boolean) {
  const fake = new FakeControlPlane({ provider: "stillfail", joins });
  const origin = await fake.start();
  const data = mkdtempSync(join(tmpdir(), "multi-"));
  await quietly(() => enroll(data, origin, "tok"));
  const state = new Cloud(data);
  const key = loadKey(data);
  const up = Effect.runSync(SubscriptionRef.make(true));
  const plane = makeControlPlane({ state, changes: Stream.never, key, up });
  const presence = Effect.runFork(plane.presence);
  t.after(async () => {
    await Effect.runPromise(Fiber.interrupt(presence));
    state.close();
    await fake.close();
  });
  await until(() => state.peersCurrent);
  return { fake, data, state, key };
}

test("joining one more workspace keeps the home one, and the state frames say both", async (t) => {
  const { fake, data, state } = await enrolled(t, true);
  assert.deepEqual(state.memberships().map((m) => [m.workspace, m.home]), [["ws1", true]]);
  const joined = await joinWorkspace(data, "join-w2");
  assert.deepEqual(joined, { workspace: "w2", workspace_name: "Team w2", name: "studio" });
  assert.deepEqual(fake.asked.find((a) => a.path === "/v1/stations/join")!.verified, ["stillfail"]);
  // The plane says it on the socket too; the home workspace stays at the top of cloud.json.
  state.reload();
  await until(() => state.memberships().length === 2);
  const file = JSON.parse(readFileSync(join(data, "mesh", "cloud.json"), "utf8"));
  assert.equal(file.workspace, "ws1");
  assert.deepEqual(file.joined.map((j: any) => j.workspace), ["w2"]);
  assert.deepEqual(state.memberships().map((m) => [m.workspace, m.workspace_name, m.home]), [["ws1", "Team", true], ["w2", "Team w2", false]]);
  assert.equal(state.home(), "ws1");
  // Joining it again changes nothing.
  await joinWorkspace(data, "join-w2");
  await until(() => JSON.stringify(state.state!.joined?.map((j) => j.workspace)) === '["w2"]');
  // Left by the plane (removed from that workspace): gone from the file, the home one stays.
  fake.joined = [];
  fake.push(state.state!.station);
  await until(() => state.memberships().length === 1);
  assert.equal(JSON.parse(readFileSync(join(data, "mesh", "cloud.json"), "utf8")).joined, undefined);
  assert.equal(state.removed(), false);
});

test("the installers' enroll (--stay) joins on a station in a workspace, and enrolls one in none or removed from its own", async (t) => {
  const { data } = await enrolled(t, true);
  assert.equal(staysIn(data), true);
  assert.equal(staysIn(mkdtempSync(join(tmpdir(), "multi-"))), false);
  const file = join(data, "mesh", "cloud.json");
  writeFileSync(file, JSON.stringify({ ...JSON.parse(readFileSync(file, "utf8")), removed_at: 1_790_000_000 }));
  assert.equal(staysIn(data), false);
});

test("a control plane from before several workspaces is not asked to move the station", async (t) => {
  const { fake, data, state } = await enrolled(t, false);
  const before = readFileSync(join(data, "mesh", "cloud.json"), "utf8");
  await assert.rejects(joinWorkspace(data, "join-w2"), /cannot add a station to more than one workspace yet; nothing changed/);
  assert.equal(readFileSync(join(data, "mesh", "cloud.json"), "utf8"), before);
  assert.equal(fake.asked.some((a) => a.path === "/v1/stations/enroll" && a.body.toString().includes("join-w2")), false);
  assert.deepEqual(state.memberships().map((m) => m.workspace), ["ws1"]);
});

test("each workspace's members are admitted with that workspace's revocations, and only its own", async (t) => {
  const { fake, data, state } = await enrolled(t, true);
  await joinWorkspace(data, "join-w2");
  state.reload();
  await until(() => state.memberships().length === 2);
  const device = "d".repeat(64);
  const now = Math.floor(Date.now() / 1000);
  const credential = (ws: string, sid = "s1") =>
    fake.grant.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub: "usr_1", email: "a@x", name: "A", ws, role: "admin", device, sid, iat: now - 10, exp: now + 3600 });
  const admit = (c: string) => verifyMemberOf(c, state.grantKeys(), state.memberships(), device);
  assert.equal(admit(credential("ws1")).viewer.workspace, "ws1");
  assert.equal(admit(credential("w2")).viewer.workspace, "w2");
  assert.throws(() => admit(credential("w3")), /another workspace/);
  // Taken back in w2: refused there, still admitted in ws1 (a revoke frame names its workspace).
  applyState(state, JSON.stringify({ type: "revoke", workspace: "w2", kind: "sid", id: "s1", at: now }));
  assert.throws(() => admit(credential("w2")), /revoked/);
  assert.equal(admit(credential("ws1")).viewer.workspace, "ws1");
  // One that names no workspace is the home one's (planes of before).
  applyState(state, JSON.stringify({ type: "revoke", kind: "sid", id: "s2", at: now }));
  assert.throws(() => admit(credential("ws1", "s2")), /revoked/);
  assert.equal(admit(credential("w2", "s2")).viewer.workspace, "w2");
  // A revocation of a workspace it is not in changes nothing.
  applyState(state, JSON.stringify({ type: "revoke", workspace: "w9", kind: "sid", id: "s3", at: now }));
  assert.deepEqual(state.state!.revocations.map((r) => r.id), ["s2"]);
});

test("the workspaces it is in, and joining more, are the say of the managers of any of them", async (t) => {
  const { data, state } = await enrolled(t, true);
  await joinWorkspace(data, "join-w2");
  state.reload();
  await until(() => state.memberships().length === 2);
  const [list, joinRoute] = routes({ cloud: state, data });
  const viewer = (workspace: string, role: string) => ({ sub: "u", email: "a@x", name: "A", role, workspace, device: "d", home: workspace === "ws1" });
  const ask = async (route: typeof list, v: ReturnType<typeof viewer>, body = "") => {
    const answer = await route!.handle({ method: route!.method, path: "/workspaces", query: [], headers: {}, body: Buffer.from(body), viewer: v, lang: "en" } as any, []);
    return [answer.status, JSON.parse(answer.body.toString())];
  };
  assert.ok(managesStation(viewer("ws1", "admin")) && managesStation(viewer("w2", "owner")) && !managesStation(viewer("ws1", "member")) && !managesStation(viewer("w2", "member")));
  assert.deepEqual(await ask(list, viewer("ws1", "owner")), [200, { workspaces: [{ workspace: "ws1", workspaceName: "Team", name: "studio", home: true }, { workspace: "w2", workspaceName: "Team w2", name: "studio", home: false }], canJoin: true }]);
  // A joined workspace's managers alike; members see their own only.
  assert.deepEqual((await ask(list, viewer("w2", "owner")))[1].workspaces.length, 2);
  assert.deepEqual(await ask(list, viewer("w2", "member")), [200, { workspaces: [{ workspace: "w2", workspaceName: "Team w2", name: "studio", home: false }], canJoin: false }]);
  const [status] = await ask(joinRoute, viewer("w2", "member"), JSON.stringify({ token: "join-w3" }));
  assert.equal(status, 403);
  const [ok, joined] = await ask(joinRoute, viewer("w2", "admin"), JSON.stringify({ token: "join-w3" }));
  assert.equal(ok, 200);
  assert.deepEqual(joined.joined, { workspace: "w3", workspaceName: "Team w3", name: "studio" });
});
