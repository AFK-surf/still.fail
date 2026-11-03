// Run a still.fail scene in Wasm with the same Core Text and Metal host used by the native picture exporter.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { compactStart } from './compact.mjs';
const started = performance.now();
function mark(stage) {
  if (process.env.MBUI_WASM_TRACE === '1') {
    const m = process.memoryUsage();
    const linear = core?.memory ? `, wasm ${Math.round(core.memory.buffer.byteLength / 1048576)} MiB` : '';
    console.error(`${stage}: ${Math.round(performance.now() - started)} ms, rss ${Math.round(m.rss / 1048576)} MiB${linear}`);
  }
}
const require = createRequire(import.meta.url);
const directory = path.dirname(fileURLToPath(import.meta.url));
const native = require(path.join(directory, 'native.node'));
const output = process.argv[2];
if (!output) throw new Error('app-picture.mjs OUTPUT.png');
const size = (process.env.MBUI_WIN ?? '390x844').split('x').map(Number);
const scale = Number(process.env.MBUI_FILM_SCALE ?? 2);
const platform = Number(process.env.MBUI_FILM_PLATFORM ?? 0);
const dark = process.env.MBUI_DARK === '1' ? 1 : 0;
const at = Number(process.env.MBUI_PICTURE_AT ?? 0);
const fps = Number(process.env.MBUI_FILM_FPS ?? 60);
const max = Number(process.env.MBUI_FILM_FRAMES ?? 3000);
const frame = process.env.MBUI_PICTURE_FRAME ? Number(process.env.MBUI_PICTURE_FRAME) : -1;
const fontScale = Number(process.env.MBUI_FONT_SCALE ?? 0);
const inset = process.env.MBUI_FILM_INSET === '1' ? 1 : 0;
const corner = Number(process.env.MBUI_FILM_WINDOW_CORNER ?? 0);
const nav = process.env.MBUI_FILM_NAV_ABLE === '1' ? 1 : 0;
const wholeMs = s => /^\d+$/.test(s ?? '') ? Number(s) : 0;
const coreMs = wholeMs(process.env.MBUI_CORE_MS);
const updatesMs = process.env.MBUI_UPDATES_MS ? wholeMs(process.env.MBUI_UPDATES_MS) : -1;
if (size.length !== 2 || !size.every(n => Number.isFinite(n) && n > 0) || !Number.isFinite(scale) || scale <= 0)
  throw new Error('invalid picture dimensions');
if (![platform, at, fps, max, frame, fontScale, corner].every(Number.isFinite) || at < 0 || fps <= 0 || max <= 0 || frame < -1 || (frame >= 0 && at > 0))
  throw new Error('invalid picture timing');
const script = name => {
  const file = process.env[name];
  if (!file) return '';
  const s = fs.readFileSync(file, 'utf8');
  if (!s) throw new Error(`empty scene script: ${file}`);
  return s;
};
const prepare = script('MBUI_FILM_PREPARE'), drive = script('MBUI_FILM_DRIVE');
if (frame >= 0 && !drive) throw new Error('a frame requires a scene script');
const strings = [process.env.MBUI_FIXTURE ?? '', process.env.MBUI_LOCALE ?? '', process.env.MBUI_DARK ?? '', prepare, drive,
  process.env.MBUI_POINTING ?? '', process.env.MBUI_NATIVE_INPUT ?? '', process.env.MBUI_KEYBOARD ?? '',
  process.env.MBUI_LOCAL_STATION ?? '', process.env.MBUI_WINDOW ?? '', process.env.MBUI_HOLD ?? '',
  process.env.MBUI_FAILED ?? '', process.env.MBUI_FAILED_WHY ?? '', process.env.MBUI_SAID ?? '',
  process.env.MBUI_UPDATE ?? '', process.env.MBUI_FILM_AUTOFILL ?? ''].map(s => Array.from(s, c => c.codePointAt(0)));
const numbers = [size[0], size[1], scale, platform, dark, at, fps, max, frame, fontScale, inset, corner, nav, coreMs, updatesMs];
let core, scratch = [], pixels;
function text() {
  const n = core.text_length();
  let s = '';
  for (let start = 0; start < n; start += 1024) {
    const values = [];
    for (let i = start; i < Math.min(n, start + 1024); i++) values.push(core.text_unit(i));
    s += String.fromCharCode(...values);
  }
  return s;
}
function bytes() {
  const b = Buffer.allocUnsafe(core.bytes_length());
  for (let i = 0; i < b.length; i++) b[i] = core.bytes_unit(i);
  return b;
}
const probe = {
  metrics(size, weight, style) { scratch = native.metrics(size, weight, style); },
  shape(size, weight, style, capacity) { scratch = native.shape(text(), size, weight, style, capacity); return scratch.length / 4; },
  textKey(size, weight, style) { return native.textKey(text(), size, weight, style); },
  glyph(key) { scratch = native.glyph(key); }, glyphPut: native.glyphPut,
  faceAdd(face, weight) { return !!native.facePath(face, text(), weight); },
  faceAddBytes(face, weight) { return !!native.face(face, bytes(), weight); },
  faceAddFamily(face) { return !!native.faceFamily(face, text()); },
  faceClear: native.faceClear, atlasSize: native.atlasSize, atlasGeneration: native.atlasGeneration,
  imageLoad(max) { if (process.env.MBUI_WASM_TRACE === '1') console.error('load image from source'); return native.imageLoad(text(), max); },
  imageBytes(max) { const data = bytes(); if (process.env.MBUI_WASM_TRACE === '1') console.error(`load image bytes: ${data.length}`); return native.imageBytes(data, max); },
  imageInfo(id) { const info = native.imageInfo(id); scratch = info.subarray(1); return info[0]; },
  imagePixels(id, capacity) { pixels = native.imagePixels(id, capacity); return pixels ? pixels.length : -1; },
  imagePixelAt(i) { return pixels[i]; }, imageFree: native.imageFree,
  turn: native.turn, view: native.view,
  result(i) { return scratch[i]; },
  optionLength(k) { return strings[k].length; }, optionPoint(k, i) { return strings[k][i]; }, optionNumber(k) { return numbers[k]; },
};
const imports = { probe, wasi_snapshot_preview1: { fd_write(fd, iovs, count, written) {
  const memory = new DataView(core.memory.buffer); let total = 0;
  for (let i = 0; i < count; i++) {
    const ptr = memory.getUint32(iovs + i * 8, true), len = memory.getUint32(iovs + i * 8 + 4, true);
    (fd === 2 ? process.stderr : process.stdout).write(Buffer.from(core.memory.buffer, ptr, len)); total += len;
  }
  memory.setUint32(written, total, true); return 0;
} } };
const source = fs.readFileSync(path.join(directory, 'scene.wasm'));
mark('read');
if (!WebAssembly.validate(source)) throw new Error('invalid source Wasm module');
const wasm = compactStart(source);
if (!WebAssembly.validate(wasm)) throw new Error('invalid compacted Wasm module');
mark('compact');
const module = await WebAssembly.compile(wasm);
mark('compile');
core = new WebAssembly.Instance(module, imports).exports;
mark('instantiate');
native.init(size[0], size[1], scale);
mark('renderer');
try {
  const n = core.draw();
  mark('scene');
  if (n < 0) throw new Error('the scene did not pass picture checks');
  const inst = new Float64Array(n * 60);
  for (let i = 0; i < inst.length; i++) inst[i] = core.item(i);
  mark('transfer');
  native.draw(inst, n, core.background(0), core.background(1), core.background(2));
  const saved = process.env.MBUI_PICTURE_TRANSPARENT === '1' ? native.snapshotTransparent(output) : native.snapshot(output);
  if (!saved) throw new Error(`could not write ${output}`);
  mark('png');
  console.log(`picture: ${output} (${Math.round(size[0] * scale)} × ${Math.round(size[1] * scale)})`);
} finally { core.done(); mark('done'); }
