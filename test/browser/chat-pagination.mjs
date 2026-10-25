// The real pagination hook must advance even when each page extends the same folded row.
import assert from 'node:assert/strict';
import { writeFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin';
import { uiAlias } from '../../web/ui/alias.ts';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const engine = process.env.BROWSER || 'chromium';
const fixture = new URL('../../web/chat-pagination-check.tsx', import.meta.url);
const html = new URL('../../web/chat-pagination-check.html', import.meta.url);
let server, browser;
try {
  writeFileSync(fixture, `
import React, { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useVirtualList, useVirtualModel } from './src/virtual/list.tsx';
import { useLoadNear, usePagingEdges } from './src/virtual/load.ts';
import * as css from './src/Chat.css.ts';
import { Retry } from '@stillfail/ui/icons.tsx';
function List() {
  const pane = useRef<HTMLDivElement>(null);
  const mode = new URLSearchParams(location.search).get("mode");
  const older = mode === "older";
  const [last, setLast] = useState(older ? 200 : 50);
  const can = older ? last > 50 : last < 200;
  const made = useVirtualModel('pagination-check', 20);
  const items = [...(mode === 'empty' ? [] : [{ key: 'letters', estimate: 36 }]), ...(can ? [{ key: 'newer', estimate: 30 }] : [{ key: 'reply', estimate: 80 }])];
  const list = useVirtualList(pane, made, items, { short: can });
  const paging = useLoadNear(list, older ? 'top' : 'bottom', can, last, async () => {
    window.loads.push(last);
    if (mode === 'failure' && window.loads.length === 1) throw new Error('offline');
    if (mode === 'controlled') {
      await new Promise<void>(resolve => { window.answer = resolve; });
      return;
    }
    setLast(last + (older ? -50 : 50));
  });
  Object.assign(window, { retry: paging.retry, failed: paging.failed, model: list.model, last, advance: () => setLast(n => n + 50) });
  return <div id="pane" ref={pane} style={{ height: 650, width: 390, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 20, padding: '24px', boxSizing: 'border-box', background: '#f5f4f0', fontFamily: 'sans-serif' }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', minHeight: row.key === 'reply' ? 80 : 36 }}>{row.key === 'letters' ? mode === 'edits' ? '同一条消息（编辑记录未增加消息行）' : last + ' 条其他会话的消息（折叠）' : row.key === 'newer' ? paging.failed ? <button type="button" className={css.msgUnsentBtn} onClick={paging.retry} aria-label="重试"><Retry size={16} />重试</button> : '加载中…' : '最新回复已加载'}</div></React.Fragment>)}{list.after()}
  </div>;
}
function EmptyWindow() {
  const pane = useRef<HTMLDivElement>(null);
  const switching = new URLSearchParams(location.search).get('mode') === 'switch';
  const [place, setPlace] = useState('empty-window');
  const [range, setRange] = useState({ first: 101, last: 250 });
  const found = switching ? place === 'next-chat' && range.last === 450 : range.first === 1;
  const edges = usePagingEdges(!found, range.first > 1, range.last < 450, place);
  const made = useVirtualModel(place, 20);
  const items = [...(edges.older ? [{ key: 'older', estimate: 30 }] : []), ...(found ? [{ key: 'reply', estimate: 2400 }] : []), ...(edges.newer ? [{ key: 'newer', estimate: 30 }] : [])];
  const list = useVirtualList(pane, made, items, { short: range.last < 450 });
  useLoadNear(list, 'top', edges.older, range.first, async () => {
    window.loads.push('older:' + range.first);
    setRange(({ first, last }) => ({ first: first - 50, last: last - 50 }));
  });
  useLoadNear(list, 'bottom', edges.newer, range.last, async () => {
    window.loads.push('newer:' + range.last);
    setRange(({ first, last }) => ({ first: first + 50, last: last + 50 }));
  });
  Object.assign(window, { model: list.model, last: range.first, found, place, committed: list.committed, switchChat: () => {
    window.loads = [];
    setPlace('next-chat');
    setRange({ first: 1, last: 150 });
  } });
  return <div id="pane" ref={pane} style={{ height: 650, width: 390, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 20 }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', height: row.key === 'reply' ? 2400 : 30 }}>{row.key === 'reply' ? '正文已找到' : '加载中…'}</div></React.Fragment>)}{list.after()}
  </div>;
}
function LongList() {
  const pane = useRef<HTMLDivElement>(null);
  const [first, setFirst] = useState(151);
  const adaptive = new URLSearchParams(location.search).get('mode') === 'adaptive';
  const made = useVirtualModel('long-pagination-check', 20);
  const opened = useRef(false);
  if (adaptive && !opened.current) { made.model.goto('m:161', 'start'); opened.current = true; }
  const items = Array.from({ length: 201 - first }, (_, i) => ({ key: 'm:' + (first + i), estimate: 100 }));
  const list = useVirtualList(pane, made, items, { short: true });
  useLoadNear(list, 'top', first > 1, first, async () => {
    window.loads.push(first);
    if (adaptive) await new Promise<void>(resolve => { window.answer = resolve; });
    setFirst(n => n - 50);
  });
  Object.assign(window, { model: list.model, last: first, committed: list.committed });
  return <div id="pane" ref={pane} style={{ height: 650, width: 390, overflow: 'auto', overflowAnchor: 'none', display: 'flex', flexDirection: 'column', gap: 20, padding: 24, boxSizing: 'border-box' }}>
    {list.layout.rows.map((row, i) => <React.Fragment key={row.key}>{list.above(row, i === 0)}<div data-vk={row.key} style={{ flex: 'none', height: 100 }}>{row.key}</div></React.Fragment>)}{list.after()}
  </div>;
}
window.loads = [];
const mode = new URLSearchParams(location.search).get('mode');
createRoot(document.getElementById('root')!).render(mode === 'long' || mode === 'adaptive' ? <LongList /> : mode === 'window' || mode === 'switch' ? <EmptyWindow /> : <List />);
`, { flag: 'wx' });
  writeFileSync(html, '<meta name="viewport" content="width=device-width, initial-scale=1"><div id="root"></div><script type="module" src="/chat-pagination-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: false, cacheDir: fileURLToPath(new URL("../../node_modules/.vite-chat-pagination", import.meta.url)), optimizeDeps: { entries: [fileURLToPath(html)] }, root: fileURLToPath(new URL('../../web', import.meta.url)), plugins: [react(), vanillaExtractPlugin()], resolve: { alias: [uiAlias] }, server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await playwright[engine].launch({ headless: true, ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {}), ...(engine === 'chromium' && process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, deviceScaleFactor: 2 });
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
  for (const mode of ['folded', 'older', 'edits', 'empty']) {
    await open(mode);
    await page.waitForFunction(target => window.last === target, mode === "older" ? 50 : 200, { polling: 50 });
    assert.deepEqual(await state(), mode === 'older'
      ? { loads: [200, 150, 100], last: 50 }
      : { loads: [50, 100, 150], last: 200 }, mode + ': pages progress without scrolling');
  }
  await open('window');
  await page.clock.runFor(3000);
  await page.waitForFunction(() => window.last === 1, null, { polling: 50, timeout: 5000 });
  assert.deepEqual((await state()).loads, ['newer:250', 'newer:300', 'newer:350', 'newer:400', 'older:301', 'older:251', 'older:201', 'older:151', 'older:101', 'older:51'], 'empty bounded window searches forward then backward without oscillating');
  await open('failure');
  await page.clock.runFor(10000);
  assert.deepEqual(await state(), { loads: [50], last: 50 }, 'failure does not retry itself');
  assert.equal(await page.evaluate(() => window.failed), true, 'failure exposes an explicit retry');
  if (process.env.PAGINATION_SCREENSHOT) await page.screenshot({ path: process.env.PAGINATION_SCREENSHOT, clip: { x: 0, y: 0, width: 390, height: 150 } });
  await page.getByRole('button', { name: '重试' }).click();
  await page.clock.runFor(1000);
  await page.waitForFunction(() => window.last === 200, null, { polling: 50 });
  assert.deepEqual(await state(), { loads: [50, 50, 100, 150], last: 200 }, 'explicit retry recovers the failed cursor and continues');
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
  await page.goto(server.resolvedUrls.local[0] + 'chat-pagination-check.html?mode=adaptive');
  await page.waitForFunction(() => window.model);
  await page.clock.runFor(1000);
  await page.waitForFunction(() => window.committed());
  assert.deepEqual((await state()).loads, [], 'opening more than a pane from the edge does not fetch');
  const scroll = top => page.evaluate(top => {
    const pane = document.querySelector('#pane'); pane.scrollTop = top; pane.dispatchEvent(new Event('scroll'));
  }, top);
  await scroll(1199);
  await page.clock.runFor(16);
  await scroll(1000);
  await page.clock.runFor(16);
  await page.waitForFunction(() => window.loads.length === 1);
  assert.equal(await page.evaluate(() => model.toStart > model.paneHeight), true, 'fast scroll fetches before the one-pane threshold');
  await scroll(950);
  await page.clock.runFor(16);
  assert.equal((await state()).loads.length, 1, 'in-flight prefetch owns its cursor');
  await page.evaluate(() => window.answer());
  await page.clock.runFor(1000);
  await page.waitForFunction(() => window.last === 101 && window.committed());
  assert.equal((await state()).loads.length, 1, 'prefetch anchor restoration does not cascade into another page');
  console.log('PASS fast-scroll prefetch before the edge, one request, restored anchor');
  // The new list must measure and commit its first visible message after the
  // switch. Let frames run and wait for that result, rather than sample mid-page.
  await page.clock.resume();
  await open('switch');
  await page.waitForFunction(() => window.last === 1 && window.committed(), null, { polling: 50 });
  assert.equal(await page.evaluate(() => window.found), false, 'a letter-only chat exhausts both directions');
  await page.evaluate(() => window.switchChat());
  await page.waitForFunction(() => window.found && window.committed(), null, { polling: 50, timeout: 5000 });
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.deepEqual((await state()).loads, ['newer:150', 'newer:200', 'newer:250', 'newer:300', 'newer:350', 'newer:400'], 'switching chats starts a fresh empty-window search');
  assert.equal(await page.evaluate(() => window.found), true, 'the recovered message stays visible instead of being paged out again');
  assert.deepEqual(errors, []);
  console.log('PASS pagination: folded/empty/edit-only pages, bounded empty-window search, explicit retry, answer/commit ordering, and long-list scrolling');

} finally {
  await browser?.close();
  await server?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
