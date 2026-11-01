// The official site as it loads (web/src/site, built by `pnpm build:site`): what shows before any script, once the
// page's own script runs with the demo's still on its way, and once the demo has taken its boxes over. Before any
// script nothing of the scene is drawn out of its place; with the page's own, the scene stands at its first frame
// from the frames built into the page (the window's and the phone's); the demo's arrival changes nothing seen.
//   PLAYWRIGHT_MODULE=… [PLAYWRIGHT_CHANNEL=chrome] [SHOTS=<dir>] node test/browser/site-first-frame.mjs [dist/site]
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';

const dir = resolve(process.argv[2] ?? 'dist/site');
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
if (out) mkdirSync(out, { recursive: true });

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.json': 'application/json' };
// Served as Cloudflare serves the site: a directory's index.html, a page's .html at its address without it.
const server = createServer((req, res) => {
  let path = join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!extname(path) && existsSync(`${path}.html`)) path = `${path}.html`;
  try { if (statSync(path).isDirectory()) path = join(path, 'index.html'); } catch { res.writeHead(404).end(); return; }
  try { res.writeHead(200, { 'content-type': TYPES[extname(path)] ?? 'application/octet-stream' }).end(readFileSync(path)); } catch { res.writeHead(404).end(); }
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const base = `http://127.0.0.1:${server.address().port}`;

/** The scripts a page names itself (its own); the rest are the demo's, loaded after. */
const own = (page) => new Set([...readFileSync(join(dir, page), 'utf8').matchAll(/<(?:script[^>]*\ssrc|link[^>]*rel="modulepreload"[^>]*\shref)="([^"]+)"/g)].map((m) => m[1]));
const ownScripts = own('index.html');

const browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});
const shot = async (page, name) => { if (out) writeFileSync(join(out, `${name}.png`), await page.screenshot()); };
const report = [];

for (const [label, size, path] of [['wide', { width: 1440, height: 900 }, '/'], ['narrow', { width: 390, height: 844 }, '/'], ['wide-en', { width: 1440, height: 900 }, '/en/']]) {
  const context = await browser.newContext({ viewport: size, locale: path === '/en/' ? 'en-US' : 'zh-CN' });

  // Before any script: the scene unseen, nothing of it drawn out of its place.
  const before = await context.newPage();
  await before.route('**/*.js', (route) => route.abort());
  await before.goto(base + path, { waitUntil: 'load' });
  await shot(before, `${label}-0-before-scripts`);
  // The scene's room: where its wires are drawn, under all of it.
  const unseen = await before.evaluate(() => {
    const room = (document.querySelector('[data-idea="1"] section[style] [data-site-wires]') ?? document.querySelector('[data-idea="1"] section[style] svg'))?.parentElement;
    return room ? getComputedStyle(room).opacity : null;
  });
  report.push(`${label}: before scripts, the scene's room opacity ${unseen}`);
  assert.equal(unseen, '0', `${label}: the scene is seen before its script has placed it`);
  await before.close();

  // The page's own script, the demo's held back: the scene at its first frame from the frames built into the page.
  const held = [];
  const page = await context.newPage();
  const said = [];
  page.on('console', (m) => said.push(`${m.type()}: ${m.text()}`));
  page.on('pageerror', (e) => said.push(`error: ${e.stack ?? e}`));
  await page.route('**/*.js', (route) => {
    if (ownScripts.has(new URL(route.request().url()).pathname)) return route.continue();
    held.push(route);
  });
  await page.goto(base + path, { waitUntil: 'load' });
  await page.waitForSelector('[data-drawn]', { state: 'attached', timeout: 10_000 }).catch(async (e) => {
    await shot(page, `${label}-1-page-script-undrawn`);
    console.log(JSON.stringify({ said }, null, 1));
    throw e;
  });
  await page.waitForTimeout(500);
  await shot(page, `${label}-1-page-script`);
  const first = await page.evaluate(() => {
    const room = document.querySelector('[data-drawn]');
    const air = room.lastElementChild;
    const flying = [...air.children].filter((e) => e.tagName !== 'STYLE' && getComputedStyle(e).display !== 'none');
    const frame = document.querySelector('[data-idea="1"] #demo > [inert]');
    const phone = document.querySelector('[data-idea="1"] iframe');
    const phoneFrame = phone?.contentDocument?.querySelector('#demo > [inert]');
    return { flying: flying.map((e) => `${e.innerText.split('\n')[0]} ${e.style.width}×${e.style.height}`), frame: !!frame, phone: phone?.getAttribute('src') ?? null, phoneFrame: !!phoneFrame, opacity: getComputedStyle(room).opacity };
  });
  report.push(`${label}: page's own script: ${JSON.stringify(first)}; demo's scripts held: ${held.length}`);
  assert.equal(first.flying.length, 4, `${label}: the four devices are not in the air at the first frame`);
  assert.ok(first.frame, `${label}: the window's frame is gone before the demo's script is here`);
  if (label !== 'narrow') assert.ok(first.phoneFrame, `${label}: the phone shows no frame while its app is on its way`);

  // The demo's scripts arrive: it takes its boxes over; what flies is read again from it at the next frame drawn.
  for (const route of held.splice(0)) await route.continue();
  await page.unroute('**/*.js');
  await page.waitForFunction(() => !document.querySelector('[data-idea="1"] #demo > [inert]'));
  await page.waitForTimeout(1500);
  await page.mouse.wheel(0, 1);
  await page.waitForTimeout(500);
  await shot(page, `${label}-2-demo`);
  const after = await page.evaluate(() => {
    const air = document.querySelector('[data-drawn]').lastElementChild;
    const flying = [...air.children].filter((e) => e.tagName !== 'STYLE' && getComputedStyle(e).display !== 'none');
    const demo = document.querySelector('[data-idea="1"] #demo');
    const phone = document.querySelector('[data-idea="1"] iframe');
    return { flying: flying.map((e) => `${e.innerText.split('\n')[0]} ${e.style.width}×${e.style.height}`), hiddenInList: [...demo.querySelectorAll('*')].filter((e) => e.style.visibility === 'hidden').length, phoneLive: !!phone?.contentDocument?.querySelector('#demo > div:not([inert])') };
  });
  report.push(`${label}: demo here: ${JSON.stringify(after)}`);
  assert.deepEqual(after.flying, first.flying, `${label}: what flies changed as the demo took over`);
  assert.equal(after.hiddenInList, 4, `${label}: the demo's own rows show in its list while their copies fly`);
  // Taken over as it was built: nothing thrown, nothing said wrong (a page that does not hydrate is drawn again whole).
  assert.deepEqual(said.filter((m) => m.startsWith('error')), [], `${label}: errors as the page was taken over`);

  // Played through: the rows land, then (wide) the phone comes to the front.
  for (const at of [0.35, 1]) {
    await page.evaluate((f) => { const s = document.querySelector('[data-idea="1"] section[style]'); window.scrollTo(0, s.offsetTop + (s.offsetHeight - innerHeight) * f); }, at);
    await page.waitForTimeout(700);
    await shot(page, `${label}-3-scrolled-${at}`);
  }
  await context.close();
}

await browser.close();
server.close();
console.log(report.join('\n'));
