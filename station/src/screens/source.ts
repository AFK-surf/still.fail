// What a person can see and drive on this station (docs/remote-screens.md): the machine's display, a tab of the
// station's browser. A source opens views; a view is pull-driven (`next` captures and encodes only when asked), so a
// slow link lowers the frame rate instead of queueing frames. The mesh layer carries views (`/admin/api/screens`);
// sources know nothing of it.

export type Codec = "h264" | "jpeg";

/// A frame's format: sent before the first frame and whenever it changes; the next frame is then a key frame.
/// `description`: H.264's avcC (what WebCodecs and MediaCodec take as the decoder's configuration).
export type FrameConfig = { codec: Codec; width: number; height: number; description?: Uint8Array };

/// One encoded frame: H.264 in AVCC (length-prefixed NAL units), or a whole JPEG. `ts`: microseconds, rising.
export type Frame = { config?: FrameConfig; key: boolean; ts: number; data: Uint8Array };

/// A person's input; coordinates are 0..1 of the frame. `mods`: bit 0 alt, 1 ctrl, 2 meta, 3 shift (CDP's order).
export type ScreenInput =
  | { t: "pointer"; kind: "down" | "up" | "move"; x: number; y: number; buttons: number }
  | { t: "wheel"; x: number; y: number; dx: number; dy: number }
  | { t: "key"; kind: "down" | "up"; key: string; code: string; mods: number }
  | { t: "text"; text: string };

export type ViewOptions = { maxWidth: number; maxHeight: number; codecs: Codec[] };

export interface ScreenView {
  /// The next frame once there is a new one, or null when the view ended (the source went away).
  next(): Promise<Frame | null>;
  /// Starts the next frame as a key frame (a client's decoder lost its state).
  keyframe(): void;
  input(event: ScreenInput): Promise<void>;
  /// Stops capturing; a pending `next` resolves null.
  close(): void;
}

export type ScreenKind = "desktop" | "browser";

export interface ScreenSource {
  /// Stable while the source lasts: `desktop`, `browser:<targetId>`.
  readonly id: string;
  readonly kind: ScreenKind;
  title(): string;
  /// Its size now, in the source's pixels.
  size(): { width: number; height: number };
  /// Fails (with a message for the person) when it cannot be seen now: no permission to capture, no display.
  open(options: ViewOptions): Promise<ScreenView>;
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
