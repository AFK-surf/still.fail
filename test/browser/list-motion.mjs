// Run against pnpm dev:web --host 127.0.0.1 --port 5187. Uses the real list hook and sidebar styles with synthetic rows.
import { writeFileSync, rmSync, mkdirSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/list-motion-check.tsx', import.meta.url);
const html = new URL('../../web/list-motion-check.html', import.meta.url);
let browser;
try {
  writeFileSync(fixture, `
import React, { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { useListMotion } from './listMotion.ts';
import * as nav from './Sidebar.css.ts';
import './styles/index.ts';
function List() {
  const [rows, setRows] = useState([1, 2, 3, 4]);
  const [tick, setTick] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  useListMotion(ref);
  Object.assign(window, { remove: () => flushSync(() => setRows(r => r.filter(n => n !== 2))),
    refresh: () => flushSync(() => setTick(t => t + 1)),
    // The glass band measured into the list's padding after the rows were first placed (Sidebar.tsx useGlassBands).
    shift: () => { ref.current!.style.paddingTop = '60px'; flushSync(() => setTick(t => t + 1)); } });
  return <div className={nav.sidebar} style={{ width: 280, height: 340 }}>
    <div className={nav.navSlider}><div className={nav.navTrack}>
    <div className={nav.navScroll} ref={ref} data-tick={tick}>
      <div className={nav.navHeading} data-flip="day">今天</div>
      {rows.map(n => <div className={nav.navSessionWrap} key={n} data-flip={String(n)}>
        <div className={nav.navRow + ' ' + nav.navSession}><span className={nav.navSessionText}>
          <span className={nav.navSessionHead}>会话 {n}</span><span className={nav.navSessionMeta}>归档动画测试</span>
        </span></div>
      </div>)}
    </div></div></div>
  </div>;
}
createRoot(document.getElementById('root')!).render(<List />);
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/list-motion-check.tsx"></script>', { flag: 'wx' });
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  for (const reducedMotion of ['no-preference', 'reduce']) for (const refresh of [false, true]) {
    const context = await browser.newContext({ viewport: { width: 360, height: 400 }, reducedMotion,
      ...(process.env.RECORD_DIR ? { recordVideo: { dir: process.env.RECORD_DIR, size: { width: 360, height: 400 } } } : {}) });
    const page = await context.newPage();
    await page.clock.install({ time: new Date('2026-01-01T00:00:00Z') });
    await page.clock.pauseAt(new Date('2026-01-01T00:00:00Z'));
    await page.goto(new URL('/list-motion-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
    await page.waitForFunction(() => typeof window.remove === 'function');
    await page.clock.runFor(300);
    const sampling = page.evaluate(async ({ refresh, capture }) => {
      const row = document.querySelector('[data-flip="3"]');
      const startY = row.getBoundingClientRect().top;
      window.remove();
      if (capture) for (const a of document.getAnimations()) { a.pause(); a.currentTime = 0; }
      const start = performance.now(), samples = [];
      // Model status snapshots arriving while the archive animation is in flight.
      const interval = refresh ? setInterval(() => window.refresh(), 32) : undefined;
      await new Promise(resolve => {
        function sample() {
          samples.push({ t: performance.now() - start, y: row.getBoundingClientRect().top,
            ghost: !!document.querySelector('[data-leaving]') });
          if (performance.now() - start < 700) requestAnimationFrame(sample); else resolve();
        }
        requestAnimationFrame(sample);
      });
      clearInterval(interval);
      return { startY, samples };
    }, { refresh, capture: !!process.env.FRAMES_DIR });
    if (process.env.FRAMES_DIR && reducedMotion === 'no-preference' && !refresh) {
      mkdirSync(process.env.FRAMES_DIR, { recursive: true });
      for (let frame = 0; frame < 46; frame++) {
        await page.clock.runFor(16);
        await page.evaluate(time => { for (const a of document.getAnimations()) a.currentTime = time; }, (frame + 1) * 16);
        await page.screenshot({ path: process.env.FRAMES_DIR + '/' + String(frame).padStart(3, '0') + '.png' });
      }
    } else await page.clock.runFor(750);
    const samples = await sampling;
    if (process.env.RECORD_DIR) {
      mkdirSync(process.env.RECORD_DIR, { recursive: true });
      writeFileSync(process.env.RECORD_DIR + '/' + reducedMotion + '-' + refresh + '.json', JSON.stringify(samples));
      await page.screenshot({ path: process.env.RECORD_DIR + '/' + reducedMotion + '-' + refresh + '.png' });
    }
    const { startY, samples: frames } = samples;
    const early = frames.find(s => s.t >= 65);
    if (reducedMotion === 'no-preference') {
      assert(frames.some(s => s.ghost), 'departure is animated');
      assert(early.y < startY - 2, 'neighbours begin closing with the fade, without a second delayed phase');
      assert(frames.find(s => s.t >= 450).y <= frames.at(-1).y + 1, 'status updates must not keep restarting the spring');
      for (let i = 1; i < frames.length; i++) assert(frames[i].y <= frames[i - 1].y + 0.5, 'no backwards jump');
    } else {
      assert(frames.every(s => !s.ghost), 'reduced motion has no ghost');
      assert(frames.every(s => Math.abs(s.y - frames.at(-1).y) < 0.5), 'reduced motion settles immediately');
    }
    assert(startY - frames.at(-1).y > 40, 'the archived row closes completely');
    console.log('PASS', reducedMotion, { refresh });
    await context.close();
  }
  // The same rows in the same order, moved by the list's own layout (its padding, its width): no motion, they are there.
  {
    const context = await browser.newContext({ viewport: { width: 360, height: 400 } });
    const page = await context.newPage();
    await page.goto(new URL('/list-motion-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
    await page.waitForFunction(() => typeof window.shift === 'function');
    await page.waitForTimeout(300);
    const { before, after } = await page.evaluate(async () => {
      const row = document.querySelector('[data-flip="3"]');
      const before = row.getBoundingClientRect().top;
      window.shift();
      await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
      const after = row.getBoundingClientRect().top;
      await new Promise(r => setTimeout(r, 1000));
      return { before: row.getBoundingClientRect().top - before, after: after - before };
    });
    assert(before > 40 && Math.abs(after - before) < 0.5, `a layout shift is taken at once (moved ${after}px of ${before} two frames later)`);
    console.log('PASS layout shift');
    await context.close();
  }
} finally {
  await browser?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
