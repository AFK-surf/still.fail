// The real useDraft: a new chat's one draft, its station picked anew: the image stays as it was picked, nothing sent up
// again; taken to send, the core is told the station it goes to (where a new chat's files go up: composer.ts).
import { writeFile, rm } from 'node:fs/promises';
import { createServer } from 'vite';
import assert from 'node:assert/strict';
import react from '@vitejs/plugin-react';
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin';
import { uiAlias } from '../../web/ui/alias.ts';
const { chromium, webkit } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const engine = process.env.BROWSER === 'webkit' ? webkit : chromium;
const fixture = new URL('../../web/composer-station-check.tsx', import.meta.url);
const html = new URL('../../web/composer-station-check.html', import.meta.url);
let server, browser;
try {
  await writeFile(fixture, `import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { useDraft } from './src/draft.ts';
import { pickAttachment } from './src/pickAttachment.ts';
import { setCore } from './src/core/react.ts';
import { StationContext } from './src/station.tsx';
import { ToastProvider } from '@stillfail/ui/toast.tsx';
const states = new Map<string, any>();
const listeners = new Map<string, Set<(value: any) => void>>();
const uploads: any[] = [];
const sent: any[] = [];
const takes: any[] = [];
Object.assign(window, { uploads, sent, takes, finish(index: number) {
  const upload = uploads[index];
  for (const [key, value] of states) {
    const files = value.files.map((f: any) => f.id === upload.id ? {...f, done:{name:f.name, size:f.size, path:\`/\${upload.station}/\${f.id}.png\`}} : f);
    const next = {...value, files, version:value.version+1}; states.set(key,next);
    for (const cb of listeners.get(key) ?? []) cb(next);
  }
} });
const state = (key: string) => {
  if (!states.has(key)) states.set(key, { text: '', quotes: [], files: [], rev: 0, version: 0, ready: false, uploading: false, starting: false });
  return states.get(key);
};
setCore({
  focus: async () => {},
  subscribe(topic: any, cb: any) {
    if (topic.topic !== 'composer') return () => {};
    const list = listeners.get(topic.key) ?? new Set(); listeners.set(topic.key, list); list.add(cb);
    cb(state(topic.key)); return () => list.delete(cb);
  },
  async call(name: string, p: any) {
    if (name === 'chat.send') { sent.push(p); return {}; }
    if (!name.startsWith('composer.')) return {};
    const s = state(p.key);
    const next = { ...s, version: s.version + 1 };
    if (name === 'composer.add') {
      next.files = [...s.files, ...p.files.map((f: any) => ({ id: f.id, name: f.name, size: f.size }))];
      for (const f of p.files) uploads.push({station:p.station, blob:f.blob, id:f.id});
    }
    if (name === 'composer.remove') next.files = s.files.filter((f: any) => f.id !== p.id);
    if (name === 'composer.text') next.text = p.text;
    if (name === 'composer.take') { takes.push(p.station); next.text = ''; next.files = []; next.quotes = []; next.rev++; }
    if (name === 'composer.starting') next.starting = p.starting;
    if (name === 'composer.error') next.error = p.error;
    states.set(p.key, next);
    for (const cb of listeners.get(p.key) ?? []) cb(next);
    return { version: next.version };
  }
} as any);
function Draft({ station }: { station: string }) {
  const draft = useDraft({ key: 'new:ws', station: \`ws/\${station}\` });
  Object.assign(window, { draft });
  return <div><button onClick={() => pickAttachment('image/*', false, draft.add)}>Pick photo</button><input type='file' onChange={e => draft.add(e.target.files!)} />{draft.files.map(f => <img key={f.id} src={f.preview} alt={f.name} />)}</div>;
}
function Page() {
  const [station, change] = useState('a'); Object.assign(window, { change });
  return <ToastProvider><StationContext value={{ address: 'ws/' + station } as any}><Draft station={station} /></StationContext></ToastProvider>;
}
createRoot(document.getElementById('root')!).render(<Page />);`, { flag: 'wx' });
  await writeFile(html, '<div id="root"></div><script type="module" src="/composer-station-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: false, root: 'web', plugins: [react(), vanillaExtractPlugin()], resolve: {alias:[uiAlias]}, define:{__POSTHOG__:'null',__BUILD__:'null'}, server: { port: 0, host: '127.0.0.1' } });
  await server.listen();
  browser = await engine.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage();
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.goto(server.resolvedUrls.local[0] + 'composer-station-check.html');
  async function paste(color) {
    await page.evaluate(async color => {
      const canvas = document.createElement('canvas'); canvas.width = canvas.height = 20;
      const context = canvas.getContext('2d'); context.fillStyle = color; context.fillRect(0,0,20,20);
      const blob = await new Promise(resolve => canvas.toBlob(resolve));
      window.draft.add([new File([blob], 'image.png', {type:'image/png'})]);
    }, color);
    await page.waitForFunction(() => document.querySelector('img')?.complete);
    return page.locator('img').getAttribute('src');
  }
  await page.waitForFunction(() => window.draft);
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', {name:'Pick photo'}).click();
  await (await chooser).setFiles({name:'first.png', mimeType:'image/png', buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=', 'base64')});
  await page.waitForFunction(() => window.draft.files[0]?.name === 'first.png');
  assert.equal(await page.locator('img').count(), 1, 'first native picker result must appear in the draft');
  await page.waitForFunction(() => { const image = document.querySelector('img'); return image?.complete && image.naturalWidth > 0; });
  assert.equal(await page.locator('input[hidden]').count(), 0, 'finished picker is removed');
  await page.evaluate(() => window.draft.remove(window.draft.files[0].id));
  await page.waitForFunction(() => window.draft.files.length === 0);
  await page.evaluate(() => window.uploads.length = 0);
  await paste('red');
  await page.evaluate(() => window.draft.setText('Keep this image'));
  for (let i = 0; i < 20; i++) {
    await page.evaluate(w => window.change(w), i % 2 === 0 ? 'b' : 'a');
    await page.waitForFunction(() => document.querySelector('img')?.complete);
    assert.equal(await page.locator('img').count(), 1);
    assert.deepEqual(await page.evaluate(() => window.draft.files.map(f => f.name)), ['image.png']);
    assert.equal(await page.evaluate(() => window.draft.text), 'Keep this image');
  }
  assert.equal(await page.evaluate(() => window.uploads.length), 1, 'not added again as the station changes');
  await page.evaluate(() => window.finish(0));
  await page.waitForFunction(() => window.draft.files[0]?.done);
  await page.evaluate(() => window.draft.send(async () => 7));
  await page.waitForFunction(() => window.sent.length === 1);
  const message = await page.evaluate(() => window.sent[0]);
  assert.equal(message.station, 'ws/a');
  assert.equal(message.text, 'Keep this image');
  assert.deepEqual(await page.evaluate(() => window.takes), ['ws/a'], 'taken to the station it goes to');
  assert.deepEqual(errors, []);
  console.log('PASS: first picker selection appears in the draft; image retained across 20 station switches, taken to the station it goes to');
} finally { await browser?.close(); await server?.close(); await rm(fixture, {force:true}); await rm(html, {force:true}); }
