// A picture's preview on a wide screen with a mouse (the stories' 图片预览): the bar along its top fades as the pointer
// rests on the picture, and stays while it is on the bar, though the page hears nothing of it there (in the desktop app
// the bar drags the window: the pointer seems to rest, or to have left the page; ViewerBar.tsx byBar). The page's clock
// is run on by hand (Playwright's), so nothing here waits on time.
// PLAYWRIGHT_MODULE selects Playwright (PLAYWRIGHT_CHANNEL a Chrome the machine has, as CI's).
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
/** Longer than any rest the bar waits out (viewer/rest.ts REST_MS). */
const REST = 5000;
let server, browser, dist;
try {
  const configFile = fileURLToPath(new URL('../../web/vite.stories.config.ts', import.meta.url));
  dist = await mkdtemp(join(tmpdir(), 'viewer-bar-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
  await page.goto(`${base}?story=preview-picture&theme=light`);
  await page.locator('[role=dialog] img').first().waitFor();
  await page.clock.install();
  const bar = page.locator('[role=dialog] header').first();
  const hidden = () => bar.evaluate((el) => el.hasAttribute('data-hidden'));
  /** The pointer leaving the page from where it is, at (x, y): as the page hears it go into the window's drag region. */
  const leave = (x, y) => page.evaluate(([x, y]) => {
    const from = document.elementFromPoint(x, y);
    from.dispatchEvent(new PointerEvent('pointerout', { bubbles: true, pointerType: 'mouse', clientX: x, clientY: y, relatedTarget: null }));
  }, [x, y]);

  // At rest on the picture: gone.
  await page.mouse.move(640, 400);
  await page.clock.runFor(REST);
  assert.equal(await hidden(), true, 'the bar fades as the pointer rests on the picture');
  // To the bar's middle (its name, where the window is dragged), resting there: it stays.
  await page.mouse.move(640, 20);
  assert.equal(await hidden(), false, 'the bar comes back as the pointer moves');
  await page.clock.runFor(REST);
  assert.equal(await hidden(), false, 'the bar stays while the pointer rests on it');
  // The page told the pointer left it there (as the desktop app's drag region does): it stays.
  await leave(640, 20);
  await page.clock.runFor(REST);
  assert.equal(await hidden(), false, 'the bar stays when the pointer goes into it as the window drags');
  // Back on the picture and out of the page below: gone at once.
  await page.mouse.move(640, 700);
  assert.equal(await hidden(), false);
  await leave(640, 700);
  assert.equal(await hidden(), true, 'the bar goes as the pointer leaves the page away from it');
  console.log('ok: a picture\'s bar fades on the picture, stays on the bar (heard or not)');
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
