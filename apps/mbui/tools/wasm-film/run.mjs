// Run a still.fail scene in Wasm with the same Core Text, Metal and film writer host as the native exporter: a picture
// (MBUI_PICTURE, drawn here), or a film (MBUI_FILM: mbui's own film, src/film, run in the scene over this host).
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
if (!output) throw new Error('run.mjs OUTPUT.png|OUTPUT.mp4');
const filming = !!process.env.MBUI_FILM;
const size = (process.env.MBUI_WIN ?? '390x844').split('x').map(Number);
const scale = Number(process.env.MBUI_FILM_SCALE ?? 2);
const platform = Number(process.env.MBUI_FILM_PLATFORM ?? 0);
const dark = process.env.MBUI_DARK === '1' ? 1 : 0;
const jsonNumber = s => { try { const n = JSON.parse(s); return typeof n === 'number' ? n : NaN; } catch { return NaN; } };
const at = jsonNumber(process.env.MBUI_PICTURE_AT || '0');
const fps = jsonNumber(process.env.MBUI_FILM_FPS || '60');
const max = Number(process.env.MBUI_FILM_FRAMES ?? 3000);
const hasFrame = !!process.env.MBUI_PICTURE_FRAME;
const frame = hasFrame ? jsonNumber(process.env.MBUI_PICTURE_FRAME) : -1;
const fontScale = Number(process.env.MBUI_FONT_SCALE ?? 0);
const inset = process.env.MBUI_FILM_INSET === '1' ? 1 : 0;
const corner = Number(process.env.MBUI_FILM_WINDOW_CORNER ?? 0);
const nav = process.env.MBUI_FILM_NAV_ABLE === '1' ? 1 : 0;
const cornersKept = process.env.MBUI_FILM_ALLOW_CORNER_FAULTS === '1' ? 1 : 0;
if (size.length !== 2 || !size.every(n => Number.isFinite(n) && n > 0) || !Number.isFinite(scale) || scale <= 0)
  throw new Error('invalid picture dimensions');
if (![platform, at, fps, max, frame, fontScale, corner].every(Number.isFinite) || at < 0 || max <= 0 ||
    !Number.isInteger(fps) || fps < 1 || fps > 2147483647 ||
    (hasFrame && (!Number.isInteger(frame) || frame < 0 || frame > 2147483647 || at > 0)))
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
const fixtureJson = process.env.MBUI_FIXTURE_JSON_FILE ? fs.readFileSync(process.env.MBUI_FIXTURE_JSON_FILE, 'utf8') : (process.env.MBUI_FIXTURE_JSON ?? '');
const strings = [process.env.MBUI_FIXTURE ?? '', process.env.MBUI_LOCALE ?? '', process.env.MBUI_DARK ?? '', prepare, drive,
  process.env.MBUI_POINTING ?? '', process.env.MBUI_NATIVE_INPUT ?? '', process.env.MBUI_KEYBOARD ?? '',
  process.env.MBUI_LOCAL_STATION ?? '', process.env.MBUI_WINDOW ?? '', process.env.MBUI_HOLD ?? '',
  process.env.MBUI_FAILED ?? '', process.env.MBUI_FAILED_WHY ?? '', process.env.MBUI_SAID ?? '',
  process.env.MBUI_UPDATE ?? '', process.env.MBUI_FILM_AUTOFILL ?? '',
  process.env.MBUI_CORE_MS ?? '', process.env.MBUI_UPDATES_MS ?? '',
  process.env.MBUI_FIX_PACE ?? '', process.env.MBUI_FIX_CORE ?? '', fixtureJson].map(s => Array.from(s, c => c.codePointAt(0)));
const numbers = [size[0], size[1], scale, platform, dark, at, fps, max, frame, fontScale, inset, corner, nav, cornersKept];
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
// The film's needs (src/film/film_wasm.mbt): a string out read through the program's film_text exports, one back a unit
// at a time; a frame's instances through film_item; the writer and the renderer the Mac host's.
class Exit {
  constructor(code) { this.code = code; }
}
let got = '', held = '';
function filmText() {
  const n = core.film_text_length();
  let s = '';
  for (let start = 0; start < n; start += 1024) {
    const values = [];
    for (let i = start; i < Math.min(n, start + 1024); i++) values.push(core.film_text_unit(i));
    s += String.fromCharCode(...values);
  }
  return s;
}
const film = {
  gotLength: () => got.length,
  gotUnit: i => got.charCodeAt(i),
  hold() { held = filmText(); },
  arg() { got = process.env[filmText()] ?? ''; },
  say() { process.stderr.write(`${filmText()}\n`); },
  read() { try { got = fs.readFileSync(filmText(), 'utf8'); } catch { got = ''; } },
  write() { try { fs.writeFileSync(held, filmText()); return 1; } catch { return 0; } },
  exit(code) { throw new Exit(code); },
  init: (w, h, s) => native.init(w, h, s),
  view: (w, h, s) => native.view(w, h, s),
  open: (w, h, fps) => native.filmOpen(filmText(), w, h, fps),
  draw(count, r, g, b) {
    const inst = new Float64Array(count * 60);
    for (let i = 0; i < inst.length; i++) inst[i] = core.film_item(i);
    return native.filmDraw(inst, count, r, g, b);
  },
  put: k => native.filmPut(k),
  close: n => native.filmClose(n),
  finish: p => native.filmFinish(p),
  snapshot: transparent => (transparent ? native.snapshotTransparent(filmText()) : native.snapshot(filmText())),
  spin: () => native.turn(),
  now: () => performance.now(),
  // (a bench's measured frame begun or ended: counted only by a profiling host, mbui's wasm_shell.c)
  mark() {},
};
// The core's env as moonrun gives it ("__moonbit_fs_unstable" & co., mbui's scripts/wasmrun.mjs): mbui's ui reads its
// Tester's frame rate there (MBUI_TEST_FPS, tester_time.mbt), so every program of it asks for them. A film's program has
// no arguments or environment of its own: none here (its words come through film.arg). Without them the film did not
// start, main e9649951, 42623942152.
const END = 'ffi_end_of_/string_array';
const handles = new Map();
let handled = 0;
const handle = v => {
  handles.set(++handled, v);
  return handled;
};
const fsUnstable = {
  begin_create_string: () => handle({ s: '' }),
  string_append_char: (h, c) => { handles.get(h).s += String.fromCharCode(c); },
  finish_create_string: h => { const { s } = handles.get(h); handles.delete(h); return s; },
  begin_read_string: s => handle({ s: Array.from(s), i: 0 }),
  string_read_char: h => { const r = handles.get(h); return r.i < r.s.length ? r.s[r.i++].codePointAt(0) : -1; },
  finish_read_string: h => { handles.delete(h); },
  begin_read_string_array: a => handle({ a, i: 0 }),
  string_array_read_string: h => { const r = handles.get(h); return r.i < r.a.length ? r.a[r.i++] : END; },
  finish_read_string_array: h => { handles.delete(h); },
  args_get: () => [],
  current_dir: () => '',
  get_env_var: () => '',
  get_env_var_exists: () => 0,
  get_env_vars: () => [],
  set_env_var() {},
  unset_env_var() {},
};
// The core's host (stillfail/core's native_wasm.mbt, "mbhost"): a film has no engine, its core the fixture's, so each
// answers as core_native.c does with none given it (mbc_use never called): not started, nothing sent, no sign-in. The
// film's program links them since a test's late core serves the app's client (sffixture's round_trip_again, #5212):
// without them the film did not start, mbui-media-runtime 42753280921, 2026-11-10.
const mbhost = {
  mbc_start: () => 0,
  mbc_send() {},
  mbc_send_bytes() {},
  mbc_stop() {},
  mbc_has_web_auth: () => 0,
  mbc_web_auth: () => 0,
  mbc_now_ms: () => performance.now(),
  mbc_wall_ms: () => Date.now(),
  mbc_screen_ack: () => 0,
  mbc_auth_scheme() { throw new Error('a film signs in to nothing: no auth scheme'); },
};
const imports = { probe, film, mbhost, __moonbit_fs_unstable: fsUnstable, __moonbit_sys_unstable: { exit(code) { throw new Exit(code); } },
  __moonbit_time_unstable: { now: () => BigInt(Date.now()) }, wasi_snapshot_preview1: { fd_write(fd, iovs, count, written) {
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
if (filming) {
  let code = 1;
  try {
    core.film();
  } catch (e) {
    if (e instanceof Exit) code = e.code;
    else throw e;
  }
  mark('film');
  process.exit(code);
}
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
