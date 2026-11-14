// A person's input as the desktops' helpers post it: the modifiers macOS takes from each event's flags alone (a click,
// a wheel, a modifier's own up), and what a view lets go of as it ends, on a Mac and on Windows. Pure: no helper runs.
import assert from "node:assert/strict";
import { test } from "node:test";
import { HelperView, TO_HELPER, helperMessage } from "../src/screens/desktop.ts";
import { FLAGS, KEYCODES, MacInput } from "../src/screens/mac-input.ts";
import { KEYS, WinInput } from "../src/screens/win-input.ts";
import type { ScreenInput } from "../src/screens/source.ts";

const at = (x: number, y: number, kind: "down" | "up" | "move", buttons: number): ScreenInput => ({ t: "pointer", kind, x, y, buttons });
const key = (kind: "down" | "up", code: string, mods: number): ScreenInput => ({ t: "key", kind, key: code, code, mods });

test("macOS: a click and a drag with ⇧ held carry shift; ⇧'s up, sent still saying shift, carries none", () => {
  const mac = new MacInput();
  assert.deepEqual(mac.ops(key("down", "ShiftLeft", 8), 0), [{ op: "key", keycode: KEYCODES.ShiftLeft, down: true, flags: FLAGS.shift }]);
  assert.deepEqual(mac.ops(at(0.3, 0.4, "down", 1), 10), [{ op: "mouse", type: "down", x: 0.3, y: 0.4, button: 0, buttons: 1, clicks: 1, flags: FLAGS.shift }]);
  assert.deepEqual(mac.ops(at(0.35, 0.4, "move", 1), 20), [{ op: "mouse", type: "move", x: 0.35, y: 0.4, button: 0, buttons: 1, clicks: 0, flags: FLAGS.shift }]);
  assert.deepEqual(mac.ops(at(0.35, 0.4, "up", 0), 30), [{ op: "mouse", type: "up", x: 0.35, y: 0.4, button: 0, buttons: 0, clicks: 1, flags: FLAGS.shift }]);
  assert.deepEqual(mac.ops(key("up", "ShiftLeft", 8), 40), [{ op: "key", keycode: KEYCODES.ShiftLeft, down: false, flags: 0 }]);
  assert.equal((mac.ops(at(0.35, 0.4, "move", 0), 50)[0] as any).flags, 0);
});

test("macOS: a wheel with ⌘ held carries command; a key's own mods and the held ones together", () => {
  const mac = new MacInput();
  mac.ops(key("down", "MetaRight", 4), 0);
  assert.deepEqual(mac.ops({ t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: -100 }, 10), [{ op: "scroll", x: 0.5, y: 0.5, dx: 0, dy: -100, flags: FLAGS.command }]);
  // A phone's keys row says ⌃ on the key alone: both go.
  assert.deepEqual(mac.ops(key("down", "KeyC", 2), 20), [{ op: "key", keycode: KEYCODES.KeyC, down: true, flags: FLAGS.command | FLAGS.ctrl }]);
  mac.ops(key("up", "KeyC", 2), 30);
  // The other ⌘ down and the first up: ⌘ still held by it.
  mac.ops(key("down", "MetaLeft", 4), 40);
  assert.deepEqual(mac.ops(key("up", "MetaRight", 4), 50), [{ op: "key", keycode: KEYCODES.MetaRight, down: false, flags: FLAGS.command }]);
  assert.deepEqual(mac.ops(key("up", "MetaLeft", 4), 60), [{ op: "key", keycode: KEYCODES.MetaLeft, down: false, flags: 0 }]);
  assert.equal((mac.ops({ t: "wheel", x: 0.5, y: 0.5, dx: 0, dy: 100 }, 70)[0] as any).flags, 0);
});

test("macOS: as a view ends, its button goes up where the pointer was, then its modifiers, each without its own flag", () => {
  const mac = new MacInput();
  assert.deepEqual(mac.release(), []);
  mac.ops(key("down", "MetaLeft", 4), 0);
  mac.ops(key("down", "ShiftLeft", 12), 10);
  mac.ops(at(0.2, 0.3, "down", 1), 20);
  mac.ops(at(0.6, 0.7, "move", 1), 30);
  assert.deepEqual(mac.release(), [
    { op: "mouse", type: "up", x: 0.6, y: 0.7, button: 0, buttons: 0, clicks: 1, flags: FLAGS.command | FLAGS.shift },
    { op: "key", keycode: KEYCODES.MetaLeft, down: false, flags: FLAGS.shift },
    { op: "key", keycode: KEYCODES.ShiftLeft, down: false, flags: 0 },
  ]);
  assert.deepEqual(mac.release(), []);
});

test("Windows: as a view ends, its buttons go up where the pointer was, then its modifier keys", () => {
  const win = new WinInput();
  assert.deepEqual(win.release(), []);
  win.ops(key("down", "ControlLeft", 2));
  win.ops(at(0.1, 0.2, "down", 2));
  win.ops(at(0.4, 0.5, "move", 2));
  assert.deepEqual(win.release(), [
    { op: "mouse", type: "up", x: 0.4, y: 0.5, button: 2 },
    { op: "key", scan: KEYS.ControlLeft!.scan, ext: false, vk: 0, down: false },
  ]);
  assert.deepEqual(win.release(), []);
  // Let go of before the view ended: nothing more.
  win.ops(key("down", "ShiftLeft", 8));
  win.ops(key("up", "ShiftLeft", 0));
  assert.deepEqual(win.release(), []);
});

test("a helper's view lets go of what is held as it ends, not once its connection is gone", () => {
  const written: Buffer[] = [];
  const listeners: Record<string, ((...args: any[]) => void)[]> = {};
  const pipe = { write: (b: Buffer) => written.push(b), destroy: () => {}, on: (event: string, f: any) => { (listeners[event] ??= []).push(f); } };
  const inputs = () => written.filter((b) => b[0] === TO_HELPER.input).map((b) => JSON.parse(b.subarray(5).toString()));
  const view = new HelperView("h264", pipe, () => {}, new MacInput());
  listeners.data!.forEach((f) => f(helperMessage(1, Buffer.from(JSON.stringify({ width: 64, height: 36, codec: "h264" })))));
  void view.input(key("down", "AltLeft", 1));
  void view.input(at(0.5, 0.5, "down", 1));
  written.length = 0;
  view.close();
  assert.deepEqual(inputs(), [
    { op: "mouse", type: "up", x: 0.5, y: 0.5, button: 0, buttons: 0, clicks: 1, flags: FLAGS.alt },
    { op: "key", keycode: KEYCODES.AltLeft, down: false, flags: 0 },
  ]);
  // The helper's connection went first: nothing to send.
  written.length = 0;
  for (const k of Object.keys(listeners)) delete listeners[k];
  const cut = new HelperView("h264", pipe, () => {}, new MacInput());
  cut.ready.catch(() => {});
  void cut.input(key("down", "ShiftLeft", 8));
  listeners.close!.forEach((f) => f());
  assert.deepEqual(inputs(), [{ op: "key", keycode: KEYCODES.ShiftLeft, down: true, flags: FLAGS.shift }]);
});
