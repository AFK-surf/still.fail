// With `pnpm dev:web --host 127.0.0.1 --port 5187` running, check the phone's new chat page: its scene runs on under the
// choices and the composer (on a band of glass frosting it) down to the screen's end, and scrolled to its end it is clear of
// them. The page is drawn from its real styles (mobile/NewChat.css.ts, ChatHost.css.ts), heights as the components set
// them. SHOTS=<dir> keeps a picture of each. PLAYWRIGHT_MODULE / CHROMIUM_EXECUTABLE select tools.
import { writeFileSync, rmSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/new-chat-foot-check.ts', import.meta.url);
const html = new URL('../../web/new-chat-foot-check.html', import.meta.url);
let browser, madeFixture = false, madeHtml = false;
try {
  writeFileSync(fixture, `
import './styles/index.ts';
import { m } from './mobile/styles/root.css.ts';
import { mScreen, mFloating } from './mobile/styles/pages.css.ts';
import { mChatHost, mComposer, mHostComposer, mComposerCapsule } from './mobile/ChatHost.css.ts';
import { mNewchatScreen, mNewBody, mNewFoot, mNewBottom, mChoosers, mChooser } from './mobile/NewChat.css.ts';
const chips = ['Opus 5.5 · medium', 'GPT-6 Astra · medium', 'Opus 5.5 · max', 'Opus 5.5 · high'];
document.body.innerHTML = \`<div class="\${m}"><div class="\${mChatHost}" data-new style="--m-foot:0px">
  <div class="\${mScreen} \${mNewchatScreen}">
    <div style="height:56px;flex:none;display:flex;align-items:center;justify-content:center;font-weight:600">New chat</div>
    <div class="\${mNewBody}" id="body">
      <div style="flex:none;width:230px;height:200px;border-radius:115px 115px 0 0;background:#E8C6B5"></div>
      <h2>What should the agent do?</h2>
      <p>Say what to do. A new chat starts on studio with the chosen model.</p>
      <div style="display:flex;flex-wrap:wrap;gap:6px;justify-content:center">\${chips.map((c) => \`<span style="padding:8px 10px;border-radius:18px;background:#2E7DD7;color:white">\${c}</span>\`).join('')}</div>
      <p id="last" style="color:#D9480F">Reading studio's profiles…</p>
    </div>
    <div class="\${mNewFoot}" id="foot"><div class="\${mNewBottom}"><div class="\${mChoosers}" id="choosers">
      <button class="\${mChooser} \${mFloating}">studio</button><button class="\${mChooser} \${mFloating}">Opus 5.5 · high</button>
    </div></div></div>
  </div>
  <div class="\${mComposer} \${mHostComposer}" id="composer"><div class="\${mFloating} \${mComposerCapsule}" style="height:88px;box-sizing:border-box;padding:14px 18px;color:#A6A8AC">Do anything</div></div>
</div></div>\`;
const host = document.querySelector<HTMLElement>('[data-new]')!;
const body = document.getElementById('body')!;
// As ChatHost.tsx and NewChat.tsx set them.
host.style.setProperty('--m-bottom', document.getElementById('composer')!.offsetHeight + 'px');
body.style.setProperty('--m-new-foot', document.getElementById('foot')!.offsetHeight + 'px');
Object.assign(window, { ready: true });
`, { flag: 'wx' });
  madeFixture = true;
  writeFileSync(html, '<script type="module" src="/src/new-chat-foot-check.ts"></script>', { flag: 'wx' });
  madeHtml = true;
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  // A phone with its keyboard up: less room than the scene needs.
  const page = await browser.newPage({ viewport: { width: 390, height: 560 }, deviceScaleFactor: 3 });
  await page.goto(new URL('/new-chat-foot-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
  await page.waitForFunction(() => window.ready === true);
  const rect = (id) => page.evaluate((id) => { const r = document.getElementById(id).getBoundingClientRect(); return { top: r.top, bottom: r.bottom }; }, id);
  const [body, foot, choosers, composer] = [await rect('body'), await rect('foot'), await rect('choosers'), await rect('composer')];
  assert(body.bottom >= composer.bottom - 0.5, `the scene runs on under the composer to the screen's end (${body.bottom} < ${composer.bottom})`);
  assert(foot.bottom >= composer.bottom - 0.5, `the band of glass goes on to the screen's end (${foot.bottom} < ${composer.bottom})`);
  assert(choosers.bottom <= composer.top + 0.5, `the choices stand just over the composer (${choosers.bottom} > ${composer.top})`);
  const scroll = await page.evaluate(() => { const b = document.getElementById('body'); return b.scrollHeight - b.clientHeight; });
  assert(scroll > 0, 'the scene is taller than its room');
  // Painted (backdrop filters too) before it is pictured.
  const painted = () => page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
  await painted();
  if (process.env.SHOTS) await page.screenshot({ path: `${process.env.SHOTS}/new-chat-foot-top.png` });
  await page.evaluate(() => { const b = document.getElementById('body'); b.scrollTop = b.scrollHeight; });
  const last = await rect('last');
  assert(last.bottom <= foot.top + 0.5, `scrolled to its end, its last line is clear of the choices (${last.bottom} > ${foot.top})`);
  await painted();
  if (process.env.SHOTS) await page.screenshot({ path: `${process.env.SHOTS}/new-chat-foot-end.png` });
  console.log('PASS the scene runs under the choices and the composer, its end clear of them');
} finally {
  await browser?.close();
  if (madeFixture) rmSync(fixture);
  if (madeHtml) rmSync(html);
}
