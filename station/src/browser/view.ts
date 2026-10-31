// A person's view of a tab of the station's browser (docs/remote-screens.md): CDP's screencast for the frames (JPEG),
// Input.dispatch* for what they do, on a connection and a session of the view's own, so the agents' own sessions on
// the tab are left as they are.
//
// While a person drives it, its clipboard's text goes both ways: what the page copies (a copy or cut, as the page put it
// on the clipboard or as it was selected; what it writes with navigator.clipboard.writeText) is heard through a binding
// the view's session adds while it is watched (Chrome stops telling of it as the watch ends; a page open then keeps the
// function until it loads again, a page loaded after has none), and a paste is the text inserted where the focus is.
//
// Pull-driven: Chrome casts a frame only once those before it are acknowledged (it keeps at most two out), and a frame
// is acknowledged only when the one after it is asked for (`next`), so a slow viewer slows the casting rather than
// having frames pile up. Of two waiting, the newer is given and the older let go.
import { type Clip, type Frame, type FrameConfig, type LoginField, type LoginFill, type PasskeyAnswer, type PasskeyAsk, type ScreenInput, type ScreenVideo, type ScreenView, type ViewOptions, CLIP_TEXT_MAX } from "../screens/source.ts";
import type { Cdp, CdpEvent } from "./cdp.ts";

/// The page's viewport in CSS pixels, as Page.getLayoutMetrics says it (what the screencast's frames show); null when
/// it says none.
export function viewportOf(m: any): { width: number; height: number } | null {
  const v = m?.cssVisualViewport ?? m?.cssLayoutViewport ?? m?.layoutViewport;
  const width = Math.round(Number(v?.clientWidth)), height = Math.round(Number(v?.clientHeight));
  return width > 0 && height > 0 ? { width, height } : null;
}

/// JPEG quality of the cast frames.
const QUALITY = 70;
/// The most pixels a CSS pixel is drawn with for a phone it is laid out for (`fit`): sharp on any phone, and frames a
/// third the size of a 3× phone's own.
const FIT_SCALE_MOST = 2;
/// At most this many frames are held unacknowledged (as Chrome sends at most).
const HELD = 2;
/// A press this soon after the last, this near it and of the same button, adds to its click count (a double click).
const CLICK_MS = 500;
const CLICK_PX = 4;

/// A JPEG's size, from its frame header (SOFn); null when there is none.
export function jpegSize(data: Uint8Array): { width: number; height: number } | null {
  if (data.length < 4 || data[0] !== 0xff || data[1] !== 0xd8) return null;
  let i = 2;
  while (i + 3 < data.length) {
    if (data[i] !== 0xff) return null;
    const marker = data[i + 1]!;
    // Fill bytes before a marker, and the markers that carry no length.
    if (marker === 0xff) {
      i++;
      continue;
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd9)) {
      i += 2;
      continue;
    }
    const length = (data[i + 2]! << 8) | data[i + 3]!;
    const sof = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (sof) {
      if (i + 8 >= data.length) return null;
      return { height: (data[i + 5]! << 8) | data[i + 6]!, width: (data[i + 7]! << 8) | data[i + 8]! };
    }
    i += 2 + length;
  }
  return null;
}

/// A point given as 0..1 of the frame, in the page's CSS pixels (what Input.dispatchMouseEvent takes).
export function toViewport(x: number, y: number, viewport: { width: number; height: number }): { x: number; y: number } {
  const clamp = (v: number) => (Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0);
  return { x: clamp(x) * viewport.width, y: clamp(y) * viewport.height };
}

/// The mouse buttons as PointerEvent.buttons has them, by CDP's names.
const BUTTONS: [number, string][] = [
  [1, "left"],
  [2, "right"],
  [4, "middle"],
  [8, "back"],
  [16, "forward"],
];
const buttonOf = (bits: number): string => BUTTONS.find(([bit]) => (bits & bit) !== 0)?.[1] ?? "none";

/// Windows' virtual key codes of the keys that are no character (Chrome acts on them by these), and of the
/// punctuation keys by their code.
const NAMED_KEYS: Record<string, number> = {
  Backspace: 8, Tab: 9, Enter: 13, Shift: 16, Control: 17, Alt: 18, Pause: 19, CapsLock: 20, Escape: 27, " ": 32,
  PageUp: 33, PageDown: 34, End: 35, Home: 36, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, Insert: 45,
  Delete: 46, Meta: 91, ContextMenu: 93,
};
const CODES: Record<string, number> = {
  Space: 32, Semicolon: 186, Equal: 187, Comma: 188, Minus: 189, Period: 190, Slash: 191, Backquote: 192,
  BracketLeft: 219, Backslash: 220, BracketRight: 221, Quote: 222,
};

export function keyCode(key: string, code: string): number {
  const named = NAMED_KEYS[key];
  if (named !== undefined) return named;
  const f = /^F([1-9]|1[0-9]|2[0-4])$/.exec(key);
  if (f) return 111 + Number(f[1]);
  if (/^Key[A-Z]$/.test(code)) return code.charCodeAt(3);
  if (/^Digit[0-9]$/.test(code)) return code.charCodeAt(5);
  if (/^Numpad[0-9]$/.test(code)) return 96 + Number(code.slice(6));
  if (CODES[code] !== undefined) return CODES[code]!;
  if (/^[a-z]$/i.test(key)) return key.toUpperCase().charCodeAt(0);
  if (/^[0-9]$/.test(key)) return key.charCodeAt(0);
  return 0;
}

const ALT = 1;
const CTRL = 2;
const META = 4;
const SHIFT = 8;

/// Editing shortcuts as macOS's Chrome takes them from CDP (as commands; elsewhere the key with its modifiers does).
const COMMANDS: Record<string, string> = { a: "selectAll", c: "copy", x: "cut", v: "paste", z: "undo" };

/// A key press or release as Input.dispatchKeyEvent takes it.
export function keyEvent(e: Extract<ScreenInput, { t: "key" }>): Record<string, unknown> {
  const modifiers = e.mods & (ALT | CTRL | META | SHIFT);
  const base = { key: e.key, code: e.code, modifiers, windowsVirtualKeyCode: keyCode(e.key, e.code), nativeVirtualKeyCode: keyCode(e.key, e.code) };
  if (e.kind === "up") return { type: "keyUp", ...base };
  const shortcut = (modifiers & (CTRL | META)) !== 0;
  // What a key types: its character, or Enter's; not with a shortcut's modifier held.
  const text = e.key === "Enter" ? "\r" : [...e.key].length === 1 && !shortcut ? e.key : undefined;
  if (text !== undefined) return { type: "keyDown", ...base, text, unmodifiedText: text };
  const command = shortcut ? COMMANDS[e.key.toLowerCase()] : undefined;
  const commands = command === undefined ? undefined : command === "undo" && (modifiers & SHIFT) !== 0 ? ["redo"] : [command];
  return { type: "rawKeyDown", ...base, ...(commands ? { commands } : {}) };
}

/// The binding a tab's copies call while a person driving it watches its clipboard.
export const COPY_BINDING = "__stillfailCopied";
/// What hears a page's copies, run in it (and in each document it opens while watched): a copy's or a cut's text, as
/// the page set it (read as the event reaches the window) or as it was selected (a field's selection, else the
/// page's), and what it writes with navigator.clipboard.writeText. Once a page; it says nothing once the binding went.
export const COPY_HOOK = `(() => {
  if (window.__stillfailCopyHook) return;
  window.__stillfailCopyHook = true;
  const say = (text) => { try { if (typeof text === "string" && text !== "" && typeof window.${COPY_BINDING} === "function") window.${COPY_BINDING}(text.slice(0, ${CLIP_TEXT_MAX / 4})); } catch {} };
  const selected = () => {
    const el = document.activeElement;
    if (el && (el.tagName === "TEXTAREA" || (el.tagName === "INPUT" && /^(text|search|url|tel|email|number)$/i.test(el.type || "text")))) {
      try { if (el.selectionStart !== el.selectionEnd) return el.value.slice(el.selectionStart, el.selectionEnd); } catch {}
      return "";
    }
    return String(window.getSelection() || "");
  };
  // What was selected, said once the copy's dispatch is over (a message to itself: a task after it) unless the page
  // set its own by then.
  let pending = null;
  const after = new MessageChannel();
  after.port1.onmessage = () => { if (pending) say(pending); pending = null; };
  const started = () => {
    pending = selected();
    after.port2.postMessage(0);
  };
  const reached = (e) => {
    let set = "";
    try { set = e.clipboardData ? e.clipboardData.getData("text/plain") : ""; } catch {}
    if (set) { pending = null; say(set); }
  };
  for (const type of ["copy", "cut"]) { window.addEventListener(type, started, true); window.addEventListener(type, reached); }
  const board = navigator.clipboard;
  if (board && typeof board.writeText === "function") {
    const write = board.writeText.bind(board);
    board.writeText = (text) => { say(String(text)); return write(text); };
  }
})()`;

/// The binding a tab's login fields call while a person driving it is offered to fill them.
export const LOGIN_BINDING = "__stillfailLogin";
/// What tells of the login field in focus, run in a page's top document (and each one it opens while watched): a
/// password field, or one an account goes in (marked so, or a text field of a form with a password field, or named
/// so), said as `{"field": …}` as the focus comes to one and `null` as it leaves; only when it changed. What it says is
/// only a hint: the site is the station's to say (the tab's address), and the page may call the binding as it likes.
export const LOGIN_HOOK = `(() => {
  if (window !== window.top || window.__stillfailLoginHook) return;
  window.__stillfailLoginHook = true;
  const kind = (el) => {
    if (!el || el.tagName !== "INPUT" || el.disabled || el.readOnly) return null;
    const type = (el.type || "text").toLowerCase();
    const auto = (el.autocomplete || "").toLowerCase();
    if (type === "password") return "password";
    if (!/^(text|email|tel)$/.test(type)) return null;
    if (/username|email|webauthn/.test(auto)) return "username";
    if (el.form && el.form.querySelector("input[type=password]")) return "username";
    return /user|email|login|account|identifier/i.test((el.name || "") + " " + (el.id || "")) ? "username" : null;
  };
  const focused = (e) => (e && e.composedPath ? e.composedPath()[0] : document.activeElement);
  let said = "";
  const say = (field) => {
    const now = field ? JSON.stringify({ field }) : "null";
    if (now === said) return;
    said = now;
    try { if (typeof window.${LOGIN_BINDING} === "function") window.${LOGIN_BINDING}(now); } catch {}
  };
  document.addEventListener("focusin", (e) => say(kind(focused(e))), true);
  // (where the focus goes: none, or one a focusin then says itself)
  document.addEventListener("focusout", (e) => say(kind(e.relatedTarget)), true);
  say(kind(document.activeElement));
})()`;

/// Fills the login form the focus is in (or the page's first, where the focus is in none): its account field and its
/// password field, as typing would leave them (the value set as the field's own setter does, then input and change
/// told), the first of them focused. Run in a world of its own, so the page's scripts do not change how it goes. What
/// was filled.
export const fillScript = (username: string | undefined, password: string | undefined) => `((username, password) => {
  const visible = (el) => !!el && !el.disabled && !el.readOnly && el.getClientRects().length > 0;
  const deep = (root) => { let el = root.activeElement; while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement; return el; };
  const active = deep(document);
  const scope = (active && active.form) || (active && active.getRootNode && active.getRootNode()) || document;
  const all = [...scope.querySelectorAll("input")].filter(visible);
  const pass = all.find((el) => (el.type || "").toLowerCase() === "password");
  const account = all.find((el) => el !== pass && /^(text|email|tel)$/.test((el.type || "text").toLowerCase())
    && (/username|email|webauthn/.test((el.autocomplete || "").toLowerCase()) || /user|email|login|account|identifier/i.test((el.name || "") + " " + (el.id || "")) || (pass && el.compareDocumentPosition(pass) & Node.DOCUMENT_POSITION_FOLLOWING)));
  const set = (el, value) => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, value);
    el.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  };
  const did = { username: false, password: false };
  if (typeof username === "string" && account) { set(account, username); did.username = true; }
  if (typeof password === "string" && pass) { set(pass, password); did.password = true; }
  const first = did.username ? account : did.password ? pass : null;
  if (first) first.focus();
  return did;
})(${JSON.stringify(username ?? null)}, ${JSON.stringify(password ?? null)})`;

/// The binding a tab's passkey sign-ins call while a person driving it signs them from their own device.
export const PASSKEY_BINDING = "__stillfailPasskey";
/// What takes a page's passkey sign-in (navigator.credentials.get with `publicKey`) to the person driving it, run in a
/// page's top document before its own scripts (and each one it opens while watched): the ask said through the binding
/// as `{"id", "rpId", "challenge", "allow", "userVerification"}` (base64url), `{"id", "gone": true}` as the page gives it
/// up (its signal), and answered by the station with `__stillfailPasskeyDone(id, answer)`: a credential made as the
/// browser makes it, or the error the browser would give. The platform is said to have an authenticator, so that sites
/// offer passkeys. Anything else (a password asked, a passkey made) goes to the browser as before.
export const PASSKEY_HOOK = `(() => {
  if (window !== window.top || window.__stillfailPasskeyHook || !navigator.credentials) return;
  window.__stillfailPasskeyHook = true;
  const creds = navigator.credentials;
  const get = creds.get.bind(creds);
  const bytes = (v) => v instanceof ArrayBuffer ? new Uint8Array(v) : ArrayBuffer.isView(v) ? new Uint8Array(v.buffer, v.byteOffset, v.byteLength) : null;
  const b64 = (v) => { const u = bytes(v); if (!u) return null; let s = ""; for (const b of u) s += String.fromCharCode(b); return btoa(s).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, ""); };
  const buf = (s) => { const t = atob(s.replace(/-/g, "+").replace(/_/g, "/")); const u = new Uint8Array(t.length); for (let i = 0; i < t.length; i++) u[i] = t.charCodeAt(i); return u.buffer; };
  const waiting = new Map();
  let next = 0;
  const said = (v) => { try { window.${PASSKEY_BINDING}(JSON.stringify(v)); return true; } catch { return false; } };
  Object.defineProperty(window, "__stillfailPasskeyDone", { value: (id, a) => {
    const w = waiting.get(id);
    if (!w) return;
    waiting.delete(id);
    if (a.error) return w.no(new DOMException(a.error === "NotAllowedError" ? "The operation either timed out or was not allowed." : String(a.error), a.error === "NotAllowedError" ? "NotAllowedError" : "UnknownError"));
    const response = { clientDataJSON: buf(a.clientData), authenticatorData: buf(a.authenticatorData), signature: buf(a.signature), userHandle: a.userHandle ? buf(a.userHandle) : null };
    const credential = { id: a.credential, rawId: buf(a.credential), type: "public-key", authenticatorAttachment: "platform", response,
      getClientExtensionResults: () => ({}),
      toJSON: () => ({ id: a.credential, rawId: a.credential, type: "public-key", authenticatorAttachment: "platform", clientExtensionResults: {},
        response: { clientDataJSON: b64(response.clientDataJSON), authenticatorData: a.authenticatorData, signature: a.signature, userHandle: a.userHandle || null } }) };
    try { Object.setPrototypeOf(response, AuthenticatorAssertionResponse.prototype); Object.setPrototypeOf(credential, PublicKeyCredential.prototype); } catch {}
    w.yes(credential);
  } });
  creds.get = function (options) {
    const pk = options && options.publicKey;
    if (!pk || !bytes(pk.challenge)) return get(options);
    const id = String(++next);
    const allow = Array.isArray(pk.allowCredentials) ? pk.allowCredentials.map((c) => b64(c && c.id)).filter((x) => x) : [];
    const ask = { id, rpId: typeof pk.rpId === "string" && pk.rpId !== "" ? pk.rpId : location.hostname, challenge: b64(pk.challenge), allow, userVerification: pk.userVerification || "preferred" };
    return new Promise((yes, no) => {
      const signal = options.signal;
      if (signal && signal.aborted) return no(signal.reason !== undefined ? signal.reason : new DOMException("The operation was aborted.", "AbortError"));
      waiting.set(id, { yes, no });
      if (signal) signal.addEventListener("abort", () => {
        if (!waiting.delete(id)) return;
        said({ id, gone: true });
        no(signal.reason !== undefined ? signal.reason : new DOMException("The operation was aborted.", "AbortError"));
      });
      if (!said(ask)) { waiting.delete(id); get(options).then(yes, no); }
    });
  };
  // (a page left takes what it asked with it)
  window.addEventListener("pagehide", () => { for (const id of waiting.keys()) said({ id, gone: true }); waiting.clear(); });
  if (window.PublicKeyCredential) {
    PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = () => Promise.resolve(true);
    PublicKeyCredential.isConditionalMediationAvailable = () => Promise.resolve(true);
  }
})()`;

/// Whether the client data a device made of the station's (`theirs`, JSON) says what the station's says: the same type,
/// challenge and origin, not across origins.
export function sameClientData(theirs: string, ours: string): boolean {
  try {
    const a = JSON.parse(theirs);
    const b = JSON.parse(ours);
    return a?.type === b.type && a?.challenge === b.challenge && a?.origin === b.origin && a?.crossOrigin !== true;
  } catch {
    return false;
  }
}

/// Whether a page on `host` may ask for a passkey of relying party `rpId`: the host itself, or a domain it is under
/// that is more than one label (as browsers take it, short of the public suffix list: a site's own passkeys are kept
/// for its own domain, and a device has none for a bare suffix).
export function rpFor(rpId: string, host: string): boolean {
  const rp = rpId.toLowerCase().replace(/\.$/, "");
  return rp !== "" && (rp === host || (rp.includes(".") && host.endsWith("." + rp)));
}

/// The host of an address (lower case, no trailing dot); "" for one with none (about:blank).
export function hostOf(url: string): string {
  try {
    return new URL(url).hostname.toLowerCase().replace(/\.$/, "");
  } catch {
    return "";
  }
}

type Cast = { ack: number; data: Uint8Array; meta: any };

export type ViewParts = {
  /// The view's own connection, and its session on the tab.
  cdp: Cdp;
  session: string;
  targetId: string;
  /// Milliseconds, for telling a double click.
  now: () => number;
  /// The tab's viewport (CSS pixels), as the frames say it.
  sized?: (size: { width: number; height: number }) => void;
  /// When the view ends.
  ended?: () => void;
};

export class TabView implements ScreenView {
  readonly #p: ViewParts;
  #received: Cast[] = [];
  #delivered: number[] = [];
  #waiter: ((frame: Frame | null) => void) | null = null;
  #ended = false;
  /// The passkey sign-in a page asked last and not yet answered: its id, the origin it was asked on, the client data
  /// made of it.
  #asked: { id: string; origin: string; clientData: string } | null = null;
  /// Who hears the passkey sign-ins (watchPasskey), told as the one asked is answered.
  #passkeyHeard: ((ask: PasskeyAsk | null) => void) | null = null;
  #keyframe = false;
  #last: { data: Uint8Array; config: FrameConfig } | null = null;
  #config: FrameConfig | null = null;
  #ts = 0;
  #viewport = { width: 0, height: 0 };
  #buttons = 0;
  #click = { count: 0, at: -Infinity, x: 0, y: 0, button: "none" };
  #unlisten: () => void;
  /// A preview's (ViewOptions.peek): the tab is not brought forward for it, so what is behind another casts nothing.
  #peek = false;
  /// Laid out for the viewer's phone (ViewOptions.fit) until it ends.
  #fitted = false;

  /// Chrome's own screencast, a JPEG a picture.
  video(): ScreenVideo {
    return { capture: "Chrome screencast", encoder: "JPEG" };
  }

  constructor(p: ViewParts) {
    this.#p = p;
    this.#unlisten = p.cdp.on((e) => this.#heard(e));
    void p.cdp.closed.then(() => this.#end());
  }

  /// Starts casting; `viewport`: the page's size before the first frame says it. Laid out for the viewer's phone
  /// (`fit`): its size and scale, and a phone's ways (Chrome's device emulation on the view's own session, which goes
  /// with it), and cast as large as that.
  async start(options: ViewOptions, viewport?: { width: number; height: number }) {
    if (viewport) this.#viewport = viewport;
    this.#peek = options.peek === true;
    const { cdp, session } = this.#p;
    await cdp.send("Page.enable", {}, session);
    const fit = options.fit && !this.#peek ? options.fit : undefined;
    let bounds = { maxWidth: options.maxWidth, maxHeight: options.maxHeight };
    if (fit) {
      const scale = Math.min(fit.scale, FIT_SCALE_MOST);
      await cdp.send("Emulation.setDeviceMetricsOverride", { width: fit.width, height: fit.height, deviceScaleFactor: scale, mobile: true }, session);
      this.#viewport = { width: fit.width, height: fit.height };
      this.#fitted = true;
      bounds = { maxWidth: fit.width * scale, maxHeight: fit.height * scale };
    } else if (!viewport) {
      const v = viewportOf(await cdp.send("Page.getLayoutMetrics", {}, session).catch(() => null));
      // The tab's size is its viewport's: told now, not only when a frame says another.
      if (v) {
        this.#viewport = v;
        this.#p.sized?.(v);
      }
    }
    await cdp.send(
      "Page.startScreencast",
      { format: "jpeg", quality: QUALITY, maxWidth: Math.max(1, Math.round(bounds.maxWidth)), maxHeight: Math.max(1, Math.round(bounds.maxHeight)), everyNthFrame: 1 },
      session,
    );
  }

  next(): Promise<Frame | null> {
    if (this.#ended) return Promise.resolve(null);
    // The frames given before were taken: Chrome may cast the next ones.
    for (const ack of this.#delivered.splice(0)) this.#ack(ack);
    if (this.#keyframe && this.#last) return Promise.resolve(this.#again());
    const frame = this.#take();
    if (frame) return Promise.resolve(frame);
    return new Promise((resolve) => (this.#waiter = resolve));
  }

  keyframe() {
    this.#keyframe = true;
    if (this.#waiter && this.#last) {
      const w = this.#waiter;
      this.#waiter = null;
      w(this.#again());
    }
  }

  async input(event: ScreenInput) {
    if (this.#ended) return;
    const { cdp, session } = this.#p;
    switch (event.t) {
      case "pointer": {
        const at = toViewport(event.x, event.y, this.#viewport);
        const before = this.#buttons;
        this.#buttons = event.buttons;
        if (event.kind === "move") {
          await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", ...at, button: buttonOf(event.buttons), buttons: event.buttons }, session);
          return;
        }
        if (event.kind === "down") {
          const button = buttonOf(event.buttons & ~before) === "none" ? "left" : buttonOf(event.buttons & ~before);
          const now = this.#p.now();
          const c = this.#click;
          const again = c.button === button && now - c.at <= CLICK_MS && Math.abs(at.x - c.x) <= CLICK_PX && Math.abs(at.y - c.y) <= CLICK_PX;
          this.#click = { count: again ? c.count + 1 : 1, at: now, x: at.x, y: at.y, button };
          await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", ...at, button, buttons: event.buttons, clickCount: this.#click.count }, session);
          return;
        }
        const released = buttonOf(before & ~event.buttons);
        const button = released === "none" ? this.#click.button : released;
        await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", ...at, button, buttons: event.buttons, clickCount: Math.max(1, this.#click.count) }, session);
        return;
      }
      case "wheel": {
        const at = toViewport(event.x, event.y, this.#viewport);
        await cdp.send("Input.dispatchMouseEvent", { type: "mouseWheel", ...at, deltaX: event.dx, deltaY: event.dy, button: "none", buttons: this.#buttons }, session);
        return;
      }
      case "key":
        await cdp.send("Input.dispatchKeyEvent", keyEvent(event), session);
        return;
      case "text":
        if (event.text !== "") await cdp.send("Input.insertText", { text: event.text }, session);
        return;
    }
  }

  /// A paste: the text inserted where the tab's focus is (Chrome's own clipboard is the machine's, left as it is).
  async setClipboard(clip: Clip, paste: boolean): Promise<void> {
    if (this.#ended || clip.type !== "text" || !paste) return;
    await this.#p.cdp.send("Input.insertText", { text: clip.text }, this.#p.session);
  }

  watchClipboard(heard: (clip: Clip) => void): () => void {
    const { cdp, session } = this.#p;
    let on = true;
    let script: string | null = null;
    const unlisten = cdp.on((e) => {
      if (on && e.method === "Runtime.bindingCalled" && e.sessionId === session && e.params?.name === COPY_BINDING && typeof e.params.payload === "string" && e.params.payload !== "") {
        heard({ type: "text", text: e.params.payload });
      }
    });
    const undo = () => {
      if (this.#ended) return;
      void cdp.send("Runtime.removeBinding", { name: COPY_BINDING }, session).catch(() => {});
      if (script !== null) void cdp.send("Page.removeScriptToEvaluateOnNewDocument", { identifier: script }, session).catch(() => {});
    };
    void (async () => {
      try {
        // The binding needs no Runtime.enable (which a page could tell).
        await cdp.send("Runtime.addBinding", { name: COPY_BINDING }, session);
        script = (await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: COPY_HOOK }, session))?.identifier ?? null;
        await cdp.send("Runtime.evaluate", { expression: COPY_HOOK }, session);
        if (!on) undo();
      } catch {}
    })();
    return () => {
      if (!on) return;
      on = false;
      unlisten();
      undo();
    };
  }

  /// The login field in focus, as the page's hook says it, with the tab's host as the browser has its address (asked
  /// each time: the page may have gone elsewhere), until the returned function.
  watchLogin(heard: (login: LoginField | null) => void): () => void {
    const { cdp, session, targetId } = this.#p;
    let on = true;
    let script: string | null = null;
    const unlisten = cdp.on((e) => {
      if (!on || e.method !== "Runtime.bindingCalled" || e.sessionId !== session || e.params?.name !== LOGIN_BINDING) return;
      let said: any = null;
      try {
        said = JSON.parse(String(e.params.payload));
      } catch {}
      const field = said?.field === "username" || said?.field === "password" ? (said.field as LoginField["field"]) : null;
      if (field === null) return heard(null);
      void this.#host(targetId).then((host) => on && heard(host === "" ? null : { host, field }));
    });
    const undo = () => {
      if (this.#ended) return;
      void cdp.send("Runtime.removeBinding", { name: LOGIN_BINDING }, session).catch(() => {});
      if (script !== null) void cdp.send("Page.removeScriptToEvaluateOnNewDocument", { identifier: script }, session).catch(() => {});
    };
    void (async () => {
      try {
        await cdp.send("Runtime.addBinding", { name: LOGIN_BINDING }, session);
        script = (await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: LOGIN_HOOK }, session))?.identifier ?? null;
        await cdp.send("Runtime.evaluate", { expression: LOGIN_HOOK }, session);
        if (!on) undo();
      } catch {}
    })();
    return () => {
      if (!on) return;
      on = false;
      unlisten();
      undo();
    };
  }

  /// Fills the login form in focus with what the person's app gave, only while the tab is on `f.host`, in a world of
  /// the page's top frame of its own (nothing of it logged).
  async fill(f: LoginFill): Promise<void> {
    if (this.#ended) return;
    const { cdp, session, targetId } = this.#p;
    if ((await this.#host(targetId)) !== f.host.toLowerCase()) return;
    const { frameTree } = await cdp.send("Page.getFrameTree", {}, session);
    const frameId = frameTree?.frame?.id;
    if (typeof frameId !== "string") return;
    const { executionContextId } = await cdp.send("Page.createIsolatedWorld", { frameId, worldName: "stillfail-fill" }, session);
    await cdp.send("Runtime.evaluate", { expression: fillScript(f.username, f.password), contextId: executionContextId, returnByValue: true }, session);
  }

  /// A page's passkey sign-ins, as its hook asks them, each checked against the tab's address as the browser has it
  /// (its origin, its host for the relying party) and made into the client data the device is to sign; null as the
  /// one asked goes. Until the returned function, which answers what is still asked as the browser would with none.
  watchPasskey(heard: (ask: PasskeyAsk | null) => void): () => void {
    const { cdp, session, targetId } = this.#p;
    let on = true;
    let script: string | null = null;
    this.#passkeyHeard = heard;
    const unlisten = cdp.on((e) => {
      if (!on || e.method !== "Runtime.bindingCalled" || e.sessionId !== session || e.params?.name !== PASSKEY_BINDING) return;
      let said: any = null;
      try {
        said = JSON.parse(String(e.params.payload));
      } catch {}
      if (typeof said?.id !== "string" || said.id === "" || said.id.length > 32) return;
      const id: string = said.id;
      if (said.gone === true) {
        if (this.#asked?.id === id) {
          this.#asked = null;
          heard(null);
        }
        return;
      }
      const b64 = (v: unknown): v is string => typeof v === "string" && v !== "" && v.length <= 1366 && /^[A-Za-z0-9_-]+$/.test(v);
      const allow: unknown[] = Array.isArray(said.allow) ? said.allow.slice(0, 64) : [];
      if (typeof said.rpId !== "string" || !b64(said.challenge) || !allow.every(b64)) return;
      const userVerification = ["required", "preferred", "discouraged"].includes(said.userVerification) ? said.userVerification : "preferred";
      void this.#url(targetId).then((url) => {
        if (!on) return;
        let origin = "";
        try {
          const u = new URL(url);
          // (a secure context only, as WebAuthn takes: https, or this machine's own)
          if (u.protocol === "https:" || (u.protocol === "http:" && (u.hostname === "localhost" || u.hostname === "127.0.0.1"))) origin = u.origin;
        } catch {}
        const host = hostOf(url);
        if (origin === "" || !rpFor(said.rpId, host)) {
          void this.#answer({ id, error: "NotAllowedError" });
          return;
        }
        const clientData = JSON.stringify({ type: "webauthn.get", challenge: said.challenge, origin, crossOrigin: false });
        // (one asked at a time, the latest: one before it is answered as given up)
        if (this.#asked !== null) void this.#answer({ id: this.#asked.id, error: "NotAllowedError" });
        this.#asked = { id, origin, clientData };
        heard({ id, host, rpId: said.rpId.toLowerCase().replace(/\.$/, ""), clientData, allow: allow as string[], userVerification });
      });
    });
    const undo = () => {
      if (this.#passkeyHeard === heard) this.#passkeyHeard = null;
      if (this.#ended) return;
      if (this.#asked !== null) void this.#answer({ id: this.#asked.id, error: "NotAllowedError" });
      this.#asked = null;
      void cdp.send("Runtime.removeBinding", { name: PASSKEY_BINDING }, session).catch(() => {});
      if (script !== null) void cdp.send("Page.removeScriptToEvaluateOnNewDocument", { identifier: script }, session).catch(() => {});
    };
    void (async () => {
      try {
        await cdp.send("Runtime.addBinding", { name: PASSKEY_BINDING }, session);
        script = (await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: PASSKEY_HOOK }, session))?.identifier ?? null;
        await cdp.send("Runtime.evaluate", { expression: PASSKEY_HOOK }, session);
        if (!on) undo();
      } catch {}
    })();
    return () => {
      if (!on) return;
      on = false;
      unlisten();
      undo();
    };
  }

  /// Answers the page's passkey sign-in with what the person's app signed, only the one asked last, while the tab is
  /// still on the origin it was asked on: its client data the station's own as it was signed, or the device's where it
  /// made its own of it (macOS), only if that says what the station's said (its type, challenge and origin).
  async passkey(a: PasskeyAnswer): Promise<void> {
    const asked = this.#asked;
    if (this.#ended || asked === null || asked.id !== a.id) return;
    this.#asked = null;
    this.#passkeyHeard?.(null);
    let origin = "";
    try {
      origin = new URL(await this.#url(this.#p.targetId)).origin;
    } catch {}
    if (origin !== asked.origin) return;
    if ("error" in a) return this.#answer(a);
    let clientData = Buffer.from(asked.clientData).toString("base64url");
    if (a.clientData !== undefined) {
      if (!sameClientData(Buffer.from(a.clientData, "base64url").toString("utf8"), asked.clientData)) return this.#answer({ id: a.id, error: "NotAllowedError" });
      clientData = a.clientData;
    }
    await this.#answer({ ...a, clientData });
  }

  /// The page's hook told how its ask `a.id` went.
  async #answer(a: { id: string } & Record<string, unknown>): Promise<void> {
    await this.#p.cdp.send("Runtime.evaluate", { expression: `window.__stillfailPasskeyDone && window.__stillfailPasskeyDone(${JSON.stringify(a.id)}, ${JSON.stringify(a)})` }, this.#p.session).catch(() => {});
  }

  /// The address of tab `targetId` as the browser has it now ("" for none).
  async #url(targetId: string): Promise<string> {
    const { targetInfo } = await this.#p.cdp.send("Target.getTargetInfo", { targetId }).catch(() => ({ targetInfo: null }));
    return String(targetInfo?.url ?? "");
  }

  /// The host of tab `targetId` as the browser has its address now ("" for none).
  async #host(targetId: string): Promise<string> {
    return hostOf(await this.#url(targetId));
  }

  close() {
    if (this.#ended) return;
    const { cdp, session } = this.#p;
    void cdp.send("Page.stopScreencast", {}, session).catch(() => {});
    // As it was laid out before (its session going takes it away too; said, for a Chrome that would keep it).
    if (this.#fitted) void cdp.send("Emulation.clearDeviceMetricsOverride", {}, session).catch(() => {});
    void cdp.send("Target.detachFromTarget", { sessionId: session }).catch(() => {}).finally(() => cdp.close());
    this.#end();
  }

  /// The tab's viewport as last cast (CSS pixels).
  viewport() {
    return this.#viewport;
  }

  #heard(e: CdpEvent) {
    const { session } = this.#p;
    if (e.method === "Page.screencastFrame" && e.sessionId === session) {
      if (this.#ended) return;
      const data = Buffer.from(String(e.params.data ?? ""), "base64");
      this.#received.push({ ack: e.params.sessionId, data, meta: e.params.metadata ?? {} });
      while (this.#received.length > HELD) this.#ack(this.#received.shift()!.ack);
      if (this.#waiter) {
        const w = this.#waiter;
        this.#waiter = null;
        w(this.#take());
      }
    } else if ((e.method === "Target.detachedFromTarget" && e.params.sessionId === session) || (e.method === "Inspector.detached" && e.sessionId === session)) {
      this.#end();
    }
  }

  /// The newest frame received, the older let go; null when none came.
  #take(): Frame | null {
    const newest = this.#received.pop();
    if (newest === undefined) return null;
    for (const older of this.#received.splice(0)) this.#ack(older.ack);
    this.#delivered.push(newest.ack);
    const meta = newest.meta;
    if (meta.deviceWidth > 0 && meta.deviceHeight > 0 && (meta.deviceWidth !== this.#viewport.width || meta.deviceHeight !== this.#viewport.height)) {
      this.#viewport = { width: meta.deviceWidth, height: meta.deviceHeight };
      this.#p.sized?.(this.#viewport);
    }
    const size = jpegSize(newest.data) ?? (this.#config ? { width: this.#config.width, height: this.#config.height } : { width: this.#viewport.width, height: this.#viewport.height });
    const config: FrameConfig = { codec: "jpeg", width: size.width, height: size.height };
    const changed = this.#config === null || this.#config.width !== config.width || this.#config.height !== config.height || this.#keyframe;
    this.#keyframe = false;
    this.#config = config;
    this.#last = { data: newest.data, config };
    const stamp = typeof meta.timestamp === "number" ? Math.round(meta.timestamp * 1e6) : this.#p.now() * 1000;
    this.#ts = Math.max(this.#ts + 1, stamp);
    return { ...(changed ? { config } : {}), key: true, ts: this.#ts, data: newest.data };
  }

  /// The last frame again, for a viewer that lost its decoder's state.
  #again(): Frame {
    this.#keyframe = false;
    const last = this.#last!;
    this.#ts += 1;
    return { config: last.config, key: true, ts: this.#ts, data: last.data };
  }

  #ack(ack: number) {
    const { cdp, session } = this.#p;
    void cdp.send("Page.screencastFrameAck", { sessionId: ack }, session).catch(() => {});
  }

  #end() {
    if (this.#ended) return;
    this.#ended = true;
    this.#unlisten();
    const w = this.#waiter;
    this.#waiter = null;
    w?.(null);
    this.#p.ended?.();
  }
}
