// What a person does over a screen they drive, said to the station as the core's `screen.input` takes it
// (docs/remote-screens.md): the pointer and the wheel at 0..1 of the picture (its letterbox left out), keys, and text
// (an IME's, a paste's, a phone's keyboard's; a paste the host takes goes on the screen's clipboard instead). A mouse clicks and drags as itself; a finger taps (a click), drags (the
// button held) and scrolls with two. Keys are heard by a hidden textarea that holds the focus while driving, so an
// IME composes in it and a phone's keyboard comes up for it. Moves and the wheel go once a frame, the latest.

export type ScreenInput =
  | { t: "pointer"; kind: "down" | "up" | "move"; x: number; y: number; buttons: number }
  | { t: "wheel"; x: number; y: number; dx: number; dy: number }
  | { t: "key"; kind: "down" | "up"; key: string; code: string; mods: number }
  | { t: "text"; text: string };

import { padGain, type Box, type PadPointer, type Zoom } from "./zoom.ts";

export interface InputHost {
  /** Where pointers are heard: the picture and its letterbox. */
  stage: HTMLElement;
  /** The picture's box, as drawn (its rect is the frame's). */
  picture: () => HTMLElement | null;
  /** What hears the keys (focused while driving). */
  keys: HTMLTextAreaElement;
  /** Whether what is done goes to the station (控制), not only looked at (只看). */
  driving: () => boolean;
  send: (input: ScreenInput) => void;
  /** A mouse is over the picture while driving (or has left it): its own pointer shows the station's shape then. */
  hovering?: (on: boolean) => void;
  /** A paste, taken by the host (onto the screen's clipboard, pasted there): true when it took it, else it is typed. */
  paste?: (data: DataTransfer) => boolean;
  /** A phone's fingers: the picture zoomed here, and driven as a trackpad where `pad` says. */
  fingers?: {
    /** As a trackpad (else directly): the finger moves `pointer`, a tap clicks where it points. */
    pad: () => boolean;
    pointer: PadPointer;
    zoom: Zoom;
    /** The picture fitted on the stage, and the stage's size (px, on the stage). */
    fit: () => Box;
    room: () => { width: number; height: number };
    /** The zoom or the pointer moved: drawn again. */
    moved: () => void;
  };
  /** The modifiers held on the keys row (bit 0 Alt, 1 Ctrl, 2 Meta, 3 Shift), let go of once a key is sent with them. */
  held?: { take: () => number };
}

/** A finger moved this far is a drag, not a tap. */
const SLOP = 8;
/** A finger held this long is a press held (the right button; on a trackpad, a drag). */
const HOLD_MS = 500;
/** A finger down again this soon after a tap on a trackpad, and moved, drags. */
const DOUBLE_MS = 300;
/** How far within the stage's edges the trackpad's pointer is kept, the picture zoomed. */
const MARGIN = 40;
/** A line or a page of the wheel, in pixels (a mouse that says lines). */
const LINE = 16;

/** The DOM's `code` of a character typed with a modifier held (⌘ then c: KeyC); "" for one with no key of its own. */
export function codeOf(c: string): string {
  const l = c.toLowerCase();
  if (l >= "a" && l <= "z" && l.length === 1) return `Key${l.toUpperCase()}`;
  if (c >= "0" && c <= "9" && c.length === 1) return `Digit${c}`;
  return PUNCTUATION[c] ?? "";
}
const PUNCTUATION: Record<string, string> = {
  " ": "Space", "-": "Minus", "=": "Equal", "[": "BracketLeft", "]": "BracketRight", "\\": "Backslash", ";": "Semicolon",
  "'": "Quote", ",": "Comma", ".": "Period", "/": "Slash", "`": "Backquote",
};

/** The modifier keys held, as the station takes them: bit 0 Alt, 1 Ctrl, 2 Meta, 3 Shift. */
export function mods(e: { altKey: boolean; ctrlKey: boolean; metaKey: boolean; shiftKey: boolean }): number {
  return (e.altKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.metaKey ? 4 : 0) | (e.shiftKey ? 8 : 0);
}

/** Starts hearing what is done over `host.stage`; the function returned stops it. */
export function hearInput(host: InputHost): () => void {
  const { stage, keys } = host;
  const offs: (() => void)[] = [];
  const on = <K extends keyof HTMLElementEventMap>(el: HTMLElement, type: K, f: (e: HTMLElementEventMap[K]) => void, options?: AddEventListenerOptions) => {
    el.addEventListener(type, f as EventListener, options);
    offs.push(() => el.removeEventListener(type, f as EventListener, options));
  };

  /** Where a point of the window is on the picture, 0..1 each way; `inside` whether it is on it at all. */
  const where = (clientX: number, clientY: number) => {
    const r = host.picture()?.getBoundingClientRect();
    if (!r || r.width <= 0 || r.height <= 0) return null;
    const x = (clientX - r.left) / r.width, y = (clientY - r.top) / r.height;
    return { x: Math.min(1, Math.max(0, x)), y: Math.min(1, Math.max(0, y)), inside: x >= 0 && x <= 1 && y >= 0 && y <= 1 };
  };

  // ── once a frame: the latest move, the wheel summed ──
  let move: { x: number; y: number; buttons: number } | null = null;
  let wheel: { x: number; y: number; dx: number; dy: number } | null = null;
  let frame = 0;
  const flush = () => {
    frame = 0;
    if (move) { host.send({ t: "pointer", kind: "move", ...move }); move = null; }
    if (wheel && (wheel.dx || wheel.dy)) host.send({ t: "wheel", ...wheel });
    wheel = null;
  };
  const later = () => { if (!frame) frame = requestAnimationFrame(flush); };
  /** What waits for the frame goes first: a press after a move is where the move left it. */
  const now = () => { if (frame) cancelAnimationFrame(frame); flush(); };
  offs.push(() => { if (frame) cancelAnimationFrame(frame); });
  const press = (kind: "down" | "up", at: { x: number; y: number }, buttons: number) => { now(); host.send({ t: "pointer", kind, x: at.x, y: at.y, buttons }); };

  // ── a mouse (or a pen): itself ──
  let held = 0;
  let over = false;
  const hover = (is: boolean) => { if (is !== over) { over = is; host.hovering?.(is); } };
  on(stage, "pointerdown", (e) => {
    if (e.pointerType === "touch" || !host.driving()) return;
    const at = where(e.clientX, e.clientY);
    // The keys follow the pointer into the picture (the letterbox too: a click beside it is still "here").
    keys.focus({ preventScroll: true });
    e.preventDefault();
    if (!at?.inside) return;
    stage.setPointerCapture(e.pointerId);
    held = e.buttons;
    press("down", at, e.buttons);
  });
  on(stage, "pointermove", (e) => {
    if (e.pointerType === "touch") return;
    const at = where(e.clientX, e.clientY);
    const driving = host.driving();
    hover(driving && e.pointerType === "mouse" && !!at?.inside);
    if (!driving || !at || (!at.inside && !held)) return;
    move = { x: at.x, y: at.y, buttons: e.buttons };
    later();
  });
  on(stage, "pointerleave", (e) => { if (e.pointerType !== "touch") hover(false); });
  on(stage, "pointerup", (e) => {
    if (e.pointerType === "touch" || !held) return;
    const at = where(e.clientX, e.clientY);
    held = e.buttons;
    if (at && host.driving()) press("up", at, e.buttons);
  });
  // Captured away (or the window lost it) with a button down: let go of it there.
  on(stage, "lostpointercapture", (e) => {
    if (e.pointerType === "touch" || !held) return;
    held = 0;
    const at = where(e.clientX, e.clientY);
    if (at && host.driving()) press("up", at, 0);
  });
  on(stage, "contextmenu", (e) => { if (host.driving()) e.preventDefault(); });
  on(stage, "wheel", (e) => {
    if (!host.driving()) return;
    const at = where(e.clientX, e.clientY);
    if (!at?.inside) return;
    e.preventDefault();
    const by = e.deltaMode === 1 ? LINE : e.deltaMode === 2 ? stage.clientHeight : 1;
    wheel = { x: at.x, y: at.y, dx: (wheel?.dx ?? 0) + e.deltaX * by, dy: (wheel?.dy ?? 0) + e.deltaY * by };
    later();
  }, { passive: false });

  // ── fingers ──
  // Driving it directly: a tap clicks where it is, one finger drags, two scroll, a press held right-clicks (a phone's).
  // As a trackpad (a phone's, where it says): a finger moves the pointer, a tap clicks where it points, tapped again
  // and moved (or held) it drags, two tapped right-click, two moving together scroll. On a phone two fingers spreading
  // zoom the picture here (never sent), and while only looking a zoomed picture is moved about.
  const pad = host.fingers;
  const fingers = new Map<number, { x: number; y: number; at: number }>();
  type Two = { kind: "" | "zoom" | "scroll"; c0: { x: number; y: number }; s0: number; from: { x: number; y: number }; spread: number; at: number; moved: boolean };
  let touch: "idle" | "pending" | "move" | "drag" | "pan" | "two" | "done" = "idle";
  let start: { x: number; y: number; at: number } | null = null;
  let two: Two | null = null;
  let again = false;
  let hold = 0;
  let lastTap = { at: -Infinity, x: 0, y: 0 };
  const middle = () => {
    let x = 0, y = 0;
    for (const f of fingers.values()) { x += f.x; y += f.y; }
    return { x: x / fingers.size, y: y / fingers.size };
  };
  const spreadOf = (c: { x: number; y: number }) => {
    let d = 0;
    for (const f of fingers.values()) d += Math.hypot(f.x - c.x, f.y - c.y);
    return d / fingers.size;
  };
  const padding = () => !!pad && host.driving() && pad.pad();
  /** A point of the window on the stage, in its own px (the zoom's). */
  const onStage = (p: { x: number; y: number }) => { const r = stage.getBoundingClientRect(); return { x: p.x - r.left, y: p.y - r.top }; };
  const atPointer = () => (pad ? { x: pad.pointer.x, y: pad.pointer.y } : null);
  const unhold = () => { if (hold) { clearTimeout(hold); hold = 0; } };
  offs.push(unhold);
  on(stage, "pointerdown", (e) => {
    if (e.pointerType !== "touch" || (!pad && !host.driving())) return;
    fingers.set(e.pointerId, { x: e.clientX, y: e.clientY, at: e.timeStamp });
    stage.setPointerCapture(e.pointerId);
    if (fingers.size === 1) {
      touch = "pending";
      start = { x: e.clientX, y: e.clientY, at: e.timeStamp };
      again = e.timeStamp - lastTap.at < DOUBLE_MS && Math.hypot(e.clientX - lastTap.x, e.clientY - lastTap.y) < SLOP * 4;
      unhold();
      hold = window.setTimeout(() => {
        hold = 0;
        if (touch !== "pending" || !host.driving() || !start) return;
        if (padding()) { const at = atPointer(); if (at) { press("down", at, 1); touch = "drag"; } return; }
        // A press held: the right button, where it is.
        const at = where(start.x, start.y);
        if (at?.inside) { press("down", at, 2); press("up", at, 0); }
        touch = "done";
      }, HOLD_MS);
    } else if (fingers.size === 2 && touch !== "two" && touch !== "done") {
      unhold();
      // A second finger: a drag under way ends where it is.
      if (touch === "drag") { const at = padding() ? atPointer() : move ? { x: move.x, y: move.y } : null; if (at) press("up", at, 0); }
      const c = middle();
      two = { kind: "", c0: c, s0: spreadOf(c), from: c, spread: spreadOf(c), at: e.timeStamp, moved: false };
      touch = "two";
    }
  });
  on(stage, "pointermove", (e) => {
    if (e.pointerType !== "touch" || !fingers.has(e.pointerId)) return;
    const was = fingers.get(e.pointerId)!;
    fingers.set(e.pointerId, { x: e.clientX, y: e.clientY, at: e.timeStamp });
    const driving = host.driving();
    if (touch === "pending" && start && Math.hypot(e.clientX - start.x, e.clientY - start.y) > SLOP) {
      unhold();
      if (padding()) {
        const at = atPointer();
        if (again && at) { press("down", at, 1); touch = "drag"; } else touch = "move";
      } else if (driving) {
        const from = where(start.x, start.y);
        if (from?.inside) { touch = "drag"; press("down", from, 1); } else touch = pad?.zoom.zoomed ? "pan" : "idle";
      } else touch = pad?.zoom.zoomed ? "pan" : "done";
      return;
    }
    if ((touch === "move" || touch === "drag") && padding() && pad) {
      const s = pad.zoom.shown(pad.fit());
      const dx = e.clientX - was.x, dy = e.clientY - was.y;
      if (s.width <= 0 || (!dx && !dy)) return;
      const gain = padGain(Math.hypot(dx, dy) / Math.max(1, e.timeStamp - was.at));
      pad.pointer.by(dx * gain / s.width, dy * gain / s.height, performance.now());
      move = { x: pad.pointer.x, y: pad.pointer.y, buttons: touch === "drag" ? 1 : 0 };
      later();
      if (pad.zoom.zoomed) pad.zoom.keep({ x: pad.pointer.x, y: pad.pointer.y }, MARGIN, pad.fit(), pad.room());
      pad.moved();
    } else if (touch === "drag" && driving) {
      const at = where(e.clientX, e.clientY);
      if (at) { move = { x: at.x, y: at.y, buttons: 1 }; later(); }
    } else if (touch === "pan" && pad) {
      pad.zoom.pan({ x: e.clientX - was.x, y: e.clientY - was.y }, pad.fit(), pad.room());
      pad.moved();
    } else if (touch === "two" && two && fingers.size >= 2) {
      const c = middle(), sp = spreadOf(c);
      if (!two.kind) {
        const spreading = Math.abs(sp - two.s0), moving = Math.hypot(c.x - two.c0.x, c.y - two.c0.y);
        if (spreading > SLOP || moving > SLOP) { two.kind = pad && spreading > moving ? "zoom" : "scroll"; two.moved = true; }
      }
      if (two.kind === "zoom" && pad) {
        pad.zoom.by(two.spread > 0 ? sp / two.spread : 1, onStage(c), { x: c.x - two.from.x, y: c.y - two.from.y }, pad.fit(), pad.room());
        pad.moved();
      } else if (two.kind === "scroll") {
        const at = padding() ? atPointer() : where(c.x, c.y);
        if (driving && at) {
          // The page follows the fingers: up is further down it.
          wheel = { x: at.x, y: at.y, dx: (wheel?.dx ?? 0) - (c.x - two.from.x), dy: (wheel?.dy ?? 0) - (c.y - two.from.y) };
          later();
        } else if (pad?.zoom.zoomed) { pad.zoom.pan({ x: c.x - two.from.x, y: c.y - two.from.y }, pad.fit(), pad.room()); pad.moved(); }
      }
      // Until it is told what they are doing, measured from where they began: none of the way lost.
      if (two.kind) { two.from = c; two.spread = sp; }
    }
  });
  const lift = (e: PointerEvent, cancelled: boolean) => {
    if (e.pointerType !== "touch" || !fingers.has(e.pointerId)) return;
    fingers.delete(e.pointerId);
    unhold();
    const driving = host.driving();
    if (touch === "two") {
      if (fingers.size) return;
      // Two fingers tapped: the right button, where the trackpad points.
      const at = atPointer();
      if (!cancelled && two && !two.moved && padding() && at && e.timeStamp - two.at < HOLD_MS) { press("down", at, 2); press("up", at, 0); }
      touch = "idle"; two = null; start = null;
      return;
    }
    if (touch === "pending" && start && !cancelled && driving) {
      const at = padding() ? atPointer() : where(start.x, start.y);
      if (at && (padding() || where(start.x, start.y)?.inside)) { press("down", at, 1); press("up", at, 0); }
      if (padding()) lastTap = { at: e.timeStamp, x: start.x, y: start.y };
    } else if (touch === "drag" && driving) {
      const at = padding() ? atPointer() : where(e.clientX, e.clientY);
      if (at) press("up", at, 0);
    }
    if (!fingers.size) { touch = "idle"; start = null; }
  };
  on(stage, "pointerup", (e) => lift(e, false));
  on(stage, "pointercancel", (e) => lift(e, true));

  // ── keys, text, an IME, a paste ──
  const down = new Map<string, string>();
  const key = (kind: "down" | "up", k: string, code: string, m: number) => host.send({ t: "key", kind, key: k, code, mods: m });
  /** The modifiers held on the keys row, for a key now (let go of after it). */
  const heldMods = () => host.held?.take() ?? 0;
  /** A key pressed and let go at once (a phone keyboard's Enter, its delete), with what is held on the keys row. */
  const stroke = (k: string, code: string) => { const m = heldMods(); key("down", k, code, m); key("up", k, code, m); };
  /** Text typed: as text, or with a modifier held on the keys row each character as its key with it (⌘ then c: ⌘C). */
  const typed = (text: string) => {
    const m = heldMods();
    if (!m) { host.send({ t: "text", text }); return; }
    for (const c of text) { const code = codeOf(c); key("down", c, code, m); key("up", c, code, m); }
  };
  /** What was held as each key went down, for it to go up with it too. */
  const downWith = new Map<string, number>();
  const letGo = () => { for (const [code, k] of down) key("up", k, code, 0); down.clear(); };
  on(keys, "keydown", (e) => {
    if (!host.driving()) return;
    // Not the app's shortcuts while its keys are the station's.
    e.stopPropagation();
    // An IME composing, or a phone keyboard that does not say which key: what it makes comes as text (below).
    if (e.isComposing || e.keyCode === 229 || e.key === "Process" || e.key === "Unidentified" || e.key === "Dead") return;
    // A paste: its text comes in the paste event.
    if ((e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === "v") return;
    const printable = [...e.key].length === 1;
    // A soft keyboard's letter (no physical key): as text.
    if (printable && !e.code && !e.ctrlKey && !e.metaKey && !e.altKey) return;
    e.preventDefault();
    const code = e.code || e.key;
    down.set(code, e.key);
    const extra = heldMods();
    downWith.set(code, extra);
    key("down", e.key, e.code, mods(e) | extra);
  });
  on(keys, "keyup", (e) => {
    e.stopPropagation();
    const code = e.code || e.key;
    if (!down.has(code)) return;
    e.preventDefault();
    down.delete(code);
    const extra = downWith.get(code) ?? 0;
    downWith.delete(code);
    if (host.driving()) key("up", e.key, e.code, mods(e) | extra);
  });
  on(keys, "beforeinput", (e) => {
    if (!host.driving() || e.isComposing) return;
    const type = e.inputType;
    if (type === "insertText" && e.data) { e.preventDefault(); typed(e.data); }
    else if (type === "insertLineBreak" || type === "insertParagraph") { e.preventDefault(); stroke("Enter", "Enter"); }
    else if (type === "deleteContentBackward") { e.preventDefault(); stroke("Backspace", "Backspace"); }
    else if (type === "deleteContentForward") { e.preventDefault(); stroke("Delete", "Delete"); }
  });
  on(keys, "compositionend", (e) => {
    if (host.driving() && e.data) typed(e.data);
    // Emptied once the IME is done with it.
    setTimeout(() => { keys.value = ""; }, 0);
  });
  // What got into it anyway (a browser that would not hold it back): said, and taken out.
  on(keys, "input", (e) => {
    if ((e as InputEvent).isComposing || !keys.value) return;
    if (host.driving()) typed(keys.value);
    keys.value = "";
  });
  on(keys, "paste", (e) => {
    e.preventDefault();
    if (!host.driving()) return;
    if (e.clipboardData && host.paste?.(e.clipboardData)) return;
    const text = e.clipboardData?.getData("text/plain");
    if (text && host.driving()) host.send({ t: "text", text });
  });
  on(keys, "blur", letGo);
  offs.push(letGo);

  return () => { for (const off of offs.splice(0).reverse()) off(); };
}
