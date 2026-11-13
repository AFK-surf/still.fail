// ACP fixture shaped as `agy acp` answers (Antigravity CLI 1.4.12): its initialize, a conversation in --gemini-dir,
// the instructions in _meta.antigravity.systemPrompt.append, session/set_model, a turn's usage in the prompt's answer.
// Without `acp`, its terminal interface signing in as 1.4.12's does (in a terminal, not signed in, not in a remote session):
// how to sign in asked, Google's page printed, the code read back (`bad`: nothing comes of it), its sign-in written to
// $HOME/.gemini/antigravity-cli, and the interface going on until it is stopped.
import { appendFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { randomUUID } from 'node:crypto';
const dump = process.env.FAKE_DUMP;
const args = process.argv.slice(2);
const promptAt = args.indexOf('-p');
if (promptAt >= 0 && args[promptAt + 1] === '/usage') await printUsage();
if (args[0] !== 'acp') await signIn();
async function printUsage() {
  if (dump) appendFileSync(dump, JSON.stringify({ args, home: process.env.HOME ?? null, geminiDir: process.env.ANTIGRAVITY_GEMINI_DIR ?? null, cloudCodeUrl: process.env.CLOUD_CODE_URL ?? null, key: process.env.GEMINI_API_KEY ?? null, updates: process.env.AGY_CLI_DISABLE_AUTO_UPDATE ?? null }) + '\n');
  if (process.env.FAKE_AGY_SIGNED_OUT) {
    process.stdout.write('Authentication required. Please visit the URL to log in:\n  https://accounts.google.com/o/oauth2/auth\n\nWaiting for authentication (timeout 60s)...\n');
    await new Promise(() => {});
  }
  if (process.env.FAKE_AGY_USAGE_ERROR) {
    const err = process.env.FAKE_AGY_USAGE_ERROR;
    process.stderr.write(`error: ${err}\n`);
    process.stdout.write(JSON.stringify({ conversation_id: '', status: 'ERROR', response: '', error: err }) + '\n');
    process.exit(1);
  }
  const tokenPath = join(process.env.ANTIGRAVITY_GEMINI_DIR ?? join(process.env.HOME ?? '', '.gemini'), 'antigravity-cli', 'antigravity-oauth-token');
  const keyringOk = Boolean(process.env.FAKE_AGY_KEYRING) && (!process.env.FAKE_KEYCHAIN_HOME || process.env.HOME === process.env.FAKE_KEYCHAIN_HOME);
  if (!existsSync(tokenPath) && !keyringOk) {
    process.stdout.write('Authentication required. Please visit the URL to log in:\n  https://accounts.google.com/o/oauth2/auth\n\nWaiting for authentication (timeout 60s)...\n');
    await new Promise(() => {});
  }
  process.stdout.write(JSON.stringify({
    conversation_id: '',
    status: 'SUCCESS',
    command: {
      name: 'usage',
      data: {
        groups: [
          {
            name: 'Gemini Models',
            buckets: [
              { id: 'gemini-weekly', name: 'Weekly Limit Remaining', window: 'weekly', remaining_fraction: 0.75, reset_time: '2026-11-19T09:14:38Z' },
              { id: 'gemini-5h', name: 'Five Hour Limit Remaining', window: '5h', remaining_fraction: 0.9, reset_time: '2026-11-12T14:14:38Z' },
            ],
          },
          {
            name: 'Claude and GPT models',
            buckets: [
              { id: '3p-weekly', name: 'Weekly Limit Remaining', window: 'weekly', remaining_fraction: 0.4, reset_time: '2026-11-19T09:14:38Z' },
              { id: '3p-5h', name: 'Five Hour Limit Remaining', window: '5h', remaining_fraction: 0, reset_time: '2026-11-12T14:14:38Z' },
            ],
          },
        ],
      },
    },
  }) + '\n');
  process.exit(0);
}
async function signIn() {
  if (dump) appendFileSync(dump, JSON.stringify({ args, home: process.env.HOME, remote: process.env.SSH_CONNECTION ?? null, key: process.env.GEMINI_API_KEY ?? null }) + '\n');
  if (!process.stdin.isTTY) { process.stderr.write('not a terminal\n'); process.exit(1); }
  const url = 'https://accounts.google.com/o/oauth2/auth?access_type=offline&client_id=1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com&code_challenge=311aMcnjlIZigwJvlJ11zPjRZcH3mLzipvgAYB_hEgc&code_challenge_method=S256&prompt=consent&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback&response_type=code&scope=openid&state=Jn-JRaj4nQfYyaCSr9NcnA';
  process.stdin.setRawMode(true);
  process.stdout.write('\u001b[?1049h Welcome to the Antigravity CLI. You are currently not signed in.\n\n Select login method:\n > 1. Google OAuth\n2. Use a Google Cloud project\n');
  let typed = '';
  let step = 'menu';
  process.stdin.on('data', (chunk) => {
    typed += chunk.toString('utf8');
    let enter;
    while ((enter = typed.indexOf('\r')) >= 0) {
      const line = typed.slice(0, enter).trim();
      typed = typed.slice(enter + 1);
      if (step === 'menu') {
        step = 'code';
        process.stdout.write(` Signing in...Your browser should open automatically. If not:\n\n ${url}\n\n If you aren't automatically redirected, paste the authorization code below:\n\n authorization code...\n`);
      } else if (step === 'code' && line !== 'bad') {
        const at = join(process.env.HOME, '.gemini', 'antigravity-cli');
        mkdirSync(at, { recursive: true });
        writeFileSync(join(at, 'antigravity-oauth-token'), JSON.stringify({ token: { access_token: `ya29.${line}`, token_type: 'Bearer' }, auth_method: 'oauth', id_token_email: 'someone@gmail.com' }));
        step = 'in';
        process.stdout.write('\u001b[2J Welcome to Antigravity CLI!\n');
      }
    }
  });
  await new Promise(() => {});
}
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
    const prev = held;
    held = m.id;
    if (prev) {
      reply(prev, { stopReason: 'end_turn', usage: { totalTokens: 510, inputTokens: 500, outputTokens: 10, thoughtTokens: 0, cachedReadTokens: 0 } });
      update({ sessionUpdate: 'user_message_chunk', content: { type: 'text', text } });
    }
    if (text === 'expired') { say({ id: m.id, error: { code: -32603, message: 'Authentication expired. Please log back in.' } }); held = null; continue; }
    if (text === 'quota') { say({ id: m.id, error: { code: -32603, message: 'RESOURCE_EXHAUSTED: You have exhausted your capacity on this model. Your quota will reset after 4h.' } }); held = null; continue; }
    update({ sessionUpdate: 'agent_thought_chunk', content: { type: 'text', text: 'thinking' } });
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: 'first ' } });
    if (text === 'hold' || text === 'hold-steer') continue;
    update({ sessionUpdate: 'agent_message_chunk', content: { type: 'text', text } });
    update({ sessionUpdate: 'tool_call', toolCallId: 't1', title: 'view_file', kind: 'read', status: 'in_progress', rawInput: { AbsolutePath: '/a.txt' } });
    update({ sessionUpdate: 'tool_call_update', toolCallId: 't1', status: 'completed', content: [{ type: 'content', content: { type: 'text', text: 'file contents' } }] });
    // A call to the station's tools, as 1.4.12 titles an MCP tool's.
    update({ sessionUpdate: 'tool_call', toolCallId: 'call_1', title: 'Run mcp_stillfail_chat_post', kind: 'other', status: 'in_progress', rawInput: { text: 'reply', toolSummary: 'Post reply' } });
    update({ sessionUpdate: 'tool_call_update', toolCallId: 'call_1', status: 'completed', content: [] });
    update({ sessionUpdate: 'usage_update', used: 5000, size: 1048576 });
    reply(m.id, { stopReason: 'end_turn', usage: { totalTokens: 1600, inputTokens: 1200, outputTokens: 300, thoughtTokens: 100, cachedReadTokens: 200 } });
    held = null;
  } else say({ id: m.id, error: { code: -32601, message: 'Method not found: ' + m.method } });
}
