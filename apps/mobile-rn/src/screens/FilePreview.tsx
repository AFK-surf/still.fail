// A file sent in a chat, opened over the whole screen (web/src/FilePreview.tsx): images to zoom, pan, step through
// and mark; video and audio to play; PDFs drawn page by page (the system's PDF renderer); Markdown rendered; CSV as a
// table; HTML in a WebView of its own; code and text highlighted. Anything else says it cannot be shown and offers the
// download. One bar floats at the top with its name and tools, frosted, and fades when left alone; a tap brings it back.
import { requireOptionalNativeModule } from "expo";
import Constants from "expo-constants";
import { Canvas, createPicture, Picture as SkiaPicture } from "@shopify/react-native-skia";
import type { File } from "expo-file-system";
import * as NavigationBar from "expo-navigation-bar";
import { setStatusBarStyle } from "expo-status-bar";
import { useEffect, useMemo, useReducer, useRef, useState, type ComponentType, type ReactNode } from "react";
import { BackHandler, Dimensions, FlatList, Image, Keyboard, PixelRatio, Platform, Pressable, ScrollView, StyleSheet, Text, View, type LayoutChangeEvent, type StyleProp, type ViewStyle } from "react-native";
import Animated, { makeMutable, runOnJS, useAnimatedStyle, useDerivedValue, useSharedValue, withSpring, withTiming, type SharedValue } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { WebView } from "react-native-webview";
import type { Attachment, ImageNear } from "../../../../web/src/core/shapes.ts";
import { useTopic } from "../../../../web/src/core/react.ts";
import { app, type ChatOf } from "../AppState";
import { t } from "../i18n";
import { installApk, mayInstall } from "../Install";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { Frost } from "../ui/Glass";
import { Ease } from "../ui/Motion";
import { SMOOTH_SCALE, Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { CODE_FONT, lerpColor, useC, withAlpha } from "../ui/Theme";
import { chatInk } from "../ui/ChatInk";
import { fileSize } from "../ui/Controls";
import { highlight } from "../ui/Highlight";
import { Markdown } from "../ui/Markdown";
import { Seg } from "../ui/Parts";
import { Progress, WaitPill, breathing, rememberBreath } from "../ui/Waiting";
import { MAX_SCALE, Zoomable, ZoomState, type Swipe } from "../ui/Zoom";
import { AnnotatedText } from "../ui/Annotated";
import { ImageMarks, MarksActions, MarksFoot, PictureButton, drawMarks } from "./ImageMarks";
import type { Picked } from "./Composer";
import { DraftOffers, MarkOffer, type OfferQuote } from "./Preview";
import { AudioViewer, VideoViewer } from "./VideoViewer";
import { BIG_FILE, FileData, PreviewKind, Shown, chatLongest, download, kindOf, type Got, type Picture } from "./ChatFiles";
import { Watched, useWatched } from "../ui/Watched";

/** The bars fade after this long left alone; after a tap that brought them back, a while longer. */
const REST_MS = 2000;
const TAP_REST_MS = 4000;
/** Above this a file shows as plain text, unhighlighted; above the next, only its start. */
const HIGHLIGHT_LIMIT = 256 * 1024;
const SHOW_LIMIT = 2 * 1024 * 1024;
const TABLE_ROWS = 2000;

/** Dark whatever the theme, as a viewer of pictures: its text, what is quieter, its canvas. */
const DarkText = "#F4F4F5";
const DarkMuted = withAlpha("#FFFFFF", 0.6);
const DarkCanvas = "#111113";

/** The stage's units are the layout's (dp): what the Kotlin's ZoomState takes as the screen's density is 1 here. */
const DENSITY = 1;

type FileLoad =
  | { t: "Loading"; got: Got | null }
  | { t: "Failed"; message: string }
  | { t: "Ready"; bytes: Uint8Array }
  /** A big file (over BIG_FILE), on the disk: never read into memory. */
  | { t: "OnDisk"; file: File };

/** A box in the window or on the stage (Compose's Rect). */
export interface Rect { left: number; top: number; width: number; height: number }

/**
 * A zoom's box for the picture (ZoomState.rect, Compose's Rect: its sides, and its size), as the stage places it.
 */
export function rectOf(z: { rect(): { left: number; top: number; width?: number; height?: number; right?: number; bottom?: number } | null } | null | undefined): Rect | null {
  const r = z?.rect() ?? null;
  if (!r) return null;
  return { left: r.left, top: r.top, width: r.width ?? (r.right ?? r.left) - r.left, height: r.height ?? (r.bottom ?? r.top) - r.top };
}

/** Draws again whenever `x` says it changed (Compose reading a state holder's snapshot state). */
function useChanges(x: { subscribe(l: () => void): () => void } | null | undefined) {
  const [, bump] = useReducer((n: number) => n + 1, 0);
  useEffect(() => (x ? x.subscribe(bump) : undefined), [x]);
}

/** A value remembered while `key` stays the same (Compose's remember(key) { mutableStateOf(init) }). */
function useKeyed<T>(key: unknown, init: () => T): [T, (v: T | ((was: T) => T)) => void] {
  const [held, setHeld] = useState<{ key: unknown; value: T }>(() => ({ key, value: init() }));
  const current = Object.is(held.key, key) ? held : { key, value: init() };
  if (current !== held) setHeld(current);
  const set = (v: T | ((was: T) => T)) => setHeld((h) => {
    const base = Object.is(h.key, key) ? h.value : init();
    return { key, value: typeof v === "function" ? (v as (was: T) => T)(base) : v };
  });
  return [current.value, set];
}

/** The system's back while `enabled` (Compose's BackHandler): true when it was taken. */
function useBack(enabled: boolean, onBack: () => void) {
  const latest = useRef(onBack);
  latest.current = onBack;
  useEffect(() => {
    if (!enabled) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { latest.current(); return true; });
    return () => sub.remove();
  }, [enabled]);
}

/** How far the keyboard has come up (WindowInsets.ime's bottom). */
function useIme(): number {
  const [h, setH] = useState(0);
  useEffect(() => {
    const show = Keyboard.addListener("keyboardDidShow", (e) => setH(e.endCoordinates.height));
    const hide = Keyboard.addListener("keyboardDidHide", () => setH(0));
    return () => { show.remove(); hide.remove(); };
  }, []);
  return h;
}

/**
 * `file` (kept by the session `sessionKey`: the Kotlin's `key`, which React keeps for itself) over the whole screen;
 * `gallery`: what an image steps through to the one before or after. Back (or ×) closes it.
 */
export function FilePreview({ station, sessionKey, file, gallery = null, canDraft = true, onClose }: {
  station: string; sessionKey: string; file: Attachment; gallery?: Gallery | null; canDraft?: boolean; onClose: () => void;
}) {
  // Drawn by ViewerHost, a layer of the app's own window over the pages (not a modal of its own): it can grow out of
  // the thumbnail in the chat and shrink back into it. Here it only says it is open, while it is.
  const open = useMemo(() => new ViewerOpen(station, new Shown(sessionKey, file), gallery, canDraft), []);
  open.onClose = onClose;
  useEffect(() => {
    FileViewers.shown.value = open;
    return () => { if (FileViewers.shown.value === open) { FileViewers.shown.value = null; FileViewers.hidden.value = null; } };
  }, [open]);
  return null;
}

// ── the viewer's layer, and its flight from and to the chat ────────────

/** The viewer grows from the thumbnail this long, and shrinks back into it; both on web mobile's --m-ease (.2, .8, .2, 1). */
const OPEN_MS = 320;
const CLOSE_MS = 280;
/** Opened or closed with no thumbnail on the screen: the web's fade (FilePreview.css.ts fp: 140ms ease-out). */
const FADE_MS = 140;

/**
 * What an image opened in the viewer steps through: the images of the chat it is opened from (as its `chat` topic names
 * it), of which the core tells those beside the one shown (`imageNear`), not the chat's every image; or a folder's.
 */
export type Gallery = { kind: "Chat"; of: ChatOf } | { kind: "Folder"; images: () => Shown[] };

let opened = 0;
/** `canDraft`: marks on it can go into its chat's draft (not a picture that is in a draft already). */
export class ViewerOpen {
  readonly n = ++opened;
  onClose: () => void = () => undefined;
  constructor(readonly station: string, readonly opened: Shown, readonly gallery: Gallery | null, readonly canDraft = true) {}
}

/** Where a thumbnail in the chat is (in the window), what it shows, and whether any of it is on the screen. */
export interface Thumb {
  /** Its box in the window as it is now (measured when asked: a list scrolled has moved it), and whether any of it shows. */
  measure(): Promise<{ bounds: Rect; visible: boolean } | null>;
  radius: number; letterbox: boolean; smooth: boolean; picture: () => Picture | null;
}

/**
 * A video closed back into its thumbnail keeps the frame it was left at (web: its still is set to that time): the
 * thumbnail shows it from then on, and opened again the video goes on from there.
 */
export class KeptFrame {
  constructor(readonly picture: Picture, readonly atUs: number) {}
}

/** The viewer open, if one is; the chat's thumbnails by the file each shows; the one hidden while the viewer is its picture. */
export const FileViewers = {
  shown: new Watched<ViewerOpen | null>(null),
  get open(): boolean { return FileViewers.shown.value !== null; },
  thumbs: new Map<string, Thumb>(),
  hidden: new Watched<string | null>(null),
  /** The frames videos were left at, by the thumbnail's id. */
  frames: new Watched<ReadonlyMap<string, KeptFrame>>(new Map()),
  setFrame(id: string, frame: KeptFrame) { FileViewers.frames.value = new Map(FileViewers.frames.value).set(id, frame); },
  id(station: string, key: string, path: string) { return `${station}/${key}/${path}`; },
};

/**
 * A thumbnail in the chat the viewer opens from (`id`: FileViewers.id): where it is, measured when the viewer asks;
 * hidden while the viewer shows its picture in its place (one picture on the screen, never two). Spread `ref`,
 * `onLayout` and `style` on its outermost view (the Kotlin's Modifier.viewerThumb).
 */
export function useViewerThumb(id: string, radius: number, letterbox = false, smooth = true, picture: () => Picture | null) {
  const ref = useRef<View>(null);
  const hidden = useWatched(FileViewers.hidden) === id;
  const thumb: Thumb = {
    measure: () => new Promise((done) => {
      const view = ref.current;
      if (!view) return done(null);
      view.measureInWindow((x, y, width, height) => {
        const { width: W, height: H } = Dimensions.get("window");
        const visible = width > 0 && height > 0 && x + width > 0 && y + height > 0 && x < W && y < H;
        done({ bounds: { left: x, top: y, width, height }, visible });
      });
    }),
    radius, letterbox, smooth, picture,
  };
  FileViewers.thumbs.set(id, thumb);
  return { ref, onLayout: () => { FileViewers.thumbs.set(id, thumb); }, style: { opacity: hidden ? 0 : 1 } as ViewStyle };
}
/** The Kotlin's name for it. */
export const viewerThumb = useViewerThumb;

/** useViewerThumb as a view around what it holds. */
export function ViewerThumb({ id, radius, letterbox = false, smooth = true, picture, children }: { id: string; radius: number; letterbox?: boolean; smooth?: boolean; picture: () => Picture | null; children?: ReactNode }) {
  const thumb = useViewerThumb(id, radius, letterbox, smooth, picture);
  return <View ref={thumb.ref} onLayout={thumb.onLayout} style={thumb.style} collapsable={false}>{children}</View>;
}

export function ForgetThumb({ id }: { id: string }) {
  useEffect(() => () => { FileViewers.thumbs.delete(id); }, [id]);
  return null;
}

const Phase = { Waiting: 0, Flying: 1, Rest: 2, Fading: 3 } as const;

/**
 * The picture's flight: `p` 0 is the thumbnail (its box, its corners, the picture cropped to it as the chat shows it),
 * 1 the picture where the stage puts it. One value moves the picture, its crop and corners, the black behind it and
 * the bars together.
 */
export class ViewerFlight {
  readonly phase = makeMutable<number>(Phase.Rest);
  readonly p = makeMutable(1);
  readonly fade = makeMutable(1);
  /** The thumbnail's box on the stage. */
  readonly from = makeMutable<Rect | null>(null);
  readonly radius = makeMutable(0);
  /** Its corners are smooth ones (ui/Smooth.tsx), as a message's picture has; plain round in the composer. */
  readonly smooth = makeMutable(true);
  /** The picture is letterboxed in the thumbnail's box (ChatFiles.tsx's imageBox): fitted inside it, not cropped. */
  readonly letterbox = makeMutable(false);
  /** The picture's box on the stage, as it is now (null until known), kept here by whoever knows it. */
  readonly to = makeMutable<Rect | null>(null);
  target: () => Rect | null = () => null;
  /** A video's frame as it shows now, and where it is (null for a picture, or before the player has one). */
  frame: () => Promise<KeptFrame | null> = async () => null;
}

/** How much of the viewer's ground and bars shows. */
function useChrome(f: ViewerFlight): SharedValue<number> {
  // Its shared values alone into the worklet: the flight itself (a class, with functions of the JS thread's) is not one
  // the UI thread can take.
  const { phase, p } = f;
  return useDerivedValue(() => (phase.value === Phase.Waiting ? 0 : phase.value === Phase.Flying ? p.value : 1));
}

/** Where a picture proportioned like `to` shows letterboxed in the box `box`: fitted inside it, centred. */
function fitted(box: Rect, to: Rect): Rect {
  "worklet";
  if (to.width <= 0 || to.height <= 0) return box;
  const k = Math.min(box.width / to.width, box.height / to.height);
  const cx = box.left + box.width / 2, cy = box.top + box.height / 2;
  return { left: cx - (to.width * k) / 2, top: cy - (to.height * k) / 2, width: to.width * k, height: to.height * k };
}

/** What wraps a picture's stage: the Kotlin's `stage: Modifier`, the flight carrying it from the thumbnail and back. */
export type StageWrap = ComponentType<{ children?: ReactNode }>;
export const NoStage: StageWrap = ({ children }) => <>{children}</>;

/** The stage (what shows the picture) carried from the thumbnail's box to its own place, or back. */
export function ViewerFlying({ f, children }: { f: ViewerFlight; children?: ReactNode }) {
  // Its shared values alone into the worklets (useChrome).
  const { phase, p, fade, from: fromBox, radius, smooth, letterbox, to: toBox } = f;
  const W = useSharedValue(0);
  const H = useSharedValue(0);
  const [laid, setLaid] = useState(false);
  const flying = () => {
    "worklet";
    if (phase.value !== Phase.Flying) return null;
    const to = toBox.value;
    const raw = fromBox.value;
    const from = raw && letterbox.value && to ? fitted(raw, to) : raw;
    if (!from || !to || to.width <= 0 || to.height <= 0) return null;
    const t = p.value;
    // Covering the thumbnail's box at the start, as a cropped picture does.
    const s0 = Math.max(from.width / to.width, from.height / to.height);
    const s = s0 + (1 - s0) * t;
    const tcx = to.left + to.width / 2, tcy = to.top + to.height / 2;
    const cx = from.left + from.width / 2 + (tcx - (from.left + from.width / 2)) * t;
    const cy = from.top + from.height / 2 + (tcy - (from.top + from.height / 2)) * t;
    // The crop, in the stage's own (unscaled) terms: the thumbnail's box growing into the picture's.
    const w = (from.width + (to.width - from.width) * t) / s;
    const h = (from.height + (to.height - from.height) * t) / s;
    const r = (radius.value * (1 - t)) / s;
    return { s, tcx, tcy, dx: cx - tcx, dy: cy - tcy, box: { left: tcx - w / 2, top: tcy - h / 2, width: w, height: h }, r };
  };
  const outer = useAnimatedStyle(() => {
    if (phase.value === Phase.Waiting) return { opacity: 0, transform: [] };
    const k = flying();
    if (!k) return { opacity: 1, transform: [] };
    // Scaled about the picture's centre, then moved to where the flight has it.
    return {
      opacity: 1,
      transform: [
        { translateX: k.dx + k.tcx - W.value / 2 }, { translateY: k.dy + k.tcy - H.value / 2 },
        { scale: k.s },
        { translateX: W.value / 2 - k.tcx }, { translateY: H.value / 2 - k.tcy },
      ],
    };
  });
  const clip = useAnimatedStyle(() => {
    const k = flying();
    if (!k) return { left: 0, top: 0, width: W.value, height: H.value, borderRadius: 0 };
    return { left: k.box.left, top: k.box.top, width: k.box.width, height: k.box.height, borderRadius: smooth.value ? k.r * SMOOTH_SCALE : k.r };
  });
  const inner = useAnimatedStyle(() => {
    const k = flying();
    return { left: k ? -k.box.left : 0, top: k ? -k.box.top : 0, width: W.value, height: H.value };
  });
  return (
    <Animated.View style={[StyleSheet.absoluteFill, outer]} onLayout={(e) => { W.value = e.nativeEvent.layout.width; H.value = e.nativeEvent.layout.height; setLaid(true); }}>
      {/* NATIVE: the clip is a plain round corner (continuous on iOS); the Smooth view's superellipse cannot take a
          radius that changes every frame. */}
      <Animated.View style={[{ position: "absolute", overflow: "hidden", borderCurve: "continuous" }, clip]}>
        <Animated.View style={[{ position: "absolute" }, inner]}>{laid ? children : null}</Animated.View>
      </Animated.View>
    </Animated.View>
  );
}

/** The viewer open over the pages (App.tsx puts it over them, under sheets, menus and toasts). */
export function ViewerHost() {
  const open = useWatched(FileViewers.shown);
  if (!open) return null;
  return <ViewerLayer key={open.n} open={open} />;
}

/** A kind the viewer carries between the thumbnail and its stage: images, and videos' stills. */
const known = (s: Shown) => { const k = kindOf(s.file.name).kind; return k === PreviewKind.Image || k === PreviewKind.Video; };

const nextFrame = () => new Promise<void>((done) => requestAnimationFrame(() => done()));
const timing = (v: SharedValue<number>, to: number, duration: number, easing: (typeof Ease)[keyof typeof Ease]) =>
  new Promise<void>((done) => { v.value = withTiming(to, { duration, easing }, () => runOnJS(done)()); });

function ViewerLayer({ open }: { open: ViewerOpen }) {
  const flight = useMemo(() => new ViewerFlight(), []);
  const origin = useRef({ x: 0, y: 0 });
  const layer = useRef<View>(null);
  const current = useRef(open.opened);
  const [closing, setClosing] = useState(false);
  const closingRef = useRef(false);
  const idOf = (s: Shown) => FileViewers.id(open.station, s.key, s.file.path);
  const thumbOf = async (s: Shown) => {
    const thumb = FileViewers.thumbs.get(idOf(s));
    if (!thumb || !known(s)) return null;
    const at = await thumb.measure();
    return at && at.visible ? { thumb, bounds: at.bounds } : null;
  };
  const place = () => new Promise<void>((done) => {
    const v = layer.current;
    if (!v) return done();
    v.measureInWindow((x, y) => { origin.current = { x, y }; done(); });
  });
  useEffect(() => {
    // It comes up in the keyboard's place: what was being typed into lets go of it first.
    Keyboard.dismiss();
    (async () => {
      await place();
      const thumb = await thumbOf(open.opened);
      // Its size waited for only as long as what is here takes (sent with it, its thumbnail's or still's, laid out):
      // one that has to come over the network (at no time known) is not waited for; the viewer fades in, showing it come.
      let isKnown = false;
      if (thumb) {
        flight.phase.value = Phase.Waiting;
        const until = Date.now() + 100;
        while (Date.now() < until && flight.target() === null) await nextFrame();
        isKnown = flight.target() !== null;
      }
      if (thumb && isKnown) {
        const b = thumb.bounds;
        flight.from.value = { left: b.left - origin.current.x, top: b.top - origin.current.y, width: b.width, height: b.height };
        flight.radius.value = thumb.thumb.radius; flight.smooth.value = thumb.thumb.smooth;
        flight.letterbox.value = thumb.thumb.letterbox;
        flight.to.value = flight.target();
        flight.p.value = 0;
        FileViewers.hidden.value = idOf(open.opened);
        flight.phase.value = Phase.Flying;
        await timing(flight.p, 1, OPEN_MS, Ease.Arrive);
      } else {
        flight.phase.value = Phase.Fading;
        flight.fade.value = 0;
        await timing(flight.fade, 1, FADE_MS, Ease.Out);
      }
      if (!closingRef.current) {
        flight.phase.value = Phase.Rest;
        FileViewers.hidden.value = null;
      }
    })();
  }, []);
  const close = () => {
    if (closingRef.current) return;
    closingRef.current = true;
    setClosing(true);
    (async () => {
      await place();
      const s = current.current;
      const thumb = await thumbOf(s);
      if (thumb && flight.target() !== null) {
        const b = thumb.bounds;
        flight.from.value = { left: b.left - origin.current.x, top: b.top - origin.current.y, width: b.width, height: b.height };
        flight.radius.value = thumb.thumb.radius; flight.smooth.value = thumb.thumb.smooth;
        flight.letterbox.value = thumb.thumb.letterbox;
        flight.to.value = flight.target();
        if (flight.phase.value !== Phase.Flying) flight.p.value = 1;
        // The thumbnail it lands in shows the frame it goes back with (hidden until then, so never seen changing).
        const frame = await flight.frame();
        if (frame) FileViewers.setFrame(idOf(s), frame);
        FileViewers.hidden.value = idOf(s);
        flight.phase.value = Phase.Flying;
        await timing(flight.p, 0, CLOSE_MS, Ease.Arrive);
      } else {
        // As web's: the viewer fades from where it is (140ms), its thumbnail (if it hid one) shown again at once.
        if (flight.phase.value === Phase.Flying) flight.fade.value = flight.p.value;
        FileViewers.hidden.value = null;
        flight.phase.value = Phase.Fading;
        await timing(flight.fade, 0, FADE_MS, Ease.Out);
      }
      // Left drawn as it ended (on the thumbnail, or gone) until the page lets it go.
      open.onClose();
    })();
  };
  const { phase: flightPhase, fade: flightFade } = flight;
  const faded = useAnimatedStyle(() => ({ opacity: flightPhase.value === Phase.Fading ? flightFade.value : 1 }));
  return (
    <Animated.View
      ref={layer}
      collapsable={false}
      style={[StyleSheet.absoluteFill, faded]}
      // Its own: no touch reaches the page under it.
      onStartShouldSetResponder={() => true}
    >
      <Viewer station={open.station} opened={open.opened} gallery={open.gallery} onClose={close} flight={flight} closing={closing} canDraft={open.canDraft} onShown={(s) => { current.current = s; }} />
    </Animated.View>
  );
}

/** Images stepped through slide this far apart, on this spring (web: FilePreview.tsx GAP, SLIDE). */
const SLIDE_GAP = 24;
const SLIDE = { mass: 1, stiffness: 400, damping: 2 * Math.sqrt(400) };

/** The image going as the next comes: its `picture` where it was (`at`), moving out to the side away from `dir`. */
interface Leaving { picture: Picture; at: Rect; dir: number; width: number }

function LeavingPicture({ l, strip }: { l: Leaving; strip: SharedValue<number> }) {
  const moved = useAnimatedStyle(() => ({ transform: [{ translateX: strip.value - l.dir * l.width }] }));
  return (
    <Animated.View style={[StyleSheet.absoluteFill, moved]} pointerEvents="none">
      <Image source={{ uri: l.picture.uri }} resizeMode="stretch" style={{ position: "absolute", left: l.at.left, top: l.at.top, width: l.at.width, height: l.at.height }} />
    </Animated.View>
  );
}

function Viewer({ station, opened, gallery, onClose, flight, closing, canDraft, onShown }: {
  station: string; opened: Shown; gallery: Gallery | null; onClose: () => void; flight: ViewerFlight; closing: boolean; canDraft: boolean; onShown: (s: Shown) => void;
}) {
  const C = useC();
  const ink = chatInk(useC());
  const insets = useSafeAreaInsets();
  const [shown, setShown] = useState(opened);
  const file = shown.file;
  const key = shown.key;
  useEffect(() => { onShown(shown); }, [shown]);
  const knownKind = useMemo(() => kindOf(file.name), [file.path]);
  const chat = gallery?.kind === "Chat" && knownKind.kind === PreviewKind.Image ? gallery.of : null;
  const told = useTopic<ImageNear>(chat ? { topic: "imageNear", station, ...("thread" in chat ? { thread: chat.thread } : { session: chat.session }), path: file.path } : null);
  const folder = useMemo(() => (knownKind.kind === PreviewKind.Image && gallery?.kind === "Folder" ? gallery.images() : []), [file.path]);
  const at = folder.findIndex((s) => s.file.path === file.path);
  // A chat's through the session that keeps each (the core says which, `owner`).
  const ownerOf = (f: Attachment | undefined) => (f?.owner ? new Shown(f.owner, f) : null);
  const before = chat ? ownerOf(told.value?.before) : at > 0 ? folder[at - 1] ?? null : null;
  const after = chat ? ownerOf(told.value?.after) : at >= 0 ? folder[at + 1] ?? null : null;
  const fullId = FileData.id(station, key, file, false);
  const keptLoad = (): FileLoad => { const k = FileData.kept(fullId); return k ? { t: "Ready", bytes: k } : { t: "Loading", got: null }; };
  // What a file of no known kind is: text, when its first bytes read as UTF-8 with no NULs. Only they are fetched.
  const [sniffed, setSniffed] = useKeyed<boolean | null>(fullId, () => {
    if (knownKind.kind !== null) return null;
    const k = FileData.kept(fullId);
    return k ? looksLikeText(k) : null;
  });
  useEffect(() => {
    if (knownKind.kind !== null || sniffed !== null) return;
    let gone = false;
    // A station from before parts cannot say: told of, as anything else not shown.
    FileData.head(app, station, key, file, SNIFF_BYTES).then((b) => looksLikeText(b), () => false).then((v) => { if (!gone) setSniffed(v); });
    return () => { gone = true; };
  }, [fullId]);
  const kind = knownKind.kind ?? (sniffed === null ? null : sniffed ? PreviewKind.Text : null);
  const sure = knownKind.kind !== null || sniffed !== null;
  // Shown here: a kind it has a viewer for, read from the disk (players, PDFs) or small enough to read into memory.
  // Anything else is told of (its name, size and kind) and fetched only when asked for: saved, or an APK installed.
  const toldOf = sure && (kind === PreviewKind.Video || kind === PreviewKind.Audio || kind === PreviewKind.Pdf ? false : kind === null ? true : file.size > BIG_FILE);
  const [asked, setAsked] = useKeyed(fullId, () => false);
  const [then, setThen] = useKeyed<Then | null>(fullId, () => null);
  // Asked again after it failed: fetched again.
  const [tries, setTries] = useKeyed(fullId, () => 0);
  const want = sure && (!toldOf || asked);
  // By the file it is of: stepped to another, what came of the one before is not taken for it (not even for a frame).
  const [got, setGot] = useState<[string, FileLoad]>(() => [fullId, keptLoad()]);
  useEffect(() => {
    if (got[0] === fullId && (got[1].t === "Ready" || got[1].t === "OnDisk")) return;
    const first = keptLoad();
    setGot([fullId, first]);
    if (first.t === "Ready" || !want) return;
    let gone = false;
    (async () => {
      let next: FileLoad;
      try {
        next = file.size > BIG_FILE
          ? { t: "OnDisk", file: await FileData.toDisk(app, station, key, file).await() }
          : { t: "Ready", bytes: await FileData.fetch(app, station, key, file, false).await() };
      } catch (e) {
        next = { t: "Failed", message: e instanceof Error ? e.message : String(e) };
      }
      if (!gone) setGot([fullId, next]);
    })();
    return () => { gone = true; };
  }, [fullId, want, tries]);
  const loaded = got[0] === fullId ? got[1] : keptLoad();
  const progress = FileData.useProgress(fullId);
  const shownLoaded: FileLoad = loaded.t === "Loading" ? { t: "Loading", got: progress } : loaded;
  // The neighbours are fetched ahead, so a step shows the next one at once.
  useEffect(() => {
    for (const n of [before, after]) if (n && n.file.size <= BIG_FILE) FileData.fetch(app, station, n.key, n.file, false).await().catch(() => undefined);
  }, [before?.file.path, after?.file.path]);
  const bytes = loaded.t === "Ready" ? loaded.bytes : null;
  const disk = loaded.t === "OnDisk" ? loaded.file : null;
  // Asked for and come: saved, or installed (not stopped by the viewer closing).
  useEffect(() => {
    const what = then;
    if (!what) return;
    if (bytes === null && disk === null) return;
    setThen(null);
    if (what === "Install") void install(fullId, file.name, bytes, disk); else void save(file.name, bytes, disk);
  }, [then, bytes, disk]);
  const ask = (what: Then) => {
    if (what === "Install" && !mayInstall()) { app.toast = t("android-chat.file.allowInstall", { app: Constants.expoConfig?.name ?? "still.fail" }); return; }
    if (bytes !== null || disk !== null) { if (what === "Install") void install(fullId, file.name, bytes, disk); else void save(file.name, bytes, disk); }
    else { if (loaded.t === "Failed") setTries((n) => n + 1); setAsked(true); setThen(what); }
  };
  const dark = kind === PreviewKind.Image || kind === PreviewKind.Video;

  // The bars float over the file, and fade when left alone (not while an image comes, nor while marking).
  const [awake, setAwake] = useState(true);
  const rest = useRef<ReturnType<typeof setTimeout> | null>(null);
  const wake = (ms = REST_MS) => {
    setAwake(true);
    if (rest.current) clearTimeout(rest.current);
    rest.current = setTimeout(() => setAwake(false), ms);
  };
  const awakeRef = useRef(awake);
  awakeRef.current = awake;
  const toggle = () => { if (awakeRef.current) { if (rest.current) clearTimeout(rest.current); setAwake(false); } else wake(TAP_REST_MS); };
  useEffect(() => { wake(); }, [file.path]);
  useEffect(() => () => { if (rest.current) clearTimeout(rest.current); }, []);

  const zoom = useMemo(() => new ZoomState(DENSITY), [file.path]);
  const marks = useMemo(() => new ImageMarks(zoom, DENSITY), [file.path]);
  useChanges(zoom);
  useChanges(marks);

  // The one shown and those beside it move as one strip, GAP apart (web: FilePreview.tsx go): a step slides it out to
  // one side and the next in from the other, a swipe carries it under the finger first. The one going is drawn from
  // its picture where it was.
  const strip = useSharedValue(0);
  const [leaving, setLeaving] = useState<Leaving | null>(null);
  const [width, setWidth] = useState(0);
  const near = useRef<[Shown | null, Shown | null]>([before, after]);
  near.current = [before, after];
  const live = useRef({ width, shown, zoom });
  live.current = { width, shown, zoom };
  const gap = SLIDE_GAP;
  const longest = chatLongest();
  const back = (v = 0) => { strip.value = withSpring(0, { ...SLIDE, velocity: v }); };
  const go = (dir: number, v = 0) => {
    const to = dir < 0 ? near.current[0] : near.current[1];
    if (!to) return back(v);
    const w = live.current.width + gap;
    const from = strip.value;
    const was = live.current.shown;
    const r = rectOf(live.current.zoom);
    const p = r ? leavingPicture(station, was, longest) : null;
    setLeaving(r && p ? { picture: p, at: r, dir, width: w } : null);
    setShown(to);
    // Set before the next frame draws the new one: it comes in from the side, not first in place.
    strip.value = from + dir * w;
    strip.value = withSpring(0, { ...SLIDE, velocity: v }, (done) => { if (done) runOnJS(setLeaving)(null); });
  };
  const swipe = useMemo<Swipe>(() => ({
    drag(dx: number) {
      // A swipe while one slides: it takes the strip as it is.
      setLeaving(null);
      // Past the first or the last, it gives only a little.
      const none = dx > 0 ? near.current[0] === null : near.current[1] === null;
      strip.value = none ? dx / 3 : dx;
    },
    end(dx: number, vx: number) {
      const far = Math.abs(dx) > Math.min(80 * DENSITY, live.current.width / 5);
      const flung = Math.abs(vx) > 300 * DENSITY && Math.sign(vx) === Math.sign(dx) && Math.abs(dx) > 10 * DENSITY;
      if (dx !== 0 && (far || flung)) go(dx > 0 ? -1 : 1, vx); else back(vx);
    },
  }), []);
  const [source, setSource] = useKeyed(file.path, () => false);
  // Marking takes back first; then the viewer closes (the Kotlin's two BackHandlers, the inner one first).
  useBack(marks.on || !closing, () => { if (marks.on) marks.back(); else if (!closing) onClose(); });
  const coming = (kind === PreviewKind.Image || (kind === PreviewKind.Video && FileData.keptPicture(`${fullId}#still`, 0) !== null)) && shownLoaded.t === "Loading";

  // The system bars' icons light over a dark viewer, as the app's again once it closes (it is in the app's own window).
  const appLight = !C.dark;
  const light = !dark && appLight;
  useEffect(() => {
    const want = closing ? appLight : light;
    setStatusBarStyle(want ? "dark" : "light");
    if (Platform.OS === "android") NavigationBar.setButtonStyleAsync(want ? "dark" : "light").catch(() => undefined);
    return () => {
      setStatusBarStyle(appLight ? "dark" : "light");
      if (Platform.OS === "android") NavigationBar.setButtonStyleAsync(appLight ? "dark" : "light").catch(() => undefined);
    };
  }, [light, closing]);
  // A video's still, as the chat shows it: what flies from the thumbnail, and stands in until the player's first frame.
  const still = useMemo(() => (knownKind.kind === PreviewKind.Video ? FileViewers.thumbs.get(FileViewers.id(station, key, file.path))?.picture() ?? FileData.keptPicture(`${fullId}#still`, 0) : null), [file.path]);
  const videoZoom = useMemo(() => new ZoomState(DENSITY), [file.path]);
  useChanges(videoZoom);
  useEffect(() => {
    const sent = sentSize(file);
    if (videoZoom.natural == null) { const n = still ? { width: still.width, height: still.height } : sent; if (n) videoZoom.fitNatural(n); }
  }, [videoZoom, still]);
  // The picture's place on the stage, for the flight: read from the zoom that has it, kept current as it changes.
  const placing = knownKind.kind === PreviewKind.Image ? zoom : knownKind.kind === PreviewKind.Video ? videoZoom : null;
  flight.target = () => rectOf(placing);
  useEffect(() => {
    if (!placing) { flight.to.value = null; return; }
    const keep = () => { flight.to.value = rectOf(placing); };
    keep();
    return placing.subscribe(keep);
  }, [placing]);
  const Stage = useMemo<StageWrap>(() => ({ children }) => <ViewerFlying f={flight}>{children}</ViewerFlying>, [flight]);
  const chrome = useChrome(flight);
  const groundShown = useAnimatedStyle(() => ({ opacity: chrome.value }));
  const chromeShown = useAnimatedStyle(() => ({ opacity: chrome.value }));
  const ground = dark ? "#000000" : kind === PreviewKind.Pdf ? lerpColor(C.bg, C.ink, 0.05) : ink.canvas;
  const startAtUs = FileViewers.frames.value.get(FileViewers.id(station, key, file.path))?.atUs ?? 0;
  const tint = dark ? DarkMuted : C.muted;
  const top = Math.max(insets.top, 8);
  const [widest, setWidest] = useState(0);
  const [outerWidth, setOuterWidth] = useState(0);
  const onSize = (e: LayoutChangeEvent) => {
    const { width: w, height: h } = e.nativeEvent.layout;
    videoZoom.fitBox({ width: w, height: h });
    setWidth(w);
    setOuterWidth(w);
  };

  let body: ReactNode = null;
  if (knownKind.kind === PreviewKind.Image && file.size <= BIG_FILE) {
    // One of its own for each image: what it remembers of one (its picture) is not the next one's.
    body = <ImageStage key={file.path} station={station} sessionKey={key} file={file} bytes={bytes} zoom={zoom} marks={marks} stage={Stage} onTap={toggle} swipe={marks.on ? null : swipe} slide={strip} />;
  } else if (knownKind.kind === PreviewKind.Video && still !== null && ((bytes === null && disk === null) || (shownLoaded.t !== "Ready" && shownLoaded.t !== "OnDisk"))) {
    body = <Poster still={still} zoom={videoZoom} stage={Stage} />;
  } else if (toldOf) {
    body = (
      <Note>
        <Facts file={file} kind={kind} cantShow={kind === null ? t("android-chat.file.cantPreview") : t("android-chat.file.tooBigToShow")} />
        {asked && shownLoaded.t === "Loading" ? (
          // On its way, asked for: how far it has come.
          progress !== null ? <FileProgress got={progress} sent={file.size} dark={false} /> : <Waiting />
        ) : (
          <View style={{ width: 220, gap: 8 }}>
            {shownLoaded.t === "Failed" ? <T size={14} color={C.red} align="center" style={{ width: "100%" }}>{t("android-chat.file.loadFailed", { error: shownLoaded.message })}</T> : null}
            {file.name.toLowerCase().endsWith(".apk") ? <NoteButton icon={null} label={t("android-chat.file.install")} strong onClick={() => ask("Install")} /> : null}
            <NoteButton icon={Icons.Download} label={t("android-chat.file.download")} strong={!file.name.toLowerCase().endsWith(".apk")} onClick={() => ask("Save")} />
          </View>
        )}
      </Note>
    );
  } else if (!sure || shownLoaded.t === "Loading") {
    body = <Note>{progress !== null ? <FileProgress got={progress} sent={file.size} dark={false} /> : <Waiting />}</Note>;
  } else if (shownLoaded.t === "Failed") {
    body = <Note><T size={15} color={C.muted} align="center">{t("android-chat.file.loadFailed", { error: shownLoaded.message })}</T></Note>;
  } else if (disk !== null) {
    if (kind === PreviewKind.Video) body = (
      <VideoViewer file={disk.uri} name={file.name} awake={awake} wake={() => wake(TAP_REST_MS)} onTap={toggle} glass={DarkGlass16} zoomOf={videoZoom} stage={Stage} poster={still}
        chrome={chrome} startAtUs={startAtUs} frameOut={(read) => { flight.frame = read; }} />
    );
    else if (kind === PreviewKind.Audio) body = <Note><AudioViewer file={disk.uri} name={file.name} /></Note>;
    else if (kind === PreviewKind.Pdf) body = <PdfViewer file={disk.uri} onTap={toggle} />;
  } else if (bytes === null) {
    body = null;
  } else if (kind === PreviewKind.Video) {
    body = (
      <OnDisk id={fullId} name={file.name} bytes={bytes} waiting={() => (still !== null ? <Poster still={still} zoom={videoZoom} stage={Stage} /> : <Note><Waiting /></Note>)}>
        {(f) => (
          <VideoViewer file={f.uri} name={file.name} awake={awake} wake={() => wake(TAP_REST_MS)} onTap={toggle} glass={DarkGlass16} zoomOf={videoZoom} stage={Stage} poster={still}
            chrome={chrome} startAtUs={startAtUs} frameOut={(read) => { flight.frame = read; }} />
        )}
      </OnDisk>
    );
  } else if (kind === PreviewKind.Audio) {
    body = <OnDisk id={fullId} name={file.name} bytes={bytes}>{(f) => <Note><AudioViewer file={f.uri} name={file.name} /></Note>}</OnDisk>;
  } else if (kind === PreviewKind.Pdf) {
    body = <OnDisk id={fullId} name={file.name} bytes={bytes}>{(f) => <PdfViewer file={f.uri} onTap={toggle} />}</OnDisk>;
  } else if (kind !== null) {
    body = <TextViewer bytes={bytes} kind={kind} language={knownKind.language} name={file.name} source={source} onTap={toggle} />;
  }

  // A page's taps are its own (they do not reach here to bring the bar back): over one, the bar stays.
  const show = awake || coming || marks.on || (kind === PreviewKind.Html && !source);
  const saving = bytes !== null || disk !== null || (toldOf && !asked);
  return (
    <View style={StyleSheet.absoluteFill} onLayout={onSize}>
      <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: ground }, groundShown]} />
      <View style={StyleSheet.absoluteFill}>
        {leaving ? <LeavingPicture l={leaving} strip={strip} /> : null}
        {/* The ones beside it, out of sight until a swipe brings them in (while one goes, it is drawn in their place). */}
        {knownKind.kind === PreviewKind.Image && !marks.on && leaving === null ? (
          <>
            {before ? <Beside key={`b:${before.file.path}`} station={station} s={before} thumbLongest={longest} strip={strip} offset={-(width + gap)} /> : null}
            {after ? <Beside key={`a:${after.file.path}`} station={station} s={after} thumbLongest={longest} strip={strip} offset={width + gap} /> : null}
          </>
        ) : null}
        {body}
      </View>
      {/* Over the image's sides, in the middle: to the one before and after. */}
      {(before !== null || after !== null) && !marks.on ? ([[before, "left"], [after, "right"]] as const).map(([to, side], i) => (to !== null ? (
        <Animated.View key={side} pointerEvents={show ? "auto" : "none"} style={[{ position: "absolute", top: 0, bottom: 0, [side]: 8, justifyContent: "center" }, chromeShown]}>
          <View style={{ opacity: show ? 1 : 0, width: 36, height: 36, borderRadius: 18, elevation: 1, shadowColor: "#000", shadowOpacity: 0.3, shadowRadius: 1, shadowOffset: { width: 0, height: 0.5 } }}>
            <Pressable disabled={!show} onPress={() => go(i === 0 ? -1 : 1)} android_ripple={{ color: withAlpha("#FFFFFF", 0.2), borderless: false }}
              style={{ width: 36, height: 36, borderRadius: 18, overflow: "hidden", backgroundColor: withAlpha(DarkCanvas, 0.8), alignItems: "center", justifyContent: "center" }}>
              <Icon icon={i === 0 ? Icons.ChevronLeft : Icons.ChevronRight} size={22} color={DarkText} />
            </Pressable>
          </View>
        </Animated.View>
      ) : null)) : null}
      {/* The bar at the top: the file's name, its own tools, how far it has come, download and close. */}
      <Animated.View pointerEvents="box-none" style={[{ position: "absolute", left: 0, right: 0, top, alignItems: "center" }, chromeShown]}>
        <View
          pointerEvents={show ? "auto" : "none"}
          onLayout={(e) => { const w = e.nativeEvent.layout.width; if (w > widest) setWidest(w); }}
          style={{ minWidth: widest, maxWidth: Math.max(0, outerWidth - 16), opacity: show ? 1 : 0 }}
        >
          {dark ? (
            <DarkGlass radius={14} style={{ height: 44 }}>{barRow()}</DarkGlass>
          ) : (
            <PageGlass radius={14} style={{ height: 44 }}>{barRow()}</PageGlass>
          )}
        </View>
      </Animated.View>
      {marks.on ? (
        <View style={{ position: "absolute", left: 0, right: 0, bottom: insets.bottom + 8, alignItems: "center" }} pointerEvents="box-none">
          <MarksFoot marks={marks} haze={null} glass={DarkGlass14} />
        </View>
      ) : null}
    </View>
  );

  function barRow() {
    return (
      <View style={{ height: 44, flexDirection: "row", alignItems: "center", gap: 4, paddingLeft: 12, paddingRight: 2 }}>
        <T size={15} weight="600" color={dark ? DarkText : C.ink} numberOfLines={1} style={{ flexShrink: 1, flexGrow: 1, minWidth: 0, paddingRight: 12 }}>{file.name}</T>
        {coming && progress !== null ? <FileProgress got={progress} sent={file.size} dark inBar /> : null}
        {marks.on ? (
          <MarksActions marks={marks} canDraft={canDraft}
            onDownload={() => { if (bytes !== null) void finish(marks, bytes, zoom, file, async (p) => { app.toast = (await marks.save(p.name)) ? t("android-chat.file.saved") : t("android-chat.file.saveFailed"); }); }}
            onDraft={() => {
              // Into the draft of the chat whose agent keeps the image: its page takes it (Preview.tsx → TakeDraftOffers).
              if (bytes !== null) void finish(marks, bytes, zoom, file, async (p, quotes) => { DraftOffers.add(new MarkOffer(station, key, [p], quotes)); marks.leave(); onClose(); });
            }} />
        ) : coming ? null : knownKind.kind === PreviewKind.Image ? (
          // While the whole of it comes the bar says how far it has; its tools come with it.
          <>
            <PictureButton icon={Icons.Minus} label={t("android-chat.file.zoomOut")} enabled={zoom.scale > zoom.minScale + 1e-4} tint={tint} onClick={() => zoom.zoomTo(zoom.scale / 1.25, null, true)} />
            <Smooth radius={12} style={{ height: 32, minWidth: 52 }}>
              <Pressable onPress={() => zoom.reset(true)} android_ripple={{ color: withAlpha(tint, 0.2), borderless: false }} style={{ height: 32, minWidth: 52, alignItems: "center", justifyContent: "center" }}>
                <T size={13} color={tint}>{`${Math.round(zoom.scale * 100)}%`}</T>
              </Pressable>
            </Smooth>
            <PictureButton icon={Icons.Plus} label={t("android-chat.file.zoomIn")} enabled={zoom.scale < MAX_SCALE - 1e-4} tint={tint} onClick={() => zoom.zoomTo(zoom.scale * 1.25, null, true)} />
            {bytes !== null ? <PictureButton icon={Icons.Edit} label={t("android-chat.file.mark")} tint={tint} onClick={() => marks.start()} /> : null}
          </>
        ) : kind === PreviewKind.Markdown || kind === PreviewKind.Csv || kind === PreviewKind.Html ? (
          <View style={{ width: 120 }}>
            <Seg options={[t("android-chat.file.tab.preview"), t("android-chat.file.tab.source")]} selected={source ? 1 : 0} onSelect={(i: number) => setSource(i === 1)} height={30} fill radius={15} inset={2} />
          </View>
        ) : null}
        {/* A file told of (not shown) can be asked for from here as well as from its page. */}
        {!marks.on && !coming ? (
          <View style={{ opacity: saving ? 1 : 0 }}>
            <PictureButton icon={Icons.Download} label={t("android-chat.file.download")} enabled={saving} tint={tint} onClick={() => ask("Save")} />
          </View>
        ) : null}
        <PictureButton icon={Icons.Close} label={t("common.close")} tint={tint} onClick={onClose} />
      </View>
    );
  }
}

/** The marked image made and handed on (`use`), with a quote per numbered mark; what went wrong said in the bar. */
async function finish(marks: ImageMarks, bytes: Uint8Array, zoom: ZoomState, file: Attachment, use: (p: Picked, quotes: OfferQuote[]) => Promise<void>) {
  const natural = zoom.natural;
  if (!natural) return;
  marks.busy = true;
  marks.error = null;
  try {
    marks.putDown();
    const all = marks.all();
    const made = await marks.render(bytes, natural);
    if (!made) throw new Error(t("android-chat.file.drawFailed"));
    const d = new Date();
    const stamp = [d.getHours(), d.getMinutes(), d.getSeconds()].map((n) => String(n).padStart(2, "0")).join("");
    const dot = file.name.lastIndexOf(".");
    const name = t("android-chat.file.marked.name", { name: dot >= 0 ? file.name.substring(0, dot) : file.name, stamp });
    await use({ ...made, name } as Picked, marks.quotes(all, name, file.name, natural));
  } catch (e) {
    marks.error = (e instanceof Error ? e.message : "") || t("android-chat.file.drawFailed");
  } finally {
    marks.busy = false;
  }
}

/** Frosted glass over a picture. */
export function DarkGlass({ radius, style, children }: { radius: number; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  return (
    <Smooth radius={radius} style={[{ backgroundColor: "#000000" }, style]}>
      <Frost tint="#121214" alpha={0.62} px={24} style={StyleSheet.absoluteFill} />
      {children}
    </Smooth>
  );
}
/** The Kotlin's darkGlass(haze, Smooth(16.dp)) and Smooth(14.dp), as what wraps a bar. */
export const DarkGlass16: StageWrapStyled = ({ style, children }) => <DarkGlass radius={16} style={style}>{children}</DarkGlass>;
export const DarkGlass14: StageWrapStyled = ({ style, children }) => <DarkGlass radius={14} style={style}>{children}</DarkGlass>;
/** What a bar's glass is (the Kotlin's `glass: Modifier`): a box that holds the bar. */
export type StageWrapStyled = ComponentType<{ style?: StyleProp<ViewStyle>; children?: ReactNode }>;

/** The same over a page of the theme's colours (a document), as the composer's. */
function PageGlass({ radius, style, children }: { radius: number; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const C = useC();
  // Over the viewer's canvas (web FilePreview.css.ts: --canvas), white in the light.
  const bg = chatInk(useC()).canvas;
  const tint = C.dark ? C.surface2 : C.surface;
  return (
    <View style={[{ borderRadius: radius * SMOOTH_SCALE, elevation: 6, shadowColor: "#000", shadowOpacity: 0.12, shadowRadius: 6, shadowOffset: { width: 0, height: 2 } }, style]}>
      <Smooth radius={radius} style={[StyleSheet.absoluteFill, { backgroundColor: bg }]}>
        <Frost tint={tint} alpha={0.72} px={20} style={StyleSheet.absoluteFill} />
      </Smooth>
      {children}
    </View>
  );
}

function Note({ children }: { children?: ReactNode }) {
  return <View style={{ flex: 1, padding: 24, alignItems: "center", justifyContent: "center", gap: 14 }}>{children}</View>;
}

/** A file not here yet, its size not known: what a viewer's page waits on, as every wait is said (ui/Waiting.tsx). */
const Waiting = () => <WaitPill text={t("common.reading")} />;

/** How many of a file's first bytes tell whether it is text. */
const SNIFF_BYTES = 8192;

/** What a file told of (not shown here) is fetched for, once asked. */
type Then = "Save" | "Install";

/** A file not shown here, told of: its kind's mark, its name, its size and extension, and why it is not shown. */
function Facts({ file, kind, cantShow }: { file: Attachment; kind: PreviewKind | null; cantShow: string }) {
  const C = useC();
  const dot = file.name.lastIndexOf(".");
  const e = dot >= 0 ? file.name.substring(dot + 1) : "";
  const ext = e.length > 0 && e.length <= 12 && e !== file.name ? e.toUpperCase() : null;
  return (
    <View style={{ alignItems: "center", gap: 6 }}>
      <Icon icon={kind === null ? Icons.File : Icons.FileText} size={44} color={C.muted} />
      <T size={17} line={23} weight="600" color={C.ink} align="center" numberOfLines={3} style={{ marginTop: 6 }}>{file.name}</T>
      <T size={13} color={C.muted}>{[fileSize(file.size), ext].filter((x) => x !== null).join(" · ")}</T>
      <T size={14} color={C.muted} align="center" style={{ marginTop: 4 }}>{cantShow}</T>
    </View>
  );
}

/** A button on a note's page: the accent's when `strong`, the chip colour's otherwise. */
function NoteButton({ icon, label, strong, onClick }: { icon: IconPaths | null; label: string; strong: boolean; onClick: () => void }) {
  const C = useC();
  const ink = strong ? "#FFFFFF" : C.ink;
  return (
    <Smooth radius={12} style={{ width: "100%", backgroundColor: strong ? C.accent : C.chip }}>
      <Pressable onPress={onClick} android_ripple={{ color: withAlpha(ink, 0.15), borderless: false }}
        style={{ flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 6, paddingHorizontal: 14, paddingVertical: 10 }}>
        {icon ? <Icon icon={icon} size={16} color={ink} /> : null}
        <T size={15} weight="500" color={ink}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/** A file put in the phone's Downloads, from memory or from the disk; said in a toast. */
async function save(name: string, bytes: Uint8Array | null, disk: File | null) {
  const ok = disk !== null ? await download(name, disk) : bytes !== null && (await download(name, bytes));
  app.toast = ok ? t("android-chat.file.saved") : t("android-chat.file.saveFailed");
}

/** An APK handed to the system's installer, which asks the person to confirm; a failure is said in a toast. */
async function install(id: string, name: string, bytes: Uint8Array | null, disk: File | null) {
  try {
    const apk = disk ?? (bytes ? await FileData.onDisk(id, name, bytes) : null);
    if (!apk) return;
    // The installer takes the file's path on the disk.
    installApk(decodeURIComponent(apk.uri.replace(/^file:\/\//, "")));
  } catch (e) {
    app.toast = t("android-chat.file.installFailed", { error: e instanceof Error ? e.message || e.name : String(e) });
  }
}

/** How much of a file has come, out of its size (the station's, else the one sent with it). */
function FileProgress({ got, sent, dark, inBar = false }: { got: Got; sent: number; dark: boolean; inBar?: boolean }) {
  const C = useC();
  const total = got[1] ?? (sent > 0 ? sent : null);
  const part = total !== null && total > 0 ? Math.min(1, got[0] / total) : null;
  const text = dark ? DarkText : C.ink;
  const muted = dark ? DarkMuted : C.muted;
  let words: ReactNode;
  if (total !== null) {
    // The size so far in bold, where the sentence has it.
    const sentence = t("android-chat.file.loading.size");
    const cut = sentence.indexOf("{size}");
    const before = cut >= 0 ? sentence.substring(0, cut) : sentence;
    const after = cut >= 0 ? sentence.substring(cut + "{size}".length) : "";
    words = (
      <>
        {!inBar ? before : null}
        <Text style={{ color: text, fontWeight: "600" }}>{fileSize(got[0])}</Text>
        {` / ${fileSize(total)}`}
        {!inBar ? after : null}
      </>
    );
  } else words = t("common.reading");
  // Its size not known: the bar sweeps (ui/Waiting.tsx Progress).
  if (inBar) return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 8 }}>
      <T size={13} color={muted} numberOfLines={1}>{words}</T>
      <View style={{ width: 48 }}><Progress part={part} /></View>
    </View>
  );
  return (
    <Smooth radius={14} style={{ width: 220, backgroundColor: C.dark ? C.surface2 : C.surface }}>
      <View style={{ paddingHorizontal: 14, paddingVertical: 12, gap: 8, alignItems: "center" }}>
        <T size={15} color={muted} align="center">{words}</T>
        <View style={{ alignSelf: "stretch" }}><Progress part={part} /></View>
      </View>
    </Smooth>
  );
}

/** Text, when its first bytes decode as UTF-8 with no NULs. */
function looksLikeText(bytes: Uint8Array): boolean {
  const n = Math.min(bytes.length, 8192);
  for (let i = 0; i < n; i++) if (bytes[i] === 0) return false;
  // The cut may split a character; its last bytes are left out.
  const end = bytes.length > 8192 ? 8188 : n;
  for (let i = 0; i < end;) {
    const b = bytes[i]!;
    const extra = b < 0x80 ? 0 : b >= 0xc2 && b <= 0xdf ? 1 : b >= 0xe0 && b <= 0xef ? 2 : b >= 0xf0 && b <= 0xf4 ? 3 : -1;
    if (extra < 0) return false;
    // A character cut off at the end is not whole UTF-8: the decoder refuses it.
    if (i + extra >= end) return false;
    for (let k = 1; k <= extra; k++) if ((bytes[i + k]! & 0xc0) !== 0x80) return false;
    // Overlong and out-of-range forms, as a strict decoder refuses them.
    if (extra === 2 && ((b === 0xe0 && bytes[i + 1]! < 0xa0) || (b === 0xed && bytes[i + 1]! > 0x9f))) return false;
    if (extra === 3 && ((b === 0xf0 && bytes[i + 1]! < 0x90) || (b === 0xf4 && bytes[i + 1]! > 0x8f))) return false;
    i += extra + 1;
  }
  return true;
}

/** UTF-8 bytes as text (malformed sequences as U+FFFD), as Kotlin's String(bytes, UTF_8). */
export function utf8(bytes: Uint8Array): string {
  const Decoder = (globalThis as { TextDecoder?: new (label?: string) => { decode(b: Uint8Array): string } }).TextDecoder;
  if (Decoder) return new Decoder("utf-8").decode(bytes);
  let out = "";
  const chunk: number[] = [];
  const flush = () => { out += String.fromCharCode(...chunk); chunk.length = 0; };
  for (let i = 0; i < bytes.length;) {
    const b = bytes[i]!;
    let cp = 0xfffd, len = 1;
    if (b < 0x80) cp = b;
    else if (b >= 0xc2 && b <= 0xdf && i + 1 < bytes.length && (bytes[i + 1]! & 0xc0) === 0x80) { cp = ((b & 0x1f) << 6) | (bytes[i + 1]! & 0x3f); len = 2; }
    else if (b >= 0xe0 && b <= 0xef && i + 2 < bytes.length && (bytes[i + 1]! & 0xc0) === 0x80 && (bytes[i + 2]! & 0xc0) === 0x80) { cp = ((b & 0x0f) << 12) | ((bytes[i + 1]! & 0x3f) << 6) | (bytes[i + 2]! & 0x3f); len = 3; }
    else if (b >= 0xf0 && b <= 0xf4 && i + 3 < bytes.length && (bytes[i + 1]! & 0xc0) === 0x80 && (bytes[i + 2]! & 0xc0) === 0x80 && (bytes[i + 3]! & 0xc0) === 0x80) {
      cp = ((b & 0x07) << 18) | ((bytes[i + 1]! & 0x3f) << 12) | ((bytes[i + 2]! & 0x3f) << 6) | (bytes[i + 3]! & 0x3f); len = 4;
    }
    if (cp > 0xffff) { cp -= 0x10000; chunk.push(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff)); } else chunk.push(cp);
    if (chunk.length > 8000) flush();
    i += len;
  }
  flush();
  return out;
}

/** Shows `children` once the file is on the phone's disk (the players and the PDF renderer read files). */
function OnDisk({ id, name, bytes, waiting = () => <Note><Waiting /></Note>, children }: { id: string; name: string; bytes: Uint8Array; waiting?: () => ReactNode; children: (file: File) => ReactNode }) {
  const [file, setFile] = useKeyed<File | null>(id, () => null);
  useEffect(() => {
    let gone = false;
    FileData.onDisk(id, name, bytes).then((f) => { if (!gone) setFile(f); }, () => undefined);
    return () => { gone = true; };
  }, [id]);
  return <>{file ? children(file) : waiting()}</>;
}

/** A video's still where the player will show it (`zoom`), until it can. */
function Poster({ still, zoom, stage: Stage }: { still: Picture; zoom: ZoomState; stage: StageWrap }) {
  useChanges(zoom);
  return <Stage><DrawFitted p={still} zoom={zoom} /></Stage>;
}

/** A picture where `zoom` puts it on its stage (the Kotlin's drawFitted). */
export function DrawFitted({ p, zoom }: { p: Picture; zoom: ZoomState }) {
  useChanges(zoom);
  const r = rectOf(zoom);
  if (!r) return null;
  return <Image source={{ uri: p.uri }} resizeMode="stretch" style={{ position: "absolute", left: r.left, top: r.top, width: r.width, height: r.height }} />;
}

// ── images ─────────────────────────────────────────────────────────────

/** An image beside the one shown, fitted as the stage will fit it, drawn `offset` px aside of the strip. */
function Beside({ station, s, thumbLongest, strip, offset }: { station: string; s: Shown; thumbLongest: number; strip: SharedValue<number>; offset: number }) {
  const id = FileData.id(station, s.key, s.file, false);
  const [picture, setPicture] = useState<Picture | null>(() => leavingPicture(station, s, thumbLongest));
  useEffect(() => {
    const kept = FileData.keptPicture(id, 4096);
    if (kept) { setPicture(kept); return; }
    let gone = false;
    (async () => {
      let bytes: Uint8Array;
      try { bytes = await FileData.fetch(app, station, s.key, s.file, false).await(); } catch { return; }
      const p = await FileData.picture(id, bytes, 4096);
      if (p && !gone) setPicture(p);
    })();
    return () => { gone = true; };
  }, [id]);
  const zoom = useMemo(() => new ZoomState(DENSITY), []);
  useChanges(zoom);
  const moved = useAnimatedStyle(() => ({ transform: [{ translateX: strip.value + offset }] }));
  if (!picture) return null;
  zoom.fitNatural(sentSize(s.file) ?? { width: picture.width, height: picture.height });
  const r = rectOf(zoom);
  return (
    <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, moved]} onLayout={(e) => zoom.fitBox({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
      {r ? <Image source={{ uri: picture.uri }} resizeMode="stretch" style={{ position: "absolute", left: r.left, top: r.top, width: r.width, height: r.height }} /> : null}
    </Animated.View>
  );
}

/** What the stage drew of `s`: the whole of it if it came, else the chat's thumbnail. */
function leavingPicture(station: string, s: Shown, thumbLongest: number): Picture | null {
  return FileData.keptPicture(FileData.id(station, s.key, s.file, false), 4096) ?? FileData.keptPicture(FileData.id(station, s.key, s.file, true), thumbLongest);
}

/**
 * An image fitted to the screen, to pinch, pan and double-tap; fitted, one finger sideways is `swipe`'s (drawn `slide`
 * px aside). Until the whole of it comes (`bytes`), its thumbnail (as the chat showed it) stands in its place. Marked,
 * the marks are drawn over it, moved and zoomed with it.
 */
function ImageStage({ station, sessionKey: key, file, bytes, zoom, marks, stage: Stage, onTap, swipe, slide }: {
  station: string; sessionKey: string; file: Attachment; bytes: Uint8Array | null; zoom: ZoomState; marks: ImageMarks; stage: StageWrap;
  onTap: () => void; swipe: Swipe | null; slide: SharedValue<number>;
}) {
  const thumbId = FileData.id(station, key, file, true);
  const longest = chatLongest();
  const thumb = useMemo(() => FileData.keptPicture(thumbId, longest), [thumbId]);
  const fullId = FileData.id(station, key, file, false);
  const [failed, setFailed] = useKeyed(fullId, () => false);
  const [full, setFull] = useKeyed<Picture | null>(fullId, () => FileData.keptPicture(fullId, 4096));
  useEffect(() => {
    if (full !== null || bytes === null) return;
    let gone = false;
    FileData.picture(fullId, bytes, 4096).then((p) => { if (gone) return; setFull(p); if (p === null) setFailed(true); });
    return () => { gone = true; };
  }, [fullId, bytes]);
  useEffect(() => {
    const sent = sentSize(file);
    // The size the system read of the whole picture once it came.
    const read = full ? { width: full.width, height: full.height } : null;
    // A thumbnail's own size is not the image's: it only stands in the image's place.
    zoom.fitNatural(read ?? sent ?? (thumb ? { width: thumb.width, height: thumb.height } : null));
  }, [fullId, bytes, thumb, full]);
  // Words written under where the keyboard comes up: the image goes up with them, above it.
  const ime = useIme();
  const gap = 24;
  const wb = marks.writingBottom();
  const below = wb != null ? wb + gap - (zoom.box.height - ime) : 0;
  const lift = useSharedValue(0);
  useEffect(() => { lift.value = withSpring(ime > 0 && below > 0 ? below : 0, { mass: 1, stiffness: 1500, damping: 2 * Math.sqrt(1500) }); }, [ime > 0 && below > 0 ? below : 0]);
  const lifted = useAnimatedStyle(() => ({ transform: [{ translateY: -lift.value }] }));
  // Moved by the strip in drawing only: the gestures measure the finger on the stage, which stays put.
  const slid = useAnimatedStyle(() => ({ transform: [{ translateX: slide.value }] }));
  const C = useC();
  if (failed && file.name.toLowerCase().endsWith(".svg") && bytes !== null) {
    // Not a bitmap: drawn by a page of its own.
    return (
      <HtmlPage html={"<!doctype html><meta name=viewport content=\"width=device-width,initial-scale=1\"><body style=\"margin:0;display:grid;place-items:center;min-height:100vh;background:#000\">" +
        `<img style="max-width:100%;max-height:100vh" src="data:image/svg+xml;base64,${base64Of(bytes)}">`} />
    );
  }
  if (failed) return <Note><T size={15} color={DarkMuted}>{t("android-chat.file.image.failed")}</T></Note>;
  const picture = full ?? thumb;
  const r = rectOf(zoom);
  void C;
  return (
    <Stage>
      <Animated.View style={[StyleSheet.absoluteFill, lifted]}>
        <Zoomable state={zoom} onTap={onTap} swipe={swipe} strokes={marks.on ? marks : null} style={StyleSheet.absoluteFill}>
          <Animated.View style={[StyleSheet.absoluteFill, slid]} pointerEvents="none">
            {/* NATIVE: past 2× the Kotlin draws the picture's pixels as they are (FilterQuality.None); the system's
                image view always filters. */}
            {r && picture ? <Image source={{ uri: picture.uri }} resizeMode="stretch" style={{ position: "absolute", left: r.left, top: r.top, width: r.width, height: r.height }} /> : null}
            {marks.on && r ? (
              <Canvas style={StyleSheet.absoluteFill}>
                <SkiaPicture picture={createPicture((canvas) => {
                  canvas.translate(r.left, r.top);
                  canvas.scale(zoom.k, zoom.k);
                  drawMarks(canvas, marks.drawn());
                  marks.drawPicked(canvas, zoom.k);
                })} />
              </Canvas>
            ) : null}
          </Animated.View>
          {marks.on ? <>{marks.Pins()}{marks.WritingField()}</> : null}
        </Zoomable>
      </Animated.View>
    </Stage>
  );
}

/** Bytes as base64 (the protocol's form for bytes, and a data URI's). */
export function base64Of(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return globalThis.btoa(s);
}

// ── PDFs ───────────────────────────────────────────────────────────────

/** An open PDF: its pages' sizes, each drawn by the system's renderer one at a time (under its own lock), closed once let go. */
interface PdfNative {
  open(uri: string): Promise<{ id: string; sizes: { width: number; height: number }[] }>;
  /** Page `page` drawn `width` pixels wide on white (RENDER_MODE_FOR_DISPLAY), as a PNG file's uri; null once closed. */
  render(id: string, page: number, width: number): Promise<string | null>;
  close(id: string): Promise<void>;
}
// NATIVE: a module "StillfailPdf" over android.graphics.pdf.PdfRenderer: open(uri) → its pages' sizes (opening each
// page under a lock, the descriptor closed again if it fails), render(id, page, width) → the page drawn at most 2400
// wide, as FilePreview.kt's PdfViewer does, close(id) once no page is being drawn.
const pdfNative = requireOptionalNativeModule<PdfNative>("StillfailPdf");

type PdfDoc = { id: string; sizes: { width: number; height: number }[] };

/** Pages drawn by the system's PDF renderer, each as it scrolls near, as wide as the screen allows. */
function PdfViewer({ file, onTap }: { file: string; onTap: () => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const [doc, setDoc] = useState<{ ok: PdfDoc } | { error: string } | null>(null);
  useEffect(() => {
    let made: PdfDoc | null = null;
    let gone = false;
    (async () => {
      try {
        if (!pdfNative) throw new Error("PdfRenderer");
        made = await pdfNative.open(file);
        if (gone) { void pdfNative.close(made.id); return; }
        setDoc({ ok: made });
      } catch (e) {
        if (!gone) setDoc({ error: e instanceof Error ? e.message : String(e) });
      }
    })();
    // Gone (or gone while it opened): closed, once no page is being drawn.
    return () => { gone = true; if (made) void pdfNative?.close(made.id); };
  }, [file]);
  // A page not drawn yet is its shape, breathing as everything waited on (ui/Waiting.tsx), not a blank sheet.
  const breath = rememberBreath();
  if (doc === null) return <Note><WaitPill text={t("common.opening")} /></Note>;
  if ("error" in doc) return <Note><T size={15} color={C.muted}>{t("android-chat.file.pdf.failed", { error: doc.error })}</T></Note>;
  const pdf = doc.ok;
  return (
    <FlatList
      data={pdf.sizes}
      keyExtractor={(_, i) => String(i)}
      onTouchEnd={onTap}
      contentContainerStyle={{ paddingLeft: 12, paddingRight: 12, paddingTop: 60 + insets.top, paddingBottom: 12 + insets.bottom, gap: 12 }}
      renderItem={({ item: size, index: i }) => <PdfPage pdf={pdf} i={i} size={size} breath={breath} />}
    />
  );
}

function PdfPage({ pdf, i, size, breath }: { pdf: PdfDoc; i: number; size: { width: number; height: number }; breath: ReturnType<typeof rememberBreath> }) {
  const C = useC();
  const [width, setWidth] = useState(0);
  const [page, setPage] = useState<string | null>(null);
  useEffect(() => {
    if (width <= 0 || !pdfNative) return;
    let gone = false;
    const w = Math.min(Math.round(width * PixelRatioGet()), 2400);
    pdfNative.render(pdf.id, i, w).then((uri) => { if (!gone) setPage(uri); }, () => undefined);
    return () => { gone = true; };
  }, [width]);
  return (
    <View
      onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
      style={[{ width: "100%", aspectRatio: size.width / Math.max(1, size.height) },
        page !== null ? { elevation: 2, shadowColor: "#000", shadowOpacity: 0.2, shadowRadius: 2, backgroundColor: "#FFFFFF" } : [breathing(breath), { backgroundColor: C.bubble }]]}
    >
      {page !== null ? <Image source={{ uri: page }} accessibilityLabel={t("android-chat.file.pdf.page", { n: i + 1 })} resizeMode="stretch" style={StyleSheet.absoluteFill} /> : null}
    </View>
  );
}
const PixelRatioGet = () => PixelRatio.get();

// ── text ───────────────────────────────────────────────────────────────

/** Markdown rendered, CSV a table, HTML a page (each, or its source); code highlighted; text as it is. */
function TextViewer({ bytes, kind, language, name, source, onTap }: { bytes: Uint8Array; kind: PreviewKind; language: string | null; name: string; source: boolean; onTap: () => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const cut = bytes.length > SHOW_LIMIT;
  const [text, setText] = useKeyed<string | null>(bytes, () => null);
  useEffect(() => {
    let gone = false;
    // Off the frame that draws it: decoded once it has shown its wait.
    const timer = setTimeout(() => { if (!gone) setText(utf8(bytes.subarray(0, Math.min(bytes.length, SHOW_LIMIT)))); }, 0);
    return () => { gone = true; clearTimeout(timer); };
  }, [bytes]);
  const dark = C.dark;
  const lang = kind === PreviewKind.Markdown ? "markdown" : kind === PreviewKind.Csv ? null : language;
  const colored = useMemo(() => (text !== null && lang !== null && text.length <= HIGHLIGHT_LIMIT ? highlight(text, lang, dark) : null), [text, lang, dark]);
  if (text === null) return <Note><Waiting /></Note>;
  const tx = text;
  if (kind === PreviewKind.Html && !source) {
    // Its scripts run, in a page of its own that reaches nothing of the app's.
    const html = /<!doctype|<html[\s>]/i.test(tx.substring(0, 2048)) ? tx
      : `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><body style="margin:0;padding:16px;font-family:system-ui,sans-serif">${tx}`;
    return <View style={{ flex: 1, paddingTop: 60 + insets.top }}><HtmlPage html={html} /></View>;
  }
  const top = insets.top;
  const bottom = insets.bottom;
  if (kind === PreviewKind.Csv && !source) return <CsvTable text={tx} tab={name.toLowerCase().endsWith(".tsv")} cut={cut} top={top} bottom={bottom} onTap={onTap} />;
  let content: ReactNode;
  if (kind === PreviewKind.Markdown && !source) content = <View style={{ paddingLeft: 18, paddingRight: 18, paddingTop: 64 + top, paddingBottom: 64 + bottom }}><Markdown text={tx} /></View>;
  else if (colored !== null) content = (
    <ScrollView horizontal>
      <View style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 80 + top, paddingBottom: 64 + bottom }}>
        <AnnotatedText text={colored} style={{ fontFamily: CODE_FONT, fontSize: 12.5, lineHeight: 20, color: C.ink }} />
      </View>
    </ScrollView>
  );
  else content = <Text style={{ fontFamily: CODE_FONT, fontSize: 12.5, lineHeight: 20.6, color: C.ink, paddingLeft: 16, paddingRight: 16, paddingTop: 60 + top, paddingBottom: 48 + bottom }}>{tx}</Text>;
  return (
    <ScrollView style={{ flex: 1 }} onTouchEnd={onTap}>
      {cut ? <Cut words={t("android-chat.file.cut", { size: fileSize(SHOW_LIMIT) })} top={top} /> : null}
      {content}
    </ScrollView>
  );
}

function Cut({ words, top }: { words: string; top: number }) {
  const C = useC();
  return <T size={13} color={C.warn} style={{ width: "100%", backgroundColor: withAlpha(C.warn, 0.14), paddingLeft: 20, paddingRight: 20, paddingTop: 8 + top, paddingBottom: 8 }}>{words}</T>;
}

/** A page of its own in a WebView: scripts on, nothing of the phone's files or the app's reachable; links stay out. */
function HtmlPage({ html }: { html: string }) {
  return (
    <WebView
      style={{ flex: 1, backgroundColor: "#FFFFFF" }}
      originWhitelist={["*"]}
      source={{ html }}
      javaScriptEnabled
      allowFileAccess={false}
      allowFileAccessFromFileURLs={false}
      allowUniversalAccessFromFileURLs={false}
      domStorageEnabled={false}
      // Its own document loads; every link and navigation after it stays out.
      onShouldStartLoadWithRequest={(r) => r.url === "about:blank" || r.url.startsWith("data:")}
    />
  );
}

/** Rows of a CSV (or TSV), quotes and all. */
export function parseCsv(text: string, separator: string, limit = Number.MAX_SAFE_INTEGER): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  let i = 0;
  while (i < text.length && rows.length < limit) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"' && field.length === 0) quoted = true;
    else if (c === separator) { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); rows.push(row); row = []; field = "";
    } else field += c;
    i++;
  }
  if ((field.length > 0 || row.length > 0) && rows.length < limit) { row.push(field); rows.push(row); }
  return rows;
}

/** A table: a row number, then its columns, each as wide as what it holds (up to a limit); the head stays on top. */
function CsvTable({ text, tab, cut, top, bottom, onTap }: { text: string; tab: boolean; cut: boolean; top: number; bottom: number; onTap: () => void }) {
  const C = useC();
  const ink = chatInk(useC());
  const rows = useMemo(() => parseCsv(text, tab ? "\t" : ",", TABLE_ROWS + 1), [text]);
  const head = rows[0];
  const body = useMemo(() => rows.slice(1, 1 + TABLE_ROWS), [rows]);
  const more = rows.length - 1 > TABLE_ROWS;
  // As the cells' text draws it: each column measured by laying its first rows out unseen (the widest of them), as
  // the Kotlin's text measurer does.
  const sample = useMemo(() => (head ? [head, ...body.slice(0, 200)] : []), [rows]);
  const [measured, setMeasured] = useState<{ cols: number[]; number: number } | null>(null);
  const got = useRef<{ cols: (number | undefined)[]; number?: number }>({ cols: [] });
  useEffect(() => { got.current = { cols: [] }; setMeasured(null); }, [text]);
  if (!head) return null;
  const took = () => {
    const g = got.current;
    if (g.number === undefined || head.some((_, j) => g.cols[j] === undefined)) return;
    setMeasured({ cols: head.map((_, j) => Math.min(420, Math.max(48, g.cols[j]! + 32))), number: g.number + 36 });
  };
  if (!measured) return (
    <View style={{ position: "absolute", opacity: 0, left: 0, top: 0, flexDirection: "row" }} pointerEvents="none">
      {head.map((_, j) => (
        <View key={j} style={{ alignItems: "flex-start" }} onLayout={(e) => { got.current.cols[j] = e.nativeEvent.layout.width; took(); }}>
          {sample.map((r, i) => <T key={i} size={15} weight="600" numberOfLines={1} style={{ flexShrink: 0 }}>{(r[j] ?? "").substring(0, 80)}</T>)}
        </View>
      ))}
      <View style={{ alignItems: "flex-start" }} onLayout={(e) => { got.current.number = e.nativeEvent.layout.width; took(); }}>
        <T size={15}>{`${body.length}`}</T>
      </View>
    </View>
  );
  const widths = measured.cols;
  const number = measured.number;
  const all = number + widths.reduce((a, b) => a + b, 0);
  type Item = { t: "head" } | { t: "row"; i: number; r: string[] } | { t: "cut" };
  const items: Item[] = [{ t: "head" }, ...body.map((r, i) => ({ t: "row" as const, i, r })), ...(more || cut ? [{ t: "cut" as const }] : [])];
  return (
    <ScrollView horizontal style={{ flex: 1 }} onTouchEnd={onTap}>
      <FlatList
        style={{ width: all }}
        data={items}
        stickyHeaderIndices={[0]}
        keyExtractor={(it, k) => (it.t === "row" ? `r${it.i}` : `${it.t}${k}`)}
        contentContainerStyle={{ paddingTop: 60 + top, paddingBottom: 48 + bottom }}
        renderItem={({ item }) => {
          if (item.t === "head") return (
            // A hairline along its bottom.
            <View style={{ flexDirection: "row", backgroundColor: ink.canvas, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: C.line }}>
              <View style={{ width: number }} />
              {head.map((h, j) => <Cell key={j} text={h} width={widths[j]!} weight="600" color={C.ink} />)}
            </View>
          );
          if (item.t === "cut") return <Cut words={t("android-chat.file.cut.rows", { n: TABLE_ROWS })} top={0} />;
          return (
            <View style={{ flexDirection: "row" }}>
              <T size={15} color={C.muted} align="right" style={{ width: number, paddingLeft: 20, paddingRight: 16, paddingTop: 8, paddingBottom: 8 }}>{`${item.i + 1}`}</T>
              {head.map((_, j) => <Cell key={j} text={item.r[j] ?? ""} width={widths[j]!} weight={undefined} color={C.ink} />)}
            </View>
          );
        }}
      />
    </ScrollView>
  );
}

function Cell({ text, width, weight, color }: { text: string; width: number; weight: "600" | undefined; color: string }) {
  return <T size={15} weight={weight} color={color} numberOfLines={1} style={{ width, paddingHorizontal: 16, paddingVertical: 8 }}>{text}</T>;
}

/** The size the sender recorded, when it did. */
function sentSize(file: Attachment): { width: number; height: number } | null {
  const width = file.width;
  const height = file.height;
  if (width == null || height == null) return null;
  return width > 0 && height > 0 ? { width, height } : null;
}
