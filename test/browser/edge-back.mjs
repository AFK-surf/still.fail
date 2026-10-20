// The actual mobile shell: edge taps reach controls, drags/cancelled swipes do not, and a browser-drawn back
// is not animated a second time. Runs its own Vite fixture with the demo core, without a station or network data.
// PLAYWRIGHT_MODULE selects Playwright; ENGINES defaults to chromium,webkit. SHOTS optionally keeps pictures.
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/edge-back-check.tsx', import.meta.url);
const html = new URL('../../web/edge-back-check.html', import.meta.url);
let server, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React, { useCallback } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Route, Routes, type Location } from 'react-router';
import './src/styles/index.ts';
import './src/demo/mount.tsx';
import { ACCOUNT } from './src/demo/station.ts';
import { setPageRoot } from './src/brand.tsx';
import { MobileShell, useApp } from './src/mobile/app.tsx';
import * as css from './src/mobile/app.css.ts';

Object.assign(window, { reviewEdge: css.mEdge, reviewClicks: 0, reviewMoves: [] });
function Page({ name }: { name: string }) {
  const app = useApp();
  Object.assign(window, { reviewApp: app });
  return <div style={{ height: '100%', padding: '90px 28px', background: name === 'home' ? '#eeece5' : '#f9f7f1', color: '#222' }}>
    <button data-review-back style={{ position: 'absolute', left: 0, top: 0, width: 70, height: 56 }} onClick={() => { (window as any).reviewClicks++; app.pop(); }}>返回</button>
    <h1>{name === 'home' ? '列表' : name === 'one' ? '第一层页面' : '第二层页面'}</h1>
    <p>手机页面的返回手势</p>
    <button onClick={() => app.push('/w/demo/one')}>打开第一层</button>
    <button onClick={() => app.push('/w/demo/two')}>打开第二层</button>
    <button data-review-target style={{ position: 'absolute', left: 0, top: 170, width: 150, height: 80 }} onClick={() => { (window as any).reviewClicks++; }}>测试点按</button>
  </div>;
}
function App() {
  const routes = useCallback((location: Location) => <Routes location={location}>
    <Route path='/w/demo' element={<Page name='home' />} />
    <Route path='/w/demo/one' element={<Page name='one' />} />
    <Route path='/w/demo/two' element={<Page name='two' />} />
  </Routes>, []);
  return <MobileShell entry={{ id: 'demo', name: 'Review', account: ACCOUNT }} routes={routes} recent={() => null} />;
}
history.replaceState(null, '', '/w/demo');
const root = document.getElementById('app')!;
setPageRoot(root);
new MutationObserver(() => {
  for (const p of document.querySelectorAll('[data-role="in"], [data-role="out"]')) (window as any).reviewMoves.push(p.getAttribute('data-role'));
}).observe(root, { subtree: true, attributes: true, attributeFilter: ['data-role'], childList: true });
createRoot(root).render(<BrowserRouter><App /></BrowserRouter>);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/edge-back-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (process.env.SHOTS) await mkdir(process.env.SHOTS, { recursive: true });
const frames = page => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
for (const engine of (process.env.ENGINES || 'chromium,webkit').split(',')) {
  const type = playwright[engine];
  const browser = await type.launch();
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  await context.addInitScript(() => {
    window.addEventListener('popstate', e => {
      if (window.reviewUA) Object.defineProperty(e, 'hasUAVisualTransition', { value: true });
      window.reviewUA = false;
    }, { capture: true });
  });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => { errors.push(e.message); console.error(engine, e.message); });
  const settle = async () => {
    await page.waitForFunction(() => !!document.querySelector('[data-role="top"]') && !document.querySelector('[data-role="in"], [data-role="out"]'));
    await frames(page);
  };
  const open = async path => {
    await page.evaluate(path => window.reviewApp.push(path), path);
    await page.waitForFunction(path => window.reviewApp.current === path, path);
    await settle();
  };
  const gesture = async (points, cancel = false) => {
    const edge = await page.evaluate(() => '.' + window.reviewEdge);
    await page.locator(edge).waitFor();
    if (engine === 'chromium') {
      const cdp = await context.newCDPSession(page);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: points[0][0], y: points[0][1] }] });
      for (const [x, y] of points.slice(1)) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y }] });
        await frames(page);
      }
      await cdp.send('Input.dispatchTouchEvent', { type: cancel ? 'touchCancel' : 'touchEnd', touchPoints: [] });
      await cdp.detach();
    } else {
      await page.locator(edge).evaluate(el => { el.setPointerCapture = () => {}; });
      await page.locator(edge).dispatchEvent('pointerdown', { pointerId: 1, pointerType: 'touch', clientX: points[0][0], clientY: points[0][1] });
      for (const [clientX, clientY] of points.slice(1)) {
        await page.locator(edge).dispatchEvent('pointermove', { pointerId: 1, pointerType: 'touch', clientX, clientY });
        await frames(page);
      }
      const [clientX, clientY] = points.at(-1);
      await page.locator(edge).dispatchEvent(cancel ? 'pointercancel' : 'pointerup', { pointerId: 1, pointerType: 'touch', clientX, clientY });
    }
    await frames(page);
    await page.evaluate(() => Promise.all([...document.querySelectorAll('[data-role="top"]')].flatMap(el => el.getAnimations().map(a => a.finished))));
  };
  try {
    await page.goto(base + '/edge-back-check.html');
    await page.waitForFunction(() => window.reviewApp?.current === '/w/demo');
    await open('/w/demo/one');
    const prevented = await page.evaluate(() => {
      const e = new Event('touchstart', { bubbles: true, cancelable: true });
      document.querySelector('.' + window.reviewEdge).dispatchEvent(e);
      return e.defaultPrevented;
    });
    assert.ok(prevented, 'edge touchstart cancels browser default');
    await gesture([[8, 210]]);
    assert.equal(await page.evaluate(() => window.reviewClicks), 1, 'tap passes through exactly once');
    await page.evaluate(() => { window.reviewClicks = 0; });
    await gesture([[8, 320], [8, 270], [8, 210]]);
    const verticalClicks = await page.evaluate(() => window.reviewClicks);
    await page.evaluate(() => { window.reviewClicks = 0; });
    await gesture([[8, 210], [90, 210], [8, 210]]);
    const returnedClicks = await page.evaluate(() => window.reviewClicks);
    console.log(JSON.stringify({ engine, verticalClicks, returnedClicks }));
    assert.equal(verticalClicks, 0, 'vertical drag must not become a tap');
    assert.equal(returnedClicks, 0, 'cancelled swipe must not become a tap');
    await page.evaluate(() => { window.reviewClicks = 0; });
    await gesture([[8, 210], [60, 210]], true);
    assert.equal(await page.evaluate(() => window.reviewClicks), 0, 'pointer cancel never clicks');
    await gesture([[8, 28]]);
    await page.waitForFunction(() => window.reviewApp.current === '/w/demo');
    await settle();
    await open('/w/demo/one');
    await open('/w/demo/two');
    await gesture([[8, 340], [70, 340], [140, 340], [230, 340]]);
    await page.waitForFunction(() => window.reviewApp.current === '/w/demo/one');
    await settle();
    await open('/w/demo/two');
    await page.evaluate(() => { window.reviewMoves = []; window.reviewUA = true; history.back(); });
    await page.waitForFunction(() => window.reviewApp.current === '/w/demo/one');
    await frames(page);
    assert.deepEqual(await page.evaluate(() => window.reviewMoves), [], 'UA transition is not animated again');
    await open('/w/demo/two');
    await page.evaluate(() => { window.reviewMoves = []; history.back(); });
    await page.waitForFunction(() => window.reviewApp.current === '/w/demo/one');
    await frames(page);
    assert.ok((await page.evaluate(() => window.reviewMoves)).includes('in'), 'ordinary back still animates');
    await settle();
    assert.deepEqual(errors, []);
    if (process.env.SHOTS) await page.screenshot({ path: `${process.env.SHOTS}/${engine}-edge-back.png` });
    console.log(`PASS ${engine}: edge taps, cancelled/vertical drags, back navigation, native-transition fallback`);
  } finally { await context.close(); await browser.close(); }
}

} finally {
  await server?.close();
  if (madeFixture) await rm(fixture);
  if (madeHtml) await rm(html);
}
