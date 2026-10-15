// Every story (web/stories/stories.tsx) opened, taken to its state by its steps, and measured (measure.mjs: every
// corner, every small panel; docs/ui-panels.md). A new part of the app with a story is measured with no more written
// here. Builds the stories once (as a page, not module by module: the dev server's per-module transforms were most of
// the time on CI's four cores) and serves the build. PLAYWRIGHT_MODULE selects Playwright (PLAYWRIGHT_CHANNEL a Chrome the
// machine has, as CI's); SHOTS keeps a picture of each story; ONLY=<id,…> opens only those; REPORT=1 lists what is off
// instead of failing; PAGES how many are opened at once (6); SHARD=<i>/<n> only the i-th of every n (CI's jobs side by side).
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';
import { corners, panels } from './measure.mjs';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const only = process.env.ONLY?.split(',');
let server, browser, dist;
try {
  const configFile = fileURLToPath(new URL('../../web/vite.stories.config.ts', import.meta.url));
  dist = await mkdtemp(join(tmpdir(), 'stories-'));
  await build({ configFile, build: { outDir: dist, emptyOutDir: true, minify: false, reportCompressedSize: false }, logLevel: 'error' });
  server = await preview({ configFile, build: { outDir: dist }, preview: { host: '127.0.0.1', port: 0, strictPort: false }, logLevel: 'error' });
  const base = `http://127.0.0.1:${server.httpServer.address().port}/`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});

  // The stories, as the gallery lists them.
  const index = await browser.newPage();
  await index.goto(base);
  await index.waitForFunction(() => Array.isArray(window.stories));
  const [shard, shards] = (process.env.SHARD || '1/1').split('/').map(Number);
  const stories = (await index.evaluate(() => window.stories)).filter((s, i) => (!only || only.includes(s.id)) && i % shards === shard - 1);
  await index.close();

  // Settled: fonts in, every transition and finite animation over (spinners go on), after `ms` for what starts late.
  const settle = (page, ms) => page.waitForTimeout(ms).then(() => page.evaluate(() => Promise.race([
    document.fonts.ready.then(() => Promise.all(document.getAnimations().filter((a) => a.effect?.getTiming().iterations !== Infinity).map((a) => a.finished.catch(() => {})))),
    new Promise((ok) => setTimeout(ok, 3000)),
  ])));

  const wrong = [];
  const take = async (story) => {
    const page = await browser.newPage({ viewport: story.phone ? { width: 390, height: 844 } : { width: 1280, height: 800 }, deviceScaleFactor: 1, locale: 'zh-CN' });
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.goto(`${base}?story=${story.id}&theme=light`);
    await settle(page, 1000);
    let reached = true;
    for (const step of story.steps) {
      try {
        const at = (selector) => page.locator(selector).filter({ visible: true }).first();
        if (step.click) await at(step.click).click({ timeout: 5000 });
        if (step.rightClick) await at(step.rightClick).click({ button: 'right', timeout: 5000 });
        if (step.hover) await at(step.hover).hover({ timeout: 5000 });
        if (step.text) await page.getByText(step.text, { exact: true }).filter({ visible: true }).first().click({ timeout: 5000 });
        if (step.key) await page.keyboard.press(step.key);
        if (step.move) await page.mouse.move(step.move[0], step.move[1]);
        await settle(page, 450);
      } catch (e) {
        reached = false;
        wrong.push(`${story.id}: could not take step ${JSON.stringify(step)} (${e.message.split('\n')[0]})`);
        break;
      }
    }
    if (reached) {
      const c = await page.evaluate(corners);
      const p = await page.evaluate(panels);
      for (const w of [...c.wrong, ...p.wrong]) wrong.push(`${story.id}: ${w}`);
      if (out) await page.screenshot({ path: `${out}/${story.id}.png` });
      // Then each list scrolled to its end, and measured again: what is at a list's foot (⌘K's last row) shows only so.
      const scrolled = await page.evaluate(() => {
        let n = 0;
        for (const el of document.querySelectorAll('body *')) {
          const o = getComputedStyle(el);
          if (/auto|scroll/.test(o.overflowY) && el.scrollHeight > el.clientHeight + 1) { el.scrollTop = el.scrollHeight; n++; }
          if (/auto|scroll/.test(o.overflowX) && el.scrollWidth > el.clientWidth + 1) { el.scrollLeft = el.scrollWidth; n++; }
        }
        return n;
      });
      let more = 0;
      if (scrolled) {
        await settle(page, 300);
        const c2 = await page.evaluate(corners), p2 = await page.evaluate(panels);
        for (const w of [...c2.wrong, ...p2.wrong]) { wrong.push(`${story.id} (scrolled to the end): ${w}`); more++; }
        if (out && more) await page.screenshot({ path: `${out}/${story.id}-end.png` });
      }
      console.log(`${story.id}: ${c.measured} corner(s), ${p.surfaces} panel(s) measured${scrolled ? `, again scrolled to the end` : ''}; ${c.wrong.length + p.wrong.length + more} off`);
    }
    for (const e of errors) console.log(`${story.id}: page error ${e}`);
    await page.close();
  };
  // Several at once, each in a page of its own.
  const queue = [...stories];
  await Promise.all(Array.from({ length: Number(process.env.PAGES) || 6 }, async () => { while (queue.length) await take(queue.shift()); }));
  const distinct = [...new Set(wrong)];
  if (process.env.REPORT) { console.log(`\n${distinct.length} off:`); for (const w of distinct) console.log('  ' + w); }
  else assert.deepEqual(distinct, []);
  console.log(`ok: ${stories.length} stories, every corner and small panel as it should be`);
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
