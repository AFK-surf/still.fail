// The share page end to end (docs/public-share.md): a station's guest door (station/src/publish/guest.ts, on the mesh
// addon, on a relay) holding one published snapshot — people's and agents' messages, Markdown, code, images, a mermaid
// chart, an HTML visualization, a file to download — and the page, from a dev cloud's share host, reading it. Pictures
// of it at a phone's and a desktop's width, light and dark, and of each way it fails (the link cut short, taken down,
// the station away); a file downloaded on a visit of its own; the page's console (a CSP refusal shows there).
// Needs a dev cloud whose share host was built for it (cloud/test/dev.ts says how), and station/ installed.
//   STILLFAIL_MESH_NATIVE=$(node scripts/native.ts file mesh) PLAYWRIGHT_MODULE=… SHOTS=<dir> \
//     node test/browser/share-page.mjs http://127.0.0.1:<PORT + 5> [relay, default http://127.0.0.1:3340]
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Store } from '../../station/src/store/store.ts';
import { Guests, GUEST_ALPN } from '../../station/src/publish/guest.ts';
import { snapshotDir } from '../../station/src/publish/index.ts';
import { loadMesh } from '../../station/src/mesh/native.ts';
import { linkHash } from '../../web/src/share/link.ts';

const [shareHost, relay = 'http://127.0.0.1:3340'] = process.argv.slice(2);
assert.ok(shareHost, 'usage: share-page.mjs <share host> [relay]');
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.SHOTS;
if (out) mkdirSync(out, { recursive: true });
const random = (n) => randomBytes(n).toString('base64url');

const tmp = mkdtempSync(join(tmpdir(), 'share-page-'));
let store, endpoint, browser;
try {
  browser = await playwright.chromium.launch({ args: ['--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessChecks'] });

  // The pictures in the chat: made here, as screenshots are.
  const draw = async (html, width, height) => {
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
    await page.setContent(`<body style="margin:0;font:15px -apple-system,system-ui,sans-serif">${html}</body>`);
    const png = await page.screenshot({ type: 'png' });
    await page.close();
    return png;
  };
  const broken = await draw(`<div style="height:100vh;display:grid;place-items:center;background:#f6f6f8"><div style="width:300px;padding:28px;border-radius:16px;background:#fff;box-shadow:0 2px 12px #0001">
    <div style="font-weight:600;font-size:20px;margin-bottom:16px">登录</div><div style="height:38px;border:1px solid #ddd;border-radius:10px;margin-bottom:10px;padding:9px 12px;color:#999">邮箱</div>
    <div style="height:38px;border:1px solid #ddd;border-radius:10px;margin-bottom:16px;padding:9px 12px;color:#999">密码</div><div style="height:40px;border-radius:20px;background:#bbb;color:#fff;display:grid;place-items:center">继续</div>
    <div style="margin-top:12px;color:#c33;font-size:13px">TypeError: undefined is not an object (evaluating 'form.requestSubmit')</div></div></div>`, 720, 480);
  const fixed = await draw(`<div style="height:100vh;display:grid;place-items:center;background:#f6f6f8"><div style="width:300px;padding:28px;border-radius:16px;background:#fff;box-shadow:0 2px 12px #0001">
    <div style="font-weight:600;font-size:20px;margin-bottom:16px">登录</div><div style="height:38px;border:1px solid #ddd;border-radius:10px;margin-bottom:10px;padding:9px 12px">alice@acme.dev</div>
    <div style="height:38px;border:1px solid #ddd;border-radius:10px;margin-bottom:16px;padding:9px 12px">••••••••••</div><div style="height:40px;border-radius:20px;background:#e5704a;color:#fff;display:grid;place-items:center">继续</div>
    <div style="margin-top:12px;color:#2f8f5b;font-size:13px">✓ 已登录，正在跳转…</div></div></div>`, 720, 480);
  const timing = `<div style="font:14px var(--e-font, system-ui);color:var(--e-text)">
  <div style="font-weight:600;margin-bottom:10px">登录耗时（p50，毫秒）</div>
  ${[['Chrome', 180, 182], ['Safari', 2400, 190], ['Firefox', 175, 178]].map(([name, before, after]) => `
  <div style="display:grid;grid-template-columns:64px 1fr;gap:6px 10px;align-items:center;margin-bottom:8px"><span>${name}</span>
    <div><div style="height:10px;border-radius:5px;background:var(--e-line-strong);width:${Math.round((before / 2400) * 100)}%"></div>
    <div style="height:10px;border-radius:5px;margin-top:4px;background:var(--e-accent);width:${Math.round((after / 2400) * 100)}%"></div></div></div>`).join('')}
  <div style="color:var(--e-muted);font-size:12px">灰：修之前 · 橙：修之后</div></div>`;
  const log = 'vitest run --project web\n ✓ test/login.test.ts (12 tests) 340ms\n ✓ test/form.test.ts (4 tests) 85ms\n\n Test Files  2 passed (2)\n      Tests  16 passed (16)\n';

  const t0 = Date.parse('2026-10-15T09:12:00+08:00');
  const files = [
    { k: 'f0', name: 'safari-login.png', type: 'image/png', bytes: broken, width: 720, height: 480 },
    { k: 'f1', name: 'login-fixed.png', type: 'image/png', bytes: fixed, width: 720, height: 480 },
    { k: 'f2', name: 'timing.html', type: 'text/html', bytes: Buffer.from(timing) },
    { k: 'f3', name: 'test-run.log', type: 'text/plain', bytes: Buffer.from(log) },
  ];
  const meta = (f) => ({ k: f.k, name: f.name, size: f.bytes.length, type: f.type, ...(f.width ? { width: f.width, height: f.height } : {}) });
  const snapshot = {
    v: 1, title: 'Safari 上登录按钮没反应', station: 'Studio', at: t0 + 3600_000, by: '小王', redacted: 1,
    entries: [
      { n: 1, at: t0, authorKind: 'person', author: '小王', text: '登录页在 Safari 上点「继续」没反应，控制台报错见截图。帮忙看一下？', files: [meta(files[0])] },
      { n: 2, at: t0 + 95_000, authorKind: 'agent', author: 'ember', text: [
        '找到了：Safari 16.3 及以前没有 `HTMLFormElement.requestSubmit()`，`LoginForm.tsx` 里直接调用它，所以点了没反应。',
        '',
        '## 改法',
        '',
        '1. 有 `requestSubmit` 时照旧用它（会走浏览器自己的表单校验）',
        '2. 没有时先 `reportValidity()`，再派发一个 `submit` 事件',
        '',
        '```ts',
        'export function submit(form: HTMLFormElement) {',
        '  if (typeof form.requestSubmit === "function") return form.requestSubmit();',
        '  if (!form.reportValidity()) return;',
        '  form.dispatchEvent(new Event("submit", { cancelable: true, bubbles: true }));',
        '}',
        '```',
        '',
        '改完在 Safari 16.3 上试过：',
        '',
        '![](login-fixed.png)',
        '',
        '测试用的账号密码已经换成 `[已隐藏]`，没有写进代码。',
      ].join('\n'), files: [meta(files[1])] },
      { n: 3, at: t0 + 140_000, authorKind: 'agent', author: 'ember', text: [
        '提交的流程现在是这样：',
        '',
        '```mermaid',
        'flowchart LR',
        '  A[点「继续」] --> B{有 requestSubmit?}',
        '  B -- 有 --> C[requestSubmit]',
        '  B -- 没有 --> D[reportValidity] --> E[派发 submit]',
        '  C --> F[onSubmit 登录]',
        '  E --> F',
        '```',
        '',
        '三个浏览器上登录的耗时，修之前 Safari 是超时重试才进去的：',
        '',
        '[登录耗时](timing.html)',
      ].join('\n'), files: [meta(files[2])] },
      { n: 4, at: t0 + 600_000, authorKind: 'person', author: '小王', text: '好了，Safari 上能登录了。合进去吧 https://github.com/acme/web/pull/412', files: [] },
      { n: 5, at: t0 + 660_000, authorKind: 'agent', author: 'ember', text: [
        '已合进 main，测试都过了：',
        '',
        '| 浏览器 | 修之前 | 修之后 |',
        '|---|---|---|',
        '| Safari 16.3 | 点了没反应 | 正常 |',
        '| Chrome 141 | 正常 | 正常 |',
        '| Firefox 143 | 正常 | 正常 |',
        '',
        '完整的测试输出在附件里。',
      ].join('\n'), files: [meta(files[3])] },
    ],
  };

  // The station: its store with the snapshot written out, its guest door on the relay.
  store = Store.open(join(tmp, 'stillfail.db'));
  const id = random(12), key = random(32);
  mkdirSync(join(snapshotDir(store, id), 'f'), { recursive: true });
  const json = Buffer.from(JSON.stringify(snapshot));
  writeFileSync(join(snapshotDir(store, id), 'snapshot.json'), json);
  for (const f of files) writeFileSync(join(snapshotDir(store, id), 'f', f.k), f.bytes);
  store.addPublished({ id, thread: 1, key, title: snapshot.title, by: 'wang@acme.dev', byName: '小王', at: snapshot.at, upto: 5, size: json.length + files.reduce((n, f) => n + f.bytes.length, 0) });
  const guests = new Guests(store);
  endpoint = await loadMesh().bind({ secretKey: randomBytes(32), alpns: [GUEST_ALPN], relayUrls: [relay] });
  await endpoint.online();
  let visits = 0, open = 0;
  void (async () => {
    for (let conn = await endpoint.accept(); conn; conn = await endpoint.accept()) {
      if (!conn.alpn().equals(GUEST_ALPN)) { conn.close(0, 'no'); continue; }
      visits++;
      open++;
      void guests.serve(conn).finally(() => { open--; });
    }
  })();
  const station = endpoint.id();
  const linkOf = (k = key, s = station) => `${shareHost}/${linkHash(s, id, k)}`;
  console.log(`station ${station} on ${relay}; link ${linkOf()}`);

  const errors = [];
  const look = async (name, url, { width, height, scheme, mobile, ready }) => {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 2, isMobile: mobile, hasTouch: mobile, colorScheme: scheme, locale: 'zh-CN', acceptDownloads: true });
    const page = await context.newPage();
    page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errors.push(`${name}: ${m.text()}`); });
    page.on('pageerror', (e) => errors.push(`${name}: ${e.message}`));
    page.on('requestfailed', (r) => errors.push(`${name}: ${r.url()} ${r.failure()?.errorText}`));
    await page.goto(url);
    try {
      await ready(page);
    } catch (e) {
      // What it showed instead, and what it said.
      if (out) await page.screenshot({ path: join(out, `${name}-failed.png`), fullPage: true });
      console.log(errors.join('\n'));
      throw e;
    }
    if (out) {
      // The whole page in view at once: a frame out of view is not painted, and a full-page picture would show it blank.
      const tall = await page.evaluate(() => document.documentElement.scrollHeight);
      await page.setViewportSize({ width, height: Math.max(height, tall) });
      await page.waitForTimeout(1500);
      await page.screenshot({ path: join(out, `${name}.png`) });
      await page.setViewportSize({ width, height });
    }
    return { page, context };
  };
  // Read whole: every image in, the visualization and the chart drawn in their frames, no visit left open.
  const whole = async (page) => {
    await page.waitForSelector('main h1', { timeout: 60_000 });
    await page.waitForFunction(() => [...document.querySelectorAll('main button img')].length >= 2 && [...document.querySelectorAll('main img')].every((i) => i.complete && i.naturalWidth > 0), null, { timeout: 60_000 });
    // Sized to what they drew: their scripts ran (the mermaid chart's needs its CDN; without it, it is its code). A frame
    // out of view is not laid out (Chromium throttles it): each is brought into view first.
    await page.waitForFunction(() => document.querySelectorAll('main iframe').length > 0, null, { timeout: 60_000 });
    for (const frame of await page.locator('main iframe').all()) {
      await frame.scrollIntoViewIfNeeded();
      await page.waitForFunction((f) => { const h = f.getBoundingClientRect().height; return h > 20 && h !== 120; }, await frame.elementHandle(), { timeout: 60_000 });
    }
    await page.evaluate(() => scrollTo(0, 0));
    await page.waitForTimeout(800);
  };
  const shapes = [
    ['phone', { width: 390, height: 844, mobile: true }],
    ['desktop', { width: 1280, height: 800, mobile: false }],
  ];
  for (const [shape, size] of shapes) {
    for (const scheme of ['light', 'dark']) {
      const { context } = await look(`${shape}-${scheme}`, linkOf(), { ...size, scheme, ready: whole });
      await context.close();
    }
  }
  // Each visit went once it had read what it came for (the station closes one left idle only after 30 s).
  for (let i = 0; i < 50 && open > 0; i++) await new Promise((r) => setTimeout(r, 100));
  assert.equal(open, 0, 'a visit left open');
  console.log(`visits: ${visits}, open now: ${open}`);

  // A file not shown: read on a visit of its own when asked for, and saved.
  {
    const { page, context } = await look('download', linkOf(), { width: 1280, height: 800, mobile: false, scheme: 'light', ready: whole });
    const before = visits;
    const [download] = await Promise.all([page.waitForEvent('download', { timeout: 60_000 }), page.getByRole('button', { name: /test-run\.log/ }).click()]);
    assert.equal(download.suggestedFilename(), 'test-run.log');
    const saved = join(tmp, 'saved.log');
    await download.saveAs(saved);
    assert.equal((await import('node:fs')).readFileSync(saved, 'utf8'), log);
    assert.equal(visits, before + 1, 'one more visit for it');
    await context.close();
  }

  // What fails, a line each.
  const said = (text) => async (page) => { await page.getByText(text).waitFor({ timeout: 60_000 }); };
  for (const [name, url, text] of [
    ['malformed', `${shareHost}/#${station.slice(0, 20)}`, '这个链接不完整'],
    ['gone', linkOf(random(32)), '这个分享不存在或已撤销'],
    ['offline', linkOf(key, randomBytes(32).toString('hex')), '连不上这台 station'],
  ]) {
    const { context } = await look(`state-${name}`, url, { width: 390, height: 844, mobile: true, scheme: 'light', ready: said(text) });
    await context.close();
  }
  if (errors.length) console.log(`console:\n  ${errors.join('\n  ')}`);
  assert.ok(!errors.some((e) => /Content Security Policy/i.test(e)), 'the page or a frame was refused something by its CSP');
  console.log('share page: ok');
} finally {
  await browser?.close();
  await endpoint?.close();
  store?.close?.();
  rmSync(tmp, { recursive: true, force: true });
}
// The station's idle timers would hold the process for half a minute more.
process.exit(0);
