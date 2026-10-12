// The phone's agent card and the chat's own sheet (web/src/mobile/AgentSheet.tsx, Chat.tsx): an agent's name beside
// its messages opens its card over the chat (where it stands, its figures, the rows that lead on), whose history row
// opens its execution history, its details headed with the same; "…" opens the chat's sheet, whose agent row opens the
// card. Runs its own Vite fixture with the demo core, without a station or network data.
// PLAYWRIGHT_MODULE selects Playwright; SHOTS optionally keeps pictures.
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const fixture = new URL('../../web/agent-sheet-check.tsx', import.meta.url);
const html = new URL('../../web/agent-sheet-check.html', import.meta.url);
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
createRoot(root).render(<DemoApp phone />);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/agent-sheet-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch();
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => { errors.push(e.message); console.error(e.message); });
  await page.goto(base + '/agent-sheet-check.html');
  // A sheet has come up (or gone) once nothing of it moves.
  const rest = () => page.waitForTimeout(600);
  const shot = async (name, dark = false) => {
    if (!out) return;
    await page.evaluate((theme) => { document.documentElement.dataset.theme = theme; }, dark ? 'dark' : 'light');
    await page.screenshot({ path: `${out}/${name}.png` });
    await page.evaluate(() => { document.documentElement.dataset.theme = 'light'; });
  };
  const name = page.locator('[data-role="agent"] button').first();
  await name.waitFor({ timeout: 30000 });
  await rest();

  // Its name: its card over the chat, not its history.
  await name.tap();
  await rest();
  const tiles = page.getByText('费用估算', { exact: true });
  await tiles.waitFor();
  assert.ok(await page.getByText('缓存命中', { exact: true }).isVisible(), 'the card has its figures');
  assert.ok(await page.getByText('账号', { exact: true }).isVisible(), 'the card has its account row');
  assert.equal(await page.getByText('执行历史', { exact: true }).count(), 0, 'the name does not open the history');
  // As tall as what it shows: its last row is in view, and little is left under it.
  const row = await page.getByText('历史', { exact: true }).boundingBox();
  assert.ok(row && row.y + row.height < 844, `the card's rows are in view (${row?.y})`);
  assert.ok(row && 844 - (row.y + row.height) < 120, `the card ends near its rows (${row && 844 - row.y - row.height}px under them)`);
  await shot('agent-card');
  await shot('agent-card-dark', true);

  // Its history row: the sheet goes, the history comes; its details are headed with the same figures.
  await page.getByText('历史', { exact: true }).tap();
  await page.getByText('执行历史', { exact: true }).waitFor();
  await rest();
  await page.getByText('详情', { exact: true }).tap();
  await tiles.waitFor();
  assert.ok(await page.getByText('轮次', { exact: true }).isVisible(), 'the details say its turns');
  await shot('history-details');
  await page.getByRole('button', { name: '返回' }).first().tap();
  await rest();

  // "…": the chat's own sheet, its name with a way to change it, its agents, what can be done.
  await page.getByRole('button', { name: '对话信息' }).tap();
  await page.getByRole('button', { name: '重命名对话' }).waitFor();
  await rest();
  assert.ok(await page.getByText('归档对话', { exact: true }).isVisible(), 'the chat can be archived from its sheet');
  await shot('chat-info');
  // Its agent's row: the agent's card.
  await page.getByRole('button').filter({ hasText: /进行中|已完成|等你决定|出错了/ }).last().tap();
  await tiles.waitFor();
  assert.equal(await page.getByText('归档对话', { exact: true }).count(), 0, 'the card took the sheet');
  assert.deepEqual(errors, []);
  console.log('ok: the agent card and the chat sheet');
} finally {
  await browser?.close();
  await server?.close();
  if (madeFixture) await rm(fixture, { force: true });
  if (madeHtml) await rm(html, { force: true });
}
