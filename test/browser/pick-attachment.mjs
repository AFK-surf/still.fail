// A native picker must keep its input alive while the page is idle (WebKit bug 201289).
// Use CDP rather than Playwright's FileChooser: its ElementHandle would itself retain the detached input.
import assert from 'node:assert/strict';
import { writeFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const html = new URL('../../web/pick-attachment-check.html', import.meta.url);
const photo = new URL('../../web/pick-attachment-check.png', import.meta.url);
let browser, server;
try {
  await writeFile(photo, Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=', 'base64'), {flag:'wx'});
  await writeFile(html, `<button>Pick</button><script type="module">
import { pickAttachment } from '/src/pickAttachment.ts';
window.received = [];
document.querySelector('button').onclick = () => {
  const create = document.createElement.bind(document);
  document.createElement = (...args) => {
    const input = create(...args);
    window.weak = new WeakRef(input);
    return input;
  };
  try {
    if (window.legacy) {
      const input = document.createElement('input'); input.type = 'file';
      input.onchange = () => { if (input.files?.length) window.received.push(input.files[0].name); };
      input.click();
    } else pickAttachment('image/*', false, files => window.received.push(files[0].name));
  } finally { document.createElement = create; }
};
window.ready = true;
</script>`, {flag:'wx'});
  server = await createServer({ configFile:false, root:'web', server:{port:0, host:'127.0.0.1'} });
  await server.listen();
  browser = await chromium.launch({headless:true, ...(process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE} : {})});
  const page = await browser.newPage();
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Page.enable');
  await cdp.send('Page.setInterceptFileChooserDialog', {enabled:true});
  await page.goto(server.resolvedUrls.local[0] + 'pick-attachment-check.html');
  await page.waitForFunction(() => window.ready);
  // First show that the original implementation loses the input and cannot deliver the selection.
  await page.evaluate(() => { window.legacy = true; });
  let chooser = new Promise(resolve => cdp.once('Page.fileChooserOpened', resolve));
  await page.getByRole('button').click();
  let { backendNodeId } = await chooser;
  await cdp.send('HeapProfiler.collectGarbage');
  assert.equal(await page.evaluate(() => !!window.weak.deref()), false);
  await assert.rejects(cdp.send('DOM.setFileInputFiles', {backendNodeId, files:[fileURLToPath(photo)]}), /No node found/);
  assert.deepEqual(await page.evaluate(() => window.received), []);
  // A fresh first selection and a repeated selection both survive GC and reach the callback exactly once.
  await page.evaluate(() => { window.legacy = false; });
  for (let i = 0; i < 2; i++) {
    chooser = new Promise(resolve => cdp.once('Page.fileChooserOpened', resolve));
    await page.getByRole('button').click();
    ({ backendNodeId } = await chooser);
    await cdp.send('HeapProfiler.collectGarbage');
    assert.equal(await page.evaluate(() => !!window.weak.deref()?.isConnected), true);
    await cdp.send('DOM.setFileInputFiles', {backendNodeId, files:[fileURLToPath(photo)]});
    assert.equal(await page.locator('input').count(), 0);
    assert.equal(await page.evaluate(() => window.received.length), i + 1);
  }
  console.log('PASS: original detached picker loses its selection after GC; attached picker delivers first and repeated selections');
} finally {
  await browser?.close(); await server?.close();
  await rm(html, {force:true}); await rm(photo, {force:true});
}
