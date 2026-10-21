// A folded sidebar shown a while over the page (Rail.tsx peekSidebar) in the desktop app on Windows (data-desktop
// "custom"), in the stories (侧栏收起后临时展开): nothing under it drags the window. Where the window drags, Windows takes
// the pointer and the page is told it left: the sidebar folded again as the pointer reached 新建对话, over the page's top
// row (shell.css.ts main), which drags the window. Folded again, the page's top row drags it as before.
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
  dist = await mkdtemp(join(tmpdir(), 'peek-drag-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
  await page.goto(`${base}?story=app-sidebar-peek&theme=light`);
  const place = page.locator('[aria-label="对话"]').filter({ visible: true }).first();
  await place.waitFor();
  // As in the desktop app on Windows (its drag regions are styled under [data-desktop]).
  await page.evaluate(() => { document.documentElement.dataset.desktop = 'custom'; });
  await place.click();
  await page.waitForFunction(() => document.documentElement.dataset.sidebar === 'closed');
  await place.hover();
  await page.waitForFunction(() => 'sidebarPeek' in document.documentElement.dataset);
  const newChat = page.getByText('新建对话', { exact: true }).filter({ visible: true }).first();
  await newChat.hover();

  /** The boxes that drag the window (elements, and their ::before and ::after), and the folded sidebar's (the rail's and 新建对话's block). */
  const regions = () => page.evaluate(() => {
    const drags = [];
    const box = (r) => ({ left: r.left, top: r.top, right: r.right, bottom: r.bottom });
    for (const el of document.querySelectorAll('*')) {
      const own = el.getBoundingClientRect();
      if (getComputedStyle(el).getPropertyValue('-webkit-app-region') === 'drag' && own.width > 0 && own.height > 0) drags.push({ what: el.className || el.tagName, ...box(own) });
      for (const pseudo of ['::before', '::after']) {
        const s = getComputedStyle(el, pseudo);
        if (s.content === 'none' || s.display === 'none' || s.getPropertyValue('-webkit-app-region') !== 'drag') continue;
        // Placed by its offsets in what holds it: the window (fixed), or its element (positioned here, as these are).
        const at = s.position === 'fixed' ? { left: 0, top: 0, width: innerWidth, height: innerHeight } : own;
        const n = (v) => (v === 'auto' ? 0 : parseFloat(v));
        const left = at.left + n(s.left), top = at.top + n(s.top);
        const width = parseFloat(s.width) || at.width - n(s.left) - n(s.right), height = parseFloat(s.height) || at.height - n(s.top) - n(s.bottom);
        if (width > 0 && height > 0) drags.push({ what: `${el.className || el.tagName}${pseudo}`, left, top, right: left + width, bottom: top + height });
      }
    }
    const row = [...document.querySelectorAll('a, button')].find((e) => e.textContent.trim() === '新建对话' && e.getClientRects().length > 0);
    const rail = document.querySelector('[aria-label="对话"]');
    let dock = row;
    while (dock && !dock.contains(rail)) dock = dock.parentElement;
    return { drags, dock: box(dock.getBoundingClientRect()), row: box(row.getBoundingClientRect()) };
  });
  const over = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

  const shown = await regions();
  assert.ok(shown.row.right > shown.dock.left + 56, `新建对话 shown in the sidebar beside the rail: ${JSON.stringify(shown)}`);
  const under = shown.drags.filter((d) => over(d, shown.dock));
  assert.deepEqual(under, [], 'nothing under the sidebar shown a while drags the window');
  console.log('ok: the sidebar shown a while has nothing dragging the window under it');

  // The pointer off it: folded again, and the page's top row drags the window again.
  await page.mouse.move(1000, 500, { steps: 4 });
  await page.waitForFunction(() => !('sidebarPeek' in document.documentElement.dataset));
  const folded = await regions();
  assert.ok(folded.drags.some((d) => d.top <= 0 && d.right >= 1000 && d.bottom >= 40), `the page's top row drags the window, folded again: ${JSON.stringify(folded.drags)}`);
  console.log('ok: folded again, the page\'s top row drags the window');
  await page.close();
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
