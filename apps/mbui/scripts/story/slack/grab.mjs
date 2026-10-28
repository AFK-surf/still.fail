// Slack's desktop client as it shows (started by grab.sh with a debugging port): its page's structure, styles and
// fonts kept to slack/desk/ for film 5's Slack (its words all replaced by made-up ones there), and a picture of it.
import { createRequire } from 'node:module';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';
const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(process.env.PW_FROM || here, 'x.js'));
const { chromium } = require('playwright-core');
const out = join(here, 'desk');
mkdirSync(out, { recursive: true });
const b = await chromium.connectOverCDP('http://127.0.0.1:9333');
let page = null;
for (let i = 0; i < 60 && !page; i++) {
  for (const c of b.contexts()) for (const p of c.pages()) if (p.url().includes('app.slack.com/client')) page = p;
  if (!page) await new Promise((r) => setTimeout(r, 1000));
}
if (!page) { console.log('no client page:', b.contexts().flatMap((c) => c.pages().map((p) => p.url()))); process.exit(1); }
await page.waitForSelector('.p-channel_sidebar', { timeout: 60000 }).catch(() => {});
// (laid out at the size of a window of a Mac's (GRAB_SIZE, points), at twice its pixels)
const [gw, gh] = (process.env.GRAB_SIZE || '1272x813').split('x').map(Number);
{
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: gw, height: gh, deviceScaleFactor: 2, mobile: false });
  await new Promise((r) => setTimeout(r, 2000));
}
// (GRAB_DARK=1: as a Mac in dark mode shows it, the system's scheme only pretended for the page: nothing of the
// account's own theme changed)
if (process.env.GRAB_DARK === '1') {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'dark' }] });
  await new Promise((r) => setTimeout(r, 2000));
}
await new Promise((r) => setTimeout(r, 2000));
// (a channel with a thread open beside it: the one called GRAB_CHANNEL, its latest message with replies opened)
const channel = process.env.GRAB_CHANNEL || 'support';
await page.locator('.p-channel_sidebar__name', { hasText: new RegExp(`^${channel}$`) }).first().click().catch((e) => console.log('channel', e.message));
await new Promise((r) => setTimeout(r, 4000));
const replies = page.locator('[data-qa="reply_bar_count"]');
console.log('threads', await replies.count());
if (await replies.count()) { await replies.last().click(); await new Promise((r) => setTimeout(r, 4000)); }
console.log('url', page.url());
await page.screenshot({ path: join(out, 'as-shown.png') });
const css = await page.evaluate(() => {
  const parts = [];
  // (and what the client gave the document as constructed sheets: its theme's colours)
  for (const s of document.adoptedStyleSheets || []) parts.push([...s.cssRules].map((r) => r.cssText).join('\n'));
  // (the custom properties as they stand on the document and the body, for any set by script)
  for (const el of [document.documentElement, document.body]) {
    const cs = getComputedStyle(el), vars = [];
    for (let i = 0; i < cs.length; i++) if (cs[i].startsWith('--')) vars.push(`${cs[i]}:${cs.getPropertyValue(cs[i])}`);
    parts.push(`${el === document.body ? 'body' : 'html'}{${vars.join(';')}}`);
  }
  for (const s of document.styleSheets) {
    try { parts.push([...s.cssRules].map((r) => r.cssText).join('\n')); } catch (e) { if (s.href) parts.push(`@import url("${s.href}");`); }
  }
  return parts.join('\n');
});
writeFileSync(join(out, 'slack.css'), css);
const html = await page.evaluate(() => document.documentElement.outerHTML);
writeFileSync(join(out, 'slack.raw.html'), html);
const size = await page.evaluate(() => [innerWidth, innerHeight, devicePixelRatio]);
console.log('size', size, 'css', css.length, 'html', html.length, 'adopted', await page.evaluate(() => (document.adoptedStyleSheets || []).length));
await b.close();
