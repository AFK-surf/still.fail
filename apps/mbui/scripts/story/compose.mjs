// A story's film laid in the device and filmed: `node compose.mjs <name> [still times…]`. Its frames (out/film/
// story-<name>.mp4) taken out, its marks and taps read off its log (DRIVE AT, DRIVE tap), compose.html drawn at each
// frame by Chrome and put into out/film/promo-<name>.mp4; with times, only those, as out/stills/promo-<name>-N.png.
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const app = join(here, '../..');
const [name, ...stills] = process.argv.slice(2);
const FFMPEG = '/opt/homebrew/bin/ffmpeg', FPS = 60;
const film = join(app, `out/film/story-${name}.mp4`);
const log = readFileSync(join(app, `out/story/${name}.log`), 'utf8');
// the run's clock at the film's first frame: 1000 ms (Tester's start)
const T0 = 1000;
const marks = {}, taps = [], kbs = [];
let pending = null;
for (const line of log.split('\n')) {
  let m = line.match(/^DRIVE AT ([\d.]+) (.+)$/);
  if (m && m[2].startsWith('kb=')) { kbs.push([(Number(m[1]) - T0) / 1000, Number(m[2].slice(3))]); continue; }
  // a press drawn where it was (tap@X,Y), or a finger dragged (drag@X,Y,DX,DY,MS)
  if (m && /^(tap|drag)@/.test(m[2])) { const [x, y, dx = 0, dy = 0, ms = 0] = m[2].split('@')[1].split(',').map(Number); taps.push({ t: (Number(m[1]) - T0) / 1000, x, y, dx, dy, ms }); continue; }
  if (m) { marks[m[2]] = (Number(m[1]) - T0) / 1000; if (m[2].startsWith('tap=')) pending = marks[m[2]]; continue; }
  m = line.match(/^DRIVE tap .* at ([\d.]+),([\d.]+)$/);
  if (m && pending !== null) { taps.push({ t: pending, x: Number(m[1]), y: Number(m[2]) }); pending = null; }
}
const shots = (await import(pathToFileURL(join(here, `${name}.shots.js`)))).default(marks);
const frames = join(app, 'out/frames'); rmSync(frames, { recursive: true, force: true }); mkdirSync(frames, { recursive: true });
const frameAt = (t) => Math.min(Math.round(t * FPS), 1e9);
// a still's time: seconds, or a mark and how far after it (unfold+0.4, tap=合并-0.2)
const when = (a) => { const m = a.match(/^(.*?)([+-][\d.]+)?$/); return isNaN(Number(a)) ? marks[m[1]] + Number(m[2] || 0) : Number(a); };
const want = stills.length ? stills.map(when) : null;
// the frames: all of them for the film, those asked (and the one before the fold) for stills
const take = (t, out) => execFileSync(FFMPEG, ['-loglevel', 'error', '-y', '-ss', String(t), '-i', film, '-frames:v', '1', '-q:v', '2', out]);
let total;
if (want) { for (const t of want) take(t, join(frames, `${frameAt(t)}.jpg`)); total = 0; }
else { execFileSync(FFMPEG, ['-loglevel', 'error', '-i', film, '-q:v', '2', '-start_number', '0', join(frames, '%d.jpg')]); total = readdirSync(frames).length; }
const closedAt = marks.unfold - 1 / FPS;
take(closedAt, join(frames, 'closed.jpg'));
const require = createRequire(join(process.env.PW_FROM || app, 'x.js'));
const { chromium } = require('playwright-core');
const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
page.on('pageerror', (e) => console.error('page:', e.message));
await page.addInitScript(({ story, shots }) => { window.STORY = story; window.SHOTS = shots; }, { story: { marks, taps, kbs, device: process.env.DEVICE || (name === 'iduo' ? 'iduo' : 'pixel') }, shots });
await page.goto(pathToFileURL(join(here, 'compose.html')).href);
await page.waitForFunction(() => window.ready === true);
const url = (f) => pathToFileURL(join(frames, `${f}.jpg`)).href;
const closedUrl = pathToFileURL(join(frames, 'closed.jpg')).href;
if (want) {
  mkdirSync(join(app, 'out/stills'), { recursive: true });
  for (const [i, t] of want.entries()) {
    await page.evaluate(([t, a, b]) => window.render(t, a, b), [t, url(frameAt(t)), closedUrl]);
    await page.screenshot({ path: join(app, `out/stills/promo-${name}-${i + 1}.png`) });
    console.log('still', i + 1, t);
  }
} else {
  const ff = spawn(FFMPEG, ['-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-preset', 'slow', '-movflags', '+faststart', join(app, `out/film/promo-${name}.mp4`)], { stdio: ['pipe', 'inherit', 'inherit'] });
  const n = Math.round(marks.end * FPS);
  for (let f = 0; f < n; f++) {
    await page.evaluate(([t, a, b]) => window.render(t, a, b), [f / FPS, url(Math.min(f, total - 1)), closedUrl]);
    const jpg = await page.screenshot({ type: 'jpeg', quality: 93 });
    if (!ff.stdin.write(jpg)) await new Promise((ok) => ff.stdin.once('drain', ok));
    if (f % 300 === 0) console.log(`compose: ${f}/${n}`);
  }
  ff.stdin.end();
  await new Promise((ok, no) => ff.on('close', (c) => (c === 0 ? ok() : no(new Error('ffmpeg ' + c)))));
}
await browser.close();
console.log(JSON.stringify(marks));
