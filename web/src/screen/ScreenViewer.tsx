// One of a station's screens (its desktop, a tab of its browser: docs/remote-screens.md), seen and driven in the app.
// The core opens the view (`screen.view`) and says how it is (its `state`: connecting, live, again, over and why;
// 只看 or 控制, who else is on it); its frames are drawn here outside React (frames.ts), and what is done over the
// picture goes back as the core takes it (input.ts). Nothing here is drawn again per frame: the picture, its place and
// the station's pointer are written straight into the page.
//
// With a mouse it is a file opened's page: the bar along the top (the way back, the screen's name, what the core says
// of the view and of the connection, 只看/控制, a window of its own), always there, the picture below it: what is at
// the top of the screen (its windows' title bars) is never under it. On a phone: frosted bars above and below the
// picture (the way back and the name; 只看/控制 and the keyboard), always there. Beside a chat (a tab of its side panel,
// `panel`) its tab names it: its bar has only the tools, and a way to its own page.
//
// A simulator's device buttons (主屏幕, 多任务, 锁屏, the software keyboard) and a picture of it: with a mouse a column
// beside the device, on a phone the row over the foot (where a desktop's keys row is).
//
// While driving it, its clipboard goes both ways and files go to its machine (Transfer.tsx): a copy made on it comes
// onto this device's clipboard, a paste here is pasted there, a file dropped on it (or picked) is put where it says.
//
// On a phone a tab of the station's browser is laid out for the stage it is shown on, as the phone's own browser would
// lay it out (`fit`: docs/remote-screens.md), and a finger taps it where it is.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { core } from "../core/react.ts";
import type { ScreenViewState } from "../core/shapes.ts";
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Camera, Chat, ChevronLeft, Close, Cursor, Expand, Eye, Keyboard, Landscape, More, Paste, Power, Trackpad, Trash, Upload } from "@stillfail/ui/icons.tsx";
import { useAct, useToast } from "@stillfail/ui/toast.tsx";
import { ViewerBar } from "@stillfail/ui/viewer/ViewerBar.tsx";
import { panelEdge } from "@stillfail/ui/styles/controls.css.ts";
import { Button, PanelButton, Segmented, Tip, WaitPill } from "../ui.tsx";
import { t } from "../i18n.ts";
import { ScreenFrames, asks, decodable, fpsOf, viewSize, type FrameConfig, type FrameHead, type Fps, type Quality } from "./frames.ts";
import { hearInput, type ScreenInput } from "./input.ts";
import { PAD_SETTLE_MS, PadPointer, Zoom, fitIn } from "./zoom.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useStationNet } from "../cloud/StationCards.tsx";
import { useStationOs } from "../api.ts";
import { ControlCenter, NetChip, ScaleButton, combosFor, type Combo, type Meter } from "./ScreenPanel.tsx";
import { useScreens, useTabActions } from "./ScreenList.tsx";
import { CopiedNote, DropVeil, SendsPanel, clipOf, pasted, putClip, useSends, type Clip } from "./Transfer.tsx";
import * as css from "./ScreenViewer.css.ts";

/** What the view's bar shows: its state but the pointer (which moves often, and is drawn without React). */
type Shown = Omit<ScreenViewState, "cursor">;

const OVER = new Set(["ended", "outdated", "gone", "denied", "failed"]);
/** Over, but perhaps not for good: opened again on asking. */
const AGAIN = new Set(["ended", "denied", "failed"]);

/** A call that only says something to the view as it goes (an ack, input): nothing to wait for, nothing to tell. */
const tell = (name: string, params: Record<string, unknown>) => { core().call(name, params).catch(() => undefined); };

const newName = () => (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function" ? crypto.randomUUID() : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`);

export function ScreenViewer({ station, screen, backLabel, onBack, onWindow, onGone, onGrants, phone = false, panel }: {
  /** The station's address (`<workspace>/<id>`). */
  station: string;
  /** The screen's id on it (`desktop`, `browser:<target>`). */
  screen: string;
  backLabel: string;
  onBack: () => void;
  /** Opens it in a window of its own (none where it is in one, or cannot be). */
  onWindow?: (() => void) | undefined;
  /** Its screen gone (a sign-in's tab closed as it ended): what was opened for it is left. */
  onGone?: (() => void) | undefined;
  /** Opens its station's page where its grants are asked for (权限): offered while one is missing. */
  onGrants?: (() => void) | undefined;
  /** The phone's way: bars above and below, fingers, the keyboard on asking. */
  phone?: boolean;
  /** Beside a chat, in a tab of its side panel (named there): its page opened instead (`onExpand`). */
  panel?: { onExpand: () => void } | undefined;
}) {
  const stage = useRef<HTMLDivElement>(null);
  const picture = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  /** A part of the screen the station sends alone while the picture is zoomed in, laid over the whole (frames.ts). */
  const partCanvas = useRef<HTMLCanvasElement>(null);
  /** The part in sight last told the core (`screen.look`): "" the whole. */
  const looked = useRef("");
  const pointer = useRef<HTMLSpanElement>(null);
  /** A simulator's buttons beside the device, with a mouse (placed with the picture). */
  const device = useRef<HTMLDivElement>(null);
  const keys = useRef<HTMLTextAreaElement>(null);
  /** This page's name for the view open now (each opening its own). */
  const view = useRef("");
  /** The latest state, its pointer too. */
  const latest = useRef<ScreenViewState | null>(null);
  /** The picture's size, as last drawn. */
  const size = useRef({ width: 0, height: 0 });
  /** A mouse over the picture while driving: the station's pointer is not drawn then (the mouse's own takes its shape). */
  const hovering = useRef(false);
  /** A phone's zoom of the picture, and the pointer its finger moves as a trackpad (zoom.ts). */
  const zoom = useRef(new Zoom());
  const padPointer = useRef(new PadPointer());
  /** This device's way for a finger: as a trackpad unless it keeps `direct` (a simulator's is a touchscreen: below). */
  const padKept = usePrefs((p) => p.screenTouch) !== "direct";
  /**
   * 全屏 on a phone: the screen alone, the browser's own full screen where it has one (and sideways where it lets the
   * page turn it), the bars folded into one button over the corner (open: `toolsOpen`).
   */
  const viewerEl = useRef<HTMLDivElement>(null);
  const [full, setFull] = useState(false);
  const [toolsOpen, setToolsOpen] = useState(false);
  const goFull = (on: boolean) => {
    setFull(on);
    setToolsOpen(false);
    const el = viewerEl.current;
    if (on) {
      el?.requestFullscreen?.({ navigationUI: "hide" }).then(() => (window.screen.orientation as { lock?: (o: string) => Promise<void> } | undefined)?.lock?.("landscape")).catch(() => undefined);
    } else {
      try { window.screen.orientation?.unlock?.(); } catch { /* not locked */ }
      if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined);
    }
  };
  // The browser's full screen left (its back, a swipe): 全屏 too.
  useEffect(() => {
    const left = () => { if (!document.fullscreenElement) setFull(false); };
    document.addEventListener("fullscreenchange", left);
    return () => document.removeEventListener("fullscreenchange", left);
  }, []);
  /** The modifiers held on the keys row (bit 0 Alt, 1 Ctrl, 2 Meta, 3 Shift), for the next key. */
  const [held, setHeld] = useState(0);
  const heldRef = useRef(0);
  heldRef.current = held;

  const [attempt, setAttempt] = useState(0);
  /** How large a picture is asked for (its panel's 画质; a phone's is as its window is): another opens the view again. */
  const quality: Quality = phone ? "auto" : usePrefs((p) => p.screenQuality) as Quality | undefined ?? "auto";
  /** The 画质 a view opens with; another chosen while it is open asks it of that view (`screen.bounds`). */
  const qualityRef = useRef(quality);
  qualityRef.current = quality;
  /** The most frames a second asked (its panel's 帧率): another asks it of the open view as 画质 does. */
  const fps: Fps = fpsOf(usePrefs((p) => p.screenFps));
  const fpsRef = useRef(fps);
  fpsRef.current = fps;
  /** The codec asked (its panel's 编码): `h264` only, or the best both ends have. Another opens the view again. */
  const codec: "auto" | "h264" = usePrefs((p) => p.screenCodec) === "h264" ? "h264" : "auto";
  /** What came of the view: its panel reads the frames and bits a second from it. */
  const meter = useRef<Meter>({ frames: 0, bytes: 0 });
  const [shown, setShown] = useState<Shown | null>(null);
  /** A simulator's screen is touched where it is, as the device's own is (no trackpad to choose). */
  const touchscreen = shown?.kind === "simulator";
  /** A tab of the station's browser on a phone, laid out for it: tapped where it is, as in the phone's own browser. */
  const laidOut = phone && shown?.kind === "browser";
  /** A finger drives it as a trackpad (unless this device keeps `direct`), on a phone. */
  const pad = padKept && phone && !touchscreen && !laidOut;
  const padRef = useRef(pad);
  padRef.current = pad;
  const touchscreenRef = useRef(touchscreen);
  touchscreenRef.current = touchscreen;
  const [failure, setFailure] = useState<string | null>(null);
  const [drawn, setDrawn] = useState(false);
  /** 只看/控制 as asked, until the core says it is so. */
  const [want, setWant] = useState<boolean | null>(null);
  const [typing, setTyping] = useState(false);
  /** A copy made on the screen this browser would not put on the clipboard by itself: offered until taken or put away. */
  const [copied, setCopied] = useState<Clip | null>(null);
  /** A file dragged over the screen while it can take one. */
  const [dragging, setDragging] = useState(false);
  const [sendsOpen, setSendsOpen] = useState(false);
  const files = useRef<HTMLInputElement>(null);
  const toast = useToast();
  const toastRef = useRef(toast);
  toastRef.current = toast;

  const phase = failure ? "failed" : shown?.phase ?? "connecting";
  const gone = useRef(onGone);
  gone.current = onGone;
  useEffect(() => { if (phase === "gone") gone.current?.(); }, [phase]);
  const live = phase === "live";
  const over = OVER.has(phase);
  const waiting = phase === "connecting" || phase === "reconnecting";
  const driving = live && shown?.control === true;
  const drivingRef = useRef(driving);
  drivingRef.current = driving;
  /** What a person driving it has of its clipboard, and where a file dropped on it goes (none while only looking). */
  const clipTypes = driving ? shown?.clipboard ?? [] : [];
  const clipTypesRef = useRef(clipTypes);
  clipTypesRef.current = clipTypes;
  const drop = driving ? shown?.drop : undefined;

  /** The stage's size, and the picture fitted in it, whole, in the middle (letterboxed). */
  // A simulator's buttons beside the device take their column on both sides, the device staying in the middle.
  const room = useCallback(() => ({ width: Math.max(0, (stage.current?.clientWidth ?? 0) - (device.current ? 2 * DEVICE_ROOM : 0)), height: stage.current?.clientHeight ?? 0 }), []);
  const fit = useCallback(() => fitIn(room(), size.current.width, size.current.height), [room]);
  /** The picture where it is drawn: fitted, and zoomed on a phone. */
  const place = useCallback(() => {
    const p = picture.current;
    if (!p || !size.current.width || !size.current.height) return;
    const f = fit();
    // Kept within the stage as it resizes.
    zoom.current.pan({ x: 0, y: 0 }, f, room());
    const shown = zoom.current.shown(f);
    p.style.width = `${Math.round(shown.width)}px`;
    p.style.height = `${Math.round(shown.height)}px`;
    const left = shown.left + (device.current ? DEVICE_ROOM : 0);
    p.style.left = `${Math.round(left)}px`;
    p.style.top = `${Math.round(shown.top)}px`;
    // Zoomed in, the part in sight, in this device's pixels: the station sends it alone, as sharp as it is shown here
    // (the core asks once it has stayed a moment); the whole again once it is not.
    const r = room();
    const x0 = Math.max(0, -shown.left / shown.width), y0 = Math.max(0, -shown.top / shown.height);
    const x1 = Math.min(1, (r.width - shown.left) / shown.width), y1 = Math.min(1, (r.height - shown.top) / shown.height);
    const zoomed = zoom.current.zoomed && x1 > x0 && y1 > y0;
    const ratio = window.devicePixelRatio || 1;
    const look = zoomed ? { region: { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }, width: Math.round((x1 - x0) * shown.width * ratio), height: Math.round((y1 - y0) * shown.height * ratio) } : { region: null, width: 0, height: 0 };
    const key = zoomed ? JSON.stringify(look) : "";
    if (key !== looked.current && view.current) {
      looked.current = key;
      tell("screen.look", { view: view.current, ...look });
    }
    // The buttons by the device's right edge, at its top (the stage's place in the viewer added).
    const d = device.current, s = stage.current;
    if (d && s) {
      d.style.left = `${Math.round(s.offsetLeft + left + shown.width + DEVICE_GAP)}px`;
      d.style.top = `${Math.round(s.offsetTop + shown.top)}px`;
    }
  }, [fit, room]);
  useLayoutEffect(() => {
    const s = stage.current;
    if (!s) return;
    const watch = new ResizeObserver(place);
    watch.observe(s);
    return () => watch.disconnect();
  }, [place]);

  // A simulator's buttons come (or go) beside the device: it is fitted again.
  useLayoutEffect(place, [place, touchscreen, phone, phase]);

  /** The station's pointer where it says, and the mouse's own in its shape while it drives here. */
  const drawPointer = useCallback(() => {
    const el = pointer.current;
    const station = latest.current?.cursor;
    // Driven as a trackpad: where the finger has moved it (ahead of the station's word), in the station's shape.
    const at = padRef.current && drivingRef.current && station ? { ...station, x: padPointer.current.x, y: padPointer.current.y } : padRef.current && drivingRef.current ? { x: padPointer.current.x, y: padPointer.current.y, shape: "" } : station;
    if (el) {
      // Hidden on the screen too ("none"), or while this mouse is its pointer (then shown in its shape, below).
      el.hidden = !at || at.shape === "none" || (hovering.current && drivingRef.current);
      if (at) { el.style.left = `${at.x * 100}%`; el.style.top = `${at.y * 100}%`; }
      // As large as a pointer on the screen would look at the picture's size: smaller on a phone, never past 18 px.
      const shown = picture.current?.clientWidth ?? 0;
      if (shown > 0) el.style.setProperty("--pointer", `${Math.round(Math.min(18, Math.max(10, shown / 90)))}px`);
    }
    if (stage.current) stage.current.style.cursor = drivingRef.current && at?.shape ? at.shape : "";
  }, []);

  // The view: open while the page is, opened again on asking (`attempt`).
  useEffect(() => {
    const c = canvas.current;
    if (!c) return;
    const name = newName();
    view.current = name;
    // (a view of its own: the part in sight told it again)
    looked.current = "";
    setFailure(null);
    const abort = new AbortController();
    let open = true;
    const frames: ScreenFrames = new ScreenFrames(c, {
      ack: (ts) => tell("screen.ack", { view: name, ts }),
      keyframe: () => tell("screen.keyframe", { view: name }),
      // H.265 said to play here and did not (or held frames back): opened again, H.264 now.
      unplayable: () => { if (open) setAttempt((n) => n + 1); },
      drawn: (width, height) => {
        // Another size of frame: fitted again.
        if (width !== size.current.width || height !== size.current.height) zoom.current.reset();
        size.current = { width, height };
        place();
        setDrawn(true);
      },
    }, partCanvas.current);
    meter.current.decode = () => frames.stats();
    // A copy made on the screen: on this device's clipboard at once where the browser lets it, else offered.
    const copiedThere = (clip: Clip) => {
      putClip(clip).then(() => { if (open) { setCopied(null); toastRef.current(t("web-pages.screen.copied")); } }, () => { if (open) setCopied(clip); });
    };
    const settle = { timer: 0 };
    const took = (state: ScreenViewState) => {
      latest.current = state;
      // The trackpad's pointer where the station says, once the finger has let it be (and again once its echo has come).
      padPointer.current.follow(state.cursor, performance.now());
      clearTimeout(settle.timer);
      settle.timer = window.setTimeout(() => { padPointer.current.follow(latest.current?.cursor, performance.now()); drawPointer(); }, PAD_SETTLE_MS + 100);
      drawPointer();
      const { cursor: _, ...rest } = state;
      setShown((was) => (was && JSON.stringify(was) === JSON.stringify(rest) ? was : rest));
    };
    void decodable(codec === "h264").then((codecs) => {
      if (!open) return;
      // On a phone, the stage it is shown on: a tab of the station's browser is laid out for it.
      const s = stage.current;
      const fit = phone && s && s.clientWidth > 0 && s.clientHeight > 0 ? { fit: { width: s.clientWidth, height: s.clientHeight, scale: window.devicePixelRatio || 1 } } : {};
      core().call("screen.view", { station, screen, view: name, codecs, ...viewSize(qualityRef.current), ...asks(qualityRef.current, fpsRef.current), ...fit }, (value, bytes) => {
        if (!open) return;
        const v = value as { state?: ScreenViewState; config?: FrameConfig; frame?: FrameHead; clipboard?: { type?: string; text?: string } };
        if (v.frame) {
          meter.current.frames++;
          meter.current.bytes += bytes?.length ?? 0;
          frames.frame(v.frame, bytes);
        }
        else if (v.config) frames.config(v.config, bytes);
        else if (v.state) took(v.state);
        else if (v.clipboard) { const clip = clipOf(v.clipboard, bytes); if (clip) copiedThere(clip); }
      }, abort.signal).then(() => {
        // Answered: over. The last state said why; one that did not leave it there is ended.
        if (open) setShown((was) => (was && !OVER.has(was.phase) ? { ...was, phase: "ended" } : was));
      }, (e: unknown) => {
        if (!open || (e as { code?: string } | null)?.code === "cancelled") return;
        setFailure(e instanceof Error ? e.message : String(e));
      });
    });
    return () => {
      open = false;
      clearTimeout(settle.timer);
      abort.abort();
      frames.close();
    };
  }, [station, screen, attempt, codec, place, drawPointer, phone]);

  // Another 画质 or 帧率: the open view goes on, its pictures asked this large and this often (the core opens its stream
  // again, the one before kept until the new one has opened: a Windows desktop keeps the display scale set from it).
  const boundsAsked = useRef(`${quality} ${fps}`);
  useEffect(() => {
    if (boundsAsked.current === `${quality} ${fps}`) return;
    boundsAsked.current = `${quality} ${fps}`;
    if (view.current) tell("screen.bounds", { view: view.current, ...viewSize(quality), ...asks(quality, fps) });
  }, [quality, fps]);

  // What is done over the picture, while driving.
  useEffect(() => {
    const s = stage.current, k = keys.current;
    if (!s || !k) return;
    return hearInput({
      stage: s, keys: k, picture: () => picture.current,
      driving: () => drivingRef.current,
      send: (input: ScreenInput) => { if (drivingRef.current) tell("screen.input", { view: view.current, input }); },
      hovering: (on) => { hovering.current = on; drawPointer(); },
      // A paste onto the screen's clipboard, pasted there, where it carries what is pasted; else it is typed.
      paste: (data) => {
        const types = clipTypesRef.current;
        if (!types.length) return false;
        const png = types.includes("png") && [...data.files].some((f) => f.type === "image/png");
        if (!png && !(types.includes("text") && data.getData("text/plain"))) return false;
        void pasted(data, types).then((clip) => { if (clip) setClipboard(clip); });
        return true;
      },
      ...(phone ? { fingers: {
        pad: () => padRef.current, touchscreen: () => touchscreenRef.current, pointer: padPointer.current, zoom: zoom.current, fit, room,
        moved: () => { place(); drawPointer(); },
      } } : {}),
      held: { take: () => { const m = heldRef.current; if (m) { heldRef.current = 0; setHeld(0); } return m; } },
    });
  }, [drawPointer, phone, fit, room, place]);
  // Only looking (or no longer live): the keys let go, the keyboard down.
  useEffect(() => {
    drawPointer();
    if (!driving && document.activeElement === keys.current) keys.current?.blur();
  }, [driving, drawPointer]);

  // 只看 / 控制: as asked at once, the core's word once it has said so (or back, if it could not).
  const act = useAct();
  const actRef = useRef(act);
  actRef.current = act;
  /** The screen's clipboard set and pasted there (a paste here, a phone's paste, a file's path). */
  const setClipboard = (clip: { text: string } | { png: Uint8Array }) => {
    // A picture's bytes beside the call (`png: true`).
    const set = "png" in clip ? core().callBytes("screen.clipboard", { view: view.current, png: true, paste: true }, clip.png) : core().call("screen.clipboard", { view: view.current, ...clip, paste: true });
    actRef.current(set, t("web-pages.screen.pasteWhat"));
  };
  // A phone's paste: what this device's clipboard holds, read within the tap.
  const pasteHere = () => {
    if (!navigator.clipboard?.readText) return;
    navigator.clipboard.readText().then((text) => {
      if (text) setClipboard({ text });
      else toast(t("web-pages.screen.clipboardEmpty"));
    }, () => toast(t("web-pages.screen.clipboardUnread")));
  };
  const sends = useSends(station, drop);
  const sendFiles = (list: File[]) => {
    if (!drop || list.length === 0) return;
    setSendsOpen(true);
    sends.send(list);
  };
  const reveal = (path: string) => tell("screen.input", { view: view.current, input: { t: "reveal", path } });
  // Not driving any more: nothing dragged over it is taken.
  useEffect(() => { if (!drop) setDragging(false); }, [drop]);
  const sendsShown = drop !== undefined && sendsOpen && (sends.going.length > 0 || sends.sent.length > 0);
  const control = want ?? shown?.control ?? false;
  // What the station lacks to be driven (macOS Accessibility): 控制 is not to be had, and the bar says what to turn on.
  const access = shown?.access;
  const undrivable = live && access?.control === false;
  useEffect(() => { if (want !== null && (shown?.control === want || undrivable)) setWant(null); }, [shown?.control, want, undrivable]);
  const setControl = (next: boolean) => {
    if (!shown?.may || next === control) return;
    setWant(next);
    const asked = core().call("screen.control", { view: view.current, control: next });
    act(asked, t("web-pages.screen.switchWhat"));
    asked.catch(() => setWant(null));
  };

  // Someone else drives it (an agent at work, a person) and this view only looks: who, said apart from the line, and
  // 接管 at hand (控制, their input waiting) until it is pressed.
  const controllers = shown?.controllers ?? [];
  const takeOver = live && shown?.takeOver === true && want !== true;
  const controlling = controllers.length ? t("web-pages.screen.controlling", { names: controllers.join(t("web-pages.screen.and")) }) : "";
  const takeOverButton = (
    <Tip label={t("web-pages.screen.takeOverTip", { names: controllers.join(t("web-pages.screen.and")) || t("web-pages.screen.someone") })}>
      <Button variant="primary" className={css.takeOver} onClick={() => setControl(true)}>{t("web-pages.screen.takeOver")}</Button>
    </Tip>
  );
  const others = takeOver && (
    <span className={css.controllers}><span className={css.controllersDot} aria-hidden="true" /><span className={css.controllersText}>{controlling}</span></span>
  );

  const title = shown?.title || t("web-pages.screen.title");
  // The window named after it while it is shown (a window of its own has the system's title bar).
  useEffect(() => {
    const was = document.title;
    document.title = title;
    return () => { document.title = was; };
  }, [title]);
  // Over, the panel says why; while it cannot be driven, what to turn on follows who is on it.
  const line = over ? "" : [shown?.line, undrivable ? access?.message : undefined].filter(Boolean).join(" · ");
  const may = shown?.may ?? true;
  /** Why 控制 is not there to pick, when it is not. */
  const cannot = !may ? t("web-pages.screen.readOnly") : undrivable ? access?.message ?? "" : "";
  /** What happened, as the core says it (and what the station lacks, where it says). */
  const headline = OVER.has(phase) ? t(`web-pages.screen.over.${phase}`) : "";
  const why = [failure ?? shown?.message, access?.message].filter((w, i, all): w is string => !!w && w !== headline && all.indexOf(w) === i);
  // Denied for a grant the station lacks (macOS's): where it is asked for is a tap away, not to be looked for.
  const granting = phase === "denied" && onGrants !== undefined && (access?.capture === false || access?.control === false);
  // How this device reaches the station while it is seen: the way (直连, a relay), its round trip and packets lost,
  // each in its colour as it gets worse (the station page's figures, the `stationNet` view). With a mouse they are the
  // bar's own mark (NetChip); a phone says them in its head's line.
  const net = useStationNet(live ? station : null);
  const netParts = phone && net ? [<span key="path">{net.path}</span>, ...[net.rtt, net.loss].flatMap((f, i) => (f ? [<span key={i} className={css.figure} data-level={f.level}>{f.text}</span>] : []))] : [];
  const meta = line || netParts.length ? <>{[...(line ? [<span key="line">{line}</span>] : []), ...netParts].flatMap((part, i) => (i ? [" · ", part] : [part]))}</> : null;
  const os = useStationOs(station);
  // A tab of the station's browser: the chat that opened it, and closing it (then back where it was opened from).
  const tab = useTabActions(station, useScreens(station)?.screens.find((s) => s.id === screen), onBack);
  const sendCombo = (c: Combo) => {
    for (const kind of ["down", "up"] as const) tell("screen.input", { view: view.current, input: { t: "key", kind, key: c.key, code: c.code, mods: c.mods } });
  };
  // A simulator's button: Simulator.app's shortcut for it, as the station takes it (sim-input.ts).
  const press = (b: DeviceButton) => {
    for (const kind of ["down", "up"] as const) tell("screen.input", { view: view.current, input: { t: "key", kind, key: b.key, code: b.code, mods: b.mods } });
  };
  // A picture of it: the one shown, as drawn (as large as the view is asked), saved as a PNG.
  const shoot = () => {
    canvas.current?.toBlob((blob) => {
      if (!blob) return;
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      const at = new Date();
      const pad = (n: number) => String(n).padStart(2, "0");
      a.download = `${title} ${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())} ${pad(at.getHours())}.${pad(at.getMinutes())}.${pad(at.getSeconds())}.png`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      toast(t("web-pages.screen.device.shotSaved"));
    }, "image/png");
  };
  const deviceButtons = (className: string) => (
    <>
      {/* On a phone its own keyboard types (the device's hardware keyboard, which puts its software one away): not this. */}
      {DEVICE_BUTTONS.filter((b) => !phone || b.name !== "keyboard").map((b) => (
        <Tip key={b.name} label={`${t(`web-pages.screen.device.${b.name}`)}  ${b.shortcut}`}>
          <button type="button" className={className} aria-label={t(`web-pages.screen.device.${b.name}`)} disabled={!driving}
            // A phone's keyboard stays up: the field keeps the focus.
            onPointerDown={(e) => e.preventDefault()} onClick={() => press(b)}>{b.icon}</button>
        </Tip>
      ))}
      <Tip label={t("web-pages.screen.device.shot")}>
        <button type="button" className={className} aria-label={t("web-pages.screen.device.shot")} disabled={!drawn} onClick={shoot}><Camera size={18} /></button>
      </Tip>
    </>
  );
  // The screen's display scale, while driving one whose station changes it (Windows): set there, said back.
  const scale = driving ? shown?.scale : undefined;
  const setScale = (percent: number) => tell("screen.input", { view: view.current, input: { t: "scale", percent } });
  const viewTools = !over ? (
    <>
      {live && <NetChip net={net} shown={shown} meter={meter} os={os} />}
      <ControlCenter quality={quality} onQuality={(q) => setPrefs({ screenQuality: q === "auto" ? null : q })} scale={scale} onScale={setScale}
        fps={fps} onFps={(f) => setPrefs({ screenFps: f === "auto" ? null : f })}
        codec={codec} onCodec={(c) => setPrefs({ screenCodec: c === "auto" ? null : c })}
        combos={driving ? combosFor(os) : []} onCombo={sendCombo} onSend={drop ? () => files.current?.click() : undefined}
        onWindow={onWindow} full={full} onFull={goFull} chat={tab.chat} onClose={tab.close} onLeave={onBack} />
    </>
  ) : null;
  const modes = (
    <Tip label={cannot}>
      <span className={css.mode}>
        <Segmented label={t("web-pages.screen.mode")} value={control ? "control" : "look"} onChange={(v) => setControl(v === "control")}
          options={[{ value: "look", label: t("web-pages.screen.look") }, { value: "control", label: t("web-pages.screen.control"), disabled: !may || !live || undrivable }]} />
      </span>
    </Tip>
  );

  return (
    <div ref={viewerEl} className={css.viewer} data-phone={phone || undefined} data-full={(phone && full) || undefined}
      data-keys={(phone && !over && (touchscreen ? !full : driving && (!full || typing))) || undefined} data-phase={phase}
      onDragOver={(e) => { if (drop && e.dataTransfer.types.includes("Files")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; setDragging(true); } }}
      onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false); }}
      onDrop={(e) => { if (!drop || !e.dataTransfer.files.length) return; e.preventDefault(); setDragging(false); sendFiles([...e.dataTransfer.files]); }}>
      <div ref={stage} className={css.stage} data-driving={driving || undefined}>
        <div ref={picture} className={css.picture} data-shown={drawn || undefined} data-faded={over || undefined}>
          <canvas ref={canvas} className={css.canvas} />
          <canvas ref={partCanvas} className={css.part} hidden />
          <span ref={pointer} className={css.cursor} hidden><Arrow /></span>
        </div>
        <textarea ref={keys} className={css.keys} aria-label={t("web-pages.screen.keys")} tabIndex={-1} rows={1}
          autoCapitalize="off" autoCorrect="off" autoComplete="off" spellCheck={false}
          onFocus={() => setTyping(true)} onBlur={() => setTyping(false)} />
      </div>
      {touchscreen && !phone && !over && (
        <div ref={device} className={css.device} role="toolbar" aria-orientation="vertical" aria-label={t("web-pages.screen.device")}>{deviceButtons(css.deviceButton)}</div>
      )}
      {dragging && drop && <DropVeil title={title} drop={drop} />}
      {copied && driving && <CopiedNote clip={copied} onDone={(put) => { setCopied(null); if (put) toast(t("web-pages.screen.copied")); }} />}
      {sendsShown && drop && (
        <SendsPanel drop={drop} going={sends.going} sent={sends.sent}
          onPastePath={(path) => setClipboard({ text: path })} onReveal={reveal}
          onClose={() => { sends.clear(); if (!sends.going.some((u) => u.state === "sending")) setSendsOpen(false); }} />
      )}
      <input ref={files} type="file" multiple hidden onChange={(e) => { const list = [...(e.target.files ?? [])]; e.target.value = ""; sendFiles(list); }} />
      {waiting && <WaitPill over text={phase === "reconnecting" ? t("common.reconnecting") : t("common.connecting")} />}
      {over && (
        <div className={css.note} role="alert">
          <div className={css.noteWords}>
            <span className={css.noteTitle}>{headline}</span>
            {why.map((w) => <span key={w} className={css.noteWhy}>{w}</span>)}
          </div>
          <div className={`${css.noteFoot} ${panelEdge}`}>
            <PanelButton tone={AGAIN.has(phase) ? "quiet" : "accent"} onClick={onBack}>{t("common.back")}</PanelButton>
            {AGAIN.has(phase) && <PanelButton tone={granting ? "quiet" : "accent"} onClick={() => { setShown(null); setAttempt((n) => n + 1); }}>{t("web-pages.screen.again")}</PanelButton>}
            {granting && <PanelButton tone="accent" onClick={onGrants}>{t("web-pages.screen.toGrants")}</PanelButton>}
          </div>
        </div>
      )}
      {phone ? (
        <>
          <header className={css.head}>
            <Tip label={backLabel}><button type="button" className={css.back} aria-label={backLabel} onClick={onBack}><ChevronLeft size={20} /></button></Tip>
            <span className={css.headText}><b>{title}</b>{meta && <small>{meta}</small>}</span>
            {tab.chat && <button type="button" className={css.back} aria-label={t("web-pages.screen.openChat", { title: tab.chat.title })} onClick={tab.chat.open}><Chat size={18} /></button>}
            {tab.close && <button type="button" className={css.back} aria-label={t("web-pages.screen.close")} disabled={tab.closing} onClick={tab.close}><Trash size={18} /></button>}
          </header>
          {!over && touchscreen && !full && (
            <div className={css.keysRow} role="toolbar" aria-label={t("web-pages.screen.device")}>{deviceButtons(css.rowKey)}</div>
          )}
          {!over && driving && !touchscreen && (!full || typing) && (
            <div className={css.keysRow} role="toolbar" aria-label={t("web-pages.screen.keysRow")}>
              {ROW_KEYS.map((k) => {
                const on = k.mod !== undefined && (held & k.mod) !== 0;
                const name = k.name ? t(k.name) : k.label;
                return (
                  <button key={k.code ?? k.name} type="button" className={css.rowKey} aria-label={name} aria-pressed={k.mod !== undefined ? on : undefined}
                    // The keyboard stays up: the field keeps the focus.
                    onPointerDown={(e) => e.preventDefault()}
                    onClick={() => {
                      if (k.mod !== undefined) { setHeld((m) => m ^ k.mod!); return; }
                      const m = heldRef.current;
                      if (m) { heldRef.current = 0; setHeld(0); }
                      tell("screen.input", { view: view.current, input: { t: "key", kind: "down", key: k.key, code: k.code, mods: m } });
                      tell("screen.input", { view: view.current, input: { t: "key", kind: "up", key: k.key, code: k.code, mods: m } });
                    }}>
                    {k.icon ?? k.label}
                  </button>
                );
              })}
            </div>
          )}
          {!over && (
            <div className={css.foot}>
              {takeOver ? <>{others}{takeOverButton}</> : modes}
              {driving && !touchscreen && !laidOut && (
                <Tip label={t("web-pages.screen.trackpad")}>
                  <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.trackpad")} aria-pressed={pad}
                    onClick={() => { setPrefs({ screenTouch: pad ? "direct" : null }); toast(t(pad ? "web-pages.screen.padOff" : "web-pages.screen.padOn")); }}>
                    <Trackpad size={18} />
                  </button>
                </Tip>
              )}
              <Tip label={t("web-pages.screen.keyboard")}>
                <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.keyboard")} aria-pressed={typing} disabled={!driving}
                  // The keyboard comes up for the field only from within the tap itself.
                  onClick={() => { if (typing) keys.current?.blur(); else keys.current?.focus({ preventScroll: true }); }}>
                  <Keyboard size={18} />
                </button>
              </Tip>
              {scale && <ScaleButton scale={scale} onScale={setScale} className={css.keyboard} />}
              {clipTypes.includes("text") && (
                <Tip label={t("web-pages.screen.paste")}>
                  <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.paste")} onClick={pasteHere}><Paste size={18} /></button>
                </Tip>
              )}
              {drop && (
                <Tip label={t("web-pages.screen.sendFile")}>
                  <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.sendFile")} onClick={() => files.current?.click()}><Upload size={18} /></button>
                </Tip>
              )}
              <Tip label={t("web-pages.screen.full")}>
                <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.full")} onClick={() => goFull(true)}><Landscape size={18} /></button>
              </Tip>
            </div>
          )}
          {full && (
            <div className={css.fullTools}>
              <button type="button" className={css.keyboard} aria-label={t(toolsOpen ? "web-pages.screen.toolsClose" : "web-pages.screen.tools")} aria-expanded={toolsOpen}
                onClick={() => setToolsOpen((o) => !o)}>{toolsOpen ? <Close size={18} /> : <More size={18} />}</button>
              {toolsOpen && (
                <>
                  {!over && may && live && !undrivable && !takeOver && (
                    <button type="button" className={css.keyboard} aria-label={control ? t("web-pages.screen.control") : t("web-pages.screen.look")}
                      onClick={() => setControl(!control)}>{control ? <Cursor size={18} /> : <Eye size={18} />}</button>
                  )}
                  {driving && !touchscreen && !laidOut && (
                    <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.trackpad")} aria-pressed={pad}
                      onClick={() => { setPrefs({ screenTouch: pad ? "direct" : null }); toast(t(pad ? "web-pages.screen.padOff" : "web-pages.screen.padOn")); }}><Trackpad size={18} /></button>
                  )}
                  {driving && (
                    <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.keyboard")} aria-pressed={typing}
                      onClick={() => { if (typing) keys.current?.blur(); else keys.current?.focus({ preventScroll: true }); }}><Keyboard size={18} /></button>
                  )}
                  {clipTypes.includes("text") && (
                    <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.paste")} onClick={pasteHere}><Paste size={18} /></button>
                  )}
                  {drop && (
                    <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.sendFile")} onClick={() => files.current?.click()}><Upload size={18} /></button>
                  )}
                  <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.unfull")} onClick={() => goFull(false)}><Landscape size={18} /></button>
                </>
              )}
            </div>
          )}
        </>
      ) : panel ? (
        <header className={css.panelBar}>
          {over ? <span /> : takeOver ? <span className={css.takeOverTools}>{others}{takeOverButton}</span> : modes}
          <span className={css.panelTools}>
            {viewTools}
            <Tip label={t("web-pages.screen.expand")}>
              <button type="button" className={css.panelExpand} aria-label={t("web-pages.screen.expand")} onClick={panel.onExpand}><Expand size={16} /></button>
            </Tip>
          </span>
        </header>
      ) : (
        <ViewerBar back={{ label: backLabel, onClick: onBack }} name={title} meta={meta}
          tools={over ? undefined : takeOver ? <span className={css.takeOverTools}>{others}{takeOverButton}</span> : <>{viewTools}{modes}</>} />
      )}
    </div>
  );
}

/** The keys row's keys (a phone's keyboard has not these): what each sends, or the modifier it holds for the next key. */
const ROW_KEYS: { label: string; name?: string; key?: string; code?: string; mod?: number; icon?: React.ReactNode }[] = [
  { label: "Esc", key: "Escape", code: "Escape" },
  { label: "Tab", key: "Tab", code: "Tab" },
  { label: "⌘", name: "web-pages.screen.key.command", mod: 4 },
  { label: "⌃", name: "web-pages.screen.key.control", mod: 2 },
  { label: "⌥", name: "web-pages.screen.key.option", mod: 1 },
  { label: "⇧", name: "web-pages.screen.key.shift", mod: 8 },
  { label: "", name: "web-pages.screen.key.left", key: "ArrowLeft", code: "ArrowLeft", icon: <ArrowLeft size={16} /> },
  { label: "", name: "web-pages.screen.key.up", key: "ArrowUp", code: "ArrowUp", icon: <ArrowUp size={16} /> },
  { label: "", name: "web-pages.screen.key.down", key: "ArrowDown", code: "ArrowDown", icon: <ArrowDown size={16} /> },
  { label: "", name: "web-pages.screen.key.right", key: "ArrowRight", code: "ArrowRight", icon: <ArrowRight size={16} /> },
];

/** How far a simulator's buttons are from the device, and the column they take (theirs and the gap). */
const DEVICE_GAP = 12;
const DEVICE_ROOM = 40 + 2 * DEVICE_GAP;

type DeviceButton = { name: "home" | "appSwitcher" | "lock" | "keyboard"; key: string; code: string; mods: number; shortcut: string; icon: React.ReactNode };
/** A simulator's buttons, each as Simulator.app's shortcut presses it (mods: 2 ⌃, 4 ⌘, 8 ⇧). */
const DEVICE_BUTTONS: DeviceButton[] = [
  { name: "home", key: "h", code: "KeyH", mods: 4 | 8, shortcut: "⇧⌘H", icon: <HomeIcon /> },
  { name: "appSwitcher", key: "h", code: "KeyH", mods: 2 | 4 | 8, shortcut: "⌃⇧⌘H", icon: <AppsIcon /> },
  { name: "lock", key: "l", code: "KeyL", mods: 4, shortcut: "⌘L", icon: <Power size={18} /> },
  { name: "keyboard", key: "k", code: "KeyK", mods: 4, shortcut: "⌘K", icon: <Keyboard size={18} /> },
];

/** 主屏幕: a house, drawn as the icons are (24 box, round 1.75 lines). */
function HomeIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 10.5L12 4L20 10.5V18Q20 20 18 20H14.5V14.5H9.5V20H6Q4 20 4 18Z" />
    </svg>
  );
}
/** 多任务: the apps' cards side by side, the middle one in front. */
function AppsIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="8" y="4" width="8" height="16" rx="2" />
      <path d="M5 6.5V17.5 M19 6.5V17.5" />
    </svg>
  );
}

/** The station's pointer: an arrow, its tip at the point. */
function Arrow() {
  return (
    <svg viewBox="0 0 18 18" aria-hidden="true">
      <path d="M4 2L14.5 10.2L9.6 10.9L7.2 15.6Z" fill="#fff" stroke="#000" strokeWidth="1.2" strokeLinejoin="round" />
    </svg>
  );
}
