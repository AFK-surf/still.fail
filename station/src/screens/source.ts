// What a person can see and drive on this station (docs/remote-screens.md): the machine's display, a tab of the
// station's browser. A source opens views; a view is pull-driven (`next` captures and encodes only when asked), so a
// slow link lowers the frame rate instead of queueing frames. The mesh layer carries views (`/admin/api/screens`);
// sources know nothing of it.

export type Codec = "h265" | "h264" | "jpeg";

/// A frame's format: sent before the first frame and whenever it changes; the next frame is then a key frame.
/// `description`: H.264's avcC, H.265's hvcC (what WebCodecs and MediaCodec take as the decoder's configuration).
export type FrameConfig = { codec: Codec; width: number; height: number; description?: Uint8Array };

/// One encoded frame: H.264 or H.265 as length-prefixed NAL units (AVCC, HVCC), or a whole JPEG. `ts`: microseconds, rising.
export type Frame = { config?: FrameConfig; key: boolean; ts: number; data: Uint8Array };

/// A person's input; coordinates are 0..1 of the frame. `mods`: bit 0 alt, 1 ctrl, 2 meta, 3 shift (CDP's order).
export type ScreenInput =
  | { t: "pointer"; kind: "down" | "up" | "move"; x: number; y: number; buttons: number }
  | { t: "wheel"; x: number; y: number; dx: number; dy: number }
  | { t: "key"; kind: "down" | "up"; key: string; code: string; mods: number }
  | { t: "text"; text: string };

/// `peek`: a preview (a link's card in a chat): it brings nothing forward, wakes nothing and is not among those on it.
/// `bitrate`: what to encode at first (bits a second; none: the source's own), until `ScreenView.rate` says otherwise.
export type ViewOptions = { maxWidth: number; maxHeight: number; codecs: Codec[]; peek?: boolean; bitrate?: number };

/// What a screen's clipboard holds, as a view carries it (docs/remote-screens.md `clipboard`): text, or a PNG picture.
export type ClipType = "text" | "png";
export type Clip = { type: "text"; text: string } | { type: "png"; data: Uint8Array };
/// The most a clipboard carries each way: text (its UTF-8 bytes), a picture.
export const CLIP_TEXT_MAX = 1024 * 1024;
export const CLIP_PNG_MAX = 8 * 1024 * 1024;

/// Whether a clip is within its bounds.
export function clipFits(clip: Clip): boolean {
  return clip.type === "text" ? clip.text !== "" && Buffer.byteLength(clip.text, "utf8") <= CLIP_TEXT_MAX : clip.data.length > 0 && clip.data.length <= CLIP_PNG_MAX;
}

export interface ScreenView {
  /// The next frame once there is a new one, or null when the view ended (the source went away).
  next(): Promise<Frame | null>;
  /// Starts the next frame as a key frame (a client's decoder lost its state).
  keyframe(): void;
  input(event: ScreenInput): Promise<void>;
  /// Encodes from the next frame at about this many bits a second (the link carries no more: docs/remote-screens.md,
  /// "Pace"); one without it encodes at its own.
  rate?(bitsPerSecond: number): void;
  /// Its pictures from now on fitted into these bounds (a config first: docs/remote-screens.md, "Pace"); one without it
  /// keeps those it opened with.
  bounds?(maxWidth: number, maxHeight: number): void;
  /// Stops capturing; a pending `next` resolves null.
  close(): void;
  /// The source's clipboard set (of a type its `clipboard()` names), then, with `paste`, pasted where its focus is (the
  /// machine's paste key, a tab's insertion). Only a view a person drives is asked.
  setClipboard?(clip: Clip, paste: boolean): Promise<void>;
  /// Hears the source's clipboard each time it changes (a copy made on it; not what it holds as this starts), until
  /// the returned function. Only a view a person drives is asked, for as long as it is open.
  watchClipboard?(heard: (clip: Clip) => void): () => void;
  /// Hears where the pointer is on the source (0..1 of the frame) and its shape (a CSS cursor's name) as it moves or
  /// changes, until the returned function: a source whose pictures leave the pointer out (a video of the desktop) says
  /// it so; one without it draws it in its pictures, or has none.
  watchCursor?(heard: (cursor: ScreenCursor) => void): () => void;
  /// Shows a file in the machine's file manager (a file dropped into the view, put on the machine): the source's
  /// `reveal` says it can.
  reveal?(path: string): Promise<void>;
}

export type ScreenKind = "desktop" | "browser";

/// Where a screen's pointer is, 0..1 of the frame, and its shape as CSS names it.
export type ScreenCursor = { x: number; y: number; shape: string };

/// A display's scale as its system has it (Windows' Settings › Display › Scale): now, the one recommended, and the
/// steps it takes, in percent.
export type ScreenScale = { percent: number; recommended: number; steps: number[] };

/// Whether a source can be seen and driven now, for one that may not be (the desktop: macOS's grants, a machine it is
/// not supported on). `app` and `path`: what a person turns on in System Settings for it; `asking`: a window on the
/// machine asks for it now.
export type ScreenAccess = { capture: boolean; control: boolean; unsupported?: "platform" | "helper"; app?: string; path?: string; asking?: boolean };

export interface ScreenSource {
  /// Stable while the source lasts: `desktop`, `browser:<targetId>`.
  readonly id: string;
  readonly kind: ScreenKind;
  title(): string;
  /// Its size now, in the source's pixels.
  size(): { width: number; height: number };
  /// Fails (with a message for the person) when it cannot be seen now: no permission to capture, no display.
  open(options: ViewOptions): Promise<ScreenView>;
  /// Whether it can be seen and driven now; none: always.
  access?(): ScreenAccess;
  /// The clipboard types its views carry both ways while a person drives (`setClipboard`, `watchClipboard`); none: no
  /// clipboard.
  clipboard?(): ClipType[];
  /// Its views can show a file in the machine's file manager (`reveal`).
  readonly reveal?: boolean;
  /// It can be previewed (`ViewOptions.peek`): a tab of the browser, not the desktop (whose view wakes its display).
  readonly peek?: boolean;
  /// The session that opened it (a tab of the browser an agent opened), when known.
  openedBy?(): string | undefined;
  /// Closes it for good (a tab of the browser); none: it is not closed from a person's app (the desktop).
  discard?(): Promise<void>;
  /// Its display's scale (null when it is not had now); none: a source whose scale is not changed (macOS, a tab).
  scale?(): Promise<ScreenScale | null>;
  /// Sets its display's scale to one of its steps, and says it as `scale` does; until its last view ends, after which
  /// it is put back as it was before the first change.
  setScale?(percent: number): Promise<ScreenScale>;
}

/// The station's sources: parts add theirs (the desktop at start, the browser per tab) and take them away.
export interface Screens {
  add(source: ScreenSource): () => void;
  list(): ScreenSource[];
  get(id: string): ScreenSource | undefined;
  /// Called with the list each time a source comes or goes (or its title changes).
  watch(listener: (sources: ScreenSource[]) => void): () => void;
}

export function makeScreens(): Screens & { changed(): void } {
  const sources = new Map<string, ScreenSource>();
  const listeners = new Set<(sources: ScreenSource[]) => void>();
  const changed = () => {
    const all = [...sources.values()];
    for (const listener of listeners) listener(all);
  };
  return {
    add(source) {
      sources.set(source.id, source);
      changed();
      return () => {
        if (sources.get(source.id) === source) {
          sources.delete(source.id);
          changed();
        }
      };
    },
    list: () => [...sources.values()],
    get: (id) => sources.get(id),
    watch(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    changed,
  };
}
