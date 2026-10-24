// A chat's files downloaded to this device by the core (views/downloads.ts): fetched a part at a time whatever page
// asked, how far each has come told to every page (`downloads`), kept with its chat as it comes, so the page that
// takes it reads it from the device; one read in part before (a preview) goes on from there; one that failed starts
// again when asked again; one called off is gone, what was kept of it with it.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { FakeHost } from "../src/testing.ts";
import { apply as applyOps } from "../src/delta.ts";
import { call, subscribe } from "./helpers.ts";
import { Raw, started, stationReplies, status } from "./station-fixture.ts";

const ST = "ws/st";
const MB = 1024 * 1024;
const bytesOf = (n: number, from = 0) => Uint8Array.from({ length: n }, (_, i) => (from + i) % 251);

/// The session `k1`'s files (by name): their parts answered with the whole size; `broken` names answer 500.
function files(host: FakeHost, all: Map<string, Uint8Array>, broken: Set<string> = new Set()): void {
  stationReplies(host, (req) => {
    const u = new URL(req.url);
    if (!u.pathname.endsWith("/sessions/k1/parts")) return undefined;
    const name = u.searchParams.get("name") ?? "";
    if (broken.has(name)) return status(500, { error: "磁盘读不出来" });
    const f = all.get(name);
    if (f === undefined) return status(404, { error: "文件不存在" });
    const offset = Number(u.searchParams.get("offset"));
    const body = f.slice(offset, offset + Number(u.searchParams.get("length")));
    return new Raw({ status: 200, headers: [["content-type", "application/zip"], ["stillfail-total", String(f.length)]], body });
  });
}

async function rig(all: Map<string, Uint8Array>, broken: Set<string> = new Set()) {
  const t = await started();
  files(t.host, all, broken);
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
  const started = await r.ask("download.start", { station: ST, key: "k1", name: "build.zip", size: zip.length });
  const id = started.ok.download.id as string;
  assert.equal(started.ok.download.state, "going");
  const [d] = await r.view();
  assert.deepEqual([d.id, d.name, d.state, d.loaded, d.progress], [id, "build.zip", "ready", zip.length, 1]);
  assert.equal(r.parts("build.zip"), 3, "three parts of 4 MB");
  // asked again while ready: the same one, nothing fetched again
  assert.equal((await r.ask("download.start", { station: ST, key: "k1", name: "build.zip", size: zip.length })).ok.download.id, id);
  assert.equal(r.parts("build.zip"), 3);
  // taken once: out of the list; a second page taking it gets nothing
  assert.deepEqual((await r.ask("download.take", { id })).ok, { taken: true });
  assert.deepEqual((await r.ask("download.take", { id })).ok, { taken: false });
  assert.deepEqual(await r.view(), []);
  // what the page reads to save it comes off the device
  const read = await r.ask("station.file.part", { station: ST, key: "k1", name: "build.zip", offset: 4 * MB, length: 4 * MB, keep: true, size: zip.length });
  assert.deepEqual([...read.bytes.slice(0, 4)], [...zip.slice(4 * MB, 4 * MB + 4)]);
  assert.equal(r.parts("build.zip"), 3, "not asked of the station again");
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
  assert.equal(bad.state, "failed");
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

test("a download called off while it comes stops there", async () => {
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
  t.core.close();
});
