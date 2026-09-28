// Run with `pnpm dev:web --host 127.0.0.1 --port 5187` in another terminal.
// Requires ffmpeg and Playwright (PLAYWRIGHT_MODULE may name an external installation).
// CHROMIUM_EXECUTABLE optionally selects an installed browser.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
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
  import {createRoot} from 'react-dom/client';
  import {Files, imageBox} from './Chat.tsx';
  import * as css from './Chat.css.ts';
  const look = {files: css.msgFiles, image: css.msgImage, wait: css.msgImageWait, box: imageBox, open: css.fileCardOpen, card: f => <span>{f.name}</span>};
  const file = name => ({name, path: '/test/'+name,size:1000});
  createRoot(document.getElementById('root')!).render(<><Files owner={()=>'test'} files={[file('sample.mp4'),file('broken.webm')]} look={look}/><div style={{height:2500}}/><Files owner={()=>'test'} files={[file('later.mp4')]} look={look}/></>);
  `, {flag: 'wx'});
  madeFixture = true;
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/video-check.tsx"></script>\n', {flag: 'wx'});
  madeHtml = true;
  execFileSync('ffmpeg', ['-v','error','-f','lavfi','-i','color=c=blue:s=320x180:d=2','-c:v','libx264','-pix_fmt','yuv420p',join(temp,'sample.mp4')]);
  browser = await chromium.launch({headless:true, ...(process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE} : {})});
  const page=await browser.newPage();
  page.on("pageerror",e=>console.error(e));
  page.on("console",m=>console.log(m.type(),m.text()));
  const bytes=readFileSync(join(temp,'sample.mp4')).toString('base64');
  await page.addInitScript(({bytes})=>{window.calls=[];window.__videoTestCall=async(name,params)=>{window.calls.push(params);return {type:'application/octet-stream',bytes:params.name==='broken.webm'?'YmFk':bytes};};},{bytes});
  await page.route('**/src/core/react.ts', async route=>{const response=await route.fetch();const text=await response.text();assert(text.includes('core().call(name, params)'));await route.fulfill({response,body:text.replace('core().call(name, params)','window.__videoTestCall(name, params)')});});
  await page.goto('http://127.0.0.1:5187/admin/video-check.html');
  await page.waitForFunction(()=>document.querySelector('button video')?.readyState>=2);
  assert(await page.getByRole('button',{name:'播放 sample.mp4'}).isVisible());
  await page.getByRole('button',{name:'查看 broken.webm'}).waitFor();
  assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='later.mp4')),false);
  assert.equal(await page.evaluate(()=>window.calls.find(c=>c.name==='sample.mp4').thumb),undefined);
  await page.getByRole('button',{name:'播放 sample.mp4'}).click();
  await page.waitForFunction(()=>document.querySelector('video[controls]')?.currentTime>0);
  assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='sample.mp4').length),1);
  await page.keyboard.press('Escape');
  await page.setViewportSize({width:390,height:844});
  assert(await page.getByRole('button',{name:'播放 sample.mp4'}).isVisible());
  await page.getByRole('button',{name:'播放 later.mp4'}).scrollIntoViewIfNeeded();
  await page.waitForFunction(()=>window.calls.some(c=>c.name==='later.mp4'));
  console.log('PASS: decoded still, broken-video fallback, lazy loading, original MIME handling, modal playback, cache reuse, narrow viewport');
} finally {
  await browser?.close();
  if (madeFixture) rmSync(fixture, {force:true});
  if (madeHtml) rmSync(html, {force:true});
  rmSync(temp, {recursive:true, force:true});
}
