// Run on a disposable X11 display with STILLFAIL_TEST_X11_REAL_MESH=1 and the matching mesh addon. This exercises the
// real QUIC transport and X server, rather than the in-memory mesh used by the regular screen tests.
import assert from "node:assert/strict";
import { execFile, spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { promisify } from "node:util";
import { loadMesh, type Connection, type Endpoint, type Stream } from "../src/mesh/native.ts";
import { answerScreen, frame, FrameIn, KIND, SCREEN_TYPE } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { ScreenHub, ScreenRefused } from "../src/screens/hub.ts";
import { X11Desktop } from "../src/screens/x11-desktop.ts";
import { Computer } from "../src/tools/computer.ts";

const run = promisify(execFile);
const us = () => Number(process.hrtime.bigint() / 1000n);

async function until(check: () => boolean | Promise<boolean>, what: string, timeout = 5_000) {
  const end = performance.now() + timeout;
  while (performance.now() < end) {
    if (await check()) return;
    await sleep(50);
  }
  assert.fail(`timed out waiting for ${what}`);
}

type OpenView = { stream: Stream; served: Promise<void>; frames: FrameIn };
async function open(conn: Connection, theirs: Connection, hub: ScreenHub, role: "member" | "viewer", bounds = { maxWidth: 640, maxHeight: 400 }): Promise<OpenView> {
  const stream = await conn.openBi();
  await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: { "stillfail-lang": "en", "stillfail-build": "0.1.0" }, screen: { ...bounds, codecs: ["jpeg"], control: true, fps: 15 } });
  const incoming = (await theirs.acceptBi())!;
  const request = new Reader(incoming);
  const head = await request.line();
  const served = answerScreen(hub, incoming, request.carry, head, { sub: "u", email: "test@example.com", name: role, role, workspace: "w", device: "d" }, () => true);
  const reader = new Reader(stream);
  assert.deepEqual(await reader.line(), { status: 200, headers: { "content-type": SCREEN_TYPE } });
  return { stream, served, frames: new FrameIn(stream, reader.carry, 16 * 1024 * 1024) };
}

async function video(view: OpenView, configs: any[] = []): Promise<Buffer> {
  for (;;) {
    const next = await view.frames.next();
    assert.ok(next, "the screen stream ended before a video frame");
    if (next.kind === KIND.config) configs.push(JSON.parse(next.payload.toString()));
    if (next.kind === KIND.video) return next.payload;
  }
}

const ack = (view: OpenView, payload: Buffer) => view.stream.write(frame(KIND.ack, payload.subarray(1, 9)));
const input = (view: OpenView, event: object) => view.stream.write(frame(KIND.input, Buffer.from(JSON.stringify(event))));

/// A pixel outside the test window, to verify that changed X11 content actually reaches the client.
function corner(payload: Buffer, width: number, height: number): [number, number, number] {
  const decoded = spawnSync("ffmpeg", ["-nostdin", "-loglevel", "error", "-f", "mjpeg", "-i", "pipe:0", "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"], { input: payload.subarray(9), maxBuffer: width * height * 3 + 1024, timeout: 10_000 });
  assert.equal(decoded.status, 0, decoded.stderr.toString());
  assert.equal(decoded.stdout.length, width * height * 3);
  const at = ((height - 20) * width + width - 20) * 3;
  return [decoded.stdout[at]!, decoded.stdout[at + 1]!, decoded.stdout[at + 2]!];
}

test("real QUIC: X11 frames, backpressure, read-only access, input and disconnect cleanup", { skip: process.env.STILLFAIL_TEST_X11_REAL_MESH !== "1", timeout: 90_000 }, async () => {
  const env = { ...process.env };
  const observer = spawn("stdbuf", ["-oL", "xev", "-geometry", "600x500+0+0", "-event", "keyboard", "-event", "mouse"], { env });
  let observed = "";
  observer.stdout.on("data", (chunk: Buffer) => { observed += chunk.toString(); });
  const desktop = new X11Desktop({ env, changed: () => {}, title: () => "X11 real transport test" });
  const hub = new ScreenHub();
  hub.add(desktop);
  const views: OpenView[] = [];
  let station: Endpoint | undefined, device: Endpoint | undefined, conn: Connection | undefined;
  try {
    let window = "";
    await until(async () => {
      try { window = (await run("xdotool", ["search", "--name", "Event Tester"], { env })).stdout.trim().split("\n")[0] ?? ""; return !!window; }
      catch { return false; }
    }, "the test window");
    await run("xdotool", ["windowfocus", window], { env });
    await run("xsetroot", ["-solid", "#ff0000"], { env });
    await desktop.refresh(true);
    assert.deepEqual(desktop.size(), { width: 1280, height: 800 });
    await assert.rejects(desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["h265"] }), (e: ScreenRefused) => e.status === 415);
    const denied = new X11Desktop({ env: { ...env, XAUTHORITY: "/nonexistent/stillfail-test-auth" }, changed: () => {} });
    await denied.refresh(true);
    assert.equal(denied.access().reason, "linuxUnavailable");
    await denied.close();
    const broken = new X11Desktop({ env, ffmpeg: "/bin/false", changed: () => {} });
    await assert.rejects(broken.open({ maxWidth: 640, maxHeight: 400, codecs: ["jpeg"] }), (e: ScreenRefused) => e.status === 503);
    await broken.close();

    const mesh = loadMesh();
    const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
    [station, device] = await Promise.all([bind(), bind()]);
    const accepting = station.accept();
    conn = await device.connect({ id: station.id(), ips: [`127.0.0.1:${station.sockets()[0]!.split(":").at(-1)}`] }, ALPN);
    const theirs = (await accepting)!;
    const driver = await open(conn, theirs, hub, "member");
    views.push(driver);
    const configs: any[] = [];
    const first = await video(driver, configs);
    const second = await video(driver, configs);
    assert.deepEqual(configs, [{ codec: "jpeg", width: 640, height: 400 }]);
    assert.equal(first[0], 1);
    const red = corner(first, 640, 400);
    assert.ok(red[0] > 180 && red[0] > red[1] * 2 && red[0] > red[2] * 2, `red background: ${red}`);

    // With no ACK the pacer stops after two frames. A later ACK must yield a recent blue frame, not an old queue.
    await run("xsetroot", ["-solid", "#0000ff"], { env });
    await sleep(1_200);
    await ack(driver, second);
    const fresh = await video(driver);
    const ageMs = (us() - Number(fresh.readBigUInt64BE(1))) / 1000;
    assert.ok(ageMs >= 0 && ageMs < 600, `frame after backpressure was ${ageMs.toFixed(1)} ms old`);
    const blue = corner(fresh, 640, 400);
    assert.ok(blue[2] > 180 && blue[2] > blue[0] * 2 && blue[2] > blue[1] * 2, `blue background: ${blue}`);
    await ack(driver, fresh);
    let count = 0, bytes = 0;
    const start = performance.now();
    while (performance.now() - start < 3_000) {
      const f = await video(driver);
      count++;
      bytes += f.length;
      await ack(driver, f);
    }
    const seconds = (performance.now() - start) / 1000;
    assert.ok(count >= 10 && count <= 55, `${count} frames in ${seconds.toFixed(2)} s`);
    console.log(`X11 over QUIC: ${(count / seconds).toFixed(1)} fps, ${((bytes * 8) / seconds / 1_000_000).toFixed(2)} Mbit/s; post-backpressure frame ${ageMs.toFixed(1)} ms old`);

    // A second viewer can watch at different bounds, but its requested control must not move the mouse or type.
    const viewer = await open(conn, theirs, hub, "viewer", { maxWidth: 333, maxHeight: 203 });
    views.push(viewer);
    const viewerConfig: any[] = [];
    const viewerFrame = await video(viewer, viewerConfig);
    assert.deepEqual(viewerConfig, [{ codec: "jpeg", width: 324, height: 202 }]);
    corner(viewerFrame, 324, 202);
    await input(driver, { t: "pointer", kind: "move", x: 0.25, y: 0.35, buttons: 0 });
    const location = async () => (await run("xdotool", ["getmouselocation", "--shell"], { env })).stdout;
    await until(async () => (await location()).includes("X=320\n") && (await location()).includes("Y=280\n"), "the driver's pointer");
    await input(viewer, { t: "pointer", kind: "move", x: 0.8, y: 0.8, buttons: 0 });
    await input(viewer, { t: "key", kind: "down", key: "z", code: "KeyZ", mods: 0 });
    await input(viewer, { t: "key", kind: "up", key: "z", code: "KeyZ", mods: 0 });
    await sleep(500);
    const unchanged = await location();
    assert.match(unchanged, /X=320\n/);
    assert.match(unchanged, /Y=280\n/);
    assert.doesNotMatch(observed, /keysym 0x7a, z/);

    // Drag, scroll, a modifier supplied with a key, and Unicode text pass through the same wire.
    const before = observed.length;
    await input(driver, { t: "pointer", kind: "down", x: 0.25, y: 0.35, buttons: 1 });
    await input(driver, { t: "pointer", kind: "move", x: 0.3, y: 0.25, buttons: 1 });
    await input(driver, { t: "pointer", kind: "up", x: 0.3, y: 0.25, buttons: 0 });
    await input(driver, { t: "wheel", x: 0.3, y: 0.25, dx: 0, dy: 200 });
    await input(driver, { t: "key", kind: "down", key: "A", code: "KeyA", mods: 8 });
    await input(driver, { t: "key", kind: "up", key: "A", code: "KeyA", mods: 8 });
    await input(driver, { t: "key", kind: "down", key: "1", code: "Digit1", mods: 0 });
    await input(driver, { t: "key", kind: "up", key: "1", code: "Digit1", mods: 0 });
    await input(driver, { t: "text", text: "你好" });
    await until(() => {
      const events = observed.slice(before);
      return events.includes("ButtonPress event") && events.includes("ButtonRelease event") && events.includes("button 1") && events.includes("button 5") && events.includes("keysym 0x41, A") && events.includes("keycode 10 (keysym 0x31, 1)") && events.includes("U4F60") && events.includes("U597D");
    }, "drag, wheel, modified key, digit and Chinese text");

    // KeyboardEvent.code is a physical key: on French AZERTY, the Q position types 'a' at X keycode 24.
    await run("setxkbmap", ["-layout", "fr"], { env });
    const french = observed.length;
    await input(driver, { t: "key", kind: "down", key: "q", code: "KeyQ", mods: 0 });
    await input(driver, { t: "key", kind: "up", key: "q", code: "KeyQ", mods: 0 });
    await input(driver, { t: "key", kind: "down", key: "1", code: "Digit1", mods: 0 });
    await input(driver, { t: "key", kind: "up", key: "1", code: "Digit1", mods: 0 });
    await until(() => observed.slice(french).includes("keycode 10 (keysym 0x26, ampersand)"), "the French-layout keys");
    assert.match(observed.slice(french), /keycode 24 \(keysym 0x61, a\)/);
    await run("setxkbmap", ["-layout", "us"], { env });

    // A dropped connection must let go of the button and modifier the viewer was holding.
    const holding = observed.length;
    await input(driver, { t: "pointer", kind: "down", x: 0.3, y: 0.25, buttons: 1 });
    await input(driver, { t: "key", kind: "down", key: "Shift", code: "ShiftLeft", mods: 8 });
    await until(() => observed.slice(holding).includes("button 1") && observed.slice(holding).includes("Shift_L"), "held inputs");
    const beforeClose = observed.length;
    await driver.stream.finish();
    await driver.served;
    views.splice(views.indexOf(driver), 1);
    await until(() => observed.slice(beforeClose).includes("ButtonRelease event") && observed.slice(beforeClose).includes("KeyRelease event") && observed.slice(beforeClose).includes("Shift_L"), "held inputs released after disconnect");
    await viewer.stream.finish();
    await viewer.served;
    views.splice(views.indexOf(viewer), 1);

    // The agent's own computer tool uses the same source, without the member transport.
    const computer = new Computer({ hub, base: () => null, name: () => "test agent" });
    try {
      const shot = await computer.act("test", { screen: "desktop", action: "screenshot" });
      const image = shot.content.find((c) => c.type === "image");
      assert.ok(image && image.type === "image" && image.mimeType === "image/jpeg");
      assert.deepEqual([...Buffer.from(image.data, "base64").subarray(0, 2)], [0xff, 0xd8]);
      const clicks = observed.length;
      await computer.act("test", { screen: "desktop", action: "click", x: 320, y: 280, screenshot: false });
      await until(() => observed.slice(clicks).includes("ButtonPress event") && observed.slice(clicks).includes("ButtonRelease event"), "the agent's click");
    } finally { computer.closeAll(); }
    await until(async () => {
      const p = await run("ps", ["-o", "comm=", "--ppid", String(process.pid)], { env });
      return !p.stdout.split("\n").some((line) => line.trim() === "ffmpeg");
    }, "capture processes to exit");
  } finally {
    await Promise.allSettled(views.map(async (v) => { await v.stream.finish(); await v.served; }));
    await desktop.close();
    conn?.close(0, "test done");
    await Promise.all([station?.close(), device?.close()]);
    observer.kill();
  }
});
