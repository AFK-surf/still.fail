// The desktop as a screen (docs/remote-screens.md) on a real Mac: the helper (native/screen, prebuilt by
// scripts/native.ts) encoding H.264 on the hardware encoder, its frames over a real iroh link on this machine to a
// client that acknowledges them as it gets them, and decoded afterwards with ffmpeg (when the machine has it) into a
// PNG. Says the frame rate and bitrate it measured. Real time and real processes: a side test.
//
// Two of them: made-up 1080p pictures (the helper's --synthetic: the encoder and the link, whether or not this
// process may capture the screen), moving and still; and the display itself, which macOS lets the helper capture only
// when the process responsible for it (the terminal, sshd, a launchd job…) has Screen Recording: skipped, saying
// which, when it has not. SCREEN_OUT: where the streams and PNGs are kept (default: a temporary directory).
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, statSync, writeFileSync } from "node:fs";
import { platform, tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import type { Viewer } from "../src/mesh/credential.ts";
import { loadMesh } from "../src/mesh/native.ts";
import { FrameIn, KIND, answerScreen, frame } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { Desktop, type HelperStatus } from "../src/screens/desktop.ts";
import { ScreenHub } from "../src/screens/hub.ts";

const MAC = platform() === "darwin";
const ROOT = fileURLToPath(new URL("../..", import.meta.url));
const SECONDS = Number(process.env.SCREEN_SECONDS ?? 5);
const OUT = process.env.SCREEN_OUT ?? mkdtempSync(join(tmpdir(), "screen-side-"));
const viewer: Viewer = { sub: "u", email: "side@example.com", name: "Side", role: "member", workspace: "w", device: "d" };

const helper = () => process.env.STILLFAIL_SCREEN ?? execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", "screen"], { encoding: "utf8" }).trim();
const ffmpeg = () => [process.env.FFMPEG, "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].find((p) => p && existsSync(p)) ?? null;

/// A station with `hub`'s screens and a device, linked over iroh on this machine (no relay).
async function linked(hub: ScreenHub) {
  const mesh = loadMesh();
  const station = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const device = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false });
  const accepting = station.accept();
  const conn = await device.connect({ id: station.id(), ips: station.sockets() }, ALPN);
  const theirs = (await accepting)!;
  void (async () => {
    for (let s = await theirs.acceptBi(); s; s = await theirs.acceptBi()) {
      const heard = new Reader(s);
      const head = await heard.line();
      void answerScreen(hub, s, heard.carry, head, viewer, () => true);
    }
  })();
  return { conn, via: () => conn.via(), close: () => Promise.all([station.close(), device.close()]) };
}

/// avcC's parameter sets, and an AVCC frame's NAL units, as Annex B (what ffmpeg reads from a .h264 file).
function annexB(avcC: Buffer): Buffer[] {
  const out: Buffer[] = [];
  let at = 6;
  for (let i = 0, n = avcC[5]! & 31; i < n; i++, at += 2 + avcC.readUInt16BE(at)) out.push(Buffer.from([0, 0, 0, 1]), avcC.subarray(at + 2, at + 2 + avcC.readUInt16BE(at)));
  for (let i = 0, n = avcC[at++]!; i < n; i++, at += 2 + avcC.readUInt16BE(at)) out.push(Buffer.from([0, 0, 0, 1]), avcC.subarray(at + 2, at + 2 + avcC.readUInt16BE(at)));
  return out;
}
function nals(avcc: Buffer): Buffer[] {
  const out: Buffer[] = [];
  for (let at = 0; at + 4 <= avcc.length; at += 4 + avcc.readUInt32BE(at)) out.push(Buffer.from([0, 0, 0, 1]), avcc.subarray(at + 4, at + 4 + avcc.readUInt32BE(at)));
  return out;
}

type Measured = { frames: number; keys: number; fps: number; mbps: number; width: number; height: number; via: string | null; file: string };

/// A view for SECONDS: each frame acknowledged as it comes; `move` posts input every 16 ms (the pointer, to make the
/// screen change). The stream kept as `<label>.h264`.
async function view(link: Awaited<ReturnType<typeof linked>>, label: string, move?: (n: number) => unknown): Promise<Measured> {
  const stream = await link.conn.openBi();
  await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: { "stillfail-lang": "en" }, screen: { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: move !== undefined } });
  const heard = new Reader(stream);
  const answer = await heard.line();
  assert.equal(answer.status, 200, `${JSON.stringify(answer)} ${answer.status === 200 ? "" : (await heard.rest()).toString()}`);
  const frames = new FrameIn(stream, heard.carry);
  const kept: Buffer[] = [];
  let count = 0, keys = 0, bytes = 0, width = 0, height = 0;
  const started = performance.now();
  let n = 0;
  // Once finished, nothing more is written (the station's last frames are still read).
  let finished = false;
  const mover = move
    ? setInterval(() => {
        if (!finished) stream.write(frame(KIND.input, Buffer.from(JSON.stringify(move(n++))))).catch(() => {});
      }, 16)
    : null;
  const stop = setTimeout(() => {
    if (mover) clearInterval(mover);
    finished = true;
    void stream.finish();
  }, SECONDS * 1000);
  for (let f = await frames.next(); f !== null; f = await frames.next()) {
    if (f.kind === KIND.config) {
      const config = JSON.parse(f.payload.toString());
      ({ width, height } = config);
      kept.push(...annexB(Buffer.from(config.description, "base64")));
    } else if (f.kind === KIND.video) {
      count++;
      keys += f.payload[0]! & 1;
      bytes += f.payload.length - 9;
      kept.push(...nals(f.payload.subarray(9)));
      if (!finished) await stream.write(frame(KIND.ack, f.payload.subarray(1, 9)));
    }
  }
  clearTimeout(stop);
  const seconds = (performance.now() - started) / 1000;
  const file = join(OUT, `${label}.h264`);
  writeFileSync(file, Buffer.concat(kept));
  const measured = { frames: count, keys, fps: count / seconds, mbps: (bytes * 8) / seconds / 1e6, width, height, via: link.via(), file };
  console.log(`screen: ${label} ${width}×${height} over ${measured.via}: ${count} frames in ${seconds.toFixed(1)} s, ${measured.fps.toFixed(1)} fps, ${measured.mbps.toFixed(2)} Mbit/s, ${keys} key`);
  return measured;
}

/// All of a stream decodes (ffmpeg counts its frames), its first frame kept as a PNG.
function decodes(m: Measured, label: string) {
  const ff = ffmpeg();
  if (ff === null) return console.log("screen: no ffmpeg here, not decoded");
  const png = join(OUT, `${label}.png`);
  const shot = spawnSync(ff, ["-loglevel", "error", "-y", "-i", m.file, "-frames:v", "1", "-update", "1", png], { encoding: "utf8" });
  assert.equal(shot.status, 0, shot.stderr);
  assert.ok(statSync(png).size > 0);
  const all = spawnSync(ff, ["-loglevel", "error", "-i", m.file, "-f", "null", "-", "-progress", "pipe:1"], { encoding: "utf8" });
  assert.equal(all.status, 0, all.stderr);
  const decoded = Number(/frame=(\d+)\s*\n(?![\s\S]*frame=)/.exec(all.stdout)?.[1] ?? -1);
  assert.equal(decoded, m.frames, "every frame sent decodes");
  console.log(`screen: ${label}: all ${decoded} frames decode; the first is ${png}`);
}

test("made-up 1080p pictures: encoded on the hardware, over iroh, decoded; a still screen sends one frame", { skip: !MAC }, async () => {
  mkdirSync(OUT, { recursive: true });
  for (const mode of ["moving", "still"] as const) {
    const hub = new ScreenHub();
    const desktop = new Desktop({ supported: true, helper: helper(), changed: () => {}, synthetic: mode });
    hub.add(desktop);
    const link = await linked(hub);
    try {
      const m = await view(link, `synthetic-${mode}`);
      assert.ok(m.width > 0 && m.height > 0 && m.width <= 1920 && m.height <= 1080);
      if (mode === "still") assert.equal(m.frames, 1, "a screen that does not change sends its first frame only");
      else assert.ok(m.frames > SECONDS, "a moving screen keeps sending");
      assert.ok(m.keys >= 1);
      decodes(m, `synthetic-${mode}`);
    } finally {
      desktop.close();
      await link.close();
    }
  }
});

test("the display itself: still, then with the pointer moving", { skip: !MAC }, async (t) => {
  const status: HelperStatus = JSON.parse(execFileSync(helper(), ["status"], { encoding: "utf8" }));
  console.log(`screen: status ${JSON.stringify(status)}`);
  if (!status.capture) return t.skip(`Screen Recording is not granted to ${status.responsible?.path || "the process responsible for this one"}`);
  const hub = new ScreenHub();
  const desktop = new Desktop({ supported: true, helper: helper(), changed: () => {} });
  hub.add(desktop);
  const link = await linked(hub);
  try {
    decodes(await view(link, "display-still"), "display-still");
    if (!status.control) return t.skip(`Accessibility is not granted to ${status.responsible?.path}: the pointer is not moved`);
    const moving = await view(link, "display-moving", (n) => ({ t: "pointer", kind: "move", x: 0.5 + 0.3 * Math.sin(n / 10), y: 0.5 + 0.3 * Math.cos(n / 10), buttons: 0 }));
    assert.ok(moving.frames > SECONDS);
    decodes(moving, "display-moving");
  } finally {
    desktop.close();
    await link.close();
  }
});
