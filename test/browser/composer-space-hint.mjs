// Run against this worktree's `pnpm dev:web --host 127.0.0.1 --port 5187`.
// Exercises the real shortcut dispatcher and availability hook with a portalled Radix menu.
import assert from 'node:assert/strict';
import { writeFileSync, rmSync } from 'node:fs';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/src/space-hint-check.tsx', import.meta.url);
const html = new URL('../../web/space-hint-check.html', import.meta.url);
let browser;
try {
  writeFileSync(fixture, `import React from 'react';
import {createRoot} from 'react-dom/client';
import {DropdownMenu} from 'radix-ui';
import {usePageKeysAvailable, useShortcut} from './keymap.ts';
function Check() {
  const available = usePageKeysAvailable();
  useShortcut('composer.focus', () => document.querySelector('textarea')!.focus());
  return <><DropdownMenu.Root modal={false}><DropdownMenu.Trigger>workspace</DropdownMenu.Trigger>
  <DropdownMenu.Portal><DropdownMenu.Content><DropdownMenu.Item>切换 workspace</DropdownMenu.Item></DropdownMenu.Content></DropdownMenu.Portal>
  </DropdownMenu.Root><div id="blank" tabIndex={-1}>对话内容</div>
  <textarea placeholder={available ? '按空格输入' : '发消息'}/></>;
}
createRoot(document.getElementById('root')!).render(<Check/>);
`, {flag:'wx'});
  writeFileSync(html, '<div id="root"></div><script type="module" src="/src/space-hint-check.tsx"></script>', {flag:'wx'});
  browser = await chromium.launch({headless:true, ...(process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE} : {})});
  const page = await browser.newPage();
  const errors=[]; page.on('pageerror', e=>errors.push(e.message));
  await page.goto(`${process.env.TEST_URL || 'http://127.0.0.1:5187'}/space-hint-check.html`);
  const hint = async expected => page.waitForFunction(expected=>document.querySelector('textarea')?.placeholder===expected,expected);
  await page.locator('#blank').focus(); await hint('按空格输入');
  await page.keyboard.press('Space');
  assert(await page.locator('textarea').evaluate(el=>el===document.activeElement)); await hint('发消息');
  await page.getByRole('button',{name:'workspace'}).click();
  await page.getByRole('menu').waitFor(); await hint('发消息');
  await page.keyboard.press('Space');
  assert.equal(await page.locator('textarea').evaluate(el=>el===document.activeElement),false);
  await page.keyboard.press('Escape'); await page.locator('#blank').focus(); await hint('按空格输入');
  for (const role of ['menu','dialog','alertdialog','listbox']) {
    // No focus event: opening and removing a portal must still update the hint.
    await page.evaluate(role=>{const el=document.createElement('div');el.id='overlay';el.role=role;document.body.append(el)},role);
    await hint('发消息'); await page.keyboard.press('Space');
    assert.equal(await page.locator('textarea').evaluate(el=>el===document.activeElement),false);
    await page.locator('#overlay').evaluate(el=>el.remove()); await hint('按空格输入');
  }
  await page.evaluate(()=>{const el=document.createElement('div');el.id='overlay';document.body.append(el);el.role='dialog'});
  await hint('发消息');
  await page.locator('#overlay').evaluate(el=>el.removeAttribute('role')); await hint('按空格输入');
  await page.getByRole('button',{name:'workspace'}).focus(); await hint('发消息');
  await page.locator('#blank').focus(); await page.keyboard.press('Space'); await hint('发消息');
  assert(await page.locator('textarea').evaluate(el=>el===document.activeElement));
  assert.deepEqual(errors,[]);
  console.log('PASS: Space focuses composer; Radix menu hides hint and keeps keyboard input; all four overlay roles hide hint without focus changes; removing overlays or changing role restores hint; focused buttons hide hint; no browser errors.');
} finally {
  await browser?.close();
  rmSync(fixture,{force:true}); rmSync(html,{force:true});
}
