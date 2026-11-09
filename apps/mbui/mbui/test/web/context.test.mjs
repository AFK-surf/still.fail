// A browser can take a WebGL context while a stream is stopped. Its last picture must still be there on restoration.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

function browser() {
  const element = () => ({
    style: {}, listeners: new Map(),
    addEventListener(name, f) { this.listeners.set(name, [...(this.listeners.get(name) || []), f]); },
    dispatch(name, e = {}) { for (const f of this.listeners.get(name) || []) f(e); },
  });
  const uploads = [], bitmaps = [], videos = [];
  let lost = false;
  const ext = { loseContext() {}, restoreContext() {} };
  const gl = new Proxy({}, { get: (_, name) => {
    if (name === 'getShaderParameter' || name === 'getProgramParameter') return () => true;
    if (name === 'getExtension') return () => ext;
    if (name === 'isContextLost') return () => lost;
    if (name === 'texImage2D') return (...args) => uploads.push(args.at(-1));
    return () => ({});
  } });
  const canvas = { ...element(), width: 0, height: 0, getContext: () => gl,
    getBoundingClientRect: () => ({ width: 200, height: 200, left: 0, top: 0 }) };
  const ime = element();
  const document = { createElement: () => ({ ...element(), getContext: () => ({}) }),
    getElementById: id => id === 'c' ? canvas : ime, addEventListener() {} };
  class VideoDecoder {
    static isConfigSupported() { return Promise.resolve({ supported: true }); }
    constructor({ output }) { this.output = output; }
    configure() {}
    decode(chunk) { const frame = videos.shift(); frame.timestamp = chunk.timestamp; this.output(frame); }
    close() {}
  }
  class EncodedVideoChunk { constructor(fields) { Object.assign(this, fields); } }
  const win = { ...element(), document, navigator: { platform: 'MacIntel' }, location: { search: '' }, URLSearchParams,
    Intl, Blob, VideoDecoder, EncodedVideoChunk, createImageBitmap: async () => bitmaps.shift(),
    devicePixelRatio: 1, performance: { now: () => 0 }, requestAnimationFrame() {} };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const host = win.__mbhost;
  host.run('test', () => {}, () => {}, () => {}, () => {}, () => {});
  return { host, canvas, uploads, bitmaps, videos, setLost(value) { lost = value; } };
}

const frame = () => ({ width: 16, height: 16, displayWidth: 16, displayHeight: 16, closed: 0,
  close() { this.closed++; } });
const tick = () => new Promise(resolve => setImmediate(resolve));

test('a stopped JPEG stream is restored, and replaced or closed pictures are released', async () => {
  const b = browser(), id = b.host.streamOpen(), first = frame(), second = frame();
  b.bitmaps.push(first);
  b.host.streamJpeg(id, [1], 1);
  await tick();
  assert.equal(b.host.streamNext(id), 'f 1 16 16');
  b.host.streamShow(id, 1);
  b.uploads.length = 0;
  b.canvas.dispatch('webglcontextrestored');
  assert.equal(b.uploads.at(-1), first, 'restoration uploads the last shown picture');
  assert.equal(first.closed, 0, 'the picture remains available for another restoration');
  b.bitmaps.push(second);
  b.host.streamJpeg(id, [2], 2);
  await tick();
  b.host.streamShow(id, 2);
  assert.equal(first.closed, 1, 'the replaced picture is released');
  b.uploads.length = 0;
  b.canvas.dispatch('webglcontextrestored');
  assert.equal(b.uploads.at(-1), second);
  b.host.streamClose(id);
  assert.equal(second.closed, 1, 'closing the stream releases its picture');
});

test('a stopped H.264 stream restores its last decoded VideoFrame and releases it on close', async () => {
  const b = browser(), id = b.host.streamOpen(), picture = frame();
  await tick(); // the browser has answered whether the decoder is supported
  b.host.streamH264(id, [1, 0x42, 0xe0, 0x2a], 16, 16);
  b.videos.push(picture);
  b.host.streamFrame(id, [1], true, 3);
  assert.equal(b.host.streamNext(id), 'f 3 16 16');
  b.host.streamShow(id, 3);
  b.uploads.length = 0;
  b.canvas.dispatch('webglcontextrestored');
  assert.equal(b.uploads.at(-1), picture);
  b.host.streamClose(id);
  assert.equal(picture.closed, 1);
});

test('a stream shown twice while the context is lost restores only its newest picture', async () => {
  const b = browser(), id = b.host.streamOpen(), first = frame(), second = frame();
  b.setLost(true);
  b.uploads.length = 0;
  b.bitmaps.push(first);
  b.host.streamJpeg(id, [1], 1);
  await tick();
  b.host.streamShow(id, 1);
  b.bitmaps.push(second);
  b.host.streamJpeg(id, [2], 2);
  await tick();
  b.host.streamShow(id, 2);
  assert.equal(b.uploads.length, 0, 'a lost context is not uploaded into');
  assert.equal(first.closed, 1, 'the older lost-context picture is released');
  assert.equal(second.closed, 0);
  b.setLost(false);
  b.canvas.dispatch('webglcontextrestored');
  assert.equal(b.uploads.at(-1), second, 'only the newest picture is restored');
  b.host.streamClose(id);
  assert.equal(second.closed, 1);
});

test('the restore test driver reports each new loss until it is restored', () => {
  const b = browser();
  b.canvas.dispatch('webglcontextrestored');
  assert.equal(b.host.drive(11), true);
  assert.equal(b.host.drive(10), true);
  assert.equal(b.host.drive(11), false);
  b.canvas.dispatch('webglcontextrestored');
  assert.equal(b.host.drive(11), true);
});
