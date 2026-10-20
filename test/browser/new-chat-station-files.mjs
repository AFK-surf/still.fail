// A new chat moved to another station leaves its files with the station they went up to: the real useDraft against a
// core keeping each draft's versions on its own (as client/core-ts/src/composer.ts does). No hosted station.
import assert from 'node:assert/strict';
import { writeFile, rm } from 'node:fs/promises';
import { createServer } from 'vite';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/new-chat-station-files-check.tsx', import.meta.url);
const html = new URL('../../web/new-chat-station-files-check.html', import.meta.url);
let server, browser;
try {
  await writeFile(fixture, `import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router';
import { Tooltip } from 'radix-ui';
import './src/styles/index.ts';
import { setCore } from './src/core/react.ts';
import { useDraft } from './src/draft.ts';
import { ToastProvider } from '@stillfail/ui/toast.tsx';
import { StationContext } from './src/station.tsx';
import { setPageRoot } from './src/brand.tsx';
const blank = () => ({text:'',files:[] as any[],quotes:[],rev:0,version:0,ready:false,uploading:false,starting:false});
const drafts = new Map<string, any>();
const listeners = new Map<string, Set<any>>();
const sent:any[] = [];
(window as any).sent = sent;
const of = (key:string) => { if (!drafts.has(key)) drafts.set(key, blank()); return drafts.get(key); };
// Each draft counts its own versions, as the core's do.
const emit = (key:string) => { const v = of(key); drafts.set(key, {...v, version: v.version + 1}); listeners.get(key)?.forEach((f:any) => f({...drafts.get(key)})); };
const set = (key:string, patch:any) => { drafts.set(key, {...of(key), ...patch}); emit(key); return of(key).version; };
setCore({
  subscribe(topic:any, next:any) {
    if (topic.topic === 'composer') {
      const key = String(topic.key);
      if (!listeners.has(key)) listeners.set(key, new Set());
      listeners.get(key)!.add(next); next({...of(key)});
      return () => listeners.get(key)!.delete(next);
    }
    next(topic.topic === 'prefs' ? {} : []); return () => {};
  },
  async call(name:string, p:any) {
    const key = String(p.key);
    if (name === 'composer.text') return { version: set(key, {text: p.text, rev: of(key).rev}) };
    // Up at once, kept by the station it went to.
    if (name === 'composer.add') return { version: set(key, {files: [...of(key).files, ...p.files.map(({blob, ...f}:any) => ({...f, done: {name: f.name, path: '/' + p.station + '/uploads/' + f.name, size: f.size}}))]}) };
    if (name === 'composer.move') {
      const a = of(key);
      set(p.to, {text: a.text, rev: of(p.to).rev + 1});
      set(key, {text: '', rev: a.rev + 1});
      return { version: of(p.to).version };
    }
    if (name === 'composer.remove') return { version: set(key, {files: of(key).files.filter((f:any) => f.id !== p.id)}) };
    if (name === 'composer.error') return { version: set(key, {error: p.error}) };
    if (name === 'composer.take') return { version: set(key, {text: '', files: [], quotes: [], rev: of(key).rev + 1}) };
    if (name.startsWith('composer.')) return { version: set(key, {}) };
    if (name === 'chat.send') { sent.push(p); return new Promise(() => {}); }
    return {};
  }, focus: async () => {},
} as any);
function Page() {
  const [station, setStation] = useState('ws/mini');
  // The draft's key going with its station, or kept (a station changed under a draft, however that came to be).
  const [kept, setKept] = useState<string | null>(null);
  const draft = useDraft({ key: kept ?? 'new:' + station, station });
  (window as any).draft = draft;
  (window as any).toStation = setStation;
  (window as any).keepKey = setKept;
  return <main><p data-files>{draft.files.map((f) => f.name + '@' + (f.done?.path ?? '')).join(',')}</p><p data-text>{draft.text}</p><p data-error>{draft.error ?? ''}</p></main>;
}
setPageRoot(document.documentElement);
createRoot(document.getElementById('root')!).render(<MemoryRouter><ToastProvider><Tooltip.Provider><StationContext value={{id:'mini',name:'mini',address:'ws/mini',base:'',settings:'',online:true}}><Page/></StationContext></Tooltip.Provider></ToastProvider></MemoryRouter>);
`, { flag: 'wx' });
  await writeFile(html, '<meta charset="utf-8"><div id="root"></div><script type="module" src="/new-chat-station-files-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: 'web/vite.config.ts', mode: 'cloud', server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(server.resolvedUrls.local[0] + 'new-chat-station-files-check.html');
  await page.waitForFunction(() => window.draft);
  const settle = () => page.evaluate(() => new Promise(resolve => setTimeout(resolve, 50)));
  // Pasted on mini, then written to there a while (its versions run ahead of the next station's draft).
  await page.evaluate(() => window.draft.add([new File(['png'], 'shot.png', { type: 'image/png' })]));
  await settle();
  for (const words of ['这', '这是', '这是什么', '这是什么东西']) { await page.evaluate((w) => window.draft.setText(w), words); await settle(); }
  assert.equal(await page.locator('[data-files]').textContent(), 'shot.png@/ws/mini/uploads/shot.png');
  // The chooser moved to pengx17: the words go with it, the file stays with mini.
  await page.evaluate(() => window.toStation('ws/pengx17'));
  await settle();
  assert.equal(await page.locator('[data-text]').textContent(), '这是什么东西', 'the words go on');
  assert.equal(await page.locator('[data-files]').textContent(), '', "mini's file does not show on pengx17");
  await page.evaluate(() => { window.draft.send(async () => 7); });
  await page.waitForFunction(() => window.sent.length === 1);
  const message = await page.evaluate(() => window.sent[0]);
  assert.equal(message.text, '这是什么东西');
  assert.deepEqual(message.attachments, [], "no file of mini's goes to pengx17");
  assert.deepEqual(message.uploads ?? [], []);
  // A file that went up to one station in a draft whose station changed under it: not sent from there, it goes up to
  // the station the message goes to, and the message waits to be sent again.
  await page.evaluate(() => window.keepKey('new:ws/pengx17'));
  await page.evaluate(() => window.draft.add([new File(['png'], 'again.png', { type: 'image/png' })]));
  await settle();
  await page.evaluate(() => window.draft.setText('再看这张'));
  await settle();
  await page.evaluate(() => window.toStation('ws/mini'));
  await settle();
  assert.equal(await page.evaluate(() => window.draft.send(async () => 7)), null, 'not sent from the station before');
  await settle();
  assert.equal(await page.evaluate(() => window.sent.length), 1);
  assert.equal(await page.locator('[data-files]').textContent(), 'again.png@/ws/mini/uploads/again.png', 'up again to the station it goes to');
  assert.match(await page.locator('[data-error]').textContent(), /again\.png/);
  await page.evaluate(() => { window.draft.send(async () => 7); });
  await page.waitForFunction(() => window.sent.length === 2);
  const again = await page.evaluate(() => window.sent[1]);
  assert.equal(again.text, '再看这张');
  assert.deepEqual(again.attachments.map((a) => a.path), ['/ws/mini/uploads/again.png']);
  assert.deepEqual(errors, []);
  console.log("PASS: a new chat moved to another station sends without the files left with the station before; a file of another station goes up again first");
} finally {
  await browser?.close();
  await server?.close();
  await rm(fixture, { force: true });
  await rm(html, { force: true });
}
