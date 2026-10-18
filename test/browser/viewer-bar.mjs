// The bar along a viewer's top on a wide screen with a mouse (ViewerBar.tsx), in the stories: a picture (图片预览), a
// film playing (播放器) and a screen driven (屏幕 · 控制), whose bars fade as the pointer rests. In the desktop app the bar
// drags the window, and where it does the page hears nothing of the pointer; so it drags only while the pointer is on
// it (held): the bar stays then though nothing more is heard (macOS), or the page is told the pointer left it (Windows),
// and lets go, fading again, once the pointer is heard back on what is shown. Gone, it neither drags nor takes the
// pointer: nothing under it out of reach. The page's clock is run on by hand (Playwright's), so nothing here waits on time.
// PLAYWRIGHT_MODULE selects Playwright (PLAYWRIGHT_CHANNEL a Chrome the machine has, as CI's).
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
/** Longer than any rest a bar waits out (viewer/rest.ts REST_MS). */
const REST = 5000;
let server, browser, dist;
try {
  const configFile = fileURLToPath(new URL('../../web/vite.stories.config.ts', import.meta.url));
  dist = await mkdtemp(join(tmpdir(), 'viewer-bar-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  const cases = [
    { story: 'preview-picture', shown: '[role=dialog] img' },
    { story: 'player', shown: 'video', start: () => { const v = document.querySelector('video'); v.muted = true; return v.play(); } },
    { story: 'screen-live', shown: 'canvas' },
  ];
  for (const { story, shown, start } of cases) {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
    await page.goto(`${base}?story=${story}&theme=light`);
    await page.locator(shown).first().waitFor();
    if (start) await page.evaluate(start);
    // As in the desktop app (its drag regions are styled under [data-desktop]).
    await page.evaluate(() => { document.documentElement.dataset.desktop = 'inset'; });
    await page.clock.install();
    const bar = page.locator('header').filter({ has: page.locator('button[aria-label]') }).first();
    const state = () => bar.evaluate((el) => ({ hidden: el.hasAttribute('data-hidden'), drags: getComputedStyle(el).getPropertyValue('-webkit-app-region') === 'drag' }));
    const is = async (want, why) => assert.deepEqual(await state(), want, `${story}: ${why}`);
    /** The page told the pointer left it at (x, y), as Windows tells it of the pointer gone into a drag region. */
    const leave = (x, y) => page.evaluate(([x, y]) => {
      document.elementFromPoint(x, y).dispatchEvent(new PointerEvent('pointerout', { bubbles: true, pointerType: 'mouse', clientX: x, clientY: y, relatedTarget: null }));
    }, [x, y]);

    // Woken by the pointer just under it (a screen driven wakes it only there), then at rest on what is shown.
    await page.mouse.move(640, 60);
    await page.mouse.move(640, 400);
    await page.clock.runFor(REST);
    await is({ hidden: true, drags: false }, 'gone as the pointer rests on what is shown, dragging nothing');
    // Onto the bar's middle (its name): heard coming, held, dragging; then nothing more is heard of the pointer.
    await page.mouse.move(640, 300);
    await page.mouse.move(640, 20, { steps: 4 });
    // (A screen driven brings its bar only as the pointer gets there: it is heard once it has slid in, the pointer moving on.)
    while (await bar.evaluate((el) => el.getBoundingClientRect().top !== 0)) await new Promise((ok) => setTimeout(ok, 20));
    await page.mouse.move(644, 20);
    await is({ hidden: false, drags: true }, 'the pointer on it: there, dragging the window');
    await page.clock.runFor(REST);
    await is({ hidden: false, drags: true }, 'stays while the pointer is on it, nothing more heard');
    await leave(640, 20);
    await page.clock.runFor(REST);
    await is({ hidden: false, drags: true }, 'stays as the page is told the pointer left it there');
    // Back on what is shown: let go, and gone again at rest.
    await page.mouse.move(640, 400, { steps: 4 });
    await is({ hidden: false, drags: false }, 'the pointer back on what is shown: no longer dragging');
    await page.clock.runFor(REST);
    await is({ hidden: true, drags: false }, 'gone again as the pointer rests');
    await page.close();
    console.log(`ok: ${story}: the bar drags only while the pointer is on it, and stays then`);
  }
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
