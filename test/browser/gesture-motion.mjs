// The real bar's frame work: steady release animation should not rerender React or remeasure on every pointer event.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {writeFile,rm,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createServer} from 'vite';
const pw=await import(process.env.PLAYWRIGHT_MODULE||'playwright');
const fixture=new URL('../../web/gesture-motion-check.tsx',import.meta.url), html=new URL('../../web/gesture-motion-check.html',import.meta.url);
let server,madeFixture=false,madeHtml=false;
try{
 await writeFile(fixture,`import React from 'react';
import {createRoot} from 'react-dom/client';
import './src/styles/index.ts';
import {DemoApp} from './src/demo/mount.tsx';
import {setPageRoot} from './src/brand.tsx';
const root=document.getElementById('app');root.style.cssText='position:fixed;inset:0';setPageRoot(root);createRoot(root).render(<DemoApp phone/>);
`,{flag:'wx'});madeFixture=true;
 await writeFile(html,'<meta name="viewport" content="width=device-width, initial-scale=1"><div id="app"></div><script type="module" src="/gesture-motion-check.tsx"></script>',{flag:'wx'});madeHtml=true;
 server=await createServer({configFile:fileURLToPath(new URL('../../web/vite.demo.config.ts',import.meta.url)),root:fileURLToPath(new URL('../../web',import.meta.url)),plugins:[{name:'bar-render-count',enforce:'pre',transform(code,id){if(!id.split('?')[0].endsWith('/mobile/Bar.tsx'))return;const source=process.env.BASELINE_BAR?readFileSync(process.env.BASELINE_BAR,'utf8'):code;return source.replace('export function BottomBar({ scope, place, shown, go, onPanel }: BottomBarProps) {','export function BottomBar({ scope, place, shown, go, onPanel }: BottomBarProps) { window.barRenders=(window.barRenders||0)+1;');}}],server:{host:'127.0.0.1',port:0,hmr:false}});
 await server.listen();
 for(const engine of (process.env.ENGINES||'chromium,webkit').split(',')){
  const browser=await pw[engine].launch();
  try{
   const page=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true,locale:'zh-CN',...(process.env.VIDEO?{recordVideo:{dir:process.env.VIDEO,size:{width:390,height:844}}}:{})});
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.clock.install();
   await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/gesture-motion-check.html`);
   await page.locator('header').first().waitFor();await page.waitForTimeout(900);
   await page.getByRole('button',{name:/返回|会话/}).first().tap();await page.waitForTimeout(900);
   const tab=await page.getByRole('tab',{name:'对话',exact:true}).boundingBox();
   await page.clock.pauseAt(await page.evaluate(()=>Date.now()));
   await page.evaluate(()=>{
    const wrap=document.querySelector('[data-bar=glass]').parentElement;window.wrap=wrap;window.rectReads=0;
    const read=wrap.getBoundingClientRect.bind(wrap);wrap.getBoundingClientRect=()=>{window.rectReads++;return read();};wrap.setPointerCapture=()=>{};
   });
   const touch=(type,x,y)=>page.evaluate(({type,x,y})=>window.wrap.dispatchEvent(new PointerEvent(type,{bubbles:true,pointerId:1,pointerType:'touch',buttons:type==='pointerup'?0:1,clientX:x,clientY:y})),{type,x,y});
   const frames=async ms=>{for(let at=0;at<ms;at+=16)await page.clock.runFor(Math.min(16,ms-at));};
   const x=tab.x+tab.width/2;
   await touch('pointerdown',x,tab.y+28);await touch('pointermove',x,tab.y-30);await frames(32);
   await page.evaluate(()=>{window.barRenders=0;window.rectReads=0;});
   await frames(1200);
   const settlingRenders=await page.evaluate(()=>window.barRenders);
   await page.evaluate(({x,y})=>{for(let i=0;i<200;i++)window.wrap.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,pointerId:1,pointerType:'touch',buttons:1,clientX:x+(i%3),clientY:y}));},{x,y:tab.y-30});
   await frames(32);
   const moveReads=await page.evaluate(()=>window.rectReads);
   const open=await page.evaluate(()=>{const glass=document.querySelector('[data-bar=glass]').getBoundingClientRect(),row=document.querySelector('[role=tablist]').getBoundingClientRect();return row.top-glass.top;});
   assert(open>50,'the panel actually opened while its render count was measured');
   await touch('pointercancel',x,tab.y-30);await frames(900);
   if(process.env.SHOTS){await mkdir(process.env.SHOTS,{recursive:true});await page.screenshot({path:`${process.env.SHOTS}/gesture-panel-${engine}.png`});}
   await page.evaluate(()=>{window.barRenders=0;});
   await page.locator('[data-bar=scrim]').dispatchEvent('pointerdown');await frames(1200);
   const closeRenders=await page.evaluate(()=>window.barRenders);
   const closed=await page.evaluate(()=>{const glass=document.querySelector('[data-bar=glass]').getBoundingClientRect(),row=document.querySelector('[role=tablist]').getBoundingClientRect();return Math.abs(row.top-glass.top);});
   assert(closed<1,'close reaches its endpoint');
   if(!process.env.BASELINE_BAR){assert(settlingRenders<=4,`release caused ${settlingRenders} React renders`);assert(closeRenders<=4,`close caused ${closeRenders} React renders`);assert.equal(moveReads,0,'pointer movement uses the bounds captured at grab');}
   assert.deepEqual(errors,[]);
   console.log(JSON.stringify({engine,settlingRenders,closeRenders,moveReads}));
   await page.close();
  }finally{await browser.close();}
 }
}finally{await server?.close();if(madeFixture)await rm(fixture,{force:true});if(madeHtml)await rm(html,{force:true});}
