// The phone's back from a preview (web/src/backPage.ts) leaves the page even after the service's page moved itself:
// a frame at another origin pushes entries of its own, and the browser's back would step those first.
// PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node test/browser/preview-back.mjs
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { build } = createRequire(require.resolve('vite'))('esbuild');
const playwright = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const bundle = await build({ entryPoints: [new URL('../../web/src/backPage.ts', import.meta.url).pathname], bundle: true, write: false, format: 'iife', globalName: 'backs' });
const origin = (server) => `http://127.0.0.1:${server.address().port}`;
const listen = (handler) => new Promise((resolve) => { const server = createServer(handler); server.listen(0, '127.0.0.1', () => resolve(server)); });
// The service, at an origin of its own (as the preview host is): its links move it by hash, its routes by pushState.
const service = await listen((_, res) => {
  res.setHeader('content-type', 'text/html');
  res.end(`<a id="hash" href="#dashboard">dashboard</a><script>window.route = (p) => history.pushState({}, '', p);</script>`);
});
const app = await listen((req, res) => {
  if (req.url === '/backPage.js') { res.setHeader('content-type', 'text/javascript'); res.end(bundle.outputFiles[0].text); return; }
  res.setHeader('content-type', 'text/html');
  res.end(`<script src="/backPage.js"></script><script>
    window.pops = 0;
    addEventListener('popstate', () => { pops++; if (location.pathname !== '/preview') document.querySelector('iframe')?.remove(); });
    // The chat, then its preview pushed over it (as the router does).
    window.openPreview = () => new Promise((resolve) => {
      history.pushState({ idx: 1 }, '', '/preview');
      const frame = document.createElement('iframe');
      frame.src = '${origin(service)}/app';
      frame.onload = resolve;
      document.body.append(frame);
    });
  </script>`);
});

const engines = (process.env.ENGINES || 'chromium,webkit').split(',');
for (const name of engines) {
  const browser = await playwright[name].launch({ headless: true });
  try {
    const run = async (back) => {
      const page = await browser.newPage();
      await page.goto(origin(app) + '/chat');
      await page.evaluate(() => openPreview());
      const frame = page.frames().find((f) => f.url().startsWith(origin(service)));
      // The service moves itself: a link by hash, then two routes of its own.
      await frame.click('#hash');
      await frame.evaluate(() => { route('/app/reports'); route('/app/live'); });
      await frame.waitForFunction(() => location.pathname === '/app/live');
      const length = await page.evaluate(() => history.length);
      await page.evaluate(back);
      await page.waitForTimeout(500);
      const at = await page.evaluate(() => ({ path: location.pathname, pops }));
      await page.close();
      return { ...at, length };
    };
    const plain = await run(() => history.back());
    console.log(`${name}: history.back() after the frame moved: at ${plain.path} (history ${plain.length} long)`);
    const ours = await run(() => backs.backPage(() => history.back()));
    console.log(`${name}: backPage() after the frame moved: at ${ours.path}`);
    assert.equal(ours.path, '/chat', `${name}: backPage left the preview`);
    assert.equal(ours.pops, 1, `${name}: one move back, seen by the page`);
  } finally {
    await browser.close();
  }
}
console.log('ok');
process.exit(0);
