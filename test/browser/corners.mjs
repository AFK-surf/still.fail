// Every corner in the app, measured (docs/ui-panels.md, "every rounded box"): in the demo's pages and states (wide and
// phone, the sidebar open, folded and shown a while, the panels that open), each rounded thing that stands in a corner
// of the rounded box drawn round it is as far from both edges of that corner and rounded as the box less that distance
// (concentric). Not a list of panels: whatever is drawn is measured, so a new one is too. Runs its own Vite fixture with
// the demo core, as agent-sheet.mjs does. PLAYWRIGHT_MODULE selects Playwright; SHOTS keeps a picture of each state;
// REPORT=1 prints every mismatch (grouped) instead of failing on the first state.
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const fixture = new URL('../../web/corners-check.tsx', import.meta.url);
const html = new URL('../../web/corners-check.html', import.meta.url);
let server, browser;
const made = [];

/** In the page: each rounded thing in a corner of the rounded box round it, and how it is off. */
function measure() {
  const px = (v) => parseFloat(v) || 0;
  const drawn = (cs) => {
    const bg = cs.backgroundColor;
    const hasBg = bg && bg !== 'transparent' && !/rgba\([^)]*,\s*0\)$/.test(bg);
    return hasBg || px(cs.borderTopWidth) > 0 || (cs.boxShadow && cs.boxShadow !== 'none') || cs.backdropFilter !== 'none';
  };
  const radius = (cs) => Math.max(px(cs.borderTopLeftRadius), px(cs.borderTopRightRadius), px(cs.borderBottomLeftRadius), px(cs.borderBottomRightRadius));
  const name = (el) => (el.className && el.className.toString().split(' ').find((c) => /__/.test(c))?.replace(/__.*/, '')) || el.tagName.toLowerCase();
  /** What shows of it: cut by what clips between it and `upTo`. */
  const shown = (el, upTo) => {
    const b = el.getBoundingClientRect();
    const r = { left: b.left, right: b.right, top: b.top, bottom: b.bottom };
    for (let a = el.parentElement; a && a !== upTo; a = a.parentElement) {
      const o = getComputedStyle(a);
      if (o.overflowX === 'visible' && o.overflowY === 'visible') continue;
      const c = a.getBoundingClientRect();
      r.left = Math.max(r.left, c.left); r.right = Math.min(r.right, c.right); r.top = Math.max(r.top, c.top); r.bottom = Math.min(r.bottom, c.bottom);
    }
    return r.right - r.left >= b.width - 0.5 && r.bottom - r.top >= b.height - 0.5 ? b : null;
  };
  const wrong = [];
  let measured = 0;
  for (const el of document.querySelectorAll('body *')) {
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || px(cs.opacity) === 0 && cs.opacity !== '') continue;
    const re = radius(cs);
    if (re < 0.5) continue;
    // What shows a ground of its own (now, or while pointed at: what is pressed); not a picture or a mark.
    if (/^(IMG|SVG|VIDEO|CANVAS)$/i.test(el.tagName)) continue;
    const pressed = el.matches('button, a[href], [role=button], [role=menuitem], [role=menuitemradio], [role=menuitemcheckbox], [role=option], [role=tab], input, textarea, select, summary');
    if (!drawn(cs) && !pressed) continue;
    const b = el.getBoundingClientRect();
    if (b.width < 8 || b.height < 8) continue;
    // The rounded box drawn round it.
    let box = el.parentElement, bs = null;
    while (box && box !== document.body) {
      bs = getComputedStyle(box);
      if (radius(bs) >= 0.5 && drawn(bs)) break;
      box = box.parentElement;
    }
    if (!box || box === document.body) continue;
    const r = shown(el, box);
    if (!r) continue;
    const c = box.getBoundingClientRect();
    const rb = radius(bs);
    const inL = c.left + px(bs.borderLeftWidth), inR = c.right - px(bs.borderRightWidth), inT = c.top + px(bs.borderTopWidth), inB = c.bottom - px(bs.borderBottomWidth);
    const gl = r.left - inL, gr = inR - r.right, gt = r.top - inT, gb = inB - r.bottom;
    if (Math.min(gl, gr, gt, gb) < -0.5) continue; // reaching out of it (a badge on its edge): not in its corner
    // In a corner: within the box's curve of both edges that meet there.
    const corners = [['top left', gl, gt, 'borderTopLeftRadius'], ['top right', gr, gt, 'borderTopRightRadius'], ['bottom left', gl, gb, 'borderBottomLeftRadius'], ['bottom right', gr, gb, 'borderBottomRightRadius']];
    for (const [where, g1, g2, prop] of corners) {
      // Its corner as drawn (no more than half its side), and what stands in it: within a little over half of that from
      // both edges (further in, it is beside the corner, not in it).
      const rbc = Math.min(px(bs[prop]), c.width / 2, c.height / 2);
      if (rbc < 0.5 || g1 > rbc * 0.6 || g2 > rbc * 0.6) continue;
      measured++;
      const who = `${name(box)} › ${name(el)} (${where})`;
      if (Math.abs(g1 - g2) > 1) { wrong.push(`${who}: ${g1.toFixed(1)} from the side, ${g2.toFixed(1)} from the ${where.split(' ')[0]}`); continue; }
      const own = Math.min(px(cs[prop]), r.height / 2, r.width / 2), want = Math.min(Math.max(rbc - g1, 0), r.height / 2, r.width / 2);
      if (Math.abs(own - want) > 1) wrong.push(`${who}: rounded ${own.toFixed(1)}, ${g1.toFixed(1)} in from a corner of ${rbc.toFixed(1)} (wants ${want.toFixed(1)})`);
    }
  }
  return { measured, wrong };
}

try {
  await writeFile(fixture, `import './src/styles/index.ts';
import { mountDemo } from './src/demo/mount.tsx';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
mountDemo(root);
`, { flag: 'wx' });
  made.push(fixture);
  await writeFile(html, '<!doctype html><html lang="zh"><div id="app"></div><script type="module" src="/corners-check.tsx"></script></html>', { flag: 'wx' });
  made.push(html);
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false }, logLevel: 'error' });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  // A Chrome the machine has (CI's Linux runner: PLAYWRIGHT_CHANNEL=chrome), or Playwright's own.
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  /** The states looked at, from a fresh page each: [name, viewport, steps]. */
  const wide = { width: 1280, height: 800 }, phone = { width: 390, height: 844 };
  const click = (sel, opts) => async (p) => { await p.locator(sel).filter({ visible: true }).first().click(opts); await p.waitForTimeout(500); };
  const hover = (sel) => async (p) => { await p.locator(sel).filter({ visible: true }).first().hover(); await p.waitForTimeout(800); };
  const key = (k) => async (p) => { await p.locator('textarea').first().click(); await p.keyboard.press(k); await p.waitForTimeout(500); };
  const states = [
    ['chat', wide, []],
    ['filter menu', wide, [click('[aria-label^="筛选会话"]')]],
    ['chat info', wide, [click('[aria-label="对话信息"]')]],
    ['jobs', wide, [click('[aria-label="服务和后台任务"]')]],
    ['workspace menu', wide, [click('[aria-label="新建 workspace、添加账号"]')]],
    ['rail menu', wide, [click('[aria-label="文件"]', { button: 'right' })]],
    ['rail adder', wide, [click('[aria-label="文件"]', { button: 'right' }), click('text=自定义侧边条')]],
    ['station card', wide, [async (p) => { await p.locator('header').getByText(/Studio|这台机器/).first().hover(); await p.waitForTimeout(900); }]],
    ['⌘K', wide, [key('ControlOrMeta+k')]],
    ['sidebar folded', wide, [click('[aria-label="对话"]')]],
    ['sidebar shown a while', wide, [click('[aria-label="对话"]'), hover('[aria-label="对话"]'), async (p) => { await p.mouse.move(150, 60); await p.waitForTimeout(600); }]],
    ['files', wide, [click('[aria-label="文件"]')]],
    ['settings', wide, [click('[aria-label="设置"]')]],
    ['new chat', wide, [click('text=新建对话')]],
    ['station', wide, [click('[aria-label^="Station"]')]],
    ['phone chat', phone, []],
  ];
  const all = [];
  for (const [name, viewport, steps] of states) {
    const page = await browser.newPage({ viewport, deviceScaleFactor: 1, locale: 'zh-CN' });
    await page.goto(base + '/corners-check.html');
    await page.waitForTimeout(2200);
    let ok = true;
    for (const step of steps) { try { await step(page); } catch (e) { ok = false; console.log(`${name}: could not get there (${e.message.split('\n')[0]})`); break; } }
    if (ok) {
      const got = await page.evaluate(measure);
      console.log(`${name}: ${got.measured} corner(s) measured, ${got.wrong.length} off`);
      for (const w of got.wrong) all.push(`${name}: ${w}`);
      if (out) await page.screenshot({ path: `${out}/corners-${name.replace(/\W+/g, '-')}.png` });
    }
    await page.close();
  }
  const unique = [...new Set(all.map((w) => w.replace(/^[^:]+: /, '')))];
  if (process.env.REPORT) { console.log(`\n${unique.length} distinct:`); for (const w of unique) console.log('  ' + w); }
  else assert.deepEqual(unique, []);
  console.log('ok: every corner concentric with the box round it');
} finally {
  await browser?.close();
  await server?.close();
  for (const f of made) await rm(f);
}
