// What a person can see and drive on this station: the machine's display, a tab of the
// station's browser. A source opens views; a view is pull-driven (`next` gives a frame only when asked), so a slow
// link lowers the frame rate instead of queueing frames. The mesh layer carries views (`/admin/api/screens`);
// sources know nothing of it.

import type { Panel } from "./sim-mask.ts";
import type { ChromeSource } from "./sim-chrome.ts";
import type { SimDebug } from "./sim-debug.ts";

export type Codec = "h265" | "h264" | "jpeg";

/// A frame's format: sent before the first frame and whenever it changes; the next frame is then a key frame.
/// `description`: H.264's avcC, H.265's hvcC (what WebCodecs and MediaCodec take as the decoder's configuration).
/// `region`: the part of the screen the frames after it show (a view zoomed in, "Regions");
/// none: the whole screen.
export type FrameConfig = { codec: Codec; width: number; height: number; description?: Uint8Array; region?: Region };

/// A part of the screen, 0..1 of its width and height: its left, its top, its width, its height.
/// A 20 ms packet of system output: 3840 bytes of interleaved stereo PCM16, or one Opus packet (RFC 6716) of those 960
/// frames where the view asked `opus` and the source encodes it (`codec` says which).
export type AudioFrame = { ts: number; data: Uint8Array; codec: AudioCodec };
export type AudioCodec = "pcm_s16le" | "opus";
/// The longest Opus packet (RFC 6716 3.2.1).
export const OPUS_MAX = 1275;

export type Region = { x: number; y: number; w: number; h: number };

/// One encoded frame: H.264 or H.265 as length-prefixed NAL units (AVCC, HVCC), or a whole JPEG. `ts`: microseconds, rising.
export type Frame = { config?: FrameConfig; key: boolean; ts: number; data: Uint8Array };

/// A person's input; coordinates are 0..1 of the screen (the whole of it, whatever part the frames show). `mods`: bit 0 alt, 1 ctrl, 2 meta, 3 shift (CDP's order).
export type ScreenInput =
  | { t: "pointer"; kind: "down" | "up" | "move"; x: number; y: number; buttons: number }
  | { t: "wheel"; x: number; y: number; dx: number; dy: number }
  | { t: "key"; kind: "down" | "up"; key: string; code: string; mods: number }
  | { t: "text"; text: string }
  /// A foldable simulator's hinge (`ScreenSource.poses`).
  | { t: "pose"; name: "closed" | "book" | "open" }
  // What Device Hub does of a device besides its keys and a finger
  | { t: "device"; name: "volume_up" | "volume_down" | "memory_warning" | "rotate" }
  /// A button of a simulator's device, held as long as it is here (`ScreenSource.chrome`: its HID usage).
  | { t: "button"; page: number; usage: number; down: boolean };

/// `peek`: a preview (a link's card in a chat): it brings nothing forward, wakes nothing and is not among those on it.
/// `bitrate`: what to encode at first (bits a second; none: the source's own), until `ScreenView.rate` says otherwise.
/// `fps`: the most frames a second the view asked (its 帧率; none: 自动, as many as the source makes): a source that
/// captures and encodes at a rate (the desktop's helpers) does so at it; the view's pace lets no more go whatever the
/// source.
/// `fit`: the viewer's own screen (a phone), in its CSS pixels and their scale: a source that lays itself out (a tab of
/// the browser) does so for it while the view is open, as that phone's browser would; others take no notice.
/// `opus`: the viewer decodes Opus too (with `audio`): a source that encodes it sends the sound so (about 64 kbit/s,
/// where PCM is 1.5 Mbit/s), the others PCM.
/// `gamut: "p3"`: the viewer shows a video tagged Display P3 as such: a source that has wider colours (this Mac's
/// desktop) may send them; the others' stay sRGB, as they are without it.
export type ViewOptions = { maxWidth: number; maxHeight: number; codecs: Codec[]; peek?: boolean; bitrate?: number; fps?: number; fit?: ViewFit; audio?: boolean; opus?: boolean; gamut?: "p3" };
export type ViewFit = { width: number; height: number; scale: number };

/// The codec a source that makes `own` (best first) sends a view: the first of them the view takes; for a preview
/// (`peek`), JPEG where both have it, so a card stays a picture now and then while a source with nothing but a video
/// (an Android device's) still gets a card that takes one. None: nothing in common.
export function codecFor(options: Pick<ViewOptions, "codecs" | "peek">, own: readonly Codec[]): Codec | undefined {
  if (options.peek === true && own.includes("jpeg") && options.codecs.includes("jpeg")) return "jpeg";
  return own.find((c) => options.codecs.includes(c));
}

/// The least part of the screen a look shows, of its width or height (a 50th: zoomed in 50 times).
export const LOOK_LEAST = 0.02;
/// A part this much of the screen or more, both ways, is the whole of it.
const LOOK_WHOLE = 0.98;

/// A part of the screen as a look or a source says it, checked: within the screen, at least LOOK_LEAST each way; null
/// when it is not one, or is (about) the whole screen.
export function regionOf(v: any): Region | null {
  if (v === null || typeof v !== "object" || ![v.x, v.y, v.w, v.h].every((n) => typeof n === "number" && Number.isFinite(n))) return null;
  const w = Math.min(1, Math.max(LOOK_LEAST, v.w)), h = Math.min(1, Math.max(LOOK_LEAST, v.h));
  if (w >= LOOK_WHOLE && h >= LOOK_WHOLE) return null;
  const x = Math.min(1 - w, Math.max(0, v.x)), y = Math.min(1 - h, Math.max(0, v.y));
  const r4 = (n: number) => Math.round(n * 10_000) / 10_000;
  return { x: r4(x), y: r4(y), w: r4(w), h: r4(h) };
}

/// What a screen's clipboard holds, as a view carries it: text, or a PNG picture.
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
  /// Negotiated system output: 48 kHz stereo, PCM16 or Opus, one bounded packet, null when unavailable.
  nextAudio?(): Promise<AudioFrame | null>;
  /// Starts the next frame as a key frame (a client's decoder lost its state).
  keyframe(): void;
  input(event: ScreenInput): Promise<void>;
  /// Encodes from the next frame at about this many bits a second (the link carries no more,
  /// "Pace"); one without it encodes at its own.
  rate?(bitsPerSecond: number): void;
  /// Its pictures from now on fitted into these bounds (a config first, "Pace"), of `region` of
  /// the screen where it frames a part (`regions`), else of the whole; one without it keeps those it opened with.
  bounds?(maxWidth: number, maxHeight: number, region?: Region | null): void;
  /// It frames a part of the screen when `bounds` says one (its configs then say which: `FrameConfig.region`).
  regions?(): boolean;
  /// How its pictures are made (once it opened); none: not said.
  video?(): ScreenVideo;
  /// Stops capturing; a pending `next` resolves null.
  close(): void;
  /// The source's clipboard set (of a type its `clipboard()` names), then, with `paste`, pasted where its focus is (the
  /// machine's paste key, a tab's insertion). Only a view a person drives is asked.
  setClipboard?(clip: Clip, paste: boolean): Promise<void>;
  /// Hears the source's clipboard each time it changes (a copy made on it; not what it holds as this starts), until
  /// the returned function. Only a view a person drives is asked, for as long as it is open.
  watchClipboard?(heard: (clip: Clip) => void): () => void;
  /// Hears where the pointer is on the source (0..1 of the screen) and its shape (a CSS cursor's name) as it moves or
  /// changes, until the returned function: a source whose pictures leave the pointer out (a video of the desktop) says
  /// it so; one without it draws it in its pictures, or has none.
  watchCursor?(heard: (cursor: ScreenCursor) => void): () => void;
  /// Hears how far a device's picture is turned clockwise, in quarter turns, as it changes and at once, until the returned
  /// function: a simulator's, whose case is drawn turned with it.
  watchTurn?(heard: (turn: number) => void): () => void;
  /// Hears a desktop's windows and the one shown alone as they change and at once, until the returned function: a
  /// source that shows one window alone (still.fail Helper's), where `window` picks one.
  watchWindows?(heard: (windows: ScreenWindows) => void): () => void;
  /// One window shown alone from now on (one of those `watchWindows` said), or the whole display again (null).
  window?(id: number | null): void;
  /// Shows a file in the machine's file manager (a file dropped into the view, put on the machine): the source's
  /// `reveal` says it can.
  reveal?(path: string): Promise<void>;
  /// Hears the login field the source's focus is in (a page's username or password field: a tab of the browser), with
  /// the site it is on as the station knows it, and null as the focus leaves one, until the returned function. Only a
  /// view a person drives is asked: their app offers to fill it from their own password manager.
  watchLogin?(heard: (login: LoginField | null) => void): () => void;
  /// Fills the login form the focus is in with what the person's app gave, if the page is still on `host`.
  fill?(f: LoginFill): Promise<void>;
  /// Hears a page's ask to sign in with a passkey (WebAuthn's navigator.credentials.get, a tab of the browser), checked
  /// against the site it is on as the station knows it, and null as it goes (answered, given up by the page, or the
  /// page gone), until the returned function. Only a view a person drives is asked: their app signs it with a passkey
  /// of their own device.
  watchPasskey?(heard: (ask: PasskeyAsk | null) => void): () => void;
  /// Answers the ask `a.id` with what the person's app signed (or that it signed nothing), if the page is still where
  /// it asked.
  passkey?(a: PasskeyAnswer): Promise<void>;
  /// Hears a child screen (`browser:<id>`) this tab opened while driven (a link to a new window or an OAuth popup).
  watchChild?(heard: (screenId: string) => void): () => void;
}

/// A login field in focus: the site's host (as the browser has its address, not as the page says it), and which field.
export type LoginField = { host: string; field: "username" | "password" };
/// A login form filled from a person's app: for `host`, its account and password (either may be absent).
export type LoginFill = { host: string; username?: string; password?: string };
/// A page's ask to sign in with a passkey: `id` its own; the site's host and the relying party it names (the host, or
/// a domain the host is under); the client data the station made of it (its challenge, the tab's origin as the
/// browser has its address), which the device signs as it is; the credentials the site takes (base64url ids, none:
/// any of the device's for it); whether the person is to be verified (`required`, `preferred`, `discouraged`).
export type PasskeyAsk = { id: string; host: string; rpId: string; clientData: string; allow: string[]; userVerification: string };
/// What a person's app answers an ask with (base64url): the credential signed with, its authenticator data, the
/// signature and the user handle, and the client data signed where the device made its own of the station's (macOS:
/// the same challenge, type and origin, written its way); or `error` (the person said no, or the device has none).
export type PasskeyAnswer =
  | { id: string; credential: string; authenticatorData: string; signature: string; userHandle?: string; clientData?: string }
  | { id: string; error: string };

export type ScreenKind = "desktop" | "browser" | "simulator";

/// How a view's pictures are made, as its statistics show it: what captures them (ScreenCaptureKit,
/// Windows.Graphics.Capture, Chrome's screencast), the encoder's name as it says it, and whether it is the hardware's
/// (none: a JPEG a picture, nothing to say).
export type ScreenVideo = { capture: string; encoder?: string; hardware?: boolean };

/// Where a screen's pointer is, 0..1 of the screen, and its shape as CSS names it.
export type ScreenCursor = { x: number; y: number; shape: string };

/// The key an app makes for a person's tab of the station's browser it opens (`browser:<key>`), as the browser's
/// user-tabs.ts `#freshKey` makes them.
export const USER_TAB_ID = /^u_[0-9a-f]{12}$/;

/// An app's window on a desktop, as a view may show it alone (`ScreenView.window`): its id (the system's), its app's
/// name and its title.
export type ScreenWindow = { id: number; app: string; title: string };
/// A desktop's windows as its view says them, and the one it shows alone (null: the whole display).
export type ScreenWindows = { windows: ScreenWindow[]; window: number | null };
/// The most windows said (the rest left out), and the longest app's name or title (cut there).
export const WINDOWS_MOST = 60;
export const WINDOW_WORDS_MOST = 200;

/// A desktop's windows as a helper said them, checked: at most WINDOWS_MOST, each with a whole id, words cut.
export function windowsOf(v: unknown): ScreenWindow[] {
  if (!Array.isArray(v)) return [];
  const out: ScreenWindow[] = [];
  for (const w of v) {
    if (out.length >= WINDOWS_MOST) break;
    if (w === null || typeof w !== "object") continue;
    const { id, app, title } = w as Record<string, unknown>;
    if (typeof id !== "number" || !Number.isInteger(id) || id <= 0) continue;
    out.push({ id, app: typeof app === "string" ? app.slice(0, WINDOW_WORDS_MOST) : "", title: typeof title === "string" ? title.slice(0, WINDOW_WORDS_MOST) : "" });
  }
  return out;
}

/// A display's scale as its system has it (Windows' Settings › Display › Scale): now, the one recommended, and the
/// steps it takes, in percent.
export type ScreenScale = { percent: number; recommended: number; steps: number[] };

/// A display's resolution as its system has it (Windows' Settings › Display › Display resolution): now, and the modes
/// it takes (landscape, the largest first), in pixels.
export type ScreenResolution = { width: number; height: number; modes: { width: number; height: number }[] };

/// Whether a source can be seen and driven now, for one that may not be (the desktop: macOS's grants, a machine it is
/// not supported on). `app` and `path`: what a person turns on in System Settings for it; `asking`: a window on the
/// machine asks for it now.
export type ScreenAccess = { capture: boolean; control: boolean; unsupported?: "platform" | "helper"; reason?: "linuxNoDisplay" | "linuxWayland" | "linuxTools" | "linuxToolsPreparing" | "linuxToolsFailed" | "linuxUnavailable" | "linuxPortalConsent" | "linuxPortalUnavailable" | "linuxDesktopStarting" | "linuxX11FallbackUnavailable"; app?: string; path?: string; asking?: boolean };

export interface ScreenSource {
  /// Stable while the source lasts: `desktop`, `browser:<targetId>`, `simulator:<udid>`, `android:<id>`.
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
  /// A chat's Farview tab (browser/farview.ts): an app that draws Farview's protocol itself reads it over a stream of
  /// its own (`{"farview": {"screen": id}}`, the host's bytes as they are) instead of a view's pictures.
  readonly farview?: boolean;
  /// The session that opened it (a tab of the browser an agent opened), when known.
  openedBy?(): string | undefined;
  /// A browser tab a person opened on this station (kept in Chrome's persistent profile, hidden from agents).
  readonly userTab?: boolean;
  /// Whether this user tab is hibernated (its Chrome page closed to free memory until opened again).
  sleeping?(): boolean;
  /// The site (`hostname[:port]`) of a browser tab, without path, query or hash.
  site?(): string | undefined;
  /// A browser tab's whole address, as its address bar shows it (`about:blank` on a new tab's page).
  address?(): string;
  /// Navigates a browser tab to `url` (an address, or words searched for, as a browser's address bar takes them).
  openUrl?(url: string): Promise<void>;
  /// Reloads a browser tab.
  reload?(): Promise<void>;
  /// Goes back, or forward, a page in a browser tab's history (nothing where it has none that way).
  back?(): Promise<void>;
  forward?(): Promise<void>;
  /// Hibernates a user tab now, closing its underlying Chrome page while keeping its saved address and title.
  sleep?(): Promise<void>;
  /// Closes it for good (a tab of the browser, a simulator shut down); none: it is not closed from a person's app (the
  /// desktop).
  discard?(): Promise<void>;
  /// Since when it has been up (ms; a simulator's boot): what costs the machine while nobody uses it, told so a person
  /// sees one left running (the core's `longJobs`); none: not told.
  since?(): number | undefined;
  /// Its display's scale (null when it is not had now); none: a source whose scale is not changed (macOS, a tab).
  scale?(): Promise<ScreenScale | null>;
  /// Sets its display's scale to one of its steps, and says it as `scale` does; until its last view ends, after which
  /// it is put back as it was before the first change.
  setScale?(percent: number): Promise<ScreenScale>;
  /// Its display's resolution (null when it is not had now); none: a source whose resolution is not changed.
  resolution?(): Promise<ScreenResolution | null>;
  /// Sets its display's resolution to one of its modes, and says it as `resolution` does; until its last view ends,
  /// after which it is put back as it was before the first change.
  setResolution?(width: number, height: number): Promise<ScreenResolution>;
  /// Its apps' accessibility trees (screens/ui.ts): one agent-desktop command run with `args` where its apps are (the
  /// desktop's: still.fail Helper on macOS, the station on Windows), its JSON envelope; none: no trees.
  ui?(args: string[]): Promise<unknown>;
  /// Its apps' logs and their restart (screens/sim-debug.ts): a simulator's; none: nothing to debug on it.
  readonly debug?: SimDebug;
  /// It folds (an iPhone Duo): its input takes `pose`.
  readonly poses?: boolean;
  /// A simulator's case and buttons as Xcode has them, each panel's (sim-chrome.ts); none: as `panels` says.
  readonly chrome?: readonly ChromeSource[];
  /// A simulator's panels and their corners (sim-mask.ts).
  readonly panels?: readonly Panel[];
}

/// The station's browser as `ScreenHub` reaches it without importing `browser/`.
export interface ScreenBrowser {
  available(): boolean;
  openUserTab(url: string, id?: string): Promise<string>;
}

/// The station's sources: parts add theirs (the desktop at start, the browser per tab) and take them away.
export interface Screens {
  add(source: ScreenSource): () => void;
  list(): ScreenSource[];
  get(id: string): ScreenSource | undefined;
  /// Called with the list each time a source comes or goes (or its title changes).
  watch(listener: (sources: ScreenSource[]) => void): () => void;
  /// Registers the station's browser so members can open persistent user pages (`POST /screens/browser`).
  setBrowser?(browser: ScreenBrowser | null): void;
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
