// A new device met face to face puts this one's code up wherever the person is (web/src/cloud/Security.tsx
// SecurityPrompt, web/src/mobile/Security.tsx): a dialog on the desktop, a sheet on a phone, kept up as pages change,
// naming every workspace it asks into (one not open among them), with no way to approve it here (only typing the code
// there does); done there, it goes; closed by hand, it is turned away (`lockPrompt.deny`).
// Runs the demo's app with its made-up core (a `lockPrompts` topic added to it here), without a station or network
// data.
// PLAYWRIGHT_MODULE selects Playwright (PLAYWRIGHT_CHANNEL a browser of the machine's); SHOTS optionally keeps pictures.
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const fixture = new URL('../../web/lock-prompt-check.tsx', import.meta.url);
const html = new URL('../../web/lock-prompt-check.html', import.meta.url);
// The demo's core, with the new devices showing a code (window.__prompts) and the lock calls kept (window.__calls);
// `lockPrompt.deny` puts it up no more, as the core does.
const withLock = {
  name: 'demo-lock',
  enforce: 'pre',
  transform(code, id) {
    if (!id.endsWith('/src/demo/mount.tsx')) return;
    return code
      .replace('    default:\n      if (import.meta.env.DEV)', '    case "lockPrompts": return (globalThis as any).__prompts ?? null;\n    default:\n      if (import.meta.env.DEV)')
      .replace(/function answer\(name: string, params: Record<string, unknown>[^{]*\{/, (head) => head + '\n  if (name.startsWith("lock")) { ((globalThis as any).__calls ??= []).push([name, params]); if (name === "lockPrompt.deny") { (globalThis as any).__prompts = { pairing: [] }; setTimeout(publish, 0); } return null; }')
      .replace('setTopicSource(valueOf);', 'setTopicSource(valueOf);\n(globalThis as any).__publish = () => publish();');
  },
};
// Asking into two workspaces of the person's: 日常 is not the one open.
const request = {
  device: 'cc'.repeat(32), email: 'lier@example.com', name: '李二', kind: 'app', label: 'still.fail 安卓版 · Pixel 8', code: 'K7F-2QX', created_at: Math.floor(Date.now() / 1000) - 60,
  workspaces: [{ id: 'w1', name: '3720' }, { id: 'w2', name: '日常', emoji: '☀️' }],
};
const lock = (pairing) => ({ pairing });
let server, browser, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import './src/styles/index.ts';
import { DemoApp } from './src/demo/mount.tsx';
import { setPageRoot } from './src/brand.tsx';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
setPageRoot(root);
createRoot(root).render(<DemoApp phone={location.search.includes('phone')} />);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/lock-prompt-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), plugins: [withLock], server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  for (const phone of [false, true]) {
    const context = await browser.newContext(phone
      ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' }
      : { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2, locale: 'zh-CN' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => { errors.push(e.message); console.error(e.message); });
    // Waiting from the start: put up as the app opens, wherever it is.
    await page.addInitScript((l) => { globalThis.__prompts = l; }, lock([request]));
    await page.goto(`${base}/lock-prompt-check.html${phone ? '?phone' : ''}`);
    const title = page.getByText('李二的新设备请求批准', { exact: true });
    await title.waitFor({ timeout: 30000 }).catch(async (e) => {
      if (out) await page.screenshot({ path: `${out}/failed-${phone ? 'phone' : 'desktop'}.png` });
      console.error('core patched:', await page.evaluate(() => typeof globalThis.__publish), 'calls:', JSON.stringify(await page.evaluate(() => globalThis.__calls ?? null)));
      throw e;
    });
    await page.waitForTimeout(600);
    assert.ok(await page.getByText('K7F-2QX', { exact: true }).isVisible(), 'it shows the code to type there');
    // Its mark (an emoji) beside its name.
    for (const name of ['3720', '☀️日常']) assert.ok(await page.getByText(name, { exact: true }).isVisible(), `it names ${name}`);
    assert.equal(await page.getByRole('button', { name: /批准/ }).count(), 0, 'nothing here approves it');
    const denied = async () => (await page.evaluate(() => globalThis.__calls ?? [])).filter(([n]) => n === 'lockPrompt.deny').map(([, p]) => p.device);
    assert.deepEqual(await denied(), [], 'not turned away just for coming up');
    if (out) await page.screenshot({ path: `${out}/${phone ? 'phone' : 'desktop'}.png` });
    if (out) {
      await page.evaluate(() => { document.documentElement.dataset.theme = 'dark'; });
      await page.screenshot({ path: `${out}/${phone ? 'phone' : 'desktop'}-dark.png` });
      await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
    }
    // Done on the new device: gone here.
    await page.evaluate((l) => { globalThis.__prompts = l; globalThis.__publish(); }, lock([]));
    await title.waitFor({ state: 'hidden', timeout: 5000 });
    // Another comes: up again; closed by hand, it is turned away.
    await page.evaluate((l) => { globalThis.__prompts = l; globalThis.__publish(); }, lock([request]));
    await title.waitFor({ timeout: 5000 });
    await page.waitForTimeout(600);
    if (phone) await page.touchscreen.tap(195, 60);
    else await page.keyboard.press('Escape');
    await title.waitFor({ state: 'hidden', timeout: 5000 });
    assert.deepEqual(await denied(), [request.device], 'closed by hand: turned away');
    assert.deepEqual(errors, []);
    await context.close();
    console.log(`ok: ${phone ? 'phone' : 'desktop'}`);
  }
} finally {
  await browser?.close();
  await server?.close();
  if (madeFixture) await rm(fixture, { force: true });
  if (madeHtml) await rm(html, { force: true });
}
