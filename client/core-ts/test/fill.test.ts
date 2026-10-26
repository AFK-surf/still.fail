// What was opened and let go is brought whole after everything else (fill.ts): a chat's file a viewer read a part of
// goes on coming once nothing is waited on, kept as it comes, so opened again it is all here; a request a person waits
// on stops it, and it goes on after; it goes on as the core starts again; it waits for a station not reached; a file
// the station no longer has is let go; a drive's video goes on too.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { FakeHost } from "../src/testing.ts";
import { Core } from "../src/core.ts";
import { HostError } from "../src/error.ts";
import { FILL_RECENT_MS, IDLE_MS } from "../src/fill.ts";
import { chatKeptId, keptId } from "../src/drive-kept.ts";
import { HostWire } from "../src/station/wire.ts";
import { call } from "./helpers.ts";
import { Raw, started, stationReplies, status } from "./station-fixture.ts";

const ST = "ws/st";
const MB = 1024 * 1024;
const bytesOf = (n: number, from = 0) => Uint8Array.from({ length: n }, (_, i) => (from + i) % 251);

/// The session `k1`'s files by name, read a part at a time; `away` ones not reached. The drive's files by path.
function files(host: FakeHost, all: Map<string, Uint8Array>, away: Set<string> = new Set(), drive: Map<string, Uint8Array> = new Map()): void {
  stationReplies(host, (req) => {
    const u = new URL(req.url);
    if (u.pathname.endsWith("/drive/read")) {
      const f = drive.get(u.searchParams.get("path") ?? "");
      if (f === undefined) return status(404, { error: "文件不存在" });
      const offset = Number(u.searchParams.get("offset"));
      const body = f.slice(offset, offset + Number(u.searchParams.get("length")));
      return new Raw({ status: 200, headers: [["content-type", "video/mp4"], ["stillfail-total", String(f.length)], ["stillfail-mtime", "7"]], body });
    }
    if (!u.pathname.endsWith("/sessions/k1/parts")) return undefined;
    const name = u.searchParams.get("name") ?? "";
    if (away.has(name)) throw new HostError("没连上");
    const f = all.get(name);
    if (f === undefined) return status(404, { error: "文件不存在" });
    const offset = Number(u.searchParams.get("offset"));
    const body = f.slice(offset, offset + Number(u.searchParams.get("length")));
    return new Raw({ status: 200, headers: [["content-type", "video/mp4"], ["stillfail-total", String(f.length)]], body });
  });
}

async function rig<T extends { host: FakeHost; core: Core }>(t: T) {
  const ui = t.core.connect();
  let n = 100;
  const ask = async (name: string, params: Record<string, unknown>) => {
    const id = ++n;
    call(t.core, ui, id, name, params);
    await t.host.settle();
    return t.host.takeEmitted().map(([, m]) => m as Record<string, unknown>).find((m) => m.id === id && ("ok" in m || "error" in m));
  };
  const parts = (name: string) => t.host.requests.filter((r) => r.url.includes("/sessions/k1/parts") && r.url.includes(`name=${name}&`)).length;
  const whole = (id: string, size: number) => Effect.runPromise(t.core.inner.driveKept.whole(id, size));
  return { ...t, ask, parts, whole };
}

test("a chat's video a viewer let go of is brought whole once nothing is waited on, and read from the device after", async () => {
  const film = bytesOf(10 * MB, 3);
  const t = await started();
  files(t.host, new Map([["film.mp4", film]]));
  const r = await rig(t);
  // the player read its start and was closed
  await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 0, length: MB, keep: true, size: film.length, stream: true });
  assert.equal(r.parts("film.mp4"), 1);
  // not before nothing has been waited on a while
  await t.host.time.pass(IDLE_MS / 2);
  assert.equal(r.parts("film.mp4"), 1);
  await t.host.time.pass(IDLE_MS);
  assert.equal(await r.whole(chatKeptId(ST, "k1", "film.mp4"), film.length), true);
  assert.equal(r.parts("film.mp4"), 4, "the rest in parts of 4 MB");
  // opened again: off the device
  const again = await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 8 * MB, length: 2 * MB, keep: true, size: film.length });
  assert.deepEqual([...(again!.bytes as Uint8Array).slice(0, 4)], [...film.slice(8 * MB, 8 * MB + 4)]);
  assert.equal(r.parts("film.mp4"), 4);
  t.core.close();
});

test("a request waited on stops the part under way, what came of it kept; it goes on once nothing has been waited on a while", async () => {
  const film = bytesOf(10 * MB, 5);
  const other = bytesOf(2 * MB, 9);
  const t = await started();
  files(t.host, new Map([["film.mp4", film], ["other.mp4", other]]));
  const r = await rig(t);
  await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 0, length: MB, keep: true, size: film.length });
  // its next part held as it goes
  const held = t.host.hold(`name=film.mp4&offset=${MB}&length=${4 * MB}`);
  await t.host.time.pass(IDLE_MS + 100);
  assert.equal(r.parts("film.mp4"), 2);
  // the person opens another: what they wait on stops it
  const opened = t.host.hold(`name=other.mp4&offset=0&length=${2 * MB}`);
  const id = 999;
  call(t.core, t.core.connect(), id, "station.file.part", { station: ST, key: "k1", name: "other.mp4", offset: 0, length: 2 * MB, keep: true, size: other.length });
  await t.host.settle();
  held();
  // nothing more of it while that is waited on, however long
  await t.host.time.pass(IDLE_MS * 3);
  assert.equal(r.parts("film.mp4"), 2);
  opened();
  await t.host.settle();
  // then on, from where it was, the one opened since first
  await t.host.time.pass(IDLE_MS + 100);
  assert.equal(await r.whole(chatKeptId(ST, "k1", "film.mp4"), film.length), true);
  assert.equal(await r.whole(chatKeptId(ST, "k1", "other.mp4"), other.length), true);
  t.core.close();
});

test("it goes on as the core starts again; a station not reached is waited for; a file the station no longer has is let go", async () => {
  const film = bytesOf(6 * MB, 2);
  const gone = bytesOf(6 * MB, 4);
  const all = new Map([["film.mp4", film], ["gone.mp4", gone]]);
  const away = new Set<string>();
  const t = await started();
  files(t.host, all, away);
  const r = await rig(t);
  await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 0, length: MB, keep: true, size: film.length });
  await r.ask("station.file.part", { station: ST, key: "k1", name: "gone.mp4", offset: 0, length: MB, keep: true, size: gone.length });
  t.core.close();
  // started again over the same device: the station not reached, and one of them gone from it
  away.add("film.mp4");
  all.delete("gone.mp4");
  const core = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  await t.host.time.pass(IDLE_MS * 2);
  const kept = core.inner.driveKept;
  assert.equal(await Effect.runPromise(kept.has(chatKeptId(ST, "k1", "gone.mp4"))), false, "what was kept of the one gone let go");
  assert.equal(await Effect.runPromise(kept.whole(chatKeptId(ST, "k1", "film.mp4"), film.length)), false);
  const tried = r.parts("film.mp4");
  await t.host.time.pass(IDLE_MS * 3);
  assert.equal(r.parts("film.mp4"), tried, "not asked again while its station is not reached");
  away.delete("film.mp4");
  core.inner.fill.stationBack(ST);
  await t.host.time.pass(IDLE_MS + 100);
  assert.equal(await Effect.runPromise(kept.whole(chatKeptId(ST, "k1", "film.mp4"), film.length)), true);
  core.close();
});

test("one read long ago is left as it is: only what was opened lately is brought", async () => {
  const film = bytesOf(6 * MB, 6);
  const t = await started();
  files(t.host, new Map([["old.mp4", film]]));
  const r = await rig(t);
  // read, then the app closed for days
  await r.ask("station.file.part", { station: ST, key: "k1", name: "old.mp4", offset: 0, length: MB, keep: true, size: film.length });
  t.core.close();
  t.host.advance(FILL_RECENT_MS + 1);
  const core = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  await t.host.time.pass(IDLE_MS * 2);
  assert.equal(r.parts("old.mp4"), 1);
  core.close();
});

test("what is brought is listed as it stands; one stopped goes, what was kept of it with it; the prefs turn it off or bound it", async () => {
  const film = bytesOf(10 * MB, 3);
  const clip = bytesOf(6 * MB, 4);
  const big = bytesOf(8 * MB, 5);
  const t = await started();
  files(t.host, new Map([["film.mp4", film], ["clip.mp4", clip], ["big.mp4", big]]));
  const r = await rig(t);
  const keeping = () => (t.core.inner.downloads.view().keeping as { name: string; state: string; loaded: number; statusText: string }[]);
  for (const [name, f] of [["film.mp4", film], ["clip.mp4", clip], ["big.mp4", big]] as const) {
    await r.ask("station.file.part", { station: ST, key: "k1", name, offset: 0, length: MB, keep: true, size: f.length });
  }
  // listed as they are let go, before any comes: the one read last first
  assert.deepEqual(keeping().map((k) => [k.name, k.loaded]), [["big.mp4", MB], ["clip.mp4", MB], ["film.mp4", MB]]);
  assert.ok(keeping().every((k) => k.statusText.length > 0));
  // the one coming, while its part comes
  const held = t.host.hold(`name=big.mp4&offset=${MB}&length=${4 * MB}`);
  await t.host.time.pass(IDLE_MS + 100);
  assert.deepEqual(keeping().map((k) => [k.name, k.state]), [["big.mp4", "going"], ["clip.mp4", "queued"], ["film.mp4", "queued"]]);
  // stopped: no longer listed, nothing of it kept; the next goes on (held as it comes)
  const id = chatKeptId(ST, "k1", "big.mp4");
  const next = t.host.hold(`name=clip.mp4&offset=${MB}&length=${4 * MB}`);
  await r.ask("fill.stop", { id });
  held();
  await t.host.settle();
  assert.equal(await Effect.runPromise(t.core.inner.driveKept.has(id)), false);
  assert.deepEqual(keeping().map((k) => [k.name, k.state]), [["clip.mp4", "going"], ["film.mp4", "queued"]]);
  // turned off: none listed, the part coming stopped, none brought
  await r.ask("prefs.set", { fillOff: true });
  assert.deepEqual(keeping(), []);
  next();
  const before = r.parts("film.mp4") + r.parts("clip.mp4");
  await t.host.time.pass(IDLE_MS * 3);
  assert.equal(r.parts("film.mp4") + r.parts("clip.mp4"), before);
  assert.equal(await r.whole(chatKeptId(ST, "k1", "clip.mp4"), clip.length), false);
  // on again, up to 7 MB: the clip, not the film
  await r.ask("prefs.set", { fillOff: null, fillMax: 7 * MB });
  await t.host.time.pass(IDLE_MS + 100);
  assert.equal(await r.whole(chatKeptId(ST, "k1", "clip.mp4"), clip.length), true);
  assert.equal(await r.whole(chatKeptId(ST, "k1", "film.mp4"), film.length), false);
  assert.deepEqual(keeping(), []);
  // any size (its part held as it comes), then all of them stopped at once
  const last = t.host.hold(`name=film.mp4&offset=${MB}&length=${4 * MB}`);
  await r.ask("prefs.set", { fillMax: 0 });
  assert.deepEqual(keeping().map((k) => k.name), ["film.mp4"]);
  await r.ask("fill.stopAll", {});
  last();
  await t.host.settle();
  assert.deepEqual(keeping(), []);
  assert.equal(await Effect.runPromise(t.core.inner.driveKept.has(chatKeptId(ST, "k1", "film.mp4"))), false);
  t.core.close();
});

test("a drive's video a player let go of goes on as a chat's file does", async () => {
  const clip = bytesOf(6 * MB, 1);
  const t = await started();
  files(t.host, new Map(), new Set(), new Map([["clip.mp4", clip]]));
  const r = await rig(t);
  await r.ask("drive.read", { station: ST, root: "home", path: "clip.mp4", keep: "played", mtime: 7, size: clip.length, offset: 0, length: MB });
  await t.host.time.pass(IDLE_MS + 100);
  assert.equal(await r.whole(keptId(ST, "home", "clip.mp4"), clip.length), true);
  t.core.close();
});
