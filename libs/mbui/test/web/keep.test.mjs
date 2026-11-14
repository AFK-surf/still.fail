// A file kept on the device (src/hostapi/keep.mbt) on the web is the browser's download (web/host.js H.keepBegin …
// H.keepEnd): its parts copied as they come, one Blob of them all at the finish, an <a download> clicked on its URL,
// kept once clicked and where only its name; the URL revoked never in the click's task, only as a later keep finishes
// a minute or more after it (or the page goes). It holds web/host.js alone, run in Node with as little of a page as it reads:
// not whether a real browser saves the file (its download is its own), nor what the app does with the answer.
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
  // what was clicked to download: its name, its URL's Blob, and whether it was in the document then
  const downloads = [], blobs = new Map(), revoked = [];
  const body = { children: new Set(), appendChild(e) { this.children.add(e); e.parent = this; } };
  const document = { body, getElementById: (id) => id === 'c' ? canvas : ime, addEventListener() {},
    createElement: (tag) => ({ ...element(), tag, getContext: () => ({}),
      remove() { this.parent?.children.delete(this); this.parent = null; },
      click() {
        if (this.tag === 'a' && this.download !== undefined) {
          downloads.push({ name: this.download, url: this.href, blob: blobs.get(this.href), inDocument: body.children.has(this) });
        }
      } }) };
  let nextUrl = 1;
  const URL = { createObjectURL(b) { const u = `blob:test/${nextUrl++}`; blobs.set(u, b); return u; },
    revokeObjectURL(u) { revoked.push(u); blobs.delete(u); } };
  const said = [], frames = [], clock = { ms: 0 };
  const win = { ...element(), document, navigator: { platform: 'MacIntel' }, location: { search: '' }, URLSearchParams,
    Intl, queueMicrotask, devicePixelRatio: 1, performance: { now: () => clock.ms }, Blob, URL,
    requestAnimationFrame(f) { frames.push(f); } };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const H = win.__mbhost;
  H.run('test', () => {}, () => {}, () => {}, () => {}, () => {});
  const asked = H.requestFrame;
  H.requestFrame = () => { said.push('frame asked'); asked(); };
  // the frames asked for drawn, as the display's next one comes
  const frame = () => { const fs = frames.splice(0); for (const f of fs) f(0); };
  return { H, win, said, frame, downloads, revoked, clock };
}

const task = () => new Promise((resolve) => setTimeout(resolve, 0));
const bytesOf = async (blob) => [...new Uint8Array(await blob.arrayBuffer())];

test('a file kept is the browser\'s download of every part as given, its name and type, kept once clicked', async () => {
  const b = browser();
  await task();
  b.frame();
  b.said.length = 0;
  const id = b.H.keepBegin('报告 2026.pdf', 'application/pdf', 1);
  assert.ok(id > 0, 'a keep begun');
  assert.equal(b.H.keepState(id), 0, 'keeping while its bytes come');
  // a part given as a view of memory used again after the call (the app's): what was given then is kept
  const memory = new Uint8Array([9, 9, 1, 2, 3, 9]);
  assert.equal(b.H.keepAppend(id, memory.subarray(2, 5)), 1);
  memory.fill(7);
  const second = new Uint8Array([4, 5]);
  assert.equal(b.H.keepAppend(id, second), 1);
  second.fill(0);
  assert.equal(b.H.keepState(id), 0, 'keeping till it is finished');
  assert.equal(b.downloads.length, 0, 'nothing downloaded before the finish');
  assert.equal(b.H.keepWhere(id), '');
  b.H.keepFinish(id);
  assert.equal(b.downloads.length, 1, 'one download as it is finished');
  const d = b.downloads[0];
  assert.equal(d.name, '报告 2026.pdf');
  assert.ok(d.inDocument, 'clicked in the document');
  assert.equal(d.blob.type, 'application/pdf');
  assert.deepEqual(await bytesOf(d.blob), [1, 2, 3, 4, 5], 'the bytes as they were given, in order');
  assert.equal(b.H.keepState(id), 1, 'kept once clicked');
  assert.equal(b.H.keepWhere(id), '报告 2026.pdf', 'where: its name, all the browser tells');
  assert.ok(b.said.includes('frame asked'), 'a frame asked for as it is kept');
  assert.equal(b.H.keepAppend(id, new Uint8Array([6])), 0, 'nothing appended once finished');
  assert.deepEqual(b.revoked, [], 'its URL not revoked in the click\'s task');
  b.H.keepEnd(id);
  assert.deepEqual(b.revoked, [], 'nor as it is let go: the download may still be reading it');
  assert.equal(b.H.keepState(id), 3, 'one let go is known no more');
});

test('a type not known is a download of bytes; a name is made one the download attribute takes', async () => {
  const b = browser();
  await task();
  const id = b.H.keepBegin('a/b\\c\u0007.txt', '', 2);
  b.H.keepAppend(id, new Uint8Array([1]));
  b.H.keepFinish(id);
  assert.equal(b.downloads[0].name, 'a_b_c.txt');
  assert.equal(b.downloads[0].blob.type, 'application/octet-stream');
  assert.equal(b.H.keepWhere(id), 'a_b_c.txt');
  const empty = b.H.keepBegin('', 'image/png', 3);
  b.H.keepFinish(empty);
  assert.equal(b.downloads[1].name, 'download', 'a picture into the album is the browser\'s download too');
  assert.deepEqual(await bytesOf(b.downloads[1].blob), []);
  assert.equal(b.H.keepState(empty), 1);
});

test('one let go unfinished downloads nothing, and the next is a keep of its own', async () => {
  const b = browser();
  await task();
  const id = b.H.keepBegin('half.bin', '', 1);
  b.H.keepAppend(id, new Uint8Array([1, 2]));
  b.H.keepEnd(id);
  assert.equal(b.downloads.length, 0, 'nothing downloaded');
  assert.equal(b.H.keepAppend(id, new Uint8Array([3])), 0, 'nothing appended to it after');
  b.H.keepFinish(id);
  assert.equal(b.downloads.length, 0, 'nor finished after');
  const next = b.H.keepBegin('whole.bin', '', 1);
  assert.notEqual(next, id, 'a fresh id');
  assert.equal(b.H.keepState(next), 0);
  b.H.keepAppend(next, new Uint8Array([8]));
  b.H.keepFinish(next);
  assert.equal(b.downloads.length, 1);
  assert.equal(b.downloads[0].name, 'whole.bin');
  assert.deepEqual(await bytesOf(b.downloads[0].blob), [8], 'none of the one let go in it');
});

test('a URL clicked is revoked as a later keep finishes a minute after it, never sooner', async () => {
  const b = browser();
  await task();
  b.frame();
  const one = b.H.keepBegin('one', '', 1);
  b.H.keepFinish(one);
  const two = b.H.keepBegin('two', '', 1);
  b.H.keepFinish(two);
  assert.deepEqual(b.revoked, [], 'two in one frame: neither revoked');
  b.frame();
  b.clock.ms = 59999;
  const soon = b.H.keepBegin('soon', '', 1);
  b.H.keepFinish(soon);
  assert.deepEqual(b.revoked, [], 'a later frame, within the minute: the browser may still be reading them');
  b.clock.ms = 60000;
  const three = b.H.keepBegin('three', '', 1);
  b.H.keepFinish(three);
  assert.deepEqual(b.revoked.sort(), [b.downloads[0].url, b.downloads[1].url].sort(), 'those a minute old, not the one a millisecond old');
  b.win.dispatch('pagehide', {});
  assert.ok(b.revoked.includes(b.downloads[2].url) && b.revoked.includes(b.downloads[3].url), 'the rest as the page goes');
});
