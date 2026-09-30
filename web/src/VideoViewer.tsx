// A video to play and to step through frame by frame, for a close look at an interface's motion. It plays in a
// <video>; paused, the frame shown is one decoded from the file itself (Mediabunny reads it, WebCodecs decodes it), so
// a step is to the very next frame the file has, whatever its frame rate, and what shows is that frame's pixels:
// to zoom into, to read a pixel's colour from, to save as a PNG.
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import type { CanvasSink, Input, WrappedCanvas } from "mediabunny";
import { REST_MS, TAP_REST_MS, useZoom } from "./FilePreview.tsx";
import { Camera, ChevronLeft, ChevronRight, Landscape, Pause, Play } from "./icons.tsx";
import * as css from "./VideoViewer.css.ts";
import * as fpCss from "./FilePreview.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import { Tip } from "./ui.tsx";

type Canvas = HTMLCanvasElement | OffscreenCanvas;

/** Frames decoded are kept up to about this many bytes (a few dozen screen-sized ones). */
const KEEP_BYTES = 500e6;
/** Without the file's own frames (a codec the browser cannot decode), a step is this long. */
const GUESSED_STEP = 1 / 60;
const RATES = ["0.1", "0.25", "0.5", "1"] as const;
type Rate = (typeof RATES)[number];

/**
 * A video file's frames: when each starts, as the file has them, and each decoded when asked. Those decoded last are
 * kept, and decoding goes on from the last asked for, so stepping either way decodes each frame about once.
 */
class Frames {
  private kept = new Map<number, Canvas>();
  private cursor: { canvases: AsyncGenerator<WrappedCanvas, void, unknown>; next: number } | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private wanted = -1;
  private last = 0;
  private closed = false;

  private constructor(private input: Input, private sink: CanvasSink, readonly starts: number[], readonly lastDuration: number, private room: number) {}

  /** The frames of a video, or null when there is no video track the browser can decode. */
  static async open(blob: Blob): Promise<Frames | null> {
    const mb = await import("mediabunny");
    const input = new mb.Input({ formats: mb.ALL_FORMATS, source: new mb.BlobSource(blob) });
    try {
      const track = await input.getPrimaryVideoTrack();
      if (!track || !(await track.canDecode())) { input.dispose(); return null; }
      const packets: { timestamp: number; duration: number }[] = [];
      for await (const p of new mb.EncodedPacketSink(track).packets(undefined, undefined, { metadataOnly: true })) packets.push({ timestamp: p.timestamp, duration: p.duration });
      if (!packets.length) { input.dispose(); return null; }
      // Packets come in decoding order; frames show in time order.
      packets.sort((a, b) => a.timestamp - b.timestamp);
      const pixels = (await track.getDisplayWidth()) * (await track.getDisplayHeight());
      const room = Math.max(10, Math.min(90, Math.floor(KEEP_BYTES / (pixels * 4))));
      return new Frames(input, new mb.CanvasSink(track), packets.map((p) => p.timestamp), packets.at(-1)!.duration, room);
    } catch (e) {
      input.dispose();
      throw e;
    }
  }

  /** The frame showing at `time` (the last to start by then). */
  at(time: number): number {
    const s = this.starts;
    let lo = 0, hi = s.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (s[mid]! <= time + 1e-4) lo = mid; else hi = mid - 1;
    }
    return lo;
  }

  /** How long frame `i` stays on screen, in seconds. */
  held(i: number): number {
    return i + 1 < this.starts.length ? this.starts[i + 1]! - this.starts[i]! : this.lastDuration;
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
      // Going back, the frames before it are decoded along with it: the steps back after it are then at hand.
      const from = i < this.last ? Math.max(0, i - this.room + 2) : i;
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

/** Seconds as m:ss.mmm. */
function clock(seconds: number): string {
  const ms = Math.max(0, Math.round(seconds * 1000));
  return `${Math.floor(ms / 60000)}:${String(Math.floor(ms / 1000) % 60).padStart(2, "0")}.${String(ms % 1000).padStart(3, "0")}`;
}

/** Its frame rate, and whether it holds (a screen recording's frames come only when something changes). */
function rateOf(starts: number[]): { fps: number; steady: boolean } {
  const gaps = starts.slice(1).map((s, i) => s - starts[i]!).sort((a, b) => a - b);
  if (!gaps.length) return { fps: 0, steady: true };
  const typical = gaps[gaps.length >> 1]!;
  const span = starts.at(-1)! - starts[0]!;
  return { fps: span > 0 ? gaps.length / span : 0, steady: gaps.at(-1)! < typical * 1.5 && gaps[0]! > typical / 1.5 };
}

/** The screen's turning locked (only where a page may: Android's browsers, in full screen; not iOS's). */
type Turnable = ScreenOrientation & { lock?(orientation: "landscape"): Promise<void>; unlock?(): void };
const canTurn = () => !!document.fullscreenEnabled && typeof (screen.orientation as Turnable | undefined)?.lock === "function";

export function VideoViewer({ url, blob, name }: { url: string; blob: Blob; name: string }) {
  const video = useRef<HTMLVideoElement>(null);
  const picture = useRef<HTMLCanvasElement>(null);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  // null while the file is read; "none" when its frames cannot be decoded here (then steps are by time).
  const [frames, setFrames] = useState<Frames | "none" | null>(null);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [drawn, setDrawn] = useState(-1);
  const [rate, setRate] = useState<Rate>("1");
  const [pixel, setPixel] = useState<{ x: number; y: number; color: string; clientX: number; clientY: number } | null>(null);
  // The controls float over the picture, and fade out when the pointer leaves it or rests a while (not over them).
  const [awake, setAwake] = useState(true);
  const resting = useRef(0);
  const onControls = useRef(false);
  const tapAt = useRef<{ x: number; y: number } | null>(null);
  const wake = useCallback((ms = REST_MS) => {
    setAwake(true);
    clearTimeout(resting.current);
    resting.current = window.setTimeout(() => { if (!onControls.current) setAwake(false); }, ms);
  }, []);
  useEffect(() => { wake(); return () => clearTimeout(resting.current); }, [wake]);

  // On a phone, the player can take the whole screen turned sideways.
  const root = useRef<HTMLDivElement>(null);
  const [turned, setTurned] = useState(false);
  useEffect(() => {
    const on = () => {
      const now = !!root.current && document.fullscreenElement === root.current;
      setTurned(now);
      if (!now) (screen.orientation as Turnable).unlock?.();
    };
    document.addEventListener("fullscreenchange", on);
    return () => document.removeEventListener("fullscreenchange", on);
  }, []);
  const turn = async () => {
    if (document.fullscreenElement) { await document.exitFullscreen(); return; }
    await root.current?.requestFullscreen({ navigationUI: "hide" });
    await (screen.orientation as Turnable).lock?.("landscape").catch(() => {});
  };
  // Zoom's tools go in the player's bar with the rest, not in the page's.
  const [zoomTools, setZoomTools] = useState<ReactNode>(null);
  const zoom = useZoom(natural, setZoomTools);
  const decoded = frames instanceof Frames ? frames : null;
  const decodedRef = useRef(decoded);
  decodedRef.current = decoded;
  const at = decoded ? decoded.at(time) : -1;
  const still = !!decoded && !playing && drawn === at;

  useEffect(() => {
    let live = true;
    let opened: Frames | null = null;
    setFrames(null);
    Frames.open(blob).then((f) => {
      opened = f;
      if (live) setFrames(f ?? "none"); else f?.dispose();
    }, (e: unknown) => {
      console.warn("video frames:", e);
      if (live) setFrames("none");
    });
    return () => { live = false; opened?.dispose(); };
  }, [blob]);

  // Playing, the time is the frame the video shows (not its clock, which runs between frames).
  useEffect(() => {
    const v = video.current;
    if (!v || !("requestVideoFrameCallback" in v)) return;
    let id = 0;
    const tick = (_: number, meta: VideoFrameCallbackMetadata) => {
      // Paused, the file's frames say where it is: a frame the video shows late (as it stops) must not move it back.
      if (!v.paused || !decodedRef.current) setTime(meta.mediaTime);
      id = v.requestVideoFrameCallback(tick);
    };
    id = v.requestVideoFrameCallback(tick);
    return () => v.cancelVideoFrameCallback(id);
  }, []);

  // Paused, the frame is drawn from the file.
  useEffect(() => {
    if (!decoded || playing || at < 0) return;
    let live = true;
    decoded.get(at).then((frame) => {
      const el = picture.current;
      if (!live || !frame || !el) return;
      if (el.width !== frame.width || el.height !== frame.height) { el.width = frame.width; el.height = frame.height; }
      el.getContext("2d", { willReadFrequently: true })!.drawImage(frame, 0, 0);
      setDrawn(at);
    }, (e: unknown) => console.warn("video frame:", e));
    return () => { live = false; };
  }, [decoded, playing, at]);

  useEffect(() => { if (video.current) video.current.playbackRate = Number(rate); }, [rate]);

  const toggle = useCallback(() => {
    const v = video.current;
    if (!v) return;
    if (!v.paused) { v.pause(); return; }
    if (decoded) {
      // From the frame stepped to (the video itself was left where it paused); from the start again at the end.
      const i = at >= decoded.starts.length - 1 ? 0 : at;
      v.currentTime = decoded.starts[i]! + 1e-4;
    }
    void v.play();
  }, [decoded, at]);

  const timeRef = useRef(time);
  timeRef.current = time;
  /** Paused, to the frame `to` makes of the one shown (without the file's frames, steps of a guessed frame rate). */
  const go = useCallback((to: (current: number) => number) => {
    const v = video.current;
    if (!v) return;
    if (!v.paused) v.pause();
    if (decoded) setTime(decoded.starts[Math.max(0, Math.min(decoded.starts.length - 1, to(decoded.at(timeRef.current))))]!);
    else v.currentTime = Math.max(0, Math.min(v.duration || 0, to(Math.round(v.currentTime / GUESSED_STEP)) * GUESSED_STEP));
  }, [decoded]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const by = e.shiftKey ? 10 : 1;
      if (e.key === " " || e.key === "k") toggle();
      else if (e.key === "ArrowLeft" || e.key === ",") go((i) => i - by);
      else if (e.key === "ArrowRight" || e.key === ".") go((i) => i + by);
      else if (e.key === "Home") go(() => 0);
      else if (e.key === "End") go(() => Infinity);
      else return;
      e.preventDefault();
      wake();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggle, go, wake]);

  const onPointerMove = (e: React.PointerEvent) => {
    zoom.stageProps.onPointerMove(e);
    const el = picture.current;
    if (!still || !el || e.pointerType === "touch") { setPixel(null); return; }
    const r = el.getBoundingClientRect();
    const x = Math.floor(((e.clientX - r.left) / r.width) * el.width), y = Math.floor(((e.clientY - r.top) / r.height) * el.height);
    if (x < 0 || y < 0 || x >= el.width || y >= el.height) { setPixel(null); return; }
    const [red, green, blue] = el.getContext("2d", { willReadFrequently: true })!.getImageData(x, y, 1, 1).data;
    setPixel({ x, y, clientX: e.clientX, clientY: e.clientY, color: `#${[red!, green!, blue!].map((c) => c.toString(16).padStart(2, "0")).join("").toUpperCase()}` });
  };

  const save = () => {
    picture.current?.toBlob((png) => {
      if (!png) return;
      const a = document.createElement("a");
      a.href = URL.createObjectURL(png);
      a.download = `${name.replace(/\.[^.]+$/, "")}-${at + 1}.png`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    }, "image/png");
  };

  const count = decoded?.starts.length ?? 0;
  const rateInfo = decoded ? rateOf(decoded.starts) : null;
  const pixelated = zoom.scale >= 2 || undefined;
  const seek = (t: number) => go(() => (decoded ? decoded.at(t) : Math.round(t / GUESSED_STEP)));
  const now = decoded ? decoded.starts[at]! : time;
  const facts = decoded ? [
    { key: "frame", text: <><b className={css.vvNow}>{at + 1}</b><span className={css.vvDim}> / {count} 帧</span></> },
    { key: "time", text: clock(now) },
    { key: "held", text: <Tip label="这一帧在屏幕上停留的时间"><span>{`停留 ${(decoded.held(at) * 1000).toFixed(1)} ms`}</span></Tip> },
    ...(rateInfo ? [{ key: "fps", text: <span className={css.vvDim}>{rateInfo.steady ? `${Math.round(rateInfo.fps)} fps` : `可变帧率 · 均 ${Math.round(rateInfo.fps)} fps`}</span> }] : []),
  ] : [
    { key: "time", text: <><b className={css.vvNow}>{clock(time)}</b><span className={css.vvDim}> / {clock(duration)}</span></> },
    { key: "note", text: <span className={css.vvDim}>{frames === null ? "正在读取帧…" : "没法逐帧解码，按 60 fps 估算"}</span> },
  ];
  // Beside the pointer, on the side with room.
  const left = pixel && pixel.clientX > window.innerWidth - 220;
  return (
    <div ref={root} className={css.vv} data-viewer-ground=""
      // A mouse wakes them by moving; a finger has no hover, and a tap on the picture shows or hides them.
      onPointerMove={(e) => { if (e.pointerType === "mouse") wake(); }}
      onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; clearTimeout(resting.current); if (!onControls.current) setAwake(false); }}
      onPointerDown={(e) => { tapAt.current = { x: e.clientX, y: e.clientY }; }}
      onPointerUp={(e) => {
        const t = tapAt.current;
        if (e.pointerType === "mouse" || !t || Math.hypot(e.clientX - t.x, e.clientY - t.y) > 10 || !zoom.stage.current?.contains(e.target as Node)) return;
        if (awake) { clearTimeout(resting.current); setAwake(false); } else wake(TAP_REST_MS);
      }}>
      <div ref={zoom.stage} className={`${fpCss.fpStage} ${css.vvStage}`} {...zoom.stageProps} onPointerMove={onPointerMove} onPointerLeave={() => setPixel(null)}>
        <video ref={video} className={css.vvPicture} data-pixelated={pixelated} src={url} autoPlay playsInline data-viewer-picture=""
          style={zoom.place ?? { visibility: "hidden" }}
          onLoadedMetadata={(e) => { const v = e.currentTarget; setNatural({ w: v.videoWidth, h: v.videoHeight }); setDuration(v.duration); }}
          onPlay={() => setPlaying(true)} onPause={() => setPlaying(false)} />
        <canvas ref={picture} className={css.vvPicture} data-pixelated={pixelated} aria-label={decoded ? `第 ${at + 1} 帧` : undefined}
          style={{ ...(zoom.place ?? {}), visibility: still && zoom.place ? "visible" : "hidden" }} />
      </div>
      {pixel && (
        <span className={css.vvPixel} style={{ top: pixel.clientY + 16, ...(left ? { right: window.innerWidth - pixel.clientX + 12 } : { left: pixel.clientX + 16 }) }}>
          <span className={css.vvSwatch} style={{ background: pixel.color }} />{pixel.color}<span className={css.vvDim}>{pixel.x}, {pixel.y}</span>
        </span>
      )}
      <div className={css.vvBar} data-floats data-awake={awake || undefined}
        onPointerEnter={(e) => { if (e.pointerType !== "mouse") return; onControls.current = true; clearTimeout(resting.current); setAwake(true); }}
        onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; onControls.current = false; wake(); }}
        // A finger on them keeps them a while longer.
        onPointerDown={(e) => { if (e.pointerType !== "mouse") wake(TAP_REST_MS); }}>
        <Timeline start={decoded?.starts[0] ?? 0} end={decoded ? decoded.starts.at(-1)! + decoded.lastDuration : duration} now={now} onSeek={seek} />
        <div className={css.vvRow}>
          <span className={css.vvGroup}>
            <Tip label="上一帧（← 或 ,；Shift 一次 10 帧）"><button type="button" className={pagesCss.iconBtn} aria-label="上一帧" onClick={() => go((i) => i - 1)}><ChevronLeft size={18} /></button></Tip>
            <Tip label={playing ? "暂停（空格）" : "播放（空格）"}><button type="button" className={pagesCss.iconBtn} aria-label={playing ? "暂停" : "播放"} onClick={toggle}>
              {playing ? <Pause size={18} /> : <Play size={18} />}
            </button></Tip>
            <Tip label="下一帧（→ 或 .；Shift 一次 10 帧）"><button type="button" className={pagesCss.iconBtn} aria-label="下一帧" onClick={() => go((i) => i + 1)}><ChevronRight size={18} /></button></Tip>
          </span>
          <span className={css.vvInfo}>
            {facts.map((f) => <span key={f.key} className={css.vvFact} data-fact={f.key}>{f.text}</span>)}
          </span>
          <span className={css.vvGroup}>
            {zoomTools}
            <Tip label="播放速度（点一下换一档）"><button type="button" className={css.vvRate}
              onClick={() => setRate((r) => RATES[(RATES.indexOf(r) + RATES.length - 1) % RATES.length]!)}>{rate}×</button></Tip>
            <Tip label="把这一帧存成 PNG"><button type="button" className={pagesCss.iconBtn} aria-label="保存这一帧" disabled={!still} onClick={save}><Camera size={18} /></button></Tip>
            {canTurn() && <button type="button" className={`${pagesCss.iconBtn} ${css.vvTurn}`} aria-label={turned ? "退出横屏" : "横屏"} aria-pressed={turned}
              onClick={() => void turn().catch((e: unknown) => console.warn("full screen:", e))}><Landscape size={18} /></button>}
          </span>
        </div>
      </div>
    </div>
  );
}

/** Where in the video it is, to click or drag to a place. */
function Timeline({ start, end, now, onSeek }: { start: number; end: number; now: number; onSeek(time: number): void }) {
  const box = useRef<HTMLDivElement>(null);
  const span = Math.max(1e-6, end - start);
  const at = (clientX: number) => {
    const r = box.current!.getBoundingClientRect();
    return start + Math.min(1, Math.max(0, (clientX - r.left) / r.width)) * span;
  };
  const dragging = useRef(false);
  const where = `${Math.min(100, Math.max(0, ((now - start) / span) * 100))}%`;
  return (
    <div ref={box} className={css.vvTimeline} role="slider" aria-label="位置" aria-valuemin={0} aria-valuemax={Math.round(span * 1000)} aria-valuenow={Math.round((now - start) * 1000)}
      onPointerDown={(e) => { if (e.button !== 0) return; e.currentTarget.setPointerCapture(e.pointerId); dragging.current = true; onSeek(at(e.clientX)); }}
      onPointerMove={(e) => { if (dragging.current) onSeek(at(e.clientX)); }}
      onPointerUp={() => { dragging.current = false; }} onPointerCancel={() => { dragging.current = false; }}>
      <span className={css.vvTrack}><span className={css.vvPlayed} style={{ width: where }} /></span>
      <span className={css.vvHead} style={{ left: where }} />
    </div>
  );
}
