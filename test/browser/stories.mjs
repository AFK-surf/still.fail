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
// (how far the page's own time runs on after each step: the longest of its motions and of what waits on them)
const still_ms = 3000;
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

  // The page's time is the test's (Playwright's clock): its timers, its frames and the demo's core run as far as a step
  // says, at once, never a wait of real time. Settled: fonts and pictures in, the page's time run on by `ms` (what
  // comes late: the demo's next line), then by `still_ms` more in steps, each step's transitions and finite animations
  // taken to their ends (they run on the browser's own clock: finished, not waited for; spinners go on), so that what
  // the app times by them (a row's turn after the one before it, listQueue.ts) comes as it would.
  // (the clock's moves on the page's own controller, what page.clock.runFor asks of it: page.clock's each add a script
  // to the context, run again in every page it opens after, and a context here opens the stories one after another)
  const tick = (page, ms) => page.evaluate((ms) => globalThis.__pwClock.controller.runFor(ms), ms);
  // What comes in real time, held to the test's (a script in each of the context's documents, before the page's own).
  // A video or a song never plays in real time: play() and pause() say so as an element does (its paused, its events),
  // and its time stays where it is, as the clock's does once fixed; what it loads (its length, its first frame, a seek)
  // is waited for. So is what else comes to the page in real time (a fetch and its body, a blob's bytes, a picture, a
  // font, a video's frames decoded): each a named event, never a wait of real time. Played as it came, the stories'
  // clip (4 s) had got as far as real time took it by each look, its end (its controls back) in some runs and not in
  // others (run 40064315157).
  const hold = () => {
    const pending = new Set();
    const track = (p) => { if (p && typeof p.then === 'function') { pending.add(p); const done = () => pending.delete(p); p.then(done, done); } return p; };
    const wrap = (o, k) => { const f = o[k]; if (typeof f === 'function') o[k] = function (...a) { return track(f.apply(this, a)); }; };
    wrap(globalThis, 'fetch');
    for (const k of ['arrayBuffer', 'blob', 'bytes', 'formData', 'json', 'text']) wrap(Response.prototype, k);
    for (const k of ['arrayBuffer', 'bytes', 'text']) wrap(Blob.prototype, k);
    wrap(globalThis, 'createImageBitmap');
    // A video decoder's frames, owed from each chunk it is given until it gives one back (or is flushed, reset, closed).
    const owed = new Map();
    const heard = new Set();
    const owe = (d, n) => {
      const left = n === null ? 0 : (owed.get(d) ?? 0) + n;
      if (left > 0) owed.set(d, left); else owed.delete(d);
      for (const r of heard) r();
      heard.clear();
    };
    if (globalThis.VideoDecoder) {
      globalThis.VideoDecoder = class extends VideoDecoder {
        constructor(init) {
          super({ ...init, output: (f) => { owe(this, -1); init.output(f); }, error: (e) => { owe(this, null); init.error(e); } });
        }
        decode(chunk) { owe(this, 1); return super.decode(chunk); }
        flush() { return track(super.flush().finally(() => owe(this, null))); }
        reset() { owe(this, null); return super.reset(); }
        close() { owe(this, null); return super.close(); }
      };
    }
    // No service worker: one takes the page over, and answers a drive's file a range at a time, in real time (its
    // waits on the clock's timers). A file is read whole so, as where a browser runs none (drive/stream.ts).
    delete Navigator.prototype.serviceWorker;
    const media = HTMLMediaElement.prototype;
    const playing = new WeakSet();
    const fire = (el, type) => queueMicrotask(() => el.dispatchEvent(new Event(type)));
    Object.defineProperty(media, 'paused', { configurable: true, enumerable: true, get() { return !playing.has(this); } });
    media.play = function () {
      if (!playing.has(this)) { playing.add(this); fire(this, 'play'); fire(this, this.readyState >= HTMLMediaElement.HAVE_FUTURE_DATA ? 'playing' : 'waiting'); }
      return Promise.resolve();
    };
    media.pause = function () { if (playing.delete(this)) fire(this, 'pause'); };
    // (a new source stops it, as it does an element playing)
    addEventListener('emptied', (e) => { if (playing.delete(e.target)) fire(e.target, 'pause'); }, true);
    // Loading: until its first frame (a song's length) is in, or it stopped loading short of it, or failed; seeking.
    const loading = (el) => !el.error && el.networkState !== HTMLMediaElement.NETWORK_NO_SOURCE && !!el.currentSrc
      && (el.seeking || (el.readyState < (el instanceof HTMLVideoElement ? HTMLMediaElement.HAVE_CURRENT_DATA : HTMLMediaElement.HAVE_METADATA)
        && !(el.readyState >= HTMLMediaElement.HAVE_METADATA && el.networkState === HTMLMediaElement.NETWORK_IDLE)));
    const on = (el, types) => new Promise((r) => { for (const t of types) el.addEventListener(t, r, { once: true }); });
    const task = () => new Promise((r) => { const c = new MessageChannel(); c.port1.onmessage = () => r(); c.port2.postMessage(0); });
    // Done once a task of its own (what was let in takes its turn: a render, the next read) finds nothing still coming.
    globalThis.__held = async () => {
      for (;;) {
        await task();
        const waits = [...pending];
        if (document.fonts.status === 'loading') waits.push(document.fonts.ready);
        for (const i of document.images) if (!i.complete) waits.push(on(i, ['load', 'error']));
        if (owed.size) waits.push(new Promise((r) => heard.add(r)));
        for (const m of document.querySelectorAll('video, audio')) if (loading(m)) waits.push(on(m, ['loadeddata', 'suspend', 'seeked', 'error', 'emptied', 'abort']));
        if (!waits.length) return;
        await Promise.race(waits).catch(() => {});
      }
    };
  };
  // Its steps in the page itself, not two round trips each: a share's pages spent 238-326 s settling so, 115-158 s
  // in the page, its run 125-139 s and 114-117 s on the same runners, nothing measured otherwise (2026-10-23). Before
  // each step, what comes in real time is in (hold).
  const settle = (page, ms) => page.evaluate(async ([ms, still]) => {
    await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
    await globalThis.__held();
    const clock = globalThis.__pwClock.controller;
    await clock.runFor(ms);
    for (let t = 0; t < still; t += 100) {
      const going = document.getAnimations().filter((a) => (a.playState === 'running' || a.pending) && a.effect?.getTiming().iterations !== Infinity);
      for (const a of going) a.finish();
      await Promise.all(going.map((a) => a.finished.catch(() => {})));
      await globalThis.__held();
      await clock.runFor(100);
    }
  }, [ms, still_ms]);

  // Still: what moves by script (its springs, not among the page's animations) at its end: settled. Its steps in the page
  // itself, on the clock Playwright puts there (what page.clock.runFor asks of it), not two round trips each: the page
  // held still (the demo ended, its time fixed), nothing it waits for comes in real time meanwhile. The four looks of
  // a story were a third of the stories' time on CI's runners, 161-237 s of a share's pages, 29-54 s so (2026-10-23).
  const steady = (page) => page.evaluate(async (still) => {
    const clock = globalThis.__pwClock.controller;
    for (let t = 0; t < still; t += 100) {
      const going = document.getAnimations().filter((a) => (a.playState === 'running' || a.pending) && a.effect?.getTiming().iterations !== Infinity);
      for (const a of going) a.finish();
      await Promise.all(going.map((a) => a.finished.catch(() => {})));
      await clock.runFor(100);
    }
  }, still_ms);

  const wrong = [];
  /** A page with the story in it, taken to its state by its steps; whether it got there. */
  const open = async (story, page, cdp) => {
    // What the story before it kept in the browser gone (its storage, its cookies, the pointer over it, a finger's
    // emulation, motion reduced): only what the context's cache holds stays. Opened in the page the one before was in
    // (a document of its own), the app's scripts compiled once a page rather than once a story: a story opened in 266 ms
    // in a page of its own, 67 ms so (Studio, 2026-10-23); in a context of its own, a page 30% sooner. The clock is the
    // context's, each document's from the same moment.
    await page.evaluate(() => sessionStorage.clear()).catch(() => {});
    await page.context().clearCookies();
    await cdp.send('Storage.clearDataForOrigin', { origin: new URL(base).origin, storageTypes: 'all' });
    await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: false });
    await page.mouse.move(-1, -1);
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    await page.setViewportSize(story.phone ? { width: 390, height: 844 } : { width: 1280, height: 800 });
    const errors = [];
    const onError = (e) => errors.push(e.message);
    page.on('pageerror', onError);
    await page.goto(`${base}?story=${story.id}&theme=light`);
    await settle(page, 1000);
    let reached = true;
    for (const step of story.steps) {
      try {
        const at = (selector) => page.locator(selector).filter({ visible: true }).first();
        // (the pointer first, as a hand moves before it presses: what wakes as it moves is there to press)
        if (step.move) await page.mouse.move(step.move[0], step.move[1]);
        if (step.click) await at(step.click).click({ timeout: 5000 });
        if (step.rightClick) await at(step.rightClick).click({ button: 'right', timeout: 5000 });
        if (step.hover) await at(step.hover).hover({ timeout: 5000 });
        if (step.text) await page.getByText(step.text, { exact: true }).filter({ visible: true }).first().click({ timeout: 5000 });
        if (step.key) await page.keyboard.press(step.key);
        if (step.hold) {
          // A real finger, held on its middle as long as a long press.
          const box = await at(step.hold).boundingBox({ timeout: 5000 });
          await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x + box.width / 2, y: box.y + box.height / 2 }] });
          await tick(page, 800);
          await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        }
        await settle(page, 450);
      } catch (e) {
        reached = false;
        wrong.push(`${story.id}: could not take step ${JSON.stringify(step)} (${e.message.split('\n')[0]})`);
        break;
      }
    }
    return { errors, reached, done: () => page.off('pageerror', onError) };
  };
  const take = async (story, page, cdp) => {
    const { errors, reached, done } = await open(story, page, cdp);
    if (reached) {
      const c = await page.evaluate(corners);
      const p = await page.evaluate(panels);
      for (const w of [...c.wrong, ...p.wrong]) wrong.push(`${story.id}: ${w}`);
      // Motion reduced and not, twice each, on the page held still (the demo's chats ended where they are): drawn the same
      // (it only takes the time out of motion). A difference follows the setting both times: what changes on a switch
      // whichever way (a bar woken by the pointer the page's change moves over again) or with time is not its doing; nor
      // is what loops, or what is in it.
      await page.evaluate(() => window.endDemo?.());
      // The clock's time held where it is from here on (its timers and frames still run, so what moves gets to its end):
      // what reads the time (a wait's minutes and seconds) says the same at each look. Run on, a counter's width matched
      // with motion twice and not without, by chance (run 39732288569).
      await page.evaluate(() => globalThis.__pwClock.controller.setFixedTime(Date.now()));
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
    done();
    for (const e of errors) console.log(`${story.id}: page error ${e}`);
  };
  // Several at once, each line of them in a page and a context of its own.
  const queue = [...stories];
  await Promise.all(Array.from({ length: Number(process.env.PAGES) || 6 }, async () => {
    const context = await browser.newContext({ deviceScaleFactor: 1, locale: 'zh-CN', reducedMotion: 'no-preference' });
    await context.clock.install();
    await context.addInitScript(hold);
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    while (queue.length) await take(queue.shift(), page, cdp);
    await context.close();
  }));
  const distinct = [...new Set(wrong)];
  if (process.env.REPORT) { console.log(`\n${distinct.length} off:`); for (const w of distinct) console.log('  ' + w); }
  else assert.deepEqual(distinct, []);
  console.log(`ok: ${stories.length} stories, every corner and small panel as it should be`);
} finally {
  await browser?.close();
  await server?.close();
  if (dist) await rm(dist, { recursive: true, force: true });
}
