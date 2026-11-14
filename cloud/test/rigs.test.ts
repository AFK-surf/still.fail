// A rig (a station that only runs tasks): a machine a member adds as their own, which only runs what the workspace's stations send it. The
// cloud lists it apart from the stations, with its person; a station's state names the rigs in a field of their own
// (one from before them takes no rig for a station), a rig's the stations and whose it is.
import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

type Harness = Awaited<ReturnType<typeof harness>>;
type As = ReturnType<Harness["as"]>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}
type Station = Awaited<ReturnType<typeof key>>;

const view = async (who: As, workspace: string) => (await (await who("GET", `/v1/workspaces/${workspace}`)).json()) as any;

async function enroll(h: Harness, station: Station, token: string, body: Record<string, unknown> = {}, join = false): Promise<{ status: number; body: any }> {
  const signature = await station.sign(`stillfail-station-enroll-v1:${h.origin}:${token}:${station.id}`);
  const response = await h.fetch(join ? "/v1/stations/join" : "/v1/stations/enroll", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token, station: station.id, signature, version: "0.5.0", ...body }),
  });
  return { status: response.status, body: await response.json() };
}

async function connect(h: Harness, station: Station) {
  const ts = h.now();
  const response = await h.fetch("/v1/stations/connect", {
    headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`) },
  });
  assert.equal(response.status, 101);
  const ws = response.webSocket!;
  const frames: any[] = [];
  const closed = new Promise<number>((resolve) => ws.addEventListener("close", (event) => resolve(event.code), { once: true }));
  ws.addEventListener("message", (event) => void (event.data === "pong" || frames.push(JSON.parse(event.data as string))));
  ws.accept();
  /** The last state it was told since the last time, everything sent for what was done before arrived (h.heard). */
  const state = async () => {
    await h.heard(ws);
    return frames.splice(0).filter((f) => f.type === "state").at(-1);
  };
  return { closed, state };
}

test("a member adds a rig of their own: listed apart from the stations, told to them in a field of its own, gone with its person", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const home = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    assert.equal((await alice("POST", `/v1/workspaces/${home}/members`, { role: "member", emails: ["bob@example.test"] })).status, 200);
    const subOf = async (email: string) => (await view(alice, home)).members.find((m: any) => m.email === email).sub as string;
    const bobSub = await subOf("bob@example.test");

    const station = await key(), rig = await key();
    const stationToken = ((await (await alice("POST", `/v1/workspaces/${home}/enrollments`, { name: "willow" })).json()) as any).token as string;
    assert.equal((await enroll(h, station, stationToken)).status, 200);

    // A member adds one (a station is its managers' to add); one outside the workspace adds none.
    assert.equal((await bob("POST", `/v1/workspaces/${home}/enrollments`, { name: "x" })).status, 403);
    assert.equal((await h.as(await h.login("carol"))("POST", `/v1/workspaces/${home}/rigs/enrollments`, { name: "x" })).status, 404);
    const made = (await (await bob("POST", `/v1/workspaces/${home}/rigs/enrollments`, { name: "build-box" })).json()) as any;
    assert.equal(made.rig, true);
    assert.match(made.install, /install\.sh \| sh -s -- /);

    // Its token makes a rig and nothing else; a station's token makes none.
    assert.deepEqual(await enroll(h, rig, made.token), { status: 409, body: { error: "rig_enrollment" } }, "a station's program from before rigs does not serve under a rig's name");
    const other = ((await (await alice("POST", `/v1/workspaces/${home}/enrollments`, { name: "nas" })).json()) as any).token as string;
    assert.deepEqual(await enroll(h, rig, other, { rig: true }), { status: 409, body: { error: "station_enrollment" } });
    assert.deepEqual(await enroll(h, rig, made.token, { rig: true }, true), { status: 409, body: { error: "rig_enrollment" } }, "a rig joins no second workspace");
    const joined = await enroll(h, rig, made.token, { rig: true });
    assert.equal(joined.status, 200);
    assert.deepEqual(joined.body.rig, { owner: bobSub, owner_email: "bob@example.test", owner_name: "Name of bob" });

    // Listed apart, with its person; the stations' count is the stations'.
    const seen = await view(alice, home);
    assert.deepEqual(seen.stations.map((s: any) => s.id), [station.id]);
    assert.deepEqual(seen.rigs.map((r: any) => [r.id, r.name, r.owner, r.owner_email, r.version]), [[rig.id, "build-box", bobSub, "bob@example.test", "0.5.0"]]);
    assert.equal((((await (await alice("GET", "/v1/me")).json()) as any).workspaces as any[]).find((w) => w.id === home).stations, 1);

    // A station is told the rigs beside its peers; a rig the stations, and whose it is.
    const s = await connect(h, station);
    const told = await s.state();
    assert.deepEqual(told.peers.map((p: any) => p.id), [station.id]);
    assert.deepEqual(told.rigs, [{ id: rig.id, name: "build-box", owner: bobSub, owner_email: "bob@example.test", owner_name: "Name of bob", version: "0.5.0" }]);
    const r = await connect(h, rig);
    const mine = await r.state();
    assert.deepEqual(mine.peers.map((p: any) => p.id), [station.id]);
    assert.deepEqual(mine.rig, { owner: bobSub });
    assert.equal(mine.rigs, undefined);

    // Its person renames it; another member neither renames nor removes it.
    const dave = h.as(await h.login("dave"));
    assert.equal((await alice("POST", `/v1/workspaces/${home}/members`, { role: "member", emails: ["dave@example.test"] })).status, 200);
    assert.equal((await dave("PATCH", `/v1/workspaces/${home}/stations/${rig.id}`, { name: "mine" })).status, 403);
    assert.equal((await dave("DELETE", `/v1/workspaces/${home}/stations/${rig.id}`)).status, 403);
    assert.equal((await bob("PATCH", `/v1/workspaces/${home}/stations/${rig.id}`, { name: "gpu-box" })).status, 200);
    assert.equal((await s.state()).rigs[0].name, "gpu-box");

    // Its person out of the workspace, it leaves with them.
    assert.equal((await alice("DELETE", `/v1/workspaces/${home}/members/${bobSub}`)).status, 200);
    assert.equal(await r.closed, 4004);
    assert.equal((await view(alice, home)).rigs, undefined);
    assert.equal((await s.state()).rigs, undefined, "nothing said with none, as before there were any");
  } finally {
    await h.close();
  }
});

test("a station's mode is its owner's, who added it: made one that only runs tasks, still theirs, and whole again", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const carol = h.as(await h.login("carol"));
    const home = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    assert.equal((await alice("POST", `/v1/workspaces/${home}/members`, { role: "member", emails: ["bob@example.test"] })).status, 200);
    assert.equal((await alice("POST", `/v1/workspaces/${home}/members`, { role: "admin", emails: ["carol@example.test"] })).status, 200);
    const subOf = async (email: string) => (await view(alice, home)).members.find((m: any) => m.email === email).sub as string;
    const carolSub = await subOf("carol@example.test"), bobSub = await subOf("bob@example.test");
    // Alice (the workspace's owner) adds the first, Carol (an admin) the second.
    const first = await key(), second = await key();
    for (const [who, station, name] of [[alice, first, "willow"], [carol, second, "nas"]] as const) {
      const token = ((await (await who("POST", `/v1/workspaces/${home}/enrollments`, { name })).json()) as any).token as string;
      assert.equal((await enroll(h, station, token)).status, 200);
    }
    const a = await connect(h, first), b = await connect(h, second);
    await a.state();
    await b.state();
    const mode = (who: As, station: Station, to: string) => who("PATCH", `/v1/workspaces/${home}/stations/${station.id}`, { mode: to });

    // Its adder's alone: a member is refused, and so is the workspace's owner, who did not add it.
    assert.equal((await mode(bob, second, "tasks")).status, 403);
    assert.equal((await mode(alice, second, "tasks")).status, 403);
    assert.equal((await mode(carol, second, "sideways")).status, 400);
    assert.equal((await mode(carol, second, "tasks")).status, 200);
    // Still the adder's.
    const seen = await view(alice, home);
    assert.deepEqual(seen.stations.map((s: any) => s.id), [first.id]);
    assert.deepEqual(seen.rigs.map((r: any) => [r.id, r.name, r.owner]), [[second.id, "nas", carolSub]]);
    // Both are told at once: the others that it is a rig now, itself whose.
    assert.deepEqual((await a.state()).rigs.map((r: any) => r.id), [second.id]);
    const told = await b.state();
    assert.deepEqual(told.rig, { owner: carolSub });
    assert.deepEqual(told.peers.map((p: any) => p.id), [first.id]);
    // Said again, nothing changes; the workspace keeps one whole station.
    assert.equal((await mode(carol, second, "tasks")).status, 200);
    assert.deepEqual(await (await mode(alice, first, "tasks")).json(), { error: "last_station" });

    // Whole again: its owner's, not another manager's; among the stations, told as one.
    assert.equal((await mode(alice, second, "full")).status, 403);
    assert.equal((await mode(bob, second, "full")).status, 403);
    assert.equal((await mode(carol, second, "full")).status, 200);
    assert.deepEqual((await view(alice, home)).stations.map((s: any) => s.id), [first.id, second.id]);
    assert.equal((await view(alice, home)).rigs, undefined);
    assert.equal((await b.state()).rig, undefined);
    assert.equal((await a.state()).rigs, undefined);

    // One a plain member added stays one that only runs tasks: they add no whole station, and a manager may not make it one.
    const box = await key();
    const made = (await (await bob("POST", `/v1/workspaces/${home}/rigs/enrollments`, { name: "build-box" })).json()) as any;
    assert.equal((await enroll(h, box, made.token, { rig: true })).status, 200);
    assert.equal((await mode(bob, box, "full")).status, 403);
    assert.equal((await mode(alice, box, "full")).status, 403);
    assert.deepEqual((await view(alice, home)).rigs.map((r: any) => [r.id, r.owner]), [[box.id, bobSub]]);

    // A station in a second workspace stays a whole one.
    const other = ((await (await carol("POST", "/v1/workspaces", { name: "Other" })).json()) as any).id as string;
    const join = ((await (await carol("POST", `/v1/workspaces/${other}/enrollments`, { name: "nas" })).json()) as any).token as string;
    assert.equal((await enroll(h, second, join, {}, true)).status, 200);
    assert.deepEqual(await (await mode(carol, second, "tasks")).json(), { error: "station_in_others" });
  } finally {
    await h.close();
  }
});

test("a station whose adder is no member any more: the workspace's owner makes it one that only runs tasks, and it is theirs; an admin does not", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const carol = h.as(await h.login("carol"));
    const dave = h.as(await h.login("dave"));
    const home = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    assert.equal((await alice("POST", `/v1/workspaces/${home}/members`, { role: "admin", emails: ["carol@example.test", "dave@example.test"] })).status, 200);
    const subOf = async (email: string) => (await view(alice, home)).members.find((m: any) => m.email === email).sub as string;
    const aliceSub = await subOf("alice@example.test"), carolSub = await subOf("carol@example.test");
    const first = await key(), second = await key();
    for (const [who, station, name] of [[alice, first, "willow"], [carol, second, "nas"]] as const) {
      const token = ((await (await who("POST", `/v1/workspaces/${home}/enrollments`, { name })).json()) as any).token as string;
      assert.equal((await enroll(h, station, token)).status, 200);
    }
    const mode = (who: As, station: Station, to: string) => who("PATCH", `/v1/workspaces/${home}/stations/${station.id}`, { mode: to });
    assert.equal((await mode(alice, second, "tasks")).status, 403, "its adder is a member: theirs");

    // Its adder gone, the station stays, nobody's to change but the workspace's owner's.
    assert.equal((await alice("DELETE", `/v1/workspaces/${home}/members/${carolSub}`)).status, 200);
    assert.deepEqual((await view(alice, home)).stations.map((s: any) => s.id), [first.id, second.id]);
    assert.equal((await mode(dave, second, "tasks")).status, 403);
    assert.equal((await mode(alice, second, "tasks")).status, 200);
    assert.deepEqual((await view(alice, home)).rigs.map((r: any) => [r.id, r.owner]), [[second.id, aliceSub]]);
    // Theirs now: whole again is theirs too, not the other admin's.
    assert.equal((await mode(dave, second, "full")).status, 403);
    assert.equal((await mode(alice, second, "full")).status, 200);
  } finally {
    await h.close();
  }
});

test("a rig's person removes it themselves", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const bob = h.as(await h.login("bob"));
    const home = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    assert.equal((await alice("POST", `/v1/workspaces/${home}/members`, { role: "member", emails: ["bob@example.test"] })).status, 200);
    const rig = await key();
    const made = (await (await bob("POST", `/v1/workspaces/${home}/rigs/enrollments`, { name: "build-box" })).json()) as any;
    assert.equal((await enroll(h, rig, made.token, { rig: true })).status, 200);
    const r = await connect(h, rig);
    assert.equal((await bob("DELETE", `/v1/workspaces/${home}/stations/${rig.id}`)).status, 200);
    assert.equal(await r.closed, 4004);
  } finally {
    await h.close();
  }
});

test("the installers pass a rig's command on: `rig:<person>` after the token (and a lock's hash), as `--rig <person>`", async () => {
  const { installScript } = await import("../src/install.ts");
  const { windowsInstallScript } = await import("../src/install-windows.ts");
  const sh = installScript("https://ember.test");
  assert.match(sh, /case "\$lock" in rig:\*\) rig="\$lock" lock="" ;; esac/);
  assert.match(sh, /station enroll "\$origin" "\$token" --stay \$\{lock:\+--lock "\$lock"\} \$\{rig:\+--rig "\$\{rig#rig:\}"\}/);
  const ps = windowsInstallScript("https://ember.test");
  assert.match(ps, /if \(\$Lock -like 'rig:\*'\) \{ \$Rig = \$Lock; \$Lock = '' \}/);
  assert.match(ps, /if \(\$Rig\) \{ \$pin \+= @\('--rig', \$Rig\.Substring\(4\)\) \}/);
});
