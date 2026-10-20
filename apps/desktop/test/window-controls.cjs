// Windows integration: start dev:web on 5198, build the addon, then run this with Electron.
// STILLFAIL_WINDOW_CONTROLS=<path to window-controls.node>; SHOTS=<directory> captures actual windows.
// Uses the production React component, preload, main-process adapter, and native addon; no user data or mouse moves.
const { app, BrowserWindow, ipcMain, desktopCapturer } = require('electron');
const fs = require('node:fs');
const { join, resolve } = require('node:path');
const { tmpdir } = require('node:os');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const assert = require('node:assert/strict');
const { buildSync } = require('../node_modules/esbuild');
const root = resolve(__dirname, '../../..');
const scratch = fs.mkdtempSync(join(tmpdir(), 'stillfail-controls-'));
app.setPath('userData', join(scratch, 'profile'));
app.on('window-all-closed', () => {});
buildSync({ entryPoints: [join(root, 'apps/desktop/src/window-controls.ts'), join(root, 'apps/desktop/src/preload.ts')], bundle: true, platform: 'node', format: 'cjs', external: ['electron'], outdir: scratch });
const { attachWindowControls } = require(join(scratch, 'window-controls.js'));
const native = require(process.env.STILLFAIL_WINDOW_CONTROLS || join(root, 'apps/desktop/build/window-controls.node'));
const fixture = join(root, 'web/src/window-controls-check.tsx');
const html = join(root, 'web/window-controls-check.html');
let win, controls, madeFixture = false, madeHtml = false;
for (const [key, value] of Object.entries({ frame: 'custom', version: '0.1.0', beta: true, scheme: 'stillfail-beta', 'cloud-origin': 'https://app.still.fail' })) {
  ipcMain.on('app:' + key, (event) => { event.returnValue = value; });
}
ipcMain.on('window:action', (_event, action) => controls.action(action));
ipcMain.on('window:bounds', (_event, rect) => controls.bounds(rect));
ipcMain.handle('window:state', () => controls.state());
const delay = ms => new Promise(r => setTimeout(r, ms));
async function until(test) { for (let n = 0; n < 100; n++) { if (await test()) return; await delay(50); } throw Error('timed out'); }
const js = code => win.webContents.executeJavaScript(code);
async function inspect(action = 'inspect') {
  const { stdout } = await promisify(execFile)('powershell.exe', ['-NoProfile', '-File', join(__dirname, 'window-controls.ps1'), '-ParentWindow', win.getNativeWindowHandle().readBigUInt64LE().toString(), '-Action', action], { windowsHide: true });
  return JSON.parse(stdout.trim());
}
async function geometry() {
  const expected = await js(`(() => { const r=document.querySelector('[data-hover]').getBoundingClientRect(), s=devicePixelRatio; return {x:Math.round(r.x*s),y:Math.round(r.y*s),width:Math.round(r.right*s)-Math.round(r.x*s),height:Math.round(r.bottom*s)-Math.round(r.y*s)}; })()`);
  const { hit, visible, ...actual } = await inspect();
  assert.equal(hit, 9); assert.equal(visible, true, JSON.stringify({actual,expected,state:controls.state(),bounds:win.getBounds(),root:await js('document.documentElement.outerHTML.slice(0,400)')})); assert.deepEqual(actual, expected);
}
async function shot(name) {
  if (!process.env.SHOTS) return;
  fs.mkdirSync(process.env.SHOTS, { recursive: true });
  const sources = await desktopCapturer.getSources({ types: ['window'], thumbnailSize: { width: 2560, height: 1000 } });
  const source = sources.find(s => s.id === win.getMediaSourceId());
  assert(source && !source.thumbnail.isEmpty());
  const { width, height } = source.thumbnail.getSize();
  fs.writeFileSync(join(process.env.SHOTS, name + '.png'), source.thumbnail.crop({ x: 0, y: 0, width, height: Math.round(height * .35) }).toPNG());
}
async function run() {
  await app.whenReady();
  assert.throws(() => native.setBounds(Buffer.alloc(8), 0, 0, 32, 32));
  assert.throws(() => native.setBounds(Buffer.alloc(1), 0, 0, 32, 32));
  fs.writeFileSync(fixture, `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Dialog } from 'radix-ui';
import '@fontsource-variable/inter';
import './styles/index.ts';
import { WindowControls } from './WindowControls.tsx';
import { pageBar } from './styles/sidebar.css.ts';
import { iconBtn } from './styles/pages.css.ts';
import { Web, Info, PanelOpen } from './icons.tsx';
import * as modal from './Switcher.css.ts';
document.documentElement.dataset.desktop='custom';
document.documentElement.dataset.theme='light';
function App() {
  const [open,setOpen]=useState(false); Object.assign(window,{setOpen});
  return <><header className={pageBar}><strong>Windows window controls</strong><span/><div style={{display:'flex',gap:2,justifySelf:'end'}}>{[Web,Info,PanelOpen].map((Icon,i)=><button key={i} className={iconBtn}><Icon size={16} strokeWidth={1.7}/></button>)}</div></header><main style={{padding:48}}>Window controls integration test</main><WindowControls/><Dialog.Root open={open} onOpenChange={setOpen}><Dialog.Portal><Dialog.Overlay className={modal.overlay}/><Dialog.Content className={modal.switcher} aria-describedby={undefined}><Dialog.Title>Test dialog</Dialog.Title></Dialog.Content></Dialog.Portal></Dialog.Root></>;
}
createRoot(document.getElementById('root')).render(<App/>);
`, { flag: 'wx' }); madeFixture = true;
  fs.writeFileSync(html, '<div id="root"></div><script type="module" src="/src/window-controls-check.tsx"></script>', { flag: 'wx' }); madeHtml = true;
  win = new BrowserWindow({ width: 1280, height: 500, show: false, titleBarStyle: 'hidden', webPreferences: { preload: join(scratch, 'preload.js'), sandbox: true, contextIsolation: true } });
  controls = attachWindowControls(win, native);
  win.on('enter-full-screen', () => win.webContents.send('window:fullscreen', true));
  win.on('leave-full-screen', () => win.webContents.send('window:fullscreen', false));
  await win.loadURL('http://127.0.0.1:5198/window-controls-check.html');
  win.showInactive();
  await until(() => js(`!!document.querySelector('[data-hover]')`));
  await geometry();
  assert(await js(`Array.from(document.querySelectorAll('button')).every(b=>{const r=b.getBoundingClientRect();return r.width===32 && r.height===32 && r.y+r.height/2===22})`));
  await shot('custom-light');
  await js(`window.testStates=[]; void window.stillfailDesktop.windowControls.watch(s=>window.testStates.push(s))`);
  await inspect('hover'); assert(await js('window.testStates.some(s=>s.hover)'));
  await inspect('leave'); await until(() => !controls.state().hover);
  await inspect('cancel'); assert(!win.isMaximized());
  await inspect('click'); await until(() => win.isMaximized()); await geometry();
  await until(() => js(`document.querySelector('[data-hover]').getAttribute('aria-label') === 'Restore' || document.querySelector('[data-hover]').getAttribute('aria-label') === '还原'`));
  await inspect('click'); await until(() => !win.isMaximized()); await geometry();
  for (const zoom of [0.8, 1.25, 1.5, 1]) { win.webContents.setZoomFactor(zoom); await delay(200); await geometry(); }
  win.setSize(980, 500); await delay(200); await geometry();
  win.setSize(1280, 500); await delay(200); await geometry();
  await js(`document.documentElement.dataset.theme='dark'`); await delay(200); await shot('custom-dark');
  await js('window.setOpen(true)'); await delay(250); await geometry(); await shot('custom-modal');
  await js('window.setOpen(false)');
  win.setFullScreen(true); await until(() => win.isFullScreen()); await delay(250); assert.equal((await inspect()).visible, false);
  win.setFullScreen(false); await until(() => !win.isFullScreen()); await delay(250); await geometry();
  await win.webContents.reload(); await until(() => js(`!!document.querySelector('[data-hover]')`)); await delay(200); await geometry();
  // Keyboard/assistive activation follows the DOM path too.
  await js(`document.querySelector('[data-hover]').click()`); await until(() => win.isMaximized());
  await js(`document.querySelector('[data-hover]').click()`); await until(() => !win.isMaximized());
  controls.action('minimize'); assert(win.isMinimized()); win.restore();
  controls.action('close'); await until(() => win.isDestroyed());
  console.log('PASS: native HTMAXBUTTON, matching 32x32 geometry, hover/leave, click/drag-off, maximize/restore, zoom 80/125/150%, resize, theme, modal, fullscreen, reload, DOM activation, minimize/close, invalid HWND');
}
const watchdog = setTimeout(() => finish(1, Error('test exceeded 90s')), 90000);
function finish(code, error) { clearTimeout(watchdog); if (error) console.error(error); if (madeFixture) fs.rmSync(fixture, { force: true }); if (madeHtml) fs.rmSync(html, { force: true }); app.exit(code); }
run().then(() => finish(0), error => finish(1, error));
