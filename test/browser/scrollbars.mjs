// Run against pnpm dev:web --host 127.0.0.1 --port 5187. The floating scrollbars (scrollbars.ts) over two panes: a
// sidebar under the pointer and a chat opened beside it.
import { writeFileSync, rmSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/scrollbars-check.ts', import.meta.url);
const html = new URL('../../web/scrollbars-check.html', import.meta.url);
let browser;
try {
  writeFileSync(fixture, `
import { startScrollbars } from './scrollbars.ts';
import './styles/index.ts';
document.body.style.cssText = 'margin:0;display:flex;height:100vh';
const pane = (id: string) => {
  const el = document.createElement('div');
  el.id = id;
  el.style.cssText = 'overflow-y:auto;height:100%;flex:1';
  el.innerHTML = '<div style="height:3000px"></div>';
  return el;
};
const side = pane('side'), main = document.createElement('div');
main.style.cssText = 'flex:2;height:100%;display:flex';
main.append(pane('chat'));
document.body.append(side, main);
startScrollbars();
Object.assign(window, {
  // Another chat opened: the pane made anew in place of the last, and taken to its foot.
  open: () => { const el = pane('chat'); main.replaceChildren(el); el.scrollTop = 1e6; },
});
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/scrollbars-check.ts"></script>', { flag: 'wx' });
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const context = await browser.newContext({ viewport: { width: 900, height: 500 } });
  const page = await context.newPage();
  await page.clock.install();
  await page.goto(new URL('/scrollbars-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
  await page.waitForFunction(() => typeof window.open === 'function');
  const settle = async (ms = 100) => { await page.clock.runFor(ms); await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))); };
  const owner = () => page.evaluate(() => [...document.querySelectorAll('[data-axis="y"][data-on]')].map(t => t.parentElement === document.body ? 'side' : 'chat').sort().join(','));

  // A chat opened from the sidebar: the sidebar's bar stays all along, the chat's shows for its scroll and goes.
  await page.mouse.move(100, 250);
  await settle();
  assert.equal(await owner(), 'side', 'the bar of the pane under the pointer');
  await page.evaluate(() => window.open());
  for (let t = 0; t < 600; t += 100) {
    await settle();
    assert.equal(await owner(), 'chat,side', `at ${t}ms after opening, the sidebar's bar is still there beside the chat's`);
  }
  await settle(1000);
  assert.equal(await owner(), 'side', 'the chat\'s bar goes; the sidebar\'s stays');
  console.log('PASS opened from the sidebar');

  // Another chat opened under the pointer (a shortcut): its bar stays, as the last one's did.
  await page.mouse.move(600, 250);
  await settle();
  assert.equal(await owner(), 'chat');
  await page.evaluate(() => window.open());
  await settle(2000);
  assert.equal(await owner(), 'chat', 'the new chat under the pointer keeps its bar');
  console.log('PASS opened under the pointer');
  await context.close();
} finally {
  await browser?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
