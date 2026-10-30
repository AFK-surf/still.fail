// The phone's bottom bar under random fingers (web/src/mobile/Bar.tsx): taps, slides, strokes up into the panel and
// over its rows, let go half way, the scrim, 令 — often the next before the last one's motion is over. After each
// settles, the bar must be in a state it can be in: the panel shut or open as the scrim says, nothing of a bar
// switch left over, the places drawn those of the bar in view, the ball over the place in view (or gone, with that
// place not in the bar). SEED=n replays a run; N gestures (default 60); RUNS seeds from SEED (default 3).
// PLAYWRIGHT_MODULE selects Playwright.
import { writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/bottom-bar-fuzz.tsx', import.meta.url);
const html = new URL('../../web/bottom-bar-fuzz.html', import.meta.url);
const N = +(process.env.N || 60), RUNS = +(process.env.RUNS || 3), SEED = +(process.env.SEED || 1);
let server, browser, made = false, failed = 0;
try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import './src/styles/index.ts';
import { DemoApp } from './src/demo/mount.tsx';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
createRoot(root).render(<DemoApp phone />);
`, { flag: 'wx' });
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/bottom-bar-fuzz.tsx"></script></html>', { flag: 'wx' });
  made = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  browser = await playwright.chromium.launch();
  for (let run = 0; run < RUNS; run++) {
    const seed = SEED + run;
    let s = seed;
    const rnd = () => ((s = (s * 1103515245 + 12345) % 2147483648) / 2147483648);
    const pick = (a) => a[Math.floor(rnd() * a.length)];
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, locale: 'zh-CN' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.goto(base + '/bottom-bar-fuzz.html');
    await page.locator('header').first().waitFor({ timeout: 30000 });
    await page.waitForTimeout(800);
    await page.getByRole('button', { name: /返回|会话/ }).first().tap();
    await page.locator('[data-tab]').first().waitFor();
    await page.waitForTimeout(800);
    const cdp = await context.newCDPSession(page);
    const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
    const check = () => page.evaluate(() => {
      const bad = [];
      const host = document.querySelector('[data-bar=host]');
      if (!host) return ['no bar'];
      const open = !!document.querySelector('[data-bar=scrim]');
      if (open !== host.hasAttribute('data-open')) bad.push('the scrim and the panel disagree');
      if (document.querySelector('[data-bar=stack]')) bad.push('a bar switch left half done');
      const glass = document.querySelector('[data-bar=glass]').getBoundingClientRect();
      const row = document.querySelector('[role=tablist]').getBoundingClientRect();
      if (!open && Math.abs(glass.top - row.top) > 1) bad.push(`closed, yet the glass reaches above the bar (${Math.round(row.top - glass.top)})`);
      if (open && glass.top > row.top - 40) bad.push('open, yet the glass is not up');
      const ball = document.querySelector('[data-bar=ball]'), shownBall = +getComputedStyle(ball).opacity > 0.5;
      const on = document.querySelector('[data-tab][aria-selected=true]');
      if (on && !shownBall) bad.push(`the ball is hidden though ${on.dataset.tab} is in view`);
      if (on && shownBall) {
        const a = ball.getBoundingClientRect(), t = on.getBoundingClientRect();
        const dx = (a.left + a.right) / 2 - (t.left + t.right) / 2, dy = (a.top + a.bottom) / 2 - (t.top + t.bottom) / 2;
        if (Math.hypot(dx, dy) > 2) bad.push(`the ball is off ${on.dataset.tab} by ${Math.round(dx)},${Math.round(dy)}`);
      }
      if (!on && shownBall && !open) bad.push('the ball is shown over no place');
      return bad;
    });
    const log = [];
    let backs = 0;
    for (let i = 0; i < N; i++) {
      const away = await page.locator('[data-bar=host][data-away]').count();
      // A page pushed over the place (令 opened a new chat, a tap let through to the page: a chat from 用量's
      // rows): back from it, not a gesture of the count. Its back is the top bar's button furthest up and left (返回, 取消,
      // or the name of the page under it); a chat's bar has its agent's activity before it in the page.
      if (away) {
        const back = await page.locator('[data-role=top] button').evaluateAll((es) => {
          const shown = es.map((e, i) => ({ i, r: e.getBoundingClientRect() })).filter(({ r }) => r.width > 0 && r.height > 0);
          shown.sort((a, b) => (Math.round(a.r.top / 8) - Math.round(b.r.top / 8)) || (a.r.left - b.r.left));
          return shown[0]?.i ?? 0;
        });
        await page.locator('[data-role=top] button').nth(back).tap({ timeout: 3000 }).catch(() => {});
        await page.waitForTimeout(900); i--; if (++backs > 5) throw new Error('could not get back to a place'); continue;
      }
      backs = 0;
      const row = await page.locator('[role=tablist]').boundingBox();
      const open = await page.locator('[data-bar=scrim]').count();
      const kind = pick(open ? ['tapRow', 'tapRowPlace', 'tapBar', 'stroke', 'scrim'] : ['tapBar', 'tapBar', 'stroke', 'swipeHalf', 'swipeFull', 'slide', 'ling']);
      log.push(kind);
      const cy = row.y + row.height / 2, x0 = row.x + 30 + rnd() * (row.width - 60);
      if (kind === 'tapBar') { const tabs = page.locator('[data-tab]'); const n = await tabs.count(); const r = await tabs.nth(Math.floor(rnd() * n)).boundingBox(); await page.touchscreen.tap(r.x + r.width / 2, r.y + r.height / 2); }
      if (kind === 'ling') { const l = page.locator('[data-action=ling]'); if (await l.count() && +(await l.evaluate((e) => getComputedStyle(e).opacity)) > 0.5) { const r = await l.boundingBox(); await page.touchscreen.tap(r.x + r.width / 2, r.y + r.height / 2); } }
      if (kind === 'scrim') await page.touchscreen.tap(195, 120);
      if (kind === 'tapRow' || kind === 'tapRowPlace') {
        const places = page.locator('[data-bar=rows] [data-place]');
        const n = await places.count();
        if (n) { const r = await places.nth(Math.floor(rnd() * n)).boundingBox(); await page.touchscreen.tap(kind === 'tapRow' ? 24 : r.x + r.width / 2, r.y + r.height / 2); }
      }
      if (['stroke', 'swipeHalf', 'swipeFull', 'slide'].includes(kind)) {
        const pts = kind === 'swipeHalf' ? [[x0, cy - 20 - rnd() * 40]] : kind === 'swipeFull' ? [[x0, cy - 150]] : kind === 'slide' ? [[row.x + 30 + rnd() * (row.width - 60), cy]] : [[row.x + rnd() * row.width, cy - rnd() * 140], [row.x + rnd() * row.width, cy - rnd() * 140]];
        await touch('touchStart', x0, cy);
        let [px, py] = [x0, cy];
        for (const [qx, qy] of pts) { for (let k = 1; k <= 8; k++) { await touch('touchMove', px + (qx - px) * k / 8, py + (qy - py) * k / 8); await page.waitForTimeout(12); } [px, py] = [qx, qy]; }
        await touch('touchEnd');
      }
      if (process.env.VERBOSE) console.log(`  ${i} ${kind}`);
      // Often the next gesture comes while this one's motion is still going.
      if (rnd() < 0.4 && i < N - 1) { await page.waitForTimeout(40 + rnd() * 250); continue; }
      await page.waitForTimeout(1300);
      const bad = await check();
      if (bad.length || errors.length) { console.error(`SEED=${seed} gesture ${i} (${log.slice(-5).join(' → ')}): ${[...bad, ...errors].join('; ')}`); failed++; break; }
    }
    console.log(`SEED=${seed}: ${log.length} gestures`);
    await context.close();
  }
  if (failed) process.exitCode = 1;
  else console.log('bottom bar fuzz: ok');
} finally {
  await browser?.close();
  await server?.close();
  if (made) { await rm(fixture); await rm(html); }
}
