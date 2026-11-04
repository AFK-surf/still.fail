// ACP fixture shaped as `agy acp` answers (Antigravity CLI 1.4.12): its initialize, a conversation in --gemini-dir,
// the instructions in _meta.antigravity.systemPrompt.append, session/set_model, a turn's usage in the prompt's answer.
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
const dir = args[args.indexOf('--gemini-dir') + 1];
const conversations = join(dir, 'antigravity-cli', 'conversations');
mkdirSync(conversations, { recursive: true });
if (dump) appendFileSync(dump, JSON.stringify({ args, key: process.env.GEMINI_API_KEY ?? null, updates: process.env.AGY_CLI_DISABLE_AUTO_UPDATE ?? null }) + '\n');
const models = { currentModelId: 'gemini-3.5-flash', availableModels: [{ modelId: 'gemini-3.5-flash', name: 'Gemini 3.5 Flash' }, { modelId: 'gemini-3.1-pro', name: 'Gemini 3.1 Pro' }] };
for await (const line of createInterface({ input: process.stdin })) {
  const m = JSON.parse(line);
  if (dump) appendFileSync(dump + '.rpc', line + '\n');
  if (!m.method) continue;
  const p = m.params;
  if (m.method === 'initialize') reply(m.id, { protocolVersion: 1, agentCapabilities: { loadSession: true, _meta: { antigravity: { tier: true, systemPrompt: { append: true } } } }, agentInfo: { name: 'Antigravity ACP Server', version: '1.4.12' } });
  else if (m.method === 'session/new') {
    if (process.env.FAKE_AGY_SIGNED_OUT) { say({ id: m.id, error: { code: -32000, message: 'Authentication required' } }); continue; }
    sessionId = randomUUID();
    writeFileSync(join(conversations, sessionId), 'conversation');
    reply(m.id, { sessionId, models });
  } else if (m.method === 'session/load') {
    sessionId = p.sessionId;
    if (!existsSync(join(conversations, sessionId))) { say({ id: m.id, error: { code: -32602, message: 'conversation not found' } }); continue; }
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'past replay' } });
    reply(m.id, { models });
  } else if (m.method === 'session/set_model') {
    if (!models.availableModels.some((x) => x.modelId === p.modelId)) say({ id: m.id, error: { code: -32602, message: 'unknown model' } });
    else reply(m.id, {});
  } else if (m.method === 'session/cancel') {
    if (held) reply(held, { stopReason: 'cancelled' }); held = null;
  } else if (m.method === 'session/prompt') {
    const text = p.prompt[0].text;
    held = m.id;
    if (text === 'expired') { say({ id: m.id, error: { code: -32603, message: 'Authentication expired. Please log back in.' } }); held = null; continue; }
    if (text === 'quota') { say({ id: m.id, error: { code: -32603, message: 'RESOURCE_EXHAUSTED: You have exhausted your capacity on this model. Your quota will reset after 4h.' } }); held = null; continue; }
    update({ sessionUpdate: 'agent_thought_chunk', content: { type: 'text', text: 'thinking' } });
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'first ' } });
    if (text === 'hold') continue;
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text } });
    update({ sessionUpdate: 'tool_call', toolCallId: 't1', title: 'view_file', kind: 'read', status: 'in_progress', rawInput: { AbsolutePath: '/a.txt' } });
    update({ sessionUpdate: 'tool_call_update', toolCallId: 't1', status: 'completed', content: [{ type: 'content', content: { type: 'text', text: 'file contents' } }] });
    update({ sessionUpdate: 'usage_update', used: 5000, size: 1048576 });
    reply(m.id, { stopReason: 'end_turn', usage: { totalTokens: 1600, inputTokens: 1200, outputTokens: 300, thoughtTokens: 100, cachedReadTokens: 200 } });
    held = null;
  } else say({ id: m.id, error: { code: -32601, message: 'Method not found: ' + m.method } });
}
