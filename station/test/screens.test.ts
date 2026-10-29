// The station's screens (docs/remote-screens.md): the view wire over a member's link in memory (framing, at most
// as many frames not acknowledged as the pace lets go, read-only members, who is on a screen, how a view ends), with a fake source; the
// list (GET /screens, `screens` on the event stream); a person's input as macOS posts it; the desktop source with a
// fake helper (its grants, its view protocol); the clipboard both ways and files dropped (only for a view that drives,
// within bounds, of the types a source carries). Nothing here captures a screen: side/screen-desktop.test.ts does.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import { Events } from "../src/api/events.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { FrameIn, KIND, MAX_CLIP_IN, MAX_IN, SCREEN_TYPE, answerScreen, asked, frame, parseClip, parseInput } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HELPER_APP, HelperApp } from "../src/helper/app.ts";
import { Desktop, HelperView, TO_HELPER, helperClip, helperMessage } from "../src/screens/desktop.ts";
import { dropFolder } from "../src/drive/drive.ts";
import { ScreenHub, ScreenRefused } from "../src/screens/hub.ts";
import { CLICK_MS, FLAGS, KEYCODES, MacInput } from "../src/screens/mac-input.ts";
import { USAGES, SimInput } from "../src/screens/sim-input.ts";
import { SIMCTL, Simulators, bootedOf, runtimeName, screenOf } from "../src/screens/simulator.ts";
import { WindowsDesktop, screenBinary } from "../src/screens/win-desktop.ts";
import { KEYS, WinInput } from "../src/screens/win-input.ts";
import { CLIP_PNG_MAX, CLIP_TEXT_MAX, type Clip, type ClipType, type Frame, type ScreenAccess, type ScreenInput, type ScreenSource, type ScreenView, type ViewOptions } from "../src/screens/source.ts";
import { WINDOWS } from "../src/platform/index.ts";
import { settle, testClock } from "./hub-fakes.ts";
import { MAX_UNACKED, QUEUE_MS, START_RATE, START_UNACKED, STILL_MS, ownRate, rateCeiling } from "../src/mesh/screen-pace.ts";
import type { Clock } from "effect";
import { memoryMesh, vanish } from "./memory-mesh.ts";
import { Superseded } from "../src/mesh/superseded.ts";

const member: Viewer = { sub: "u1", email: "pat@example.com", name: "Pat", role: "member", workspace: "w", device: "d" };
const reader: Viewer = { sub: "u2", email: "vic@example.com", name: "Vic", role: "viewer", workspace: "w", device: "e" };

/// A source whose views give a frame each time one is asked for (the first a key frame with its config), and say what
/// they were asked.
class FakeView implements ScreenView {
  asked = 0;
  keyframes = 0;
  inputs: ScreenInput[] = [];
  /// What was asked of its clipboard, in order with its input (`input` the key or text, `clip` a clipboard set).
  asks: ({ input: ScreenInput } | { clip: Clip; paste: boolean } | { reveal: string })[] = [];
  /// Who hears its clipboard while it is watched.
  copied: ((clip: Clip) => void) | null = null;
  watched = 0;
  closed = false;
  /// After this many frames, none more (the source has nothing more to show).
  last = Infinity;
  next(): Promise<Frame | null> {
    if (this.closed || this.asked >= this.last) return Promise.resolve(null);
    const n = ++this.asked;
    const config = n === 1 ? { config: { codec: "h264" as const, width: 64, height: 36, description: new Uint8Array([1, 100, 0, 31]) } } : {};
    return Promise.resolve({ ...config, key: n === 1, ts: n * 1000, data: new Uint8Array([0, 0, 0, 1, n]) });
  }
  keyframe() {
    this.keyframes++;
  }
  async input(event: ScreenInput) {
    this.inputs.push(event);
    this.asks.push({ input: event });
  }
  async setClipboard(clip: Clip, paste: boolean) {
    this.asks.push({ clip, paste });
  }
  watchClipboard(heard: (clip: Clip) => void) {
    this.watched++;
    this.copied = heard;
    return () => {
      if (this.copied === heard) this.copied = null;
    };
  }
  async reveal(path: string) {
    this.asks.push({ reveal: path });
  }
  /// Who hears the pointer while it is watched.
  pointer: ((cursor: { x: number; y: number; shape: string }) => void) | null = null;
  watchCursor(heard: (cursor: { x: number; y: number; shape: string }) => void) {
    this.pointer = heard;
    return () => {
      if (this.pointer === heard) this.pointer = null;
    };
  }
  close() {
    this.closed = true;
  }
}

/// A view of a screen that stays still after its first picture (a desktop left alone): no picture more until a key
/// frame is asked, which sends that picture again; it says the bit rates it was asked, as a video's source does.
class StillView extends FakeView {
  rates: number[] = [];
  /// The frame asked for and not given yet: given as a key frame is asked, none as the view closes.
  #asked: { n: number; give: (frame: Frame | null) => void } | null = null;
  override next(): Promise<Frame | null> {
    if (this.closed) return Promise.resolve(null);
    const n = ++this.asked;
    if (n === 1) return Promise.resolve({ config: { codec: "h264", width: 1920, height: 1080, description: new Uint8Array([1, 100, 0, 31]) }, key: true, ts: 1000, data: new Uint8Array([0, 0, 0, 1, 1]) });
    return new Promise((give) => (this.#asked = { n, give }));
  }
  override keyframe() {
    this.keyframes++;
    const asked = this.#asked;
    this.#asked = null;
    asked?.give({ key: true, ts: asked.n * 1000, data: new Uint8Array([0, 0, 0, 1, asked.n]) });
  }
  override close() {
    super.close();
    this.#asked?.give(null);
    this.#asked = null;
  }
  rate(bits: number) {
    this.rates.push(bits);
  }
}

class FakeSource implements ScreenSource {
  readonly kind = "browser" as const;
  /// What its views are (a still screen's: StillView).
  make: () => FakeView = () => new FakeView();
  views: FakeView[] = [];
  opened: ViewOptions[] = [];
  name = "Tab";
  refuse: Error | null = null;
  types: ClipType[] = [];
  reveal = false;
  readonly id: string;
  constructor(id = "fake") {
    this.id = id;
  }
  title() {
    return this.name;
  }
  size() {
    return { width: 1280, height: 720 };
  }
  clipboard() {
    return this.types;
  }
  async open(options: ViewOptions): Promise<ScreenView> {
    this.opened.push(options);
    if (this.refuse) throw this.refuse;
    const view = this.make();
    this.views.push(view);
    return view;
  }
}

/// A member's link in memory: the device's connection and the station's.
async function link() {
  const mesh = memoryMesh();
  const station = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [] });
  const device = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [] });
  const accepting = station.accept();
  const conn = await device.connect({ id: station.id() }, ALPN);
  return { conn, theirs: (await accepting)! };
}

/// A view opened as a client opens one: its head line, the station answering it (`served`), the answer's head.
async function open(hub: ScreenHub, viewer: Viewer, screen: unknown = { maxWidth: 1920, maxHeight: 1080, codecs: ["h264", "jpeg"], control: true }, path = "/admin/api/screens/fake/view", clock?: Clock.Clock) {
  const { conn, theirs } = await link();
  const stream = await conn.openBi();
  await writeLine(stream, { method: "POST", path, headers: { "stillfail-lang": "en" }, screen });
  const incoming = (await theirs.acceptBi())!;
  const heard = new Reader(incoming);
  const head = await heard.line();
  const served = answerScreen(hub, incoming, heard.carry, head, viewer, () => true, clock);
  const client = new Reader(stream);
  const answer = await client.line();
  return { conn, stream, served, answer, client, frames: new FrameIn(stream, client.carry) };
}

const json = (payload: Buffer) => JSON.parse(payload.toString("utf8"));
const ts8 = (ts: number) => {
  const b = Buffer.alloc(8);
  b.writeBigUInt64BE(BigInt(ts));
  return b;
};

/// The next frame of `kind`, the states before it gathered.
async function until(frames: FrameIn, kind: number, states: any[] = []): Promise<Buffer> {
  for (;;) {
    const got = await frames.next();
    assert.ok(got, `the stream ended before a frame of kind ${kind}`);
    if (got.kind === kind) return got.payload;
    if (got.kind === KIND.state) states.push(json(got.payload));
  }
}

test("a view: its answer, what it is, then the config and frames as the source gives them", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  const v = await open(hub, member, { maxWidth: 99999, codecs: ["vp9", "h264"], control: true });
  assert.deepEqual(v.answer, { status: 200, headers: { "content-type": SCREEN_TYPE } });
  // What it asked, bounded; the codecs ours only; the height as not said; at the pace's start rate.
  assert.deepEqual(source.opened, [{ maxWidth: 8192, maxHeight: 1080, codecs: ["h264"], bitrate: START_RATE }]);
  const states: any[] = [];
  const config = json(await until(v.frames, KIND.config, states));
  assert.deepEqual(states, [{ title: "Tab", control: true }, { viewers: ["Pat"], controlledBy: ["Pat"] }]);
  assert.deepEqual(config, { codec: "h264", width: 64, height: 36, description: Buffer.from([1, 100, 0, 31]).toString("base64") });
  const first = await until(v.frames, KIND.video);
  assert.equal(first[0], 1, "the first frame is a key frame");
  assert.equal(first.readBigUInt64BE(1), 1000n);
  assert.deepEqual([...first.subarray(9)], [0, 0, 0, 1, 1]);
  const second = await until(v.frames, KIND.video);
  assert.equal(second[0], 0);
  assert.equal(second.readBigUInt64BE(1), 2000n);
  await v.stream.finish();
  await v.served;
});

test("frames go unacknowledged while the link keeps up: two before its round trip is known, none once one waits too long", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  const time = testClock();
  const v = await open(hub, member, undefined, undefined, time.clock);
  await until(v.frames, KIND.video);
  await until(v.frames, KIND.video);
  await settle();
  const view = source.views[0]!;
  assert.equal(view.asked, START_UNACKED, "before an acknowledgement, two");
  // The first decoded at once (a round trip of 0 ms): the link keeps up, frames go until MAX_UNACKED are on the way.
  await v.stream.write(frame(KIND.ack, ts8(1000)));
  await settle();
  assert.equal(view.asked, 1 + MAX_UNACKED);
  // Later than the round trip and QUEUE_MS: a queue builds, nothing more goes, not even as one is acknowledged.
  await time.adjust(QUEUE_MS + 1);
  await v.stream.write(frame(KIND.ack, ts8(2000)));
  await settle();
  assert.equal(view.asked, 1 + MAX_UNACKED);
  // All of them decoded: they go again.
  await v.stream.write(frame(KIND.ack, ts8(view.asked * 1000)));
  await settle();
  assert.equal(view.asked, 1 + 2 * MAX_UNACKED);
  // A short ack says nothing.
  await v.stream.write(frame(KIND.ack, Buffer.alloc(3)));
  await settle();
  assert.equal(view.asked, 1 + 2 * MAX_UNACKED);
  // A key frame asked for goes to the source.
  await v.stream.write(frame(KIND.keyframe, Buffer.alloc(0)));
  await settle();
  assert.equal(view.keyframes, 1);
  await v.stream.finish();
  await v.served;
});

/// A view of a source that frames a part of its screen when asked (a desktop's): it says the bounds asked, and its next
/// frame after them is a key frame with a config of that size, saying the part.
class PartView extends FakeView {
  bounded: [number, number, unknown][] = [];
  #config: Frame["config"] | null = null;
  regions() {
    return true;
  }
  bounds(maxWidth: number, maxHeight: number, region?: unknown) {
    this.bounded.push([maxWidth, maxHeight, region ?? null]);
    this.#config = { codec: "h264", width: maxWidth, height: maxHeight, description: new Uint8Array([1, 100, 0, 31]), ...(region ? { region: region as any } : {}) };
  }
  override next(): Promise<Frame | null> {
    const config = this.#config;
    if (config === null) return super.next();
    this.#config = null;
    const n = ++this.asked;
    return Promise.resolve({ config, key: true, ts: n * 1000, data: new Uint8Array([0, 0, 0, 1, n]) });
  }
}

test("a look: a source that frames parts frames the part as large as the client shows it, its config saying which; the whole again at the view's own bounds; one that does not is not asked", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  source.make = () => new PartView();
  hub.add(source);
  const v = await open(hub, member, { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: true });
  await until(v.frames, KIND.video);
  const view = source.views[0] as PartView;
  const look = (said: unknown) => v.stream.write(frame(KIND.look, Buffer.from(JSON.stringify(said))));
  const ack = async () => {
    await v.stream.write(frame(KIND.ack, ts8(view.asked * 1000)));
    await settle();
  };
  // A quarter of the screen in its middle, shown 1200×676 device pixels: framed so, the config saying the part.
  await look({ region: { x: 0.375, y: 0.375, w: 0.25, h: 0.25 }, maxWidth: 1200, maxHeight: 676 });
  await settle();
  assert.deepEqual(view.bounded, [[1200, 676, { x: 0.375, y: 0.375, w: 0.25, h: 0.25 }]]);
  await ack();
  let config = json(await until(v.frames, KIND.config));
  assert.deepEqual(config.region, { x: 0.375, y: 0.375, w: 0.25, h: 0.25 });
  assert.equal(config.width, 1200);
  // The same look again: nothing asked. One past the screen's edge, or smaller than a 50th: kept within it.
  await look({ region: { x: 0.375, y: 0.375, w: 0.25, h: 0.25 }, maxWidth: 1200, maxHeight: 676 });
  await look({ region: { x: 0.99, y: -0.5, w: 0.001, h: 0.5 }, maxWidth: 99999, maxHeight: 4 });
  await settle();
  assert.deepEqual(view.bounded.slice(1), [[8192, 16, { x: 0.98, y: 0, w: 0.02, h: 0.5 }]]);
  // The whole again (none, or about all of it): the view's own bounds, no part; its config says none.
  await look({ region: { x: 0, y: 0, w: 0.99, h: 1 }, maxWidth: 400, maxHeight: 400 });
  await settle();
  assert.deepEqual(view.bounded.at(-1), [1920, 1080, null]);
  await ack();
  // (the configs of the looks before it first, as frames went meanwhile)
  do config = json(await until(v.frames, KIND.config));
  while (config.width !== 1920);
  assert.equal(config.region, undefined);
  assert.equal(config.width, 1920);
  // Not JSON: let be.
  await v.stream.write(frame(KIND.look, Buffer.from("{")));
  await settle();
  assert.equal(view.bounded.length, 3);
  await v.stream.finish();
  await v.served;
  // A source that frames no parts (a tab of the browser) is not asked: the client goes on drawing the whole screen.
  source.make = () => Object.assign(new PartView(), { regions: () => false });
  const w = await open(hub, member, { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: true });
  await until(w.frames, KIND.video);
  await w.stream.write(frame(KIND.look, Buffer.from(JSON.stringify({ region: { x: 0.5, y: 0.5, w: 0.5, h: 0.5 } }))));
  await settle();
  assert.deepEqual((source.views[1] as PartView).bounded, []);
  await w.stream.finish();
  await w.served;
});

test("the helper's view of a part of the display: the part asked with the bounds of a helper that frames parts (none of one from before them), each config saying the part its frames show as the helper said it", () => {
  const written: Buffer[] = [];
  const listeners: Record<string, ((chunk: Buffer) => void)[]> = {};
  const pipe = {
    write: (b: Buffer) => written.push(b),
    destroy: () => {},
    on: (event: string, f: any) => {
      (listeners[event] ??= []).push(f);
    },
  };
  const say = (kind: number, payload: Buffer | object) => listeners.data!.forEach((f) => f(helperMessage(kind, Buffer.isBuffer(payload) ? payload : Buffer.from(JSON.stringify(payload)))));
  const frames: (Frame | null)[] = [];
  const config = (w: number, h: number) => {
    const c = Buffer.alloc(8);
    c.writeUInt32BE(w, 0);
    c.writeUInt32BE(h, 4);
    return Buffer.concat([c, Buffer.from([1, 66, 0, 31])]);
  };
  const picture = (key: boolean, n: number) => {
    const f = Buffer.alloc(9);
    f[0] = key ? 1 : 0;
    f.writeBigUInt64BE(BigInt(n * 1000), 1);
    return Buffer.concat([f, Buffer.from([n])]);
  };
  const bounds = () => written.filter((b) => b[0] === TO_HELPER.bounds).map((b) => JSON.parse(b.subarray(5).toString()));
  const part = { x: 0.5, y: 0, w: 0.5, h: 0.5 };
  // A helper from before parts: the bounds alone, the whole display.
  const old = new HelperView("h264", pipe, () => {});
  say(1, { width: 1920, height: 1080, encoder: "e", codec: "h264" });
  assert.equal(old.regions(), false);
  old.bounds(1280, 720, part);
  assert.deepEqual(bounds(), [{ maxWidth: 1280, maxHeight: 720 }]);
  old.close();
  written.length = 0;
  delete listeners.data;
  const view = new HelperView("h264", pipe, () => {});
  say(1, { width: 1920, height: 1080, encoder: "e", codec: "h264", regions: true });
  assert.equal(view.regions(), true);
  view.bounds(1200, 676, part);
  assert.deepEqual(bounds(), [{ maxWidth: 1200, maxHeight: 676, region: part }]);
  const next = () => void view.next().then((f) => frames.push(f));
  // The whole display first; then the part as the helper framed it, at another size (a config with the part); then
  // a part of the same size (its config again, saying it); then the whole again.
  next();
  say(2, config(1920, 1080));
  say(3, picture(true, 1));
  next();
  say(7, { region: part });
  say(2, config(1200, 676));
  say(3, picture(true, 2));
  next();
  say(3, picture(false, 3));
  next();
  say(7, { region: { x: 0.25, y: 0, w: 0.5, h: 0.5 } });
  say(3, picture(true, 4));
  next();
  say(7, { region: null });
  say(3, picture(true, 5));
  return settle().then(() => {
    assert.deepEqual(
      frames.map((f) => f?.config && { width: f.config.width, region: f.config.region ?? null }),
      [{ width: 1920, region: null }, { width: 1200, region: part }, undefined, { width: 1200, region: { x: 0.25, y: 0, w: 0.5, h: 0.5 } }, { width: 1200, region: null }],
    );
    view.close();
  });
});

test("a still screen's picture goes again sharper as the rate goes up, a key frame each STILL_MS, until it is at the source's own", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  source.make = () => new StillView();
  hub.add(source);
  const time = testClock();
  const v = await open(hub, member, undefined, undefined, time.clock);
  const first = await until(v.frames, KIND.video);
  assert.equal(first[0], 1);
  const view = source.views[0] as StillView;
  // Each acknowledged at once: the rate goes up a step; still for STILL_MS, the picture again as a key frame at it.
  let ts = 1000;
  const steps: number[] = [];
  for (;;) {
    await v.stream.write(frame(KIND.ack, ts8(ts)));
    await settle();
    await time.adjust(STILL_MS);
    await settle();
    if (view.keyframes === steps.length) break;
    steps.push(view.rates.at(-1)!);
    const again = await until(v.frames, KIND.video);
    assert.equal(again[0], 1, "the picture again is a key frame");
    ts = Number(again.readBigUInt64BE(1));
  }
  // Up from START_RATE by the pace's steps to the source's own (1920×1080's), and then no more.
  assert.deepEqual(steps, [2_250_000, 3_375_000, 5_062_500, ownRate(1920, 1080)]);
  await time.adjust(5 * STILL_MS);
  await settle();
  assert.equal(view.keyframes, steps.length);
  await v.stream.finish();
  await v.served;
});

test("原画 asked: the rate goes up past the source's own, to its pixels × 8; 高清 × 4; a client that says none, its own", async () => {
  for (const [quality, top] of [["original", rateCeiling(1920, 1080, "original")], ["hd", rateCeiling(1920, 1080, "hd")], [undefined, ownRate(1920, 1080)]] as const) {
    const hub = new ScreenHub();
    const source = new FakeSource();
    source.make = () => new StillView();
    hub.add(source);
    const time = testClock();
    const v = await open(hub, member, { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: true, ...(quality ? { quality } : {}) }, undefined, time.clock);
    await until(v.frames, KIND.video);
    const view = source.views[0] as StillView;
    let ts = 1000;
    for (let i = 0; i < 20; i++) {
      await v.stream.write(frame(KIND.ack, ts8(ts)));
      await settle();
      await time.adjust(STILL_MS);
      await settle();
      if (view.keyframes === i) break;
      ts = Number((await until(v.frames, KIND.video)).readBigUInt64BE(1));
    }
    assert.equal(Math.max(...view.rates), top, `${quality}`);
    await v.stream.finish();
    await v.served;
  }
});

test("a view's ask: its 帧率 among those offered, none for 自动, another or a preview's", () => {
  const ask = { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] };
  for (const fps of [120, 90, 60, 30, 15]) assert.equal(asked({ ...ask, fps }).fps, fps);
  for (const fps of [undefined, 0, 45, 240, "60"]) assert.equal("fps" in asked({ ...ask, fps }), false, String(fps));
  assert.equal(asked({ ...ask, fps: 30, peek: true }).fps, undefined);
});

test("a 帧率 asked: its source opened with it, and no more frames a second go than it", async () => {
  for (const fps of [15, undefined]) {
    const hub = new ScreenHub();
    const source = new FakeSource();
    hub.add(source);
    const time = testClock();
    const v = await open(hub, member, { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: true, ...(fps ? { fps } : {}) }, undefined, time.clock);
    assert.equal(source.opened[0]!.fps, fps);
    await until(v.frames, KIND.video);
    // (what comes read as it comes)
    const read = (async () => {
      while ((await v.frames.next()) !== null);
    })();
    const view = source.views[0]!;
    // Each frame acknowledged 5 ms on, for a second of the view's clock (自动: a tenth of one), its source with a new
    // picture each time.
    const from = view.asked;
    for (let ms = 0; ms < (fps ? 1000 : 100); ms += 5) {
      await v.stream.write(frame(KIND.ack, ts8(view.asked * 1000)));
      await settle();
      await time.adjust(5);
      await settle();
    }
    const went = view.asked - from;
    if (fps) assert.ok(went >= fps - 1 && went <= fps + 1, `${went} at ${fps}`);
    else assert.ok(went > 15, `自动: ${went} in 100 ms`);
    await v.stream.finish();
    await v.served;
    await read;
  }
});

test("a view's ask: its 画质 among those known, none for a preview's", () => {
  const ask = { maxWidth: 1920, maxHeight: 1080, codecs: ["h265", "h264"] };
  assert.equal(asked({ ...ask, quality: "original" }).quality, "original");
  assert.equal(asked({ ...ask, quality: "hd" }).quality, "hd");
  assert.equal(asked({ ...ask, quality: "best" }).quality, undefined);
  assert.equal(asked(ask).quality, undefined);
  assert.equal(asked({ ...ask, quality: "original", peek: true }).quality, undefined);
});

test("a view's ask: Display P3 only as `gamut: \"p3\"` says, else sRGB (none)", () => {
  const ask = { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] };
  assert.equal(asked({ ...ask, gamut: "p3" }).gamut, "p3");
  for (const gamut of [undefined, "P3", "rec2020", true]) assert.equal("gamut" in asked({ ...ask, gamut }), false, String(gamut));
});

test("the pointer a source says beside its pictures goes to the view as its state's cursor", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  const v = await open(hub, member);
  await until(v.frames, KIND.video);
  const view = source.views[0]!;
  assert.ok(view.pointer, "watched as the view opened");
  view.pointer!({ x: 0.25, y: 0.5, shape: "text" });
  for (;;) {
    const got = await v.frames.next();
    if (got?.kind === KIND.state && json(got.payload).cursor) {
      assert.deepEqual(json(got.payload).cursor, { x: 0.25, y: 0.5, shape: "text" });
      break;
    }
  }
  await v.stream.finish();
  await v.served;
  assert.equal(view.pointer, null, "no longer heard once the view ended");
});

test("the display's scale: told to a person who drives it, set as they ask; a read-only member neither hears nor sets it", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  let scale = { percent: 300, recommended: 150, steps: [100, 125, 150, 175, 200, 225, 250, 300, 350] };
  const set: number[] = [];
  Object.assign(source, {
    scale: async () => scale,
    setScale: async (percent: number) => (set.push(percent), (scale = { ...scale, percent })),
  });
  hub.add(source);
  const driver = await open(hub, member);
  const states: any[] = [];
  await until(driver.frames, KIND.video, states);
  while (!states.some((s) => s.scale)) states.push(json(await until(driver.frames, KIND.state)));
  assert.deepEqual(states.find((s) => s.scale).scale, { percent: 300, recommended: 150, steps: scale.steps });
  await driver.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "scale", percent: 150 }))));
  // Not a percent Windows has, or not a number: dropped before the source.
  await driver.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "scale", percent: 1000 }))));
  await driver.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "scale", percent: "150" }))));
  for (;;) {
    const got = await driver.frames.next();
    if (got?.kind === KIND.state && json(got.payload).scale?.percent === 150) break;
  }
  assert.deepEqual(set, [150]);
  const viewer = await open(hub, reader, { codecs: ["h264"], control: true });
  const seen: any[] = [];
  await until(viewer.frames, KIND.video, seen);
  await viewer.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "scale", percent: 100 }))));
  await settle();
  assert.deepEqual(set, [150]);
  assert.ok(!seen.some((s) => s.scale));
  await driver.stream.finish();
  await viewer.stream.finish();
  await Promise.all([driver.served, viewer.served]);
});

test("the display's resolution: told to a person who drives it, set as they ask; a read-only member neither hears nor sets it", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  const modes = [{ width: 2560, height: 1440 }, { width: 1920, height: 1080 }, { width: 1600, height: 1200 }];
  let resolution = { width: 2560, height: 1440, modes };
  const set: string[] = [];
  Object.assign(source, {
    resolution: async () => resolution,
    setResolution: async (width: number, height: number) => (set.push(`${width}x${height}`), (resolution = { ...resolution, width, height })),
  });
  hub.add(source);
  const driver = await open(hub, member);
  const states: any[] = [];
  await until(driver.frames, KIND.video, states);
  while (!states.some((s) => s.resolution)) states.push(json(await until(driver.frames, KIND.state)));
  assert.deepEqual(states.find((s) => s.resolution).resolution, { width: 2560, height: 1440, modes });
  await driver.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "resolution", width: 1600, height: 1200 }))));
  // Not a size, or not numbers: dropped before the source.
  await driver.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "resolution", width: 10, height: 10 }))));
  await driver.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "resolution", width: "1600", height: 1200 }))));
  for (;;) {
    const got = await driver.frames.next();
    if (got?.kind === KIND.state && json(got.payload).resolution?.width === 1600) break;
  }
  assert.deepEqual(set, ["1600x1200"]);
  const viewer = await open(hub, reader, { codecs: ["h264"], control: true });
  const seen: any[] = [];
  await until(viewer.frames, KIND.video, seen);
  await viewer.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "resolution", width: 1920, height: 1080 }))));
  await settle();
  assert.deepEqual(set, ["1600x1200"]);
  assert.ok(!seen.some((s) => s.resolution));
  await driver.stream.finish();
  await viewer.stream.finish();
  await Promise.all([driver.served, viewer.served]);
});

test("input reaches the source from a member who asked to drive, checked; a read-only member's is dropped", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  const driver = await open(hub, member);
  const watcher = await open(hub, reader);
  const looker = await open(hub, member, { codecs: ["jpeg"], control: false });
  const states: any[] = [];
  await until(watcher.frames, KIND.video, states);
  assert.deepEqual(states[0], { title: "Tab", control: false }, "a read-only member does not drive, whatever it asks");
  const send = (v: typeof driver, e: unknown) => v.stream.write(frame(KIND.input, Buffer.from(JSON.stringify(e))));
  await send(driver, { t: "pointer", kind: "down", x: 1.5, y: 0.25, buttons: 1 });
  await send(driver, { t: "key", kind: "down", key: "a", code: "KeyA", mods: 4 });
  await send(driver, { t: "pointer", kind: "sideways", x: 0, y: 0 });
  await send(driver, { t: "text", text: "" });
  await driver.stream.write(frame(KIND.input, Buffer.from("not json")));
  await send(driver, { t: "text", text: "你好" });
  await send(watcher, { t: "text", text: "nope" });
  await send(looker, { t: "text", text: "nope" });
  await settle();
  const [mine, theirs, looked] = source.views;
  assert.deepEqual(mine!.inputs, [
    { t: "pointer", kind: "down", x: 1, y: 0.25, buttons: 1 },
    { t: "key", kind: "down", key: "a", code: "KeyA", mods: 4 },
    { t: "text", text: "你好" },
  ]);
  assert.deepEqual(theirs!.inputs, []);
  assert.deepEqual(looked!.inputs, []);
  for (const v of [driver, watcher, looker]) await v.stream.finish();
  await Promise.all([driver.served, watcher.served, looker.served]);
});

test("who is on a screen: every view's person, told to all on it and in the list as they come and go", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  let told = 0;
  hub.onChange(() => told++);
  const driver = await open(hub, member);
  const watcher = await open(hub, reader);
  const states: any[] = [];
  await until(driver.frames, KIND.video, states);
  await settle();
  assert.deepEqual(hub.people("fake"), { viewers: ["Pat", "Vic"], controlledBy: ["Pat"] });
  assert.deepEqual(hub.listed("en").screens, [{ id: "fake", kind: "browser", title: "Tab", width: 1280, height: 720, viewers: ["Pat", "Vic"], controlledBy: ["Pat"] }]);
  assert.equal(told, 2);
  await watcher.stream.finish();
  await watcher.served;
  // The driver hears that Vic left.
  const later: any[] = [];
  for (;;) {
    const got = await driver.frames.next();
    if (got?.kind === KIND.state) later.push(json(got.payload));
    if (later.some((s) => s.viewers?.length === 1)) break;
  }
  assert.deepEqual(later.at(-1), { viewers: ["Pat"], controlledBy: ["Pat"] });
  assert.deepEqual(hub.people("fake"), { viewers: ["Pat"], controlledBy: ["Pat"] });
  assert.equal(told, 3);
  await driver.stream.finish();
  await driver.served;
  assert.deepEqual(hub.people("fake"), { viewers: [], controlledBy: [] });
});

test("an app killed with a view open: connecting again, its dead connection is closed and its view lets the screen go; a live one's stays", async () => {
  const hub = new ScreenHub();
  hub.add(new FakeSource());
  const mesh = memoryMesh();
  const station = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [] });
  const superseded = new Superseded();
  const key = randomBytes(32);
  /// The device's process (one key, as Android's app and every tab of a phone's Chrome have), its view driving.
  const app = async () => {
    const device = await mesh.bind({ secretKey: key, alpns: [ALPN], relayUrls: [] });
    const accepting = station.accept();
    const conn = await device.connect({ id: station.id() }, ALPN);
    const theirs = (await accepting)!;
    const asked = superseded.arrived(theirs);
    const stream = await conn.openBi();
    await writeLine(stream, { method: "POST", path: "/admin/api/screens/fake/view", headers: {}, screen: { codecs: ["h264"], control: true } });
    const incoming = (await theirs.acceptBi())!;
    const heard = new Reader(incoming);
    const served = answerScreen(hub, incoming, heard.carry, await heard.line(), member, () => true);
    const client = new Reader(stream);
    await client.line();
    await until(new FrameIn(stream, client.carry), KIND.video);
    return { device, theirs, asked, served };
  };
  const first = await app();
  await settle();
  assert.deepEqual(hub.people("fake").controlledBy, ["Pat"]);
  // Another tab of the same phone: the first answers, and keeps its view.
  const tab = await app();
  await tab.asked;
  await settle();
  assert.equal(first.theirs.isClosed(), false, "a live client of the same key is left alone");
  assert.deepEqual(hub.people("fake").controlledBy, ["Pat", "Pat"]);
  // Both killed (force-stopped): nothing tells the station. Opened again: both found gone, their views ended.
  vanish(first.device);
  vanish(tab.device);
  await settle();
  assert.deepEqual(hub.people("fake").controlledBy, ["Pat", "Pat"], "a killed app's views are held until its key comes again");
  const again = await app();
  await again.asked;
  await first.served;
  await tab.served;
  await settle();
  assert.equal(first.theirs.isClosed(), true);
  assert.equal(tab.theirs.isClosed(), true);
  assert.equal(again.theirs.isClosed(), false);
  assert.deepEqual(hub.people("fake"), { viewers: ["Pat"], controlledBy: ["Pat"] });
});

test("a preview (a link's card in a chat) only looks, is not among those on it, and only of a source that can be previewed", async () => {
  const hub = new ScreenHub();
  const source = Object.assign(new FakeSource(), { peek: true });
  const still = new FakeSource("still");
  hub.add(source);
  hub.add(still);
  assert.equal(hub.listed("en").screens[0]!.peek, true);
  assert.equal("peek" in hub.listed("en").screens[1]!, false);
  const card = await open(hub, member, { maxWidth: 480, maxHeight: 300, codecs: ["jpeg"], control: true, peek: true });
  assert.equal(card.answer.status, 200);
  const states: any[] = [];
  await until(card.frames, KIND.video, states);
  await settle();
  assert.equal(states[0].control, false);
  assert.equal(source.opened.at(-1)!.peek, true);
  assert.deepEqual(hub.people("fake"), { viewers: [], controlledBy: [] });
  // Its input is dropped: it only looks.
  await card.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "text", text: "x" }))));
  await card.stream.finish();
  await card.served;
  assert.deepEqual(source.views[0]!.inputs, []);
  // One that cannot be previewed (the desktop, whose view wakes its display) is refused, not opened.
  const refused = await open(hub, member, { maxWidth: 480, maxHeight: 300, codecs: ["jpeg"], peek: true }, "/admin/api/screens/still/view");
  assert.equal(refused.answer.status, 501);
  assert.equal(still.opened.length, 0);
});

/// The rest of a view's frames, its states gathered, until the station finishes it.
async function rest(frames: FrameIn): Promise<any[]> {
  const states: any[] = [];
  for (let got = await frames.next(); got !== null; got = await frames.next()) if (got.kind === KIND.state) states.push(json(got.payload));
  return states;
}

test("a view ends when the client finishes, the source goes or has no more, the station stops, or the link breaks", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  const remove = hub.add(source);
  // The client finishes: told so, the capture stops.
  const a = await open(hub, member);
  await until(a.frames, KIND.video);
  await a.stream.finish();
  assert.deepEqual((await rest(a.frames)).at(-1), { ended: "finished" });
  await a.served;
  assert.equal(source.views[0]!.closed, true);
  // The source goes.
  const b = await open(hub, member);
  await until(b.frames, KIND.video);
  remove();
  assert.deepEqual((await rest(b.frames)).at(-1), { ended: "gone" });
  await b.served;
  assert.equal(source.views[1]!.closed, true);
  hub.add(source);
  // It has nothing more to show.
  source.refuse = null;
  const c = await open(hub, member);
  source.views[2]!.last = 1;
  await c.stream.write(frame(KIND.ack, ts8(2000)));
  assert.deepEqual((await rest(c.frames)).at(-1), { ended: "gone" });
  await c.served;
  // The station stops.
  const d = await open(hub, member);
  await until(d.frames, KIND.video);
  hub.close();
  assert.deepEqual((await rest(d.frames)).at(-1), { ended: "stopping" });
  await d.served;
  assert.equal(source.views[3]!.closed, true);
  // The connection goes: nothing more is written, the capture stops, nobody is on it.
  const e = await open(hub, member);
  await until(e.frames, KIND.video);
  e.conn.close(0, "gone");
  await e.served;
  assert.equal(source.views[4]!.closed, true);
  assert.deepEqual(hub.people("fake"), { viewers: [], controlledBy: [] });
  // A frame too large breaks it.
  const f = await open(hub, member);
  await until(f.frames, KIND.video);
  await f.stream.write(frame(KIND.input, Buffer.alloc(MAX_IN + 1)));
  await f.served;
  assert.equal(source.views[5]!.closed, true);
});

test("what a view cannot be: answered with a status and why, in the asker's language", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  const body = async (v: Awaited<ReturnType<typeof open>>) => JSON.parse((await v.client.rest()).toString());
  const none = await open(hub, member, { codecs: ["h264"] }, "/admin/api/screens/elsewhere/view");
  assert.equal(none.answer.status, 404);
  assert.equal((await body(none)).error, "This screen is no longer on this station");
  const codecs = await open(hub, member, { codecs: ["vp9"] });
  assert.equal(codecs.answer.status, 400);
  const path = await open(hub, member, { codecs: ["h264"] }, "/admin/api/screens/fake");
  assert.equal(path.answer.status, 404);
  // What is missing, and that a window on the machine asks for it now.
  const access: ScreenAccess = { capture: false, control: false, app: "still.fail Helper", path: "/x/still.fail Helper.app", asking: true };
  source.refuse = new ScreenRefused(503, "station.screen.captureOff", { app: "still.fail Helper" }, access);
  const refused = await open(hub, member, { codecs: ["h264"] });
  assert.equal(refused.answer.status, 503);
  const said = await body(refused);
  assert.equal(
    said.error,
    "This Mac hasn't let still.fail Helper record its screen or control it yet. A permission window is open on that Mac: click Allow there, drag still.fail Helper into the list in System Settings, then open the screen again.",
  );
  assert.deepEqual(said.access, { capture: false, control: false, message: said.error, app: "still.fail Helper", path: "/x/still.fail Helper.app", asking: true });
  source.refuse = new Error("tab crashed");
  const failed = await open(hub, member, { codecs: ["h264"] });
  assert.equal(failed.answer.status, 503);
  assert.equal((await body(failed)).error, "The screen couldn't be opened: tab crashed");
  await Promise.all([none.served, codecs.served, path.served, refused.served, failed.served]);
});

test("the list: GET /screens with each source's access; an old station's 404; `screens` on the event stream", async () => {
  const hub = new ScreenHub();
  hub.add(new FakeSource());
  hub.add(new Desktop({ supported: false, helper: null, changed: () => hub.changed(), title: () => "studio" }));
  const viewer = member;
  const ask = (admin: Admin, lang: "en" | "zh") => admin.handle({ method: "GET", path: "/screens", query: [], search: "", headers: {}, body: Buffer.alloc(0), viewer, lang });
  const answer = await ask(new Admin({ names: new Map(), read: async () => "{}" } as any, { screens: hub }), "zh");
  assert.equal(answer.status, 200);
  assert.deepEqual(JSON.parse((answer.body as Buffer).toString()).screens[1], {
    id: "desktop", kind: "desktop", title: "studio", width: 0, height: 0, viewers: [], controlledBy: [],
    access: { capture: false, control: false, message: "目前仅支持查看 macOS 和 Windows station 的本机屏幕" },
  });
  // What a station without screens (one from before) answers.
  assert.equal((await ask(new Admin({ names: new Map(), read: async () => "{}" } as any), "en")).status, 404);
  // On the event stream, in each stream's language.
  const events = new Events({ readers: { read: async () => "[]" } as any, subscribe: () => () => {}, host: async () => ({}), jobLog: () => null, tail: () => "", outputAt: () => null, sessionExists: () => false });
  const zh = (await events.open(viewer, "zh", false, [], [])).body as AsyncIterableIterator<Buffer>;
  const en = (await events.open(viewer, "en", false, [], [])).body as AsyncIterableIterator<Buffer>;
  events.screens((lang) => hub.listed(lang));
  const told = async (body: AsyncIterableIterator<Buffer>) => {
    for (;;) {
      const text = (await body.next()).value!.toString();
      const m = /event: screens\ndata: (.*)\n/.exec(text);
      if (m) return JSON.parse(m[1]!);
    }
  };
  assert.equal((await told(zh)).screens[1].access.message, "目前仅支持查看 macOS 和 Windows station 的本机屏幕");
  assert.equal((await told(en)).screens[1].access.message, "Only macOS and Windows stations' own screens can be viewed for now");
  await zh.return!();
  await en.return!();
});

test("input as macOS posts it: buttons, click counts, drags, keys by their place, modifiers, text", () => {
  const mac = new MacInput();
  const at = (x: number, y: number, kind: "down" | "up" | "move", buttons: number) => ({ t: "pointer" as const, kind, x, y, buttons });
  assert.deepEqual(mac.ops(at(0.5, 0.5, "down", 1), 0), [{ op: "mouse", type: "down", x: 0.5, y: 0.5, button: 0, buttons: 1, clicks: 1, flags: 0 }]);
  assert.deepEqual(mac.ops(at(0.6, 0.5, "move", 1), 10), [{ op: "mouse", type: "move", x: 0.6, y: 0.5, button: 0, buttons: 1, clicks: 0, flags: 0 }]);
  assert.deepEqual(mac.ops(at(0.5, 0.5, "up", 0), 20), [{ op: "mouse", type: "up", x: 0.5, y: 0.5, button: 0, buttons: 0, clicks: 1, flags: 0 }]);
  // Again soon and near: a double click, its up too.
  assert.equal((mac.ops(at(0.501, 0.5, "down", 1), 100)[0] as any).clicks, 2);
  assert.equal((mac.ops(at(0.501, 0.5, "up", 0), 120)[0] as any).clicks, 2);
  // Too late: one click again.
  assert.equal((mac.ops(at(0.501, 0.5, "down", 1), 120 + CLICK_MS + 1)[0] as any).clicks, 1);
  mac.ops(at(0.501, 0.5, "up", 0), 700);
  // The right button, then the middle one while it is held.
  assert.deepEqual(mac.ops(at(0.2, 0.2, "down", 2), 2000)[0], { op: "mouse", type: "down", x: 0.2, y: 0.2, button: 2, buttons: 2, clicks: 1, flags: 0 });
  assert.equal((mac.ops(at(0.2, 0.2, "down", 6), 2010)[0] as any).button, 1);
  assert.deepEqual(mac.ops(at(0.2, 0.2, "up", 4), 2020)[0], { op: "mouse", type: "up", x: 0.2, y: 0.2, button: 2, buttons: 4, clicks: 1, flags: 0 });
  assert.deepEqual(mac.ops({ t: "wheel", x: 0.1, y: 0.9, dx: 0, dy: 120 }, 0), [{ op: "scroll", x: 0.1, y: 0.9, dx: 0, dy: 120, flags: 0 }]);
  // ⌘C by its place, whatever the layout; arrows as a Mac keyboard has them.
  assert.deepEqual(mac.ops({ t: "key", kind: "down", key: "c", code: "KeyC", mods: 4 }, 0), [{ op: "key", keycode: KEYCODES.KeyC, down: true, flags: FLAGS.command }]);
  assert.deepEqual(mac.ops({ t: "key", kind: "up", key: "ArrowUp", code: "ArrowUp", mods: 9 }, 0), [{ op: "key", keycode: 0x7e, down: false, flags: FLAGS.alt | FLAGS.shift | FLAGS.numericPad | FLAGS.fn }]);
  // A key of no known place types what it says; not with ⌘ or ctrl, and not on its up.
  assert.deepEqual(mac.ops({ t: "key", kind: "down", key: "é", code: "", mods: 8 }, 0), [{ op: "text", text: "é" }]);
  assert.deepEqual(mac.ops({ t: "key", kind: "up", key: "é", code: "", mods: 0 }, 0), []);
  assert.deepEqual(mac.ops({ t: "key", kind: "down", key: "é", code: "", mods: 4 }, 0), []);
  assert.deepEqual(mac.ops({ t: "key", kind: "down", key: "Unidentified", code: "", mods: 0 }, 0), []);
  assert.deepEqual(mac.ops({ t: "text", text: "你好" }, 0), [{ op: "text", text: "你好" }]);
  assert.equal(parseInput({ t: "wheel", x: 0, y: 0, dx: 1e9, dy: -1e9 })?.t, "wheel");
  assert.deepEqual(parseInput({ t: "wheel", x: 0, y: 0, dx: 1e9, dy: -1e9 }), { t: "wheel", x: 0, y: 0, dx: 10_000, dy: -10_000 });
  assert.equal(parseInput({ t: "key", kind: "down", key: "x".repeat(65), code: "KeyX" }), null);
});


test("input as Windows posts it: buttons, a wheel in its units, keys by their scan code, modifiers pressed round a key", () => {
  const win = new WinInput();
  const at = (x: number, y: number, kind: "down" | "up" | "move", buttons: number) => ({ t: "pointer" as const, kind, x, y, buttons });
  assert.deepEqual(win.ops(at(0.5, 0.5, "down", 1)), [{ op: "mouse", type: "down", x: 0.5, y: 0.5, button: 0 }]);
  assert.deepEqual(win.ops(at(0.6, 0.5, "move", 1)), [{ op: "mouse", type: "move", x: 0.6, y: 0.5, button: 0 }]);
  assert.deepEqual(win.ops(at(0.6, 0.5, "up", 0)), [{ op: "mouse", type: "up", x: 0.6, y: 0.5, button: 0 }]);
  // The right button, then the middle one while it is held, and the right one let go.
  assert.equal((win.ops(at(0.2, 0.2, "down", 2))[0] as any).button, 2);
  assert.equal((win.ops(at(0.2, 0.2, "down", 6))[0] as any).button, 1);
  assert.equal((win.ops(at(0.2, 0.2, "up", 4))[0] as any).button, 2);
  // A page's notch (100 pixels down) is Windows' (120 up); a trackpad's small ones add up to whole units.
  assert.deepEqual(win.ops({ t: "wheel", x: 0.1, y: 0.9, dx: 0, dy: 100 }), [{ op: "wheel", x: 0.1, y: 0.9, dx: 0, dy: -120 }]);
  assert.deepEqual(win.ops({ t: "wheel", x: 0.1, y: 0.9, dx: 0.5, dy: 0 }), []);
  assert.deepEqual(win.ops({ t: "wheel", x: 0.1, y: 0.9, dx: 0.5, dy: 0 }), [{ op: "wheel", x: 0.1, y: 0.9, dx: 1, dy: 0 }]);
  // Ctrl+C as a keyboard gives it: Ctrl down first, so nothing pressed round C.
  assert.deepEqual(win.ops({ t: "key", kind: "down", key: "Control", code: "ControlLeft", mods: 2 }), [{ op: "key", scan: 0x1d, ext: false, vk: 0, down: true }]);
  assert.deepEqual(win.ops({ t: "key", kind: "down", key: "c", code: "KeyC", mods: 2 }), [{ op: "key", scan: KEYS.KeyC!.scan, ext: false, vk: 0, down: true }]);
  win.ops({ t: "key", kind: "up", key: "c", code: "KeyC", mods: 2 });
  win.ops({ t: "key", kind: "up", key: "Control", code: "ControlLeft", mods: 0 });
  // A phone's keys row (⌃ held for the next key, no Ctrl of its own): Ctrl and Shift pressed round it.
  assert.deepEqual(win.ops({ t: "key", kind: "down", key: "V", code: "KeyV", mods: 2 | 8 }), [
    { op: "key", scan: 0x1d, ext: false, vk: 0, down: true },
    { op: "key", scan: 0x2a, ext: false, vk: 0, down: true },
    { op: "key", scan: 0x2f, ext: false, vk: 0, down: true },
    { op: "key", scan: 0x2a, ext: false, vk: 0, down: false },
    { op: "key", scan: 0x1d, ext: false, vk: 0, down: false },
  ]);
  // E0 keys, and one Windows says by its virtual key.
  assert.deepEqual(win.ops({ t: "key", kind: "up", key: "ArrowUp", code: "ArrowUp", mods: 0 }), [{ op: "key", scan: 0x48, ext: true, vk: 0, down: false }]);
  assert.deepEqual(win.ops({ t: "key", kind: "down", key: "Meta", code: "MetaLeft", mods: 4 }), [{ op: "key", scan: 0x5b, ext: true, vk: 0, down: true }]);
  assert.deepEqual(win.ops({ t: "key", kind: "down", key: "Pause", code: "Pause", mods: 0 }), [{ op: "key", scan: 0, ext: false, vk: 0x13, down: true }]);
  // A key of no known place types what it says; not with ctrl or the Windows key, and not on its up.
  assert.deepEqual(win.ops({ t: "key", kind: "down", key: "é", code: "", mods: 8 }), [{ op: "text", text: "é" }]);
  assert.deepEqual(win.ops({ t: "key", kind: "up", key: "é", code: "", mods: 0 }), []);
  assert.deepEqual(win.ops({ t: "key", kind: "down", key: "é", code: "", mods: 2 }), []);
  assert.deepEqual(win.ops({ t: "text", text: "你好" }), [{ op: "text", text: "你好" }]);
});

/// stillfail-screen as native/screen's is, as a process (node running this): `status` says a display; `view` answers
/// its request with its info (or, asked for a 1-pixel view, that it cannot capture), each next with a frame (the first
/// with its config; asked for a 2-pixel view, it ends by itself after the second), and notes the request and each
/// input in its log, a JSON line each.
const FAKE_SCREEN = `
const fs = require("node:fs");
const [mode, log] = process.argv.slice(2);
if (mode === "status") { console.log(JSON.stringify({ ok: true, display: { id: 1, width: 2560, height: 1600 }, capture: true })); process.exit(0); }
if (mode === "scale") {
  const kept = log + ".scale", steps = [100, 125, 150, 175, 200, 225, 250, 300, 350], asked = process.argv[4];
  if (asked !== undefined) {
    if (!steps.includes(Number(asked))) { console.log(JSON.stringify({ error: asked + "% is not a step of this display" })); process.exit(0); }
    fs.writeFileSync(kept, asked); fs.appendFileSync(log, JSON.stringify({ scale: Number(asked) }) + "\\n");
  }
  console.log(JSON.stringify({ percent: fs.existsSync(kept) ? Number(fs.readFileSync(kept, "utf8")) : 300, recommended: 150, steps }));
  process.exit(0);
}
if (mode === "resolution") {
  const kept = log + ".resolution", modes = ["2560x1600", "1920x1200", "1600x1200"], asked = process.argv[4];
  if (asked !== undefined) {
    if (!modes.includes(asked)) { console.log(JSON.stringify({ error: asked + " is not a mode of this display" })); process.exit(0); }
    fs.writeFileSync(kept, asked); fs.appendFileSync(log, JSON.stringify({ resolution: asked }) + "\\n");
  }
  const [w, h] = (fs.existsSync(kept) ? fs.readFileSync(kept, "utf8") : "2560x1600").split("x").map(Number);
  console.log(JSON.stringify({ width: w, height: h, modes: modes.map((m) => ({ width: Number(m.split("x")[0]), height: Number(m.split("x")[1]) })) }));
  process.exit(0);
}
const out = (kind, payload) => { const head = Buffer.alloc(5); head[0] = kind; head.writeUInt32BE(payload.length, 1); process.stdout.write(Buffer.concat([head, payload])); };
let carry = Buffer.alloc(0), request = null, n = 0;
process.stdin.on("data", (chunk) => {
  carry = Buffer.concat([carry, chunk]);
  if (request === null) {
    const at = carry.indexOf(10); if (at < 0) return;
    request = JSON.parse(carry.subarray(0, at)); carry = carry.subarray(at + 1);
    fs.appendFileSync(log, JSON.stringify(request) + "\\n");
    if (request.maxWidth === 1) { out(1, Buffer.from(JSON.stringify({ error: "no display to capture", code: "display" }))); return process.exit(0); }
    out(1, Buffer.from(JSON.stringify({ width: 1280, height: 800, encoder: "fake" })));
  }
  while (carry.length >= 5) {
    const length = carry.readUInt32BE(1); if (carry.length < 5 + length) return;
    const kind = carry[0], payload = carry.subarray(5, 5 + length); carry = carry.subarray(5 + length);
    if (kind === 1) {
      n++;
      if (n === 1) { const c = Buffer.alloc(8); c.writeUInt32BE(1280, 0); c.writeUInt32BE(800, 4); out(2, Buffer.concat([c, Buffer.from([1, 66, 0, 31])])); }
      const f = Buffer.alloc(9); f[0] = n === 1 ? 1 : 0; f.writeBigUInt64BE(BigInt(n * 1000), 1); out(3, Buffer.concat([f, Buffer.from([0, 0, 0, 1, n])]));
      if (request.maxWidth === 2 && n === 2) process.stdout.end(() => process.exit(3));
    } else if (kind === 3) fs.appendFileSync(log, payload.toString() + "\\n");
  }
});
process.stdin.on("end", () => process.exit(0));
`;

test("Windows' desktop: a stillfail-screen process a view, asked for each frame, input as Windows posts it; its size as it says", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sf-winscreen-"));
  const script = join(dir, "fake-screen.cjs");
  const log = join(dir, "log");
  writeFileSync(script, FAKE_SCREEN);
  writeFileSync(log, "");
  const started: string[][] = [];
  const start = (_binary: string, args: string[]) => (started.push(args), spawn(process.execPath, [script, args[0]!, log], { stdio: ["pipe", "pipe", "inherit"] }));
  const none = new WindowsDesktop({ binary: null, changed: () => {} });
  assert.equal(none.access().unsupported, "helper");
  await assert.rejects(none.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }), (e: ScreenRefused) => e.status === 501 && e.key === "station.screen.noHelper");
  let changed = 0;
  const desktop = new WindowsDesktop({ binary: "stillfail-screen.exe", changed: () => changed++, start, title: () => "PC" });
  assert.deepEqual(desktop.access(), { capture: true, control: true });
  assert.deepEqual(desktop.clipboard(), ["text", "png"]);
  await desktop.refresh(true);
  assert.deepEqual(started, [["status"]]);
  assert.deepEqual(desktop.size(), { width: 2560, height: 1600 });
  assert.equal(changed, 1);
  // Looked at a moment ago: not asked again.
  await desktop.refresh();
  assert.equal(started.length, 1);
  await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: [] }), (e: ScreenRefused) => e.status === 415);
  const view = await desktop.open({ maxWidth: 1280, maxHeight: 800, codecs: ["h264", "jpeg"] });
  assert.deepEqual(started.at(-1), ["view"]);
  // How its pictures are made, as its info named the encoder (none says "software": the hardware's).
  assert.deepEqual(view.video?.(), { capture: "Windows.Graphics.Capture", encoder: "fake", hardware: true });
  assert.deepEqual(await view.next(), { key: true, ts: 1000, data: new Uint8Array([0, 0, 0, 1, 1]), config: { codec: "h264", width: 1280, height: 800, description: new Uint8Array([1, 66, 0, 31]) } });
  await view.input({ t: "key", kind: "down", key: "c", code: "KeyC", mods: 0 });
  await view.input({ t: "pointer", kind: "down", x: 0.25, y: 0.5, buttons: 1 });
  // Its input is had before the next frame is answered (it reads in order).
  assert.deepEqual(await view.next(), { key: false, ts: 2000, data: new Uint8Array([0, 0, 0, 1, 2]) });
  const lines = readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(lines, [
    { codec: "h264", maxWidth: 1280, maxHeight: 800 },
    { op: "key", scan: 0x2e, ext: false, vk: 0, down: true },
    { op: "mouse", type: "down", x: 0.25, y: 0.5, button: 0 },
  ]);
  // Closed: a pending frame is none.
  const pending = view.next();
  view.close();
  assert.equal(await pending, null);
  // H.265 asked of it: as its info says what it made; one that says nothing (from before H.265) made H.264.
  const asked = await desktop.open({ maxWidth: 1280, maxHeight: 800, codecs: ["h265", "h264"] });
  assert.equal((await asked.next())?.config?.codec, "h264");
  assert.equal(readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l)).at(-1).codec, "h265");
  asked.close();
  // The 帧率 asked: in its request (it captures and encodes at it); none asked, none said (above).
  const capped = await desktop.open({ maxWidth: 1280, maxHeight: 800, codecs: ["h264"], fps: 120 });
  assert.equal(readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l)).at(-1).fps, 120);
  capped.close();
  // One that cannot capture says why.
  await assert.rejects(desktop.open({ maxWidth: 1, maxHeight: 1, codecs: ["jpeg"] }), (e: ScreenRefused) => e.status === 503 && /no display to capture/.test(e.message));
  await desktop.close();
  rmSync(dir, { recursive: true, force: true });
});

test("Windows' desktop: a view whose process ends by itself goes on in a new one, from its config; one that keeps ending ends", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sf-winscreen-"));
  const script = join(dir, "fake-screen.cjs");
  const log = join(dir, "log");
  writeFileSync(script, FAKE_SCREEN);
  writeFileSync(log, "");
  let views = 0;
  const start = (_binary: string, args: string[]) => (args[0] === "view" && views++, spawn(process.execPath, [script, args[0]!, log], { stdio: ["pipe", "pipe", "inherit"] }));
  const desktop = new WindowsDesktop({ binary: "stillfail-screen.exe", changed: () => {}, start });
  const view = await desktop.open({ maxWidth: 2, maxHeight: 2, codecs: ["h264"] });
  const frames = [];
  for (let f = await view.next(); f !== null; f = await view.next()) frames.push(f);
  // Two frames a process: the first and three started again, each from its config and a key frame; then it ends.
  assert.equal(views, 4);
  assert.equal(frames.length, 8);
  assert.deepEqual(frames.map((f) => f.key), [true, false, true, false, true, false, true, false]);
  assert.ok(frames.filter((_, i) => i % 2 === 0).every((f) => f.config?.codec === "h264"));
  // Ended: closed as a view the station closes is (nothing more started).
  view.close();
  assert.equal(await view.next(), null);
  assert.equal(views, 4);
  await desktop.close();
  rmSync(dir, { recursive: true, force: true });
});

test("Windows' desktop: the display's scale set while viewed, put back as it was once the last view ends", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sf-winscreen-"));
  const script = join(dir, "fake-screen.cjs");
  const log = join(dir, "log");
  writeFileSync(script, FAKE_SCREEN);
  writeFileSync(log, "");
  const start = (_binary: string, args: string[]) => spawn(process.execPath, [script, args[0]!, log, ...args.slice(1)], { stdio: ["pipe", "pipe", "inherit"] });
  const desktop = new WindowsDesktop({ binary: "stillfail-screen.exe", changed: () => {}, start });
  const steps = [100, 125, 150, 175, 200, 225, 250, 300, 350];
  assert.deepEqual(await desktop.scale(), { percent: 300, recommended: 150, steps });
  const a = await desktop.open({ maxWidth: 1280, maxHeight: 800, codecs: ["h264"] });
  const b = await desktop.open({ maxWidth: 1280, maxHeight: 800, codecs: ["h264"] });
  assert.deepEqual(await desktop.setScale(150), { percent: 150, recommended: 150, steps });
  assert.deepEqual(await desktop.setScale(125), { percent: 125, recommended: 150, steps });
  // Not one of its steps: refused as stillfail-screen says, nothing changed.
  await assert.rejects(desktop.setScale(130), /130% is not a step/);
  assert.equal((await desktop.scale())?.percent, 125);
  // One view left: as it was set.
  a.close();
  assert.equal((await desktop.scale())?.percent, 125);
  // The last one gone: as it was before the first change (300%, not 150%).
  b.close();
  assert.equal((await desktop.scale())?.percent, 300);
  const scales = readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l)).filter((l) => "scale" in l).map((l) => l.scale);
  assert.deepEqual(scales, [150, 125, 300]);
  await desktop.close();
  rmSync(dir, { recursive: true, force: true });
});

test("Windows' desktop: the display's resolution set while viewed, put back as it was once the last view ends", async () => {
  const dir = mkdtempSync(join(tmpdir(), "sf-winscreen-"));
  const script = join(dir, "fake-screen.cjs");
  const log = join(dir, "log");
  writeFileSync(script, FAKE_SCREEN);
  writeFileSync(log, "");
  const start = (_binary: string, args: string[]) => spawn(process.execPath, [script, args[0]!, log, ...args.slice(1)], { stdio: ["pipe", "pipe", "inherit"] });
  let changed = 0;
  const desktop = new WindowsDesktop({ binary: "stillfail-screen.exe", changed: () => changed++, start });
  const modes = [{ width: 2560, height: 1600 }, { width: 1920, height: 1200 }, { width: 1600, height: 1200 }];
  assert.deepEqual(await desktop.resolution(), { width: 2560, height: 1600, modes });
  const a = await desktop.open({ maxWidth: 1280, maxHeight: 800, codecs: ["h264"] });
  const b = await desktop.open({ maxWidth: 1280, maxHeight: 800, codecs: ["h264"] });
  assert.deepEqual(await desktop.setResolution(1920, 1200), { width: 1920, height: 1200, modes });
  assert.deepEqual(await desktop.setResolution(1600, 1200), { width: 1600, height: 1200, modes });
  // Not one of its modes: refused as stillfail-screen says, nothing changed.
  await assert.rejects(desktop.setResolution(1024, 768), /1024x768 is not a mode/);
  assert.equal((await desktop.resolution())?.width, 1600);
  // One view left: as it was set.
  a.close();
  assert.equal((await desktop.resolution())?.width, 1600);
  // The last one gone: as it was before the first change.
  b.close();
  assert.equal((await desktop.resolution())?.width, 2560);
  const sizes = readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l)).filter((l) => "resolution" in l).map((l) => l.resolution);
  assert.deepEqual(sizes, ["1920x1200", "1600x1200", "2560x1600"]);
  // (listed anew each time its size changed)
  assert.ok(changed >= 3);
  await desktop.close();
  rmSync(dir, { recursive: true, force: true });
});

// The real one, where it is built (a Windows machine with a display): a JPEG view of the main display.
const realScreen = WINDOWS ? screenBinary() : null;
test("Windows' desktop, for real: stillfail-screen gives a picture of the display", { skip: realScreen === null }, async () => {
  const desktop = new WindowsDesktop({ binary: realScreen, changed: () => {} });
  await desktop.refresh(true);
  assert.ok(desktop.size().width > 0);
  const view = await desktop.open({ maxWidth: 640, maxHeight: 640, codecs: ["jpeg"] });
  const first = (await view.next())!;
  assert.equal(first.config?.codec, "jpeg");
  assert.ok(first.config!.width <= 640 && first.config!.height <= 640);
  assert.deepEqual([...first.data.subarray(0, 2)], [0xff, 0xd8]);
  // A key frame asked for: the same picture again when the screen did not change.
  view.keyframe();
  assert.ok((await view.next())!.key);
  view.close();
  await desktop.close();
});

/// still.fail Helper as native/helper's is, in this process: started by `launch` (the station's `open`) with its socket
/// and token; `status` as `status` is, `permissions.show` noted (its window then up), `quit` noted, `screen.view`
/// (and `simulator.view`) answering with made-up frames and noting the input. `restartOnce`: its next view asks to start again (a grant taken
/// since it started), and it is back on its socket a moment later, as the app started again is.
class FakeHelperApp {
  launches = 0;
  quits = 0;
  shown: any[] = [];
  inputs: any[] = [];
  views: any[] = [];
  /// What views asked of the clipboard (messages 4, 5, 6), and how the latest view is told of a copy (message 5).
  clips: Buffer[] = [];
  watches: number[] = [];
  reveals: string[] = [];
  copy: ((payload: Buffer) => void) | null = null;
  asking = false;
  restartOnce = false;
  status: any;
  #server: net.Server | null = null;
  #where: { path: string; token: string } | null = null;
  #conns = new Set<net.Socket>();
  watching = 0;
  constructor(status: any) {
    this.status = status;
  }
  #closed = false;
  launch = async (_app: string, env: Record<string, string>) => {
    // Closed with the test: a station still watching it must not have it listen again (the test would never end).
    if (this.#closed) throw new Error("the test's helper is closed");
    this.launches++;
    this.#where = { path: env.STILLFAIL_HELPER_SOCKET!, token: env.STILLFAIL_HELPER_TOKEN! };
    await this.#listen();
  };
  async #listen() {
    const { path, token } = this.#where!;
    rmSync(path, { force: true });
    const server = net.createServer((conn) => this.#serve(conn, token));
    await new Promise<void>((resolve) => server.listen(path, resolve));
    this.#server = server;
  }
  #stop() {
    this.#server?.close();
    this.#server = null;
    rmSync(this.#where!.path, { force: true });
  }
  close() {
    this.#closed = true;
    this.crash();
  }
  /// It ends by itself (macOS's Quit & Reopen, a crash): its socket gone, every connection with it.
  crash() {
    this.#stop();
    for (const c of this.#conns) c.destroy();
  }
  /// macOS starts it again itself, from its place (not the station's launch).
  async reopen() {
    await this.#listen();
  }
  #serve(conn: net.Socket, token: string) {
    this.#conns.add(conn);
    conn.on("close", () => this.#conns.delete(conn));
    let carry = Buffer.alloc(0);
    let viewing: ((chunk: Buffer) => void) | null = null;
    const line = (v: unknown) => conn.end(`${JSON.stringify(v)}\n`);
    // The station closing a view while a frame is on its way: nothing to it.
    conn.on("error", () => {});
    conn.on("data", (chunk: Buffer) => {
      if (viewing) return viewing(chunk);
      carry = Buffer.concat([carry, chunk]);
      const at = carry.indexOf(10);
      if (at < 0) return;
      const ask = JSON.parse(carry.subarray(0, at).toString());
      const rest = carry.subarray(at + 1);
      if (ask.token !== token) return line({ error: "not the station's token" });
      switch (ask.op) {
        case "hello":
          return line({ ok: true, v: 1 });
        case "status":
          return line({ ...this.status, asking: this.asking });
        case "permissions.show":
          this.shown.push(ask.words);
          this.asking = true;
          return line({ ok: true });
        case "watch":
          this.watching++;
          conn.write(`${JSON.stringify({ ok: true })}\n`);
          return;
        case "quit":
          this.quits++;
          line({ ok: true });
          return this.#stop();
        case "screen.view":
        case "simulator.view": {
          this.views.push(ask);
          if (this.restartOnce) {
            this.restartOnce = false;
            conn.end(helperMessage(1, Buffer.from(JSON.stringify({ error: "restarting", code: "restart" }))));
            this.#stop();
            setImmediate(() => void this.#listen());
            return;
          }
          conn.write(helperMessage(1, Buffer.from(JSON.stringify({ width: 64, height: 36, encoder: "fake", ...(ask.audio === true ? { audio: true } : {}) }))));
          if (ask.audio === true) conn.write(helperMessage(8, Buffer.from(JSON.stringify({ codec: "pcm_s16le", sampleRate: 48000, channels: 2 }))));
          let sounds = 0;
          this.copy = (payload) => conn.write(helperMessage(5, payload));
          let n = 0;
          let key = true;
          let inbox = Buffer.alloc(0);
          viewing = (more) => {
            inbox = Buffer.concat([inbox, more]);
            while (inbox.length >= 5 && inbox.length >= 5 + inbox.readUInt32BE(1)) {
              const kind = inbox[0]!;
              const payload = inbox.subarray(5, 5 + inbox.readUInt32BE(1));
              inbox = inbox.subarray(5 + payload.length);
              if (kind === 1) {
                n++;
                if (n === 1) {
                  const size = Buffer.alloc(8);
                  size.writeUInt32BE(64, 0);
                  size.writeUInt32BE(36, 4);
                  conn.write(helperMessage(2, Buffer.concat([size, Buffer.from([1, 66, 0, 30])])));
                }
                const head = Buffer.alloc(9);
                head[0] = key ? 1 : 0;
                head.writeBigUInt64BE(BigInt(n * 1000), 1);
                key = false;
                conn.write(helperMessage(3, Buffer.concat([head, Buffer.from([0, 0, 0, 1, n])])));
              } else if (kind === 2) key = true;
              else if (kind === 3) this.inputs.push(JSON.parse(payload.toString()));
              else if (kind === 4) this.clips.push(Buffer.from(payload));
              else if (kind === 5) this.watches.push(payload[0]!);
              else if (kind === 6) this.reveals.push(payload.toString());
              else if (kind === 9) {
                // A packet of system output, 20 ms on from the last; counted on the view's ask.
                ask.audioAsked = (ask.audioAsked ?? 0) + 1;
                const packet = Buffer.alloc(3848, ++sounds);
                packet.writeBigUInt64BE(BigInt(1_000_000 + sounds * 20_000), 0);
                conn.write(helperMessage(9, packet));
              }
            }
          };
          if (rest.length > 0) viewing(rest);
          return;
        }
      }
    });
  }
}

/// A release's helper app (its code files only) and a station's data directory for it.
function helperRelease() {
  const root = mkdtempSync(join(tmpdir(), "helper-"));
  const app = join(root, "release", HELPER_APP);
  mkdirSync(join(app, "Contents/MacOS"), { recursive: true });
  mkdirSync(join(app, "Contents/_CodeSignature"), { recursive: true });
  writeFileSync(join(app, "Contents/MacOS/stillfail-helper"), "code 1");
  writeFileSync(join(app, "Contents/Info.plist"), "<plist/>");
  writeFileSync(join(app, "Contents/_CodeSignature/CodeResources"), "signed 1");
  return { app, dir: join(root, "data", "helper") };
}

const display = { id: 1, width: 3024, height: 1964 };
const responsible = (dir: string) => ({ pid: 1, path: join(dir, HELPER_APP), name: "still.fail Helper" });

// Unix sockets: the helper is macOS's; Windows' pipes are not these paths.
test("the desktop: unsupported, or without its helper, says so; a grant missing puts the helper's window up, once an attempt", { skip: WINDOWS }, async () => {
  const off = new Desktop({ supported: false, helper: null, changed: () => {} });
  assert.deepEqual(off.access(), { capture: false, control: false, unsupported: "platform" });
  await assert.rejects(off.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }), (e: ScreenRefused) => e.status === 501 && e.key === "station.screen.unsupported");
  const lost = new Desktop({ supported: true, helper: null, changed: () => {} });
  assert.equal(lost.access().unsupported, "helper");

  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: false, control: false, display, responsible: responsible(dir), live: { capture: false, control: false } });
  const helper = new HelperApp({ app, dir, launch: fake.launch });
  let changed = 0;
  const desktop = new Desktop({ supported: true, helper, changed: () => changed++, lang: () => "en" });
  // Nothing said before it is looked at; the helper not started for nothing.
  assert.deepEqual(desktop.access(), { capture: true, control: true });
  assert.equal(fake.launches, 0);
  await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: [] }), (e: ScreenRefused) => e.status === 415);
  await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }), (e: ScreenRefused) => e.status === 503 && e.key === "station.screen.captureOff" && e.access?.asking === true);
  // Started once, from its copy in the station's data, its token the station's only.
  assert.equal(fake.launches, 1);
  assert.ok(existsSync(join(dir, HELPER_APP, "Contents/MacOS/stillfail-helper")));
  assert.equal(statSync(join(dir, "token")).mode & 0o777, 0o600);
  // Its window up, in the station's words; the grants it asks for those it has.
  assert.equal(fake.shown.length, 1);
  assert.equal(fake.shown[0].title, "Let still.fail see and control this Mac");
  assert.equal(fake.shown[0].panel["permission_flow.panel.title"], "Drag the app below into the list above to allow **%2$@**.");
  assert.equal(fake.shown[0].panel["permission_flow.pane.screen_recording"], "Screen Recording");
  assert.deepEqual(desktop.access(), { capture: false, control: false, app: "still.fail Helper", path: join(dir, HELPER_APP), asking: true });
  assert.equal(desktop.size().width, 3024);
  assert.ok(changed >= 1);
  // Opened again: up again (it is brought to the front), not twice at once.
  await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }));
  assert.equal(fake.shown.length, 2);
  assert.equal(fake.launches, 1);
  // Granted: seen at the next look.
  fake.status = { ...fake.status, capture: true, control: true };
  fake.asking = false;
  await desktop.refresh(true);
  assert.deepEqual(desktop.access(), { capture: true, control: true, app: "still.fail Helper", path: join(dir, HELPER_APP) });
  await desktop.close();
  fake.close();
});

test("the helper app: found again by the station's next process, started anew when its code changed", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: true, control: true, display });
  // Each made when its process starts: it reads the token the one before left.
  const stations: HelperApp[] = [];
  const station = () => (stations.push(new HelperApp({ app, dir, launch: fake.launch })), stations.at(-1)!);
  await station().request({ op: "status" });
  // The next station process (a handover): the same app, by the token the first one left.
  await station().request({ op: "status" });
  assert.equal(fake.launches, 1);
  // A release with other code: the running one quits, the new copy starts.
  writeFileSync(join(app, "Contents/MacOS/stillfail-helper"), "code 2");
  await station().request({ op: "status" });
  assert.equal(fake.quits, 1);
  assert.equal(fake.launches, 2);
  assert.equal(readFileSync(join(dir, HELPER_APP, "Contents/MacOS/stillfail-helper"), "utf8"), "code 2");
  // All of them stopping at once: none watching starts it again when another's quit ends it.
  await Promise.all(stations.map((s) => s.quit()));
  fake.close();
});

test("the desktop's view: a connection to the helper, asked for each frame, its config on the first, input as macOS's", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: true, control: true, display, live: { capture: false, control: true } });
  // Granted since it started: its first view has it start again, and the view is asked for once more.
  fake.restartOnce = true;
  const desktop = new Desktop({ supported: true, helper: new HelperApp({ app, dir, launch: fake.launch }), changed: () => {} });
  const view = await desktop.open({ maxWidth: 1280, maxHeight: 720, codecs: ["h264", "jpeg"] });
  assert.equal(fake.shown.length, 0, "nothing missing, no window");
  assert.equal(fake.views.length, 2);
  assert.deepEqual(fake.views[1], { op: "screen.view", codec: "h264", maxWidth: 1280, maxHeight: 720, display: 1, token: fake.views[1].token });
  const first = (await view.next())!;
  assert.deepEqual(first, { key: true, ts: 1000, data: new Uint8Array([0, 0, 0, 1, 1]), config: { codec: "h264", width: 64, height: 36, description: new Uint8Array([1, 66, 0, 30]) } });
  assert.deepEqual(await view.next(), { key: false, ts: 2000, data: new Uint8Array([0, 0, 0, 1, 2]) });
  view.keyframe();
  assert.equal((await view.next())!.key, true);
  await view.input({ t: "key", kind: "down", key: "v", code: "KeyV", mods: 4 });
  // Its input is had before the next frame is answered (the helper reads in order).
  await view.next();
  assert.deepEqual(fake.inputs, [{ op: "key", keycode: KEYCODES.KeyV, down: true, flags: FLAGS.command }]);
  // Closed: a pending frame is none.
  const pending = view.next();
  view.close();
  assert.equal(await pending, null);
  assert.equal(await view.next(), null);
  // A client showing Display P3 as such: the helper asked for it.
  const wide = await desktop.open({ maxWidth: 1280, maxHeight: 720, codecs: ["h264"], gamut: "p3" });
  assert.equal(fake.views.at(-1).gamut, "p3");
  wide.close();
  await desktop.close();
  fake.close();
});

test("the desktop for a view without H.264 (an agent's): JPEG pictures, its config without a description", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: true, control: true, display, live: { capture: true, control: true } });
  const desktop = new Desktop({ supported: true, helper: new HelperApp({ app, dir, launch: fake.launch }), changed: () => {} });
  await assert.rejects(desktop.open({ maxWidth: 1280, maxHeight: 720, codecs: [] }), (e: ScreenRefused) => e.status === 415);
  const view = await desktop.open({ maxWidth: 1280, maxHeight: 720, codecs: ["jpeg"] });
  assert.equal(fake.views[0].codec, "jpeg");
  assert.deepEqual((await view.next())!.config, { codec: "jpeg", width: 64, height: 36 });
  view.close();
  // The 帧率 asked goes to the helper (ScreenCaptureKit's frame interval, the encoder's expected rate).
  const capped = await desktop.open({ maxWidth: 1280, maxHeight: 720, codecs: ["h264"], fps: 30 });
  assert.equal(fake.views.at(-1).fps, 30);
  capped.close();
  await desktop.close();
  fake.close();
});

test("the Mac's desktop sends its system output to a view that asked for it, pulled packet by packet; never to one that did not", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: true, control: true, display, live: { capture: true, control: true } });
  const desktop = new Desktop({ supported: true, helper: new HelperApp({ app, dir, launch: fake.launch }), changed: () => {} });
  const hub = new ScreenHub();
  hub.add(desktop);
  // A failure must not leave the fake helper listening (the file's tests would never end).
  try {
    for (const requested of [true, false]) {
      fake.views = [];
      const v = await open(hub, member, { codecs: ["h264"], control: true, ...(requested ? { audio: "pcm_s16le" } : {}) }, "/admin/api/screens/desktop/view");
      assert.equal(v.answer.status, 200);
      if (requested) {
        // The helper asked for the system output too; the client told the format before the first packet.
        assert.equal(fake.views[0].audio, true);
        assert.deepEqual(json(await until(v.frames, KIND.audioConfig)), { codec: "pcm_s16le", sampleRate: 48000, channels: 2 });
        for (const n of [1, 2]) {
          const packet = await until(v.frames, KIND.audio);
          assert.equal(packet.length, 8 + 3840);
          assert.equal(packet.readBigUInt64BE(), BigInt(1_000_000 + n * 20_000));
          assert.deepEqual(packet.subarray(8), Buffer.alloc(3840, n));
        }
      } else {
        await until(v.frames, KIND.video);
        assert.equal(fake.views[0].audio, undefined);
      }
      await v.stream.finish();
      await v.served;
      if (!requested) assert.equal(fake.views[0].audioAsked, undefined, "no audio pulled from a view that did not ask");
    }
    // A preview never asks for it, whatever it says.
    fake.views = [];
    const peek = await desktop.open({ maxWidth: 640, maxHeight: 360, codecs: ["h264"], audio: true, peek: true });
    assert.equal(fake.views[0].audio, undefined);
    assert.equal(await peek.nextAudio!(), null);
    peek.close();
  } finally {
    await desktop.close();
    fake.close();
  }
});

test("a view the station opens itself (an agent's) shows who has it, driving or not, until it closes", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  let told = 0;
  hub.onChange(() => told++);
  const view = await hub.openAs("fake", { maxWidth: 800, maxHeight: 600, codecs: ["jpeg"] }, { name: "agent: 登录 GitHub", control: true });
  assert.deepEqual(hub.people("fake"), { viewers: ["agent: 登录 GitHub"], controlledBy: ["agent: 登录 GitHub"] });
  // A person on it too is told who drives it.
  const person = await open(hub, member, { codecs: ["jpeg"], control: false });
  const states: any[] = [];
  await until(person.frames, KIND.video, states);
  assert.deepEqual(states[1], { viewers: ["agent: 登录 GitHub", "Pat"], controlledBy: ["agent: 登录 GitHub"] });
  // Its input goes to the source with nobody's link in between.
  await view.input({ t: "text", text: "hello" });
  assert.deepEqual(source.views[0]!.inputs, [{ t: "text", text: "hello" }]);
  assert.equal((await view.next())!.ts, 1000);
  view.close();
  assert.equal(source.views[0]!.closed, true);
  assert.deepEqual(hub.people("fake"), { viewers: ["Pat"], controlledBy: [] });
  await assert.rejects(hub.openAs("elsewhere", { maxWidth: 800, maxHeight: 600, codecs: ["jpeg"] }, { name: "agent", control: false }), (e: ScreenRefused) => e.status === 404);
  assert.ok(told >= 3);
  await person.stream.finish();
  await person.served;
});

/// Moves `time` on 100 ms each time the station waits on it, until `done`: its time passes only while it waits, so
/// what it does between its waits (asking the helper over its socket) comes first however slow the machine is.
async function passing(time: ReturnType<typeof testClock>, done: () => boolean) {
  let seen = time.asked();
  for (let i = 0; i < 2_000 && !done(); i++) {
    if (time.asked() > seen) {
      seen = time.asked();
      await time.adjust(100);
    } else await new Promise((r) => setImmediate(r));
  }
  assert.ok(done(), "never came to pass");
}

test("the helper watched: ended by itself it is started again, once, its window up again for a grant still missing", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: false, control: false, display, responsible: responsible(dir) });
  const time = testClock();
  // Each time it is back: what the desktop does then, followed to its end before the helper goes again (a request of
  // it still under way as the helper went would start it, as it should).
  let backs = 0;
  let backing: Promise<void> = Promise.resolve();
  const helper: HelperApp = new HelperApp({ app, dir, launch: fake.launch, clock: time.clock, onBack: () => (backs++, (backing = desktop.helperBack())) });
  const desktop: Desktop = new Desktop({ supported: true, helper, changed: () => {}, lang: () => "en" });
  const back = async (n: number) => {
    await passing(time, () => backs === n);
    await backing;
  };
  await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }));
  assert.deepEqual([fake.launches, fake.shown.length, fake.watching], [1, 1, 1]);
  // One grant taken, then macOS quits it to reopen it, and does not: the station starts it, and asks for the other.
  fake.status = { ...fake.status, capture: true };
  fake.asking = false;
  fake.crash();
  await back(1);
  assert.deepEqual([fake.launches, fake.watching, fake.shown.length], [2, 2, 2]);
  // macOS reopened it itself this time: the station takes it as it is, a second one not started.
  fake.crash();
  await fake.reopen();
  await back(2);
  assert.deepEqual([fake.launches, fake.watching, fake.shown.length], [2, 3, 3]);
  // All granted: back once more, no window.
  fake.status = { ...fake.status, control: true };
  fake.crash();
  await fake.reopen();
  await back(3);
  assert.equal(fake.shown.length, 3, "up again only while a grant was missing");
  // Asked to end with the station: not started again.
  await desktop.close();
  await settle();
  await time.adjust(60_000);
  await settle();
  assert.equal(fake.launches, 2);
  fake.close();
});

// ── the clipboard and files dropped ──

const clipFrame = (flags: number, type: number, body: Buffer) => frame(KIND.setClipboard, Buffer.concat([Buffer.from([flags, type]), body]));

test("the clipboard: a view that drives it hears the source's copies and sets it, pasted after the keys before it", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  source.types = ["text", "png"];
  hub.add(source);
  const v = await open(hub, member);
  await until(v.frames, KIND.video);
  const view = source.views[0]!;
  assert.equal(view.watched, 1, "watched for as long as the view drives it");
  // A copy made on it: to the client as it comes (type byte, then the bytes).
  view.copied!({ type: "text", text: "复制的" });
  const copied = await until(v.frames, KIND.clipboard);
  assert.equal(copied[0], 1);
  assert.equal(copied.subarray(1).toString("utf8"), "复制的");
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
  view.copied!({ type: "png", data: new Uint8Array(png) });
  const picture = await until(v.frames, KIND.clipboard);
  assert.equal(picture[0], 2);
  assert.deepEqual(picture.subarray(1), png);
  // The client's paste: after the key it sent before it, in order.
  await v.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "key", kind: "down", key: "Meta", code: "MetaLeft", mods: 4 }))));
  await v.stream.write(clipFrame(1, 1, Buffer.from("粘贴的")));
  await v.stream.write(clipFrame(0, 2, png));
  await settle();
  assert.deepEqual(view.asks, [
    { input: { t: "key", kind: "down", key: "Meta", code: "MetaLeft", mods: 4 } },
    { clip: { type: "text", text: "粘贴的" }, paste: true },
    { clip: { type: "png", data: new Uint8Array(png) }, paste: false },
  ]);
  await v.stream.finish();
  await v.served;
  assert.equal(view.copied, null, "no longer watched once the view ended");
});

test("the clipboard only for a view that drives it: one that looks, a read-only member's, never hear it nor set it", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  source.types = ["text"];
  hub.add(source);
  const looker = await open(hub, member, { codecs: ["jpeg"], control: false });
  const reader_ = await open(hub, reader);
  await until(looker.frames, KIND.video);
  await until(reader_.frames, KIND.video);
  assert.deepEqual(source.views.map((v) => v.watched), [0, 0], "not watched for them: nothing looked at");
  for (const v of [looker, reader_]) {
    await v.stream.write(clipFrame(1, 1, Buffer.from("nope")));
    await v.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "reveal", path: "/tmp/x" }))));
  }
  await settle();
  assert.deepEqual(source.views.map((v) => v.asks), [[], []]);
  for (const v of [looker, reader_]) await v.stream.finish();
  await Promise.all([looker.served, reader_.served]);
});

test("the clipboard's bounds and types: past its bound or of a type the source does not carry, dropped; a frame past the most ends the view", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  source.types = ["text"];
  hub.add(source);
  const v = await open(hub, member);
  await until(v.frames, KIND.video);
  const view = source.views[0]!;
  // A picture to a source of text only; text past 1 MB; no type; nothing; then one within bounds.
  await v.stream.write(clipFrame(1, 2, Buffer.from([0x89, 0x50, 0x4e, 0x47])));
  await v.stream.write(clipFrame(1, 1, Buffer.alloc(CLIP_TEXT_MAX + 1, 0x61)));
  await v.stream.write(clipFrame(1, 9, Buffer.from("x")));
  await v.stream.write(clipFrame(1, 1, Buffer.alloc(0)));
  await v.stream.write(clipFrame(1, 1, Buffer.alloc(CLIP_TEXT_MAX, 0x62)));
  await settle();
  assert.equal(view.asks.length, 1);
  assert.equal((view.asks[0] as { clip: Clip }).clip.type, "text");
  assert.equal(((view.asks[0] as { clip: { text: string } }).clip.text).length, CLIP_TEXT_MAX);
  // A copy past its bound is not sent; one of a type not carried is not either.
  view.copied!({ type: "text", text: "a".repeat(CLIP_TEXT_MAX + 1) });
  view.copied!({ type: "png", data: new Uint8Array([1]) });
  view.copied!({ type: "text", text: "fits" });
  assert.equal((await until(v.frames, KIND.clipboard)).subarray(1).toString(), "fits");
  // A clipboard frame may be a picture's size (an input frame may not); past it, the view ends.
  assert.equal(MAX_CLIP_IN, 2 + CLIP_PNG_MAX);
  const head = Buffer.alloc(5);
  head[0] = KIND.setClipboard;
  head.writeUInt32BE(MAX_CLIP_IN + 1, 1);
  await v.stream.write(head);
  await v.served;
  assert.equal(view.closed, true);
  // Parsed alone: a PNG of the most size is one; a byte more is none.
  assert.ok(parseClip(Buffer.concat([Buffer.from([0, 2]), Buffer.alloc(CLIP_PNG_MAX)])));
  assert.equal(parseClip(Buffer.concat([Buffer.from([0, 2]), Buffer.alloc(CLIP_PNG_MAX + 1)])), null);
  assert.equal(MAX_IN, 64 * 1024, "other frames keep their bound");
});

test("reveal: a file shown in the file manager by a view that drives a source that can; not by one that cannot", async () => {
  const hub = new ScreenHub();
  const can = new FakeSource("can");
  can.reveal = true;
  const cannot = new FakeSource("cannot");
  hub.add(can);
  hub.add(cannot);
  const a = await open(hub, member, undefined, "/admin/api/screens/can/view");
  const b = await open(hub, member, undefined, "/admin/api/screens/cannot/view");
  const reveal = (v: typeof a, path: unknown) => v.stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "reveal", path }))));
  await reveal(a, "/Users/pat/Downloads/a.pdf");
  await reveal(a, 7);
  await reveal(b, "/Users/pat/Downloads/a.pdf");
  await settle();
  assert.deepEqual(can.views[0]!.asks, [{ reveal: "/Users/pat/Downloads/a.pdf" }]);
  assert.deepEqual(cannot.views[0]!.asks, []);
  for (const v of [a, b]) await v.stream.finish();
  await Promise.all([a.served, b.served]);
});

test("a tab is closed from a person's app (POST /screens/<id>/close) and says which session opened it; the desktop is not closed", async () => {
  const hub = new ScreenHub();
  const closed: string[] = [];
  const tab = Object.assign(new FakeSource("browser:A"), { openedBy: () => "EMBER/1.2", discard: async () => void closed.push("browser:A") });
  hub.add(tab);
  hub.add(new Desktop({ supported: false, helper: null, changed: () => hub.changed(), title: () => "studio" }));
  const [a, d] = hub.listed("en").screens;
  assert.equal(a!.closable, true);
  assert.equal(a!.openedBy, "EMBER/1.2");
  assert.equal("closable" in d!, false);
  assert.equal("openedBy" in d!, false);
  const admin = new Admin({ names: new Map(), read: async () => "{}" } as any, { screens: hub });
  const close = (id: string, viewer: Viewer, lang: "en" | "zh" = "en") =>
    admin.handle({ method: "POST", path: `/screens/${encodeURIComponent(id)}/close`, query: [], search: "", headers: {}, body: Buffer.alloc(0), viewer, lang });
  assert.equal((await close("browser:A", reader)).status, 403, "a read-only member only looks");
  assert.deepEqual(closed, []);
  assert.equal((await close("browser:A", member)).status, 200);
  assert.deepEqual(closed, ["browser:A"]);
  const desktop = await close("desktop", member, "zh");
  assert.equal(desktop.status, 405);
  assert.equal(JSON.parse((desktop.body as Buffer).toString()).error, "该画面不能在这里关闭");
  assert.equal((await close("browser:gone", member)).status, 404);
  tab.discard = async () => {
    throw new Error("No target with given id found");
  };
  const refused = await close("browser:A", member);
  assert.equal(refused.status, 502);
  assert.match(JSON.parse((refused.body as Buffer).toString()).error, /No target/);
});

test("the list says what each screen carries: its clipboard's types, where a file dropped goes and whether it can be shown", () => {
  const hub = new ScreenHub({ drop: () => "/Users/pat/Downloads" });
  const tab = new FakeSource("tab");
  tab.types = ["text"];
  const plain = new FakeSource("plain");
  plain.reveal = true;
  hub.add(tab);
  hub.add(plain);
  const [a, b] = hub.listed("en").screens;
  assert.deepEqual(a!.clipboard, ["text"]);
  assert.deepEqual(a!.drop, { folder: "/Users/pat/Downloads", reveal: false });
  assert.equal("clipboard" in b!, false, "none said for a source without a clipboard");
  assert.deepEqual(b!.drop, { folder: "/Users/pat/Downloads", reveal: true });
  // A station that takes no files says no `drop` (as one from before them).
  const none = new ScreenHub();
  none.add(new FakeSource());
  assert.equal("drop" in none.listed("en").screens[0]!, false);
  // The desktop: text and pictures, shown in Finder, wherever its helper is; none where it is not supported.
  const { app, dir } = helperRelease();
  assert.deepEqual(new Desktop({ supported: true, helper: new HelperApp({ app, dir }), changed: () => {} }).clipboard(), ["text", "png"]);
  assert.deepEqual(new Desktop({ supported: false, helper: null, changed: () => {} }).clipboard(), []);
});

test("where a dropped file goes: the home's Downloads, else the home (what is in it never listed)", () => {
  const home = mkdtempSync(join(tmpdir(), "drop-"));
  assert.equal(dropFolder(home), home, "no Downloads: the home");
  mkdirSync(join(home, "Downloads"));
  assert.equal(dropFolder(home), join(home, "Downloads"));
  rmSync(home, { recursive: true, force: true });
});

test("the desktop's clipboard: set and pasted, watched and heard, a file revealed, as the helper's messages", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: true, control: true, display, live: { capture: true, control: true } });
  const desktop = new Desktop({ supported: true, helper: new HelperApp({ app, dir, launch: fake.launch }), changed: () => {} });
  const view = await desktop.open({ maxWidth: 1280, maxHeight: 720, codecs: ["h264"] });
  const heard: Clip[] = [];
  const unwatch = view.watchClipboard!((clip) => heard.push(clip));
  await view.setClipboard!({ type: "text", text: "你好" }, true);
  await view.setClipboard!({ type: "png", data: new Uint8Array([9, 8]) }, false);
  await view.reveal!("/Users/pat/Downloads/a.pdf");
  // The helper reads in order: had by the time the next frame is answered.
  await view.next();
  assert.deepEqual(fake.watches, [1]);
  assert.deepEqual(fake.clips, [Buffer.concat([Buffer.from([1, 1]), Buffer.from("你好")]), Buffer.from([0, 2, 9, 8])]);
  assert.deepEqual(fake.reveals, ["/Users/pat/Downloads/a.pdf"]);
  assert.equal(TO_HELPER.clipboard, 4);
  // What the helper says was copied; past the bound, nothing.
  fake.copy!(helperClip({ type: "text", text: "copied" }));
  fake.copy!(Buffer.concat([Buffer.from([1]), Buffer.alloc(CLIP_TEXT_MAX + 1, 0x61)]));
  fake.copy!(helperClip({ type: "png", data: new Uint8Array([7]) }));
  await view.next();
  assert.deepEqual(heard, [{ type: "text", text: "copied" }, { type: "png", data: new Uint8Array([7]) }]);
  unwatch();
  await view.next();
  assert.deepEqual(fake.watches, [1, 0], "no longer watched: the helper stops looking");
  view.close();
  fake.close();
});

test("input as an iOS Simulator takes it: the left button a finger (from an edge, a system gesture), a wheel, keys by their HID usage, its buttons by Simulator.app's shortcuts, text typed or pasted", () => {
  const sim = new SimInput();
  const pointer = (kind: "down" | "up" | "move", x: number, y: number, buttons: number): ScreenInput => ({ t: "pointer", kind, x, y, buttons });
  // A pointer moving with nothing held, or another button: no finger.
  assert.deepEqual(sim.ops(pointer("move", 0.5, 0.5, 0)), []);
  assert.deepEqual(sim.ops(pointer("down", 0.5, 0.5, 2)), []);
  assert.deepEqual(sim.ops(pointer("down", 0.25, 0.5, 1)), [{ op: "touch", type: "begin", x: 0.25, y: 0.5 }]);
  assert.deepEqual(sim.ops(pointer("move", 0.3, 0.6, 1)), [{ op: "touch", type: "move", x: 0.3, y: 0.6 }]);
  assert.deepEqual(sim.ops(pointer("up", 0.3, 0.6, 0)), [{ op: "touch", type: "end", x: 0.3, y: 0.6 }]);
  // From the bottom edge: the home indicator's swipe, the whole gesture; out of the screen, held within it.
  assert.deepEqual(sim.ops(pointer("down", 0.5, 0.99, 1)), [{ op: "touch", type: "begin", x: 0.5, y: 0.99, edge: 3 }]);
  assert.deepEqual(sim.ops(pointer("move", 0.5, -0.2, 1)), [{ op: "touch", type: "move", x: 0.5, y: 0, edge: 3 }]);
  // The button let go where the page saw no up (the pointer left the view): the finger lifts at the next move.
  assert.deepEqual(sim.ops(pointer("move", 0.5, 0.4, 0)), [{ op: "touch", type: "end", x: 0.5, y: 0.4, edge: 3 }]);
  assert.deepEqual(sim.ops(pointer("down", 0.5, 0.01, 1))[0], { op: "touch", type: "begin", x: 0.5, y: 0.01, edge: 2 });
  sim.ops(pointer("up", 0.5, 0.3, 0));
  assert.deepEqual(sim.ops({ t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: 120 }), [{ op: "scroll", x: 0.5, y: 0.5, dx: 0, dy: 120 }]);
  assert.deepEqual(sim.ops({ t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: 0 }), []);
  const key = (kind: "down" | "up", code: string, mods = 0): ScreenInput => ({ t: "key", kind, key: "", code, mods });
  assert.deepEqual(sim.ops(key("down", "KeyA")), [{ op: "key", type: "down", usage: 0x04 }]);
  assert.deepEqual(sim.ops(key("up", "Enter")), [{ op: "key", type: "up", usage: 0x28 }]);
  assert.equal(USAGES.Digit0, 0x27);
  assert.equal(USAGES.F12, 0x45);
  assert.deepEqual(sim.ops(key("down", "Unidentified")), []);
  // A modifier held from its own key is not pressed again round the next; one only named in `mods` (a phone's keys row) is.
  assert.deepEqual(sim.ops(key("down", "ShiftLeft", 8)), [{ op: "key", type: "down", usage: 0xe1 }]);
  assert.deepEqual(sim.ops(key("down", "KeyA", 8)), [{ op: "key", type: "down", usage: 0x04 }]);
  sim.ops(key("up", "ShiftLeft"));
  assert.deepEqual(sim.ops(key("down", "KeyA", 2)), [{ op: "key", type: "down", usage: 0xe0 }, { op: "key", type: "down", usage: 0x04 }]);
  assert.deepEqual(sim.ops(key("up", "KeyA", 2)), [{ op: "key", type: "up", usage: 0x04 }, { op: "key", type: "up", usage: 0xe0 }]);
  // Simulator.app's shortcuts: the device's buttons, once (as the key goes down).
  assert.deepEqual(sim.ops(key("down", "KeyH", 12)), [{ op: "button", name: "home" }]);
  assert.deepEqual(sim.ops(key("up", "KeyH", 12)), []);
  assert.deepEqual(sim.ops(key("down", "KeyL", 4)), [{ op: "button", name: "lock" }]);
  assert.deepEqual(sim.ops(key("down", "KeyK", 4)), [{ op: "button", name: "keyboard" }]);
  assert.deepEqual(sim.ops(key("down", "KeyH", 14)), [{ op: "button", name: "app_switcher" }]);
  // ⌃⌘ with another key is that key, ⌃⌘ round it.
  assert.deepEqual(sim.ops(key("down", "KeyL", 6))[0], { op: "key", type: "down", usage: 0xe0 });
  // Text: a US keyboard's keys, shift round what needs it; anything one does not type, pasted whole.
  assert.deepEqual(sim.ops({ t: "text", text: "a!" }), [
    { op: "key", type: "down", usage: 0x04 }, { op: "key", type: "up", usage: 0x04 },
    { op: "key", type: "down", usage: 0xe1 }, { op: "key", type: "down", usage: 0x1e }, { op: "key", type: "up", usage: 0x1e }, { op: "key", type: "up", usage: 0xe1 },
  ]);
  assert.deepEqual(sim.ops({ t: "text", text: "你好 a" }), [{ op: "paste", text: "你好 a" }]);
  assert.deepEqual(sim.ops({ t: "text", text: "" }), []);
});

test("the simulators booted, as simctl lists them: their runtime's name, their screen's size", () => {
  const listed = {
    devices: {
      "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
        { udid: "5A25EA86-3568-43D6-9068-8B2CB5FADB26", name: "iPhone 17", state: "Booted", deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17" },
        { udid: "422DED77-9031-4A8D-93D7-67F1A7C4A272", name: "iPhone 17", state: "Shutdown" },
        { udid: "not a udid", name: "x", state: "Booted" },
      ],
      "com.apple.CoreSimulator.SimRuntime.xrOS-27-0": [{ udid: "6518D637-E9E0-4293-B844-EAC38471B04F", name: "Apple Vision Pro", state: "Booted" }],
      broken: "nothing",
    },
  };
  assert.deepEqual(bootedOf(listed), [
    { udid: "5A25EA86-3568-43D6-9068-8B2CB5FADB26", name: "iPhone 17", runtime: "iOS 26.2", type: "com.apple.CoreSimulator.SimDeviceType.iPhone-17" },
    { udid: "6518D637-E9E0-4293-B844-EAC38471B04F", name: "Apple Vision Pro", runtime: "visionOS 27.0", type: "" },
  ]);
  assert.deepEqual(bootedOf(null), []);
  assert.equal(runtimeName("something else"), "something else");
  assert.deepEqual(screenOf({ capabilities: { ScreenDimensionsCapability: { "main-screen-width": 1206, "main-screen-height": 2622 } } }), { width: 1206, height: 2622 });
  assert.deepEqual(screenOf({}), { width: 0, height: 0 });
});

test("a simulator a screen while it is booted: listed with its device's name and size, a view the helper's simulator.view, input as the device takes it; gone as it shuts down", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: false, control: false, display });
  const helper = new HelperApp({ app, dir, launch: fake.launch });
  const hub = new ScreenHub();
  const udid = "5A25EA86-3568-43D6-9068-8B2CB5FADB26";
  let booted = true;
  const runs: string[] = [];
  const run = async (file: string, args: string[]) => {
    runs.push([file, ...args].join(" "));
    if (file === SIMCTL && args.join(" ") === "list -j devices")
      return JSON.stringify({ devices: { "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [{ udid, name: "iPhone 17", state: booted ? "Booted" : "Shutdown", deviceTypeIdentifier: "t17" }] } });
    if (file === SIMCTL && args.join(" ") === "list -j devicetypes") return JSON.stringify({ devicetypes: [{ identifier: "t17", bundlePath: "/t17.simdevicetype" }] });
    if (file === "plutil") return JSON.stringify({ capabilities: { ScreenDimensionsCapability: { "main-screen-width": 1206, "main-screen-height": 2622 } } });
    throw new Error(`not run here: ${file}`);
  };
  const simulators = new Simulators({ screens: hub, helper, run, devices: join(dir, "no devices here") });
  await simulators.start();
  const listed = hub.listed("en").screens.find((s: any) => s.kind === "simulator") as any;
  assert.equal(listed?.id, `simulator:${udid}`);
  assert.equal(listed?.title, "iPhone 17 · iOS 26.2");
  assert.deepEqual([listed?.width, listed?.height], [1206, 2622]);
  // Its size is asked once a device type, not again as the list is looked at again.
  await simulators.refresh();
  assert.equal(runs.filter((r) => r.includes("devicetypes")).length, 1);
  assert.equal(hub.list().length, 1);

  const view = await hub.get(`simulator:${udid}`)!.open({ maxWidth: 1280, maxHeight: 720, codecs: ["h264", "jpeg"] });
  assert.deepEqual(fake.views[0], { op: "simulator.view", udid, codec: "h264", maxWidth: 1280, maxHeight: 720, token: fake.views[0].token });
  assert.equal((await view.next())!.config?.codec, "h264");
  assert.deepEqual(view.video?.(), { capture: "CoreSimulator", encoder: "fake", hardware: true });
  await view.input({ t: "pointer", kind: "down", x: 0.5, y: 0.5, buttons: 1 });
  await view.input({ t: "key", kind: "down", key: "H", code: "KeyH", mods: 12 });
  await view.next();
  assert.deepEqual(fake.inputs, [{ op: "touch", type: "begin", x: 0.5, y: 0.5 }, { op: "button", name: "home" }]);

  // Shut down: out of the list, its view ended.
  booted = false;
  await simulators.refresh();
  assert.equal(hub.list().length, 0);
  assert.equal(await view.next(), null);
  simulators.close();
  await helper.quit();
  fake.close();
});

test("no simulators where there is no helper, nor where simctl cannot be run", async () => {
  const hub = new ScreenHub();
  let asked = 0;
  await new Simulators({ screens: hub, helper: null, run: async () => (asked++, "") }).start();
  assert.equal(asked, 0);
  const { app, dir } = helperRelease();
  const failing = new Simulators({ screens: hub, helper: new HelperApp({ app, dir, launch: async () => {} }), run: async () => Promise.reject(new Error(`${SIMCTL} list -j devices: ENOENT`)), devices: join(dir, "none") });
  await failing.start();
  assert.equal(hub.list().length, 0);
  failing.close();
});

test("system audio is pull driven, old helpers decline it, and close releases a pending packet", async () => {
  const written: Buffer[] = [];
  const listeners: Record<string, ((chunk: Buffer) => void)[]> = {};
  const pipe = { write: (b: Buffer) => written.push(b), destroy: () => {}, on: (event: string, f: any) => { (listeners[event] ??= []).push(f); } };
  const say = (kind: number, body: Buffer | object) => listeners.data!.forEach((f) => f(helperMessage(kind, Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body)))));
  const view = new HelperView("h264", pipe, () => {}, new WinInput(), "Windows.Graphics.Capture", true);
  say(1, { width: 64, height: 36, codec: "h264", audio: true });
  await view.ready;
  say(8, { codec: "pcm_s16le", sampleRate: 48000, channels: 2 });
  assert.equal(written.length, 0);
  const packet = view.nextAudio();
  assert.equal(written[0]![0], TO_HELPER.audio);
  const payload = Buffer.alloc(3848, 1);
  payload.writeBigUInt64BE(123456789n, 0);
  say(9, payload);
  assert.deepEqual(await packet, { ts: 123456789, data: new Uint8Array(payload.subarray(8)) });
  const pending = view.nextAudio();
  view.close();
  assert.equal(await pending, null);
  delete listeners.data;
  const old = new HelperView("h264", pipe, () => {}, new WinInput(), "Windows.Graphics.Capture", true);
  say(1, { width: 64, height: 36, codec: "h264" });
  await old.ready;
  assert.equal(await old.nextAudio(), null);
  old.close();
});

test("negotiated system audio flows while the picture is still, and unrequested audio is never pulled", async () => {
  class SoundView extends StillView {
    audioAsked = 0;
    async nextAudio() {
      this.audioAsked++;
      return this.audioAsked === 1 ? { ts: 43210, data: new Uint8Array(3840).fill(7) } : null;
    }
  }
  for (const requested of [false, true]) {
    const hub = new ScreenHub();
    const source = new FakeSource();
    const sound = new SoundView();
    source.make = () => sound;
    hub.add(source);
    const v = await open(hub, member, { codecs: ["h264"], ...(requested ? { audio: "pcm_s16le" } : {}) });
    if (requested) {
      assert.equal(source.opened[0]!.audio, true);
      assert.deepEqual(json(await until(v.frames, KIND.audioConfig)), { codec: "pcm_s16le", sampleRate: 48000, channels: 2 });
      const packet = await until(v.frames, KIND.audio);
      assert.equal(packet.readBigUInt64BE(), 43210n);
      assert.deepEqual(packet.subarray(8), Buffer.alloc(3840, 7));
    } else {
      await until(v.frames, KIND.video);
      assert.equal(source.opened[0]!.audio, undefined);
      assert.equal(sound.audioAsked, 0);
    }
    await v.stream.finish();
    await v.served;
    assert.equal(sound.closed, true);
  }
});
