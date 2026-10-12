// Run against pnpm dev:web --host 127.0.0.1 --port 5187. A message pane's floor (scroll.ts) with the real
// useStickToBottom: what leaves the bottom while the pane follows it leaves its room behind, so nothing on screen drops;
// once the reader scrolls up from there, the room nobody sees is let go, and scrolling back down ends at the last
// message, not in blank room as tall as what left.
import { writeFileSync, rmSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/chat-floor-check.tsx', import.meta.url);
const html = new URL('../../web/chat-floor-check.html', import.meta.url);
let browser;
try {
  writeFileSync(fixture, `
import { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { useStickToBottom } from './scroll.ts';
let set: (h: number[]) => void = () => {};
function Pane() {
  const [heights, setHeights] = useState(() => Array.from({ length: 30 }, () => 80));
  set = setHeights;
  const list = useRef<HTMLDivElement>(null);
  const floor = useRef<HTMLDivElement>(null);
  useStickToBottom(list, '.msg', floor);
  return (
    <div id="pane" ref={list} style={{ height: '400px', overflowY: 'auto', paddingBottom: '100px', display: 'flex', flexDirection: 'column' }}>
      {heights.map((h, i) => <div key={i} className="msg" style={{ height: h + 'px', flex: 'none', borderBottom: '1px solid #ccc' }}>{i}</div>)}
      <div id="floor" ref={floor} style={{ flex: 'none' }} />
    </div>
  );
}
createRoot(document.getElementById('root')!).render(<Pane />);
let heights = Array.from({ length: 30 }, () => 80);
const pane = () => document.getElementById('pane')!;
Object.assign(window, {
  push: (h: number) => { heights = [...heights, h]; flushSync(() => set(heights)); },
  toBottom: () => pane().dispatchEvent(new CustomEvent('to-bottom', { detail: 'at-once' })),
  pop: () => { heights = heights.slice(0, -1); flushSync(() => set(heights)); },
  frames: (n: number) => new Promise<void>((done) => { const next = () => (n-- > 0 ? requestAnimationFrame(next) : done()); next(); }),
  state: () => {
    const el = pane(), msgs = el.querySelectorAll('.msg'), last = msgs[msgs.length - 1]!;
    return { top: el.scrollTop, max: el.scrollHeight - el.clientHeight, floor: document.getElementById('floor')!.offsetHeight,
      // How far the last message's bottom is above the pane's bottom: blank room under it.
      blank: el.getBoundingClientRect().bottom - last.getBoundingClientRect().bottom };
  },
});
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/chat-floor-check.tsx"></script>', { flag: 'wx' });
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 600, height: 600 } });
  await page.goto(new URL('/chat-floor-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
  await page.waitForFunction(() => typeof window.push === 'function');
  await page.evaluate(() => window.frames(40));
  const state = () => page.evaluate(() => window.state());
  const settle = () => page.evaluate(() => window.frames(40));

  // At the bottom, a long message comes and goes (an activity folding away, a message replaced by a shorter one).
  // (A new long message is followed to its top, to be read from its start: the reader goes on to its end.)
  await page.evaluate(() => window.push(2400));
  await settle();
  await page.evaluate(() => window.toBottom());
  await settle();
  let s = await state();
  assert.ok(s.max - s.top <= 2, `following the bottom after a long message (${JSON.stringify(s)})`);
  const before = s.top;
  await page.evaluate(() => window.pop());
  await settle();
  s = await state();
  assert.ok(Math.abs(s.top - before) <= 1, `nothing drops as it leaves: the pane stays where it was (${JSON.stringify(s)})`);
  assert.ok(s.floor > 2000, `its room is held by the floor (${JSON.stringify(s)})`);

  // The reader scrolls up, then all the way down again.
  await page.mouse.move(300, 200);
  for (let i = 0; i < 40; i++) { await page.mouse.wheel(0, -300); await page.waitForTimeout(16); }
  await settle();
  for (let i = 0; i < 60; i++) { await page.mouse.wheel(0, 300); await page.waitForTimeout(16); }
  await settle();
  s = await state();
  assert.ok(s.max - s.top <= 2, `scrolled to the end (${JSON.stringify(s)})`);
  assert.ok(s.blank <= 100 + 2, `the end is the last message over the pane's foot, not blank room (${JSON.stringify(s)})`);

  // A short message that leaves the bottom while following still leaves its room, as before.
  await page.evaluate(() => window.push(120));
  await settle();
  const at = (await state()).top;
  await page.evaluate(() => window.pop());
  await settle();
  s = await state();
  assert.ok(Math.abs(s.top - at) <= 1, `a folding row does not pull the list up (${JSON.stringify(s)})`);
  console.log('PASS');
} finally {
  await browser?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
