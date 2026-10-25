// The wheel over the files' columns (DriveViews.tsx ColumnsView), in the stories (文件 · 分栏), on a window short enough
// that the first column has more than it shows: a wheel over it scrolls it alone, and one over a column with nothing
// more to show scrolls nothing. The page under the columns was taller than the window (they were as tall as the window
// less a guess at the head over them), so a wheel over a column at its end went on to the page and every column moved
// up together under the head.
// PLAYWRIGHT_MODULE selects Playwright (PLAYWRIGHT_CHANNEL a Chrome the machine has, as CI's).
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
let server, browser, dist;
try {
  const configFile = fileURLToPath(new URL('../../web/vite.stories.config.ts', import.meta.url));
  dist = await mkdtemp(join(tmpdir(), 'drive-columns-wheel-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  /** The files' page in columns, 主目录 › code › acme › web, on a page of its own (a wheel's gesture stays with the
   * scroller it began over a while: each case a page of its own, as a new gesture). */
  const opened = async () => {
    const page = await browser.newPage({ viewport: { width: 1280, height: 360 }, locale: 'zh-CN' });
    await page.goto(`${base}?story=app-files-deep&theme=light`);
    await page.locator('[aria-label="文件"]').filter({ visible: true }).first().click();
    await page.getByText('主目录', { exact: true }).filter({ visible: true }).first().click();
    const list = page.locator('[data-view="columns"]');
    for (const name of ['code', 'acme', 'web']) {
      await list.locator('[draggable="true"]').filter({ hasText: name }).last().click();
    }
    await list.locator('[draggable="true"]').filter({ hasText: 'vite.config.ts' }).first().waitFor();
    /** How far the page and each column are scrolled, and where each column is on the window. */
    const where = () => page.evaluate(() => {
      const columns = [...document.querySelectorAll('[data-view="columns"] > * > * > :first-child')];
      const pageEl = document.querySelector('[data-view="columns"]').closest('section');
      return { page: pageEl.scrollTop, sizes: columns.map((c) => `${c.scrollHeight}/${c.clientHeight}`), scrolled: columns.map((c) => c.scrollTop), tops: columns.map((c) => Math.round(c.getBoundingClientRect().top)) };
    });
    /** The wheel turned down over the row named `text`, then until the page has settled. */
    const wheelOver = async (text) => {
      const box = await list.locator('[draggable="true"]').filter({ hasText: text }).last().boundingBox();
      await page.mouse.move(box.x + 20, box.y + box.height / 2);
      for (let i = 0; i < 6; i++) await page.mouse.wheel(0, 120);
      await page.waitForFunction(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(() => done(true)))));
    };
    return { page, where, wheelOver };
  };

  {
    const { page, where, wheelOver } = await opened();
    const before = await where();
    assert.ok(before.scrolled.length >= 3, `the columns: ${JSON.stringify(before)}`);
    await wheelOver('vite.config.ts');
    await page.waitForTimeout(400);
    assert.deepEqual(await where(), before, 'a wheel over the last column, which shows all it has: nothing moves');
    await page.close();
  }
  {
    const { page, where, wheelOver } = await opened();
    const before = await where();
    await wheelOver('Documents');
    await page.waitForFunction(() => document.querySelector('[data-view="columns"] > * > * > :first-child').scrollTop > 0);
    const after = await where();
    assert.equal(after.page, 0, 'the page itself never scrolls');
    assert.deepEqual(after.tops, before.tops, 'no column moves on the window');
    assert.deepEqual(after.scrolled.slice(1), before.scrolled.slice(1), `the other columns where they were: ${JSON.stringify(after)}`);
    await page.close();
  }
  console.log('ok: a wheel over a files column scrolls that column alone, never the page under them');
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
