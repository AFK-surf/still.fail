// A login card's device code, pressed (web/src/MachineLogins.tsx CardCode), on the stories' login-card-device, wide and
// at a phone's width: it is copied, a toast says so, nothing opens; by keyboard too (focused, Enter, Space); it has no
// ground at rest nor under the pointer (docs/ui-panels.md: nothing new to round). Builds the stories as stories.mjs does.
// PLAYWRIGHT_MODULE / PLAYWRIGHT_CHANNEL as there.
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
  dist = await mkdtemp(join(tmpdir(), 'stories-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});
  for (const viewport of [{ width: 1280, height: 800 }, { width: 390, height: 844 }]) {
    const ctx = await browser.newContext({ viewport, locale: 'zh-CN', permissions: ['clipboard-read', 'clipboard-write'] });
    await ctx.addInitScript(() => { window.open = (url) => { (window.__opened ??= []).push(String(url)); return null; }; });
    const page = await ctx.newPage();
    await page.goto(new URL(`?story=login-card-device&theme=light`, base).href);
    const code = page.locator('[data-login-code]');
    await code.waitFor({ timeout: 20000 });
    const shown = (await code.textContent()).trim();
    const at = `${viewport.width} wide`;
    assert.match(shown, /^[A-Z0-9]{4}-[A-Z0-9]{4}$/, `${at}: the card shows a code`);
    assert.equal(await code.evaluate((e) => e.tagName), 'BUTTON', `${at}: the code is a button`);
    assert.match(await code.getAttribute('aria-label'), /复制验证码/, `${at}: named for what it does`);
    assert.equal(await code.evaluate((e) => getComputedStyle(e).cursor), 'pointer', `${at}: a pointer's hand over it`);
    const ground = () => code.evaluate((e) => getComputedStyle(e).backgroundColor);
    assert.equal(await ground(), 'rgba(0, 0, 0, 0)', `${at}: no ground at rest`);
    await code.hover();
    assert.equal(await ground(), 'rgba(0, 0, 0, 0)', `${at}: no ground under the pointer`);
    await page.evaluate(() => navigator.clipboard.writeText(''));
    await code.click();
    await page.getByText('验证码已复制', { exact: true }).waitFor({ timeout: 3000 });
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), shown, `${at}: pressed, the code is copied`);
    assert.deepEqual(await page.evaluate(() => window.__opened ?? []), [], `${at}: pressing the code opens nothing`);
    for (const key of ['Enter', 'Space']) {
      await page.evaluate(() => navigator.clipboard.writeText(''));
      await code.focus();
      await page.keyboard.press(key);
      await page.waitForFunction((want) => navigator.clipboard.readText().then((t) => t === want), shown, { timeout: 3000 });
    }
    await ctx.close();
  }
  console.log('PASS');
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
