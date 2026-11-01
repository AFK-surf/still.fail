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
    await page.waitForFunction((narrow) => {
      const demo = document.querySelector('[data-idea="1"] #demo');
      return document.querySelector('[data-drawn]') && demo && !demo.querySelector(':scope > [inert]') &&
        demo.querySelector(narrow ? '[data-tab="files"]' : '[data-rail-item="files"] a');
    }, label === 'narrow');
    await page.evaluate(async () => {
      document.documentElement.style.scrollBehavior = 'auto';
      await document.fonts.ready;
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + (scene.offsetHeight - innerHeight) * 0.2);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });

    // The connections keep flowing even with the finger still. That movement must not repaint their drawing on the
    // main thread every frame: the page has to respond immediately when the visitor starts scrolling again.
    if (label === 'narrow') {
      const wireClasses = await page.evaluate(async () => {
        const wires = document.querySelector('[data-drawn]').firstElementChild;
        window.__otherAnimations = document.getAnimations().filter((animation) =>
          animation.playState === 'running' && !wires.contains(animation.effect?.target));
        for (const animation of window.__otherAnimations) animation.pause();
        await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        window.__wireAnimation = wires.getAnimations({ subtree: true }).find((a) => a.playState === 'running');
        return [...new Set([wires, ...wires.querySelectorAll('*')].flatMap((el) => [...el.classList]))];
      });
      assert.ok(await page.evaluate(() => !!window.__wireAnimation), 'the connections continue to flow');
      const cdp = await page.context().newCDPSession(page), events = [];
      cdp.on('Tracing.dataCollected', ({ value }) => events.push(...value));
      for (const moving of [false, true]) {
        await cdp.send('Tracing.start', { categories: 'devtools.timeline,disabled-by-default-devtools.timeline', transferMode: 'ReportEvents' });
        const advanced = await page.evaluate((moving) => new Promise((resolve) => {
          const before = window.__wireAnimation.currentTime, from = scrollY;
          let frames = 0;
          function frame() {
            if (moving) window.scrollTo(0, from + frames * 3);
            if (++frames < 20) requestAnimationFrame(frame);
            else requestAnimationFrame(() => requestAnimationFrame(() => resolve(window.__wireAnimation.currentTime > before)));
          }
          requestAnimationFrame(frame);
        }), moving);
        const stopped = new Promise((resolve) => cdp.once('Tracing.tracingComplete', resolve));
        await cdp.send('Tracing.end');
        await stopped;
        assert.ok(advanced, 'the connections actually moved during the trace');
        const painted = events.splice(0).filter((e) => {
          if (e.ph !== 'X' || e.name !== 'Paint') return false;
          const classes = /class='([^']+)'/.exec(e.args?.data?.nodeName ?? '')?.[1]?.split(/\s+/) ?? [];
          return classes.some((c) => wireClasses.includes(c));
        }).length;
        console.log(`${label}: ${painted} connection repaints ${moving ? 'while scrolling' : 'while their dashes flow'}`);
        if (painted) problems.push(`the connections repaint on the main thread ${moving ? 'while scrolling' : 'while flowing'}`);
      }
      await cdp.detach();
      await page.evaluate(() => { for (const animation of window.__otherAnimations) animation.play(); });
    }

    // Every visible connection must still join the centres of the flying devices throughout their movement.
    for (const at of [0.2, 0.4]) {
      const errors = await page.evaluate(async ({ at, narrow }) => {
        const scene = document.querySelector('[data-idea="1"] section[style]');
        window.scrollTo(0, scene.offsetTop + (scene.offsetHeight - innerHeight) * at);
        await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        const room = document.querySelector('[data-drawn]'), wires = room.querySelector('[data-site-wires]');
        if (!wires) return [];
        const cards = [...room.lastElementChild.children].filter((el) => el.tagName !== 'STYLE');
        const devices = narrow ? cards : [...cards, room.children[2]];
        const centres = devices.map((el) => { const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
        const origin = wires.getBoundingClientRect();
        const out = [];
        let n = 0;
        for (let p = 0; p < centres.length; p++) for (let q = p + 1; q < centres.length; q++) {
          const line = wires.children[n++], style = getComputedStyle(line), m = new DOMMatrixReadOnly(style.transform);
          const width = parseFloat(style.width), start = { x: origin.x + m.e, y: origin.y + m.f + 0.75 };
          const end = { x: start.x + m.a * width, y: start.y + m.b * width };
          out.push(Math.hypot(start.x - centres[p].x, start.y - centres[p].y), Math.hypot(end.x - centres[q].x, end.y - centres[q].y));
        }
        return out;
      }, { at, narrow: label === 'narrow' });
      if (errors.length !== (label === 'narrow' ? 12 : 20) || Math.max(...errors) > 1) problems.push(`${label}: connections did not follow the devices`);
    }
    await page.evaluate(async () => {
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

    // Once the scene has scrolled off screen, another scroll below it must not reposition its connections.
    await page.evaluate(async () => {
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + scene.offsetHeight + innerHeight);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      window.__sitePathWrites = 0;
      const paths = scene.querySelector('[data-site-wires]') ?? scene.querySelector('svg g');
      window.__sitePathObserver = new MutationObserver((records) => { window.__sitePathWrites += records.length; });
      window.__sitePathObserver.observe(paths, { attributes: true, attributeFilter: ['d', 'style'], subtree: true });
      window.scrollBy(0, 100);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
    const writes = await page.evaluate(() => { window.__sitePathObserver.disconnect(); return window.__sitePathWrites; });
    console.log(`${label}: ${writes} path writes on a scroll after the scene`);
    if (writes) problems.push(`${label}: the off-screen scene was redrawn`);
    const offscreen = await page.evaluate(() => {
      const scene = document.querySelector('[data-idea="1"] section[style]');
      const wires = scene.querySelector('[data-site-wires]') ?? scene.querySelector('svg');
      const animations = wires.getAnimations({ subtree: true });
      return { total: animations.length, running: animations.filter((a) => a.playState === 'running').length };
    });
    console.log(`${label}: ${offscreen.running} of ${offscreen.total} connection animations running off screen`);
    if (!offscreen.total || offscreen.running) problems.push(`${label}: the connections kept animating off screen`);
    await page.evaluate(async () => {
      const scene = document.querySelector('[data-idea="1"] section[style]');
      window.scrollTo(0, scene.offsetTop + (scene.offsetHeight - innerHeight) * 0.2);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
    await page.waitForFunction(() => document.querySelector('[data-idea="1"] section[style] [data-site-wires], [data-idea="1"] section[style] svg')
      ?.getAnimations({ subtree: true }).some((a) => a.playState === 'running'));
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
      observer.observe(scene.querySelector('[data-site-wires]') ?? scene.querySelector('svg g'), { attributes: true, attributeFilter: ['d', 'style'], subtree: true });
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
    if (label === 'narrow') {
      // The system's motion preference can change while this scene is on screen.
      await page.emulateMedia({ reducedMotion: 'reduce' });
      const animations = await page.evaluate(() => document.querySelector('[data-site-wires]')?.getAnimations({ subtree: true }).length ?? 0);
      if (animations) problems.push('the connections continued to animate with reduced motion');
      await page.emulateMedia({ reducedMotion: 'no-preference' });
      await page.waitForFunction(() => document.querySelector('[data-site-wires]')?.getAnimations({ subtree: true }).some((a) => a.playState === 'running'));
    }
    await page.close();
  }
  assert.deepEqual(problems, []);
} finally {
  await browser.close();
  server.close();
}
