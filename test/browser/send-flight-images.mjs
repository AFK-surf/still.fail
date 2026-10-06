// With `pnpm dev:web --host 127.0.0.1 --port 5187` running, check that images sent in an open chat fly from their
// thumbnails in the composer to their place in the row (with words, and alone). No station: the row is put in by hand.
// STRIP_DIR=<dir> also writes each case's frames (the flight's clock stepped 40 ms at a time) as strip-<case>.png.
// PLAYWRIGHT_MODULE / CHROMIUM_EXECUTABLE select tools.
import { writeFileSync, rmSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/send-flight-images-check.ts', import.meta.url);
const html = new URL('../../web/send-flight-images-check.html', import.meta.url);
let browser, madeFixture = false, madeHtml = false;
try {
  writeFileSync(fixture, `
import './styles/index.ts';
import { sendingHere } from './madeChat.ts';
import { chatMessages } from './Chat.css.ts';
import { msg, msgBubble, msgTime } from './styles/conversation.css.ts';
import { msgMine, msgPlain } from './styles/chat.css.ts';
const canvas = document.createElement('canvas');
canvas.width = 600; canvas.height = 400;
const g = canvas.getContext('2d')!;
const grad = g.createLinearGradient(0, 0, 600, 400);
grad.addColorStop(0, '#2e7dd7'); grad.addColorStop(1, '#f2a65a');
g.fillStyle = grad; g.fillRect(0, 0, 600, 400);
g.fillStyle = '#fff'; g.beginPath(); g.arc(180, 180, 90, 0, Math.PI * 2); g.fill();
const src = canvas.toDataURL();
const layer = document.createElement('div');
layer.style.cssText = 'position:relative;width:420px;height:640px;background:#fff;overflow:hidden';
layer.innerHTML = '<div id="list" style="position:absolute;inset:0 0 120px 0;display:flex;flex-direction:column;justify-content:flex-end;padding:12px"></div>' +
  '<div data-made-composer style="position:absolute;left:10px;right:10px;bottom:10px;padding:8px;border-radius:20px;background:#f3f3f3">' +
  '<span data-send-image="a.png" style="display:block;width:56px;height:56px;border-radius:12px;overflow:hidden"><img src="' + src + '" style="width:100%;height:100%;object-fit:cover"></span>' +
  '<textarea style="display:block;width:100%;border:0;background:none;font:15px/22px sans-serif;resize:none"></textarea></div>';
document.body.style.margin = '0';
document.body.append(layer);
const list = layer.querySelector<HTMLElement>('#list')!;
list.className = chatMessages;
const field = layer.querySelector('textarea')!;
Object.assign(window, { sendFlight(text: string) {
  field.value = text;
  list.replaceChildren();
  sendingHere(field, text, { layer, z: '4', list });
  // The draft empties: the thumbnail is gone from the composer.
  layer.querySelector('[data-made-composer] [data-send-image]')!.remove();
  field.value = '';
  const row = document.createElement('div');
  row.className = msg + ' ' + msgMine;
  row.innerHTML = (text ? '<div class="' + msgBubble + '"><div class="' + msgPlain + '">' + text + '</div></div>' : '') +
    '<button data-send-image="a.png" style="display:block;margin-left:auto;width:240px;height:160px;padding:0;border:0;border-radius:10px;overflow:hidden"><img src="' + src + '" style="width:100%;height:100%;object-fit:cover"></button>' +
    '<span class="' + msgTime + '">刚刚</span>';
  list.append(row);
  const box = layer.getBoundingClientRect();
  const rel = (r: DOMRect) => ({ x: r.left - box.left, y: r.top - box.top, w: r.width, h: r.height });
  return new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => {
    const target = rel(row.querySelector('[data-send-image]')!.getBoundingClientRect());
    resolve({ target });
  })));
} });
Object.assign(window, { stand() {
  const el = [...layer.querySelectorAll<HTMLElement>('[data-send-image]')].find(e => e.parentElement !== null && e.closest('#list') === null && e.closest('[data-made-composer]') === null && getComputedStyle(e).visibility !== 'hidden');
  const flying = [...layer.querySelectorAll<HTMLElement>('div[aria-hidden] > img')].map(i => i.parentElement!).find(p => p.style.position === 'absolute');
  const box = layer.getBoundingClientRect();
  if (!flying) return null;
  const r = flying.getBoundingClientRect();
  return { x: r.left - box.left, y: r.top - box.top, w: r.width, h: r.height, el: !!el };
} });
`, { flag: 'wx' });
  madeFixture = true;
  writeFileSync(html, '<script type="module" src="/src/send-flight-images-check.ts"></script>', { flag: 'wx' });
  madeHtml = true;
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  for (const [name, text] of [['with-words', 'Safari 上是这样的'], ['alone', '']]) {
    const page = await browser.newPage({ viewport: { width: 420, height: 640 }, deviceScaleFactor: 2 });
    await page.goto(new URL('/send-flight-images-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
    await page.waitForFunction(() => typeof window.sendFlight === 'function');
    const thumb = await page.evaluate(() => {
      const r = document.querySelector('[data-made-composer] [data-send-image]').getBoundingClientRect();
      return { x: r.left, y: r.top, w: r.width, h: r.height };
    });
    const { target } = await page.evaluate(t => window.sendFlight(t), text);
    // The flight's one clock, paused and stepped: each frame as it is at that point of it.
    const frames = [];
    const shots = [];
    // (Not to its very end, where it finishes and lets the row show itself.)
    for (const t of [0, 40, 80, 120, 160, 200, 240, 280, 320, 360, 400, 440, 480, 519.5]) {
      await page.evaluate(t => {
        for (const a of document.getAnimations()) { a.pause(); a.currentTime = t; }
      }, t);
      await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
      frames.push({ t, at: await page.evaluate(() => window.stand()) });
      if (process.env.STRIP_DIR) shots.push(await page.screenshot());
    }
    const first = frames[0].at;
    const last = frames.at(-1).at;
    assert(first && last, `${name}: the picture flies (${JSON.stringify(frames)})`);
    const near = (a, b) => Math.abs(a - b) < 1.5;
    assert(near(first.x, thumb.x) && near(first.y, thumb.y) && near(first.w, thumb.w) && near(first.h, thumb.h), `${name}: starts on its thumbnail ${JSON.stringify(first)} vs ${JSON.stringify(thumb)}`);
    assert(near(last.x, target.x) && near(last.y, target.y) && near(last.w, target.w) && near(last.h, target.h), `${name}: ends on its place ${JSON.stringify(last)} vs ${JSON.stringify(target)}`);
    const ys = frames.map(f => f.at.y);
    assert(ys.every((y, i) => i === 0 || y <= ys[i - 1] + 0.5), `${name}: rises without going back (${ys.join(' ')})`);
    if (process.env.STRIP_DIR) {
      const strip = await browser.newPage({ viewport: { width: 210 * shots.length, height: 320 } });
      await strip.setContent(`<body style="margin:0;display:flex">${shots.map(s => `<img style="width:210px;height:320px;border-right:1px solid #ccc" src="data:image/png;base64,${s.toString('base64')}">`).join('')}</body>`);
      await strip.screenshot({ path: `${process.env.STRIP_DIR}/strip-${name}.png` });
      await strip.close();
    }
    console.log('PASS', name);
    await page.close();
  }
} finally {
  await browser?.close();
  if (madeFixture) rmSync(fixture);
  if (madeHtml) rmSync(html);
}
