// The station's driver of a Cursor agent (agents/cursor.ts): Cursor's TypeScript SDK (@cursor/sdk) run in this process,
// its local runtime (the agent loop here, the models Cursor's). One line of JSON per message on stdin and stdout, for the
// one session of the process:
//   in:  {id, op: "open", cwd, resume?, model?, mcpUrl, rules, sessions}   → {id, session} | {id, error}
//        {id, op: "prompt", text, model?}   starts a turn (a run): → {id} once it runs, {id, error} when it could not
//        {id, op: "steer", text}            into the running turn: → {id, delivered}
//        {id, op: "cancel"}                 stops the running turn (it ends cancelled)
//   out: {id, ...} answers; {ev: "message", message} what the SDK says as the turn goes (its SDKMessage);
//        {ev: "end", status, error?, usage?, model?} the turn ended (finished, cancelled, error).
// Its environment says the rest: STILLFAIL_CURSOR_SDK (the package's directory), STILLFAIL_CURSOR_HOME (the SDK's home in
// the profile's: what it keeps of its agents, apart from the person's ~/.cursor, while the shells it runs keep HOME),
// CURSOR_API_KEY, STILLFAIL_MCP_TOKEN (the station's tools' token).
// It keeps the session's transcript itself (`sessions`/<agent id>.jsonl, read by read/transcript.ts): the SDK's own store
// is a database of checkpoints, not something to read a history from.
import { appendFileSync, mkdirSync, readFileSync } from 'node:fs'
import { createRequire, syncBuiltinESMExports } from 'node:module'
import { join } from 'node:path'
import { createInterface } from 'node:readline'
import { pathToFileURL } from 'node:url'

const write = (message) => process.stdout.write(`${JSON.stringify(message)}\n`)
/// The most of a tool's result kept in the transcript and sent as it is.
const RESULT_CHARS = 64 * 1024

/// A model as the station names one, `id` or `id[param=value,…]` (Cursor's own way of writing a variant), as the SDK
/// takes it.
export function modelOf(name) {
  if (typeof name !== 'string' || name === '') return undefined
  const at = name.indexOf('[')
  if (at < 0 || !name.endsWith(']')) return { id: name }
  const params = name
    .slice(at + 1, -1)
    .split(',')
    .map((p) => p.split('='))
    .filter(([k, v]) => k && v !== undefined)
    .map(([k, v]) => ({ id: k.trim(), value: v.trim() }))
  return params.length > 0 ? { id: name.slice(0, at), params } : { id: name.slice(0, at) }
}

const clip = (v) => {
  const text = typeof v === 'string' ? v : JSON.stringify(v ?? null)
  return text.length > RESULT_CHARS ? text.slice(0, RESULT_CHARS) : text
}

async function main() {
  // The SDK's home: its agents' store, transcripts and terminals under the profile's, not the person's ~/.cursor. Only
  // os.homedir is told so (the SDK asks it); HOME stays the person's for the commands the agent runs.
  const home = process.env.STILLFAIL_CURSOR_HOME
  if (home) {
    mkdirSync(home, { recursive: true })
    createRequire(import.meta.url)('node:os').homedir = () => home
    syncBuiltinESMExports()
  }
  // The package's ES module, as its exports say (dist/esm/index.js).
  const dir = process.env.STILLFAIL_CURSOR_SDK ?? ''
  const exported = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))?.exports?.['.']
  const sdk = await import(pathToFileURL(join(dir, exported?.import ?? exported?.default ?? 'dist/esm/index.js')).href)

  let agent = null
  let transcript = null
  let model
  /// The run of the turn under way, and what it said so far that is kept whole (the model's text and thoughts come in
  /// pieces).
  let run = null
  let said = null

  const keep = (line) => {
    if (transcript === null) return
    try {
      appendFileSync(transcript, `${JSON.stringify({ time: Date.now(), ...line })}\n`)
    } catch {}
  }
  const flush = () => {
    if (said !== null && said.text !== '') keep(said)
    said = null
  }
  const hear = (message) => {
    const type = message?.type
    if (type === 'assistant' || type === 'thinking') {
      const text = type === 'thinking' ? (message.text ?? '') : (message.message?.content ?? []).map((c) => (c?.type === 'text' ? c.text : '')).join('')
      const kind = type === 'thinking' ? 'thinking' : 'assistant'
      if (said?.type !== kind) flush()
      said ??= { type: kind, text: '' }
      said.text += text
    } else if (type === 'tool_call') {
      flush()
      if (message.status !== 'running') keep({ type: 'tool', id: message.call_id, name: message.name, status: message.status, args: message.args ?? null, result: clip(message.result) })
    } else if (type === 'user') {
      flush()
      // A message put in the running turn (the prompt itself is kept as it is given).
      const text = (message.message?.content ?? []).map((c) => c?.text ?? '').join('')
      if (text !== '') keep({ type: 'user', text, steered: true })
    }
    const out = type === 'tool_call' ? { ...message, result: message.result === undefined ? undefined : clip(message.result) } : message
    write({ ev: 'message', message: out })
  }

  const options = ({ cwd, mcpUrl, rules }) => ({
    ...(model ? { model } : {}),
    // The station's instructions, its memory and skills are a folder of their own (`rules`): project rules there, not
    // the person's Cursor rules or the account's.
    local: { cwd, dirs: [rules], settingSources: ['project'] },
    mcpServers: { stillfail: { type: 'http', url: mcpUrl, headers: { Authorization: `Bearer ${process.env.STILLFAIL_MCP_TOKEN ?? ''}` } } },
  })

  async function turn(text, chosen) {
    try {
      run = await agent.send(text, chosen ? { model: chosen } : undefined)
    } catch (error) {
      run = null
      return { error: String(error?.message ?? error), code: error?.code }
    }
    const current = run
    void (async () => {
      try {
        for await (const message of current.stream()) hear(message)
      } catch {}
      let result = null
      try {
        result = await current.wait()
      } catch (error) {
        result = { status: 'error', error: { message: String(error?.message ?? error), code: error?.code } }
      }
      flush()
      if (result?.usage) keep({ type: 'usage', run: current.id, model: result.model?.id ?? model?.id ?? null, usage: result.usage })
      keep({ type: 'end', status: result?.status ?? 'error', ...(result?.error ? { error: result.error } : {}) })
      if (run === current) run = null
      write({ ev: 'end', run: current.id, status: result?.status ?? 'error', error: result?.error, usage: result?.usage, model: result?.model?.id ?? model?.id })
    })()
    return {}
  }

  const ops = {
    async open(message) {
      if (agent !== null) throw new Error('a session is open')
      // The SDK's local agents need one named: Auto (`default`) when the profile names none.
      model = modelOf(message.model) ?? model ?? { id: 'default' }
      mkdirSync(message.sessions, { recursive: true })
      agent = message.resume ? await sdk.Agent.resume(message.resume, options(message)) : await sdk.Agent.create(options(message))
      transcript = join(message.sessions, `${agent.agentId}.jsonl`)
      if (!message.resume) keep({ type: 'session', id: agent.agentId, cwd: message.cwd })
      return { session: agent.agentId }
    },
    async prompt({ text, model: name }) {
      if (run !== null) throw new Error('a turn is already running')
      const chosen = modelOf(name)
      if (chosen) model = chosen
      flush()
      keep({ type: 'user', text })
      const started = await turn(text, chosen)
      if (started.error !== undefined) {
        keep({ type: 'end', status: 'error', error: { message: started.error, code: started.code } })
        throw Object.assign(new Error(started.error), { code: started.code })
      }
      return {}
    },
    async steer({ text }) {
      const current = run
      if (current === null || typeof current.steer !== 'function') return { delivered: false }
      return { delivered: (await current.steer(text)) === 'complete_delivered' }
    },
    async cancel() {
      await run?.cancel()
      return {}
    },
  }

  const lines = createInterface({ input: process.stdin })
  lines.on('line', async (line) => {
    let message
    try {
      message = JSON.parse(line)
    } catch {
      return
    }
    const op = ops[message?.op]
    try {
      if (!op) throw new Error(`unknown op ${message?.op}`)
      if (message.op !== 'open' && agent === null) throw new Error('no session is open')
      write({ id: message.id, ...(await op(message)) })
    } catch (error) {
      write({ id: message.id, error: String(error?.message ?? error), ...(error?.code ? { code: String(error.code) } : {}) })
    }
  })
  // The station closing stdin ends the process (what the SDK keeps of the agent is on disk already).
  lines.on('close', () => {
    try {
      agent?.close()
    } catch {}
    process.exit(0)
  })
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) await main()
