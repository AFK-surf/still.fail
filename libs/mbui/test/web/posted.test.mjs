// What is posted to the browser's host from outside the frames (H.post: the core's worker) is told to the app between
// frames (outside(OUTSIDE_POSTED): ui's messages_between), no frame asked for it, before a key the browser gives in a
// later task; never left for the next frame to take as it begins (src/ui/messages.mbt messages_arrive: there the frame
// has brought the window's tree before what came is taken, and a change only the tree reads went undrawn, 2026-11-11).
// It holds web/host.js alone, run in Node with as little of a page as it reads: not a real browser's order of its
// events, nor what the app does once told (the same messages_between as every host's, the Tester's tests').
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

function browser() {
  const element = () => ({
    style: {}, listeners: new Map(),
    addEventListener(name, f) { this.listeners.set(name, [...(this.listeners.get(name) || []), f]); },
    dispatch(name, e) { for (const f of this.listeners.get(name) || []) f(e); },
  });
  const gl = new Proxy({}, { get: (_, name) =>
    name === 'getShaderParameter' || name === 'getProgramParameter' ? () => true : () => ({}) });
  const canvas = { ...element(), width: 0, height: 0, getContext: () => gl,
    getBoundingClientRect: () => ({ width: 800, height: 600, left: 0, top: 0 }) };
  const ime = element();
  const document = { createElement: () => ({ ...element(), getContext: () => ({}) }),
    getElementById: (id) => id === 'c' ? canvas : ime, addEventListener() {} };
  const said = [];
  const win = { ...element(), document, navigator: { platform: 'MacIntel' }, location: { search: '' }, URLSearchParams,
    Intl, queueMicrotask, devicePixelRatio: 1, performance: { now: () => 0 },
    requestAnimationFrame() { said.push('frame') } };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const H = win.__mbhost;
  H.run('test', () => {}, () => {}, () => {}, (code) => said.push('key ' + code), () => {});
  H.setOutside((kind, id, state) => said.push(`outside ${kind} ${id} ${state}`));
  const asked = H.requestFrame;
  H.requestFrame = () => { said.push('frame asked'); asked(); };
  const key = (k) => win.dispatch('keydown', { target: canvas, key: k, code: '', ctrlKey: false, metaKey: false,
    altKey: false, shiftKey: false, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } });
  return { H, said, key };
}

const task = () => new Promise((resolve) => setTimeout(resolve, 0));

test('a message posted is told between frames, no frame asked for it, before a key that comes after it', async () => {
  const b = browser();
  await task();
  b.said.length = 0;
  // posted in one task, a key in the next: the app told of what came as the posting task ends
  b.H.post('core', '{"id":1,"value":[]}');
  b.H.post('core', '{"id":2,"value":[]}');
  assert.deepEqual(b.said, [], 'told as the posting task ends, not inside H.post');
  await task();
  b.key('a');
  assert.deepEqual(b.said, ['outside 11 0 0', 'key 1097'], 'what was posted told first, once for both, then the key');
  assert.ok(!b.said.includes('frame asked'), 'no frame asked for what was posted: the app asks where something is left');
  // all of it there for the app to take, in the order posted
  assert.equal(b.H.postTake(), 2);
  assert.equal(b.H.postNext(), 'core');
  assert.equal(b.H.postJson(), '{"id":1,"value":[]}');
  assert.equal(b.H.postNext(), 'core');
  assert.equal(b.H.postJson(), '{"id":2,"value":[]}');
});
