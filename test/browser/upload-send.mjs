// Runs the real useDraft and ComposerView against a held upload. No hosted station.
import assert from 'node:assert/strict';
import { writeFile, rm } from 'node:fs/promises';
import { createServer } from 'vite';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/upload-send-check.tsx', import.meta.url);
const html = new URL('../../web/upload-send-check.html', import.meta.url);
let server, browser;
try {
  await writeFile(fixture, `import React from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router';
import { Tooltip } from 'radix-ui';
import './src/styles/index.ts';
import { setCore } from './src/core/react.ts';
import { useDraft } from './src/draft.ts';
import { ComposerView } from './src/Chat.tsx';
import { ToastProvider } from './src/toast.tsx';
import { StationContext } from './src/station.tsx';
import { setPageRoot } from './src/brand.tsx';
let value:any = {text:'',files:[],quotes:[],rev:0,version:0,ready:false,uploading:false,starting:false};
const listeners = new Set<any>();
const sent:any[] = [];
(window as any).sent = sent;
function emit() {value={...value,version:value.version+1};listeners.forEach(f=>f({...value}));}
setCore({
  subscribe(topic:any, next:any) {
    if(topic.topic==='composer'){listeners.add(next);next({...value});return ()=>listeners.delete(next);}
    next(topic.topic==='prefs'?{}:[]);return ()=>{};
  },
  async call(name:string,p:any){
    if(name==='composer.text') value={...value,text:p.text};
    if(name==='composer.add') value={...value,files:[...value.files,...p.files.map(({blob,...f}:any)=>f)]};
    if(name==='composer.take') value={...value,text:'',files:[],quotes:[],rev:value.rev+1};
    if(name==='composer.starting') value={...value,starting:p.starting};
    if(name.startsWith('composer.')){emit();return {version:value.version};}
    if(name==='chat.send'){sent.push(p);return new Promise(()=>{});}
    return {};
  }, focus:async()=>{},
} as any);
function Page(){
 const draft=useDraft({key:'ws/st:k',station:'ws/st'});
 return <main style={{maxWidth:720,margin:'80px auto',padding:24}}><h2>still.fail</h2><p>附件上传中的发送测试</p><ComposerView draft={draft} thread={7} sessionKey={null} draftKey="ws/st:k" /></main>;
}
setPageRoot(document.documentElement);
createRoot(document.getElementById('root')!).render(<MemoryRouter><ToastProvider><Tooltip.Provider><StationContext value={{id:'st',name:'Test',address:'ws/st',base:'',settings:'',online:true}}><Page/></StationContext></Tooltip.Provider></ToastProvider></MemoryRouter>);
`, { flag: 'wx' });
  await writeFile(html, '<meta charset="utf-8"><div id="root"></div><script type="module" src="/upload-send-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: 'web/vite.config.ts', mode: 'cloud', server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 1100, height: 650 }, reducedMotion: 'reduce' });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(server.resolvedUrls.local[0] + 'upload-send-check.html');
  const send = page.locator('button[type=submit]');
  await page.locator('input[type=file]').setInputFiles({ name: 'slow-upload.txt', mimeType: 'text/plain', buffer: Buffer.from('held upload') });
  await page.waitForFunction(() => !document.querySelector('button[type=submit]')?.disabled);
  assert.equal(await send.isEnabled(), true, 'attachment-only send is enabled during upload');
  await page.locator('textarea:not([aria-hidden])').fill('请看这个附件');
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  if (process.env.SCREENSHOT_DIR) await page.screenshot({ path: process.env.SCREENSHOT_DIR + '/upload-send-ready.png' });
  await send.click();
  await page.waitForFunction(() => window.sent.length === 1 && document.querySelector('textarea')?.value === '');
  const first = await page.evaluate(() => window.sent[0]);
  assert.equal(first.text, '请看这个附件');
  assert.equal(first.uploads.length, 1);
  assert.equal(first.uploads[0].name, 'slow-upload.txt');
  assert.deepEqual(first.attachments, []);
  assert.equal(await page.locator('textarea:not([aria-hidden])').inputValue(), '');
  assert.equal(await page.getByText('slow-upload.txt', { exact: true }).count(), 0);
  await page.locator('textarea:not([aria-hidden])').fill('继续写下一条');
  assert.equal(await send.isEnabled(), true);
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  if (process.env.SCREENSHOT_DIR) await page.screenshot({ path: process.env.SCREENSHOT_DIR + '/upload-send-next.png' });
  await page.locator('textarea:not([aria-hidden])').press('Enter');
  await page.waitForFunction(() => window.sent.length === 2);
  assert.equal((await page.evaluate(() => window.sent[1])).text, '继续写下一条');
  assert.deepEqual(errors, []);
  console.log('PASS: pending attachment sends by click, clears composer, and next message sends by Enter');
} finally {
  await browser?.close();
  await server?.close();
  await rm(fixture, { force: true });
  await rm(html, { force: true });
}
