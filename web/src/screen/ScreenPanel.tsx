// What the screen's bar has (ScreenViewer.tsx) with a mouse, beside 只看/控制, as a remote desktop's window has it: how
// the view goes (a signal mark and how long it has been seen; pressed, the whole of it under the round trip), and 控制中心, a menu of what can be done with the view: 画质 (how
// large a picture is asked for), 缩放 (the screen's own display scale, where its station changes it: Windows), 组合键 (the keys this device's own system would take for itself: ⌘Tab, Alt+Tab, the
// Windows key…, sent to the screen), sending files, a window of its own, 全屏, and 断开.
import { useEffect, useRef, useState, type MutableRefObject, type ReactNode } from "react";
import { DropdownMenu, Popover } from "radix-ui";
import type { ScreenScale, ScreenViewState, StationNet } from "../core/shapes.ts";
import { Chat, Check, ChevronDown, ChevronRight, Close, Expand, External, Keyboard, Monitor, Play, Shrink, Sliders, TextSize, Trash, Upload } from "@stillfail/ui/icons.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { Keys } from "../ui.tsx";
import { t } from "../i18n.ts";
import { FPS_CHOICES, type DecodeStats, type Fps, type Quality } from "./frames.ts";
import * as css from "./ScreenViewer.css.ts";

/** What came of the view so far: frames and their bytes (counted as they come; read each second while shown), and how
 * the page's decoder goes. */
export type Meter = { frames: number; bytes: number; decode?: () => DecodeStats };

/** A key sent with modifiers (bit 0 Alt, 1 Ctrl, 2 Meta, 3 Shift: input.ts), as the screen's system names it. */
export type Combo = { name: string; keys: string; key: string; code: string; mods: number };

const ALT = 1, CTRL = 2, META = 4, SHIFT = 8;

/** The combos worth sending to a station's system (its host's `os`, in words: macOS 26.6.2, Windows 11 Pro…): what
 * this device would keep for itself, or has no key for. */
export function combosFor(os: string | undefined): Combo[] {
  if (/^mac|darwin/i.test(os ?? "")) return [
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

/** How the view goes, as a remote desktop's window says it: the signal mark (its bars and colour as the round trip is)
 * and how long it has been seen; pressed, the whole of it under the round trip: frames and bits a second, packets
 * lost; the way and the station's system; the picture's size and codec, what captures it and whether it is encoded on
 * the hardware. */
export function NetChip({ net, shown, meter, os }: { net: StationNet | null; shown: Omit<ScreenViewState, "cursor"> | null; meter: MutableRefObject<Meter>; os: string | undefined }) {
  const [open, setOpen] = useState(false);
  const rate = useRate(meter, open);
  const since = useSince();
  const level = net?.rtt?.level;
  // Read again each second while open (the rate's ticks draw it anew).
  const decode = open ? meter.current.decode?.() : undefined;
  const [copied, setCopied] = useState(false);
  const groups: [string, ReactNode][][] = [
    [
      [t("web-pages.screen.stat.frameLatency"), shown?.latency ? `${shown.latency.frame} ms` : "—"],
      [t("web-pages.screen.stat.beforeSent"), shown?.latency ? `${shown.latency.before} ms` : "—"],
      [t("web-pages.screen.stat.decode"), decode?.ms != null
        ? <>{decode.ms} ms{decode.held > 0 && <span className={css.figure} data-level="amber">{` · ${t("web-pages.screen.stat.held", { count: decode.held })}`}</span>}</> : "—"],
      [t("web-pages.screen.stat.fps"), rate ? String(Math.round(rate.fps)) : "—"],
      [t("web-pages.screen.stat.bitrate"), rate ? bitrate(rate.bps) : "—"],
      [t("web-pages.screen.stat.loss"), net?.loss ? <span className={css.figure} data-level={net.loss.level}>{net.loss.text}</span> : "0%"],
    ],
    [
      [t("web-pages.screen.stat.path"), net?.path ?? "—"],
      [t("web-pages.screen.stat.system"), os ?? "—"],
    ],
    [
      [t("web-pages.screen.stat.picture"), shown?.width && shown.height ? `${shown.width}×${shown.height}` : "—"],
      [t("web-pages.screen.stat.codec"), shown?.codec ? (shown.codec === "h264" ? "H.264" : shown.codec === "h265" ? "H.265" : shown.codec.toUpperCase()) : "—"],
      [t("web-pages.screen.stat.capture"), shown?.video?.capture ?? "—"],
      [t("web-pages.screen.stat.encoder"), shown?.video?.hardware === undefined ? "—"
        : <span title={shown.video.encoder}>{t(shown.video.hardware ? "web-pages.screen.stat.hardware" : "web-pages.screen.stat.software")}</span>],
    ],
  ];
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button type="button" className={css.netChip} aria-label={t("web-pages.screen.stats")}>
          <span className={css.netMark} data-level={level}><Bars level={level} /></span>
          <span className={css.netTime}>{since}</span>
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={css.netPanel} side="bottom" align="start" sideOffset={6} collisionPadding={8}
          onOpenAutoFocus={(e) => e.preventDefault()} onCloseAutoFocus={(e) => e.preventDefault()}>
          <div className={css.netHead}>
            <span className={css.netHeadMark} data-level={level}><Bars level={level} size={20} /></span>
            <b>{t("web-pages.screen.stat.rttHead", { rtt: net?.rtt?.text ?? "—" })}</b>
          </div>
          {groups.map((group, i) => (
            <dl key={i} className={css.netRows}>
              {group.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
            </dl>
          ))}
          <button type="button" className={css.netCopy} onClick={() => {
            // Everything above as figures (no screen, no names), for a report.
            const said = {
              rtt: net?.rtt?.text, loss: net?.loss?.text ?? "0%", path: net?.path, system: os, fps: rate ? Math.round(rate.fps) : null,
              bps: rate ? Math.round(rate.bps) : null, picture: shown?.width ? `${shown.width}x${shown.height}` : null, codec: shown?.codec,
              latency: shown?.latency ?? null, video: shown?.video ?? null, decode: decode ?? null, agent: navigator.userAgent,
            };
            void navigator.clipboard?.writeText(JSON.stringify(said)).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1500); }, () => {});
          }}>{t(copied ? "web-pages.screen.stat.copied" : "web-pages.screen.stat.copy")}</button>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** How long it has been seen (from when this was first drawn): 00:20:50, a second at a time. */
function useSince(): string {
  const start = useRef(performance.now());
  const [now, setNow] = useState(start.current);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(performance.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const s = Math.max(0, Math.floor((now - start.current) / 1000));
  const two = (n: number) => String(n).padStart(2, "0");
  return `${two(Math.floor(s / 3600))}:${two(Math.floor(s / 60) % 60)}:${two(s % 60)}`;
}

/** Three bars: all as the round trip is good, two as it is slow, one as it is very slow, none before it is known. */
function Bars({ level, size = 14 }: { level: string | undefined; size?: number }) {
  const lit = level === "ok" ? 3 : level === "amber" ? 2 : level === "red" ? 1 : 0;
  return (
    <svg width={size} height={(size * 12) / 14} viewBox="0 0 14 12" aria-hidden="true">
      {[4, 7, 11].map((h, i) => <rect key={h} x={i * 5} y={12 - h} width="3" height={h} rx="1" fill="currentColor" opacity={i < lit ? 1 : 0.25} />)}
    </svg>
  );
}

/** A scale as the menu says it: 150%, and 推荐 beside the one its system recommends. */
function scaleWords(percent: number, scale: ScreenScale): string {
  return percent === scale.recommended ? t("web-pages.screen.scaleRecommended", { percent }) : `${percent}%`;
}

/** The scale's steps as radio items, the one now checked. */
function ScaleItems({ scale, onScale, item }: { scale: ScreenScale; onScale: (percent: number) => void; item: string }) {
  return (
    <DropdownMenu.RadioGroup value={String(scale.percent)} onValueChange={(v) => onScale(Number(v))}>
      {scale.steps.map((p) => (
        <DropdownMenu.RadioItem key={p} value={String(p)} className={item}>
          <span className={css.menuCheck}><DropdownMenu.ItemIndicator><Check size={14} /></DropdownMenu.ItemIndicator></span>
          <span className={css.menuWords}>{scaleWords(p, scale)}</span>
        </DropdownMenu.RadioItem>
      ))}
    </DropdownMenu.RadioGroup>
  );
}

/** A phone's 缩放: its button in the viewer's foot, the steps above it. */
export function ScaleButton({ scale, onScale, className }: { scale: ScreenScale; onScale: (percent: number) => void; className: string }) {
  const item = `${controlsCss.menuItem} ${css.menuItem}`;
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className={className} aria-label={t("web-pages.screen.scale")}><TextSize size={18} /></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${css.menu}`} side="top" sideOffset={6} collisionPadding={8} onCloseAutoFocus={(e) => e.preventDefault()}>
          <ScaleItems scale={scale} onScale={onScale} item={item} />
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** A 帧率 as the menu says it: 自动, or its frames a second. */
const fpsLabel = (f: Fps) => (f === "auto" ? t("web-pages.screen.fps.auto") : String(f));

/** 控制中心: what can be done with the view, as a menu (画质, 缩放 and 组合键 open beside it). */
export function ControlCenter({ quality, onQuality, fps, onFps, codec, onCodec, scale, onScale, combos, onCombo, onSend, onWindow, full, onFull, chat, onClose, onLeave }: {
  quality: Quality;
  onQuality: (q: Quality) => void;
  /** The most frames a second asked (帧率): `auto` as many as come. */
  fps: Fps;
  onFps: (f: Fps) => void;
  /** The codec asked: the best both ends have, or H.264 only. */
  codec: "auto" | "h264";
  onCodec: (c: "auto" | "h264") => void;
  /** The screen's display scale, while driving one whose station changes it. */
  scale?: ScreenScale | undefined;
  onScale: (percent: number) => void;
  /** None while it is not driven. */
  combos: Combo[];
  onCombo: (c: Combo) => void;
  /** Sends files to its machine (while driving, where it takes them). */
  onSend?: (() => void) | undefined;
  /** Opens it in a window of its own (none where it is in one). */
  onWindow?: (() => void) | undefined;
  full: boolean;
  onFull: (on: boolean) => void;
  /** The chat that opened it (a tab of the station's browser), and going there. */
  chat?: { title: string; open: () => void } | undefined;
  /** Closes it for good (a tab of the station's browser). */
  onClose?: (() => void) | undefined;
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
          <DropdownMenu.Sub>
            <DropdownMenu.SubTrigger className={item}>
              <Play size={16} /><span className={css.menuWords}>{t("web-pages.screen.fps")}</span>
              <span className={css.menuEnd}>{fpsLabel(fps)}</span><ChevronRight size={14} />
            </DropdownMenu.SubTrigger>
            <DropdownMenu.Portal>
              <DropdownMenu.SubContent className={list} sideOffset={6} collisionPadding={8}>
                <DropdownMenu.RadioGroup value={String(fps)} onValueChange={(v) => onFps(v === "auto" ? "auto" : (Number(v) as Fps))}>
                  {FPS_CHOICES.map((f) => (
                    <DropdownMenu.RadioItem key={f} value={String(f)} className={item}>
                      <span className={css.menuCheck}><DropdownMenu.ItemIndicator><Check size={14} /></DropdownMenu.ItemIndicator></span>
                      <span className={css.menuWords}>{fpsLabel(f)}</span>
                      {f === "auto" && <span className={css.menuEnd}>{t("web-pages.screen.fpsHint.auto")}</span>}
                    </DropdownMenu.RadioItem>
                  ))}
                </DropdownMenu.RadioGroup>
              </DropdownMenu.SubContent>
            </DropdownMenu.Portal>
          </DropdownMenu.Sub>
          <DropdownMenu.Sub>
            <DropdownMenu.SubTrigger className={item}>
              <Monitor size={16} /><span className={css.menuWords}>{t("web-pages.screen.codec")}</span>
              <span className={css.menuEnd}>{t(`web-pages.screen.codec.${codec}`)}</span><ChevronRight size={14} />
            </DropdownMenu.SubTrigger>
            <DropdownMenu.Portal>
              <DropdownMenu.SubContent className={list} sideOffset={6} collisionPadding={8}>
                <DropdownMenu.RadioGroup value={codec} onValueChange={(v) => onCodec(v as "auto" | "h264")}>
                  {(["auto", "h264"] as const).map((c) => (
                    <DropdownMenu.RadioItem key={c} value={c} className={item}>
                      <span className={css.menuCheck}><DropdownMenu.ItemIndicator><Check size={14} /></DropdownMenu.ItemIndicator></span>
                      <span className={css.menuWords}>{t(`web-pages.screen.codec.${c}`)}</span>
                      <span className={css.menuEnd}>{t(`web-pages.screen.codecHint.${c}`)}</span>
                    </DropdownMenu.RadioItem>
                  ))}
                </DropdownMenu.RadioGroup>
              </DropdownMenu.SubContent>
            </DropdownMenu.Portal>
          </DropdownMenu.Sub>
          {scale && (
            <DropdownMenu.Sub>
              <DropdownMenu.SubTrigger className={item}>
                <TextSize size={16} /><span className={css.menuWords}>{t("web-pages.screen.scale")}</span>
                <span className={css.menuEnd}>{scale.percent}%</span><ChevronRight size={14} />
              </DropdownMenu.SubTrigger>
              <DropdownMenu.Portal>
                <DropdownMenu.SubContent className={list} sideOffset={6} collisionPadding={8}>
                  <ScaleItems scale={scale} onScale={onScale} item={item} />
                </DropdownMenu.SubContent>
              </DropdownMenu.Portal>
            </DropdownMenu.Sub>
          )}
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
                      <Keys caps={c.keys.split(" ")} />
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
          {chat && (
            <DropdownMenu.Item className={item} onSelect={chat.open}><Chat size={16} /><span className={css.menuWords}>{t("web-pages.screen.openChat", { title: chat.title })}</span></DropdownMenu.Item>
          )}
          <DropdownMenu.Separator className={controlsCss.menuSep} />
          {onClose && (
            <DropdownMenu.Item className={item} data-danger onSelect={onClose}><Trash size={16} /><span className={css.menuWords}>{t("web-pages.screen.close")}</span></DropdownMenu.Item>
          )}
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
