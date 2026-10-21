// Copies into a station's drive in the core (views/transfers.ts, docs/drive.md "Copying between stations"): the
// person's transfers on every station of the workspace, read as each stream opens and told as they change, in words; a
// copy from another station asked of the one the files are on first (its grant), then of the one they go to; one
// within a station asked of it alone; a transfer stopped or taken up again.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { HttpRequest } from "../src/host.ts";
import { HostWire, type RequestHead, type StationWire } from "../src/station/wire.ts";
import type { StationAddr } from "../src/station/addr.ts";
import type { FakeHost } from "../src/testing.ts";
import { apply as applyOps } from "../src/delta.ts";
import { call, subscribe } from "./helpers.ts";
import { started, stationReplies, status } from "./station-fixture.ts";

/// Which station a request is for, as the wire says it (both answer at the same origin here).
const AT = "x-test-station";

const transfer = (over: Record<string, unknown> = {}) => ({
  id: "t1", by: "a@x.com", workspace: "ws", home: true, anywhere: true, move: false,
  from: { station: "st", stationName: "studio", root: "/Users/lin", path: "Documents", names: ["首页截图.png", "设置页.png"] },
  to: { root: "/Users/me", path: "照片" }, conflicts: {}, state: "copying", done: 0, at: 0, total: 2 * 1024 * 1024, copied: 1024 * 1024, count: 2, files: 2,
  current: "首页截图.png", createdAt: 5, ...over,
});

/// A core reaching `ws/st` (studio) and `ws/st2` (mini); each answers `answer(station, method, path, body)`.
async function rig(answer: (station: string, key: string, body: any) => unknown) {
  const asked: { station: string; key: string; body: any }[] = [];
  const wire = (host: FakeHost) => {
    const inner = new HostWire(host);
    return { request: (station: StationAddr, head: RequestHead, body: Uint8Array) => inner.request(station, { ...head, headers: [...head.headers, [AT, station.station]] }, body) } as StationWire;
  };
  const s = await started(undefined, 0, wire, (x) => {
    x.cloud.also = { stations: [{ id: "st", name: "studio", online: true, last_seen: null }, { id: "st2", name: "mini", online: true, last_seen: null }] };
    stationReplies(x.host, (req: HttpRequest) => {
      const station = req.headers.find(([k]) => k === AT)?.[1] ?? "st";
      const path = req.url.replace("https://stillfail.test/admin/api", "");
      if (!path.startsWith("/drive/transfers") && !path.startsWith("/drive/grant")) return undefined;
      const key = `${req.method} ${path}`;
      const body = req.body && req.body.length ? JSON.parse(new TextDecoder().decode(req.body)) : null;
      if (req.method !== "GET") asked.push({ station, key, body });
      return answer(station, key, body);
    });
  });
  const ui = s.core.connect();
  const values = new Map<number, any>();
  const done = new Map<number, any>();
  const take = () => {
    for (const [, m] of s.host.takeEmitted()) {
      const msg = m as Record<string, unknown>;
      if ("value" in msg) values.set(msg.id as number, msg.value);
      else if ("delta" in msg) values.set(msg.id as number, applyOps(values.get(msg.id as number), msg.delta as never));
      else if ("ok" in msg || "error" in msg) done.set(msg.id as number, msg);
    }
  };
  let n = 100;
  const ask = async (name: string, params: Record<string, unknown>) => {
    const id = ++n;
    call(s.core, ui, id, name, params);
    for (let i = 0; i < 200 && !done.has(id); i++) {
      await s.host.time.pass(10);
      take();
    }
    await s.host.time.pass(100);
    take();
    return done.get(id);
  };
  subscribe(s.core, ui, 1, { topic: "driveTransfers", workspace: "ws" } as never);
  await s.host.time.pass(500);
  take();
  return { ...s, asked, ask, view: () => (take(), values.get(1)) };
}

test("the person's transfers on every station, in words; told as they change", async () => {
  const r = await rig((station, key) => {
    if (key !== "GET /drive/transfers") return undefined;
    return station === "st2" ? { transfers: [transfer()] } : status(404, { error: "no route" });
  });
  const v = r.view();
  assert.equal(v.supported, true);
  assert.equal(v.loaded, true);
  const [t] = v.transfers;
  assert.deepEqual(
    [t.station, t.stationName, t.fromStation, t.fromStationName, t.title, t.toText, t.statusText, t.progress, t.active, t.current],
    ["ws/st2", "mini", "ws/st", "studio", "首页截图.png 等 2 项", "mini › 照片", "1.0 MB / 2.0 MB", 0.5, true, "首页截图.png"],
  );
  // Done, as a station tells it.
  r.push("drive-transfers", { transfer: transfer({ id: "t9", from: { station: null, root: "/a", path: "", names: ["b.txt"] }, to: { root: "/a", path: "" }, state: "done", copied: 3, total: 3, endedAt: 9, createdAt: 9 }) });
  await r.host.time.pass(100);
  const after = r.view();
  assert.deepEqual(after.transfers.map((x: any) => x.id), ["t9", "t1"], "newest first");
  // From the station's own drive (the stream it came on is the one it runs on).
  const nine = after.transfers[0];
  const name = nine.station === "ws/st" ? "studio" : "mini";
  assert.deepEqual([nine.fromStation, nine.title, nine.statusText, nine.progress, nine.active, nine.toText], [nine.station, "b.txt", "已完成 · 3 B", 1, false, `${name} › a`]);
  r.core.close();
});

test("a copy from another station: granted where the files are, then copied where they go; within one, asked of it alone", async () => {
  const r = await rig((_station, key, body) => {
    if (key === "GET /drive/transfers") return { transfers: [] };
    if (key === "POST /drive/grant") return { grant: "g.sig", expires: 1 };
    if (key === "POST /drive/transfers") return { transfer: transfer({ id: "t2", state: "queued", copied: 0, from: { ...body.from, station: body.from.station ?? null } }) };
    if (key === "POST /drive/transfers/t2/cancel") return { transfer: transfer({ id: "t2", state: "cancelled", endedAt: 7 }) };
    return undefined;
  });
  const from = { station: "ws/st", root: "/Users/lin", path: "Documents", names: ["首页截图.png"] };
  const got = await r.ask("drive.transfer", { from, to: { station: "ws/st2", root: "/Users/me", path: "照片" }, conflicts: { "首页截图.png": "keep" } });
  assert.ok("ok" in got, JSON.stringify(got));
  assert.deepEqual(r.asked, [
    { station: "st", key: "POST /drive/grant", body: { root: "/Users/lin", path: "Documents", names: ["首页截图.png"], move: false } },
    { station: "st2", key: "POST /drive/transfers", body: { from: { station: "st", grant: "g.sig", root: "/Users/lin", path: "Documents", names: ["首页截图.png"] }, to: { root: "/Users/me", path: "照片" }, move: false, conflicts: { "首页截图.png": "keep" } } },
  ]);
  assert.equal(got.ok.transfer.statusText, "排队中");
  // Shown at once, before its station tells it.
  assert.deepEqual(r.view().transfers.map((x: any) => [x.id, x.station]), [["t2", "ws/st2"]]);
  const cancelled = await r.ask("drive.transfer.cancel", { station: "ws/st2", id: "t2" });
  assert.equal(cancelled.ok.transfer.statusText, "已取消");
  assert.equal(r.view().transfers[0].active, false);

  r.asked.length = 0;
  await r.ask("drive.transfer", { from: { ...from, station: "ws/st2" }, to: { station: "ws/st2", root: "/Users/me", path: "" }, move: true });
  assert.deepEqual(r.asked.map((a) => [a.station, a.key, a.body?.from?.station, a.body?.move]), [["st2", "POST /drive/transfers", undefined, true]]);

  const other = await r.ask("drive.transfer", { from: { ...from, station: "elsewhere/st" }, to: { station: "ws/st2", root: "/", path: "" } });
  assert.equal(other.error.code, "invalid_params");
  r.core.close();
});
