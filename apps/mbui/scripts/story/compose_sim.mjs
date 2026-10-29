// Film 1 as the iPhone Duo simulator showed it (scripts/story/film_ios.sh): its two screens' recordings
// (rec/ios-outer.mp4 till the unfold, rec/ios-inner.mp4 from just before it, the inner one recorded on its side) put on
// one time line by rec/ios-times.txt and the app's log (rec/ios-app.txt: where the drive touched), on Apple's model
// folded and unfolded (duo3d/film.html), from a camera on the drive's marks (iduo-sim.cam3d.js), into
// out/film/promo3d-sim.mp4; `node compose_sim.mjs [still times…]` only those, as out/stills/promo3d-sim-N.png (a time:
// seconds, or a mark ± seconds: answer+0.8).
import { execFileSync, spawn } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { filmSound } from './sound.mjs';
const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '../..');
// (FILM_REC: another take's recordings, rec-en's the English film's; FILM_NAME what the film is called in out/film)
const rec = join(here, process.env.FILM_REC || 'rec');
const NAME = process.env.FILM_NAME || 'promo3d-sim';
const stills = process.argv.slice(2);
const FFMPEG = '/opt/homebrew/bin/ffmpeg', FPS = 60;
const ASSETS = process.env.DUO_ASSETS || join(app, 'out/duo3d-assets');

// ---- one time line: the film's 0 the drive's start; each recording's frames at this Mac's clock ----
const times = readFileSync(join(rec, 'ios-times.txt'), 'utf8').trim().split('\n').map((l) => l.split(' '));
const at = times.filter((l) => l[0] === 'at').map(([, wall, ms, ...name]) => ({ wall: +wall, app: +ms / 1000, name: name.join(' ') }));
// (the app's clock to this Mac's: as soon as a line was seen, the least of how late each was)
const off = Math.min(...at.map((a) => a.wall - a.app));
const start = at.find((a) => a.name === 'start').app;
const wallOf = (t) => start + off + t;
const marks = Object.fromEntries(at.map((a) => [a.name, a.app - start]));
const recStart = Object.fromEntries(times.filter((l) => l[0] === 'rec').map(([, k, w]) => [k, +w]));
// (a take on the outer screen alone, never unfolded: no swap, the phone folded throughout)
const swap = times.find((l) => l[0] === 'fold');
const foldDone = swap ? +swap[1] - (start + off) : Infinity;
// the phone opened on the model as SpringBoard opened it (its swap 0.64 s, answered as it ended), flat FLIP later
const FLIP = 1.1, U = foldDone - 0.64 - 0.15;
marks.unfold3d = U;
// (the end: the last of the recording held a while, the phone going away after it)
const END = marks.end - 0.2;

// where the drive touched: its taps (a tap's place on the log after its mark) and drags, in points of the screen in use
const log = readFileSync(join(rec, 'ios-app.txt'), 'utf8').split('\n');
const touches = [];
let lastAt = null;
for (const line of log) {
  let m = line.match(/^DRIVE AT ([\d.]+) /);
  if (m) { lastAt = +m[1] / 1000 - start; continue; }
  m = line.match(/^DRIVE tap(?:xy)? .* at ([\d.]+),([\d.]+)$/);
  if (m && lastAt !== null) touches.push({ t: lastAt, x: +m[1], y: +m[2], dx: 0, dy: 0, ms: 90 });
  m = line.match(/^DRIVE (?:drag|dragon) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+)?.* from ([\d.]+),([\d.]+)$/);
  // (none before the film's start: what readies the screen for it)
  if (m && lastAt !== null) {
    const drag = line.startsWith('DRIVE drag ');
    const [dx, dy, ms] = drag ? [+m[3], +m[4], 350] : [+m[1], +m[2], +m[3]];
    touches.push({ t: lastAt, x: +m[5], y: +m[6], dx, dy, ms });
  }
}
const OUTER = [466, 678], INNER = [951, 669];
// the touches on the screen in use at t, as a recording with its touches shown has them, a little more marked: a disc
// where the finger is (in over 60 ms, held at least 180 ms, out over 300 ms as a ring opens round it), and behind a
// drag the way it came, fading: [x, y] of the screen's width and height, how far down (0 to 1), how far lifted (0 to 1)
// and the way behind it
const HOLD = 0.18, LIFT = 0.3;
function touchesAt(t, size) {
  const out = [];
  for (const k of touches) {
    const t0 = k.t + 0.08, t1 = t0 + Math.max(HOLD, k.ms / 1000), tm = t0 + k.ms / 1000;
    if (t < t0 - 0.06 || t > t1 + LIFT) continue;
    const down = Math.min(1, Math.max(0, (t - t0 + 0.06) / 0.06));
    const lift = t > t1 ? Math.min(1, (t - t1) / LIFT) : 0;
    const at = (u) => { const p = Math.min(1, Math.max(0, (u - t0) / Math.max(1e-3, tm - t0))); const e = 1 - (1 - p) ** 2; return [(k.x + k.dx * e) / size[0], (k.y + k.dy * e) / size[1]]; };
    const trail = [];
    if (k.dx || k.dy) for (let u = Math.max(t0, Math.min(t, tm) - 0.25); u <= Math.min(t, tm); u += 1 / 120) trail.push(at(u));
    out.push({ at: at(t), down, lift, trail });
  }
  return out;
}
const taps = touches.map((k) => k.t + 0.08);
// the letters a `keys` step typed (DRIVE KEY <ms> <letter>), each a finger on its key of the inner screen's keyboard as
// iOS lays it out held open (its points, as the recording shows it), a capital's shift a moment before it
const KEYBOARD = (() => {
  const k = {};
  const row = (letters, x0, y) => [...letters].forEach((l, i) => { k[l] = [x0 + i * 79.4, y]; });
  row('qwertyuiop', 116, 469); row('asdfghjkl', 156, 521); row('zxcvbnm', 235, 573);
  k[' '] = [474, 626]; k.shift = [128, 573];
  return k;
})();
const keys = [];
for (const line of log) {
  const m = line.match(/^DRIVE KEY ([\d.]+) (.)$/);
  if (!m) continue;
  const t = +m[1] / 1000 - start, l = m[2];
  const at = KEYBOARD[l.toLowerCase()];
  if (!at) continue;
  if (l !== l.toLowerCase()) touches.push({ t: t - 0.1, x: KEYBOARD.shift[0], y: KEYBOARD.shift[1], dx: 0, dy: 0, ms: 50 });
  touches.push({ t: t - 0.08, x: at[0], y: at[1], dx: 0, dy: 0, ms: 60 });
  keys.push(t);
}

// ---- the recordings' frames at 60 a second, the inner one turned upright (as the screen is held: landscape) ----
const frames = join(app, 'out/sim-frames', process.env.FILM_REC || 'rec');
// (made again for another recording under the same name: its size and time kept with them)
const stamp = (k) => { const s = statSync(join(rec, `ios-${k}.mp4`)); return `${s.size} ${s.mtimeMs}`; };
const need = (k) => !existsSync(join(frames, k, '1.jpg')) || !existsSync(join(frames, `${k}.stamp`)) ||
  readFileSync(join(frames, `${k}.stamp`), 'utf8') !== stamp(k);
for (const [k, vf] of [['outer', `fps=${FPS}`], ['inner', `transpose=1,fps=${FPS}`]]) {
  if (!existsSync(join(rec, `ios-${k}.mp4`)) || !need(k)) continue;
  rmSync(join(frames, k), { recursive: true, force: true });
  mkdirSync(join(frames, k), { recursive: true });
  execFileSync(FFMPEG, ['-loglevel', 'error', '-i', join(rec, `ios-${k}.mp4`), '-vf', vf, '-q:v', '2', '-start_number', '0', join(frames, k, '%d.jpg')]);
  writeFileSync(join(frames, `${k}.stamp`), stamp(k));
}
const count = (k) => existsSync(join(frames, k)) ? readdirSync(join(frames, k)).length : 0;
const nOuter = count('outer'), nInner = count('inner');
const frameOf = (k, t, n) => Math.min(n - 1, Math.max(0, Math.round((wallOf(t) - recStart[k]) * FPS)));
// (the outer screen held at its last before the unfold; the inner one, while the phone opens, at the swap's end)
const outerAt = (t) => frameOf('outer', Math.min(t, U), nOuter);
const innerAt = (t) => frameOf('inner', Math.max(t, foldDone + 0.05), nInner);

const when = (a) => { const m = a.match(/^(.*?)([+-][\d.]+)?$/); return isNaN(Number(a)) ? marks[m[1]] + Number(m[2] || 0) : Number(a); };
// (FILM_FROM: the film from that moment of the take, a mark and how long after it: what came before it left out)
const FROM = process.env.FILM_FROM ? when(process.env.FILM_FROM) : 0;
marks.from = FROM;
// (FILM_CAM: another film's camera, by its marks)
const cams = (await import(pathToFileURL(join(here, process.env.FILM_CAM || 'iduo-sim.cam3d.js')))).default(marks);
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const ease = (x) => { x = clamp(x); return x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const keyed = (fr, t) => {
  if (t <= fr[0][0]) return fr[0].slice(1);
  for (let i = 1; i < fr.length; i++) {
    if (t <= fr[i][0]) { const a = fr[i - 1], b = fr[i], k = ease((t - a[0]) / (b[0] - a[0])); return a.slice(1).map((v, j) => v + (b[j + 1] - v) * k); }
  }
  return fr[fr.length - 1].slice(1);
};
const angleAt = (t) => 180 * ease((t - U) / FLIP);

const types = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.usdc': 'application/octet-stream', '.avif': 'image/avif' };
const server = createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = p.startsWith('/duo3d/assets/') ? join(ASSETS, p.slice('/duo3d/assets/'.length))
    : p.startsWith('/frames/') ? join(frames, p.slice(8)) : join(here, p);
  if (!existsSync(file) || statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
  createReadStream(file).pipe(res);
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const base = `http://127.0.0.1:${server.address().port}/`;
const require = createRequire(join(process.env.PW_FROM || app, 'x.js'));
const { chromium } = require('playwright-core');
const browser = await chromium.launch({ channel: 'chrome', args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
// (drawn at 4K, 3840 × 2160: the page's 1920 × 1080 at twice its pixels; FILM_SCALE=1 for 1080p)
const SCALE = Number(process.env.FILM_SCALE || 2);
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: SCALE });
page.on('pageerror', (e) => console.error('3d:', e.message));
await page.goto(`${base}duo3d/film.html`);
await page.waitForFunction(() => window.ready3d === true, null, { timeout: 120000 });
if (process.env.FILM_END_LINE) await page.evaluate((w) => { document.getElementById('endline').textContent = w; }, process.env.FILM_END_LINE);
// FILM_DESK: a computer's window beside the phone (the film's desktop Slack, slack/desk/desk.html: build.mjs), live in
// the picture: its page in a frame of the film's, told each frame where the film is (window.at(t, marks): FILM_DESK_MARKS
// names them, {"ana": "start+0.4", …}), so what moves in it (a key, the caret, the pointer) moves as the film goes
const DESK = process.env.FILM_DESK || '';
let deskMarks = {};
if (DESK) {
  const named = JSON.parse(process.env.FILM_DESK_MARKS || '{}');
  deskMarks = Object.fromEntries(Object.entries(named).map(([k, v]) => [k, when(v)]));
  await page.evaluate(async (url) => {
    const d = document.getElementById('desk');
    d.replaceChildren();
    const f = document.createElement('iframe');
    f.id = 'deskframe';
    f.style.cssText = 'position:absolute;left:0;top:0;width:1272px;height:813px;border:0;transform-origin:0 0;transform:scale(' + (900 / 1272) + ')';
    d.append(f);
    await new Promise((ok) => { f.onload = ok; f.src = url; });
    await f.contentDocument.fonts.ready;
    // (every face of its fonts loaded now: one first needed mid-film, a letter or a weight not yet used, would leave its
    // words blank while it loads)
    await Promise.all([...f.contentDocument.fonts].map((face) => face.load().catch(() => null)));
  }, `${base}${DESK}`);
  keys.push(...(await page.evaluate((m) => document.getElementById('deskframe').contentWindow.deskKeys?.(m) ?? [], deskMarks)));
}
// (FILM_CAPTIONS: a line under the picture as the film goes, by its marks: [from, to, words] each, iduo-slack-captions.js;
// FILM_END_LINE: the end card's line under the name)
const captions = process.env.FILM_CAPTIONS ? (await import(pathToFileURL(join(here, process.env.FILM_CAPTIONS)))).default(marks) : [];
const captionAt = (t) => {
  const c = captions.find(([a, b]) => t >= a - 0.25 && t <= b + 0.25);
  return c ? { words: c[2], o: clamp(Math.min(t - c[0], c[1] - t) / 0.25 + 1) } : { words: '', o: 0 };
};
const views = process.env.FILM_DESK_VIEW ? (await import(pathToFileURL(join(here, process.env.FILM_DESK_VIEW)))).default(marks) : null;
const deskAt = (t) => {
  const [ds, dx, dy, vx] = views ? keyed(views, t) : [1, 0, 0, 470];
  return { t, marks: deskMarks, ds, dx, dy, vx };
};
async function draw(t) {
  const a = angleAt(t);
  const s = {
    outer: a < 180 ? `${base}frames/outer/${outerAt(t)}.jpg` : null,
    inner: a > 0 ? `${base}frames/inner/${innerAt(t)}.jpg` : null,
  };
  const tc = { outer: t < U ? touchesAt(t, OUTER) : [], inner: t > U ? touchesAt(t, INNER) : [] };
  const desk = DESK ? deskAt(t) : null;
  const cap = captionAt(t);
  await page.evaluate(async ([s, angle, cam, endT, tc, desk, cap]) => {
    const ce = document.getElementById('cap');
    if (ce.textContent !== cap.words) ce.textContent = cap.words;
    ce.style.opacity = String(cap.o * (1 - Math.min(1, Math.max(0, endT))));
    if (desk) {
      const d = document.getElementById('desk');
      d.style.display = 'block';
      document.getElementById('viewport').style.transform = `translateX(${desk.vx}px)`;
      d.style.transformOrigin = '0 0';
      d.style.transform = `translate(${desk.dx}px, ${desk.dy}px) scale(${desk.ds})`;
      const w = document.getElementById('deskframe').contentWindow;
      w.at(desk.t, desk.marks);
      // (its new state painted before the picture is taken: what changed laid out and drawn, its words too)
      await new Promise((ok) => w.requestAnimationFrame(() => w.requestAnimationFrame(() => w.requestAnimationFrame(ok))));
      // (and its words rastered: drawn at the camera's scale, a changed line's tiles come a moment after the frame)
      await new Promise((ok) => setTimeout(ok, 80));
    }
    await window.frame3d({ outer: s.outer, inner: s.inner, angle, cam, touches: tc });
    const e = Math.min(1, Math.max(0, endT));
    document.getElementById('viewport').style.opacity = String(1 - e);
    document.getElementById('desk').style.opacity = String(1 - e);
    document.getElementById('end').style.opacity = String(Math.min(1, Math.max(0, (endT - .55) / .9)));
  }, [s, a, keyed(cams, t), (t - END) / .9, tc, desk, cap]);
}
if (stills.length) {
  mkdirSync(join(app, 'out/stills'), { recursive: true });
  for (const [i, a] of stills.entries()) {
    await draw(when(a));
    await page.screenshot({ path: join(app, `out/stills/${NAME}-${i + 1}.png`) });
    console.log('still', i + 1, a, when(a).toFixed(2));
  }
} else {
  const n = Math.round((END - FROM + 1.5) * FPS);
  // its sound, on the same marks from where it starts (sound.mjs): what came before left out
  const later = Object.fromEntries(Object.entries(marks).filter(([, v]) => v >= FROM).map(([k, v]) => [k, v - FROM]));
  const wav = join(app, 'out/film/' + NAME + '.wav');
  filmSound({ seconds: n / FPS, marks: later, taps: taps.filter((t) => t >= FROM).map((t) => t - FROM),
    keys: keys.filter((t) => t >= FROM).map((t) => t - FROM), unfold: U - FROM, flip: FLIP,
    end: END - FROM, out: wav + '.raw.wav' });
  // (as loud as films are played: -16 LUFS)
  execFileSync(FFMPEG, ['-loglevel', 'error', '-y', '-i', wav + '.raw.wav', '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', '48000', wav]);
  const ff = spawn(FFMPEG, ['-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-', '-i', wav,
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-preset', 'slow', '-c:a', 'aac', '-b:a', '192k', '-shortest',
    '-movflags', '+faststart', join(app, 'out/film/' + NAME + '.mp4')], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let f = 0; f < n; f++) {
    await draw(FROM + f / FPS);
    const jpg = await page.screenshot({ type: 'jpeg', quality: 93 });
    if (!ff.stdin.write(jpg)) await new Promise((ok) => ff.stdin.once('drain', ok));
    if (f % 300 === 0) console.log(`compose_sim: ${f}/${n}`);
  }
  ff.stdin.end();
  await new Promise((ok, no) => ff.on('close', (c) => (c === 0 ? ok() : no(new Error('ffmpeg ' + c)))));
  // and at 2K (2560 × 1440) from it where asked (FILM_2K=1)
  if (SCALE >= 2 && process.env.FILM_2K === '1') {
    execFileSync(FFMPEG, ['-loglevel', 'error', '-y', '-i', join(app, 'out/film/' + NAME + '.mp4'), '-vf', 'scale=2560:1440:flags=lanczos',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-preset', 'slow', '-c:a', 'copy', '-movflags', '+faststart',
      join(app, 'out/film/' + NAME + '-2k.mp4')]);
  }
}
await browser.close();
server.close();
console.log(JSON.stringify(Object.fromEntries(Object.entries(marks).map(([k, v]) => [k, +v.toFixed(2)]))));
