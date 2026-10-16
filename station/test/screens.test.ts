// The station's screens (docs/remote-screens.md): the view wire over a member's link in memory (framing, at most
// UNACKED frames not acknowledged, read-only members, who is on a screen, how a view ends), with a fake source; the
// list (GET /screens, `screens` on the event stream); a person's input as macOS posts it; the desktop source with a
// fake helper (its grants, its view protocol). Nothing here captures a screen: side/screen-desktop.test.ts does.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import { Events } from "../src/api/events.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { FrameIn, KIND, MAX_IN, SCREEN_TYPE, UNACKED, answerScreen, frame, parseInput } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { Desktop } from "../src/screens/desktop.ts";
import { ScreenHub, ScreenRefused } from "../src/screens/hub.ts";
import { CLICK_MS, FLAGS, KEYCODES, MacInput } from "../src/screens/mac-input.ts";
import type { Frame, ScreenAccess, ScreenInput, ScreenSource, ScreenView, ViewOptions } from "../src/screens/source.ts";
import { WINDOWS } from "../src/platform/index.ts";
import { exe, script } from "./accounts-fakes.ts";
import { settle } from "./hub-fakes.ts";
import { memoryMesh } from "./memory-mesh.ts";

const member: Viewer = { sub: "u1", email: "pat@example.com", name: "Pat", role: "member", workspace: "w", device: "d" };
const reader: Viewer = { sub: "u2", email: "vic@example.com", name: "Vic", role: "viewer", workspace: "w", device: "e" };

/// A source whose views give a frame each time one is asked for (the first a key frame with its config), and say what
/// they were asked.
class FakeView implements ScreenView {
  asked = 0;
  keyframes = 0;
  inputs: ScreenInput[] = [];
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
  }
  close() {
    this.closed = true;
  }
}

class FakeSource implements ScreenSource {
  readonly kind = "browser" as const;
  views: FakeView[] = [];
  opened: ViewOptions[] = [];
  name = "Tab";
  refuse: Error | null = null;
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
  async open(options: ViewOptions): Promise<ScreenView> {
    this.opened.push(options);
    if (this.refuse) throw this.refuse;
    const view = new FakeView();
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
async function open(hub: ScreenHub, viewer: Viewer, screen: unknown = { maxWidth: 1920, maxHeight: 1080, codecs: ["h264", "jpeg"], control: true }, path = "/admin/api/screens/fake/view") {
  const { conn, theirs } = await link();
  const stream = await conn.openBi();
  await writeLine(stream, { method: "POST", path, headers: { "stillfail-lang": "en" }, screen });
  const incoming = (await theirs.acceptBi())!;
  const heard = new Reader(incoming);
  const head = await heard.line();
  const served = answerScreen(hub, incoming, heard.carry, head, viewer, () => true);
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
  // What it asked, bounded; the codecs ours only; the height as not said.
  assert.deepEqual(source.opened, [{ maxWidth: 8192, maxHeight: 1080, codecs: ["h264"] }]);
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

test("at most two frames go unacknowledged: the source is asked for the next as one is acknowledged", async () => {
  const hub = new ScreenHub();
  const source = new FakeSource();
  hub.add(source);
  const v = await open(hub, member);
  await until(v.frames, KIND.video);
  await until(v.frames, KIND.video);
  await settle();
  const view = source.views[0]!;
  assert.equal(UNACKED, 2);
  assert.equal(view.asked, 2, "no frame is made while two are not acknowledged");
  // The first decoded: one more.
  await v.stream.write(frame(KIND.ack, ts8(1000)));
  assert.equal((await until(v.frames, KIND.video)).readBigUInt64BE(1), 3000n);
  await settle();
  assert.equal(view.asked, 3);
  // An ack says all up to it were decoded: two more.
  await v.stream.write(frame(KIND.ack, ts8(3000)));
  await until(v.frames, KIND.video);
  await until(v.frames, KIND.video);
  await settle();
  assert.equal(view.asked, 5);
  // A short ack says nothing.
  await v.stream.write(frame(KIND.ack, Buffer.alloc(3)));
  await settle();
  assert.equal(view.asked, 5);
  // A key frame asked for goes to the source.
  await v.stream.write(frame(KIND.keyframe, Buffer.alloc(0)));
  await settle();
  assert.equal(view.keyframes, 1);
  await v.stream.finish();
  await v.served;
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
  assert.equal((await body(none)).error, "This screen isn't on this station any more");
  const codecs = await open(hub, member, { codecs: ["vp9"] });
  assert.equal(codecs.answer.status, 400);
  const path = await open(hub, member, { codecs: ["h264"] }, "/admin/api/screens/fake");
  assert.equal(path.answer.status, 404);
  const access: ScreenAccess = { capture: false, control: false, app: "stillfail-station", path: "/x/stillfail-station" };
  source.refuse = new ScreenRefused(503, "station.screen.captureOff", { app: "stillfail-station", path: "/x/stillfail-station" }, access);
  const refused = await open(hub, member, { codecs: ["h264"] });
  assert.equal(refused.answer.status, 503);
  const said = await body(refused);
  assert.match(said.error, /Screen Recording is off for stillfail-station/);
  assert.equal(said.access.capture, false);
  assert.match(said.access.message, /Accessibility is off for stillfail-station/);
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
    access: { capture: false, control: false, message: "目前只能看到 macOS station 的本机屏幕" },
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
  assert.equal((await told(zh)).screens[1].access.message, "目前只能看到 macOS station 的本机屏幕");
  assert.equal((await told(en)).screens[1].access.message, "Seeing this machine's screen works only on macOS stations for now");
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

/// A helper as native/screen's is, in Node: `status` from status.json, `request` noted, `view` answering the framed
/// protocol with made-up frames and noting the input it is given.
function fakeHelper(status: object) {
  const dir = mkdtempSync(join(tmpdir(), "fake-screen-"));
  writeFileSync(join(dir, "status.json"), JSON.stringify(status));
  const path = join(dir, "stillfail-screen");
  script(path, `#!/usr/bin/env node
const fs = require("node:fs"), path = require("node:path");
const dir = ${JSON.stringify(dir)};
const note = (line) => fs.appendFileSync(path.join(dir, "log"), line + "\\n");
const cmd = process.argv[2];
note(process.argv.slice(2).join(" "));
if (cmd === "status" || cmd === "request") { process.stdout.write(fs.readFileSync(path.join(dir, "status.json"), "utf8") + "\\n"); process.exit(0); }
const send = (kind, payload) => { const head = Buffer.alloc(5); head[0] = kind; head.writeUInt32BE(payload.length, 1); process.stdout.write(Buffer.concat([head, payload])); };
send(1, Buffer.from(JSON.stringify({ width: 64, height: 36, encoder: "fake" })));
let carry = Buffer.alloc(0), n = 0, key = true;
process.stdin.on("data", (chunk) => {
  carry = Buffer.concat([carry, chunk]);
  while (carry.length >= 5 && carry.length >= 5 + carry.readUInt32BE(1)) {
    const kind = carry[0], payload = carry.subarray(5, 5 + carry.readUInt32BE(1));
    carry = carry.subarray(5 + payload.length);
    if (kind === 1) {
      n++;
      if (n === 1) { const c = Buffer.alloc(8); c.writeUInt32BE(64, 0); c.writeUInt32BE(36, 4); send(2, Buffer.concat([c, Buffer.from([1, 66, 0, 30])])); }
      const f = Buffer.alloc(9); f[0] = key ? 1 : 0; f.writeBigUInt64BE(BigInt(n * 1000), 1); key = false;
      send(3, Buffer.concat([f, Buffer.from([0, 0, 0, 1, n])]));
    } else if (kind === 2) key = true;
    else if (kind === 3) note("input " + payload.toString());
  }
});
process.stdin.on("end", () => process.exit(0));
`);
  const log = () => {
    try {
      return readFileSync(join(dir, "log"), "utf8").split("\n").filter(Boolean);
    } catch {
      return [];
    }
  };
  return { path: exe(path), dir, log, set: (s: object) => writeFileSync(join(dir, "status.json"), JSON.stringify(s)) };
}

const responsible = { pid: 1, path: "/Users/x/.stillfail/app/mesh/target/release/stillfail-station", name: "stillfail-station" };
const display = { id: 1, width: 3024, height: 1964 };

// The helper is a process the station runs by its path (execFile, spawn): a .cmd stand-in is not one on Windows, where
// the desktop is not supported anyway.
test("the desktop: unsupported, without its helper, or refused for want of a grant, says so; macOS is asked once", { skip: WINDOWS }, async () => {
  const off = new Desktop({ supported: false, helper: "/nowhere", changed: () => {} });
  assert.deepEqual(off.access(), { capture: false, control: false, unsupported: "platform" });
  await assert.rejects(off.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }), (e: ScreenRefused) => e.status === 501 && e.key === "station.screen.unsupported");
  const lost = new Desktop({ supported: true, helper: null, changed: () => {} });
  assert.equal(lost.access().unsupported, "helper");
  const helper = fakeHelper({ capture: false, control: false, responsible, display });
  let changed = 0;
  const desktop = new Desktop({ supported: true, helper: helper.path, changed: () => changed++ });
  await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["jpeg"] }), (e: ScreenRefused) => e.status === 415);
  await desktop.refresh();
  assert.equal(changed, 1);
  assert.deepEqual(desktop.size(), { width: 3024, height: 1964 });
  assert.deepEqual(desktop.access(), { capture: false, control: false, app: "stillfail-station", path: responsible.path });
  for (let i = 0; i < 2; i++) {
    await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }), (e: ScreenRefused) => e.status === 503 && e.key === "station.screen.captureOff" && e.args.path === responsible.path);
  }
  // Asked of macOS once, its answer not waited for.
  await settle();
  for (;;) {
    if (helper.log().includes("request")) break;
    await settle();
  }
  assert.equal(helper.log().filter((l) => l === "request").length, 1);
  // Granted since: seen at the next look.
  helper.set({ capture: true, control: true, responsible, display });
  await desktop.refresh(true);
  assert.equal(changed, 2);
  assert.deepEqual(desktop.access(), { capture: true, control: true, app: "stillfail-station", path: responsible.path });
});

test("the desktop's view: the helper per view, asked for each frame, its config on the first, input as macOS's", { skip: WINDOWS }, async () => {
  const helper = fakeHelper({ capture: true, control: true, responsible, display });
  const desktop = new Desktop({ supported: true, helper: helper.path, changed: () => {} });
  const view = await desktop.open({ maxWidth: 1280, maxHeight: 720, codecs: ["h264", "jpeg"] });
  assert.ok(helper.log().includes("view --max-width 1280 --max-height 720 --display 1"));
  const first = (await view.next())!;
  assert.deepEqual(first, { key: true, ts: 1000, data: new Uint8Array([0, 0, 0, 1, 1]), config: { codec: "h264", width: 64, height: 36, description: new Uint8Array([1, 66, 0, 30]) } });
  const second = (await view.next())!;
  assert.deepEqual(second, { key: false, ts: 2000, data: new Uint8Array([0, 0, 0, 1, 2]) });
  view.keyframe();
  assert.equal((await view.next())!.key, true);
  await view.input({ t: "key", kind: "down", key: "v", code: "KeyV", mods: 4 });
  // Its input is noted before the next frame is answered (the helper reads in order).
  await view.next();
  assert.deepEqual(helper.log().filter((l) => l.startsWith("input ")).map((l) => JSON.parse(l.slice(6))), [{ op: "key", keycode: KEYCODES.KeyV, down: true, flags: FLAGS.command }]);
  // Closed: a pending frame is none, the helper goes.
  const pending = view.next();
  view.close();
  assert.equal(await pending, null);
  assert.equal(await view.next(), null);
});
