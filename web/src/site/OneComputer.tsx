// The first idea: your devices, joined into one computer. Scrolled through, the devices first stand apart, each joined
// to every other; then they go into one window and are its list of stations; last, the same on the phone.
//
// Nothing fades in or out to cover a change, and nothing is swapped for a look-alike: the devices are the app's own
// rows (its station list, the live demo), moved out of their places and back. The window is not faded in: it shows
// only where they are, then grows out of them (its clip, their boxes widening to its own). The phone is a device from the start, the phone's app
// running in it, small; it comes to the front at the end while the computer's window steps back, both seen all along.
// On a narrow screen the window is the phone's app itself, and the devices its station cards.
import { useEffect, useRef } from "react";
import * as css from "./site.css.ts";
import { APP, Button, Demo, type DemoProps } from "./Site.tsx";

/** The workspace's machines, by the names the demo's stations have (demo/station.ts stationViews). */
const NAMES = ["笔记本", "Studio", "Mini", "服务器"];

/** What the steps say, in order. */
const STEPS = [
  { title: "设备之间点对点连接", text: "手机、笔记本、台式机和服务器两两直连，无法直连时经加密中继转发" },
  { title: "用起来像一台电脑", text: "所有设备在同一个 still.fail 里，每台的文件、订阅和任务都能用" },
  { title: "在手机上也一样", text: "从任何一台设备打开，看到的都是所有设备" },
];

/** The phone, as drawn: its screen's size (its app laid out at it), and how much of it shows at each step. */
const PHONE = { w: 390, h: 760, r: 44 };

interface Box { x: number; y: number; w: number; h: number }
const clamp = (x: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
const ease = (t: number) => t * t * (3 - 2 * t);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const mix = (a: Box, b: Box, t: number): Box => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t) });
const centre = (b: Box) => ({ x: b.x + b.w / 2, y: b.y + b.h / 2 });

/** A rounded rectangle as a path, for the window's clip. */
const rounded = ({ x, y, w, h }: Box, r: number) => {
  const q = Math.max(0, Math.min(r, w / 2, h / 2));
  return `M${x + q} ${y}H${x + w - q}A${q} ${q} 0 0 1 ${x + w} ${y + q}V${y + h - q}A${q} ${q} 0 0 1 ${x + w - q} ${y + h}`
    + `H${x + q}A${q} ${q} 0 0 1 ${x} ${y + h - q}V${y + q}A${q} ${q} 0 0 1 ${x + q} ${y}Z`;
};

/**
 * The window: a computer's, or (on a narrow screen) a phone's, laid out at a phone's size and drawn smaller (`k`) to
 * fit, so that all its stations are in it; where it stands, drawn.
 */
function windowAt(room: { w: number; h: number }, narrow: boolean): Box & { k: number } {
  const w = narrow ? 380 : Math.min(1040, room.w - 48);
  // A phone's tall enough that its four stations stand clear of its bottom bar and its button (which would come over
  // the last one as the rest of the app shows).
  const h = narrow ? 920 : Math.min(600, room.h - 24);
  const k = narrow ? Math.min(1, (room.h - 16) / h, (room.w - 24) / w) : 1;
  return { x: (room.w - w * k) / 2, y: (room.h - h * k) / 2, w, h, k };
}

/**
 * The devices apart, each a centre in a design box fitted into the room: the machines, and on a wide screen the
 * phone before them. A narrow screen's are its cards, drawn smaller (`scale`).
 */
function apart(room: { w: number; h: number }, narrow: boolean) {
  const design = narrow ? { w: 360, h: 560 } : { w: 1000, h: 540 };
  // In NAMES' order, placed so that none crosses another on its way into the list (Studio, Mini, 笔记本, 服务器 down it).
  const machines = narrow ? [[150, 340], [150, 70], [210, 205], [210, 475]] : [[560, 300], [360, 100], [790, 90], [850, 430]];
  const s = Math.min(room.w / design.w, room.h / design.h, 1);
  const ox = (room.w - design.w * s) / 2, oy = Math.min((room.h - design.h * s) / 2, 24);
  const at = ([x, y]: number[]) => ({ x: ox + x! * s, y: oy + y! * s });
  // The phone on the right, the side the window will have it on: it goes there without passing over the machines.
  return { machines: machines.map(at), phone: at([960, 260]), scale: narrow ? 0.7 : 1 };
}

/** The app's row for a machine: its name where the app writes it, out to its link (the computer's list) or to its
 *  whole card (the phone's: the first box out from it with a ground of its own, as wide as the window). */
function rowOf(app: HTMLElement, name: string, phone: boolean): HTMLElement | undefined {
  const words = [...app.querySelectorAll<HTMLElement>("span, b, div")].find((el) => el.childElementCount === 0 && el.textContent?.trim() === name);
  const wide = app.getBoundingClientRect().width * 0.85;
  let row: HTMLElement | null = words ?? null;
  const card = (el: HTMLElement) => { const c = getComputedStyle(el).backgroundColor; return !!c && c !== "transparent" && !/rgba\(.*,\s*0\)$/.test(c); };
  const done = (el: HTMLElement) => phone ? card(el) && el.getBoundingClientRect().width >= wide : el.matches("a, button, [role=link], [role=button]");
  while (row && row !== app && !done(row)) row = row.parentElement;
  return row && row !== app ? row : undefined;
}

/** What is behind an element: the first colour laid under it on the way out. */
function ground(el: HTMLElement): string {
  for (let at: HTMLElement | null = el; at; at = at.parentElement) {
    const c = getComputedStyle(at).backgroundColor;
    if (c && c !== "transparent" && !/rgba\(.*,\s*0\)$/.test(c)) return c;
  }
  return "transparent";
}

export function OneComputer(props: DemoProps) {
  const scene = useRef<HTMLElement>(null);
  const room = useRef<HTMLDivElement>(null);
  const win = useRef<HTMLDivElement>(null);
  const screen = useRef<HTMLDivElement>(null);
  const phone = useRef<HTMLDivElement>(null);
  const phoneScreen = useRef<HTMLDivElement>(null);
  const lines = useRef<SVGGElement>(null);
  const words = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = scene.current, space = room.current, outer = win.current, inner = screen.current, hand = phone.current, wires = lines.current;
    if (!el || !space || !outer || !inner || !hand || !wires) return;
    const narrow = innerWidth <= 860;
    // The phone's own app beside the computer's (a wide screen only: on a narrow one the window is the phone).
    if (!narrow && el.offsetParent !== null && phoneScreen.current && props.mountDemoView) props.mountDemoView(phoneScreen.current);

    // The rows themselves, where the app has them in the window (in its own size), what holds them in (the app's
    // lists, cut at their edges), what they stand on and their corners; read again until the app is there, and when
    // the room changes size.
    interface Row { el: HTMLElement; box: Box; ground: string; radius: number; holders: HTMLElement[] }
    let rows: Row[] = [];
    // How large the window is drawn just now; whether the rows are out of their lists just now.
    let drawn = 1, out = false;
    // While they fly, the rows are let out of their lists and each laid on its own ground, and nothing else of the app
    // is drawn (what lies where they pass, its header, its buttons over them); home, all put back as it was.
    let app: HTMLElement | null = null;
    const letOut = (on: boolean) => {
      if (on === out) return;
      out = on;
      if (app) app.style.visibility = on ? "hidden" : "";
      for (const r of rows) {
        r.el.style.visibility = on ? "visible" : "";
        for (const h of r.holders) Object.assign(h.style, { overflow: on ? "visible" : "", contain: on ? "none" : "", clipPath: on ? "none" : "" });
        Object.assign(r.el.style, on
          ? { position: "relative", zIndex: "1", background: r.ground, transformOrigin: "0 0" }
          : { position: "", zIndex: "", background: "", transformOrigin: "", transform: "" });
      }
    };
    const read = () => {
      letOut(false);
      app = inner.querySelector<HTMLElement>("#demo");
      const found = app ? NAMES.map((n) => rowOf(app!, n, narrow)) : [];
      if (!app || found.some((r) => !r)) return false;
      const at = inner.getBoundingClientRect();
      rows = (found as HTMLElement[]).map((row) => {
        const b = row.getBoundingClientRect();
        const holders: HTMLElement[] = [];
        for (let h = row.parentElement; h && h !== inner; h = h.parentElement) holders.push(h);
        return {
          el: row, holders, ground: ground(row), radius: Number.parseFloat(getComputedStyle(row).borderTopLeftRadius) || 0,
          box: { x: (b.left - at.left) / drawn, y: (b.top - at.top) / drawn, w: b.width / drawn, h: b.height / drawn },
        };
      });
      return true;
    };

    let asked = 0;
    const draw = () => {
      asked = 0;
      if (el.offsetParent === null) return;
      const size = { w: space.clientWidth, h: space.clientHeight };
      const w = windowAt(size, narrow);
      Object.assign(outer.style, { left: `${w.x}px`, top: `${w.y}px`, width: `${w.w}px`, height: `${w.h}px` });

      // Where the scene is: from its first step to its last, moving all the while it is scrolled (only a little at
      // its start and end holds still), so that nothing stands still under a moving finger.
      const steps = narrow ? [0, 1] : [0, 1, 2];
      const span = el.offsetHeight - innerHeight;
      const x = clamp((clamp(-el.getBoundingClientRect().top / Math.max(1, span)) - 0.06) / 0.88) * (steps.length - 1);
      const i = Math.min(Math.floor(x), steps.length - 2);
      const t = clamp(x - i);
      // 0 → 1: the devices fly to their rows (fly), then the window grows out of the rows (grow), the one taking over
      // from the other at the same pace. 1 → 2: the computer's window steps back as the phone comes to the front.
      const fly = i === 0 ? clamp(t / 0.55) : 1;
      const grow = i === 0 ? clamp((t - 0.55) / 0.45) : 1;
      const front = i === 1 ? t : 0;

      // The window, drawn at its size, stepping back (about its centre) as the phone comes forward.
      const back = lerp(1, 0.8, front), s = w.k * back;
      const tx = lerp(0, -size.w * 0.14, front) + (w.w * w.k * (1 - back)) / 2, ty = (w.h * w.k * (1 - back)) / 2;
      outer.style.transform = `translate(${tx}px, ${ty}px) scale(${s})`;
      drawn = s;
      if (rows.length === 0 && !read()) { asked = requestAnimationFrame(draw); return; }
      const inRoom = (b: Box): Box => ({ x: w.x + tx + b.x * s, y: w.y + ty + b.y * s, w: b.w * s, h: b.h * s });

      // The devices are the app's own rows: moved from apart to where they stand, the window shown only where they are
      // (its clip, their boxes); home, the window grows out of them (their boxes widening to its own).
      const parts = apart(size, narrow);
      const local = rows.map((r, k) => {
        const from = parts.machines[k]!;
        const scale = lerp(parts.scale / s, 1, fly);
        const start = { x: (from.x - (r.box.w * parts.scale) / 2 - w.x - tx) / s, y: (from.y - (r.box.h * parts.scale) / 2 - w.y - ty) / s };
        const at = { x: lerp(start.x, r.box.x, fly), y: lerp(start.y, r.box.y, fly) };
        if (fly < 1) r.el.style.transform = `translate(${at.x - r.box.x}px, ${at.y - r.box.y}px) scale(${scale})`;
        return { x: at.x, y: at.y, w: r.box.w * scale, h: r.box.h * scale, r: r.radius * scale };
      });
      letOut(fly < 1);
      const whole = { x: 0, y: 0, w: w.w, h: w.h }, corner = narrow ? 36 : 20;
      inner.style.clipPath = `path('${(fly < 1
        ? local.map((b) => rounded(b, b.r))
        : rows.map((r) => rounded(mix(r.box, whole, grow), lerp(r.radius, corner, grow)))).join(" ")}')`;
      const placed = local.map(inRoom);

      // The phone (a wide screen's): small among the devices, then beside the window, then in front at full size.
      let phoneAt: Box | undefined;
      if (!narrow) {
        const small = Math.min(0.32, (size.h * 0.42) / PHONE.h), beside = Math.min(0.5, (w.h * 0.85) / PHONE.h), full = Math.min(1, (size.h - 24) / PHONE.h);
        const p0 = { ...parts.phone, s: small };
        const p1 = { x: w.x + w.w - 20, y: w.y + w.h * 0.58, s: beside };
        const p2 = { x: size.w / 2 + size.w * 0.16, y: size.h / 2, s: full };
        const p = i === 0 ? { x: lerp(p0.x, p1.x, t), y: lerp(p0.y, p1.y, t), s: lerp(p0.s, p1.s, t) } : { x: lerp(p1.x, p2.x, front), y: lerp(p1.y, p2.y, front), s: lerp(p1.s, p2.s, front) };
        hand.style.transform = `translate(${p.x - (PHONE.w * p.s) / 2}px, ${p.y - (PHONE.h * p.s) / 2}px) scale(${p.s})`;
        phoneAt = { x: p.x - (PHONE.w * p.s) / 2, y: p.y - (PHONE.h * p.s) / 2, w: PHONE.w * p.s, h: PHONE.h * p.s };
      }

      // Every device joined to every other, under the window: as the devices come together the lines shorten, and the
      // window, grown, covers them; those to the phone stay, the phone joined to it.
      const ends = [...placed, ...(phoneAt ? [phoneAt] : [])].map(centre);
      const paths = wires.querySelectorAll("path");
      let n = 0;
      for (let p = 0; p < ends.length; p++) for (let q = p + 1; q < ends.length; q++) {
        paths[n++]?.setAttribute("d", `M${ends[p]!.x} ${ends[p]!.y} L${ends[q]!.x} ${ends[q]!.y}`);
      }
      // What the steps say, one under another: the next comes up as this one goes, about the middle of the way.
      words.current?.style.setProperty("--at", `${i + ease(clamp((t - 0.4) / 0.2))}`);
    };
    const ask = () => { if (!asked) asked = requestAnimationFrame(draw); };
    const resized = () => { letOut(false); rows = []; ask(); };
    draw();
    addEventListener("scroll", ask, { passive: true });
    addEventListener("resize", resized);
    return () => {
      removeEventListener("scroll", ask);
      removeEventListener("resize", resized);
      cancelAnimationFrame(asked);
      letOut(false);
    };
  }, [props.mountDemoView]);

  // Every pair of the four machines and the phone.
  const pairs = 10;
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
            <div className={css.stepTrack} ref={words}>
              {STEPS.map((s) => (
                <div key={s.title} className={css.stepSay}>
                  <b>{s.title}</b><span>{s.text}</span>
                </div>
              ))}
            </div>
          </div>
          <div className={css.oneRoom} ref={room}>
            <svg className={css.oneWires} aria-hidden><g ref={lines}>{Array.from({ length: pairs }, (_, i) => <path key={i} />)}</g></svg>
            <div className={css.oneLift}>
              <div className={css.oneWindow} ref={win}>
                <div className={css.oneScreen} ref={screen}>
                  <Demo v="1" start="stations" className={css.oneDemo} {...(props.mountDemo ? { mount: props.mountDemo } : {})} {...(props.demo ? { frame: props.demo } : {})} />
                </div>
              </div>
            </div>
            <div className={css.onePhone} ref={phone}>
              <div className={css.onePhoneScreen} ref={phoneScreen} style={{ width: PHONE.w, height: PHONE.h }} />
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
