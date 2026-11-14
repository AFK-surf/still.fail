// A station restarted while a device views its screen, over the real network and still.fail's relays: how often the
// device's connection opens and then carries nothing, and how long it takes to see frames again. Run by hand, the
// station on one machine and the device on another (2026-11-12: tokyo-mac-studio-0 and Office-VM-1):
//   station <keyfile>                      a station endpoint serving a moving screen (1080p at 60 frames a second, as
//                                          ScreenHub and answerScreen serve one); POST /bench/exit closes it and exits:
//                                          run it in a loop (`while true; do node … station key; sleep 1; done`), each
//                                          exit a restart on another port
//   id <keyfile>                           the endpoint id of that key
//   device <station id> <rounds>           each round: a fresh device reaches the station and views it, asks it to exit,
//                                          reaches it again and views it; one JSON line a round on stdout
//   exit <station id>                      asks the station to exit
// How the device reaches it: by default the worst case, a dial each second with the earlier ones left going, and a
// connection that opened but showed no frame within DEAD_MS counted `dead`, its paths' timeline kept in the line;
// with DIAL=app as the app does (client/core-ts mesh.ts): one dial at a time, given up at CONNECT_MS, pings every
// TICK_MS and the link let go after DEAD_PINGS missed (`dropped`). STILLFAIL_MESH_NATIVE names the addon measured.
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";
import { type Connection, type Endpoint, loadMesh } from "../src/mesh/native.ts";
import { FrameIn, KIND, answerScreen, frame } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { ScreenHub } from "../src/screens/hub.ts";
import type { Frame, ScreenSource, ScreenView } from "../src/screens/source.ts";

const RELAYS = (process.env.RELAYS ?? "https://app.still.fail,https://39.105.157.122,https://47.76.247.168,https://120.24.233.158,https://47.79.40.84,https://relay.pvg.office.afk.surf:8445").split(",");
const DEAD_MS = Number(process.env.DEAD_MS ?? 8000);
const BITRATE = 6_000_000;
const FPS = 60;
const now = () => performance.now();
const nowUs = () => Number(process.hrtime.bigint() / 1000n);
const wall = () => new Date().toISOString();
const sleep = (ms: number) => new Promise<"t">((r) => setTimeout(() => r("t"), ms));
const mesh = loadMesh() as any;
const keyOf = (file: string) => {
  if (!existsSync(file)) writeFileSync(file, randomBytes(32));
  return readFileSync(file);
};

function movingSource(): ScreenSource {
  return {
    id: "desktop",
    kind: "desktop",
    title: () => "bench",
    size: () => ({ width: 1920, height: 1080 }),
    async open(options): Promise<ScreenView> {
      let closed = false, key = true, last = 0, first = true;
      let bitrate = Math.min(BITRATE, options.bitrate ?? BITRATE);
      const fit = (w: number, h: number) => { const k = Math.min(1, w / 1920, h / 1080); return { width: Math.round(1920 * k), height: Math.round(1080 * k) }; };
      let size = fit(options.maxWidth, options.maxHeight);
      return {
        async next(): Promise<Frame | null> {
          const due = last + 1000 / FPS;
          if (now() < due) await sleep(due - now());
          if (closed) return null;
          last = now();
          const bytes = Math.max(200, Math.round(bitrate / 8 / FPS) * (key ? 8 : 1));
          const f: Frame = { key, ts: nowUs(), data: randomBytes(bytes), ...(first ? { config: { codec: "h264", ...size, description: new Uint8Array([1]) } } : {}) };
          key = false; first = false;
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

const short = (p: any) => (p.ip ? `ip:${p.ip}` : new URL(p.relay).hostname) + (p.selected ? "*" : "") + `:${p.rttMs == null ? "-" : Math.round(p.rttMs)}/${p.txPackets}/${p.lostPackets}`;
const pathsOf = (c: Connection) => ((c as any).paths?.() ?? []).map(short).join(" ");
const statsOf = (c: Connection) => { const s = (c as any).stats?.(); return s ? `rx${s.rxPackets}/${s.rxData} tx${s.txPackets}/${s.txData}` : ""; };

async function station(file: string) {
  const ep: Endpoint = await mesh.bind({ secretKey: keyOf(file), alpns: [ALPN], relayUrls: RELAYS, discovery: true });
  await ep.online();
  console.log(JSON.stringify({ up: ep.id(), sockets: ep.sockets(), at: wall() }));
  const hub = new ScreenHub();
  hub.add(movingSource());
  const viewer = { sub: "u", email: "bench@still.fail", name: "bench", role: "member", workspace: "w", device: "d" } as any;
  for (let conn = await ep.accept(); conn; conn = await ep.accept()) {
    const c = conn;
    const id = c.remoteId().slice(0, 8);
    const t0 = now();
    console.log(JSON.stringify({ accepted: id, at: wall(), paths: pathsOf(c) }));
    // What each connection's paths and counts were through its first seconds, and how it went.
    const tl: string[] = [];
    const ticker = setInterval(() => { if (tl.length < 40) tl.push(`${Math.round(now() - t0)} ${statsOf(c)} ${pathsOf(c)}`); }, 250);
    let streams = 0;
    void c.closed().then((why) => { clearInterval(ticker); console.log(JSON.stringify({ closed: id, at: wall(), why, streams, tl: streams === 0 || /dead/.test(why) ? tl : undefined })); });
    void (async () => {
      for (let s = await c.acceptBi(); s; s = await c.acceptBi()) {
        streams++;
        const reader = new Reader(s);
        const head = await reader.line();
        if (head?.path === "/bench/ping") {
          void writeLine(s, { pong: true }).then(() => s.finish()).catch(() => {});
          continue;
        }
        if (head?.path === "/bench/exit") {
          console.log(JSON.stringify({ exit: wall() }));
          await ep.close();
          process.exit(0);
        }
        void answerScreen(hub, s, reader.carry, head, viewer, () => true);
      }
    })().catch(() => {});
  }
}

type Seen = { headMs: number | null; frames: number[]; tl: string[]; error?: string };

/// Views the screen on `conn` until `until`; gives up at `dead` ms without a frame.
async function view(conn: Connection, ms: number): Promise<Seen> {
  const t0 = now();
  const tl: string[] = [];
  const ticker = setInterval(() => { if (tl.length < 40) tl.push(`${Math.round(now() - t0)} ${statsOf(conn)} ${pathsOf(conn)}`); }, 250);
  const seen: Seen = { headMs: null, frames: [], tl };
  const deadAt = t0 + DEAD_MS;
  const until = t0 + ms;
  let stream: any = null;
  try {
    const opened = await Promise.race([conn.openBi(), sleep(DEAD_MS)]);
    if (opened === "t") throw new Error("openBi never answered");
    stream = opened;
    await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: {}, screen: { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: false } });
    const reader = new Reader(stream);
    const head = await Promise.race([reader.line(), sleep(Math.max(0, deadAt - now()))]);
    if (head === "t") throw new Error("no head");
    seen.headMs = Math.round(now() - t0);
    if (head?.status !== 200) throw new Error(`refused: ${JSON.stringify(head)}`);
    const frames = new FrameIn(stream, reader.carry, 64 * 1024 * 1024);
    while (now() < until) {
      const limit = seen.frames.length === 0 ? deadAt : until;
      const f = await Promise.race([frames.next(), sleep(Math.max(0, limit - now()))]);
      if (f === "t") { if (seen.frames.length === 0) throw new Error("no frame"); break; }
      if (f === null) throw new Error("stream ended");
      if (f.kind !== KIND.video) continue;
      seen.frames.push(Math.round(now() - t0));
      void stream.write(frame(KIND.ack, f.payload.subarray(1, 9))).catch(() => {});
    }
  } catch (e) {
    seen.error = String((e as Error)?.message ?? e);
  }
  clearInterval(ticker);
  void stream?.finish().catch(() => {});
  return seen;
}

const gapMax = (fs: number[]) => Math.max(0, ...fs.slice(1).map((t, i) => t - fs[i]!));

/// Dials every second (earlier dials left going) until one opens and shows frames; a connection that opens and shows
/// none within DEAD_MS is counted dead, closed, and dialling goes on.
async function reach(ep: Endpoint, id: string, from: number, budget: number) {
  const dead: Record<string, unknown>[] = [];
  let tries = 0;
  while (now() - from < budget) {
    // The dials still going once one connected (or the budget is spent) are given up (an addon from before goes on).
    let giveUp = () => {};
    const givenUp = new Promise<void>((resolve) => (giveUp = resolve));
    const conn = await new Promise<Connection | null>((resolve) => {
      let done = false;
      const give = setTimeout(() => { done = true; clearInterval(again); resolve(null); }, Math.max(0, budget - (now() - from)));
      const dial = () => {
        if (done) return;
        tries++;
        ep.connect({ id, relays: RELAYS }, ALPN, [], givenUp).then((c) => { if (done) { c.close(0, "late"); return; } done = true; clearTimeout(give); clearInterval(again); resolve(c); }, () => {});
      };
      const again = setInterval(dial, 1000);
      dial();
    });
    giveUp();
    if (conn === null) break;
    const connectedMs = Math.round(now() - from);
    const at = wall();
    const paths = pathsOf(conn);
    const seen = await view(conn, 6000);
    if (seen.frames.length > 0) return { tries, connectedMs, firstFrameMs: connectedMs + seen.frames[0]!, gapMax: gapMax(seen.frames), frames: seen.frames.length, path: pathsOf(conn), dead, conn };
    dead.push({ at, connectedMs, error: seen.error, headMs: seen.headMs, pathsAtOpen: paths, tl: seen.tl });
    conn.close(0, "dead");
  }
  return { tries, dead, conn: null };
}

/// As the app reaches a station (client/core-ts mesh.ts): one dial at a time, given up after CONNECT_MS (left to finish
/// or fail on its own, closed if it connects late); on a connection, a ping every TICK_MS answered within PING_MS, and
/// after DEAD_PINGS missed in a row it is let go and dialled again. Until a frame comes.
const CONNECT_MS = 10_000;
const TICK_MS = 5_000;
const PING_MS = 3_000;
const DEAD_PINGS = 3;
async function ping(conn: Connection): Promise<boolean> {
  const asked = (async () => {
    const s = await conn.openBi();
    await writeLine(s, { method: "POST", path: "/bench/ping", headers: {} });
    const line = await new Reader(s).line();
    return line?.pong === true;
  })().catch(() => false);
  return (await Promise.race([asked, sleep(PING_MS)])) === true;
}
async function reachApp(ep: Endpoint, id: string, from: number, budget: number) {
  let dials = 0, timedOut = 0, failed = 0;
  const dropped: Record<string, unknown>[] = [];
  while (now() - from < budget) {
    dials++;
    let late = false;
    // Given up as the app gives up its opening's dial (an addon from before goes on with it).
    let giveUp = () => {};
    const givenUp = new Promise<void>((resolve) => (giveUp = resolve));
    const dial = ep.connect({ id, relays: RELAYS }, ALPN, [], givenUp);
    dial.then((c) => { if (late) c.close(0, "late"); }, () => {});
    const conn = await Promise.race([dial.catch(() => "failed" as const), sleep(CONNECT_MS)]);
    if (conn === "t") { late = true; giveUp(); timedOut++; continue; }
    if (conn === "failed") { failed++; await sleep(1000); continue; }
    const connectedMs = Math.round(now() - from);
    const at = wall();
    // The view, and the pings beside it until a frame came or the link is let go.
    let firstFrame: number | null = null;
    let missed = 0, gone = false;
    const view = (async () => {
      try {
        const s = await conn.openBi();
        await writeLine(s, { method: "POST", path: "/admin/api/screens/desktop/view", headers: {}, screen: { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: false } });
        const reader = new Reader(s);
        const head = await reader.line();
        if (head?.status !== 200) return;
        const frames = new FrameIn(s, reader.carry, 64 * 1024 * 1024);
        for (let f = await frames.next(); f && !gone; f = await frames.next()) {
          if (f.kind === KIND.video) { firstFrame = now(); void s.finish().catch(() => {}); return; }
        }
      } catch {}
    })();
    while (firstFrame === null && missed < DEAD_PINGS && now() - from < budget) {
      const tick = await Promise.race([view.then(() => "v" as const), sleep(TICK_MS)]);
      if (firstFrame !== null) break;
      if (tick === "v" && firstFrame === null && conn.isClosed()) { missed = DEAD_PINGS; break; }
      missed = (await ping(conn)) ? 0 : missed + 1;
    }
    if (firstFrame !== null) return { dials, timedOut, failed, connectedMs, firstFrameMs: Math.round(firstFrame - from), dropped, conn };
    gone = true;
    dropped.push({ at, connectedMs, paths: pathsOf(conn), stats: statsOf(conn) });
    conn.close(0, "dead");
  }
  return { dials, timedOut, failed, dropped, conn: null };
}

async function device(id: string, rounds: number) {
  const reachBy = process.env.DIAL === "app" ? reachApp : reach;
  for (let r = 0; r < rounds; r++) {
    const ep: Endpoint = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: RELAYS, discovery: true });
    const row: Record<string, unknown> = { round: r, at: wall(), device: ep.id().slice(0, 8) };
    try {
      const t0 = now();
      const first = await reachBy(ep, id, t0, 60_000);
      row.first = { ...first, conn: undefined };
      if (first.conn) {
        const conn = first.conn;
        const ask = await conn.openBi();
        const tKill = now();
        row.killAt = wall();
        await writeLine(ask, { method: "POST", path: "/bench/exit", headers: {} });
        void ask.finish().catch(() => {});
        await Promise.race([conn.closed(), sleep(5000)]);
        const again = await reachBy(ep, id, tKill, 120_000);
        row.again = { ...again, conn: undefined };
        again.conn?.close(0, "done");
      }
    } catch (e) {
      row.error = String(e);
    }
    // Its close waits for every dial still in its handshake to end, up to the connections' idle timeout: not waited
    // past a few seconds (they go on in the background meanwhile, as an app's abandoned dials do).
    const closed = await Promise.race([ep.close().then(() => "closed" as const), sleep(5000)]);
    if (closed === "t") row.closeHung = true;
    console.log(JSON.stringify(row));
    await sleep(3000);
  }
}

const [mode, ...rest] = process.argv.slice(2);
if (mode === "station") await station(rest[0]!);
else if (mode === "id") { const ep = await mesh.bind({ secretKey: keyOf(rest[0]!), alpns: [ALPN], relayUrls: [], discovery: false }); console.log(ep.id()); await ep.close(); process.exit(0); }
else if (mode === "device") { await device(rest[0]!, Number(rest[1] ?? 5)); process.exit(0); }
else if (mode === "exit") {
  const ep: Endpoint = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: RELAYS, discovery: true });
  const conn = await ep.connect({ id: rest[0]!, relays: RELAYS }, ALPN);
  const ask = await conn.openBi();
  await writeLine(ask, { method: "POST", path: "/bench/exit", headers: {} });
  await ask.finish().catch(() => {});
  await Promise.race([conn.closed(), sleep(5000)]);
  process.exit(0);
}
