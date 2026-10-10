// A completed edge swipe hands both real MobileShell pages to their animations without changing their positions.
// Browser history can be held until the test lets it arrive; CSS animation frames and fallback timers are controlled.
// No station: a demo core and named pages. PLAYWRIGHT_MODULE and ENGINES select the browsers.
import assert from 'node:assert/strict';
import { writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/swipe-continue-check.tsx', import.meta.url);
const html = new URL('../../web/swipe-continue-check.html', import.meta.url);
let server, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React, { useCallback } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, useNavigate, type Location } from 'react-router';
import './src/styles/index.ts';
import './src/demo/mount.tsx';
import { ACCOUNT } from './src/demo/station.ts';
import { setPageRoot } from './src/brand.tsx';
import { MobileShell, useApp } from './src/mobile/app.tsx';
import * as css from './src/mobile/app.css.ts';
Object.assign(window, { reviewEdge: css.mEdge });
function Page({ path }: { path: string }) {
  const app = useApp();
  Object.assign(window, { reviewApp: app });
  return <div style={{ padding: '80px 28px' }}><h1>{path}</h1><p>手机页面返回</p></div>;
}
function App() {
  Object.assign(window, { reviewNavigate: useNavigate() });
  const routes = useCallback((location: Location) => <Page path={location.pathname} />, []);
  return <MobileShell entry={{ id: 'demo', name: 'Test', account: ACCOUNT }} routes={routes} recent={() => null} />;
}
history.replaceState(null, '', '/w/demo');
const root = document.getElementById('app')!;
setPageRoot(root);
createRoot(root).render(<BrowserRouter><App /></BrowserRouter>);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/swipe-continue-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  for (const engine of (process.env.ENGINES || 'chromium,webkit').split(',')) {
    const browser = await playwright[engine].launch();
    try {
      for (const route of ['one', 'settings', 'new', 'replaced', 'reduce', 'blocked']) {
        const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, reducedMotion: route === 'reduce' ? 'reduce' : 'no-preference' });
        const errors = [];
        page.on('pageerror', e => errors.push(e.message));
        await page.addInitScript(() => {
          // Both browsers also cover their real Navigation API in edge-back and preview-back. Here the fallback can
          // be held so the handoff is checked before and after the asynchronous history traversal.
          Object.defineProperty(window, 'navigation', { value: undefined, configurable: true });
          const go = history.go.bind(history);
          history.go = delta => {
            if (window.reviewHold && delta < 0) window.reviewRelease = () => go(delta);
            else go(delta);
          };
        });
        await page.clock.install({ time: new Date('2026-01-01T00:00:00Z') });
        await page.clock.pauseAt(new Date('2026-01-01T00:00:01Z'));
        await page.goto(base + '/swipe-continue-check.html');
        const until = async (predicate, message, argument) => {
          for (let frame = 0; frame < 60; frame++) {
            if (await page.evaluate(predicate, argument)) return;
            await page.clock.runFor(16);
          }
          assert.fail(`${engine}/${route}: ${message}`);
        };
        await until(() => window.reviewApp?.current === '/w/demo', 'fixture mounted');
        await page.addStyleTag({ content: '[data-role="in"], [data-role="out"] { animation-play-state: paused !important; }' });
        const settle = async () => {
          await page.evaluate(() => { for (const a of document.getAnimations()) a.finish(); });
          await page.clock.runFor(450);
          await until(() => !!document.querySelector('[data-role="top"]'), 'page settled');
        };
        const open = async path => {
          await page.evaluate(path => window.reviewApp.push(path), path);
          await until(path => window.reviewApp.current === path, 'route committed', path);
          await settle();
        };
        if (route === 'replaced') {
          await open('/w/demo/original');
          await page.evaluate(() => window.reviewNavigate('/w/demo/kept', { replace: true }));
          await until(() => window.reviewApp.current === '/w/demo/kept', 'replacement committed');
        }
        await open('/w/demo/' + (['replaced', 'reduce', 'blocked'].includes(route) ? 'one' : route));
        const snapshot = () => page.evaluate(() => [...document.querySelectorAll('[data-role]')].map(el => ({ role: el.dataset.role, x: el.getBoundingClientRect().x, y: el.getBoundingClientRect().y, visibility: getComputedStyle(el).visibility, way: el.dataset.way })));
        const edge = page.locator(await page.evaluate(() => '.' + window.reviewEdge));
        await edge.evaluate(el => { el.setPointerCapture = () => {}; });
        await page.evaluate(() => { window.reviewHold = true; });
        const point = { pointerId: 1, pointerType: 'touch', clientX: 8, clientY: 300 };
        await edge.dispatchEvent('pointerdown', point);
        await edge.dispatchEvent('pointermove', { ...point, clientX: 168 });
        await until(() => document.querySelector('[data-role="top"]')?.getBoundingClientRect().x === 160, 'drag committed');
        const dragged = await snapshot();
        await edge.dispatchEvent('pointerup', { ...point, clientX: 168 });
        await page.clock.runFor(100);
        assert.deepEqual(await snapshot(), dragged, `${engine}/${route}: both pages stay where the finger left them until history arrives`);
        if (route === 'blocked') {
          await page.clock.runFor(1000);
          await until(() => !document.querySelector('[data-swiping], [data-role="peek"]'), 'expired hold committed');
          await page.evaluate(async () => {
            document.querySelector('[data-role="top"]').getBoundingClientRect();
            const animations = document.getAnimations();
            for (const a of animations) a.finish();
            await Promise.allSettled(animations.map(a => a.finished));
          });
          const restored = await snapshot();
          assert.equal(restored.find(p => p.role === 'top').x, 0, 'failed back restores page');
          assert.ok(!restored.some(p => p.role === 'peek'), 'failed back hides underlying page');
          assert.deepEqual(errors, []);
          await page.close();
          console.log(`PASS ${engine}: blocked back recovers on its controlled timer`);
          continue;
        }
        await page.evaluate(() => window.reviewRelease());
        await until(() => !document.querySelector('[data-swiping]'), 'swipe handed to navigation');
        if (route === 'reduce') {
          const reduced = await snapshot();
          assert.equal(reduced.find(p => p.role === 'top').x, 0, 'reduced motion leaves no swipe transform');
          assert.ok(!reduced.some(p => p.role === 'out' || p.role === 'in'), 'reduced motion does not animate');
        } else {
          const start = await snapshot();
          console.log(JSON.stringify({ engine, route, dragged, start }));
          assert.equal(start.find(p => p.role === 'out')?.x, dragged.find(p => p.role === 'top').x, `${engine}/${route}: outgoing starts at released x`);
          assert.equal(start.find(p => p.role === 'in')?.x, dragged.find(p => p.role === 'peek').x, `${engine}/${route}: incoming starts at exposed x`);
          assert.ok(start.filter(p => ['in', 'out'].includes(p.role)).every(p => p.visibility === 'visible'), 'both pages are visible');
          let previous = start;
          for (let frame = 1; frame <= 12; frame++) {
            await page.evaluate(progress => { for (const el of document.querySelectorAll('[data-role="in"], [data-role="out"]')) for (const a of el.getAnimations()) a.currentTime = Number(a.effect.getTiming().duration) * progress; }, frame / 12);
            const current = await snapshot();
            for (const role of ['in', 'out']) {
              const p = current.find(p => p.role === role);
              assert.ok(p.x >= previous.find(p => p.role === role).x - 0.02, `${engine}/${route}: ${role} never reverses at frame ${frame}`);
              assert.equal(p.y, 0, 'edge swipe stays horizontal');
            }
            previous = current;
          }
          assert.equal(previous.find(p => p.role === 'out').x, 390, 'outgoing reaches the screen edge');
          assert.equal(previous.find(p => p.role === 'in').x, 0, 'incoming reaches its normal position');
          await settle();
          await page.evaluate(() => { window.reviewHold = false; });
          await open('/w/demo/' + (route === 'replaced' ? 'one' : route));
          await page.evaluate(() => window.reviewApp.pop());
          await until(() => !!document.querySelector('[data-role="out"]'), 'ordinary back committed');
          const ordinary = (await snapshot()).find(p => p.role === 'out');
          assert.equal(ordinary.way, route === 'settings' ? 'left' : route === 'new' ? 'rise' : 'side', 'button back retains the original entry direction');
          assert.equal(ordinary.x, 0, 'ordinary back does not inherit the last swipe');
          assert.equal(ordinary.y, 0, 'ordinary back starts at rest');
        }
        assert.deepEqual(errors, []);
        console.log(`PASS ${engine}: ${route} continues from the released positions`);
        await page.close();
      }
    } finally { await browser.close(); }
  }
} finally {
  await server?.close();
  if (madeFixture) await rm(fixture);
  if (madeHtml) await rm(html);
}
