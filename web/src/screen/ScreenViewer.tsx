// One of a station's screens (its desktop, a tab of its browser: docs/remote-screens.md), seen and driven in the app.
// The core opens the view (`screen.view`) and says how it is (its `state`: connecting, live, again, over and why;
// 只看 or 控制, who else is on it); its frames are drawn here outside React (frames.ts), and what is done over the
// picture goes back as the core takes it (input.ts). Nothing here is drawn again per frame: the picture, its place and
// the station's pointer are written straight into the page.
//
// With a mouse it is a file opened's page: the bar along the top (the way back, the screen's name, what the core says
// of the view, 只看/控制), gone after a moment at rest while driving and back as the pointer comes to the top. On a
// phone: frosted bars above and below the picture (the way back and the name; 只看/控制 and the keyboard), always there.
//
// While driving it, its clipboard goes both ways and files go to its machine (Transfer.tsx): a copy made on it comes
// onto this device's clipboard, a paste here is pasted there, a file dropped on it (or picked) is put where it says.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { core } from "../core/react.ts";
import type { ScreenViewState } from "../core/shapes.ts";
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp, ChevronLeft, Close, Cursor, Eye, Keyboard, Landscape, More, Paste, Trackpad, Upload } from "@stillfail/ui/icons.tsx";
import { useAct, useToast } from "@stillfail/ui/toast.tsx";
import { byBar, ViewerBar, ViewerTool } from "@stillfail/ui/viewer/ViewerBar.tsx";
import { panelEdge } from "@stillfail/ui/styles/controls.css.ts";
import { REST_MS } from "@stillfail/ui/viewer/rest.ts";
import { Button, PanelButton, Segmented, Tip, WaitPill } from "../ui.tsx";
import { t } from "../i18n.ts";
import { ScreenFrames, decodable, viewSize, type FrameConfig, type FrameHead } from "./frames.ts";
import { hearInput, type ScreenInput } from "./input.ts";
import { PAD_SETTLE_MS, PadPointer, Zoom, fitIn } from "./zoom.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
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

export function ScreenViewer({ station, screen, backLabel, onBack, phone = false }: {
  /** The station's address (`<workspace>/<id>`). */
  station: string;
  /** The screen's id on it (`desktop`, `browser:<target>`). */
  screen: string;
  backLabel: string;
  onBack: () => void;
  /** The phone's way: bars above and below, fingers, the keyboard on asking. */
  phone?: boolean;
}) {
  const stage = useRef<HTMLDivElement>(null);
  const picture = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const pointer = useRef<HTMLSpanElement>(null);
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
  /** A finger drives it as a trackpad (unless this device keeps `direct`), on a phone. */
  const pad = usePrefs((p) => p.screenTouch) !== "direct" && phone;
  const padRef = useRef(pad);
  padRef.current = pad;
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
  const [shown, setShown] = useState<Shown | null>(null);
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
  const room = useCallback(() => ({ width: stage.current?.clientWidth ?? 0, height: stage.current?.clientHeight ?? 0 }), []);
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
    p.style.left = `${Math.round(shown.left)}px`;
    p.style.top = `${Math.round(shown.top)}px`;
  }, [fit, room]);
  useLayoutEffect(() => {
    const s = stage.current;
    if (!s) return;
    const watch = new ResizeObserver(place);
    watch.observe(s);
    return () => watch.disconnect();
  }, [place]);

  /** The station's pointer where it says, and the mouse's own in its shape while it drives here. */
  const drawPointer = useCallback(() => {
    const el = pointer.current;
    const station = latest.current?.cursor;
    // Driven as a trackpad: where the finger has moved it (ahead of the station's word), in the station's shape.
    const at = padRef.current && drivingRef.current && station ? { ...station, x: padPointer.current.x, y: padPointer.current.y } : padRef.current && drivingRef.current ? { x: padPointer.current.x, y: padPointer.current.y, shape: "" } : station;
    if (el) {
      el.hidden = !at || (hovering.current && drivingRef.current);
      if (at) { el.style.left = `${at.x * 100}%`; el.style.top = `${at.y * 100}%`; }
    }
    if (stage.current) stage.current.style.cursor = drivingRef.current && at?.shape ? at.shape : "";
  }, []);

  // The view: open while the page is, opened again on asking (`attempt`).
  useEffect(() => {
    const c = canvas.current;
    if (!c) return;
    const name = newName();
    view.current = name;
    setFailure(null);
    const abort = new AbortController();
    let open = true;
    const frames = new ScreenFrames(c, {
      ack: (ts) => tell("screen.ack", { view: name, ts }),
      keyframe: () => tell("screen.keyframe", { view: name }),
      drawn: (width, height) => {
        // Another size of frame: fitted again.
        if (width !== size.current.width || height !== size.current.height) zoom.current.reset();
        size.current = { width, height };
        place();
        setDrawn(true);
      },
    });
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
    void decodable().then((codecs) => {
      if (!open) return;
      core().call("screen.view", { station, screen, view: name, codecs, ...viewSize() }, (value, bytes) => {
        if (!open) return;
        const v = value as { state?: ScreenViewState; config?: FrameConfig; frame?: FrameHead; clipboard?: { type?: string; text?: string } };
        if (v.frame) frames.frame(v.frame, bytes);
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
  }, [station, screen, attempt, place, drawPointer]);

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
        pad: () => padRef.current, pointer: padPointer.current, zoom: zoom.current, fit, room,
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

  // With a mouse, the bar goes after a moment at rest while live, and comes back as the pointer comes to the top (or
  // anywhere, while only looking). A finger keeps it; so does someone else driving it (who, and 接管, stay in sight).
  const [awake, setAwake] = useState(true);
  const rest = useRef(0);
  // The pointer on the bar, which it does not hear where it drags the window (ViewerBar.tsx byBar): it stays.
  const onBar = useRef(false);
  const wake = useCallback(() => {
    setAwake(true);
    clearTimeout(rest.current);
    rest.current = window.setTimeout(() => { if (!onBar.current) setAwake(false); }, REST_MS);
  }, []);
  useEffect(() => { wake(); return () => clearTimeout(rest.current); }, [wake]);
  const touched = useRef(false);
  const onPointerMove = (e: React.PointerEvent) => {
    if (e.pointerType !== "mouse") { touched.current = true; clearTimeout(rest.current); setAwake(true); return; }
    touched.current = false;
    onBar.current = !phone && byBar(e);
    if (!drivingRef.current || onBar.current) wake();
  };

  const title = shown?.title || t("web-pages.screen.title");
  // Over, the panel says why; while it cannot be driven, what to turn on follows who is on it.
  const line = over ? "" : [shown?.line, undrivable ? access?.message : undefined].filter(Boolean).join(" · ");
  const may = shown?.may ?? true;
  /** Why 控制 is not there to pick, when it is not. */
  const cannot = !may ? t("web-pages.screen.readOnly") : undrivable ? access?.message ?? "" : "";
  /** What happened, as the core says it (and what the station lacks, where it says). */
  const headline = OVER.has(phase) ? t(`web-pages.screen.over.${phase}`) : "";
  const why = [failure ?? shown?.message, access?.message].filter((w, i, all): w is string => !!w && w !== headline && all.indexOf(w) === i);
  const sendTool = drop && !over ? (
    <ViewerTool label={t("web-pages.screen.sendFile")} onClick={() => files.current?.click()}><Upload size={18} /></ViewerTool>
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
      data-keys={(phone && !over && driving && (!full || typing)) || undefined} data-phase={phase} onPointerMove={onPointerMove} onPointerDown={onPointerMove}
      onDragOver={(e) => { if (drop && e.dataTransfer.types.includes("Files")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; setDragging(true); } }}
      onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false); }}
      onDrop={(e) => { if (!drop || !e.dataTransfer.files.length) return; e.preventDefault(); setDragging(false); sendFiles([...e.dataTransfer.files]); }}>
      <div ref={stage} className={css.stage} data-driving={driving || undefined}>
        <div ref={picture} className={css.picture} data-shown={drawn || undefined} data-faded={over || undefined}>
          <canvas ref={canvas} className={css.canvas} />
          <span ref={pointer} className={css.cursor} hidden><Arrow /></span>
        </div>
        <textarea ref={keys} className={css.keys} aria-label={t("web-pages.screen.keys")} tabIndex={-1} rows={1}
          autoCapitalize="off" autoCorrect="off" autoComplete="off" spellCheck={false}
          onFocus={() => setTyping(true)} onBlur={() => setTyping(false)} />
      </div>
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
            {AGAIN.has(phase) && <PanelButton tone="accent" onClick={() => { setShown(null); setAttempt((n) => n + 1); }}>{t("web-pages.screen.again")}</PanelButton>}
          </div>
        </div>
      )}
      {phone ? (
        <>
          <header className={css.head}>
            <Tip label={backLabel}><button type="button" className={css.back} aria-label={backLabel} onClick={onBack}><ChevronLeft size={20} /></button></Tip>
            <span className={css.headText}><b>{title}</b>{line && <small>{line}</small>}</span>
          </header>
          {!over && driving && (!full || typing) && (
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
              {driving && (
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
                  {driving && (
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
      ) : (
        <ViewerBar back={{ label: backLabel, onClick: onBack }} name={title} meta={line}
          hidden={live && !awake && !touched.current && !takeOver && controllers.length === 0}
          tools={over ? undefined : takeOver ? <span className={css.takeOverTools}>{others}{takeOverButton}</span> : <>{sendTool}{modes}</>} />
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

/** The station's pointer: an arrow, its tip at the point. */
function Arrow() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
      <path d="M4 2L14.5 10.2L9.6 10.9L7.2 15.6Z" fill="#fff" stroke="#000" strokeWidth="1.2" strokeLinejoin="round" />
    </svg>
  );
}
