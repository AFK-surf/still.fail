// The one player of films and songs (the drive's files and a chat's, as the app's mbui player is, src/sf/player.mbt):
// a video is a video, whether a chat's recording of a screen or a film of a station's drive, and is watched both ways.
// To look closely: paused, a step to the frame before or after (the file's own frames, frames.ts: Mediabunny reads the
// file, WebCodecs decodes it; what shows paused is that frame's pixels), the time to the millisecond and which frame of
// how many at what rate (said only when the file's frames are read: never guessed), slow speeds (0.1×, 0.25×, 0.5×),
// the picture zoomed and moved (zoom.ts), a pixel's colour under the pointer, the frame saved as a PNG. Along the
// timeline (or a finger along the picture) it goes frame by frame, paused meanwhile, and plays on as it was once let
// go. To watch: opened where it was left on this device (from its start again when it was left near its end), the
// subtitle beside it (E01.srt for E01.mp4; SubRip and ASS turned into WebVTT), faster speeds, 15 s back and on, the
// folder's others of its kind as its playlist, the next one played at its end after a few seconds counted down.
// A film is shown on black, its controls a deep tint with words near white, whatever the theme; a song has no
// picture, and is on the page's own colours.
//
// A drive's file plays as it comes (file.ts `stream`: the app's service worker answers the player's ranges from
// `drive.read`), never fetched whole first; where no service worker runs the page, one of up to 200 MB is read whole
// first (its progress shown), a bigger one says it cannot be played here and offers the download. A chat's is here.
//
// With a mouse (a desktop's): the bar every file opened has along the top (ViewerBar.tsx), the controls floating over
// the foot, both gone as the pointer rests while it plays. A click plays or pauses, a double click fills the screen;
// the wheel with ⌘ or ⌃ (a trackpad's pinch) zooms round the pointer, the wheel alone moves what is zoomed in. Keys:
// Space or K plays or pauses; paused, ← → and , . step a frame (with ⇧ ten), Home and End to the first and the last;
// playing, ← → jump 15 s; J L jump 15 s; ↑ ↓ the sound; M mutes; F fills the screen; C the subtitle; ⇧N ⇧P the next
// one and the one before; + − 0 1 zoom. 选集 docks the others at the right.
//
// With a finger (a phone's): a tap brings or takes the controls, a double tap on the left or right third jumps 15 s,
// in the middle plays or pauses; held, it plays at 2× until let go; a finger along it moves through the time, down it
// closes it; two fingers zoom. Paused, its controls step frames; playing, they jump 15 s. 选集 a sheet of the page's.
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { DropdownMenu } from "radix-ui";
import { Back15, Camera, Captions, Check, ChevronLeft, ChevronRight, Close, Download, Expand, FileAudio, Forward15, Landscape, List, Pause, Play, Shrink, SkipBack, SkipForward, Volume, VolumeX } from "../icons.tsx";
import { PanelButton, PanelFoot, PanelHead, PanelRow, Tip } from "../parts.tsx";
import { Progress, WaitLine, WaitPill } from "../waiting.tsx";
import { fileSize as sizeOf } from "../fileSize.ts";
import { t } from "../i18n.ts";
import * as pageCss from "../styles/page.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import { viewerHost } from "./host.ts";
import type { Got, ViewerEntry, ViewerFile } from "./file.ts";
import { sideSubtitle } from "./names.ts";
import { REST_MS, TAP_REST_MS } from "./rest.ts";
import * as vvCss from "./media.css.ts";
import { ViewerBar, ViewerDownload, ViewerTool } from "./ViewerBar.tsx";
import { decodeText } from "./decode.ts";
import { toVtt } from "./subtitles.ts";
import { Frames, rateOf } from "./frames.ts";
import { clock, clockMs, draggedTo, playlist, SPEEDS, speedLabel } from "./playing.ts";
import { useZoom } from "./zoom.ts";
import * as css from "./Player.css.ts";

/** Without a stream, the most read whole to be played. */
const WHOLE_MAX = 200 * 1024 * 1024;
/** What 15 s back and on jump. */
const STEP = 15;
/** Without the file's own frames (not read yet, or a codec the browser cannot decode), a step is a 60th of a second. */
const GUESSED_STEP = 1 / 60;
/** At its end, the next one plays this many seconds after, counted down. */
const NEXT_S = 5;
/** Held still, a finger plays it this much faster, once it has been held this long. */
const HELD_RATE = 2;
const HOLD_MS = 500;
/** A second tap this soon after the first is a double one; what a double tap did is said this long. */
const DOUBLE_TAP_MS = 300;
const NOTE_MS = 800;
/** A finger across the whole picture moves through this much of it (all of a shorter one). */
const DRAG_SPAN = 120;
/** A finger has moved once it is this far from where it went down; down this far, it closes the player. */
const MOVED = 10;
const CLOSE_DY = 120;

type Source = { state: "opening"; got: Got | null } | { state: "ready"; url: string; streamed: boolean } | { state: "error"; message: string; save?: boolean };

/** How far ahead of what plays the file is read: this much playing time, and this much more. */
const AHEAD_S = 30;
const AHEAD_BYTES = 4 * 1024 * 1024;

function useSource(file: ViewerFile, media: React.RefObject<HTMLVideoElement | null>): Source {
  const { blob, stream } = file;
  const [source, setSource] = useState<Source>({ state: "opening", got: null });
  useEffect(() => {
    let live = true;
    let close: (() => void) | null = null;
    let url: string | null = null;
    // Here already (a chat's file a preview has fetched): played from here.
    if (blob) {
      url = URL.createObjectURL(blob);
      setSource({ state: "ready", url, streamed: false });
      return () => { if (url) URL.revokeObjectURL(url); };
    }
    setSource({ state: "opening", got: null });
    const type = file.type || (file.kind === "audio" ? "audio/mpeg" : "video/mp4");
    void (async () => {
      // Read about what is played soon, not as far as the browser would buffer (by the file's bytes a second).
      const s = stream ? await stream(type, () => {
        const v = media.current;
        if (!v || !Number.isFinite(v.duration) || v.duration <= 0) return null;
        return ((v.currentTime + AHEAD_S) / v.duration) * file.size + AHEAD_BYTES;
      }).catch(() => null) : null;
      if (s && !live) { s.close(); return; }
      if (!live) return;
      if (s) {
        close = s.close;
        setSource({ state: "ready", url: s.url, streamed: true });
        return;
      }
      if (file.size > WHOLE_MAX) {
        setSource({ state: "error", message: t("web-pages.drive.player.noStream", { size: sizeOf(WHOLE_MAX) }), save: true });
        return;
      }
      file.read({ type, onProgress: (got) => { if (live) setSource({ state: "opening", got }); } }).then((blob) => {
        if (!live) return;
        url = URL.createObjectURL(blob);
        setSource({ state: "ready", url, streamed: false });
      }, (e: unknown) => { if (live) setSource({ state: "error", message: e instanceof Error ? e.message : String(e) }); });
    })();
    return () => { live = false; close?.(); if (url) URL.revokeObjectURL(url); };
  }, [file.blob ?? file.key ?? file, file.size, file.mtime]); // eslint-disable-line react-hooks/exhaustive-deps
  return source;
}

/** The subtitle beside it, as a WebVTT file's URL (none: null). */
function useSubtitle(file: ViewerFile, siblings: readonly ViewerEntry[]): { url: string; name: string } | null {
  const name = useMemo(() => sideSubtitle(file.name, siblings.filter((e) => !e.dir).map((e) => e.name)), [file.name, siblings]);
  const side = name ? siblings.find((e) => e.name === name) : undefined;
  const [shown, setShown] = useState<{ url: string; name: string } | null>(null);
  useEffect(() => {
    setShown(null);
    const beside = file.beside;
    if (!beside || !side || side.size > 8 * 1024 * 1024) return;
    let live = true;
    let url: string | null = null;
    beside(side, "text/plain").then(async (blob) => {
      const text = decodeText(new Uint8Array(await blob.arrayBuffer())).text;
      if (!live) return;
      url = URL.createObjectURL(new Blob([toVtt(side.name, text)], { type: "text/vtt" }));
      setShown({ url, name: side.name });
    }, () => undefined);
    return () => { live = false; if (url) URL.revokeObjectURL(url); };
  }, [file.blob ?? file.key ?? file, side?.name, side?.size, side?.mtime]); // eslint-disable-line react-hooks/exhaustive-deps
  return shown;
}

/** What a finger on the picture is doing (a phone's). */
type Touch = { id: number; x: number; y: number; from: number; drag: "none" | "time" | "close" | "zoom"; held: boolean; hold: number };

/**
 * A video or a song played (file.ts): one of a station's drive (streamed, the folder's others its playlist and its
 * subtitles, where it was left kept), or a chat's file a preview has here already.
 */
export function Player({ file, siblings = [], backLabel, onBack, onGo = () => {} }: {
  file: ViewerFile; siblings?: readonly ViewerEntry[]; backLabel: string; onBack: () => void; onGo?: (name: string) => void;
}) {
  const entry = file;
  const narrow = viewerHost().useNarrow();
  const sheets = viewerHost().useSheets();
  const desk = !narrow;
  // A small window (a phone's browser, a narrow one): its controls as a phone's, the way a mouse works as it does.
  const small = useSmall();
  const compact = narrow || small;
  const audio = entry.kind === "audio";
  const picture = !audio;
  const media = useRef<HTMLVideoElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const source = useSource(file, media);
  const subtitle = useSubtitle(file, siblings);
  const place = file.usePlace();
  const root = useRef<HTMLDivElement>(null);
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState<[number, number][]>([]);
  const [waiting, setWaiting] = useState(false);
  const [rate, setRate] = useState(1);
  const [captions, setCaptions] = useState(true);
  const [full, setFull] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);
  const [volume, setVolume] = useState(heard.volume);
  const [muted, setMuted] = useState(heard.muted);
  const [listing, setListing] = useState(false);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [ended, setEnded] = useState(false);
  // Its frames: null until read (a chat's at once; a drive's once it is first paused, read as it streams), "none" when
  // the browser cannot decode them (steps then by a 60th of a second).
  const [frames, setFrames] = useState<Frames | "none" | null>(null);
  const [wantFrames, setWantFrames] = useState(!!file.blob);
  const [drawn, setDrawn] = useState(-1);
  // Where a finger (or the pointer) along the time has taken it while it is on it: paused meanwhile.
  const [scrub, setScrub] = useState<number | null>(null);
  const [held, setHeld] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [dragY, setDragY] = useState(0);
  const [pixel, setPixel] = useState<{ x: number; y: number; color: string; clientX: number; clientY: number } | null>(null);

  const list = useMemo(() => playlist(siblings, entry.kind), [siblings, entry.kind]);
  const index = list.findIndex((e) => e.name === entry.name);
  const prev = index > 0 ? list[index - 1] : undefined;
  const next = index >= 0 ? list[index + 1] : undefined;
  const many = list.length > 1;

  const decoded = frames instanceof Frames ? frames : null;
  const shown = scrub ?? time;
  const at = decoded ? decoded.at(shown) : -1;
  const still = !!decoded && (!playing || scrub !== null) && drawn === at;
  const timeRef = useRef(time);
  timeRef.current = time;
  const decodedRef = useRef(decoded);
  decodedRef.current = decoded;

  // ── the controls float, and fade ──
  const [awake, setAwake] = useState(true);
  const resting = useRef(0);
  const onControls = useRef(false);
  // The pointer on the bar along the top (with a mouse on a wide screen; ViewerBar's onHeld).
  const onBar = useRef(false);
  const wake = useCallback((ms = REST_MS) => {
    setAwake(true);
    clearTimeout(resting.current);
    // (gone only while it plays: not while it opens, nor paused)
    resting.current = window.setTimeout(() => { const v = media.current; if (!onControls.current && !onBar.current && v && !v.paused) setAwake(false); }, ms);
  }, []);
  useEffect(() => { wake(); return () => clearTimeout(resting.current); }, [wake]);
  const keep = {
    onPointerEnter: (e: React.PointerEvent) => { if (e.pointerType !== "mouse") return; onControls.current = true; clearTimeout(resting.current); setAwake(true); },
    onPointerLeave: (e: React.PointerEvent) => { if (e.pointerType !== "mouse") return; onControls.current = false; wake(); },
    onPointerDown: (e: React.PointerEvent) => { if (e.pointerType !== "mouse") wake(TAP_REST_MS); },
  };
  const say = useCallback((words: string) => {
    setNote(words);
    window.setTimeout(() => setNote((n) => (n === words ? null : n)), NOTE_MS);
  }, []);

  // ── where it was left ──
  const resumed = useRef(false);
  const lastKept = useRef(0);
  const keepPlace = useCallback(() => {
    const v = media.current;
    if (!v || !resumed.current || !Number.isFinite(v.duration) || v.duration <= 0) return;
    file.keepPlace(v.currentTime * 1000, v.duration * 1000);
  }, [file]);
  useEffect(() => () => keepPlace(), [keepPlace]);
  useEffect(() => {
    const away = () => keepPlace();
    addEventListener("pagehide", away);
    return () => removeEventListener("pagehide", away);
  }, [keepPlace]);
  const resume = useCallback(() => {
    const v = media.current;
    if (!v || resumed.current || place === undefined || !Number.isFinite(v.duration)) return;
    resumed.current = true;
    const s = (place?.at ?? 0) / 1000;
    // Near its end it starts again; near its start it starts there anyway.
    if (s > 5 && s < v.duration - 5) v.currentTime = s;
    void v.play().catch(() => undefined);
  }, [place]);
  useEffect(() => { if (duration > 0) resume(); }, [duration, resume]);

  // ── its frames ──
  useEffect(() => {
    if (!picture || !wantFrames || source.state !== "ready" || frames !== null) return;
    let live = true;
    Frames.open(file.blob ?? source.url).then((f) => {
      if (live) setFrames(f ?? "none"); else f?.dispose();
    }, (e: unknown) => {
      console.warn("video frames:", e);
      if (live) setFrames("none");
    });
    return () => { live = false; };
  }, [picture, wantFrames, source, file.blob]); // eslint-disable-line react-hooks/exhaustive-deps
  // (those read let go with the player, or when others are read in their place)
  useEffect(() => () => { if (frames instanceof Frames) frames.dispose(); }, [frames]);

  // Playing, the time is the frame the video shows (not its clock, which runs between frames).
  useEffect(() => {
    const v = media.current;
    if (!v || !("requestVideoFrameCallback" in v)) return;
    let id = 0;
    const tick = (_: number, meta: VideoFrameCallbackMetadata) => {
      // Paused, the file's frames say where it is: a frame the video shows late (as it stops) must not move it back.
      if (!v.paused || !decodedRef.current) setTime(meta.mediaTime);
      id = v.requestVideoFrameCallback(tick);
    };
    id = v.requestVideoFrameCallback(tick);
    return () => v.cancelVideoFrameCallback(id);
  }, [source]);

  // Paused (or moved through), the frame is drawn from the file, each as it comes though another was asked for since:
  // dragging along the timeline, the picture follows as fast as the frames are decoded. What is drawn stays until the
  // next is, and goes as it plays again.
  const drawing = useRef({ live: false });
  const looking = picture && (!playing || scrub !== null);
  useEffect(() => {
    if (!decoded || !looking) return;
    const d = { live: true };
    drawing.current = d;
    return () => { d.live = false; setDrawn(-1); };
  }, [decoded, looking]);
  useEffect(() => {
    if (!decoded || !looking || at < 0) return;
    const d = drawing.current;
    decoded.get(at).then((frame) => {
      const el = canvas.current;
      if (!d.live || !frame || !el) return;
      if (el.width !== frame.width || el.height !== frame.height) { el.width = frame.width; el.height = frame.height; }
      el.getContext("2d", { willReadFrequently: true })!.drawImage(frame, 0, 0);
      setDrawn(at);
    }, (e: unknown) => console.warn("video frame:", e));
  }, [decoded, looking, at]);

  // ── doing ──
  const toggle = useCallback(() => {
    const v = media.current;
    if (!v) return;
    if (!v.paused) { v.pause(); return; }
    const d = decodedRef.current;
    if (v.ended || (d && d.at(timeRef.current) >= d.starts.length - 1)) v.currentTime = 0;
    // From the frame stepped to (the video itself was left where it paused).
    else if (d) v.currentTime = d.starts[d.at(timeRef.current)]! + 1e-4;
    void v.play().catch(() => undefined);
    wake();
  }, [wake]);
  /** Paused, to the frame `to` makes of the one shown (without the file's frames, steps of a 60th of a second). */
  const go = useCallback((to: (current: number) => number) => {
    const v = media.current;
    if (!v) return;
    if (!v.paused) v.pause();
    setWantFrames(true);
    const d = decodedRef.current;
    if (d) setTime(d.starts[Math.max(0, Math.min(d.starts.length - 1, to(d.at(timeRef.current))))]!);
    else v.currentTime = Math.max(0, Math.min(v.duration || 0, to(Math.round(v.currentTime / GUESSED_STEP)) * GUESSED_STEP));
    wake();
  }, [wake]);
  const step = useCallback((by: number) => go((i) => i + by), [go]);
  const seek = useCallback((to: number) => {
    const v = media.current;
    if (!v || !Number.isFinite(v.duration)) return;
    const s = Math.max(0, Math.min(v.duration - 0.1, to));
    v.currentTime = s;
    const d = decodedRef.current;
    setTime(d && v.paused ? d.starts[d.at(s)]! : s);
    wake();
  }, [wake]);
  const by = useCallback((s: number) => seek(timeRef.current + s), [seek]);
  // A finger (or the pointer) along the time: paused while it is on it, the picture going to the start of each frame
  // it comes to; let go, there, played again if it played when it came.
  const scrubbing = useRef<{ played: boolean; to: number } | null>(null);
  const scrubTo = useCallback((s: number) => {
    const v = media.current;
    if (!v) return;
    if (!scrubbing.current) {
      scrubbing.current = { played: !v.paused, to: s };
      v.pause();
      setWantFrames(true);
    }
    const d = decodedRef.current;
    const to = d ? d.starts[d.at(s)]! : s;
    scrubbing.current.to = to;
    setScrub(to);
    // (without the file's frames, the video goes there as the browser can)
    if (!d) v.currentTime = to;
    wake();
  }, [wake]);
  const scrubDone = useCallback(() => {
    const sc = scrubbing.current;
    scrubbing.current = null;
    setScrub(null);
    const v = media.current;
    if (!sc || !v) return;
    setTime(sc.to);
    v.currentTime = sc.to + (decodedRef.current ? 1e-4 : 0);
    if (sc.played) void v.play().catch(() => undefined);
    wake();
  }, [wake]);
  const turn = useCallback(async () => {
    const el = root.current, v = media.current as (HTMLVideoElement & { webkitEnterFullscreen?: () => void }) | null;
    if (document.fullscreenElement) { await document.exitFullscreen().catch(() => undefined); return; }
    if (el?.requestFullscreen && document.fullscreenEnabled) {
      await el.requestFullscreen({ navigationUI: "hide" }).catch(() => undefined);
      // A phone turned sideways with it, where a page may lock the screen's turning (Android's browsers).
      if (narrow) await (screen.orientation as Turnable | undefined)?.lock?.("landscape").catch(() => undefined);
      return;
    }
    // iPhone Safari: only the video itself, in the system's player.
    v?.webkitEnterFullscreen?.();
  }, [narrow]);
  useEffect(() => {
    const on = () => {
      const now = !!root.current && document.fullscreenElement === root.current;
      setFull(now);
      if (!now) (screen.orientation as Turnable | undefined)?.unlock?.();
    };
    document.addEventListener("fullscreenchange", on);
    return () => document.removeEventListener("fullscreenchange", on);
  }, []);
  useEffect(() => { if (media.current) media.current.playbackRate = held ? HELD_RATE : rate; }, [rate, held, source]);
  // How loud, kept for the next one played while the page is open.
  useEffect(() => {
    heard.volume = volume; heard.muted = muted;
    if (media.current) { media.current.volume = volume; media.current.muted = muted; }
  }, [volume, muted, source]);
  const louder = useCallback((d: number) => { setMuted(false); setVolume((v) => Math.min(1, Math.max(0, Math.round((v + d) * 20) / 20))); }, []);
  // The subtitle's lines drawn here, not by the browser: above the controls while they show, lower when they fade.
  const [cue, setCue] = useState<string | null>(null);
  useEffect(() => {
    const track = media.current?.textTracks[0];
    if (!track) { setCue(null); return; }
    track.mode = "hidden";
    const change = () => setCue([...(track.activeCues ?? [])].map((c) => (c as VTTCue).text).join("\n") || null);
    track.addEventListener("cuechange", change);
    change();
    return () => track.removeEventListener("cuechange", change);
  }, [subtitle, source]);

  /** The frame shown saved as a PNG, named by the frame it is: the file's own when read, else what the video shows. */
  const save = useCallback(() => {
    const v = media.current;
    let from: HTMLCanvasElement | null = still ? canvas.current : null;
    if (!from && v && v.videoWidth > 0) {
      from = document.createElement("canvas");
      from.width = v.videoWidth; from.height = v.videoHeight;
      from.getContext("2d")!.drawImage(v, 0, 0);
    }
    const frame = decoded ? at + 1 : Math.round(shown / GUESSED_STEP) + 1;
    from?.toBlob((png) => {
      if (!png) return;
      const a = document.createElement("a");
      a.href = URL.createObjectURL(png);
      a.download = `${entry.name.replace(/\.[^.]+$/, "")}-${frame}.png`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    }, "image/png");
  }, [still, decoded, at, shown, entry.name]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || (e.target as Element | null)?.closest?.("input, textarea, [role=menu]")) return;
      const paused = !!media.current?.paused;
      const frames10 = e.shiftKey ? 10 : 1;
      if (e.key === " " || e.key === "k") toggle();
      else if (e.key === "," && picture) step(-frames10);
      else if (e.key === "." && picture) step(frames10);
      else if (e.key === "ArrowLeft") { if (paused && picture) step(-frames10); else by(-STEP); }
      else if (e.key === "ArrowRight") { if (paused && picture) step(frames10); else by(STEP); }
      else if (e.key === "Home" && paused && picture) go(() => 0);
      else if (e.key === "End" && paused && picture) go(() => Infinity);
      else if (e.key === "j") by(-STEP);
      else if (e.key === "l") by(STEP);
      else if (e.key === "f" && picture) void turn();
      else if (e.key === "m") setMuted((m) => !m);
      else if (e.key === "ArrowUp" && desk) louder(0.05);
      else if (e.key === "ArrowDown" && desk) louder(-0.05);
      else if (e.key === "c" && subtitle) setCaptions((c) => !c);
      else if (e.key === "N" && next) onGo(next.name);
      else if (e.key === "P" && prev) onGo(prev.name);
      else return;
      e.preventDefault();
      wake();
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [toggle, step, go, by, turn, wake, subtitle, next, prev, onGo, desk, louder, picture]);

  const readBuffered = () => {
    const v = media.current;
    if (!v) return;
    const out: [number, number][] = [];
    for (let i = 0; i < v.buffered.length; i++) out.push([v.buffered.start(i), v.buffered.end(i)]);
    setBuffered(out);
  };

  // ── the picture: zoomed and moved, a finger's gestures ──
  // (a film edge to edge, enlarged as players show one, under the bars that float over it)
  const zoom = useZoom(picture ? natural : null, { margin: () => 0, enlarge: true, doubleClick: false, floats: false });
  const touch = useRef<Touch | null>(null);
  const fingers = useRef(0);
  // A mouse's press: where, to tell a click (plays or pauses) from a drag (moves what is zoomed in).
  const pressed = useRef<{ x: number; y: number; mouse: boolean } | null>(null);
  const lastTap = useRef<{ at: number; x: number } | null>(null);
  const tapWait = useRef(0);
  useEffect(() => () => { clearTimeout(tapWait.current); if (touch.current) clearTimeout(touch.current.hold); }, []);
  const tapped = (x: number, width: number) => {
    const before = lastTap.current;
    const now = performance.now();
    if (before && now - before.at < DOUBLE_TAP_MS) {
      // a double tap: a side's 15 s, the middle plays or pauses
      clearTimeout(tapWait.current);
      lastTap.current = null;
      const third = x < width / 3 ? -1 : x > (width * 2) / 3 ? 1 : 0;
      if (third < 0) { by(-STEP); say(t("web-pages.drive.player.back15")); }
      else if (third > 0) { by(STEP); say(t("web-pages.drive.player.forward15")); }
      else { say(media.current?.paused ? t("web-pages.drive.player.playing") : t("web-pages.drive.player.paused")); toggle(); }
      return;
    }
    // a single one, once no second comes: the controls shown or hidden
    lastTap.current = { at: now, x };
    clearTimeout(tapWait.current);
    tapWait.current = window.setTimeout(() => {
      lastTap.current = null;
      if (awake && media.current && !media.current.paused) { clearTimeout(resting.current); setAwake(false); } else wake(TAP_REST_MS);
    }, DOUBLE_TAP_MS);
  };
  const stageDown = (e: React.PointerEvent<HTMLDivElement>) => {
    pressed.current = { x: e.clientX, y: e.clientY, mouse: e.pointerType === "mouse" };
    fingers.current += e.pointerType === "touch" ? 1 : 0;
    if (e.pointerType !== "touch" || !picture) { zoom.stageProps.onPointerDown(e); return; }
    // two fingers, or zoomed in: the zoom's (a pinch, the picture moved)
    if (fingers.current > 1 || zoom.zoomed) {
      if (touch.current) { clearTimeout(touch.current.hold); if (touch.current.drag === "time") scrubDone(); touch.current = null; }
      zoom.stageProps.onPointerDown(e);
      return;
    }
    e.currentTarget.setPointerCapture(e.pointerId);
    const tc: Touch = { id: e.pointerId, x: e.clientX, y: e.clientY, from: timeRef.current, drag: "none", held: false, hold: 0 };
    // held still while it plays: 2× until let go
    tc.hold = window.setTimeout(() => {
      if (touch.current !== tc || tc.drag !== "none" || !media.current || media.current.paused) return;
      tc.held = true;
      setHeld(true);
    }, HOLD_MS);
    touch.current = tc;
    zoom.stageProps.onPointerDown(e);
  };
  const stageMove = (e: React.PointerEvent<HTMLDivElement>) => {
    const tc = touch.current;
    if (!tc || tc.id !== e.pointerId) { zoom.stageProps.onPointerMove(e); onPixel(e); return; }
    const dx = e.clientX - tc.x, dy = e.clientY - tc.y;
    if (tc.drag === "none" && !tc.held && Math.hypot(dx, dy) > MOVED) {
      clearTimeout(tc.hold);
      tc.drag = Math.abs(dx) > Math.abs(dy) && duration > 0 ? "time" : dy > 0 ? "close" : "zoom";
      wake();
    }
    if (tc.drag === "time") scrubTo(draggedTo(tc.from, dx, e.currentTarget.clientWidth, duration, DRAG_SPAN));
    else if (tc.drag === "close") setDragY(Math.max(0, dy));
    else if (tc.drag === "zoom") zoom.stageProps.onPointerMove(e);
  };
  const stageUp = (e: React.PointerEvent<HTMLDivElement>) => {
    fingers.current = Math.max(0, fingers.current - (e.pointerType === "touch" ? 1 : 0));
    zoom.stageProps.onPointerUp(e);
    const tc = touch.current;
    if (!tc || tc.id !== e.pointerId) return;
    touch.current = null;
    clearTimeout(tc.hold);
    if (tc.held) { setHeld(false); return; }
    if (tc.drag === "time") scrubDone();
    else if (tc.drag === "close") {
      setDragY(0);
      if (e.type === "pointerup" && e.clientY - tc.y > CLOSE_DY) { if (full) void turn(); else onBack(); }
    } else if (tc.drag === "none" && e.type === "pointerup") tapped(e.clientX - e.currentTarget.getBoundingClientRect().left, e.currentTarget.clientWidth);
  };
  // With a mouse over a frame of the file's own, paused: the colour of the pixel under the pointer.
  const onPixel = (e: React.PointerEvent) => {
    const el = canvas.current;
    if (!still || !el || e.pointerType !== "mouse") { if (pixel) setPixel(null); return; }
    const r = el.getBoundingClientRect();
    const x = Math.floor(((e.clientX - r.left) / r.width) * el.width), y = Math.floor(((e.clientY - r.top) / r.height) * el.height);
    if (x < 0 || y < 0 || x >= el.width || y >= el.height) { setPixel(null); return; }
    const [red, green, blue] = el.getContext("2d", { willReadFrequently: true })!.getImageData(x, y, 1, 1).data;
    setPixel({ x, y, clientX: e.clientX, clientY: e.clientY, color: `#${[red!, green!, blue!].map((c) => c.toString(16).padStart(2, "0")).join("").toUpperCase()}` });
  };

  // ── at its end ──
  const [nextOff, setNextOff] = useState<string | null>(null);
  const offering = ended && !!next && nextOff !== next.name;
  const [left, setLeft] = useState(NEXT_S);
  const goRef = useRef(onGo);
  goRef.current = onGo;
  const nextName = next?.name;
  useEffect(() => {
    if (!offering || !nextName) return;
    setLeft(NEXT_S);
    let n = NEXT_S;
    const id = window.setInterval(() => {
      n -= 1;
      if (n > 0) { setLeft(n); return; }
      clearInterval(id);
      goRef.current(nextName);
    }, 1000);
    return () => clearInterval(id);
  }, [offering, nextName]);

  let body: ReactNode;
  if (source.state === "error" || failed) {
    body = (
      <div className={css.note}>
        <span>{failed ?? (source.state === "error" ? source.message : "")}</span>
        {source.state === "error" && source.save && <button type="button" className={css.noteButton} onClick={file.save}><Download size={16} />{t("web-pages.drive.download")}</button>}
      </div>
    );
  } else if (source.state === "opening") {
    body = (
      <div className={css.note}>
        {source.got
          ? <><span>{t("web-pages.drive.reader.reading", { got: sizeOf(source.got.loaded), of: sizeOf(source.got.total) })}</span>
            <Progress part={source.got.total > 0 ? source.got.loaded / source.got.total : null} label={t("common.reading")} className={css.noteBar} /></>
          : <WaitLine text={t("common.opening")} />}
      </div>
    );
  } else {
    // (zoomed in past fitted, each of its pixels a sharp square; a film enlarged to fit is drawn smooth)
    const pixelated = (picture && zoom.zoomed && zoom.scale >= 2) || undefined;
    body = (
      <>
        <video ref={media} className={picture ? vvCss.vvPicture : css.media} data-audio={audio || undefined} data-pixelated={pixelated} src={source.url} playsInline preload="metadata"
          data-viewer-picture={picture ? "" : undefined} style={picture ? zoom.place ?? { visibility: "hidden" } : undefined}
          onLoadedMetadata={(e) => { const v = e.currentTarget; setDuration(v.duration); setFailed(null); if (v.videoWidth > 0) setNatural({ w: v.videoWidth, h: v.videoHeight }); }}
          onDurationChange={(e) => setDuration(e.currentTarget.duration)}
          onTimeUpdate={(e) => {
            const v = e.currentTarget;
            if (!v.paused || !decodedRef.current) { if (!scrubbing.current) setTime(v.currentTime); }
            if (Math.abs(v.currentTime * 1000 - lastKept.current) > 5000) { lastKept.current = v.currentTime * 1000; keepPlace(); }
          }}
          onSeeked={(e) => { readBuffered(); if (!decodedRef.current && !scrubbing.current) setTime(e.currentTarget.currentTime); }}
          onProgress={readBuffered}
          onPlay={() => { setPlaying(true); setEnded(false); wake(); }}
          onPause={() => { setPlaying(false); setAwake(true); keepPlace(); if (!scrubbing.current) setWantFrames(true); }}
          onWaiting={() => setWaiting(true)} onPlaying={() => setWaiting(false)} onCanPlay={() => setWaiting(false)}
          onEnded={() => { keepPlace(); setEnded(true); setAwake(true); }}
          onError={(e) => setFailed(t("web-pages.drive.player.failed", { error: e.currentTarget.error?.message || String(e.currentTarget.error?.code ?? "") }))}>
          {subtitle && <track kind="subtitles" src={subtitle.url} label={subtitle.name} default />}
        </video>
        {picture && <canvas ref={canvas} className={vvCss.vvPicture} data-pixelated={pixelated} aria-label={decoded ? t("web-main.video.frame", { n: at + 1 }) : undefined}
          style={{ ...(zoom.place ?? {}), visibility: (!playing || scrub !== null) && drawn >= 0 && zoom.place ? "visible" : "hidden" }} />}
      </>
    );
  }

  // What is said of where it is: playing (and a song, and a film not ready) the time of how long; paused or moved
  // through, the time to the millisecond, with the file's frames which frame of how many at what rate.
  const count = decoded?.starts.length ?? 0;
  const rateInfo = useMemo(() => (decoded ? rateOf(decoded.starts) : null), [decoded]);
  const fps = rateInfo && rateInfo.fps > 0 ? (rateInfo.steady ? `${Math.round(rateInfo.fps)} fps` : t("web-main.video.variableRate", { fps: Math.round(rateInfo.fps) })) : null;
  const close = picture && duration > 0 && (!playing || scrub !== null);
  // (paused, its controls step frames; a finger along the time leaves them as they were: it plays on as it did)
  const willPlay = scrubbing.current ? scrubbing.current.played : playing;
  const inspect = picture && duration > 0 && !willPlay;
  const where = close && decoded
    ? <><b className={vvCss.vvNow}>{clockMs(decoded.starts[at]!)}</b><span className={vvCss.vvDim}> · {at + 1} / {t("web-main.video.frames", { n: count })}{fps ? ` · ${fps}` : ""}</span></>
    : <><b className={vvCss.vvNow}>{close ? clockMs(shown) : clock(shown)}</b><span className={vvCss.vvDim}> / {duration > 0 ? clock(duration) : "--:--"}</span></>;
  const end = decoded ? decoded.end : duration;
  const meta = [
    many && index >= 0 ? `${index + 1} / ${list.length}` : null,
    sizeOf(entry.size),
    natural ? `${natural.w}×${natural.h}` : null,
    picture && end > 0 ? clock(end) : null,
    fps,
  ].filter(Boolean).join(" · ");
  const said = note ?? (held ? t("web-pages.drive.player.held") : touch.current?.drag === "time" && scrub !== null ? `${clock(scrub)} / ${clock(duration)}` : null);
  const pick = (other: string) => { media.current?.pause(); onGo(other); };
  const openList = () => {
    if (desk) { setListing((l) => !l); return; }
    sheets?.({
      height: 0.6, title: t("web-pages.drive.player.list"),
      trailing: () => <>{index + 1} / {list.length}</>,
      body: (done) => <ListRows list={list} index={index} playing={playing} onPick={(n) => { done(); if (n !== entry.name) pick(n); }} />,
    });
  };
  // Beside the pointer, on the side with room.
  const pixelLeft = pixel && pixel.clientX > window.innerWidth - 220;

  return (
    <div ref={root} className={`${vvCss.vv} ${css.player}`} data-narrow={narrow || undefined} data-film={picture || undefined}
      data-list={(desk && listing && many) || undefined} data-viewer-ground="" data-zoom-root=""
      onPointerMove={(e) => { if (e.pointerType === "mouse") wake(); }}
      onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; clearTimeout(resting.current); setPixel(null); if (!onControls.current && !onBar.current && playing) setAwake(false); }}>
      <div ref={zoom.stage} className={css.stage} data-viewer-stage="" {...zoom.stageProps}
        style={dragY ? { transform: `translateY(${dragY}px)`, opacity: Math.max(0.4, 1 - dragY / 600) } : undefined}
        onPointerDown={stageDown} onPointerMove={stageMove} onPointerUp={stageUp} onPointerCancel={stageUp}
        onClick={(e) => {
          const p = pressed.current;
          if (desk && e.button === 0 && p?.mouse && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 4) toggle();
        }}
        onDoubleClick={() => { if (desk && picture) void turn(); }}>
        {audio && source.state === "ready" && <div className={css.cover}><FileAudio size={72} strokeWidth={1.2} /><span>{entry.name}</span></div>}
        {body}
        {waiting && source.state === "ready" && !failed && <WaitPill over text={t("web-pages.drive.player.buffering")} />}
      </div>
      {pixel && (
        <span className={vvCss.vvPixel} style={{ top: pixel.clientY + 16, ...(pixelLeft ? { right: window.innerWidth - pixel.clientX + 12 } : { left: pixel.clientX + 16 }) }}>
          <span className={vvCss.vvSwatch} style={{ background: pixel.color }} />{pixel.color}<span className={vvCss.vvDim}>{pixel.x}, {pixel.y}</span>
        </span>
      )}
      {said && <div className={css.said}><span>{said}</span></div>}
      {captions && cue && <div className={css.cue} data-awake={awake || undefined}><span>{cue.replace(/<[^>]+>/g, "")}</span></div>}
      {offering && next && (
        <div className={`${controlsCss.popover} ${css.ended}`} role="status">
          <PanelHead title={t("web-pages.drive.player.ended")} note={t("web-pages.drive.player.nextIn", { n: left })} />
          <PanelRow icon={<SkipForward size={16} />} label={t("web-pages.drive.player.nextOne", { name: next.name })} onClick={() => { setNextOff(next.name); pick(next.name); }} />
          <PanelFoot><PanelButton tone="quiet" onClick={() => setNextOff(next.name)}>{t("common.cancel")}</PanelButton></PanelFoot>
        </div>
      )}
      {desk && !full ? (
        <ViewerBar back={{ label: backLabel, onClick: onBack }} name={entry.name} title={file.title} hidden={!awake && !listing}
          onHeld={(on) => { onBar.current = on; if (on) { clearTimeout(resting.current); setAwake(true); } else wake(); }}
          meta={meta}
          tools={<>
            {many && <ViewerTool label={t("web-pages.drive.player.list")} on={listing} onClick={openList}><List size={18} /></ViewerTool>}
            <ViewerDownload name={entry.name} onSave={file.save} />
          </>} />
      ) : (
        <header className={css.head} data-awake={awake || undefined} {...keep}>
          <Tip label={backLabel}><button type="button" className={`${pageCss.iconBtn} ${css.bright}`} aria-label={backLabel} onClick={() => { if (full) void turn(); else onBack(); }}><ChevronLeft size={20} /></button></Tip>
          <span className={css.name}><b>{entry.name}</b>{many && index >= 0 && <small>{index + 1} / {list.length}</small>}</span>
          {many && sheets && <Tip label={t("web-pages.drive.player.list")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.drive.player.list")} onClick={openList}><List size={18} /></button></Tip>}
          <Tip label={t("web-pages.drive.download")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.drive.download")} onClick={file.save}><Download size={18} /></button></Tip>
        </header>
      )}
      {desk && listing && many && (
        <aside className={css.list}>
          <div className={css.listHead}>
            <b>{t("web-pages.drive.player.list")}</b><small>{index + 1} / {list.length}</small>
            <Tip label={t("common.close")}><button type="button" className={pageCss.iconBtn} aria-label={t("common.close")} onClick={() => setListing(false)}><Close size={16} /></button></Tip>
          </div>
          <ListRows list={list} index={index} playing={playing} onPick={(n) => { if (n !== entry.name) pick(n); }} />
        </aside>
      )}
      <div className={vvCss.vvBar} data-floats data-awake={awake || source.state !== "ready" || undefined} {...keep}>
        {/* On a phone the time goes over the timeline: the buttons take the row. */}
        <span className={css.timeTop}>{where}</span>
        <Timeline duration={duration} now={shown} buffered={buffered} onScrub={scrubTo} onDone={scrubDone} />
        <div className={vvCss.vvRow}>
          <span className={vvCss.vvGroup}>
            {many && <Key label={t("web-pages.drive.player.prev")} disabled={!prev} onClick={() => prev && pick(prev.name)}><SkipBack size={18} /></Key>}
            {(!compact || !inspect) && <Key label={t("web-pages.drive.player.back15")} onClick={() => by(-STEP)}><Back15 size={20} /></Key>}
            {picture && (!compact || inspect) && <Key label={t("web-main.video.prev")} tip={t("web-main.video.prevKey")} disabled={duration <= 0} onClick={() => step(-1)}><ChevronLeft size={18} /></Key>}
            <Key label={playing ? t("web-main.video.pause") : t("web-main.video.play")} tip={playing ? t("web-main.video.pauseKey") : t("web-main.video.playKey")} bright onClick={toggle}>
              {playing ? <Pause size={20} /> : <Play size={20} />}
            </Key>
            {picture && (!compact || inspect) && <Key label={t("web-main.video.next")} tip={t("web-main.video.nextKey")} disabled={duration <= 0} onClick={() => step(1)}><ChevronRight size={18} /></Key>}
            {(!compact || !inspect) && <Key label={t("web-pages.drive.player.forward15")} onClick={() => by(STEP)}><Forward15 size={20} /></Key>}
            {many && <Key label={t("web-pages.drive.player.next")} disabled={!next} onClick={() => next && pick(next.name)}><SkipForward size={18} /></Key>}
          </span>
          <span className={`${vvCss.vvInfo} ${css.timeRow}`}><span className={vvCss.vvFact}>{where}</span></span>
          <span className={vvCss.vvGroup}>
            {!compact && <VolumeControl volume={volume} muted={muted} onVolume={(v) => { setVolume(v); setMuted(v === 0); }} onMute={() => setMuted((m) => !m)} />}
            <SpeedMenu rate={rate} onRate={setRate} container={root.current} />
            {subtitle && <Key label={t("web-pages.drive.player.captions")} tip={captions ? t("web-pages.drive.player.captionsOff") : t("web-pages.drive.player.captionsOn")} pressed={captions} onClick={() => setCaptions((c) => !c)}><Captions size={18} /></Key>}
            {picture && inspect && <Key label={t("web-main.video.save")} tip={t("web-main.video.saveTip")} onClick={save}><Camera size={18} /></Key>}
            {picture && (desk
              ? <Key label={full ? t("web-pages.drive.player.unfull") : t("web-pages.drive.player.full")} onClick={() => void turn()}>{full ? <Shrink size={18} /> : <Expand size={18} />}</Key>
              : <Key label={full ? t("web-main.video.unturn") : t("web-main.video.turn")} pressed={full} onClick={() => void turn()}><Landscape size={18} /></Key>)}
          </span>
        </div>
      </div>
    </div>
  );
}

/** Whether the window is a phone's size (640 or narrower), told again as it changes. */
function useSmall(): boolean {
  const query = "(max-width: 640px)";
  const [small, setSmall] = useState(() => typeof matchMedia === "function" && matchMedia(query).matches);
  useEffect(() => {
    if (typeof matchMedia !== "function") return;
    const q = matchMedia(query);
    const on = () => setSmall(q.matches);
    on();
    q.addEventListener("change", on);
    return () => q.removeEventListener("change", on);
  }, []);
  return small;
}

/** The screen's turning locked (only where a page may: Android's browsers, in full screen; not iOS's). */
type Turnable = ScreenOrientation & { lock?(orientation: "landscape"): Promise<void>; unlock?(): void };

/** One of the controls' buttons, named on hover (`tip`: with its key). */
function Key({ label, tip, disabled, pressed, bright, onClick, children }: { label: string; tip?: string; disabled?: boolean; pressed?: boolean; bright?: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <Tip label={tip ?? label}>
      <button type="button" className={bright ? `${pageCss.iconBtn} ${css.bright}` : pageCss.iconBtn} aria-label={label} aria-pressed={pressed} disabled={disabled} onClick={onClick}>{children}</button>
    </Tip>
  );
}

/** The folder's others, numbered, the one playing marked; one picked plays. */
function ListRows({ list, index, playing, onPick }: { list: readonly ViewerEntry[]; index: number; playing: boolean; onPick: (name: string) => void }) {
  return (
    <div className={css.listRows}>
      {list.map((e, i) => (
        <button key={e.name} type="button" className={css.listRow} data-current={i === index || undefined} onClick={() => onPick(e.name)}>
          <small>{i + 1}</small><span>{e.name}</span>{i === index && (playing ? <Play size={14} /> : <Check size={14} />)}
        </button>
      ))}
    </div>
  );
}

/** The speed as a figure, its speeds a menu: slow ones to look closely, fast ones to get through. */
function SpeedMenu({ rate, onRate, container }: { rate: number; onRate: (rate: number) => void; container: HTMLElement | null }) {
  return (
    <DropdownMenu.Root modal={false}>
      <Tip label={t("web-pages.drive.player.rate")}>
        <DropdownMenu.Trigger asChild><button type="button" className={vvCss.vvRate} aria-label={t("web-pages.drive.player.rate")}>{speedLabel(rate)}</button></DropdownMenu.Trigger>
      </Tip>
      <DropdownMenu.Portal container={container}>
        <DropdownMenu.Content className={`${controlsCss.popover} ${css.speeds}`} side="top" align="end" sideOffset={8} collisionPadding={8}>
          <DropdownMenu.RadioGroup value={String(rate)} onValueChange={(v) => onRate(Number(v))}>
            {SPEEDS.map((s) => (
              <DropdownMenu.RadioItem key={s} value={String(s)} className={`${controlsCss.menuItem} ${css.speed}`}>
                <span>{speedLabel(s)}</span>
                <DropdownMenu.ItemIndicator><Check size={14} /></DropdownMenu.ItemIndicator>
              </DropdownMenu.RadioItem>
            ))}
          </DropdownMenu.RadioGroup>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** How loud, for the next played as for this one while the page is open. */
const heard = { volume: 1, muted: false };

/** The sound: a button that mutes, and beside it a line to drag (wider while pointed at). */
function VolumeControl({ volume, muted, onVolume, onMute }: { volume: number; muted: boolean; onVolume: (v: number) => void; onMute: () => void }) {
  const box = useRef<HTMLSpanElement>(null);
  const [drag, setDrag] = useState<number | null>(null);
  const at = (x: number) => {
    const r = box.current!.getBoundingClientRect();
    return Math.round(Math.min(1, Math.max(0, (x - r.left) / r.width)) * 20) / 20;
  };
  const shown = drag ?? (muted ? 0 : volume);
  const silent = muted || volume === 0;
  return (
    <span className={css.volume}>
      <Tip label={silent ? t("web-pages.drive.player.unmute") : t("web-pages.drive.player.mute")}>
        <button type="button" className={pageCss.iconBtn} aria-label={silent ? t("web-pages.drive.player.unmute") : t("web-pages.drive.player.mute")} onClick={onMute}>
          {silent ? <VolumeX size={18} /> : <Volume size={18} />}
        </button>
      </Tip>
      <span ref={box} className={css.volumeLine} role="slider" aria-label={t("web-pages.drive.player.volume")} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(shown * 100)} tabIndex={0}
        onPointerDown={(e) => { if (e.button !== 0) return; e.currentTarget.setPointerCapture(e.pointerId); const v = at(e.clientX); setDrag(v); onVolume(v); }}
        onPointerMove={(e) => { if (drag === null) return; const v = at(e.clientX); setDrag(v); onVolume(v); }}
        onPointerUp={() => setDrag(null)} onPointerCancel={() => setDrag(null)}>
        <span className={css.volumeTrack}><span style={{ transform: `scaleX(${shown})` }} /></span>
        <span className={vvCss.vvHeadRail} style={{ transform: `translateX(${shown * 100}%)` }}><span className={css.volumeHead} /></span>
      </span>
    </span>
  );
}

/** Where in it it is, to click or drag to a place (the picture going with the pointer, `onScrub`, until `onDone`); what
 *  has come so far a lighter band; with a mouse over it, the time where it points. */
function Timeline({ duration, now, buffered, onScrub, onDone }: { duration: number; now: number; buffered: [number, number][]; onScrub: (time: number) => void; onDone: () => void }) {
  const box = useRef<HTMLDivElement>(null);
  const span = duration > 0 && Number.isFinite(duration) ? duration : 0;
  const dragging = useRef(false);
  const [over, setOver] = useState<number | null>(null);
  const at = (x: number) => {
    const r = box.current!.getBoundingClientRect();
    return Math.min(1, Math.max(0, (x - r.left) / r.width)) * span;
  };
  const share = span ? Math.min(1, Math.max(0, now / span)) : 0;
  const pointed = dragging.current ? now : over;
  const done = () => { if (!dragging.current) return; dragging.current = false; onDone(); };
  return (
    <div ref={box} className={vvCss.vvTimeline} role="slider" aria-label={t("web-main.video.position")} aria-valuemin={0} aria-valuemax={Math.round(span * 1000)}
      aria-valuenow={Math.round(now * 1000)} aria-valuetext={clock(now)}
      onPointerDown={(e) => { if (e.button !== 0 || !span) return; e.currentTarget.setPointerCapture(e.pointerId); dragging.current = true; onScrub(at(e.clientX)); }}
      onPointerMove={(e) => { if (dragging.current) onScrub(at(e.clientX)); if (e.pointerType === "mouse" && span) setOver(at(e.clientX)); }}
      onPointerLeave={() => setOver(null)}
      onPointerUp={(e) => { if (dragging.current) onScrub(at(e.clientX)); done(); }}
      onPointerCancel={done}>
      <span className={vvCss.vvTrack}>
        {span > 0 && buffered.map(([a, b], i) => <span key={i} className={css.buffered} style={{ left: `${(a / span) * 100}%`, width: `${((b - a) / span) * 100}%` }} />)}
        <span className={vvCss.vvPlayed} style={{ transform: `scaleX(${share})` }} />
      </span>
      <span className={vvCss.vvHeadRail} style={{ transform: `translateX(${share * 100}%)` }}><span className={vvCss.vvHead} /></span>
      {pointed !== null && span > 0 && <span className={css.pointed} style={{ left: `${(pointed / span) * 100}%` }}>{clock(pointed)}</span>}
    </div>
  );
}
