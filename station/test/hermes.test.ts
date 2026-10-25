import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join, delimiter } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { after, test } from "node:test";
import { HermesDriver, hermesEnv, outcomeOf } from "../src/agents/hermes.ts";
import type { OpenOptions, RuntimeEvent } from "../src/agents/runtime.ts";
import { transcriptPath, readTimeline } from "../src/read/transcript.ts";
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
  await until(() => ended(after).length === 1);
  assert.match(readFileSync(transcriptPath('hermes', options.profile.home, adopted.id())!, 'utf8'), /first last/);
  assert.equal(ended(events).length, 0); await adopted.dispose();
});
test('configuration stays within its profile and rejects unsafe session IDs', async () => {
  const { options, driver } = setup();
  assert.equal(hermesEnv(options).HERMES_HOME, join(options.profile.home, 'hermes'));
  assert.deepEqual(accessKinds('hermes'), ['env']);
  await assert.rejects(driver.open({ ...options, resume: '../escape' }, () => {}), /invalid Hermes session id/);
  await assert.rejects(driver.open({ ...options, model: 'bad' }, () => {}), /unknown model/);
  assert.equal(outcomeOf({ error: { message: '429 rate limit' } }).kind, 'failed');
});

test('crash adoption reconstructs partial text without duplicating completed steps', async () => {
  const { options, events, driver } = setup(); const s = await driver.open(options, e => events.push(e));
  await s.prompt('handover');
  await until(() => events.some(e => e.type === 'live' && e.event.kind === 'delta' && e.event.text === 'first '));
  s.detach();
  const next = new HermesDriver({ data }); drivers.push(next); const after: RuntimeEvent[] = [];
  const adopted = await next.adopt({ ...options, resume: s.id() }, null, e => after.push(e));
  await until(() => ended(after).length === 1);
  const records = readFileSync(transcriptPath('hermes', options.profile.home, adopted.id())!, 'utf8').trim().split('\n').map(s => JSON.parse(s));
  assert.equal(records.filter(r => r.type === 'thinking').length, 1);
  assert.equal(records.find(r => r.type === 'assistant').text, 'first last');
  await adopted.dispose();
});
