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
  // A Chrome the machine has (CI's Linux runner: PLAYWRIGHT_CHANNEL=chrome), or Playwright's own.
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2, locale: 'zh-CN' });
  await page.goto(base + '/align-check.html');
  await page.waitForTimeout(2500);

  /** Every open surface's corner and what sits at its corners, as drawn: the mismatches, said. */
  const measure = () => page.evaluate(() => {
    const px = (v) => parseFloat(v) || 0;
    const resolve = (el, value) => {
      const probe = document.createElement('div');
      probe.style.cssText = `position:absolute;visibility:hidden;padding:0;border:0;margin:0;width:${value}`;
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
      // A small panel (all but ⌘K, a dialog) is padded 6 (docs/ui-panels.md).
      const small = !/Switcher/.test(s.className.toString());
      if (small && Math.abs(pad - 6) > 0.5) wrong.push(`${name}: padded ${pad}, not 6`);
      const edgeLeft = s.getBoundingClientRect().left + px(cs.borderLeftWidth);
      // A panel of words: each block not at its padding stands in by a row's padding (10).
      if (small && cs.getPropertyValue('--panel-kind').trim() === 'card') {
        for (const c of s.children) {
          if (/panelEdge/.test(c.className.toString())) continue;
          const cc = getComputedStyle(c), who = `${name} › ${c.className.toString().split(' ')[0] || c.tagName}`;
          const pl = px(cc.paddingLeft);
          if (Math.abs(pl - 10) > 0.5) wrong.push(`${who}: words in by ${pl}, not 10`);
          // As far from the top and the foot as from the sides.
          if (c === s.firstElementChild && Math.abs(px(cc.paddingTop) - 10) > 0.5) wrong.push(`${who}: ${px(cc.paddingTop)} above the words, not 10`);
          if (c === s.lastElementChild && Math.abs(px(cc.paddingBottom) - 10) > 0.5) wrong.push(`${who}: ${px(cc.paddingBottom)} under the words, not 10`);
        }
      }
      // A row (as wide as the panel's room, at its padding, with words): its words in by a row's padding (10).
      if (small) {
        const room = s.getBoundingClientRect().width - 2 * px(cs.borderLeftWidth) - 2 * pad;
        for (const d of s.querySelectorAll('button, a, [role=menuitem], [role=option], [role=menuitemradio], [role=menuitemcheckbox]')) {
          const r = d.getBoundingClientRect();
          if (!r.width || Math.abs(r.left - edgeLeft - pad) > 0.6 || r.width < room * 0.8 || !d.textContent.trim()) continue;
          const pl = px(getComputedStyle(d).paddingLeft);
          if (pl < 9.5) wrong.push(`${name} › ${d.className.toString().split(' ')[0] || d.tagName}: a row's words in by ${pl}, not 10`);
        }
      }
      // What sits at one of its corners (within its padding of two edges that meet): as far from both, and rounded as
      // the surface's corner less that distance.
      const box = s.getBoundingClientRect(), border = px(cs.borderRightWidth);
      const near = pad + 1;
      for (const d of s.querySelectorAll('*')) {
        // As much of it as shows: cut by what scrolls or clips between it and the surface.
        const b = d.getBoundingClientRect();
        const r = { left: b.left, right: b.right, top: b.top, bottom: b.bottom };
        for (let a = d.parentElement; a && a !== s; a = a.parentElement) {
          const o = getComputedStyle(a);
          if (o.overflowX === 'visible' && o.overflowY === 'visible') continue;
          const c = a.getBoundingClientRect();
          r.left = Math.max(r.left, c.left); r.right = Math.min(r.right, c.right); r.top = Math.max(r.top, c.top); r.bottom = Math.min(r.bottom, c.bottom);
        }
        r.width = r.right - r.left; r.height = r.bottom - r.top;
        if (r.width <= 0 || r.height <= 0 || r.height < b.height - 0.5 || r.width < b.width - 0.5) continue;
        const dr = px(getComputedStyle(d).borderBottomRightRadius);
        if (!r.width || !r.height || !dr) continue;
        const gl = r.left - box.left - border, gr = box.right - border - r.right, gt = r.top - box.top - border, gb = box.bottom - border - r.bottom;
        const side = gl <= near ? gl : gr <= near ? gr : null, end = gt <= near ? gt : gb <= near ? gb : null;
        if (side === null || end === null || side < -0.5 || end < -0.5) continue;
        corners++;
        const who = `${name} › ${d.className.toString().split(' ')[0] || d.tagName}`;
        if (Math.abs(side - end) > 0.75) wrong.push(`${who}: ${side.toFixed(1)} from the side, ${end.toFixed(1)} from the top or foot`);
        else if (Math.abs(Math.min(dr, r.height / 2, r.width / 2) - Math.min(outer - side, r.height / 2, r.width / 2)) > 0.75) wrong.push(`${who}: corner ${dr} ${side.toFixed(1)} in from a corner of ${outer}`);
      }
    }
    return { surfaces, corners, wrong };
  });

  const checks = [
    ['filter menu', async () => page.locator('[aria-label="筛选会话：全部"]').click()],
    ['chat info', async () => page.locator('[aria-label="对话信息"]').click()],
    ['⌘K', async () => { await page.locator('textarea').first().click(); await page.keyboard.press('ControlOrMeta+k'); }],
    ['jobs', async () => page.locator('[aria-label="服务和后台任务"]').click()],
    ['workspace menu', async () => page.locator('[aria-label="新建 workspace、添加账号"]').click()],
    ['rail menu', async () => page.locator('[aria-label="文件"]').first().click({ button: 'right' })],
    ['rail adder', async () => { await page.locator('[aria-label="文件"]').first().click({ button: 'right' }); await page.waitForTimeout(300); await page.getByText('自定义侧边条').click(); }],
    ['station card', async () => { await page.mouse.move(1, 1); await page.locator('header').getByText(/Studio|这台机器/).first().hover(); await page.waitForTimeout(900); }],
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
