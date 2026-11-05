// A browser's pinch (a wheel with ctrl) zooms the page unless the app zoomed something of its own by it.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

function browser(keeps) {
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
  const win = { ...element(), document, navigator: { platform: 'MacIntel' }, location: { search: '' }, URLSearchParams,
    Intl, devicePixelRatio: 1, performance: { now: () => 0 }, requestAnimationFrame() {} };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const wheels = [];
  // (the app as host_js.mbt's wheel_kept tells it: whether it zoomed something of its own by the wheel)
  const wheel = (x, y, dx, dy, phase) => {
    wheels.push(phase >> 4);
    if (keeps !== undefined) win.__mbhost.wheelKept = keeps(phase >> 4);
  };
  win.__mbhost.run('test', () => {}, () => {}, wheel, () => {}, () => {});
  return {
    wheel(mods = {}) {
      const event = { clientX: 10, clientY: 10, deltaX: 0, deltaY: -3, deltaMode: 0,
        ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...mods,
        defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } };
      wheels.length = 0;
      canvas.dispatch('wheel', event);
      return { prevented: event.defaultPrevented, mods: wheels[0] };
    },
  };
}

test('a pinch the app zoomed nothing by is the page\'s, one it zoomed a picture by is the app\'s', () => {
  const page = browser(() => false);
  // (ctrl: ui's wheel_mod_ctrl and wheel_mod_pinch, 2 | 16)
  assert.deepEqual(page.wheel({ ctrlKey: true }), { prevented: false, mods: 18 });
  assert.deepEqual(page.wheel(), { prevented: true, mods: 0 });
  assert.deepEqual(page.wheel({ metaKey: true }), { prevented: true, mods: 8 });
  const picture = browser(() => true);
  assert.deepEqual(picture.wheel({ ctrlKey: true }), { prevented: true, mods: 18 });
  // (an app that says nothing of it keeps every wheel, as before)
  assert.deepEqual(browser().wheel({ ctrlKey: true }), { prevented: true, mods: 18 });
});
