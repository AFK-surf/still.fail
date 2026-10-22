// The first idea: your devices, joined into one computer. Scrolled through, the devices first stand apart, each joined
// to every other; then they go into one window, as its list of devices, and the window shows what is on all of them
// together (conversations, files, subscriptions, tasks), each line saying which device it is on; last, the same window
// on a phone.
import { useEffect, useRef, useState, type ReactNode } from "react";
import * as css from "./site.css.ts";
import { APP, Button, Demo, type DemoProps } from "./Site.tsx";

const ICON = { width: 20, height: 20, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.75, strokeLinecap: "round", strokeLinejoin: "round", "aria-hidden": true } as const;

/** The devices, each with what it is and the colour that marks what is on it. */
const DEVICES: { key: string; name: string; kind: string; color: string; icon: ReactNode }[] = [
  { key: "phone", name: "手机", kind: "Android", color: "#71717A", icon: <svg {...ICON}><rect x="7" y="3" width="10" height="18" rx="2.5" /><path d="M11 18h2" /></svg> },
  { key: "laptop", name: "笔记本", kind: "MacBook", color: "#8B5CF6", icon: <svg {...ICON}><rect x="5" y="5" width="14" height="10" rx="1.5" /><path d="M3 19h18" /></svg> },
  { key: "studio", name: "Studio", kind: "Mac Studio", color: "#E5704A", icon: <svg {...ICON}><rect x="4" y="9" width="16" height="9" rx="2.5" /><path d="M8 15h2" /></svg> },
  { key: "mini", name: "Mini", kind: "Mac mini", color: "#3B82F6", icon: <svg {...ICON}><rect x="4" y="11" width="16" height="6" rx="2" /><path d="M8 14h1" /></svg> },
  { key: "server", name: "服务器", kind: "Linux", color: "#16A34A", icon: <svg {...ICON}><rect x="5" y="4" width="14" height="7" rx="1.5" /><rect x="5" y="13" width="14" height="7" rx="1.5" /><path d="M8 7.5h1M8 16.5h1" /></svg> },
];
const color = (key: string) => DEVICES.find((d) => d.key === key)!.color;
const nameOf = (key: string) => DEVICES.find((d) => d.key === key)!.name;

/** What the steps say, in order. */
const STEPS = [
  { title: "设备之间点对点连接", text: "手机、笔记本、台式机和服务器两两直连，无法直连时经加密中继转发" },
  { title: "用起来像一台电脑", text: "一个界面里是所有设备上的对话、文件、订阅和任务" },
  { title: "在手机上也是全部", text: "从任何一台设备打开，看到的都是所有设备" },
];

// ---- Where things are at each step ----

interface Box { x: number; y: number; w: number; h: number }
const clamp = (x: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
const ease = (t: number) => t * t * (3 - 2 * t);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const mix = (a: Box, b: Box, t: number): Box => ({ x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t) });

/** The devices apart: where each stands, as centres in a design box, fitted into the room. */
function apart(room: { w: number; h: number }, narrow: boolean): Box[] {
  const design = narrow ? { w: 360, h: 520 } : { w: 1000, h: 540 };
  const at = narrow
    ? [[95, 70], [265, 150], [110, 250], [255, 350], [120, 450]]
    : [[150, 360], [330, 110], [520, 320], [720, 110], [860, 400]];
  const chip = narrow ? { w: 150, h: 52 } : { w: 196, h: 60 };
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

export function OneComputer(props: DemoProps) {
  const scene = useRef<HTMLElement>(null);
  const room = useRef<HTMLDivElement>(null);
  const win = useRef<HTMLDivElement>(null);
  const chips = useRef<(HTMLDivElement | null)[]>([]);
  const lines = useRef<SVGGElement>(null);
  const [step, setStep] = useState(0);

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
      const layout = (s: number) => {
        if (s === 0) return { chips: apart(size, narrow), win: windowAt(size, false), shown: 0 };
        const w = windowAt(size, s === 2);
        return { chips: inWindow(w, s === 2), win: w, shown: 1 };
      };
      const a = layout(from), b = layout(to);
      // The window comes in where it will stand, from a little smaller; from the first step to the phone (a narrow
      // screen) it comes in as the phone's.
      const winA = from === 0 ? b.win : a.win;
      const w = mix(winA, b.win, from === 0 ? 1 : t);
      const shown = lerp(a.shown, b.shown, t);
      const grow = from === 0 ? lerp(0.94, 1, t) : 1;
      Object.assign(box.style, {
        left: `${w.x}px`, top: `${w.y}px`, width: `${w.w}px`, height: `${w.h}px`, opacity: `${shown}`,
        transform: `scale(${grow})`, visibility: shown > 0 ? "visible" : "hidden",
      });
      const placed = a.chips.map((c, k) => mix(c, b.chips[k]!, t));
      placed.forEach((c, k) => {
        const node = chips.current[k];
        if (!node) return;
        Object.assign(node.style, { left: `${c.x}px`, top: `${c.y}px`, width: `${c.w}px`, height: `${c.h}px` });
        // On the phone's window only their marks show.
        node.style.setProperty("--words", `${clamp((c.w - 90) / 60)}`);
      });
      // Every device joined to every other while they stand apart.
      const centre = (c: Box) => [c.x + c.w / 2, c.y + c.h / 2] as const;
      const paths = wires.querySelectorAll("path");
      let n = 0;
      for (let p = 0; p < placed.length; p++) for (let q = p + 1; q < placed.length; q++) {
        const [x1, y1] = centre(placed[p]!), [x2, y2] = centre(placed[q]!);
        paths[n++]?.setAttribute("d", `M${x1} ${y1} L${x2} ${y2}`);
      }
      wires.style.opacity = `${1 - shown}`;
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
            <div className={css.oneWindow} ref={win}><AllDevices /></div>
            {DEVICES.map((d, k) => (
              <div key={d.key} className={css.oneChip} ref={(node) => { chips.current[k] = node; }}>
                <i style={{ background: d.color }}>{d.icon}</i>
                <span><b>{d.name}</b><small>{d.kind}</small></span>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className={css.section}>
        <div className={css.wrap}>
          <h2 className={css.headingTitle}>试用 still.fail</h2>
          <p className={css.headingLede}>以下为使用示例数据的 still.fail</p>
          <div className={`${css.edge} ${css.demoAfterHeading}`}>
            <Demo v="1" {...(props.mountDemo ? { mount: props.mountDemo } : {})} {...(props.demo ? { frame: props.demo } : {})} />
          </div>
        </div>
      </section>
    </>
  );
}

// ---- The window: what is on all the devices, together ----

const PANELS: { title: string; rows: { text: string; on: string; note?: string }[] }[] = [
  { title: "对话", rows: [{ text: "登录页手机适配", on: "studio" }, { text: "排查 API 变慢", on: "server" }, { text: "每周依赖升级", on: "mini" }] },
  { title: "文件", rows: [{ text: "Projects/still.fail", on: "studio" }, { text: "Desktop/设计稿", on: "laptop" }, { text: "/var/log/api", on: "server" }] },
  { title: "订阅", rows: [{ text: "Claude Max", on: "studio", note: "所有设备可用" }, { text: "ChatGPT Pro", on: "mini", note: "所有设备可用" }] },
  { title: "任务", rows: [{ text: "pnpm test", on: "studio", note: "运行中" }, { text: "数据库备份", on: "server", note: "运行中" }, { text: "构建 Android", on: "mini", note: "运行中" }] },
];

function AllDevices() {
  return (
    <div className={css.all}>
      <div className={css.allHead}><b>所有设备</b><span>5 台在线</span></div>
      <div className={css.allSide} />
      <div className={css.allMain}>
        {PANELS.map((p) => (
          <div key={p.title} className={css.allPanel}>
            <b className={css.allTitle}>{p.title}</b>
            {p.rows.map((r) => (
              <div key={r.text} className={css.allRow}>
                <span className={css.allText}>{r.text}</span>
                {r.note && <span className={css.allNote}>{r.note}</span>}
                <span className={css.allOn}><i style={{ background: color(r.on) }} />{nameOf(r.on)}</span>
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
