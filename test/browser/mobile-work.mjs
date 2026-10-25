// The mobile app's retained pages and long home list: bounded DOM, positions kept on return,
// hidden effects stopped, and an unrelated operation cannot redraw every subscribed row.
import assert from 'node:assert/strict';
import { writeFile, rm, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
const pw = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fixture = new URL('../../web/mobile-work-check.tsx', import.meta.url);
const html = new URL('../../web/mobile-work-check.html', import.meta.url);
let server, browser, madeFixture = false, madeHtml = false;
try {
  await writeFile(fixture, `import React, {memo,useEffect} from 'react';
import {createRoot} from 'react-dom/client';
import {Tooltip} from 'radix-ui';
import {BrowserRouter,Routes,Route} from 'react-router';
import './src/styles/index.ts';
import {extendDemo,demoCore} from './src/demo/mount.tsx';
import {ACCOUNT} from './src/demo/station.ts';
import {MobileShell,useApp} from './src/mobile/app.tsx';
import {Home} from './src/mobile/Home.tsx';
import {setSidebarMode} from './src/station.tsx';
import {useDoing} from './src/doing.ts';
import {setPageRoot} from './src/brand.tsx';
import {restingLoop} from '@stillfail/ui/motion.ts';
let doing=[];
const lists=new Map();
extendDemo({call(name,params){if(name!=='chat.archive')return;window.archived=true;for(const list of lists.values())list.days=list.days.map(d=>({...d,items:d.items.filter(i=>i.session!==params.session)}));setTimeout(()=>demoCore.publish(),0);return null;},topic:t=>t.topic==='doing'?{doing}:undefined,then(t,v){
 if(t.topic!=='chats'||!v?.days?.[0]?.items?.length)return;
 const key=JSON.stringify(t);if(!lists.has(key)){const item=v.days[0].items[0];lists.set(key,{...v,days:[{...v.days[0],items:Array.from({length:1000},(_,i)=>({...item,id:'row-'+i,session:'row-'+i,title:'会话 '+i,archivable:i===0,watch:null}))}]});}return lists.get(key);
}});
window.probeRenders=0;window.activeHome=0;
const Probe=memo(({id})=>{const on=useDoing('chat.pin',{session:id});window.probeRenders++;return <span>{String(on)}</span>;});
function HomePage(){const app=useApp();window.app=app;useEffect(()=>{window.activeHome++;return()=>{window.activeHome--;};},[]);return <Home/>;}
const routes=location=><Routes location={location}><Route path='/w/:ws' element={<HomePage/>}/><Route path='*' element={<div>另一页</div>}/></Routes>;
history.replaceState(null,'','/w/demo');
const root=document.getElementById('app');setPageRoot(root);
createRoot(root).render(<Tooltip.Provider><BrowserRouter><MobileShell entry={{id:'demo',name:'Test',account:ACCOUNT}} routes={routes} recent={()=>null}/></BrowserRouter></Tooltip.Provider>);
createRoot(document.getElementById('probes')).render(<>{Array.from({length:120},(_,i)=><Probe key={i} id={String(i)}/>)}</>);
Object.assign(window,{filter:f=>setSidebarMode('demo',f),operate:()=>{window.probeRenders=0;doing=[{call:'chat.pin',params:{session:'0'},stage:'running'}];demoCore.publish();},loop:restingLoop});
`, { flag: 'wx' });
  madeFixture = true;
  await writeFile(html, '<meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><div id="probes" style="display:none"></div><script type="module" src="/mobile-work-check.tsx"></script>', { flag: 'wx' });
  madeHtml = true;
  server=await createServer({configFile:fileURLToPath(new URL('../../web/vite.demo.config.ts',import.meta.url)),root:fileURLToPath(new URL('../../web',import.meta.url)),server:{host:'127.0.0.1',port:0,hmr:false}});
  await server.listen();
  for(const engine of (process.env.ENGINES||'chromium,webkit').split(',')){
    browser=await pw[engine].launch({ ...(engine === 'chromium' && process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {}) });
    const page=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true,locale:'zh-CN',...(process.env.VIDEO?{recordVideo:{dir:process.env.VIDEO,size:{width:390,height:844}}}:{})});
    let phase='initial';const errors=[];page.on('pageerror',e=>{errors.push(e.message);console.error(engine,phase,e.message);});
    await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/mobile-work-check.html`);
    await page.locator('[data-home-pane=all] [data-vk]').first().waitFor();
    await page.waitForTimeout(700);
    const rows=()=>page.locator('[data-home-pane=all] [data-vk]').count();
    assert(await rows()<50,`${engine}: only nearby rows are mounted`);
    const height=await page.locator('[data-home-pane=all]').evaluate(e=>e.scrollHeight);
    assert.equal(await page.locator('[data-home-pane=all]').evaluate(e=>e.scrollTop),0,`${engine}: home opens below its header, at the very top`);
    assert(height>66000,`${engine}: the whole list still takes its room`);
    phase='edges';
    for (const edge of ['top','bottom']) {
      const report=await page.locator('[data-home-pane=all]').evaluate(async(el,edge)=>{
        el.scrollTop=edge==='top'?0:el.scrollHeight;
        await new Promise(r=>setTimeout(r,300));
        let proto=el,descriptor;
        while(proto&&!descriptor){descriptor=Object.getOwnPropertyDescriptor(proto,'scrollTop');proto=Object.getPrototypeOf(proto);}
        const writes=[];
        let outside=null;
        Object.defineProperty(el,'scrollTop',{configurable:true,get:()=>outside??descriptor.get.call(el),set:v=>{writes.push(v);descriptor.set.call(el,v);}});
        try {
          for(const amount of [12,40,24]){
            outside=edge==='top'?-amount:el.scrollHeight-el.clientHeight+amount;
            el.dispatchEvent(new Event('scroll'));
            await new Promise(r=>setTimeout(r,70));
          }
          await new Promise(r=>setTimeout(r,200));
          return {writes,behavior:getComputedStyle(el).overscrollBehaviorY};
        }finally{delete el.scrollTop;el.dispatchEvent(new Event('scroll'));}
      },edge);
      assert.deepEqual(report.writes,[],`${engine}: ${edge} rubber-band positions must never be corrected by script`);
      assert.equal(report.behavior,'none',`${engine}: virtual Home disables competing native bounce`);
    }
    await page.locator('[data-home-pane=all]').evaluate(el=>{el.scrollTop=0;});await page.waitForTimeout(300);
    await page.evaluate(()=>window.operate());await page.waitForTimeout(100);
    assert.equal(await page.evaluate(()=>window.probeRenders),1,`${engine}: only the affected operation subscriber renders`);
    phase='archive';
    const archiveRow=page.locator('[data-home-pane=all] [data-vk$="/row-0"]');
    const swipe=archiveRow.locator('[data-archivable]').locator('..').locator('..');
    const box=await swipe.boundingBox();
    if(engine==='chromium'){
      const cdp=await page.context().newCDPSession(page);
      const touch=(type,x)=>cdp.send('Input.dispatchTouchEvent',{type,touchPoints:type==='touchEnd'?[]:[{x,y:box.y+33}]});
      await touch('touchStart',320);for(const x of [280,240,190,140,90]){await touch('touchMove',x);await page.waitForTimeout(20);}await touch('touchEnd',90);await cdp.detach();
    }else{
      await swipe.evaluate(el=>{el.setPointerCapture=()=>{};});
      await swipe.dispatchEvent('pointerdown',{pointerId:1,pointerType:'touch',clientX:320,clientY:box.y+33});
      await swipe.dispatchEvent('pointermove',{pointerId:1,pointerType:'touch',clientX:90,clientY:box.y+33});
      await swipe.dispatchEvent('pointerup',{pointerId:1,pointerType:'touch',clientX:90,clientY:box.y+33});
    }
    await page.waitForFunction(()=>window.archived===true);
    await archiveRow.waitFor({state:'detached'});
    const scroll=async(top)=>{await page.locator('[data-home-pane=all]').evaluate((e,top)=>{e.scrollTop=top;},top);await page.waitForTimeout(300);};
    phase='scroll';
    await scroll(5000);
    assert(await rows()<80,`${engine}: scrolling keeps the DOM bounded`);
    const before=await page.locator('[data-home-pane=all]').evaluate(e=>e.scrollTop);
    phase='filter';
    await page.evaluate(()=>window.filter('mine'));await page.waitForTimeout(400);
    assert.equal(await page.locator('[data-home-pane=all]').evaluate(e=>getComputedStyle(e).display),'none');
    await page.evaluate(()=>window.filter('all'));await page.waitForTimeout(400);
    assert(Math.abs(await page.locator('[data-home-pane=all]').evaluate(e=>e.scrollTop)-before)<2,`${engine}: filter return keeps its position`);
    phase='page';
    await page.evaluate(()=>window.app.push('/w/demo/other'));await page.waitForTimeout(500);
    assert.equal(await page.evaluate(()=>window.activeHome),0,`${engine}: the covered page cleans up its effects`);
    await page.evaluate(()=>window.app.pop());await page.waitForTimeout(500);
    assert.equal(await page.evaluate(()=>window.activeHome),1,`${engine}: returning resumes its effects once`);
    assert(Math.abs(await page.locator('[data-home-pane=all]').evaluate(e=>e.scrollTop)-before)<2,`${engine}: page return keeps its position`);
    // Cover Home in the middle of a filter transition. On return the old pane must not stay awake forever.
    await page.evaluate(()=>window.filter('watching'));await page.waitForTimeout(40);
    await page.evaluate(()=>window.app.push('/w/demo/other'));await page.waitForTimeout(400);
    await page.evaluate(()=>window.app.pop());await page.waitForTimeout(400);
    assert.equal(await page.locator('[data-home-pane]:visible').count(),1,`${engine}: interrupted filters leave one active pane`);
    await page.evaluate(()=>window.filter('all'));await page.waitForTimeout(300);
    await scroll(65000);assert(await rows()<80);
    assert(await page.getByText('会话 990',{exact:true}).count()>0,`${engine}: the last rows can be reached`);
    const played=await page.evaluate(async()=>{
      const parent=document.createElement('div'),el=document.createElement('span');el.textContent='wait';parent.append(el);document.body.append(parent);parent.style.visibility='hidden';
      let played=0;const animate=el.animate.bind(el);el.animate=(...args)=>{played++;return animate(...args);};
      const stop=window.loop(el,[{opacity:0},{opacity:1}],{period:120,duration:40});
      await new Promise(r=>setTimeout(r,300));const hidden=played;parent.style.visibility='visible';await new Promise(r=>setTimeout(r,300));const visible=played;stop();parent.remove();return{hidden,visible};
    });
    assert.equal(played.hidden,0,`${engine}: hidden loops never start`);assert(played.visible>0);
    if(process.env.SHOTS){await mkdir(process.env.SHOTS,{recursive:true});await page.screenshot({path:`${process.env.SHOTS}/${engine}-home.png`});}
    assert.deepEqual(errors,[]);
    console.log(`PASS ${engine}: 1000-row home bounded, filter/page positions kept, effects suspended, 1/120 operation rows rendered, hidden loops stopped`);
    await page.close();await browser.close();browser=null;
  }
}finally{await browser?.close();await server?.close();if(madeFixture)await rm(fixture,{force:true});if(madeHtml)await rm(html,{force:true});}
