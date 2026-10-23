// What the screen's bar has (ScreenViewer.tsx) with a mouse, beside 只看/控制, as a remote desktop's window has it: how
// the view goes (a signal mark and the round trip; pressed, the whole of it: the way, packets lost, the frames and bits a
// second as they come, the picture's size and codec), and 控制中心, a menu of what can be done with the view: 画质 (how
// large a picture is asked for), 组合键 (the keys this device's own system would take for itself: ⌘Tab, Alt+Tab, the
// Windows key…, sent to the screen), sending files, a window of its own, 全屏, and 断开.
import { useEffect, useRef, useState, type MutableRefObject, type ReactNode } from "react";
import { DropdownMenu, Popover } from "radix-ui";
import type { ScreenViewState, StationNet } from "../core/shapes.ts";
import { Check, ChevronDown, ChevronRight, Close, Expand, External, Keyboard, Monitor, Shrink, Sliders, Upload } from "@stillfail/ui/icons.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { t } from "../i18n.ts";
import type { Quality } from "./frames.ts";
import * as css from "./ScreenViewer.css.ts";

/** What came of the view so far: frames and their bytes (counted as they come; read each second while shown). */
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

const QUALITIES = ["auto", "smooth", "hd", "original"] as const;

/** The frames and bits a second over the last second, read while `on`. */
function useRate(meter: MutableRefObject<Meter>, on: boolean): { fps: number; bps: number } | null {
  const [rate, setRate] = useState<{ fps: number; bps: number } | null>(null);
  const last = useRef<{ at: number; frames: number; bytes: number } | null>(null);
  useEffect(() => {
    if (!on) { last.current = null; setRate(null); return; }
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
  }, [on, meter]);
  return rate;
}

/** How the view goes: the signal mark (bars as the round trip is) and the round trip; pressed, the whole of it. */
export function NetChip({ net, shown, meter }: { net: StationNet | null; shown: Omit<ScreenViewState, "cursor"> | null; meter: MutableRefObject<Meter> }) {
  const [open, setOpen] = useState(false);
  const rate = useRate(meter, open);
  const level = net?.rtt?.level;
  const picture = shown?.width && shown.height ? `${shown.width}×${shown.height}` : "—";
  const codec = shown?.codec ? (shown.codec === "h264" ? "H.264" : shown.codec.toUpperCase()) : "—";
  const groups: [string, ReactNode][][] = [
    [
      [t("web-pages.screen.stat.fps"), rate ? `${Math.round(rate.fps)} fps` : "—"],
      [t("web-pages.screen.stat.bitrate"), rate ? bitrate(rate.bps) : "—"],
      [t("web-pages.screen.stat.loss"), net?.loss ? <span className={css.figure} data-level={net.loss.level}>{net.loss.text}</span> : "0%"],
    ],
    [[t("web-pages.screen.stat.path"), net?.path ?? "—"]],
    [[t("web-pages.screen.stat.picture"), picture], [t("web-pages.screen.stat.codec"), codec]],
  ];
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button type="button" className={css.netChip} aria-label={t("web-pages.screen.stats")} data-level={level}>
          <Bars level={level} />
          <span>{net?.rtt?.text ?? "—"}</span>
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={css.netPanel} side="bottom" align="center" sideOffset={6} collisionPadding={8}
          onOpenAutoFocus={(e) => e.preventDefault()} onCloseAutoFocus={(e) => e.preventDefault()}>
          <div className={css.netHead}>
            <span className={css.figure} data-level={level}><Bars level={level} /></span>
            <span>{t("web-pages.screen.stat.rtt")}</span>
            <b className={css.figure} data-level={level}>{net?.rtt?.text ?? "—"}</b>
          </div>
          {groups.map((group, i) => (
            <dl key={i} className={css.netRows}>
              {group.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
            </dl>
          ))}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** Three bars: all as the round trip is good, two as it is slow, one as it is very slow, none before it is known. */
function Bars({ level }: { level: string | undefined }) {
  const lit = level === "ok" ? 3 : level === "amber" ? 2 : level === "red" ? 1 : 0;
  return (
    <svg width="14" height="12" viewBox="0 0 14 12" aria-hidden="true">
      {[4, 7, 11].map((h, i) => <rect key={h} x={i * 5} y={12 - h} width="3" height={h} rx="1" fill="currentColor" opacity={i < lit ? 1 : 0.25} />)}
    </svg>
  );
}

/** 控制中心: what can be done with the view, as a menu (画质 and 组合键 open beside it). */
export function ControlCenter({ quality, onQuality, combos, onCombo, onSend, onWindow, full, onFull, onLeave }: {
  quality: Quality;
  onQuality: (q: Quality) => void;
  /** None while it is not driven. */
  combos: Combo[];
  onCombo: (c: Combo) => void;
  /** Sends files to its machine (while driving, where it takes them). */
  onSend?: (() => void) | undefined;
  /** Opens it in a window of its own (none where it is in one). */
  onWindow?: (() => void) | undefined;
  full: boolean;
  onFull: (on: boolean) => void;
  /** 断开: back where it was opened from. */
  onLeave: () => void;
}) {
  const item = `${controlsCss.menuItem} ${css.menuItem}`;
  const list = `${controlsCss.popover} ${controlsCss.menuList} ${css.menu}`;
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className={css.centerButton}>
        <Sliders size={16} /><span>{t("web-pages.screen.panel")}</span><ChevronDown size={12} />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={list} align="end" sideOffset={6} collisionPadding={8} onCloseAutoFocus={(e) => e.preventDefault()}>
          <DropdownMenu.Sub>
            <DropdownMenu.SubTrigger className={item}>
              <Monitor size={16} /><span className={css.menuWords}>{t("web-pages.screen.quality")}</span>
              <span className={css.menuEnd}>{t(`web-pages.screen.quality.${quality}`)}</span><ChevronRight size={14} />
            </DropdownMenu.SubTrigger>
            <DropdownMenu.Portal>
              <DropdownMenu.SubContent className={list} sideOffset={6} collisionPadding={8}>
                <DropdownMenu.RadioGroup value={quality} onValueChange={(v) => onQuality(v as Quality)}>
                  {QUALITIES.map((q) => (
                    <DropdownMenu.RadioItem key={q} value={q} className={item}>
                      <span className={css.menuCheck}><DropdownMenu.ItemIndicator><Check size={14} /></DropdownMenu.ItemIndicator></span>
                      <span className={css.menuWords}>{t(`web-pages.screen.quality.${q}`)}</span>
                      <span className={css.menuEnd}>{t(`web-pages.screen.qualityHint.${q}`)}</span>
                    </DropdownMenu.RadioItem>
                  ))}
                </DropdownMenu.RadioGroup>
              </DropdownMenu.SubContent>
            </DropdownMenu.Portal>
          </DropdownMenu.Sub>
          {combos.length > 0 && (
            <DropdownMenu.Sub>
              <DropdownMenu.SubTrigger className={item}>
                <Keyboard size={16} /><span className={css.menuWords}>{t("web-pages.screen.combos")}</span><ChevronRight size={14} />
              </DropdownMenu.SubTrigger>
              <DropdownMenu.Portal>
                <DropdownMenu.SubContent className={list} sideOffset={6} collisionPadding={8}>
                  {combos.map((c) => (
                    <DropdownMenu.Item key={c.keys} className={item} onSelect={() => onCombo(c)}>
                      <span className={css.menuWords}>{c.name}</span>
                      <span className={css.menuKeys}>{c.keys.split(" ").map((k) => <kbd key={k}>{k}</kbd>)}</span>
                    </DropdownMenu.Item>
                  ))}
                </DropdownMenu.SubContent>
              </DropdownMenu.Portal>
            </DropdownMenu.Sub>
          )}
          <DropdownMenu.Separator className={controlsCss.menuSep} />
          {onSend && (
            <DropdownMenu.Item className={item} onSelect={onSend}><Upload size={16} /><span className={css.menuWords}>{t("web-pages.screen.sendFile")}</span></DropdownMenu.Item>
          )}
          {onWindow && (
            <DropdownMenu.Item className={item} onSelect={onWindow}><External size={16} /><span className={css.menuWords}>{t("web-pages.screen.window")}</span></DropdownMenu.Item>
          )}
          <DropdownMenu.Item className={item} onSelect={() => onFull(!full)}>
            {full ? <Shrink size={16} /> : <Expand size={16} />}<span className={css.menuWords}>{full ? t("web-pages.screen.unfull") : t("web-pages.screen.full")}</span>
          </DropdownMenu.Item>
          <DropdownMenu.Separator className={controlsCss.menuSep} />
          <DropdownMenu.Item className={item} data-danger onSelect={onLeave}><Close size={16} /><span className={css.menuWords}>{t("web-pages.screen.leave")}</span></DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** Bits a second, as a link's speed is said: 850 kbps, 4.2 Mbps. */
function bitrate(bps: number): string {
  if (bps >= 1e6) return `${(bps / 1e6).toFixed(bps >= 1e7 ? 0 : 1)} Mbps`;
  return `${Math.round(bps / 1e3)} kbps`;
}
