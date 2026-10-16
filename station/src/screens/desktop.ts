// This machine's display as a screen source (`desktop`, docs/remote-screens.md): on macOS, still.fail Helper
// (helper/app.ts) captures the main display with ScreenCaptureKit, encodes H.264 with VideoToolbox (or a JPEG a
// picture, for a view that takes no H.264) and posts input with CGEvent, a view a connection to it; elsewhere the desktop says it is not supported, and opens nothing.
//
// macOS grants Screen Recording and Accessibility to the helper app. Opening the desktop while one is missing puts the
// helper's window up on this Mac (once an attempt, the system's own prompt not asked: it would fight the window): a
// row per grant, Allow opens System Settings with the app to drag into its list. The helper starts itself again once a
// grant is taken, so the grant is in effect; the station's process is never restarted for it. What is missing, and
// whether the window is up, is told with the screens (`access`).
import type net from "node:net";
import { hostname } from "node:os";
import type { HelperApp } from "../helper/app.ts";
import { wall } from "../ops/fibers.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { ScreenRefused } from "./hub.ts";
import { MacInput } from "./mac-input.ts";
import type { Codec, Frame, FrameConfig, ScreenAccess, ScreenInput, ScreenSource, ScreenView, ViewOptions } from "./source.ts";

/// What the helper's `status` says.
export type HelperStatus = {
  capture: boolean;
  control: boolean;
  responsible?: { pid: number; path: string; name: string };
  display?: { id: number; width: number; height: number };
  /// What its running process may do (a grant is had once it starts again).
  live?: { capture: boolean; control: boolean };
  /// Whether its window asking for the grants is up.
  asking?: boolean;
};

/// A look at the grants is this fresh at most (a list asked for twice at once looks once).
const FRESH_MS = 2_000;

export type DesktopOptions = {
  /// Whether this machine's display can be seen at all (platform.hasDesktopScreen).
  supported: boolean;
  /// still.fail Helper, null when the release has none.
  helper: HelperApp | null;
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
  readonly #o: DesktopOptions;
  #status: HelperStatus | null = null;
  #checked = -Infinity;
  #checking: Promise<void> | null = null;
  readonly #views = new Set<HelperView>();
  /// Its window was put up for grants not all taken yet: up again when the helper comes back still lacking one.
  #wanted = false;

  constructor(options: DesktopOptions) {
    this.#o = options;
  }

  title(): string {
    return this.#o.title?.() ?? hostname().replace(/\.local$/, "");
  }

  size(): { width: number; height: number } {
    return { width: this.#status?.display?.width ?? 0, height: this.#status?.display?.height ?? 0 };
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

  /// The grants and the display as macOS has them now (at most FRESH_MS old, unless `force`); the helper started for it.
  refresh(force = false): Promise<void> {
    const helper = this.#o.helper;
    if (!this.#o.supported || helper === null) return Promise.resolve();
    if (!force && wall.now() - this.#checked < FRESH_MS) return Promise.resolve();
    this.#checking ??= helper
      .request({ op: "status" })
      .then(
        (status: HelperStatus) => {
          this.#checked = wall.now();
          const before = JSON.stringify(this.#status);
          this.#status = status;
          if (JSON.stringify(status) !== before) this.#o.changed();
        },
        (error) => log.warn("screens", "still.fail Helper did not answer", { error: (error as Error).message }),
      )
      .finally(() => (this.#checking = null));
    return this.#checking;
  }

  async open(options: ViewOptions): Promise<ScreenView> {
    const helper = this.#o.helper;
    if (!this.#o.supported) throw new ScreenRefused(501, "station.screen.unsupported", {}, this.access());
    if (helper === null) throw new ScreenRefused(501, "station.screen.noHelper", {}, this.access());
    // H.264 where it is taken (the hardware's, small); else a JPEG a picture (an agent's view, a client without H.264).
    const codec: Codec | undefined = options.codecs.includes("h264") ? "h264" : options.codecs.includes("jpeg") ? "jpeg" : undefined;
    if (codec === undefined) throw new ScreenRefused(415, "station.screen.codec", { codec: "H.264, JPEG" });
    await this.refresh(true);
    const synthetic = this.#o.synthetic !== undefined;
    if (!synthetic && this.#status === null) throw new ScreenRefused(503, "station.screen.failed", { said: "still.fail Helper did not answer" });
    if (!synthetic && this.#status !== null && (!this.#status.capture || !this.#status.control)) await this.#ask(helper);
    if (!synthetic && this.#status?.capture !== true) throw this.#refused();
    // Granted since the helper started: it starts itself again to have it, and is asked once more.
    for (let attempt = 0; ; attempt++) {
      const view = new HelperView(codec, await helper.connect({ op: "screen.view", codec, maxWidth: options.maxWidth, maxHeight: options.maxHeight, ...(this.#status?.display ? { display: this.#status.display.id } : {}), ...(synthetic ? { synthetic: this.#o.synthetic } : {}) }), () => this.#views.delete(view));
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
      await helper.request({ op: "permissions.show", words: windowWords(this.#o.lang?.() ?? stationLang()) });
      await this.refresh(true);
    } catch (error) {
      log.warn("screens", "still.fail Helper's window did not show", { error: (error as Error).message });
    }
  }

  /// The station stopping: every view ends, and the helper (resolved once it is gone).
  close(): Promise<void> {
    for (const view of [...this.#views]) view.close();
    return this.#o.helper?.quit().catch(() => {}) ?? Promise.resolve();
  }
}

type HelperError = Error & { code?: string };

/// The helper's messages: a kind byte, the payload's length (4 bytes), the payload (native/helper's ScreenView.swift).
export function helperMessage(kind: number, payload: Buffer = Buffer.alloc(0)): Buffer {
  const head = Buffer.alloc(5);
  head[0] = kind;
  head.writeUInt32BE(payload.length, 1);
  return Buffer.concat([head, payload]);
}

/// One view: a connection to the helper, asked for each frame.
class HelperView implements ScreenView {
  readonly ready: Promise<{ width: number; height: number }>;
  readonly #socket: net.Socket;
  readonly #input = new MacInput();
  #carry: Buffer = Buffer.alloc(0);
  #waiting: ((frame: Frame | null) => void)[] = [];
  #config: FrameConfig | undefined;
  #ended = false;
  #settle!: { resolve: (v: { width: number; height: number }) => void; reject: (e: Error) => void };
  readonly #gone: () => void;

  readonly #codec: Codec;

  constructor(codec: Codec, socket: net.Socket, gone: () => void) {
    this.#codec = codec;
    this.#socket = socket;
    this.#gone = gone;
    this.ready = new Promise((resolve, reject) => (this.#settle = { resolve, reject }));
    socket.on("data", (chunk: Buffer) => this.#heard(chunk));
    socket.on("error", () => this.close());
    socket.on("close", () => {
      this.#settle.reject(new Error("still.fail Helper ended the view"));
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
          log.info("screens", "a view of the desktop opened", { width: info.width, height: info.height, encoder: info.encoder });
          this.#settle.resolve({ width: info.width, height: info.height });
        }
        return;
      }
      case 2:
        this.#config = { codec: this.#codec, width: payload.readUInt32BE(0), height: payload.readUInt32BE(4), ...(this.#codec === "h264" ? { description: new Uint8Array(payload.subarray(8)) } : {}) };
        return;
      case 3: {
        const frame: Frame = { key: (payload[0]! & 1) === 1, ts: Number(payload.readBigUInt64BE(1)), data: new Uint8Array(payload.subarray(9)) };
        if (this.#config !== undefined) {
          frame.config = this.#config;
          this.#config = undefined;
        }
        this.#waiting.shift()?.(frame);
        return;
      }
      case 4:
        log.info("screens", "still.fail Helper", { said: payload.toString() });
        return;
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
      this.#send(1);
    });
  }

  keyframe() {
    this.#send(2);
  }

  async input(event: ScreenInput): Promise<void> {
    for (const op of this.#input.ops(event, wall.now())) this.#send(3, Buffer.from(JSON.stringify(op)));
  }

  close() {
    if (this.#ended) return;
    this.#ended = true;
    this.#socket.destroy();
    for (const resolve of this.#waiting.splice(0)) resolve(null);
    this.#gone();
  }
}
