// The first idea: your devices, joined into one computer. Scrolled through, the devices first stand apart, each joined
// to every other; then they go into one window and are its list of stations; last, the same on the phone.
//
// What is drawn over what is what lies over what: the wires, under the devices; each device, its shell, its screen
// (its app, cut to the screen's corners) and its camera island on the glass; over them all, what is in the air. The
// devices are the app's rows (its station list, the live demo): while one flies it is in the air, drawn as the app
// draws it (every style of each part of it as the app has it), and its place in the list is empty; on landing it is
// the row in the list again, where it is drawn the same. Nothing fades in or out to cover a change. The phone is a
// device from the start, the phone's app running in it, small; it comes to the front at the end while the computer
// steps back, both seen all along. On a narrow screen the window is the phone's app itself, and the devices its cards.
//
// The apps are the scene's while it puts them together, and the visitor's once it has: the window's once its rows are
// home, the phone's once it is in front. Till then they take no input, so that nothing changes under what flies.
import { useEffect, useRef } from "react";
import type { MountedDemo } from "../demo/mount.tsx";
import * as css from "./site.css.ts";
import { APP, Button, Demo, type DemoProps } from "./Site.tsx";
import { featurePage, useSay, useSiteLang } from "./words.ts";

/** How many steps the scene is scrolled through. */
const STEPS = 3;
/** How much later in its step each device sets off than the one under it. */
const LAG = 0.12;

/**
 * A phone's screen, the one beside the computer and a narrow screen's window alike (the same app, drawn the same):
 * its app laid out at this size, tall enough that its four stations stand clear of its bottom bar and its button.
 */
const PHONE = { w: 390, h: 870, r: 44 };
/**
 * The shells round the screens: a phone's edge (`edge` wide, all round); a laptop's, its edge round the screen and
 * its base under it, `over` wider than the edge each side and `foot` high.
 */
const SHELL = { edge: 12, laptop: { edge: 14, over: 70, foot: 18 } };
/** How tall a phone showing what it is for is: a phone's own height (an iPhone's, at its width). */
const FEATURE_H = 844;
/** The phone with its shell. */
const HAND = { w: PHONE.w + 2 * SHELL.edge, h: PHONE.h + 2 * SHELL.edge };

interface Box { x: number; y: number; w: number; h: number }
const clamp = (x: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
const ease = (t: number) => t * t * (3 - 2 * t);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const centre = (b: Box) => ({ x: b.x + b.w / 2, y: b.y + b.h / 2 });


/**
 * The window: a computer's, or (on a narrow screen) a phone's, laid out at a phone's size and drawn smaller (`k`) to
 * fit, so that all its stations are in it; where it stands, drawn.
 */
function windowAt(room: { w: number; h: number }, narrow: boolean): Box & { k: number } {
  // What the shell adds round the screen: left, top, right and bottom.
  const l = narrow ? SHELL.edge : SHELL.laptop.edge + SHELL.laptop.over, t = narrow ? SHELL.edge : SHELL.laptop.edge;
  const b = narrow ? SHELL.edge : SHELL.laptop.edge + SHELL.laptop.foot;
  const w = narrow ? PHONE.w : Math.min(1040, room.w - 48 - 2 * l);
  const h = narrow ? PHONE.h : Math.min(600, room.h - 24 - t - b);
  const k = narrow ? Math.min(1, (room.h - 16) / (h + t + b), (room.w - 24) / (w + 2 * l)) : 1;
  return { x: (room.w - w * k) / 2, y: (room.h - (h + t + b) * k) / 2 + t * k, w, h, k };
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

/** The app's row for a machine: its name where the app writes it (and shows it: of the frame the page was built with,
 *  the desktop's app or the phone's), out to its link (the computer's list) or to its whole card (the phone's: the
 *  first box out from it with a ground of its own, as wide as the window). */
function rowOf(app: HTMLElement, name: string, phone: boolean): HTMLElement | undefined {
  const words = [...app.querySelectorAll<HTMLElement>("span, b, div")].find((el) => el.childElementCount === 0 && el.textContent?.trim() === name && el.getClientRects().length > 0);
  const wide = app.getBoundingClientRect().width * 0.85;
  let row: HTMLElement | null = words ?? null;
  const card = (el: HTMLElement) => { const c = getComputedStyle(el).backgroundColor; return !!c && c !== "transparent" && !/rgba\(.*,\s*0\)$/.test(c); };
  const done = (el: HTMLElement) => phone ? card(el) && el.getBoundingClientRect().width >= wide : el.matches("a, button, [role=link], [role=button]");
  while (row && row !== app && !done(row)) row = row.parentElement;
  return row && row !== app ? row : undefined;
}

/** How opaque a computed colour is (rgb(), rgba(), or color(… / a)). */
function alpha(c: string): number {
  if (!c || c === "transparent") return 0;
  const a = /\/\s*([\d.]+%?)\s*\)$/.exec(c)?.[1] ?? /^rgba\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\)$/.exec(c)?.[1];
  return a === undefined ? 1 : a.endsWith("%") ? parseFloat(a) / 100 : parseFloat(a);
}

/** What a row is seen on in its list: its own colour and each laid under it on the way out, to the first that hides
 *  what is further out (a highlighted row is a tint over its list's colour), as one background. */
function ground(el: HTMLElement): string {
  const tints: string[] = [];
  for (let at: HTMLElement | null = el; at; at = at.parentElement) {
    const c = getComputedStyle(at).backgroundColor, a = alpha(c);
    if (a === 0) continue;
    if (a >= 1) return [...tints.map((t) => `linear-gradient(${t}, ${t})`), c].join(", ");
    tints.push(c);
  }
  return tints.length ? tints.map((t) => `linear-gradient(${t}, ${t})`).join(", ") : "transparent";
}

/**
 * A row as the app draws it, to be drawn anywhere: each part of it with every style the app gives it written on it,
 * its ::before and ::after too (in `sheet`, by a number of its own), so that nothing it is drawn in changes it.
 */
function drawnAs(row: HTMLElement, sheet: string[]): HTMLElement {
  const out = row.cloneNode(true) as HTMLElement;
  // Every computed style lists the same properties: named once, not read off each of them again (which took two
  // thirds of the time).
  const names = Array.from(getComputedStyle(row));
  const all = (cs: CSSStyleDeclaration) => {
    let text = "";
    for (let k = 0; k < names.length; k++) text += `${k ? ";" : ""}${names[k]}:${cs.getPropertyValue(names[k]!)}`;
    return text;
  };
  const copy = (from: Element, to: Element) => {
    (to as HTMLElement | SVGElement).style.cssText = all(getComputedStyle(from));
    for (const pseudo of ["::before", "::after"]) {
      const cs = getComputedStyle(from, pseudo);
      if (cs.content === "none" || cs.content === "normal") continue;
      const n = sheet.length;
      to.setAttribute("data-air", String(n));
      sheet.push(`[data-air="${n}"]${pseudo}{${all(cs)}}`);
    }
    for (let k = 0; k < from.children.length; k++) copy(from.children[k]!, to.children[k]!);
  };
  copy(row, out);
  out.removeAttribute("id");
  for (const e of out.querySelectorAll("[id]")) e.removeAttribute("id");
  Object.assign(out.style, { position: "absolute", left: "0", top: "0", margin: "0", transformOrigin: "0 0", transition: "none", animation: "none", visibility: "visible" });
  // Only drawn: nothing in it is clicked, focused or read out.
  out.setAttribute("inert", "");
  out.setAttribute("aria-hidden", "true");
  return out;
}

/**
 * A phone showing what it is for: the phone's app at its page, as built (featurePage), asked for once it is near the
 * screen, by the page's script (as the one beside the computer is): nothing of it is read while the page loads.
 */
function FeaturePhone({ at, title }: { at: string; title: string }) {
  const lang = useSiteLang();
  const frame = useRef<HTMLIFrameElement>(null);
  useEffect(() => {
    const el = frame.current;
    if (!el) return;
    const near = new IntersectionObserver(([entry]) => {
      if (!entry?.isIntersecting) return;
      near.disconnect();
      el.src = `${lang === "en" ? "/en/" : "/"}${featurePage(at)}`;
    }, { rootMargin: "600px 0px" });
    near.observe(el);
    return () => near.disconnect();
  }, [at, lang]);
  return (
    <div className={css.featurePhone}>
      <div className={css.featureShell}>
        <i className={css.oneKeys} />
        <i className={css.oneIsland} />
        <iframe ref={frame} className={css.onePhoneScreen} data-at={at} width={PHONE.w} height={FEATURE_H} title={title} tabIndex={-1} inert />
      </div>
    </div>
  );
}

export function OneComputer(props: DemoProps) {
  const say = useSay(), lang = useSiteLang();
  // The workspace's machines, by the names the demo's stations have in the page's language.
  const names = say.machines;
  const scene = useRef<HTMLElement>(null);
  const room = useRef<HTMLDivElement>(null);
  const win = useRef<HTMLDivElement>(null);
  const screen = useRef<HTMLDivElement>(null);
  const phone = useRef<HTMLDivElement>(null);
  const phoneScreen = useRef<HTMLIFrameElement>(null);
  const lines = useRef<HTMLDivElement>(null);
  const air = useRef<HTMLDivElement>(null);
  const demo = useRef<MountedDemo>(null);

  useEffect(() => {
    const el = scene.current, space = room.current, outer = win.current, inner = screen.current, hand = phone.current, wires = lines.current;
    if (!el || !space || !outer || !inner || !hand || !wires || !air.current) return;
    const narrow = innerWidth <= 860;
    // The phone's own app beside the computer's, a page of its own as wide as a phone (site/phone.html, in the page's
    // language), so that it is laid out as on one (its rules go by the screen's width); a wide screen only: on a narrow
    // one the window is the phone. At the address it is served at, without .html (Cloudflare sends a page's .html address
    // on to it: one more trip before the phone shows anything).
    if (!narrow && el.offsetParent !== null && phoneScreen.current && !phoneScreen.current.src) phoneScreen.current.src = lang === "en" ? "/en/phone" : "/phone";

    // The rows, where the app has them in the window (in its own size), and each as it is drawn there, for the air;
    // read again until the app is there, when the room changes size, and once the app is drawn anew (the demo taking
    // its box over from the frame the page was built with: those read before fly on till its rows are there).
    interface Row { el: HTMLElement; box: Box; flying: HTMLElement; shadow: string }
    let rows: Row[] = [];
    // How large the window is drawn just now; whether the rows are in the air just now.
    let drawn = 1, out = false;
    const sky = air.current!;
    const links = [...wires.children] as HTMLElement[];
    let wireWidth = 0;
    // A scroll outside the scene holds its first or last frame. Do not redraw it on every scroll down the rest of the
    // page. A resize or restyle can still change that frame, so remember its room and forget it when its rows change.
    let last: { x: number; w: number; h: number; viewportWidth: number } | undefined;
    let appSize: { w: number; h: number; viewportWidth: number } | undefined;
    const leave = () => { for (const r of rows) r.el.style.visibility = ""; sky.replaceChildren(); rows = []; out = false; last = undefined; };
    // In the air, or home: a row is drawn in one of the two, never both.
    const fly = (on: boolean) => {
      if (on === out) return;
      out = on;
      for (const r of rows) { r.el.style.visibility = on ? "hidden" : ""; r.flying.style.display = on ? "" : "none"; }
    };
    const read = () => {
      const app = inner.querySelector<HTMLElement>("#demo");
      const found = app ? names.map((n) => rowOf(app, n, narrow)) : [];
      if (!app || found.some((r) => !r)) return false;
      // A phone's window (a narrow screen's) is in a phone's shell: a status bar's room under its camera island.
      if (narrow && app.dataset.phone === undefined) { app.dataset.phone = ""; return false; }
      leave();
      const at = inner.getBoundingClientRect();
      const sheet: string[] = [];
      rows = (found as HTMLElement[]).map((row) => {
        const b = row.getBoundingClientRect();
        const box = { x: (b.left - at.left) / drawn, y: (b.top - at.top) / drawn, w: b.width / drawn, h: b.height / drawn };
        // As it is drawn once it has changed, not on its way (the selected row's colour comes in by a transition).
        const parts = [row, ...row.querySelectorAll<HTMLElement>("*")], was = parts.map((e) => e.style.transition);
        for (const e of parts) e.style.transition = "none";
        const flying = drawnAs(row, sheet);
        Object.assign(flying.style, { background: ground(row), display: "none", boxSizing: "border-box", width: `${box.w}px`, height: `${box.h}px` });
        const own = getComputedStyle(row).boxShadow;
        parts.forEach((e, k) => { e.style.transition = was[k]!; });
        return { el: row, flying, shadow: own === "none" ? "" : `, ${own}`, box };
      });
      const style = document.createElement("style");
      style.textContent = sheet.join("\n");
      sky.replaceChildren(style, ...rows.map((r) => r.flying));
      return true;
    };

    let asked = 0;
    const draw = () => {
      asked = 0;
      if (el.offsetParent === null) return;
      const size = { w: space.clientWidth, h: space.clientHeight };
      const w = windowAt(size, narrow);

      // Where the scene is: from its first step to its last, moving all the while it is scrolled (only a little at
      // its start and end holds still), so that nothing stands still under a moving finger.
      const steps = narrow ? [0, 1] : [0, 1, 2];
      const span = el.offsetHeight - innerHeight;
      const x = clamp((clamp(-el.getBoundingClientRect().top / Math.max(1, span)) - 0.06) / 0.88) * (steps.length - 1);
      if (last && last.x === x && last.w === size.w && last.h === size.h && last.viewportWidth === innerWidth && rows[0]?.el.isConnected) return;
      // The phone's app is laid out at PHONE.w × PHONE.h: a height change only scales it. The laptop's app can change
      // size, and a viewport-width change can also change its CSS. Recopy the rows only when those can change.
      if (appSize && (appSize.w !== w.w || appSize.h !== w.h || appSize.viewportWidth !== innerWidth)) leave();
      appSize = { w: w.w, h: w.h, viewportWidth: innerWidth };
      Object.assign(outer.style, { left: `${w.x}px`, top: `${w.y}px`, width: `${w.w}px`, height: `${w.h}px` });
      const i = Math.min(Math.floor(x), steps.length - 2);
      const t = clamp(x - i);
      // 0 → 1: the device comes up from below, its screen's list with its rows' places empty (rise), and they fly into
      // them one after another, the lowest first (landing: of the `k`-th to go; all of them home with the last): each
      // goes down out of the way of those still standing above it, so that none crosses another in the air. 1 → 2: the
      // computer steps back as the phone comes to the front (front). Everything only moves: nothing is cut out, shown
      // or faded.
      const rise = i === 0 ? ease(clamp(t / 0.7)) : 1;
      const landingOf = (k: number) => i === 0 ? ease(clamp((t - k * LAG) / (1 - (names.length - 1) * LAG))) : 1;
      const landing = landingOf(names.length - 1);
      const front = i === 1 ? t : 0;

      // The window, drawn at its size: up from below the room, then stepping back (about its centre) as the phone
      // comes forward.
      const back = lerp(1, 0.8, front), s = w.k * back;
      const below = size.h - w.y + 60;
      const tx = lerp(0, -size.w * 0.14, front) + (w.w * w.k * (1 - back)) / 2, ty = (w.h * w.k * (1 - back)) / 2 + lerp(below, 0, rise);
      outer.style.transform = `translate(${tx}px, ${ty}px) scale(${s})`;
      drawn = s;
      // The window's app is the visitor's while its rows are home. Played back out of that, the scene takes it again:
      // as it opened, if the visitor has used it, and its rows read again, so that what flies out is what it shows.
      const home = landing === 1;
      if (outer.inert === home) {
        outer.inert = !home;
        // Reopening only replaces the app if it was used. Keep the already copied rows otherwise; if it was used,
        // reopen replaces the old rows and `gone` reads the new ones below.
        if (!home) demo.current?.reopen();
      }
      const gone = rows.length > 0 && !rows[0]!.el.isConnected;
      if ((rows.length === 0 || gone) && !read()) {
        if (rows.length === 0) { asked = requestAnimationFrame(draw); return; }
        ask();
      }
      const inRoom = (b: Box): Box => ({ x: w.x + tx + b.x * s, y: w.y + ty + b.y * s, w: b.w * s, h: b.h * s });

      // The devices are the app's rows: from where they stand apart (in the room) to their places in its list, in the
      // air until they are there; a shadow under each, as under the devices, closing up as it comes down into the screen.
      const parts = apart(size, narrow);
      const order = parts.machines.map((_, k) => k).sort((a, b) => parts.machines[b]!.y - parts.machines[a]!.y);
      const placed = rows.map((r, k) => {
        const from = parts.machines[k]!, home = inRoom(r.box), landed = landingOf(order.indexOf(k));
        const scale = lerp(parts.scale, s, landed);
        const x = lerp(from.x - (r.box.w * parts.scale) / 2, home.x, landed), y = lerp(from.y - (r.box.h * parts.scale) / 2, home.y, landed);
        if (landing < 1) {
          const up = 1 - landed;
          Object.assign(r.flying.style, {
            transform: `translate(${x}px, ${y}px) scale(${scale})`,
            boxShadow: `0 ${(30 * up) / scale}px ${(40 * up) / scale}px rgba(0, 0, 0, ${0.18 * up})${r.shadow}`,
          });
        }
        return { x, y, w: r.box.w * scale, h: r.box.h * scale };
      });
      fly(landing < 1);

      // The phone (a wide screen's): small among the devices, then beside the window, then in front at full size.
      let phoneAt: Box | undefined;
      if (!narrow) {
        const small = Math.min(0.32, (size.h * 0.42) / HAND.h), beside = Math.min(0.5, (w.h * 0.85) / HAND.h), full = Math.min(1, (size.h - 24) / HAND.h);
        const p0 = { ...parts.phone, s: small };
        const p1 = { x: w.x + w.w - 20, y: w.y + w.h * 0.58, s: beside };
        const p2 = { x: size.w / 2 + size.w * 0.16, y: size.h / 2, s: full };
        const p = i === 0 ? { x: lerp(p0.x, p1.x, t), y: lerp(p0.y, p1.y, t), s: lerp(p0.s, p1.s, t) } : { x: lerp(p1.x, p2.x, front), y: lerp(p1.y, p2.y, front), s: lerp(p1.s, p2.s, front) };
        hand.style.transform = `translate(${p.x - (HAND.w * p.s) / 2}px, ${p.y - (HAND.h * p.s) / 2}px) scale(${p.s})`;
        if (hand.inert !== front < 1) hand.inert = front < 1;
        phoneAt = { x: p.x - (HAND.w * p.s) / 2, y: p.y - (HAND.h * p.s) / 2, w: HAND.w * p.s, h: HAND.h * p.s };
      }

      // Every device joined to every other, under the window: as the devices come together the lines shorten, and the
      // window, grown, covers them; those to the phone stay, the phone joined to it.
      const ends = [...placed, ...(phoneAt ? [phoneAt] : [])].map(centre);
      // The line's clipping box is wider than any pair of points in the room. Its width only changes when the room
      // changes, not on scroll; the two inverse scales keep the dashes the same length as the clip follows its ends.
      const maxWire = 2 * Math.max(size.w, size.h) + 128;
      if (wireWidth !== maxWire) {
        wireWidth = maxWire;
        for (const link of links) link.style.width = `${wireWidth}px`;
      }
      let n = 0;
      for (let p = 0; p < ends.length; p++) for (let q = p + 1; q < ends.length; q++) {
        const a = ends[p]!, b = ends[q]!, link = links[n++]!;
        const dx = b.x - a.x, dy = b.y - a.y, k = Math.hypot(dx, dy) / wireWidth;
        link.style.transform = `translate(${a.x}px, ${a.y - 0.75}px) rotate(${Math.atan2(dy, dx)}rad) scaleX(${k})`;
        if (k) (link.firstElementChild as HTMLElement).style.transform = `scaleX(${1 / k})`;
      }
      // All of it placed: seen from now on (site.css.ts).
      if (space.dataset.drawn === undefined) space.dataset.drawn = "";
      last = { x, w: size.w, h: size.h, viewportWidth: innerWidth };
    };
    const ask = () => { if (!asked) asked = requestAnimationFrame(draw); };
    const resized = () => ask();
    // The rows drawn again in the air when the app is drawn otherwise: in the other theme (once it has taken it), or in
    // its own type once that has come (read before, a row keeps the widths the stand-in type gave its parts, and its
    // words are cut short in them).
    const restyled = () => requestAnimationFrame(() => requestAnimationFrame(() => { leave(); ask(); }));
    const themes = new MutationObserver(restyled), dark = matchMedia("(prefers-color-scheme: dark)");
    // Nothing in the scene can be seen once its section is out of view. Pause the connections until it returns.
    const visible = new IntersectionObserver(([entry]) => { wires.toggleAttribute("data-offscreen", !entry?.isIntersecting); });
    visible.observe(el);
    themes.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    dark.addEventListener("change", restyled);
    document.fonts.addEventListener("loadingdone", restyled);
    draw();
    addEventListener("scroll", ask, { passive: true });
    addEventListener("resize", resized);
    return () => {
      visible.disconnect();
      themes.disconnect();
      dark.removeEventListener("change", restyled);
      document.fonts.removeEventListener("loadingdone", restyled);
      removeEventListener("scroll", ask);
      removeEventListener("resize", resized);
      cancelAnimationFrame(asked);
      leave();
    };
  }, [lang, names]);

  // Every pair of the four machines and the phone.
  const pairs = 10;
  return (
    <>
      <header className={css.sameHero}>
        <div className={css.wrap}>
          {/* Its full stop still.fail's dot, as in the name and the mark. */}
          <h1 className={css.sameTitle}>{say.title.replace(/\.$/, "")}<span className={css.titleDot}>.</span></h1>
          <div className={css.sameActions}><Button href={APP} kind="primary" large>{say.start}</Button></div>
        </div>
      </header>

      <section className={css.scene} ref={scene} style={{ height: `${STEPS * 100}vh` }}>
        <div className={css.sceneStick}>
          <div className={css.oneRoom} ref={room}>
            <div className={css.oneWires} ref={lines} data-site-wires aria-hidden>
              {Array.from({ length: pairs }, (_, i) => <div className={css.oneWire} key={i}><div className={css.oneWireScale}><div className={css.oneWireDashes} /></div></div>)}
            </div>
            <div className={css.oneLift}>
              <div className={css.oneWindow} ref={win} inert>
                {/* Its shell: a laptop's edge and base (a phone's edge on a narrow screen), under the screen. */}
                <div className={css.oneEdge} />
                <div className={css.oneBase} />
                <div className={css.oneKeysInWindow} />
                <div className={css.oneScreen} ref={screen}>
                  <Demo v="1" start="stations" className={css.oneDemo} held={demo} {...(props.mountDemo ? { mount: props.mountDemo } : {})} {...(props.demo ? { frame: props.demo.stations } : {})} />
                </div>
                <div className={css.oneIslandInWindow} />
              </div>
            </div>
            <div className={css.onePhone} ref={phone} style={{ width: HAND.w, height: HAND.h, padding: SHELL.edge }} inert>
              <i className={css.oneKeys} />
              <i className={css.oneIsland} />
              <iframe className={css.onePhoneScreen} ref={phoneScreen} width={PHONE.w} height={PHONE.h} title={say.phoneTitle} tabIndex={-1} />
            </div>
            <div className={css.oneAir} ref={air} />
          </div>
        </div>
      </section>

      {/* What it is for. */}
      <section className={css.section}>
        <div className={css.wrap}>
          <h2 className={css.headingTitle}>{say.scenesTitle}</h2>
          {/* Each on the phone's app, at its page (FeaturePhone): a picture of it at work, taking no input, so that the
              page scrolls on over it; what is not here yet, in words alone. */}
          <ol className={`${css.links} ${css.scenes}`}>
            {say.scenes.map((p, k) => (
              <li key={p.title} className={css.link} data-soon={p.soon || undefined}>
                {p.at ? <FeaturePhone at={p.at} title={p.title} /> : null}
                <span className={css.linkNumber}>{String(k + 1).padStart(2, "0")}{p.soon ? ` · ${say.soon}` : ""}</span>
                <h3 className={css.linkTitle}>{p.title}</h3>
                <p className={css.linkText}>{p.text}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>
    </>
  );
}
