// Windows native-controls smoke test. Start dev:web on port 5198, then run:
// electron apps/desktop/test/window-colors.cjs
// SHOTS=<directory> also captures the actual Windows controls (capturePage excludes them).
// Uses a disposable profile, real Radix dialogs and the app's styles, with fixture content.
const { app, BrowserWindow, ipcMain, desktopCapturer } = require('electron');
const { writeFileSync, mkdirSync, rmSync } = require('node:fs');
const { join, resolve } = require('node:path');
const assert = require('node:assert/strict');
const { tmpdir } = require('node:os');
const { mkdtempSync } = require('node:fs');
const root = resolve(__dirname, '../../..');
const profile = mkdtempSync(join(tmpdir(), 'stillfail-window-colors-'));
app.setPath('userData', profile);
const fixture = join(root, 'web/src/window-colors-check.tsx');
const html = join(root, 'web/window-colors-check.html');
let win, madeFixture = false, madeHtml = false;
const colors = [];
ipcMain.on('test:colors', (_event, color, symbolColor) => {
  colors.push(color);
  win.setTitleBarOverlay({ color, symbolColor });
});
async function run() {
  await app.whenReady();
  writeFileSync(fixture, `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Dialog } from 'radix-ui';
import './styles/index.ts';
import * as css from './Switcher.css.ts';
import { pageBar } from './styles/sidebar.css.ts';
import { followWindowColors } from './titleBar${process.env.BASELINE ? '-before' : ''}.ts';
const { ipcRenderer } = window.require('electron');
window.stillfailDesktop = { frame: 'overlay', windowColors: (...args) => ipcRenderer.send('test:colors', ...args) };
document.documentElement.dataset.desktop = 'overlay';
document.documentElement.dataset.theme = 'light';
function Demo() {
  const [open, setOpen] = useState(false);
  const [nested, setNested] = useState(false);
  Object.assign(window, { setOpen, setNested });
  const modal = (isOpen, change, title) => <Dialog.Root open={isOpen} onOpenChange={change}><Dialog.Portal>
    <Dialog.Overlay className={css.overlay} />
    <Dialog.Content className={css.switcher} aria-describedby={undefined}>
      <Dialog.Title className={css.hidden}>{title}</Dialog.Title>
      <input className={css.search} placeholder="Search chats, messages and actions" />
      <div className={css.results}>{['Windows window controls', 'Daily project review', 'New chat', 'Settings'].map(t =>
        <div className={css.row} key={t}><span className={css.title}>{t}</span></div>)}</div>
    </Dialog.Content>
  </Dialog.Portal></Dialog.Root>;
  return <><div className={pageBar}>Windows window controls</div>
    <main style={{padding: '70px 100px'}}><h2>Native window controls</h2><p>Search overlays should shade the title bar consistently.</p>
    <button onClick={() => setOpen(true)}>Search chats</button></main>
    {modal(open, setOpen, 'Search chats')}{modal(nested, setNested, 'Second dialog')}</>;
}
createRoot(document.getElementById('root')!).render(<Demo />);
followWindowColors();
Object.assign(window, { ready: true });
`, { flag: 'wx' });
  madeFixture = true;
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/window-colors-check.tsx"></script>', { flag: 'wx' });
  madeHtml = true;
  win = new BrowserWindow({ width: 1000, height: 660, show: false,
    title: 'Window controls verification', titleBarStyle: 'hidden', frame: false,
    titleBarOverlay: { color: '#ffffff', symbolColor: '#3b3e43', height: 44 },
    webPreferences: { nodeIntegration: true, contextIsolation: false, backgroundThrottling: false } });
  win.webContents.on('console-message', (event) => console.log('renderer:', event.message));
  const url = new URL('/window-colors-check.html', process.env.WEB_URL || 'http://127.0.0.1:5198');
  assert(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname), 'test content must be local');
  await win.loadURL(url.href);
  win.showInactive();
  const evaluate = (script) => win.webContents.executeJavaScript(script);
  // Wait for rendering and real CSS animations, then for the colour bridge's final animation frame.
  const settled = () => evaluate(`(async () => {
    const frame = () => new Promise(r => requestAnimationFrame(r));
    await frame(); await frame();
    await Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => {})));
    await frame(); await frame();
  })()`);
  await settled();
  assert(await evaluate('!!window.ready && !!window.setOpen'));
  const shot = async (name) => {
    if (!process.env.SHOTS) return;
    mkdirSync(process.env.SHOTS, { recursive: true });
    const sources = await desktopCapturer.getSources({ types: ['window'], thumbnailSize: { width: 2000, height: 1320 } });
    const source = sources.find(s => s.id === win.getMediaSourceId());
    assert(source && !source.thumbnail.isEmpty(), 'native window capture');
    writeFileSync(join(process.env.SHOTS, `${name}.png`), source.thumbnail.toPNG());
  };
  const base = colors.at(-1);
  console.log('base:', base);
  const matchesPaint = async () => {
    const width = await evaluate('document.documentElement.clientWidth');
    const image = await win.webContents.capturePage({ x: width - 200, y: 22, width: 1, height: 1 });
    const [b, g, r] = image.toBitmap();
    const color = colors.at(-1);
    for (const [i, actual] of [r, g, b].entries()) {
      const expected = parseInt(color.slice(1 + i * 2, 3 + i * 2), 16);
      assert(Math.abs(actual - expected) <= 1, `native ${color} matches painted background ${[r, g, b]}`);
    }
  };
  await evaluate('window.setOpen(true)'); await settled();
  const shade = colors.at(-1);
  console.log('shade:', shade);
  assert.equal(await evaluate('document.body.style.pointerEvents'), 'none', 'modal still blocks the page');
  if (!process.env.BASELINE) assert.notEqual(shade, base, 'search shade reaches native controls');
  await shot(process.env.BASELINE ? 'before-light' : 'after-light');
  if (process.env.BASELINE) return;
  await matchesPaint();
  await evaluate('window.setNested(true)'); await settled();
  assert.notEqual(colors.at(-1), shade, 'stacked shades composite');
  await matchesPaint();
  await evaluate('window.setNested(false)'); await settled();
  assert.equal(colors.at(-1), shade, 'closing the second dialog preserves the first shade');
  await evaluate('window.setOpen(false)'); await settled();
  assert.equal(colors.at(-1), base, 'closing restores the page');
  await evaluate('document.documentElement.dataset.theme = "dark"'); await settled();
  const dark = colors.at(-1);
  assert.notEqual(dark, base, 'dark theme follows');
  await evaluate('window.setOpen(true)'); await settled();
  assert.notEqual(colors.at(-1), dark, 'dark shade follows');
  await matchesPaint();
  await shot('after-dark');
  await evaluate('document.documentElement.dataset.theme = "light"'); await settled();
  assert.equal(colors.at(-1), shade, 'theme switch inside modal retains shade');
  await evaluate('window.setOpen(false)'); await settled();
  assert.equal(colors.at(-1), base);
  console.log('PASS open / close / nested dialogs / light / dark / theme change with modal open; native colours:', colors);
}
run().then(() => finish(0), (error) => { console.error(error); finish(1); });
function finish(code) {
  win?.destroy();
  if (madeFixture) rmSync(fixture);
  if (madeHtml) rmSync(html);
  // Chromium may still hold files until exit; this disposable profile is never the user's app data.
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
  app.exit(code);
}
