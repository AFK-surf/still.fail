// Pointer reception is split between a canvas and boxes while a site's frame is visible. The boxes are still the app:
// crossing between them or transferring capture to one must not say that the pointer left the window.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

function browser(withSite = true) {
  const made = [], captures = [], pointers = [];
  const element = (tag) => {
    const el = {
      tagName: tag.toUpperCase(), style: {}, listeners: new Map(), children: [], parent: null,
      addEventListener(name, f) { this.listeners.set(name, [...(this.listeners.get(name) || []), f]); },
      dispatch(name, e) { for (const f of this.listeners.get(name) || []) f(e); },
      appendChild(child) { child.remove(); this.children.push(child); child.parent = this; return child; },
      insertBefore(child, before) {
        child.remove();
        const i = this.children.indexOf(before);
        this.children.splice(i < 0 ? this.children.length : i, 0, child);
        child.parent = this;
        return child;
      },
      remove() {
        if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1);
        this.parent = null;
      },
      getContext() { return {}; },
      getBoundingClientRect() { return { left: 0, top: 0, width: 500, height: 400, right: 500, bottom: 400 }; },
      setPointerCapture(id) { captures.push([this, id]); },
    };
    made.push(el);
    return el;
  };
  const gl = new Proxy({}, { get: (_, name) => {
    if (name === 'getShaderParameter' || name === 'getProgramParameter') return () => true;
    return () => ({});
  } });
  const body = element('body'), canvas = element('canvas'), ime = element('textarea');
  canvas.getContext = () => gl;
  body.appendChild(canvas);
  body.appendChild(ime);
  const document = {
    body,
    createElement: element,
    getElementById: (id) => id === 'c' ? canvas : ime,
    querySelector: () => canvas,
    addEventListener() {},
  };
  const win = {
    document, navigator: { platform: 'MacIntel' }, location: { search: '', href: 'http://localhost/' },
    URL, URLSearchParams, Intl, crypto: { randomUUID: () => 'site' },
    devicePixelRatio: 1, performance: { now: () => 0 }, requestAnimationFrame() {},
    getComputedStyle: () => ({ borderTopLeftRadius: '0', borderTopRightRadius: '0',
      borderBottomRightRadius: '0', borderBottomLeftRadius: '0' }),
    addEventListener() {}, console: { log() {} },
  };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const host = win.__mbhost;
  host.run('test', () => {}, (kind, x, y, button) => pointers.push([kind, x, y, button]), () => {}, () => {}, () => {});
  if (!withSite) return { host, canvas, captures, pointers };
  host.siteFrame = '/site';
  const id = host.viewOpen(3, '/');
  host.viewPlace(id, 100, 100, 250, 250, 100, 100, 350, 350, true);
  host.viewTell(id, 4, '100 100 250 250');
  const under = made.find(e => e.style.cssText === 'position:fixed;inset:0;z-index:0;touch-action:none');
  const cover = made.find(e => e.style.cssText === 'position:fixed;z-index:2;touch-action:none');
  const frame = made.find(e => e.tagName === 'IFRAME');
  assert.ok(id && under && cover && frame, 'site and its input layers exist');
  return { host, id, canvas, under, cover, frame, captures, pointers };
}

function leave(from, to, type = 'mouse') {
  from.dispatch('pointerleave', { pointerType: type, relatedTarget: to });
}

function down(on, type = 'mouse', id = 1) {
  on.dispatch('pointerdown', { pointerType: type, pointerId: id, button: 0, clientX: 120, clientY: 150,
    preventDefault() {} });
}

test('only leaving the app input layers says that the mouse left the window', () => {
  const initial = browser(false);
  leave(initial.canvas, null);
  assert.deepEqual(initial.pointers, [[7, -1, -1, 0]], 'leaving the window before a site was opened');
  const b = browser();
  for (const [from, to] of [[b.under, b.cover], [b.cover, b.under], [b.canvas, b.under], [b.under, b.canvas]]) {
    leave(from, to);
  }
  assert.deepEqual(b.pointers, []);
  leave(b.cover, b.frame);
  leave(b.under, null);
  leave(b.cover, null, 'touch');
  assert.deepEqual(b.pointers, [[7, -1, -1, 0], [7, -1, -1, 0]]);
});

test('a cover uses the persistent under layer for capture; after the last site closes the canvas captures itself', () => {
  const b = browser();
  down(b.cover);
  assert.deepEqual(b.captures, [[b.under, 1]]);
  assert.deepEqual(b.pointers, [[0, 120, 150, 0]]);
  b.host.viewClose(b.id);
  b.captures.length = 0;
  b.pointers.length = 0;
  down(b.canvas, 'touch', 42);
  assert.deepEqual(b.captures, [[b.canvas, 42]]);
  assert.deepEqual(b.pointers, [[10, 120, 150, 42]]);
});
