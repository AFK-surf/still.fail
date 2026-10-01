// With `pnpm dev:web --host 127.0.0.1 --port 5187` running, check the real send flight and emphasis stylesheet.
// No station or model: only the delivery timing is simulated. PLAYWRIGHT_MODULE / CHROMIUM_EXECUTABLE select tools.
import { writeFileSync, rmSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/send-flight-check.ts', import.meta.url);
const html = new URL('../../web/send-flight-check.html', import.meta.url);
let browser, madeFixture = false, madeHtml = false;
try {
  writeFileSync(fixture, `
import './styles/index.ts';
import { sendingHere } from './madeChat.ts';
import { chatMessages } from './Chat.css.ts';
import { msg, msgBubble, msgTime } from './styles/conversation.css.ts';
import { msgMine, msgPlain } from './styles/chat.css.ts';
const layer = document.createElement('div');
layer.style.cssText = 'position:relative;width:800px;height:600px';
layer.innerHTML = '<div id="list" data-focus-motion style="height:350px"></div><textarea style="position:absolute;top:440px;width:600px;font:14px/24px sans-serif">继续这个对话</textarea>';
document.body.append(layer);
const list = layer.querySelector<HTMLElement>('#list')!;
list.className = chatMessages;
const field = layer.querySelector('textarea')!;
Object.assign(window, { sendFlight(replace: boolean) {
  list.replaceChildren();
  sendingHere(field, field.value, { layer, z: '4', list });
  let row = document.createElement('div');
  row.className = msg + ' ' + msgMine;
  row.innerHTML = '<div class="' + msgBubble + '"><div class="' + msgPlain + '">继续这个对话</div></div><span class="' + msgTime + '" style="visibility:visible">正在发送</span>';
  list.append(row);
  if (replace) setTimeout(() => {
    const next = row.cloneNode(true) as HTMLElement;
    next.removeAttribute('style');
    delete next.dataset.sendCovered;
    row.replaceWith(next); row = next;
  }, 100);
  return new Promise(resolve => {
    const samples: unknown[] = [];
    const start = performance.now();
    function sample() {
      const style = getComputedStyle(row);
      const ghost = [...layer.children].some(el => el !== list && el.querySelector('.' + msgMine));
      samples.push({ t: performance.now() - start, ghost, visibility: style.visibility, opacity: +style.opacity,
        status: getComputedStyle(row.lastElementChild!).visibility });
      if (performance.now() - start < 850) requestAnimationFrame(sample); else resolve(samples);
    }
    requestAnimationFrame(sample);
  });
} });
`, { flag: 'wx' });
  madeFixture = true;
  writeFileSync(html, '<script type="module" src="/src/send-flight-check.ts"></script>', { flag: 'wx' });
  madeHtml = true;
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  for (const reducedMotion of ['no-preference', 'reduce']) for (const replace of [false, true]) {
    const page = await browser.newPage({ reducedMotion });
    await page.goto(new URL('/send-flight-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
    await page.waitForFunction(() => typeof window.sendFlight === 'function');
    const samples = await page.evaluate(replace => window.sendFlight(replace), replace);
    const flying = samples.filter(s => s.ghost);
    if (reducedMotion === 'no-preference') {
      assert(flying.length > 0, 'must exercise the flight');
      assert(flying.every(s => (s.visibility === 'hidden' && s.status === 'hidden') || s.opacity === 0), 'the row and its status stay covered');
    } else assert.equal(flying.length, 0);
    const after = samples.filter(s => s.t > (flying.at(-1)?.t ?? 0));
    assert(after.length > 0);
    assert(after.every(s => s.visibility === 'visible' && s.opacity === 1), 'no blank frame or second fade at handoff');
    console.log('PASS', reducedMotion, replace ? 'receipt replaces row' : 'receipt keeps row');
    await page.close();
  }
} finally {
  await browser?.close();
  if (madeFixture) rmSync(fixture);
  if (madeHtml) rmSync(html);
}
