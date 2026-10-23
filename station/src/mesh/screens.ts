// A view of one of the station's screens over a member's link (docs/remote-screens.md, "Wire"): a stream whose head
// line has a `screen` object, answered 200 `application/x-stillfail-screen`, then frames both ways, each a kind byte,
// its payload's length (4 bytes, big-endian) and the payload. Station → client: `config`, `video`, `state`; client →
// station: `input`, `ack`, `keyframe`; and the screen's clipboard both ways (`clipboard`), for a view that drives it
// (the station sends it as it changes, the client to set it and paste). The source is asked for a frame only while the
// `Pacer` lets one go: as many as the link holds (a far one holds several), none while the oldest not acknowledged
// waits longer than the link takes with no queue; and the source is asked for the bit rate the link carries
// (screen-pace.ts). So a slow link lowers the bit rate, then the frame rate, rather than queueing frames.
//
// A read-only member views, their input is dropped. The view ends when the client finishes its side (`ended:
// "finished"`), the source goes (`"gone"`, also when it has no more frames), the station stops (`"stopping"`), or the
// stream or its connection breaks (nothing more is written then); its source's capture stops with it.
import type { Clock } from "effect";
import { langOfCore } from "../api/request.ts";
import { liveClock } from "../ops/fibers.ts";
import { tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { type AccessShown, type ScreenHub, ScreenRefused, accessShown } from "../screens/hub.ts";
import { type Clip, type ClipType, type Codec, type Frame, type FrameConfig, type ScreenInput, type ScreenSource, type ScreenView, CLIP_PNG_MAX, clipFits } from "../screens/source.ts";
import { type Viewer, readOnly } from "./credential.ts";
import type { Stream } from "./native.ts";
import { Pacer, ownRate } from "./screen-pace.ts";
import { writeLine } from "./serve.ts";

export const SCREEN_TYPE = "application/x-stillfail-screen";
export const KIND = { config: 1, video: 2, state: 3, clipboard: 4, input: 16, ack: 17, keyframe: 18, setClipboard: 19 } as const;
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
  return Buffer.from(JSON.stringify({ codec: c.codec, width: c.width, height: c.height, ...(c.description ? { description: Buffer.from(c.description).toString("base64") } : {}) }));
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

/// What a client's input frame asks of the file manager (`{t: "reveal", path}`): the path, or null when it is not that.
export function parseReveal(v: any): string | null {
  return v !== null && typeof v === "object" && v.t === "reveal" && typeof v.path === "string" && v.path !== "" && v.path.length <= 4096 ? v.path : null;
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

/// What a view's ask says: its bounds (16..8192, 1920×1080 when not said) and the codecs it takes, ours only.
function asked(screen: any): { maxWidth: number; maxHeight: number; codecs: Codec[]; control: boolean; peek: boolean } {
  const bound = (v: unknown, otherwise: number) => (num(v) ? Math.min(8192, Math.max(16, Math.round(v))) : otherwise);
  const codecs = Array.isArray(screen.codecs) ? CODECS.filter((c) => screen.codecs.includes(c)) : [];
  // A preview (`peek`, a link's card in a chat) only looks.
  const peek = screen.peek === true;
  return { maxWidth: bound(screen.maxWidth, 1920), maxHeight: bound(screen.maxHeight, 1080), codecs, control: screen.control === true && !peek, peek };
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
    view = await source.open({ maxWidth: ask.maxWidth, maxHeight: ask.maxHeight, codecs: ask.codecs, ...(ask.peek ? { peek: true } : {}) });
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
  const pacer = new Pacer(() => Number(clock.monotonicTimeNanosUnsafe()) / 1e6);
  await new ViewSession({ hub, id, source, view, stream, frames: new FrameIn(stream, carry), name: viewer.name || viewer.email, control, peek: ask.peek, access, pacer }).run();
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
  #title: string;
  /// The bit rate the source was last asked for.
  #rate: number | null = null;

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
  readonly access: AccessShown | undefined;
  readonly pacer: Pacer;

  constructor(o: { hub: ScreenHub; id: string; source: ScreenSource; view: ScreenView; stream: Stream; frames: FrameIn; name: string; control: boolean; peek?: boolean; access: AccessShown | undefined; pacer: Pacer }) {
    this.hub = o.hub;
    this.id = o.id;
    this.source = o.source;
    this.view = o.view;
    this.stream = o.stream;
    this.frames = o.frames;
    this.name = o.name;
    this.control = o.control;
    this.peek = o.peek === true;
    this.access = o.access;
    this.pacer = o.pacer;
    this.#title = o.source.title();
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
    void this.#state({ title: this.#title, control: this.control, ...(this.access ? { access: this.access } : {}) });
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
    void this.stream.stopped().then(
      () => this.#stop(null),
      () => this.#stop(null),
    );
    void this.#read();
    await this.#pump();
    await this.#over;
  }

  /// The source asked for the bit rate the link carries, when it changed by more than a little.
  #pace() {
    const rate = this.pacer.rate();
    if (rate === null || !this.view.rate) return;
    if (this.#rate !== null && Math.abs(rate - this.#rate) < this.#rate * 0.05) return;
    this.#rate = rate;
    this.view.rate(Math.round(rate));
  }

  /// Frames out, while the client keeps up.
  async #pump() {
    while (!this.#closed) {
      if (!this.pacer.may()) {
        this.#pace();
        await new Promise<void>((resolve) => (this.#wake = resolve));
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
        if (next.config.codec !== "jpeg") this.pacer.ceiling(ownRate(next.config.width, next.config.height));
        void this.#send(KIND.config, configPayload(next.config));
      }
      this.pacer.sent(next.ts, next.data.length);
      await this.#send(KIND.video, videoPayload(next));
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
            this.pacer.acked(Number(got.payload.readBigUInt64BE(0)));
            this.#pace();
            this.#wake();
            break;
          }
          case KIND.keyframe:
            this.view.keyframe();
            break;
          case KIND.input: {
            if (!this.control) break;
            let raw: unknown = null;
            try {
              raw = JSON.parse(got.payload.toString("utf8"));
            } catch {}
            const reveal = parseReveal(raw);
            if (reveal !== null) {
              if (this.source.reveal && this.view.reveal) this.#then(() => this.view.reveal!(reveal));
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
