// What a person does over a screen they drive, said to the station as the core's `screen.input` takes it
// (docs/remote-screens.md): the pointer and the wheel at 0..1 of the picture (its letterbox left out), keys, and text
// (an IME's, a paste's, a phone's keyboard's). A mouse clicks and drags as itself; a finger taps (a click), drags (the
// button held) and scrolls with two. Keys are heard by a hidden textarea that holds the focus while driving, so an
// IME composes in it and a phone's keyboard comes up for it. Moves and the wheel go once a frame, the latest.

export type ScreenInput =
  | { t: "pointer"; kind: "down" | "up" | "move"; x: number; y: number; buttons: number }
  | { t: "wheel"; x: number; y: number; dx: number; dy: number }
  | { t: "key"; kind: "down" | "up"; key: string; code: string; mods: number }
  | { t: "text"; text: string };

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
}

/** A finger moved this far is a drag, not a tap. */
const SLOP = 8;
/** A line or a page of the wheel, in pixels (a mouse that says lines). */
const LINE = 16;

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

  // ── fingers: a tap clicks, one drags, two scroll ──
  const fingers = new Map<number, { x: number; y: number }>();
  let touch: "idle" | "pending" | "drag" | "scroll" = "idle";
  let start: { x: number; y: number } | null = null;
  let centre: { x: number; y: number } | null = null;
  const middle = () => {
    let x = 0, y = 0;
    for (const f of fingers.values()) { x += f.x; y += f.y; }
    return { x: x / fingers.size, y: y / fingers.size };
  };
  on(stage, "pointerdown", (e) => {
    if (e.pointerType !== "touch" || !host.driving()) return;
    fingers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    stage.setPointerCapture(e.pointerId);
    if (fingers.size === 1) { touch = "pending"; start = { x: e.clientX, y: e.clientY }; }
    else if (fingers.size === 2 && touch === "pending") { touch = "scroll"; centre = middle(); }
  });
  on(stage, "pointermove", (e) => {
    if (e.pointerType !== "touch" || !fingers.has(e.pointerId)) return;
    fingers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (!host.driving()) return;
    if (touch === "pending" && start && Math.hypot(e.clientX - start.x, e.clientY - start.y) > SLOP) {
      const from = where(start.x, start.y);
      if (from?.inside) { touch = "drag"; press("down", from, 1); } else touch = "idle";
    }
    if (touch === "drag") {
      const at = where(e.clientX, e.clientY);
      if (at) { move = { x: at.x, y: at.y, buttons: 1 }; later(); }
    } else if (touch === "scroll" && centre) {
      const c = middle();
      const at = where(c.x, c.y);
      // The page follows the fingers: up is further down it.
      if (at) { wheel = { x: at.x, y: at.y, dx: (wheel?.dx ?? 0) - (c.x - centre.x), dy: (wheel?.dy ?? 0) - (c.y - centre.y) }; later(); }
      centre = c;
    }
  });
  const lift = (e: PointerEvent, cancelled: boolean) => {
    if (e.pointerType !== "touch" || !fingers.has(e.pointerId)) return;
    fingers.delete(e.pointerId);
    if (touch === "scroll") { centre = fingers.size ? middle() : null; if (!fingers.size) touch = "idle"; return; }
    const driving = host.driving();
    if (touch === "pending" && start && !cancelled && driving) {
      const at = where(start.x, start.y);
      if (at?.inside) { press("down", at, 1); press("up", at, 0); }
    } else if (touch === "drag" && driving) {
      const at = where(e.clientX, e.clientY);
      if (at) press("up", at, 0);
    }
    if (!fingers.size) { touch = "idle"; start = null; }
  };
  on(stage, "pointerup", (e) => lift(e, false));
  on(stage, "pointercancel", (e) => lift(e, true));

  // ── keys, text, an IME, a paste ──
  const down = new Map<string, string>();
  const key = (kind: "down" | "up", k: string, code: string, m: number) => host.send({ t: "key", kind, key: k, code, mods: m });
  /** A key pressed and let go at once (a phone keyboard's Enter, its delete). */
  const stroke = (k: string, code: string) => { key("down", k, code, 0); key("up", k, code, 0); };
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
    key("down", e.key, e.code, mods(e));
  });
  on(keys, "keyup", (e) => {
    e.stopPropagation();
    const code = e.code || e.key;
    if (!down.has(code)) return;
    e.preventDefault();
    down.delete(code);
    if (host.driving()) key("up", e.key, e.code, mods(e));
  });
  on(keys, "beforeinput", (e) => {
    if (!host.driving() || e.isComposing) return;
    const type = e.inputType;
    if (type === "insertText" && e.data) { e.preventDefault(); host.send({ t: "text", text: e.data }); }
    else if (type === "insertLineBreak" || type === "insertParagraph") { e.preventDefault(); stroke("Enter", "Enter"); }
    else if (type === "deleteContentBackward") { e.preventDefault(); stroke("Backspace", "Backspace"); }
    else if (type === "deleteContentForward") { e.preventDefault(); stroke("Delete", "Delete"); }
  });
  on(keys, "compositionend", (e) => {
    if (host.driving() && e.data) host.send({ t: "text", text: e.data });
    // Emptied once the IME is done with it.
    setTimeout(() => { keys.value = ""; }, 0);
  });
  // What got into it anyway (a browser that would not hold it back): said, and taken out.
  on(keys, "input", (e) => {
    if ((e as InputEvent).isComposing || !keys.value) return;
    if (host.driving()) host.send({ t: "text", text: keys.value });
    keys.value = "";
  });
  on(keys, "paste", (e) => {
    e.preventDefault();
    const text = e.clipboardData?.getData("text/plain");
    if (text && host.driving()) host.send({ t: "text", text });
  });
  on(keys, "blur", letGo);
  offs.push(letGo);

  return () => { for (const off of offs.splice(0).reverse()) off(); };
}
