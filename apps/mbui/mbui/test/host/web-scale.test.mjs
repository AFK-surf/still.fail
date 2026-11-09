// The browser host's scale contract, without a window: fractional sizes and device pixels agree; a resolution change
// alone requests a frame and invalidates the atlas before that frame uses it. The 2D bounds make bitmap sizes observable.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

test('the web host keeps glyphs and its canvas aligned to the device pixels', async () => {
  const listeners = new Map(), queries = [], queued = [], frames = [], observers = [];
  let measurements = 0, viewport;
  const gl = new Proxy({}, { get: (_, name) => {
    if (name === 'getShaderParameter' || name === 'getProgramParameter') return () => true;
    if (name === 'getUniformLocation') return (_program, uniform) => uniform;
    if (name === 'uniform2f') return (uniform, x, y) => { if (uniform === 'u_vp') viewport = [x, y]; };
    return () => ({});
  } });
  const context2d = () => ({
    measureText: () => ({ actualBoundingBoxLeft: 1, actualBoundingBoxRight: 7, actualBoundingBoxAscent: 10,
      actualBoundingBoxDescent: 3, fontBoundingBoxAscent: 10, fontBoundingBoxDescent: 3, width: 8 }),
    clearRect() {}, fillText() {},
    getImageData: (_x, _y, w, h) => ({ data: new Uint8ClampedArray(w * h * 4) }),
  });
  const element = () => ({ addEventListener() {}, style: {} });
  const canvas = { ...element(), cssWidth: 400, cssHeight: 300, clientWidth: 400, clientHeight: 300,
    width: 0, height: 0, getContext: () => gl,
    getBoundingClientRect() { measurements++; return { width: this.cssWidth, height: this.cssHeight }; },
  };
  const ime = element();
  const document = {
    createElement: () => ({ ...element(), getContext: () => context2d() }),
    getElementById: (id) => id === 'c' ? canvas : ime,
    addEventListener() {},
  };
  const win = {
    document, location: { search: '' }, URLSearchParams, Intl, devicePixelRatio: 1,
    performance: { now: () => 0 }, requestAnimationFrame: (f) => queued.push(f),
    addEventListener: (name, f) => listeners.set(name, f),
    ResizeObserver: class {
      constructor(f) { this.changed = f; observers.push(this); }
      observe(el) { assert.equal(el, canvas); }
    },
    matchMedia: (query) => {
      const q = { query, listener: null,
        addEventListener: (_name, f) => { q.listener = f; },
        removeEventListener: (_name, f) => { if (q.listener === f) q.listener = null; },
      };
      queries.push(q);
      return q;
    },
  };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const host = win.__mbhost;
  host.run('test', (w, h, scale) => {
    const out = new Float64Array(8);
    host.glyph(host.textKey('A', 14, 400, 0), out);
    frames.push({ w, h, scale, generation: host.atlasGeneration(), pixels: [out[2] * scale, out[3] * scale] });
  }, () => {}, () => {}, () => {}, () => {});
  await Promise.resolve(); // H.run requests its first frame once the decoder's answer is known.
  const draw = () => { assert.equal(queued.length, 1, 'one frame requested'); queued.shift()(0); return frames.at(-1); };
  assert.deepEqual(draw(), { w: 400, h: 300, scale: 1, generation: 0, pixels: [10, 15] });
  assert.equal(queries.at(-1).query, '(resolution: 1dppx)');
  assert.equal(measurements, 1);

  // A CSS resize at the same scale leaves the atlas valid.
  canvas.cssWidth = canvas.clientWidth = 500;
  listeners.get('resize')();
  assert.deepEqual(draw(), { w: 500, h: 300, scale: 1, generation: 0, pixels: [10, 15] });

  // Moving the window can change its scale without a resize event. The old query fires and the host watches the new one.
  win.devicePixelRatio = 2;
  queries.at(-1).listener();
  assert.equal(queries[0].listener, null);
  assert.deepEqual(draw(), { w: 500, h: 300, scale: 2, generation: 1, pixels: [18, 28] });
  assert.equal(canvas.width, 1000);
  assert.equal(queries.at(-1).query, '(resolution: 2dppx)');

  win.devicePixelRatio = 1.25;
  queries.at(-1).listener();
  assert.equal(queries[1].listener, null);
  assert.deepEqual(draw(), { w: 500, h: 300, scale: 1.25, generation: 2, pixels: [13, 19] });
  assert.equal(queries.at(-1).query, '(resolution: 1.25dppx)');

  // A fractional CSS size is not the rounded clientWidth. Recompute the backing pixels when only the canvas changes,
  // and map a point to exactly 1.25 pixels rather than stretching to fit the rounded buffer.
  canvas.cssWidth = 500.4;
  canvas.cssHeight = 300.4;
  observers[0].changed();
  assert.deepEqual(draw(), { w: 500.4, h: 300.4, scale: 1.25, generation: 2, pixels: [13, 19] });
  assert.deepEqual([canvas.width, canvas.height], [626, 376]);
  host.present(new Float64Array(60), 1, 1, 1, 1);
  assert.deepEqual(viewport, [626 / 1.25, 376 / 1.25]);

  // Ordinary frames neither invalidate the atlas, reread layout, nor recreate the resolution listener.
  const measured = measurements;
  for (let i = 0; i < 100; i++) {
    host.requestFrame();
    assert.equal(draw().generation, 2);
  }
  assert.equal(queries.length, 3);
  assert.equal(measurements, measured);
});
