// This machine's display as a screen source (`desktop`, docs/remote-screens.md): on macOS, still.fail Helper
// (helper/app.ts) captures the main display with ScreenCaptureKit, encodes H.264 with VideoToolbox (or a JPEG a
// picture, for a view that takes no H.264) and posts input with CGEvent, a view a connection to it. Windows' is
// win-desktop.ts (its views are this file's HelperView too); elsewhere the desktop says it is not supported, and opens
// nothing.
//
// macOS grants Screen Recording and Accessibility to the helper app. Opening the desktop while one is missing puts the
// helper's window up on this Mac (once an attempt, the system's own prompt not asked: it would fight the window): a
// row per grant, Allow opens System Settings with the app to drag into its list. The helper starts itself again once a
// grant is taken, so the grant is in effect; the station's process is never restarted for it. What is missing, and
// whether the window is up, is told with the screens (`access`).
//
// A view a person drives carries the Mac's clipboard both ways (text, PNG): the helper sets NSPasteboard and pastes with
// ⌘V, and, while the view watches it, looks at its changeCount every half a second and says what was copied.
import { hostname } from "node:os";
import type { HelperApp } from "../helper/app.ts";
import { HelperGrants } from "../helper/grants.ts";
import { wall } from "../ops/fibers.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { ScreenRefused } from "./hub.ts";
import { MacInput } from "./mac-input.ts";
import { helperUi } from "./ui.ts";
export type { HelperStatus } from "../helper/grants.ts";
import { type AudioFrame, type Clip, type ClipType, type Codec, type Frame, type FrameConfig, type Region, type ScreenAccess, type ScreenCursor, type ScreenInput, type ScreenVideo, type ScreenSource, type ScreenView, type ViewOptions, clipFits, regionOf } from "./source.ts";

export type DesktopOptions = {
  /// Whether this machine's display can be seen at all (platform.desktopScreen: the helper).
  supported: boolean;
  /// still.fail Helper, null when the release has none.
  helper: HelperApp | null;
  /// What is known of its grants, shared with the station's other parts (default: its own).
  grants?: HelperGrants | null;
  /// Told when its size or access changed.
  changed: () => void;
  /// Its title (default: the machine's name).
  title?: () => string;
  /// The language of the helper's window (default: the station's).
  lang?: () => Lang;
  /// The side test's measurement of the encoder and the link without Screen Recording: made-up pictures, no capture.
  /// Never set by the station.
  synthetic?: "moving" | "still";
};

/// The helper's window's words, in `lang` (Permissions.swift; PermissionFlow's panel under `panel`).
export function windowWords(lang: Lang): Record<string, unknown> {
  const w = (key: string, args: Record<string, unknown> = {}) => tr(lang, `station.helper.window.${key}`, args);
  return {
    title: w("title"),
    subtitle: w("subtitle"),
    capture: w("capture"),
    captureWhy: w("captureWhy"),
    control: w("control"),
    controlWhy: w("controlWhy"),
    allow: w("allow"),
    done: w("done"),
    panel: {
      // String(format:) positions: the app, then the grant.
      "permission_flow.panel.title": w("drag", { app: "%1$@", grant: "%2$@" }),
      "permission_flow.panel.step": w("step", { n: "%d" }),
      "permission_flow.drag.label": w("dragLabel"),
      "permission_flow.pane.screen_recording": w("capture"),
      "permission_flow.pane.accessibility": w("control"),
      "permission_flow.pane.permission": w("grant"),
      "permission_flow.app.this_app": "still.fail Helper",
    },
  };
}

export class Desktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly reveal = true;
  readonly #o: DesktopOptions;
  readonly #grants: HelperGrants | null;
  readonly #views = new Set<HelperView>();
  /// Its window was put up for grants not all taken yet: up again when the helper comes back still lacking one.
  #wanted = false;

  constructor(options: DesktopOptions) {
    this.#o = options;
    this.#grants = options.helper === null ? null : (options.grants ?? new HelperGrants({ helper: options.helper }));
    // Its grants or display changed: told with the screens.
    this.#grants?.onChange(() => this.#o.changed());
  }

  get #status() {
    return this.#grants?.status() ?? null;
  }

  title(): string {
    return this.#o.title?.() ?? hostname().replace(/\.local$/, "");
  }

  size(): { width: number; height: number } {
    return { width: this.#status?.display?.width ?? 0, height: this.#status?.display?.height ?? 0 };
  }

  /// Text and pictures, wherever the helper is.
  clipboard(): ClipType[] {
    return this.#o.supported && this.#o.helper !== null ? ["text", "png"] : [];
  }

  access(): ScreenAccess {
    if (!this.#o.supported) return { capture: false, control: false, unsupported: "platform" };
    if (this.#o.helper === null) return { capture: false, control: false, unsupported: "helper" };
    const s = this.#status;
    // Not looked at yet: nothing said.
    if (s === null) return { capture: true, control: true };
    const who = s.responsible?.path ? { app: s.responsible.name, path: s.responsible.path } : {};
    return { capture: s.capture, control: s.control, ...who, ...(s.asking ? { asking: true } : {}) };
  }

  /// The grants and the display as macOS has them now (at most a moment old, unless `force`); the helper started for it.
  refresh(force = false): Promise<void> {
    if (!this.#o.supported || this.#grants === null) return Promise.resolve();
    return this.#grants.refresh(force);
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    const helper = this.#o.helper;
    if (!this.#o.supported) throw new ScreenRefused(501, "station.screen.unsupported", {}, this.access());
    if (helper === null) throw new ScreenRefused(501, "station.screen.noHelper", {}, this.access());
    // H.265 where it is taken (the hardware's, smallest; the helper makes H.264 where this Mac encodes no H.265), H.264,
    // else a JPEG a picture (an agent's view, a client without either).
    const codec: Codec | undefined = (["h265", "h264", "jpeg"] as const).find((c) => options.codecs.includes(c));
    if (codec === undefined) throw new ScreenRefused(415, "station.screen.codec", { codec: "H.264, JPEG" });
    await this.refresh(true);
    const synthetic = this.#o.synthetic !== undefined;
    if (!synthetic && this.#status === null) throw new ScreenRefused(503, "station.screen.failed", { said: "still.fail Helper did not answer" });
    if (!synthetic && this.#status !== null && (!this.#status.capture || !this.#status.control)) await this.#ask(helper);
    if (!synthetic && this.#status?.capture !== true) throw this.#refused();
    // Granted since the helper started: it starts itself again to have it, and is asked once more.
    // The Mac's system output too, when the client asked for it (never a preview's): a helper from before it says no
    // `audio` in its info, and none is pulled.
    const audio = options.audio === true && !options.peek;
    for (let attempt = 0; ; attempt++) {
      const view = new HelperView(codec, await helper.connect({ op: "screen.view", codec, maxWidth: options.maxWidth, maxHeight: options.maxHeight, ...(options.bitrate ? { bitrate: Math.round(options.bitrate) } : {}), ...(options.fps ? { fps: options.fps } : {}), ...(options.gamut ? { gamut: options.gamut } : {}), ...(this.#status?.display ? { display: this.#status.display.id } : {}), ...(audio ? { audio: true } : {}), ...(synthetic ? { synthetic: this.#o.synthetic } : {}) }), () => this.#views.delete(view), new MacInput(), "ScreenCaptureKit", audio);
      this.#views.add(view);
      try {
        await view.ready;
        return view;
      } catch (error) {
        view.close();
        const code = (error as HelperError).code;
        if (code === "restart" && attempt === 0) {
          await helper.back();
          continue;
        }
        if (code === "capture" || code === "restart") {
          await this.refresh(true);
          throw this.#refused();
        }
        throw new ScreenRefused(503, "station.screen.failed", { said: (error as Error).message });
      }
    }
  }

  #refused(): ScreenRefused {
    const access = this.access();
    return new ScreenRefused(503, "station.screen.captureOff", { app: access.app || "still.fail Helper" }, access);
  }

  /// The helper came back after it ended by itself (macOS's Quit & Reopen after a grant, a crash): its window again,
  /// with what is still missing, when it was asking.
  async helperBack() {
    await this.refresh(true);
    const s = this.#status;
    if (s === null) return;
    if (s.capture && s.control) this.#wanted = false;
    else if (this.#wanted && this.#o.helper !== null) await this.#ask(this.#o.helper);
  }

  /// The helper's window asking for what is missing, on this Mac, in its language; what it says then.
  async #ask(helper: HelperApp) {
    this.#wanted = true;
    try {
      await helper.request({ op: "permissions.show", words: windowWords(this.#o.lang?.() ?? stationLang()), grants: ["capture", "control"] });
      await this.refresh(true);
    } catch (error) {
      log.warn("screens", "still.fail Helper's window did not show", { error: (error as Error).message });
    }
  }

  /// Its apps' accessibility trees: agent-desktop in still.fail Helper, with the helper's Accessibility (screens/ui.ts).
  ui(args: string[]): Promise<unknown> {
    const helper = this.#o.helper;
    if (!this.#o.supported || helper === null) return Promise.reject(new ScreenRefused(501, this.#o.supported ? "station.screen.noHelper" : "station.screen.unsupported", {}, this.access()));
    return helperUi(helper)(args);
  }

  /// The station stopping: every view ends, and the helper (resolved once it is gone).
  close(): Promise<void> {
    for (const view of [...this.#views]) view.close();
    return this.#o.helper?.quit().catch(() => {}) ?? Promise.resolve();
  }
}

type HelperError = Error & { code?: string };

/// The helper's messages: a kind byte, the payload's length (4 bytes), the payload (native/helper's ScreenView.swift).
/// To it: 1 next, 2 keyframe, 3 input, 4 clipboard (flags: bit 0 paste; type: 1 text, 2 PNG; the bytes), 5 watch the
/// clipboard (1 on, 0 off), 6 reveal (the path), 7 rate (bits a second, 4 bytes), 8 bounds (JSON {maxWidth, maxHeight,
/// region?}: `region` a part of the display, 0..1 of it, framed alone; none, the whole); a helper from before 7 and 8
/// lets them be, one from before regions frames the whole display (its info says `regions: true` where it frames parts);
/// 9 audio (empty: the next 20 ms packet of system output, a view opened with `audio: true` whose info says `audio: true`).
/// From it: 1 info, 2 config, 3 frame, 4 event, 5 clipboard (type, bytes), 6 cursor (JSON {x, y, shape}: a video's
/// pictures leave the pointer out), 7 region (JSON {region}: the part of the display the frames from the next on show,
/// as it was framed; null the whole; said before the frame whose part is another than the last one's), 8 audio config
/// (JSON {codec: "pcm_s16le", sampleRate: 48000, channels: 2}, or {error}: no more audio), 9 audio (8 bytes timestamp
/// µs, then 3840 bytes of interleaved stereo PCM16).
export const TO_HELPER = { next: 1, keyframe: 2, input: 3, clipboard: 4, watch: 5, reveal: 6, rate: 7, bounds: 8, audio: 9 } as const;
const CLIP_BYTE: Record<ClipType, number> = { text: 1, png: 2 };

/// A clip as the helper's `clipboard` message has it: from the helper (`flags` none) or to it.
export function helperClip(clip: Clip, flags?: number): Buffer {
  const body = clip.type === "text" ? Buffer.from(clip.text, "utf8") : Buffer.from(clip.data);
  return Buffer.concat([Buffer.from(flags === undefined ? [CLIP_BYTE[clip.type]] : [flags, CLIP_BYTE[clip.type]]), body]);
}
export function helperMessage(kind: number, payload: Buffer = Buffer.alloc(0)): Buffer {
  const head = Buffer.alloc(5);
  head[0] = kind;
  head.writeUInt32BE(payload.length, 1);
  return Buffer.concat([head, payload]);
}

/// What carries a view's messages to and from the helper: its socket (macOS), or a process's pipes (Windows'
/// stillfail-screen, win-desktop.ts).
export type HelperPipe = { write(data: Buffer): unknown; destroy(): unknown; on(event: "data", listener: (chunk: Buffer) => void): unknown; on(event: "error" | "close", listener: () => void): unknown };

/// How a view's input is posted on the machine: the ops its helper takes for one person's event (mac-input.ts,
/// win-input.ts), at `now` (ms).
export type InputOps = { ops(event: ScreenInput, now: number): object[] };

/// One view: a connection to the helper, asked for each frame.
export class HelperView implements ScreenView {
  readonly ready: Promise<{ width: number; height: number }>;
  readonly #socket: HelperPipe;
  readonly #input: InputOps;
  #carry: Buffer = Buffer.alloc(0);
  #waiting: ((frame: Frame | null) => void)[] = [];
  #config: FrameConfig | undefined;
  #audio = false;
  #audioWait: ((frame: AudioFrame | null) => void) | null = null;
  /// The latest config said (a frame of another part of the display goes with it again, its part said), the part the
  /// next frame shows as the helper said it (null: the whole), and whether its info said it frames parts.
  #lastConfig: FrameConfig | undefined;
  #region: Region | null = null;
  #sentRegion: Region | null = null;
  #regions = false;
  #ended = false;
  #settle!: { resolve: (v: { width: number; height: number }) => void; reject: (e: Error) => void };
  readonly #gone: () => void;
  /// Who hears the clipboard as it changes, while it is watched.
  #clipboard: ((clip: Clip) => void) | null = null;
  /// Who hears the pointer, and the last it said (told at once to one who starts to hear it).
  #cursor: ((cursor: ScreenCursor) => void) | null = null;
  #lastCursor: ScreenCursor | null = null;

  /// What it was asked for, then what it encodes (its `info`).
  #codec: Codec;

  /// What captures its pictures (still.fail Helper's ScreenCaptureKit, stillfail-screen's Windows.Graphics.Capture), and
  /// the encoder as its info named it.
  readonly #capture: string;
  #encoder = "";

  constructor(codec: Codec, socket: HelperPipe, gone: () => void, input: InputOps = new MacInput(), capture = "ScreenCaptureKit", audio = false) {
    this.#audio = audio;
    this.#codec = codec;
    this.#capture = capture;
    this.#socket = socket;
    this.#input = input;
    this.#gone = gone;
    this.ready = new Promise((resolve, reject) => (this.#settle = { resolve, reject }));
    socket.on("data", (chunk: Buffer) => this.#heard(chunk));
    socket.on("error", () => this.close());
    socket.on("close", () => {
      this.#settle.reject(new Error("the screen's helper ended the view"));
      this.close();
    });
  }

  #heard(chunk: Buffer) {
    this.#carry = this.#carry.length === 0 ? chunk : Buffer.concat([this.#carry, chunk]);
    while (this.#carry.length >= 5) {
      const length = this.#carry.readUInt32BE(1);
      if (this.#carry.length < 5 + length) return;
      const kind = this.#carry[0]!;
      const payload = this.#carry.subarray(5, 5 + length);
      this.#carry = this.#carry.subarray(5 + length);
      this.#message(kind, payload);
    }
  }

  #message(kind: number, payload: Buffer) {
    switch (kind) {
      case 1: {
        const info = JSON.parse(payload.toString());
        if (typeof info.error === "string") this.#settle.reject(Object.assign(new Error(info.error), { code: info.code }));
        else {
          // What it encodes: as it says (H.264 where H.265 was asked and this Mac has no encoder of it; a helper from
          // before H.265 says nothing and makes H.264 of anything but JPEG).
          this.#codec = info.codec === "h265" || info.codec === "h264" || info.codec === "jpeg" ? info.codec : this.#codec === "jpeg" ? "jpeg" : "h264";
          log.info("screens", "a view opened", { capture: this.#capture, width: info.width, height: info.height, encoder: info.encoder });
          if (typeof info.encoder === "string") this.#encoder = info.encoder.slice(0, 200);
          this.#regions = info.regions === true;
          this.#audio = this.#audio && info.audio === true;
          this.#settle.resolve({ width: info.width, height: info.height });
        }
        return;
      }
      case 8: {
        let config: any;
        try { config = JSON.parse(payload.toString()); } catch { config = null; }
        if (config?.codec !== "pcm_s16le" || config.sampleRate !== 48000 || config.channels !== 2) {
          this.#audio = false;
          const resolve = this.#audioWait;
          this.#audioWait = null;
          resolve?.(null);
        }
        return;
      }
      case 9: {
        const resolve = this.#audioWait;
        this.#audioWait = null;
        if (!resolve) return;
        if (payload.length !== 3848) { this.#audio = false; resolve(null); return; }
        resolve({ ts: Number(payload.readBigUInt64BE(0)), data: new Uint8Array(payload.subarray(8)) });
        return;
      }
      case 2:
        this.#config = { codec: this.#codec, width: payload.readUInt32BE(0), height: payload.readUInt32BE(4), ...(this.#codec !== "jpeg" ? { description: new Uint8Array(payload.subarray(8)) } : {}) };
        return;
      case 7: {
        let said: any = null;
        try {
          said = JSON.parse(payload.toString());
        } catch {}
        this.#region = regionOf(said?.region);
        return;
      }
      case 3: {
        const frame: Frame = { key: (payload[0]! & 1) === 1, ts: Number(payload.readBigUInt64BE(1)), data: new Uint8Array(payload.subarray(9)) };
        // Another part of the display than the last frame's: a config again, saying it (the same codec and size).
        if (this.#config === undefined && this.#lastConfig !== undefined && JSON.stringify(this.#region) !== JSON.stringify(this.#sentRegion)) this.#config = this.#lastConfig;
        if (this.#config !== undefined) {
          const { region: _, ...config } = this.#config;
          this.#lastConfig = config;
          this.#sentRegion = this.#region;
          frame.config = this.#region ? { ...config, region: this.#region } : config;
          this.#config = undefined;
        }
        this.#waiting.shift()?.(frame);
        return;
      }
      case 4:
        log.info("screens", "still.fail Helper", { said: payload.toString() });
        return;
      case 6: {
        let said: any = null;
        try {
          said = JSON.parse(payload.toString());
        } catch {}
        const unit = (v: unknown) => typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 1;
        if (said === null || !unit(said.x) || !unit(said.y)) return;
        this.#lastCursor = { x: said.x, y: said.y, shape: typeof said.shape === "string" && /^[a-z-]{1,24}$/.test(said.shape) ? said.shape : "default" };
        this.#cursor?.(this.#lastCursor);
        return;
      }
      case 5: {
        const body = payload.subarray(1);
        const clip: Clip | null = payload[0] === 1 ? { type: "text", text: body.toString("utf8") } : payload[0] === 2 ? { type: "png", data: new Uint8Array(body) } : null;
        if (clip !== null && clipFits(clip)) this.#clipboard?.(clip);
        return;
      }
    }
  }

  #send(kind: number, payload?: Buffer) {
    if (this.#ended) return;
    this.#socket.write(helperMessage(kind, payload));
  }

  next(): Promise<Frame | null> {
    if (this.#ended) return Promise.resolve(null);
    return new Promise((resolve) => {
      this.#waiting.push(resolve);
      this.#send(TO_HELPER.next);
    });
  }

  hasAudio(): boolean { return this.#audio; }

  nextAudio(): Promise<AudioFrame | null> {
    if (this.#ended || !this.#audio) return Promise.resolve(null);
    if (this.#audioWait) return Promise.reject(new Error("audio already pending"));
    return new Promise((resolve) => {
      this.#audioWait = resolve;
      this.#send(TO_HELPER.audio);
    });
  }

  keyframe() {
    this.#send(TO_HELPER.keyframe);
  }

  video(): ScreenVideo {
    // The helpers name a software encoder so ("software", "Microsoft H.264 (software)"); a JPEG is no encoder's.
    if (this.#codec === "jpeg" || this.#encoder === "") return { capture: this.#capture, ...(this.#encoder ? { encoder: this.#encoder } : {}) };
    return { capture: this.#capture, encoder: this.#encoder, hardware: !/software/i.test(this.#encoder) };
  }

  rate(bitsPerSecond: number) {
    if (this.#codec === "jpeg") return;
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(Math.min(0xffff_ffff, Math.max(0, Math.round(bitsPerSecond))));
    this.#send(TO_HELPER.rate, payload);
  }

  bounds(maxWidth: number, maxHeight: number, region?: Region | null) {
    const part = region && this.#regions ? { region } : {};
    this.#send(TO_HELPER.bounds, Buffer.from(JSON.stringify({ maxWidth: Math.round(maxWidth), maxHeight: Math.round(maxHeight), ...part })));
  }

  regions(): boolean {
    return this.#regions;
  }

  async input(event: ScreenInput): Promise<void> {
    for (const op of this.#input.ops(event, wall.now())) this.#send(TO_HELPER.input, Buffer.from(JSON.stringify(op)));
  }

  async setClipboard(clip: Clip, paste: boolean): Promise<void> {
    this.#send(TO_HELPER.clipboard, helperClip(clip, paste ? 1 : 0));
  }

  watchClipboard(heard: (clip: Clip) => void): () => void {
    this.#clipboard = heard;
    this.#send(TO_HELPER.watch, Buffer.from([1]));
    return () => {
      if (this.#clipboard !== heard) return;
      this.#clipboard = null;
      this.#send(TO_HELPER.watch, Buffer.from([0]));
    };
  }

  async reveal(path: string): Promise<void> {
    this.#send(TO_HELPER.reveal, Buffer.from(path, "utf8"));
  }

  watchCursor(heard: (cursor: ScreenCursor) => void): () => void {
    this.#cursor = heard;
    if (this.#lastCursor) heard(this.#lastCursor);
    return () => {
      if (this.#cursor === heard) this.#cursor = null;
    };
  }

  close() {
    if (this.#ended) return;
    this.#ended = true;
    this.#socket.destroy();
    for (const resolve of this.#waiting.splice(0)) resolve(null);
    this.#audioWait?.(null);
    this.#audioWait = null;
    this.#gone();
  }
}
