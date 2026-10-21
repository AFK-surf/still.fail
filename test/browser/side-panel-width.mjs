// A chat's side panel, opened (pages/ChatSide.tsx useSidePanel), leaves the page to its styles once it is in: the window
// narrowed afterwards, the chat keeps its 360 and the panel gives way (styles/session.css.ts). With reduced motion the
// slide's last width stayed on the page: the panel kept the width it opened at, and the chat beside it was crushed to a
// strip, its composer to a column (in the stories: 执行历史).
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
  dist = await mkdtemp(join(tmpdir(), 'side-panel-width-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  for (const reducedMotion of ['reduce', 'no-preference']) {
    const page = await browser.newPage({ viewport: { width: 1600, height: 800 }, locale: 'zh-CN', reducedMotion });
    // A panel dragged wide: wider than the narrowed window leaves it beside the chat's 360.
    await page.addInitScript(() => localStorage.setItem('stillfail.width.--panel-w', '670'));
    await page.goto(`${base}?story=app-chat&theme=light`);
    const tile = page.locator('[aria-label$="的执行历史"]').filter({ visible: true }).first();
    await tile.click();
    await page.waitForFunction(() => document.querySelector('[data-over-composer]')?.getBoundingClientRect().width === 670);
    await page.setViewportSize({ width: 1197, height: 800 });
    const laid = () => page.evaluate(() => {
      const chat = document.querySelector('section[data-avoid-previews]').getBoundingClientRect();
      const panel = document.querySelector('[data-over-composer]').getBoundingClientRect();
      const grid = document.querySelector('[data-panel]');
      return { chat: chat.width, panel: panel.width, inline: grid.style.gridTemplateColumns };
    });
    // At rest (the slide over, whenever it ends): nothing of it left on the page, and the chat its 360.
    try {
      await page.waitForFunction(() => document.querySelector('[data-panel]').style.gridTemplateColumns === ''
        && document.querySelector('section[data-avoid-previews]').getBoundingClientRect().width >= 360, null, { timeout: 10000 });
    } catch {
      assert.fail(`${reducedMotion}: at rest, the slide's width is off the page and the chat keeps 360 beside the panel: ${JSON.stringify(await laid())}`);
    }
    const at = await laid();
    console.log(`ok (${reducedMotion}): the window narrowed, the chat keeps ${at.chat}px and the panel gives way to ${at.panel}px`);
    await page.close();
  }
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
