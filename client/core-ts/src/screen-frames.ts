// A screen view's frames on its stream (docs/remote-screens.md, Wire): a kind byte, the payload's length (4 bytes,
// big-endian), the payload. The station sends `config`, `video` and `state`; the client `input`, `ack`, `keyframe` and
// `look` (the part of the screen it shows, zoomed in); the screen's clipboard goes both ways (`clipboard`) while the
// view drives it.
// Read as the stream's pieces come, however they are cut: each frame's bytes are copied once, into an array of its own
// (what goes to the UI, transferred on the web).
import { fromBase64, fromUtf8, isObject, utf8 } from "./util.ts";

export const CONFIG = 1;
export const VIDEO = 2;
export const STATE = 3;
export const CLIPBOARD = 4;
export const INPUT = 16;
export const ACK = 17;
export const KEYFRAME = 18;
export const SET_CLIPBOARD = 19;
export const LOOK = 20;

/// A clip's type on the wire.
export type ClipType = "text" | "png";
const CLIP_BYTE: Record<ClipType, number> = { text: 1, png: 2 };
const CLIP_OF_BYTE: Record<number, ClipType> = { 1: "text", 2: "png" };
/// The most a clipboard carries each way (station/src/screens/source.ts): text's UTF-8 bytes, a picture's.
export const CLIP_TEXT_MAX = 1024 * 1024;
export const CLIP_PNG_MAX = 8 * 1024 * 1024;

/// A frame longer than this is no frame: the stream is out of step (or not a view's).
export const MAX_FRAME = 64 * 1024 * 1024;

// deno-lint-ignore no-explicit-any
type J = any;

/// A part of the screen, 0..1 of its width and height.
export type Region = { x: number; y: number; w: number; h: number };

/// `region`: the part of the screen the frames after it show (null: the whole).
export type FrameConfig = { codec: string; width: number; height: number; description: Uint8Array | null; region: Region | null };

/// What the station sends, read.
export type StationFrame =
  | { config: FrameConfig }
  | { video: { key: boolean; ts: number; data: Uint8Array } }
  | { state: J }
  /// The screen's clipboard, changed: its type and its bytes (text in UTF-8).
  | { clipboard: { type: ClipType; data: Uint8Array } }
  /// A kind this client does not know (a later station's): passed over.
  | { other: number };

const TWO_32 = 2 ** 32;

/// The frames of a stream, read as its pieces come.
export class FrameReader {
  readonly #chunks: Uint8Array[] = [];
  /// Where the first piece's unread bytes start.
  #at = 0;
  #have = 0;

  push(chunk: Uint8Array): void {
    if (chunk.length === 0) return;
    this.#chunks.push(chunk);
    this.#have += chunk.length;
  }

  /// The next whole frame, or null until more has come. Throws when the stream is not a view's frames.
  next(): StationFrame | null {
    if (this.#have < 5) return null;
    const kind = this.#peek(0);
    const length = ((this.#peek(1) << 24) | (this.#peek(2) << 16) | (this.#peek(3) << 8) | this.#peek(4)) >>> 0;
    if (length > MAX_FRAME) throw new Error(`a frame of ${length} bytes`);
    if (this.#have < 5 + length) return null;
    this.#skip(5);
    switch (kind) {
      case VIDEO: {
        if (length < 9) {
          this.#skip(length);
          throw new Error("a video frame without its head");
        }
        const head = this.#take(9);
        const view = new DataView(head.buffer);
        const ts = view.getUint32(1) * TWO_32 + view.getUint32(5);
        return { video: { key: (head[0]! & 1) === 1, ts, data: this.#take(length - 9) } };
      }
      case CONFIG: {
        const c = json(this.#take(length));
        if (!isObject(c) || typeof c.codec !== "string") throw new Error("a config that says no codec");
        const description = typeof c.description === "string" && c.description !== "" ? fromBase64(c.description) : null;
        return { config: { codec: c.codec, width: whole(c.width), height: whole(c.height), description, region: regionOf(c.region) } };
      }
      case STATE:
        return { state: json(this.#take(length)) };
      case CLIPBOARD: {
        const type = length > 0 ? CLIP_OF_BYTE[this.#peek(0)] : undefined;
        if (type === undefined) {
          this.#skip(length);
          return { other: kind };
        }
        this.#skip(1);
        return { clipboard: { type, data: this.#take(length - 1) } };
      }
      default:
        this.#skip(length);
        return { other: kind };
    }
  }

  #peek(i: number): number {
    let at = this.#at + i;
    for (const chunk of this.#chunks) {
      if (at < chunk.length) return chunk[at]!;
      at -= chunk.length;
    }
    return 0;
  }

  /// The next `n` bytes, in an array of their own.
  #take(n: number): Uint8Array {
    const out = new Uint8Array(n);
    let filled = 0;
    while (filled < n) {
      const chunk = this.#chunks[0]!;
      const count = Math.min(n - filled, chunk.length - this.#at);
      out.set(chunk.subarray(this.#at, this.#at + count), filled);
      filled += count;
      this.#advance(count);
    }
    return out;
  }

  #skip(n: number): void {
    let left = n;
    while (left > 0) {
      const chunk = this.#chunks[0]!;
      const count = Math.min(left, chunk.length - this.#at);
      left -= count;
      this.#advance(count);
    }
  }

  #advance(count: number): void {
    this.#at += count;
    this.#have -= count;
    if (this.#at === this.#chunks[0]!.length) {
      this.#chunks.shift();
      this.#at = 0;
    }
  }
}

function json(bytes: Uint8Array): J {
  return JSON.parse(fromUtf8(bytes));
}

/// A part of the screen as a station says it: within the screen, more than nothing each way; null when it is not one.
export function regionOf(v: unknown): Region | null {
  if (!isObject(v)) return null;
  const n = (k: string) => (typeof v[k] === "number" && Number.isFinite(v[k]) ? (v[k] as number) : NaN);
  const [x, y, w, h] = [n("x"), n("y"), n("w"), n("h")];
  if (!(x >= 0 && y >= 0 && w > 0 && h > 0 && x + w <= 1.0001 && y + h <= 1.0001)) return null;
  return { x, y, w, h };
}

function whole(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.round(v) : 0;
}

function frame(kind: number, payload: Uint8Array): Uint8Array {
  const out = new Uint8Array(5 + payload.length);
  out[0] = kind;
  new DataView(out.buffer).setUint32(1, payload.length);
  out.set(payload, 5);
  return out;
}

/// A person's input (screen.ts checks it first).
export function inputFrame(input: J): Uint8Array {
  return frame(INPUT, utf8(JSON.stringify(input)));
}

/// The timestamp (µs) of the last frame the client decoded.
export function ackFrame(ts: number): Uint8Array {
  const payload = new Uint8Array(8);
  const view = new DataView(payload.buffer);
  const t = Math.max(0, Math.floor(ts));
  view.setUint32(0, Math.floor(t / TWO_32));
  view.setUint32(4, t % TWO_32);
  return frame(ACK, payload);
}

export function keyframeFrame(): Uint8Array {
  return frame(KEYFRAME, new Uint8Array(0));
}

/// The part of the screen the client shows (null: the whole), and the bounds its pictures are to fit in (the device
/// pixels it is shown in).
export function lookFrame(region: Region | null, maxWidth: number, maxHeight: number): Uint8Array {
  return frame(LOOK, utf8(JSON.stringify(region ? { region, maxWidth, maxHeight } : { region: null })));
}

/// The screen's clipboard set (and pasted, with `paste`): flags, type, the bytes.
export function clipboardFrame(type: ClipType, data: Uint8Array, paste: boolean): Uint8Array {
  const payload = new Uint8Array(2 + data.length);
  payload[0] = paste ? 1 : 0;
  payload[1] = CLIP_BYTE[type];
  payload.set(data, 2);
  return frame(SET_CLIPBOARD, payload);
}

// ── what a station sends, for its tests and the test station ──

export function configFrame(config: { codec: string; width: number; height: number; description?: string; region?: Region }): Uint8Array {
  return frame(CONFIG, utf8(JSON.stringify(config)));
}

export function videoFrame(key: boolean, ts: number, data: Uint8Array): Uint8Array {
  const payload = new Uint8Array(9 + data.length);
  const view = new DataView(payload.buffer);
  payload[0] = key ? 1 : 0;
  view.setUint32(1, Math.floor(ts / TWO_32));
  view.setUint32(5, ts % TWO_32);
  payload.set(data, 9);
  return frame(VIDEO, payload);
}

export function stateFrame(state: J): Uint8Array {
  return frame(STATE, utf8(JSON.stringify(state)));
}

export function copiedFrame(type: ClipType, data: Uint8Array): Uint8Array {
  const payload = new Uint8Array(1 + data.length);
  payload[0] = CLIP_BYTE[type];
  payload.set(data, 1);
  return frame(CLIPBOARD, payload);
}

/// What the client sends, read (the test station's side).
export type ClientFrame = { input: J } | { ack: number } | { keyframe: true } | { look: J } | { clipboard: { type: ClipType | null; paste: boolean; data: Uint8Array } } | { other: number };

export function readClientFrames(buf: Uint8Array): [ClientFrame[], Uint8Array] {
  const frames: ClientFrame[] = [];
  let at = 0;
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  while (buf.length - at >= 5) {
    const len = view.getUint32(at + 1);
    if (buf.length - at - 5 < len) break;
    const payload = buf.subarray(at + 5, at + 5 + len);
    switch (buf[at]) {
      case INPUT:
        frames.push({ input: json(payload) });
        break;
      case ACK: {
        const p = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
        frames.push({ ack: p.getUint32(0) * TWO_32 + p.getUint32(4) });
        break;
      }
      case KEYFRAME:
        frames.push({ keyframe: true });
        break;
      case LOOK:
        frames.push({ look: json(payload) });
        break;
      case SET_CLIPBOARD:
        frames.push({ clipboard: { type: CLIP_OF_BYTE[payload[1] ?? 0] ?? null, paste: ((payload[0] ?? 0) & 1) === 1, data: payload.slice(2) } });
        break;
      default:
        frames.push({ other: buf[at]! });
    }
    at += 5 + len;
  }
  return [frames, buf.slice(at)];
}
