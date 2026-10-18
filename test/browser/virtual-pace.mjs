// The real virtual-list hook: a following list that gets far more at its end than it shows goes there at once, and
// what it shows there is drawn coming in by the list's law (virtual/pace.ts): one frame loop, every row moving one way,
// never faster than the law allows, all of it where it is laid out at the end.
import assert from 'node:assert/strict';
import { writeFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin';
import { uiAlias } from '../../web/ui/alias.ts';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/virtual-pace-check.tsx', import.meta.url);
const html = new URL('../../web/virtual-pace-check.html', import.meta.url);
let server, browser;
try {
  writeFileSync(fixture, `
import React, { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { useVirtualList, useVirtualModel } from './src/virtual/list.tsx';
function List() {
  const pane = useRef<HTMLDivElement>(null);
  const [count, setCount] = useState(20);
  const made = useVirtualModel('pace-check', 28);
  const list = useVirtualList(pane, made, Array.from({ length: count }, (_, i) => ({ key: String(i), estimate: 100 })), { smooth: true });
  Object.assign(window, { model: list.model, append: () => flushSync(() => setCount(100)), toEnd: list.toEnd });
  return <div id="pane" ref={pane} style={{ height: 500, width: 700, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 28, padding: '24px 40px 140px', boxSizing: 'border-box' }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', height: 100 }}>Message {row.key}</div></React.Fragment>)}{list.after()}
  </div>;
}
createRoot(document.getElementById('root')!).render(<List />);
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/virtual-pace-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: false, root: fileURLToPath(new URL('../../web', import.meta.url)), plugins: [react(), vanillaExtractPlugin()], resolve: { alias: [uiAlias] }, server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage();
  const time = new Date('2026-01-01T00:00:00Z');
  await page.clock.install({ time });
  await page.clock.pauseAt(time);
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.addInitScript(() => {
    const request = requestAnimationFrame.bind(window), cancel = cancelAnimationFrame.bind(window);
    const loops = new Set();
    window.paceStats = { peak: 0, pending: () => loops.size };
    window.requestAnimationFrame = callback => {
      // Vite serves the source here, without minifying callback names.
      const loop = callback.name === 'step';
      const id = request(time => { loops.delete(id); callback(time); });
      if (loop) { loops.add(id); paceStats.peak = Math.max(paceStats.peak, loops.size); }
      return id;
    };
    window.cancelAnimationFrame = id => { loops.delete(id); cancel(id); };
  });
  await page.goto(server.resolvedUrls.local[0] + 'virtual-pace-check.html');
  await page.waitForFunction(() => window.model);
  // Past the hook's opening period, so what comes is drawn coming rather than placed at once.
  await page.clock.runFor(700);
  // Its pane measured (its size reported by the browser as it draws).
  for (let i = 0; i < 50 && !(await page.evaluate(() => model.paneWidth > 0)); i++) { await page.waitForTimeout(50); await page.clock.runFor(20); }
  const sampling = page.evaluate(async () => {
    const pane = document.getElementById('pane');
    const top = () => pane.querySelector('[data-vk="99"]')?.getBoundingClientRect().top ?? null;
    window.append();
    // (Put once its new rows are measured: in the frame they are drawn in. Before it, the pane still where it was.)
    await new Promise(requestAnimationFrame);
    const at = [];
    const first = { scrollTop: pane.scrollTop, target: model.target() };
    // Fixed frame count, with no repeated mutation: the motion must finish on its own.
    for (let i = 0; i < 120; i++) { at.push({ t: performance.now(), y: top() }); await new Promise(requestAnimationFrame); }
    const last = pane.querySelector('[data-vk="99"]');
    return { at, first, peak: paceStats.peak, pending: paceStats.pending(), offset: last?.style.translate ?? null, laidOut: last ? last.offsetTop - pane.scrollTop : null, y: top() };
  });
  await page.clock.runFor(6000);
  const result = await sampling;
  assert(Math.abs(result.first.scrollTop - result.first.target) < 1, `the pane goes to the end at once (${result.first.scrollTop} / ${result.first.target})`);
  assert.equal(result.peak, 1, 'one frame loop');
  assert.equal(result.pending, 0, 'it ends with no animation callbacks left');
  assert.equal(result.offset, '', 'drawn where it is laid out at the end');
  const seen = result.at.filter((s) => s.y !== null);
  assert(seen[0].y > seen.at(-1).y + 100, `the last row comes up from below (${seen[0].y} → ${seen.at(-1).y})`);
  for (let i = 1; i < seen.length; i++) {
    const d = seen[i].y - seen[i - 1].y, dt = Math.max(1, seen[i].t - seen[i - 1].t);
    assert(d <= 0.5, `one way only (${d}px at frame ${i})`);
    assert(-d / dt <= 1.2 * 1.05, `within the law's speed (${(-d / dt).toFixed(2)}px/ms at frame ${i})`);
  }
  assert.deepEqual(errors, []);
  console.log('PASS virtual pace: at the end at once, drawn coming one way within the law, one frame loop, settled');
} finally {
  await browser?.close();
  await server?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
