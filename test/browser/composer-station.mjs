// The real useDraft: station selection retains the current image and uploads its bytes to the selected station.
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
Object.assign(window, { uploads, sent, finish(index: number) {
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
Object.assign(window, { restoreFile() {
  const key = 'new:ws/a';
  const next = {...state(key), rev:state(key).rev+1, version:state(key).version+1, files:[{id:'restored', name:'restored.png', size:100, done:{name:'restored.png', path:'/a/restored.png', size:100}}]};
  states.set(key,next);
  for (const cb of listeners.get(key) ?? []) cb(next);
} });
state('new:ws/b').files = [{id:'old', name:'older-picture.png', size:100, done:{name:'older-picture.png', path:'/b/old.png', size:100}}];
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
    if (name === 'composer.carry' || name === 'composer.move') {
      const target = state(p.to);
      const carried = {...target, text:s.text, quotes:s.quotes, files:name === 'composer.carry' ? s.files : target.files, rev:target.rev+1, version:target.version+1};
      states.set(p.to, carried);
      for (const cb of listeners.get(p.to) ?? []) cb(carried);
      next.text = ''; next.quotes = []; next.files = name === 'composer.carry' ? [] : s.files;
      states.set(p.key,next);
      for (const cb of listeners.get(p.key) ?? []) cb(next);
      return {version:carried.version};
    }
    if (name === 'composer.text') next.text = p.text;
    if (name === 'composer.take') { next.text = ''; next.files = []; next.quotes = []; next.rev++; }
    if (name === 'composer.starting') next.starting = p.starting;
    if (name === 'composer.error') next.error = p.error;
    states.set(p.key, next);
    for (const cb of listeners.get(p.key) ?? []) cb(next);
    return { version: next.version };
  }
} as any);
function Draft({ workspace }: { workspace: string }) {
  const draft = useDraft({ key: \`new:ws/\${workspace}\`, station: \`ws/\${workspace}\` });
  Object.assign(window, { draft });
  return <div><button onClick={() => pickAttachment('image/*', false, draft.add)}>Pick photo</button><input type='file' onChange={e => draft.add(e.target.files!)} />{draft.files.map(f => <img key={f.id} src={f.preview} alt={f.name} />)}</div>;
}
function Page() {
  const [workspace, change] = useState('a'); Object.assign(window, { change });
  return <ToastProvider><StationContext value={{ address: 'ws/' + workspace } as any}><Draft workspace={workspace} /></StationContext></ToastProvider>;
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
  const original = await page.evaluate(async () => Array.from(new Uint8Array(await window.uploads[0].blob.arrayBuffer())));
  for (let i = 0; i < 20; i++) {
    // Cover both completed uploads and a selection made while the previous upload is still in flight.
    if (i % 2 === 0) await page.evaluate(() => window.finish(window.uploads.length-1));
    const station = i % 2 === 0 ? 'b' : 'a';
    await page.evaluate(w => window.change(w), station);
    await page.waitForFunction(count => window.uploads.length === count, i + 2);
    assert.equal(await page.locator('img').count(), 1);
    assert.deepEqual(await page.evaluate(() => window.draft.files.map(f => f.name)), ['image.png']);
    assert.equal(await page.evaluate(() => window.draft.text), 'Keep this image');
    await page.evaluate(index => window.finish(index), i);
    const uploaded = await page.evaluate(async () => {
      const f = window.uploads.at(-1);
      return {station:f.station, bytes:Array.from(new Uint8Array(await f.blob.arrayBuffer()))};
    });
    assert.equal(uploaded.station, `ws/${station}`);
    assert.deepEqual(uploaded.bytes, original);
  }
  await page.evaluate(() => window.finish(window.uploads.length-1));
  await page.waitForFunction(() => window.draft.files[0]?.done);
  await page.evaluate(() => window.draft.send(async () => 7));
  await page.waitForFunction(() => window.sent.length === 1);
  const message = await page.evaluate(() => window.sent[0]);
  assert.equal(message.station, 'ws/a');
  assert.equal(message.text, 'Keep this image');
  assert.equal(message.attachments.length, 1);
  assert.match(message.attachments[0].path, /^[/]ws[/]a[/]/);
  assert.equal(message.attachments[0].name, 'image.png');
  // A restored attachment has no local bytes: keep it visible and refuse to send an old station's path as a new upload.
  await page.evaluate(() => window.restoreFile());
  await page.waitForFunction(() => window.draft.files[0]?.name === 'restored.png');
  await page.evaluate(() => window.change('b'));
  await page.waitForFunction(() => window.draft.files[0]?.name === 'restored.png');
  assert.equal(await page.evaluate(() => window.draft.send(async () => 7)), null);
  assert.equal(await page.evaluate(() => window.sent.length), 1);
  assert.ok(await page.evaluate(() => window.draft.error));
  assert.deepEqual(errors, []);
  console.log('PASS: first picker selection appears in the draft; image retained and identical bytes uploaded across 20 station switches');
} finally { await browser?.close(); await server?.close(); await rm(fixture, {force:true}); await rm(html, {force:true}); }
