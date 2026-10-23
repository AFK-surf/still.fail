// A screen's view over a link made worse on purpose (docs/remote-screens.md, "Wire"): a station endpoint and a member's
// on this machine, iroh between them through a UDP proxy that delays, drops and limits what it carries, the view's frames
// from a source that makes a picture of the size an encoder would (BITRATE, 60 a second, a key frame first) whenever one
// is asked. For each link it says the frames a second the device drew, how late they were (from capture to drawn), how
// often the picture stood still for longer than 200 ms, and the bits a second that came.
//
//   node scripts/native.ts run mesh -- node station/side/screen-net.ts
//   SOURCE=helper node scripts/native.ts run mesh helper -- node station/side/screen-net.ts
//
// LINK_SECONDS (default 8) a link; LINKS to pick some by name (comma separated); BITRATE (default 6000000) the source's.
import { execFileSync } from "node:child_process";
import { createSocket, type RemoteInfo } from "node:dgram";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import { networkInterfaces, tmpdir } from "node:os";
import { performance } from "node:perf_hooks";
import { type Endpoint, loadMesh } from "../src/mesh/native.ts";
import { FrameIn, KIND, answerScreen, frame } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HelperApp } from "../src/helper/app.ts";
import { Desktop } from "../src/screens/desktop.ts";
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

type Link = { name: string; rttMs: number; loss: number; mbps: number | null };
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
    async open(): Promise<ScreenView> {
      let closed = false;
      let key = true;
      let last = 0;
      let first = true;
      let bitrate = BITRATE;
      return {
        async next(): Promise<Frame | null> {
          const due = last + 1000 / FPS;
          if (now() < due) await sleep(due - now());
          if (closed) return null;
          last = now();
          const size = Math.max(200, Math.round(bitrate / 8 / FPS) * (key ? 8 : 1));
          const f: Frame = { key, ts: nowUs(), data: randomBytes(size), ...(first ? { config: { codec: "h264", width: 1920, height: 1080, description: new Uint8Array([1]) } } : {}) };
          key = false;
          first = false;
          return f;
        },
        keyframe: () => void (key = true),
        rate: (bps) => void (bitrate = bps),
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
  // A device of its own each link: iroh keeps the ways it knew to a station, the last link's proxy among them.
  const proxy = await impair(link, station.sockets().find((s) => !s.startsWith("0.0.0.0") && !s.startsWith("["))!);
  const conn = await device.connect({ id: station.id(), ips: [proxy.address] }, ALPN);
  const stream = await conn.openBi();
  await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: {}, screen: { maxWidth: 1920, maxHeight: 1080, codecs: CODECS, control: false } });
  const reader = new Reader(stream);
  const head = await reader.line();
  if (head?.status !== 200) throw new Error(`refused: ${JSON.stringify(head)}`);
  const frames = new FrameIn(stream, reader.carry, 64 * 1024 * 1024);
  const late: number[] = [];
  const drawn: number[] = [];
  let bytes = 0;
  let codec = "";
  const kept: Buffer[] = [];
  const start = now();
  const end = start + SECONDS * 1000;
  // The first second is the view starting (the key frame, the window growing): not counted.
  const counted = start + 1000;
  while (now() < end) {
    const f = await frames.next();
    if (f === null) break;
    if (f.kind === KIND.config) {
      const config = JSON.parse(f.payload.toString());
      codec = config.codec;
      if (DUMP && config.description) kept.push(...parameterSets(codec, Buffer.from(config.description, "base64")));
    }
    if (f.kind !== KIND.video) continue;
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
  const span = (now() - counted) / 1000;
  const gaps = drawn.slice(1).map((t, i) => t - drawn[i]!);
  const stalls = gaps.filter((g) => g > 200);
  return {
    link: link.name,
    codec,
    fps: +(drawn.length / span).toFixed(1),
    lateP50: Math.round(pct(late, 0.5)),
    lateP95: Math.round(pct(late, 0.95)),
    stalls: stalls.length,
    stalledMs: Math.round(stalls.reduce((a, b) => a + b, 0)),
    mbps: +((bytes * 8) / span / 1e6).toFixed(2),
  };
}

async function main() {
  const mesh = loadMesh();
  // The device on 127.0.0.1, the station on an address it cannot reach from there (a tunnel's, as Tailscale's 100.x;
  // STATION_AT another): the device reaches it only through the proxy, whatever ways the station tells it of.
  const bind = (at: string) => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false, bindAddr: at });
  const station = await bind(process.env.STATION_AT ?? `${tunnel()}:0`);
  const hub = new ScreenHub();
  const source: ScreenSource = SOURCE === "helper" ? new Desktop({ supported: true, helper: new HelperApp({ app: helperApp(), dir: mkdtempSync(join(tmpdir(), "screen-net-")) }), changed: () => {}, synthetic: "moving" }) : movingSource();
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
  for (const link of LINKS.filter((l) => !only || only.includes(l.name))) {
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
