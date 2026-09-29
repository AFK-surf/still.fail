// The page's size in a preview, chosen: as big as the preview, a phone's to a desktop's, any size typed, turned. With
// a pointer it is the bar's button (the size and how much it is drawn at, and a turn beside it) opening a popover, which
// also zooms; on a touch screen it is the toolbar over the page (PreviewStage.tsx), whose "自定义" opens the same
// choices in a sheet from the bottom.
import { Dialog, Popover } from "radix-ui";
import { useEffect, useState, useSyncExternalStore } from "react";
import { Check, Devices, Landscape, Minus, Plus } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import { LIMIT, PRESETS, presetOf, setViewport, type Viewport } from "./viewport.ts";
import * as css from "./ViewportSize.css.ts";

const TOUCH = "(hover: none) and (pointer: coarse)";
export function useTouch(): boolean {
  return useSyncExternalStore((listener) => {
    const query = matchMedia(TOUCH);
    query.addEventListener("change", listener);
    return () => query.removeEventListener("change", listener);
  }, () => matchMedia(TOUCH).matches);
}

/** `390 × 844`, with `×` a little apart. */
export const dims = (w: number, h: number | null) => `${Math.round(w)} × ${h === null ? "自动" : Math.round(h)}`;

/** How the page is drawn now, and moving it on: zooming in and out (about `at` in the stage, else its middle), and back
 * to fitted. */
export interface Zoom { scale: number; free: boolean; zoom(factor: number, at?: { x: number; y: number }): void; fit(): void }

/**
 * The bar's button for the page's size in the preview `viewKey`, with a turn beside it once there is a height to turn.
 * `compact`: the bar has other things to say (marking the page), so the icon alone. A touch screen has its toolbar
 * under the page instead: here only a button that opens it again once it was folded away.
 */
export function ViewportButton({ viewKey, viewport, zoom, turn, compact = false, folded, unfold }:
  { viewKey: string; viewport: Viewport | null; zoom: Zoom; turn(): void; compact?: boolean; folded: boolean; unfold(): void }) {
  const touch = useTouch();
  const [open, setOpen] = useState(false);
  if (touch) {
    return folded ? (
      <button type="button" className={css.button} data-sized={viewport ? true : undefined} aria-label="页面尺寸" onClick={unfold}>
        <Devices size={14} strokeWidth={1.75} />
        {viewport && <span className={css.buttonText}>{dims(viewport.width, viewport.height)}</span>}
      </button>
    ) : null;
  }
  const turnable = viewport?.height != null && !compact;
  return (
    <>
      <Popover.Root open={open} onOpenChange={setOpen}>
        <Tip label={open ? null : "页面尺寸"}>
          <Popover.Trigger asChild>
            <button type="button" className={css.button} data-sized={viewport && !compact ? true : undefined} aria-label="页面尺寸">
              <Devices size={14} strokeWidth={1.75} />
              {viewport && !compact && (
                <span className={css.buttonText}>
                  {dims(viewport.width, viewport.height)}
                  <span className={css.buttonScale}>{Math.round(zoom.scale * 100)}%</span>
                </span>
              )}
            </button>
          </Popover.Trigger>
        </Tip>
        <Popover.Portal>
          <Popover.Content className={css.popover} align="end" sideOffset={6} collisionPadding={8} onOpenAutoFocus={(e) => e.preventDefault()}>
            <Panel viewKey={viewKey} viewport={viewport} zoom={zoom} turn={turn} done={() => setOpen(false)} />
          </Popover.Content>
        </Popover.Portal>
      </Popover.Root>
      {turnable && (
        <Tip label="横竖互换">
          <button type="button" className={css.turnBar} aria-label="横竖互换" onClick={turn}><Landscape size={15} strokeWidth={1.75} /></button>
        </Tip>
      )}
    </>
  );
}

/** The choices in a sheet from the bottom (a touch screen's "自定义"). */
export function ViewportSheet({ open, onOpenChange, viewKey, viewport, turn }:
  { open: boolean; onOpenChange(open: boolean): void; viewKey: string; viewport: Viewport | null; turn(): void }) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className={css.sheetShade} />
        <Dialog.Content className={css.sheet} aria-describedby={undefined} onOpenAutoFocus={(e) => e.preventDefault()}>
          <span className={css.sheetGrab} aria-hidden />
          <Dialog.Title className={css.sheetTitle}>页面尺寸</Dialog.Title>
          <Panel viewKey={viewKey} viewport={viewport} turn={turn} touch done={() => onOpenChange(false)} />
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

/** What the page's size can be. A preset (or as big as the preview) is chosen and done with; typed sizes, turning and
 * zooming stay open to be tried. */
function Panel({ viewKey, viewport, zoom, turn, touch = false, done }:
  { viewKey: string; viewport: Viewport | null; zoom?: Zoom; turn(): void; touch?: boolean; done(): void }) {
  const set = (v: Viewport | null) => setViewport(viewKey, v);
  const preset = presetOf(viewport);
  const choose = (v: Viewport | null) => { set(v); done(); };
  return (
    <div className={css.panel} data-touch={touch || undefined}>
      <Option checked={!viewport} name="自适应" note="跟随预览区" onChoose={() => choose(null)} />
      {PRESETS.map((p) => (
        // Each as it is made (a phone upright, a laptop wide); the one chosen stays as it was turned.
        <Option key={p.name} checked={preset === p.name} name={p.name} note={dims(p.width, p.height)}
          onChoose={() => choose(preset === p.name ? viewport : { width: p.width, height: p.height })} />
      ))}
      <div className={css.sep} />
      <Custom viewport={viewport} set={set} turn={turn} />
      {zoom && (
        <>
          <div className={css.sep} />
          <div className={css.row}>
            <span className={css.label}>缩放</span>
            <div className={css.zoom}>
              <button type="button" className={css.turn} aria-label="缩小" disabled={!viewport} onClick={() => zoom.zoom(1 / 1.25)}><Minus size={14} strokeWidth={2} /></button>
              <span className={css.zoomValue}>{viewport ? `${Math.round(zoom.scale * 100)}%` : "—"}</span>
              <button type="button" className={css.turn} aria-label="放大" disabled={!viewport} onClick={() => zoom.zoom(1.25)}><Plus size={14} strokeWidth={2} /></button>
            </div>
            <button type="button" className={css.fit} disabled={!viewport || !zoom.free} onClick={zoom.fit}>适应</button>
          </div>
          <p className={css.hint}>拖灰底或按住空格拖页面来移动，⌘/Ctrl + 滚轮缩放，双击灰底适应</p>
        </>
      )}
    </div>
  );
}

function Option({ checked, name, note, onChoose }: { checked: boolean; name: string; note: string; onChoose(): void }) {
  return (
    <button type="button" className={css.option} aria-pressed={checked} onClick={onChoose}>
      <span className={css.check}>{checked && <Check size={14} strokeWidth={2} />}</span>
      <span className={css.optionName}>{name}</span>
      <span className={css.optionNote}>{note}</span>
    </button>
  );
}

/** Any size, typed: the width, and the height (empty: as high as the preview leaves it); turned by the button. */
function Custom({ viewport, set, turn }: { viewport: Viewport | null; set(v: Viewport | null): void; turn(): void }) {
  const [w, setW] = useState(viewport ? String(viewport.width) : "");
  const [h, setH] = useState(viewport?.height != null ? String(viewport.height) : "");
  // What it is now shows here unless it is being typed.
  const [typing, setTyping] = useState(false);
  useEffect(() => {
    if (typing) return;
    setW(viewport ? String(viewport.width) : "");
    setH(viewport?.height != null ? String(viewport.height) : "");
  }, [viewport, typing]);
  const commit = () => {
    const width = parseInt(w, 10), height = h.trim() ? parseInt(h, 10) : null;
    if (!Number.isFinite(width) || (height !== null && !Number.isFinite(height))) return;
    if (viewport && width === viewport.width && height === viewport.height) return;
    set({ width, height });
  };
  const field = (value: string, change: (v: string) => void, label: string, placeholder: string) => (
    <input className={css.field} value={value} inputMode="numeric" aria-label={label} placeholder={placeholder}
      onChange={(e) => change(e.target.value.replace(/\D/g, "").slice(0, 4))}
      onFocus={(e) => { setTyping(true); e.currentTarget.select(); }}
      onBlur={() => { setTyping(false); commit(); }}
      onKeyDown={(e) => {
        if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); commit(); }
        else if (e.key === "ArrowUp" || e.key === "ArrowDown") {
          // Up and down step it (by 10 with shift), as a number field would.
          e.preventDefault();
          const now = parseInt(value, 10) || (label === "宽" ? viewport?.width ?? 390 : 800);
          const next = Math.max(LIMIT.min, Math.min(LIMIT.max, now + (e.key === "ArrowUp" ? 1 : -1) * (e.shiftKey ? 10 : 1)));
          change(String(next));
        }
      }} />
  );
  const turnable = viewport !== null && viewport.height !== null;
  return (
    <div className={css.row}>
      <span className={css.label}>自定义</span>
      <div className={css.fields}>
        {field(w, setW, "宽", "宽")}
        <span className={css.times} aria-hidden>×</span>
        {field(h, setH, "高", "自动")}
      </div>
      <Tip label={turnable ? "横竖互换" : null}>
        <button type="button" className={css.turn} aria-label="横竖互换" disabled={!turnable} onClick={turn}>
          <Landscape size={15} strokeWidth={1.75} />
        </button>
      </Tip>
    </div>
  );
}
