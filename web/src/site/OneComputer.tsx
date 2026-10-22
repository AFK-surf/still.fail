// The first idea: your devices, joined into one computer. Scrolled through, the devices first stand apart, each joined
// to every other; then the real app comes in on its station page and each machine goes into its own row there, all
// of them one list in one window; last, the same app on a phone.
import { useEffect, useMemo, useRef, useState } from "react";
import { StationMark } from "../StationMark.tsx";
import { NavItem, NavLine, navFill } from "../SidebarList.tsx";
import { MeterChip } from "../components.tsx";
import { netOf, stationViews } from "../demo/station.ts";
import type { Meter } from "../core/shapes.ts";
import { t } from "../i18n.ts";
import * as railCss from "../Rail.css.ts";
import * as stationCss from "../cloud/StationPage.css.ts";
import * as css from "./site.css.ts";
import { APP, Button, Demo, type DemoProps } from "./Site.tsx";

/** The devices: the workspace's machines (the demo's stations, demo/station.ts stationViews, by name) and the phone
 *  they are used from. */
const DEVICES = [
  { key: "phone", name: "手机", station: false },
  { key: "laptop", name: "笔记本", station: true },
  { key: "studio", name: "Studio", station: true },
  { key: "mini", name: "Mini", station: true },
  { key: "server", name: "服务器", station: true },
];
type Listed = ReturnType<typeof stationViews>[number];

/**
 * A device as the app lists it (cloud/StationPage.tsx StationRow, with the same parts and the demo's figures): its
 * mark, name and whether it works, its CPU, memory and disk, how it is reached. So that it is seen to go into its
 * row, it looks as that row does; the phone, not a station, as such a row would.
 */
function DeviceRow({ name, view }: { name: string; view: Listed | undefined }) {
  if (!view) {
    return (
      <NavItem mark={<StationMark icon="glyph:phone:pink" size={16} />} title={name} end={<span className={railCss.dot} data-online />}>
        <NavLine><span className={navFill}>Android · 正在使用</span></NavLine>
      </NavItem>
    );
  }
  const net = netOf(view.station);
  const running = view.overview.counts.running;
  return (
    <NavItem mark={<StationMark icon={view.icon} size={16} />} title={view.name}
      end={<><span className={railCss.dot} data-online />{running > 0 && <span className={stationCss.busy}>{t("web-pages.stations.page.runningShort", { n: running })}</span>}</>}>
      <span className={stationCss.rowMeters}>
        {(view.host.meters as unknown as Meter[]).map((m) => <MeterChip key={m.label} meter={m} brief bare />)}
      </span>
      <NavLine><span className={navFill}>{net.path}{" · "}<span className={stationCss.low} data-level={net.rtt.level}>{net.rtt.text}</span></span></NavLine>
    </NavItem>
  );
}

/** What the steps say, in order. */
const STEPS = [
  { title: "设备之间点对点连接", text: "手机、笔记本、台式机和服务器两两直连，无法直连时经加密中继转发" },
  { title: "用起来像一台电脑", text: "所有设备在同一个 still.fail 里，每台的文件、订阅和任务都能用" },
  { title: "在手机上也一样", text: "从任何一台设备打开，看到的都是所有设备" },
];

// ---- Where things are at each step ----

interface Box { x: number; y: number; w: number; h: number }
const clamp = (x: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
const ease = (t: number) => t * t * (3 - 2 * t);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const mix = (a: Box, b: Box, t: number): Box => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t) });

/** The devices apart: where each stands, as centres in a design box, fitted into the room. */
function apart(room: { w: number; h: number }, narrow: boolean, size?: { w: number; h: number }): Box[] {
  const design = narrow ? { w: 360, h: 540 } : { w: 1000, h: 540 };
  const at = narrow
    ? [[150, 40], [210, 150], [150, 260], [210, 370], [150, 480]]
    : [[150, 360], [330, 110], [520, 320], [720, 110], [860, 400]];
  const chip = narrow ? { w: 280, h: 84 } : size ?? { w: 272, h: 84 };
  const s = Math.min(room.w / design.w, room.h / design.h, 1.15);
  // Near the words above, not lost in the middle of a tall room.
  const ox = (room.w - design.w * s) / 2, oy = Math.min((room.h - design.h * s) / 2, 32);
  return at.map(([x, y]) => ({ x: ox + x! * s - chip.w / 2, y: oy + y! * s - chip.h / 2, ...chip }));
}

/** The window: as wide as a computer's, or as a phone. */
function windowAt(room: { w: number; h: number }, phone: boolean): Box {
  const w = phone ? Math.min(380, room.w - 32) : Math.min(1040, room.w - 48);
  const h = phone ? Math.min(720, room.h - 24) : Math.min(600, room.h - 24);
  return { x: (room.w - w) / 2, y: (room.h - h) / 2, w, h };
}

/** The devices in the window: down its sidebar on a computer, along its top on a phone. */
function inWindow(win: Box, phone: boolean): Box[] {
  if (!phone) return DEVICES.map((_, i) => ({ x: win.x + 12, y: win.y + 60 + i * 50, w: 196, h: 44 }));
  const gap = 6, w = (win.w - 24 - gap * (DEVICES.length - 1)) / DEVICES.length;
  return DEVICES.map((_, i) => ({ x: win.x + 12 + i * (w + gap), y: win.y + 56, w, h: 40 }));
}

/** Where each machine's row is in the app's station list (the live demo), in the room; none before the app is there. */
function rowsIn(win: HTMLElement, room: HTMLElement): (Box | undefined)[] {
  const at = room.getBoundingClientRect();
  return DEVICES.map((d) => {
    if (!d.station) return undefined;
    // Its name where the app writes it, then out to its row: a link or button (the computer's list), or a card as
    // wide as the window (the phone's).
    const words = [...win.querySelectorAll("span, b, div")].find((el) => el.childElementCount === 0 && el.textContent?.trim() === d.name);
    let row: Element | null = words ?? null;
    const wide = win.getBoundingClientRect().width * 0.85;
    while (row && row !== win && !row.matches("a, button, [role=link], [role=button]") && row.getBoundingClientRect().width < wide) row = row.parentElement;
    if (!row || row === win) return undefined;
    const r = row.getBoundingClientRect();
    return r.width > 0 ? { x: r.left - at.left, y: r.top - at.top, w: r.width, h: r.height } : undefined;
  });
}

export function OneComputer(props: DemoProps) {
  const scene = useRef<HTMLElement>(null);
  const room = useRef<HTMLDivElement>(null);
  const win = useRef<HTMLDivElement>(null);
  const chips = useRef<(HTMLDivElement | null)[]>([]);
  const lines = useRef<SVGGElement>(null);
  const [step, setStep] = useState(0);
  const views = useMemo(() => stationViews(), []);

  useEffect(() => {
    const el = scene.current, space = room.current, box = win.current, wires = lines.current;
    if (!el || !space || !box || !wires) return;
    let asked = 0;
    const draw = () => {
      asked = 0;
      if (el.offsetParent === null) return;
      const narrow = innerWidth <= 860;
      const size = { w: space.clientWidth, h: space.clientHeight };
      // The steps this screen goes through: on a narrow one, from apart straight to the phone's window.
      const steps = narrow ? [0, 2] : [0, 1, 2];
      const span = el.offsetHeight - innerHeight;
      const x = clamp(-el.getBoundingClientRect().top / Math.max(1, span)) * (steps.length - 1);
      const i = Math.min(Math.floor(x), steps.length - 2);
      const t = ease(clamp((x - i - 0.3) / 0.4));
      const from = steps[i]!, to = steps[i + 1]!;
      // In the window, each machine goes to its row in the app's list; the rows are read where the window stands (it
      // stands there, at its size, before it is seen).
      const rows = rowsIn(box, space);
      const layout = (s: number) => {
        const row = rows.find((r) => r);
        if (s === 0) return { chips: apart(size, narrow, row && { w: row.w, h: row.h }), win: windowAt(size, false), shown: 0 };
        const w = windowAt(size, s === 2);
        const fallback = inWindow(w, s === 2);
        return { chips: DEVICES.map((_, k) => rows[k] ?? fallback[k]!), win: w, shown: 1 };
      };
      const a = layout(from), b = layout(to);
      // Coming together: the devices fly to their rows first, over a window not there yet; then the window comes in
      // under them, the app's rows exactly where they are; then they give way to the rows. Nothing seen through
      // anything while it moves.
      const joining = from === 0;
      const move = joining ? ease(clamp(t / 0.7)) : t;
      const shown = joining ? lerp(a.shown, b.shown, clamp((t - 0.6) / 0.3)) : lerp(a.shown, b.shown, t);
      const w = joining ? b.win : mix(a.win, b.win, t);
      Object.assign(box.style, {
        left: `${w.x}px`, top: `${w.y}px`, width: `${w.w}px`, height: `${w.h}px`, opacity: `${shown}`, visibility: shown > 0 ? "visible" : "hidden",
      });
      const placed = a.chips.map((c, k) => mix(c, b.chips[k]!, move));
      placed.forEach((c, k) => {
        const node = chips.current[k];
        if (!node) return;
        // As wide as its row, as tall as what it says (the row's own height).
        Object.assign(node.style, { left: `${c.x}px`, top: `${c.y}px`, width: `${c.w}px` });
        // The phone, not one of the machines, goes on its way; the machines once the window is under them.
        const gone = joining ? (DEVICES[k]!.station ? clamp((t - 0.88) / 0.12) : clamp(t / 0.5)) : 1;
        node.style.opacity = `${1 - gone}`;
        node.style.visibility = gone < 1 ? "visible" : "hidden";
      });
      // Every device joined to every other while they stand apart.
      const centre = (c: Box) => [c.x + c.w / 2, c.y + c.h / 2] as const;
      const paths = wires.querySelectorAll("path");
      let n = 0;
      for (let p = 0; p < placed.length; p++) for (let q = p + 1; q < placed.length; q++) {
        const [x1, y1] = centre(placed[p]!), [x2, y2] = centre(placed[q]!);
        paths[n++]?.setAttribute("d", `M${x1} ${y1} L${x2} ${y2}`);
      }
      wires.style.opacity = `${joining ? 1 - move : 0}`;
      setStep(t < 0.5 ? from : to);
    };
    const ask = () => { if (!asked) asked = requestAnimationFrame(draw); };
    draw();
    addEventListener("scroll", ask, { passive: true });
    addEventListener("resize", ask);
    return () => { removeEventListener("scroll", ask); removeEventListener("resize", ask); cancelAnimationFrame(asked); };
  }, []);

  const pairs = (DEVICES.length * (DEVICES.length - 1)) / 2;
  return (
    <>
      <header className={css.sameHero}>
        <div className={css.wrap}>
          <h1 className={css.sameTitle}><span className={css.phrase}>把你的设备</span><span className={css.phrase}>连成一台电脑</span></h1>
          <p className={css.sameLede}>手机、笔记本、台式机和服务器之间点对点连接。在任何一台上，都能打开其他设备的文件、使用它们的订阅、把任务交给它们运行。</p>
          <div className={css.sameActions}><Button href={APP} kind="primary" large>开始使用</Button></div>
        </div>
      </header>

      <section className={css.scene} ref={scene} style={{ height: `${STEPS.length * 100}vh` }}>
        <div className={css.sceneStick}>
          <div className={css.stepWords}>
            {STEPS.map((s, i) => (
              <div key={s.title} className={css.stepSay} data-at={step === i ? "" : undefined}>
                <b>{s.title}</b><span>{s.text}</span>
              </div>
            ))}
          </div>
          <div className={css.oneRoom} ref={room}>
            <svg className={css.oneWires} aria-hidden><g ref={lines}>{Array.from({ length: pairs }, (_, i) => <path key={i} />)}</g></svg>
            <div className={css.oneWindow} ref={win}>
              <Demo v="1" start="stations" className={css.oneDemo} {...(props.mountDemo ? { mount: props.mountDemo } : {})} {...(props.demo ? { frame: props.demo } : {})} />
            </div>
            {DEVICES.map((d, k) => (
              <div key={d.key} className={css.oneChip} ref={(node) => { chips.current[k] = node; }}>
                <DeviceRow name={d.name} view={views.find((v) => v.name === d.name)} />
              </div>
            ))}
          </div>
        </div>
      </section>

    </>
  );
}
