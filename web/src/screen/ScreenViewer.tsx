// One of a station's screens (its desktop, a tab of its browser: docs/remote-screens.md), seen and driven in the app.
// The core opens the view (`screen.view`) and says how it is (its `state`: connecting, live, again, over and why;
// 只看 or 控制, who else is on it); its frames are drawn here outside React (frames.ts), and what is done over the
// picture goes back as the core takes it (input.ts). Nothing here is drawn again per frame: the picture, its place and
// the station's pointer are written straight into the page.
//
// With a mouse it is a file opened's page: the bar along the top (the way back, the screen's name, what the core says
// of the view, 只看/控制), gone after a moment at rest while driving and back as the pointer comes to the top. On a
// phone: frosted bars above and below the picture (the way back and the name; 只看/控制 and the keyboard), always there.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { core } from "../core/react.ts";
import type { ScreenViewState } from "../core/shapes.ts";
import { ChevronLeft, Keyboard } from "@stillfail/ui/icons.tsx";
import { useAct } from "@stillfail/ui/toast.tsx";
import { ViewerBar, VIEWER_BAR_REACH } from "@stillfail/ui/viewer/ViewerBar.tsx";
import { panelEdge } from "@stillfail/ui/styles/controls.css.ts";
import { REST_MS } from "@stillfail/ui/viewer/rest.ts";
import { Button, PanelButton, Segmented, Tip } from "../ui.tsx";
import { t } from "../i18n.ts";
import { ScreenFrames, decodable, viewSize, type FrameConfig, type FrameHead } from "./frames.ts";
import { hearInput, type ScreenInput } from "./input.ts";
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

  const [attempt, setAttempt] = useState(0);
  const [shown, setShown] = useState<Shown | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [drawn, setDrawn] = useState(false);
  /** 只看/控制 as asked, until the core says it is so. */
  const [want, setWant] = useState<boolean | null>(null);
  const [typing, setTyping] = useState(false);

  const phase = failure ? "failed" : shown?.phase ?? "connecting";
  const live = phase === "live";
  const over = OVER.has(phase);
  const waiting = phase === "connecting" || phase === "reconnecting";
  const driving = live && shown?.control === true;
  const drivingRef = useRef(driving);
  drivingRef.current = driving;

  /** The picture fitted in the stage, whole, in the middle (letterboxed). */
  const place = useCallback(() => {
    const s = stage.current, p = picture.current;
    const { width, height } = size.current;
    if (!s || !p || !width || !height) return;
    const scale = Math.min(s.clientWidth / width, s.clientHeight / height);
    const w = Math.round(width * scale), h = Math.round(height * scale);
    p.style.width = `${w}px`;
    p.style.height = `${h}px`;
    p.style.left = `${Math.round((s.clientWidth - w) / 2)}px`;
    p.style.top = `${Math.round((s.clientHeight - h) / 2)}px`;
  }, []);
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
    const at = latest.current?.cursor;
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
        size.current = { width, height };
        place();
        setDrawn(true);
      },
    });
    const took = (state: ScreenViewState) => {
      latest.current = state;
      drawPointer();
      const { cursor: _, ...rest } = state;
      setShown((was) => (was && JSON.stringify(was) === JSON.stringify(rest) ? was : rest));
    };
    void decodable().then((codecs) => {
      if (!open) return;
      core().call("screen.view", { station, screen, view: name, codecs, ...viewSize() }, (value, bytes) => {
        if (!open) return;
        const v = value as { state?: ScreenViewState; config?: FrameConfig; frame?: FrameHead };
        if (v.frame) frames.frame(v.frame, bytes);
        else if (v.config) frames.config(v.config, bytes);
        else if (v.state) took(v.state);
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
    });
  }, [drawPointer]);
  // Only looking (or no longer live): the keys let go, the keyboard down.
  useEffect(() => {
    drawPointer();
    if (!driving && document.activeElement === keys.current) keys.current?.blur();
  }, [driving, drawPointer]);

  // 只看 / 控制: as asked at once, the core's word once it has said so (or back, if it could not).
  const act = useAct();
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
  const wake = useCallback(() => {
    setAwake(true);
    clearTimeout(rest.current);
    rest.current = window.setTimeout(() => setAwake(false), REST_MS);
  }, []);
  useEffect(() => { wake(); return () => clearTimeout(rest.current); }, [wake]);
  const touched = useRef(false);
  const onPointerMove = (e: React.PointerEvent) => {
    if (e.pointerType !== "mouse") { touched.current = true; clearTimeout(rest.current); setAwake(true); return; }
    touched.current = false;
    if (!drivingRef.current || e.clientY < VIEWER_BAR_REACH) wake();
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
  const modes = (
    <Tip label={cannot}>
      <span className={css.mode}>
        <Segmented label={t("web-pages.screen.mode")} value={control ? "control" : "look"} onChange={(v) => setControl(v === "control")}
          options={[{ value: "look", label: t("web-pages.screen.look") }, { value: "control", label: t("web-pages.screen.control"), disabled: !may || !live || undrivable }]} />
      </span>
    </Tip>
  );

  return (
    <div className={css.viewer} data-phone={phone || undefined} data-phase={phase} onPointerMove={onPointerMove} onPointerDown={onPointerMove}>
      <div ref={stage} className={css.stage} data-driving={driving || undefined}>
        <div ref={picture} className={css.picture} data-shown={drawn || undefined} data-faded={over || undefined}>
          <canvas ref={canvas} className={css.canvas} />
          <span ref={pointer} className={css.cursor} hidden><Arrow /></span>
        </div>
        <textarea ref={keys} className={css.keys} aria-label={t("web-pages.screen.keys")} tabIndex={-1} rows={1}
          autoCapitalize="off" autoCorrect="off" autoComplete="off" spellCheck={false}
          onFocus={() => setTyping(true)} onBlur={() => setTyping(false)} />
      </div>
      {waiting && (
        <div className={css.waiting} role="status">
          <span className={css.spinnerBox} aria-hidden="true"><span className={css.spinner} /></span>
          <span className={css.waitingText}>{phase === "reconnecting" ? t("web-pages.screen.reconnecting") : t("web-pages.screen.connecting")}</span>
        </div>
      )}
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
          {!over && (
            <div className={css.foot}>
              {takeOver ? <>{others}{takeOverButton}</> : modes}
              <Tip label={t("web-pages.screen.keyboard")}>
                <button type="button" className={css.keyboard} aria-label={t("web-pages.screen.keyboard")} aria-pressed={typing} disabled={!driving}
                  // The keyboard comes up for the field only from within the tap itself.
                  onClick={() => { if (typing) keys.current?.blur(); else keys.current?.focus({ preventScroll: true }); }}>
                  <Keyboard size={18} />
                </button>
              </Tip>
            </div>
          )}
        </>
      ) : (
        <ViewerBar back={{ label: backLabel, onClick: onBack }} name={title} meta={line}
          hidden={live && !awake && !touched.current && !takeOver && controllers.length === 0}
          tools={over ? undefined : takeOver ? <span className={css.takeOverTools}>{others}{takeOverButton}</span> : modes} />
      )}
    </div>
  );
}

/** The station's pointer: an arrow, its tip at the point. */
function Arrow() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
      <path d="M4 2L14.5 10.2L9.6 10.9L7.2 15.6Z" fill="#fff" stroke="#000" strokeWidth="1.2" strokeLinejoin="round" />
    </svg>
  );
}
