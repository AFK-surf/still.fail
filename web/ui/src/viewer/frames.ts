// A video's own frames (the player's look closely, Player.tsx): when each starts, as the file has them, and each
// decoded when asked (Mediabunny reads the file, WebCodecs decodes it), so a step is to the very next frame the file
// has, whatever its rate, and what shows paused is that frame's pixels: to zoom into, to read a pixel's colour from,
// to save as a PNG. A file here already is read from memory; a drive's, as it streams (the page's ranges of it).
import type { CanvasSink, Input, Source, WrappedCanvas } from "mediabunny";

type Canvas = HTMLCanvasElement | OffscreenCanvas;

/** Frames decoded are kept up to about this many bytes (a few dozen screen-sized ones). */
const KEEP_BYTES = 500e6;

/** The frame showing at `time` among frames starting at `starts` (in order): the last to start by then. */
export function frameAt(starts: readonly number[], time: number): number {
  let lo = 0, hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid]! <= time + 1e-4) lo = mid; else hi = mid - 1;
  }
  return Math.max(0, lo);
}

/** Its frame rate, and whether it holds (a screen recording's frames come only when something changes). */
export function rateOf(starts: readonly number[]): { fps: number; steady: boolean } {
  const gaps = starts.slice(1).map((s, i) => s - starts[i]!).sort((a, b) => a - b);
  if (!gaps.length) return { fps: 0, steady: true };
  const typical = gaps[gaps.length >> 1]!;
  const span = starts.at(-1)! - starts[0]!;
  return { fps: span > 0 ? gaps.length / span : 0, steady: gaps.at(-1)! < typical * 1.5 && gaps[0]! > typical / 1.5 };
}

/**
 * A video file's frames: when each starts, as the file has them, and each decoded when asked. Those decoded last are
 * kept, and decoding goes on from the last asked for, so stepping either way decodes each frame about once.
 */
export class Frames {
  private kept = new Map<number, Canvas>();
  private cursor: { canvases: AsyncGenerator<WrappedCanvas, void, unknown>; next: number } | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private wanted = -1;
  private last = 0;
  private closed = false;
  private readonly input: Input;
  private readonly sink: CanvasSink;
  readonly starts: number[];
  /** The frames decoding can start at (its key frames), in order. */
  private readonly keys: number[];
  readonly lastDuration: number;
  /** How many decoded frames are kept. */
  private readonly room: number;

  private constructor(input: Input, sink: CanvasSink, starts: number[], keys: number[], lastDuration: number, room: number) {
    this.input = input;
    this.sink = sink;
    this.starts = starts;
    this.keys = keys;
    this.lastDuration = lastDuration;
    this.room = room;
  }

  /** The frames of a video (here already, or at a URL that answers ranges), or null when it has no video track the
   *  browser can decode. */
  static async open(from: Blob | string): Promise<Frames | null> {
    const mb = await import("mediabunny");
    const source: Source = typeof from === "string" ? new mb.UrlSource(from) : new mb.BlobSource(from);
    const input = new mb.Input({ formats: mb.ALL_FORMATS, source });
    try {
      const track = await input.getPrimaryVideoTrack();
      if (!track || !(await track.canDecode())) { input.dispose(); return null; }
      const packets: { timestamp: number; duration: number; key: boolean }[] = [];
      for await (const p of new mb.EncodedPacketSink(track).packets(undefined, undefined, { metadataOnly: true })) packets.push({ timestamp: p.timestamp, duration: p.duration, key: p.type === "key" });
      if (!packets.length) { input.dispose(); return null; }
      // Packets come in decoding order; frames show in time order.
      packets.sort((a, b) => a.timestamp - b.timestamp);
      const pixels = (await track.getDisplayWidth()) * (await track.getDisplayHeight());
      const room = Math.max(10, Math.min(90, Math.floor(KEEP_BYTES / (pixels * 4))));
      const keys = packets.flatMap((p, i) => (p.key ? [i] : []));
      return new Frames(input, new mb.CanvasSink(track), packets.map((p) => p.timestamp), keys, packets.at(-1)!.duration, room);
    } catch (e) {
      input.dispose();
      throw e;
    }
  }

  /** The frame showing at `time` (the last to start by then). */
  at(time: number): number {
    return frameAt(this.starts, time);
  }

  /** When it ends: its last frame's start and how long that one shows. */
  get end(): number {
    return this.starts.at(-1)! + this.lastDuration;
  }

  /** Frame `i` decoded; null when another was asked for before its turn came (only the latest is decoded). */
  get(i: number): Promise<Canvas | null> {
    this.wanted = i;
    const run = this.queue.then(() => (this.wanted === i && !this.closed ? this.decode(i) : null));
    this.queue = run.catch(() => null);
    return run;
  }

  private async decode(i: number): Promise<Canvas | null> {
    const hit = this.kept.get(i);
    if (hit) {
      this.kept.delete(i);
      this.kept.set(i, hit);
      this.last = i;
      return hit;
    }
    let c = this.cursor;
    if (!c || c.next > i || i - c.next > this.room) {
      await c?.canvases.return();
      // Going back, the frames before it are decoded along with it: the steps back after it are then at hand. Only
      // those from its key frame on, which are decoded to reach it anyway: from further back, the key frame before
      // would be decoded from too, and a drag back would wait on a few dozen frames more than one forward does.
      const from = i < this.last ? Math.max(this.keyAt(i), i - this.room + 2) : i;
      c = this.cursor = { canvases: this.sink.canvases(this.starts[from]), next: from };
    }
    while (c.next <= i) {
      const r = await c.canvases.next();
      if (r.done) { this.cursor = null; break; }
      const n = this.nearest(r.value.timestamp);
      c.next = n + 1;
      this.kept.delete(n);
      this.kept.set(n, r.value.canvas);
    }
    for (const k of this.kept.keys()) {
      if (this.kept.size <= this.room) break;
      if (k !== i) this.kept.delete(k);
    }
    this.last = i;
    return this.kept.get(i) ?? null;
  }

  /** The key frame decoding frame `i` starts from. */
  private keyAt(i: number): number {
    const k = this.keys;
    let lo = 0, hi = k.length - 1;
    if (hi < 0 || k[0]! > i) return 0;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (k[mid]! <= i) lo = mid; else hi = mid - 1;
    }
    return k[lo]!;
  }

  private nearest(time: number): number {
    const i = this.at(time);
    const next = this.starts[i + 1];
    return next !== undefined && next - time < time - this.starts[i]! ? i + 1 : i;
  }

  dispose() {
    this.closed = true;
    void this.cursor?.canvases.return();
    this.cursor = null;
    this.kept.clear();
    this.input.dispose();
  }
}
