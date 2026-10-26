// A new chat's one draft, its station picked anew: its words and its file stay as they are, and it is taken to the
// station it goes to (where the core sends a new chat's files up: composer.ts); the real useDraft against a core keeping
// each draft's versions on its own. No hosted station.
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
const blank = () => ({text:'',files:[] as any[],quotes:[],rev:0,version:0,ready:false,uploading:false,starting:false});
const drafts = new Map<string, any>();
const listeners = new Map<string, Set<any>>();
const sent:any[] = [];
const takes:any[] = [];
(window as any).sent = sent;
(window as any).takes = takes;
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
    if (name === 'composer.remove') return { version: set(key, {files: of(key).files.filter((f:any) => f.id !== p.id)}) };
    if (name === 'composer.error') return { version: set(key, {error: p.error}) };
    if (name === 'composer.take') { takes.push(p.station); return { version: set(key, {text: '', files: [], quotes: [], rev: of(key).rev + 1}) }; }
    if (name.startsWith('composer.')) return { version: set(key, {}) };
    if (name === 'chat.send') { sent.push(p); return new Promise(() => {}); }
    return {};
  }, focus: async () => {},
} as any);
function Page() {
  const [station, setStation] = useState('ws/mini');
  const draft = useDraft({ key: 'new:ws', station });
  (window as any).draft = draft;
  (window as any).toStation = setStation;
  return <main><p data-files>{draft.files.map((f) => f.name + '@' + (f.done?.path ?? '')).join(',')}</p><p data-text>{draft.text}</p><p data-error>{draft.error ?? ''}</p></main>;
}
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
  // Pasted on mini, then written to a while.
  await page.evaluate(() => window.draft.add([new File(['png'], 'shot.png', { type: 'image/png' })]));
  await settle();
  for (const words of ['这', '这是', '这是什么', '这是什么东西']) { await page.evaluate((w) => window.draft.setText(w), words); await settle(); }
  assert.equal(await page.locator('[data-files]').textContent(), 'shot.png@/ws/mini/uploads/shot.png');
  // The chooser moved to pengx17: the words and the file stay, nothing added again.
  await page.evaluate(() => window.toStation('ws/pengx17'));
  await settle();
  assert.equal(await page.locator('[data-text]').textContent(), '这是什么东西', 'the words stay');
  assert.equal(await page.locator('[data-files]').textContent(), 'shot.png@/ws/mini/uploads/shot.png', 'the file as it was');
  await page.evaluate(() => { window.draft.send(async () => 7); });
  await page.waitForFunction(() => window.sent.length === 1);
  const message = await page.evaluate(() => window.sent[0]);
  assert.equal(message.text, '这是什么东西');
  assert.deepEqual(await page.evaluate(() => window.takes), ['ws/pengx17'], 'taken to the station it goes to');
  assert.deepEqual(errors, []);
  console.log("PASS: a new chat's station picked anew keeps its words and its file, and it is taken to the station picked");
} finally {
  await browser?.close();
  await server?.close();
  await rm(fixture, { force: true });
  await rm(html, { force: true });
}
