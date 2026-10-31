// The Rust core's station/tests.rs, ported (same names; the checks as the TS core's design has them: the station is
// read into records by its sync, and its topics read only those; docs/core-ts.md). The Rust tests drove the station
// module with a fake wire and sink; these drive a core over the host's fetch (station-fixture.ts).
import assert from "node:assert/strict";
import { zstdCompressSync, zstdDecompressSync } from "node:zlib";
import { Decompress } from "fzstd";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { dbName } from "../src/data.ts";
import { Core } from "../src/core.ts";
import { CoreError } from "../src/error.ts";
import { encode, request } from "../src/ops.ts";
import { StationAddr } from "../src/station/addr.ts";
import { SseParser } from "../src/station/sse.ts";
import { run } from "./run.ts";
import { Raw, base, entries, entry, overview, session, started, status, stationReplies, threadView } from "./station-fixture.ts";
import { merge } from "../src/entries.ts";
import { apply, call, readsOf, subscribe, v } from "./helpers.ts";
import { COALESCE_MS, EVICT_AFTER_MS } from "../src/store.ts";
import { CHANGES_RETRY_MS, EVENTS_COALESCE_MS, LINK_KEY, LONG_MISSES, OFFLINE_RETRY_MS, READ_RETRY_MS, RECONNECT_MAX_MS, RECONNECT_MS, STREAM_IDLE_MS } from "../src/station/sync.ts";
import { digest } from "../src/digest.ts";
import { Priority } from "../src/sync/scheduler.ts";
import { JSON_IDLE_MS, SOCKET_OPEN_MS } from "../src/station/requests.ts";
import { HostWire, concat, encodeFrame, takeFrames, type LinkNet } from "../src/station/wire.ts";
import { NET_EVERY_MS } from "../src/station/topics.ts";
import { apply as applyOps, type Op } from "../src/delta.ts";
import type { FakeHost } from "../src/testing.ts";

const gets = (host: FakeHost, path: string) => host.requests.flatMap(readsOf).filter((url) => url.endsWith(path)).length;
const text = (b: Uint8Array | null | undefined) => (b === undefined || b === null ? undefined : new TextDecoder().decode(b));

// deno-lint-ignore no-explicit-any
type J = any;
const ST = "ws/st";
const remote = () => StationAddr.parse(ST);
const op = (name: string, params: J) => request(name, { station: ST, ...params })!;
const failure = async (e: Effect.Effect<unknown, CoreError>) => {
  const r = await Effect.runPromise(Effect.result(e));
  assert.equal(r._tag, "Failure");
  return (r as { failure: CoreError }).failure;
};

test("parses_addresses", () => {
  assert.deepEqual([remote().workspace, remote().station], ["ws", "st"]);
  assert.equal(remote().toString(), "ws/st");
  for (const bad of ["", "ws", "/st", "ws/", "a/b/c", "Local"]) {
    assert.throws(() => StationAddr.parse(bad), (e: CoreError) => e.code === "invalid_params", bad);
  }
  // A station's own page, still in kept links and prefs: gone, said so.
  assert.throws(() => StationAddr.parse("local"), (e: CoreError) => e.code === "gone");
});

test("parses_sse_across_chunks", () => {
  const p = new SseParser();
  const bytes = (s: string) => new TextEncoder().encode(s);
  assert.deepEqual(p.feed(bytes("retry: 2000\n\n: ping\n\nevent: sess")), []);
  assert.deepEqual(p.feed(bytes('ion\r\ndata: {"key":"a"}\r\n\r\ndata: x\ndata:y\n\nevent: e\n')), [
    ["session", '{"key":"a"}'],
    ["message", "x\ny"],
  ]);
  const text = bytes("data: 你好\n\n");
  assert.deepEqual(p.feed(text.slice(0, 7)), []);
  assert.deepEqual(p.feed(text.slice(7)), [["e", "你好"]]);
});

test("encodes_like_the_web", () => {
  assert.equal(encode("a b/ç!"), "a%20b%2F%C3%A7!");
});

test("maps_request_errors", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /overview": { connects: [] },
    "POST /sessions/k/stop": status(403, { error: "没有权限" }),
    "GET /host": status(500, "oops"),
  });
  const requests = core.inner.stations.requests;
  assert.deepEqual(await run(requests.call(remote(), "GET", "/overview", null)), { connects: [] });
  let e = await failure(core.inner.stations.perform(op("session.stop", { key: "k" }), null));
  assert.deepEqual([e.code, e.message, e.status], ["http_403", "没有权限", 403]);
  e = await failure(requests.call(remote(), "GET", "/host", null));
  assert.deepEqual([e.code, e.message, e.status], ["http_500", "请求失败（500）", 500]);
  // A bodyless named operation stays bodyless.
  const stop = host.requests.find((r) => r.url.endsWith("/sessions/k/stop"))!;
  assert.equal(stop.body?.length ?? 0, 0);
  core.close();
});

test("uploads_and_reads_files", async () => {
  const { host, core } = await started({
    ...base(),
    "POST /uploads?name=a%20b.png": { name: "a b.png" },
    "GET /sessions/k/files?name=x": status(404, { error: "文件不存在" }),
  });
  const requests = core.inner.stations.requests;
  const saved = (await run(requests.upload(remote(), "a b.png", new Uint8Array([1, 2, 3]), null))) as J;
  assert.equal(saved.name, "a b.png");
  assert.deepEqual([...host.requests.find((r) => r.url.includes("/uploads"))!.body!], [1, 2, 3]);
  const e = await failure(requests.file(remote(), "k", "x", false, () => {}, null));
  assert.deepEqual([e.message, e.status], ["无法读取文件", 404]);
  core.close();
});

test("uploads_in_parts_and_whole_to_a_station_before_parts", async () => {
  const { host, core } = await started({
    ...base(),
    "POST /uploads/parts?id=abcdefgh12&name=a.bin&size=3&offset=0": { have: 3, file: { name: "a.bin", path: "/u/a.bin", size: 3 } },
    "POST /uploads?name=b.bin": { name: "b.bin", path: "/u/b.bin", size: 4 },
  });
  const requests = core.inner.stations.requests;
  assert.deepEqual(await run(requests.uploadPart(remote(), { id: "abcdefgh12", name: "a.bin", size: 3, offset: 0 }, new Uint8Array([1, 2, 3]), null)), { have: 3, file: { name: "a.bin", path: "/u/a.bin", size: 3 } });
  // A station from before parts (404): the parts are kept here, and the whole file goes in one upload.
  const q = { id: "oldstation", name: "b.bin", size: 4 };
  assert.deepEqual(await run(requests.uploadPart(remote(), { ...q, offset: 0 }, new Uint8Array([1, 2]), null)), { have: 2 });
  assert.deepEqual(await run(requests.uploadPart(remote(), { ...q, offset: 0 + 9 }, new Uint8Array([9]), null)), { have: 2 });
  assert.deepEqual(await run(requests.uploadPart(remote(), { ...q, offset: 2 }, new Uint8Array([3, 4]), null)), { have: 4, file: { name: "b.bin", path: "/u/b.bin", size: 4 } });
  assert.deepEqual([...host.requests.find((r) => r.url.includes("/uploads?name=b.bin"))!.body!], [1, 2, 3, 4]);
  // Too big for it: said so.
  const e = await failure(requests.uploadPart(remote(), { id: "toobig1234", name: "c.bin", size: 60 * 1024 * 1024, offset: 0 }, new Uint8Array([1]), null));
  assert.equal(e.status, 413);
  core.close();
});

test("fetches_a_file_in_parts_and_a_poster", async () => {
  const { core } = await started({
    ...base(),
    "GET /sessions/k/parts?name=v.mp4&offset=0&length=4": "abcd",
    "GET /sessions/k/parts?name=old.mp4&offset=0&length=4": status(404, { error: "no route GET /sessions/k/parts" }),
    "GET /sessions/k/parts?name=gone.mp4&offset=0&length=4": status(404, { error: "文件不存在" }),
    "GET /sessions/k/poster?name=v.mp4": "jpeg",
  });
  const requests = core.inner.stations.requests;
  const got = await run(requests.filePart(remote(), "k", "v.mp4", 0, 4, null));
  assert.equal(new TextDecoder().decode(got.bytes), JSON.stringify("abcd"));
  // A station from before parts, and a file that is not there, apart.
  assert.equal((await failure(requests.filePart(remote(), "k", "old.mp4", 0, 4, null))).code, "unsupported");
  assert.equal((await failure(requests.filePart(remote(), "k", "gone.mp4", 0, 4, null))).code, "http_404");
  assert.equal(new TextDecoder().decode((await run(requests.poster(remote(), "k", "v.mp4", null)))!), JSON.stringify("jpeg"));
  assert.equal(await run(requests.poster(remote(), "k", "none.mp4", null)), null);
  core.close();
});

test("tells_how_far_a_file_has_come", async () => {
  const big = "x".repeat(300 * 1024);
  const { core } = await started({ ...base(), "GET /sessions/k/files?name=big": big });
  const heard: [number, number | null][] = [];
  const [, bytes] = await run(core.inner.stations.requests.file(remote(), "k", "big", false, (loaded, total) => heard.push([loaded, total]), null));
  // At the start, then once past 64 KB (the size not given, it comes in one chunk here).
  assert.deepEqual(heard, [[0, null], [bytes.length, null]]);
  core.close();
});

test("tells_how_far_a_part_has_come", async () => {
  const big = "x".repeat(300 * 1024);
  const { core } = await started({ ...base(), "GET /sessions/k/parts?name=big&offset=0&length=4194304": big });
  const heard: number[] = [];
  const got = await run(core.inner.stations.requests.filePart(remote(), "k", "big", 0, 4194304, null, (loaded) => heard.push(loaded)));
  // Past 64 KB (it comes in one chunk here); nothing heard without asking.
  assert.deepEqual(heard, [got.bytes.length]);
  core.close();
});

test("hands_a_part_over_as_it_comes", async () => {
  const big = "x".repeat(300 * 1024);
  const { host, core } = await started({
    ...base(),
    "GET /sessions/k/parts?name=big&offset=0&length=4194304": big,
    "GET /sessions/k/parts?name=gone&offset=0&length=4194304": status(404, { error: "文件不存在" }),
  });
  const ui = core.connect();
  const said = (id: number) => host.takeEmitted().map(([, m]) => m as J).filter((m) => m.id === id);
  call(core, ui, 1, "station.file.part", { station: ST, key: "k", name: "big", offset: 0, length: 4194304, stream: true });
  await host.settle();
  const one = said(1);
  const pieces = one.filter((m) => m.bytes !== undefined);
  // Its bytes beside values saying how far it has come, none in its answer.
  assert.equal(text(concat(pieces.map((m) => m.bytes))), JSON.stringify(big));
  assert.deepEqual(pieces.at(-1)?.value, { loaded: JSON.stringify(big).length });
  assert.equal(one.find((m) => "ok" in m)?.ok.bytes, undefined);
  // An error's body is not handed over as the file's.
  call(core, ui, 2, "station.file.part", { station: ST, key: "k", name: "gone", offset: 0, length: 4194304, stream: true });
  await host.settle();
  const two = said(2);
  assert.equal(two.filter((m) => m.bytes !== undefined).length, 0);
  assert.equal(two.find((m) => "error" in m)?.error.code, "http_404");
  core.close();
});

test("a_file_a_message_names_opens_whole_its_bytes_beside_from_a_station_new_or_old", async () => {
  const { host, core } = await started(base());
  stationReplies(host, (req) => {
    if (req.url.endsWith("/sessions/k/open?path=%2Fw%2Fnew.png&raw=1")) {
      return new Raw({ status: 200, headers: [["content-type", "image/png"], ["stillfail-name", "new.png"], ["stillfail-path", encodeURIComponent("/w/new.png")]], body: new Uint8Array([1, 2, 3]) });
    }
    // A station from before `raw`: its JSON, the bytes in it as base64.
    if (req.url.endsWith("/sessions/k/open?path=%2Fw%2Fold.png&raw=1")) return { name: "old.png", path: "/w/old.png", type: "image/png", size: 2, bytes: Buffer.from([4, 5]).toString("base64") };
    if (req.url.endsWith("/sessions/k/open?path=%2Fw%2Fgone.png&raw=1")) return status(404, { error: "no such file" });
    return undefined;
  });
  const ui = core.connect();
  const said = (id: number) => host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m)) as J;
  call(core, ui, 1, "file.open", { station: ST, key: "k", path: "/w/new.png" });
  await host.settle();
  const fresh = said(1);
  assert.deepEqual([fresh.ok, [...fresh.bytes]], [{ name: "new.png", path: "/w/new.png", type: "image/png", size: 3 }, [1, 2, 3]]);
  call(core, ui, 2, "file.open", { station: ST, key: "k", path: "/w/old.png" });
  await host.settle();
  const old = said(2);
  assert.deepEqual([old.ok, [...old.bytes]], [{ name: "old.png", path: "/w/old.png", type: "image/png", size: 2 }, [4, 5]]);
  call(core, ui, 3, "file.open", { station: ST, key: "k", path: "/w/gone.png" });
  await host.settle();
  assert.equal(said(3).error.code, "http_404");
  core.close();
});

test("a_part_of_a_file_a_message_names_is_read_by_its_path_its_whole_size_said_or_cut_from_the_whole_of_an_old_station", async () => {
  const { host, core } = await started(base());
  stationReplies(host, (req) => {
    if (req.url.endsWith("/sessions/k/open?path=%2Fw%2Fnew.log&raw=1&offset=2&length=3")) {
      return new Raw({ status: 200, headers: [["content-type", "text/plain"], ["stillfail-name", "new.log"], ["stillfail-path", encodeURIComponent("/w/new.log")], ["stillfail-total", "40"]], body: new Uint8Array([3, 4, 5]) });
    }
    // A station from before parts by path: the whole, no total.
    if (req.url.endsWith("/sessions/k/open?path=%2Fw%2Fold.log&raw=1&offset=2&length=3")) {
      return new Raw({ status: 200, headers: [["content-type", "text/plain"], ["stillfail-name", "old.log"], ["stillfail-path", encodeURIComponent("/w/old.log")]], body: new Uint8Array([1, 2, 3, 4, 5, 6, 7]) });
    }
    return undefined;
  });
  const ui = core.connect();
  const said = (id: number) => host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m)) as J;
  call(core, ui, 1, "file.open", { station: ST, key: "k", path: "/w/new.log", offset: 2, length: 3 });
  await host.settle();
  const fresh = said(1);
  assert.deepEqual([fresh.ok, [...fresh.bytes]], [{ name: "new.log", path: "/w/new.log", type: "text/plain", size: 40 }, [3, 4, 5]]);
  call(core, ui, 2, "file.open", { station: ST, key: "k", path: "/w/old.log", offset: 2, length: 3 });
  await host.settle();
  const old = said(2);
  assert.deepEqual([old.ok, [...old.bytes]], [{ name: "old.log", path: "/w/old.log", type: "text/plain", size: 7 }, [3, 4, 5]]);
  core.close();
});

void stationReplies;

const linkOf = (values: Map<number, unknown>, id: number) => (values.get(id) as J)?.state;

test("a_station_not_reached_is_down_and_asked_for_nothing_until_it_is", async () => {
  // Never reached: down (whatever else says otherwise), and kept so for the next start.
  const { host, core, gate } = await started({ ...base(), "GET /overview": { connects: [], profiles: [] } }, 0, undefined, (s) => (s.gate.stream = "fail"));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "link", station: ST });
  subscribe(core, ui, 2, { topic: "overview", station: ST });
  await host.settle();
  apply(host, values);
  assert.equal(linkOf(values, 1), "offline");
  assert.equal(core.inner.data.record("link", ST), "offline");
  assert.equal(gets(host, "/admin/api/overview"), 0, "down: nothing asked");
  // Reached: what it holds is read.
  gate.stream = "open";
  await host.time.pass(RECONNECT_MS * 2 + 50, 50);
  apply(host, values);
  assert.equal(linkOf(values, 1), "online");
  assert.equal(gets(host, "/admin/api/overview"), 1, "back: what it holds is read");
  assert.equal(core.inner.data.record("link", ST), "online");
  core.close();
});

test("a_station_the_cloud_says_is_not_online_is_tried_seldom_and_at_once_when_it_is_back", async () => {
  const { host, core, gate } = await started(base(), 0, undefined, (s) => {
    s.gate.stream = "fail";
    s.cloud.online = false;
  });
  const tries = () => host.requests.filter((r) => r.url.includes("/admin/api/events")).length;
  const first = tries();
  assert.ok(first >= 1);
  // Not tried again each minute while the cloud says it is not online.
  await host.time.pass(5 * RECONNECT_MAX_MS, 1_000);
  assert.equal(tries(), first);
  // The cloud says it is back: tried at once.
  gate.stream = "open";
  host.socketSend("/v1/events", JSON.stringify({ type: "station", workspace: "ws", id: "st", online: true }));
  await host.time.pass(1_000, 100);
  assert.equal(tries(), first + 1);
  core.close();
});

test("a_station_that_was_up_is_tried_again_at_once_though_the_cloud_says_it_is_not_online", async () => {
  // The cloud hears of a station on a way of its own: it says the station is not online while its stream here is open.
  const { host, core, end, push } = await started();
  const tries = () => host.requests.filter((r) => r.url.includes("/admin/api/events")).length;
  host.socketSend("/v1/events", JSON.stringify({ type: "station", workspace: "ws", id: "st", online: false }));
  await host.settle();
  const before = tries();
  // Its stream ends: opened again as one coming back, not left OFFLINE_RETRY_MS.
  end();
  await host.time.pass(RECONNECT_MS + 50, 50);
  assert.equal(tries(), before + 1);
  assert.equal(core.inner.data.record("link", ST), "online");
  // And what the agent says comes as it is said.
  push("thread", { id: 7, entries: [entry(4, "来了")] });
  await host.settle();
  assert.deepEqual([...core.inner.data.logRange("entry", ST, "7", 4, 4).keys()], [4]);
  core.close();
});

test("a_push_brings_its_chat_onto_the_device_whether_the_stream_told_it_or_not", async () => {
  const answers: J = { ...base() };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const held = (thread: number) => [...core.inner.data.logRange("entry", ST, String(thread), 1, 100).keys()];
  assert.deepEqual(held(7), [1, 2, 3]);
  const answered = (id: number) => host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m));
  // Said while the phone slept: its stream did not tell it, its push did.
  answers["GET /threads/7/entries?after=3"] = { last: 4, entries: [entry(4, "做完了")] };
  call(core, ui, 1, "notice.bring", { station: ST, session: "k1", seq: 4 });
  await host.settle();
  assert.deepEqual(answered(1)?.ok, null);
  assert.deepEqual(held(7), [1, 2, 3, 4]);
  // Held already (the stream told it first): nothing is asked.
  let from = host.requests.length;
  call(core, ui, 2, "notice.bring", { station: ST, session: "k1", seq: 4 });
  await host.settle();
  assert.deepEqual(answered(2)?.ok, null);
  assert.equal(host.requests.slice(from).filter((r) => r.url.includes("/entries")).length, 0);
  // An older station's push says no message: asked what came after what is held.
  answers["GET /threads/7/entries?after=4"] = { last: 5, entries: [entry(5, "又一条")] };
  call(core, ui, 3, "notice.bring", { station: ST, session: "k1" });
  await host.settle();
  assert.deepEqual(held(7), [1, 2, 3, 4, 5]);
  // A chat the device has not heard of: the station's chats say which it is, and its latest is read.
  answers["GET /chats"] = [...answers["GET /chats"], { id: "8", thread: 8, session: "k2", title: "新的", agents: [], lastActiveAt: 2 }];
  answers["GET /threads/8/entries?limit=50"] = { last: 1, entries: [{ ...entry(1, "你好"), thread: 8 }] };
  call(core, ui, 4, "notice.bring", { station: ST, session: "k2", seq: 1 });
  await host.settle();
  assert.deepEqual(answered(4)?.ok, null);
  assert.deepEqual(held(8), [1]);
  // Of a station the device does not reach: nothing is read.
  from = host.requests.length;
  call(core, ui, 5, "notice.bring", { station: "ws/other", session: "k1", seq: 1 });
  await host.settle();
  assert.deepEqual(answered(5)?.ok, null);
  assert.equal(host.requests.slice(from).filter((r) => r.url.includes("/admin/api/")).length, 0);
  core.close();
});

test("a_station_that_answers_a_request_has_its_stream_tried_now_not_when_its_wait_ends", async () => {
  // Not reached while the cloud says it is not online: tried again in OFFLINE_RETRY_MS.
  const answers = { ...base(), "POST /threads/7/messages": { n: 4 }, "GET /threads/7/entries?limit=50": { last: 4, entries: entries(1, 4) } };
  const { host, core, gate, push } = await started(answers, 0, undefined, (s) => {
    s.gate.stream = "fail";
    s.cloud.online = false;
  });
  const tries = () => host.requests.filter((r) => r.url.includes("/admin/api/events")).length;
  await host.time.pass(RECONNECT_MAX_MS, 1_000);
  const before = tries();
  // A person's message goes through (the station is there after all): its stream is opened now.
  gate.stream = "open";
  assert.equal(await run(core.inner.stations.post(ST, 7, { text: "在吗" }, null)), 4);
  await host.time.pass(1_000, 100);
  assert.equal(tries(), before + 1);
  assert.equal(core.inner.data.record("link", ST), "online");
  // What the agent says after it comes as it is said, without another message asked for.
  push("thread", { id: 7, entries: [entry(5, "在")] });
  await host.settle();
  assert.deepEqual([...core.inner.data.logRange("entry", ST, "7", 5, 5).keys()], [5]);
  core.close();
});

test("a_station_the_cloud_lists_online_again_is_tried_at_once_though_its_event_went_by", async () => {
  const { host, core, gate, cloud } = await started(base(), 0, undefined, (s) => {
    s.gate.stream = "fail";
    s.cloud.online = false;
  });
  const tries = () => host.requests.filter((r) => r.url.includes("/admin/api/events")).length;
  await host.time.pass(RECONNECT_MAX_MS, 1_000);
  const before = tries();
  // The workspace read anew (its socket was down as the station came back) lists it online.
  gate.stream = "open";
  cloud.online = true;
  host.socketSend("/v1/events", JSON.stringify({ type: "workspace", id: "ws" }));
  await host.time.pass(1_000, 100);
  assert.equal(tries(), before + 1);
  assert.equal(core.inner.data.record("link", ST), "online");
  core.close();
});

test("a_station_down_shows_it_is_tried_again_as_soon_as_a_person_asks", async () => {
  const { host, core, gate } = await started(base(), 0, undefined, (s) => (s.gate.stream = "fail"));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "link", station: ST });
  await host.settle();
  apply(host, values);
  assert.equal(linkOf(values, 1), "offline");
  subscribe(core, ui, 3, { topic: "stations", scope: "ws" });
  await host.settle();
  apply(host, values);
  const shown = () => (values.get(3) as J[]).find((s) => s.station === ST);
  assert.equal(shown().online, false);
  // 重试 (client.wake, network), and the try it starts takes a while: said to be tried, still down meanwhile (what
  // shows of it does not change to come back as the try fails).
  gate.stream = "hang";
  call(core, ui, 2, "client.wake", { away: 0, network: true });
  await host.time.pass(COALESCE_MS * 4, 10);
  apply(host, values);
  assert.equal(linkOf(values, 1), "connecting");
  assert.equal((values.get(1) as J).retrying, true);
  assert.deepEqual([shown().online, shown().reconnecting, shown().link.retrying], [false, false, true]);
  core.close();
});

test("a_stations_host_reading_makes_its_overview_in_the_list_again_not_every_time", async () => {
  // A station tells its host reading every few seconds, each station of a workspace in turn: the list was made anew
  // each time, every station's overview copied and its times put in words again, and the new chat's view after it
  // (50-80 ms a time on a phone, 2026-10-31). Its overview as the list shows it is made again only as it changes.
  const { host, core } = await started(base());
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 3, { topic: "stations", scope: "ws" });
  await host.settle();
  apply(host, values);
  const item = () => (core.inner.store.get({ topic: "stations", scope: "ws" }) as J[]).find((s) => s.station === ST);
  const before = item();
  assert.ok(before.overview !== null && typeof before.overview === "object", JSON.stringify(before).slice(0, 300));
  core.inner.stations.link(ST)!.memory.set("host", { os: "macOS", cpus: 8, load: 1, memory: { usedBytes: 1, totalBytes: 2 } });
  core.inner.stations.onChange(ST, "host");
  await host.time.pass(COALESCE_MS * 2, 10);
  const after = item();
  assert.notEqual(after.host, before.host, "its reading shown");
  assert.equal(after.overview, before.overview, "its overview as it was made");
  core.close();
});

const summary = (key: string, turns: number) => ({ ...session(key, turns), title: null, archivedAt: null, lastTurn: null });

test("a_rows_digest_is_the_stations_whatever_the_order_of_its_fields", () => {
  // The values station/test/hub-routes.test.ts takes: the station makes the same digests.
  const v = { b: [1, "x", null, true, { z: 2, y: [] }], a: { d: 1.5, c: '中文 \u2028 "q"' }, e: -0 };
  const w = { e: 0, a: { c: '中文 \u2028 "q"', d: 1.5 }, b: [1, "x", null, true, { y: [], z: 2 }] };
  assert.deepEqual([digest(v), digest(w), digest(Object.freeze({ k: 1 })), digest({ k: 2 })], ["txw0i07ix8", "txw0i07ix8", "1x451bsuzqf", "1jui8glvs7p"]);
});

/// The digests a list was asked with (POST /changed/<list>) in the requests from `from` on.
const heldIn = (host: FakeHost, from: number, list: string): J[] =>
  host.requests
    .slice(from)
    .filter((r) => r.method === "POST" && r.url.endsWith(`/admin/api/changed/${list}`))
    .map((r) => JSON.parse(new TextDecoder().decode(r.body!)).held);

/// A station of `n` chats (threads 1 to n, each of `last` entries) beside its one session.
const manyChats = (n: number, last: number): J => {
  const answers: J = { ...base(), "GET /threads": Array.from({ length: n }, (_, i) => threadView(i + 1, last)) };
  for (let id = 1; id <= n; id++) answers[`GET /threads/${id}/entries?limit=50`] = { last, entries: entries(1, last).map((e) => ({ ...e, thread: id })) };
  return answers;
};
const batchesIn = (host: FakeHost, from = 0) => host.requests.slice(from).filter((r) => r.method === "POST" && r.url.endsWith("/admin/api/batch"));

test("a_stations_history_comes_in_batches", async () => {
  const { host, core } = await started(manyChats(60, 3));
  // 60 chats' entries, the session's detail and its transcript's latest page: in two batches of what was 62 requests,
  // nothing read alone.
  const batches = batchesIn(host).map((r) => JSON.parse(new TextDecoder().decode(r.body!)).gets as string[]);
  assert.deepEqual(batches.map((b) => b.length), [40, 22]);
  assert.deepEqual(batches[0]!.slice(0, 3), ["/sessions/k1", "/threads/60/entries?limit=50", "/threads/59/entries?limit=50"], "the latest chats first");
  assert.equal(batches[1]!.at(-1), "/sessions/k1/timeline?before=1000000000000000&limit=200&brief=1");
  assert.equal(host.requests.filter((r) => r.method === "GET" && r.url.includes("/entries")).length, 0);
  for (const id of [1, 30, 60]) assert.deepEqual(core.inner.data.logNumbers("entry", ST, String(id)), [1, 2, 3]);
  core.close();
});

test("a_chat_opened_is_read_at_once_not_behind_the_batches", async () => {
  const s = await ui(manyChats(60, 3), (st) => st.host.hold("/admin/api/batch"));
  // The history's batch hangs on a slow link; a chat opened: its latest page alone, at once.
  assert.equal(batchesIn(s.host).length, 1);
  subscribe(s.core, s.ui, 1, { topic: "thread", station: ST, thread: 1 });
  await s.read();
  assert.deepEqual(nums(s.values), [1, 2, 3]);
  assert.equal(gets(s.host, "/admin/api/threads/1/entries?limit=50"), 1);
  s.core.close();
});

test("a_station_from_before_batches_is_read_a_request_a_read", async () => {
  const { host, core } = await started(manyChats(3, 3), 0, undefined, (st) => (st.batches.on = false));
  // Asked once, refused (it has no such route): each read its own request, as before.
  const alone = (path: string) => host.requests.filter((r) => r.method === "GET" && r.url.endsWith(path)).length;
  assert.equal(batchesIn(host).length, 1);
  assert.deepEqual([1, 2, 3].map((id) => alone(`/admin/api/threads/${id}/entries?limit=50`)), [1, 1, 1]);
  assert.equal(alone("/admin/api/sessions/k1"), 1);
  for (const id of [1, 2, 3]) assert.deepEqual(core.inner.data.logNumbers("entry", ST, String(id)), [1, 2, 3]);
  core.close();
});

test("a_read_of_the_history_that_brings_nothing_is_not_asked_again_until_the_next_sweep", async () => {
  // A chat said to go to 5, whose station gives nothing.
  const answers: J = { ...base(), "GET /threads": [threadView(7, 5)], "GET /threads/7/entries?limit=50": { last: 5, entries: [] } };
  const { host, core } = await started(answers);
  await host.time.pass(5_000, 500);
  assert.equal(gets(host, "/admin/api/threads/7/entries?limit=50"), 1);
  core.inner.stations.snapshot(ST);
  await host.settle();
  assert.equal(gets(host, "/admin/api/threads/7/entries?limit=50"), 2, "asked again in the next");
  core.close();
});

test("lists_held_are_read_again_as_what_changed_of_them", async () => {
  const answers: J = { ...base(), "GET /sessions": [session("k1"), session("k2")], "GET /sessions/k2": { session: session("k2"), threads: [], turns: [], jobs: [] } };
  const s = await ui(answers);
  const { host, core } = s;
  // Nothing held: read whole.
  assert.deepEqual([gets(host, "/admin/api/threads"), heldIn(host, 0, "threads").length], [1, 0]);
  // Held, each row as the station has it (the fields the device keeps apart put back too): read again, every row is
  // held as it is, and the station would send none.
  const lists: [string, string, string][] = [["chats", "id", "GET /chats"], ["threads", "id", "GET /threads"], ["sessions", "key", "GET /sessions"]];
  const asked = (from: number) => lists.map(([list]) => heldIn(host, from, list).at(-1));
  const as = (rows: J[], id: string) => Object.fromEntries(rows.map((r) => [String(r[id]), digest(r)]));
  let from = host.requests.length;
  core.inner.stations.snapshot(ST);
  await host.settle();
  assert.deepEqual(asked(from), lists.map(([, id, get]) => as(answers[get], id)));
  // So after the app starts anew, the rows read from its database.
  const again = await reopen(s);
  from = host.requests.length;
  again.core.inner.stations.snapshot(ST);
  await host.settle();
  assert.deepEqual(asked(from), lists.map(([, id, get]) => as(answers[get], id)));
  // One thread on, one new, the chat gone: the device has the lists as the station does.
  answers["GET /threads"] = [threadView(7, 4), threadView(8, 1)];
  answers["GET /threads/7/entries?after=3"] = { last: 4, entries: [entry(4, "m4")] };
  answers["GET /chats"] = [];
  again.core.inner.stations.snapshot(ST);
  await host.settle();
  const threads = (again.core.inner.data.get({ topic: "threads", station: ST }) as J[]).map((t) => [t.id, t.last]).sort();
  assert.deepEqual(threads, [[7, 4], [8, 1]]);
  assert.deepEqual(again.core.inner.data.get({ topic: "chatRows", station: ST }), []);
  assert.deepEqual((again.core.inner.data.get({ topic: "sessions", station: ST }) as J[]).map((x) => x.key).sort(), ["k1", "k2"]);
  assert.equal(host.requests.filter((r) => r.method === "GET" && r.url.endsWith("/admin/api/threads")).length, 1, "whole only the first time");
  again.core.close();
});

test("a_station_from_before_is_read_whole_and_asked_again_after_a_while", async () => {
  const { host, core, changes } = await started(base());
  changes.on = false;
  const lists = ["chats", "threads", "sessions"];
  const asked = (from: number) => lists.map((l) => heldIn(host, from, l).length).reduce((a, b) => a + b, 0);
  const whole = (from: number) => lists.map((l) => host.requests.slice(from).filter((r) => r.method === "GET" && r.url.endsWith(`/admin/api/${l}`)).length);
  let from = host.requests.length;
  core.inner.stations.snapshot(ST);
  await host.settle();
  // Asked what changed, refused (it has no such route): read whole, and the rest whole at once.
  assert.ok(asked(from) >= 1);
  assert.deepEqual(whole(from), [1, 1, 1]);
  from = host.requests.length;
  core.inner.stations.snapshot(ST);
  await host.settle();
  assert.deepEqual([asked(from), whole(from)], [0, [1, 1, 1]]);
  // Updated since, maybe: asked again after a while.
  changes.on = true;
  host.advance(CHANGES_RETRY_MS);
  from = host.requests.length;
  core.inner.stations.snapshot(ST);
  await host.settle();
  assert.deepEqual([asked(from), whole(from)], [3, [0, 0, 0]]);
  core.close();
});

test("what_changed_answered_no_or_not_adding_up_is_read_whole", async () => {
  const { host, core } = await started(base());
  // A row in the order neither held nor sent.
  let reply: unknown = { order: ["7", "x"], rows: [] };
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/changed/chats") ? reply : undefined));
  const whole = (from: number) => host.requests.slice(from).filter((r) => r.method === "GET" && r.url.endsWith("/admin/api/chats")).length;
  let from = host.requests.length;
  core.inner.stations.snapshot(ST);
  await host.settle();
  assert.equal(whole(from), 1);
  assert.deepEqual((core.inner.data.get({ topic: "chatRows", station: ST }) as J[]).map((r) => r.id), ["7"]);
  // Answered no (too much held, say): read whole, and asked again the next time.
  reply = status(413, { error: "request too large" });
  for (const _ of [1, 2]) {
    from = host.requests.length;
    core.inner.stations.snapshot(ST);
    await host.settle();
    assert.deepEqual([heldIn(host, from, "chats").length, whole(from)], [1, 1]);
  }
  core.close();
});

test("writes_bring_what_they_touch_up_to_date", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /sessions": [summary("k 1", 0), summary("other", 0)],
    "GET /sessions/k%201": { session: summary("k 1", 0), threads: [], turns: [] },
    "GET /sessions/other": { session: summary("other", 0), threads: [], turns: [] },
    "GET /threads": [],
    "POST /sessions/k%201/stop": {},
    "GET /slack/config-token": {},
    "POST /profiles/p/check": {},
    "POST /updates/channel": [],
    "POST /slack/config-tokens": {},
  });
  const perform = (name: string, params: J) => run(core.inner.stations.perform(op(name, params), null));
  await host.settle();
  assert.notEqual(core.inner.data.get({ topic: "session", station: ST, key: "k 1" }), undefined);
  const [s, k, o, other, chats] = ["/admin/api/sessions", "/admin/api/sessions/k%201", "/admin/api/overview", "/admin/api/sessions/other", "/admin/api/chats"].map((p) => gets(host, p));
  await perform("session.stop", { key: "k 1" });
  await host.settle();
  // Its process stopped: its own detail read again before the call answers; the lists that show it its station tells
  // as they change, and are not read whole again.
  assert.equal(gets(host, "/admin/api/sessions"), s);
  assert.equal(gets(host, "/admin/api/sessions/k%201"), k + 1);
  assert.equal(gets(host, "/admin/api/chats"), chats);
  assert.equal(gets(host, "/admin/api/sessions/other"), other);
  assert.equal(gets(host, "/admin/api/overview"), o);
  // A profile edit answers the overview: that is the record now, nothing is read again.
  // (Checked already: a profile not checked yet is checked as it appears, which reads the overview again.)
  const edited = { ...overview, profiles: [{ id: "p", check: { state: "ok", detail: "", checkedAt: 1 } }] };
  stationReplies(host, (req) => (req.method === "PUT" && req.url.endsWith("/profiles/p") ? edited : undefined));
  const put = await perform("profile.put", { id: "p", input: {} });
  assert.deepEqual(put, edited, JSON.stringify(host.requests.slice(-3).map((r) => [r.method, r.url])));
  assert.deepEqual(core.inner.data.get({ topic: "overview", station: ST }), edited);
  assert.equal(gets(host, "/admin/api/overview"), o);
  await perform("profile.check", { id: "p" });
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), o + 1);
  // Put on another update channel: its versions (the overview's) read again.
  await perform("software.channel", { channel: "beta" });
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), o + 2);
  // Another chat on a session answers its thread, which goes into the records without a request.
  const reads = host.requests.length;
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/threads") ? { ...threadView(9, 0), sessions: [{ thread: 9, session: "k 1" }] } : undefined));
  await perform("chat.forSession", { session: "k 1" });
  await host.settle();
  assert.equal((core.inner.data.get({ topic: "session", station: ST, key: "k 1" }) as J).threads[0].id, 9);
  assert.equal((core.inner.data.get({ topic: "threads", station: ST }) as J)[0].id, 9);
  // The threads and sessions are not read again for it. (The TS core reads the chat rows, which the station makes, so
  // the new chat is in the list as the station has it; and the sync brings the new chat's entries onto the device.)
  assert.deepEqual(
    host.requests.slice(reads).map((r) => `${r.method} ${r.url.replace("https://stillfail.test/admin/api", "")}`).filter((r) => !r.includes("/threads/9/entries") && r !== "GET /chats" && r !== "POST /changed/chats"),
    ["POST /threads"],
  );
  // A read changes nothing.
  await run(core.inner.stations.requests.call(remote(), "GET", "/slack/config-token", null));
  assert.equal(gets(host, "/admin/api/overview"), o + 2);
  // The workspace's app configuration token: every Slack connect's app is read again, as it now reads.
  let app = "no_config_token";
  stationReplies(host, (req) => (req.url.endsWith("/connects/ds/slack-app") ? { state: app } : req.url.endsWith("/overview") ? { ...edited, connects: [{ id: "ds", kind: "slack" }] } : undefined));
  core.inner.data.set({ topic: "overview", station: ST }, { ...edited, connects: [{ id: "ds", kind: "slack" }] });
  app = "ok";
  await perform("slack.addConfigToken", { refreshToken: "x" });
  assert.equal((core.inner.data.get({ topic: "slackApp", station: ST, connect: "ds" }) as J).state, "ok");
  core.close();
});

test("operation_effects_do_not_depend_on_the_wire_path", async () => {
  const { host, core } = await started({ ...base(), "POST /different-endpoint": {}, "POST /slack/verify": {}, "GET /jobs/j": { connects: [], profiles: [] } });
  await host.settle();
  const before = gets(host, "/admin/api/overview");
  const check = op("profile.check", { id: "p" });
  await run(core.inner.stations.perform({ ...check, path: "/different-endpoint" }, null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), before + 1);
  await run(core.inner.stations.perform(op("slack.verify", { appToken: "app", botToken: "bot" }), null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), before + 1, "checking tokens is not a settings change");
  // A response that happens to resemble an overview does not give a read write effects.
  await run(core.inner.stations.perform(op("job.get", { id: "j" }), null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), before + 1);
  core.close();
});

test("archive_fallback_updates_the_session_only_after_success", async () => {
  const answers: J = { ...base(), "GET /sessions/k": { session: summary("k", 0), threads: [], turns: [] }, "GET /sessions": [summary("k", 0)] };
  const { host, core } = await started(answers);
  await host.settle();
  const archive = op("chat.archive", { thread: 7, session: "k", archived: true });
  const before = gets(host, "/admin/api/sessions/k");
  const posts = (path: string) => host.requests.filter((r) => r.method === "POST" && r.url.endsWith(path)).length;
  answers["POST /threads/7/archive"] = status(403, { error: "denied" });
  assert.equal((await failure(core.inner.stations.perform(archive, null))).status, 403);
  assert.equal(posts("/admin/api/sessions/k/archive"), 0);
  assert.equal(gets(host, "/admin/api/sessions/k"), before);
  answers["POST /threads/7/archive"] = status(404, {});
  answers["POST /sessions/k/archive"] = status(500, {});
  await failure(core.inner.stations.perform(archive, null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions/k"), before);
  answers["POST /sessions/k/archive"] = {};
  await run(core.inner.stations.perform(archive, null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions/k"), before + 1);
  assert.equal(posts("/admin/api/sessions/k/archive"), 2);
  core.close();
});

/// A log as the station said it (the topic goes out with its last line and when, in words, besides).
const raw = (log: J) => ({ text: log.text, outputAt: log.outputAt });
const sessionOf = (core: J, key: string) => core.inner.data.get({ topic: "session", station: ST, key }) as J;
const reqs = (host: FakeHost) => host.requests.filter((r) => r.url.includes("/admin/api/")).length;

test("jobs_are_put_in_place_from_their_events_and_from_stopping_them", async () => {
  const job = (id: string, state: string) => ({ id, session: "a", name: id, state, port: 4817, startedAt: 1 });
  const answers: J = {
    ...base(),
    "GET /sessions": [summary("a", 0)],
    "GET /sessions/a": { session: summary("a", 0), threads: [], turns: [], jobs: [job("j1", "running")] },
    "GET /jobs": [{ ...job("j1", "running"), chat: { id: "7", title: "t", archived: false } }],
    "POST /jobs/j1/stop": job("j1", "stopped"),
  };
  const { host, core, push } = await started(answers);
  await host.settle();
  const open = () => core.inner.data.get({ topic: "jobs", station: ST }) as J[];
  const reads = reqs(host);
  // Stopped from a page: the answer is the job as it is now, in its chat and gone from the open ones, with nothing
  // read again.
  await run(core.inner.stations.perform(op("job.stop", { id: "j1" }), null));
  await host.settle();
  assert.equal(sessionOf(core, "a").jobs[0].state, "stopped");
  assert.deepEqual(open(), []);
  assert.equal(reqs(host), reads + 1);
  // Started again elsewhere (an agent, another device): its event puts it back; which chat it is in, the list read
  // again says.
  push("job", job("j1", "running"));
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  assert.equal(sessionOf(core, "a").jobs[0].state, "running");
  assert.equal(open()[0].chat.id, "7");
  assert.equal(gets(host, "/admin/api/jobs"), 2);
  // A new one goes in front of its session's; one listed keeps its chat as it changes.
  push("job", job("j2", "failed"));
  push("job", { ...job("j1", "exited"), restarts: 1 });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  const jobs = sessionOf(core, "a").jobs;
  assert.deepEqual([jobs[0].id, jobs[1].state], ["j2", "exited"]);
  assert.equal(open()[0].restarts, 1);
  assert.equal(open()[0].chat.id, "7");
  assert.equal(gets(host, "/admin/api/jobs"), 2);
  // One that was over, cleared (here or on another device): out of its chat's.
  push("job-removed", { id: "j2", session: "a" });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  assert.deepEqual(sessionOf(core, "a").jobs.map((j: J) => j.id), ["j1"]);
  core.close();
});

test("a_jobs_log_is_read_once_and_then_kept_current_by_the_stations_events", async () => {
  const { host, core, push, streams } = await started({
    ...base(),
    "GET /jobs/j1/log?lines=400": { text: "a\nb", outputAt: 5, follows: true },
    "GET /jobs/j1/log?lines=1": { text: "b", outputAt: 5, follows: true },
  });
  const ui = core.connect();
  const values = new Map();
  const log = (lines: number) => ({ topic: "jobLog", station: ST, job: "j1", lines });
  const openStreams = () => streams.filter((s) => !s.closed).map((s) => s.path);
  subscribe(core, ui, 1, log(400));
  await host.settle();
  await host.settle();
  apply(host, values);
  assert.deepEqual(raw(v(values, 1)), { text: "a\nb", outputAt: 5 });
  assert.deepEqual(openStreams(), ["/events?running=1&job=j1&lines=400"]);
  // As it grows the station says so, each topic its own lines; nothing is read again, and nothing waits to.
  subscribe(core, ui, 2, log(1));
  await host.settle();
  await host.settle();
  assert.deepEqual(openStreams(), ["/events?running=1&job=j1&lines=1&job=j1&lines=400"]);
  host.time.sleeps.length = 0;
  push("job-log", { id: "j1", lines: 400, text: "a\nb\nc", outputAt: 9 });
  push("job-log", { id: "j1", lines: 1, text: "c", outputAt: 9 });
  await host.settle();
  apply(host, values);
  assert.deepEqual(raw(v(values, 1)), { text: "a\nb\nc", outputAt: 9 });
  assert.deepEqual(raw(v(values, 2)), { text: "c", outputAt: 9 });
  await host.time.pass(5_000, 100);
  assert.deepEqual([gets(host, "/admin/api/jobs/j1/log?lines=400"), gets(host, "/admin/api/jobs/j1/log?lines=1")], [1, 1]);
  // Given up: the stream no longer asks for it (once its grace is over).
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  assert.deepEqual(openStreams(), ["/events?running=1&job=j1&lines=1"]);
  core.close();
});

test("a_jobs_log_on_a_station_that_does_not_follow_it_is_read_again_less_often_while_it_stays_the_same", async () => {
  // Deliberately otherwise (docs/core-ts.md, rule 2): the Rust core read an older station's log again and again,
  // backing off; the TS core reads it once as it opens and never again.
  const answers: J = { ...base(), "GET /jobs/j1/log?lines=1": { text: "a", outputAt: 5 } };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "jobLog", station: ST, job: "j1", lines: 1 });
  await host.settle();
  await host.settle();
  apply(host, values);
  assert.deepEqual(raw(v(values, 1)), { text: "a", outputAt: 5 });
  answers["GET /jobs/j1/log?lines=1"] = { text: "b", outputAt: 6 };
  await host.time.pass(60_000, 1_000);
  assert.equal(gets(host, "/admin/api/jobs/j1/log?lines=1"), 1);
  core.close();
});

test("requests_carry_the_trace_they_are_made_in", async () => {
  // Adapted: a topic asks nothing (rule 6), so what carries a trace is the station's reading (one trace from its
  // connecting) and a request made inside a call (its call's trace); one outside every trace has its own.
  const { host, core } = await started(base(), 1);
  const parents = host.requests.filter((r) => r.url.includes("/admin/api/")).map((r) => [r.url, r.headers.find(([k]) => k === "traceparent")?.[1] ?? ""]);
  const trace = parents[0][1].slice(3, 35);
  for (const [url, parent] of parents) {
    assert.ok(parent.startsWith("00-") && parent.endsWith("-01") && parent.length === 55, `${url}: ${parent}`);
  }
  const snapshot = ["/events?running=1", "/overview", "/sessions", "/threads", "/chats", "/jobs"].map((p) => parents.find(([u]) => u === `https://stillfail.test/admin/api${p}`)![1]);
  assert.ok(snapshot.every((p) => p.slice(3, 35) === trace), JSON.stringify(snapshot));
  // Each request is a span of its own.
  assert.equal(new Set(snapshot.map((p) => p.slice(36, 52))).size, snapshot.length);
  // Outside every trace: a trace of its own.
  await run(core.inner.stations.requests.call(remote(), "GET", "/overview", null));
  const last = host.requests.at(-1)!.headers.find(([k]) => k === "traceparent")![1];
  assert.notEqual(last.slice(3, 35), trace);
  core.close();
});

test("topics_are_read_once_and_nothing_runs_on_a_timer", async () => {
  const { host, core, streams } = await started();
  const ui = core.connect();
  const topics = [
    { topic: "session", station: ST, key: "k1" }, { topic: "sessions", station: ST }, { topic: "overview", station: ST }, { topic: "threads", station: ST },
    { topic: "thread", station: ST, thread: 7 }, { topic: "host", station: ST }, { topic: "link", station: ST }, { topic: "live", station: ST, key: "k1" },
  ];
  const reads = () => host.requests.filter((r) => r.url.includes("/admin/api/") && !r.url.includes("/events")).length;
  const before = reads();
  topics.forEach((t, i) => subscribe(core, ui, i + 1, t));
  await host.settle();
  await host.settle();
  assert.deepEqual(streams.filter((s) => !s.closed).map((s) => s.path), ["/events?running=1&host=1&live=k1&from=0&last=200&brief=1"]);
  // Subscribing reads nothing: what is held shows (the stream opened anew for the host and the live session).
  assert.equal(reads(), before, JSON.stringify(host.requests.filter((r) => r.url.includes("/admin/api/") && !r.url.includes("/events")).slice(before).map((r) => r.url)));
  const requests = reqs(host);
  host.time.sleeps.length = 0;
  await host.time.pass(RECONNECT_MS * 2, 100);
  assert.equal(reqs(host), requests, "idle: no request");
  core.close();
});

// ── threads: their entries are records on the device, a chat's window is read from them ──

const edit = (n: number, target: number, text: string) => ({ thread: 7, n, kind: "edit", target, ts: null, authorKind: "person", author: "a@x.com", text, at: n });
const coalesce = (host: FakeHost) => host.time.pass(EVENTS_COALESCE_MS + 100, 50);

/// A core whose station has `answers`, and a UI on it with its values.
async function ui(answers: J, before?: Parameters<typeof started>[3]) {
  const s = await started(answers, 0, undefined, before);
  const id = s.core.connect();
  const values = new Map<number, unknown>();
  const read = async () => {
    await s.host.settle();
    apply(s.host, values);
  };
  return { ...s, ui: id, values, read };
}

const page = (values: Map<number, unknown>, id = 1) => v(values, id);
const nums = (values: Map<number, unknown>, id = 1) => page(values, id).entries.map((e: J) => e.n);
const texts = (values: Map<number, unknown>, id = 1) => merge(page(values, id).entries).map((m: J) => m.text);
const windowOf = (values: Map<number, unknown>, id = 1) => [page(values, id).first, page(values, id).last, page(values, id).end];
const thread7 = { topic: "thread", station: ST, thread: 7 };
const threadsOf = (core: J) => core.inner.data.get({ topic: "threads", station: ST }) as J[];

test("thread_events_append_entries_and_refresh_summaries", async () => {
  const answers: J = {
    ...base(),
    "GET /threads/7/entries?limit=50": { last: 12, entries: [entry(11, "a"), entry(12, "b")] },
    "GET /threads": [threadView(7, 12, 12, 0)],
    "GET /threads/7": threadView(7, 15, 12, 2),
    "GET /threads/8": threadView(8, 20, 0, 1),
  };
  const { host, core, push, values, read } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  assert.deepEqual(texts(values), ["a", "b"]);
  // New entries (an edit among them), in one burst: appended at once, one known already skipped; the summary is
  // read once after it.
  push("thread", { id: 7, entries: [entry(13, "c")] });
  push("thread", { id: 7, entries: [entry(13, "c"), entry(14, "d"), edit(15, 12, "b 改了")] });
  await read();
  assert.deepEqual(nums(values), [11, 12, 13, 14, 15]);
  assert.deepEqual(texts(values), ["a", "b 改了", "c", "d"]);
  assert.equal(page(values).last, 15);
  assert.equal(gets(host, "/admin/api/threads/7"), 0, "waits for the burst to end");
  await coalesce(host);
  assert.equal(gets(host, "/admin/api/threads/7"), 1);
  assert.equal(threadsOf(core)[0].unread, 2);
  // A thread not listed yet comes in, first (its last message is the newest).
  push("thread", { id: 8, entries: [{ ...entry(20, "x"), thread: 8 }] });
  await coalesce(host);
  assert.deepEqual(threadsOf(core).map((t) => t.id), [8, 7]);
  // Reading up to the last entry: nothing unread, without a request. Short of it: counted again.
  push("read", { viewer: "a@x.com", thread: 7, n: 15 });
  await host.settle();
  assert.deepEqual([threadsOf(core)[1].unread, threadsOf(core)[1].read], [0, 15]);
  push("read", { viewer: "a@x.com", thread: 8, n: 15 });
  await coalesce(host);
  assert.equal(gets(host, "/admin/api/threads/8"), 2);
  // A thread gone: out of the list.
  answers["GET /threads/8"] = status(404, { error: "unknown thread 8" });
  push("thread", { id: 8, entries: [] });
  await coalesce(host);
  assert.equal(threadsOf(core).length, 1);
  core.close();
});

test("a_thread_its_station_tells_the_summary_of_is_not_read_again", async () => {
  const { host, core, push, read } = await ui({ ...base(), "GET /threads": [threadView(7, 3)], "GET /threads/7/entries?limit=50": { last: 3, entries: entries(1, 3) } });
  await read();
  const summaries = () => gets(host, "/admin/api/threads/7");
  // Told after what was said, before or after it: put in place, not read.
  push("thread", { id: 7, entries: [entry(4, "m4")] });
  push("thread-view", { ...threadView(7, 4, 3, 1) });
  push("thread-view", { ...threadView(7, 5, 3, 2) });
  push("thread", { id: 7, entries: [entry(5, "m5")] });
  await host.time.pass(EVENTS_COALESCE_MS + 100, 50);
  assert.equal(summaries(), 0);
  const t = threadsOf(core).find((x: J) => x.id === 7);
  assert.deepEqual([t.last, t.unread], [5, 2]);
  // A station from before tells none: read as before.
  push("thread", { id: 7, entries: [entry(6, "m6")] });
  await host.time.pass(EVENTS_COALESCE_MS + 100, 50);
  assert.equal(summaries(), 1);
  core.close();
});

test("a_gap_is_read_once_and_what_came_meanwhile_waits_for_it", async () => {
  const { host, core, push, values, read } = await ui({
    ...base(),
    "GET /threads": [threadView(7, 3)],
    "GET /threads/7/entries?limit=50": { last: 3, entries: entries(1, 3) },
    "GET /threads/7/entries?from=4&to=5": { last: 7, entries: entries(4, 5) },
  });
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  // Entries 4 and 5 never came: 6 shows the gap, and 7 comes while it is read.
  push("thread", { id: 7, entries: [entry(6, "m6")] });
  push("thread", { id: 7, entries: [entry(7, "m7")] });
  await read();
  await read();
  assert.deepEqual(nums(values), [1, 2, 3, 4, 5, 6, 7]);
  assert.equal(gets(host, "/admin/api/threads/7/entries?from=4&to=5"), 1);
  assert.equal(entryReads(host).length, 2, JSON.stringify(entryReads(host)));
  core.close();
});

test("a_thread_its_summary_says_goes_further_than_what_is_held_is_read_whoever_said_so", async () => {
  const answers: J = { ...base(), "GET /threads/7/entries?after=3": { last: 5, entries: entries(4, 5) } };
  const { host, core, push, values, read } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  const from = host.requests.length;
  // Its summary alone says it goes to 5 (the entries were never told): read once the burst is over, not before.
  push("thread-view", { ...threadView(7, 5, 3, 2) });
  await host.settle();
  assert.deepEqual(entryReads(host, from), [], "waits for the burst to end: the entries are mostly on their way");
  await coalesce(host);
  await read();
  assert.deepEqual(entryReads(host, from), ["/threads/7/entries?after=3"]);
  assert.deepEqual(nums(values), [1, 2, 3, 4, 5]);
  // Said with its entries, in either order: they are held by the time the burst is over, and nothing is read.
  push("thread-view", { ...threadView(7, 6, 3, 3) });
  push("thread", { id: 7, entries: [entry(6, "m6")] });
  push("thread", { id: 7, entries: [entry(7, "m7")] });
  push("thread-view", { ...threadView(7, 7, 3, 4) });
  await coalesce(host);
  await read();
  assert.deepEqual(entryReads(host, from), ["/threads/7/entries?after=3"]);
  assert.deepEqual(nums(values), [1, 2, 3, 4, 5, 6, 7]);
  // A read of its summary (after something was read, say) says so as well.
  answers["GET /threads/7"] = threadView(7, 9, 7, 2);
  answers["GET /threads/7/entries?after=7"] = { last: 9, entries: entries(8, 9) };
  push("read", { viewer: "a@x.com", thread: 7, n: 4 });
  await coalesce(host);
  await coalesce(host);
  await read();
  assert.deepEqual(entryReads(host, from), ["/threads/7/entries?after=3", "/threads/7/entries?after=7"]);
  assert.deepEqual(nums(values), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  core.close();
});

test("a_thread_not_open_its_summary_says_goes_further_is_read_too_and_one_none_of_which_is_held_waits_to_be_brought", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 3), threadView(8, 2)],
    "GET /threads/8/entries?limit=50": { last: 2, entries: [{ ...entry(1, "x1"), thread: 8 }, { ...entry(2, "x2"), thread: 8 }] },
    "GET /threads/8/entries?after=2": { last: 3, entries: [{ ...entry(3, "x3"), thread: 8 }] },
  };
  const { host, core, push } = await started(answers);
  await host.settle();
  const held = (id: number) => core.inner.data.logNumbers("entry", ST, String(id));
  assert.deepEqual(held(8), [1, 2]);
  const from = host.requests.length;
  push("thread-view", { ...threadView(8, 3, 2, 1) });
  // One the device holds nothing of (it is new): brought with the station's history, not by this.
  push("thread-view", { ...threadView(9, 4, 0, 4) });
  await coalesce(host);
  await host.settle();
  assert.deepEqual(entryReads(host, from), ["/threads/8/entries?after=2"]);
  assert.deepEqual(held(8), [1, 2, 3]);
  core.close();
});

test("a_thread_keeps_a_page_ahead_so_going_back_does_not_wait", async () => {
  // Further than the Rust core (which kept one page ahead): the whole thread is brought onto the device, so going
  // back asks the station nothing.
  const { host, core, values, read } = await ui({
    ...base(),
    "GET /threads": [threadView(7, 300)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
    "GET /threads/7/entries?from=201&to=250": { last: 300, entries: entries(201, 250) },
    "GET /threads/7/entries?from=151&to=200": { last: 300, entries: entries(151, 200) },
    "GET /threads/7/entries?from=101&to=150": { last: 300, entries: entries(101, 150) },
    "GET /threads/7/entries?from=51&to=100": { last: 300, entries: entries(51, 100) },
    "GET /threads/7/entries?from=1&to=50": { last: 300, entries: entries(1, 50) },
  });
  await host.time.pass(1_000, 50);
  assert.equal(gets(host, "/admin/api/threads/7/entries?from=201&to=250"), 1, "the page before, brought in ahead");
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  const asked = host.requests.length;
  assert.equal(await run(core.inner.stationTopics.older(ST, 7)), true);
  await read();
  assert.equal(page(values).first, 201);
  assert.equal(host.requests.length, asked, "going back asks nothing");
  core.close();
});

/// The core closed (its writes done) and another started over the same device and station.
async function reopen(s: { host: FakeHost; core: J }) {
  await run(s.core.inner.data.written);
  s.core.close();
  s.host.takeEmitted();
  const { Core } = await import("../src/core.ts");
  const { HostWire } = await import("../src/station/wire.ts");
  const core = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
  await s.host.time.pass(500);
  const id = core.connect();
  const values = new Map<number, unknown>();
  const read = async () => {
    await s.host.settle();
    apply(s.host, values);
  };
  return { core, ui: id, values, read };
}
const entryReads = (host: FakeHost, from = 0) => host.requests.slice(from).flatMap(readsOf).filter((url) => url.includes("/entries")).map((url) => url.replace("https://stillfail.test/admin/api", ""));
const topicOf = (core: J, topic: J) => core.inner.stationTopics.compute(topic);

test("session_events_update_in_place", async () => {
  const turn = { id: "t1", kind: "chat", outcome: null, declared: null, detail: null, startedAt: 1, endedAt: null };
  const { host, core, push } = await started({
    ...base(),
    "GET /sessions": [summary("a", 1), summary("b", 0)],
    "GET /sessions/a": { session: summary("a", 1), threads: [], turns: [turn] },
    "GET /sessions/b": { session: summary("b", 0), threads: [], turns: [] },
    "GET /sessions/c": { session: summary("c", 0), threads: [], turns: [] },
  });
  await host.settle();
  const reads = reqs(host);
  // The same turns: only the summary changes, without a request. (A session new to the device has its detail brought
  // in, rule 6.)
  const renamed = { ...summary("a", 1), title: "新名字", lastTurn: { kind: "chat", outcome: null, declared: null, detail: null, startedAt: 1, endedAt: null } };
  push("session", renamed);
  push("session", summary("c", 0));
  await host.settle();
  assert.equal(reqs(host), reads + 1);
  assert.equal(gets(host, "/admin/api/sessions/c"), 1);
  const list = () => core.inner.data.get({ topic: "sessions", station: ST }) as J[];
  assert.deepEqual(list().map((s) => s.key), ["c", "a", "b"]);
  assert.equal(list()[1].title, "新名字");
  assert.equal(sessionOf(core, "a").session.title, "新名字");
  // The turn ended, said by a station from before (its last turn named by no id): the detail's turns are read again.
  push("session", { ...renamed, lastTurn: { ...renamed.lastTurn, endedAt: 2 } });
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions/a"), 2);
  // Said with its id: the turn put in place, then one more, as they go on; nothing read.
  push("session", { ...renamed, lastTurn: { ...turn, endedAt: 3 } });
  push("session", { ...renamed, turns: 2, lastTurn: { ...turn, id: "t2", startedAt: 4 } });
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions/a"), 2);
  assert.deepEqual(sessionOf(core, "a").turns.map((t: J) => [t.id, t.endedAt]), [["t1", 3], ["t2", null]]);
  // Turns it did not hear of (two at once): read again.
  push("session", { ...renamed, turns: 4, lastTurn: { ...turn, id: "t4", startedAt: 9 } });
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions/a"), 3);
  // Archived: gone from the list. Removed: gone, and its topic says so.
  push("session", { ...summary("b", 0), archivedAt: 5 });
  push("session-removed", { key: "a" });
  await host.settle();
  assert.deepEqual(list().map((s) => s.key), ["c"]);
  assert.equal(topicOf(core, { topic: "session", station: ST, key: "a" }).err.status, 404);
  core.close();
});

test("overview_and_host_come_from_events", async () => {
  const { host, core, push, streams } = await started();
  const ui = core.connect();
  const values = new Map();
  const open = () => streams.filter((s) => !s.closed).map((s) => s.path);
  assert.deepEqual(open(), ["/events?running=1"]);
  push("overview", { connects: [1] });
  await host.settle();
  assert.deepEqual(core.inner.data.get({ topic: "overview", station: ST }), { connects: [1] });
  // Host samples are asked for while a host topic is live: the stream opens anew with ?host=1, and the old one goes
  // once it has.
  subscribe(core, ui, 1, { topic: "host", station: ST });
  await host.settle();
  await host.settle();
  assert.deepEqual(open(), ["/events?running=1&host=1"]);
  const sample = { hostname: "studio", os: "macOS 26", arch: "arm64", cpus: 8, cpuModel: "M4", load: 0.2, uptimeSec: 100, memory: { totalBytes: 1024, usedBytes: 512, swapUsedBytes: null }, disk: { path: "/", totalBytes: 1024, freeBytes: 512 }, emberRssBytes: 10, checkedAt: 1 };
  push("host", sample);
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).hostname, "studio");
  assert.equal(gets(host, "/admin/api/overview"), 1, "a handover is no reconnect: nothing is read again");
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  assert.deepEqual(open(), ["/events?running=1"]);
  assert.equal(gets(host, "/admin/api/host"), 0);
  core.close();
});

test("the_stations_list_goes_out_again_as_the_way_to_a_station_changes_not_with_each_reading_of_its_connection", async () => {
  // One sampler for a station's `net` and `way`: a reading whose round trip and bytes moved puts out its card's figures
  // (`stationNet`) alone; the list, which says only how it is reached, goes out again once that changes.
  let reading: LinkNet = { path: "direct", relay: null, rttMs: 12, measured: null, today: null, rxBytes: 1000, txBytes: 100, packets: null };
  let readings = 0;
  const net = () => ((readings += 1), reading);
  const { host, core } = await started(base(), 0, (h) => Object.assign(new HostWire(h), { net }));
  const ui = core.connect();
  const values = new Map<number, J>();
  const said = new Map<number, number>();
  const read = async () => {
    await host.time.pass(NET_EVERY_MS, 100);
    for (const [, m] of host.takeEmitted()) {
      const id = (m as { id: number }).id;
      if ("value" in m) values.set(id, m.value);
      else if ("delta" in m) values.set(id, applyOps(values.get(id), m.delta as Op[]));
      else continue;
      said.set(id, (said.get(id) ?? 0) + 1);
    }
  };
  const station = () => (values.get(1) as J[]).find((s) => s.station === ST);
  subscribe(core, ui, 1, { topic: "stations", scope: "ws" });
  subscribe(core, ui, 2, { topic: "stationNet", station: ST });
  await read();
  await read();
  assert.deepEqual(station().way, { path: "直连", via: "direct" });
  assert.equal(values.get(2).rtt.text, "12 ms");
  const [list, card] = [said.get(1), said.get(2)];
  reading = { ...reading, rttMs: 340, rxBytes: 9000, txBytes: 700 };
  await read();
  await read();
  assert.deepEqual(values.get(2).rtt, { text: "340 ms", level: "amber" });
  assert.ok(said.get(2)! > card!, "the card's figures go out");
  assert.equal(said.get(1), list, "the list does not");
  reading = { ...reading, path: "relay", relay: "relay.test" };
  await read();
  await read();
  assert.deepEqual(station().way, { path: "中继 relay.test", via: "relay" });
  assert.equal(values.get(2).path, "中继 relay.test");
  assert.equal(said.get(1), list! + 1);
  // Its figures no longer shown: the list's way is still sampled; with the list gone too, nothing is.
  core.receive(ui, { kind: "unsubscribe", id: 2, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  reading = { ...reading, path: "direct", relay: null };
  await read();
  await read();
  assert.deepEqual(station().way, { path: "直连", via: "direct" });
  // The list goes after its grace, and the topics it watched after theirs.
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(2 * EVICT_AFTER_MS + 500, 500);
  const before = readings;
  await read();
  assert.equal(readings, before);
  core.close();
});

test("a_stream_taking_over_asks_for_what_came_after_the_last_event_its_predecessor_gave", async () => {
  const { host, core, streams } = await started();
  const ui = core.connect();
  const open = () => streams.filter((s) => !s.closed).map((s) => s.path);
  assert.deepEqual(open(), ["/events?running=1"]);
  // Events with ids (a station of this run, numbered); one from before ids had a run says nothing.
  const said = (id: string, name: string, data: unknown) =>
    Queue.offerUnsafe(streams.at(-1)!.queue, new TextEncoder().encode(`id: ${id}\nevent: ${name}\ndata: ${JSON.stringify(data)}\n\n`));
  said("1f2e3d4c.6", "overview", { connects: [] });
  said("1f2e3d4c.9", "overview", { connects: [1] });
  said("12", "overview", { connects: [2] });
  await host.settle();
  // Something more is wanted of it: the stream taking over asks for what came after 9 (the one it replaces may be let
  // go before it gives what was said as this one was asked for).
  subscribe(core, ui, 1, { topic: "host", station: ST });
  await host.settle();
  await host.settle();
  assert.deepEqual(open(), [`/events?running=1&host=1&since=${encodeURIComponent("1f2e3d4c.9")}`]);
  assert.equal(gets(host, "/admin/api/overview"), 1, "a handover reads nothing again");
  core.close();
});

test("a_stream_coming_back_after_its_link_went_is_told_what_it_missed_and_reads_nothing_again", async () => {
  const { host, core, push, streams, end, gate } = await started();
  const reads = () => ["/admin/api/overview", "/admin/api/sessions", "/admin/api/threads", "/admin/api/chats"].map((p) => gets(host, p));
  const said = (id: string, name: string, data: unknown) =>
    Queue.offerUnsafe(streams.at(-1)!.queue, new TextEncoder().encode(`id: ${id}\nevent: ${name}\ndata: ${JSON.stringify(data)}\n\n`));
  said("1f2e3d4c.9", "overview", { connects: [1] });
  await host.settle();
  const first = reads();
  assert.deepEqual(first, [1, 1, 1, 1], "the first stream reads the station");
  // The stream goes (its link moved to another way, or lost its way): the next asks for what came after the last event
  // heard, and is told it first.
  gate.resumes = true;
  end();
  await host.time.pass(RECONNECT_MS + 50, 50);
  assert.equal(streams.at(-1)!.path, `/events?running=1&since=${encodeURIComponent("1f2e3d4c.9")}`);
  said("1f2e3d4c.10", "overview", { connects: [2] });
  await host.settle();
  assert.deepEqual(reads(), first, "told what it missed: nothing read again");
  assert.deepEqual(core.inner.data.get({ topic: "overview", station: ST }), { connects: [2] });
  // One that could not be told all it missed (too long ago, or the station started anew): read again, once, though
  // it says `missed` too.
  gate.resumes = false;
  end();
  // The second in a row that ended at once: it waits twice as long.
  await host.time.pass(2 * RECONNECT_MS + 50, 50);
  assert.equal(streams.at(-1)!.path, `/events?running=1&since=${encodeURIComponent("1f2e3d4c.10")}`);
  push("missed", {});
  await host.settle();
  assert.deepEqual(reads(), first.map((n) => n + 1));
  core.close();
});

test("a_chat_open_is_asked_what_was_said_since_before_the_station_is_read_again", async () => {
  const answers: J = { ...base(), "GET /threads/7/entries?after=3": { last: 3, entries: [] } };
  const { host, core, end, values, read } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  assert.deepEqual(nums(values), [1, 2, 3]);
  // The stream goes and comes back without being told what it missed (its station started anew, say): what the agent
  // said meanwhile shows without waiting on the lists and the history read behind them.
  answers["GET /threads/7/entries?after=3"] = { last: 5, entries: entries(4, 5) };
  answers["GET /threads"] = [threadView(7, 5)];
  const from = host.requests.length;
  end();
  await host.time.pass(RECONNECT_MS + 50, 50);
  await read();
  assert.deepEqual(nums(values), [1, 2, 3, 4, 5]);
  const asked = host.requests.slice(from).map((r) => r.url.replace("https://stillfail.test/admin/api", ""));
  const at = asked.indexOf("/threads/7/entries?after=3");
  assert.ok(at >= 0, "asked what was said since");
  for (const list of ["/changed/threads", "/changed/chats", "/changed/sessions", "/batch"]) assert.ok(asked.indexOf(list) < 0 || at < asked.indexOf(list), `before ${list}`);
  core.close();
});

test("a_chat_open_is_asked_what_was_said_since_though_its_stream_came_back_told_what_it_missed", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 3), threadView(8, 2)],
    "GET /threads/8/entries?limit=50": { last: 2, entries: [{ ...entry(1, "x1"), thread: 8 }, { ...entry(2, "x2"), thread: 8 }] },
  };
  const { host, core, push, streams, end, gate, values, read } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  const said = (id: string, name: string, data: unknown) =>
    Queue.offerUnsafe(streams.at(-1)!.queue, new TextEncoder().encode(`id: ${id}\nevent: ${name}\ndata: ${JSON.stringify(data)}\n\n`));
  said("1f2e3d4c.9", "overview", { connects: [1] });
  await host.settle();
  // The stream goes and comes back saying it told all that was missed, though it did not tell what was said in the
  // chat (what the device hears of a station's events is not what says how far a chat goes): the chat shown is asked,
  // and nothing else is read, a chat not shown neither.
  answers["GET /threads/7/entries?after=3"] = { last: 5, entries: entries(4, 5) };
  gate.resumes = true;
  const from = host.requests.length;
  end();
  await host.time.pass(RECONNECT_MS + 50, 50);
  await read();
  assert.equal(streams.at(-1)!.path, `/events?running=1&since=${encodeURIComponent("1f2e3d4c.9")}`);
  assert.deepEqual(nums(values), [1, 2, 3, 4, 5]);
  // Its screens are the exception: held in memory only and changing as people come and go, they are asked again
  // whenever the stream was away (a small list; screens.ts).
  const asked = host.requests.slice(from).flatMap(readsOf).filter((url) => url.includes("/admin/api/") && !url.includes("/events") && !url.endsWith("/screens")).map((url) => url.replace("https://stillfail.test/admin/api", ""));
  assert.deepEqual(asked, ["/threads/7/entries?after=3"]);
  // A stream that takes over from one still heard (an agent started: the stream follows it) was not away: nothing asked.
  const again = host.requests.length;
  push("chat", { id: "7", thread: 7, session: "k1", title: "部署", lastActiveAt: 1, agents: [{ key: "k1", process: "running" }] });
  await host.settle();
  await host.settle();
  assert.ok(streams.at(-1)!.path.includes("live=k1"), streams.at(-1)!.path);
  assert.deepEqual(entryReads(host, again), []);
  core.close();
});

test("a_stream_taking_over_told_it_missed_what_came_since_reads_the_station_again", async () => {
  const { host, core, push, streams } = await started();
  const ui = core.connect();
  const reads = () => ["/admin/api/overview", "/admin/api/sessions", "/admin/api/threads", "/admin/api/chats"].map((p) => gets(host, p));
  Queue.offerUnsafe(streams.at(-1)!.queue, new TextEncoder().encode(`id: 1f2e3d4c.9\nevent: overview\ndata: {}\n\n`));
  await host.settle();
  const before = reads();
  // Taking over from a stream still open: nothing read again, unless the station could not tell all it missed.
  subscribe(core, ui, 1, { topic: "host", station: ST });
  await host.settle();
  await host.settle();
  assert.deepEqual(reads(), before);
  push("missed", {});
  await host.settle();
  assert.deepEqual(reads(), before.map((n) => n + 1));
  core.close();
});

test("answers_come_compressed_as_asked_and_are_read_as_they_were", async () => {
  const many = Array.from({ length: 300 }, (_, i) => threadView(i + 1, 3));
  const answers = { ...base(), "GET /threads": many };
  const { host, core, push } = await started(answers);
  const asked = host.requests.find((r) => r.url.endsWith("/admin/api/threads"))!;
  assert.ok(asked.headers.some(([k, v]) => k === "accept-encoding" && v === "zstd"));
  assert.equal((core.inner.data.get({ topic: "threads", station: ST }) as J[]).length, 300);
  // The stream too, event by event.
  push("overview", { connects: ["compressed"] });
  await host.settle();
  assert.deepEqual(core.inner.data.get({ topic: "overview", station: ST }), { connects: ["compressed"] });
  core.close();
});

test("what_a_person_waits_on_is_not_held_up_by_reads_that_take_long", async () => {
  const { host, core } = await started({ ...base(), "GET /threads/9/entries?limit=50": { last: 1, entries: [entry(1, "m1")] } });
  const sync = core.inner.stations;
  // A slow link: the station read again, its first two reads taking all the time there is (the sessions, held here,
  // asked as what changed of them).
  const release = [host.hold("/admin/api/overview"), host.hold("/admin/api/changed/sessions")];
  sync.snapshot(ST);
  await host.settle();
  const ran: string[] = [];
  const task = (name: string) => Effect.sync(() => void ran.push(name));
  core.inner.scheduler.enqueue(ST, `${ST} shown`, Priority.shown, task("shown"));
  const asked = run(sync.ask(ST, "asked", task("asked")));
  core.inner.scheduler.enqueue(ST, `${ST} focused`, Priority.focused, task("focused"));
  await host.settle();
  // What a person waits on and the chat open run at once; the rest waits its turn.
  assert.deepEqual(ran.sort(), ["asked", "focused"]);
  await asked;
  // A chat opened as they hang: its messages read at once.
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "thread", station: ST, thread: 9 });
  await host.settle();
  assert.equal(gets(host, "/admin/api/threads/9/entries?limit=50"), 1);
  release.forEach((r) => r());
  await host.settle();
  assert.ok(ran.includes("shown"));
  core.close();
});

test("what_the_agents_spent_is_read_only_while_a_page_shows_it", async () => {
  const { host, core, push, streams, gate } = await started();
  stationReplies(host, (req) => (req.url.includes("/admin/api/usage?") ? { rows: [] } : undefined));
  // Its stream, gone quiet as time passes here, comes back told what it missed (a stream read anew may have missed a
  // change: what is held is read again as it is next shown).
  gate.resumes = true;
  Queue.offerUnsafe(streams.at(-1)!.queue, new TextEncoder().encode(`id: 1f2e3d4c.1\nevent: overview\ndata: {}\n\n`));
  const usage = () => host.requests.filter((r) => r.url.includes("/admin/api/usage?")).length;
  assert.equal(usage(), 0, "not shown as the station is read");
  push("usage", {});
  await host.settle();
  assert.equal(usage(), 0, "nor as it changes: with every model call, some 200 KB each time");
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "stationUsage", station: ST });
  await host.settle();
  assert.equal(usage(), 1, "shown: read");
  push("usage", {});
  await host.settle();
  assert.equal(usage(), 2, "and again as it changes while shown");
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  subscribe(core, ui, 2, { topic: "stationUsage", station: ST });
  await host.settle();
  assert.equal(usage(), 2, "shown again, unchanged since: what is held is current");
  core.receive(ui, { kind: "unsubscribe", id: 2, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  push("usage", {});
  await host.settle();
  subscribe(core, ui, 3, { topic: "stationUsage", station: ST });
  await host.settle();
  assert.equal(usage(), 3, "changed while not shown: read as it is shown again");
  // The page of usage (a view made from it) shows it as well.
  core.receive(ui, { kind: "unsubscribe", id: 3, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  subscribe(core, ui, 4, { topic: "usage", scope: "ws" });
  await host.settle();
  assert.equal(usage(), 3);
  push("usage", {});
  await host.settle();
  assert.equal(usage(), 4, "changed while the page shows it: read");
  core.close();
});

test("the_archive_is_read_only_while_a_page_shows_it", async () => {
  const s = await ui({ ...base(), "POST /threads/7/archive": { ok: true } });
  // Its stream comes back told what it missed, as in the test before.
  s.gate.resumes = true;
  Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode(`id: 1f2e3d4c.1\nevent: overview\ndata: {}\n\n`));
  const archived = () => gets(s.host, "/chats?archived=1");
  const archive = async (id: number) => {
    call(s.core, s.ui, id, "chat.archive", { station: ST, session: "k1", thread: 7, archived: true });
    await s.read();
  };
  const shown = async (id: number) => {
    subscribe(s.core, s.ui, id, { topic: "archive", scope: "ws" });
    await s.read();
  };
  const left = async (id: number) => {
    s.core.receive(s.ui, { kind: "unsubscribe", id, unsubscribe: true });
    await s.host.time.pass(EVICT_AFTER_MS + 500, 500);
  };
  assert.equal(archived(), 0, "not shown as the station is read");
  await archive(1);
  assert.equal(archived(), 0, "nor as a chat is archived");
  await shown(2);
  assert.equal(archived(), 1, "shown: read");
  await archive(3);
  assert.equal(archived(), 2, "and again as one is archived while it is shown");
  await left(2);
  await shown(4);
  assert.equal(archived(), 2, "shown again, unchanged since: what is held is current");
  await left(4);
  await archive(5);
  await shown(6);
  assert.equal(archived(), 3, "one archived while not shown: read as it is shown again");
  s.core.close();
});

test("what_a_chat_shows_small_is_read_once_and_kept_on_the_device", async () => {
  const s = await ui({
    ...base(),
    "GET /sessions/k/files?name=a.png&thumb=1": "small",
    "GET /sessions/k/files?name=a.png": "whole",
    "GET /sessions/k/poster?name=v.mp4": "jpeg",
  });
  const asked = async (c: { core: J; ui: number }, id: number, name: string, params: J) => {
    call(c.core, c.ui, id, name, params);
    await s.host.settle();
    // Its answer and the bytes beside it.
    const m = s.host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m)) as J;
    return { ok: m?.ok, bytes: m?.bytes === undefined ? undefined : new TextDecoder().decode(m.bytes) };
  };
  const thumb = { station: ST, key: "k", name: "a.png", thumb: true };
  const poster = { station: ST, key: "k", name: "v.mp4" };
  const small = await asked(s, 1, "station.file", thumb);
  assert.deepEqual(small, { ok: { type: "application/json" }, bytes: JSON.stringify("small") });
  // (what the device had says so: what shows it shows it as it is)
  const held = (a: { ok: J; bytes: string | undefined }) => ({ ...a, ok: { ...a.ok, held: true } });
  assert.deepEqual(await asked(s, 2, "station.file", thumb), held(small), "shown again: from the device");
  const jpeg = await asked(s, 3, "station.poster", poster);
  assert.deepEqual(await asked(s, 4, "station.poster", poster), held(jpeg));
  assert.deepEqual([gets(s.host, "/sessions/k/files?name=a.png&thumb=1"), gets(s.host, "/sessions/k/poster?name=v.mp4")], [1, 1]);
  // The whole file is read as it is opened: not kept.
  await asked(s, 5, "station.file", { ...thumb, thumb: false });
  await asked(s, 6, "station.file", { ...thumb, thumb: false });
  assert.equal(gets(s.host, "/sessions/k/files?name=a.png"), 2);
  // The app started anew: still there.
  const later = await reopen(s);
  assert.deepEqual(await asked(later, 7, "station.file", thumb), held(small));
  assert.deepEqual(await asked(later, 8, "station.poster", poster), held(jpeg));
  assert.deepEqual([gets(s.host, "/sessions/k/files?name=a.png&thumb=1"), gets(s.host, "/sessions/k/poster?name=v.mp4")], [1, 1]);
  later.core.close();
});

test("what_a_widget_kept_is_kept_on_the_device_answered_at_once_and_read_again_behind", async () => {
  const answers: J = { ...base(), "GET /sessions/k/widget-state?path=a.html": { state: { n: 1 } }, "PUT /sessions/k/widget-state": {} };
  const s = await ui(answers);
  const asked = async (c: { core: J; ui: number }, id: number, name: string, params: J) => {
    call(c.core, c.ui, id, name, { station: ST, key: "k", path: "a.html", ...params });
    await s.host.settle();
    return (s.host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === id && ("ok" in m || "error" in m)) as J)?.ok;
  };
  const reads = () => gets(s.host, "/sessions/k/widget-state?path=a.html");
  assert.deepEqual(await asked(s, 1, "widget.state", {}), { state: { n: 1 } });
  // The station's changed meanwhile (another device): what is kept answers at once, what it says now kept after.
  answers["GET /sessions/k/widget-state?path=a.html"] = { state: { n: 2 } };
  assert.deepEqual(await asked(s, 2, "widget.state", {}), { state: { n: 1 } });
  assert.equal(reads(), 2);
  // Kept here: kept on the device at once, as it goes to the station.
  await asked(s, 3, "widget.setState", { state: { n: 3 } });
  assert.equal(s.host.requests.filter((r) => r.method === "PUT" && r.url.endsWith("/sessions/k/widget-state")).length, 1);
  // The app started anew: what was kept last.
  const later = await reopen(s);
  assert.deepEqual(await asked(later, 4, "widget.state", {}), { state: { n: 3 } });
  later.core.close();
});

test("a_thread_opens_from_what_is_kept_and_asks_only_for_what_came_after", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 300)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
  };
  const s = await ui(answers);
  s.core.receive(s.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await s.read();
  s.push("thread", { id: 7, entries: [entry(301, "m301")] });
  await s.read();
  assert.equal(nums(s.values).length, 51);
  // Started anew: the kept page at once, then only what came after it is asked for (and the rest of the thread, in
  // the background: here the station has no more to give).
  answers["GET /threads"] = [threadView(7, 302)];
  answers["GET /threads/7/entries?after=301"] = { last: 302, entries: [entry(302, "m302")] };
  const asked = s.host.requests.length;
  const again = await reopen(s);
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await again.read();
  assert.deepEqual(windowOf(again.values), [253, 302, true]);
  assert.equal(page(again.values).thread.id, 7);
  // Caught up on (kept, then read): none of it was said while the chat was open.
  assert.equal(page(again.values).caught, 302);
  const read = entryReads(s.host, asked);
  assert.ok(!read.some((p) => p.includes("limit=50") && !p.includes("before")), JSON.stringify(read));
  assert.equal(read.filter((p) => p === "/threads/7/entries?after=301").length, 1, JSON.stringify(read));
  // Scrolling up reads what is kept first; past it, the station (and what it answers is kept too).
  answers["GET /threads/7/entries?before=253&limit=50"] = { last: 302, entries: entries(203, 252) };
  assert.equal(await run(again.core.inner.stationTopics.older(ST, 7)), true);
  await again.read();
  assert.equal(page(again.values).first, 203);
  const third = await reopen({ host: s.host, core: again.core });
  third.core.receive(third.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await third.read();
  const before = s.host.requests.length;
  assert.equal(await run(third.core.inner.stationTopics.older(ST, 7)), true);
  await third.read();
  assert.deepEqual(nums(third.values), Array.from({ length: 100 }, (_, i) => 203 + i), "two pages, both from what is kept");
  assert.equal(entryReads(s.host, before).filter((p) => p.includes("before=")).length, 0);
  assert.equal(texts(third.values).at(-1), "m302");
  third.core.close();
});

test("a_chat_with_something_unread_opens_whole_at_it_and_pages_either_way", async () => {
  // 300 entries, read up to 200: the window is the page before the first unread and the page from it.
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 300, 200, 100)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
    "GET /threads/7/entries?from=151&to=250": { last: 300, entries: entries(151, 250) },
  };
  const { host, core, push, values, read } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  await read();
  assert.deepEqual(windowOf(values), [151, 250, false]);
  // Said meanwhile, past the window: it waits (kept for when the window comes down to it).
  push("thread", { id: 7, entries: [entry(301, "m301")] });
  await read();
  assert.deepEqual(windowOf(values), [151, 250, false]);
  // Down: the page after, from the device (brought in by the sync, not asked again); then what waited, and the
  // window is at its end, as many gone at its start.
  assert.equal(await run(core.inner.stationTopics.newer(ST, 7)), true);
  await read();
  assert.deepEqual(windowOf(values), [151, 300, false]);
  assert.equal(await run(core.inner.stationTopics.newer(ST, 7)), false);
  await read();
  assert.deepEqual(windowOf(values), [152, 301, true]);
  assert.equal(page(values).caught, 301);
  // Up: the page before comes in, and as many go at the other end.
  answers["GET /threads/7/entries?before=152&limit=50"] = { last: 301, entries: entries(102, 151) };
  assert.equal(await run(core.inner.stationTopics.older(ST, 7)), true);
  await read();
  assert.deepEqual(windowOf(values), [102, 251, false]);
  assert.equal(nums(values).length, 150);
  // To the end: its latest page in place of the window, from the device.
  const asked = host.requests.length;
  await run(core.inner.stationTopics.latest(ST, 7));
  await read();
  assert.deepEqual(windowOf(values), [252, 301, true]);
  assert.deepEqual(entryReads(host, asked), []);
  // At its end, what is said joins it.
  push("thread", { id: 7, entries: [entry(302, "m302")] });
  await read();
  assert.equal(windowOf(values)[1], 302);
  core.close();
});

test("a_chat_opens_from_the_device_when_what_is_kept_is_current_and_else_waits_to_be_whole", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 300)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
  };
  const s = await ui(answers);
  // Opened again, nothing new: from the device alone.
  let asked = s.host.requests.length;
  let again = await reopen(s);
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await again.read();
  assert.deepEqual(windowOf(again.values), [251, 300, true]);
  assert.ok(entryReads(s.host, asked).every((p) => !p.includes("limit=50")), JSON.stringify(entryReads(s.host, asked)));
  // Opened again with 20 new (read): what came after is read; the first value is whole.
  answers["GET /threads"] = [threadView(7, 320)];
  answers["GET /threads/7/entries?after=300"] = { last: 320, entries: entries(301, 320) };
  asked = s.host.requests.length;
  again = await reopen({ host: s.host, core: again.core });
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await again.read();
  assert.deepEqual(windowOf(again.values), [271, 320, true]);
  assert.equal(page(again.values).caught, 320, "read, not said");
  // Left short of its end and opened again: there.
  again.core.inner.stationTopics.place(ST, 7, 120, null);
  again.core.receive(again.ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await s.host.time.pass(EVICT_AFTER_MS + 500, 500);
  answers["GET /threads/7/entries?from=70&to=169"] = { last: 320, entries: entries(70, 169) };
  again.core.receive(again.ui, { kind: "subscribe", id: 2, subscribe: thread7 });
  await again.read();
  await again.read();
  assert.deepEqual(windowOf(again.values, 2), [70, 169, false]);
  again.core.close();
});

test("where_a_chat_was_left_is_kept_on_the_device_for_a_core_started_anew", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 300)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
  };
  const s = await ui(answers);
  s.core.receive(s.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await s.read();
  // Left 180 down: the core goes (the page reloaded) before the chat is opened again.
  s.core.inner.stationTopics.place(ST, 7, 180, -36.5);
  await s.host.settle();
  answers["GET /threads/7/entries?from=130&to=229"] = { last: 300, entries: entries(130, 229) };
  let again = await reopen(s);
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await again.read();
  await again.read();
  assert.deepEqual(windowOf(again.values), [130, 229, false]);
  assert.deepEqual([page(again.values).at, page(again.values).atOffset], [180, -36.5]);
  // Left at its end: the next core opens it there.
  again.core.inner.stationTopics.place(ST, 7, null, null);
  await s.host.settle();
  again = await reopen({ host: s.host, core: again.core });
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: thread7 });
  await again.read();
  assert.equal(windowOf(again.values)[2], true);
  assert.equal(page(again.values).at, undefined);
  again.core.close();
});

test("a_chat_not_open_keeps_up_on_the_device", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 300)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
  };
  const { host, core, push, values, read } = await ui(answers);
  // Nobody looking; what is said meanwhile carries on what is kept. Past a gap, what came after what is kept is read
  // then, so it stays whole.
  answers["GET /threads/7/entries?from=302&to=302"] = { last: 303, entries: [entry(302, "m302")] };
  push("thread", { id: 7, entries: [entry(301, "m301")] });
  push("thread", { id: 7, entries: [entry(303, "m303")] });
  await host.settle();
  await host.settle();
  assert.equal(gets(host, "/admin/api/threads/7/entries?from=302&to=302"), 1, "asked only for the gap");
  // Opened: whole from the device, asking nothing.
  const asked = host.requests.length;
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  assert.equal(texts(values).at(-1), "m303");
  assert.deepEqual(nums(values).slice(-3), [301, 302, 303]);
  assert.deepEqual(entryReads(host, asked), []);
  assert.equal(page(values).caught, 303);
  core.close();
});

test("a_removed_thread_and_a_removed_sessions_transcript_are_forgotten", async () => {
  const { host, core, push } = await started({ ...base(), "GET /threads/7/entries?limit=50": { last: 2, entries: entries(1, 2) } });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "live", station: ST, key: "k1" });
  await host.settle();
  await host.settle();
  push("live", { key: "k1", type: "timeline", start: 0, entries: ["a"], usage: {} });
  await host.settle();
  await run(core.inner.data.written);
  const keys = (table: string) => host.rows(dbName("s1"), `SELECT * FROM ${table} WHERE station = 'ws/st'`);
  assert.ok(keys("entry").length > 0 && keys("transcript").length > 0);
  push("thread-removed", { id: 7 });
  push("session-removed", { key: "k1" });
  await host.settle();
  await run(core.inner.data.written);
  assert.deepEqual([keys("entry"), keys("transcript")], [[], []]);
  core.close();
});

test("chat_rows_come_from_the_station_and_follow_its_events", async () => {
  const row = (id: string, thread: number | null, last: number, unread: boolean) => ({ id, thread, session: "k1", title: id, agents: [], lastActiveAt: 1, last: last > 0 ? { seq: last, text: "…" } : null, unread });
  const answers: J = { ...base(), "GET /chats": [row("7", 7, 12, true), row("k", null, 0, false)], "PUT /threads/7/read": { n: 13 } };
  const { host, core, push, streams } = await started(answers);
  await host.settle();
  assert.deepEqual(streams.filter((s) => !s.closed).map((s) => s.path), ["/events?running=1"]);
  const rows = () => core.inner.data.get({ topic: "chatRows", station: ST }) as J[];
  const ids = () => rows().map((r) => r.id);
  assert.deepEqual(ids(), ["7", "k"]);
  const reads = reqs(host);
  // Rows change, come and go as the station says, without a request.
  push("chat", { ...row("7", 7, 13, true), title: "排查" });
  push("chat", row("8", 8, 1, false));
  push("chat-removed", { id: "k" });
  await host.settle();
  assert.deepEqual(ids(), ["7", "8"]);
  assert.equal(rows()[0].title, "排查");
  assert.equal(reqs(host), reads);
  // Read short of the last message: still unread; up to it: read, at once.
  push("read", { viewer: "a@x.com", thread: 7, n: 12 });
  await host.settle();
  assert.equal(rows()[0].unread, true);
  await run(core.inner.stations.read(ST, 7, 13, null));
  assert.equal(rows()[0].unread, false);
  // A new chat is written: the rows are current when the write answers.
  answers["GET /chats"] = [row("9", 9, 0, false)];
  answers["POST /threads"] = { ...threadView(9, 0), sessions: [{ thread: 9, session: "k1" }] };
  await run(core.inner.stations.perform(op("chat.forSession", { session: "k1" }), null));
  assert.deepEqual(ids(), ["9"]);
  // So is saying who one is on Slack.
  answers["PUT /me/slack/U7"] = { ...overview, slackUsers: ["U7"] };
  const before = gets(host, "/admin/api/chats");
  await run(core.inner.stations.perform(op("slack.identity", { user: "U7", bound: true }), null));
  assert.equal(gets(host, "/admin/api/chats"), before + 1);
  core.close();
});

test("a_session_topic_follows_its_threads", async () => {
  const members = (id: number, keys: string[]) => keys.map((session) => ({ thread: id, session }));
  const answers: J = {
    ...base(),
    "GET /sessions/k1": { session: summary("k1", 0), threads: [{ ...threadView(7, 12, 0, 1) }], turns: [] },
    "GET /threads/9": { ...threadView(9, 30, 0, 1), sessions: members(9, ["k1", "j"]) },
  };
  const { host, core, push } = await started(answers);
  await host.settle();
  push("thread", { id: 9, entries: [] });
  push("read", { viewer: "a@x.com", thread: 7, n: 12 });
  await coalesce(host);
  const detail = () => sessionOf(core, "k1");
  assert.deepEqual(detail().threads.map((t: J) => t.id), [9, 7]);
  assert.equal(detail().threads[1].unread, 0);
  // The session left thread 9.
  answers["GET /threads/9"] = { ...threadView(9, 30, 0, 1), sessions: members(9, ["j"]) };
  push("thread", { id: 9, entries: [] });
  await coalesce(host);
  assert.equal(detail().threads.length, 1);
  core.close();
});

test("a_thread_pages_back_and_catches_up", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 4)],
    "GET /threads/7/entries?limit=50": { last: 4, entries: [entry(3, "c"), entry(4, "d")] },
    "GET /threads/7/entries?from=1&to=2": { last: 4, entries: [entry(1, "a"), entry(2, "b")] },
  };
  const { host, core, values, read, end } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  core.receive(1, { kind: "subscribe", id: 2, subscribe: { topic: "link", station: ST } });
  await read();
  // The whole thread came onto the device, nobody asking: its window has it all, nothing older.
  assert.deepEqual(texts(values), ["a", "b", "c", "d"]);
  assert.equal(await run(core.inner.stationTopics.older(ST, 7)), false);
  assert.equal(page(values).caught, 4);
  assert.equal(host.requests.filter((r) => r.url.includes("/entries?before=")).length, 0);
  // The stream was down: what came after the last entry is read, and the pages stay.
  answers["GET /threads"] = [threadView(7, 5)];
  answers["GET /threads/7/entries?after=4"] = { last: 5, entries: [entry(5, "e")] };
  end();
  await read();
  assert.equal(v(values, 2).state, "reconnecting");
  await host.time.pass(RECONNECT_MS + 50, 50);
  await read();
  assert.equal(v(values, 2).state, "online");
  assert.deepEqual(texts(values), ["a", "b", "c", "d", "e"]);
  assert.equal(page(values).caught, 5, "what was missed while the stream was down is caught up on");
  assert.equal(gets(host, "/admin/api/threads/7/entries?limit=50"), 1);
  core.close();
});

test("posts_into_a_thread_answering_as_the_station_takes_it_its_entry_coming_as_any_does", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 12)],
    "GET /threads/7/entries?limit=50": { last: 12, entries: [entry(12, "d")] },
    "POST /threads/7/messages": { n: 13 },
    "GET /threads/7/entries?after=12": { last: 13, entries: [entry(13, "你好")] },
    "PUT /threads/7/read": { viewer: "a@x.com", thread: 7, n: 13 },
  };
  const { host, core, values, read, push } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  const entryReads = (from: number) => host.requests.slice(from).filter((r) => r.url.includes("/threads/7/entries")).length;
  // Sent once the station takes it: nothing of the thread is read for it.
  let from = host.requests.length;
  assert.equal(await run(core.inner.stations.post(ST, 7, { text: "你好" }, null)), 13);
  assert.equal(entryReads(from), 0);
  // Its stream not telling it, its entry is read once the burst is over.
  await host.time.pass(EVENTS_COALESCE_MS + 50, 50);
  await read();
  assert.deepEqual(texts(values), ["d", "你好"]);
  assert.equal(entryReads(from), 1);
  // Reading: sent once, not again for less.
  await run(core.inner.stations.read(ST, 7, 13, null));
  await run(core.inner.stations.read(ST, 7, 12, null));
  const puts = host.requests.filter((r) => r.method === "PUT" && r.url.endsWith("/threads/7/read"));
  assert.equal(puts.length, 1);
  assert.equal(text(puts[0].body), '{"n":13}');
  assert.equal(threadsOf(core)[0].unread, 0);
  // Told by its stream (as it mostly is): not read at all.
  answers["POST /threads/7/messages"] = { n: 14 };
  from = host.requests.length;
  assert.equal(await run(core.inner.stations.post(ST, 7, { text: "再一条" }, null)), 14);
  push("thread", { id: 7, entries: [entry(14, "再一条")] });
  await host.time.pass(EVENTS_COALESCE_MS + 50, 50);
  await read();
  assert.deepEqual(texts(values), ["d", "你好", "再一条"]);
  assert.equal(entryReads(from), 0);
  core.close();
});

test("events_reconnect_report_the_link_and_read_everything_once", async () => {
  const { host, core, gate, end, streams } = await started();
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "link", station: ST });
  const read = async () => {
    await host.settle();
    apply(host, values);
  };
  await read();
  assert.equal(linkOf(values, 1), "online");
  gate.stream = "fail";
  end();
  await read();
  // It was up and dropped: coming back, for a few tries.
  assert.equal(linkOf(values, 1), "reconnecting");
  await host.time.pass(RECONNECT_MS + 50, 50);
  await read();
  assert.deepEqual(v(values, 1), { state: "reconnecting", message: "连不上（10月6日 09:00:02）" });
  gate.stream = 403;
  await host.time.pass(RECONNECT_MS + 50, 50);
  await read();
  assert.deepEqual(v(values, 1), { state: "error", message: "没有权限" });
  const s = gets(host, "/admin/api/sessions");
  gate.stream = "open";
  // Tries come less often as they miss: twice the wait by now.
  await host.time.pass(RECONNECT_MS + 50, 50);
  await read();
  assert.equal(linkOf(values, 1), "error");
  await host.time.pass(RECONNECT_MS, 50);
  await read();
  assert.equal(linkOf(values, 1), "online");
  assert.equal(gets(host, "/admin/api/sessions"), s + 1, "a reconnect reads the station once");
  // Deliberately otherwise (rule 6): nothing shown, the stream stays open (the sync keeps the station current).
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  assert.equal(streams.filter((x) => !x.closed).length, 1);
  core.close();
});

/// 2026-10-18: a phone on its station's LAN showed 正在重连 every minute or so, as its requests moved between the LAN and
/// a relay and its stream opened again on the new way. A stream that ends while another way to the station is up opens
/// again at once, the station shown as reached all along; with none up, it is coming back as before.
test("a_stream_gone_while_another_way_is_up_opens_again_with_the_station_still_reached", async () => {
  class Ways extends HostWire {
    up = true;
    standing() {
      return this.up;
    }
  }
  const made: Ways[] = [];
  const { host, core, end, streams } = await started(base(), 0, (h) => {
    const w = new Ways(h);
    made.push(w);
    return w;
  });
  const ui = core.connect();
  const values = new Map();
  const seen: unknown[] = [];
  subscribe(core, ui, 1, { topic: "link", station: ST });
  const read = async () => {
    await host.settle();
    apply(host, values);
    seen.push(linkOf(values, 1));
  };
  await read();
  assert.equal(linkOf(values, 1), "online");
  await host.time.pass(RECONNECT_MS + 50, 50);
  const opened = streams.length;
  end();
  await read();
  // Open again on the other way at once, nothing waited out, never shown as coming back.
  assert.equal(streams.length, opened + 1);
  assert.equal(streams.filter((x) => !x.closed).length, 1);
  assert.deepEqual([...new Set(seen)], ["online"]);
  // One that ends as soon as it opens, after another that did not hold either (STREAM_HELD_MS), waits out twice
  // RECONNECT_MS, the station still reached.
  end();
  await read();
  assert.equal(streams.length, opened + 1);
  assert.equal(linkOf(values, 1), "online");
  await host.time.pass(2 * RECONNECT_MS + 50, 50);
  await read();
  assert.equal(streams.length, opened + 2);
  assert.deepEqual([...new Set(seen)], ["online"]);
  // No way up: coming back.
  await host.time.pass(RECONNECT_MS + 50, 50);
  for (const w of made) w.up = false;
  end();
  await read();
  assert.equal(linkOf(values, 1), "reconnecting");
  await host.time.pass(4 * RECONNECT_MS + 50, 50);
  await read();
  assert.equal(linkOf(values, 1), "online");
  core.close();
});

const liveK = { topic: "live", station: ST, key: "k1" };
/// The live topic's value as the core makes it (before the protocol's shapes: these items are only markers).
const liveOf = (core: J) => topicOf(core, liveK).ok;
const streamPaths = (host: FakeHost) => host.requests.filter((r) => r.url.includes("/admin/api/events")).map((r) => r.url.replace("https://stillfail.test/admin/api", ""));

test("live_holds_the_transcript_and_its_usage", async () => {
  const s = await ui(base());
  const { host, core, values, read } = s;
  core.receive(1, { kind: "subscribe", id: 1, subscribe: liveK });
  await read();
  await read();
  assert.ok(streamPaths(host).includes("/events?running=1&live=k1&from=0&last=200&brief=1"), JSON.stringify(streamPaths(host)));
  const push = (m: J) => s.push("live", { key: "k1", ...m });
  push({ type: "timeline", start: 0, entries: ["a", "b"], usage: { modelCalls: 1, model: "claude-opus" } });
  push({ type: "steps", steps: [], phase: null });
  await read();
  assert.deepEqual([liveOf(core).loaded, liveOf(core).timeline, liveOf(core).usage.model], [true, ["a", "b"], "claude-opus"]);
  push({ type: "timeline", start: 2, entries: ["c"], usage: { modelCalls: 2 } });
  await read();
  assert.deepEqual(liveOf(core).timeline, ["a", "b", "c"]);
  assert.equal(liveOf(core).usage.modelCalls, 2);
  // Overlap: replaced from `start`.
  push({ type: "timeline", start: 1, entries: ["B", "c", "d"], usage: {} });
  await read();
  assert.deepEqual(liveOf(core).timeline, ["a", "B", "c", "d"]);
  // Reconnects ask from what is known.
  s.end();
  await host.time.pass(RECONNECT_MS + 50, 50);
  assert.ok(streamPaths(host).includes("/events?running=1&live=k1&from=4&last=200&brief=1"), JSON.stringify(streamPaths(host)));
  // Started anew: the kept transcript at once, and only what came after it is asked for.
  let again = await reopen(s);
  const asked = streamPaths(host).length;
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: liveK });
  await again.read();
  await again.read();
  assert.deepEqual(liveOf(again.core).timeline, ["a", "B", "c", "d"]);
  assert.ok(streamPaths(host).slice(asked).includes("/events?running=1&live=k1&from=4&last=200&brief=1"), JSON.stringify(streamPaths(host)));
  // Written anew and shorter: what is kept is cut there too.
  s.push("live", { key: "k1", type: "timeline", start: 1, entries: [], usage: {} });
  await again.read();
  assert.deepEqual(liveOf(again.core).timeline, ["a"]);
  again = await reopen({ host, core: again.core });
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: liveK });
  await again.read();
  await again.read();
  assert.deepEqual(liveOf(again.core).timeline, ["a"]);
  // Past what is here (the station sent only its latest page): the timeline starts there.
  s.push("live", { key: "k1", type: "timeline", start: 9, entries: ["z"], usage: {} });
  await again.read();
  assert.deepEqual([liveOf(again.core).first, liveOf(again.core).timeline], [9, ["z"]]);
  const before = streamPaths(host).length;
  again = await reopen({ host, core: again.core });
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: liveK });
  await again.read();
  await again.read();
  assert.deepEqual([liveOf(again.core).first, liveOf(again.core).timeline], [9, ["z"]]);
  assert.ok(streamPaths(host).slice(before).includes("/events?running=1&live=k1&from=10&last=200&brief=1"), JSON.stringify(streamPaths(host)));
  again.core.close();
});

test("a_transcript_shows_its_latest_page_and_the_ones_before_as_asked", async () => {
  const items = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => `e${from + i}`);
  const answers: J = base();
  const s = await ui(answers);
  const { host, core, values, read } = s;
  core.receive(1, { kind: "subscribe", id: 1, subscribe: liveK });
  await read();
  await read();
  s.push("live", { key: "k1", type: "timeline", start: 300, entries: items(300, 499), usage: {} });
  await read();
  assert.equal(liveOf(core).first, 300);
  // From the station, and kept.
  answers["GET /sessions/k1/timeline?before=300&limit=200&brief=1"] = { start: 100, entries: items(100, 299) };
  assert.equal(await run(core.inner.stationTopics.historyOlder(ST, "k1")), true);
  await read();
  assert.deepEqual([liveOf(core).first, liveOf(core).timeline.length, liveOf(core).timeline[0]], [100, 400, "e100"]);
  answers["GET /sessions/k1/timeline?before=100&limit=200&brief=1"] = { start: 0, entries: items(0, 99) };
  assert.equal(await run(core.inner.stationTopics.historyOlder(ST, "k1")), false);
  await read();
  assert.equal(liveOf(core).first, 0);
  assert.equal(await run(core.inner.stationTopics.historyOlder(ST, "k1")), false);
  // Opened again: the latest page from the device, the one before it from the device too.
  const again = await reopen(s);
  const asked = host.requests.length;
  again.core.receive(again.ui, { kind: "subscribe", id: 1, subscribe: liveK });
  await again.read();
  await again.read();
  assert.deepEqual([liveOf(again.core).first, liveOf(again.core).timeline[0]], [300, "e300"]);
  assert.ok(streamPaths(host).includes("/events?running=1&live=k1&from=500&last=200&brief=1"), JSON.stringify(streamPaths(host)));
  assert.equal(await run(again.core.inner.stationTopics.historyOlder(ST, "k1")), true);
  await again.read();
  assert.equal(liveOf(again.core).first, 100);
  assert.ok(!host.requests.slice(asked).some((r) => r.url.includes("/timeline")));
  again.core.close();
});

test("an_agent_used_lately_has_its_whole_history_brought_in_the_background_one_not_used_its_latest_alone", async () => {
  const items = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => `e${from + i}`);
  const answers: J = base();
  answers["GET /sessions/k1/timeline?before=300&limit=200&brief=1"] = { start: 100, entries: items(100, 299), end: 500 };
  answers["GET /sessions/k1/timeline?before=100&limit=200&brief=1"] = { start: 0, entries: items(0, 99), end: 500 };
  const s = await ui(answers, (st) => (st.gate.follows = true));
  const { host, core, read } = s;
  const older = () => host.requests.filter((r) => /timeline\?before=(300|100)&/.test(r.url)).length;
  // Its latest, as told; nothing before it is brought for an agent not used lately.
  s.push("live", { key: "k1", type: "timeline", start: 300, entries: items(300, 499), usage: {} });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  await read();
  assert.equal(older(), 0);
  // Its chat opened: what is before it is brought, page after page, down to its first entry.
  core.receive(s.ui, { kind: "subscribe", id: 9, subscribe: thread7 });
  await read();
  await read();
  await read();
  assert.equal(older(), 2);
  assert.deepEqual([core.inner.data.logSpan("transcript", ST, "k1")?.min, core.inner.data.logCount("transcript", ST, "k1", 0, 499)], [0, 500]);
  core.close();
});

test("an_agent_at_rest_says_what_it_used_and_what_can_be_done_to_its_context_as_its_summary_says_now", async () => {
  const answers: J = base();
  const used = { modelCalls: 4, inputTokens: 1000, cachedTokens: 900, outputTokens: 20, model: "claude-opus-5-5", contextTokens: 300, contextWindow: null, cost: 1.5, unpricedCalls: 0 };
  const ended = { id: "t1", kind: "input", startedAt: 1, endedAt: 2, outcome: "completed" };
  const rested = { ...session("k1", 1), runtimeSessionId: "r", lastTurn: ended };
  // Its detail as a station said it before either was said; its list as the station says it now.
  answers["GET /sessions/k1"] = { session: rested, threads: [], turns: [ended], jobs: [] };
  answers["GET /sessions"] = [{ ...rested, contextActions: ["compact", "clear"], usage: used }];
  // A station that follows the sessions at work itself: one at rest is named on no stream, which says nothing of it.
  const s = await ui(answers, (st) => (st.gate.follows = true));
  const { core, values, read } = s;
  core.receive(s.ui, { kind: "subscribe", id: 1, subscribe: { topic: "agentCard", station: ST, key: "k1" } });
  core.receive(s.ui, { kind: "subscribe", id: 2, subscribe: { topic: "history", station: ST, key: "k1" } });
  await read();
  await read();
  const card = v(values, 1) as J;
  assert.deepEqual([card.cost, card.cache.text, card.context.text], ["$1.50", "90%", "300"]);
  assert.equal((v(values, 2) as J).usage[0].value, "4 次");
  const agent = core.inner.views.agent(ST, "k1");
  assert.deepEqual([agent.session.canCompact, agent.session.canClear], [true, true]);
  core.close();
});

test("an_agents_card_says_what_it_has_going_in_the_background_and_its_checklist_as_its_station_tells_them", async () => {
  const s = await ui(base());
  const { host, core, values, read } = s;
  core.receive(s.ui, { kind: "subscribe", id: 1, subscribe: { topic: "agentCard", station: ST, key: "k1" } });
  await read();
  await read();
  const card = () => v(values, 1) as J;
  // A station from before says neither: nothing.
  assert.deepEqual([card().tasks, card().plan, card().planText, card().workLine], [[], [], undefined, undefined]);
  const now = host.nowMs();
  const task = (id: string, kind: string, description: string, elapsedMs: number) => ({ id, kind, description, startedAt: 1, elapsedMs });
  const plan = [["Read", "completed"], ["Fix", "in_progress"], ["Test", "pending"], ["Docs", "pending"], ["Ship", "pending"]].map(([text, status]) => ({ text, status }));
  s.push("live", { key: "k1", type: "work", tasks: [task("a1", "agent", "Survey the gaps\nmore", 90_000), task("b1", "command", "", 5_000), task("b2", "command", "watch CI", 1), task("b3", "command", "lint", 1)], plan });
  await read();
  await read();
  const c = card();
  // Each task by what it is (its description's first line, else its kind), since when on this device's clock.
  assert.deepEqual(c.tasks.slice(0, 2).map((t: J) => [t.id, t.kind, t.text, t.kindText]), [["a1", "agent", "Survey the gaps", "子代理"], ["b1", "command", "命令", "命令"]]);
  assert.ok(Math.abs(c.tasks[0].since - (now - 90_000)) < 1000);
  // Its checklist whole and how much is done; all of it in one line, with the item under way.
  assert.equal(c.plan.length, 5);
  assert.equal(c.planText, "已完成 1/5");
  assert.equal(c.workLine, "后台 4 · 清单 1/5：Fix");
  assert.deepEqual([c.workMark, c.workMarkShort, c.workMarkCount], ["后台 4 · 1/5", "4 · 1/5", "4"]);
  // Said again whole: what ended is gone; a turn ending (clear) leaves them be.
  s.push("live", { key: "k1", type: "work", tasks: [task("b2", "command", "watch CI", 1)], plan: plan.map((p) => ({ ...p, status: "completed" })) });
  s.push("live", { key: "k1", type: "clear" });
  await read();
  await read();
  assert.deepEqual([card().tasks.map((t: J) => t.id), card().planText, card().workLine], [["b2"], "已完成 5/5", "后台 1 · 清单 5/5"]);
  assert.equal(card().workMark, "后台 1 · 5/5");
  // Only a checklist: its part alone; neither: no line.
  s.push("live", { key: "k1", type: "work", tasks: [], plan });
  await read();
  await read();
  assert.equal(card().workLine, "清单 1/5：Fix");
  assert.deepEqual([card().workMark, card().workMarkCount], ["清单 1/5", "1/5"]);
  s.push("live", { key: "k1", type: "work", tasks: [task("b2", "command", "watch CI", 1)], plan: [] });
  await read();
  await read();
  assert.deepEqual([card().workLine, card().workMark], ["后台 1", "后台 1"]);
  s.push("live", { key: "k1", type: "work", tasks: [], plan: [] });
  await read();
  await read();
  assert.deepEqual([card().workLine, card().workMark], [undefined, undefined]);
  core.close();
});

test("a_history_step_in_brief_is_read_whole_as_it_is_opened_and_shown_so", async () => {
  const answers: J = base();
  const s = await ui(answers);
  const { core, values, read } = s;
  core.receive(1, { kind: "subscribe", id: 1, subscribe: { topic: "history", station: ST, key: "k1" } });
  await read();
  await read();
  // In brief, as the station pushes it: the call by what says what it does, the result without what it gave.
  const call = { at: "2026-10-08T00:00:00Z", kind: "tool_call", text: JSON.stringify({ command: "pnpm test", description: "Run the tests" }), tool: "Bash", callId: "c" };
  s.push("live", { key: "k1", type: "timeline", start: 7, entries: [{ ...call, brief: true }, { at: "2026-10-08T00:00:03Z", kind: "tool_result", text: "", ok: true, callId: "c", brief: true }], usage: {} });
  await read();
  const step = () => {
    const group = (v(values, 1) as J).items.find((i: J) => i.body.kind === "group").body.content;
    return group.rows.find((r: J) => r.kind === "step").content;
  };
  assert.deepEqual([step().said, step().brief, step().entries], ["Run the tests", true, [7, 8]]);
  // Opened: read whole, behind what is shown in brief, and shown so.
  const whole = { ...call, text: JSON.stringify({ command: "pnpm test --runInBand", description: "Run the tests", timeout: 600000 }, null, 2) };
  answers["GET /sessions/k1/timeline?from=7&to=8"] = { start: 7, entries: [whole, { at: "2026-10-08T00:00:03Z", kind: "tool_result", text: "Tests: 18 passed", ok: true, callId: "c" }] };
  await run(core.inner.stationTopics.historyDetail(ST, "k1", 7, 8));
  await read();
  assert.deepEqual([step().brief, step().result, JSON.parse(step().call).timeout], [false, "Tests: 18 passed", 600000]);
  core.close();
});

test("a_stream_silent_past_its_keepalive_is_read_again", async () => {
  const { host, core, streams } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, liveK);
  await host.settle();
  await host.settle();
  const path = "/admin/api/events?running=1&live=k1&from=0&last=200&brief=1";
  assert.equal(gets(host, path), 1);
  // The keepalive keeps it open.
  await host.time.pass(STREAM_IDLE_MS / 2, 500);
  const open = streams.filter((s) => !s.closed).at(-1)!;
  Queue.offerUnsafe(open.queue, new TextEncoder().encode(": ping\n\n"));
  await host.time.pass(STREAM_IDLE_MS / 2 + 5_000, 500);
  assert.equal(gets(host, path), 1);
  // Nothing at all for longer: the link is taken for gone, and it is asked for again.
  await host.time.pass(STREAM_IDLE_MS + RECONNECT_MS + 5_000, 500);
  assert.equal(gets(host, path), 2);
  core.close();
});

test("a_stream_replaced_after_it_went_quiet_reads_again_what_it_may_have_missed", async () => {
  const answers: J = {
    ...base(),
    "GET /threads": [threadView(7, 12)],
    "GET /threads/7/entries?limit=50": { last: 12, entries: [entry(11, "a"), entry(12, "b")] },
  };
  const { host, core, values, read } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  assert.deepEqual(nums(values), [11, 12]);
  // Opened for something more while its stream is heard from: nothing is read again.
  const lists = gets(host, "/admin/api/threads");
  core.receive(1, { kind: "subscribe", id: 2, subscribe: { topic: "host", station: ST } });
  await read();
  assert.equal(gets(host, "/admin/api/threads"), lists);
  // The app away for a minute: its stream died unnoticed, and 13 was said meanwhile (its event never came).
  answers["GET /threads"] = [threadView(7, 13, 12, 1)];
  answers["GET /threads/7/entries?after=12"] = { last: 13, entries: [entry(13, "c")] };
  host.advance(60_000);
  // Back, a new stream opened in its place (asking for something else): what it missed is read.
  core.receive(1, { kind: "unsubscribe", id: 2, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  await read();
  assert.deepEqual(nums(values), [11, 12, 13]);
  assert.equal(threadsOf(core)[0].last, 13);
  core.close();
});

test("a_preview_socket_nothing_answers_fails_in_time", async () => {
  class Silent extends HostWire {
    socket() {
      return Effect.never;
    }
  }
  const { host, core } = await started(base(), 0, (h) => new Silent(h));
  host.time.sleeps.length = 0;
  const opening = core.inner.runner.run(Effect.result(Effect.scoped(core.inner.stations.requests.previewSocket(remote(), 5180, "/", [], null))));
  await host.time.pass(SOCKET_OPEN_MS + 100, 1_000);
  const r = (await opening) as J;
  assert.equal(r._tag, "Failure");
  assert.equal(r.failure.code, "timeout");
  assert.ok(host.time.sleeps.includes(SOCKET_OPEN_MS));
  core.close();
});

test("live_steps_and_phase", async () => {
  const s = await ui(base());
  const { host, core, values, read } = s;
  core.receive(1, { kind: "subscribe", id: 1, subscribe: liveK });
  await read();
  await read();
  const push = (m: J) => s.push("live", { key: "k1", ...m });
  const now = host.nowMs();
  push({ type: "steps", steps: [{ id: "s0", step: "text", input: "", startedAt: 1 }], phase: { phase: "thinking", elapsedMs: 5000 } });
  await read();
  let x = liveOf(core);
  assert.equal(x.steps[0].id, "s0");
  assert.equal(x.phase.phase, "thinking");
  assert.ok(Number.isInteger(x.phase.since), "a whole number of ms: clients read it as one");
  assert.ok(Math.abs(x.phase.since - (now - 5000)) < 1000, `${x.phase.since} vs ${now}`);
  push({ type: "step", event: { kind: "start", id: "t1", step: "tool", tool: "Bash", input: "ls" } });
  push({ type: "step", event: { kind: "end", id: "t1" } });
  push({ type: "step", event: { kind: "phase", phase: "responding" } });
  await read();
  x = liveOf(core);
  const t1 = x.steps[1];
  // What it is, not what it wrote: the station tells turning points only.
  assert.deepEqual([t1.tool, t1.input, t1.ended], ["Bash", "ls", true]);
  assert.ok(t1.output === undefined && t1.text === undefined && t1.subagent === undefined);
  assert.equal(x.phase.phase, "responding");
  assert.ok(x.phase.since >= now);
  // No entries: ended steps stay.
  push({ type: "timeline", start: 0, entries: [], usage: {} });
  await read();
  assert.equal(liveOf(core).steps.length, 2);
  // Entries: they recorded the ended step.
  push({ type: "timeline", start: 0, entries: ["x"], usage: {} });
  await read();
  assert.deepEqual(liveOf(core).steps.map((st: J) => st.id), ["s0"]);
  // A restarted id replaces the old step.
  push({ type: "step", event: { kind: "start", id: "s0", step: "text", subagent: true, parent: "t0" } });
  await read();
  x = liveOf(core);
  assert.equal(x.steps.length, 1);
  assert.deepEqual([x.steps[0].step, x.steps[0].subagent, x.steps[0].parent], ["text", true, "t0"]);
  push({ type: "clear" });
  await read();
  x = liveOf(core);
  assert.deepEqual([x.steps, x.phase, x.timeline], [[], null, ["x"]]);
  core.close();
});

test("an_ended_step_goes_once_the_transcript_held_goes_past_it_however_it_came", async () => {
  const answers: J = base();
  const s = await ui(answers, (st) => (st.gate.follows = true));
  const { host, core, read } = s;
  core.receive(1, { kind: "subscribe", id: 1, subscribe: liveK });
  await read();
  await read();
  const push = (m: J) => s.push("live", { key: "k1", ...m });
  push({ type: "timeline", start: 0, entries: ["a", "b"], usage: {} });
  push({ type: "steps", steps: [], phase: null });
  push({ type: "step", event: { kind: "start", id: "s1", step: "thinking" } });
  push({ type: "step", event: { kind: "end", id: "s1" } });
  await read();
  assert.deepEqual(liveOf(core).steps.map((st: J) => [st.id, st.ended]), [["s1", true]]);
  // What came after it is read, not told on the stream (its summary says the transcript went further): the step it
  // recorded goes all the same.
  answers["GET /sessions/k1/timeline?after=1&before=1000000000000000&limit=200&brief=1"] = { start: 2, entries: ["c", "d"], end: 4 };
  s.push("session", { ...session("k1"), transcriptLength: 4 });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  await read();
  assert.deepEqual(liveOf(core).timeline, ["a", "b", "c", "d"]);
  assert.deepEqual(liveOf(core).steps, []);
  core.close();
});

test("a_bad_station_and_a_stations_no_are_errors_a_passing_failure_keeps_loading", async () => {
  const answers: J = { ...base(), "GET /sessions": status(404, { error: "没有" }), "GET /threads": status(502, { error: "坏了" }) };
  const { host, core } = await started(answers);
  await host.settle();
  assert.equal(topicOf(core, { topic: "overview", station: "nope" }).err.code, "invalid_params");
  assert.equal(topicOf(core, { topic: "sessions", station: ST }).err.message, "没有");
  // A failure that passes (a 502): no error, still loading, read again shortly.
  assert.equal(topicOf(core, { topic: "threads", station: ST }), undefined);
  assert.equal(core.inner.data.get({ topic: "threads", station: ST }), undefined, "loading, not an error");
  answers["GET /threads"] = [];
  await host.time.pass(READ_RETRY_MS + 100, 100);
  assert.deepEqual(core.inner.data.get({ topic: "threads", station: ST }), []);
  core.close();
});

test("socket_frames_are_taken_whole_however_they_come_apart", () => {
  const frames: J[] = [{ text: "héllo" }, { binary: new Uint8Array([0, 255]) }, { close: [4001, "done"] }];
  const bytes = new Uint8Array(frames.flatMap((f) => [...encodeFrame(f)]));
  assert.deepEqual([...bytes.slice(0, 5)], [1, 0, 0, 0, 6], "kind, then the length big-endian");
  // One byte at a time: each frame once it is all there, nothing before.
  let buf: Uint8Array = new Uint8Array();
  const got: J[] = [];
  for (const b of bytes) {
    const [taken, rest] = takeFrames(new Uint8Array([...buf, b]));
    got.push(...taken);
    buf = rest;
  }
  assert.deepEqual(got, frames);
  assert.equal(buf.length, 0);
  // All at once, with the start of another after them.
  const [all, rest] = takeFrames(new Uint8Array([...bytes, 2, 0, 0]));
  assert.deepEqual(all, frames);
  assert.deepEqual([...rest], [2, 0, 0]);
  // A close with no code says 1005, as a WebSocket does.
  assert.deepEqual(takeFrames(new Uint8Array([8, 0, 0, 0, 0]))[0], [{ close: [1005, ""] }]);
});

const posted = (host: FakeHost, path: string) => host.requests.filter((r) => r.method === "POST" && r.url.endsWith(path));

test("updating_available_software_skips_installs_and_updates_station_last", async () => {
  const items = [
    { id: "station", installed: true, updatable: true, newer: true },
    { id: "claude", installed: true, updatable: true, newer: true },
    { id: "codex", installed: false, updatable: true, newer: true },
    { id: "manual", installed: true, updatable: false, newer: true },
  ];
  const { host, core } = await started({ ...base(), "GET /overview": { ...overview, updates: items }, "POST /updates": items });
  await run(core.inner.stations.perform(op("software.updateAll", {}), null));
  assert.deepEqual(posted(host, "/admin/api/updates").map((r) => JSON.parse(text(r.body)!).id), ["claude", "station"]);
  assert.equal(posted(host, "/admin/api/updates/all").length, 0, "batch remains compatible with the existing station API");
  core.close();
});

test("a_failed_runtime_stops_the_batch_before_station_restarts", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /overview": { ...overview, updates: [{ id: "station", installed: true, updatable: true, newer: true }, { id: "claude", installed: true, updatable: true, newer: true }] },
    "POST /updates": [{ id: "claude", state: "failed", message: "download failed" }],
  });
  const e = await failure(core.inner.stations.perform(op("software.updateAll", {}), null));
  assert.ok(e.message.includes("download failed"));
  assert.equal(posted(host, "/admin/api/updates").length, 1);
  core.close();
});

test("an_existing_update_is_not_started_twice_by_a_batch", async () => {
  const { host, core } = await started({ ...base(), "GET /overview": { ...overview, updates: [{ id: "codex", state: "updating" }] } });
  const e = await failure(core.inner.stations.perform(op("software.updateAll", {}), null));
  assert.ok(e.message.includes("正在更新"), e.message);
  assert.equal(posted(host, "/admin/api/updates").length, 0);
  core.close();
});

test("a_batch_waits_for_a_runtime_to_finish_before_starting_station", async () => {
  const items = [{ id: "station", installed: true, updatable: true, newer: true }, { id: "claude", installed: true, updatable: true, newer: true }];
  const answers: J = { ...base(), "GET /overview": { ...overview, updates: items }, "POST /updates": [{ id: "claude", state: "updating" }] };
  const { host, core, push } = await started(answers);
  const done = Effect.runPromise(Effect.result(core.inner.stations.perform(op("software.updateAll", {}), null)));
  await host.time.pass(3_000, 100);
  assert.equal(posted(host, "/admin/api/updates").length, 1, "station cannot restart during a runtime update");
  // Its progress is the station's to tell (its overview event, as the pages see it), not asked again each second.
  const asked = () => host.requests.filter((r) => r.method === "GET" && r.url.endsWith("/admin/api/overview")).length;
  const before = asked();
  await host.time.pass(10_000, 100);
  assert.equal(asked(), before);
  assert.equal(posted(host, "/admin/api/updates").length, 1);
  push("overview", { ...overview, updates: [{ id: "claude", state: "idle" }] });
  await host.time.pass(500, 100);
  assert.equal(((await done) as J)._tag, "Success");
  assert.equal(posted(host, "/admin/api/updates").length, 2);
  core.close();
});

test("an_old_notification_to_a_missing_or_forbidden_thread_reports_the_failure", async () => {
  for (const code of [403, 404, 410]) {
    // A chat the station does not list (an old notification's): opened, it is read, and its failure shows.
    const { core, read } = await ui({
      ...base(),
      "GET /threads/9": status(code, { error: "对话已不可用" }),
      "GET /threads/9/entries?limit=50": status(code, { error: "对话已不可用" }),
    });
    core.receive(1, { kind: "subscribe", id: 1, subscribe: { topic: "thread", station: ST, thread: 9 } });
    await read();
    await read();
    assert.equal(topicOf(core, { topic: "thread", station: ST, thread: 9 })?.err?.status, code, String(code));
    core.close();
  }
});

// sync.rs
test("the_core_keeps_its_workspaces_stations_and_agents_at_work_with_nobody_looking", async () => {
  const { host, core, push, streams } = await started();
  // Nobody subscribed: the account's workspaces, their stations, and what each station holds are read.
  for (const path of ["/v1/me", "/v1/workspaces/ws", "/admin/api/overview", "/admin/api/sessions", "/admin/api/threads", "/admin/api/chats"]) {
    assert.ok(host.requests.some((r) => r.url.endsWith(path)), path);
  }
  assert.equal(core.inner.stations.link(ST)?.state.state, "online");
  // An agent at work: its live state is kept too (its stream follows it); one idle is not.
  push("chat", { id: "7", thread: 7, session: "k1", title: "部署", lastActiveAt: 1, agents: [{ key: "k", process: "running" }, { key: "idle", process: "warm" }] });
  await host.settle();
  await host.settle();
  assert.deepEqual(streams.filter((s) => !s.closed).map((s) => s.path), ["/events?running=1&live=k&from=0&last=200&brief=1"]);
  core.close();
});

test("how_a_station_was_last_time_is_there_as_its_link_starts_and_an_old_file_of_it_moves_into_the_database", async () => {
  const { host, core } = await started({ ...base(), "GET /overview": { connects: [], profiles: [] } }, 0, undefined, (s) => (s.gate.stream = "fail"));
  await host.settle();
  assert.equal(core.inner.data.record("link", ST), "offline");
  await run(core.inner.data.written);
  core.close();
  host.onFetchStream(() => Effect.never);
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui = again.connect();
  const values = new Map();
  subscribe(again, ui, 1, { topic: "link", station: ST });
  await host.settle();
  apply(host, values);
  // Why, as the device can tell before it tries: still.fail cloud is reached and lists it online.
  assert.deepEqual(values.get(1), { state: "connecting", last: "offline", cause: "unreached" }, "as it was, from the start");
  again.inner.data.forgetRecord("link", ST);
  await run(again.inner.data.written);
  again.close();
  host.store(`${LINK_KEY}/${ST}`, new TextEncoder().encode("offline"));
  const third = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  third.connect();
  await host.settle();
  assert.equal(third.inner.data.record("link", ST), "offline");
  assert.equal(host.stored(`${LINK_KEY}/${ST}`), undefined);
  third.close();
});

test("a_station_not_reached_for_long_is_tried_seldom_though_the_cloud_says_it_is_online", async () => {
  const { host, core, gate } = await started(base(), 0, undefined, (s) => (s.gate.stream = "fail"));
  const tries = () => host.requests.filter((r) => r.url.includes("/admin/api/events")).length;
  // Tried less and less often, at most RECONNECT_MAX_MS apart: its LONG_MISSES-th miss some seven minutes in…
  await host.time.pass(LONG_MISSES * RECONNECT_MAX_MS, 1_000);
  assert.equal(tries(), LONG_MISSES);
  // …and then not for OFFLINE_RETRY_MS, as one the cloud says is not online.
  await host.time.pass(4 * RECONNECT_MAX_MS, 1_000);
  assert.equal(tries(), LONG_MISSES);
  await host.time.pass(OFFLINE_RETRY_MS - 4 * RECONNECT_MAX_MS, 1_000);
  assert.equal(tries(), LONG_MISSES + 1);
  // Reached at the try after.
  gate.stream = "open";
  await host.time.pass(OFFLINE_RETRY_MS / 2 + 30_000, 1_000);
  assert.equal(tries(), LONG_MISSES + 2);
  assert.equal(core.inner.data.record("link", ST), "online");
  core.close();
});

test("an_agent_ending_its_turn_keeps_the_stream_one_starting_opens_it_anew", async () => {
  const { host, core, push, streams } = await started();
  const open = () => streams.filter((s) => !s.closed).map((s) => s.path);
  const row = (id: string, agents: unknown[]) => push("chat", { id, thread: Number(id), session: `s${id}`, title: "部署", lastActiveAt: 1, agents });
  row("7", [{ key: "k", process: "running" }]);
  await host.settle();
  await host.settle();
  assert.deepEqual(open(), ["/events?running=1&live=k&from=0&last=200&brief=1"]);
  const opened = streams.length;
  // Its turn over: the stream goes on as it is, still following it.
  row("7", [{ key: "k", process: "warm" }]);
  await host.settle();
  await host.settle();
  assert.equal(streams.length, opened);
  assert.deepEqual(open(), ["/events?running=1&live=k&from=0&last=200&brief=1"]);
  // Another at work: a stream for what is wanted now, without the one done.
  row("8", [{ key: "j", process: "running" }]);
  await host.settle();
  await host.settle();
  assert.equal(streams.length, opened + 1);
  assert.deepEqual(open(), ["/events?running=1&live=j&from=0&last=200&brief=1"]);
  core.close();
});

test("a_station_that_follows_the_agents_at_work_itself_names_none_and_one_starting_opens_no_stream", async () => {
  const { host, core, push, streams } = await started(base(), 0, undefined, (s) => (s.gate.follows = true));
  const open = () => streams.filter((s) => !s.closed).map((s) => s.path);
  assert.deepEqual(open(), ["/events?running=1"]);
  assert.equal(core.inner.stations.link(ST)?.followsRunning, true);
  const opened = streams.length;
  // Agents starting and ending their turns: the stream goes on as it is.
  for (const process of ["running", "warm", "running"]) {
    push("chat", { id: "7", thread: 7, session: "k1", title: "部署", lastActiveAt: 1, agents: [{ key: "k", process }] });
    push("chat", { id: "8", thread: 8, session: "s8", title: "测试", lastActiveAt: 1, agents: [{ key: "j", process }] });
    await host.settle();
    await host.settle();
  }
  assert.equal(streams.length, opened);
  assert.deepEqual(open(), ["/events?running=1"]);
  // A page showing an agent's history: no stream for it either.
  const id = core.connect();
  core.receive(id, { kind: "subscribe", id: 1, subscribe: { topic: "live", station: ST, key: "k" } });
  await host.settle();
  await host.settle();
  assert.equal(streams.length, opened);
  core.close();
});

test("what_a_device_lacks_of_a_transcript_after_what_it_holds_is_read_in_the_background_once_anything_says_it_goes_further", async () => {
  const items = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => `e${from + i}`);
  const answers: J = base();
  const s = await ui(answers, (st) => (st.gate.follows = true));
  const { host, core, read } = s;
  const timelines = () => host.requests.filter((r) => r.url.includes("/sessions/k1/timeline")).map((r) => r.url.replace("https://stillfail.test/admin/api", ""));
  // What it holds: told as it was written.
  s.push("live", { key: "k1", type: "timeline", start: 0, entries: items(0, 3), usage: {} });
  await read();
  const before = timelines().length;
  // A stream opening says where it stands now, nothing of what came before: what came after what is held is read.
  answers["GET /sessions/k1/timeline?after=3&before=1000000000000000&limit=200&brief=1"] = { start: 4, entries: items(4, 8), end: 9 };
  s.push("live", { key: "k1", type: "timeline", start: 9, entries: [], usage: {} });
  s.push("live", { key: "k1", type: "steps", steps: [], phase: null });
  // (what says it goes further is looked at once the burst is over)
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  await read();
  assert.deepEqual(timelines().slice(before), ["/sessions/k1/timeline?after=3&before=1000000000000000&limit=200&brief=1"]);
  assert.deepEqual([core.inner.data.logSpan("transcript", ST, "k1")?.max, core.inner.data.logCount("transcript", ST, "k1", 0, 8)], [8, 9]);
  // Its summary says it went further while nothing was told (a stream away as its turn ended): read the same way.
  answers["GET /sessions/k1/timeline?after=8&before=1000000000000000&limit=200&brief=1"] = { start: 9, entries: items(9, 11), end: 12 };
  s.push("session", { ...session("k1"), transcriptLength: 12 });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  await read();
  assert.deepEqual([core.inner.data.logSpan("transcript", ST, "k1")?.max, core.inner.data.logCount("transcript", ST, "k1", 0, 11)], [11, 12]);
  // Told past a hole (entries a stream missed): the hole is read, in brief.
  answers["GET /sessions/k1/timeline?from=12&to=13&brief=1"] = { start: 12, entries: items(12, 13), end: 15 };
  s.push("live", { key: "k1", type: "timeline", start: 14, entries: ["e14"], usage: {} });
  await read();
  await read();
  assert.ok(timelines().includes("/sessions/k1/timeline?from=12&to=13&brief=1"), JSON.stringify(timelines()));
  assert.equal(core.inner.data.logCount("transcript", ST, "k1", 0, 14), 15);
  // Nothing more: nothing more is read.
  const asked = timelines().length;
  s.push("session", { ...session("k1"), transcriptLength: 15 });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  await read();
  assert.equal(timelines().length, asked);
  core.close();
});

test("a_station_from_before_keeps_a_transcript_as_it_did_its_latest_page_and_what_its_stream_tells", async () => {
  const items = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => `e${from + i}`);
  const s = await ui(base());
  const { host, core, read } = s;
  const timelines = () => host.requests.filter((r) => r.url.includes("/sessions/k1/timeline")).length;
  s.push("live", { key: "k1", type: "timeline", start: 0, entries: items(0, 3), usage: {} });
  await read();
  const before = timelines();
  s.push("live", { key: "k1", type: "timeline", start: 9, entries: ["e9"], usage: {} });
  s.push("session", { ...session("k1"), transcriptLength: 20 });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  await read();
  assert.equal(timelines(), before, "its holes and what its summary says are not read");
  assert.equal(core.inner.stations.link(ST)?.followsRunning, false);
  s.core.close();
});

test("a_core_started_again_takes_its_stations_up_from_the_last_event_kept_and_reads_nothing_again_when_told", async () => {
  for (const resumes of [true, false]) {
    const { host, core, streams, gate } = await started();
    gate.resumes = resumes;
    await host.settle();
    // An event with its id, as a station tells it: written down with what it changed.
    const open = streams.filter((s) => !s.closed).at(-1)!;
    const row = { id: "7", thread: 7, session: "k1", title: "部署", lastActiveAt: 1, agents: [] };
    Queue.offerUnsafe(open.queue, new TextEncoder().encode(`id: 1a.7\nevent: chat\ndata: ${JSON.stringify(row)}\n\n`));
    await host.settle();
    await run(core.inner.data.written);
    core.close();
    const before = host.requests.length;
    const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
    again.connect();
    await host.settle();
    await host.settle();
    const asked = host.requests.slice(before).map((r) => r.url.replace("https://stillfail.test/admin/api", "")).filter((u) => !u.startsWith("http"));
    assert.ok(asked.some((u) => u.startsWith("/events") && u.includes("since=1a.7")), JSON.stringify(asked));
    const lists = asked.filter((u) => ["/overview", "/chats", "/sessions", "/threads", "/jobs"].includes(u) || u.startsWith("/changed/"));
    // Told what came after it: nothing read again. Not told so (more than an hour later, the station started again):
    // everything is, as before.
    if (resumes) assert.deepEqual(lists, [], JSON.stringify(asked));
    else assert.ok(lists.includes("/overview"), JSON.stringify(asked));
    again.close();
  }
});

test("invalid_json_and_truncated_compression_fail_instead_of_becoming_empty_pages", async () => {
  const { core, host } = await started();
  const path = "/threads/7/entries?from=4&to=5";
  const call = () => core.inner.stations.requests.call(remote(), "GET", path, null);
  let response = { status: 200, headers: [] as [string, string][], body: new TextEncoder().encode('{"entries":[') };
  stationReplies(host, req => req.url.endsWith(path) ? new Raw(response) : undefined);
  try {
    assert.equal((await failure(call())).code, "bad_response");
    const encoded = zstdCompressSync(Buffer.from(JSON.stringify({ entries: entries(4, 5) })));
    response = { status: 200, headers: [["content-encoding", "zstd"]], body: encoded.subarray(0, encoded.length - 1) };
    await failure(call());
    response = { status: 200, headers: [], body: new TextEncoder().encode(JSON.stringify({ entries: entries(4, 5) })) };
    assert.deepEqual(await run(call()), { entries: entries(4, 5) }, "a fresh retry reads the intact reply");
    response = { status: 204, headers: [], body: new Uint8Array() };
    assert.deepEqual(await run(call()), {}, "intentional no-content replies remain valid");
  } finally { core.close(); }
});

/// A host that takes zstd apart itself (Host.unzstd: a native app's shell, libzstd), stood in for by fzstd: what each
/// piece makes, whole once all it took decompresses; how often one was opened, closed and pushed to.
function hostUnzstd(host: FakeHost) {
  const counts = { opened: 0, closed: 0, pushes: 0 };
  Object.assign(host, {
    unzstd: () =>
      Effect.acquireRelease(
        Effect.sync(() => {
          counts.opened++;
          const took: Uint8Array[] = [];
          const made: Uint8Array[] = [];
          const d = new Decompress((data) => made.push(data));
          return {
            push: (piece: Uint8Array) =>
              Effect.sync(() => {
                counts.pushes++;
                took.push(piece);
                d.push(piece);
                let whole = true;
                try {
                  zstdDecompressSync(concat(took));
                } catch {
                  whole = false;
                }
                return { bytes: concat(made.splice(0)), whole };
              }),
          };
        }),
        () => Effect.sync(() => void counts.closed++),
      ),
  });
  return counts;
}

test("a_host_that_takes_zstd_apart_itself_is_given_every_compressed_reply_and_a_cut_one_still_fails", async () => {
  let counts = { opened: 0, closed: 0, pushes: 0 };
  const { core, host } = await started(base(), 0, undefined, (s) => (counts = hostUnzstd(s.host)));
  const path = "/threads/7/entries?from=4&to=5";
  const call = () => core.inner.stations.requests.call(remote(), "GET", path, null);
  const encoded = zstdCompressSync(Buffer.from(JSON.stringify({ entries: entries(4, 5) })));
  let response = { status: 200, headers: [["content-encoding", "zstd"]] as [string, string][], body: new Uint8Array(encoded) };
  stationReplies(host, (req) => (req.url.endsWith(path) ? new Raw(response) : undefined));
  try {
    // (what the core read as it started, its stream among it, went through the host's)
    assert.ok(counts.pushes > 0, JSON.stringify(counts));
    const was = { ...counts };
    assert.deepEqual(await run(call()), { entries: entries(4, 5) });
    assert.ok(counts.pushes > was.pushes);
    response = { status: 200, headers: [["content-encoding", "zstd"]], body: encoded.subarray(0, encoded.length - 1) };
    await failure(call());
    // each let go once what read it is done, whole or failed
    assert.equal(counts.opened - was.opened, 2);
    assert.equal(counts.closed - was.closed, 2);
  } finally {
    core.close();
  }
});

test("a_partial_chat_page_keeps_the_reading_window_and_retries_through_the_core_call", async () => {
  const path = "GET /threads/7/entries?from=151&to=200";
  const replies: J = {
    ...base(),
    "GET /threads": [threadView(7, 300, 100, 200)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
    "GET /threads/7/entries?from=51&to=150": { last: 300, entries: entries(51, 150) },
    [path]: { last: 300, entries: entries(151, 175) },
  };
  const s = await ui(replies);
  try {
    subscribe(s.core, s.ui, 1, thread7);
    await s.read();
    assert.deepEqual(windowOf(s.values), [51, 150, false]);
    const newer = async (id: number) => {
      call(s.core, s.ui, id, "chat.newer", { station: ST, thread: 7 });
      await s.host.settle();
      const answer = s.host.emitted.map(([, m]) => m as J).find(m => m.id === id && ("ok" in m || "error" in m));
      assert.ok(answer, "the core answers the UI call");
      await s.read();
      return answer;
    };
    assert.equal((await newer(2)).error.code, "bad_response");
    assert.deepEqual(windowOf(s.values), [51, 150, false], "a partial reply does not advance the visible window");
    assert.equal(s.core.inner.data.logCount("entry", ST, "7", 151, 175), 25, "valid records from the failed page remain cached");
    replies[path] = { last: 300, entries: entries(151, 200) };
    assert.ok("ok" in await newer(3));
    assert.deepEqual(windowOf(s.values), [51, 200, false]);
    assert.deepEqual(nums(s.values), Array.from({ length: 150 }, (_, i) => i + 51), "retry fills the gap without losing or duplicating records");
  } finally { s.core.close(); }
});

test("json_requests_time_out_on_silent_heads_or_bodies_and_release_their_scope", async () => {
  for (const stalled of ["head", "body"]) {
    let closed = 0;
    class Silent extends HostWire {
      override request(...args: Parameters<HostWire["request"]>) {
        if (!args[1].path.endsWith("/silent-json")) return super.request(...args);
        return Effect.gen(function* () {
          yield* Effect.addFinalizer(() => Effect.sync(() => { closed++; }));
          if (stalled === "head") return yield* Effect.never;
          return { status: 200, headers: [] as [string, string][], via: null, body: { take: Effect.never } };
        });
      }
    }
    const { host, core } = await started(base(), 0, h => new Silent(h));
    try {
      const reading = core.inner.runner.run(Effect.result(core.inner.stations.requests.call(remote(), "GET", "/silent-json", null)));
      await host.time.pass(JSON_IDLE_MS + 100, 1000);
      const result = await reading;
      assert.equal(result._tag === "Failure" && result.failure.code, "timeout", stalled);
      assert.equal(closed, 1, stalled + ": the request scope closes on timeout");
    } finally { core.close(); }
  }
});

test("json_idle_timeout_resets_as_bytes_arrive_on_a_slow_link", async () => {
  class Slow extends HostWire {
    override request(...args: Parameters<HostWire["request"]>) {
      if (!args[1].path.endsWith("/slow-json")) return super.request(...args);
      let next = 0;
      const chunks = ['{"entries":', '[]', '}'];
      return Effect.succeed({ status: 200, headers: [] as [string, string][], via: null, body: {
        take: Effect.gen(function* () {
          if (next === chunks.length) return null;
          yield* Effect.sleep(JSON_IDLE_MS * 0.75);
          return new TextEncoder().encode(chunks[next++]!);
        }),
      } });
    }
  }
  const { host, core } = await started(base(), 0, h => new Slow(h));
  try {
    const reading = core.inner.runner.run(Effect.result(core.inner.stations.requests.call(remote(), "GET", "/slow-json", null)));
    await host.time.pass(JSON_IDLE_MS * 3, 1000);
    const result = await reading;
    assert.equal(result._tag, "Success");
    assert.deepEqual(result._tag === "Success" && result.success, { entries: [] });
  } finally { core.close(); }
});
