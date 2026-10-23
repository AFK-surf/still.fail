// A folder dragged in the files' columns (DriveViews.tsx ColumnsView), in the stories (文件 · 分栏): the folder shown says
// "松开移到" over the space beside the columns, and says nothing once a column takes the drag instead. The list kept saying
// it, dropped in a column, until the next drag (a column stops the drag on its way up, so the list never heard of it
// again). A column under the pointer is marked while it takes the drag, unmarked once dropped.
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
  dist = await mkdtemp(join(tmpdir(), 'drive-drop-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
  await page.goto(`${base}?story=app-files-deep&theme=light`);
  await page.locator('[aria-label="文件"]').filter({ visible: true }).first().click();
  await page.getByText('主目录', { exact: true }).filter({ visible: true }).first().click();
  const list = page.locator('[data-view="columns"]');
  const row = list.locator('[draggable="true"]').filter({ hasText: 'code' }).first();
  await row.click();
  await list.locator('[draggable="true"]').filter({ hasText: 'acme' }).first().waitFor();

  /** What the list says a drop does there (none: nothing), and how many columns are marked as taking it. */
  const said = () => page.evaluate(() => ({
    list: document.querySelector('[data-view="columns"]').getAttribute('data-dragging') ?? 'none',
    marked: document.querySelectorAll('[data-view="columns"] [data-drop]').length,
  }));
  const r = await row.boundingBox();
  const l = await list.boundingBox();
  // Beside the columns (no column there), then down the first column under its rows.
  const beside = { x: l.x + l.width - 40, y: l.y + 400 };
  const inColumn = { x: r.x + 40, y: l.y + 400 };

  await page.mouse.move(r.x + 10, r.y + r.height / 2);
  await page.mouse.down();
  await page.mouse.move(r.x + 30, r.y + r.height / 2, { steps: 5 });
  await page.mouse.move(beside.x, beside.y, { steps: 15 });
  assert.deepEqual(await said(), { list: 'move', marked: 0 }, 'beside the columns: into the folder shown');
  await page.mouse.move(inColumn.x, inColumn.y, { steps: 15 });
  assert.deepEqual(await said(), { list: 'none', marked: 1 }, 'in a column: the column takes it, the list says nothing');
  await page.mouse.up();
  await page.waitForFunction(() => !document.querySelector('[data-view="columns"]').hasAttribute('data-dragging'), null, { timeout: 5000 });
  assert.deepEqual(await said(), { list: 'none', marked: 0 }, 'dropped in the column: nothing said or marked');
  console.log('ok: a folder dragged beside the columns and dropped in one leaves nothing said over the list');
  await page.close();
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
