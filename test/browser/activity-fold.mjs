// Run against pnpm dev:web --host 127.0.0.1 --port 5187. An agent's activity line folding to its avatar and back, with
// the real moveState and activity styles: once a motion ends nothing it held stays on the line, so words and the time
// that grow after it unfold are not cut down to the width it had then.
import { writeFileSync, rmSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/activity-fold-check.tsx', import.meta.url);
const html = new URL('../../web/activity-fold-check.html', import.meta.url);
let browser;
try {
  writeFileSync(fixture, `
import { moveState, EASE_OUT } from './motion.ts';
import * as css from './Chat.css.ts';
import './styles/index.ts';
const root = document.getElementById('root')!;
root.style.width = '600px';
root.innerHTML = '<div class="' + css.agentActivity + '" id="row"><button class="' + css.activityLine + '"><span class="' +
  css.activityAvatar + '" style="width:24px;height:24px"></span><span class="' + css.activityTail + '" id="tail"><span class="' +
  css.activityNow + '"><span class="' + css.activityNowText + '" id="now">思考中</span></span><span class="' + css.activityElapsed +
  '" id="elapsed">5s</span></span></button></div>';
const row = document.getElementById('row')!, tail = document.getElementById('tail')!;
Object.assign(window, {
  fold: (folded: boolean) => moveState([[tail, ['width', 'opacity']]], () => row.toggleAttribute('data-folded', folded), { duration: 0.17, ease: EASE_OUT }),
  say: (now: string, elapsed: string) => { document.getElementById('now')!.textContent = now; document.getElementById('elapsed')!.textContent = elapsed; },
  held: () => tail.getAttribute('style') ?? '',
  frames: (n: number) => new Promise<void>((done) => { const next = () => (n-- > 0 ? requestAnimationFrame(next) : done()); next(); }),
  shown: () => { const now = document.getElementById('now')!; return { width: now.clientWidth, needs: now.scrollWidth }; },
});
`, { flag: 'wx' });
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/activity-fold-check.tsx"></script>', { flag: 'wx' });
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 700, height: 200 } });
  await page.goto(new URL('/activity-fold-check.html', process.env.WEB_URL || 'http://127.0.0.1:5187').href);
  await page.waitForFunction(() => typeof window.fold === 'function');
  // Motion's last frame comes at a time of its own: repeated, a write after the line let go shows at least once. Each
  // motion is waited out (a slow machine draws 170ms late), and the line looked at again a few frames after.
  const settled = async (what) => {
    await page.waitForFunction(() => window.held() === '', null, { timeout: 3000 }).catch(() => {});
    await page.evaluate(() => window.frames(3));
    assert.equal(await page.evaluate(() => window.held()), '', what);
  };
  for (let i = 0; i < 20; i++) {
    await page.evaluate(() => { window.say('思考中', '5s'); window.fold(true); });
    await settled(`fold ${i}: nothing held once folded`);
    await page.evaluate(() => window.fold(false));
    await settled(`unfold ${i}: nothing held once unfolded`);
    await page.evaluate(() => window.say('读取 Chat.tsx and what it says about the activity line', '1m 45s'));
    const shown = await page.evaluate(() => window.shown());
    assert.equal(shown.width, shown.needs, `unfold ${i}: the words that grew after are shown whole`);
  }
  console.log('PASS');
} finally {
  await browser?.close();
  rmSync(fixture, { force: true });
  rmSync(html, { force: true });
}
