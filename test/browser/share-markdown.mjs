// The real share entry and Vite stand-ins, with only the guest transport replaced by an in-memory station.
// No login, native addon or relay needed. Exercises the same parsing path in messages and attachment previews.
// node test/browser/share-markdown.mjs (SHOTS=<dir> saves phone/desktop light/dark evidence)
import assert from 'node:assert/strict';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createServer } from 'vite';
import { chromium } from 'playwright-core';

const words = [
  '## 分享排版一致性', '',
  '**粗体**、*斜体*、~~删除~~ 与 `行内代码`。', '',
  '| 项目 | 结果 | 数量 |', '|:---|:---:|---:|', '| 中文表格 | 正常 | 42 |', '| 较长内容也能保持完整可读 | 通过 | 100 |', '',
  '> 引用内容', '', '- [x] 已完成', '- [ ] 待处理', '', '1. 第一项', '2. 第二项', '',
  '```ts', 'const answer = 42; // shared colours', '```', '',
  '公式：\\(x^2 + y^2\\)', '', '$$', '\\frac{a}{b}', '$$', '',
  '[外部链接](https://example.com/docs)', '',
];
const notes = words.join('\n');
const noteFile = { k: 'f0', name: 'notes.md', type: 'text/markdown', size: Buffer.byteLength(notes) };
const snapshot = { v: 1, title: '分享页排版验证', station: 'test', at: 1793000000000, by: 'test', redacted: 0, entries: [
  { n: 1, at: 1793000000000, authorKind: 'agent', author: 'Codex', text: notes + '\n也可以[查看附件](notes.md)。', files: [noteFile] },
] };
const transport = `
export class Unreachable extends Error {}
export async function visit() {
  return { close: async () => {}, conn: { openBi: async () => {
    let request, sent = false;
    return {
      write: async b => { request = JSON.parse(new TextDecoder().decode(b)); }, finish: async () => {},
      read: async () => {
        if (sent) return null; sent = true;
        const text = request.file ? ${JSON.stringify(notes)} : ${JSON.stringify(JSON.stringify(snapshot))};
        const body = new TextEncoder().encode(text);
        const head = new TextEncoder().encode(JSON.stringify({ok:true,size:body.length,type:request.file?'text/markdown':'application/json'})+'\\n');
        const bytes = new Uint8Array(head.length+body.length); bytes.set(head); bytes.set(body,head.length); return bytes;
      }
    };
  } } };
}`;
const server = await createServer({
  configFile: resolve('web/vite.share.config.ts'),
  root: resolve('web'),
  server: { host: '127.0.0.1', port: 0 },
  plugins: [{ name: 'test-guest-transport', enforce: 'pre', load(id) {
    if (id === resolve('web/src/share/iroh.ts')) return transport;
  } }],
});
let browser;
try {
  await server.listen();
  const base = server.resolvedUrls.local[0];
  browser = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : { channel: process.env.PLAYWRIGHT_CHANNEL }) });
  for (const width of [390, 1280]) for (const colorScheme of ['light', 'dark']) {
    const context = await browser.newContext({ viewport: { width, height: 1000 }, deviceScaleFactor: 2, colorScheme, locale: 'zh-CN' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    page.setDefaultTimeout(15000);
    await page.route('**/v1/relays', r => r.fulfill({ json: { relay_urls: ['https://relay.invalid'] } }));
    await page.goto(base + 'share/#' + Buffer.alloc(32).toString('base64url') + '.AbCdEfGhIjKlMn_-.'.concat('k'.repeat(43)));
    const check = async scope => {
      await scope.getByRole('heading', { name: '分享排版一致性' }).waitFor();
      assert.equal(await scope.locator('table th').count(), 3);
      assert.equal(await scope.locator('table td').count(), 6);
      assert.equal(await scope.locator('strong').textContent(), '粗体');
      assert.equal(await scope.locator('em').textContent(), '斜体');
      assert.equal(await scope.locator('del').textContent(), '删除');
      assert.equal(await scope.locator('blockquote').textContent(), '引用内容');
      assert.equal(await scope.locator('ol li').count(), 2);
      assert.equal(await scope.locator('input[type=checkbox]:checked').count(), 1);
      assert.equal(await scope.locator('a[href="https://example.com/docs"]').count(), 1);
      assert.ok(await scope.locator('pre span').count() > 0, 'code has highlighted tokens');
      await scope.locator('[role=math] svg').first().waitFor();
      assert.equal(await scope.locator('[role=math]').count(), 2);
    };
    await check(page.locator('main'));
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'tables do not overflow the page');
    if (process.env.SHOTS) {
      mkdirSync(process.env.SHOTS, { recursive: true });
      await page.screenshot({ path: resolve(process.env.SHOTS, `share-${width}-${colorScheme}.png`), fullPage: true });
    }
    await page.getByRole('link', { name: '查看附件', exact: true }).click();
    await check(page.getByRole('dialog'));
    assert.deepEqual(errors, [], 'no rendering errors');
    await context.close();
    console.log(`${width}px ${colorScheme}: message and Markdown attachment passed`);
  }
} finally {
  await browser?.close();
  await server.close();
}
