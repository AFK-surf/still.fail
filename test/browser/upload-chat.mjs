// Real core -> CoreClient -> virtualized ChatRows, with the station's upload held until released.
import assert from 'node:assert/strict';
import { writeFile, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { createServer } from 'vite';
import { base, started, threadView } from '../../client/core-ts/test/station-fixture.ts';
const { Deferred, Effect } = createRequire(new URL('../../client/core-ts/package.json', import.meta.url))('effect');
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/upload-chat-check.tsx', import.meta.url);
const html = new URL('../../web/upload-chat-check.html', import.meta.url);
const answers = { ...base(), 'GET /threads': [threadView(7, 0)], 'GET /threads/7/entries?limit=50': { last: 0, entries: [] } };
const t = await started(answers);
const ui = t.core.connect();
const gate = Deferred.makeUnsafe();
const posted = [];
t.core.inner.stations.requests.uploadPart = () => Deferred.await(gate);
t.core.inner.stations.post = (_station, thread, message) => Effect.sync(() => { posted.push({ thread, ...message }); return posted.length; });
let server, browser, work = Promise.resolve();
const bridge = { name: 'upload-test-core', configureServer(vite) {
  vite.middlewares.use('/__upload_test', (req, res) => {
    work = work.then(async () => {
      const chunks = []; for await (const chunk of req) chunks.push(chunk);
      const message = JSON.parse(Buffer.concat(chunks).toString() || 'null');
      if (message?.call === 'composer.add') for (const file of message.params.files) file.blob = new Blob([Uint8Array.from(file.bytes)], { type: file.type });
      if (message) t.core.receiveRaw(ui, message);
      await t.host.settle(); await t.host.time.pass(60); await t.host.settle();
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify(t.host.takeEmitted().filter(([id]) => id === ui).map(([, message]) => message)));
    }).catch(error => { res.statusCode = 500; res.end(String(error.stack)); });
  });
} };
try {
  await writeFile(fixture, `import React, { useRef } from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router';
import { Tooltip } from 'radix-ui';
import './src/styles/index.ts';
import { setCore, useTopic } from './src/core/react.ts';
import { followMotion } from '@stillfail/ui/motion.ts';
// The emulated system's reduced motion on the root, as the app's pages put it.
followMotion();
import { CoreClient } from './src/core/client.ts';
import { useDraft } from './src/draft.ts';
import { ComposerView, ChatRows, useMessageList } from './src/Chat.tsx';
import * as css from './src/Chat.css.ts';
import { ToastProvider } from '@stillfail/ui/toast.tsx';
import { StationContext } from './src/station.tsx';
const client = new CoreClient(onMessage => {
 let closed=false, queue=Promise.resolve();
 function post(message:any) {
  queue=queue.then(async()=>{
   if(message?.call==='composer.add') message={...message,params:{...message.params,files:await Promise.all(message.params.files.map(async(f:any)=>({...f,blob:undefined,type:f.blob.type,bytes:Array.from(new Uint8Array(await f.blob.arrayBuffer()))})))}};
   const response=await fetch('/__upload_test',{method:'POST',body:JSON.stringify(message)});
   for(const value of await response.json()) onMessage(value);
  });
 }
 function poll(){if(closed)return;post(null);queue.finally(()=>setTimeout(poll,20));}
 setTimeout(poll,0);
 return {post,close(){closed=true;}};
});
setCore(client);
function Messages({chat}:any){
 const list=useRef<HTMLDivElement>(null);
 const rows=useMessageList(list,chat,'upload-check',new Map(),28);
 return <div data-testid="messages" ref={list} className={css.chatMessages} style={{height:280,overflow:'auto',position:'relative'}}><ChatRows chat={chat} rows={rows} to={7}/></div>;
}
function Page(){
 const draft=useDraft({key:'ws/st:k',station:'ws/st'});
 const chat=useTopic<any>({topic:'chat',station:'ws/st',thread:7}).value;
 return <main style={{maxWidth:720,margin:'50px auto',padding:24}}><h2>still.fail</h2>{chat&&<Messages chat={chat}/>}<ComposerView draft={draft} thread={7} sessionKey={null} draftKey="ws/st:k" /></main>;
}
createRoot(document.getElementById('root')!).render(<MemoryRouter><ToastProvider><Tooltip.Provider><StationContext value={{id:'st',name:'Test',address:'ws/st',base:'',settings:'',online:true}}><Page/></StationContext></Tooltip.Provider></ToastProvider></MemoryRouter>);
`, { flag: 'wx' });
  await writeFile(html, '<meta charset="utf-8"><div id="root"></div><script type="module" src="/upload-chat-check.tsx"></script>', { flag: 'wx' });
  server = await createServer({ configFile: 'web/vite.config.ts', mode: 'cloud', plugins: [bridge], server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
  const page = await browser.newPage({ viewport: { width: 1100, height: 700 }, reducedMotion: 'reduce' });
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await page.goto(server.resolvedUrls.local[0]+'upload-chat-check.html');
  await page.getByTestId('messages').waitFor();
  await page.locator('input[type=file]').setInputFiles({name:'slow-upload.txt',mimeType:'text/plain',buffer:Buffer.from('abc')});
  await page.locator('textarea:not([aria-hidden])').fill('请看这个附件');
  await page.waitForFunction(()=>!document.querySelector('button[type=submit]')?.disabled);
  await page.locator('button[type=submit]').click();
  const bubble=page.getByTestId('messages').locator('[data-role=person]');
  await bubble.getByText('请看这个附件',{exact:true}).waitFor();
  await bubble.getByText('slow-upload.txt',{exact:true}).waitFor();
  assert.equal(await page.locator('textarea:not([aria-hidden])').inputValue(),'');
  assert.match(await bubble.innerText(),/Uploading|正在上传/);
  assert.equal(posted.length,0,'message is already in the chat while provider has received nothing');
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  if(process.env.SCREENSHOT_DIR) await page.screenshot({path:process.env.SCREENSHOT_DIR+'/upload-chat-queued.png'});
  await page.locator('textarea:not([aria-hidden])').fill('继续写下一条');
  assert.equal(await page.locator('button[type=submit]').isEnabled(),true);
  Deferred.doneUnsafe(gate,Effect.succeed({have:3,file:{name:'slow-upload.txt',path:'/u/slow-upload.txt',size:3}}));
  await t.host.settle();
  await page.waitForFunction(()=>!document.querySelector('[data-testid=messages]')?.textContent?.includes('Uploading'));
  assert.equal(posted.length,1);
  assert.equal(posted[0].text,'请看这个附件');
  assert.equal(posted[0].attachments[0].path,'/u/slow-upload.txt');
  assert.deepEqual(errors,[]);
  console.log('PASS: real core publishes the message and uploading attachment into the real chat list before station delivery');
} finally {
  await browser?.close(); await server?.close(); await work; t.core.close();
  await rm(fixture,{force:true}); await rm(html,{force:true});
}
