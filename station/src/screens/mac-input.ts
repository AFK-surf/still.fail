// A person's input (source.ts `ScreenInput`, as a page has it) as macOS posts it: which mouse button went down or up
// and how many clicks it makes, a page's key `code` as the Mac's virtual key, its modifiers as CGEventFlags. What the
// desktop's helper is given (native/screen: `{op: "mouse" | "scroll" | "key" | "text"}`); it only posts.
import type { ScreenInput } from "./source.ts";

export type MacOp =
  | { op: "mouse"; type: "move" | "down" | "up"; x: number; y: number; button: number; buttons: number; clicks: number; flags: number }
  | { op: "scroll"; x: number; y: number; dx: number; dy: number; flags: number }
  | { op: "key"; keycode: number; down: boolean; flags: number }
  | { op: "text"; text: string };

/// CGEventFlags of a ScreenInput's `mods` (bit 0 alt, 1 ctrl, 2 meta, 3 shift).
export const FLAGS = { alt: 0x80000, ctrl: 0x40000, command: 0x100000, shift: 0x20000, numericPad: 0x200000, fn: 0x800000 };
export function flagsOf(mods: number): number {
  return (mods & 1 ? FLAGS.alt : 0) | (mods & 2 ? FLAGS.ctrl : 0) | (mods & 4 ? FLAGS.command : 0) | (mods & 8 ? FLAGS.shift : 0);
}

/// A page's KeyboardEvent.code (the key's place, whatever the layout) → the Mac's virtual key (Events.h kVK_*).
export const KEYCODES: Record<string, number> = {
  KeyA: 0x00, KeyS: 0x01, KeyD: 0x02, KeyF: 0x03, KeyH: 0x04, KeyG: 0x05, KeyZ: 0x06, KeyX: 0x07, KeyC: 0x08, KeyV: 0x09,
  IntlBackslash: 0x0a, KeyB: 0x0b, KeyQ: 0x0c, KeyW: 0x0d, KeyE: 0x0e, KeyR: 0x0f, KeyY: 0x10, KeyT: 0x11,
  Digit1: 0x12, Digit2: 0x13, Digit3: 0x14, Digit4: 0x15, Digit6: 0x16, Digit5: 0x17, Equal: 0x18, Digit9: 0x19,
  Digit7: 0x1a, Minus: 0x1b, Digit8: 0x1c, Digit0: 0x1d, BracketRight: 0x1e, KeyO: 0x1f, KeyU: 0x20, BracketLeft: 0x21,
  KeyI: 0x22, KeyP: 0x23, Enter: 0x24, KeyL: 0x25, KeyJ: 0x26, Quote: 0x27, KeyK: 0x28, Semicolon: 0x29, Backslash: 0x2a,
  Comma: 0x2b, Slash: 0x2c, KeyN: 0x2d, KeyM: 0x2e, Period: 0x2f, Tab: 0x30, Space: 0x31, Backquote: 0x32,
  Backspace: 0x33, Escape: 0x35, MetaRight: 0x36, MetaLeft: 0x37, ShiftLeft: 0x38, CapsLock: 0x39, AltLeft: 0x3a,
  ControlLeft: 0x3b, ShiftRight: 0x3c, AltRight: 0x3d, ControlRight: 0x3e, Fn: 0x3f, F17: 0x40, NumpadDecimal: 0x41,
  NumpadMultiply: 0x43, NumpadAdd: 0x45, NumLock: 0x47, AudioVolumeUp: 0x48, AudioVolumeDown: 0x49,
  AudioVolumeMute: 0x4a, NumpadDivide: 0x4b, NumpadEnter: 0x4c, NumpadSubtract: 0x4e, F18: 0x4f, F19: 0x50,
  NumpadEqual: 0x51, Numpad0: 0x52, Numpad1: 0x53, Numpad2: 0x54, Numpad3: 0x55, Numpad4: 0x56, Numpad5: 0x57,
  Numpad6: 0x58, Numpad7: 0x59, F20: 0x5a, Numpad8: 0x5b, Numpad9: 0x5c, IntlYen: 0x5d, IntlRo: 0x5e, NumpadComma: 0x5f,
  F5: 0x60, F6: 0x61, F7: 0x62, F3: 0x63, F8: 0x64, F9: 0x65, Lang2: 0x66, F11: 0x67, Lang1: 0x68, F13: 0x69, F16: 0x6a,
  F14: 0x6b, F10: 0x6d, ContextMenu: 0x6e, F12: 0x6f, F15: 0x71, Insert: 0x72, Help: 0x72, Home: 0x73, PageUp: 0x74,
  Delete: 0x75, F4: 0x76, End: 0x77, F2: 0x78, PageDown: 0x79, F1: 0x7a, ArrowLeft: 0x7b, ArrowRight: 0x7c,
  ArrowDown: 0x7d, ArrowUp: 0x7e,
};
/// Keys a Mac's keyboard says are on its function row or keypad: posted with the flags its own keyboard gives them.
const ARROWS = new Set([0x7b, 0x7c, 0x7d, 0x7e]);
const FN_KEYS = new Set([0x72, 0x73, 0x74, 0x75, 0x77, 0x79, 0x7a, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6d, 0x67, 0x6f]);

/// Two downs of a button this close (ms, and in 0..1 of the screen) are one double click (macOS's default interval).
export const CLICK_MS = 500;
const CLICK_NEAR = 0.01;

/// DOM `buttons` bits (1 left, 2 right, 4 middle) → DOM `button` (0 left, 1 middle, 2 right).
const BUTTON_OF_BIT: Record<number, number> = { 1: 0, 2: 2, 4: 1 };
const lowestBit = (bits: number) => bits & -bits;

/// One view's input as it goes: which buttons are held, and the last press (for click counts).
export class MacInput {
  #buttons = 0;
  #press: { at: number; x: number; y: number; button: number; clicks: number } | null = null;

  /// What `e` is posted as, at `now` (ms).
  ops(e: ScreenInput, now: number): MacOp[] {
    switch (e.t) {
      case "pointer": {
        const before = this.#buttons;
        this.#buttons = e.buttons & 7;
        if (e.kind === "move") return [{ op: "mouse", type: "move", x: e.x, y: e.y, button: 0, buttons: this.#buttons, clicks: 0, flags: 0 }];
        if (e.kind === "down") {
          const bit = lowestBit(this.#buttons & ~before) || 1;
          const button = BUTTON_OF_BIT[bit] ?? 0;
          const last = this.#press;
          const again = last !== null && last.button === button && now - last.at <= CLICK_MS && Math.abs(last.x - e.x) <= CLICK_NEAR && Math.abs(last.y - e.y) <= CLICK_NEAR;
          const clicks = again ? last.clicks + 1 : 1;
          this.#press = { at: now, x: e.x, y: e.y, button, clicks };
          this.#buttons |= bit;
          return [{ op: "mouse", type: "down", x: e.x, y: e.y, button, buttons: this.#buttons, clicks, flags: 0 }];
        }
        const bit = lowestBit(before & ~this.#buttons) || lowestBit(before) || 1;
        const button = BUTTON_OF_BIT[bit] ?? 0;
        this.#buttons &= ~bit;
        const clicks = this.#press?.button === button ? this.#press.clicks : 1;
        return [{ op: "mouse", type: "up", x: e.x, y: e.y, button, buttons: this.#buttons, clicks, flags: 0 }];
      }
      case "wheel":
        return [{ op: "scroll", x: e.x, y: e.y, dx: e.dx, dy: e.dy, flags: 0 }];
      case "key": {
        const keycode = KEYCODES[e.code];
        if (keycode === undefined) {
          // A key of no known place (another layout's, a phone's keyboard): what it types, when it types one thing.
          return e.kind === "down" && Array.from(e.key).length === 1 && (e.mods & 6) === 0 ? [{ op: "text", text: e.key }] : [];
        }
        const flags = flagsOf(e.mods) | (ARROWS.has(keycode) ? FLAGS.numericPad | FLAGS.fn : 0) | (FN_KEYS.has(keycode) ? FLAGS.fn : 0);
        return [{ op: "key", keycode, down: e.kind === "down", flags }];
      }
      case "text":
        return e.text === "" ? [] : [{ op: "text", text: e.text }];
    }
  }
}
