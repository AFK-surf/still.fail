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
  const document = { createElement: () => ({ ...element(), getContext: () => ({}) }),
    getElementById: (id) => id === 'c' ? canvas : ime,
    addEventListener() {} };
  const win = { ...element(), document, navigator: { platform }, location: { search: '' }, URLSearchParams, Intl,
    devicePixelRatio: 1, performance: { now: () => 0 }, requestAnimationFrame() {} };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const keys = [];
  win.__mbhost.run('test', () => {}, () => {}, () => {}, (code, mods) => keys.push([code, mods]), () => {});
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
  };
}

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
