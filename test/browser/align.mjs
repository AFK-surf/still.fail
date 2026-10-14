// Surfaces measured as drawn (web/src/styles/align.ts, case 1): in the demo's pages, every surface open (a menu, a
// popover, ⌘K) has its corner its padding and its inner corner together, and what sits at one of its corners is
// rounded by the inner corner and stands as far from both edges. Runs its own Vite fixture with the demo core, as
// agent-sheet.mjs does. PLAYWRIGHT_MODULE selects Playwright; SHOTS optionally keeps pictures.
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const fixture = new URL('../../web/align-check.tsx', import.meta.url);
const html = new URL('../../web/align-check.html', import.meta.url);
let server, browser;
const made = [];
try {
  await writeFile(fixture, `import './src/styles/index.ts';
import { mountDemo } from './src/demo/mount.tsx';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
mountDemo(root);
`, { flag: 'wx' });
  made.push(fixture);
  await writeFile(html, '<!doctype html><html lang="zh"><div id="app"></div><script type="module" src="/align-check.tsx"></script></html>', { flag: 'wx' });
  made.push(html);
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false }, logLevel: 'error' });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2, locale: 'zh-CN' });
  await page.goto(base + '/align-check.html');
  await page.waitForTimeout(2500);

  /** Every open surface's corner and what sits at its corners, as drawn: the mismatches, said. */
  const measure = () => page.evaluate(() => {
    const px = (v) => parseFloat(v) || 0;
    const resolve = (el, value) => {
      const probe = document.createElement('div');
      probe.style.cssText = `position:absolute;visibility:hidden;width:${value}`;
      el.appendChild(probe);
      const w = probe.getBoundingClientRect().width;
      probe.remove();
      return w;
    };
    const wrong = [];
    let surfaces = 0, corners = 0;
    for (const s of document.querySelectorAll('body *')) {
      const cs = getComputedStyle(s);
      // A surface says its own --panel-pad (what sits in it only inherits it) and is padded by it.
      const padVar = cs.getPropertyValue('--panel-pad').trim();
      const parentVar = s.parentElement ? getComputedStyle(s.parentElement).getPropertyValue('--panel-pad').trim() : '';
      if (!padVar || padVar === parentVar || !s.getClientRects().length) continue;
      if (Math.abs(px(cs.paddingRight) - resolve(s, 'var(--panel-pad)')) > 0.5) continue;
      surfaces++;
      const pad = resolve(s, 'var(--panel-pad)'), inner = resolve(s, 'var(--panel-in)');
      const name = s.className.toString().split(' ')[0];
      const outer = px(cs.borderTopLeftRadius);
      if (Math.abs(outer - (inner + pad)) > 0.5) wrong.push(`${name}: corner ${outer}, not ${inner} + ${pad}`);
      const box = s.getBoundingClientRect(), border = px(cs.borderRightWidth);
      const right = box.right - border - pad, bottom = box.bottom - border - pad, left = box.left + border + pad, top = box.top + border + pad;
      for (const d of s.querySelectorAll('*')) {
        const r = d.getBoundingClientRect();
        const dr = px(getComputedStyle(d).borderBottomRightRadius);
        if (!r.width || !dr) continue;
        const atRight = Math.abs(r.right - right) < 0.75, atBottom = Math.abs(r.bottom - bottom) < 0.75;
        const atLeft = Math.abs(r.left - left) < 0.75, atTop = Math.abs(r.top - top) < 0.75;
        if (!((atRight || atLeft) && (atTop || atBottom))) continue;
        corners++;
        if (Math.abs(dr - inner) > 0.5) wrong.push(`${name} › ${d.className.toString().split(' ')[0] || d.tagName}: corner ${dr} at the surface's corner, not ${inner}`);
      }
    }
    return { surfaces, corners, wrong };
  });

  const checks = [
    ['filter menu', async () => page.locator('[aria-label="筛选会话：全部"]').click()],
    ['chat info', async () => page.locator('[aria-label="对话信息"]').click()],
    ['⌘K', async () => { await page.locator('textarea').first().click(); await page.keyboard.press('Meta+k'); }],
  ];
  const failures = [];
  for (const [name, open] of checks) {
    await open();
    await page.waitForTimeout(500);
    const got = await measure();
    console.log(`${name}: ${got.surfaces} surface(s), ${got.corners} thing(s) at a corner`);
    if (out) await page.screenshot({ path: `${out}/align-${name.replace(/\W+/g, '-')}.png` });
    assert.ok(got.surfaces > 0, `${name}: no surface found open`);
    failures.push(...got.wrong.map((w) => `${name}: ${w}`));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
  }
  assert.deepEqual(failures, []);
  console.log('ok: every surface concentric with what sits at its corners');
} finally {
  await browser?.close();
  await server?.close();
  for (const f of made) await rm(f);
}
