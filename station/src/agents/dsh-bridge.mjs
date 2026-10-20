// The station's protocol driver inside DeepSeek Harness (a Cordis plugin dsh loads from the path its patch names:
// agents/dsh.ts). One line of JSON per message on stdin and stdout, for the one session of the process:
//   in:  {id, op: "open", cwd, resume?, provider?, model?}   → {id, session} | {id, error}
//        {id, op: "prompt" | "steer", text}   a message for the next turn, or for the running turn's next step
//        {id, op: "cancel"}                   stops the running turn (it ends aborted)
//   out: {id, ...} answers; {ev: "event", type, data} the session's turns and tool calls as dsh commits them;
//        {ev: "stream", frame} the model's output as it streams (text, thinking, a call's input).
// Plain JavaScript that imports nothing of dsh's: dsh loads it from the station's directory, where its packages do not
// resolve. The station's tools are mounted by the patch (dsh's own mcp-client), not here.
import { randomUUID } from 'node:crypto'
import { createInterface } from 'node:readline'

export const name = 'stillfail-bridge'
export const inject = ['agents']

/// The session events the station reads (the rest stay in dsh's log): a turn's bounds and its tool calls.
const EVENTS = new Set(['turn/start', 'turn/end', 'tool/call', 'tool/result'])
/// The most of a tool's result sent as it is (the whole is in the transcript).
const RESULT_CHARS = 64 * 1024

const write = (message) => process.stdout.write(`${JSON.stringify(message)}\n`)
/// A user message as dsh's createUserMessage makes one: identified, frozen.
const userMessage = (text) => {
  const content = Object.freeze([Object.freeze({ type: 'text', text })])
  return Object.freeze({ content, source: Object.freeze({ kind: 'user' }), role: 'user', id: randomUUID() })
}

function clipped(data) {
  const content = data?.message?.content
  if (!Array.isArray(content)) return data
  const cut = content.map((c) => (typeof c?.text === 'string' && c.text.length > RESULT_CHARS ? { ...c, text: c.text.slice(0, RESULT_CHARS) } : c))
  return { ...data, message: { ...data.message, content: cut } }
}

export function apply(ctx) {
  let agent = null
  let handle = null

  ctx.on('session/event', (session, event) => {
    if (agent === null || session.id !== agent.session.id || !EVENTS.has(event.type)) return
    write({ ev: 'event', type: event.type, data: event.type === 'tool/result' ? clipped(event.data) : event.data })
  })
  ctx.on('agent/assistant-stream', ({ agent: from, frame }) => {
    if (agent === null || from?.id !== agent.id) return
    // The finish carries the provider's replay state, which the station has no use for.
    if (frame?.type === 'chunk' && frame.chunk?.type === 'finish') return
    write({ ev: 'stream', frame })
  })

  const ops = {
    async open({ cwd, resume, provider, model }) {
      if (agent !== null) throw new Error('a session is open')
      const agentOptions = provider && model ? { provider, model } : undefined
      handle = resume
        ? await ctx.agents.resume({ resumeSessionId: resume, agentOptions })
        : await ctx.agents.create({ sessionId: randomUUID(), meta: { cwd }, agentOptions })
      agent = handle.agent
      return { session: agent.session.id }
    },
    prompt({ text }) {
      agent.followup(userMessage(text))
      return {}
    },
    steer({ text }) {
      agent.steer(userMessage(text))
      return {}
    },
    cancel() {
      agent.cancel({ kind: 'user' })
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
      write({ id: message.id, error: String(error?.message ?? error) })
    }
  })
  // The station closing stdin ends the process (dsh's own exit disposes the agent and flushes its log).
  lines.on('close', () => {
    void (handle?.dispose() ?? Promise.resolve()).finally(() => process.exit(0))
  })
}
