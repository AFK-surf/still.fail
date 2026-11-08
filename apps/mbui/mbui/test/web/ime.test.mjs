// What a phone's input method and soft keyboard do to the browser host's field and page, without a browser: voice
// input replaces its guess as it hears more, and the app is told the edit, not every guess one after another; the soft
// keyboard ends the visual viewport above it, and the app is laid out above it; Safari's Done lets the field go.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/host.js', import.meta.url), 'utf8');

function browser() {
  const queued = [], frames = [], texts = [];
  const element = () => ({
    style: {}, listeners: new Map(),
    addEventListener(name, f) { this.listeners.set(name, [...(this.listeners.get(name) || []), f]); },
    dispatch(name, e = {}) { for (const f of this.listeners.get(name) || []) f(e); },
  });
  const gl = new Proxy({}, { get: (_, name) => {
    if (name === 'getShaderParameter' || name === 'getProgramParameter') return () => true;
    return () => ({});
  } });
  const canvas = { ...element(), width: 0, height: 0, getContext: () => gl,
    getBoundingClientRect: () => ({ width: 400, height: 300, left: 0, top: 0 }) };
  const document = { activeElement: null, createElement: () => ({ ...element(), getContext: () => ({}) }),
    getElementById: (id) => id === 'c' ? canvas : ta, addEventListener() {} };
  // (a textarea's words, selection and focus)
  const ta = { ...element(), value: '', selectionStart: 0, selectionEnd: 0,
    setSelectionRange(s, e) { this.selectionStart = s; this.selectionEnd = e; },
    focus() { document.activeElement = this; },
    blur() { if (document.activeElement === this) { document.activeElement = null; this.dispatch('blur'); } } };
  const visualViewport = { ...element(), height: 300, offsetTop: 0, scale: 1 };
  const win = { ...element(), document, navigator: { platform: 'iPhone' }, location: { search: '' }, URLSearchParams,
    Intl, devicePixelRatio: 1, performance: { now: () => 0 }, requestAnimationFrame: (f) => queued.push(f),
    visualViewport, matchMedia: () => ({ addEventListener() {}, removeEventListener() {} }) };
  win.window = win;
  vm.runInNewContext(source, win, { filename: 'host.js' });
  const host = win.__mbhost;
  host.run('test', (w, h) => frames.push(h), () => {}, () => {}, () => {}, (kind, s, a, b) => texts.push([kind, s, a, b]));
  // The field's words as the app has them from what it was told (text kinds 3, the range a to b taken out, the caret
  // left there; 0, s put in at the caret), as src/ui's editor and ios_app.m's replaceRange:withText: do.
  let app = '', caret = 0;
  const told = () => {
    for (const [kind, s, a, b] of texts.splice(0)) {
      if (kind === 3) { app = app.slice(0, a) + app.slice(b); caret = a; }
      if (kind === 0) { app = app.slice(0, caret) + s + app.slice(caret); caret += s.length; }
    }
    return app;
  };
  // What the input method does to the textarea, and the input event it then sends.
  const edit = (from, to, put, inputType) => {
    ta.value = ta.value.slice(0, from) + put + ta.value.slice(to);
    ta.setSelectionRange(from + put.length, from + put.length);
    ta.dispatch('input', { inputType, data: put || null, isComposing: false });
  };
  // the field's words and selection as the app says them (setIme), its own model of them starting there
  const ime = (text = '', s = 0, e = s) => { host.setIme(true, 0, 0, 100, 20, text, s, e); app = text; caret = s; };
  const draw = () => { assert.equal(queued.length, 1, 'one frame requested'); queued.shift()(0); return frames.at(-1); };
  return { ta, document, visualViewport, texts, ime, told, edit, draw };
}

test('voice input that replaces its last guess writes the sentence once', () => {
  const b = browser();
  b.ime();
  let prev = '';
  for (const next of ['今天', '今天天气', '今天天气真不错 👋']) {
    // iOS's dictation: its last guess selected, the next inserted over it (WebPage::replaceDictatedText)
    const end = b.ta.selectionStart;
    b.edit(end - prev.length, end, next, 'insertText');
    prev = next;
  }
  assert.equal(b.told(), '今天天气真不错 👋');
});

test('voice input that deletes its guess key by key writes the sentence once', () => {
  const b = browser();
  b.ime();
  let prev = '';
  for (const next of ['今天', '今天天气', '今天天气真不错']) {
    // a keyboard's own deletes (deleteContentBackward, no key event), then the next guess typed
    for (let i = 0; i < prev.length; i++) b.edit(b.ta.selectionStart - 1, b.ta.selectionStart, '', 'deleteContentBackward');
    b.edit(b.ta.selectionStart, b.ta.selectionStart, next, 'insertText');
    prev = next;
  }
  assert.equal(b.told(), '今天天气真不错');
});

test('a correction replaces its word', () => {
  const b = browser();
  b.ime('teh cat', 3);
  b.edit(0, 3, 'the', 'insertReplacementText');
  assert.equal(b.told(), 'the cat');
});

test('the soft keyboard over the page lays the app out above it, and Done lets the field go', async () => {
  const b = browser();
  await Promise.resolve(); // H.run requests its first frame once the decoder's answer is known.
  assert.equal(b.draw(), 300);
  // A phone's keyboard changes no size of the page's, only the visual viewport's; that asks for a frame itself.
  b.visualViewport.height = 300 - 120;
  b.visualViewport.dispatch('resize');
  assert.equal(b.draw(), 180, 'laid out above the keyboard');
  b.ime();
  assert.equal(b.document.activeElement, b.ta);
  b.texts.length = 0;
  // Safari's Done: the keyboard put away by the person, the field blurred
  b.ta.blur();
  assert.deepEqual(b.texts.map(([k]) => k), [7], 'the app told the field let go');
  b.visualViewport.height = 300;
  b.visualViewport.dispatch('resize');
  assert.equal(b.draw(), 300, 'the whole canvas once the keyboard is gone');
});
