// The site's first scene while scrolling: its cards stay in place when only the viewport height changes (as the
// browser's bars move), and a scene already off the screen is not redrawn while the rest of the page scrolls.
//   PLAYWRIGHT_MODULE=playwright-core [PLAYWRIGHT_CHANNEL=chrome] node test/browser/site-scroll.mjs [dist/site]
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';

const dir = resolve(process.argv[2] ?? 'dist/site');
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };
const server = createServer((req, res) => {
  let path = join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!extname(path) && existsSync(`${path}.html`)) path += '.html';
  try {
    if (statSync(path).isDirectory()) path = join(path, 'index.html');
    res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' }).end(readFileSync(path));
  } catch { res.writeHead(404).end(); }
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});
const problems = [];

try {
  for (const [label, size] of [['narrow', { width: 390, height: 844 }], ['wide', { width: 1440, height: 900 }]]) {
    const page = await browser.newPage({ viewport: size, locale: 'zh-CN', ...(label === 'narrow' ? { isMobile: true, hasTouch: true } : {}) });
    await page.goto(`http://127.0.0.1:${server.address().port}/`, { waitUntil: 'load' });
    await page.waitForFunction(() => document.querySelector('[data-drawn]') && !document.querySelector('[data-idea="1"] #demo > [inert]'));
    await page.evaluate(async () => {
      document.documentElement.style.scrollBehavior = 'auto';
      await document.fonts.ready;
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + (scene.offsetHeight - innerHeight) * 0.2);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });

    if (label === 'narrow') {
      const cards = await page.evaluate(() => {
        const sky = document.querySelector('[data-drawn]').lastElementChild;
        window.__siteCards = [...sky.children].filter((el) => el.tagName !== 'STYLE');
        window.__siteCardTransform = window.__siteCards[0]?.style.transform;
        return window.__siteCards.length;
      });
      assert.equal(cards, 4, 'four cards fly in the scene');
      for (const height of [836, 828, 820, 812]) {
        await page.setViewportSize({ width: size.width, height });
        await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      }
      const { retained, moved } = await page.evaluate(() => ({
        retained: window.__siteCards.filter((el) => el.isConnected).length,
        moved: window.__siteCards[0]?.style.transform !== window.__siteCardTransform,
      }));
      console.log(`${label}: ${retained} of ${cards} flying cards retained through height changes`);
      if (retained !== cards) problems.push('the flying cards were rebuilt when only the viewport height changed');
      if (!moved) problems.push('the flying cards did not follow the changed viewport');

      // A theme really does change the cards' appearance, so it must still replace the copies.
      await page.evaluate(() => { document.documentElement.dataset.theme = 'dark'; });
      await page.waitForFunction(() => window.__siteCards.every((el) => !el.isConnected));
    }

    // Once the scene has scrolled off screen, another scroll below it must not touch its paths.
    await page.evaluate(async () => {
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + scene.offsetHeight + innerHeight);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      window.__sitePathWrites = 0;
      const paths = scene.querySelector('svg g');
      window.__sitePathObserver = new MutationObserver((records) => { window.__sitePathWrites += records.length; });
      window.__sitePathObserver.observe(paths, { attributes: true, attributeFilter: ['d'], subtree: true });
      window.scrollBy(0, 100);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
    const writes = await page.evaluate(() => { window.__sitePathObserver.disconnect(); return window.__sitePathWrites; });
    console.log(`${label}: ${writes} path writes on a scroll after the scene`);
    if (writes) problems.push(`${label}: the off-screen scene was redrawn`);
    await page.evaluate(async () => {
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + (scene.offsetHeight - innerHeight) * 0.2);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
    const flying = await page.evaluate(() => [...document.querySelector('[data-drawn]').lastElementChild.children]
      .filter((el) => el.tagName !== 'STYLE' && getComputedStyle(el).display !== 'none').length);
    if (flying !== 4) problems.push(`${label}: the scene did not resume when scrolled back into view`);

    // Going to the end and back without touching the demo should reuse the very same cards. If the visitor has used
    // the demo, however, it must reopen as it was and the cards must be read from that newly opened app.
    await page.evaluate(() => {
      window.__roundtripCards = [...document.querySelector('[data-drawn]').lastElementChild.children].filter((el) => el.tagName !== 'STYLE');
    });
    const travel = async (fraction) => page.evaluate(async (f) => {
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + (scene.offsetHeight - innerHeight) * f);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    }, fraction);
    await travel(1);
    await travel(0.2);
    const roundtrip = await page.evaluate(() => window.__roundtripCards.filter((el) => el.isConnected).length);
    console.log(`${label}: ${roundtrip} of 4 cards retained on an untouched round trip`);
    if (roundtrip !== 4) problems.push(`${label}: an untouched round trip rebuilt the flying cards`);

    if (label === 'narrow') {
      await travel(1);
      const beforeSwipe = await page.evaluate(() => ({
        y: scrollY,
        inDemo: !!document.elementFromPoint(195, 180)?.closest('[data-idea="1"] #demo'),
      }));
      assert.ok(beforeSwipe.inDemo, 'the swipe starts on the interactive demo');
      const cdp = await page.context().newCDPSession(page);
      await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 180, yDistance: 300, speed: 900, gestureSourceType: 'touch' });
      await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const swipe = await page.evaluate(() => ({ y: scrollY, retained: window.__roundtripCards.filter((el) => el.isConnected).length }));
      await cdp.detach();
      assert.ok(swipe.y < beforeSwipe.y, 'the touch gesture actually scrolled the page back');
      console.log(`${label}: ${swipe.retained} of 4 cards retained on a touch scroll over the demo`);
      if (swipe.retained !== 4) problems.push('a touch scroll over the demo was mistaken for using it');
    }
    await travel(1);
    // Visit a different page in the demo, then scroll the rest of the site. The scene must stay still until it is
    // played backwards, when the used demo is reopened at its original page.
    const files = label === 'narrow' ? '[data-tab="files"]' : '[data-rail-item="files"] a';
    const fileTab = page.locator(`[data-idea="1"] #demo ${files}`);
    if (label === 'narrow') await fileTab.tap({ force: true });
    else await fileTab.click({ force: true });
    await page.waitForFunction((narrow) => narrow
      ? document.querySelector('[data-idea="1"] #demo [data-tab="files"]')?.getAttribute('aria-selected') === 'true'
      : document.querySelector('[data-idea="1"] #demo [data-rail-item="files"] a')?.hasAttribute('data-on'), label === 'narrow');
    const afterUse = await page.evaluate(async () => {
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + scene.offsetHeight + innerHeight);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      let writes = 0;
      const observer = new MutationObserver((records) => { writes += records.length; });
      observer.observe(scene.querySelector('svg g'), { attributes: true, attributeFilter: ['d'], subtree: true });
      for (let n = 0; n < 5; n++) await new Promise((resolve) => requestAnimationFrame(resolve));
      observer.disconnect();
      return writes;
    });
    console.log(`${label}: ${afterUse} path writes after visiting another page in the demo`);
    if (afterUse) problems.push(`${label}: the off-screen scene kept redrawing after the demo was used`);
    await travel(0.2);
    const reopened = await page.evaluate(() => ({
      old: window.__roundtripCards.filter((el) => el.isConnected).length,
      flying: [...document.querySelector('[data-drawn]').lastElementChild.children]
        .filter((el) => el.tagName !== 'STYLE' && getComputedStyle(el).display !== 'none').length,
    }));
    if (reopened.old || reopened.flying !== 4) problems.push(`${label}: the demo did not reopen after it was used`);
    await page.close();
  }
  assert.deepEqual(problems, []);
} finally {
  await browser.close();
  server.close();
}
