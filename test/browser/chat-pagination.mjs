// The real pagination hook must advance even when each page extends the same folded row.
import assert from 'node:assert/strict';
import { writeFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin';
import { uiAlias } from '../../web/ui/alias.ts';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/chat-pagination-check.tsx', import.meta.url);
const html = new URL('../../web/chat-pagination-check.html', import.meta.url);
let server, browser;
try {
  writeFileSync(fixture, `
import React, { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useVirtualList, useVirtualModel } from './src/virtual/list.tsx';
import { useLoadNear } from './src/virtual/load.ts';
function List() {
  const pane = useRef<HTMLDivElement>(null);
  const [last, setLast] = useState(50);
  const made = useVirtualModel('pagination-check', 20);
  const items = [{ key: 'letters', estimate: 36 }, ...(last < 200 ? [{ key: 'newer', estimate: 30 }] : [{ key: 'reply', estimate: 80 }])];
  const list = useVirtualList(pane, made, items, { short: last < 200 });
  useLoadNear(list, 'bottom', last < 200, last, async () => {
    window.loads.push(last);
    await new Promise(resolve => setTimeout(resolve, 20));
    setLast(last + 50);
  });
  Object.assign(window, { model: list.model, last });
  return <div id="pane" ref={pane} style={{ height: 650, width: 390, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 20, padding: '24px', boxSizing: 'border-box', background: '#f5f4f0', fontFamily: 'sans-serif' }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', minHeight: row.key === 'reply' ? 80 : 36 }}>{row.key === 'letters' ? last + ' 条其他会话的消息（折叠）' : row.key === 'newer' ? '加载中…' : '最新回复已加载'}</div></React.Fragment>)}{list.after()}
  </div>;
}
window.loads = [];
createRoot(document.getElementById('root')!).render(<List />);
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/chat-pagination-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: false, root: fileURLToPath(new URL('../../web', import.meta.url)), plugins: [react(), vanillaExtractPlugin()], resolve: { alias: [uiAlias] }, server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true });
  const time = new Date('2026-01-01T00:00:00Z');
  await page.clock.install({ time });
  await page.clock.pauseAt(time);
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(server.resolvedUrls.local[0] + 'chat-pagination-check.html');
  await page.waitForFunction(() => window.model);
  await page.clock.runFor(2000);
  const result = await page.evaluate(() => ({ loads: window.loads, last: window.last }));
  assert.deepEqual(result.loads, [50, 100, 150], 'folded pages continue until the latest reply arrives');
  assert.equal(result.last, 200);
  assert.deepEqual(errors, []);
  console.log('PASS folded chat pagination: three pages loaded without scrolling, latest reply shown');
} finally {
  await browser?.close();
  await server?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
