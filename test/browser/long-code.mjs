// The real Code component keeps searchable/copyable text while deferring offscreen highlighting.
import assert from 'node:assert/strict';
import { writeFile, rm, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/long-code-check.tsx', import.meta.url);
const html = new URL('../../web/long-code-check.html', import.meta.url);
let server, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React from 'react';
import { createRoot } from 'react-dom/client';
import './src/styles/index.ts';
import './src/demo/mount.tsx';
import { Code } from './src/Prose.tsx';
import { markdown } from './src/styles/conversation.css.ts';
import { ink } from '../client/core-ts/src/highlight.ts';
let source = Array.from({length: 1600}, (_, i) => 'const value' + i + ' = "你好 👋"; // line ' + i + '\n').join('');
Object.assign(window, {source});
const root = createRoot(document.getElementById('app')!);
const draw = () => root.render(<div className={markdown} style={{width: 370, margin: 10}}><Code text={source} language="typescript" ink={ink(source, 'typescript')} /></div>);
window.append = () => { source += '// the next streamed line\n'; window.source = source; draw(); };
draw();
`, { flag: 'wx' }); madeFixture = true;
  await writeFile(html, '<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/long-code-check.tsx"></script>', { flag: 'wx' }); madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  for (const engine of (process.env.ENGINES || 'chromium,webkit').split(',')) {
    const browser = await playwright[engine].launch();
    try {
      const page = await browser.newPage({ viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true });
      await page.addInitScript(() => {
        Object.defineProperty(navigator, 'clipboard', { value: {writeText: async text => {window.copied = text;}} });
      });
      const errors = []; page.on('pageerror', error => errors.push(error.message));
      await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/long-code-check.html`);
      await page.waitForFunction(() => document.querySelector('[data-code-chunk] span'));
      const stats = () => page.evaluate(() => ({
        text: document.querySelector('pre code').textContent === window.source,
        chunks: document.querySelectorAll('[data-code-chunk]').length,
        painted: [...document.querySelectorAll('[data-code-chunk]')].filter(el => el.children.length).length,
        spans: document.querySelectorAll('pre span').length,
        height: document.querySelector('pre').getBoundingClientRect().height,
      }));
      const before = await stats();
      assert(before.text); assert(before.chunks > 30); assert(before.painted < before.chunks / 4);
      // An arriving line changes the source and ink, but not the reader's selection in an earlier line.
      await page.evaluate(() => {
        const walker = document.createTreeWalker(document.querySelector('pre code'), NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          const at = node.textContent.indexOf('value0');
          if (at < 0) continue;
          const range = document.createRange(); range.setStart(node, at); range.setEnd(node, at + 6);
          getSelection().removeAllRanges(); getSelection().addRange(range);
          break;
        }
        window.append();
      });
      await page.waitForFunction(() => document.querySelector('pre code').textContent === window.source);
      assert.equal(await page.evaluate(() => getSelection().toString()), 'value0', 'streamed code preserves selection in unchanged text');
      await page.evaluate(() => getSelection().removeAllRanges());
      const appended = await stats();
      await page.getByRole('button').click();
      assert.equal(await page.evaluate(() => window.copied === window.source), true, 'copy button includes offscreen code');
      // Select all before a far chunk enters view. Its plain text nodes must not be replaced under the selection.
      const selected = await page.evaluate(() => {
        const code = document.querySelector('pre code');
        const range = document.createRange(); range.selectNodeContents(code);
        const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
        const target = document.querySelector('[data-code-chunk="25"]');
        window.targetNode = target.firstChild;
        target.scrollIntoView({block:'center'});
        return selection.toString();
      });
      await page.waitForTimeout(200);
      assert.equal(await page.evaluate(() => getSelection().toString()), selected, 'scroll highlighting preserves selection');
      assert.equal(await page.evaluate(() => document.querySelector('[data-code-chunk="25"]').firstChild === window.targetNode), true);
      await page.evaluate(() => getSelection().removeAllRanges());
      await page.waitForFunction(() => document.querySelector('[data-code-chunk="25"] span'));
      assert.equal(await page.evaluate(() => {
        getSelection().removeAllRanges();
        return window.find('value1500') && getSelection().toString() === 'value1500';
      }), true, 'browser find reaches code whose highlighting was deferred');
      await page.evaluate(() => getSelection().removeAllRanges());
      const after = await stats();
      assert(after.text); assert(Math.abs(after.height - appended.height) < 1, 'highlighting changes no geometry');
      if (process.env.SHOTS) {
        await mkdir(process.env.SHOTS, {recursive:true});
        await page.screenshot({path:`${process.env.SHOTS}/long-code-${engine}.png`});
      }
      assert.deepEqual(errors, []);
      console.log(`PASS ${engine}: source, copy, selection, stable height; initially ${before.painted}/${before.chunks} chunks highlighted (${before.spans} spans)`);
    } finally { await browser.close(); }
  }
} finally {
  await server?.close();
  if (madeFixture) await rm(fixture, {force:true});
  if (madeHtml) await rm(html, {force:true});
}
