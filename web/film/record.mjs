// The promo film, made: `node web/film/record.mjs [shots] [build] [panes] [screens] [scene]` (all with none), into
// out/film/ (FILM_OUT). shots: the login pages the agents "took" (web/film/shots/); build: the panes' page
// (vite.film.config.ts); panes: the phone's (story.ts) filmed frame by frame on its own clock, into frames/<pane>/;
// screens: each machine's screen (screens.html) into frames/screen-<name>/; scene: the room they are in (scene.html)
// rendered frame by frame into film.mp4 (FILM_AT=<s,…>: only those moments, into peek/). Nothing waits on real time: the page's
// clock is Playwright's, and every animation of the page is held to it (step()). PANES=phone,home picks panes;
// PLAYWRIGHT_MODULE / PLAYWRIGHT_CHANNEL as test/browser's.
import { spawn } from 'node:child_process';
import { createReadStream, existsSync } from 'node:fs';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ASK, TIMES } from './times.ts';

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const OUT = process.env.FILM_OUT || here('../../out/film');
const FPS = 60;
const asked = process.argv.slice(2);
const doing = (s) => asked.length === 0 || asked.includes(s);
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const launch = () => playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL === '' ? {} : { channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome' });
/** The film's clock starts here: 2026-10-28 08:40 in Beijing. */
const T0 = Date.UTC(2026, 9, 28, 0, 40);

await mkdir(OUT, { recursive: true });

// ---- shots: the pictures the agents send back ----
if (doing('shots')) {
  const login = ({ dark, chrome, w, h }) => `<!doctype html><html><head><meta charset="utf-8"><style>
    *{box-sizing:border-box;margin:0}body{width:${w}px;height:${h}px;font:15px/1.4 -apple-system,"PingFang SC",sans-serif;background:${dark ? '#121316' : '#f4f5f7'};color:${dark ? '#eceef2' : '#16181d'};display:flex;flex-direction:column}
    .bar{height:${chrome === 'android' ? 28 : 34}px;display:flex;align-items:center;padding:0 12px;font-size:12px;gap:8px;${chrome === 'android' ? '' : `background:${dark ? '#1c1d21' : '#fff'};border-bottom:1px solid ${dark ? '#2a2b30' : '#e3e5e9'}`}}
    .dots{display:flex;gap:7px}.dots i{width:12px;height:12px;border-radius:50%;display:block}
    .win{margin-left:auto;display:flex;gap:22px;font-size:13px;opacity:.7}
    .main{flex:1;display:flex;align-items:center;justify-content:center}
    .card{width:${chrome === 'android' ? w - 40 : 340}px;padding:28px 24px;border-radius:18px;background:${dark ? '#1c1d21' : '#fff'};box-shadow:0 1px 3px rgba(0,0,0,.08)}
    .logo{width:40px;height:40px;border-radius:11px;background:#5b5bd6;margin-bottom:18px}
    h1{font-size:22px;margin-bottom:4px}p{font-size:13px;opacity:.6;margin-bottom:22px}
    .f{height:44px;border-radius:10px;border:1px solid ${dark ? '#34353b' : '#dcdfe4'};margin-bottom:12px;padding:0 14px;display:flex;align-items:center;font-size:14px;opacity:.75}
    .b{height:46px;border-radius:10px;background:#5b5bd6;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:600;margin-top:18px}
  </style></head><body>
    <div class="bar">${chrome === 'android' ? `<b>8:52</b><span style="margin-left:auto">5G ▮▮▮ 86%</span>`
      : chrome === 'mac' ? '<div class="dots"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div><span style="margin:0 auto;opacity:.7">Acme</span>'
      : '<span style="opacity:.8">Acme</span><div class="win"><span>—</span><span>☐</span><span>✕</span></div>'}</div>
    <div class="main"><div class="card"><div class="logo"></div><h1>登录 Acme</h1><p>欢迎回来</p>
      <div class="f">you@acme.dev</div><div class="f">••••••••••</div><div class="b">登录</div></div></div>
  </body></html>`;
  const browser = await launch();
  await mkdir(here('shots'), { recursive: true });
  for (const [name, o] of Object.entries({ android: { dark: true, chrome: 'android', w: 360, h: 740 }, windows: { dark: false, chrome: 'windows', w: 640, h: 430 }, mac: { dark: true, chrome: 'mac', w: 640, h: 430 } })) {
    const page = await browser.newPage({ viewport: { width: o.w, height: o.h }, deviceScaleFactor: 2 });
    await page.setContent(login(o));
    await page.screenshot({ path: here(`shots/${name}.png`) });
    await page.close();
  }
  // The three together, as the Mac at home sends them back in one picture.
  const uri = async (n) => `data:image/png;base64,${(await readFile(here(`shots/${n}.png`))).toString('base64')}`;
  const page = await browser.newPage({ viewport: { width: 900, height: 500 }, deviceScaleFactor: 2 });
  await page.setContent(`<body style="margin:0;width:900px;height:500px;background:linear-gradient(135deg,#e9e7f7,#f6efe9);position:relative;overflow:hidden">
    <img src="${await uri('windows')}" style="position:absolute;left:36px;top:40px;width:420px;border-radius:10px;box-shadow:0 12px 30px rgba(0,0,0,.18)">
    <img src="${await uri('mac')}" style="position:absolute;left:300px;top:150px;width:420px;border-radius:10px;box-shadow:0 12px 30px rgba(0,0,0,.25)">
    <img src="${await uri('android')}" style="position:absolute;left:676px;top:30px;width:200px;border-radius:22px;box-shadow:0 12px 30px rgba(0,0,0,.25);border:5px solid #111">
  </body>`);
  await page.screenshot({ path: here('shots/all.png') });
  await browser.close();
  console.log('shots: done');
}

// ---- build ----
if (doing('build')) {
  const { build } = await import('vite');
  await build({ configFile: here('../vite.film.config.ts'), build: { minify: false, reportCompressedSize: false }, logLevel: 'warn' });
  console.log('build: done');
}

/** Serves `root` (the built page, the frames) on a port of its own. */
function serve(root) {
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.json': 'application/json' };
  const server = createServer(async (req, res) => {
    let path = join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (existsSync(path) && (await stat(path)).isDirectory()) path = join(path, 'index.html');
    if (!existsSync(path)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' });
    createReadStream(path).pipe(res);
  });
  return new Promise((ok) => server.listen(0, '127.0.0.1', () => ok({ server, base: `http://127.0.0.1:${server.address().port}/` })));
}

/**
 * The page on to its next frame: its clock run on by `ms`, every animation of it (CSS's, the Web Animations Motion
 * runs) held at where that clock has it, and its pictures decoded.
 */
const step = (page, ms) => page.evaluate(async (ms) => {
  await globalThis.__pwClock.controller.runFor(ms);
  const now = Date.now();
  for (const a of document.getAnimations()) {
    if (a.__born === undefined) { a.__born = now - ms; a.pause(); }
    const end = a.effect?.getComputedTiming().endTime ?? Infinity;
    const at = (now - a.__born) * (a.playbackRate || 1);
    if (end !== Infinity && at >= end) { if (a.playState !== 'finished') a.finish(); } else a.currentTime = at;
  }
  await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
}, ms);

// ---- panes ----
const PANES = {
  phone: { viewport: { width: 390, height: 844 }, scale: 2, phone: true },
  home: { viewport: { width: 760, height: 820 }, scale: 2 },
  studio: { viewport: { width: 760, height: 820 }, scale: 2 },
  win: { viewport: { width: 760, height: 820 }, scale: 2 },
  cloud: { viewport: { width: 760, height: 820 }, scale: 2 },
};

async function film(name, base, browser) {
  const o = PANES[name];
  const dir = join(OUT, 'frames', name);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  const context = await browser.newContext({
    viewport: o.viewport, deviceScaleFactor: o.scale, timezoneId: 'Asia/Shanghai', locale: 'zh-CN',
    ...(o.phone ? { isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36' } : {}),
  });
  await context.clock.install({ time: T0 - 5000 });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.error(`${name}: ${e.message}`));
  await page.clock.pauseAt(T0);
  if (process.env.FILM_DEBUG) page.on('console', (m) => console.log(`${name} console: ${m.text()}`));
  await page.goto(`${base}?pane=${name}${process.env.FILM_DEBUG ? '&debug=1' : ''}`);
  await page.waitForFunction(() => window.filmReady === true);
  const frames = Math.round((Number(process.env.FILM_UNTIL || TIMES.end) / 1000) * FPS);
  const every = Number(process.env.FILM_EVERY || 1);
  const dt = 1000 / FPS;
  const centre = async (find) => {
    const r = await page.evaluate(find);
    if (!r) throw new Error(`${name}: nothing to tap`);
    return r;
  };
  let typed = 0;
  const taps = [];
  const tap = async (t, x, y) => { taps.push({ t, x, y }); await page.touchscreen.tap(x, y); };
  for (let f = 0; f < frames; f++) {
    const t = f * dt;
    if (o.phone) {
      const due = (ms) => t >= ms && t - dt < ms;
      if (due(TIMES.tapField)) {
        const { x, y } = await centre(() => { const el = [...document.querySelectorAll('textarea')].find((e) => e.getClientRects().length); if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
        await tap(t, x, y);
      }
      const chars = [...ASK];
      const want = t < TIMES.typeFrom ? 0 : Math.min(chars.length, Math.floor(((t - TIMES.typeFrom) / (TIMES.typeTo - TIMES.typeFrom)) * chars.length));
      while (typed < want) await page.keyboard.insertText(chars[typed++]);
      if (due(TIMES.send)) {
        const { x, y } = await centre(() => { const el = [...document.querySelectorAll('button[aria-label]')].find((b) => /发送|Send/.test(b.getAttribute('aria-label')) && b.getClientRects().length); if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
        await tap(t, x, y);
      }
      if (due(TIMES.toLatest) || due(TIMES.toLatestAgain)) {
        const r = await page.evaluate(() => { const el = [...document.querySelectorAll('button[aria-label]')].find((b) => /最新|底部|新消息|latest/i.test(b.getAttribute('aria-label')) && b.getClientRects().length); if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
        if (r) await tap(t, r.x, r.y); else console.error(`${name}: no button to the latest`);
      }
      if (due(TIMES.merge)) {
        const { x, y } = await centre(() => { const el = [...document.querySelectorAll('button')].reverse().find((b) => b.textContent?.trim().startsWith('合并') && b.getClientRects().length); if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
        await tap(t, x, y);
      }
    }
    await step(page, f === 0 ? 0 : dt);
    if (f % every === 0) await page.screenshot({ path: join(dir, `${String(f).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 90, caret: 'initial' });
    if (f % 300 === 0) console.log(`${name}: ${f}/${frames}`);
  }
  if (process.env.FILM_DEBUG) console.log(name, 'images:', await page.evaluate(() => [...document.querySelectorAll('[data-send-image]')].map((b) => JSON.stringify({ ...b.dataset }))));
  if (o.phone) await writeFile(join(dir, 'taps.json'), JSON.stringify(taps));
  await context.close();
}

if (doing('panes')) {
  const { server, base } = await serve(here('../../dist/film'));
  const browser = await launch();
  const names = (process.env.PANES || 'phone').split(',');
  await Promise.all(names.map((n) => film(n, base, browser)));
  await browser.close();
  server.close();
  console.log('panes: done');
}

// ---- assets: the machines' models and the light, public and free (CREDITS.md says whose each is) ----
/** Files fetched once into assets/: [where, url]. */
const RAW = 'https://raw.githubusercontent.com';
const PH = 'https://dl.polyhaven.org/file/ph-assets';
const FILES = [
  ['iphone.glb', `${RAW}/lenxism/mockstudio/HEAD/public/models/iphone-17-pro/device.glb`],
  ['studio-display.glb', `${RAW}/lenxism/mockstudio/HEAD/public/models/studio-display/device.glb`],
  ['mac-mini.glb', `${RAW}/kosumic/whip/HEAD/launch-videos/source-assets/models/mac-mini-m4/mac-mini-m4.glb`],
  ['office.hdr', `${PH}/HDRIs/hdr/2k/lythwood_room_2k.hdr`],
  ['metro.hdr', `${PH}/HDRIs/hdr/4k/metro_noord_4k.hdr`],
  ['wood_diff.jpg', `${PH}/Textures/jpg/2k/wood_table_001/wood_table_001_diff_2k.jpg`],
  ['wood_rough.jpg', `${PH}/Textures/jpg/2k/wood_table_001/wood_table_001_rough_2k.jpg`],
  ['wood_nor.jpg', `${PH}/Textures/jpg/2k/wood_table_001/wood_table_001_nor_gl_2k.jpg`],
  ['wall_diff.jpg', `${PH}/Textures/jpg/2k/painted_plaster_wall/painted_plaster_wall_diff_2k.jpg`],
  ['wall_nor.jpg', `${PH}/Textures/jpg/2k/painted_plaster_wall/painted_plaster_wall_nor_gl_2k.jpg`],
  ['floor_diff.jpg', `${PH}/Textures/jpg/2k/wood_floor_deck/wood_floor_deck_diff_2k.jpg`],
  ['wall-mac.jpg', `${PH}/HDRIs/extra/Tonemapped%20JPG/venice_sunset.jpg`],
  ['wall-win.jpg', `${PH}/HDRIs/extra/Tonemapped%20JPG/kloofendal_48d_partly_cloudy_puresky.jpg`],
];
/** Folders (a model and its textures) taken out of a repository: [where, repository, path]. */
const FOLDERS = [
  ['macbook', 'jeantimex/liquid-glass-html-in-canvas', 'public/models/macbook'],
  ['monitor', 'SalamPS/TekkomFiber', 'public/3dasset/asus_pc_gaming_monitor'],
  ['gaming-pc', 'SalamPS/TekkomFiber', 'public/3dasset/custom_gaming_pc'],
];
const run = (cmd, args, cwd) => new Promise((ok, no) => spawn(cmd, args, { cwd, stdio: 'inherit' }).on('close', (c) => (c === 0 ? ok() : no(new Error(`${cmd} ${args.join(' ')}: ${c}`)))));
if (doing('assets')) {
  const A = join(OUT, 'assets');
  await mkdir(A, { recursive: true });
  for (const [name, url] of FILES) if (!existsSync(join(A, name))) await run('curl', ['-fsSL', '--retry', '3', '-o', join(A, name), url]);
  // Poly Haven's models (the room's things), each its glTF and the files it names.
  for (const id of ['potted_plant_02', 'Shelf_01', 'hanging_picture_frame_01', 'hanging_picture_frame_02', 'potted_plant_04', 'alarm_clock_01', 'book_encyclopedia_set_01', 'ceramic_vase_01']) {
    const dir = join(A, 'ph', id);
    if (existsSync(join(dir, `${id}.gltf`))) continue;
    const info = await (await fetch(`https://api.polyhaven.com/files/${id}`)).json();
    const g = info.gltf['1k'].gltf;
    await mkdir(dir, { recursive: true });
    await run('curl', ['-fsSL', '-o', join(dir, `${id}.gltf`), g.url]);
    for (const [path, f] of Object.entries(g.include ?? {})) { await mkdir(join(dir, path, '..'), { recursive: true }); await run('curl', ['-fsSL', '-o', join(dir, path), f.url]); }
  }
  for (const [name, repo, path] of FOLDERS) {
    if (existsSync(join(A, name))) continue;
    const tmp = join(A, `.${name}`);
    await rm(tmp, { recursive: true, force: true });
    await run('git', ['clone', '--depth', '1', '--filter=blob:none', '--sparse', `https://github.com/${repo}.git`, tmp]);
    await run('git', ['sparse-checkout', 'set', '--no-cone', path], tmp);
    await run('mv', [join(tmp, path), join(A, name)]);
    await rm(tmp, { recursive: true, force: true });
  }
  if (!existsSync(join(OUT, 'vendor/node_modules/@vscode/codicons'))) {
    await mkdir(join(OUT, 'vendor'), { recursive: true });
    await run('npm', ['install', '--no-save', '--prefix', join(OUT, 'vendor'), 'three@0.180.0', 'n8ao@^1.9.0', 'postprocessing@^6.37.0', '@vscode/codicons@^0.0.36']);
  }
  console.log('assets: done');
}

// ---- screens: what each machine's screen shows (screens.html), 30 a second ----
const LENGTH = 38;
const SCREEN_FPS = 30;
if (doing('screens')) {
  await writeFile(join(OUT, 'screens.html'), await readFile(here('screens.html')));
  const { server, base } = await serve(OUT);
  const browser = await launch();
  await Promise.all(['home', 'studio', 'win', 'cloud'].map(async (name) => {
    const dir = join(OUT, 'frames', `screen-${name}`);
    await rm(dir, { recursive: true, force: true });
    await mkdir(dir, { recursive: true });
    const page = await browser.newPage({ viewport: { width: 920, height: 575 }, deviceScaleFactor: 2 });
    page.on('pageerror', (e) => console.error(`screen ${name}: ${e.message}`));
    await page.goto(`${base}screens.html?screen=${name}`);
    await page.waitForFunction(() => typeof window.draw === 'function');
    for (let f = 0; f < LENGTH * SCREEN_FPS; f++) {
      await page.evaluate(async (s) => { await window.draw(s); }, f / SCREEN_FPS);
      await page.screenshot({ path: join(dir, `${String(f).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 90 });
    }
    await page.close();
  }));
  await browser.close();
  server.close();
  console.log('screens: done');
}

// ---- scene: the room (scene.html, three.js), frame by frame, into film.mp4 ----
if (doing('scene')) {
  const { readdir } = await import('node:fs/promises');
  await writeFile(join(OUT, 'scene.html'), await readFile(here('scene.html')));
  const count = {};
  for (const n of await readdir(join(OUT, 'frames'))) if (!n.endsWith('.json')) count[n] = (await readdir(join(OUT, 'frames', n))).filter((f) => f.endsWith('.jpg')).length;
  await writeFile(join(OUT, 'frames', 'count.json'), JSON.stringify(count));
  const { server, base } = await serve(OUT);
  const browser = await playwright.chromium.launch({
    ...(process.env.PLAYWRIGHT_CHANNEL === '' ? {} : { channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome' }),
    args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist', '--enable-unsafe-swiftshader'],
  });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on('pageerror', (e) => console.error(`scene: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log(`scene: ${m.text()}`); });
  await page.goto(`${base}scene.html`);
  await page.waitForFunction(() => window.ready === true || window.failed, null, { timeout: 180000 });
  console.log('scene: gl', await page.evaluate(() => { const gl = document.querySelector('canvas').getContext('webgl2'); const d = gl.getExtension('WEBGL_debug_renderer_info'); return d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) : '?'; }));
  const only = process.env.FILM_AT?.split(',').map(Number);
  if (only) {
    await mkdir(join(OUT, 'peek'), { recursive: true });
    for (const s of only) {
      await page.evaluate((s) => window.render(s), s);
      await page.screenshot({ path: join(OUT, 'peek', `at-${s}.jpg`), type: 'jpeg', quality: 88 });
    }
  } else {
    const ff = spawn(process.env.FFMPEG || 'ffmpeg', ['-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16', '-preset', 'slow', '-movflags', '+faststart', join(OUT, 'film.mp4')], { stdio: ['pipe', 'inherit', 'inherit'] });
    const frames = Math.round(LENGTH * FPS);
    const t0 = Date.now();
    for (let f = 0; f < frames; f++) {
      await page.evaluate((s) => window.render(s), f / FPS);
      const jpg = await page.screenshot({ type: 'jpeg', quality: 95 });
      if (!ff.stdin.write(jpg)) await new Promise((ok) => ff.stdin.once('drain', ok));
      if (f % 300 === 0) console.log(`scene: ${f}/${frames} (${Math.round((Date.now() - t0) / 1000)} s)`);
    }
    ff.stdin.end();
    await new Promise((ok, no) => ff.on('close', (code) => (code === 0 ? ok() : no(new Error(`ffmpeg ${code}`)))));
    console.log(`scene: ${join(OUT, 'film.mp4')}`);
  }
  await browser.close();
  server.close();
}

// ---- The path-traced film: the room exported (export), Cycles' pictures (cycles), the words over them (overlay),
// the two put together (final). FILM_FRAMES=150,420 (or 0-1140) picks frames; FILM_SAMPLES Cycles' samples. ----
const CFPS = 30;
async function scenePage(query = '') {
  const { server, base } = await serve(OUT);
  const browser = await playwright.chromium.launch({
    ...(process.env.PLAYWRIGHT_CHANNEL === '' ? {} : { channel: process.env.PLAYWRIGHT_CHANNEL || 'chrome' }),
    args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on('pageerror', (e) => console.error(`scene: ${e.message}`));
  await writeFile(join(OUT, 'scene.html'), await readFile(here('scene.html')));
  await page.goto(`${base}scene.html${query}`);
  await page.waitForFunction(() => window.ready === true || window.failed, null, { timeout: 180000 });
  return { page, close: async () => { await browser.close(); server.close(); } };
}
if (doing('export')) {
  const C = join(OUT, 'cycles');
  await mkdir(join(OUT, 'frames', 'phone-bar'), { recursive: true });
  await mkdir(C, { recursive: true });
  const { page, close } = await scenePage();
  const { appendFile } = await import('node:fs/promises');
  await rm(join(C, 'scene.glb'), { force: true });
  await page.exposeFunction('saveChunk', (b64) => appendFile(join(C, 'scene.glb'), Buffer.from(b64, 'base64')));
  console.log('export: glb bytes', await page.evaluate(() => window.exportGlb()));
  const plan = await page.evaluate((fps) => window.plan(fps), CFPS);
  // The phone's pictures with its status bar, those the film shows.
  for (const fr of plan) {
    const src = fr.screens.phone;
    if (!src) continue;
    const name = `frames/phone-bar/${src.split('/').pop().replace('.jpg', '')}-${fr.clock.replace(':', '')}.jpg`;
    if (!existsSync(join(OUT, name))) {
      const url = await page.evaluate(([src, clock]) => window.phoneBar(src, clock), [src, fr.clock]);
      await writeFile(join(OUT, name), Buffer.from(url.split(',')[1], 'base64'));
    }
    fr.screens.phone = name;
  }
  await writeFile(join(C, 'plan.json'), JSON.stringify(plan));
  await close();
  console.log(`export: ${plan.length} frames planned`);
}
const FRAMES = process.env.FILM_FRAMES || `0-${LENGTH * CFPS}`;
if (doing('cycles')) {
  await run(process.env.BLENDER || 'blender', ['-b', '-P', here('film.py'), '--', OUT, FRAMES, process.env.FILM_SAMPLES || '128']);
}
if (doing('overlay')) {
  const dir = join(OUT, 'cycles', 'overlay');
  await mkdir(dir, { recursive: true });
  const { page, close } = await scenePage('?overlay=1');
  const list = FRAMES.includes('-') ? (([a, b]) => Array.from({ length: b - a }, (_, i) => a + i))(FRAMES.split('-').map(Number)) : FRAMES.split(',').map(Number);
  for (const f of list) {
    await page.evaluate((s) => window.render(s), f / CFPS);
    await page.screenshot({ path: join(dir, `${String(f).padStart(5, '0')}.png`), omitBackground: true });
  }
  await close();
  console.log('overlay: done');
}
if (doing('final')) {
  const C = join(OUT, 'cycles');
  if (process.env.FILM_FRAMES && !process.env.FILM_FRAMES.includes('-')) {
    // Stills: each Cycles picture with its words over it.
    await mkdir(join(OUT, 'peek'), { recursive: true });
    for (const f of process.env.FILM_FRAMES.split(',')) {
      const n = String(f).padStart(5, '0');
      await run(process.env.FFMPEG || 'ffmpeg', ['-loglevel', 'error', '-y', '-i', join(C, 'frames', `${n}.png`), '-i', join(C, 'overlay', `${n}.png`), '-filter_complex', 'overlay', '-q:v', '3', join(OUT, 'peek', `cycles-${f}.jpg`)]);
    }
  } else {
    // Under the end card nothing shows: the frames not rendered there are the last one that was.
    let last = null;
    for (let f = 0; f < LENGTH * CFPS; f++) {
      const p = join(C, 'frames', `${String(f).padStart(5, '0')}.png`);
      if (existsSync(p)) last = p; else if (last) await writeFile(p, await readFile(last));
    }
    await run(process.env.FFMPEG || 'ffmpeg', ['-loglevel', 'error', '-y', '-framerate', String(CFPS), '-i', join(C, 'frames', '%05d.png'), '-framerate', String(CFPS), '-i', join(C, 'overlay', '%05d.png'),
      '-filter_complex', '[0][1]overlay', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow', '-movflags', '+faststart', join(OUT, 'film-cycles.mp4')]);
    console.log(`final: ${join(OUT, 'film-cycles.mp4')}`);
  }
}
