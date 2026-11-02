// Real X11 and (when requested) real QUIC, on a disposable display. Never use a person's desktop for this test.
import assert from "node:assert/strict";
import { execFile, spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { promisify } from "node:util";
import { loadMesh, type Connection, type Endpoint, type Stream } from "../src/mesh/native.ts";
import { answerScreen, frame, FrameIn, KIND, SCREEN_TYPE } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { ScreenHub } from "../src/screens/hub.ts";
import { X11Desktop } from "../src/screens/x11-desktop.ts";
import { memoryMesh } from "./memory-mesh.ts";

const run = promisify(execFile);
const enabled = process.env.STILLFAIL_TEST_X11 === "1";
const nowUs = () => Number(process.hrtime.bigint() / 1000n);
const START = Buffer.from([0, 0, 0, 1]);

/// Convert the screen protocol's avcC and length-prefixed pictures to Annex B for an independent decoder.
function annexConfig(bytes: Buffer): Buffer[] {
  const result: Buffer[] = [];
  let at = 6;
  const read = () => {
    const length = bytes.readUInt16BE(at);
    at += 2;
    assert.ok(at + length <= bytes.length);
    result.push(START, bytes.subarray(at, at + length));
    at += length;
  };
  for (let n = bytes[5]! & 31; n > 0; n--) read();
  for (let n = bytes[at++]!; n > 0; n--) read();
  return result;
}
function annexFrame(bytes: Buffer): Buffer[] {
  const result: Buffer[] = [];
  for (let at = 0; at < bytes.length;) {
    assert.ok(at + 4 <= bytes.length);
    const length = bytes.readUInt32BE(at);
    at += 4;
    assert.ok(length > 0 && at + length <= bytes.length);
    result.push(START, bytes.subarray(at, at + length));
    at += length;
  }
  return result;
}

test("H.264 over the screen wire stays decodable through backpressure and a key-frame request", { skip: !enabled, timeout: 45_000 }, async () => {
  const env = { ...process.env };
  // Keep an X client connected: Xvfb resets its root background when its last client disconnects.
  const observer = spawn("xev", ["-event", "keyboard"], { env, stdio: "ignore" });
  const desktop = new X11Desktop({ env, changed: () => {} });
  const hub = new ScreenHub();
  hub.add(desktop);
  let station: Endpoint | undefined, device: Endpoint | undefined, conn: Connection | undefined, stream: Stream | undefined;
  let served: Promise<void> | undefined;
  try {
    let connected = false;
    for (let i = 0; i < 100 && !connected; i++) {
      try { await run("xdotool", ["search", "--name", "Event Tester"], { env }); connected = true; }
      catch { await sleep(50); }
    }
    assert.ok(connected, "the X observer connected");
    await run("xsetroot", ["-solid", "#ff0000"], { env });
    const real = process.env.STILLFAIL_TEST_X11_REAL_MESH === "1";
    const mesh = real ? loadMesh() : memoryMesh();
    const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
    [station, device] = await Promise.all([bind(), bind()]);
    const accepting = station.accept();
    const ips = real ? [`127.0.0.1:${station.sockets()[0]!.split(":").at(-1)}`] : undefined;
    conn = await device.connect({ id: station.id(), ...(ips ? { ips } : {}) }, ALPN);
    const theirs = (await accepting)!;
    stream = await conn.openBi();
    await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: {}, screen: { maxWidth: 640, maxHeight: 400, codecs: ["h264", "jpeg"], control: true, fps: 15 } });
    const incoming = (await theirs.acceptBi())!;
    const request = new Reader(incoming);
    const head = await request.line();
    served = answerScreen(hub, incoming, request.carry, head, { sub: "u", email: "test@example.com", name: "test", role: "member", workspace: "w", device: "d" }, () => true);
    const reader = new Reader(stream);
    assert.deepEqual(await reader.line(), { status: 200, headers: { "content-type": SCREEN_TYPE } });
    const frames = new FrameIn(stream, reader.carry, 16 * 1024 * 1024);
    const annex: Buffer[] = [];
    let configCount = 0, frameCount = 0;
    const next = async () => {
      for (;;) {
        const got = await frames.next();
        assert.ok(got, "screen ended before a video frame");
        if (got.kind === KIND.config) {
          const c = JSON.parse(got.payload.toString());
          assert.equal(c.codec, "h264");
          assert.equal(c.width, 640);
          assert.equal(c.height, 400);
          annex.push(...annexConfig(Buffer.from(c.description, "base64")));
          configCount++;
        }
        if (got.kind === KIND.video) {
          annex.push(...annexFrame(got.payload.subarray(9)));
          frameCount++;
          return got.payload;
        }
      }
    };
    const ack = (payload: Buffer) => stream!.write(frame(KIND.ack, payload.subarray(1, 9)));
    const first = await next();
    const second = await next();
    assert.equal(first[0], 1);
    assert.equal(second[0], 0);
    assert.equal(configCount, 1);

    // The transport pauses when two frames are unacknowledged. Once it resumes, the encoder must get the latest raw
    // picture, without silently skipping any already-encoded delta frame.
    await run("xsetroot", ["-solid", "#0000ff"], { env });
    await sleep(1_200);
    await ack(second);
    const fresh = await next();
    const age = (nowUs() - Number(fresh.readBigUInt64BE(1))) / 1000;
    assert.ok(age >= 0 && age < 700, `post-backpressure frame is ${age.toFixed(1)} ms old`);
    await ack(fresh);

    // Decoder recovery asks for a key frame. A restart carries its new avcC before that frame.
    await stream.write(frame(KIND.keyframe, Buffer.alloc(0)));
    let recovered = false;
    for (let i = 0; i < 20 && !recovered; i++) {
      const f = await next();
      recovered = configCount >= 2 && f[0] === 1;
      await ack(f);
    }
    assert.ok(recovered, "a requested key frame and its configuration arrived");
    for (let i = 0; i < 4; i++) { const f = await next(); await ack(f); }

    const decoded = spawnSync("ffmpeg", ["-nostdin", "-loglevel", "error", "-f", "h264", "-i", "pipe:0", "-vsync", "0", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
      { input: Buffer.concat(annex), maxBuffer: 640 * 400 * 3 * (frameCount + 1), timeout: 15_000 });
    assert.equal(decoded.status, 0, decoded.stderr.toString());
    assert.equal(decoded.stdout.length, 640 * 400 * 3 * frameCount, decoded.stderr.toString());
    const pixel = (n: number) => {
      const at = n * 640 * 400 * 3 + ((400 - 20) * 640 + 640 - 20) * 3;
      return [...decoded.stdout.subarray(at, at + 3)];
    };
    const red = pixel(0), blue = pixel(2);
    assert.ok(red[0]! > 170 && red[0]! > red[2]! * 2, `first frame: ${red}`);
    assert.ok(blue[2]! > 170 && blue[2]! > blue[0]! * 2, `frame after backpressure: ${blue}`);
    console.log(`decoded ${frameCount} H.264 frames, including recovery; frame after backpressure was ${age.toFixed(1)} ms old`);
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

test("H.264 bitrate changes restart cleanly; missing encoder falls back to JPEG", { skip: !enabled, timeout: 30_000 }, async () => {
  const env = { ...process.env };
  const desktop = new X11Desktop({ env, changed: () => {} });
  const view = await desktop.open({ maxWidth: 640, maxHeight: 400, codecs: ["h264", "jpeg"], bitrate: 1_500_000 });
  try {
    const first = await view.next();
    assert.equal(first?.config?.codec, "h264");
    assert.equal(first?.key, true);
    const second = await view.next();
    assert.equal(second?.key, false);
    await sleep(1_600);
    view.rate!(400_000);
    const changed = await view.next();
    assert.equal(changed?.config?.codec, "h264");
    assert.equal(changed?.key, true);
    // A temporary increase should not immediately restart the encoder. A sustained increase should eventually
    // raise the rate, and an explicit recovery request must still bypass the cooldown.
    view.rate!(1_500_000);
    await sleep(1_600);
    const steady = await view.next();
    assert.equal(steady?.config, undefined);
    assert.equal(steady?.key, false);
    await sleep(3_100);
    const faster = await view.next();
    assert.equal(faster?.config?.codec, "h264");
    assert.equal(faster?.key, true);
    view.keyframe();
    const key = await view.next();
    assert.equal(key?.config?.codec, "h264");
    assert.equal(key?.key, true);
  } finally { view.close(); await desktop.close(); }

  // An ffmpeg build that advertises libx264 but cannot start it must leave a JPEG-capable client able to watch.
  const dir = mkdtempSync(join(tmpdir(), "sf-x11-encoder-"));
  const fake = join(dir, "ffmpeg");
  const real = (await run("which", ["ffmpeg"], { env })).stdout.trim();
  writeFileSync(fake, `#!/bin/sh\ncase " $* " in\n  *" -encoders "*) echo ' V..... libx264'; exit 0;;\n  *" -c:v libx264 "*) exit 1;;\nesac\nexec "${real}" "$@"\n`);
  chmodSync(fake, 0o755);
  const fallback = new X11Desktop({ env, ffmpeg: fake, changed: () => {} });
  try {
    const jpeg = await fallback.open({ maxWidth: 640, maxHeight: 400, codecs: ["h264", "jpeg"] });
    try { assert.equal((await jpeg.next())?.config?.codec, "jpeg"); } finally { jpeg.close(); }
  } finally { await fallback.close(); rmSync(dir, { recursive: true, force: true }); }
});
