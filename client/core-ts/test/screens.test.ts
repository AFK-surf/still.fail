// A station's screens seen and driven (docs/remote-screens.md; src/screens.ts, src/screen-frames.ts): the `screens`
// topic from the station's GET /screens and its `screens` events, and a view's stream as a fake station answers it.
// What varies is how the station's bytes are cut on the way (each seed its own cuts; a failure names its seed, and
// SIM_SEED=<seed> runs it again); nothing waits for real time.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { linkTarget } from "../src/asks.ts";
import { parseCall } from "../src/core/calls.ts";
import { CoreError } from "../src/error.ts";
import { FrameReader, ackFrame, configFrame, inputFrame, keyframeFrame, readClientFrames, stateFrame, videoFrame, type ClientFrame, type StationFrame } from "../src/screen-frames.ts";
import { checkInput, othersOf } from "../src/screens.ts";
import { HostWire, type RequestHead, type ScreenAsk, type StationWire } from "../src/station/wire.ts";
import type { FakeHost } from "../src/testing.ts";
import { base64 } from "../src/util.ts";
import { apply, call, subscribe } from "./helpers.ts";
import { seeds } from "./sim-seeds.ts";
import { base, started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// Draws from a seed (xorshift): the same seed, the same cuts.
function random(seed: number): () => number {
  let s = seed * 2654435761 || 1;
  return () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return (s >>> 0) / 4294967296;
  };
}

/// Bytes cut into pieces of 1 byte up to a few KB, as a stream may bring them.
function cut(bytes: Uint8Array, draw: () => number): Uint8Array[] {
  const out: Uint8Array[] = [];
  for (let at = 0; at < bytes.length; ) {
    const n = 1 + Math.floor(draw() * (draw() < 0.3 ? 8 : 6000));
    out.push(bytes.slice(at, at + n));
    at += n;
  }
  return out;
}

function bytesOf(n: number, seed: number): Uint8Array {
  const out = new Uint8Array(n);
  const draw = random(seed + 7);
  for (let i = 0; i < n; i++) out[i] = Math.floor(draw() * 256);
  return out;
}

const join = (parts: Uint8Array[]) => new Uint8Array(Buffer.concat(parts));

function each(name: string, body: (seed: number) => Promise<void> | void) {
  test(name, async () => {
    for (const seed of seeds()) {
      try {
        await body(seed);
      } catch (e) {
        const error = e instanceof Error ? e : new Error(String(e));
        error.message = `seed ${seed} (SIM_SEED=${seed} runs it again):\n${error.message}`;
        throw error;
      }
    }
  });
}

// ── frames ──

each("a_views_frames_are_read_whole_however_the_stream_cuts_them", (seed) => {
  const avcc = bytesOf(40, seed);
  const frames = [
    configFrame({ codec: "h264", width: 1920, height: 1080, description: base64(avcc) }),
    videoFrame(true, 0, bytesOf(70_000, seed)),
    stateFrame({ cursor: { x: 0.5, y: 0.25, shape: "pointer" }, controlledBy: ["Bob"] }),
    videoFrame(false, 2 ** 40 + 33_333, bytesOf(3, seed + 1)),
    // A kind a later station may send: passed over.
    new Uint8Array([9, 0, 0, 0, 2, 1, 2]),
    configFrame({ codec: "jpeg", width: 800, height: 600 }),
    videoFrame(true, 2 ** 40 + 66_666, bytesOf(12_345, seed + 2)),
  ];
  const reader = new FrameReader();
  const read: StationFrame[] = [];
  for (const piece of cut(join(frames), random(seed))) {
    reader.push(piece);
    for (let f = reader.next(); f !== null; f = reader.next()) read.push(f);
  }
  assert.equal(read.length, 7);
  assert.deepEqual(read[0], { config: { codec: "h264", width: 1920, height: 1080, description: avcc } });
  const video = read[1] as Extract<StationFrame, { video: unknown }>;
  assert.deepEqual([video.video.key, video.video.ts, video.video.data], [true, 0, bytesOf(70_000, seed)]);
  // Each frame's bytes are an array of their own (what the web transfers to its page).
  assert.equal(video.video.data.byteOffset, 0);
  assert.equal(video.video.data.buffer.byteLength, 70_000);
  assert.deepEqual(read[2], { state: { cursor: { x: 0.5, y: 0.25, shape: "pointer" }, controlledBy: ["Bob"] } });
  assert.deepEqual(read[3], { video: { key: false, ts: 2 ** 40 + 33_333, data: bytesOf(3, seed + 1) } });
  assert.deepEqual(read[4], { other: 9 });
  assert.deepEqual(read[5], { config: { codec: "jpeg", width: 800, height: 600, description: null } });
  assert.equal((read[6] as J).video.ts, 2 ** 40 + 66_666);
});

test("what_a_client_sends_on_a_view_is_framed_as_the_station_reads_it", () => {
  const sent = join([inputFrame({ t: "text", text: "你好" }), ackFrame(2 ** 33 + 5), keyframeFrame()]);
  const [frames, rest] = readClientFrames(sent);
  assert.deepEqual(frames, [{ input: { t: "text", text: "你好" } }, { ack: 2 ** 33 + 5 }, { keyframe: true }]);
  assert.equal(rest.length, 0);
  assert.throws(() => {
    const r = new FrameReader();
    r.push(new Uint8Array([2, 0xff, 0xff, 0xff, 0xff]));
    r.next();
  }, /a frame of/);
});

test("a_persons_input_is_checked_and_put_in_the_frame", () => {
  assert.deepEqual(checkInput({ t: "pointer", kind: "down", x: 1.5, y: -0.1, buttons: 1, extra: true }), { t: "pointer", kind: "down", x: 1, y: 0, buttons: 1 });
  assert.deepEqual(checkInput({ t: "key", kind: "up", key: "Enter", code: "Enter", mods: 9 }), { t: "key", kind: "up", key: "Enter", code: "Enter", mods: 9 });
  assert.deepEqual(checkInput({ t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: -120 }), { t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: -120 });
  for (const bad of [null, { t: "pointer", kind: "drag", x: 0, y: 0 }, { t: "pointer", kind: "down", x: Number.NaN, y: 0 }, { t: "key", kind: "down", key: "" }, { t: "text", text: "" }, { t: "paste" }]) {
    assert.throws(() => checkInput(bad), (e: J) => e.code === "invalid_params");
  }
  assert.deepEqual(othersOf(["a@x.com", "Bob", "a@x.com", "Bob"], ["a@x.com"]), ["Bob", "a@x.com"], "one of the viewer's own is theirs; the others are another window");
  const view = parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", maxWidth: 99999, codecs: ["vp9", "jpeg"] }) as J;
  assert.deepEqual(view.call.ask, { maxWidth: 7680, maxHeight: 1080, codecs: ["jpeg"], control: true });
  assert.throws(() => parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", codecs: ["vp9"] }));
  assert.throws(() => parseCall("screen.control", { view: "v1" }));
});

test("a_screen_link_opens_the_screen", () => {
  const origin = "https://app.still.fail";
  assert.deepEqual(linkTarget("https://app.still.fail/w/ws1/s/st1/screen/browser%3AABC", origin), { opens: "screen", workspace: "ws1", station: "st1", screen: "browser:ABC" });
  assert.deepEqual(linkTarget("https://app.youdid.wtf/w/ws1/s/st1/screen/desktop", origin), { opens: "screen", workspace: "ws1", station: "st1", screen: "desktop" });
  assert.equal(linkTarget("https://app.still.fail/w/ws1/s/st1/screen/", origin), null);
});

// ── a station's views, faked ──

/// One view the fake station has open: what the client asked, what it sent, and the station's side of the stream.
type Viewing = { head: RequestHead; ask: ScreenAsk; got: ClientFrame[]; closed: boolean; send(bytes: Uint8Array): void; end(): void };

/// A wire whose requests go over the host's fetch (station-fixture.ts) and whose screen views a test drives: `answer`
/// says how the station answers each (200, or a status and its error).
function screenWire(seed: number) {
  const views: Viewing[] = [];
  const opts: { answer: (v: Viewing) => number | [number, string] } = { answer: () => 200 };
  const draw = random(seed);
  const make = (host: FakeHost): StationWire => {
    const plain = new HostWire(host);
    return {
      request: (s, head, body) => plain.request(s, head, body),
      screen: (_station, head, ask) =>
        Effect.gen(function* () {
          const queue = yield* Queue.unbounded<Uint8Array | null>();
          let carry: Uint8Array = new Uint8Array();
          const v: Viewing = {
            head,
            ask,
            got: [],
            closed: false,
            send: (bytes) => {
              for (const piece of cut(bytes, draw)) Queue.offerUnsafe(queue, piece);
            },
            end: () => void Queue.offerUnsafe(queue, null),
          };
          views.push(v);
          yield* Effect.addFinalizer(() => Effect.sync(() => (v.closed = true)));
          const said = opts.answer(v);
          const code = typeof said === "number" ? said : said[0];
          if (code !== 200) v.send(new TextEncoder().encode(JSON.stringify({ error: typeof said === "number" ? "no" : said[1] })));
          if (code !== 200) v.end();
          return {
            reply: { status: code, headers: [["content-type", "application/x-stillfail-screen"]] as [string, string][], body: { take: Queue.take(queue) }, via: null },
            send: {
              write: (bytes: Uint8Array) =>
                Effect.sync(() => {
                  const [frames, rest] = readClientFrames(join([carry, bytes]));
                  carry = rest;
                  v.got.push(...frames);
                }),
              finish: () => {},
            },
          };
        }),
    };
  };
  return { views, opts, make };
}

const SCREENS = { screens: [{ id: "desktop", kind: "desktop", title: "studio 的桌面", width: 3024, height: 1964, viewers: [] }, { id: "browser:T1", kind: "browser", title: "登录 - GitHub", width: 1280, height: 800, viewers: ["Bob"] }] };

/// What the core said to the UI: each message under `id`, in order.
function said(host: FakeHost, log: J[]): void {
  for (const [, m] of host.takeEmitted()) log.push(m);
}
const states = (log: J[], id: number) => log.filter((m) => m.id === id && m.value?.state).map((m) => m.value.state);
const lastState = (log: J[], id: number) => states(log, id).at(-1);

async function viewing(seed: number, answers: Record<string, unknown> = { ...base(), "GET /screens": SCREENS }, role?: string) {
  const wire = screenWire(seed);
  const s = await started(answers, 0, wire.make, (st) => {
    if (role) st.cloud.role = role;
  });
  const ui = s.core.connect();
  return { ...s, ...wire, ui };
}

each("a_stations_screens_are_listed_and_kept_as_its_events_say", async (seed) => {
  const { host, core, ui, push } = await viewing(seed);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screens", station: "ws/st" });
  await host.settle();
  apply(host, values);
  const v = values.get(1) as J;
  assert.equal(v.known, true);
  assert.equal(v.control, true);
  assert.deepEqual(v.screens.map((x: J) => [x.id, x.kind, x.title, x.link]), [
    ["desktop", "desktop", "studio 的桌面", "/w/ws/s/st/screen/desktop"],
    ["browser:T1", "browser", "登录 - GitHub", "/w/ws/s/st/screen/browser%3AT1"],
  ]);
  assert.equal(v.screens[1].line, "浏览器标签页 · 1280×800 · Bob 在看");
  push("screens", { screens: [{ ...SCREENS.screens[0], viewers: ["Bob", "Carol", "Dan"] }] });
  await host.settle();
  apply(host, values);
  const after = values.get(1) as J;
  assert.equal(after.screens.length, 1);
  assert.equal(after.screens[0].line, "桌面 · 3024×1964 · Bob、Carol 等 1 人 在看");
  core.close();
});

test("a_station_from_before_screens_has_none_and_needs_an_update", async () => {
  const answers = base();
  const { host, core, ui, views } = await viewing(1, answers);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screens", station: "ws/st" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(values.get(1), { screens: [], outdated: true, control: true, known: true, note: "这台 station 需要更新才能远程看屏幕" });
  // Its link opens the viewer, which says so at once: no stream is opened (such a station would never answer one).
  const log: J[] = [];
  call(core, ui, 2, "screen.view", { station: "ws/st", screen: "desktop", view: "v" });
  await host.settle();
  said(host, log);
  assert.equal(views.length, 0);
  assert.equal(lastState(log, 2).phase, "outdated");
  assert.deepEqual(log.find((m) => m.id === 2 && "ok" in m), { id: 2, ok: null });
  core.close();
});

each("a_view_brings_its_frames_with_their_bytes_and_takes_acks_key_frames_and_input", async (seed) => {
  const { host, core, ui, views } = await viewing(seed);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v", maxWidth: 1280, maxHeight: 720, codecs: ["h264", "jpeg"] });
  await host.settle();
  assert.equal(views.length, 1);
  const [v] = views;
  assert.equal(v!.head.method, "POST");
  assert.equal(v!.head.path, "/admin/api/screens/desktop/view");
  assert.deepEqual(v!.ask, { maxWidth: 1280, maxHeight: 720, codecs: ["h264", "jpeg"], control: true });
  const avcc = bytesOf(38, seed);
  const key = bytesOf(150_000, seed);
  const delta = bytesOf(900, seed + 1);
  v!.send(join([configFrame({ codec: "h264", width: 1280, height: 720, description: base64(avcc) }), videoFrame(true, 1_000, key), videoFrame(false, 34_333, delta)]));
  await host.settle();
  said(host, log);
  const config = log.find((m) => m.id === 1 && m.value?.config);
  assert.deepEqual(config.value, { config: { codec: "h264", width: 1280, height: 720 } });
  assert.deepEqual(config.bytes, avcc);
  const frames = log.filter((m) => m.id === 1 && m.value?.frame);
  assert.deepEqual(frames.map((m) => m.value.frame), [{ key: true, ts: 1_000 }, { key: false, ts: 34_333 }]);
  assert.deepEqual(frames[0].bytes, key);
  assert.deepEqual(frames[1].bytes, delta);
  const live = lastState(log, 1);
  assert.deepEqual([live.phase, live.control, live.may, live.width, live.height, live.codec, live.title, live.line], ["live", true, true, 1280, 720, "h264", "studio 的桌面", "控制"]);
  // What the page sends goes on the stream, in order.
  call(core, ui, 2, "screen.ack", { view: "v", ts: 1_000 });
  call(core, ui, 3, "screen.input", { view: "v", input: { t: "pointer", kind: "down", x: 0.25, y: 0.5, buttons: 1 } });
  call(core, ui, 4, "screen.input", { view: "v", input: { t: "pointer", kind: "up", x: 0.25, y: 0.5, buttons: 0 } });
  call(core, ui, 5, "screen.keyframe", { view: "v" });
  call(core, ui, 6, "screen.ack", { view: "v", ts: 34_333 });
  await host.settle();
  assert.deepEqual(v!.got, [
    { ack: 1_000 },
    { input: { t: "pointer", kind: "down", x: 0.25, y: 0.5, buttons: 1 } },
    { input: { t: "pointer", kind: "up", x: 0.25, y: 0.5, buttons: 0 } },
    { keyframe: true },
    { ack: 34_333 },
  ]);
  // Who else is on it, the viewer left out; the pointer as the station draws it.
  v!.send(stateFrame({ controlledBy: ["a@x.com", "Bob"], cursor: { x: 0.1, y: 0.2, shape: "text" } }));
  await host.settle();
  said(host, log);
  const now = lastState(log, 1);
  assert.deepEqual([now.others, now.line, now.cursor], [["Bob"], "控制 · Bob 也在看", { x: 0.1, y: 0.2, shape: "text" }]);
  // The page goes: the stream closes.
  core.receive(ui, { kind: "cancel", id: 1, cancel: true });
  await host.settle();
  assert.equal(v!.closed, true);
  core.close();
});

each("only_looking_is_opened_again_without_control_and_takes_no_input", async (seed) => {
  const { host, core, ui, views } = await viewing(seed);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v" });
  await host.settle();
  views[0]!.send(join([configFrame({ codec: "jpeg", width: 640, height: 480 }), videoFrame(true, 1, bytesOf(500, seed))]));
  await host.settle();
  call(core, ui, 2, "screen.control", { view: "v", control: false });
  await host.settle();
  assert.equal(views.length, 2, "opened again");
  assert.equal(views[0]!.closed, true);
  assert.equal(views[1]!.ask.control, false);
  call(core, ui, 3, "screen.input", { view: "v", input: { t: "text", text: "x" } });
  call(core, ui, 4, "screen.ack", { view: "v", ts: 1 });
  await host.settle();
  assert.deepEqual(views[1]!.got, [{ ack: 1 }], "no input while only looking");
  said(host, log);
  const watch = lastState(log, 1);
  assert.deepEqual([watch.phase, watch.control, watch.line], ["live", false, "只看"], "the last frame stays: no connecting in between");
  const all = states(log, 1);
  assert.equal(all.slice(all.findIndex((s: J) => s.phase === "live")).some((s: J) => s.phase !== "live"), false);
  core.close();
});

each("a_read_only_member_only_looks", async (seed) => {
  const { host, core, ui, views } = await viewing(seed, undefined, "viewer");
  const log: J[] = [];
  subscribe(core, ui, 9, { topic: "screens", station: "ws/st" });
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v", control: true });
  await host.settle();
  said(host, log);
  assert.equal(log.filter((m) => m.id === 9 && "value" in m).at(-1).value.control, false);
  assert.equal(views[0]!.ask.control, false);
  call(core, ui, 2, "screen.control", { view: "v", control: true });
  call(core, ui, 3, "screen.input", { view: "v", input: { t: "text", text: "x" } });
  await host.settle();
  said(host, log);
  assert.equal(views.length, 1);
  assert.deepEqual(views[0]!.got, []);
  const s = lastState(log, 1);
  assert.deepEqual([s.may, s.control, s.line], [false, false, "只看"]);
  core.close();
});

each("a_view_that_drops_is_opened_again_and_one_the_station_ends_says_why", async (seed) => {
  const { host, core, ui, views } = await viewing(seed);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "browser:T1", view: "v" });
  await host.settle();
  views[0]!.send(join([configFrame({ codec: "jpeg", width: 1280, height: 800 }), videoFrame(true, 5, bytesOf(800, seed))]));
  await host.settle();
  views[0]!.end();
  await host.settle();
  said(host, log);
  assert.equal(lastState(log, 1).phase, "reconnecting");
  await host.time.pass(1_000);
  assert.equal(views.length, 2, "opened again after a while");
  views[1]!.send(videoFrame(true, 6, bytesOf(800, seed + 3)));
  await host.settle();
  said(host, log);
  assert.equal(lastState(log, 1).phase, "live");
  views[1]!.send(stateFrame({ ended: "标签页关了" }));
  await host.settle();
  said(host, log);
  const ended = lastState(log, 1);
  assert.deepEqual([ended.phase, ended.message], ["ended", "标签页关了"]);
  assert.deepEqual(log.find((m) => m.id === 1 && "ok" in m), { id: 1, ok: null });
  core.close();
});

test("a_view_refused_says_why_and_is_not_tried_again", async () => {
  const cases: [number | [number, string], string, string][] = [
    [[404, "no screen browser:T9"], "gone", "这个屏幕已经不在了"],
    [[404, "no route POST /screens/x/view"], "outdated", "这台 station 需要更新才能远程看屏幕"],
    [[403, "没有屏幕录制权限"], "denied", "没有屏幕录制权限"],
    [[409, "这台机器没有显示器"], "denied", "这台机器没有显示器"],
  ];
  for (const [answer, phase, message] of cases) {
    const { host, core, ui, views, opts } = await viewing(1);
    opts.answer = () => answer;
    const log: J[] = [];
    call(core, ui, 1, "screen.view", { station: "ws/st", screen: "browser:T9", view: "v" });
    await host.settle();
    await host.time.pass(60_000);
    said(host, log);
    const s = lastState(log, 1);
    assert.deepEqual([s.phase, s.message], [phase, message], JSON.stringify(answer));
    assert.equal(views.length, 1, "not tried again");
    assert.deepEqual(log.find((m) => m.id === 1 && "ok" in m), { id: 1, ok: null });
    core.close();
  }
});

test("a_view_the_station_cannot_open_now_is_tried_again_then_given_up", async () => {
  // The link is there but every open fails on the way (no status): tried again with growing waits, then failed.
  let opens = 0;
  const { host, core } = await started({ ...base(), "GET /screens": SCREENS }, 0, (h) => ({
    request: (s, head, body) => new HostWire(h).request(s, head, body),
    screen: () =>
      Effect.suspend(() => {
        opens++;
        return Effect.fail(new CoreError("mesh", "cut"));
      }),
  }));
  const ui = core.connect();
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v" });
  await host.time.pass(120_000, 100);
  said(host, log);
  assert.equal(opens, 8);
  assert.deepEqual(states(log, 1).map((s: J) => s.phase).filter((p: string, i: number, a: string[]) => p !== a[i - 1]), ["connecting", "reconnecting", "failed"]);
  core.close();
});

test("acks_after_a_view_went_are_let_go_and_input_to_none_is_refused", async () => {
  const { host, core, ui } = await viewing(1);
  const log: J[] = [];
  call(core, ui, 1, "screen.ack", { view: "gone", ts: 1 });
  call(core, ui, 2, "screen.input", { view: "gone", input: { t: "text", text: "x" } });
  call(core, ui, 3, "screen.view", { station: "ws/st", screen: "desktop", view: "v" });
  call(core, ui, 4, "screen.view", { station: "ws/st", screen: "desktop", view: "v" });
  await host.settle();
  said(host, log);
  assert.deepEqual(log.find((m) => m.id === 1), { id: 1, ok: null });
  assert.equal(log.find((m) => m.id === 2).error.code, "not_found");
  assert.equal(log.find((m) => m.id === 4).error.code, "invalid_params", "one view of a name at a time");
  core.close();
});

