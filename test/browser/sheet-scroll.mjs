// The real sheet host, grabber and scrolling body: taking hold must leave the reader's place alone.
// Runs its own server. PLAYWRIGHT_MODULE and ENGINES select the browsers.
import assert from 'node:assert/strict';
import { writeFile, rm, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/sheet-scroll-check.tsx', import.meta.url);
const html = new URL('../../web/sheet-scroll-check.html', import.meta.url);
let server, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import './src/styles/index.ts';
import './src/demo/mount.tsx';
import { ACCOUNT } from './src/demo/station.ts';
import { setPageRoot } from './src/brand.tsx';
import { MobileShell, SheetGrab, SheetHead, useApp } from './src/mobile/app.tsx';
import * as css from './src/mobile/styles/sheets.css.ts';
function Page() {
  const app = useApp();
  return <button onClick={() => app.sheet({height: .55, draggable: true, content: () => <>
    <SheetGrab /><SheetHead title="面板的阅读位置" />
    <div className={css.mSheetScroll} data-list>
      {Array.from({length: 40}, (_, i) => <div key={i} data-row={i} style={{height: 48, padding: '12px 20px', boxSizing: 'border-box'}}>项目 {i + 1}</div>)}
    </div>
  </>})}>打开面板</button>;
}
history.replaceState(null, '', '/w/demo');
const root = document.getElementById('app')!;
setPageRoot(root);
createRoot(root).render(<BrowserRouter><MobileShell entry={{id: 'demo', name: 'Test', account: ACCOUNT}} routes={() => <Page />} recent={() => null} /></BrowserRouter>);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/sheet-scroll-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ cacheDir: fileURLToPath(new URL('../../node_modules/.vite-sheet-scroll', import.meta.url)), configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  const failures = [];
  for (const engine of (process.env.ENGINES || 'chromium,webkit').split(',')) {
    const browser = await playwright[engine].launch({timeout: 30000});
    try {
      for (const scrolled of [true, false]) {
        const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        await page.goto(base + '/sheet-scroll-check.html');
        await page.getByRole('button', { name: '打开面板' }).click();
        await page.locator('[data-draggable]').waitFor();
        await page.waitForFunction(() => { const sheet = document.querySelector('[data-list]')?.parentElement; return sheet?.hasAttribute('data-open'); });
        await page.evaluate(async scrolled => {
          await document.fonts.ready;
          for (const a of document.getAnimations()) a.finish();
          const list = document.querySelector('[data-list]');
          list.scrollTop = scrolled ? list.scrollHeight - list.clientHeight - 20 : 0;
        }, scrolled);
        const frames = () => page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
        await frames();
        const read = () => page.evaluate(() => {
          const list = document.querySelector('[data-list]'), sheet = list.parentElement;
          return { scroll: list.scrollTop, row: list.lastElementChild.getBoundingClientRect().top, top: sheet.getBoundingClientRect().top, height: sheet.offsetHeight };
        });
        const shot = async label => { if (process.env.SHEET_EVIDENCE && engine === 'chromium') { await mkdir(process.env.SHEET_EVIDENCE, {recursive:true}); await page.screenshot({path: process.env.SHEET_EVIDENCE + '/' + engine + '-' + (scrolled ? 'scrolled' : 'top') + '-' + label + '.png'}); } };
        const before = await read();
        await shot('before');
        const grab = await page.locator('[data-draggable]').boundingBox();
        await page.mouse.move(grab.x + grab.width / 2, grab.y + grab.height / 2);
        await page.mouse.down();
        await frames();
        const held = await read();
        await shot('held');
        console.log(JSON.stringify({engine, scrolled, before, held}));
        assert.equal(held.scroll, before.scroll, `${engine}: taking hold must not scroll the sheet's list`);
        assert.ok(Math.abs(held.row - before.row) < 1, `${engine}: taking hold must not move its visible content`);
        const heights = [];
        for (const dy of [10,20,30,40]) {
          await page.mouse.move(grab.x + grab.width / 2, grab.y + grab.height / 2 + dy);
          await frames();
          const moved = await read(); heights.push(moved.height);
          assert.equal(moved.scroll, before.scroll, 'dragging down keeps the reader’s place');
          assert.ok(Math.abs(moved.top - before.top - dy) < 1, 'sheet follows the finger');
        }
        if (!scrolled) assert.equal(new Set(heights).size, 1, 'unscrolled sheet moves without changing its layout height each frame');
        await shot('dragged');
        await page.mouse.up();
        await page.waitForFunction(() => { const sheet = document.querySelector('[data-list]').parentElement; return !sheet.hasAttribute('data-dragging') && !sheet.style.translate && Math.abs(sheet.getBoundingClientRect().height - innerHeight * .55) < 1; });
        await shot('settled');
        assert.deepEqual(errors, []);
        console.log(`PASS ${engine}/${scrolled ? 'scrolled' : 'top'}: stable reading, drag and settled height`);
        await page.close();
      }
    } catch (e) { console.error(engine, e); failures.push(e); } finally { await browser.close(); }
  }
  if (failures.length) throw new AggregateError(failures, 'Sheet reading position changed');
} finally {
  await server?.close();
  if (madeFixture) await rm(fixture);
  if (madeHtml) await rm(html);
}
