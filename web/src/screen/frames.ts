// A screen view's pictures (docs/remote-screens.md; the core's `screen.view`): its `config` and `frame` values, with
// their bytes, drawn onto a canvas outside React. H.265 and H.264 through WebCodecs' VideoDecoder (the hvcC or avcC
// the config carries configures it), JPEG through createImageBitmap; each frame acknowledged once drawn (the station
// sends no more while those it sent wait: docs/remote-screens.md, "Pace"), and a key frame asked for when the decoder
// lost its state.

export type Codec = "h265" | "h264" | "jpeg";

/** An H.265 decoder failed before it drew anything (said to play it, it did not): H.264 from then on, on this page. */
let h265Failed = false;

/** Whether WebCodecs plays this codec here (with the hardware where the browser has it). */
async function plays(codec: string): Promise<boolean> {
  try {
    return (await VideoDecoder.isConfigSupported({ codec, optimizeForLatency: true })).supported === true;
  } catch {
    return false;
  }
}

/**
 * What the page decodes, best first: H.265 (Main, as the station encodes it on a Mac) and H.264 (Baseline) where
 * WebCodecs plays them, JPEG anywhere.
 */
export async function decodable(): Promise<Codec[]> {
  if (typeof VideoDecoder === "undefined") return ["jpeg"];
  const [h265, h264] = await Promise.all([!h265Failed && plays("hvc1.1.6.L153.B0"), plays("avc1.42E01F")]);
  return [...(h265 ? ["h265" as const] : []), ...(h264 ? ["h264" as const] : []), "jpeg"];
}

/** The codec string of an avcC (its profile, compatibility and level bytes): `avc1.PPCCLL`. */
export function avcCodec(avcc: Uint8Array | undefined): string {
  if (!avcc || avcc.length < 4) return "avc1.42E01F";
  const hex = (b: number) => b.toString(16).padStart(2, "0").toUpperCase();
  return `avc1.${hex(avcc[1]!)}${hex(avcc[2]!)}${hex(avcc[3]!)}`;
}

/**
 * The codec string of an hvcC (ISO/IEC 14496-15 E.3): `hvc1.` its profile (space and idc), its compatibility flags
 * (bits reversed, in hex), its tier and level, its constraint bytes (the trailing zero ones left out).
 */
export function hvcCodec(hvcc: Uint8Array | undefined): string {
  if (!hvcc || hvcc.length < 13) return "hvc1.1.6.L153.B0";
  const space = ["", "A", "B", "C"][hvcc[1]! >> 6]!;
  const tier = hvcc[1]! & 0x20 ? "H" : "L";
  const profile = hvcc[1]! & 0x1f;
  let flags = ((hvcc[2]! << 24) | (hvcc[3]! << 16) | (hvcc[4]! << 8) | hvcc[5]!) >>> 0;
  let reversed = 0;
  for (let i = 0; i < 32; i++, flags >>>= 1) reversed = ((reversed << 1) | (flags & 1)) >>> 0;
  const constraints = [...hvcc.subarray(6, 12)];
  while (constraints.length > 0 && constraints.at(-1) === 0) constraints.pop();
  return ["hvc1", `${space}${profile}`, reversed.toString(16).toUpperCase(), `${tier}${hvcc[12]}`, ...constraints.map((b) => b.toString(16).toUpperCase())].join(".");
}

/** The picture's size as chosen on this device (prefs `screenQuality`): `auto` as the window is. */
export type Quality = "auto" | "smooth" | "hd" | "original";
/** The bounds each chosen size asks for; `original`: the largest the core lets a view ask (the screen's own size). */
const QUALITY = { smooth: [1280, 720], hd: [1920, 1080], original: [7680, 4320] } as const;

/**
 * How large a picture to ask for: as chosen, or (`auto`) the window in device pixels, no larger than 1920×1080
 * (2560×1440 on a screen that has more), so a phone is not sent a desktop's every pixel.
 */
export function viewSize(quality: Quality = "auto"): { maxWidth: number; maxHeight: number } {
  if (quality !== "auto") { const [maxWidth, maxHeight] = QUALITY[quality]; return { maxWidth, maxHeight }; }
  const ratio = window.devicePixelRatio || 1;
  const big = screen.width * ratio >= 2560 && screen.height * ratio >= 1440;
  const [w, h] = big ? [2560, 1440] : [1920, 1080];
  return { maxWidth: Math.min(w, Math.round(window.innerWidth * ratio)), maxHeight: Math.min(h, Math.round(window.innerHeight * ratio)) };
}

export interface FrameConfig { codec: string; width: number; height: number }
export interface FrameHead { key: boolean; ts: number }

export interface FramesHooks {
  /** The frame of `ts` is drawn (or dropped): the station may send the next. */
  ack(ts: number): void;
  /** The decoder lost its state: the next frame must be a key frame. */
  keyframe(): void;
  /** A frame was drawn, `width`×`height` (the first one, and each time the size changes). */
  drawn(width: number, height: number): void;
  /** The codec does not play here after all (H.265 that failed before a frame): the view is to be opened again. */
  unplayable?(): void;
}

/** Draws a view's frames on `canvas` as they come, in the order they come. `close` when the view is gone. */
export class ScreenFrames {
  readonly #canvas: HTMLCanvasElement;
  readonly #ctx: CanvasRenderingContext2D | null;
  readonly #hooks: FramesHooks;
  #config: FrameConfig | null = null;
  #description: Uint8Array | undefined;
  #decoder: VideoDecoder | null = null;
  /** Nothing to decode from until a key frame comes (the first, after a config, after the decoder failed). */
  #needKey = true;
  /** The latest frame heard: acknowledged when the decoder fails, so the station does not wait on frames it lost. */
  #lastTs: number | null = null;
  /** JPEGs are decoded off the page's thread but drawn in the order they came. */
  #jpegs: Promise<void> = Promise.resolve();
  #closed = false;
  /** A frame came out of a decoder of this view's. */
  #played = false;
  #size = { width: 0, height: 0 };

  constructor(canvas: HTMLCanvasElement, hooks: FramesHooks) {
    this.#canvas = canvas;
    this.#ctx = canvas.getContext("2d", { alpha: false });
    this.#hooks = hooks;
  }

  /** A `config` value: what the frames after it are. The next video frame is a key frame. */
  config(config: FrameConfig, bytes: Uint8Array | undefined): void {
    if (this.#closed) return;
    this.#config = config;
    this.#description = bytes;
    this.#needKey = true;
    this.#dropDecoder();
    if (config.codec === "h264" || config.codec === "h265") this.#makeDecoder();
  }

  /** A `frame` value and its bytes. */
  frame(head: FrameHead, bytes: Uint8Array | undefined): void {
    if (this.#closed) return;
    this.#lastTs = head.ts;
    const config = this.#config;
    if (!config || !bytes) { this.#hooks.ack(head.ts); return; }
    if (config.codec === "jpeg") { this.#jpeg(head.ts, bytes); return; }
    if (config.codec !== "h264" && config.codec !== "h265") { this.#hooks.ack(head.ts); return; }
    if (this.#needKey && !head.key) { this.#hooks.ack(head.ts); return; }
    if (!this.#decoder && !this.#makeDecoder()) { this.#hooks.ack(head.ts); return; }
    try {
      this.#decoder!.decode(new EncodedVideoChunk({ type: head.key ? "key" : "delta", timestamp: head.ts, data: bytes }));
      this.#needKey = false;
    } catch {
      this.#lost();
    }
  }

  close(): void {
    this.#closed = true;
    this.#dropDecoder();
  }

  #makeDecoder(): boolean {
    if (typeof VideoDecoder === "undefined" || !this.#config) return false;
    const decoder = new VideoDecoder({
      output: (frame) => {
        if (this.#closed || decoder !== this.#decoder) { frame.close(); return; }
        this.#played = true;
        const ts = frame.timestamp;
        this.#draw(frame, frame.displayWidth, frame.displayHeight);
        frame.close();
        this.#hooks.ack(ts);
      },
      error: () => { if (decoder === this.#decoder) this.#lost(); },
    });
    try {
      decoder.configure({
        codec: this.#config.codec === "h265" ? hvcCodec(this.#description) : avcCodec(this.#description), optimizeForLatency: true, codedWidth: this.#config.width, codedHeight: this.#config.height,
        ...(this.#description ? { description: this.#description } : {}),
      });
    } catch {
      decoder.close();
      if (this.#config.codec === "h265" && !this.#played) {
        h265Failed = true;
        this.#hooks.unplayable?.();
      }
      return false;
    }
    this.#decoder = decoder;
    return true;
  }

  #dropDecoder(): void {
    const d = this.#decoder;
    this.#decoder = null;
    if (d && d.state !== "closed") d.close();
  }

  /** The decoder failed: a new one from the same config, from the next key frame, which the station is asked for. */
  #lost(): void {
    if (this.#config?.codec === "h265" && !this.#played) {
      h265Failed = true;
      this.#dropDecoder();
      this.#hooks.unplayable?.();
      return;
    }
    this.#dropDecoder();
    this.#needKey = true;
    if (this.#lastTs !== null) this.#hooks.ack(this.#lastTs);
    this.#hooks.keyframe();
  }

  #jpeg(ts: number, bytes: Uint8Array): void {
    const decoded = createImageBitmap(new Blob([bytes as BlobPart], { type: "image/jpeg" })).catch(() => null);
    this.#jpegs = this.#jpegs.then(async () => {
      const bitmap = await decoded;
      if (bitmap && !this.#closed) this.#draw(bitmap, bitmap.width, bitmap.height);
      bitmap?.close();
      if (!this.#closed) this.#hooks.ack(ts);
    });
  }

  #draw(picture: CanvasImageSource, width: number, height: number): void {
    const c = this.#canvas;
    // Sized as the picture, its pixels its own: the page scales the canvas, not what is drawn on it. Resized only as a
    // frame of the new size is drawn, so the last one stays until then.
    if (c.width !== width || c.height !== height) { c.width = width; c.height = height; }
    this.#ctx?.drawImage(picture, 0, 0, width, height);
    if (this.#size.width !== width || this.#size.height !== height) {
      this.#size = { width, height };
      this.#hooks.drawn(width, height);
    }
  }
}
