// ACP fixture shaped as `codebuddy --acp` answers (CodeBuddy Code 2.179.3): its initialize, `Authentication required`
// when signed out, session/new and session/load (`codebuddy.ai/suppressReplay` keeps the past from being said again),
// session/set_model, session/steer into the running turn, MCP tools named mcp__<server>__<tool>, usage_update.
import { appendFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { randomUUID } from 'node:crypto';
const dump = process.env.FAKE_DUMP;
const args = process.argv.slice(2);
const say = (m) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', ...m }) + '\n');
const reply = (id, result) => say({ id, result });
let sessionId;
let held;
const update = (u) => say({ method: 'session/update', params: { sessionId, update: u } });
const sessions = join(process.env.CODEBUDDY_CONFIG_DIR, 'sessions');
mkdirSync(sessions, { recursive: true });
if (dump) appendFileSync(dump, JSON.stringify({ args, key: process.env.CODEBUDDY_API_KEY ?? null, site: process.env.CODEBUDDY_INTERNET_ENVIRONMENT ?? null, config: process.env.CODEBUDDY_CONFIG_DIR, updates: process.env.DISABLE_AUTOUPDATER ?? null }) + '\n');
const models = { currentModelId: 'default-model', availableModels: [{ modelId: 'default-model', name: 'Default' }, { modelId: 'deepseek-v4.1-flash', name: 'DeepSeek V4.1 Flash' }] };
const signedIn = () => process.env.CODEBUDDY_API_KEY !== undefined;
for await (const line of createInterface({ input: process.stdin })) {
  const m = JSON.parse(line);
  if (dump) appendFileSync(dump + '.rpc', line + '\n');
  if (!m.method) continue;
  const p = m.params;
  if (m.method === 'initialize') reply(m.id, { protocolVersion: 1, agentCapabilities: { promptCapabilities: { image: true, embeddedContext: true }, mcpCapabilities: { http: true, sse: true }, loadSession: true }, authMethods: [{ id: 'internal', name: 'Login with WeChat', description: null }] });
  else if (m.method === 'session/new') {
    if (!signedIn()) { say({ id: m.id, error: { code: -32000, message: 'Authentication required', data: { category: 'auth' } } }); continue; }
    sessionId = randomUUID();
    writeFileSync(join(sessions, sessionId), 'session');
    reply(m.id, { sessionId, models });
  } else if (m.method === 'session/load') {
    sessionId = p.sessionId;
    if (!existsSync(join(sessions, sessionId))) { say({ id: m.id, error: { code: -32603, message: 'Internal error', data: { details: `Session not found: ${sessionId}` } } }); continue; }
    if (p._meta?.['codebuddy.ai/suppressReplay'] !== true) update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'past replay' } });
    reply(m.id, { models });
  } else if (m.method === 'session/set_model') {
    if (!models.availableModels.some((x) => x.modelId === p.modelId)) say({ id: m.id, error: { code: -32603, message: 'Internal error', data: { details: 'unknown model' } } });
    else reply(m.id, { modelId: p.modelId });
  } else if (m.method === 'session/steer') {
    if (!held) { reply(m.id, { steered: false, reason: 'idle' }); continue; }
    reply(m.id, { steered: true });
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: ` (heard ${p.contentBlocks[0].text})` } });
  } else if (m.method === 'session/cancel') {
    if (held) reply(held, { stopReason: 'cancelled' }); held = null;
  } else if (m.method === 'session/prompt') {
    const text = p.prompt[0].text;
    held = m.id;
    if (text === 'expired') { say({ id: m.id, error: { code: -32000, message: 'Authentication required', data: { category: 'auth' } } }); held = null; continue; }
    if (text === 'credits') { say({ id: m.id, error: { code: -32603, message: 'Internal error', data: { details: 'Insufficient credits: your plan quota is used up' } } }); held = null; continue; }
    update({ sessionUpdate: 'agent_thought_chunk', content: { type: 'text', text: 'thinking' } });
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'first ' } });
    if (text === 'hold') continue;
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text } });
    update({ sessionUpdate: 'tool_call', toolCallId: 't1', title: 'Read', kind: 'other', status: 'in_progress', rawInput: { file_path: '/a.txt' }, _meta: { 'codebuddy.ai/toolName': 'Read' } });
    update({ sessionUpdate: 'tool_call_update', toolCallId: 't1', status: 'completed', content: [{ type: 'content', content: { type: 'text', text: 'file contents' } }] });
    update({ sessionUpdate: 'tool_call', toolCallId: 'call_1', title: 'mcp__stillfail__chat_post', kind: 'other', status: 'in_progress', rawInput: { text: 'reply' }, _meta: { 'codebuddy.ai/toolName': 'mcp__stillfail__chat_post' } });
    update({ sessionUpdate: 'tool_call_update', toolCallId: 'call_1', status: 'completed', content: [] });
    update({ sessionUpdate: 'usage_update', used: 5000, size: 200000 });
    reply(m.id, { stopReason: 'end_turn', usage: { totalTokens: 1600, inputTokens: 1200, outputTokens: 300, thoughtTokens: 100, cachedReadTokens: 200 } });
    held = null;
  } else say({ id: m.id, error: { code: -32601, message: `"Method not found": ${m.method}` } });
}
