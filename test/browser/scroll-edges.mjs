// Shared virtual panes and pull-to-reload under Safari-style out-of-range scrollTop samples.
// Injection checks ownership of scroll position; it does not emulate iPhone compositor physics.
import assert from 'node:assert/strict';
import {writeFile,rm} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createServer} from 'vite';
const pw=await import(process.env.PLAYWRIGHT_MODULE||'playwright');
const fixture=new URL('../../web/scroll-edges-check.tsx',import.meta.url), html=new URL('../../web/scroll-edges-check.html',import.meta.url);
let server,madeFixture=false,madeHtml=false;
try{
 await writeFile(fixture,`import React,{Activity,useRef,useState} from 'react';
import {createRoot} from 'react-dom/client';
import './src/styles/index.ts';
import {useVirtualList,useVirtualModel} from './src/virtual/list.tsx';
import {usePullToReload} from './src/mobile/pull.ts';
import {scrollToEnd} from './src/scrollBounds.ts';
import {mHomePane} from './src/mobile/Home.css.ts';
import {mHSteps} from './src/mobile/History.css.ts';
import {mMessages} from './src/mobile/styles/chat.css.ts';
import {historyBody} from './src/History.css.ts';
import {mJobOutput} from './src/mobile/Chat.css.ts';
import {jobOutput} from './src/Jobs.css.ts';
import {sendsList} from './src/screen/Transfer.css.ts';
window.models={};window.bump={};window.reloads=[];
function List({name,kind}){
 const el=useRef(null), made=useVirtualModel(name,0,false),[height,setHeight]=useState(50),[loaded,load]=useState(name!=='history');
 if(name==='history')window.loadHistory=()=>load(true);
 const items=Array.from({length:name==='empty'?0:name==='short'?2:80},(_,i)=>({key:String(i),estimate:i===0?height:50,exact:i===0?height:50}));
 const virtual=useVirtualList(el,made,items,{cover:lead=>lead});
 window.models[name]=made.model;window.bump[name]=()=>setHeight(n=>n+10);
 if(!loaded)return <div>Loading</div>;
 return <div ref={el} id={name} className={kind+' height-'+height} style={{position:'relative',height:400,width:390,padding:0,gap:0,flex:'none','--list-gap':'0px'}}>
 {virtual.layout.rows.map((r,i)=><React.Fragment key={r.key}>{virtual.above(r,i===0)}<div data-vk={r.key} style={{height:r.key==='0'?height:50,flex:'none'}}>{name} {r.key}</div></React.Fragment>)}{virtual.after()}
 </div>;
}
function Pull(){const pull=usePullToReload(mHomePane);return <div {...pull.handlers}><div id='pull-mark' ref={pull.mark}/><div id='pull-pane' className={mHomePane} style={{position:'relative',height:200}}>Pull</div></div>;}
function App(){const [hidden,hide]=useState(false);window.hide=hide;return <>
 <List name='home' kind={mHomePane}/><List name='history' kind={mHSteps}/><List name='chat' kind={mMessages}/><List name='desktop' kind={historyBody}/>
 <List name='short' kind={mHomePane}/><List name='empty' kind={mHomePane}/>
 <Activity mode={hidden?'hidden':'visible'}><Pull/></Activity>
 {[mJobOutput,jobOutput,sendsList].map((kind,i)=><div key={i} id={'log'+i} className={kind} style={{height:100,maxHeight:100}}><div style={{height:1000}}>Output</div></div>)}
 </>;}
window.follow=scrollToEnd;createRoot(document.getElementById('root')).render(<App/>);
`,{flag:'wx'});madeFixture=true;
 await writeFile(html,'<meta name="viewport" content="width=device-width, initial-scale=1"><div id="root"></div><script type="module" src="/scroll-edges-check.tsx"></script>',{flag:'wx'});madeHtml=true;
 server=await createServer({configFile:fileURLToPath(new URL('../../web/vite.demo.config.ts',import.meta.url)),root:fileURLToPath(new URL('../../web',import.meta.url)),plugins:[{name:'reload-probe',enforce:'pre',resolveId(source,importer){if(source==='../reloads.ts'&&importer?.endsWith('/mobile/pull.ts'))return '\0reload-probe';},load(id){if(id==='\0reload-probe')return 'export function reload(reason){window.reloads.push(reason)}';}}],server:{host:'127.0.0.1',port:0,hmr:false}});
 await server.listen();
 for(const engine of (process.env.ENGINES||'chromium,webkit').split(',')){
  const browser=await pw[engine].launch();
  try{
   const page=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/scroll-edges-check.html`);
   await page.waitForFunction(()=>window.models?.home);await page.evaluate(()=>window.loadHistory());await page.locator('#history').waitFor();await page.waitForTimeout(600);
   for(const name of ['home','history','chat','desktop','short','empty'])for(const edge of ['top','bottom']){
    const report=await page.evaluate(async({name,edge})=>{
     const el=document.getElementById(name);el.scrollTop=edge==='top'?0:el.scrollHeight;await new Promise(r=>setTimeout(r,200));
     let p=el,d;while(p&&!d){d=Object.getOwnPropertyDescriptor(p,'scrollTop');p=Object.getPrototypeOf(p);}
     const writes=[];let fake=edge==='top'?-30:el.scrollHeight-el.clientHeight+30;
     Object.defineProperty(el,'scrollTop',{configurable:true,get:()=>fake,set:v=>{writes.push(v);d.set.call(el,v);}});
     try{
      el.dispatchEvent(new Event('scroll'));window.bump[name]();await new Promise(r=>setTimeout(r,220));
      return {writes,behavior:getComputedStyle(el).overscrollBehaviorY};
     }finally{delete el.scrollTop;el.dispatchEvent(new Event('scroll'));}
    },{name,edge});
    assert.deepEqual(report.writes,[],`${engine} ${name} ${edge}: resize/rest must not correct rubber-band displacement`);
    assert.equal(report.behavior,'none');
   }
   for(const name of ['log0','log1','log2']){
    const result=await page.evaluate(name=>{
     const el=document.getElementById(name);window.follow(el);let writes=0;
     let p=el,d;while(p&&!d){d=Object.getOwnPropertyDescriptor(p,'scrollTop');p=Object.getPrototypeOf(p);}
     let fake=el.scrollTop;Object.defineProperty(el,'scrollTop',{configurable:true,get:()=>fake,set:()=>{writes++;}});
     try{window.follow(el);fake=-20;window.follow(el);fake=el.scrollHeight-el.clientHeight+20;window.follow(el);return {writes,behavior:getComputedStyle(el).overscrollBehaviorY};}
     finally{delete el.scrollTop;}
    },name);
    assert.deepEqual(result,{writes:0,behavior:'none'});
   }
   assert.equal(await page.locator('#pull-pane').evaluate(el=>getComputedStyle(el).overscrollBehaviorY),'none','Home without a virtual list still gives the pull gesture sole ownership of its displacement');
   const touch=(type,y=100,count=1,x=100)=>page.evaluate(({type,y,count,x})=>{
    const el=document.getElementById('pull-pane'),event=new Event(type,{bubbles:true});
    Object.defineProperty(event,'touches',{value:Array.from({length:count},(_,identifier)=>({identifier,clientX:x,clientY:y,target:el}))});el.dispatchEvent(event);
   },{type,y,count,x});
   await touch('touchstart');await touch('touchmove',160);
   assert.equal(await page.locator('#pull-pane').evaluate(e=>e.style.translate),'0px 30px');
   await page.locator('#pull-pane').evaluate(el=>Object.defineProperty(el,'scrollTop',{configurable:true,get:()=>-20}));
   await touch('touchmove',164);
   assert.equal(await page.locator('#pull-pane').evaluate(e=>e.style.translate),'0px 32px','native displacement cannot switch the pull driver');
   await page.locator('#pull-pane').evaluate(el=>{delete el.scrollTop;});
   await touch('touchcancel',164,0);await page.waitForTimeout(260);
   assert.equal(await page.locator('#pull-pane').evaluate(e=>e.style.translate),'');
   await touch('touchstart');await touch('touchmove',160);await touch('touchstart',160,2);
   assert.equal(await page.locator('#pull-pane').evaluate(e=>e.style.translate),'','second finger cancels and restores the pane');
   await touch('touchstart');await touch('touchmove',160);await page.evaluate(()=>window.hide(true));await page.waitForTimeout(50);await page.evaluate(()=>window.hide(false));
   await page.waitForTimeout(50);
   assert.equal(await page.locator('#pull-pane').evaluate(e=>e.style.translate),'','covered Home retains no pull displacement');
   assert.equal(await page.locator('#pull-mark').getAttribute('data-pulling'),null);
   await touch('touchstart');await touch('touchmove',160);await touch('touchend',160,0);
   assert.deepEqual(await page.evaluate(()=>window.reloads),[],'short pulls do not reload');
   await touch('touchstart');await touch('touchmove',190);await touch('touchend',190,0);
   await touch('touchend',190,0);
   assert.deepEqual(await page.evaluate(()=>window.reloads),['pull'],'one intentional long pull reloads once');
   assert.equal(await page.locator('#pull-mark').getAttribute('data-reloading'),'');
   assert.equal(await page.locator('#pull-mark').evaluate(e=>e.style.getPropertyValue('--pull')),'1','reload indicator stays visible until navigation');
   assert.deepEqual(errors,[]);
   console.log('PASS '+engine+': four virtual pane styles plus short/empty lists, output followers, pull cancel/multitouch/Activity cleanup/reload');
  }finally{await browser.close();}
 }
}finally{await server?.close();if(madeFixture)await rm(fixture,{force:true});if(madeHtml)await rm(html,{force:true});}
