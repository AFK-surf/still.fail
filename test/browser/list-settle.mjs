// What moves in a chat's message list never makes what shows jump: played in the demo's chat (its made-up core, the
// real pages), each thing that comes, goes or changes size there is watched frame by frame, as drawn (sampled after
// the frame's layout, its observers and scroll put right), and no message may move one way and back within a few
// frames: a box laid out at another size for a moment, the pane pulled up by the browser and put back, a gap snapping
// shut at the end. The list follows its end (scrolled to the bottom, taller than the pane), where all of that shows.
// Each case is played on the wide pages and on the phone's. Not a check of timing: frames dropped or slow change how
// many samples there are, never which way anything moves.
// PLAYWRIGHT_MODULE selects Playwright; SHOTS keeps each case's samples (JSON), and with RECORD=1 its frames as drawn
// (JPEG, from the browser's screencast); ONLY=<case> plays one; JUMPS=1 fails on a jump too (else it is said); PAGES=<n> plays at once (2); THROTTLE=<n> slows the page's CPU n times (a slower
// machine than the one at hand: what moves must not depend on it).
import assert from 'node:assert/strict';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
const fixture = new URL('../../web/list-settle-check.tsx', import.meta.url);
const html = new URL('../../web/list-settle-check.html', import.meta.url);
let server, browser, madeFixture = false, madeHtml = false;

/** In the page: what a station would say into the open chat, and the frames sampled as drawn. */
function helpers() {
  const { core, message } = window.demo;
  const chat = () => core.chats.find((c) => c.key === 'ember:c-demo-safari');
  const set = (change) => { const c = chat(); change(c); core.publish(); };
  const card = (c, asked = true) => ({
    ...message(c, 'agent', '部署有两种做法：\n\n- 直接替换，几分钟完成，会中断一下\n- 新旧并行再切流量，慢一点但不中断\n\n你选哪个？', Date.now()),
    options: [{ label: '直接替换', detail: '几分钟完成，会中断一下' }, { label: '并行切换', detail: '慢一点，不中断', recommended: true }, { label: '先不部署', detail: '等下周再说' }],
    card: { type: 'options', assigneeText: '待你决策' }, decision: { resolved: false }, ...(asked ? { asked: true } : {}),
  });
  const pane = () => {
    let e = document.querySelector('[data-vk^="m:"]');
    while (e && !(e.scrollHeight > e.clientHeight && /auto|scroll/.test(getComputedStyle(e).overflowY))) e = e.parentElement;
    return e;
  };
  /**
   * Each frame as it is drawn: read in a size observer of its own, made after the list's (observers are told in the
   * order they were made), so after the list has put the pane right and the activity's glide drawn where it is, in the
   * frame's rendering, before it is painted. (A task after the frame may come after the next change, not yet drawn.)
   */
  const sample = (ms) => new Promise((done) => {
    const frames = [];
    const t0 = performance.now();
    // The agents' lines there already (one starting now is new).
    const before = new Set([...(pane()?.querySelectorAll(':scope > [data-vk^="a:"]') ?? [])].map((a) => a.dataset.vk));
    const beat = document.body.appendChild(document.createElement('div'));
    beat.style.cssText = 'position:fixed;left:0;top:0;height:1px;width:1px;pointer-events:none;opacity:0';
    let n = 0;
    const seen = new ResizeObserver(() => {
      const p = pane();
      const rows = {};
      // Not one that shows nothing: a message waiting to come out of its avatar, an activity folded while its avatar flies,
      // a message sent covered by the copy flying from the composer, one waiting its turn (listQueue.ts).
      for (const el of p?.querySelectorAll(':scope > [data-vk]:not([data-held]):not([data-away]):not([data-send-covered]):not([data-queued])') ?? []) rows[el.dataset.vk] = Math.round(el.getBoundingClientRect().top * 10) / 10;
      // An agent's line showing while the reader's message is still on its way to the list (it comes once that lands).
      const act = [...(p?.querySelectorAll(':scope > [data-vk^="a:"]') ?? [])].find((a) => !before.has(a.dataset.vk));
      const early = !!act && !!p.querySelector(':scope > [data-send-covered]') && act.getBoundingClientRect().height > 4 && +getComputedStyle(act).opacity > 0.1;
      frames.push({ t: Math.round(performance.now() - t0), top: p ? Math.round(p.scrollTop) : null, rows, early });
    });
    seen.observe(beat);
    const tick = () => {
      if (performance.now() - t0 >= ms) { seen.disconnect(); beat.remove(); done(frames); return; }
      beat.style.width = `${(n++ % 2) + 1}px`;
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
  window.check = { chat, set, card, pane, sample, message };
}

/** Rows moving one way and then back within three frames, by two pixels or more each way (less is not seen: a step
 * of the pane and of what closes falling a frame apart). */
function backAndForth(frames) {
  const found = [];
  for (let i = 1; i < frames.length; i++) {
    for (const [key, top] of Object.entries(frames[i].rows)) {
      const was = frames[i - 1].rows[key];
      if (was === undefined) continue;
      const d = top - was;
      if (Math.abs(d) < 2) continue;
      for (let j = i + 1; j < Math.min(frames.length, i + 3); j++) {
        const a = frames[j - 1].rows[key], b = frames[j].rows[key];
        if (a === undefined || b === undefined) break;
        const e = b - a;
        if (Math.abs(e) >= 2 && Math.sign(e) !== Math.sign(d)) { found.push(`${key} ${d > 0 ? '+' : ''}${d.toFixed(1)}px at ${frames[i].t}ms, back ${e.toFixed(1)}px at ${frames[j].t}ms`); break; }
      }
    }
  }
  return found;
}

/**
 * Rows jumping: in one frame by a lot (24px or more), and at three times the speed or more of the frames either side
 * (by the time each frame took: a long frame's bigger step on a slow machine is still the same glide), only on screen.
 */
function jumps(frames, height) {
  const found = [];
  const speed = (a, b, ta, tb) => (b - a) / Math.max(8, tb - ta);
  for (let i = 2; i < frames.length - 1; i++) {
    for (const [key, top] of Object.entries(frames[i].rows)) {
      const a = frames[i - 2].rows[key], b = frames[i - 1].rows[key], c = frames[i + 1].rows[key];
      if (a === undefined || b === undefined || c === undefined) continue;
      if ((b < 0 || b > height) && (top < 0 || top > height)) continue;
      const d = top - b;
      if (Math.abs(d) < 24) continue;
      const v = Math.abs(speed(b, top, frames[i - 1].t, frames[i].t));
      const around = Math.max(Math.abs(speed(a, b, frames[i - 2].t, frames[i - 1].t)), Math.abs(speed(top, c, frames[i].t, frames[i + 1].t)));
      if (v >= 3 * around) found.push(`${key} ${d > 0 ? '+' : ''}${d.toFixed(1)}px at once at ${frames[i].t}ms`);
    }
  }
  return found;
}

const CASES = {
  // A whole turn: a message sent, its agent at work at once, then its reply said as it stops (in the same moment, as
  // an agent's last post and its turn's end come).
  async turn(page) {
    await page.evaluate(() => check.set((c) => { c.running = null; }));
    await page.waitForTimeout(1200);
    const field = page.locator('textarea:not([aria-hidden])').filter({ visible: true }).last();
    await field.fill('把登录页按钮改一下');
    const watching = page.evaluate(() => check.sample(4200));
    await field.press('Enter');
    await page.evaluate(() => check.set((c) => { c.running = { activity: '读取 src/auth/LoginForm.tsx', since: Date.now(), started: true }; }));
    await page.waitForTimeout(1600);
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.message(c, 'agent', '改好了：\n\n- 按钮撑满容器\n- 左右各 16px\n- 深色模式下也看得见')]; }));
    await page.waitForTimeout(60);
    await page.evaluate(() => check.set((c) => { c.running = null; }));
    return watching;
  },
  // A message written in the composer and sent, nothing asked.
  async send(page) {
    await page.waitForTimeout(300);
    const field = page.locator('textarea:not([aria-hidden])').filter({ visible: true }).last();
    await field.fill('再看一下手机上的效果');
    const watching = page.evaluate(() => check.sample(2600));
    await field.press('Enter');
    return watching;
  },
  // A message sent, and its agent at work at once (before the words have landed): its line comes after them.
  async work(page) {
    await page.evaluate(() => check.set((c) => { c.running = null; }));
    await page.waitForTimeout(1200);
    const field = page.locator('textarea:not([aria-hidden])').filter({ visible: true }).last();
    await field.fill('先跑一下测试');
    const watching = page.evaluate(() => check.sample(2600));
    await field.press('Enter');
    await page.evaluate(() => check.set((c) => { c.running = { activity: '运行 pnpm test', since: Date.now(), started: true }; }));
    return watching;
  },
  // The agent says something, no line of its own at work showing: it comes in at the end, followed.
  async arrive(page) {
    await page.evaluate(() => check.set((c) => { c.running = null; }));
    await page.waitForTimeout(1200);
    const watching = page.evaluate(() => check.sample(1500));
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.message(c, 'agent', '改好了，截图在这：\n\n- 按钮撑满容器\n- 左右各 16px\n- 深色模式下也看得见')]; }));
    return watching;
  },
  // One taller than the pane comes in: followed from its top.
  async long(page) {
    await page.evaluate(() => check.set((c) => { c.running = null; }));
    await page.waitForTimeout(1200);
    const watching = page.evaluate(() => check.sample(1500));
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.message(c, 'agent', Array.from({ length: 40 }, (_, i) => `- 第 ${i + 1} 项：登录页按钮、表单留白和深色模式都检查过了`).join('\n'))]; }));
    return watching;
  },
  // A reply written in the composer answers the card: its options settle into the line saying so.
  async reply(page) {
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.card(c)]; }));
    await page.waitForTimeout(900);
    const field = page.locator('textarea:not([aria-hidden])').filter({ visible: true }).last();
    await field.fill('就并行吧');
    const watching = page.evaluate(() => check.sample(1800));
    await field.press('Enter');
    return watching;
  },
  // An option picked.
  async pick(page) {
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.card(c)]; }));
    await page.waitForTimeout(900);
    const watching = page.evaluate(() => check.sample(1800));
    await page.getByRole('button', { name: /并行切换/ }).last().click();
    return watching;
  },
  // 忽略 under it: gone, its room closing.
  async dismiss(page) {
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.card(c)]; }));
    await page.waitForTimeout(900);
    const watching = page.evaluate(() => check.sample(1500));
    await page.getByRole('button', { name: '忽略', exact: true }).last().click();
    return watching;
  },
  // 留着/归档 under the last post, coming and then going.
  async archive(page) {
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.message(c, 'agent', '都做完了，分支已经合进 main。', Date.now())]; }));
    await page.waitForTimeout(900);
    const coming = page.evaluate(() => check.sample(1200));
    await page.evaluate(() => check.set((c) => { c.messages = c.messages.map((m, i) => (i === c.messages.length - 1 ? { ...m, archive: true } : m)); }));
    const came = await coming;
    await page.waitForTimeout(300);
    const going = page.evaluate(() => check.sample(1200));
    await page.evaluate(() => check.set((c) => { c.messages = c.messages.map(({ archive: _, ...m }) => m); }));
    return [...came, ...(await going)];
  },
  // The agent at work: its line comes in at the end, and goes once it stops.
  async activity(page) {
    const coming = page.evaluate(() => check.sample(1000));
    await page.evaluate(() => check.set((c) => { c.running = { activity: '读取 src/auth/LoginForm.tsx', since: Date.now(), started: true }; }));
    const came = await coming;
    const going = page.evaluate(() => check.sample(1800));
    await page.evaluate(() => check.set((c) => { c.running = null; }));
    return [...came, ...(await going)];
  },
  // A message said as its agent's line shows comes out of its avatar; then the agent stops.
  async emit(page) {
    await page.evaluate(() => check.set((c) => { c.running = { activity: '运行 pnpm test login', since: Date.now(), started: true }; }));
    await page.waitForTimeout(900);
    const watching = page.evaluate(() => check.sample(2600));
    await page.evaluate(() => check.set((c) => { c.messages = [...c.messages, check.message(c, 'agent', '测试都过了，18 个用例全绿。\n\n- 登录页按钮撑满容器\n- 表单左右各 16px')]; }));
    await page.waitForTimeout(1300);
    await page.evaluate(() => check.set((c) => { c.running = null; }));
    return watching;
  },
};

try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import './src/styles/index.ts';
import { DemoApp, demoCore } from './src/demo/mount.tsx';
import { message } from './src/demo/fixtures.ts';
const root = document.getElementById('app')!;
root.style.cssText = 'position:fixed;inset:0';
Object.assign(window, { demo: { core: demoCore, message } });
createRoot(root).render(<DemoApp phone={location.hash === '#phone'} />);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/list-settle-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false }, logLevel: 'error' });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  if (out) await mkdir(out, { recursive: true });
  browser = await playwright.chromium.launch(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {});
  const failures = [];
  const notes = [];
  // SHARD=<i>/<n>: only the i-th of every n of the plays (CI's jobs side by side).
  const [shard, shards] = (process.env.SHARD || '1/1').split('/').map(Number);
  let played = -1;
  const plays = [];
  for (const phone of [false, true]) for (const [name, play] of Object.entries(CASES)) {
    if (process.env.ONLY && process.env.ONLY !== name) continue;
    if (++played % shards !== shard - 1) continue;
    plays.push([phone, name, play]);
  }
  // PAGES of them at once (2), each in a context of its own: a play is mostly its page's own time running (what it
  // waits for comes by real frames), so one after another the job was waiting, not working: a share took 90-150 s on
  // CI's runners (2026-10-23). Frames dropped while another plays change how many samples there are, never which way
  // anything moves (THROTTLE).
  const take = async (phone, name, play) => {
    const context = await browser.newContext(phone
      ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN' }
      : { viewport: { width: 1280, height: 800 }, locale: 'zh-CN' });
    const page = await context.newPage();
    if (process.env.THROTTLE) await (await context.newCDPSession(page)).send('Emulation.setCPUThrottlingRate', { rate: Number(process.env.THROTTLE) });
    page.on('pageerror', (e) => failures.push(`${name}: page error ${e.message}`));
    await page.goto(base + '/list-settle-check.html' + (phone ? '#phone' : ''));
    await page.waitForFunction(() => !!window.demo && !!document.querySelector('[data-vk^="m:"]'), null, { timeout: 30000 });
    await page.evaluate(helpers);
    // Long enough to scroll, and at its end: what is said there is followed.
    await page.evaluate(() => check.set((c) => {
      const said = ['先看一下最近的提交', '登录页这两天改得最多', '按钮写死了 320px', '手机上超出了屏幕', '改成撑满容器了', '截图看过了'];
      for (let i = 0; i < 8; i++) c.messages = [...c.messages, check.message(c, i % 2 ? 'agent' : 'me', said[i % said.length], Date.now() - (8 - i) * 60_000)];
    }));
    await page.waitForTimeout(1200);
    const where = `${phone ? 'phone' : 'wide'} ${name}`;
    const shots = [];
    const cdp = out && process.env.RECORD ? await context.newCDPSession(page) : null;
    if (cdp) {
      cdp.on('Page.screencastFrame', (f) => { shots.push(f.data); cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {}); });
      await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 80, everyNthFrame: 1 });
    }
    const frames = await play(page);
    // Come to rest (on a slow machine what came last may still be gliding): then where it stopped.
    const end = await page.evaluate(async () => {
      const p = check.pane();
      let last = -1;
      for (let n = 0; n < 40 && p.scrollTop !== last; n++) { last = p.scrollTop; await new Promise((r) => setTimeout(r, 150)); }
      return p.scrollHeight - p.clientHeight - p.scrollTop;
    });
    if (cdp) {
      await cdp.send('Page.stopScreencast');
      const dir = `${out}/${where.replace(' ', '-')}`;
      await mkdir(dir, { recursive: true });
      await Promise.all(shots.map((data, i) => writeFile(`${dir}/f${String(i).padStart(3, '0')}.jpg`, Buffer.from(data, 'base64'))));
    }
    if (out) await writeFile(`${out}/${where.replace(' ', '-')}.json`, JSON.stringify(frames));
    assert.ok(frames.length > 20, `${where}: frames were sampled (${frames.length})`);
    const found = backAndForth(frames);
    if (found.length) failures.push(`${where}: moved and back\n    ${found.slice(0, 6).join('\n    ')}`);
    const jumped = jumps(frames, phone ? 844 : 800);
    // (an agent's line may come as the words sent fly: nothing waits for another, each row opening its own room,
    // docs/list-motion.md, 2026-10-30)
    // Said, not failed on, unless JUMPS=1: how big a step a frame takes is the machine's (a slow frame's is bigger).
    if (jumped.length) (process.env.JUMPS ? failures : notes).push(`${where}: jumped\n    ${jumped.slice(0, 6).join('\n    ')}`);
    // (One taller than the pane is read from its top: not followed to the end.)
    if (end > 1 && name !== 'long') failures.push(`${where}: left ${Math.round(end)}px short of the list's end`);
    console.log(found.length || (process.env.JUMPS && jumped.length) ? 'FAIL' : 'ok  ', where, `(${frames.length} frames)`);
    await context.close();
  };
  await Promise.all(Array.from({ length: Number(process.env.PAGES) || 2 }, async () => {
    while (plays.length) await take(...plays.shift());
  }));
  if (notes.length) console.log(notes.join('\n'));
  if (failures.length) { console.error(failures.join('\n')); process.exitCode = 1; }
} finally {
  await browser?.close();
  await server?.close();
  if (madeFixture) await rm(fixture);
  if (madeHtml) await rm(html);
}
