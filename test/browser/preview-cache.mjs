// Real Chromium Service Worker -> frame -> bridge -> HTTP fixture, without station credentials or a deployment.
// PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node test/browser/preview-cache.mjs
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { previewFiles } from '../../cloud/src/preview.ts';
const require = createRequire(import.meta.url);
const { build } = createRequire(require.resolve('vite'))('esbuild');
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const bundle = await build({ entryPoints: [new URL('../../web/src/previewBridge.ts', import.meta.url).pathname], bundle: true, write: false, format: 'iife', globalName: 'preview' });
const files = previewFiles();
let version = 1;
const hits = [];
const origin = (server) => `http://127.0.0.1:${server.address().port}`;
const listen = (handler) => new Promise((resolve) => { const server = createServer(handler); server.listen(0, '127.0.0.1', () => resolve(server)); });
const fixture = await listen((req, res) => {
  hits.push({ path: req.url, conditional: req.headers['if-none-match'] });
  if (req.url === '/') { res.setHeader('content-type', 'text/html'); res.end('<!doctype html><html><head></head><body>fixture</body></html>'); return; }
  const tag = `"${version}"`;
  res.setHeader('content-type', 'text/javascript');
  res.setHeader('cache-control', req.url === '/dep.js' ? 'max-age=3600, immutable' : 'no-cache');
  res.setHeader('etag', tag);
  if (req.headers['if-none-match'] === tag) { res.writeHead(304); res.end(); }
  else res.end(`export default ${version}`);
});
const previewHost = await listen((req, res) => {
  const path = new URL(req.url, 'http://test').pathname.slice(1);
  const body = files[path.endsWith('/frame') ? path + '.html' : path];
  if (body === undefined) { res.writeHead(404); res.end(); return; }
  res.setHeader('content-type', path.endsWith('.js') ? 'text/javascript' : 'text/html');
  res.setHeader('service-worker-allowed', '/'); res.end(body);
});
const parent = await listen(async (req, res) => {
  if (req.url.startsWith('/rpc/')) {
    const upstream = await fetch(origin(fixture) + req.url.slice(4), { headers: req.headers['if-none-match'] ? { 'if-none-match': req.headers['if-none-match'] } : {} });
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ status: upstream.status, headers: [...upstream.headers], body: Buffer.from(await upstream.arrayBuffer()).toString('base64') })); return;
  }
  if (req.url === '/bridge.js') { res.setHeader('content-type', 'text/javascript'); res.end(bundle.outputFiles[0].text); return; }
  res.setHeader('content-type', 'text/html');
  res.end(`<script src="/bridge.js"></script><script>
    addEventListener('message', e => {
      if(e.data?.type !== 'ember-preview-ready') return;
      const c = new MessageChannel();
      window.stopBridge = preview.bridge(c.port1, { station:'fixture', service:1, streams:true, call: async (_, p, progress, signal) => {
        const r = await (await fetch('/rpc' + p.path, {headers:p.headers, signal})).json();
        progress({head:{status:r.status,headers:r.headers}});
        if(r.body) progress({chunk:r.body});
      }});
      e.source.postMessage({type:'ember-preview-port',streams:true}, e.origin, [c.port2]);
    });
  </script><iframe src="${origin(previewHost)}/_ember/frame?n=cache-test&path=%2F"></iframe>`);
});
let browser;
try {
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.goto(origin(parent));
  await page.waitForFunction(() => document.querySelector('iframe') && window.stopBridge);
  let frame;
  for (let i = 0; i < 100; i++) { frame = page.frames().find(f => f.url() === origin(previewHost) + '/'); if (frame) break; await page.waitForTimeout(50); }
  assert.ok(frame, 'the fixture page loaded through the actual Service Worker');
  await frame.waitForLoadState();
  const get = (path, cache = 'default') => frame.evaluate(async ({path, cache}) => { const r = await fetch(path, {cache}); return {status:r.status, body:await r.text()}; }, {path, cache});
  assert.deepEqual(await get('/dep.js'), {status:200,body:'export default 1'});
  assert.deepEqual(await get('/dep.js'), {status:200,body:'export default 1'});
  assert.equal(hits.filter(h=>h.path==='/dep.js').length,1, 'fresh resource skips the tunnel');
  await get('/src.js');
  assert.deepEqual(await get('/src.js'), {status:200,body:'export default 1'});
  assert.equal(hits.filter(h=>h.path==='/src.js').at(-1).conditional,'"1"');
  version = 2;
  assert.deepEqual(await get('/src.js'), {status:200,body:'export default 2'});
  assert.deepEqual(await get('/dep.js','reload'), {status:200,body:'export default 2'});
  assert.equal(hits.filter(h=>h.path==='/dep.js').length,2, 'reload bypass crosses the SW/frame boundary');
  console.log(JSON.stringify({ passed:true, upstreamRequests:hits }, null, 2));
} finally {
  await browser?.close();
  await Promise.all([parent,previewHost,fixture].map(s=>new Promise(r=>{s.closeAllConnections();s.close(r)})));
}
