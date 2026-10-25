// A retained chat's effects resume on return: opening a link and assigning a new chat's address happen once,
// while its draft and messages remain current. Runs locally in Chromium and WebKit, with the demo core.
import assert from 'node:assert/strict';
import {writeFile, rm} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createServer} from 'vite';
const pw = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/mobile-resume-check.tsx', import.meta.url);
const html = new URL('../../web/mobile-resume-check.html', import.meta.url);
let server, browser, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, `import React from 'react';
import {createRoot} from 'react-dom/client';
import {BrowserRouter,Routes,Route,useNavigate} from 'react-router';
import {Tooltip} from 'radix-ui';
import './src/styles/index.ts';
import {extendDemo,demoCore} from './src/demo/mount.tsx';
import {ACCOUNT,runs} from './src/demo/station.ts';
import {chatView,message,SAFARI_KEY} from './src/demo/fixtures.ts';
import {MobileWorkspace} from './src/mobile/index.tsx';
import {mEdge} from './src/mobile/app.css.ts';
import {setPageRoot} from './src/brand.tsx';
const pending=new URLSearchParams(location.search).has('pending');
const chat=demoCore.chats.find(c=>c.key===SAFARI_KEY)!;
extendDemo({topic:t=>t.topic==='job'?{id:'review',name:'预览测试',state:'exited',port:null,open:false}:
 t.topic==='chat'&&t.session==='new:review'?{...chatView(chat,runs()),key:'ember:c-review-ready'}:undefined});
history.replaceState(null,'','/w/demo/s/local/chats/'+(pending?'new%3Areview':encodeURIComponent(SAFARI_KEY)+'?service=review'));
window.receive=()=>{chat.messages.push(message(chat,'agent','隐藏期间收到的消息'));demoCore.publish();};
window.edge=mEdge;
function Navigation(){window.go=useNavigate();return null;}
const root=document.getElementById('app')!;setPageRoot(root);
createRoot(root).render(<Tooltip.Provider><BrowserRouter><Navigation/><Routes><Route path='/w/demo/*' element={<MobileWorkspace entry={{id:'demo',name:'Test',account:ACCOUNT}}/>}/></Routes></BrowserRouter></Tooltip.Provider>);
`, {flag:'wx'});
  madeFixture = true;
  await writeFile(html, '<meta name="viewport" content="width=device-width,initial-scale=1"><div id="app" style="position:fixed;inset:0"></div><script type="module" src="/mobile-resume-check.tsx"></script>', {flag:'wx'});
  madeHtml = true;
  server = await createServer({configFile:fileURLToPath(new URL('../../web/vite.demo.config.ts',import.meta.url)),root:fileURLToPath(new URL('../../web',import.meta.url)),server:{host:'127.0.0.1',port:0,hmr:false}});
  await server.listen();
  for (const engine of (process.env.ENGINES || 'chromium,webkit').split(',')) {
    browser = await pw[engine].launch();
    const page = await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true,locale:'zh-CN'});
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    const hidden = () => page.waitForFunction(() => [...document.querySelectorAll('[data-role=under] > *')].some(e => getComputedStyle(e).display === 'none'));
    const settled = () => page.waitForFunction(() => !document.querySelector('[data-role=in],[data-role=out]'));
    const chatPath = '/w/demo/s/local/chats/ember%3Ac-demo-safari';
    await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/mobile-resume-check.html`);
    await page.waitForFunction(() => location.pathname.endsWith('/services/review'));
    await hidden();
    await page.goBack();
    await page.waitForFunction(path => location.pathname === path && !document.querySelector('[data-role=in],[data-role=out]'), chatPath);
    const input = page.locator('[data-role=top] textarea:not([aria-hidden])');
    await input.fill('返回后继续写的草稿');
    await page.evaluate(() => window.go('/w/demo/settings'));
    await hidden();
    await page.evaluate(() => window.receive());
    await page.goBack();
    await page.waitForFunction(path => location.pathname === path && !document.querySelector('[data-role=in],[data-role=out]'), chatPath);
    assert.equal(await input.inputValue(), '返回后继续写的草稿', `${engine}: a covered chat keeps its draft`);
    await page.getByText('隐藏期间收到的消息', {exact:true}).waitFor();

    // A provisional chat already renamed by its station must not replace the covering page during a back preview.
    await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/mobile-resume-check.html?pending`);
    await page.waitForFunction(() => location.pathname.endsWith('/chats/ember%3Ac-review-ready'));
    await input.waitFor();
    await page.evaluate(() => window.go('/w/demo/settings'));
    await hidden();
    const edge = page.locator(await page.evaluate(() => '.' + window.edge));
    await edge.evaluate(el => { el.setPointerCapture = () => {}; });
    await edge.dispatchEvent('pointerdown', {pointerId:7,pointerType:'touch',clientX:2,clientY:350,buttons:1});
    await edge.dispatchEvent('pointermove', {pointerId:7,pointerType:'touch',clientX:65,clientY:350,buttons:1});
    await page.waitForFunction(() => document.querySelector('[data-role=peek]'));
    await page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
    assert.equal(new URL(page.url()).pathname, '/w/demo/settings', `${engine}: resuming the chat cannot replace its covering page`);
    await edge.dispatchEvent('pointercancel', {pointerId:7,pointerType:'touch',clientX:65,clientY:350});
    await settled();
    await page.goBack();
    await input.waitFor();
    await settled();
    assert.equal(new URL(page.url()).pathname, '/w/demo/s/local/chats/ember%3Ac-review-ready');
    assert.deepEqual(errors, []);
    console.log(`PASS ${engine}: service back stays in chat; draft and new messages survive hiding; assigned chat address is not replayed on a back preview`);
    await browser.close(); browser = null;
  }
} finally {
  await browser?.close(); await server?.close();
  if (madeFixture) await rm(fixture); if (madeHtml) await rm(html);
}
