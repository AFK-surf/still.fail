// ACP fixture matching Hermes' public protocol: no vendor-specific auth, rules or config options.
import { appendFileSync, existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { randomUUID } from 'node:crypto';
const dump = process.env.FAKE_DUMP;
const say = (m) => process.stdout.write(JSON.stringify({ jsonrpc: '2.0', ...m }) + '\n');
let sessionId;
let held;
const reply = (id, result) => say({ id, result });
const update = (u) => say({ method: 'session/update', params: { sessionId, update: u } });
if (dump) appendFileSync(dump, JSON.stringify({ args: process.argv.slice(2), home: process.env.HERMES_HOME, key: process.env.OPENAI_API_KEY ?? null }) + '\n');
for await (const line of createInterface({ input: process.stdin })) {
  const m = JSON.parse(line);
  if (dump) appendFileSync(dump + '.rpc', line + '\n');
  if (!m.method) {
    if (m.id === 'permission') {
      update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: m.result.outcome.optionId } });
      reply(held, { stopReason: 'end_turn' }); held = null;
    }
    continue;
  }
  const p = m.params;
  if (m.method === 'initialize') reply(m.id, { protocolVersion: 1, agentCapabilities: { loadSession: true, mcpCapabilities: { http: true } } });
  else if (m.method === 'session/new') {
    sessionId = randomUUID();
    writeFileSync(join(process.env.HERMES_HOME, sessionId), 'session');
    reply(m.id, { sessionId });
  } else if (m.method === 'session/load') {
    sessionId = p.sessionId;
    if (!existsSync(join(process.env.HERMES_HOME, sessionId))) say({ id: m.id, error: { code: -32602, message: 'session not found' } });
    else {
      update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'past replay' } });
      reply(m.id, {});
    }
  } else if (m.method === 'session/set_model') {
    if (p.modelId === 'bad') say({ id: m.id, error: { code: -32602, message: 'unknown model' } });
    else reply(m.id, {});
  } else if (m.method === 'session/cancel') {
    if (held) reply(held, { stopReason: 'cancelled' }); held = null;
  } else if (m.method === 'session/prompt') {
    const text = p.prompt[0].text.split('</stillfail-context>\n\n').at(-1);
    held = m.id;
    if (text === 'exit') process.exit(4);
    if (text === 'fail') { say({ id: m.id, error: { code: -32603, message: '401 Unauthorized' } }); held = null; continue; }
    if (text === 'ask') { say({ id: 'permission', method: 'session/request_permission', params: { sessionId, options: [{ kind: 'allow_always', optionId: 'always' }, { kind: 'allow_once', optionId: 'once' }] } }); continue; }
    update({ sessionUpdate: 'agent_thought_chunk', content: { type: 'text', text: 'thinking' } });
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'first ' } });
    if (text === 'hold' || text === 'handover') {
      if (text === 'handover') setTimeout(() => {
        update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'last' } });
        reply(m.id, { stopReason: 'end_turn' }); held = null;
      }, 1500);
      continue;
    }
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text } });
    update({ sessionUpdate: 'tool_call', toolCallId: 't1', title: 'read_file', kind: 'read', status: 'in_progress', rawInput: { path: 'a.txt' } });
    update({ sessionUpdate: 'tool_call_update', toolCallId: 't1', status: 'completed', content: [{ type: 'content', content: { type: 'text', text: 'file contents' } }] });
    reply(m.id, { stopReason: 'end_turn' }); held = null;
  } else say({ id: m.id, error: { code: -32601, message: 'Unsupported: ' + m.method } });
}
