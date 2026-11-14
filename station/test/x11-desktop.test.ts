import assert from "node:assert/strict";
import { execFile, spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { promisify } from "node:util";
import { answerScreen, frame, FrameIn, KIND, SCREEN_TYPE } from "../src/mesh/screens.ts";
import { loadMesh, type Connection, type Endpoint, type Stream } from "../src/mesh/native.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { accessShown, ScreenHub } from "../src/screens/hub.ts";
import { X11Desktop } from "../src/screens/x11-desktop.ts";
import { memoryMesh } from "./memory-mesh.ts";

const run = promisify(execFile);

test("Linux desktop reports the reason when it cannot reach an X11 session", async () => {
  const env: NodeJS.ProcessEnv = {};
  const desktop = new X11Desktop({ env, changed: () => {} });
  await desktop.refresh(true);
  assert.equal(desktop.access().reason, "linuxNoDisplay");
  assert.match(accessShown(desktop.access(), "en")!.message, /no accessible desktop/);
  env.DISPLAY = ":99";
  env.WAYLAND_DISPLAY = "wayland-0";
  await desktop.refresh(true);
  assert.equal(desktop.access().reason, "linuxWayland");
  delete env.WAYLAND_DISPLAY;
  env.PATH = "";
  await desktop.refresh(true);
  assert.equal(desktop.access().reason, "linuxTools");
  await assert.rejects(desktop.open({ maxWidth: 640, maxHeight: 480, codecs: ["jpeg"] }), /ffmpeg with X11 support and xdotool/);
});

/// This test is run on a disposable X11 display, not a person's desktop.
test("an X11 desktop over the screen wire carries a decodable frame and drives pointer and keyboard", { skip: process.env.STILLFAIL_TEST_X11 !== "1", timeout: 30_000 }, async () => {
  const env = { ...process.env };
  const observer = spawn("stdbuf", ["-oL", "xev", "-event", "keyboard"], { env });
  let observed = "";
  observer.stdout.on("data", (chunk: Buffer) => { observed += chunk.toString(); });
  const desktop = new X11Desktop({ env, changed: () => {}, title: () => "X11 test" });
  const hub = new ScreenHub();
  hub.add(desktop);
  let served: Promise<void> | undefined;
  let stream: Stream | undefined;
  let station: Endpoint | undefined, device: Endpoint | undefined, conn: Connection | undefined;
  try {
    let window = "";
    for (let n = 0; n < 50 && !window; n++) {
      try { window = (await run("xdotool", ["search", "--name", "Event Tester"], { env })).stdout.trim().split("\n")[0] ?? ""; }
      catch { await sleep(100); }
    }
    assert.ok(window, "xev opened its test window");
    await run("xdotool", ["windowfocus", window], { env });
    await desktop.refresh(true);
    assert.deepEqual(desktop.size(), { width: 1280, height: 800 });
    assert.equal(desktop.access().capture, true);

    const real = process.env.STILLFAIL_TEST_X11_REAL_MESH === "1";
    const mesh = real ? loadMesh() : memoryMesh();
    const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
    station = await bind();
    device = await bind();
    const accepting = station.accept();
    const ips = real ? [`127.0.0.1:${station.sockets()[0]!.split(":").at(-1)}`] : undefined;
    conn = await device.connect({ id: station.id(), ...(ips ? { ips } : {}) }, ALPN);
    const theirs = (await accepting)!;
    stream = await conn.openBi();
    await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: { "stillfail-lang": "en", "stillfail-build": "0.1.0" }, screen: { maxWidth: 640, maxHeight: 400, codecs: ["jpeg"], control: true } });
    const incoming = (await theirs.acceptBi())!;
    const request = new Reader(incoming);
    const head = await request.line();
    served = answerScreen(hub, incoming, request.carry, head, { sub: "u", email: "test@example.com", name: "test", role: "member", workspace: "w", device: "d" }, () => true);
    const reader = new Reader(stream);
    assert.deepEqual(await reader.line(), { status: 200, headers: { "content-type": SCREEN_TYPE } });
    const frames = new FrameIn(stream, reader.carry);
    let config: any = null;
    let picture: Buffer | null = null;
    while (!picture) {
      const got = await frames.next();
      assert.ok(got);
      if (got.kind === KIND.config) config = JSON.parse(got.payload.toString());
      if (got.kind === KIND.video) picture = got.payload;
    }
    assert.deepEqual(config, { codec: "jpeg", width: 640, height: 400 });
    assert.equal(picture[0], 1);
    const jpeg = picture.subarray(9);
    assert.deepEqual([...jpeg.subarray(0, 2)], [0xff, 0xd8]);
    const decoded = spawnSync("ffmpeg", ["-nostdin", "-loglevel", "error", "-f", "mjpeg", "-i", "pipe:0", "-frames:v", "1", "-f", "null", "-"], { input: jpeg, env, timeout: 10_000 });
    assert.equal(decoded.status, 0, decoded.stderr.toString());

    const send = (input: object) => stream!.write(frame(KIND.input, Buffer.from(JSON.stringify(input))));
    await send({ t: "pointer", kind: "move", x: 0.25, y: 0.35, buttons: 0 });
    await send({ t: "key", kind: "down", key: "a", code: "KeyA", mods: 0 });
    await send({ t: "key", kind: "up", key: "a", code: "KeyA", mods: 0 });
    await send({ t: "text", text: "你好" });
    let pointer = "";
    for (let n = 0; n < 50; n++) {
      pointer = (await run("xdotool", ["getmouselocation", "--shell"], { env })).stdout;
      if (pointer.includes("X=320\n") && pointer.includes("Y=280\n") && observed.includes("KeyRelease event") && observed.includes("keysym 0x61, a") && observed.includes("U4F60") && observed.includes("U597D")) break;
      await sleep(100);
    }
    assert.match(pointer, /X=320\n/);
    assert.match(pointer, /Y=280\n/);
    assert.match(observed, /KeyPress event/);
    assert.match(observed, /KeyRelease event/);
    assert.match(observed, /keysym 0x61, a/);
    assert.match(observed, /U4F60/);
    assert.match(observed, /U597D/);
    await stream.finish();
    await served;
    served = undefined;
  } finally {
    if (served) { await stream?.finish(); await served; }
    conn?.close(0, "test done");
    await Promise.all([station?.close(), device?.close()]);
    await desktop.close();
    observer.kill();
  }
});
