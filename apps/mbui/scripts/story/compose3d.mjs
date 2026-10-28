// A story's film on a 3D iPhone Duo: `node compose3d.mjs <name> [still times…]`. Its frames (out/film/story-<name>.mp4)
// and marks as compose.mjs reads them; each screen drawn by compose.html alone (STORY.screens: the app's frame, its
// bars, keyboard and taps), then shown on Apple's model folded and unfolded (duo3d/film.html) from a camera on the
// story's marks (<name>.cam3d.js), into out/film/promo3d-<name>.mp4; with times, only those, as out/stills/promo3d-<name>-N.png.
// Apple's model is prepared out of the repository (duo3d/prepare-assets.py, DUO_ASSETS: out/duo3d-assets).
import { execFileSync, spawn } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, readFileSync, rmSync, readdirSync, statSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { filmSound } from './sound.mjs';
const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '../..');
const [name, ...stills] = process.argv.slice(2);
const FFMPEG = '/opt/homebrew/bin/ffmpeg', FPS = 60;
const ASSETS = process.env.DUO_ASSETS || join(app, 'out/duo3d-assets');
// the phone (FILM_DEVICE: iduo, Apple's model in duo3d; zfold, a Galaxy Z Fold made in zfold3d), the words' language
// (FILM_LANG: en for English's keyboard), drawn at 4K (FILM_SCALE 2: 3840 x 2160, and 2K from it; 1: 1080p)
const DEVICE = process.env.FILM_DEVICE || 'iduo';
const MODEL = DEVICE === 'zfold' ? 'zfold3d' : 'duo3d';
const SCALE = Number(process.env.FILM_SCALE || 2);
const SHEET = DEVICE === 'zfold' ? [1969, 2520 + 2184] : [2857, 2038 + 2011];
const film = join(app, `out/film/story-${name}.mp4`);
const log = readFileSync(join(app, `out/story/${name}.log`), 'utf8');
const T0 = 1000;
const marks = {}, taps = [], kbs = [], nav = [];
let pending = null;
for (const line of log.split('\n')) {
  const nm = line.match(/^FILM NAV (\d+) (.+)$/);
  if (nm) { nav.push([Number(nm[1]), nm[2]]); continue; }
  let m = line.match(/^DRIVE AT ([\d.]+) (.+)$/);
  if (m && m[2].startsWith('kb=')) { kbs.push([(Number(m[1]) - T0) / 1000, Number(m[2].slice(3))]); continue; }
  if (m && /^(tap|drag)@/.test(m[2])) { const [x, y, dx = 0, dy = 0, ms = 0] = m[2].split('@')[1].split(',').map(Number); taps.push({ t: (Number(m[1]) - T0) / 1000, x, y, dx, dy, ms }); continue; }
  if (m) { marks[m[2]] = (Number(m[1]) - T0) / 1000; if (m[2].startsWith('tap=')) pending = marks[m[2]]; continue; }
  m = line.match(/^DRIVE tap .* at ([\d.]+),([\d.]+)$/);
  if (m && pending !== null) { taps.push({ t: pending, x: Number(m[1]), y: Number(m[2]) }); pending = null; }
}
const cams = (await import(pathToFileURL(join(here, `${name}.cam3d.js`)))).default(marks);
const U = marks.unfold, FLIP = 1.1, END = marks.end - 1.6;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const ease = (x) => { x = clamp(x); return x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const keyed = (frames, t) => {
  if (t <= frames[0][0]) return frames[0].slice(1);
  for (let i = 1; i < frames.length; i++) {
    if (t <= frames[i][0]) { const a = frames[i - 1], b = frames[i], k = ease((t - a[0]) / (b[0] - a[0])); return a.slice(1).map((v, j) => v + (b[j + 1] - v) * k); }
  }
  return frames[frames.length - 1].slice(1);
};
// how far it is open: folded till the unfold, flat a FLIP later (the reference's slider, 0 to 180)
const angleAt = (t) => 180 * ease((t - U) / FLIP);

const frames = join(app, 'out/frames'); rmSync(frames, { recursive: true, force: true }); mkdirSync(frames, { recursive: true });
const screens = join(app, 'out/screens'); rmSync(screens, { recursive: true, force: true }); mkdirSync(screens, { recursive: true });
const frameAt = (t) => Math.round(t * FPS);
const when = (a) => { const m = a.match(/^(.*?)([+-][\d.]+)?$/); return isNaN(Number(a)) ? marks[m[1]] + Number(m[2] || 0) : Number(a); };
const want = stills.length ? stills.map(when) : null;
const take = (t, out) => execFileSync(FFMPEG, ['-loglevel', 'error', '-y', '-ss', String(t), '-i', film, '-frames:v', '1', '-q:v', '2', out]);
let total;
if (want) { for (const t of want) take(t, join(frames, `${frameAt(t)}.jpg`)); total = 1e9; }
else { execFileSync(FFMPEG, ['-loglevel', 'error', '-i', film, '-q:v', '2', '-start_number', '0', join(frames, '%d.jpg')]); total = readdirSync(frames).length; }
take(U - 1 / FPS, join(frames, 'closed.jpg'));

// the pages, over HTTP (the model's loader reads it so): scripts/story, its assets from ASSETS, the frames, the screens
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.usdc': 'application/octet-stream', '.avif': 'image/avif' };
const server = createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = p.startsWith('/duo3d/assets/') ? join(ASSETS, p.slice('/duo3d/assets/'.length))
    : p.startsWith('/frames/') ? join(frames, p.slice(8)) : p.startsWith('/screens/') ? join(screens, p.slice(9)) : join(here, p);
  if (!existsSync(file) || statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
  createReadStream(file).pipe(res);
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const base = `http://127.0.0.1:${server.address().port}/`;
const require = createRequire(join(process.env.PW_FROM || app, 'x.js'));
const { chromium } = require('playwright-core');
const browser = await chromium.launch({ channel: 'chrome', args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });

// ---- the screens, each as compose.html draws it ----
const sp = await browser.newPage({ viewport: { width: SHEET[0], height: SHEET[1] }, deviceScaleFactor: 1 });
sp.on('pageerror', (e) => console.error('screens:', e.message));
await sp.addInitScript((story) => { window.STORY = story; window.SHOTS = { cam: [[0, 1, 0, 0]], spot: [[0, 0, 0, 1, 1, 0]] }; }, { marks, taps, kbs, nav, device: DEVICE, lang: process.env.FILM_LANG || 'zh', screens: true });
await sp.goto(`${base}compose.html`);
await sp.waitForFunction(() => window.ready === true);
const box = await sp.evaluate(() => window.SCREENS);
async function drawScreens(f) {
  const t = f / FPS;
  await sp.evaluate(([t, a, b]) => window.render(t, a, b), [t, `${base}frames/${Math.min(f, total - 1)}.jpg`, `${base}frames/closed.jpg`]);
  const out = {};
  if (t < U + FLIP) { await writeFile(join(screens, `o${f}.jpg`), await sp.screenshot({ type: 'jpeg', quality: 92, clip: { x: box.outer[0], y: box.outer[1], width: box.outer[2], height: box.outer[3] } })); out.outer = `${base}screens/o${f}.jpg`; }
  if (t >= U) { await writeFile(join(screens, `i${f}.jpg`), await sp.screenshot({ type: 'jpeg', quality: 92, clip: { x: box.inner[0], y: box.inner[1], width: box.inner[2], height: box.inner[3] } })); out.inner = `${base}screens/i${f}.jpg`; }
  return out;
}

// ---- the phone ----
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: SCALE });
page.on('pageerror', (e) => console.error('3d:', e.message));
page.on('console', (m) => { if (m.type() === 'error') console.error('3d console:', m.text()); });
await page.goto(`${base}${MODEL}/film.html`);
await page.waitForFunction(() => window.ready3d === true, null, { timeout: 120000 });
async function draw(f) {
  const t = f / FPS;
  const s = await drawScreens(f);
  await page.evaluate(async ([s, angle, cam, endT]) => {
    await window.frame3d({ outer: s.outer, inner: s.inner, angle, cam });
    // the end: the phone away, the mark
    const e = Math.min(1, Math.max(0, endT));
    document.getElementById('viewport').style.opacity = String(1 - e);
    document.getElementById('end').style.opacity = String(Math.min(1, Math.max(0, (endT - .55) / .9)));
  }, [s, angleAt(t), keyed(cams, t), (t - END) / .9]);
}
if (want) {
  mkdirSync(join(app, 'out/stills'), { recursive: true });
  for (const [i, t] of want.entries()) {
    await draw(frameAt(t));
    await page.screenshot({ path: join(app, `out/stills/promo3d-${name}-${i + 1}.png`) });
    console.log('still', i + 1, t);
  }
} else {
  const n = Math.round(marks.end * FPS);
  // its sound on the same marks (sound.mjs), as loud as films are played
  const wav = join(app, `out/film/promo3d-${name}.wav`);
  filmSound({ seconds: n / FPS, marks, taps: taps.map((k) => k.t), unfold: U, flip: FLIP, end: END, out: wav + '.raw.wav' });
  execFileSync(FFMPEG, ['-loglevel', 'error', '-y', '-i', wav + '.raw.wav', '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', '48000', wav]);
  const ff = spawn(FFMPEG, ['-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-', '-i', wav,
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-preset', 'slow', '-c:a', 'aac', '-b:a', '192k', '-shortest',
    '-movflags', '+faststart', join(app, `out/film/promo3d-${name}.mp4`)], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let f = 0; f < n; f++) {
    await draw(f);
    const jpg = await page.screenshot({ type: 'jpeg', quality: 93 });
    if (!ff.stdin.write(jpg)) await new Promise((ok) => ff.stdin.once('drain', ok));
    // (what is drawn is kept only for the frame: the screens' pictures go)
    for (const k of ['o', 'i']) rmSync(join(screens, `${k}${f}.jpg`), { force: true });
    if (f % 300 === 0) console.log(`compose3d: ${f}/${n}`);
  }
  ff.stdin.end();
  await new Promise((ok, no) => ff.on('close', (c) => (c === 0 ? ok() : no(new Error('ffmpeg ' + c)))));
  // and at 2K (2560 × 1440), from it
  if (SCALE >= 2) {
    execFileSync(FFMPEG, ['-loglevel', 'error', '-y', '-i', join(app, `out/film/promo3d-${name}.mp4`), '-vf', 'scale=2560:1440:flags=lanczos',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-preset', 'slow', '-c:a', 'copy', '-movflags', '+faststart',
      join(app, `out/film/promo3d-${name}-2k.mp4`)]);
  }
}
await browser.close();
server.close();
console.log(JSON.stringify(marks));
