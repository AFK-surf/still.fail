// The screen's panel, from its bar (ScreenViewer.tsx), with a mouse: how large a picture is asked for (画质), the keys
// this device's own system would take for itself (组合键: ⌘Tab, Alt+Tab, the Windows key…) sent to the screen, 全屏, and
// how the view goes (连接: the way and round trip as the station page says them, the frames and bits a second as they
// come, the picture's size and codec).
import { useEffect, useRef, useState, type MutableRefObject } from "react";
import { Popover } from "radix-ui";
import type { ScreenViewState, StationNet } from "../core/shapes.ts";
import { Expand, Shrink, Sliders } from "@stillfail/ui/icons.tsx";
import { Segmented, Tip } from "../ui.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";
import { tool } from "@stillfail/ui/viewer/ViewerBar.css.ts";
import { t } from "../i18n.ts";
import type { Quality } from "./frames.ts";
import * as css from "./ScreenViewer.css.ts";

/** What came of the view so far: frames and their bytes (counted as they come; the panel reads them each second). */
export type Meter = { frames: number; bytes: number };

/** A key sent with modifiers (bit 0 Alt, 1 Ctrl, 2 Meta, 3 Shift: input.ts), as the screen's system names it. */
export type Combo = { name: string; keys: string; key: string; code: string; mods: number };

const ALT = 1, CTRL = 2, META = 4, SHIFT = 8;

/** The combos worth sending to a station's system: what this device would keep for itself, or has no key for. */
export function combosFor(os: string | undefined): Combo[] {
  if (os === "macos") return [
    { name: t("web-pages.screen.combo.switchApp"), keys: "⌘ Tab", key: "Tab", code: "Tab", mods: META },
    { name: t("web-pages.screen.combo.spotlight"), keys: "⌘ Space", key: " ", code: "Space", mods: META },
    { name: t("web-pages.screen.combo.missionControl"), keys: "⌃ ↑", key: "ArrowUp", code: "ArrowUp", mods: CTRL },
    { name: t("web-pages.screen.combo.forceQuit"), keys: "⌘ ⌥ Esc", key: "Escape", code: "Escape", mods: META | ALT },
    { name: t("web-pages.screen.combo.quit"), keys: "⌘ Q", key: "q", code: "KeyQ", mods: META },
    { name: t("web-pages.screen.combo.screenshot"), keys: "⌘ ⇧ 4", key: "4", code: "Digit4", mods: META | SHIFT },
  ];
  return [
    { name: t("web-pages.screen.combo.start"), keys: "Win", key: "Meta", code: "MetaLeft", mods: 0 },
    { name: t("web-pages.screen.combo.switchWindow"), keys: "Alt Tab", key: "Tab", code: "Tab", mods: ALT },
    { name: t("web-pages.screen.combo.desktop"), keys: "Win D", key: "d", code: "KeyD", mods: META },
    { name: t("web-pages.screen.combo.taskManager"), keys: "Ctrl Shift Esc", key: "Escape", code: "Escape", mods: CTRL | SHIFT },
    { name: t("web-pages.screen.combo.close"), keys: "Alt F4", key: "F4", code: "F4", mods: ALT },
    { name: t("web-pages.screen.combo.snip"), keys: "Win Shift S", key: "s", code: "KeyS", mods: META | SHIFT },
  ];
}

export function ScreenPanel({ quality, onQuality, combos, onCombo, full, onFull, net, shown, meter }: {
  quality: Quality;
  onQuality: (q: Quality) => void;
  /** None while it is not driven. */
  combos: Combo[];
  onCombo: (c: Combo) => void;
  full: boolean;
  onFull: (on: boolean) => void;
  net: StationNet | null;
  shown: Omit<ScreenViewState, "cursor"> | null;
  meter: MutableRefObject<Meter>;
}) {
  const [open, setOpen] = useState(false);
  const [rate, setRate] = useState<{ fps: number; bps: number } | null>(null);
  const last = useRef<{ at: number; frames: number; bytes: number } | null>(null);
  // Each second while open: the frames and bits that came since.
  useEffect(() => {
    if (!open) { last.current = null; setRate(null); return; }
    const read = () => {
      const now = performance.now(), m = meter.current, was = last.current;
      if (was && now > was.at) {
        const s = (now - was.at) / 1000;
        setRate({ fps: (m.frames - was.frames) / s, bps: ((m.bytes - was.bytes) * 8) / s });
      }
      last.current = { at: now, frames: m.frames, bytes: m.bytes };
    };
    read();
    const timer = window.setInterval(read, 1000);
    return () => clearInterval(timer);
  }, [open, meter]);

  const label = t("web-pages.screen.panel");
  const picture = shown?.width && shown.height ? `${shown.width}×${shown.height}${shown.codec ? ` · ${shown.codec === "h264" ? "H.264" : shown.codec.toUpperCase()}` : ""}` : null;
  // The view's figures first, as tiles: the round trip in its colour (and packets lost, when some are), the frames and
  // bits a second, the way.
  const tiles: { label: string; value: string; level?: string | undefined }[] = [
    { label: t("web-pages.screen.stat.rtt"), value: net?.rtt?.text ?? "—", level: net?.rtt?.level },
    { label: t("web-pages.screen.stat.fps"), value: rate ? String(Math.round(rate.fps)) : "—" },
    { label: t("web-pages.screen.stat.bitrate"), value: rate ? bitrate(rate.bps) : "—" },
    { label: t("web-pages.screen.stat.path"), value: net?.path ?? "—" },
  ];
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Tip label={label}>
        <Popover.Trigger asChild>
          <button type="button" className={`${pageCss.iconBtn} ${tool}`} aria-label={label} aria-expanded={open} data-on={open || undefined}><Sliders size={18} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={css.panel} side="bottom" align="end" sideOffset={6} collisionPadding={8} aria-label={label}
          onOpenAutoFocus={(e) => e.preventDefault()} onCloseAutoFocus={(e) => e.preventDefault()}>
          <div className={css.view}>
          <div className={css.tiles}>
            {tiles.map((tile) => (
              <div key={tile.label} className={css.tile}>
                <b className={css.figure} data-level={tile.level}>{tile.value}</b>
                <span>{tile.label}</span>
              </div>
            ))}
          </div>
          {(picture || net?.loss) && (
            <div className={css.tilesNote}>
              {picture}
              {net?.loss && <>{picture && " · "}<span className={css.figure} data-level={net.loss.level}>{net.loss.text}</span></>}
            </div>
          )}
          </div>
          <div className={css.section}>
            <span className={css.sectionLabel}>{t("web-pages.screen.quality")}</span>
            <Segmented label={t("web-pages.screen.quality")} value={quality} onChange={onQuality}
              options={(["auto", "smooth", "hd", "original"] as const).map((q) => ({ value: q, label: t(`web-pages.screen.quality.${q}`) }))} />
          </div>
          {combos.length > 0 && (
            <div className={css.section}>
              <span className={css.sectionLabel}>{t("web-pages.screen.combos")}</span>
              <div className={css.combos}>
                {combos.map((c) => (
                  <button key={c.keys} type="button" className={css.combo} onClick={() => onCombo(c)}>
                    <span className={css.keycaps}>{c.keys.split(" ").map((k) => <kbd key={k} className={css.keycap}>{k}</kbd>)}</span>
                    <span className={css.comboName}>{c.name}</span>
                  </button>
                ))}
              </div>
            </div>
          )}
          <div className={css.section}>
            <button type="button" className={css.fullRow} onClick={() => { setOpen(false); onFull(!full); }}>
              {full ? <Shrink size={16} /> : <Expand size={16} />}
              <span>{full ? t("web-pages.screen.unfull") : t("web-pages.screen.full")}</span>
            </button>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** Bits a second, as a link's speed is said: 850 kbps, 4.2 Mbps. */
function bitrate(bps: number): string {
  if (bps >= 1e6) return `${(bps / 1e6).toFixed(bps >= 1e7 ? 0 : 1)} Mbps`;
  return `${Math.round(bps / 1e3)} kbps`;
}
