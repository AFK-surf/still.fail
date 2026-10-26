// Picking a passage of a message where it is, in a phone's chat (web/src/mobile/pick.tsx): a finger held on an agent's
// words picks the word under it and, sliding on, widens it while the list holds still; lifted, the passage has its
// handles and the bar (引用, 复制, 全选). Scrolling keeps it, the handles following; a tap elsewhere lets go of it; 引用
// puts it into the composer as a quote. Runs its own Vite fixture with the demo core, without a station or network data.
// PLAYWRIGHT_MODULE selects Playwright; SHOTS optionally keeps pictures (light and dark).
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const engine = process.env.BROWSER || 'chromium';
const fixture = new URL('../../web/pick-quote-check.tsx', import.meta.url);
const html = new URL('../../web/pick-quote-check.html', import.meta.url);
let server, browser, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import './src/styles/index.ts';
import { DemoApp } from './src/demo/mount.tsx';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
createRoot(root).render(<DemoApp phone />);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/pick-quote-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright[engine].launch({ executablePath: process.env.BROWSER_EXECUTABLE });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' });
  if (engine === 'chromium') await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: base });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => { errors.push(e.message); console.error(e.message); });
  await page.goto(base + '/pick-quote-check.html');
  const cdp = engine === 'chromium' ? await context.newCDPSession(page) : null;
  // WebKit has no CDP touch injection. Dispatch the long-press events to exercise the same picking code;
  // use actual mouse input for its handles below. This does not replace an iPhone gesture check.
  const touch = (type, x, y) => cdp
    ? cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] })
    : page.evaluate(({ type, x, y }) => {
      if (type === 'touchStart') window.checkTouchTarget = document.elementFromPoint(x, y);
      const target = window.checkTouchTarget;
      const points = type === 'touchEnd' ? [] : [{ identifier: 1, target, clientX: x, clientY: y }];
      const event = new Event(type.toLowerCase(), { bubbles: true, cancelable: true });
      Object.defineProperty(event, 'touches', { value: points });
      target.dispatchEvent(event);
    }, { type, x, y });
  const shot = async (name) => {
    if (!out) return;
    for (const theme of ['light', 'dark']) {
      await page.evaluate((theme) => { document.documentElement.dataset.theme = theme; }, theme);
      await page.waitForTimeout(100);
      await page.screenshot({ path: `${out}/${name}-${theme}.png` });
    }
    await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
  };

  // An agent's words, in view: a point on its first line of plain prose (not a link, not code), a few characters in.
  await page.locator('[data-role="agent"][data-ts]').first().waitFor({ timeout: 30000 });
  await page.waitForTimeout(800);
  const spot = await page.evaluate(() => {
    const rows = [...document.querySelectorAll('[data-role="agent"][data-ts]')];
    for (const row of rows.reverse()) {
      const r = row.getBoundingClientRect();
      if (r.top < 140 || r.bottom > 640) continue;
      const walker = document.createTreeWalker(row, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (node.data.trim().length < 12 || !node.parentElement.closest('p, li') || node.parentElement.closest('a, button, code')) continue;
        const range = document.createRange();
        range.setStart(node, 4);
        range.setEnd(node, 5);
        const box = range.getBoundingClientRect();
        if (box.top < 150 || box.bottom > 620 || box.width === 0) continue;
        let list = row.parentElement;
        while (list && !/auto|scroll/.test(getComputedStyle(list).overflowY)) list = list.parentElement;
        list.dataset.checkList = '';
        return { x: box.left + box.width / 2, y: box.top + box.height / 2, ts: row.dataset.ts };
      }
    }
    return null;
  });
  assert.ok(spot, 'an agent message with prose in view');
  const state = () => page.evaluate(() => {
    const h = CSS.highlights.get('chat-picked');
    const text = h ? [...h].map((r) => r.toString()).join('') : '';
    const seen = (el) => !!el && getComputedStyle(el).visibility !== 'hidden' && el.getBoundingClientRect().height > 0;
    const handles = [...document.querySelectorAll('span[data-pick]')];
    const bar = document.querySelector('div[data-pick]');
    return {
      text, handles: handles.filter(seen).length, handleTops: handles.map((x) => x.getBoundingClientRect().top),
      bar: seen(bar) ? [...bar.querySelectorAll('button')].map((b) => b.textContent) : null,
      scroll: document.querySelector('[data-check-list]').scrollTop,
    };
  });

  // Held: the word under the finger; sliding on along the line widens it, the list still.
  const before = await state();
  await touch('touchStart', spot.x, spot.y);
  await page.waitForTimeout(800);
  const held = await state();
  assert.ok(held.text.length > 0, 'holding picks the word under the finger');
  assert.equal(held.bar, null, 'no bar while the finger is down');
  for (let dx = 10; dx <= 90; dx += 10) { await touch('touchMove', spot.x + dx, spot.y + dx / 6); await page.waitForTimeout(30); }
  const widened = await state();
  assert.ok(widened.text.length > held.text.length, `sliding widens it (${JSON.stringify(held.text)} → ${JSON.stringify(widened.text)})`);
  assert.equal(widened.scroll, before.scroll, 'the list holds still while picking');
  await touch('touchEnd');
  await page.waitForTimeout(400);
  const lifted = await state();
  assert.equal(lifted.text, widened.text, 'lifting keeps it');
  assert.equal(lifted.handles, 2, 'both handles show');
  assert.deepEqual(lifted.bar, ['引用', '复制', '全选'], 'the bar offers 引用, 复制, 全选');
  await shot('selection-initial');
  // Drag both knobs: a small movement keeps the endpoint on its line rather than jumping to a hit-tested handle.
  for (const which of ['start', 'end']) {
    const handle = page.locator(`span[data-pick][data-end="${which}"]`);
    const box = await handle.boundingBox();
    const x = box.x + box.width / 2, y = which === 'start' ? box.y - 5 : box.y + box.height + 5;
    const prior = (await state()).text;
    const down = async () => { if (cdp) await touch('touchStart', x, y); else { await page.mouse.move(x, y); await page.mouse.down(); } };
    const move = (to) => cdp ? touch('touchMove', to, y) : page.mouse.move(to, y);
    const up = () => cdp ? touch('touchEnd') : page.mouse.up();
    await down();
    await page.waitForFunction(() => !document.querySelector('div[data-pick]'));
    // Other fingers neither take over this drag nor finish it when released or cancelled.
    for (const type of ['pointerdown', 'pointerup', 'pointercancel', 'lostpointercapture']) {
      await handle.evaluate((el, type) => el.dispatchEvent(new PointerEvent(type, {pointerId:99999, isPrimary:false, bubbles:true})), type);
      await page.evaluate(() => new Promise(requestAnimationFrame));
      assert.equal(await page.locator('div[data-pick]').count(), 0, `${type} from another pointer keeps the active drag`);
    }
    await move(x + 1);
    await up();
    await page.waitForTimeout(100);
    assert.equal((await state()).text, prior, 'a slight knob movement does not change the passage');
    await down();
    await move(x + (which === 'start' ? -16 : 16));
    await up();
    await page.waitForTimeout(100);
    assert.ok((await state()).text.length > prior.length, `${which} knob extends the passage`);
  }
  assert.ok(await page.locator('[data-pick-paint] > span').count() > 0, 'selection rectangles paint independently of CSS highlights');
  // Move the end back across lines to the first selected line, keeping the knob's grab offset.
  const target = await page.evaluate(() => {
    const range = [...CSS.highlights.get('chat-picked')][0];
    const r = [...range.getClientRects()].find((r) => r.width > 20);
    return { x: r.right - 8, y: r.top + r.height / 2, bottom: r.bottom };
  });
  const endHandle = page.locator('span[data-pick][data-end="end"]');
  const endBox = await endHandle.boundingBox();
  const knob = { x: endBox.x + endBox.width / 2, y: endBox.y + endBox.height + 5 };
  if (cdp) {
    await touch('touchStart', knob.x, knob.y);
    await touch('touchMove', target.x, target.y + endBox.height / 2 + 5);
    await touch('touchEnd');
  } else {
    await page.mouse.move(knob.x, knob.y);
    await page.mouse.down();
    await page.mouse.move(target.x, target.y + endBox.height / 2 + 5);
    await page.mouse.up();
  }
  await page.waitForTimeout(100);
  const movedEnd = await endHandle.boundingBox();
  assert.ok(Math.abs(movedEnd.y + movedEnd.height - target.bottom) < 2, 'dragging across lines lands on the requested line');
  const extended = await state();
  assert.equal(await page.locator('div[data-pick]').evaluate((el) => getComputedStyle(el).webkitUserSelect), 'none', 'the toolbar cannot become a native text selection');
  assert.equal(await page.locator('div[data-pick] button').first().evaluate((el) => getComputedStyle(el).webkitUserSelect), 'none', 'toolbar buttons cannot become native selections either');
  await shot('web-pick');

  // Scrolled: kept, the handles moving with the words.
  await page.evaluate(() => { const list = document.querySelector('[data-check-list]'); list.scrollTop -= 40; list.dispatchEvent(new Event('scroll')); });
  await page.waitForTimeout(300);
  const scrolled = await state();
  assert.equal(scrolled.text, extended.text, 'scrolling keeps the extended passage');
  assert.ok(Math.abs(scrolled.handleTops[0] - lifted.handleTops[0] - (lifted.scroll - scrolled.scroll)) < 2, `the handles follow (${lifted.handleTops[0]} → ${scrolled.handleTops[0]}, scrolled ${lifted.scroll - scrolled.scroll})`);
  await page.evaluate(() => { const list = document.querySelector('[data-check-list]'); list.scrollTop += 40; list.dispatchEvent(new Event('scroll')); });
  await page.waitForTimeout(300);

  // 全选: the whole message; then no 全选.
  await page.locator('div[data-pick]').getByRole('button', { name: '全选' }).tap();
  await page.waitForTimeout(300);
  const all = await state();
  assert.ok(all.text.length > lifted.text.length, 'all of the message picked');
  assert.deepEqual(all.bar, ['引用', '复制'], 'no 全选 once all is picked');

  // A tap elsewhere lets go.
  await page.touchscreen.tap(195, 400);
  await page.waitForTimeout(300);
  assert.equal((await state()).text, '', 'a tap elsewhere lets go of it');
  assert.equal((await state()).handles, 0, 'the handles go with it');

  // Picked again, 引用: into the composer as a quote, and let go of.
  await touch('touchStart', spot.x, spot.y);
  await page.waitForTimeout(800);
  for (let dx = 10; dx <= 60; dx += 10) { await touch('touchMove', spot.x + dx, spot.y); await page.waitForTimeout(30); }
  await touch('touchEnd');
  await page.waitForTimeout(400);
  const quoted = (await state()).text.trim();
  assert.ok(quoted.length > 0, 'picked again');
  await page.locator('div[data-pick]').getByRole('button', { name: '引用' }).tap();
  await page.waitForTimeout(600);
  assert.equal((await state()).text, '', 'quoting lets go of it');
  const inComposer = await page.evaluate(() => document.querySelector('[data-made-composer]')?.textContent ?? '');
  assert.ok(inComposer.includes(quoted), `the composer has the quote (${JSON.stringify(quoted)} in ${JSON.stringify(inComposer)})`);
  await page.keyboard.press('Escape').catch(() => {});
  await page.evaluate(() => document.activeElement?.blur());
  await page.waitForTimeout(300);
  await shot('web-quote');
  assert.deepEqual(errors, []);
  console.log(`ok: picked ${JSON.stringify(widened.text)} in place, quoted ${JSON.stringify(quoted)}`);
} finally {
  await browser?.close();
  await server?.close();
  if (madeFixture) await rm(fixture, { force: true });
  if (madeHtml) await rm(html, { force: true });
}
