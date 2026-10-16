// The station's screens (docs/remote-screens.md): the view wire over a member's link in memory (framing, at most
// UNACKED frames not acknowledged, read-only members, who is on a screen, how a view ends), with a fake source; the
// list (GET /screens, `screens` on the event stream); a person's input as macOS posts it; the desktop source with a
// fake helper (its grants, its view protocol). Nothing here captures a screen: side/screen-desktop.test.ts does.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import { Events } from "../src/api/events.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { FrameIn, KIND, MAX_IN, SCREEN_TYPE, UNACKED, answerScreen, frame, parseInput } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HELPER_APP, HelperApp } from "../src/helper/app.ts";
import { Desktop, helperMessage } from "../src/screens/desktop.ts";
import { ScreenHub, ScreenRefused } from "../src/screens/hub.ts";
import { CLICK_MS, FLAGS, KEYCODES, MacInput } from "../src/screens/mac-input.ts";
import type { Frame, ScreenAccess, ScreenInput, ScreenSource, ScreenView, ViewOptions } from "../src/screens/source.ts";
import { WINDOWS } from "../src/platform/index.ts";
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
  // What is missing, and that a window on the machine asks for it now.
  const access: ScreenAccess = { capture: false, control: false, app: "still.fail Helper", path: "/x/still.fail Helper.app", asking: true };
  source.refuse = new ScreenRefused(503, "station.screen.captureOff", { app: "still.fail Helper" }, access);
  const refused = await open(hub, member, { codecs: ["h264"] });
  assert.equal(refused.answer.status, 503);
  const said = await body(refused);
  assert.equal(
    said.error,
    "This Mac hasn't let still.fail Helper record its screen yet. This Mac hasn't let still.fail Helper control it yet (Accessibility), so the screen can be seen but not driven. A window on that Mac is asking for it now: click Allow there and drag still.fail Helper into the list System Settings shows, then open the screen again.",
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


/// still.fail Helper as native/helper's is, in this process: started by `launch` (the station's `open`) with its socket
/// and token; `status` as `status` is, `permissions.show` noted (its window then up), `quit` noted, `screen.view`
/// answering with made-up frames and noting the input. `restartOnce`: its next view asks to start again (a grant taken
/// since it started), and it is back on its socket a moment later, as the app started again is.
class FakeHelperApp {
  launches = 0;
  quits = 0;
  shown: any[] = [];
  inputs: any[] = [];
  views: any[] = [];
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
        case "screen.view": {
          this.views.push(ask);
          if (this.restartOnce) {
            this.restartOnce = false;
            conn.end(helperMessage(1, Buffer.from(JSON.stringify({ error: "restarting", code: "restart" }))));
            this.#stop();
            setImmediate(() => void this.#listen());
            return;
          }
          conn.write(helperMessage(1, Buffer.from(JSON.stringify({ width: 64, height: 36, encoder: "fake" }))));
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
  await desktop.close();
  fake.close();
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

const waitFor = async (what: () => boolean) => {
  while (!what()) await new Promise((r) => setTimeout(r, 20));
};

test("the helper watched: ended by itself it is started again, once, its window up again for a grant still missing", { skip: WINDOWS }, async () => {
  const { app, dir } = helperRelease();
  const fake = new FakeHelperApp({ capture: false, control: false, display, responsible: responsible(dir) });
  let backs = 0;
  const helper: HelperApp = new HelperApp({ app, dir, launch: fake.launch, onBack: () => (backs++, void desktop.helperBack()) });
  const desktop: Desktop = new Desktop({ supported: true, helper, changed: () => {}, lang: () => "en" });
  await assert.rejects(desktop.open({ maxWidth: 1920, maxHeight: 1080, codecs: ["h264"] }));
  assert.deepEqual([fake.launches, fake.shown.length, fake.watching], [1, 1, 1]);
  // One grant taken, then macOS quits it to reopen it, and does not: the station starts it, and asks for the other.
  fake.status = { ...fake.status, capture: true };
  fake.asking = false;
  fake.crash();
  await waitFor(() => backs === 1 && fake.shown.length === 2);
  assert.deepEqual([fake.launches, fake.watching], [2, 2]);
  // macOS reopened it itself this time: the station takes it as it is, a second one not started.
  fake.crash();
  await fake.reopen();
  await waitFor(() => backs === 2 && fake.shown.length === 3);
  assert.deepEqual([fake.launches, fake.watching], [2, 3]);
  // All granted: back once more, no window.
  fake.status = { ...fake.status, control: true };
  fake.crash();
  await fake.reopen();
  await waitFor(() => backs === 3);
  await settle();
  assert.equal(fake.shown.length, 3, "up again only while a grant was missing");
  // Asked to end with the station: not started again.
  await desktop.close();
  await settle();
  await new Promise((r) => setTimeout(r, 50));
  assert.equal(fake.launches, 2);
  fake.close();
});
