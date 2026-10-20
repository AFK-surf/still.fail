// The share page end to end (docs/public-share.md): a station's guest door (station/src/publish/guest.ts, on the mesh
// addon, on a relay) holding one published snapshot — people's and agents' messages, Markdown, code, images, a mermaid
// chart, an HTML visualization, files of each kind the preview shows (a log, Markdown, TypeScript, a PDF, a CSV, an
// HTML page) — and the page, from a dev cloud's share host, reading it. Pictures of it at a phone's and a desktop's
// width, light and dark, and of each way it fails (the link cut short, taken down, the station away); files opened in
// the chat's preview (read on a visit of their own, or from what the page has), pictured too, and one downloaded from
// it; HTML only ever in the host's sandboxed /frame; the page's console (a CSP refusal shows there).
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
  const notes = [
    '# Safari 登录修复说明', '',
    '## 原因', '',
    'Safari 16.3 及以前没有 `HTMLFormElement.requestSubmit()`，`LoginForm.tsx` 直接调用它，点「继续」时抛错，表单没有提交。', '',
    '## 改动', '',
    '- `LoginForm.tsx` 改用 `submit(form)`',
    '- 新增 `submit.ts`：没有 `requestSubmit` 时先 `reportValidity()`，再派发 `submit` 事件',
    '- 测试里补了 Safari 16.3 的用例', '',
    '| 浏览器 | 修之前 | 修之后 |', '|---|---|---|', '| Safari 16.3 | 点了没反应 | 正常 |', '| Chrome 141 | 正常 | 正常 |', '| Firefox 143 | 正常 | 正常 |', '',
    '```ts', 'submit(form); // 两种浏览器都走这里', '```', '',
    '> 测试账号已经换成 `[已隐藏]`，没有写进代码。', '',
  ].join('\n');
  const code = [
    '// Submits a form as a click on its submit button would, in browsers without requestSubmit (Safari ≤ 16.3) too.',
    'export function submit(form: HTMLFormElement): void {',
    '  if (typeof form.requestSubmit === "function") {',
    '    form.requestSubmit();',
    '    return;',
    '  }',
    '  // The browser\'s own checks first, as requestSubmit runs them.',
    '  if (!form.reportValidity()) return;',
    '  const event = new Event("submit", { cancelable: true, bubbles: true });',
    '  form.dispatchEvent(event);',
    '}',
    '',
    'export const supported = (form: HTMLFormElement): boolean => typeof form.requestSubmit === "function";',
    '',
  ].join('\n');
  const csv = 'browser,version,before_ms,after_ms,result\nSafari,16.3,2400,190,fixed\nSafari,17.6,185,183,ok\nChrome,141,180,182,ok\nFirefox,143,175,178,ok\nEdge,141,182,181,ok\n';
  // A page of its own: its script runs (in its frame), and finds no way to the page around it.
  const demo = `<!doctype html><html><head><meta charset="utf-8"><title>Login check</title><style>body{font:15px system-ui,sans-serif;margin:32px;color:#222;background:#fff}h1{font-size:22px}#ran{padding:12px 16px;border-radius:10px;background:#eef7f0;color:#1d6b3a}</style></head>
<body><h1>登录检查页</h1><p>这是一个完整的 HTML 页面，在分享页里只放进沙箱里的 /frame 显示。</p><p id="ran">脚本没跑</p>
<script>let reach;try{reach=parent.document?'碰到了父页面':'?'}catch(e){reach='碰不到父页面'}document.getElementById('ran').textContent='脚本跑了 · '+reach+' · '+(self.origin==='null'?'没有自己的源':'源是 '+self.origin)</script></body></html>`;
  // A report, two pages, printed as a PDF is.
  const pdf = await (async () => {
    const page = await browser.newPage();
    await page.setContent(`<body style="font:14px -apple-system,system-ui,sans-serif;margin:48px;color:#222">
      <h1 style="font-size:26px">Safari 登录问题报告</h1><p style="color:#666">2026-10-15 · Studio</p>
      <h2 style="font-size:18px;margin-top:28px">现象</h2><p>Safari 16.3 上点「继续」没有反应，控制台报 <code>TypeError: undefined is not an object (evaluating 'form.requestSubmit')</code>。</p>
      <h2 style="font-size:18px;margin-top:28px">耗时（p50，毫秒）</h2>
      <table style="border-collapse:collapse;width:100%">${[['浏览器', '修之前', '修之后'], ['Safari 16.3', '2400', '190'], ['Chrome 141', '180', '182'], ['Firefox 143', '175', '178']]
        .map((r, i) => `<tr>${r.map((c) => `<${i ? 'td' : 'th'} style="border-bottom:1px solid #ddd;padding:8px;text-align:left">${c}</${i ? 'td' : 'th'}>`).join('')}</tr>`).join('')}</table>
      <div style="page-break-before:always"></div><h2 style="font-size:18px">附：改动</h2><pre style="background:#f5f5f7;padding:16px;border-radius:8px">${code.replace(/</g, '&lt;')}</pre></body>`);
    const bytes = await page.pdf({ format: 'A4', printBackground: true });
    await page.close();
    return bytes;
  })();

  const t0 = Date.parse('2026-10-15T09:12:00+08:00');
  const files = [
    { k: 'f0', name: 'safari-login.png', type: 'image/png', bytes: broken, width: 720, height: 480 },
    { k: 'f1', name: 'login-fixed.png', type: 'image/png', bytes: fixed, width: 720, height: 480 },
    { k: 'f2', name: 'timing.html', type: 'text/html', bytes: Buffer.from(timing) },
    { k: 'f3', name: 'test-run.log', type: 'text/plain', bytes: Buffer.from(log) },
    { k: 'f4', name: 'fix-notes.md', type: 'text/markdown', bytes: Buffer.from(notes) },
    { k: 'f5', name: 'submit.ts', type: 'text/plain', bytes: Buffer.from(code) },
    { k: 'f6', name: 'report.pdf', type: 'application/pdf', bytes: Buffer.from(pdf) },
    { k: 'f7', name: 'timings.csv', type: 'text/csv', bytes: Buffer.from(csv) },
    { k: 'f8', name: 'login-check.html', type: 'text/html', bytes: Buffer.from(demo) },
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
      { n: 6, at: t0 + 720_000, authorKind: 'agent', author: 'ember', text: [
        '补充材料：[修复说明](fix-notes.md)，还有代码、报告、数据和一个检查页，都在下面。',
      ].join('\n'), files: files.slice(4).map(meta) },
    ],
  };

  // The station: its store with the snapshot written out, its guest door on the relay.
  store = Store.open(join(tmp, 'stillfail.db'));
  const id = random(12), key = random(32);
  mkdirSync(join(snapshotDir(store, id), 'f'), { recursive: true });
  const json = Buffer.from(JSON.stringify(snapshot));
  writeFileSync(join(snapshotDir(store, id), 'snapshot.json'), json);
  for (const f of files) writeFileSync(join(snapshotDir(store, id), 'f', f.k), f.bytes);
  store.addPublished({ id, thread: 1, key, title: snapshot.title, by: 'wang@acme.dev', byName: '小王', at: snapshot.at, upto: 6, size: json.length + files.reduce((n, f) => n + f.bytes.length, 0) });
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
  const look = async (name, url, { width, height, scheme, mobile, ready, shot = true }) => {
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
    if (out && shot) {
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

  // Files open in the chat's preview: one the page has not read on a visit of its own (once), one it has (an image)
  // from what it has; each kind pictured. HTML only ever in the host's sandboxed /frame, never srcdoc, never its origin.
  const dialog = (page) => page.getByRole('dialog');
  /** The preview's bars showing (they fade when the pointer rests): a mouse moved over it, a finger's tap. */
  const awake = async (page, mobile) => {
    if (await dialog(page).getAttribute('data-awake') !== null) return;
    if (mobile) await page.touchscreen.tap(195, 500);
    else await page.mouse.move(640, 420);
    await page.waitForFunction(() => document.querySelector('[role=dialog]')?.hasAttribute('data-awake'), null, { timeout: 5000 });
  };
  const frames = async (page) => {
    for (const f of await page.locator('iframe').all()) {
      assert.equal(await f.getAttribute('sandbox'), 'allow-scripts', 'a frame sandboxed without its origin');
      assert.equal(await f.getAttribute('srcdoc'), null, 'no frame written from the page');
      assert.equal(await f.getAttribute('src'), '/frame', "every frame the host's /frame");
    }
  };
  const kinds = {
    log: { open: (page) => page.getByRole('button', { name: '查看 test-run.log' }).click(), ready: (page) => dialog(page).getByText('Test Files').waitFor({ timeout: 60_000 }) },
    md: { open: (page) => page.locator('main a', { hasText: '修复说明' }).click(), ready: (page) => dialog(page).getByRole('heading', { name: 'Safari 登录修复说明' }).waitFor({ timeout: 60_000 }) },
    ts: { open: (page) => page.getByRole('button', { name: '查看 submit.ts' }).click(), ready: async (page) => { await dialog(page).getByText('export function submit').first().waitFor({ timeout: 60_000 }); await page.waitForTimeout(800); } },
    csv: { open: (page) => page.getByRole('button', { name: '查看 timings.csv' }).click(), ready: (page) => dialog(page).locator('table td', { hasText: 'Firefox' }).waitFor({ timeout: 60_000 }) },
    pdf: {
      open: (page) => page.getByRole('button', { name: '查看 report.pdf' }).click(),
      // Its first page drawn: something on the canvas that is not white (read from a copy: the page's own is pdf.js's).
      ready: (page) => page.waitForFunction(() => {
        const c = document.querySelector('[role=dialog] canvas');
        if (!c || !c.width) return false;
        const copy = document.createElement('canvas');
        copy.width = c.width;
        copy.height = Math.min(c.height, 400);
        const g = copy.getContext('2d', { willReadFrequently: true });
        g.drawImage(c, 0, 0);
        const d = g.getImageData(0, 0, copy.width, copy.height).data;
        for (let i = 0; i < d.length; i += 4) if (d[i] < 200) return true;
        return false;
      }, null, { timeout: 60_000 }),
    },
    image: {
      open: (page) => page.getByRole('button', { name: '查看 login-fixed.png' }).click(),
      ready: (page) => page.waitForFunction(() => { const i = document.querySelector('[role=dialog] img[data-viewer-picture]'); return i && i.complete && i.naturalWidth > 0 && !i.hasAttribute('data-waiting'); }, null, { timeout: 60_000 }),
    },
    html: {
      open: (page) => page.getByRole('button', { name: '查看 login-check.html' }).click(),
      ready: async (page) => {
        const ran = page.frameLocator('[role=dialog] iframe').locator('#ran', { hasText: '脚本跑了' });
        await ran.waitFor({ timeout: 60_000 });
        // Its script ran with no way to the page, in an origin of none.
        assert.match(await ran.textContent(), /碰不到父页面 · 没有自己的源/);
      },
    },
    viz: {
      open: (page) => page.getByRole('button', { name: '全屏打开' }).click(),
      ready: (page) => page.waitForFunction(() => { const f = document.querySelector('[role=dialog] iframe'); return f && f.getAttribute('src') === '/frame'; }, null, { timeout: 60_000 }).then(() => page.waitForTimeout(1500)),
    },
  };
  const preview = async (page, name, kind, mobile) => {
    const { open, ready } = kinds[kind];
    await open(page);
    await dialog(page).waitFor({ timeout: 10_000 });
    await ready(page);
    await frames(page);
    // Nothing in it a page could be opened from: its download is a button.
    assert.equal(await dialog(page).locator('a[href^="blob:"]').count(), 0, 'a link to a blob in the preview');
    if (out) {
      // Faded in (headless Chromium moves an animation on only as it draws frames: drawn each frame until it has).
      await page.waitForFunction(() => document.querySelector('[role=dialog]').getAnimations().every((a) => a.playState === 'finished'), null, { polling: 'raf', timeout: 10_000 });
      await awake(page, mobile);
      await page.screenshot({ path: join(out, `${name}.png`) });
    }
    await page.keyboard.press('Escape');
    await dialog(page).waitFor({ state: 'detached', timeout: 10_000 });
  };
  for (const [shape, size] of shapes) {
    for (const scheme of ['light', 'dark']) {
      const { page, context } = await look(`open-${shape}-${scheme}`, linkOf(), { ...size, scheme, ready: whole, shot: false });
      for (const kind of ['log', 'md', 'pdf', 'image']) await preview(page, `preview-${kind}-${shape}-${scheme}`, kind, size.mobile);
      if (shape === 'desktop' && scheme === 'light') for (const kind of ['ts', 'csv', 'html', 'viz']) await preview(page, `preview-${kind}-${shape}-${scheme}`, kind, false);
      await context.close();
    }
  }
  {
    const { page, context } = await look('download', linkOf(), { width: 1280, height: 800, mobile: false, scheme: 'light', ready: whole, shot: false });
    // An image the page has read opens from what it has: no visit; it steps to the snapshot's other image.
    let before = visits;
    await kinds.image.open(page);
    await kinds.image.ready(page);
    await dialog(page).getByText('2 / 2').waitFor({ timeout: 10_000 });
    await page.keyboard.press('ArrowLeft');
    await dialog(page).getByText('1 / 2').waitFor({ timeout: 10_000 });
    assert.equal(visits, before, 'no visit for an image the page has');
    await page.keyboard.press('Escape');
    await dialog(page).waitFor({ state: 'detached', timeout: 10_000 });
    // A file it has not: read on a visit of its own, once; its download saves those bytes, asking nothing more.
    before = visits;
    await kinds.log.open(page);
    await kinds.log.ready(page);
    assert.equal(visits, before + 1, 'one more visit for it');
    const [download] = await Promise.all([page.waitForEvent('download', { timeout: 60_000 }), dialog(page).getByRole('button', { name: '下载', exact: true }).click()]);
    assert.equal(download.suggestedFilename(), 'test-run.log');
    const saved = join(tmp, 'saved.log');
    await download.saveAs(saved);
    assert.equal((await import('node:fs')).readFileSync(saved, 'utf8'), log);
    assert.equal(visits, before + 1, 'the download asked nothing more');
    await context.close();
  }
  for (let i = 0; i < 50 && open > 0; i++) await new Promise((r) => setTimeout(r, 100));
  assert.equal(open, 0, "a preview's visit left open");

  // What fails, a line each.
  const said = (text) => async (page) => { await page.getByText(text).waitFor({ timeout: 60_000 }); };
  for (const [name, url, text] of [
    ['malformed', `${shareHost}/#${station.slice(0, 20)}`, '链接不完整，无法打开'],
    ['gone', linkOf(random(32)), '此分享不存在或已撤销'],
    ['offline', linkOf(key, randomBytes(32).toString('hex')), '无法连接此 station'],
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
