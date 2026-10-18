// The bar along a viewer's top on a wide screen with a mouse (ViewerBar.tsx), in the stories. In the desktop app it
// drags the window, and over it the page hears nothing of the pointer: what lies under it is out of reach. So a picture
// (图片预览) and a screen (屏幕 · 控制) lie below it, the bar always there; a film (播放器), seen whole, has the bar fade
// over it as it plays, and stay while the pointer is on it, heard there or not (in the app the pointer seems to rest
// there, or to have left the page; ViewerBar.tsx byBar). The page's clock is run on by hand (Playwright's), so nothing
// here waits on time.
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
  const open = async (story, shown) => {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
    await page.goto(`${base}?story=${story}&theme=light`);
    await page.locator(shown).first().waitFor();
    await page.clock.install();
    const bar = page.locator('header').filter({ has: page.locator('button[aria-label]') }).first();
    return { page, bar, hidden: () => bar.evaluate((el) => el.hasAttribute('data-hidden')) };
  };
  /** The pointer leaving the page from (x, y): as the page hears it go into the window's drag region. */
  const leave = (page, x, y) => page.evaluate(([x, y]) => {
    document.elementFromPoint(x, y).dispatchEvent(new PointerEvent('pointerout', { bubbles: true, pointerType: 'mouse', clientX: x, clientY: y, relatedTarget: null }));
  }, [x, y]);
  /** What holds `shown` (clipping it) begins below the bar. */
  const below = (page, shown) => page.locator(shown).first().evaluate((el) => {
    const bar = [...document.querySelectorAll('header')].find((h) => h.querySelector('button[aria-label]')).getBoundingClientRect();
    let clip = el.parentElement;
    while (clip && getComputedStyle(clip).overflow !== 'hidden') clip = clip.parentElement;
    return { bar: bar.bottom, top: clip.getBoundingClientRect().top };
  });

  // A picture and a screen: below the bar, which stays as the pointer rests, on what is shown or on the bar.
  for (const [story, shown] of [['preview-picture', '[role=dialog] img'], ['screen-live', 'canvas']]) {
    const { page, hidden } = await open(story, shown);
    const at = await below(page, shown);
    assert.ok(at.top >= at.bar - 0.5, `${story}: what is shown begins below the bar (${at.top} < ${at.bar})`);
    for (const y of [400, 20]) {
      await page.mouse.move(640, y);
      await page.clock.runFor(REST);
      assert.equal(await hidden(), false, `${story}: the bar stays with the pointer at rest at ${y}`);
    }
    await leave(page, 640, 20);
    await page.clock.runFor(REST);
    assert.equal(await hidden(), false, `${story}: the bar stays as the pointer goes into it`);
    await page.close();
    console.log(`ok: ${story} below its bar, which stays`);
  }

  // A film, playing: the bar fades over it, and stays while the pointer is on it.
  {
    const { page, hidden } = await open('player', 'video');
    await page.evaluate(() => { const v = document.querySelector('video'); v.muted = true; return v.play(); });
    await page.mouse.move(640, 400);
    await page.clock.runFor(REST);
    assert.equal(await page.evaluate(() => document.querySelector('video').paused), false, 'the film plays');
    assert.equal(await hidden(), true, 'the bar fades as the pointer rests on the film');
    await page.mouse.move(640, 20);
    await page.clock.runFor(REST);
    assert.equal(await hidden(), false, 'the bar stays while the pointer rests on it');
    await leave(page, 640, 20);
    await page.clock.runFor(REST);
    assert.equal(await hidden(), false, 'the bar stays when the pointer goes into it as the window drags');
    await page.mouse.move(640, 700);
    await leave(page, 640, 700);
    assert.equal(await hidden(), true, 'the bar goes as the pointer leaves the page away from it');
    await page.close();
    console.log('ok: player: the bar fades over the film, stays on the bar (heard or not)');
  }
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
