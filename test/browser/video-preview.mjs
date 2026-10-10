// Run with `pnpm dev:web --host 127.0.0.1 --port 5187` in another terminal.
// Requires ffmpeg and Playwright (PLAYWRIGHT_MODULE may name an external installation).
// ENGINES selects the engines; CHROMIUM_EXECUTABLE optionally selects an installed Chromium.
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
const temp = mkdtempSync(join(tmpdir(), 'ember-video-'));
const fixture = new URL('../../web/src/video-check.tsx', import.meta.url);
const html = new URL('../../web/video-check.html', import.meta.url);
let browser;
let madeFixture = false, madeHtml = false;
try {
  writeFileSync(fixture, `import React from 'react';
  import './styles/index.ts';
  document.documentElement.dataset.theme = 'light';
  import {BrowserRouter} from 'react-router';
  import {Tooltip} from 'radix-ui';
  import {setPageRoot} from './brand.tsx';
  import {createRoot} from 'react-dom/client';
  import {Files} from './Chat.tsx';
  import {setCore, setTopicSource} from './core/react.ts';
  setCore({call: (...args) => window.__videoTestCall(...args), subscribe: () => () => {}} as any);
  setTopicSource(topic => topic.topic === 'prefs' ? {lang:'zh'} : undefined);
  const file = (name: string) => ({name, path: '/test/'+name,size:1000});
  setPageRoot(document.getElementById('root')!);
  createRoot(document.getElementById('root')!).render(<BrowserRouter><Tooltip.Provider><><Files owner={()=>'test'} files={[file('sample.mp4'),file('broken.webm')]}/><div style={{height:2500}}/><Files owner={()=>'test'} files={[file('later.mp4')]}/></></Tooltip.Provider></BrowserRouter>);
  `, {flag: 'wx'});
  madeFixture = true;
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/video-check.tsx"></script>\n', {flag: 'wx'});
  madeHtml = true;
  execFileSync('ffmpeg', ['-v','error','-f','lavfi','-i','color=c=blue:s=320x180:d=2','-c:v','libx264','-pix_fmt','yuv420p',join(temp,'sample.mp4')]);
  for (const engine of (process.env.ENGINES || 'chromium,webkit').split(',')) {
    browser = await playwright[engine].launch({headless:true, ...(engine === 'chromium' && process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE} : {})});
    const page=await browser.newPage({locale:'zh-CN'}); // the words asserted are the Chinese ones
    page.on("pageerror",e=>console.error(e));
    page.on("console",m=>console.log(m.type(),m.text()));
    const bytes=readFileSync(join(temp,'sample.mp4')).toString('base64');
    await page.addInitScript(({bytes})=>{window.calls=[];window.__videoTestCall=async(name,params)=>{if(name === 'station.poster') throw Error('fixture without poster');window.calls.push(params);return {type:'application/octet-stream',bytes:params.name==='broken.webm'?'YmFk':bytes};};},{bytes});

    // Expose the chat's private file list for this fixture; its real previews and player are unchanged.
    await page.route('**/src/Chat.tsx', async route => { const response = await route.fetch(); const text = await response.text(); assert(text.includes('function Files(')); await route.fulfill({response, body: text + '\nexport { Files };'}); });
    await page.goto((process.env.WEB_URL || 'http://127.0.0.1:5187') + '/video-check.html');
    await page.waitForFunction(()=>document.querySelector('button video')?.readyState>=2);
    assert(await page.getByRole('button',{name:'播放 sample.mp4'}).isVisible());
    await page.getByRole('button',{name:'查看 broken.webm'}).waitFor();
    assert(await page.getByText('暂时无法预览').isVisible());
    assert.equal(await page.getByRole('button',{name:'查看 broken.webm'}).locator('video').count(), 0);
    assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='later.mp4')),false);
    assert.equal(await page.evaluate(()=>window.calls.find(c=>c.name==='sample.mp4').thumb),undefined);
    await page.getByRole('button',{name:'播放 sample.mp4'}).click();
    await page.waitForFunction(()=>document.querySelector('video[data-viewer-picture]')?.currentTime>0);
    assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='sample.mp4').length),1);
    await page.locator('video[data-viewer-picture]').evaluate(video => video.pause());
    await page.waitForFunction(() => !document.getAnimations().some(a => a.playState === 'running' && Number.isFinite(a.effect.getTiming().iterations)));
    for (const width of [1280, 390]) {
      await page.setViewportSize({width, height: 844});
      const slider = page.getByRole('slider');
      const rect = await slider.boundingBox();
      for (const share of [.25, .75, 0]) {
        await slider.click({position:{x:Math.max(1,rect.width * share),y:rect.height / 2}});
        await page.waitForFunction(share => {
          const el = document.querySelector('[role=slider]');
          return Math.abs(Number(el.getAttribute('aria-valuenow')) - Number(el.getAttribute('aria-valuemax')) * share) <= 40;
        }, share);
        const drawn = await slider.evaluate(el => {
          const box = el.getBoundingClientRect(), fill = el.firstElementChild.firstElementChild.getBoundingClientRect();
          const head = el.lastElementChild.lastElementChild.getBoundingClientRect();
          return {width: box.width, fill: fill.width, head: head.x + head.width / 2 - box.x,
            share: Number(el.getAttribute('aria-valuenow')) / Number(el.getAttribute('aria-valuemax'))};
        });
        assert.ok(Math.abs(drawn.fill - drawn.width * drawn.share) < 1, 'played fill matches the shown time');
        assert.ok(Math.abs(drawn.head - drawn.fill) < 1, 'head stays at the end of the played fill');
      }
    }
    await page.keyboard.press('Escape');
    await page.getByRole('dialog').waitFor({state:'detached'});
    await page.setViewportSize({width:390,height:844});
    assert(await page.getByRole('button',{name:'播放 sample.mp4'}).isVisible());
    if (process.env.VIDEO_SCREENSHOT) {
      await page.addStyleTag({content:'body { padding: 24px; }'});
      await page.screenshot({path:process.env.VIDEO_SCREENSHOT.replace(/(\.[^.]+)$/, '-' + engine + '$1'), clip:{x:0,y:0,width:390,height:390}});
    }
    await page.getByRole('button',{name:'播放 later.mp4'}).scrollIntoViewIfNeeded();
    await page.waitForFunction(()=>window.calls.some(c=>c.name==='later.mp4'));
    console.log(`PASS ${engine}: decoded still, broken-video fallback, lazy loading, modal playback, seek positions, cache reuse, desktop and phone widths`);
    await browser.close(); browser = null;
  }
} finally {
  await browser?.close();
  if (madeFixture) rmSync(fixture, {force:true});
  if (madeHtml) rmSync(html, {force:true});
  rmSync(temp, {recursive:true, force:true});
}
