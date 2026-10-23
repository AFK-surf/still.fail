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
  const mode = new URLSearchParams(location.search).get("mode");
  const older = mode === "older";
  const [last, setLast] = useState(older ? 200 : 50);
  const can = older ? last > 50 : last < 200;
  const made = useVirtualModel('pagination-check', 20);
  const items = [{ key: 'letters', estimate: 36 }, ...(can ? [{ key: 'newer', estimate: 30 }] : [{ key: 'reply', estimate: 80 }])];
  const list = useVirtualList(pane, made, items, { short: can });
  useLoadNear(list, older ? 'top' : 'bottom', can, last, async () => {
    window.loads.push(last);
    if (mode === 'failure') throw new Error('offline');
    if (mode === 'controlled') {
      await new Promise<void>(resolve => { window.answer = resolve; });
      return;
    }
    setLast(last + (older ? -50 : 50));
  });
  Object.assign(window, { model: list.model, last, advance: () => setLast(n => n + 50) });
  return <div id="pane" ref={pane} style={{ height: 650, width: 390, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 20, padding: '24px', boxSizing: 'border-box', background: '#f5f4f0', fontFamily: 'sans-serif' }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', minHeight: row.key === 'reply' ? 80 : 36 }}>{row.key === 'letters' ? mode === 'edits' ? '同一条消息（编辑记录未增加消息行）' : last + ' 条其他会话的消息（折叠）' : row.key === 'newer' ? '加载中…' : '最新回复已加载'}</div></React.Fragment>)}{list.after()}
  </div>;
}
function LongList() {
  const pane = useRef<HTMLDivElement>(null);
  const [first, setFirst] = useState(151);
  const made = useVirtualModel('long-pagination-check', 20);
  const items = Array.from({ length: 201 - first }, (_, i) => ({ key: 'm:' + (first + i), estimate: 100 }));
  const list = useVirtualList(pane, made, items, { short: true });
  useLoadNear(list, 'top', first > 1, first, async () => {
    window.loads.push(first);
    setFirst(n => n - 50);
  });
  Object.assign(window, { model: list.model, last: first, committed: list.committed });
  return <div id="pane" ref={pane} style={{ height: 650, width: 390, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 20, padding: 24, boxSizing: 'border-box' }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', height: 100 }}>{row.key}</div></React.Fragment>)}{list.after()}
  </div>;
}
window.loads = [];
createRoot(document.getElementById('root')!).render(new URLSearchParams(location.search).get('mode') === 'long' ? <LongList /> : <List />);
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/chat-pagination-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: false, cacheDir: fileURLToPath(new URL("../../node_modules/.vite-chat-pagination", import.meta.url)), optimizeDeps: { entries: [fileURLToPath(html)] }, root: fileURLToPath(new URL('../../web', import.meta.url)), plugins: [react(), vanillaExtractPlugin()], resolve: { alias: [uiAlias] }, server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {}), ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true });
  const time = new Date('2026-01-01T00:00:00Z');
  await page.clock.install({ time });
  await page.clock.pauseAt(time);
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  const open = async mode => {
    await page.goto(server.resolvedUrls.local[0] + 'chat-pagination-check.html?mode=' + mode);
    await page.waitForFunction(() => window.model);
    await page.clock.runFor(1000);
    await page.waitForFunction(() => window.loads.length > 0, null, { polling: 50 });
  };
  const state = () => page.evaluate(() => ({ loads: window.loads, last: window.last }));
  for (const mode of ['folded', 'older', 'edits']) {
    await open(mode);
    await page.waitForFunction(target => window.last === target, mode === "older" ? 50 : 200, { polling: 50 });
    assert.deepEqual(await state(), mode === 'older'
      ? { loads: [200, 150, 100], last: 50 }
      : { loads: [50, 100, 150], last: 200 }, mode + ': pages progress without scrolling');
  }
  await open('failure');
  await page.clock.runFor(10000);
  assert.deepEqual(await state(), { loads: [50], last: 50 }, 'failure does not retry itself');
  await open('controlled');
  await page.evaluate(() => window.answer());
  await page.clock.runFor(10000);
  assert.deepEqual(await state(), { loads: [50], last: 50 }, 'an answer alone cannot release ownership');
  await page.evaluate(() => window.advance());
  await page.clock.runFor(1000);
  await page.waitForFunction(() => window.loads.length === 2, null, { polling: 50 });
  assert.deepEqual(await state(), { loads: [50, 100], last: 100 }, 'committed cursor releases the answered request');
  await page.evaluate(() => window.advance());
  await page.clock.runFor(1000);
  assert.deepEqual(await state(), { loads: [50, 100], last: 150 }, 'a committed cursor alone cannot release the unanswered request');
  await page.evaluate(() => window.answer());
  await page.clock.runFor(1000);
  await page.waitForFunction(() => window.loads.length === 3, null, { polling: 50 });
  assert.deepEqual(await state(), { loads: [50, 100, 150], last: 150 });
  await open('long');
  await page.waitForFunction(() => window.last === 101 && window.committed(), null, { polling: 50 });
  assert.deepEqual(await state(), { loads: [151], last: 101 }, 'restoring the anchor does not fetch another page');
  console.log('PASS long-list anchor restored without another page');
  await page.evaluate(() => {
    const pane = document.querySelector('#pane');
    pane.scrollTop = 0;
    pane.dispatchEvent(new Event('scroll'));
  });
  await page.waitForFunction(() => window.last === 51, null, { polling: 50 });
  assert.deepEqual(await state(), { loads: [151, 101], last: 51 }, 'a scroll replacing visible rows still fetches the next page');
  assert.deepEqual(errors, []);
  console.log('PASS pagination: folded newer pages, older pages, edit-only pages, failure, answer/commit ordering, and long-list scrolling');

} finally {
  await browser?.close();
  await server?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
