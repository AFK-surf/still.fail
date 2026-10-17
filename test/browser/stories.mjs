// Every story (web/stories/stories.tsx) opened, taken to its state by its steps, and measured (measure.mjs: every
// corner, every small panel; docs/ui-panels.md); then, as it rests, drawn the same with motion reduced (measure.mjs
// drawn: motion reduced only takes the time out of motion). A new part of the app with a
// story is measured with no more written here. Builds the stories once (as a page, not module by module: the dev server's per-module transforms were most of
// the time on CI's four cores) and serves the build. PLAYWRIGHT_MODULE selects Playwright (PLAYWRIGHT_CHANNEL a Chrome the
// machine has, as CI's); SHOTS keeps a picture of each story; ONLY=<id,…> opens only those; REPORT=1 lists what is off
// instead of failing; PAGES how many are opened at once (6); SHARD=<i>/<n> only the i-th of every n (CI's jobs side by side).
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, preview } from 'vite';
import { corners, drawn, panels } from './measure.mjs';
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

  // Still: drawn the same twice a little apart (what moves by script, its springs, is not among the page's animations).
  const steady = async (page) => {
    let was = null;
    for (let i = 0; i < 20; i++) {
      const { lines, loops } = await page.evaluate(drawn);
      const now = JSON.stringify(lines.filter((l) => { const at = l.split(' ')[0]; return !loops.some((x) => at === x || at.startsWith(`${x}>`)); }));
      if (now === was) return;
      was = now;
      await page.waitForTimeout(150);
    }
  };

  const wrong = [];
  /** A page with the story in it, taken to its state by its steps; whether it got there. */
  const open = async (story) => {
    const page = await browser.newPage({ viewport: story.phone ? { width: 390, height: 844 } : { width: 1280, height: 800 }, deviceScaleFactor: 1, locale: 'zh-CN', reducedMotion: 'no-preference' });
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
        if (step.hold) {
          // A real finger, held on its middle as long as a long press.
          const box = await at(step.hold).boundingBox({ timeout: 5000 });
          const cdp = await page.context().newCDPSession(page);
          await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x + box.width / 2, y: box.y + box.height / 2 }] });
          await page.waitForTimeout(800);
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        }
        await settle(page, 450);
      } catch (e) {
        reached = false;
        wrong.push(`${story.id}: could not take step ${JSON.stringify(step)} (${e.message.split('\n')[0]})`);
        break;
      }
    }
    return { page, errors, reached };
  };
  const take = async (story) => {
    const { page, errors, reached } = await open(story);
    if (reached) {
      const c = await page.evaluate(corners);
      const p = await page.evaluate(panels);
      for (const w of [...c.wrong, ...p.wrong]) wrong.push(`${story.id}: ${w}`);
      // Motion reduced and not, twice each, on the page held still (the demo's chats ended where they are): drawn the same
      // (it only takes the time out of motion). A difference follows the setting both times: what changes on a switch
      // whichever way (a bar woken by the pointer the page's change moves over again) or with time is not its doing; nor
      // is what loops, or what is in it.
      await page.evaluate(() => window.endDemo?.());
      const at = async (reducedMotion) => {
        await page.emulateMedia({ reducedMotion });
        await steady(page);
        return page.evaluate(drawn);
      };
      const look = async () => {
        const seen = [await at('reduce'), await at('no-preference'), await at('reduce'), await at('no-preference')];
        const loops = seen.flatMap((s) => s.loops);
        const shown = (lines) => new Set(lines.filter((l) => { const at = l.split(' ')[0]; return !loops.some((x) => at === x || at.startsWith(`${x}>`)); }));
        const [reduced, moving, reducedAgain, movingAgain] = seen.map((s) => shown(s.lines));
        const only = (a, b, not1, not2) => [...a].filter((l) => b.has(l) && !not1.has(l) && !not2.has(l));
        return [
          ...only(moving, movingAgain, reduced, reducedAgain).map((l) => `with motion ${l}`),
          ...only(reduced, reducedAgain, moving, movingAgain).map((l) => `motion reduced ${l}`),
        ];
      };
      const differs = await look();
      if (differs.length) wrong.push(`${story.id}: drawn otherwise with motion reduced (${differs.length} line(s)): ${differs.slice(0, 6).join('; ')}`);
      if (out && differs.length) await writeFile(`${out}/${story.id}-reduced.txt`, differs.join('\n'));
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
