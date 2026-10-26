// The bar along a viewer's top on a wide screen with a mouse (ViewerBar.tsx), in the stories: a picture (图片预览) and a
// film playing (播放器), whose bars fade as the pointer rests, and a screen driven (屏幕 · 控制), whose bar is always there
// with the picture below it (what is at the screen's top is never under it). A pointer resting on the bar is heard no
// more: the bar stays while the pointer is on it (held), and lets go, fading again, once the pointer is heard back on
// what is shown. The page's clock is run on by hand (Playwright's), so nothing here waits on time.
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
    { story: 'screen-live', shown: 'canvas', stays: true },
  ];
  for (const { story, shown, start, stays } of cases) {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
    await page.goto(`${base}?story=${story}&theme=light`);
    await page.locator(shown).first().waitFor();
    if (start) await page.evaluate(start);
    await page.clock.install();
    const bar = page.locator('header').filter({ has: page.locator('button[aria-label]') }).first();
    const state = () => bar.evaluate((el) => ({ hidden: el.hasAttribute('data-hidden') }));
    const is = async (want, why) => assert.deepEqual(await state(), want, `${story}: ${why}`);

    if (stays) {
      // Always there, the picture below it.
      await page.mouse.move(640, 400);
      await page.clock.runFor(REST);
      await is({ hidden: false }, 'there as the pointer rests on what is shown');
      await page.mouse.move(640, 20, { steps: 4 });
      await page.clock.runFor(REST);
      await is({ hidden: false }, 'there as the pointer rests on it');
      const top = await page.locator(shown).first().evaluate((el) => el.getBoundingClientRect().top);
      const bottom = await bar.evaluate((el) => el.getBoundingClientRect().bottom);
      assert.ok(top >= bottom, `${story}: the picture starts below the bar (${top} < ${bottom})`);
      await page.close();
      console.log(`ok: ${story}: the bar is always there, above the picture`);
      continue;
    }
    // Woken by the pointer just under it (a screen driven wakes it only there), then at rest on what is shown.
    await page.mouse.move(640, 60);
    await page.mouse.move(640, 400);
    await page.clock.runFor(REST);
    await is({ hidden: true }, 'gone as the pointer rests on what is shown');
    // Onto the bar's middle (its name): heard coming, held; then nothing more is heard of the pointer.
    await page.mouse.move(640, 300);
    await page.mouse.move(640, 20, { steps: 4 });
    await is({ hidden: false }, 'the pointer on it: there');
    await page.mouse.move(644, 20);
    await page.clock.runFor(REST);
    await is({ hidden: false }, 'stays while the pointer is on it, nothing more heard');
    // Back on what is shown: let go, and gone again at rest.
    await page.mouse.move(640, 400, { steps: 4 });
    await is({ hidden: false }, 'the pointer back on what is shown: there until it rests');
    await page.clock.runFor(REST);
    await is({ hidden: true }, 'gone again as the pointer rests');
    await page.close();
    console.log(`ok: ${story}: the bar stays while the pointer is on it, and goes as it rests on what is shown`);
  }
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
