// Marking a web service's page in a preview, for a chat's agent: this runs in the preview's frame (the preview host's
// /_ember/frame on the web, cloud/src/preview.ts; the desktop app's ember-preview:// one, apps/desktop/src/main.ts),
// loaded there as /_ember/annotate.js. The service's page is in a frame of that frame, on the same origin, so its
// document can be read and its clicks held here without anything put into the service.
//
// Told by the client (ember-preview-annotate): `on` (true/false) starts or ends picking, `remove` drops a mark,
// `clear` drops them all, `capture` asks for the pictures: with `each`, one PNG per mark, of what the window shows
// with only that mark drawn on it (a mark scrolled out of sight gets the window's worth of page around it); without
// (clients before that), the whole page with all the marks on it. `canvas` (true/false)
// that the page is on a canvas (PreviewStage.tsx), whose zooming and two fingers it then hands on (ember-preview-gesture). It says
// (ember-preview-annotated): `picked` with where a mark is, `focus` when a marked element is picked again, `at` with
// where the marks are in the frame's viewport as the page scrolls or moves (the client draws them), `off` when Esc
// ended picking, `reset` when the page went elsewhere (its marks gone), `shot` with the pictures (`shots`, or `png`). The frame says it can
// do this (its ember-preview-at) once attach() has its page frame. Only the box under the pointer is drawn here.
import { domToCanvas } from "modern-screenshot";

declare global {
  interface Window {
    stillfailAnnotate?: { attach(inner: HTMLIFrameElement, nonce: string): void };
    emberAnnotate?: { attach(inner: HTMLIFrameElement, nonce: string): void };
  }
}

export interface Picked {
  n: number;
  /** The page's path, and its viewport's size. */
  path: string;
  viewport: { width: number; height: number };
  /** tag#id.class, as a person reads it. */
  label: string;
  /**
   * What sort of thing it is: a word the client says in its language (button, link, image…: Marks.tsx kindName); in
   * words (按钮, 链接, 图片…) from a frame before that.
   */
  kind: string;
  /** A CSS selector that finds it in the page. */
  selector: string;
  /** Its words (or a field's value, placeholder, an image's alt), cut short. */
  text: string;
  /** Where it is in the frame's viewport (for the client's comment box), and on the whole page (the picture's). */
  rect: { x: number; y: number; width: number; height: number };
  page: { x: number; y: number; width: number; height: number };
  /** The components it is inside (React, Vue in development), innermost last, and the source file when known. */
  component: string | null;
}

/** still.fail's accent (--accent, light). */
const MARK = "#ef6a3c";
const MAX_HEIGHT = 12000;
const MAX_PIXELS = 36e6;

// Under both names: frames from before the rename (the preview host's, the desktop app's) look for `emberAnnotate`.
window.stillfailAnnotate = window.emberAnnotate = { attach };

function attach(inner: HTMLIFrameElement, nonce: string) {
  let on = false;
  let hover: Element | null = null;
  // Where ↑ went from, for ↓ to come back down the same way.
  let below: Element[] = [];
  let marks: { n: number; el: Element; rect: DOMRect }[] = [];
  let next = 1;
  let doc: Document | null = null;

  const say = (data: Record<string, unknown>, transfer: Transferable[] = []) =>
    parent.postMessage({ type: "ember-preview-annotated", nonce, ...data }, "*", transfer);

  // What is drawn over the page here: the box under the pointer while picking, with what it is. The marks are the
  // client's to draw (it is told where they are).
  const layer = document.createElement("div");
  layer.style.cssText = "position:fixed;inset:0;pointer-events:none;z-index:2147483647;overflow:hidden;font:500 11px/1 system-ui,-apple-system,sans-serif";
  const hoverBox = document.createElement("div");
  hoverBox.style.cssText = `position:absolute;display:none;box-sizing:border-box;border:1.5px solid ${MARK};background:${MARK}14;border-radius:3px`;
  const hoverName = document.createElement("div");
  // Frosted, as still.fail's own floating things are (the client's bubbles, the composer).
  hoverName.style.cssText = "position:absolute;display:none;padding:5px 9px;border-radius:999px;background:rgba(228,228,232,.72);-webkit-backdrop-filter:blur(20px) saturate(1.4);backdrop-filter:blur(20px) saturate(1.4);color:#2b2f36;white-space:nowrap;max-width:60vw;overflow:hidden;text-overflow:ellipsis;box-shadow:0 1px 3px rgba(0,0,0,.06),0 6px 20px rgba(20,24,30,.10)";
  layer.append(hoverBox, hoverName);
  const place = () => document.body && !layer.isConnected && document.body.append(layer);
  let told = "";

  const draw = () => {
    // What is marked already shows as its mark.
    if (hover && hover.isConnected && on && !marks.some((m) => m.el === hover)) {
      const r = hover.getBoundingClientRect();
      Object.assign(hoverBox.style, { display: "block", left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
      hoverName.textContent = `${kindOf(hover)} · ${Math.round(r.width)}×${Math.round(r.height)}`;
      const above = r.top >= 26;
      Object.assign(hoverName.style, { display: "block", left: `${Math.max(4, Math.min(r.left, innerWidth - 140))}px`, top: above ? `${r.top - 25}px` : `${Math.min(r.bottom + 5, innerHeight - 24)}px` });
    } else {
      hoverBox.style.display = hoverName.style.display = "none";
    }
    const at = marks.map((m) => ({ n: m.n, ...box(m.el.isConnected ? m.el.getBoundingClientRect() : m.rect) }));
    const now = JSON.stringify(at);
    if (now !== told) { told = now; say({ event: "at", at }); }
  };
  let frame = 0;
  const loop = () => {
    draw();
    frame = on || marks.length ? requestAnimationFrame(loop) : 0;
  };
  const wake = () => { place(); if (!frame) frame = requestAnimationFrame(loop); };

  const cursor = () => {
    if (!doc) return;
    const id = "ember-annotate-cursor";
    const had = doc.getElementById(id);
    if (on && !had) {
      const style = doc.createElement("style");
      style.id = id;
      style.textContent = "*, *::before, *::after { cursor: crosshair !important; }";
      (doc.head ?? doc.documentElement).append(style);
    } else if (!on) had?.remove();
  };
  const setOn = (value: boolean) => {
    on = value;
    if (!on) { hover = null; below = []; }
    cursor();
    wake();
  };

  const target = (el: Element | null): Element | null => {
    if (!el) return null;
    // A drawing's shapes are the drawing.
    const svg = el.closest("svg");
    return svg && svg !== el ? svg : el;
  };
  const pick = (el: Element) => {
    if (!doc) return;
    const had = marks.find((m) => m.el === el);
    if (had) { say({ event: "focus", n: had.n }); return; }
    const win = doc.defaultView!;
    const r = el.getBoundingClientRect();
    const n = next++;
    marks.push({ n, el, rect: r });
    const at = win.location;
    const picked: Picked = {
      n,
      path: at.pathname + at.search + at.hash,
      viewport: { width: win.innerWidth, height: win.innerHeight },
      label: label(el),
      kind: kindOf(el),
      selector: selector(el),
      text: words(el),
      rect: box(r),
      page: box(new DOMRect(r.left + win.scrollX, r.top + win.scrollY, r.width, r.height)),
      component: component(el),
    };
    say({ event: "picked", mark: picked });
    wake();
  };

  const hold = (event: Event) => {
    if (!on) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.type === "click" && (event as MouseEvent).button === 0) {
      const el = hover ?? target(event.target as Element);
      if (el) pick(el);
    }
  };
  const move = (event: PointerEvent) => {
    if (!on) return;
    const el = target(event.target as Element);
    // After ↑, moving within what is picked keeps it.
    if (el && el !== hover && !(below.length && hover?.contains(el))) { hover = el; below = []; }
  };
  const key = (event: KeyboardEvent) => {
    if (!on) return;
    if (event.key === "Escape") { setOn(false); say({ event: "off" }); }
    else if (event.key === "ArrowUp" && hover?.parentElement && hover.parentElement !== doc?.documentElement) { below.push(hover); hover = hover.parentElement; }
    else if (event.key === "ArrowDown" && hover) hover = below.pop() ?? hover.firstElementChild ?? hover;
    else if (event.key === "Enter" && hover) pick(hover);
    else return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };
  const leave = (event: MouseEvent) => { if (!event.relatedTarget) hover = null; };

  // The page as a canvas's (the client laid it out at a size of its own and said `canvas`): zooming (⌘/Ctrl and the
  // wheel, which a trackpad's pinch is) and two fingers on it move the canvas, not the page. They are said to the
  // client (ember-preview-gesture: the wheel's delta, or the fingers, where they are in the page's viewport).
  let canvas = false;
  let fingers = false;
  const gesture = (data: Record<string, unknown>) => parent.postMessage({ type: "ember-preview-gesture", nonce, ...data }, "*");
  const wheel = (event: WheelEvent) => {
    if (!canvas || !(event.ctrlKey || event.metaKey)) return;
    event.preventDefault();
    gesture({ kind: "wheel", x: event.clientX, y: event.clientY, deltaY: event.deltaY, deltaMode: event.deltaMode });
  };
  // Space held over the page takes hold of it (the canvas's, as the wheel's zooming is), unless it is typed.
  let spaceDown = false;
  const space = (event: KeyboardEvent) => {
    if (!canvas || event.code !== "Space") return;
    if (event.type === "keydown") {
      const t = event.target as HTMLElement | null;
      if (!spaceDown && (t?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t?.tagName ?? ""))) return;
      event.preventDefault();
      if (!spaceDown) { spaceDown = true; gesture({ kind: "space", down: true }); }
    } else if (spaceDown) {
      event.preventDefault();
      spaceDown = false;
      gesture({ kind: "space", down: false });
    }
  };
  const touch = (event: TouchEvent) => {
    if (!canvas) return;
    if (event.touches.length >= 2) fingers = true;
    if (!fingers) return;
    // Held from moving the page (only a move: a held start or end would leave its touch unended here).
    if (event.type === "touchmove" && event.cancelable) event.preventDefault();
    const points = [...event.touches].slice(0, 2).map((t) => ({ x: t.clientX, y: t.clientY }));
    gesture({ kind: "fingers", points });
    if (!event.touches.length) fingers = false;
  };

  // Each page the frame loads: its clicks held while picking; the marks of the one before are gone.
  const hook = () => {
    let now: Document | null = null;
    try { now = inner.contentDocument; } catch { /* not the service's page */ }
    if (!now || now === doc) return;
    doc = now;
    for (const type of ["pointerdown", "pointerup", "mousedown", "mouseup", "click", "dblclick", "auxclick", "contextmenu", "submit"]) doc.addEventListener(type, hold, true);
    doc.addEventListener("pointermove", move, true);
    doc.addEventListener("keydown", key, true);
    doc.addEventListener("mouseout", leave, true);
    doc.addEventListener("wheel", wheel, { capture: true, passive: false });
    doc.addEventListener("keydown", space, true);
    doc.addEventListener("keyup", space, true);
    for (const type of ["touchstart", "touchmove", "touchend", "touchcancel"]) doc.addEventListener(type, touch as EventListener, { capture: true, passive: false });
    if (marks.length) { marks = []; say({ event: "reset" }); }
    hover = null;
    below = [];
    cursor();
  };
  inner.addEventListener("load", hook);
  // The frame's own document too, when the keyboard is there rather than in the page.
  document.addEventListener("keydown", key, true);
  hook();

  addEventListener("message", (event) => {
    if (event.source !== parent || event.data?.type !== "ember-preview-annotate") return;
    const data = event.data as { on?: boolean; remove?: number; clear?: boolean; capture?: number; each?: boolean; canvas?: boolean };
    hook();
    if (typeof data.canvas === "boolean") canvas = data.canvas;
    if (typeof data.on === "boolean") setOn(data.on);
    if (typeof data.remove === "number") { marks = marks.filter((m) => m.n !== data.remove); wake(); }
    if (data.clear) { marks = []; next = 1; wake(); }
    if (typeof data.capture === "number") {
      const id = data.capture;
      const failed = (error: unknown) => say({ event: "shot", id, error: error instanceof Error ? error.message : String(error) });
      if (data.each) shootEach(marks).then((shots) => say({ event: "shot", id, shots }, shots.map((s) => s.png)), failed);
      else shoot(marks).then((png) => say({ event: "shot", id, png }, [png]), failed);
    }
  });

  /** Picking's box is not in the pictures. */
  async function unseen<T>(take: () => Promise<T>): Promise<T> {
    const wasOn = on;
    if (wasOn) setOn(false);
    try { return await take(); } finally { if (wasOn) setOn(true); }
  }

  const ground = (d: Document) => {
    const body = getComputedStyle(d.body ?? d.documentElement).backgroundColor;
    const root = getComputedStyle(d.documentElement).backgroundColor;
    return body && body !== "rgba(0, 0, 0, 0)" ? body : root === "rgba(0, 0, 0, 0)" ? "#ffffff" : root;
  };

  /**
   * One picture per mark, each of a window's worth of the page with only its mark drawn: what the window shows now,
   * or, for a mark out of sight, the page scrolled to it (as it would show there).
   */
  async function shootEach(shown: typeof marks): Promise<{ n: number; png: ArrayBuffer }[]> {
    if (!doc) throw new Error("no-page");
    const win = doc.defaultView!;
    const root = doc.documentElement;
    const w = win.innerWidth, h = win.innerHeight;
    const scale = Math.min(win.devicePixelRatio || 1, 2);
    const left = win.scrollX, top = win.scrollY;
    const most = Math.max(0, Math.max(root.scrollHeight, h) - h);
    // Where each is on the page, and which window's worth shows it.
    const places = shown.map((mark) => {
      const r = mark.el.isConnected ? mark.el.getBoundingClientRect() : mark.rect;
      const page = new DOMRect(r.left + left, r.top + top, r.width, r.height);
      const seen = r.bottom > 0 && r.top < h;
      const y = seen ? top : Math.round(Math.min(most, Math.max(0, page.top + page.height / 2 - h / 2)));
      return { n: mark.n, page, y };
    });
    const pictures = new Map<number, HTMLCanvasElement>();
    await unseen(async () => {
      for (const y of new Set(places.map((p) => p.y))) pictures.set(y, await windowAt(doc!, left, y, scale, y === top));
    });
    const out: { n: number; png: ArrayBuffer }[] = [];
    for (const place of places) {
      const shot = pictures.get(place.y)!;
      const canvas = document.createElement("canvas");
      canvas.width = shot.width;
      canvas.height = shot.height;
      const g = canvas.getContext("2d")!;
      g.drawImage(shot, 0, 0);
      g.scale(scale, scale);
      drawMark(g, place.n, place.page.x - left, place.page.y - place.y, place.page.width, place.page.height);
      const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, "image/png"));
      if (!blob) throw new Error("no-picture");
      out.push({ n: place.n, png: await blob.arrayBuffer() });
    }
    return out;
  }

  /**
   * The window's worth of the page at (`x`, `y`), as it shows scrolled there: what is fixed stays where it is in the
   * window, and, for where it is now (`now`), what is sticky where it is stuck.
   */
  async function windowAt(d: Document, x: number, y: number, scale: number, now: boolean): Promise<HTMLCanvasElement> {
    const win = d.defaultView!;
    const tag = "data-stillfail-shot";
    const held = new Map<string, { x: number; y: number } | null>();
    let i = 0;
    for (const el of d.body?.querySelectorAll<HTMLElement>("*") ?? []) {
      const position = win.getComputedStyle(el).position;
      if (position === "fixed") held.set(String(i), null);
      else if (position === "sticky" && now) {
        // How far it is stuck from where it would be: its place now, against its place in the flow.
        const at = el.getBoundingClientRect();
        const inline = el.style.getPropertyValue("position"), priority = el.style.getPropertyPriority("position");
        el.style.setProperty("position", "static", "important");
        const flow = el.getBoundingClientRect();
        if (inline) el.style.setProperty("position", inline, priority);
        else el.style.removeProperty("position");
        held.set(String(i), { x: at.left - flow.left, y: at.top - flow.top });
      } else continue;
      el.setAttribute(tag, String(i++));
    }
    try {
      return await domToCanvas(d.documentElement, {
        width: win.innerWidth, height: win.innerHeight, scale, timeout: 15000, backgroundColor: ground(d),
        // The picture is drawn from the page's top: moved up by where it is scrolled to.
        style: { margin: "0", transform: `translate(${-x}px, ${-y}px)` },
        onCloneEachNode: (node) => {
          // The copy is another window's: its nodes are not this one's Element.
          if (node.nodeType !== Node.ELEMENT_NODE) return;
          const at = (node as Element).getAttribute(tag);
          if (at === null) return;
          (node as Element).removeAttribute(tag);
          const style = (node as HTMLElement).style;
          const stuck = held.get(at);
          // What is fixed goes with the page's top in the copy (the moved page holds it): back into the window.
          if (stuck === null) style.translate = `${x}px ${y}px`;
          else if (stuck) Object.assign(style, { position: "relative", top: `${stuck.y}px`, left: `${stuck.x}px`, bottom: "auto", right: "auto" });
        },
      });
    } finally {
      for (const el of d.querySelectorAll(`[${tag}]`)) el.removeAttribute(tag);
    }
  }

  /** The whole page (as tall as MAX_HEIGHT), with each mark boxed and numbered. */
  async function shoot(shown: typeof marks): Promise<ArrayBuffer> {
    if (!doc) throw new Error("no-page");
    const win = doc.defaultView!;
    const root = doc.documentElement;
    const width = Math.max(root.scrollWidth, win.innerWidth);
    const height = Math.min(Math.max(root.scrollHeight, win.innerHeight), MAX_HEIGHT);
    const scale = Math.min(win.devicePixelRatio || 1, 2, Math.sqrt(MAX_PIXELS / (width * height)));
    const canvas = await unseen(() => domToCanvas(root, {
      width, height, scale, timeout: 15000, backgroundColor: ground(doc!),
      // The page is shown from its top: where it is scrolled to is not the picture's.
      style: { margin: "0" },
    }));
    const g = canvas.getContext("2d")!;
    g.scale(scale, scale);
    for (const mark of shown) {
      const r = mark.el.isConnected ? mark.el.getBoundingClientRect() : mark.rect;
      drawMark(g, mark.n, r.left + win.scrollX, r.top + win.scrollY, r.width, r.height);
    }
    const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, "image/png"));
    if (!blob) throw new Error("no-picture");
    return blob.arrayBuffer();
  }
}

/** A mark as the page shows it: the element's outline, its number in a pin on its top-left corner. */
function drawMark(g: CanvasRenderingContext2D, n: number, x: number, y: number, width: number, height: number) {
  g.save();
  g.font = "600 12px system-ui, -apple-system, sans-serif";
  g.textBaseline = "middle";
  g.textAlign = "center";
  g.strokeStyle = MARK;
  g.lineWidth = 2;
  g.beginPath();
  g.roundRect(x, y, width, height, 3);
  g.stroke();
  // The pin: its point on the corner, as the client draws it (Marks.css.ts).
  const px = Math.max(2, x) - 2, py = Math.max(24, y) - 22;
  g.shadowColor = "rgba(0,0,0,.25)";
  g.shadowBlur = 6;
  g.shadowOffsetY = 1;
  g.fillStyle = "#fff";
  g.beginPath();
  g.roundRect(px, py, 24, 24, [12, 12, 12, 3]);
  g.fill();
  g.shadowColor = "transparent";
  g.fillStyle = MARK;
  g.beginPath();
  g.roundRect(px + 2, py + 2, 20, 20, [10, 10, 10, 2]);
  g.fill();
  g.fillStyle = "#fff";
  g.fillText(String(n), px + 12, py + 12.5);
  g.restore();
}

const box = (r: DOMRect) => ({ x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) });

/** Names that look made by a build (css-in-js, css modules) say nothing to a person. */
const made = (name: string) => /\d{3,}|^css-|^sc-|^_|__[A-Za-z0-9]{5,}$|^[a-z]{1,3}-[A-Za-z0-9]{5,}$/.test(name);

function label(el: Element): string {
  let text = el.localName;
  if (el.id && !made(el.id)) text += `#${el.id}`;
  const classes = [...el.classList].filter((c) => !made(c)).slice(0, 3);
  if (classes.length) text += `.${classes.join(".")}`;
  return text;
}

const KINDS: Record<string, string> = {
  button: "button", a: "link", img: "image", svg: "icon", picture: "image", video: "video", input: "input", textarea: "input",
  select: "select", label: "label", h1: "heading", h2: "heading", h3: "heading", h4: "heading", h5: "heading", h6: "heading", p: "paragraph",
  li: "listItem", ul: "list", ol: "list", nav: "nav", header: "header", footer: "footer", table: "table", tr: "tableRow", td: "cell",
  th: "tableHeader", form: "form", aside: "aside", dialog: "dialog", code: "code", pre: "code",
};

/** What sort of thing it is, as a word the client says in its language (Picked.kind). */
function kindOf(el: Element): string {
  const role = el.getAttribute("role");
  if (role === "button") return "button";
  if (role === "link") return "link";
  if (el instanceof HTMLInputElement && ["button", "submit", "reset"].includes(el.type)) return "button";
  if (el instanceof HTMLInputElement && ["checkbox", "radio"].includes(el.type)) return "checkbox";
  if (KINDS[el.localName]) return KINDS[el.localName]!;
  // A block with words of its own reads as text, one with nothing but others inside as a block.
  const own = [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent!.trim());
  return own ? "text" : "block";
}

function selector(el: Element): string {
  const doc = el.ownerDocument;
  const one = (css: string) => { try { return doc.querySelectorAll(css).length === 1; } catch { return false; } };
  const parts: string[] = [];
  for (let node: Element | null = el; node && node !== doc.documentElement; node = node.parentElement) {
    if (node.id && !made(node.id) && one(`#${CSS.escape(node.id)}`)) { parts.unshift(`#${CSS.escape(node.id)}`); break; }
    const tag = ["data-testid", "data-test", "data-cy", "data-qa"].find((a) => node!.hasAttribute(a));
    if (tag) {
      const css = `[${tag}="${CSS.escape(node.getAttribute(tag)!)}"]`;
      if (one(css)) { parts.unshift(css); break; }
    }
    let part = node.localName;
    const kin = node.parentElement ? [...node.parentElement.children].filter((c) => c.localName === node!.localName) : [];
    if (kin.length > 1) part += `:nth-of-type(${kin.indexOf(node) + 1})`;
    parts.unshift(part);
    if (node.localName === "body") break;
  }
  return parts.join(" > ");
}

function words(el: Element): string {
  const cut = (s: string) => { const t = s.replace(/\s+/g, " ").trim(); return t.length > 80 ? `${t.slice(0, 80)}…` : t; };
  if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) return cut(el.value || el.placeholder || "");
  if (el instanceof HTMLImageElement) return cut(el.alt);
  const aria = el.getAttribute("aria-label");
  if (aria) return cut(aria);
  return cut((el as HTMLElement).innerText ?? el.textContent ?? "");
}

/** The components the element is in, as React's or Vue's development builds keep them on it. */
function component(el: Element): string | null {
  const names: string[] = [];
  let source: string | null = null;
  const own = el as unknown as Record<string, unknown>;
  const fiberKey = Object.keys(own).find((k) => k.startsWith("__reactFiber$"));
  if (fiberKey) {
    type Fiber = { type: unknown; return: Fiber | null; _debugSource?: { fileName: string; lineNumber: number } };
    for (let fiber = own[fiberKey] as Fiber | null; fiber && names.length < 4; fiber = fiber.return) {
      if (!source && fiber._debugSource) source = `${fiber._debugSource.fileName}:${fiber._debugSource.lineNumber}`;
      const type = fiber.type as { displayName?: string; name?: string; render?: { name?: string } } | string | null;
      if (!type || typeof type === "string") continue;
      const name = type.displayName || type.name || type.render?.name;
      if (name && !names.includes(name) && /^[A-Z]/.test(name)) names.unshift(name);
    }
  } else {
    type Vue = { type: { __name?: string; name?: string; __file?: string }; parent: Vue | null };
    let node: Element | null = el;
    while (node && !(node as unknown as { __vueParentComponent?: Vue }).__vueParentComponent) node = node.parentElement;
    for (let c = (node as unknown as { __vueParentComponent?: Vue } | null)?.__vueParentComponent ?? null; c && names.length < 4; c = c.parent) {
      const name = c.type.__name || c.type.name || c.type.__file?.split("/").pop()?.replace(/\.vue$/, "");
      if (!source && c.type.__file) source = c.type.__file;
      if (name && !names.includes(name)) names.unshift(name);
    }
  }
  if (!names.length) return null;
  return names.join(" › ") + (source ? `（${source}）` : "");
}
