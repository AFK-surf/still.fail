// A screen's view over a link made worse on purpose ("Wire"): a station endpoint and a member's
// on this machine, iroh between them through a UDP proxy that delays, drops and limits what it carries, the view's frames
// from a source that makes a picture of the size an encoder would (BITRATE, 60 a second, a key frame first) whenever one
// is asked. For each link it says the frames a second the device drew, how late they were (from capture to drawn), how
// often the picture stood still for longer than 200 ms, and the bits a second that came.
//
//   node scripts/native.ts run mesh -- node station/side/screen-net.ts
//   SOURCE=helper node scripts/native.ts run mesh helper -- node station/side/screen-net.ts
//   SOURCE=x11 CODECS=jpeg node scripts/native.ts run mesh -- node station/side/screen-net.ts  (an X11 session)
//   RELAY=https://… node scripts/native.ts run mesh -- node station/side/screen-net.ts   (through that relay alone)
//
// LINK_SECONDS (default 8) a link; LINKS to pick some by name (comma separated); BITRATE (default 6000000) the source's.
// AUDIO=1: the view asks for the computer's sound too, the source making a 20 ms packet of 48 kHz stereo PCM every
// 20 ms as still.fail Helper does; each link then says what share of the bytes that came were sound, how many of the
// packets made came (`soundCame`, 1 all of them), the longest the sound went without one (`soundGapMs`), and how late
// the sound and the pictures were (`soundLateP50`, beside `lateP50`). AUDIO=opus: the view says it decodes Opus too,
// and the source makes packets of OPUS_BYTES (default 160: 64 kbit/s, what the Mac's helper encodes at) instead, or
// of the sizes OPUS_PACKETS has (a file of packets, each after its length in 2 bytes big-endian), in turn. With
// SOURCE=helper the helper makes the sound too (a tone, encoded as Opus by AudioToolbox where asked). SOUND_DUMP: each
// link's packets of sound kept as `<SOUND_DUMP>-<link>.bin` (its codec's name in a line, then each packet's capture
// time in 8 bytes and its length in 2, big-endian, and the packet), to be decoded and heard.
import { execFileSync } from "node:child_process";
import { createSocket, type RemoteInfo } from "node:dgram";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import { networkInterfaces, tmpdir } from "node:os";
import { performance } from "node:perf_hooks";
import { type Endpoint, loadMesh } from "../src/mesh/native.ts";
import { FrameIn, KIND, answerScreen, frame } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HelperApp } from "../src/helper/app.ts";
import { Desktop } from "../src/screens/desktop.ts";
import { X11Desktop } from "../src/screens/x11-desktop.ts";
import { ScreenHub } from "../src/screens/hub.ts";
import type { Frame, ScreenSource, ScreenView } from "../src/screens/source.ts";

const SECONDS = Number(process.env.LINK_SECONDS ?? 8);
const BITRATE = Number(process.env.BITRATE ?? 6_000_000);
const FPS = 60;
/// `helper`: still.fail Helper's made-up moving pictures (`synthetic`), encoded on this Mac's hardware as the desktop's
/// are, instead of frames of the sizes an encoder would make.
const SOURCE = process.env.SOURCE ?? "sizes";
/// What the device takes (CODECS, comma separated; default H.265 and H.264); DUMP: each link's stream kept as
/// `<DUMP>-<link>.<codec>` (Annex B, for ffmpeg).
const CODECS = (process.env.CODECS ?? "h265,h264").split(",");
const DUMP = process.env.DUMP;
const helperApp = () => process.env.STILLFAIL_HELPER ?? execFileSync(process.execPath, [join(import.meta.dirname, "../../scripts/native.ts"), "file", "helper"], { encoding: "utf8" }).trim();
/// How long a device takes to decode and draw a frame before it acknowledges it.
const DRAW_MS = 4;
const AUDIO = process.env.AUDIO === "1" || process.env.AUDIO === "opus";
const OPUS = process.env.AUDIO === "opus";
/// A 20 ms packet of 48 kHz stereo 16-bit PCM, as still.fail Helper sends the system's sound; one of Opus.
const AUDIO_BYTES = 3840;
const OPUS_BYTES = Number(process.env.OPUS_BYTES ?? 160);
const OPUS_SIZES = ((file) => {
  if (!file) return [OPUS_BYTES];
  const b = readFileSync(file);
  const sizes: number[] = [];
  for (let at = 0; at + 2 <= b.length; at += 2 + b.readUInt16BE(at)) sizes.push(b.readUInt16BE(at));
  return sizes;
})(process.env.OPUS_PACKETS);
const SOUND_DUMP = process.env.SOUND_DUMP;

type Link = { name: string; rttMs: number; loss: number; mbps: number | null; relay?: string };
const LINKS: Link[] = [
  { name: "lan", rttMs: 2, loss: 0, mbps: null },
  { name: "city", rttMs: 40, loss: 0, mbps: null },
  { name: "far", rttMs: 150, loss: 0, mbps: null },
  { name: "city-1%", rttMs: 40, loss: 0.01, mbps: null },
  { name: "city-3%", rttMs: 40, loss: 0.03, mbps: null },
  { name: "city-8M", rttMs: 40, loss: 0, mbps: 8 },
  { name: "city-4M", rttMs: 40, loss: 0, mbps: 4 },
  { name: "city-1M", rttMs: 40, loss: 0, mbps: 1 },
  { name: "far-2%-20M", rttMs: 150, loss: 0.02, mbps: 20 },
  // a relay far away carrying a few hundred kbit/s, as a phone's way to a station through one
  { name: "far-800k", rttMs: 150, loss: 0, mbps: 0.8 },
  { name: "far-400k", rttMs: 150, loss: 0, mbps: 0.4 },
];

const now = () => performance.now();
/// Microseconds on the clock frames are stamped with: mach_absolute_time on a Mac, as still.fail Helper stamps them.
const nowUs = () => Number(process.hrtime.bigint() / 1000n);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/// A source whose pictures change all the time (a video, a scroll): a frame each 1/60 s when one is asked, its size what
/// `bitrate()` says now, the first and those asked for key frames (8 times as large).
function movingSource(): ScreenSource {
  return {
    id: "desktop",
    kind: "desktop",
    title: () => "bench",
    size: () => ({ width: 1920, height: 1080 }),
    async open(options): Promise<ScreenView> {
      let closed = false;
      let key = true;
      let last = 0;
      let first = true;
      let bitrate = Math.min(BITRATE, options.bitrate ?? BITRATE);
      // The picture's size: 1080p fitted into the bounds asked.
      const fit = (w: number, h: number) => { const k = Math.min(1, w / 1920, h / 1080); return { width: Math.round(1920 * k), height: Math.round(1080 * k) }; };
      let size = fit(options.maxWidth, options.maxHeight);
      let heard = now();
      let made = 0;
      return {
        ...(options.audio
          ? {
              async nextAudio() {
                heard += 20;
                if (now() < heard) await sleep(heard - now());
                else heard = now();
                return closed ? null : options.opus ? { ts: nowUs(), data: randomBytes(OPUS_SIZES[made++ % OPUS_SIZES.length]!), codec: "opus" as const } : { ts: nowUs(), data: randomBytes(AUDIO_BYTES), codec: "pcm_s16le" as const };
              },
            }
          : {}),
        async next(): Promise<Frame | null> {
          const due = last + 1000 / FPS;
          if (now() < due) await sleep(due - now());
          if (closed) return null;
          last = now();
          const bytes = Math.max(200, Math.round(bitrate / 8 / FPS) * (key ? 8 : 1));
          const f: Frame = { key, ts: nowUs(), data: randomBytes(bytes), ...(first ? { config: { codec: "h264", ...size, description: new Uint8Array([1]) } } : {}) };
          key = false;
          first = false;
          return f;
        },
        keyframe: () => void (key = true),
        rate: (bps) => void (bitrate = bps),
        bounds: (w, h) => void ((size = fit(w, h)), (first = true), (key = true)),
        input: async () => {},
        close: () => void (closed = true),
      };
    },
  };
}

/// A UDP proxy on 127.0.0.1 between the device and the station: each way delayed by half the round trip, dropped at
/// random, and (with `mbps`) let through no faster, a router's queue of 100 ms in front of it.
function impair(link: Link, station: string) {
  const [host, port] = [station.slice(0, station.lastIndexOf(":")).replace(/^\[|\]$/g, ""), Number(station.slice(station.lastIndexOf(":") + 1))];
  const front = createSocket("udp4");
  const v6 = host.includes(":");
  const back = createSocket(v6 ? "udp6" : "udp4");
  let device: RemoteInfo | null = null;
  let closed = false;
  const lanes = [0, 0]; // when each direction's link is free again
  const way = (dir: 0 | 1, packet: Buffer, send: (p: Buffer) => void) => {
    if (Math.random() < link.loss) return;
    let at = now();
    if (link.mbps !== null) {
      const start = Math.max(at, lanes[dir]!);
      if (start - at > 100) return; // the queue is full
      lanes[dir] = start + (packet.length * 8) / (link.mbps * 1000);
      at = lanes[dir]!;
    }
    const wait = at + link.rttMs / 2 - now();
    setTimeout(() => closed || send(packet), Math.max(0, wait));
  };
  front.on("message", (packet, from) => {
    device = from;
    way(0, packet, (p) => back.send(p, port, host));
  });
  back.on("message", (packet) => {
    const to = device;
    if (to) way(1, packet, (p) => front.send(p, to.port, to.address));
  });
  return new Promise<{ address: string; close(): void }>((resolve) => {
    front.bind(0, "127.0.0.1", () => back.bind(0, v6 ? "::1" : "0.0.0.0", () => resolve({ address: `127.0.0.1:${front.address().port}`, close: () => ((closed = true), front.close(), back.close()) })));
  });
}

/// This machine's address on a tunnel (100.64.0.0/10, as Tailscale's).
function tunnel(): string {
  const found = Object.values(networkInterfaces()).flat().find((a) => a?.family === "IPv4" && /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(a.address));
  if (!found) throw new Error("no tunnel address here: say STATION_AT, an address 127.0.0.1 does not reach");
  return found.address;
}

/// A config's parameter sets (avcC, hvcC) and a frame's length-prefixed NAL units, as Annex B (what ffmpeg reads).
const START = Buffer.from([0, 0, 0, 1]);
function parameterSets(codec: string, c: Buffer): Buffer[] {
  const out: Buffer[] = [];
  if (codec === "h265") {
    let at = 23;
    for (let i = 0, arrays = c[22]!; i < arrays; i++) {
      const n = c.readUInt16BE(at + 1);
      at += 3;
      for (let j = 0; j < n; j++, at += 2 + c.readUInt16BE(at)) out.push(START, c.subarray(at + 2, at + 2 + c.readUInt16BE(at)));
    }
    return out;
  }
  let at = 6;
  for (let i = 0, n = c[5]! & 31; i < n; i++, at += 2 + c.readUInt16BE(at)) out.push(START, c.subarray(at + 2, at + 2 + c.readUInt16BE(at)));
  for (let i = 0, n = c[at++]!; i < n; i++, at += 2 + c.readUInt16BE(at)) out.push(START, c.subarray(at + 2, at + 2 + c.readUInt16BE(at)));
  return out;
}
function units(frame: Buffer): Buffer[] {
  const out: Buffer[] = [];
  for (let at = 0; at + 4 <= frame.length; at += 4 + frame.readUInt32BE(at)) out.push(START, frame.subarray(at + 4, at + 4 + frame.readUInt32BE(at)));
  return out;
}

const pct = (xs: number[], p: number) => (xs.length === 0 ? NaN : [...xs].sort((a, b) => a - b)[Math.min(xs.length - 1, Math.floor(xs.length * p))]!);

async function run(link: Link, station: Endpoint, device: Endpoint) {
  // A device of its own each link: iroh keeps the ways it knew to a station, the last link's proxy among them. Through a
  // relay (RELAY): no proxy, the real way there and back.
  const proxy = link.relay ? { close() {} } : await impair(link, station.sockets().find((s) => !s.startsWith("0.0.0.0") && !s.startsWith("["))!);
  const conn = await device.connect(link.relay ? { id: station.id(), relays: [link.relay] } : { id: station.id(), ips: [(proxy as { address: string }).address] }, ALPN);
  const stream = await conn.openBi();
  await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: {}, screen: { maxWidth: 1920, maxHeight: 1080, codecs: CODECS, control: false, ...(AUDIO ? { audio: "pcm_s16le", ...(OPUS ? { opus: true } : {}) } : {}) } });
  const reader = new Reader(stream);
  const head = await reader.line();
  if (head?.status !== 200) throw new Error(`refused: ${JSON.stringify(head)}`);
  const frames = new FrameIn(stream, reader.carry, 64 * 1024 * 1024);
  const late: number[] = [];
  const drawn: number[] = [];
  let bytes = 0;
  let audioBytes = 0;
  let videoBytes = 0;
  let codec = "";
  let audioCodec = "";
  /// Each packet of sound that came (its capture time, ms) and how late it was.
  const heard: number[] = [];
  const soundLate: number[] = [];
  const sound: Buffer[] = [];
  /// The station's own measure of how late the frames were, as it last said it.
  let said: { frame: number; before: number } | null = null;
  /// The picture's heights, as each config said them.
  const heights: number[] = [];
  const kept: Buffer[] = [];
  const start = now();
  const end = start + SECONDS * 1000;
  // The first second is the view starting (the key frame, the window growing): not counted.
  const counted = start + 1000;
  while (now() < end) {
    const f = await frames.next();
    if (f === null) break;
    if (f.kind === KIND.state) {
      const state = JSON.parse(f.payload.toString());
      if (state.latency) said = state.latency;
    }
    if (f.kind === KIND.config) {
      const config = JSON.parse(f.payload.toString());
      codec = config.codec;
      heights.push(config.height);
      if (DUMP && config.description) kept.push(...parameterSets(codec, Buffer.from(config.description, "base64")));
    }
    if (f.kind === KIND.audioConfig) audioCodec = JSON.parse(f.payload.toString()).codec;
    if (f.kind === KIND.audio && now() >= counted) {
      audioBytes += f.payload.length;
      const ts = Number(f.payload.readBigUInt64BE(0));
      soundLate.push((nowUs() - ts) / 1000);
      heard.push(ts / 1000);
      if (SOUND_DUMP) {
        const head = Buffer.alloc(10);
        head.writeBigUInt64BE(BigInt(ts), 0);
        head.writeUInt16BE(f.payload.length - 8, 8);
        sound.push(head, f.payload.subarray(8));
      }
    }
    if (f.kind !== KIND.video) continue;
    if (now() >= counted) videoBytes += f.payload.length;
    if (DUMP) kept.push(...units(f.payload.subarray(9)));
    await sleep(DRAW_MS);
    const at = now();
    if (at >= counted) {
      late.push((nowUs() - Number(f.payload.readBigUInt64BE(1))) / 1000);
      drawn.push(at);
      bytes += f.payload.length;
    }
    void stream.write(frame(KIND.ack, f.payload.subarray(1, 9))).catch(() => {});
  }
  await stream.finish().catch(() => {});
  conn.close(0, "done");
  proxy.close();
  if (DUMP) writeFileSync(`${DUMP}-${link.name}.${codec}`, Buffer.concat(kept));
  if (SOUND_DUMP) writeFileSync(`${SOUND_DUMP}-${link.name}.bin`, Buffer.concat([Buffer.from(`${audioCodec}\n`), ...sound]));
  const span = (now() - counted) / 1000;
  const gaps = drawn.slice(1).map((t, i) => t - drawn[i]!);
  const stalls = gaps.filter((g) => g > 200);
  return {
    link: link.name,
    codec,
    heights: heights.join("→"),
    fps: +(drawn.length / span).toFixed(1),
    lateP50: Math.round(pct(late, 0.5)),
    lateP95: Math.round(pct(late, 0.95)),
    stationSaid: said,
    stalls: stalls.length,
    stalledMs: Math.round(stalls.reduce((a, b) => a + b, 0)),
    mbps: +((bytes * 8) / span / 1e6).toFixed(2),
    ...(AUDIO ? soundOf(audioCodec, heard, soundLate, span) : {}),
    ...(AUDIO ? { audioShare: +(audioBytes / Math.max(1, audioBytes + videoBytes)).toFixed(2), audioKbps: Math.round((audioBytes * 8) / span / 1000), videoKbps: Math.round((videoBytes * 8) / span / 1000) } : {}),
  };
}

/// How whole the sound was: the share of the packets made over the span that came (50 a second), the longest it went
/// without one between the first and the last, and how late they were.
function soundOf(codec: string, heard: number[], late: number[], span: number) {
  const sorted = [...heard].sort((a, b) => a - b);
  const gaps = sorted.slice(1).map((t, i) => t - sorted[i]!);
  return { soundCodec: codec, soundCame: +(heard.length / (span * 50)).toFixed(2), soundGapMs: Math.round(Math.max(0, ...gaps)), soundLateP50: Math.round(pct(late, 0.5)) };
}

async function main() {
  const mesh = loadMesh();
  // The device on 127.0.0.1, the station on an address it cannot reach from there (a tunnel's, as Tailscale's 100.x;
  // STATION_AT another): the device reaches it only through the proxy, whatever ways the station tells it of.
  // RELAY: both through that relay alone (a link `relay`, the real network to it and back, nothing made worse).
  const relay = process.env.RELAY;
  const bind = (at: string) => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: relay ? [relay] : [], discovery: false, ...(relay ? { relayOnly: true } : { bindAddr: at }) });
  const station = await bind(process.env.STATION_AT ?? (relay ? "" : `${tunnel()}:0`));
  if (relay) await station.online();
  const hub = new ScreenHub();
  const source: ScreenSource = SOURCE === "helper" ? new Desktop({ supported: true, helper: new HelperApp({ app: helperApp(), dir: mkdtempSync(join(tmpdir(), "screen-net-")) }), changed: () => {}, synthetic: "moving" })
    : SOURCE === "x11" ? new X11Desktop({ changed: () => {} }) : movingSource();
  // FIXED_RATE: the source never asked for another bit rate (as before the pace asked it).
  hub.add(process.env.FIXED_RATE ? { id: source.id, kind: source.kind, title: () => source.title(), size: () => source.size(), open: async (o) => Object.assign(await source.open(o), { rate: undefined }) } : source);
  const viewer = { sub: "u", email: "bench@still.fail", name: "bench", role: "member", workspace: "w", device: "d" };
  void (async () => {
    for (let conn = await station.accept(); conn; conn = await station.accept()) {
      void (async () => {
        for (let s = await conn.acceptBi(); s; s = await conn.acceptBi()) {
          const reader = new Reader(s);
          const head = await reader.line();
          void answerScreen(hub, s, reader.carry, head, viewer, () => true);
        }
      })().catch(() => {});
    }
  })();
  const only = process.env.LINKS?.split(",");
  const rows = [];
  const links = relay ? [{ name: `relay ${new URL(relay).host}`, rttMs: 0, loss: 0, mbps: null, relay }] : LINKS.filter((l) => !only || only.includes(l.name));
  for (const link of links) {
    const device = await bind("127.0.0.1:0");
    const row = await run(link, station, device);
    await device.close();
    console.log(JSON.stringify(row));
    rows.push(row);
  }
  console.table(rows);
  await station.close();
  process.exit(0);
}

await main();
