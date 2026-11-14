// Presets and starred models carried by their person's devices (src/sessions/presets.ts, src/api/routes/presets.ts and
// stars.ts; the rule both sides keep by, client/core-ts/src/preset-records.ts): two stations that never talk to each
// other, and a few lines of a device that reads both and brings each what it lacks.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type KeptRecord, type Star, canonical, mergeStars, newerRecord, newerStar, recordOf } from "../../client/core-ts/src/preset-records.ts";
import { Presets, presetCopyOf } from "../src/sessions/presets.ts";
import { routes as presetRoutes } from "../src/api/routes/presets.ts";
import { routes as starRoutes } from "../src/api/routes/stars.ts";
import { mergePresets } from "../src/replica/agent-carry.ts";
import { newSession, say as sayIn } from "../src/sessions/lifecycle.ts";
import { Rig, settle } from "./hub-fakes.ts";

type Viewer = { sub: string; email: string };
const ME: Viewer = { sub: "u-me", email: "me@x.io" };
const YOU: Viewer = { sub: "u-you", email: "you@x.io" };

/// A station of workspace `ws` with id `id`: its presets in a directory of its own, its routes asked as a device asks.
function station(id: string, clock: { now: number }) {
  const home = mkdtempSync(join(tmpdir(), `carried-${id}-`));
  const presets = new Presets(() => home, () => ++clock.now, { station: () => id, workspace: (ws) => ws ?? "ws" });
  let told = 0;
  const list = presetRoutes({ presets, reposDir: () => join(home, "repos"), changed: () => told++ });
  const ask = async (method: string, path: string, who: Viewer, body?: unknown) => {
    const route = list.find((r) => r.method === method && r.pattern.test(path))!;
    const found = route.pattern.exec(path)!;
    const r = { method, path, query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer: { ...who, name: "", role: "member", workspace: "ws", device: "d" } as never, lang: "en" as const };
    const answer = await route.handle(r as never, found.slice(1));
    return { status: answer.status, body: JSON.parse((answer.body as Buffer).toString()) };
  };
  return { id, home, presets, ask, told: () => told };
}
type Station = ReturnType<typeof station>;

/// A device of `who`'s: what it keeps of their records, by id.
type Device = Map<string, KeptRecord>;
const take = (d: Device, r: KeptRecord) => {
  const was = d.get(r.id);
  d.set(r.id, was === undefined ? r : newerRecord(was, r));
};
/// The device's link to each of `up` opens: it reads each one's records, keeps the newer of each, and brings each what
/// it lacks (what it holds newer than that station's).
async function carry(d: Device, who: Viewer, up: Station[]): Promise<void> {
  const theirs = new Map<string, Map<string, KeptRecord>>();
  for (const s of up) {
    const got = await s.ask("GET", "/presets/kept", who);
    assert.equal(got.status, 200);
    theirs.set(s.id, new Map(got.body.records.map((r: KeptRecord) => [r.id, r])));
    for (const r of got.body.records) take(d, r);
  }
  for (const s of up) {
    const held = theirs.get(s.id)!;
    const lacking = [...d.values()].filter((r) => {
      const t = held.get(r.id);
      return t === undefined || (canonical(t) !== canonical(r) && newerRecord(t, r) === r);
    });
    if (lacking.length === 0) continue;
    const put = await s.ask("PUT", "/presets/kept", who, { records: lacking });
    assert.equal(put.status, 200);
    assert.deepEqual(put.body.refused, []);
    for (const r of put.body.records) take(d, r);
  }
}

const live = async (s: Station, who: Viewer) => (await s.ask("GET", "/presets/kept", who)).body.records.filter((r: KeptRecord) => !("gone" in r));

/// Every order of `xs`.
function orders<T>(xs: T[]): T[][] {
  if (xs.length <= 1) return [xs];
  return xs.flatMap((x, i) => orders([...xs.slice(0, i), ...xs.slice(i + 1)]).map((rest) => [x, ...rest]));
}

const base = { id: "p-1", name: "Work", dirs: [{ path: "/a", repo: null, station: "ws/sa" }], instructions: "", createdBy: ME.email, createdAt: 1, owner: ME.sub, home: "sa" };

test("of the same records the newer is one, whatever order they are folded in", () => {
  const records: KeptRecord[] = [
    recordOf({ ...base, rev: 2, updatedAt: 10 }),
    recordOf({ ...base, rev: 2, updatedAt: 10, name: "Other" }),
    recordOf({ ...base, rev: 2, updatedAt: 30 }),
    recordOf({ id: "p-1", owner: ME.sub, rev: 2, gone: true, updatedAt: 5 }),
    recordOf({ ...base, rev: 1, updatedAt: 99 }),
    recordOf({ ...base, rev: 3, updatedAt: 1 }),
  ];
  const results = new Set(orders(records).map((o) => canonical(o.reduce((a, b) => newerRecord(a, b)))));
  assert.equal(results.size, 1);
  assert.deepEqual(JSON.parse([...results][0]!).rev, 3, "the most changes wins, whatever its time");
  // of the same rev, the deleted one; then the later; then the larger text, the same either way round
  const two = records.slice(0, 4);
  assert.equal(new Set(orders(two).map((o) => canonical(o.reduce((a, b) => newerRecord(a, b))))).size, 1);
  assert.ok("gone" in two.reduce((a, b) => newerRecord(a, b)));
  assert.equal(canonical(newerRecord(records[0]!, records[1]!)), canonical(newerRecord(records[1]!, records[0]!)));
  // what both sides make of a record is what they make of that again
  const made = recordOf({ ...base, name: " Work ", rev: 1, updatedAt: 1, stations: ["s1"], model: { model: " opus ", profiles: ["a", "a"] }, dirs: [base.dirs[0], base.dirs[0]] });
  assert.equal(canonical(recordOf(made)), canonical(made));
  assert.deepEqual((made as { dirs: unknown[] }).dirs.length, 1);
  assert.throws(() => recordOf({ ...base, rev: 0, updatedAt: 1 }), /rev/);
  assert.throws(() => recordOf({ ...base, rev: 1, updatedAt: 1, dirs: [{ path: "/a", repo: null }] }), /station/);
});

test("stars: of two of a model the higher rev, then the unstarring, then the later; merged model by model", () => {
  const stars: Star[] = [{ on: true, rev: 2, at: 5 }, { on: false, rev: 2, at: 1 }, { on: true, rev: 1, at: 50 }, { on: true, rev: 2, at: 9 }];
  assert.equal(new Set(orders(stars).map((o) => JSON.stringify(o.reduce((a, b) => newerStar(a, b))))).size, 1);
  assert.deepEqual(stars.reduce((a, b) => newerStar(a, b)), { on: false, rev: 2, at: 1 });
  const merged = mergeStars({ opus: { on: true, rev: 1, at: 1 }, sonnet: { on: true, rev: 3, at: 2 } }, { opus: { on: false, rev: 2, at: 1 }, sonnet: { on: false, rev: 1, at: 9 }, gpt: { on: true, rev: 1, at: 7 } });
  assert.deepEqual(merged, { gpt: { on: true, rev: 1, at: 7 }, opus: { on: false, rev: 2, at: 1 }, sonnet: { on: true, rev: 3, at: 2 } });
});

test("a device carries its person's presets between two stations that never talk: they come to the same, a deletion stays", async () => {
  const clock = { now: 1000 };
  const a = station("sa", clock);
  const b = station("sb", clock);
  const phone: Device = new Map();

  // made on A by an app from before; carried to B by the device
  const made = await a.ask("POST", "/presets", ME, { name: "Work", dirs: [], instructions: "Be brief." });
  assert.equal(made.status, 200);
  assert.deepEqual([made.body.rev, made.body.owner, made.body.home], [1, ME.sub, "sa"]);
  await carry(phone, ME, [a, b]);
  assert.deepEqual(await live(b, ME), await live(a, ME), "the same record on both");
  assert.ok(b.told() > 0, "B's devices told");
  // B's agents open with it; an app from before on B is not listed it (it is A's)
  assert.equal(b.presets.list("ws").length, 1);
  assert.deepEqual((await b.ask("GET", "/presets", ME)).body.presets, []);
  assert.equal((await a.ask("GET", "/presets", ME)).body.presets.length, 1);

  // deleted on A (an app from before) while B was away: B's live one is not brought back to A
  const id = made.body.id;
  assert.equal((await a.ask("DELETE", `/presets/${id}`, ME)).status, 200);
  await carry(phone, ME, [b]);
  assert.equal((await live(b, ME)).length, 1, "B, alone, still has it");
  await carry(phone, ME, [a, b]);
  assert.deepEqual(await live(a, ME), []);
  assert.deepEqual(await live(b, ME), []);
  assert.deepEqual((await b.ask("GET", "/presets/kept", ME)).body.records.map((r: KeptRecord) => [r.id, r.rev, "gone" in r]), [[id, 2, true]]);
  assert.equal(b.presets.list("ws").length, 0, "nor do B's agents open with it");
});

test("an edit made on A while B was away wins or loses by rev alone", async () => {
  const clock = { now: 1000 };
  const a = station("sa", clock);
  const b = station("sb", clock);
  const phone: Device = new Map();
  const made = (await a.ask("POST", "/presets", ME, { name: "Work", dirs: [] })).body;
  await carry(phone, ME, [a, b]);
  // A changed twice, B once and later (its clock ahead): A's has more changes and wins on both
  await a.ask("PUT", `/presets/${made.id}`, ME, { name: "Work 2", dirs: [] });
  await a.ask("PUT", `/presets/${made.id}`, ME, { name: "Work 3", dirs: [] });
  clock.now += 1_000_000;
  const fromB = phone.get(made.id) as any;
  const later = { ...fromB, name: "Work B", rev: fromB.rev + 1, updatedAt: clock.now };
  const putB = await b.ask("PUT", "/presets/kept", ME, { records: [later] });
  assert.equal(putB.body.records[0].name, "Work B");
  await carry(phone, ME, [a, b]);
  for (const s of [a, b]) assert.deepEqual((await live(s, ME)).map((r: any) => [r.name, r.rev]), [["Work 3", 3]]);
  // the other way: B's change one more than A's, A's later: B's wins
  await b.ask("PUT", "/presets/kept", ME, { records: [{ ...(phone.get(made.id) as any), name: "B again", rev: 5, updatedAt: 1 }] });
  await a.ask("PUT", `/presets/${made.id}`, ME, { name: "A again", dirs: [] });
  await carry(phone, ME, [a, b]);
  for (const s of [a, b]) assert.deepEqual((await live(s, ME)).map((r: any) => [r.name, r.rev]), [["B again", 5]]);
});

test("an app from before sees on each station only what was made there, and its changes count", async () => {
  const clock = { now: 1000 };
  const a = station("sa", clock);
  const b = station("sb", clock);
  const phone: Device = new Map();
  const onA = (await a.ask("POST", "/presets", ME, { name: "A's", dirs: [] })).body;
  const onB = (await b.ask("POST", "/presets", YOU, { name: "B's", dirs: [] })).body;
  await carry(phone, ME, [a, b]);
  await carry(new Map(), YOU, [a, b]);
  assert.deepEqual((await a.ask("GET", "/presets", ME)).body.presets.map((p: any) => p.name), ["A's"]);
  assert.deepEqual((await b.ask("GET", "/presets", ME)).body.presets.map((p: any) => p.name), ["B's"]);
  // its shape as before, the new fields beside
  const listed = (await a.ask("GET", "/presets", ME)).body;
  assert.deepEqual(Object.keys(listed).sort(), ["candidates", "clones", "presets"]);
  assert.deepEqual(Object.keys(listed.presets[0]).sort(), ["createdAt", "createdBy", "dirs", "home", "id", "instructions", "name", "owner", "rev", "updatedAt"]);
  // PUT and DELETE as before, each one change more
  const put = await a.ask("PUT", `/presets/${onA.id}`, ME, { name: "A's 2", dirs: [] });
  assert.deepEqual([put.status, put.body.name, put.body.rev], [200, "A's 2", 2]);
  assert.equal((await b.ask("DELETE", `/presets/${onB.id}`, ME)).status, 200, "nobody's to keep: anyone may, as before");
  assert.deepEqual((await b.ask("GET", "/presets", ME)).body.presets, []);
  assert.deepEqual((await b.ask("GET", "/presets/kept", YOU)).body.records.map((r: any) => [r.rev, r.gone]), [[2, true]]);
  assert.equal((await a.ask("PUT", "/presets/p-none", ME, { name: "x", dirs: [] })).status, 404);
  // everyone else's, asked at a press: live ones only, not one's own
  assert.deepEqual((await a.ask("GET", "/presets/others", YOU)).body.records.map((r: any) => r.name), ["A's 2"]);
  assert.deepEqual((await a.ask("GET", "/presets/others", ME)).body.records.map((r: any) => r.name), ["B's"], "deleted on B, not carried to A yet");
});

test("a record is taken only from its owner's devices, and only one of theirs replaced", async () => {
  const clock = { now: 1000 };
  const a = station("sa", clock);
  const mine = (await a.ask("POST", "/presets", ME, { name: "Mine", dirs: [] })).body;
  const record = (await a.ask("GET", "/presets/kept", ME)).body.records[0];
  // someone else's device saying it is theirs, or saying it of mine
  const theirs = await a.ask("PUT", "/presets/kept", YOU, { records: [{ ...record, rev: 9 }, { ...record, id: "p-new", rev: 1 }, { ...record, id: "p-yours", owner: YOU.sub, rev: 1 }, { id: "bad id!" }] });
  assert.equal(theirs.status, 200);
  assert.deepEqual(theirs.body.refused.map((x: any) => [x.at, x.id]), [[0, mine.id], [1, "p-new"], [3, "bad id!"]]);
  assert.deepEqual(theirs.body.records.map((r: any) => r.id), ["p-yours"], "the one that is theirs taken, the others refused alone");
  assert.equal((await a.ask("GET", "/presets/kept", ME)).body.records[0].rev, 1, "mine as it was");
  const takeOver = await a.ask("PUT", "/presets/kept", YOU, { records: [{ ...record, owner: YOU.sub, rev: 9 }] });
  assert.match(takeOver.body.refused[0].error, /someone else's/);
  // an older one of mine is answered with what is kept
  const older = await a.ask("PUT", "/presets/kept", ME, { records: [{ ...record, name: "Old", updatedAt: 0 }] });
  assert.deepEqual([older.body.records[0].name, older.body.refused], ["Mine", []]);
  // bounded
  assert.equal((await a.ask("PUT", "/presets/kept", ME, { records: Array.from({ length: 101 }, () => record) })).status, 413);
});

test("a file from before reads as made here, changed once, of nobody yet, and is not written for it; its maker's device says it again", async () => {
  const clock = { now: 1000 };
  const a = station("sa", clock);
  const before = `${JSON.stringify({ presets: [{ id: "p-old", name: "Old", dirs: [{ path: "/Users/me/app", repo: "github.com/acme/app" }, { path: "/x", repo: null, station: "ws/sb", stationName: "Willow" }], instructions: "", createdBy: ME.email, createdAt: 5, updatedAt: 6 }] }, null, 2)}\n`;
  writeFileSync(join(a.home, "presets.json"), before);
  const p = a.presets.get("ws", "p-old")!;
  assert.deepEqual([p.rev, p.home, p.owner], [1, "sa", ""]);
  assert.equal((await a.ask("GET", "/presets", ME)).body.presets.length, 1, "listed to an app from before");
  const kept = (await a.ask("GET", "/presets/kept", ME)).body.records;
  assert.equal(readFileSync(join(a.home, "presets.json"), "utf8"), before, "nothing written");
  // its maker's, by their email; carried with every folder naming its station, no name of an app's
  assert.deepEqual(kept.map((r: any) => [r.id, r.owner]), [["p-old", ""]]);
  assert.deepEqual(kept[0].dirs, [{ path: "/Users/me/app", repo: "github.com/acme/app", station: "ws/sa" }, { path: "/x", repo: null, station: "ws/sb" }]);
  assert.deepEqual((await a.ask("GET", "/presets/kept", YOU)).body.records, []);
  // said again with its owner (one change more), taken; by someone else, refused
  assert.match((await a.ask("PUT", "/presets/kept", YOU, { records: [{ ...kept[0], owner: YOU.sub, rev: 2 }] })).body.refused[0].error, /someone else/);
  const claimed = await a.ask("PUT", "/presets/kept", ME, { records: [{ ...kept[0], owner: ME.sub, rev: 2 }] });
  assert.deepEqual([claimed.body.refused, claimed.body.records[0].owner], [[], ME.sub]);
  assert.equal(a.presets.get("ws", "p-old")!.owner, ME.sub);
});

test("two stations given the same record keep the same bytes of it", async () => {
  const clock = { now: 1000 };
  const a = station("sa", clock);
  const b = station("sb", clock);
  const r = { ...base, name: " Work ", rev: 1, updatedAt: 7, dirs: [{ path: "/a", repo: "", station: "ws/sc" }], model: { model: "opus", effort: " high " } };
  await a.ask("PUT", "/presets/kept", ME, { records: [r] });
  await b.ask("PUT", "/presets/kept", ME, { records: [r] });
  const [ka, kb] = [(await a.ask("GET", "/presets/kept", ME)).body.records, (await b.ask("GET", "/presets/kept", ME)).body.records];
  assert.equal(JSON.stringify(ka), JSON.stringify(kb));
  assert.equal(JSON.stringify(ka[0]), JSON.stringify(recordOf(r)), "kept as both sides make it");
});

test("a retired station's presets are merged here by the newer, a deletion among them", () => {
  const ours = { presets: [{ ...base, rev: 2, updatedAt: 5 }, { ...base, id: "p-2", rev: 1, updatedAt: 5 }, { id: "p-old", name: "From before", dirs: [], createdBy: "", createdAt: 0, updatedAt: 0 }], gone: [] };
  const theirs = { presets: [{ ...base, rev: 1, updatedAt: 99, name: "Older" }, { ...base, id: "p-3", rev: 1, updatedAt: 1 }, { id: "p-old", name: "Theirs from before", dirs: [], createdBy: "", createdAt: 0, updatedAt: 1 }], gone: [{ id: "p-2", owner: ME.sub, rev: 2, gone: true, updatedAt: 1 }] };
  const merged = mergePresets(ours, theirs);
  assert.deepEqual(merged.file.presets.map((p: any) => [p.id, p.name]), [["p-1", "Work"], ["p-old", "Theirs from before"], ["p-3", "Work"]]);
  assert.deepEqual(merged.file.gone.map((g: any) => g.id), ["p-2"]);
  assert.equal(merged.taken, 3);
  assert.equal(mergePresets(merged.file, theirs).taken, 0, "once is all");
});

test("starred models: each person's own, merged model by model, told to their devices alone", async () => {
  const rows = new Map<string, string>();
  const told: string[] = [];
  const list = starRoutes({ kept: { modelStars: (ws, sub) => rows.get(`${ws}|${sub}`) ?? null, putModelStars: (ws, sub, s) => void rows.set(`${ws}|${sub}`, s) }, told: (ws, sub) => told.push(`${ws}|${sub}`) });
  const ask = async (method: string, who: Viewer, body?: unknown) => {
    const route = list.find((r) => r.method === method)!;
    const answer = await route.handle({ method, path: "/stars", query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer: { ...who, workspace: "ws" } as never, lang: "en" } as never, []);
    return { status: answer.status, body: JSON.parse((answer.body as Buffer).toString()) };
  };
  assert.deepEqual((await ask("GET", ME)).body, { stars: {} });
  await ask("PUT", ME, { stars: { opus: { on: true, rev: 1, at: 10 }, sonnet: { on: true, rev: 1, at: 11 } } });
  const second = await ask("PUT", ME, { stars: { opus: { on: false, rev: 2, at: 10 }, sonnet: { on: false, rev: 1, at: 11 } } });
  assert.deepEqual(second.body.stars, { opus: { on: false, rev: 2, at: 10 }, sonnet: { on: false, rev: 1, at: 11 } }, "of the same rev the unstarring");
  assert.deepEqual(told, ["ws|u-me", "ws|u-me"]);
  await ask("PUT", ME, { stars: { opus: { on: true, rev: 1, at: 99 } } });
  assert.equal(told.length, 2, "nothing newer, nothing told");
  assert.deepEqual((await ask("GET", YOU)).body.stars, {}, "another's are not theirs");
  assert.equal((await ask("PUT", ME, { stars: { opus: { on: "yes" } } })).status, 400);
  assert.equal((await ask("PUT", ME, { stars: Object.fromEntries(Array.from({ length: 201 }, (_, i) => [`m${i}`, { on: true, rev: 1, at: 0 }])) })).status, 400);
  assert.deepEqual(JSON.parse(rows.get("ws|u-me")!), second.body.stars, "kept by its key");
});

test("a folder naming this station is this machine's for a chat opened with it; another's is told by that station's name", async () => {
  const r = new Rig();
  const here = mkdtempSync(join(tmpdir(), "carried-here-"));
  writeFileSync(join(here, "AGENTS.md"), "# Here\nRun the tests.\n");
  mkdirSync(join(here, ".claude", "skills", "ship"), { recursive: true });
  writeFileSync(join(here, ".claude", "skills", "ship", "SKILL.md"), "---\nname: ship\n---\n");
  const record = recordOf({ ...base, rev: 1, updatedAt: 1, home: "sw", dirs: [{ path: here, repo: null, station: "ws/st" }, { path: "/far", repo: null, station: "ws/sw" }, { path: "/farther", repo: null, station: "ws/sx" }] });
  assert.deepEqual(r.hub.presets.carry(null, ME, [record]).refused, []);
  // opened here (this station is `st`): its folder here read as this machine's
  const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "local", preset: base.id });
  sayIn(r.hub, thread.id, "local", "go");
  await settle();
  const copy = presetCopyOf(r.session(key).workspace)!;
  assert.deepEqual(copy.dirs.map((d) => [d.path, d.elsewhere ?? null]), [[here, null], ["/far", "sw"], ["/farther", "sx"]]);
  assert.equal(copy.dirs[0]!.guides?.[0]?.file, "AGENTS.md", "its instructions read here");
  assert.deepEqual(copy.dirs[0]!.skills, ["ship"], "its skills linked");
  const opened = r.claude.last().options;
  assert.ok(opened.instructions.includes(`  - ${here}\n`), opened.instructions);
  assert.ok(opened.instructions.includes("/far on station sw"), opened.instructions);
  // another station's folder by the name this station knows it by, its id where it knows none
  const named = new Presets(r.hub.presets.home, () => 1, { station: () => "st", workspace: () => "ws", stationName: (id) => (id === "sw" ? "Willow" : null) });
  const elsewhere = mkdtempSync(join(tmpdir(), "carried-chat-"));
  assert.deepEqual(named.keepFor(elsewhere, null, base.id).dirs.map((d) => [d.path, d.elsewhere ?? null]), [[here, null], ["/far", "Willow"], ["/farther", "sx"]]);
  await r.close();
});
