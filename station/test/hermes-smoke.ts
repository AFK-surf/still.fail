// Real Hermes ACP smoke test against a local deterministic model and MCP server. No external model calls.
import { createServer } from 'node:http';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { HermesDriver } from '../src/agents/hermes.ts';
const data = mkdtempSync('/tmp/hm-real-');
const home = join(data, 'profile'); mkdirSync(join(home,'hermes'), {recursive:true});
let posted = false; let requests = 0;
const json = (res:any, body:any) => { res.setHeader('Content-Type','application/json'); res.end(JSON.stringify(body)); };
const server = createServer(async (req,res) => {
 let raw=''; for await (const c of req) raw += c;
 const b = raw ? JSON.parse(raw) : {};
 if (req.url === '/mcp') {
  if (req.method === 'GET') {res.statusCode=405;res.end();return;}
  if (!b.id) {res.statusCode=202;res.end();return;}
  let result:any = {};
  if (b.method === 'initialize') result = {protocolVersion:'2024-11-05',capabilities:{tools:{}},serverInfo:{name:'stillfail-smoke',version:'1'}};
  if (b.method === 'tools/list') result = {tools:[{name:'chat_post',description:'Post a reply',inputSchema:{type:'object',properties:{text:{type:'string'}},required:['text']}}]};
  if (b.method === 'tools/call') {posted=true;result={content:[{type:'text',text:'Posted'}]};}
  json(res,{jsonrpc:'2.0',id:b.id,result});return;
 }
 if (req.url?.endsWith('/models')) {json(res,{data:[{id:'smoke-model',object:'model'}]});return;}
 requests++;
 const tool = b.tools?.find((t:any) => t.function?.name?.endsWith('chat_post'))?.function?.name;
 const call = !posted && tool;
 const message = call ? {role:'assistant',content:null,tool_calls:[{id:'call_smoke',type:'function',function:{name:tool,arguments:JSON.stringify({text:'Hermes MCP smoke OK'})}}]} : {role:'assistant',content:'Hermes smoke OK'};
 const response = {id:'smoke',object:'chat.completion',created:1,model:'smoke-model',choices:[{index:0,message,finish_reason:call?'tool_calls':'stop'}],usage:{prompt_tokens:10,completion_tokens:5,total_tokens:15}};
 if (b.stream) {
  res.setHeader('Content-Type','text/event-stream');
  const delta:any = {...message}; if(delta.tool_calls) delta.tool_calls = delta.tool_calls.map((t:any,i:number)=>({...t,index:i}));
  res.write(`data: ${JSON.stringify({...response,object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason:null}]})}\n\n`);
  res.write(`data: ${JSON.stringify({...response,object:'chat.completion.chunk',choices:[{index:0,delta:{},finish_reason:call?'tool_calls':'stop'}]})}\n\n`);res.end('data: [DONE]\n\n');
 } else json(res,response);
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r)); const port=(server.address() as any).port;
writeFileSync(join(home,'hermes','config.yaml'), `model:\n  default: smoke-model\n  provider: custom\n  base_url: http://127.0.0.1:${port}/v1\n  stream: false\nagent:\n  max_turns: 4\nmemory:\n  memory_enabled: false\n  user_profile_enabled: false\n`);
const driver=new HermesDriver({data}); let complete:any; const done=new Promise(r=>complete=r);
try {
 const s=await driver.open({key:'real-smoke',profile:{id:'hm',runtime:'hermes',home,access:{kind:'env'},env:{OPENAI_API_KEY:'local-test-placeholder',OPENAI_BASE_URL:`http://127.0.0.1:${port}/v1`,HERMES_TELEMETRY_ENABLED:'false'}},cwd:data,instructions:'Use the stillfail chat_post tool to send the answer.',mcpToken:'smoke-token',mcpUrl:`http://127.0.0.1:${port}/mcp`,route:'smoke'},e=>{if(e.type==='turnEnded')complete(e.outcome);});
 console.log('REAL ACP SESSION OPENED');
 await s.prompt('Post the result with chat_post.');
 const outcome=await Promise.race([done,new Promise((_,reject)=>setTimeout(()=>reject(new Error('turn timeout')),45000).unref())]);
 console.log(JSON.stringify({outcome,posted,requests}));
 if(!posted) throw new Error('MCP tool was not called');
 const id=s.id();await s.dispose();
 const resumed=await driver.open({key:'real-smoke',profile:{id:'hm',runtime:'hermes',home,access:{kind:'env'},env:{OPENAI_API_KEY:'local-test-placeholder',OPENAI_BASE_URL:`http://127.0.0.1:${port}/v1`}},cwd:data,instructions:'Resume',mcpToken:'smoke-token',mcpUrl:`http://127.0.0.1:${port}/mcp`,route:'smoke',resume:id},()=>{});
 console.log('REAL ACP SESSION RESUMED', resumed.id()===id);await resumed.dispose();
} finally {await driver.shutdown();server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));rmSync(data,{recursive:true,force:true});}
