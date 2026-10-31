// computer: the agents operate the station's screens themselves (docs/remote-screens.md, "Agents on a screen"): a
// screenshot of one (a JPEG, the source's own frame), and a person's input on it (clicks, drags, the wheel, keys, text),
// given in the screenshot's pixels and posted as the screen contract's 0..1. Built on the ScreenSource contract only:
// a session keeps one view of a screen open while it uses it (closed after IDLE_MS unused), joined to the screen's
// people as "agent: <its chat>", so it shows in `controlledBy` and a person watching sees it work. A person driving the
// screen at that moment has it: the agent's input is refused until they leave it.
//
// On the desktop an agent also reads an app's window as its accessibility tree (`tree`, screens/ui.ts: agent-desktop)
// and acts on its elements by ref (`ref` with click, type, set, scroll; `app` with key): through the accessibility API,
// not the pointer or the keyboard focus, so it needs no picture, works on a window behind others, and goes on while a
// person drives the screen. Each such action answers with the app's tree again.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { tr } from "../ops/i18n.ts";
import { type ScreenHub, ScreenRefused, accessShown } from "../screens/hub.ts";
import { treeText } from "../screens/ui.ts";
import type { Frame, ScreenInput, ScreenSource, ScreenView } from "../screens/source.ts";
import type { Content, Tool, ToolReply } from "./mcp.ts";

/// A screenshot's longest side at most (the source scales its frames into this box).
export const SHOT_MAX = 1280;
/// A session's view of a screen closes after this long unused.
export const IDLE_MS = 60_000;
/// After an action, this long before its screenshot (the screen answering it), unless `wait` says otherwise.
export const SETTLE_MS = 500;
/// The first picture of a view comes within this, or the screen is taken as showing nothing.
export const FIRST_MS = 10_000;
/// The longest `wait`.
export const WAIT_MAX = 30_000;
/// A drag's moves between its press and its release.
export const DRAG_STEPS = 8;
/// After an action by ref, this long before the app's tree is read again, unless `wait` says otherwise.
export const TREE_SETTLE_MS = 200;
/// A scroll by ref: this many pixels of `dx`/`dy` a unit of agent-desktop's (a wheel notch's lines).
export const SCROLL_UNIT_PX = 100;

/// `mods` bits as the contract has them (CDP's order).
export const MODS = { alt: 1, ctrl: 2, meta: 4, shift: 8 } as const;

export const COMPUTER = {
  name: "computer",
  description:
    "Operate one of this station's screens yourself (the `screen` tool lists them: desktop, browser:<tab>, simulator:<udid>, an iOS Simulator booted here, touched where you click): take a screenshot, click, move, drag, scroll, type text, press keys. Coordinates are pixels of the latest screenshot of that screen (each result says its size and how it maps to the screen). Every action returns a fresh screenshot unless screenshot=false. On the desktop prefer an app's accessibility tree: action=tree with app (no app: the apps running) gives its window as text, an element a line with its ref (e12); then click, type, set (replace a field's value with text; on Windows type by ref is refused, as it needs the focus: use set) or scroll with ref act on that element without the pointer or the focus (also behind other windows, and while a person drives the screen), and key with app sends keys to that app; each answers with the app's tree again. A big window: tree with skeleton=true first, then tree with ref for one part. Use screenshots for what has no tree (a canvas, a game, a picture). For web pages prefer the browser's DevTools (the `browser` tool: Playwright/chrome-devtools-mcp read the page itself); use this for native apps and what DevTools cannot reach. While a person is controlling the screen your input by coordinates is refused: wait, or ask them in the chat. When you are stuck (a sign-in, a captcha, a permission), give the person the screen's link from the `screen` tool with chat_post kind=need_human.",
  inputSchema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ["screenshot", "tree", "click", "move", "drag", "scroll", "type", "set", "key", "wait"], description: "What to do (default screenshot)" },
      screen: { type: "string", description: "The screen's id from the `screen` tool: desktop, browser:<targetId>, simulator:<udid>" },
      x: { type: "number", description: "click, move, scroll: the point, in screenshot pixels from the left" },
      y: { type: "number", description: "click, move, scroll: the point, in screenshot pixels from the top" },
      button: { type: "string", enum: ["left", "right", "middle"], description: "click, drag: the mouse button (default left)" },
      double: { type: "boolean", description: "click: a double click" },
      from: { type: "array", items: { type: "number" }, minItems: 2, maxItems: 2, description: "drag: [x, y] where the button goes down" },
      to: { type: "array", items: { type: "number" }, minItems: 2, maxItems: 2, description: "drag: [x, y] where it is released" },
      dx: { type: "number", description: "scroll: pixels to the right (negative: left)" },
      dy: { type: "number", description: "scroll: pixels down (negative: up)" },
      text: { type: "string", description: "type: the text, as if typed (a newline presses Enter); set: the element's new value" },
      key: { type: "string", description: "key: a key or a combination, e.g. Enter, Escape, Tab, ArrowDown, PageDown, F5, a, ctrl+shift+t, cmd+c and cmd+Left on a Mac (on Windows cmd is the Windows key: ctrl+c there)" },
      mods: { type: "array", items: { type: "string", enum: ["cmd", "ctrl", "alt", "shift"] }, description: "key: modifiers held besides those in key" },
      ms: { type: "number", description: "wait: how long (ms, at most 30000) before the screenshot" },
      app: { type: "string", description: "tree: the app whose window to read (its name, e.g. Finder); key: send the keys to this app without focusing it" },
      window: { type: "string", description: "tree: one of the app's windows, by the id a tree answer names (when it has several)" },
      ref: { type: "string", description: "click, type, set, scroll: the element, by its ref in the latest tree (e12); tree: read only the part under it" },
      skeleton: { type: "boolean", description: "tree: only the window's outline (containers say how much is inside), for a big window" },
      tree: { type: "boolean", description: "After an action by ref: read the app's tree again (default true)" },
      wait: { type: "number", description: "After an action: ms before its screenshot (default 500), or before the tree is read again (by ref: default 200)" },
      screenshot: { type: "boolean", description: "After an action: return a screenshot (default true)" },
    },
    required: ["screen"],
    additionalProperties: false,
  },
};

/// Where the timers are (a test's own; the station's `wall` otherwise).
export type Timers = { later(ms: number, f: () => void): () => void };
const WALL: Timers = { later: (ms, f) => wall.after(ms, f) };

export type ComputerParts = {
  hub: ScreenHub;
  /// This station's place in its control plane's pages (`<cloud>/w/<workspace>/s/<station>`), none without pages.
  base: () => string | null;
  /// What a session's view is named among the screen's people: "agent: <its chat's title>".
  name: (session: string) => string;
  timers?: Timers;
};

type Point = { x: number; y: number };
type Size = { width: number; height: number };

/// A point of a screenshot `size` pixels large, as the contract's 0..1 (clamped to the frame).
export function toUnit(p: Point, size: Size): Point {
  const unit = (v: number, of: number) => (of > 0 ? Math.min(1, Math.max(0, v / of)) : 0);
  return { x: unit(p.x, size.width), y: unit(p.y, size.height) };
}

/// A key or a combination ("cmd+shift+t", "Enter", "ctrl+Left") as the contract's key events: the modifiers go down
/// in order, the key goes down and up, the modifiers come up in reverse (as a keyboard sends them).
export function keyPresses(combo: string, extra: string[] = []): Extract<ScreenInput, { t: "key" }>[] {
  const parts = combo.split("+").map((p) => p.trim());
  // "+" or "cmd++" (the plus key) leaves empty parts.
  if (combo === "+" || combo.endsWith("++")) parts.splice(parts.length - 2, 2, "+");
  const name = parts.pop() ?? "";
  if (name === "") throw new Error(`key: no key in ${JSON.stringify(combo)}`);
  const held: (keyof typeof MODS)[] = [];
  for (const m of [...extra, ...parts]) {
    const mod = MOD_NAMES[m.toLowerCase()];
    if (mod === undefined) throw new Error(`key: ${JSON.stringify(m)} is no modifier (cmd, ctrl, alt, shift)`);
    if (!held.includes(mod)) held.push(mod);
  }
  // A shifted character ("?", "+") is its key with shift.
  if (PUNCTUATION.some(([, shifted]) => shifted === name) && !held.includes("shift")) held.push("shift");
  const shift = held.includes("shift");
  const k = keyOf(name, shift);
  const out: Extract<ScreenInput, { t: "key" }>[] = [];
  let mods = 0;
  for (const m of held) {
    mods |= MODS[m];
    out.push({ t: "key", kind: "down", key: MOD_KEYS[m].key, code: MOD_KEYS[m].code, mods });
  }
  out.push({ t: "key", kind: "down", key: k.key, code: k.code, mods }, { t: "key", kind: "up", key: k.key, code: k.code, mods });
  for (const m of [...held].reverse()) {
    mods &= ~MODS[m];
    out.push({ t: "key", kind: "up", key: MOD_KEYS[m].key, code: MOD_KEYS[m].code, mods });
  }
  return out;
}

const MOD_NAMES: Record<string, keyof typeof MODS> = {
  cmd: "meta", command: "meta", meta: "meta", super: "meta", win: "meta", "⌘": "meta",
  ctrl: "ctrl", control: "ctrl", "⌃": "ctrl",
  alt: "alt", option: "alt", opt: "alt", "⌥": "alt",
  shift: "shift", "⇧": "shift",
};
const MOD_KEYS: Record<keyof typeof MODS, { key: string; code: string }> = {
  alt: { key: "Alt", code: "AltLeft" },
  ctrl: { key: "Control", code: "ControlLeft" },
  meta: { key: "Meta", code: "MetaLeft" },
  shift: { key: "Shift", code: "ShiftLeft" },
};
/// Keys by the names agents give them, as the DOM's `key` and `code`.
const NAMED: Record<string, { key: string; code: string }> = {
  enter: { key: "Enter", code: "Enter" }, return: { key: "Enter", code: "Enter" },
  tab: { key: "Tab", code: "Tab" },
  escape: { key: "Escape", code: "Escape" }, esc: { key: "Escape", code: "Escape" },
  backspace: { key: "Backspace", code: "Backspace" },
  delete: { key: "Delete", code: "Delete" }, del: { key: "Delete", code: "Delete" },
  space: { key: " ", code: "Space" },
  up: { key: "ArrowUp", code: "ArrowUp" }, arrowup: { key: "ArrowUp", code: "ArrowUp" },
  down: { key: "ArrowDown", code: "ArrowDown" }, arrowdown: { key: "ArrowDown", code: "ArrowDown" },
  left: { key: "ArrowLeft", code: "ArrowLeft" }, arrowleft: { key: "ArrowLeft", code: "ArrowLeft" },
  right: { key: "ArrowRight", code: "ArrowRight" }, arrowright: { key: "ArrowRight", code: "ArrowRight" },
  home: { key: "Home", code: "Home" }, end: { key: "End", code: "End" },
  pageup: { key: "PageUp", code: "PageUp" }, pagedown: { key: "PageDown", code: "PageDown" },
  insert: { key: "Insert", code: "Insert" },
};
/// The keys of a US keyboard's punctuation, by what they type (unshifted, shifted).
const PUNCTUATION: [string, string, string][] = [
  ["-", "_", "Minus"], ["=", "+", "Equal"], ["[", "{", "BracketLeft"], ["]", "}", "BracketRight"], ["\\", "|", "Backslash"],
  [";", ":", "Semicolon"], ["'", '"', "Quote"], [",", "<", "Comma"], [".", ">", "Period"], ["/", "?", "Slash"], ["`", "~", "Backquote"],
  ["1", "!", "Digit1"], ["2", "@", "Digit2"], ["3", "#", "Digit3"], ["4", "$", "Digit4"], ["5", "%", "Digit5"],
  ["6", "^", "Digit6"], ["7", "&", "Digit7"], ["8", "*", "Digit8"], ["9", "(", "Digit9"], ["0", ")", "Digit0"],
];

function keyOf(name: string, shift: boolean): { key: string; code: string } {
  const named = NAMED[name.toLowerCase()];
  if (named) return named;
  const f = /^f([1-9]|1[0-9]|20)$/i.exec(name);
  if (f) return { key: `F${f[1]}`, code: `F${f[1]}` };
  if (/^[a-z]$/i.test(name)) return { key: shift ? name.toUpperCase() : name.toLowerCase(), code: `Key${name.toUpperCase()}` };
  const p = PUNCTUATION.find(([plain, shifted]) => plain === name || shifted === name);
  if (p) return { key: shift ? p[1] : name, code: p[2] };
  if ([...name].length === 1) return { key: name, code: "" };
  throw new Error(`key: unknown key ${JSON.stringify(name)} (e.g. Enter, Tab, Escape, Backspace, Delete, Space, Up, Down, Left, Right, Home, End, PageUp, PageDown, F1-F20, a letter, a digit)`);
}

/// What typing `text` sends: the text, with Enter pressed for each newline.
export function typing(text: string): ScreenInput[] {
  const out: ScreenInput[] = [];
  text.replace(/\r\n?/g, "\n").split("\n").forEach((line, i) => {
    if (i > 0) out.push(...keyPresses("Enter"));
    // At most what a person's view may send at once.
    for (let at = 0; at < line.length; at += 1000) out.push({ t: "text", text: line.slice(at, at + 1000) });
  });
  return out;
}

const BUTTON_BITS = { left: 1, right: 2, middle: 4 } as const;

/// A click at `at` (0..1): there, the button down and up (twice for a double click).
export function clicking(at: Point, button: keyof typeof BUTTON_BITS, double: boolean): ScreenInput[] {
  const bit = BUTTON_BITS[button];
  const once: ScreenInput[] = [
    { t: "pointer", kind: "down", ...at, buttons: bit },
    { t: "pointer", kind: "up", ...at, buttons: 0 },
  ];
  return [{ t: "pointer", kind: "move", ...at, buttons: 0 }, ...once, ...(double ? once : [])];
}

/// A drag from `from` to `to` (0..1): the button down there, DRAG_STEPS moves with it held, released at `to`.
export function dragging(from: Point, to: Point, button: keyof typeof BUTTON_BITS): ScreenInput[] {
  const bit = BUTTON_BITS[button];
  const out: ScreenInput[] = [
    { t: "pointer", kind: "move", ...from, buttons: 0 },
    { t: "pointer", kind: "down", ...from, buttons: bit },
  ];
  for (let i = 1; i <= DRAG_STEPS; i++) {
    const f = i / DRAG_STEPS;
    out.push({ t: "pointer", kind: "move", x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f, buttons: bit });
  }
  out.push({ t: "pointer", kind: "up", ...to, buttons: 0 });
  return out;
}

/// A refusal the agent reads (a tool error).
class Refused extends Error {}

/// A session's view of one screen while it uses it: the frames drained as they come, the newest kept (a source sends a
/// new one only when the screen changed, so the newest is what it shows now).
class AgentView {
  readonly session: string;
  readonly id: string;
  readonly source: ScreenSource;
  readonly name: string;
  readonly #view: ScreenView;
  #latest: Frame | null = null;
  #size: Size | null = null;
  #codec: string | null = null;
  #waiters: ((ok: boolean) => void)[] = [];
  #ended = false;
  #idle: () => void = () => {};
  readonly #timers: Timers;
  readonly #gone: (v: AgentView) => void;

  constructor(o: { session: string; id: string; source: ScreenSource; name: string; view: ScreenView; timers: Timers; gone: (v: AgentView) => void }) {
    this.session = o.session;
    this.id = o.id;
    this.source = o.source;
    this.name = o.name;
    this.#view = o.view;
    this.#timers = o.timers;
    this.#gone = o.gone;
  }

  start() {
    this.touch();
    void this.#pump();
  }

  get ended() {
    return this.#ended;
  }

  /// Used now: it closes IDLE_MS from now, unless used again.
  touch() {
    this.#idle();
    this.#idle = this.#timers.later(IDLE_MS, () => this.close());
  }

  async #pump() {
    while (!this.#ended) {
      let frame: Frame | null;
      try {
        frame = await this.#view.next();
      } catch (error) {
        log.warn("computer", "a screen's frame was not had", { screen: this.id, error: (error as Error).message });
        frame = null;
      }
      if (this.#ended) return;
      if (frame === null) return this.close();
      if (frame.config) {
        this.#size = { width: frame.config.width, height: frame.config.height };
        this.#codec = frame.config.codec;
      }
      this.#latest = frame;
      for (const w of this.#waiters.splice(0)) w(true);
    }
  }

  /// The newest frame, waiting up to FIRST_MS for the first.
  async frame(): Promise<{ frame: Frame; size: Size; codec: string }> {
    if (this.#latest === null && !this.#ended) {
      await new Promise<boolean>((resolve) => {
        const stop = this.#timers.later(FIRST_MS, () => resolve(false));
        this.#waiters.push((ok) => (stop(), resolve(ok)));
      });
    }
    if (this.#ended) throw new Refused(`The screen ${this.id} went away (closed, or the station's browser stopped): call \`screen\` for those there are now.`);
    if (this.#latest === null || this.#size === null) throw new Refused(`The screen ${this.id} showed nothing within ${FIRST_MS / 1000} s; try again.`);
    return { frame: this.#latest, size: this.#size, codec: this.#codec ?? "" };
  }

  async input(events: ScreenInput[]) {
    for (const e of events) await this.#view.input(e);
  }

  close() {
    if (this.#ended) return;
    this.#ended = true;
    this.#idle();
    this.#view.close();
    for (const w of this.#waiters.splice(0)) w(false);
    this.#gone(this);
  }
}

const num = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const str = (v: unknown): string => (typeof v === "string" ? v.trim() : "");

/// The tree a session read last on a screen: its refs are that snapshot's, and an action by ref reads it again so.
type Tree = { snapshot: string; app: string; window: string };

/// agent-desktop's envelope (screens/ui.ts): its data, or what it said went wrong as the agent reads it.
function answered(envelope: any, what: string): any {
  if (envelope?.ok === true) return envelope.data ?? {};
  const e = envelope?.error ?? {};
  const lines = [`${what}: ${e.code ?? "ERROR"}: ${e.message ?? "agent-desktop failed"}`];
  if (typeof e.suggestion === "string" && e.suggestion) lines.push(e.suggestion);
  // The windows to choose from, when the app has several.
  if (e.details !== undefined) lines.push(`Details: ${JSON.stringify(e.details)}`);
  const retry = e.disposition?.retry;
  if (retry === "safe") lines.push("It was not done; it is safe to try again.");
  else if (retry === "unsafe") lines.push("It may have been done: read the tree before doing it again.");
  throw new Refused(lines.join("\n"));
}

/// The agents' hands on the station's screens: their views, by session and screen.
export class Computer {
  readonly #p: ComputerParts;
  readonly #timers: Timers;
  readonly #views = new Map<string, AgentView>();
  /// Views being opened, so two calls at once open one.
  readonly #opening = new Map<string, Promise<AgentView>>();
  /// Each session's latest tree on a screen, by `session\nscreen`.
  readonly #trees = new Map<string, Tree>();

  constructor(parts: ComputerParts) {
    this.#p = parts;
    this.#timers = parts.timers ?? WALL;
    parts.hub.whenStopping(() => this.closeAll());
  }

  /// The views open now, as `session screen` (for tests and the log).
  open(): string[] {
    return [...this.#views.values()].map((v) => `${v.session} ${v.id}`);
  }

  /// A session ended: its views close.
  closeSession(session: string) {
    for (const v of [...this.#views.values()]) if (v.session === session) v.close();
    for (const key of [...this.#trees.keys()]) if (key.startsWith(`${session}\n`)) this.#trees.delete(key);
  }

  closeAll() {
    for (const v of [...this.#views.values()]) v.close();
  }

  /// The link a person opens the screen with, and what to do with it.
  #handOver(id: string): string {
    const base = this.#p.base();
    if (base === null) return "A person can open this screen from the still.fail app (this station's control plane has no pages to link to); ask in the chat with chat_post kind=need_human.";
    return `A person can do it on this screen from their still.fail app: ${base}/screen/${encodeURIComponent(id)} — post that link on a line of its own (it shows as the screen's card) with chat_post kind=need_human, saying what to do there, and end your turn.`;
  }

  /// The people driving `id` now, other than the agents' own views.
  #persons(id: string): string[] {
    const others = [...this.#p.hub.people(id).controlledBy];
    for (const v of this.#views.values()) {
      if (v.id !== id) continue;
      const i = others.indexOf(v.name);
      if (i >= 0) others.splice(i, 1);
    }
    return others;
  }

  async #view(session: string, source: ScreenSource): Promise<AgentView> {
    const key = `${session}\n${source.id}`;
    const have = this.#views.get(key);
    if (have && !have.ended && have.source === source) return have;
    have?.close();
    const opening = this.#opening.get(key);
    if (opening) return opening;
    const made = this.#openView(session, source, key).finally(() => this.#opening.delete(key));
    this.#opening.set(key, made);
    return made;
  }

  async #openView(session: string, source: ScreenSource, key: string): Promise<AgentView> {
    let view: ScreenView;
    try {
      // Among the screen's people while it is open (closing it leaves).
      view = await this.#p.hub.openAs(source.id, { maxWidth: SHOT_MAX, maxHeight: SHOT_MAX, codecs: ["jpeg"] }, { name: this.#p.name(session), control: true });
    } catch (error) {
      if (error instanceof ScreenRefused) {
        if (error.status === 415 || error.status === 400) throw new Refused(`The screen ${source.id} does not send pictures an agent can take on this station (it sends no JPEG): update the station.`);
        const access = accessShown(error.access, "en");
        throw new Refused(`${access?.message || tr("en", error.key, error.args)}\n${this.#handOver(source.id)}`);
      }
      throw new Refused(`The screen ${source.id} could not be opened: ${(error as Error).message}`);
    }
    // Gone while it opened.
    if (this.#p.hub.get(source.id) !== source) {
      view.close();
      throw new Refused(`The screen ${source.id} went away: call \`screen\` for those there are now.`);
    }
    const v = new AgentView({
      session, id: source.id, source, view, name: this.#p.name(session), timers: this.#timers,
      gone: (gone) => {
        if (this.#views.get(key) === gone) this.#views.delete(key);
      },
    });
    this.#views.set(key, v);
    v.start();
    return v;
  }

  /// One call of the tool: what it did, and the screenshot after it.
  async act(session: string, args: Record<string, unknown>): Promise<ToolReply> {
    const action = typeof args.action === "string" && args.action !== "" ? args.action : "screenshot";
    if (!(COMPUTER.inputSchema.properties.action.enum as string[]).includes(action)) throw new Refused(`unknown action ${action}: ${COMPUTER.inputSchema.properties.action.enum.join(", ")}`);
    const id = typeof args.screen === "string" ? args.screen.trim() : "";
    const hub = this.#p.hub;
    const there = () => hub.list().map((s) => s.id).join(", ") || "none";
    if (id === "") throw new Refused(`screen is required: the id of one of this station's screens (${there()}); the \`screen\` tool lists them.`);
    const source = hub.get(id);
    if (source === undefined) throw new Refused(`no screen ${id} on this station (it has: ${there()})`);
    if (action === "tree" || action === "set" || str(args.ref) !== "" || (action === "key" && str(args.app) !== "")) return this.#byTree(session, source, action, args);
    const acting = action !== "screenshot" && action !== "wait";

    // What the input will be, checked before anything is opened or sent.
    const plan = acting ? this.#plan(action, args) : null;
    if (acting) {
      const persons = this.#persons(id);
      if (persons.length > 0)
        throw new Refused(`${persons.join(", ")} ${persons.length > 1 ? "are" : "is"} controlling ${id} right now, so your input was not sent: do not fight them. Wait and take a screenshot later (\`screen\` shows who is on it), or ask them in the chat to leave it to you.`);
    }
    if (source.access) {
      await hub.refresh();
      const access = source.access();
      if (acting && access.capture && !access.control) {
        throw new Refused(`${accessShown(access, "en")?.message ?? ""}\nYour input was not sent.\n${this.#handOver(id)}`);
      }
    }

    const view = await this.#view(session, source);
    view.touch();
    let did = "";
    if (plan !== null) {
      const { size } = await view.frame();
      const events = plan.events(size);
      await view.input(events);
      did = plan.said;
    } else if (action === "wait") {
      const ms = num(args.ms) ? Math.min(WAIT_MAX, Math.max(0, args.ms)) : 1000;
      await this.#sleep(ms);
      did = `Waited ${Math.round(ms)} ms.`;
    }
    view.touch();
    const shoot = action === "screenshot" || action === "wait" || args.screenshot !== false;
    if (!shoot) return { content: [{ type: "text", text: did || "Done." }] };
    if (acting) await this.#sleep(num(args.wait) ? Math.min(WAIT_MAX, Math.max(0, args.wait)) : SETTLE_MS);
    const { frame, size, codec } = await view.frame();
    view.touch();
    if (codec !== "jpeg") throw new Refused(`The screen ${id} sent ${codec || "no"} pictures, not JPEG: an agent cannot take them on this station yet (update the station).`);
    const content: Content[] = [{ type: "text", text: [did, this.#described(source, size, view)].filter(Boolean).join("\n") }];
    content.push({ type: "image", data: Buffer.from(frame.data).toString("base64"), mimeType: "image/jpeg" });
    return { content };
  }

  /// An app's tree (`tree`), or an action on one of its elements by ref, answered with its tree again.
  async #byTree(session: string, source: ScreenSource, action: string, args: Record<string, unknown>): Promise<ToolReply> {
    const id = source.id;
    if (source.ui === undefined) throw new Refused(`The screen ${id} has no accessibility trees: use screenshots and coordinates there (trees are the desktop's).`);
    if (source.access) {
      await this.#p.hub.refresh();
      const access = source.access();
      if (!access.control) throw new Refused(`${accessShown(access, "en")?.message ?? `The screen ${id} cannot be driven now.`}\n${this.#handOver(id)}`);
    }
    const ui = (cmd: string[]) => source.ui!(cmd).catch((error) => {
      if (error instanceof Refused) throw error;
      throw new Refused(`The screen ${id}'s apps could not be read: ${error instanceof ScreenRefused ? (accessShown(error.access, "en")?.message ?? error.message) : (error as Error).message}`);
    });
    const key = `${session}\n${id}`;
    const latest = this.#trees.get(key);
    const ref = str(args.ref);
    /// A ref as agent-desktop takes it: its snapshot's (`@s1:e12`), the latest tree's for a bare one.
    const qualified = () => {
      if (ref.startsWith("@")) return ref;
      if (!/^e\d+$/.test(ref)) throw new Refused(`${action}: ref is an element's ref from the latest tree, e.g. e12`);
      if (latest === undefined) throw new Refused(`${action}: no tree read yet on ${id}: call action=tree with app first`);
      return `@${latest.snapshot}:${ref}`;
    };

    if (action === "tree") {
      const app = str(args.app);
      const window = str(args.window);
      if (app === "" && ref === "") return { content: [{ type: "text", text: this.#apps(answered(await ui(["list-apps"]), "apps")) }] };
      const at: Tree = ref === "" ? { snapshot: "", app, window } : { ...(latest ?? { snapshot: "", app, window }), ...(app ? { app } : {}) };
      return { content: [{ type: "text", text: await this.#read(key, at, ui, { root: ref === "" ? null : qualified(), skeleton: args.skeleton === true }) }] };
    }

    let cmd: string[];
    let said: string;
    switch (action) {
      case "click": {
        const b = args.button === undefined ? "left" : args.button;
        if (b !== "left" && b !== "right") throw new Refused("click: by ref, button is left or right");
        const verb = b === "right" ? "right-click" : args.double === true ? "double-click" : "click";
        cmd = [verb, qualified()];
        said = `${b === "right" ? "Right-clicked" : args.double === true ? "Double-clicked" : "Clicked"} ${ref}.`;
        break;
      }
      case "type":
      case "set": {
        if (typeof args.text !== "string" || (action === "type" && args.text === "")) throw new Refused(`${action}: text is required`);
        cmd = action === "type" ? ["type", qualified(), args.text] : ["set-value", qualified(), args.text];
        const shown = JSON.stringify(args.text.length > 80 ? `${args.text.slice(0, 80)}…` : args.text);
        said = action === "type" ? `Typed ${shown} into ${ref}.` : `Set ${ref} to ${shown}.`;
        break;
      }
      case "scroll": {
        const dx = num(args.dx) ? args.dx : 0;
        const dy = num(args.dy) ? args.dy : 0;
        if (dx === 0 && dy === 0) throw new Refused("scroll: give dx and/or dy (pixels; dy > 0 scrolls down)");
        const vertical = Math.abs(dy) >= Math.abs(dx);
        const along = vertical ? dy : dx;
        const direction = vertical ? (dy > 0 ? "down" : "up") : dx > 0 ? "right" : "left";
        const amount = Math.max(1, Math.min(50, Math.round(Math.abs(along) / SCROLL_UNIT_PX)));
        cmd = ["scroll", qualified(), "--direction", direction, "--amount", String(amount)];
        said = `Scrolled ${ref} ${direction} by ${amount}.`;
        break;
      }
      case "key": {
        const combo = str(args.key);
        if (combo === "") throw new Refused("key: key is required (e.g. Enter, cmd+c)");
        const mods = Array.isArray(args.mods) ? args.mods.filter((m): m is string => typeof m === "string") : [];
        cmd = ["press", [...mods, combo].join("+"), "--app", str(args.app)];
        said = `Pressed ${[...mods, combo].join("+")} in ${str(args.app)}.`;
        break;
      }
      default:
        throw new Refused(`${action}: not by ref (by ref: click, type, set, scroll; key with app)`);
    }
    answered(await ui(cmd), action);
    // The app read again: its own tree, or the one named (key's).
    const again: Tree | undefined = action === "key" ? (latest?.app === str(args.app) ? latest : { snapshot: "", app: str(args.app), window: "" }) : latest;
    if (again === undefined || args.tree === false) return { content: [{ type: "text", text: said }] };
    await this.#sleep(num(args.wait) ? Math.min(WAIT_MAX, Math.max(0, args.wait)) : TREE_SETTLE_MS);
    return { content: [{ type: "text", text: `${said}\n${await this.#read(key, again, ui, { root: null, skeleton: false })}` }] };
  }

  /// An app's window read (or the part under `root`), kept as the session's latest tree: what an agent reads.
  async #read(key: string, at: Tree, ui: (cmd: string[]) => Promise<unknown>, o: { root: string | null; skeleton: boolean }): Promise<string> {
    const cmd = ["snapshot", "--compact"];
    if (at.app) cmd.push("--app", at.app);
    if (at.window) cmd.push("--window-id", at.window);
    if (o.root !== null) cmd.push("--root", o.root);
    if (o.skeleton) cmd.push("--skeleton");
    const data = answered(await ui(cmd), "tree");
    const snapshot = String(data.snapshot_id ?? "");
    const window = data.window ?? {};
    this.#trees.set(key, { snapshot, app: String(data.app ?? at.app), window: String(window.id ?? at.window) });
    const head = `${data.app ?? at.app} window ${window.id ?? "?"} ${JSON.stringify(window.title ?? "")}${o.root ? `, under ${o.root.slice(o.root.lastIndexOf(":") + 1)}` : ""}${data.complete === false ? " (not all of it: read a part with ref)" : ""}. Act on an element by its ref (ref: "e12").`;
    return `${head}\n${treeText(data.tree ?? {})}`;
  }

  /// The apps running that people use (in the Dock, on the taskbar): those agent-desktop says are in the foreground,
  /// else all but the background ones.
  #apps(data: any): string {
    const apps: { name?: string; presentation?: string }[] = (Array.isArray(data?.apps) ? data.apps : []).filter((a: any) => typeof a?.name === "string" && a.name);
    const foreground = apps.filter((a) => a.presentation === "foreground");
    const shown = [...new Set((foreground.length > 0 ? foreground : apps.filter((a) => a.presentation !== "background")).map((a) => a.name!))];
    return `Apps running (give one as app with action=tree): ${shown.join(", ") || "none"}`;
  }

  #sleep(ms: number): Promise<void> {
    return ms <= 0 ? Promise.resolve() : new Promise((resolve) => void this.#timers.later(ms, resolve));
  }

  /// What a screenshot is: its screen, its size and how its pixels map to the screen's, and who else is on it.
  #described(source: ScreenSource, size: Size, view: AgentView): string {
    const real = source.size();
    const scale = real.width > 0 && size.width > 0 ? real.width / size.width : 1;
    // By the widths: a source's listed height may be its window's (a tab's, before its first frame says otherwise).
    const scaled = Number(scale.toFixed(3));
    const lines = [
      `${source.id} ${JSON.stringify(source.title())}: screenshot ${size.width}×${size.height} px (scale ${scaled}: 1 screenshot px = ${scaled} screen px). Give x/y in this screenshot's pixels.`,
    ];
    const people = this.#p.hub.people(source.id).viewers.filter((n) => n !== view.name);
    if (people.length > 0) lines.push(`Also on this screen: ${people.join(", ")}.`);
    return lines.join("\n");
  }

  /// An input action's events, given the screenshot's size (its pixels → 0..1), and what it says it did.
  #plan(action: string, args: Record<string, unknown>): { events: (size: Size) => ScreenInput[]; said: string } {
    const point = (x: unknown, y: unknown, what: string): Point => {
      if (!num(x) || !num(y)) throw new Refused(`${action}: ${what} needs numbers x and y (pixels of the latest screenshot)`);
      return { x, y };
    };
    const inside = (p: Point, size: Size) => {
      if (p.x < 0 || p.y < 0 || p.x > size.width || p.y > size.height)
        throw new Refused(`${action}: (${p.x}, ${p.y}) is outside the screenshot (${size.width}×${size.height}); take a screenshot and give a point on it`);
      return toUnit(p, size);
    };
    const button = (): keyof typeof BUTTON_BITS => {
      const b = args.button === undefined ? "left" : args.button;
      if (b !== "left" && b !== "right" && b !== "middle") throw new Refused(`${action}: button is left, right or middle`);
      return b;
    };
    switch (action) {
      case "click": {
        const p = point(args.x, args.y, "the point");
        const b = button();
        const double = args.double === true;
        return { events: (size) => clicking(inside(p, size), b, double), said: `${double ? "Double-clicked" : "Clicked"}${b === "left" ? "" : ` (${b})`} at (${p.x}, ${p.y}).` };
      }
      case "move": {
        const p = point(args.x, args.y, "the point");
        return { events: (size) => [{ t: "pointer", kind: "move", ...inside(p, size), buttons: 0 }], said: `Moved the pointer to (${p.x}, ${p.y}).` };
      }
      case "drag": {
        const pair = (v: unknown, what: string) => (Array.isArray(v) ? point(v[0], v[1], what) : point(undefined, undefined, what));
        const from = pair(args.from, "from: [x, y]");
        const to = pair(args.to, "to: [x, y]");
        const b = button();
        return { events: (size) => dragging(inside(from, size), inside(to, size), b), said: `Dragged from (${from.x}, ${from.y}) to (${to.x}, ${to.y}).` };
      }
      case "scroll": {
        const p = point(args.x, args.y, "the point");
        const dx = num(args.dx) ? args.dx : 0;
        const dy = num(args.dy) ? args.dy : 0;
        if (dx === 0 && dy === 0) throw new Refused("scroll: give dx and/or dy (pixels; dy > 0 scrolls down)");
        const clamp = (v: number) => Math.max(-10_000, Math.min(10_000, v));
        return {
          events: (size) => {
            const at = inside(p, size);
            return [{ t: "pointer", kind: "move", ...at, buttons: 0 }, { t: "wheel", ...at, dx: clamp(dx), dy: clamp(dy) }];
          },
          said: `Scrolled by (${dx}, ${dy}) at (${p.x}, ${p.y}).`,
        };
      }
      case "type": {
        if (typeof args.text !== "string" || args.text === "") throw new Refused("type: text is required");
        const events = typing(args.text);
        return { events: () => events, said: `Typed ${JSON.stringify(args.text.length > 80 ? `${args.text.slice(0, 80)}…` : args.text)}.` };
      }
      case "key": {
        if (typeof args.key !== "string" || args.key.trim() === "") throw new Refused("key: key is required (e.g. Enter, cmd+c)");
        const mods = Array.isArray(args.mods) ? args.mods.filter((m): m is string => typeof m === "string") : [];
        let events: ScreenInput[];
        try {
          events = keyPresses(args.key.trim(), mods);
        } catch (error) {
          throw new Refused((error as Error).message);
        }
        return { events: () => events, said: `Pressed ${[...mods, args.key.trim()].join("+")}.` };
      }
      default:
        throw new Refused(`unknown action ${action}`);
    }
  }
}

/// The tool. `run` gives the text alone (for a caller without images); the endpoint calls `content`.
export function computerTools(computer: Computer): Tool[] {
  return [
    {
      ...COMPUTER,
      content: (session, args) => computer.act(session, args),
      run: async (session, args) =>
        (await computer.act(session, args)).content.map((c) => (c.type === "text" ? c.text : `[${c.mimeType} screenshot]`)).join("\n"),
    },
  ];
}
