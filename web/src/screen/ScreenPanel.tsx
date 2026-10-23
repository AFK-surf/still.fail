// The screen's panel, from its bar (ScreenViewer.tsx), with a mouse: how large a picture is asked for (画质), the keys
// this device's own system would take for itself (组合键: ⌘Tab, Alt+Tab, the Windows key…) sent to the screen, 全屏, and
// how the view goes (连接: the way and round trip as the station page says them, the frames and bits a second as they
// come, the picture's size and codec).
import { useEffect, useRef, useState, type MutableRefObject } from "react";
import { Popover } from "radix-ui";
import type { ScreenViewState, StationNet } from "../core/shapes.ts";
import { Sliders } from "@stillfail/ui/icons.tsx";
import { PanelGroup, PanelRow, Segmented, Tip } from "../ui.tsx";
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
  const figures: [string, React.ReactNode][] = [
    [t("web-pages.screen.stat.path"), net?.path ?? "—"],
    [t("web-pages.screen.stat.rtt"), net?.rtt ? <span className={css.figure} data-level={net.rtt.level}>{net.rtt.text}</span> : "—"],
    ...(net?.loss ? [[t("web-pages.screen.stat.loss"), <span className={css.figure} data-level={net.loss.level}>{net.loss.text}</span>] as [string, React.ReactNode]] : []),
    [t("web-pages.screen.stat.fps"), rate ? `${Math.round(rate.fps)} fps` : "—"],
    [t("web-pages.screen.stat.bitrate"), rate ? bitrate(rate.bps) : "—"],
    [t("web-pages.screen.stat.picture"), shown?.width && shown.height ? `${shown.width}×${shown.height}${shown.codec ? ` · ${shown.codec === "h264" ? "H.264" : shown.codec.toUpperCase()}` : ""}` : "—"],
  ];
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Tip label={label}>
        <Popover.Trigger asChild>
          <button type="button" className={`${pageCss.iconBtn} ${tool}`} aria-label={label} data-on={open || undefined}><Sliders size={18} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={css.panel} side="bottom" align="end" sideOffset={6} collisionPadding={8}
          onOpenAutoFocus={(e) => e.preventDefault()} onCloseAutoFocus={(e) => e.preventDefault()}>
          <PanelGroup label={t("web-pages.screen.quality")}>
            <div className={css.panelPad}>
              <Segmented label={t("web-pages.screen.quality")} value={quality} onChange={onQuality}
                options={(["auto", "smooth", "hd", "original"] as const).map((q) => ({ value: q, label: t(`web-pages.screen.quality.${q}`) }))} />
            </div>
          </PanelGroup>
          {combos.length > 0 && (
            <PanelGroup label={t("web-pages.screen.combos")}>
              {combos.map((c) => <PanelRow key={c.keys} label={c.name} end={<kbd className={css.keysShown}>{c.keys}</kbd>} onClick={() => onCombo(c)} />)}
            </PanelGroup>
          )}
          <PanelGroup>
            <PanelRow label={full ? t("web-pages.screen.unfull") : t("web-pages.screen.full")} onClick={() => { setOpen(false); onFull(!full); }} />
          </PanelGroup>
          <PanelGroup label={t("web-pages.screen.stats")}>
            <dl className={css.stats}>
              {figures.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
            </dl>
          </PanelGroup>
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
