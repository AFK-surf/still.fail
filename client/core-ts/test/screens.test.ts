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
import { CLIP_PNG_MAX, CLIP_TEXT_MAX, FrameReader, ackFrame, clipboardFrame, configFrame, copiedFrame, inputFrame, keyframeFrame, lookFrame, readClientFrames, stateFrame, videoFrame, type ClientFrame, type StationFrame } from "../src/screen-frames.ts";
import { LOOK_MS, checkInput, othersOf } from "../src/screens.ts";
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
  assert.deepEqual(read[0], { config: { codec: "h264", width: 1920, height: 1080, description: avcc, region: null } });
  const video = read[1] as Extract<StationFrame, { video: unknown }>;
  assert.deepEqual([video.video.key, video.video.ts, video.video.data], [true, 0, bytesOf(70_000, seed)]);
  // Each frame's bytes are an array of their own (what the web transfers to its page).
  assert.equal(video.video.data.byteOffset, 0);
  assert.equal(video.video.data.buffer.byteLength, 70_000);
  assert.deepEqual(read[2], { state: { cursor: { x: 0.5, y: 0.25, shape: "pointer" }, controlledBy: ["Bob"] } });
  assert.deepEqual(read[3], { video: { key: false, ts: 2 ** 40 + 33_333, data: bytesOf(3, seed + 1) } });
  assert.deepEqual(read[4], { other: 9 });
  assert.deepEqual(read[5], { config: { codec: "jpeg", width: 800, height: 600, description: null, region: null } });
  assert.equal((read[6] as J).video.ts, 2 ** 40 + 66_666);
});

test("what_a_client_sends_on_a_view_is_framed_as_the_station_reads_it", () => {
  const sent = join([inputFrame({ t: "text", text: "你好" }), ackFrame(2 ** 33 + 5), keyframeFrame(), lookFrame({ x: 0.5, y: 0, w: 0.5, h: 0.25 }, 1200, 300), lookFrame(null, 0, 0)]);
  const [frames, rest] = readClientFrames(sent);
  assert.deepEqual(frames, [{ input: { t: "text", text: "你好" } }, { ack: 2 ** 33 + 5 }, { keyframe: true }, { look: { region: { x: 0.5, y: 0, w: 0.5, h: 0.25 }, maxWidth: 1200, maxHeight: 300 } }, { look: { region: null } }]);
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
  assert.equal(view.call.auto, true, "no mode asked: decided as it opens");
  assert.equal((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", control: true }) as J).call.auto, false);
  assert.throws(() => parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", codecs: ["vp9"] }));
  // H.265 only from a UI that says it decodes it; none said: what every client decodes.
  assert.deepEqual((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", codecs: ["h265", "h264", "jpeg"] }) as J).call.ask.codecs, ["h265", "h264", "jpeg"]);
  assert.deepEqual((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1" }) as J).call.ask.codecs, ["h264", "jpeg"]);
  assert.throws(() => parseCall("screen.control", { view: "v1" }));
  assert.deepEqual((parseCall("screen.bounds", { view: "v1", maxWidth: 99999, maxHeight: 720.4 }) as J).call, { kind: "bounds", view: "v1", maxWidth: 7680, maxHeight: 720, quality: null, fps: null });
  // With the 画质 and 帧率 chosen (one not offered: none, 自动).
  assert.deepEqual((parseCall("screen.bounds", { view: "v1", maxWidth: 1280, maxHeight: 720, quality: "hd", fps: 30 }) as J).call, { kind: "bounds", view: "v1", maxWidth: 1280, maxHeight: 720, quality: "hd", fps: 30 });
  assert.equal((parseCall("screen.bounds", { view: "v1", maxWidth: 1280, maxHeight: 720, fps: 45 }) as J).call.fps, null);
  for (const bad of [{ view: "v1", maxWidth: 1280 }, { view: "v1", maxWidth: 0, maxHeight: 720 }, { maxWidth: 1280, maxHeight: 720 }]) assert.throws(() => parseCall("screen.bounds", bad), JSON.stringify(bad));
  // The stage a phone shows it on goes with it (a tab of the station's browser is laid out for it); not a preview's.
  const fit = { width: 389.6, height: 701, scale: 3 };
  assert.deepEqual((parseCall("screen.view", { station: "ws/st", screen: "browser:T1", view: "v1", codecs: ["jpeg"], fit }) as J).call.ask.fit, { width: 390, height: 701, scale: 3 });
  assert.equal((parseCall("screen.view", { station: "ws/st", screen: "browser:T1", view: "v1", codecs: ["jpeg"], fit, peek: true }) as J).call.ask.fit, undefined);
  for (const bad of [{ ...fit, width: 0 }, { ...fit, scale: "3" }, null]) assert.equal((parseCall("screen.view", { station: "ws/st", screen: "browser:T1", view: "v1", fit: bad }) as J).call.ask.fit, undefined, JSON.stringify(bad));
  // The 画质 chosen goes to the station (how high the bit rate goes); none for 自动, a preview or one not known.
  assert.equal((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", quality: "original" }) as J).call.ask.quality, "original");
  for (const quality of [undefined, "best", 3]) assert.equal("quality" in (parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", quality }) as J).call.ask, false, String(quality));
  assert.equal((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", quality: "hd", peek: true }) as J).call.ask.quality, undefined);
  assert.equal((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", gamut: "p3" }) as J).call.ask.gamut, "p3");
  for (const gamut of [undefined, "srgb", 1]) assert.equal("gamut" in (parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", gamut }) as J).call.ask, false, String(gamut));
  // The 帧率 chosen goes to the station (the most frames a second); none for 自动, a preview or one not offered.
  for (const fps of [120, 90, 60, 30, 15]) assert.equal((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", fps }) as J).call.ask.fps, fps);
  for (const fps of [undefined, 0, 45, 240, "60"]) assert.equal("fps" in (parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", fps }) as J).call.ask, false, String(fps));
  assert.equal((parseCall("screen.view", { station: "ws/st", screen: "desktop", view: "v1", fps: 30, peek: true }) as J).call.ask.fps, undefined);
});

test("a_screen_link_opens_the_screen", () => {
  const origin = "https://app.still.fail";
  assert.deepEqual(linkTarget("https://app.still.fail/w/ws1/s/st1/screen/browser%3AABC", origin), { opens: "screen", workspace: "ws1", station: "st1", screen: "browser:ABC" });
  assert.deepEqual(linkTarget("https://app.youdid.wtf/w/ws1/s/st1/screen/desktop", origin), { opens: "screen", workspace: "ws1", station: "st1", screen: "desktop" });
  assert.equal(linkTarget("https://app.still.fail/w/ws1/s/st1/screen/", origin), null);
});

// ── a station's views, faked ──

/// One view the fake station has open: what the client asked, what it sent, and the station's side of the stream.
/// `alongside`: how many of the others were still open as it opened.
type Viewing = { head: RequestHead; ask: ScreenAsk; got: ClientFrame[]; closed: boolean; alongside: number; tapped?: number; send(bytes: Uint8Array): void; end(): void };

/// A wire whose requests go over the host's fetch (station-fixture.ts) and whose screen views a test drives: `answer`
/// says how the station answers each (200, or a status and its error).
function screenWire(seed: number) {
  const views: Viewing[] = [];
  // `tap`: the host reads the picture and sound itself (IrohStream.tap, Apple's shell), the core only the rest
  const opts: { answer: (v: Viewing) => number | [number, string]; tap?: boolean } = { answer: () => 200 };
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
            alongside: views.filter((o) => !o.closed).length,
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
            ...(opts.tap ? { tap: (call: number) => Effect.sync(() => ((v.tapped = call), true)) } : {}),
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
  assert.equal(v.screens[1].line, "浏览器标签页 · 1280×800 · Bob 正在查看");
  push("screens", { screens: [{ ...SCREENS.screens[0], viewers: ["Bob", "Carol", "Dan"] }] });
  await host.settle();
  apply(host, values);
  const after = values.get(1) as J;
  assert.equal(after.screens.length, 1);
  assert.equal(after.screens[0].line, "桌面 · 3024×1964 · Bob、Carol 等 1 人 正在查看");
  // A grant missing: its row says what cannot be done now, in a line; the station's message (where to grant it) is
  // its view's.
  const message = "这台 Mac 尚未允许 still.fail Helper 录制屏幕。打开画面时，那台 Mac 上会弹出授权窗口。";
  for (const [capture, control, line] of [[true, false, "当前不可用：远程控制屏幕"], [false, false, "当前不可用：远程查看屏幕、远程控制屏幕"]] as const) {
    push("screens", { screens: [{ ...SCREENS.screens[0], access: { capture, control, message, app: "still.fail Helper" } }] });
    await host.settle();
    apply(host, values);
    const lacks = (values.get(1) as J).screens[0];
    assert.equal(lacks.line, line);
    assert.equal(lacks.access.message, message);
  }
  core.close();
});

test("a_tab_says_the_chat_that_opened_it_and_is_closed_by_a_member_not_a_reader", async () => {
  const answers = { ...base(), "GET /screens": { screens: [SCREENS.screens[0], { ...SCREENS.screens[1], viewers: [], closable: true, openedBy: "k1" }, { id: "browser:T2", kind: "browser", title: "x", width: 0, height: 0, closable: true, openedBy: "gone" }] }, "POST /screens/browser%3AT1/close": {} };
  const { host, core, ui } = await viewing(1, answers);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screens", station: "ws/st" });
  await host.settle();
  apply(host, values);
  const [desktop, tab, other] = (values.get(1) as J).screens;
  assert.equal(desktop.closable, false, "the desktop is not closed from here");
  assert.equal(tab.closable, true);
  assert.deepEqual(tab.chat, { id: "7", title: "部署", link: "/w/ws/s/st/chats/7" });
  assert.equal(tab.line, "浏览器标签页 · 1280×800 · 由「部署」打开");
  assert.equal(other.chat, undefined, "a session none of the viewer's chats has");
  call(core, ui, 2, "screen.close", { station: "ws/st", screen: "browser:T1" });
  await host.settle();
  assert.ok(host.requests.some((r: J) => r.method === "POST" && String(r.url).endsWith("/screens/browser%3AT1/close")));
  core.close();

  // A read-only member only looks: nothing to close.
  const reader = await viewing(1, answers, "viewer");
  const seen = new Map<number, unknown>();
  subscribe(reader.core, reader.ui, 1, { topic: "screens", station: "ws/st" });
  await reader.host.settle();
  apply(reader.host, seen);
  assert.equal((seen.get(1) as J).screens[1].closable, false);
  reader.core.close();
});

each("a_link_to_a_screen_shows_it_as_its_list_has_it_and_as_gone_once_the_list_has_it_no_more", async (seed) => {
  const { host, core, ui, push } = await viewing(seed);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screenCard", station: "ws/st", screen: "browser:T1" });
  subscribe(core, ui, 2, { topic: "screenCard", station: "ws/st", screen: "browser:CLOSED" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(values.get(1), { kind: "browser", title: "登录 - GitHub", line: "浏览器标签页 · 1280×800 · Bob 正在查看", link: "/w/ws/s/st/screen/browser%3AT1", gone: false, peek: false, width: 1280, height: 800 });
  assert.deepEqual(values.get(2), { kind: "browser", title: "浏览器标签页", line: "此屏幕已不存在", link: "/w/ws/s/st/screen/browser%3ACLOSED", gone: true, peek: false, width: 0, height: 0 });
  push("screens", { screens: [SCREENS.screens[0]] });
  await host.settle();
  apply(host, values);
  assert.equal((values.get(1) as J).gone, true);
  core.close();
});

test("a_link_to_a_screen_of_a_station_not_reached_says_what_its_id_does", async () => {
  const { host, core, ui } = await viewing(1);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screenCard", station: "ws/elsewhere", screen: "desktop" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(values.get(1), { kind: "desktop", title: "桌面", line: "远程屏幕", link: "/w/ws/s/elsewhere/screen/desktop", gone: false, peek: false, width: 0, height: 0 });
  core.close();
});

test("the_machines_own_display_is_listed_first_and_a_screen_an_agent_drives_says_so", async () => {
  const tab = { id: "browser:T1", kind: "browser", title: "登录 - GitHub", width: 1280, height: 800, viewers: ["Bob", "agent: 部署"], controlledBy: ["agent: 部署"] };
  const desktop = { id: "desktop", kind: "desktop", title: "studio 的桌面", width: 3024, height: 1964, viewers: ["Bob"], controlledBy: ["Bob"] };
  const { host, core, ui } = await viewing(1, { ...base(), "GET /screens": { screens: [tab, desktop] } });
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screens", station: "ws/st" });
  await host.settle();
  apply(host, values);
  const v = values.get(1) as J;
  assert.deepEqual(v.screens.map((x: J) => [x.id, x.agent === true]), [["desktop", false], ["browser:T1", true]]);
  core.close();
});

each("a_chat_says_the_screens_of_its_station_for_its_bar_and_which_an_agent_drives", async (seed) => {
  const { host, core, ui, push } = await viewing(seed);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7, session: null });
  await host.settle();
  apply(host, values);
  assert.deepEqual((values.get(1) as J).screens.map((s: J) => [s.id, s.title, s.agent === true]), [
    ["desktop", "studio 的桌面", false],
    ["browser:T1", "登录 - GitHub", false],
  ]);
  // An agent takes the tab: said so as the station tells it; the station's screens gone, none.
  push("screens", { screens: [SCREENS.screens[0], { ...SCREENS.screens[1], controlledBy: ["agent: 部署"] }] });
  // (the screens' value, then the chat's built from it: a window each)
  await host.settle();
  await host.settle();
  apply(host, values);
  assert.deepEqual((values.get(1) as J).screens.map((s: J) => s.agent === true), [false, true]);
  push("screens", { screens: [] });
  await host.settle();
  await host.settle();
  apply(host, values);
  assert.deepEqual((values.get(1) as J).screens ?? [], []);
  core.close();
});

test("a_simulator_is_listed_and_linked_as_one_and_a_kind_not_known_as_a_display", async () => {
  const sim = { id: "simulator:5A25EA86-3568-43D6-9068-8B2CB5FADB26", kind: "simulator", title: "iPhone 17 · iOS 26.2", width: 1206, height: 2622, viewers: [], peek: true };
  const answers = { ...base(), "GET /screens": { screens: [sim, { id: "later:1", kind: "something-later", title: "", width: 0, height: 0, viewers: [] }] } };
  const { host, core, ui } = await viewing(1, answers);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screens", station: "ws/st" });
  subscribe(core, ui, 2, { topic: "screenCard", station: "ws/elsewhere", screen: sim.id });
  await host.settle();
  apply(host, values);
  const v = values.get(1) as J;
  assert.deepEqual(v.screens.map((x: J) => [x.kind, x.title, x.line]), [
    ["simulator", "iPhone 17 · iOS 26.2", "iOS 模拟器 · 1206×2622"],
    ["desktop", "桌面", "桌面"],
  ]);
  assert.equal(v.screens[0].peek, true);
  assert.deepEqual(values.get(2), { kind: "simulator", title: "iOS 模拟器", line: "远程屏幕", link: "/w/ws/s/elsewhere/screen/simulator%3A5A25EA86-3568-43D6-9068-8B2CB5FADB26", gone: false, peek: false, width: 0, height: 0 });
  core.close();
});

test("a_preview_only_looks_and_is_asked_only_of_a_screen_its_station_says_can_be_previewed", async () => {
  const answers = { ...base(), "GET /screens": { screens: [SCREENS.screens[0], { ...SCREENS.screens[1], peek: true }] } };
  const { host, core, ui, views } = await viewing(1, answers);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screenCard", station: "ws/st", screen: "browser:T1" });
  await host.settle();
  apply(host, values);
  assert.equal((values.get(1) as J).peek, true);
  const log: J[] = [];
  call(core, ui, 2, "screen.view", { station: "ws/st", screen: "browser:T1", view: "card", maxWidth: 480, maxHeight: 300, codecs: ["jpeg"], peek: true, control: true });
  await host.settle();
  assert.equal(views.length, 1);
  assert.deepEqual(views[0]!.ask, { maxWidth: 480, maxHeight: 300, codecs: ["jpeg"], control: false, peek: true });
  // The desktop is not said to be previewable (its view wakes its display): asked as a preview, no stream is opened.
  call(core, ui, 3, "screen.view", { station: "ws/st", screen: "desktop", view: "card2", codecs: ["jpeg"], peek: true });
  await host.settle();
  said(host, log);
  assert.equal(views.length, 1);
  assert.equal(lastState(log, 3).phase, "denied");
  core.close();
});

test("a_station_from_before_screens_has_none_and_needs_an_update", async () => {
  const answers = base();
  const { host, core, ui, views } = await viewing(1, answers);
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "screens", station: "ws/st" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(values.get(1), { screens: [], outdated: true, control: true, known: true, note: "此 station 需要更新才能远程查看屏幕" });
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

each("a_view_its_host_reads_says_none_of_its_picture_and_is_live_by_the_head_it_is_left", async (seed) => {
  const { host, core, ui, views, opts } = await viewing(seed);
  opts.tap = true;
  const log: J[] = [];
  call(core, ui, 7, "screen.view", { station: "ws/st", screen: "desktop", view: "v", maxWidth: 1280, maxHeight: 720, codecs: ["h264", "jpeg"] });
  await host.settle();
  const [v] = views;
  assert.equal(v!.tapped, 7);
  // what the host leaves the core: the config, a video frame's head without its picture
  v!.send(join([configFrame({ codec: "h264", width: 1280, height: 720, description: base64(bytesOf(38, seed)) }), videoFrame(true, 1_000, new Uint8Array(0))]));
  await host.settle();
  said(host, log);
  assert.equal(log.filter((m) => m.id === 7 && (m.value?.config || m.value?.frame)).length, 0, "said by the host, not again");
  const live = lastState(log, 7);
  assert.deepEqual([live.phase, live.width, live.height, live.codec], ["live", 1280, 720, "h264"]);
  // acks still go on the stream
  call(core, ui, 8, "screen.ack", { view: "v", ts: 1_000 });
  await host.settle();
  assert.deepEqual(v!.got, [{ ack: 1_000 }]);
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
  v!.send(stateFrame({ viewers: ["a@x.com", "Bob"], controlledBy: ["a@x.com"], cursor: { x: 0.1, y: 0.2, shape: "text" } }));
  await host.settle();
  said(host, log);
  const now = lastState(log, 1);
  assert.deepEqual([now.others, now.line, now.cursor], [["Bob"], "控制 · Bob 也在查看", { x: 0.1, y: 0.2, shape: "text" }]);
  assert.equal(now.scale, undefined, "a station that says no scale: none");
  // How late its frames are, as the station measures them.
  v!.send(stateFrame({ latency: { frame: 87, before: 12 } }));
  await host.settle();
  said(host, log);
  assert.deepEqual(lastState(log, 1).latency, { frame: 87, before: 12 });
  // How its pictures are made, as the station says it.
  v!.send(stateFrame({ video: { capture: "ScreenCaptureKit", encoder: "hardware, low latency, HEVC_Main_AutoLevel", hardware: true } }));
  await host.settle();
  said(host, log);
  assert.deepEqual(lastState(log, 1).video, { capture: "ScreenCaptureKit", encoder: "hardware, low latency, HEVC_Main_AutoLevel", hardware: true });
  // Its display's scale, as the station says it, to a view that drives it; set with the input it takes.
  const steps = [100, 125, 150, 175, 200];
  v!.send(stateFrame({ scale: { percent: 200, recommended: 150, steps } }));
  await host.settle();
  said(host, log);
  assert.deepEqual(lastState(log, 1).scale, { percent: 200, recommended: 150, steps });
  call(core, ui, 7, "screen.input", { view: "v", input: { t: "scale", percent: 150 } });
  await host.settle();
  assert.deepEqual(v!.got.at(-1), { input: { t: "scale", percent: 150 } });
  // Not a scale: told as any bad input is.
  call(core, ui, 8, "screen.input", { view: "v", input: { t: "scale", percent: 99 } });
  await host.settle();
  said(host, log);
  assert.equal(log.find((m) => m.id === 8)?.error?.code, "invalid_params");
  // Its display's resolution likewise: said to a view that drives it, set with the input it takes.
  const modes = [{ width: 2560, height: 1440 }, { width: 1920, height: 1080 }];
  v!.send(stateFrame({ resolution: { width: 2560, height: 1440, modes } }));
  await host.settle();
  said(host, log);
  assert.deepEqual(lastState(log, 1).resolution, { width: 2560, height: 1440, modes });
  call(core, ui, 9, "screen.input", { view: "v", input: { t: "resolution", width: 1920, height: 1080 } });
  await host.settle();
  assert.deepEqual(v!.got.at(-1), { input: { t: "resolution", width: 1920, height: 1080 } });
  call(core, ui, 10, "screen.input", { view: "v", input: { t: "resolution", width: 1920.5, height: 1080 } });
  await host.settle();
  said(host, log);
  assert.equal(log.find((m) => m.id === 10)?.error?.code, "invalid_params");
  // The page goes: the stream closes.
  core.receive(ui, { kind: "cancel", id: 1, cancel: true });
  await host.settle();
  assert.equal(v!.closed, true);
  core.close();
});

each("zoomed_in_the_part_looked_at_is_asked_once_it_settles_and_its_frames_say_the_part", async (seed) => {
  const { host, core, ui, views } = await viewing(seed);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v", maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] });
  await host.settle();
  const avcc = bytesOf(38, seed);
  views[0]!.send(join([configFrame({ codec: "h264", width: 1920, height: 1080, description: base64(avcc) }), videoFrame(true, 1_000, bytesOf(900, seed))]));
  await host.settle();
  // A pinch: a look each step of it; asked once, as it settles, no larger than the view asked for the whole screen.
  const look = (id: number, region: J, width = 2400, height = 1080) => call(core, ui, id, "screen.look", { view: "v", region, width, height });
  look(2, { x: 0.1, y: 0.1, w: 0.8, h: 0.8 });
  await host.time.pass(100);
  look(3, { x: 0.3, y: 0.2, w: 0.5, h: 0.5 });
  await host.time.pass(100);
  look(4, { x: 0.4, y: 0.25, w: 0.333333, h: 0.333333 });
  await host.time.pass(LOOK_MS - 1);
  assert.deepEqual(views[0]!.got, [], "not settled yet");
  await host.time.pass(1);
  assert.deepEqual(views[0]!.got, [{ look: { region: { x: 0.4, y: 0.25, w: 0.3333, h: 0.3333 }, maxWidth: 1920, maxHeight: 1080 } }]);
  // The part's frames: the page told where it is; the whole screen's size (what it is laid out by) as it was.
  views[0]!.send(join([configFrame({ codec: "h264", width: 1920, height: 1080, description: base64(avcc), region: { x: 0.4, y: 0.25, w: 0.3333, h: 0.3333 } }), videoFrame(true, 2_000, bytesOf(900, seed + 1))]));
  await host.settle();
  said(host, log);
  assert.deepEqual(log.filter((m) => m.id === 1 && m.value?.config).at(-1).value, { config: { codec: "h264", width: 1920, height: 1080, region: { x: 0.4, y: 0.25, w: 0.3333, h: 0.3333 } } });
  const live = lastState(log, 1);
  assert.deepEqual([live.width, live.height], [1920, 1080]);
  // The same part again: nothing more. About all of it, or a bad one: the whole again.
  look(5, { x: 0.4, y: 0.25, w: 0.3333, h: 0.3333 });
  await host.time.pass(LOOK_MS);
  assert.equal(views[0]!.got.length, 1);
  look(6, { x: 0, y: 0, w: 0.99, h: 1 });
  await host.time.pass(LOOK_MS);
  assert.deepEqual(views[0]!.got.at(-1), { look: { region: null } });
  // Zoomed in again, and the stream drops: the new one (the whole screen) asked for the part at once.
  look(7, { x: 1.2, y: 0.5, w: 0.25, h: 0.25 }, 600, 300);
  await host.time.pass(LOOK_MS);
  assert.deepEqual(views[0]!.got.at(-1), { look: { region: { x: 0.75, y: 0.5, w: 0.25, h: 0.25 }, maxWidth: 600, maxHeight: 300 } });
  views[0]!.end();
  await host.settle();
  await host.time.pass(1_000);
  assert.equal(views.length, 2);
  assert.deepEqual(views[1]!.got, [{ look: { region: { x: 0.75, y: 0.5, w: 0.25, h: 0.25 }, maxWidth: 600, maxHeight: 300 } }]);
  // A look after the view went: let go.
  core.receive(ui, { kind: "cancel", id: 1, cancel: true });
  await host.settle();
  look(8, null);
  await host.settle();
  said(host, log);
  assert.deepEqual(log.find((m) => m.id === 8), { id: 8, ok: null });
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
  assert.equal(views[1]!.alongside, 1, "the next opened before the one before it closed");
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

each("another_size_asked_opens_the_view_again_with_it_the_stream_before_kept_until_the_new_one_opened", async (seed) => {
  const { host, core, ui, views } = await viewing(seed);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v", maxWidth: 1920, maxHeight: 1080 });
  await host.settle();
  views[0]!.send(join([configFrame({ codec: "jpeg", width: 1920, height: 1080 }), videoFrame(true, 1, bytesOf(500, seed))]));
  await host.settle();
  call(core, ui, 2, "screen.bounds", { view: "v", maxWidth: 1280, maxHeight: 720 });
  await host.settle();
  assert.equal(views.length, 2, "opened again");
  // The station had a view of this client's all along (a Windows desktop puts its display's scale back once none is).
  assert.equal(views[1]!.alongside, 1);
  assert.equal(views[0]!.closed, true);
  assert.deepEqual([views[1]!.ask.maxWidth, views[1]!.ask.maxHeight, views[1]!.ask.control], [1280, 720, true]);
  // The same size again: nothing opened.
  call(core, ui, 3, "screen.bounds", { view: "v", maxWidth: 1280, maxHeight: 720 });
  await host.settle();
  assert.equal(views.length, 2);
  // Another 帧率 (and 画质) at the same size: opened again with them; 自动 again, without.
  call(core, ui, 5, "screen.bounds", { view: "v", maxWidth: 1280, maxHeight: 720, quality: "smooth", fps: 30 });
  await host.settle();
  assert.equal(views.length, 3);
  assert.deepEqual([views[2]!.ask.maxWidth, views[2]!.ask.fps, views[2]!.ask.quality], [1280, 30, "smooth"]);
  call(core, ui, 6, "screen.bounds", { view: "v", maxWidth: 1280, maxHeight: 720 });
  await host.settle();
  assert.equal(views.length, 4);
  assert.equal("fps" in views[3]!.ask || "quality" in views[3]!.ask, false);
  // Input goes to the new stream.
  call(core, ui, 4, "screen.input", { view: "v", input: { t: "text", text: "x" } });
  await host.settle();
  assert.deepEqual(views[3]!.got, [{ input: { t: "text", text: "x" } }]);
  said(host, log);
  const all = states(log, 1);
  assert.equal(all.slice(all.findIndex((s: J) => s.phase === "live")).some((s: J) => s.phase !== "live"), false, "the last frame stays: no connecting in between");
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
    [[404, "no screen browser:T9"], "gone", "此屏幕已不存在"],
    [[404, "no route POST /screens/x/view"], "outdated", "此 station 需要更新才能远程查看屏幕"],
    [[503, "在「屏幕录制」里打开 stillfail-station"], "denied", "在「屏幕录制」里打开 stillfail-station"],
    [[403, "只读成员不能看"], "denied", "只读成员不能看"],
    [[415, "没有共同的格式"], "failed", "没有共同的格式"],
  ];
  for (const [answer, phase, message] of cases) {
    const { host, core, ui, views, opts } = await viewing(1);
    opts.answer = () => answer;
    const log: J[] = [];
    call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v" });
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

each("a_screen_an_agent_drives_opens_only_looking_and_is_taken_over_in_one_tap", async (seed) => {
  const answers = { ...base(), "GET /screens": { screens: [{ ...SCREENS.screens[1], viewers: ["agent: 修登录", "Bob"], controlledBy: ["agent: 修登录"] }] } };
  const { host, core, ui, views } = await viewing(seed, answers);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "browser:T1", view: "v" });
  await host.settle();
  assert.equal(views[0]!.ask.control, false, "opened only looking: the agent is not held off");
  views[0]!.send(join([stateFrame({ title: "登录 - GitHub", control: false }), configFrame({ codec: "jpeg", width: 10, height: 10 }), videoFrame(true, 1, bytesOf(10, seed))]));
  await host.settle();
  said(host, log);
  let s = lastState(log, 1);
  assert.deepEqual([s.control, s.takeOver, s.controllers, s.others, s.line], [false, true, ["Agent「修登录」"], ["Agent「修登录」", "Bob"], "只看 · Agent「修登录」 正在控制 · Bob 也在查看"]);
  // 接管: driving, the agent's input waits.
  call(core, ui, 2, "screen.control", { view: "v", control: true });
  await host.settle();
  assert.equal(views.length, 2);
  assert.equal(views[1]!.ask.control, true);
  views[1]!.send(stateFrame({ title: "登录 - GitHub", control: true, viewers: ["a@x.com", "agent: 修登录", "Bob"], controlledBy: ["a@x.com", "agent: 修登录"] }));
  await host.settle();
  said(host, log);
  s = lastState(log, 1);
  assert.deepEqual([s.control, s.takeOver, s.line], [true, false, "控制 · Agent「修登录」 已暂停 · Bob 也在查看"]);
  // Asked to drive outright (control: true), it drives whoever else does.
  call(core, ui, 3, "screen.view", { station: "ws/st", screen: "browser:T1", view: "w", control: true });
  await host.settle();
  assert.equal(views[2]!.ask.control, true);
  core.close();
});

each("a_screen_only_the_viewers_own_views_drive_opens_driving", async (seed) => {
  // The app killed with the view open, twice: the station still names both views until it finds them gone.
  const answers = { ...base(), "GET /screens": { screens: [{ ...SCREENS.screens[1], viewers: ["a@x.com", "A@x.com"], controlledBy: ["a@x.com", "A@x.com"] }] } };
  const { host, core, ui, views } = await viewing(seed, answers);
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "browser:T1", view: "v" });
  await host.settle();
  assert.equal(views[0]!.ask.control, true, "the viewer's own views are not someone else driving it");
  core.close();
});

test("a_screen_the_station_does_not_list_is_not_opened", async () => {
  const { host, core, ui, views } = await viewing(1);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "browser:T9", view: "v" });
  await host.settle();
  said(host, log);
  assert.equal(views.length, 0);
  assert.equal(lastState(log, 1).phase, "gone");
  core.close();
});

each("the_station_says_what_a_view_takes_and_lacks_and_when_it_stops", async (seed) => {
  const { host, core, ui, views } = await viewing(seed);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v" });
  await host.settle();
  // Seen, not driven: macOS's Accessibility grant is missing (the station's first state says so).
  views[0]!.send(join([stateFrame({ title: "桌面", control: false, access: { capture: true, control: false, message: "在「辅助功能」里打开 stillfail-station", app: "stillfail-station" } }), configFrame({ codec: "jpeg", width: 10, height: 10 }), videoFrame(true, 1, bytesOf(10, seed))]));
  await host.settle();
  said(host, log);
  const s = lastState(log, 1);
  assert.deepEqual([s.control, s.access], [false, { capture: true, control: false, message: "在「辅助功能」里打开 stillfail-station", app: "stillfail-station" }]);
  call(core, ui, 2, "screen.input", { view: "v", input: { t: "text", text: "x" } });
  await host.settle();
  assert.deepEqual(views[0]!.got, []);
  // The station stops (an update): the view is opened again once it is back.
  views[0]!.send(stateFrame({ ended: "stopping" }));
  await host.settle();
  await host.time.pass(1_000);
  assert.equal(views.length, 2);
  views[1]!.send(stateFrame({ ended: "gone" }));
  await host.settle();
  said(host, log);
  assert.deepEqual([lastState(log, 1).phase, lastState(log, 1).message], ["gone", "此屏幕已不存在"], "its screen went: over for good, nothing to open again");
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


// ── the clipboard and files dropped ──

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 7, 7]);
/// A station that says its screens carry the clipboard and take files dropped.
const CARRYING = { screens: [{ ...SCREENS.screens[0], clipboard: ["text", "png", "gif"], drop: { folder: "/Users/bob/Downloads", reveal: true } }, { ...SCREENS.screens[1], clipboard: ["text"], drop: { folder: "/Users/bob/Downloads" } }] };

each("the_clipboard_frames_both_ways_are_read_and_framed_however_cut", (seed) => {
  const text = new TextEncoder().encode("复制的 text");
  const reader = new FrameReader();
  const read: StationFrame[] = [];
  for (const piece of cut(join([copiedFrame("text", text), videoFrame(true, 1, bytesOf(20, seed)), copiedFrame("png", PNG), new Uint8Array([4, 0, 0, 0, 2, 9, 9])]), random(seed))) {
    reader.push(piece);
    for (let f = reader.next(); f !== null; f = reader.next()) read.push(f);
  }
  assert.deepEqual(read[0], { clipboard: { type: "text", data: text } });
  assert.deepEqual(read[2], { clipboard: { type: "png", data: PNG } });
  assert.deepEqual(read[3], { other: 4 }, "a clipboard of a type this client does not know is passed over");
  const [frames] = readClientFrames(join([clipboardFrame("text", text, true), clipboardFrame("png", PNG, false)]));
  assert.deepEqual(frames, [{ clipboard: { type: "text", paste: true, data: text } }, { clipboard: { type: "png", paste: false, data: PNG } }]);
});

test("a_paste_is_checked_its_size_bounded_and_a_reveal_is_an_input", () => {
  const text = parseCall("screen.clipboard", { view: "v", text: "hi" }) as J;
  assert.deepEqual([text.call.type, text.call.paste, [...text.call.data]], ["text", true, [104, 105]], "pasted unless asked not to");
  assert.equal((parseCall("screen.clipboard", { view: "v", text: "hi", paste: false }) as J).call.paste, false);
  // A picture's bytes beside the call (`png: true`); base64 in it is not taken.
  assert.equal((parseCall("screen.clipboard", { view: "v", png: true }, PNG) as J).call.type, "png");
  assert.ok(parseCall("screen.clipboard", { view: "v", text: "a".repeat(CLIP_TEXT_MAX) }));
  for (const [bad, bytes] of [[{ view: "v" }], [{ view: "v", text: "" }], [{ view: "v", text: "a".repeat(CLIP_TEXT_MAX - 1) + "é" }], [{ view: "v", png: true }, new Uint8Array([1, 2, 3])], [{ view: "v", png: true }], [{ view: "v", png: base64(PNG) }, PNG]] as [J, Uint8Array?][]) {
    assert.throws(() => parseCall("screen.clipboard", bad, bytes), (e: J) => e.code === "invalid_params", JSON.stringify(bad).slice(0, 80));
  }
  const tooBig = new Uint8Array(CLIP_PNG_MAX + 1);
  tooBig.set(PNG);
  assert.throws(() => parseCall("screen.clipboard", { view: "v", png: true }, tooBig), (e: J) => e.code === "invalid_params");
  assert.deepEqual(checkInput({ t: "reveal", path: "/Users/bob/Downloads/a.pdf" }), { t: "reveal", path: "/Users/bob/Downloads/a.pdf" });
  assert.throws(() => checkInput({ t: "reveal", path: "" }));
});

each("while_driving_the_clipboard_goes_both_ways_and_where_files_go_is_said", async (seed) => {
  const { host, core, ui, views } = await viewing(seed, { ...base(), "GET /screens": CARRYING });
  const log: J[] = [];
  const values = new Map<number, unknown>();
  subscribe(core, ui, 9, { topic: "screens", station: "ws/st" });
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v", control: true });
  await host.settle();
  apply(host, values);
  const listed = (values.get(9) as J).screens;
  assert.deepEqual([listed[0].clipboard, listed[0].drop], [["text", "png"], { folder: "/Users/bob/Downloads", reveal: true }], "ours only");
  assert.deepEqual(listed[1].drop, { folder: "/Users/bob/Downloads", reveal: false });
  views[0]!.send(join([configFrame({ codec: "jpeg", width: 10, height: 10 }), videoFrame(true, 1, bytesOf(10, seed))]));
  await host.settle();
  said(host, log);
  const live = lastState(log, 1);
  assert.deepEqual([live.clipboard, live.drop], [["text", "png"], { folder: "/Users/bob/Downloads", reveal: true }]);
  // A copy made on the screen: to the page, text in its JSON, a picture's bytes beside it.
  views[0]!.send(join([copiedFrame("text", new TextEncoder().encode("从远端复制")), copiedFrame("png", PNG)]));
  await host.settle();
  said(host, log);
  const copies = log.filter((m) => m.id === 1 && m.value?.clipboard);
  assert.deepEqual(copies[0].value, { clipboard: { type: "text", text: "从远端复制" } });
  assert.deepEqual([copies[1].value, [...copies[1].bytes]], [{ clipboard: { type: "png", size: PNG.length } }, [...PNG]]);
  // A paste here, after the key before it; a reveal as input.
  call(core, ui, 2, "screen.input", { view: "v", input: { t: "key", kind: "down", key: "Meta", code: "MetaLeft", mods: 4 } });
  call(core, ui, 3, "screen.clipboard", { view: "v", text: "粘贴" });
  call(core, ui, 4, "screen.clipboard", { view: "v", png: true, paste: false }, PNG);
  call(core, ui, 5, "screen.input", { view: "v", input: { t: "reveal", path: "/Users/bob/Downloads/a.pdf" } });
  await host.settle();
  said(host, log);
  assert.deepEqual(log.find((m) => m.id === 3), { id: 3, ok: null });
  assert.deepEqual(views[0]!.got, [
    { input: { t: "key", kind: "down", key: "Meta", code: "MetaLeft", mods: 4 } },
    { clipboard: { type: "text", paste: true, data: new TextEncoder().encode("粘贴") } },
    { clipboard: { type: "png", paste: false, data: PNG } },
    { input: { t: "reveal", path: "/Users/bob/Downloads/a.pdf" } },
  ]);
  core.close();
});

each("only_looking_there_is_no_clipboard_nor_files_and_a_paste_is_refused", async (seed) => {
  const { host, core, ui, views } = await viewing(seed, { ...base(), "GET /screens": CARRYING });
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "desktop", view: "v", control: false });
  await host.settle();
  views[0]!.send(join([configFrame({ codec: "jpeg", width: 10, height: 10 }), videoFrame(true, 1, bytesOf(10, seed)), copiedFrame("text", new TextEncoder().encode("not for a looker"))]));
  await host.settle();
  call(core, ui, 2, "screen.clipboard", { view: "v", text: "x" });
  await host.settle();
  said(host, log);
  const watch = lastState(log, 1);
  assert.deepEqual([watch.control, watch.clipboard, watch.drop], [false, [], undefined]);
  assert.equal(log.some((m) => m.id === 1 && m.value?.clipboard), false, "a copy is not given to a view that only looks");
  assert.equal(log.find((m) => m.id === 2).error.code, "invalid_params");
  assert.deepEqual(views[0]!.got, []);
  core.close();
});

each("a_station_before_the_clipboard_offers_none_and_a_paste_to_it_is_refused", async (seed) => {
  const { host, core, ui, views } = await viewing(seed);
  const log: J[] = [];
  call(core, ui, 1, "screen.view", { station: "ws/st", screen: "browser:T1", view: "v", control: true });
  await host.settle();
  views[0]!.send(join([configFrame({ codec: "jpeg", width: 10, height: 10 }), videoFrame(true, 1, bytesOf(10, seed))]));
  await host.settle();
  call(core, ui, 2, "screen.clipboard", { view: "v", text: "x" });
  await host.settle();
  said(host, log);
  const live = lastState(log, 1);
  assert.deepEqual([live.control, live.clipboard, live.drop], [true, [], undefined]);
  assert.equal(log.find((m) => m.id === 2).error.code, "unsupported");
  assert.deepEqual(views[0]!.got, [], "nothing sent to a station that would not know it");
  core.close();
});

each("screen_audio_packets_survive_fragmentation_and_validate_the_format", (seed) => {
  const wire = (kind: number, payload: Uint8Array) => {
    const out = new Uint8Array(5 + payload.length);
    out[0] = kind;
    new DataView(out.buffer).setUint32(1, payload.length);
    out.set(payload, 5);
    return out;
  };
  const config = new TextEncoder().encode(JSON.stringify({ codec: "pcm_s16le", sampleRate: 48000, channels: 2 }));
  const payload = new Uint8Array(3848);
  new DataView(payload.buffer).setBigUint64(0, 123456789n);
  payload.set(bytesOf(3840, seed), 8);
  const reader = new FrameReader();
  const got: StationFrame[] = [];
  for (const piece of cut(join([wire(5, config), wire(6, payload)]), random(seed))) {
    reader.push(piece);
    for (let v = reader.next(); v !== null; v = reader.next()) got.push(v);
  }
  assert.deepEqual(got, [{ audioConfig: { codec: "pcm_s16le", sampleRate: 48000, channels: 2 } },
    { audio: { ts: 123456789, data: payload.slice(8) } }]);
  reader.push(wire(6, new Uint8Array(12)));
  assert.throws(() => reader.next(), /invalid screen audio packet/);
});
