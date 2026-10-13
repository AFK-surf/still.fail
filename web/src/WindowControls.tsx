import { useEffect, useRef, useState } from "react";
import { Minus, Square, Copy, Close } from "./icons.tsx";
import { t } from "./i18n.ts";
import { iconBtn } from "./styles/pages.css.ts";
import * as css from "./WindowControls.css.ts";

type State = { maximized: boolean; fullscreen: boolean; hover: boolean; pressed: boolean };
const initial: State = { maximized: false, fullscreen: false, hover: false, pressed: false };

/** The same buttons as the page's toolbar, centred in its 44px row. The native target never paints. */
export function WindowControls() {
  const desktop = window.stillfailDesktop;
  const api = desktop?.frame === "custom" ? desktop.windowControls : undefined;
  const button = useRef<HTMLButtonElement>(null);
  const [state, setState] = useState(initial);
  useEffect(() => {
    if (!api) return;
    let live = true;
    const update = (value: unknown) => {
      if (live && value && typeof value === "object" && Object.keys(initial).every((key) => typeof (value as Record<string, unknown>)[key] === "boolean")) {
        setState(value as State);
      }
    };
    const off = api.watch(update);
    void api.state().then(update);
    return () => { live = false; off(); };
  }, [api]);
  useEffect(() => {
    if (!api || !button.current) return;
    const element = button.current;
    const measure = () => {
      const r = element.getBoundingClientRect();
      if (!r.width || !r.height || state.fullscreen) { api.bounds(null); return; }
      const scale = window.devicePixelRatio;
      const left = Math.round(r.left * scale), top = Math.round(r.top * scale);
      api.bounds([left, top, Math.round(r.right * scale) - left, Math.round(r.bottom * scale) - top]);
    };
    // Resizing, page zoom and moving to a monitor with another DPI all change client-pixel geometry.
    const observer = new ResizeObserver(measure);
    observer.observe(document.documentElement);
    observer.observe(element);
    window.addEventListener("resize", measure);
    measure();
    return () => { observer.disconnect(); window.removeEventListener("resize", measure); api.bounds(null); };
  }, [api, state.fullscreen, state.maximized]);
  if (!api) return null;
  const Maximize = state.maximized ? Copy : Square;
  const maxLabel = t(state.maximized ? "desktop.window.restore" : "desktop.window.maximize");
  return <div className={css.controls} role="group" aria-label={t("desktop.window.controls")}>
    <span className={css.separator} aria-hidden="true" />
    <button type="button" className={iconBtn} title={t("desktop.menu.minimize")} aria-label={t("desktop.menu.minimize")} onClick={() => api.action("minimize")}><Minus size={16} strokeWidth={1.7} /></button>
    <button type="button" ref={button} className={`${iconBtn} ${css.maximize}`} aria-label={maxLabel} data-hover={state.hover} data-pressed={state.pressed} onClick={() => api.action("maximize")}><Maximize size={16} strokeWidth={1.7} /></button>
    <button type="button" className={`${iconBtn} ${css.close}`} title={t("desktop.menu.close")} aria-label={t("desktop.menu.close")} onClick={() => api.action("close")}><Close size={16} strokeWidth={1.7} /></button>
  </div>;
}
