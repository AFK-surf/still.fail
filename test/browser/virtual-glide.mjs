// The real virtual-list hook: a following list crosses row boundaries without starting another glide.
import assert from 'node:assert/strict';
import { writeFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/virtual-glide-check.tsx', import.meta.url);
const html = new URL('../../web/virtual-glide-check.html', import.meta.url);
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
  const made = useVirtualModel('glide-check', 28);
  const list = useVirtualList(pane, made, Array.from({ length: count }, (_, i) => ({ key: String(i), estimate: 100 })), { smooth: true });
  Object.assign(window, { model: list.model, append: () => flushSync(() => setCount(100)), toEnd: list.toEnd });
  return <div id="pane" ref={pane} style={{ height: 500, width: 700, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 28, padding: '24px 40px 140px', boxSizing: 'border-box' }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', height: 100 }}>Message {row.key}</div></React.Fragment>)}{list.after()}
  </div>;
}
createRoot(document.getElementById('root')!).render(<List />);
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/virtual-glide-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: false, root: fileURLToPath(new URL('../../web', import.meta.url)), plugins: [react(), vanillaExtractPlugin()], server: { host: '127.0.0.1', port: 0 } });
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
    const glides = new Set();
    window.glideStats = { peak: 0, pending: () => glides.size };
    window.requestAnimationFrame = callback => {
      const glide = callback.name === 'glide';
      const id = request(time => { glides.delete(id); callback(time); });
      if (glide) { glides.add(id); glideStats.peak = Math.max(glideStats.peak, glides.size); }
      return id;
    };
    window.cancelAnimationFrame = id => { glides.delete(id); cancel(id); };
  });
  await page.goto(server.resolvedUrls.local[0] + 'virtual-glide-check.html');
  await page.waitForFunction(() => window.model);
  // Past the hook's opening period, so appends actually glide rather than being placed at once.
  await page.clock.runFor(700);
  const sampling = page.evaluate(async () => {
    const pane = document.getElementById('pane');
    const tops = [pane.scrollTop];
    window.append();
    // Fixed frame count, with no repeated mutation: the glide must finish on its own.
    for (let i = 0; i < 360; i++) { await new Promise(requestAnimationFrame); tops.push(pane.scrollTop); }
    return { tops, peak: glideStats.peak, pending: glideStats.pending(), target: model.target() };
  });
  await page.clock.runFor(6000);
  const result = await sampling;
  assert.equal(result.peak, 1, 'a synchronous row commit cannot fork the glide');
  assert.equal(result.pending, 0, 'the glide finishes with no orphan animation callbacks');
  assert(result.tops.at(-1) > result.tops[0] + 5000, 'the append crosses many virtual row boundaries');
  for (let i = 1; i < result.tops.length; i++) assert(result.tops[i] >= result.tops[i - 1] - 0.5, 'following does not pull backwards');
  assert(Math.abs(result.tops.at(-1) - result.target) < 1, 'the pane reaches the end');
  assert.deepEqual(errors, []);
  console.log('PASS virtual glide: one animation chain, monotonic scroll, settled at the end');
} finally {
  await browser?.close();
  await server?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
