// A chat's files downloaded to this device by the core (views/downloads.ts): fetched a part at a time whatever page
// asked, how far each has come told to every page (`downloads`), kept with its chat as it comes, so the app that takes
// it reads it from the device; saved, called off or given up, what came stays kept (never asked of the station again),
// but where the app can read the copy saved back. One read in part before (a preview) goes on from there; one stopped
// by the app's end goes on as it starts again; one whose station is not reached waits for it; one that failed starts
// again when asked again.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { FakeHost } from "../src/testing.ts";
import { Core } from "../src/core.ts";
import { AGAIN_MS, titleOf } from "../src/views/downloads.ts";
import { chatKeptId } from "../src/drive-kept.ts";
import { RECONNECT_MS } from "../src/station/sync.ts";
import { HostError } from "../src/error.ts";
import { HostWire } from "../src/station/wire.ts";
import { apply as applyOps } from "../src/delta.ts";
import { call, subscribe } from "./helpers.ts";
import { Raw, started, stationReplies, status } from "./station-fixture.ts";

const ST = "ws/st";
const MB = 1024 * 1024;
const bytesOf = (n: number, from = 0) => Uint8Array.from({ length: n }, (_, i) => (from + i) % 251);

/// A station's drive as the tests have it: its files by root and path (`root\npath`), each as it is now (its mtime);
/// its folders zipped, where each zip is (a file of `drive` too).
type Drive = { files: Map<string, { bytes: Uint8Array; mtime: number }>; zips: Map<string, { root: string; path: string; name: string }> };

/// The session `k1`'s files (by name): their parts answered with the whole size; `broken` names answer 500, `away`
/// ones are not reached. `drive`: the station's drive, read a part at a time (`/drive/read`), a folder zipped
/// (`/drive/zip`).
function files(host: FakeHost, all: Map<string, Uint8Array>, broken: Set<string> = new Set(), away: Set<string> = new Set(), drive?: Drive): void {
  stationReplies(host, (req) => {
    const u = new URL(req.url);
    if (drive && u.pathname.endsWith("/drive/read")) {
      const f = drive.files.get(`${u.searchParams.get("root")}\n${u.searchParams.get("path")}`);
      if (f === undefined) return status(404, { error: "文件不存在" });
      const offset = Number(u.searchParams.get("offset"));
      const body = f.bytes.slice(offset, offset + Number(u.searchParams.get("length")));
      return new Raw({ status: 200, headers: [["content-type", "application/octet-stream"], ["stillfail-total", String(f.bytes.length)], ["stillfail-mtime", String(f.mtime)]], body });
    }
    if (drive && u.pathname.endsWith("/drive/zip")) {
      const asked = JSON.parse(new TextDecoder().decode(req.body ?? new Uint8Array())) as { root: string; path: string };
      const z = drive.zips.get(`${asked.root}\n${asked.path}`);
      const f = z && drive.files.get(`${z.root}\n${z.path}`);
      return z && f ? status(200, { ...z, size: f.bytes.length }) : status(404, { error: "文件夹不存在" });
    }
    if (!u.pathname.endsWith("/sessions/k1/parts")) return undefined;
    const name = u.searchParams.get("name") ?? "";
    if (away.has(name)) throw new HostError("没连上");
    if (broken.has(name)) return status(500, { error: "磁盘读不出来" });
    const f = all.get(name);
    if (f === undefined) return status(404, { error: "文件不存在" });
    const offset = Number(u.searchParams.get("offset"));
    const body = f.slice(offset, offset + Number(u.searchParams.get("length")));
    return new Raw({ status: 200, headers: [["content-type", "application/zip"], ["stillfail-total", String(f.length)]], body });
  });
}

async function rig(all: Map<string, Uint8Array>, broken: Set<string> = new Set(), away: Set<string> = new Set()) {
  const t = await started();
  files(t.host, all, broken, away);
  return watch(t);
}

/// The core's downloads watched: its calls asked and answered, its list as it is told.
async function watch<T extends { host: FakeHost; core: Core }>(t: T) {
  const ui = t.core.connect();
  let list: any;
  const done = new Map<number, any>();
  const take = () => {
    for (const [, m] of t.host.takeEmitted()) {
      const msg = m as Record<string, unknown>;
      if (msg.id === 1 && "value" in msg) list = msg.value;
      else if (msg.id === 1 && "delta" in msg) list = applyOps(list, msg.delta as never);
      else if ("ok" in msg || "error" in msg) done.set(msg.id as number, msg);
    }
  };
  subscribe(t.core, ui, 1, { topic: "downloads" } as never);
  await t.host.settle();
  take();
  let n = 100;
  const ask = async (name: string, params: Record<string, unknown>) => {
    const id = ++n;
    call(t.core, ui, id, name, params);
    await t.host.settle();
    take();
    return done.get(id);
  };
  const parts = (name: string) => t.host.requests.filter((r) => r.url.includes("/sessions/k1/parts") && r.url.includes(`name=${name}&`)).length;
  const view = async () => { await t.host.settle(); take(); return list.downloads as any[]; };
  return { ...t, ask, parts, view };
}

test("a chat's file downloaded a part at a time, ready for the page that takes it, then read from the device", async () => {
  const zip = bytesOf(10 * MB, 3);
  const r = await rig(new Map([["build.zip", zip]]));
  // (a device's clock says fractions of a millisecond: the list says when in whole ones, as its shape has it)
  r.host.advance(0.387);
  const started = await r.ask("download.start", { station: ST, key: "k1", name: "build.zip", size: zip.length });
  const id = started.ok.download.id as string;
  assert.equal(started.ok.download.state, "going");
  const [d] = await r.view();
  assert.deepEqual([d.id, d.name, d.state, d.loaded, d.progress], [id, "build.zip", "ready", zip.length, 1]);
  assert.ok(Number.isSafeInteger(d.startedAt), String(d.startedAt));
  assert.equal(r.parts("build.zip"), 3, "three parts of 4 MB");
  // asked again while ready: the same one, nothing fetched again
  assert.equal((await r.ask("download.start", { station: ST, key: "k1", name: "build.zip", size: zip.length })).ok.download.id, id);
  assert.equal(r.parts("build.zip"), 3);
  // taken once, to be saved; a second page taking it gets nothing
  assert.deepEqual((await r.ask("download.take", { id })).ok, { taken: true });
  assert.deepEqual((await r.ask("download.take", { id })).ok, { taken: false });
  const [saving] = await r.view();
  assert.deepEqual([saving.state, saving.active], ["saving", true]);
  // what the app reads to save it comes off the device
  const read = await r.ask("station.file.part", { station: ST, key: "k1", name: "build.zip", offset: 4 * MB, length: 4 * MB, keep: true, size: zip.length });
  assert.deepEqual([...read.bytes.slice(0, 4)], [...zip.slice(4 * MB, 4 * MB + 4)]);
  assert.equal(r.parts("build.zip"), 3, "not asked of the station again");
  // saved where the app cannot read it back: out of the list, what came kept, read from the device after
  await r.ask("download.done", { id });
  assert.deepEqual(await r.view(), []);
  assert.equal(await Effect.runPromise(r.core.inner.driveKept.whole(id, zip.length)), true);
  await r.ask("station.file.part", { station: ST, key: "k1", name: "build.zip", offset: 0, length: 4 * MB, keep: true, size: zip.length });
  assert.equal(r.parts("build.zip"), 3);
  r.core.close();
});

test("a file sent up is called as its sender named it, not as the station keeps it", () => {
  assert.equal(titleOf("2026-10-24T21-59-13-dc7ed5-e2e-tune.m4a"), "e2e-tune.m4a");
  assert.equal(titleOf("build.zip"), "build.zip");
  // (nothing after the mark: kept as it is)
  assert.equal(titleOf("2026-10-24T21-59-13-dc7ed5-"), "2026-10-24T21-59-13-dc7ed5-");
});

test("saved, a file a viewer kept before stays kept: the device keeps what it kept before the download", async () => {
  const film = bytesOf(9 * MB, 5);
  const r = await rig(new Map([["film.mp4", film]]));
  await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 0, length: 4 * MB, keep: true, size: film.length });
  const id = (await r.ask("download.start", { station: ST, key: "k1", name: "film.mp4", size: film.length })).ok.download.id;
  assert.equal((await r.view())[0].state, "ready");
  await r.ask("download.take", { id });
  await r.ask("download.done", { id });
  assert.equal(await Effect.runPromise(r.core.inner.driveKept.has(id)), true);
  // read again: off the device
  await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 0, length: 4 * MB, keep: true, size: film.length });
  assert.equal(r.parts("film.mp4"), 3);
  r.core.close();
});

test("a download stopped by the app's end goes on as the core starts again, from what it had fetched; one taken and not saved is taken again", async () => {
  const big = bytesOf(12 * MB, 2);
  const small = bytesOf(MB, 4);
  const t = await started();
  files(t.host, new Map([["big.zip", big], ["small.zip", small]]));
  const r = await watch(t);
  const held = t.host.hold(`name=big.zip&offset=${4 * MB}&length=${4 * MB}`);
  await r.ask("download.start", { station: ST, key: "k1", name: "big.zip", size: big.length });
  const small1 = (await r.ask("download.start", { station: ST, key: "k1", name: "small.zip", size: small.length })).ok.download.id;
  assert.equal((await r.ask("download.take", { id: small1 })).ok.taken, true);
  const before = await r.view();
  assert.deepEqual(before.map((d) => [d.name, d.state, d.loaded]).sort(), [["big.zip", "going", 4 * MB], ["small.zip", "saving", MB]]);
  r.core.close();
  held();
  // started again over the same device
  const core = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  await t.host.time.pass(500);
  const again = await watch({ host: t.host, core });
  const after = await again.view();
  assert.deepEqual(after.map((d) => [d.name, d.state, d.loaded]).sort(), [["big.zip", "ready", big.length], ["small.zip", "ready", MB]]);
  assert.equal(r.parts("big.zip"), 4, "its first part not fetched again (one asked and let go as the core stopped)");
  core.close();
});

test("a video's load written down as a download before fill.ts brought those goes on as fill.ts's, from what is kept", async () => {
  const film = bytesOf(9 * MB, 8);
  const t = await started();
  files(t.host, new Map([["film.mp4", film]]));
  const r = await watch(t);
  await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 0, length: 4 * MB, keep: true, size: film.length });
  const id = chatKeptId(ST, "k1", "film.mp4");
  await Effect.runPromise(r.core.inner.driveKept.noteDownload(id, { id, station: ST, from: { kind: "chat", key: "k1", file: "film.mp4" }, name: "film.mp4", size: film.length, keptBefore: true, startedAt: 1, keep: true }));
  r.core.close();
  const core = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
  await t.host.time.pass(500);
  const again = await watch({ host: t.host, core });
  assert.deepEqual(await again.view(), []);
  assert.equal(await Effect.runPromise(core.inner.driveKept.whole(id, film.length)), true);
  assert.equal(r.parts("film.mp4"), 3, "its first part not fetched again");
  assert.deepEqual(await Effect.runPromise(core.inner.driveKept.downloads()), []);
  core.close();
});

test("a download whose station is not reached waits for it, and goes on once it is", async () => {
  const zip = bytesOf(6 * MB, 9);
  const away = new Set(["far.zip"]);
  // (its link down too: its events stream not reached)
  const t = await started(undefined, 0, undefined, (s) => (s.gate.stream = "fail"));
  files(t.host, new Map([["far.zip", zip]]), new Set(), away);
  const r = await watch(t);
  const id = (await r.ask("download.start", { station: ST, key: "k1", name: "far.zip", size: zip.length })).ok.download.id;
  const [waiting] = await r.view();
  assert.deepEqual([waiting.state, waiting.active], ["waiting", true]);
  assert.ok(waiting.statusText.length > 0);
  // its station reached again: the link back online
  away.delete("far.zip");
  t.gate.stream = "open";
  await t.host.time.pass(RECONNECT_MS * 2 + 50, 50);
  const [back] = await r.view();
  assert.deepEqual([back.id, back.state], [id, "ready"]);
  r.core.close();
});

test("a part not answered while its station's link is up (a slow network's time out) is asked again, not left waiting for a station that never went", async () => {
  const zip = bytesOf(6 * MB, 9);
  const away = new Set(["slow.zip"]);
  const r = await rig(new Map([["slow.zip", zip]]), new Set(), away);
  assert.equal(r.core.inner.stations.online(ST), true);
  const id = (await r.ask("download.start", { station: ST, key: "k1", name: "slow.zip", size: zip.length })).ok.download.id;
  const [trying] = await r.view();
  assert.equal(trying.state, "going", "not said to wait for its station");
  const tried = r.parts("slow.zip");
  away.delete("slow.zip");
  await r.host.time.pass(AGAIN_MS + 50, 50);
  const [back] = await r.view();
  assert.deepEqual([back.id, back.state], [id, "ready"]);
  assert.ok(r.parts("slow.zip") > tried);
  r.core.close();
});

test("a download goes on from what a preview kept of it; one that failed starts again when asked again; one called off is gone", async () => {
  const film = bytesOf(9 * MB, 7);
  const broken = new Set(["bad.zip"]);
  const r = await rig(new Map([["film.mp4", film], ["bad.zip", bytesOf(MB)]]), broken);
  // its first part read (and kept) by a preview
  await r.ask("station.file.part", { station: ST, key: "k1", name: "film.mp4", offset: 0, length: 4 * MB, keep: true, size: film.length });
  assert.equal(r.parts("film.mp4"), 1);
  await r.ask("download.start", { station: ST, key: "k1", name: "film.mp4", size: film.length });
  assert.equal((await r.view()).find((d) => d.name === "film.mp4").state, "ready");
  assert.equal(r.parts("film.mp4"), 3, "only the two parts not kept");
  // failed: said so, with why
  await r.ask("download.start", { station: ST, key: "k1", name: "bad.zip", size: MB });
  const bad = (await r.view()).find((d) => d.name === "bad.zip");
  assert.deepEqual([bad.state, bad.active], ["failed", false]);
  assert.ok(bad.error && bad.statusText.includes(bad.error), bad.statusText);
  // asked again once the station can: fetched again
  broken.delete("bad.zip");
  await r.ask("download.start", { station: ST, key: "k1", name: "bad.zip", size: MB });
  assert.equal((await r.view()).find((d) => d.name === "bad.zip").state, "ready");
  // called off: out of the list
  await r.ask("download.cancel", { id: bad.id });
  assert.equal((await r.view()).some((d) => d.name === "bad.zip"), false);
  r.core.close();
});

test("a download called off while it comes stops there, what came kept; asked again, only the rest is fetched", async () => {
  const big = bytesOf(12 * MB, 1);
  const t = await rig(new Map([["big.zip", big]]));
  const release = t.host.hold(`name=big.zip&offset=${4 * MB}&length=${4 * MB}`);
  const id = (await t.ask("download.start", { station: ST, key: "k1", name: "big.zip", size: big.length })).ok.download.id;
  const [going] = await t.view();
  assert.deepEqual([going.state, going.loaded], ["going", 4 * MB]);
  await t.ask("download.cancel", { id });
  release();
  assert.deepEqual(await t.view(), []);
  assert.equal(t.parts("big.zip"), 2, "the third part never asked");
  // what came of it kept: asked again, only what did not come
  assert.equal(await Effect.runPromise(t.core.inner.driveKept.has(id)), true);
  await t.ask("download.start", { station: ST, key: "k1", name: "big.zip", size: big.length });
  assert.equal((await t.view())[0].state, "ready");
  const asked = t.host.requests.filter((q) => q.url.includes("name=big.zip&")).map((q) => new URL(q.url).searchParams.get("offset"));
  // (the second never came: it was held as it was called off)
  assert.deepEqual(asked.slice(2), [String(4 * MB), String(8 * MB)], "the first part not asked again");
  t.core.close();
});

test("saved where the app can read it back, that is the file's copy on the device: what was kept of it goes, it is read from there; gone from there, read from the station and kept again", async () => {
  const zip = bytesOf(6 * MB, 11);
  const r = await rig(new Map([["build.zip", zip]]));
  const kept = () => [...r.host.storage.keys()].filter((k) => k.startsWith("drive-kept-")).length;
  const id = (await r.ask("download.start", { station: ST, key: "k1", name: "build.zip", size: zip.length })).ok.download.id;
  assert.equal((await r.view())[0].state, "ready");
  assert.equal(kept(), 2);
  await r.ask("download.take", { id });
  const at = "/Users/lin/Downloads/build.zip";
  r.host.saved.set(at, zip);
  await r.ask("download.done", { id, at });
  assert.deepEqual(await r.view(), []);
  assert.equal(kept(), 0, "no second copy kept beside the one saved");
  // opened again: read from where it was saved, not from the station
  const before = r.parts("build.zip");
  const read = await r.ask("station.file.part", { station: ST, key: "k1", name: "build.zip", offset: 4 * MB, length: 4 * MB, keep: true, size: zip.length });
  assert.deepEqual([...read.bytes], [...zip.slice(4 * MB)]);
  assert.equal(r.parts("build.zip"), before);
  // deleted from there: read from the station again, and kept as any other
  r.host.saved.delete(at);
  await r.ask("station.file.part", { station: ST, key: "k1", name: "build.zip", offset: 0, length: 4 * MB, keep: true, size: zip.length });
  assert.equal(r.parts("build.zip"), before + 1);
  assert.equal(kept(), 1);
  r.core.close();
});

test("saved where the app cannot read it back (the web's, iOS's): what came stays kept", async () => {
  const zip = bytesOf(MB, 13);
  const r = await rig(new Map([["notes.zip", zip]]));
  const id = (await r.ask("download.start", { station: ST, key: "k1", name: "notes.zip", size: zip.length })).ok.download.id;
  await r.view();
  await r.ask("download.take", { id });
  await r.ask("download.done", { id, at: "notes.zip" });
  assert.equal(await Effect.runPromise(r.core.inner.driveKept.whole(id, zip.length)), true);
  r.core.close();
});

test("a drive's file downloaded as its folder lists it, read off the device to be saved; changed on the station since, fetched as it is now", async () => {
  const doc = bytesOf(5 * MB, 17);
  const drive: Drive = { files: new Map([["docs\n报告/年报.pdf", { bytes: doc, mtime: 1700 }]]), zips: new Map() };
  const t = await started();
  files(t.host, new Map(), new Set(), new Set(), drive);
  const r = await watch(t);
  const reads = () => t.host.requests.filter((q) => q.url.includes("/drive/read")).length;
  const id = (await r.ask("download.start", { station: ST, root: "docs", path: "报告/年报.pdf", name: "年报.pdf", size: doc.length, mtime: 1700 })).ok.download.id;
  const [d] = await r.view();
  assert.deepEqual([d.root, d.path, d.name, d.state, d.key], ["docs", "报告/年报.pdf", "年报.pdf", "ready", undefined]);
  assert.equal(reads(), 2);
  await r.ask("download.take", { id });
  const part = await r.ask("download.read", { id, offset: 4 * MB, length: 4 * MB });
  assert.deepEqual([...part.bytes], [...doc.slice(4 * MB)]);
  assert.equal(reads(), 2, "off the device");
  await r.ask("download.done", { id });
  // changed on the station since (its folder read again: another mtime, the size not yet known): what was kept of it
  // as it was let go, fetched as it is now, from its start
  const now = bytesOf(3 * MB, 19);
  drive.files.set("docs\n报告/年报.pdf", { bytes: now, mtime: 1800 });
  const again = (await r.ask("download.start", { station: ST, root: "docs", path: "报告/年报.pdf", name: "年报.pdf", size: doc.length, mtime: 1800 })).ok.download.id;
  const [d2] = await r.view();
  assert.deepEqual([d2.state, d2.size], ["ready", now.length]);
  await r.ask("download.take", { id: again });
  const whole = await r.ask("download.read", { id: again, offset: 0, length: 4 * MB });
  assert.deepEqual([...whole.bytes], [...now]);
  r.core.close();
});

test("a folder downloaded: zipped on the station first (正在打包), then fetched as a file of the drive", async () => {
  const zip = bytesOf(2 * MB, 23);
  const drive: Drive = {
    files: new Map([[".stillfail-zips\n设计稿.zip", { bytes: zip, mtime: 99 }]]),
    zips: new Map([["docs\n设计稿", { root: ".stillfail-zips", path: "设计稿.zip", name: "设计稿.zip" }]]),
  };
  const t = await started();
  files(t.host, new Map(), new Set(), new Set(), drive);
  const r = await watch(t);
  const held = t.host.hold("/drive/zip");
  const id = (await r.ask("download.start", { station: ST, root: "docs", path: "设计稿", name: "设计稿.zip", zip: true })).ok.download.id;
  const [zipping] = await r.view();
  assert.deepEqual([zipping.root, zipping.path, zipping.zip, zipping.state], ["docs", "设计稿", true, "going"]);
  assert.ok(zipping.statusText.length > 0);
  held();
  const [d] = await r.view();
  assert.deepEqual([d.id, d.state, d.size, d.name], [id, "ready", zip.length, "设计稿.zip"]);
  await r.ask("download.take", { id });
  const part = await r.ask("download.read", { id, offset: 0, length: 4 * MB });
  assert.deepEqual([...part.bytes], [...zip]);
  r.core.close();
});
