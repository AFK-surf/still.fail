import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join, delimiter } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { after, test } from "node:test";
import { HermesDriver, hermesEnv, outcomeOf, hermesCatalog, HERMES_MODEL_LIMIT } from "../src/agents/hermes.ts";
import type { OpenOptions, RuntimeEvent } from "../src/agents/runtime.ts";
import { transcriptPath, readTimeline, isPosting } from "../src/read/transcript.ts";
import { CHAT_CREATE } from "../src/tools/chat.ts";
import { accessKinds } from "../src/accounts/profiles.ts";
const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "hm-") : "/tmp/hm-");
const drivers: HermesDriver[] = [];
after(async () => { await Promise.all(drivers.map((d) => d.shutdown())); rmSync(data, { recursive: true, force: true }); });
let n = 0;
function setup() {
  const id = ++n;
  const dump = join(data, `dump-${id}`);
  const options: OpenOptions = { key: `hermes-test-${id}`, profile: { id: 'hm', runtime: 'hermes', home: join(data, `home-${id}`), access: { kind: 'env' }, env: { PATH: `${fileURLToPath(new URL('./fake', import.meta.url))}${delimiter}${process.env.PATH}`, FAKE_DUMP: dump } }, cwd: data, instructions: 'Use chat_post to answer.', mcpToken: 'test-token', mcpUrl: 'http://127.0.0.1:12345/mcp', route: 'test', model: 'openrouter:test' };
  const events: RuntimeEvent[] = [];
  const driver = new HermesDriver({ data }); drivers.push(driver);
  return { options, events, driver, dump };
}
async function until(f: () => boolean) {
  const end = Date.now() + 10_000;
  while (!f()) { if (Date.now() > end) throw new Error('timed out'); await new Promise((r) => setTimeout(r, 20)); }
}
const ended = (events: RuntimeEvent[]) => events.filter((e) => e.type === 'turnEnded');
test('Hermes setup, MCP, instructions, streaming, transcript and resume', async () => {
  const { options, events, driver, dump } = setup();
  const session = await driver.open(options, e => events.push(e));
  await session.prompt('hello'); await until(() => ended(events).length === 1);
  assert.deepEqual(ended(events)[0], { type: 'turnEnded', outcome: { kind: 'completed' } });
  const calls = readFileSync(dump + '.rpc', 'utf8').trim().split('\n').map(s => JSON.parse(s));
  assert.equal(calls.find(m => m.method === 'session/new').params.mcpServers[0].headers[0].value, 'Bearer test-token');
  assert.equal(calls.find(m => m.method === 'session/set_model').params.modelId, options.model);
  assert.match(calls.find(m => m.method === 'session/prompt').params.prompt[0].text, /Use chat_post/);
  const path = transcriptPath('hermes', options.profile.home, session.id()); assert.ok(path);
  const lines = readFileSync(path, 'utf8').trim().split('\n').map(s => JSON.parse(s));
  assert.equal(lines.find(m => m.type === 'assistant').text, 'first hello');
  assert.equal(lines.find(m => m.type === 'tool').result, 'file contents');
  assert.equal(lines.find(m => m.type === 'tool').name, 'read_file');
  assert.ok(readTimeline('hermes', path).length > 0);
  const id = session.id(); await session.dispose(); events.length = 0;
  const resumed = await driver.open({ ...options, resume: id }, e => events.push(e));
  assert.equal(resumed.id(), id); assert.equal(events.length, 0);
  await resumed.prompt('again'); await until(() => ended(events).length === 1);
  assert.doesNotMatch(readFileSync(path, 'utf8'), /past replay/);
  await resumed.dispose();
});
test('cancel, queued steering, permission scope and classified failures', async () => {
  const { options, events, driver } = setup(); const s = await driver.open(options, e => events.push(e));
  await s.prompt('hold'); assert.equal(await s.steer('later'), false); await s.abort();
  await until(() => ended(events).length === 1); assert.deepEqual(ended(events)[0], { type: 'turnEnded', outcome: { kind: 'aborted' } });
  await s.prompt('ask'); await until(() => ended(events).length === 2);
  assert.ok(events.some(e => e.type === 'live' && e.event.kind === 'delta' && e.event.text === 'once'));
  await s.prompt('fail'); await until(() => ended(events).length === 3);
  assert.deepEqual(ended(events)[2], { type: 'turnEnded', outcome: { kind: 'failed', reason: 'auth', message: '401 Unauthorized' } });
  await s.dispose();
});
test('handover preserves partial transcript and completes the running turn once', async () => {
  const { options, events, driver } = setup(); const s = await driver.open(options, e => events.push(e));
  await s.prompt('handover');
  await until(() => events.some(e => e.type === 'live' && e.event.kind === 'delta' && e.event.text === 'first '));
  const snapshot = s.snapshot(); s.detach();
  const next = new HermesDriver({ data }); drivers.push(next); const after: RuntimeEvent[] = [];
  const adopted = await next.adopt(options, snapshot, e => after.push(e));
  await adopted.request('continue', '_test/continue', {});
  await until(() => ended(after).length === 1);
  assert.match(readFileSync(transcriptPath('hermes', options.profile.home, adopted.id())!, 'utf8'), /first last/);
  assert.equal(ended(events).length, 0); await adopted.dispose();
});
test('configuration stays within its profile and rejects unsafe session IDs', async () => {
  const { options, driver } = setup();
  assert.equal(hermesEnv(options).HERMES_HOME, join(options.profile.home, 'hermes'));
  assert.deepEqual(accessKinds('hermes'), ['env']);
  assert.ok(CHAT_CREATE.inputSchema.properties.runtime.enum.includes('hermes'));
  await assert.rejects(driver.open({ ...options, resume: '../escape' }, () => {}), /invalid Hermes session id/);
  await assert.rejects(driver.open({ ...options, model: 'bad' }, () => {}), /unknown model/);
  await assert.rejects(driver.open({ ...options, profile: { ...options.profile, env: { ...options.profile.env as Record<string, string>, FAKE_HERMES_VERSION: '0.21.3' } } }, () => {}), /0\.21\.7/);
  assert.equal(outcomeOf({ error: { message: '429 rate limit' } }).kind, 'failed');
});

test('crash adoption reconstructs partial text without duplicating completed steps', async () => {
  const { options, events, driver } = setup(); const s = await driver.open(options, e => events.push(e));
  await s.prompt('handover');
  await until(() => events.some(e => e.type === 'live' && e.event.kind === 'delta' && e.event.text === 'first '));
  s.detach();
  const next = new HermesDriver({ data }); drivers.push(next); const after: RuntimeEvent[] = [];
  const adopted = await next.adopt({ ...options, resume: s.id() }, null, e => after.push(e));
  await adopted.request('continue', '_test/continue', {});
  await until(() => ended(after).length === 1);
  const records = readFileSync(transcriptPath('hermes', options.profile.home, adopted.id())!, 'utf8').trim().split('\n').map(s => JSON.parse(s));
  assert.equal(records.filter(r => r.type === 'thinking').length, 1);
  assert.equal(records.find(r => r.type === 'assistant').text, 'first last');
  await adopted.dispose();
});

for (const recovery of ['none', 'handover', 'crash']) test(`station tool names and disconnection survive ${recovery}`, async () => {
  const { options, events, driver } = setup();
  let session = await driver.open(options, e => events.push(e));
  await session.prompt('lost');
  await until(() => events.some(e => e.type === 'live' && e.event.kind === 'start' && e.event.id === 'call:lost'));
  if (recovery !== 'none') {
    const snapshot = recovery === 'handover' ? session.snapshot() : null;
    const id = session.id(); session.detach();
    const next = new HermesDriver({ data }); drivers.push(next);
    session = await next.adopt({ ...options, resume: id }, snapshot, e => events.push(e));
  }
  await session.request('continue', '_test/continue', {});
  await until(() => ended(events).length === 1);
  assert.equal(events.filter(e => e.type === 'toolsLost').length, 1);
  const lines = readFileSync(transcriptPath('hermes', options.profile.home, session.id())!, 'utf8').trim().split('\n').map(s => JSON.parse(s));
  const call = lines.find(m => m.type === 'tool');
  assert.ok(isPosting(call.name));
  assert.deepEqual(call.args, { text: 'reply' });
  assert.equal(call.status, 'error');
  await session.dispose();
});

test('model discovery reads ACP inventory without a turn, MCP credentials or transcript', async () => {
  const { options, driver, dump } = setup();
  const models = await driver.models(options.profile);
  assert.deepEqual(models, ['openrouter:default', 'openrouter:test']);
  const calls = readFileSync(dump + '.rpc', 'utf8').trim().split('\n').map(s=>JSON.parse(s));
  assert.deepEqual(calls.find(c=>c.method==='session/new').params.mcpServers, []);
  assert.equal(calls.some(c=>c.method==='session/prompt' || c.method==='session/set_model'), false);
  assert.equal(readFileSync(dump, 'utf8').includes(options.mcpToken), false);
});

test('large configured-provider catalogs are bounded without hiding current or enabled models', () => {
  const { options } = setup();
  const profile = { ...options.profile, models: ['router:model-9999', 'not-listed:manual'] };
  const availableModels = Array.from({length:10_000},(_,i)=>({modelId:`router:model-${i}`}));
  const models = hermesCatalog({currentModelId:'router:model-9998',availableModels},profile);
  assert.equal(models.length,HERMES_MODEL_LIMIT);
  assert.deepEqual(models.slice(0,2),['router:model-9998','router:model-9999']);
  assert.equal(models.includes('not-listed:manual'),false, 'do not invent an unconfigured provider in the discovered catalog');
  assert.deepEqual(profile.models,['router:model-9999','not-listed:manual'], 'manual selections are not rewritten');
});
