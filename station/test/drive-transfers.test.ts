// Copying into the drive (src/drive/transfers.ts, grants.ts, module.ts): within a station and from another one with
// what it granted, a name already there replaced, kept beside or skipped, a move letting the originals go, a transfer
// that failed taken up where it was, and a grant read only as it was given.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Drive, DriveError } from "../src/drive/drive.ts";
import { covers, sign, verify, type Granted } from "../src/drive/grants.ts";
import { driveForPeer, peerSource } from "../src/drive/module.ts";
import { free, type Source, type Transfer, Transfers } from "../src/drive/transfers.ts";
import { Refused, bytesOf, withBytes } from "../src/mesh/bus.ts";
import { routes as transferRoutes } from "../src/api/routes/transfers.ts";
import type { Request } from "../src/api/request.ts";

/// A station's drive over a folder of its own: `root` pinned, deleted things to the place's own trash.
function station(name: string) {
  const base = realpathSync(mkdtempSync(join(tmpdir(), `transfers-${name}-`)));
  const root = join(base, "root");
  const data = join(base, "data");
  mkdirSync(root, { recursive: true });
  mkdirSync(data, { recursive: true });
  const config = { drive: { roots: [root] } } as any;
  const drive = new Drive({ config: () => config, protect: () => [data], home: base });
  return { base, root, data, drive };
}

const KEY = Buffer.alloc(32, 7);
let clock = 1_000_000;
const now = () => clock;

/// Transfers into `to`, reading another station's drive (`peers`, by id) as the bus would: its own handler, with the
/// workspace the request names.
function transfersInto(to: ReturnType<typeof station>, peers: Record<string, { drive: Drive; key: Buffer }> = {}, told: Transfer[] = []) {
  const ask = async (id: string, request: any) => {
    const p = peers[id];
    if (!p) throw new Error("no such station");
    return driveForPeer(p.drive, p.key, JSON.parse(JSON.stringify(request)), request.workspace, now());
  };
  return new Transfers({ dir: join(to.data, "drive-transfers"), driveFor: () => to.drive, remote: (t) => peerSource(ask, t), now, changed: (t) => told.push(structuredClone(t)) });
}

const spec = (over: Partial<Parameters<Transfers["start"]>[0]> & { from: Transfer["from"]; to: Transfer["to"] }) => ({
  by: "a@x", workspace: "ws", home: true, anywhere: true, move: false, conflicts: {}, ...over,
});

const grantOf = (s: ReturnType<typeof station>, g: Partial<Granted>) =>
  sign(KEY, { v: 1, workspace: "ws", home: true, by: "a@x", anywhere: true, root: s.root, path: "", names: [], move: false, expires: now() + 1000, ...g });

test("within a station: files and folders copied, what is there already kept beside, replaced or skipped", async () => {
  const s = station("one");
  mkdirSync(join(s.root, "src", "deep"), { recursive: true });
  writeFileSync(join(s.root, "src", "a.txt"), "a");
  writeFileSync(join(s.root, "src", "deep", "b.txt"), "bb");
  writeFileSync(join(s.root, "src", "empty.txt"), "");
  mkdirSync(join(s.root, "dst"));
  writeFileSync(join(s.root, "dst", "a.txt"), "old");
  const transfers = transfersInto(s);
  const t = transfers.start(spec({ from: { station: null, root: s.root, path: "src", names: ["deep", "a.txt", "empty.txt"] }, to: { root: s.root, path: "dst" }, conflicts: { "a.txt": "keep" } }));
  await transfers.idle();
  const done = transfers.get(t.id)!;
  assert.equal(done.state, "done", done.error);
  assert.equal(readFileSync(join(s.root, "dst", "deep", "b.txt"), "utf8"), "bb");
  assert.equal(readFileSync(join(s.root, "dst", "a.txt"), "utf8"), "old");
  assert.equal(readFileSync(join(s.root, "dst", "a 2.txt"), "utf8"), "a");
  assert.equal(readFileSync(join(s.root, "dst", "empty.txt"), "utf8"), "");
  assert.equal(done.total, 3);
  assert.equal(done.copied, 3);
  // The originals stay (a copy).
  assert.equal(readFileSync(join(s.root, "src", "a.txt"), "utf8"), "a");

  const replaced = transfers.start(spec({ from: { station: null, root: s.root, path: "src", names: ["a.txt", "deep"] }, to: { root: s.root, path: "dst" }, conflicts: { "a.txt": "replace", deep: "skip" } }));
  await transfers.idle();
  assert.equal(transfers.get(replaced.id)!.state, "done");
  assert.equal(readFileSync(join(s.root, "dst", "a.txt"), "utf8"), "a");
  assert.deepEqual(transfers.get(replaced.id)!.items.map((i) => i.path), ["a.txt"]);

  // A name there that was not answered is not overwritten.
  const asked = transfers.start(spec({ from: { station: null, root: s.root, path: "src", names: ["a.txt"] }, to: { root: s.root, path: "dst" } }));
  await transfers.idle();
  assert.equal(transfers.get(asked.id)!.state, "failed");
  assert.match(transfers.get(asked.id)!.error!, /already/);
});

test("from another station with its grant: read in parts, the originals let go once moved", async () => {
  const a = station("src");
  const b = station("dst");
  const big = Buffer.alloc(600 * 1024, 3);
  mkdirSync(join(a.root, "photos"));
  writeFileSync(join(a.root, "photos", "big.bin"), big);
  writeFileSync(join(a.root, "note.md"), "# hi");
  const told: Transfer[] = [];
  const transfers = transfersInto(b, { A: { drive: a.drive, key: KEY } }, told);
  const grant = grantOf(a, { names: ["photos", "note.md"], move: true });
  const t = transfers.start(spec({ move: true, from: { station: "A", grant, root: a.root, path: "", names: ["photos", "note.md"] }, to: { root: b.root, path: "" } }));
  await transfers.idle();
  const done = transfers.get(t.id)!;
  assert.equal(done.state, "done", done.error);
  assert.deepEqual(readFileSync(join(b.root, "photos", "big.bin")), big);
  assert.equal(readFileSync(join(b.root, "note.md"), "utf8"), "# hi");
  // Moved: gone from where they were (to that place's trash).
  assert.equal(existsSync(join(a.root, "photos")), false);
  assert.equal(existsSync(join(a.root, "note.md")), false);
  // Told as it went: walked, then copying, each file's end, done.
  assert.deepEqual([...new Set(told.map((x) => x.state))], ["queued", "walking", "copying", "done"]);
});

test("a transfer whose station went away fails, and is taken up again where it was", async () => {
  const a = station("away-src");
  const b = station("away-dst");
  const big = Buffer.from(Array.from({ length: 700 * 1024 }, (_, i) => i % 251));
  writeFileSync(join(a.root, "big.bin"), big);
  let away = true;
  const grant = grantOf(a, { names: ["big.bin"] });
  const ask = async (_id: string, request: any) => {
    const got = await driveForPeer(a.drive, KEY, request, request.workspace, now());
    const bytes = bytesOf(got);
    if (!away || bytes === null) return got;
    // Its station goes away once the first part came.
    return withBytes(got, (async function* () {
      for await (const piece of bytes) {
        yield piece.subarray(0, 256 * 1024);
        throw new Error("station is not reachable");
      }
    })());
  };
  const transfers = new Transfers({ dir: join(b.data, "drive-transfers"), driveFor: () => b.drive, remote: (t) => peerSource(ask, t), now, changed: () => {} });
  const t = transfers.start(spec({ from: { station: "A", grant, root: a.root, path: "", names: ["big.bin"] }, to: { root: b.root, path: "" } }));
  await transfers.idle();
  const failed = transfers.get(t.id)!;
  assert.equal(failed.state, "failed");
  assert.equal(failed.at, 256 * 1024);
  assert.equal(existsSync(join(b.root, "big.bin")), false);
  // A station restarted keeps it as it was.
  const again = new Transfers({ dir: join(b.data, "drive-transfers"), driveFor: () => b.drive, remote: (x) => peerSource(ask, x), now, changed: () => {} });
  assert.equal(again.get(t.id)!.at, 256 * 1024);
  away = false;
  again.retry("a@x", t.id);
  await again.idle();
  assert.equal(again.get(t.id)!.state, "done", again.get(t.id)!.error);
  assert.deepEqual(readFileSync(join(b.root, "big.bin")), big);
  assert.equal(again.get(t.id)!.copied, big.length);
});

test("cancelled: stops between parts, what was not in place is not there", async () => {
  const b = station("cancel");
  let transfers: Transfers;
  let id = "";
  // A source that is cancelled under after its first part.
  const source: Source = {
    station: "A",
    part: 4,
    walk: async () => ({ items: [{ path: "f.txt", dir: false, size: 12 }] }),
    read: async (_p, offset) => {
      if (offset === 4) transfers.cancel("a@x", id);
      return { bytes: Buffer.from("abcdefghijkl".slice(offset, offset + 4)), size: 12, mtime: 5 };
    },
    release: async () => {},
  };
  transfers = new Transfers({ dir: join(b.data, "drive-transfers"), driveFor: () => b.drive, remote: () => source, now, changed: () => {} });
  id = transfers.start(spec({ from: { station: "A", grant: "g", root: "/", path: "", names: ["f.txt"] }, to: { root: b.root, path: "" } })).id;
  await transfers.idle();
  assert.equal(transfers.get(id)!.state, "cancelled");
  assert.equal(existsSync(join(b.root, "f.txt")), false);
});

test("a file changed while it is read is read again from its start", async () => {
  const b = station("changed");
  let mtime = 1;
  const content = () => (mtime === 1 ? "old-old-old!" : "new-new-new-new!");
  const source: Source = {
    station: "A",
    part: 4,
    walk: async () => ({ items: [{ path: "f.txt", dir: false, size: 12 }] }),
    read: async (_p, offset) => {
      const got = { bytes: Buffer.from(content().slice(offset, offset + 4)), size: content().length, mtime };
      if (offset === 4) mtime = 2;
      return got;
    },
    release: async () => {},
  };
  const transfers = new Transfers({ dir: join(b.data, "drive-transfers"), driveFor: () => b.drive, remote: () => source, now, changed: () => {} });
  const t = transfers.start(spec({ from: { station: "A", grant: "g", root: "/", path: "", names: ["f.txt"] }, to: { root: b.root, path: "" } }));
  await transfers.idle();
  assert.equal(transfers.get(t.id)!.state, "done", transfers.get(t.id)!.error);
  assert.equal(readFileSync(join(b.root, "f.txt"), "utf8"), "new-new-new-new!");
  assert.equal(transfers.get(t.id)!.total, 16);
  assert.equal(transfers.get(t.id)!.copied, 16);
});

test("a grant: this station's own signature, its workspace, not expired, only what it names", async () => {
  const a = station("grant");
  writeFileSync(join(a.root, "yes.txt"), "y");
  writeFileSync(join(a.root, "no.txt"), "n");
  const grant = grantOf(a, { names: ["yes.txt"] });
  const ask = (request: any, workspace: string | null = "ws") => driveForPeer(a.drive, KEY, { grant, ...request }, workspace, now());
  assert.equal(Buffer.from((await ask({ method: "drive.part", path: "yes.txt", offset: 0 })).data, "base64").toString(), "y");
  const refusal = async (p: Promise<unknown>) => {
    try {
      await p;
    } catch (e) {
      assert.ok(e instanceof Refused);
      return (e as Error).message.split(":")[0];
    }
    return "ok";
  };
  assert.equal(await refusal(ask({ method: "drive.part", path: "no.txt", offset: 0 })), "permission");
  assert.equal(await refusal(ask({ method: "drive.part", path: "yes.txt/../no.txt", offset: 0 })), "permission");
  assert.equal(await refusal(ask({ method: "drive.part", path: "yes.txt", offset: 0 }, "other")), "permission");
  assert.equal(await refusal(ask({ method: "drive.release", names: ["yes.txt"] })), "permission");
  assert.equal(await refusal(driveForPeer(a.drive, Buffer.alloc(32, 9), { method: "drive.walk", grant }, "ws", now())), "permission");
  const tampered = `${Buffer.from(JSON.stringify({ v: 1, workspace: "ws", home: true, by: "a@x", anywhere: true, root: a.root, path: "", names: ["no.txt"], move: false, expires: now() + 1000 })).toString("base64url")}.${grant.split(".")[1]}`;
  assert.equal(await refusal(driveForPeer(a.drive, KEY, { method: "drive.walk", grant: tampered }, "ws", now())), "permission");
  clock += 2000;
  assert.throws(() => verify(KEY, grant, "ws", now()), (e: unknown) => e instanceof DriveError && /expired/.test(e.message));
  // A read-only member's grant reads as they do: a link out of the pinned folder is not followed.
  const g = verify(KEY, grantOf(a, { names: ["yes.txt"] }), "ws", now());
  assert.equal(covers(g, "yes.txt"), true);
  assert.equal(covers(g, "yes.txt/inner"), true);
  assert.equal(covers(g, "no.txt"), false);
  assert.equal(covers(g, ""), false);
});

test("a name kept beside others: numbered as Finder numbers it", () => {
  const taken = new Set(["a.txt", "a 2.txt", "b"]);
  assert.equal(free("a.txt", false, (n) => taken.has(n)), "a 3.txt");
  assert.equal(free("b", true, (n) => taken.has(n)), "b 2");
  assert.equal(free(".env", false, (n) => taken.has(n)), ".env 2");
});

test("routes: a grant read as the member reads; copying into a station only for one who may write; one's own listed", async () => {
  const a = station("routes");
  writeFileSync(join(a.root, "f.txt"), "f");
  mkdirSync(join(a.root, "in"));
  const transfers = transfersInto(a);
  const table = transferRoutes({ drive: a.drive, transfers, key: KEY, self: () => "SELF", nameOf: (s) => s, now });
  const request = (method: string, path: string, body: unknown, role = "member", email = "a@x"): Request => ({
    method, path, query: [], headers: {}, body: Buffer.from(JSON.stringify(body)), lang: "en",
    viewer: { sub: "u", email, name: "A", role, workspace: "ws", device: "d" },
  });
  const ask = async (r: Request) => {
    const route = table.find((x) => x.method === r.method && x.pattern.test(r.path))!;
    const a = await route.handle(r, [...(route.pattern.exec(r.path) ?? []).slice(1)]);
    return { status: a.status, json: JSON.parse((a.body as Buffer).toString()) };
  };
  const granted = await ask(request("POST", "/drive/grant", { root: a.root, names: ["f.txt"] }));
  assert.equal(granted.status, 200);
  assert.deepEqual(verify(KEY, granted.json.grant, "ws", now()).names, ["f.txt"]);
  assert.equal((await ask(request("POST", "/drive/grant", { root: a.root, names: ["nothing"] }))).json.code, "not_found");
  assert.equal((await ask(request("POST", "/drive/grant", { root: a.root, names: ["../x"] }))).json.code, "invalid_request");
  // A read-only member copies (from what is pinned), and does not move or copy into the station.
  assert.equal((await ask(request("POST", "/drive/grant", { root: a.root, names: ["f.txt"] }, "viewer"))).status, 200);
  assert.equal((await ask(request("POST", "/drive/grant", { root: a.root, names: ["f.txt"], move: true }, "viewer"))).json.code, "permission");
  const into = { from: { root: a.root, names: ["f.txt"] }, to: { root: a.root, path: "in" } };
  assert.equal((await ask(request("POST", "/drive/transfers", into, "viewer"))).json.code, "permission");
  // From this station itself (its own id): from its own drive.
  const started = await ask(request("POST", "/drive/transfers", { ...into, from: { ...into.from, station: "SELF" } }));
  assert.equal(started.status, 200);
  assert.equal(started.json.transfer.from.station, null);
  await transfers.idle();
  assert.equal(readFileSync(join(a.root, "in", "f.txt"), "utf8"), "f");
  assert.equal((await ask(request("POST", "/drive/transfers", { ...into, to: { root: a.root, path: "f.txt" } }))).json.code, "not_a_directory");
  assert.equal((await ask(request("POST", "/drive/transfers", { ...into, from: { ...into.from, station: "B" } }))).json.code, "invalid_request");
  const listed = await ask(request("GET", "/drive/transfers", null));
  assert.deepEqual(listed.json.transfers.map((t: any) => t.state), ["done"]);
  assert.equal(listed.json.transfers[0].items, undefined);
  assert.deepEqual((await ask(request("GET", "/drive/transfers", null, "member", "b@x"))).json.transfers, []);
  assert.equal((await ask(request("POST", `/drive/transfers/${started.json.transfer.id}/cancel`, null, "member", "b@x"))).json.code, "not_found");
});
