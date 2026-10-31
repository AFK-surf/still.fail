// A view of one of the station's screens over a member's link (docs/remote-screens.md, "Wire"): a stream whose head
// line has a `screen` object, answered 200 `application/x-stillfail-screen`, then frames both ways, each a kind byte,
// its payload's length (4 bytes, big-endian) and the payload. Station → client: `config`, `video`, `state`; client →
// station: `input`, `ack`, `keyframe`, `look` (the part of the screen it shows, zoomed in: its frames are then of that
// part, as large as the client shows it, each config saying which part); and the screen's clipboard both ways (`clipboard`), for a view that drives it
// (the station sends it as it changes, the client to set it and paste). The source is asked for a frame only while the
// `Pacer` lets one go: as many as the link holds (a far one holds several), none while the oldest not acknowledged
// waits longer than the link takes with no queue; and the source is asked for the bit rate the link carries
// (screen-pace.ts). So a slow link lowers the bit rate, then the frame rate, rather than queueing frames.
//
// A read-only member views, their input is dropped. The view ends when the client finishes its side (`ended:
// "finished"`), the source goes (`"gone"`, also when it has no more frames), the station stops (`"stopping"`), or the
// stream or its connection breaks (nothing more is written then); its source's capture stops with it.
import { type Clock, Duration, Effect } from "effect";
import { langOfCore } from "../api/request.ts";
import { liveClock } from "../ops/fibers.ts";
import { tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { type AccessShown, type ScreenHub, ScreenRefused, accessShown } from "../screens/hub.ts";
import { type Clip, type ClipType, type Codec, type Frame, type FrameConfig, type LoginFill, type Region, type ScreenInput, type ScreenSource, type ScreenView, type ViewFit, CLIP_PNG_MAX, clipFits, regionOf } from "../screens/source.ts";
import { type Viewer, readOnly } from "./credential.ts";
import type { Stream } from "./native.ts";
import { type Fps, FrameLatency, Pacer, type Quality, STILL_MS, START_RATE, Sharpener, Sizer, isFps, loopStall, rateCeiling } from "./screen-pace.ts";
import { writeLine } from "./serve.ts";

export const SCREEN_TYPE = "application/x-stillfail-screen";
export const KIND = { config: 1, video: 2, state: 3, clipboard: 4, audioConfig: 5, audio: 6, input: 16, ack: 17, keyframe: 18, setClipboard: 19, look: 20 } as const;
/// A client's frame is an input event at most: one larger ends the view.
export const MAX_IN = 64 * 1024;
/// A client's `clipboard` frame is its flags, its type and a picture at most.
export const MAX_CLIP_IN = 2 + CLIP_PNG_MAX;
/// How large a client's frame of a kind may be.
export const limitIn = (kind: number) => (kind === KIND.setClipboard ? MAX_CLIP_IN : MAX_IN);
/// A clip's type byte on the wire.
const CLIP_BYTE: Record<ClipType, number> = { text: 1, png: 2 };
const CODECS: Codec[] = ["h265", "h264", "jpeg"];
const PATH = /^\/admin\/api\/screens\/([^/?]+)\/view$/;

export function frame(kind: number, payload: Buffer): Buffer {
  const head = Buffer.alloc(5);
  head[0] = kind;
  head.writeUInt32BE(payload.length, 1);
  return Buffer.concat([head, payload]);
}

export function configPayload(c: FrameConfig): Buffer {
  return Buffer.from(JSON.stringify({ codec: c.codec, width: c.width, height: c.height, ...(c.description ? { description: Buffer.from(c.description).toString("base64") } : {}), ...(c.region ? { region: c.region } : {}) }));
}

export function videoPayload(f: Frame): Buffer {
  const head = Buffer.alloc(9);
  head[0] = f.key ? 1 : 0;
  head.writeBigUInt64BE(BigInt(Math.max(0, Math.floor(f.ts))), 1);
  return Buffer.concat([head, f.data]);
}

/// A clip as a `clipboard` frame's payload has it after its flags (station → client: none): its type byte, its bytes.
export function clipPayload(clip: Clip, flags?: number): Buffer {
  const body = clip.type === "text" ? Buffer.from(clip.text, "utf8") : Buffer.from(clip.data);
  return Buffer.concat([Buffer.from(flags === undefined ? [CLIP_BYTE[clip.type]] : [flags, CLIP_BYTE[clip.type]]), body]);
}

/// A client's `clipboard` frame: the clip (within its bounds) and whether to paste it; null when it is none.
export function parseClip(payload: Buffer): { clip: Clip; paste: boolean } | null {
  if (payload.length < 3) return null;
  const paste = (payload[0]! & 1) === 1;
  const body = payload.subarray(2);
  const clip: Clip | null = payload[1] === CLIP_BYTE.text ? { type: "text", text: body.toString("utf8") } : payload[1] === CLIP_BYTE.png ? { type: "png", data: new Uint8Array(body) } : null;
  return clip !== null && clipFits(clip) ? { clip, paste } : null;
}

/// What a client's input frame asks of the display's scale (`{t: "scale", percent}`): the percent, or null when it is
/// not that.
export function parseScale(v: any): number | null {
  return v !== null && typeof v === "object" && v.t === "scale" && Number.isInteger(v.percent) && v.percent >= 100 && v.percent <= 500 ? v.percent : null;
}

/// What a client's input frame asks of the display's resolution (`{t: "resolution", width, height}`): the size, or null
/// when it is not that.
export function parseResolution(v: any): { width: number; height: number } | null {
  const n = (x: unknown) => Number.isInteger(x) && (x as number) >= 640 && (x as number) <= 16384;
  return v !== null && typeof v === "object" && v.t === "resolution" && n(v.width) && n(v.height) ? { width: v.width, height: v.height } : null;
}

/// What a client's input frame asks of the file manager (`{t: "reveal", path}`): the path, or null when it is not that.
export function parseReveal(v: any): string | null {
  return v !== null && typeof v === "object" && v.t === "reveal" && typeof v.path === "string" && v.path !== "" && v.path.length <= 4096 ? v.path : null;
}

/// What a client's input frame fills a login form with (`{t: "fill", host, username?, password?}`: from the person's own
/// password manager, for the site the view's state said): null when it is not that. Each word is a field's: 1024
/// characters at most.
export function parseFill(v: any): LoginFill | null {
  if (v === null || typeof v !== "object" || v.t !== "fill" || typeof v.host !== "string" || v.host === "" || v.host.length > 253) return null;
  const word = (x: unknown) => typeof x === "string" && x.length <= 1024;
  if ((v.username !== undefined && !word(v.username)) || (v.password !== undefined && !word(v.password)) || (v.username === undefined && v.password === undefined)) return null;
  return { host: v.host, ...(v.username !== undefined ? { username: v.username } : {}), ...(v.password !== undefined ? { password: v.password } : {}) };
}

/// A client's `look` frame (JSON `{region, maxWidth, maxHeight}`): the part of the screen it shows (null: the whole) and
/// the bounds its pictures are to fit in (the view's own when not said, or for the whole); null when it is none.
export function parseLook(payload: Buffer, own: { maxWidth: number; maxHeight: number }): { region: Region | null; maxWidth: number; maxHeight: number } | null {
  let v: any;
  try {
    v = JSON.parse(payload.toString("utf8"));
  } catch {
    return null;
  }
  if (v === null || typeof v !== "object") return null;
  const region = regionOf(v.region);
  if (region === null) return { region: null, ...own };
  const bound = (n: unknown, otherwise: number) => (num(n) ? Math.min(8192, Math.max(16, Math.round(n))) : otherwise);
  return { region, maxWidth: bound(v.maxWidth, own.maxWidth), maxHeight: bound(v.maxHeight, own.maxHeight) };
}

/// Frames from a stream, after what came with its head line.
export class FrameIn {
  #carry: Buffer;
  readonly #stream: Stream;
  readonly #limit: (kind: number) => number;
  /// `limit`: the largest frame taken, or by its kind (the station takes a client's input frames and its clipboard;
  /// a client reads video frames).
  constructor(stream: Stream, carry: Buffer = Buffer.alloc(0), limit: number | ((kind: number) => number) = limitIn) {
    this.#stream = stream;
    this.#carry = carry;
    this.#limit = typeof limit === "number" ? () => limit : limit;
  }

  /// The next frame, or null where the stream finished between frames; throws where it ended inside one, or one is
  /// larger than its limit.
  async next(): Promise<{ kind: number; payload: Buffer } | null> {
    for (;;) {
      if (this.#carry.length >= 5) {
        const length = this.#carry.readUInt32BE(1);
        if (length > this.#limit(this.#carry[0]!)) throw new Error("screen frame too large");
        if (this.#carry.length >= 5 + length) {
          const kind = this.#carry[0]!;
          const payload = this.#carry.subarray(5, 5 + length);
          this.#carry = this.#carry.subarray(5 + length);
          return { kind, payload };
        }
      }
      const more = await this.#stream.read();
      if (more === null) {
        if (this.#carry.length === 0) return null;
        throw new Error("stream ended inside a screen frame");
      }
      this.#carry = this.#carry.length === 0 ? more : Buffer.concat([this.#carry, more]);
    }
  }
}

const num = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const unit = (v: number) => Math.min(1, Math.max(0, v));

/// A client's input event, checked: null when it is not one.
export function parseInput(v: any): ScreenInput | null {
  if (v === null || typeof v !== "object") return null;
  switch (v.t) {
    case "pointer":
      if (!["down", "up", "move"].includes(v.kind) || !num(v.x) || !num(v.y)) return null;
      return { t: "pointer", kind: v.kind, x: unit(v.x), y: unit(v.y), buttons: num(v.buttons) ? v.buttons & 7 : 0 };
    case "wheel":
      if (!num(v.x) || !num(v.y) || !num(v.dx) || !num(v.dy)) return null;
      return { t: "wheel", x: unit(v.x), y: unit(v.y), dx: Math.max(-10_000, Math.min(10_000, v.dx)), dy: Math.max(-10_000, Math.min(10_000, v.dy)) };
    case "key":
      if (!["down", "up"].includes(v.kind) || typeof v.key !== "string" || typeof v.code !== "string" || v.key.length > 64 || v.code.length > 64) return null;
      return { t: "key", kind: v.kind, key: v.key, code: v.code, mods: num(v.mods) ? v.mods & 15 : 0 };
    case "text":
      if (typeof v.text !== "string" || v.text.length === 0 || v.text.length > 4096) return null;
      return { t: "text", text: v.text };
    default:
      return null;
  }
}

/// What a view's ask says: its bounds (16..8192, 1920×1080 when not said), the codecs it takes (ours only), the 画质
/// chosen (`quality`: the most its bit rate goes to; none for 自动 and from a client before it), the 帧率 chosen (`fps`:
/// 120, 90, 60, 30 or 15, the most frames a second; none for 自动 and from a client before it), and the phone it is
/// laid out for (`fit`: 200..2000 CSS pixels a side, scale 1..4; only a view that drives it); `gamut: "p3"`: the client
/// shows a video tagged Display P3 as such (none: sRGB's colours).
export function asked(screen: any): { maxWidth: number; maxHeight: number; codecs: Codec[]; control: boolean; peek: boolean; audio?: boolean; quality?: Quality; fps?: Fps; fit?: ViewFit; gamut?: "p3" } {
  const bound = (v: unknown, otherwise: number) => (num(v) ? Math.min(8192, Math.max(16, Math.round(v))) : otherwise);
  const codecs = Array.isArray(screen.codecs) ? CODECS.filter((c) => screen.codecs.includes(c)) : [];
  // A preview (`peek`, a link's card in a chat) only looks.
  const peek = screen.peek === true;
  const control = screen.control === true && !peek;
  const f = screen.fit;
  const side = (v: unknown) => num(v) && v >= 200 && v <= 2000;
  const fit = control && f && side(f.width) && side(f.height) && num(f.scale) && f.scale >= 1 && f.scale <= 4 ? { width: Math.round(f.width), height: Math.round(f.height), scale: f.scale } : undefined;
  const quality: Quality | undefined = ["smooth", "hd", "original"].includes(screen.quality) && !peek ? screen.quality : undefined;
  const fps: Fps | undefined = isFps(screen.fps) && !peek ? screen.fps : undefined;
  return { maxWidth: bound(screen.maxWidth, 1920), maxHeight: bound(screen.maxHeight, 1080), codecs, control, peek, ...(screen.audio === "pcm_s16le" && !peek ? { audio: true } : {}), ...(quality ? { quality } : {}), ...(fps ? { fps } : {}), ...(fit ? { fit } : {}), ...(screen.gamut === "p3" ? { gamut: "p3" as const } : {}) };
}

/// A stream whose head says `"screen"` (serve.ts dispatches it): a view of a screen, for as long as both sides keep it.
/// `carry`: what came after the head line. Resolves once the view ended.
export async function answerScreen(hub: ScreenHub, stream: Stream, carry: Buffer, head: any, viewer: Viewer, up: () => boolean, clock: Clock.Clock = liveClock): Promise<void> {
  const headers: Record<string, string> = {};
  for (const [k, v] of Object.entries(head.headers ?? {})) if (typeof v === "string") headers[k] = v;
  const lang = langOfCore(headers);
  const refuse = async (status: number, error: string, more: Record<string, unknown> = {}) => {
    await writeLine(stream, { status, headers: { "content-type": "application/json" } });
    await stream.write(Buffer.from(JSON.stringify({ error, ...more })));
    await stream.finish();
  };
  const method = typeof head.method === "string" ? head.method.toUpperCase() : "GET";
  const path = typeof head.path === "string" ? head.path : "";
  const found = PATH.exec(path);
  if (found === null || method !== "POST") return refuse(404, "a screen is viewed with POST /admin/api/screens/<id>/view");
  if (!up()) return refuse(502, "station unreachable: not started");
  let id: string;
  try {
    id = decodeURIComponent(found[1]!);
  } catch {
    return refuse(404, tr(lang, "station.screen.notFound"));
  }
  const source = hub.get(id);
  if (source === undefined) return refuse(404, tr(lang, "station.screen.notFound"));
  const ask = asked(head.screen);
  if (ask.codecs.length === 0) return refuse(400, `screen.codecs: one of ${CODECS.join(", ")}`);
  if (ask.peek && !source.peek) return refuse(501, "this screen is not previewed");
  // A viewer (read-only member) sees, and does not drive.
  const control = ask.control && !readOnly(viewer);
  let view: ScreenView;
  try {
    view = await source.open({ maxWidth: ask.maxWidth, maxHeight: ask.maxHeight, codecs: ask.codecs, ...(ask.audio ? { audio: true } : {}), bitrate: START_RATE, ...(ask.fps ? { fps: ask.fps } : {}), ...(ask.peek ? { peek: true } : {}), ...(ask.fit && control ? { fit: ask.fit } : {}), ...(ask.gamut ? { gamut: ask.gamut } : {}) });
  } catch (error) {
    if (error instanceof ScreenRefused) {
      // What is missing says it all, and where it is granted.
      const access = accessShown(error.access, lang);
      return refuse(error.status, access?.message ?? tr(lang, error.key, error.args), access ? { access } : {});
    }
    return refuse(503, tr(lang, "station.screen.failed", { said: (error as Error).message }));
  }
  // Gone while it opened.
  if (hub.get(id) !== source) {
    view.close();
    return refuse(404, tr(lang, "station.screen.notFound"));
  }
  try {
    await writeLine(stream, { status: 200, headers: { "content-type": SCREEN_TYPE } });
  } catch {
    view.close();
    return;
  }
  const access = accessShown(source.access?.(), lang);
  const now = () => Number(clock.monotonicTimeNanosUnsafe()) / 1e6;
  // How long the loop stood still, on the host's own clock: what the pacer's times on the view's clock leave out only
  // when that clock is the host's (the live one). On another (a TestClock) the host's stands are no part of its time,
  // and taken from it they let a frame go past a queue the view's own time says is there (screens.test.ts, main
  // 167113d7, 40953448608: 18 frames asked for, not 17, on a loaded runner).
  const stall = clock === liveClock ? loopStall.use() : { stalled: () => 0, done: () => {} };
  const pacer = new Pacer(now, START_RATE, ask.fps, stall.stalled);
  const sizer = new Sizer(now, { maxWidth: ask.maxWidth, maxHeight: ask.maxHeight }, ask.quality);
  const sleep = (ms: number) => Effect.runPromise(clock.sleep(Duration.millis(ms)));
  await new ViewSession({ hub, id, source, view, stream, frames: new FrameIn(stream, carry), name: viewer.name || viewer.email, control, peek: ask.peek, audio: ask.audio, access, pacer, sizer, bounds: { maxWidth: ask.maxWidth, maxHeight: ask.maxHeight }, ...(ask.quality ? { quality: ask.quality } : {}), now, sleep })
    .run()
    .finally(stall.done);
}

/// One view while it lasts.
class ViewSession {
  #closed = false;
  #done!: () => void;
  readonly #over = new Promise<void>((resolve) => (this.#done = resolve));
  /// Writes, in order; one that fails breaks the view.
  #writes: Promise<void> = Promise.resolve();
  /// Inputs, in order, each once the one before was posted.
  #inputs: Promise<void> = Promise.resolve();
  #wake: () => void = () => {};
  #leave: () => void = () => {};
  #unwatch: () => void = () => {};
  #unclip: () => void = () => {};
  #unlogin: () => void = () => {};
  #unpoint: () => void = () => {};
  #title: string;
  /// The bit rate the source was last asked for.
  #rate: number | null = null;
  /// A still screen's picture sent again sharper (screen-pace.ts Sharpener), on the view's clock.
  readonly #sharpen = new Sharpener();
  #stillWait = false;
  readonly #now: () => number;
  readonly #sleep: (ms: number) => Promise<void>;

  readonly hub: ScreenHub;
  readonly id: string;
  readonly source: ScreenSource;
  readonly view: ScreenView;
  readonly stream: Stream;
  readonly frames: FrameIn;
  /// Whose it is, whether their input is taken, and what is missing of the source's access (as they read it).
  readonly name: string;
  readonly control: boolean;
  /// A preview's: not among those on the screen.
  readonly peek: boolean;
  readonly audio: boolean;
  readonly access: AccessShown | undefined;
  readonly pacer: Pacer;
  readonly sizer: Sizer;
  /// The 画质 the view asked (none: 自动, or a client before it): the most its bit rate goes to (screen-pace.ts rateCeiling).
  readonly quality: Quality | undefined;
  /// How late its frames are (the statistics' 帧延时).
  readonly latency = new FrameLatency();
  /// The picture's size, as its latest config said (H.264, H.265: what the bounds go by).
  #size: { width: number; height: number } | null = null;
  /// The bounds the view opened with (the whole screen's), and the part of the screen the client looks at now (null:
  /// the whole).
  readonly #own: { maxWidth: number; maxHeight: number };
  #region: Region | null = null;

  constructor(o: { hub: ScreenHub; id: string; source: ScreenSource; view: ScreenView; stream: Stream; frames: FrameIn; name: string; control: boolean; peek?: boolean; audio?: boolean; access: AccessShown | undefined; pacer: Pacer; sizer: Sizer; bounds: { maxWidth: number; maxHeight: number }; quality?: Quality; now: () => number; sleep: (ms: number) => Promise<void> }) {
    this.hub = o.hub;
    this.id = o.id;
    this.source = o.source;
    this.view = o.view;
    this.stream = o.stream;
    this.frames = o.frames;
    this.name = o.name;
    this.control = o.control;
    this.peek = o.peek === true;
    this.audio = o.audio === true && !this.peek;
    this.access = o.access;
    this.pacer = o.pacer;
    this.sizer = o.sizer;
    this.quality = o.quality;
    this.#own = o.bounds;
    this.#now = o.now;
    this.#sleep = o.sleep;
    this.#title = o.source.title();
  }

  /// A frame went: once the screen has been still for STILL_MS (no frame after it), if the rate has gone up since, the
  /// source sends its picture again as a key frame at the rate it is asked now (a source with a rate of its own: a
  /// video's, not JPEG's). One wait at a time, gone on from the last frame.
  #still() {
    this.#sharpen.sent(this.#now(), this.view.rate ? (this.#rate ?? START_RATE) : null);
    if (this.#stillWait) return;
    this.#stillWait = true;
    const wait = (ms: number) =>
      void this.#sleep(ms).then(() => {
        if (this.#closed) return;
        const left = this.#sharpen.left(this.#now());
        if (left > 0) return wait(left);
        this.#stillWait = false;
        if (this.#sharpen.due(this.#now(), this.#rate)) this.view.keyframe();
      });
    wait(STILL_MS);
  }

  #send(kind: number, payload: Buffer): Promise<void> {
    const written = this.#writes.then(() => this.stream.write(frame(kind, payload)));
    this.#writes = written.catch(() => this.#stop(null));
    return written.catch(() => {});
  }

  #state(state: Record<string, unknown>): Promise<void> {
    return this.#send(KIND.state, Buffer.from(JSON.stringify(state)));
  }

  /// Ends the view once: its capture stops, its people are told. `reason` null: the stream broke, nothing is written.
  #stop(reason: string | null) {
    if (this.#closed) return;
    this.#closed = true;
    this.#unclip();
    this.#unlogin();
    this.#unpoint();
    this.view.close();
    this.#leave();
    this.#unwatch();
    this.#wake();
    if (reason === null) {
      this.#done();
      return;
    }
    void this.#state({ ended: reason })
      .then(() => this.#writes)
      .then(() => this.stream.finish())
      .catch(() => {})
      .finally(() => this.#done());
  }

  async run(): Promise<void> {
    // How it starts: what it is and whether this view drives it; then who is on it (the hub tells everyone on it).
    // How its pictures are made (the statistics' 采集方式 and 编码器), where the source says.
    const video = this.view.video?.();
    void this.#state({ title: this.#title, control: this.control, ...(this.access ? { access: this.access } : {}), ...(video ? { video } : {}) });
    if (!this.peek) this.#leave = this.hub.join(this.id, { name: this.name, control: this.control, tell: (people) => void this.#state(people) });
    const unwatch = this.hub.watch(() => {
      if (this.hub.get(this.id) !== this.source) return this.#stop("gone");
      const title = this.source.title();
      if (title !== this.#title) {
        this.#title = title;
        void this.#state({ title });
      }
    });
    const unstop = this.hub.whenStopping(() => this.#stop("stopping"));
    this.#unwatch = () => (unwatch(), unstop());
    // The screen's clipboard, as it changes, to a person who drives it (never to one who only looks).
    const types = this.control ? (this.source.clipboard?.() ?? []) : [];
    if (types.length > 0 && this.view.watchClipboard) {
      this.#unclip = this.view.watchClipboard((clip) => {
        if (!this.#closed && types.includes(clip.type) && clipFits(clip)) void this.#send(KIND.clipboard, clipPayload(clip));
      });
    }
    // The login field in focus, to a person who drives it (their app offers to fill it from their password manager).
    if (this.control && this.view.watchLogin) {
      this.#unlogin = this.view.watchLogin((login) => {
        if (!this.#closed) void this.#state({ login });
      });
    }
    // The pointer, where the source's pictures leave it out (a video of the desktop): the client draws it.
    if (this.view.watchCursor) {
      this.#unpoint = this.view.watchCursor((cursor) => {
        if (!this.#closed) void this.#state({ cursor });
      });
    }
    // The display's scale, to a person who drives it (a source whose scale is changed: Windows' desktop).
    if (this.control && this.source.scale) {
      void this.source.scale().then((scale) => {
        if (scale !== null && !this.#closed) void this.#state({ scale });
      });
    }
    // Its resolution too (a source whose resolution is changed: Windows' desktop).
    if (this.control && this.source.resolution) {
      void this.source.resolution().then((resolution) => {
        if (resolution !== null && !this.#closed) void this.#state({ resolution });
      });
    }
    void this.stream.stopped().then(
      () => this.#stop(null),
      () => this.#stop(null),
    );
    void this.#read();
    if (this.audio && this.view.nextAudio) void this.#audio();
    await this.#pump();
    await this.#over;
  }

  /// One audio packet in flight: network backpressure never builds an audio queue behind video.
  async #audio(): Promise<void> {
    let configured = false;
    try {
      while (!this.#closed) {
        const next = await this.view.nextAudio!();
        if (this.#closed || next === null) break;
        if (!configured) {
          await this.#send(KIND.audioConfig, Buffer.from(JSON.stringify({ codec: "pcm_s16le", sampleRate: 48000, channels: 2 })));
          configured = true;
        }
        const payload = Buffer.alloc(8 + next.data.length);
        payload.writeBigUInt64BE(BigInt(Math.round(next.ts)), 0);
        payload.set(next.data, 8);
        await this.#send(KIND.audio, payload);
      }
    } catch (error) {
      log.info("screens", "system audio ended", { error: String(error) });
    }
  }

  /// The source asked for the bit rate the link carries, when it changed by more than a little; and for as small a
  /// picture as that rate makes sharpest (a source that changes its size).
  #pace() {
    const rate = this.pacer.rate();
    if (rate === null || !this.view.rate) return;
    if (this.#rate === null || Math.abs(rate - this.#rate) >= this.#rate * 0.05) {
      this.#rate = rate;
      this.view.rate(Math.round(rate));
    }
    if (this.#size && this.view.bounds) {
      const bounds = this.sizer.step(rate, this.pacer.through(), this.#size);
      if (bounds) this.#bounds(bounds);
    }
  }

  /// The source asked for its pictures in these bounds, of the part of the screen looked at (where it frames parts).
  #bounds(b: { maxWidth: number; maxHeight: number }) {
    if (!this.view.bounds) return;
    if (this.#region !== null) this.view.bounds(b.maxWidth, b.maxHeight, this.#region);
    else this.view.bounds(b.maxWidth, b.maxHeight);
  }

  /// The client looks at a part of the screen (or the whole again): a source that frames parts frames it, as large as
  /// asked (a config first, saying which part); one that does not goes on with the whole screen, which the client
  /// draws as it did.
  #look(look: { region: Region | null; maxWidth: number; maxHeight: number }) {
    if (!this.view.bounds || this.view.regions?.() !== true) return;
    if (JSON.stringify(look) === JSON.stringify({ region: this.#region, ...this.sizer.asked })) return;
    this.#region = look.region;
    this.#bounds(this.sizer.ask({ maxWidth: look.maxWidth, maxHeight: look.maxHeight }));
  }

  /// Frames out, while the client keeps up.
  async #pump() {
    while (!this.#closed) {
      if (!this.pacer.may()) {
        this.#pace();
        await new Promise<void>((resolve) => (this.#wake = resolve));
        continue;
      }
      // No sooner than the 帧率 asked lets it (the source asked it too, where it captures at a rate).
      const wait = this.pacer.wait();
      if (wait > 0) {
        // (woken as the view ends, too)
        await new Promise<void>((resolve) => {
          this.#wake = resolve;
          void this.#sleep(wait).then(resolve);
        });
        continue;
      }
      let next: Frame | null;
      try {
        next = await this.view.next();
      } catch (error) {
        log.warn("screens", "a screen's frame was not had", { screen: this.id, error: (error as Error).message });
        next = null;
      }
      if (this.#closed) return;
      if (next === null) return this.#stop("gone");
      if (next.config) {
        if (next.config.codec !== "jpeg") {
          this.pacer.ceiling(rateCeiling(next.config.width, next.config.height, this.quality));
          this.#size = { width: next.config.width, height: next.config.height };
        }
        void this.#send(KIND.config, configPayload(next.config));
      }
      this.pacer.sent(next.ts, next.data.length);
      this.latency.sent(next.ts);
      await this.#send(KIND.video, videoPayload(next));
      this.#still();
    }
  }

  /// What the client asks of the source, after what it asked before (a paste comes after the keys before it).
  #then(f: () => Promise<void>) {
    this.#inputs = this.#inputs.then(f).catch((error) => log.info("screens", "input not posted", { screen: this.id, error: (error as Error).message }));
  }

  /// What the client says, until it finishes.
  async #read() {
    try {
      for (;;) {
        const got = await this.frames.next();
        if (this.#closed) return;
        if (got === null) return this.#stop("finished");
        switch (got.kind) {
          case KIND.ack: {
            if (got.payload.length < 8) break;
            const acked = Number(got.payload.readBigUInt64BE(0));
            this.pacer.acked(acked);
            this.latency.acked(acked, this.pacer.rtt() ?? 0);
            const latency = this.latency.take();
            if (latency) void this.#state({ latency });
            this.#pace();
            this.#wake();
            break;
          }
          case KIND.keyframe:
            this.view.keyframe();
            break;
          case KIND.look: {
            const look = parseLook(got.payload, this.#own);
            if (look !== null) this.#look(look);
            break;
          }
          case KIND.input: {
            if (!this.control) break;
            let raw: unknown = null;
            try {
              raw = JSON.parse(got.payload.toString("utf8"));
            } catch {}
            const percent = parseScale(raw);
            if (percent !== null) {
              const source = this.source;
              if (source.setScale) {
                this.#then(() =>
                  source.setScale!(percent).then(
                    (scale) => void this.#state({ scale }),
                    (error) => log.info("screens", "the display's scale was not set", { screen: this.id, percent, error: (error as Error).message }),
                  ),
                );
              }
              break;
            }
            const size = parseResolution(raw);
            if (size !== null) {
              const source = this.source;
              if (source.setResolution) {
                this.#then(() =>
                  source.setResolution!(size.width, size.height).then(
                    (resolution) => void this.#state({ resolution }),
                    (error) => log.info("screens", "the display's resolution was not set", { screen: this.id, ...size, error: (error as Error).message }),
                  ),
                );
              }
              break;
            }
            const reveal = parseReveal(raw);
            if (reveal !== null) {
              if (this.source.reveal && this.view.reveal) this.#then(() => this.view.reveal!(reveal));
              break;
            }
            const fill = parseFill(raw);
            if (fill !== null) {
              // Only a view that drives it fills it.
              if (this.control && this.view.fill) this.#then(() => this.view.fill!(fill));
              break;
            }
            const e = parseInput(raw);
            if (e !== null) this.#then(() => this.view.input(e));
            break;
          }
          case KIND.setClipboard: {
            // Only a view that drives it sets it, of a type the source carries, within bounds.
            if (!this.control || !this.view.setClipboard) break;
            const asked = parseClip(got.payload);
            if (asked === null || !(this.source.clipboard?.() ?? []).includes(asked.clip.type)) break;
            this.#then(() => this.view.setClipboard!(asked.clip, asked.paste));
            break;
          }
          // Kinds of later clients: let be.
          default:
            break;
        }
      }
    } catch {
      this.#stop(null);
    }
  }
}
