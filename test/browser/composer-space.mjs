// The real mobile composer: a new chat's choices follow its height during a morph, while an existing chat's
// inherited spacing changes only when the morph settles. No station: the demo core supplies the composer topics.
// Runs its own Vite server. PLAYWRIGHT_MODULE and ENGINES (chromium,webkit by default) select browsers.
import assert from 'node:assert/strict';
import { writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/composer-space-check.tsx', import.meta.url);
const html = new URL('../../web/composer-space-check.html', import.meta.url);
let server, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, String.raw`import React, { useLayoutEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import './src/styles/index.ts';
import './src/demo/mount.tsx';
import { ACCOUNT } from './src/demo/station.ts';
import { setPageRoot } from './src/brand.tsx';
import { useDraft } from './src/draft.ts';
import { MobileShell } from './src/mobile/app.tsx';
import { MobileComposer } from './src/mobile/ChatHost.tsx';
import * as hostCss from './src/mobile/ChatHost.css.ts';
import * as newCss from './src/mobile/NewChat.css.ts';
import * as pageCss from './src/mobile/styles/pages.css.ts';

function Page() {
  const [fresh, setFresh] = useState(true);
  // ChatHost first mounts the page, then its composer when the page supplies its shown specification.
  const [mounted, setMounted] = useState(false);
  useLayoutEffect(() => setMounted(true), []);
  const root = useRef<HTMLDivElement>(null);
  const upload = useRef<any>(async () => { throw Error('no uploads in this fixture'); });
  const shared = useDraft({ station: 'demo/local', upload: (...args) => upload.current(...args) });
  const draft = { ...shared, focus: 0, bumpFocus() {} };
  const now = useRef(draft); now.current = draft;
  const shown = { station: 'demo/local', placeholder: '输入内容', offline: false };
  const latest = useRef({ ...shown, send() {} });
  Object.assign(window, { composerMode: setFresh });
  return <div className={hostCss.mChatHost} ref={root} data-new={fresh || undefined} style={{ '--m-foot': '0px', '--m-top': '0px' } as React.CSSProperties}>
    {fresh && <div className={newCss.mNewFoot}>
      <div className={newCss.mNewBottom}><div className={newCss.mChoosers} data-review-choices>
        <button className={newCss.mChooser + ' ' + pageCss.mFloating}>Studio</button>
        <button className={newCss.mChooser + ' ' + pageCss.mFloating}>模型</button>
      </div></div>
    </div>}
    {mounted && <MobileComposer shown={shown} draftKey={undefined} latest={latest} draft={draft} now={now} root={root} upload={upload} />}
  </div>;
}
history.replaceState(null, '', '/w/demo');
const root = document.getElementById('app')!;
setPageRoot(root);
createRoot(root).render(<BrowserRouter><MobileShell entry={{ id: 'demo', name: 'Test', account: ACCOUNT }} routes={() => <Page />} recent={() => null} /></BrowserRouter>);
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<!doctype html><html lang="zh"><meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/composer-space-check.tsx"></script></html>', { flag: 'wx' });
  madeHtml = true;
  server = await createServer({ configFile: fileURLToPath(new URL('../../web/vite.demo.config.ts', import.meta.url)), root: fileURLToPath(new URL('../../web', import.meta.url)), server: { host: '127.0.0.1', port: 0, hmr: false } });
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  for (const engine of (process.env.ENGINES || 'chromium,webkit').split(',')) {
    const browser = await playwright[engine].launch();
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, reducedMotion: 'no-preference' });
      await page.addInitScript(() => {
        const animate = Element.prototype.animate;
        Element.prototype.animate = function(...args) {
          const motion = animate.apply(this, args);
          if (this.closest('[data-made-composer]')) { motion.pause(); motion.currentTime = 0; }
          return motion;
        };
      });
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      const frames = () => page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
      const finish = async () => {
        await page.evaluate(async () => {
          const all = document.querySelector('[data-made-composer]').getAnimations({ subtree: true });
          for (const a of all) a.finish();
          await Promise.allSettled(all.map(a => a.finished));
        });
        await frames();
      };
      const size = () => page.evaluate(() => {
        const box = document.querySelector('[data-made-composer]');
        return { reserved: parseFloat(box.parentElement.parentElement.style.getPropertyValue('--m-bottom')), actual: box.parentElement.offsetHeight };
      });
      await page.goto(base + '/composer-space-check.html');
      const input = page.locator('textarea:not([aria-hidden])');
      await input.waitFor();
      await page.evaluate(() => document.fonts.ready);
      await input.fill('一行');
      await finish();
      for (const fresh of [true, false]) {
        await page.evaluate(fresh => window.composerMode(fresh), fresh);
        await input.fill('一行');
        await finish();
        const before = await size();
        await input.fill('一行\n两行\n三行\n四行\n五行');
        await page.waitForFunction(() => document.querySelector('[data-made-composer]').getAnimations().some(a => a.playState === 'paused'));
        await page.evaluate(() => {
          window.composerMotion = document.querySelector('[data-made-composer]').getAnimations()[0];
          window.composerMotion.pause();
        });
        for (const progress of [0.25, 0.5, 0.75]) {
          await page.evaluate(progress => { window.composerMotion.currentTime = window.composerMotion.effect.getTiming().duration * progress; }, progress);
          await frames();
          if (fresh) {
            const geometry = await page.evaluate(() => {
              const box = document.querySelector('[data-made-composer]').getBoundingClientRect();
              return { top: box.top, bottoms: [...document.querySelectorAll('[data-review-choices] button')].map(button => button.getBoundingClientRect().bottom) };
            });
            assert.ok(geometry.bottoms.every(bottom => bottom <= geometry.top), `${engine}: choices stay above the growing composer at ${progress}: ${JSON.stringify(geometry)}`);
          } else {
            assert.equal((await size()).reserved, before.reserved, `${engine}: a chat's inherited spacing stays put during the morph`);
          }
        }
        await finish();
        const final = await size();
        assert.equal(final.reserved, final.actual, `${engine}: settled spacing matches the composer`);
      }
      assert.deepEqual(errors, []);
      console.log(`PASS ${engine}: new-chat choices follow the composer; chat spacing waits for its settled height`);
    } finally { await browser.close(); }
  }
} finally {
  await server?.close();
  if (madeFixture) await rm(fixture);
  if (madeHtml) await rm(html);
}
