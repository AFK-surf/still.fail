// A browser's zoom keys belong to it, including while the hidden input or the shortcut recorder has focus.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

function browser(platform) {
  const element = () => ({
    style: {}, listeners: new Map(),
    addEventListener(name, f) { this.listeners.set(name, [...(this.listeners.get(name) || []), f]); },
    dispatch(name, e) { for (const f of this.listeners.get(name) || []) f(e); },
  });
  const gl = new Proxy({}, { get: (_, name) => {
    if (name === 'getShaderParameter' || name === 'getProgramParameter') return () => true;
    return () => ({});
  } });
  const canvas = { ...element(), width: 0, height: 0, getContext: () => gl,
    getBoundingClientRect: () => ({ width: 800, height: 600, left: 0, top: 0 }) };
  const ime = element();
  let focused = true;
  const document = { visibilityState: 'visible', hasFocus: () => focused,
    createElement: () => ({ ...element(), getContext: () => ({}) }),
    getElementById: (id) => id === 'c' ? canvas : ime,
    addEventListener() {} };
  const win = { ...element(), document, navigator: { platform }, location: { search: '' }, URLSearchParams, Intl,
    devicePixelRatio: 1, performance: { now: () => 0 }, requestAnimationFrame() {}, queueMicrotask: (f) => f() };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const keys = [], pointers = [];
  win.__mbhost.run('test', () => {}, (kind) => pointers.push([kind, win.__mbhost.modsHeld()]), () => {},
    (code, mods) => keys.push([code, mods]), () => {});
  return {
    host: win.__mbhost,
    press(target, key, mods = {}) {
      const event = { target: target === 'ime' ? ime : canvas, key, code: mods.code || '',
        ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...mods,
        defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } };
      keys.length = 0;
      if (target === 'ime') ime.dispatch('keydown', event);
      win.dispatch('keydown', event);
      return { prevented: event.defaultPrevented, keys: [...keys] };
    },
    release(target, key, mods = {}) {
      win.dispatch('keyup', { target: target === 'ime' ? ime : canvas, key,
        ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...mods });
    },
    pointerUp(mods = {}) {
      canvas.dispatch('pointerup', { pointerType: 'mouse', button: 0, clientX: 50, clientY: 50, timeStamp: 1,
        ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...mods });
      return pointers.at(-1);
    },
    blur() { focused = false; win.dispatch('blur', {}); },
  };
}

test('modifier changes reach the host while the pointer rests and clear on blur', () => {
  const b = browser('MacIntel');
  const seen = [];
  b.host.setModifiers((mods) => seen.push(mods));
  b.host.setAppState(() => {});
  b.press('page', 'Alt', { altKey: true });
  b.press('ime', 'Meta', { altKey: true, metaKey: true });
  b.release('ime', 'Alt', { metaKey: true });
  // The release itself carries the final flags, even if a keyboard change happened outside this page.
  assert.deepEqual(b.pointerUp({ altKey: true }), [2, 4]);
  b.blur();
  assert.deepEqual(seen, [4, 12, 8, 4, 0]);
  assert.equal(b.host.modsHeld(), 0);
});

for (const [platform, command, other] of [['Win32', 'ctrlKey', 'metaKey'], ['MacIntel', 'metaKey', 'ctrlKey']]) {
  test(`${platform}: browser zoom keys pass through the page, the input and the shortcut recorder`, () => {
    const b = browser(platform);
    for (const recording of [false, true]) {
      b.host.keyCatch(recording);
      for (const target of ['page', 'ime']) {
        for (const [key, code, shiftKey] of [
          ['=', 'Equal', false], ['+', 'Equal', true], ['-', 'Minus', false], ['0', 'Digit0', false],
          ['+', 'NumpadAdd', false], ['-', 'NumpadSubtract', false], ['0', 'Numpad0', false],
        ]) {
          assert.deepEqual(b.press(target, key, { [command]: true, code, shiftKey }), { prevented: false, keys: [] },
            `${target}, recording=${recording}: ${key} (${code})`);
        }
      }
    }
    b.host.keyCatch(false);
    // Zoom characters without the platform command, or with Alt as an app shortcut, are still the app's.
    assert.deepEqual(b.press('page', '-', {}), { prevented: true, keys: [[1045, 0]] });
    assert.deepEqual(b.press('page', '0', { [command]: true, altKey: true }),
      { prevented: true, keys: [[1048, platform === 'Win32' ? 6 : 12]] });
    assert.deepEqual(b.press('page', 'k', { [command]: true }),
      { prevented: true, keys: [[1107, platform === 'Win32' ? 2 : 8]] });
    assert.deepEqual(b.press('page', 'r', { [command]: true }), { prevented: false, keys: [] });
    assert.deepEqual(b.press('page', '-', { [other]: true }),
      { prevented: true, keys: [[1045, platform === 'Win32' ? 8 : 2]] });
  });
}
